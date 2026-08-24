import { LightningElement, track, api } from 'lwc';
import getSubordinatesincludeself from '@salesforce/apex/UserHierarchyService.getSubordinatesnosameroleusers';
import getDirectSubordinates from '@salesforce/apex/UserHierarchyService.getDirectSubordinates';
import getUserCounts from '@salesforce/apex/UserDailyCountService.getUserCounts';
import getTodayTimeline from '@salesforce/apex/UserDailyCountService.getTodayTimeline';
import getMTDCounts from '@salesforce/apex/UserDailyCountService.getMTDCounts';
import { NavigationMixin } from 'lightning/navigation';
import USER_ID from '@salesforce/user/Id';
import getEmployeeRoles from '@salesforce/apex/UserDailyCountService.getEmployeeRoles';

export default class DailySummary extends NavigationMixin(LightningElement) {
    @track userList = [];
    @track userListAllFieldUsers = [];
    @track filteredUsers = [];
    history = [];
    @track noSubordinates = false;
    @track isLoaded = false;
    @track userId = USER_ID;
    @track parentUserId;
    @track showDistributorPage = false;
    selectedUserId = '';
    selectedUserName = '';
    @track selectedBeat = '';
    @track timelineSteps = [];
    @track todayDisplay = '';
    @track timelineLoading = false;
    @track lastRefreshed = 'Never';
    refreshTimeout;
    @track isAllFieldMode = false;
    @track allEmployRoles = [];
    rendered = false;
    @track searchKey = '';
    @track selectedRoles = [];
    @track roleFilterVisible = false;  // show/hide role filter popup
@track tempSelectedRoles = [];     // temporary selections in popup

    // MTD
    @track activeDistributorTab = 'timeline';
    @track mtdData = { retailingCount: 0, officialCount: 0, leaveCount: 0, totalCount: 0, avgRetailingHours: 0, avgTotalHours: 0 };
    @track mtdLoading = false;
    @track mtdLastRefreshed = 'Never';
    @track mtdError = '';
    @track mtdVisits = [];

    @track roleUserSearchKey = '';
@track roleUserOptions = [];

 @track tempSelectedUserId = '';    // temporary user selection
    @track tempSelectedUserName = '';

 totalRetailers = 0;
totalOfficial = 0;
totalLeave = 0;

skipHistoryPush = false;
isHistoryLocked = false;


    get computedTotal() {
    return (this.totalRetailers || 0) + (this.totalOfficial || 0) + (this.totalLeave || 0);
}


   connectedCallback() {

    //sessionStorage.removeItem('dailySummaryState'); // Only when need to clear sessionStorage

    // 1️⃣ Load saved state if exists
    const saved = sessionStorage.getItem('dailySummaryState');

    if (saved) {
    const state = JSON.parse(saved);

    // Restore basic state
    this.history = Array.isArray(state.history) ? state.history : [];
    this.parentUserId = state.parentUserId || this.userId;
    this.isAllFieldMode = state.isAllFieldMode === true;
    this.showDistributorPage = state.showDistributorPage === true;
    this.selectedUserId = state.selectedUserId || '';
    this.selectedUserName = state.selectedUserName || '';
    this.activeDistributorTab = state.activeDistributorTab || 'timeline';

    // 🔥 IMPORTANT: Restore lists to avoid "noSubordinates = true"
    this.userList = Array.isArray(state.userList) ? state.userList : [];
    this.userListAllFieldUsers = Array.isArray(state.userListAllFieldUsers) 
        ? state.userListAllFieldUsers 
        : [];

        this.skipHistoryPush = true;

    // 🔥 FIX: If history exists but lists are empty → cleanup to stop wrong back button
    /*if (
        this.history.length > 0 &&
        this.userList.length === 0 &&
        this.userListAllFieldUsers.length === 0
    ) {
        console.log('⚠️ Resetting corrupt history due to empty lists on restore');
        this.history = [];
        this.saveState();
    }*/

    // -------------------------------
    // CASE 1: User was inside distributor sub-page (Timeline/MTD)
    // -------------------------------
    if (this.showDistributorPage && this.selectedUserId) {

        // Distributor takes priority → disable All-Field mode
        this.isAllFieldMode = false;

        // Restore lists used in distributor mode
        this.filteredUsers = [...this.userList];

        if (this.activeDistributorTab === 'timeline') {
            this.loadTimeline();
        } else {
            this.loadMTD();
        }
        return;
    }

    // -------------------------------
    // CASE 2: All-Field mode was active
    // -------------------------------
    if (this.isAllFieldMode && !this.showDistributorPage) {

        // SAFETY CHECK: Don’t restore All-Field from a stale session
        if (state.parentUserId !== this.userId) {
            console.log('❌ Prevented wrong All-Field redirect due to stale cache');

            this.isAllFieldMode = false;
            this.parentUserId = this.userId;
            this.showDistributorPage = false;

            this.saveState();
            this.loadData();
            return;
        }

        // VALID All-Field → restore full list
        this.filteredUsers = [...this.userListAllFieldUsers];
        this.handleAllFiledClick();
        return;
    }

    // -------------------------------
    // CASE 3: Normal dashboard view
    // -------------------------------
    this.loadData();
    return;
}


    // -------------------------------
    // First time loading component → fresh dashboard
    // -------------------------------
    this.parentUserId = this.userId;
    this.loadData();
    this.loadEmployRoles();

    console.log('Connected Call back history count:', this.history.length);
}


    async loadEmployRoles() {
        try {
            const roles = await getEmployeeRoles();
            this.allEmployRoles = roles.map(r => ({ label: r, value: r }));
            console.log('Employee roles loaded:', this.allEmployRoles);
        } catch (err) {
            console.error('Error loading employee roles from Apex:', err);
        }
    }

    async loadData() {
    if (!this.parentUserId) {
        console.warn('⛔ loadData stopped — NO parentUserId');
        return;
    }

    console.log('🔵 START loadData() for Parent:', this.parentUserId);
    this.isLoaded = false;

    try {
        console.log('📡 Fetching direct subordinates for:', this.parentUserId);
        const res = await getDirectSubordinates({ parentUserId: this.parentUserId });

        const users = Array.isArray(res) ? res : (res.users || []);
        console.log('👥 Direct Users Count:', users.length);

        if (!users.length) {
            console.warn('⚠ No subordinates found');
            this.userList = [];
            this.noSubordinates = true;
            return;
        }

        this.noSubordinates = false;

        // -------------------------------
        // Get Counts
        // -------------------------------
        const userIds = users.map(u => u.Id);
        console.log('📤 Fetching Counts For Users:', userIds);

        const counts = await getUserCounts({ userIds });
        console.log(`📥 Count Records Returned: ${counts.length}`);

        const countsMap = new Map(counts.map(c => [c.userId, c]));

        // -------------------------------
        // Build Updated User List
        // -------------------------------
        const updatedList = users
        .filter(u => u.Id !== this.parentUserId) // ✅ remove self
        .map(u => {
            const c = countsMap.get(u.Id) || {};

            console.log(`\n🧩 Processing User: ${u.Id} — ${u.Name}`);
            console.log(`   🔸 totalUsers: ${c.totalUsers || 0}`);
            console.log(`   🔸 retailCount: ${c.retailCount || 0}`);
            console.log(`   🔸 officialCount: ${c.officialCount || 0}`);
            console.log(`   🔸 leaveCount: ${c.leaveCount || 0}`);
            console.log(`   🔸 orderValue: ${c.orderValue || 0}`);
            console.log(`   🔸 beatName: ${c.beatName || 'null'}`);
            console.log(`   🔸 retailerAddress: ${c.retailerAddress || 'N/A'}`);

            return {
                ...u,
                Employee_Role__c: u.Employee_Role__c || 'No Role',

                totalUsers: c.totalUsers || 0,
                retailCount: c.retailCount || 0,
                officialCount: c.officialCount || 0,
                leaveCount: c.leaveCount || 0,
orderValue: c.orderValue ? Number(c.orderValue.toFixed(2)) : 0,

                hasVisitToday: (c.retailCount || 0) > 0,
                //hasLeaveOnly: (c.leaveCount || 0) > 0 && !(c.retailCount > 0),
                hasLeaveOnly: (c.leaveCount || 0) > 0 
              && (c.retailCount || 0) === 0
              && (c.officialCount || 0) === 0,

                showTile:
                    (c.retailCount || 0) > 0 ||
                    ((c.leaveCount || 0) > 0 && !(c.retailCount > 0)),

                beatName: c.beatName || null,
                retailerAddress: c.retailerAddress || 'N/A',
                showRetailer: !!c.retailerAddress
            };
        });

       /* updatedList.sort((a, b) => {
            if (a.Id === this.parentUserId) return -1;
            if (b.Id === this.parentUserId) return 1;
            return 0;
        });*/

        console.log('📌 FINAL userList Count:', updatedList.length);

        this.userList = updatedList;
        this.updateRefreshTime();

    } catch (err) {
        console.error('❌ ERROR in loadData:', err);
    } finally {
        this.isLoaded = true;
        console.log('🟢 loadData() COMPLETED');
    }

    console.log('loadData history count:', this.history.length);
}

async handleAllFiledClick() {
    const PARENT_USER_ID = USER_ID;
    console.log('=== handleAllFiledClick START ===');

    // push current parent to history
    //this.history.push({ parentUserId: PARENT_USER_ID });
    if (!this.skipHistoryPush) {
        this.history.push({
            parentUserId: this.parentUserId,
            userList: this.userList
        });
    }

    // Reset flag after use
    this.skipHistoryPush = false;
    console.log('handleAllFiledClick history count:', this.history.length);
    this.isAllFieldMode = true;
    this.saveState();

    try {
        // 1️⃣ Fetch all users including self
        const res = await getSubordinatesincludeself({ parentUserId: PARENT_USER_ID });
        const users = Array.isArray(res) ? res : (res.users || []);
        if (!users.length) {
            this.filteredUsers = [];
            this.resetCounts();
            return;
        }

        // 2️⃣ Fetch counts for all users
        const userIds = users.map(u => u.Id);
        const counts = await getUserCounts({ userIds });
        const countsMap = new Map(counts.map(c => [c.userId, c]));

        // 3️⃣ Prepare users for display
        const preparedUsers = users.map(u => {
            const c = countsMap.get(u.Id) || {};
            return {
                ...u,
                Employee_Role__c: u.Employee_Role__c || 'No Role',

                retailCount: c.retailCount || 0,
                officialCount: c.officialCount || 0,
                leaveCount: c.leaveCount || 0,
                totalUsers: c.totalUsers || 0,
orderValue: c.orderValue ? Number(c.orderValue.toFixed(2)) : 0,
                beatName: c.beatName || u.beatName || null,
                retailerAddress: c.retailerAddress || u.retailerAddress || 'N/A',

                hasVisitToday: (c.retailCount || 0) > 0,
                //hasLeaveOnly: (c.leaveCount || 0) > 0 && !(c.retailCount > 0),
                hasLeaveOnly: (c.leaveCount || 0) > 0
              && (c.retailCount || 0) === 0
              && (c.officialCount || 0) === 0,

                showTile: (c.retailCount || 0) > 0 || ((c.leaveCount || 0) > 0 && !(c.retailCount > 0)),
                showRetailer: !!c.retailerAddress || !!u.retailerAddress
            };
        });

        this.userListAllFieldUsers = preparedUsers;
        this.filteredUsers = [...preparedUsers];

        // 4️⃣ Compute totals for parent top progress bars
        let totalRetailers = 0,
            totalOfficial = 0,
            totalLeave = 0;

        const parentCountsArr = await getUserCounts({ userIds: [PARENT_USER_ID] });
        const parentCounts = parentCountsArr && parentCountsArr.length ? parentCountsArr[0] : {};

        totalRetailers = parentCounts.retailCount || 0;
        totalOfficial = parentCounts.officialCount || 0;
        totalLeave = parentCounts.leaveCount || 0;

        // Assign to reactive tracked properties
        this.totalRetailers = totalRetailers;
        this.totalOfficial = totalOfficial;
        this.totalLeave = totalLeave;

        console.log('Counts calculated successfully.');
    } catch (err) {
        console.error('ERROR handleAllFiledClick:', err);
        this.resetCounts();
    }

    console.log('=== handleAllFiledClick END ===');
    console.log('handleAllFiledClick history count:', this.history.length);
}


        calculateCounts() {
            // Find parent in all users
            const parent = this.userListAllFieldUsers.find(u => u.Id === this.parentUserId);
            
            if (parent) {
                this.totalRetailers = parent.retailCount || 0;
                this.totalOfficial = parent.officialCount || 0;
                this.totalLeave = parent.leaveCount || 0;
                this.totalSecondarySales = parent.orderValue || 0;
            } else {
                this.totalRetailers = 0;
                this.totalOfficial = 0;
                this.totalLeave = 0;
                this.totalSecondarySales = 0;
            }
        }


    resetCounts() {
        this.totalRetailers = 0;
        this.totalLeave = 0;
        this.totalOfficial = 0;
        this.totalSecondarySales = 0;
    }

handleRoleTabClick(event) {
    const roleFilter = event.target.dataset.value;

    if (!roleFilter || roleFilter === 'All') {
        this.filteredUsers = [...(this.userListAllFieldUsers || [])];
    } else {
        const rf = roleFilter.toString().toLowerCase();
        this.filteredUsers = (this.userListAllFieldUsers || []).filter(
            u => (u.Employee_Role__c || '').toLowerCase() === rf
        );
    }

    this.calculateCounts();
}


    async handleUserClick(event) {
        // preserve original behavior but stop propagation so clicks from inner elements don't bubble
        event.stopPropagation();
        const clickedId = event.currentTarget.dataset.userid || event.target.closest('[data-userid]')?.dataset.userid;
        if (!clickedId) return;

        if (clickedId === this.parentUserId) return;

        this.history.push({ parentUserId: this.parentUserId, userList: [...this.userList] });
        this.parentUserId = clickedId;
        this.saveState();
        await this.loadData();
        console.log('handleUserClick history count:', this.history.length);
    }
    

    async handleUserClickAllFieldUser(event) {
        event.stopPropagation();
        const clickedId = event.currentTarget.dataset.userid || event.target.closest('[data-userid]')?.dataset.userid;
        if (!clickedId) return;

        this.history.push({ parentUserId: this.parentUserId, userListAllFieldUsers: [...this.userListAllFieldUsers] });
        this.parentUserId = clickedId;
        await this.handleAllFiledClick();
        console.log('handleUserClickAllFieldUser history count:', this.history.length);
    }

    handleGoBack() {
        
         this.skipHistoryPush = true;

        if (!this.history.length) return;
        const prev = this.history.pop();
        this.parentUserId = prev.parentUserId;
        this.userList = prev.userList || [];
        this.noSubordinates = this.userList.length === 0;
        if (!this.history.length) this.isAllFieldMode = false;
        this.saveState();

        console.log(
    '🔙 Back Clicked → before pop → history count:', 
    this.history.length,
    'content:', JSON.stringify(this.history)
);

    }


async handleAllFieldBack(event) {

    this.skipHistoryPush = true;

    if (event) {
        event.stopPropagation();
        event.preventDefault();
    }

    // If history is empty → Exit All-Field Mode fully
    if (this.history.length === 0) {
        this.isAllFieldMode = false;
        this.showDistributorPage = false;
        this.parentUserId = this.userId;

        // Reload top-level dashboard
        await this.loadData();
        this.saveState();
        return;
    }

    // Go 1 step back inside All Field
    const prev = this.history.pop();
    this.parentUserId = prev.parentUserId || this.userId;

    // Check if previous view was All-Field
    if (prev.userListAllFieldUsers) {
        this.isAllFieldMode = true;
        this.userListAllFieldUsers = prev.userListAllFieldUsers || [];
        this.filteredUsers = [...this.userListAllFieldUsers];
        this.calculateCounts();
    } else {
        // Previous view was main dashboard
        this.isAllFieldMode = false;
        this.userList = prev.userList || [];
        this.noSubordinates = this.userList.length === 0;

        // Reload counts for main view
        await this.loadData();
        //window.location.reload();
        this.skipHistoryPush = false;
    }

    this.saveState();
    console.log('🟦 AllField Back → history count:', this.history.length, 'parentUserId:', this.parentUserId);
}



    // ---------- FIX: method name exactly matches template onclick={OnClosehandleAllFieldBack} ----------
    OnClosehandleAllFieldBack() {
        this.showDistributorPage = false;
        this.isAllFieldMode = false;
    }

    get canGoBack() {
        return this.history.length > 0;
    }

    updateRefreshTime() {
        this.lastRefreshed = new Date().toLocaleString();
    }

    async handleRefresh() {
    try {
        this.lastRefreshed = 'Refreshing...';

        await this.loadData();

        this.lastRefreshed = new Date().toLocaleString();

        // ✅ Force full page reload
        window.location.reload();
        
    } catch (err) {
        console.error('Refresh failed:', err);
        this.lastRefreshed = 'Error';
    }
    console.log('handleRefresh history count:', this.history.length);
}


async handleTimelineRefresh() {
    if (!this.selectedUserId) return;

    this.isHistoryLocked = true;
    this.timelineLoading = true;
    this.lastRefreshed = 'Refreshing...';

    await this.loadTimeline();

    this.lastRefreshed = new Date().toLocaleString();
    this.timelineLoading = false;
    this.isHistoryLocked = false;
    console.log('handleTimelineRefresh history count:', this.history.length);
}



    /*async handleVisitClick(event) {
        event.stopPropagation();
        this.pushHistoryForView();
        this.selectedUserId = event.currentTarget.dataset.userid;
        this.selectedUserName = event.currentTarget.dataset.username || 'Unknown User';
        this.showDistributorPage = true;
        this.selectedBeat = 'Loading...';
        this.activeDistributorTab = 'timeline';
        await this.loadTimeline();
        this.loadMTD().catch(err => console.warn('Preload MTD failed', err));
        console.log('history count:', this.history.length);
    }*/

    async handleVisitClick(event) {
    event.stopPropagation();
    // push the current view snapshot so closeDistributorPage can restore it
    this.pushHistoryForView();

    this.selectedUserId = event.currentTarget.dataset.userid;
    this.selectedUserName = event.currentTarget.dataset.username || 'Unknown User';
    this.showDistributorPage = true;
    this.isAllFieldMode = false;
    this.saveState();
    this.selectedBeat = 'Loading...';
    this.activeDistributorTab = 'timeline';
    await this.loadTimeline();
    // loadMTD can be fire-and-forget
    this.loadMTD().catch(err => console.warn('Preload MTD failed', err));
    console.log(' handleVisitClick history count:', this.history.length);
}

async closeDistributorPage() {

    this.skipHistoryPush = true;

    if (!this.history.length) {
        this.showDistributorPage = false;
        this.saveState();
        this.isAllFieldMode = false;
        this.parentUserId = this.userId;

        // reload top-level All-Field data
        await this.handleAllFiledClick().catch(err => console.warn('loadData after close failed', err));
        return;
    }

    const prev = this.history.pop();

    console.log(' closeDistributorPage prev:', prev);
    console.log(' closeDistributorPage history count:', this.history.length);

    if (prev.view === 'allField') {
        this.isAllFieldMode = true;
        this.parentUserId = prev.parentUserId || this.userId;
        this.showDistributorPage = false;

        // Reload counts freshly
        await this.handleAllFiledClick().catch(err => console.warn('restore counts failed', err));
        return;
    }

    if (prev.view === 'main') {
        this.isAllFieldMode = false;
        this.parentUserId = prev.parentUserId || this.userId;
        this.userList = prev.userList || [];
        this.noSubordinates = this.userList.length === 0;
        this.showDistributorPage = false;
        this.skipHistoryPush = false;
        return;
    }

    
    
    this.showDistributorPage = false;
    
}

    async loadTimeline() {
        if (!this.selectedUserId) return;
        const lockState = this.isHistoryLocked;
        this.isHistoryLocked = true;
        this.timelineLoading = true;
        this.timelineSteps = [];
        this.todayDisplay = '';

        try {
            const res = await getTodayTimeline({ userId: this.selectedUserId });
            const today = new Date();
            const dayName = today.toLocaleDateString('en-GB', { weekday: 'long' });
            const day = today.getDate().toString().padStart(2,'0');
            const month = today.toLocaleString('en-GB', { month: 'short' });
            const year = today.getFullYear();
            this.todayDisplay = `${dayName}. ${day}-${month}-${year}`;

            const t = (res && res.timeline) ? res.timeline : [];
            this.timelineSteps = t.map((s, idx) => ({
                uniqueKey: `${s.stepName}-${idx}-${s.stepTime}`,
                stepName: s.stepName,
                stepTime: s.stepTime,
                visitName: s.visitName,
                tasks: s.tasks || [],
                isFirstStep: idx === 0
            }));

            this.selectedBeat = res?.beatName || Null;
        } catch (err) {
            console.error('Error loading timeline:', err);
        } finally {
            this.timelineLoading = false;
            this.isHistoryLocked = lockState;
        }

        console.log('loadTimeline history count:', this.history.length);
    }

    get noTimeline() {
        return !this.timelineLoading && (!this.timelineSteps || this.timelineSteps.length === 0);
    }

    async loadMTD() {
        if (!this.selectedUserId) return;

        const lockState = this.isHistoryLocked;
        this.isHistoryLocked = true;

        this.mtdLoading = true;
        this.mtdError = '';
        try {
            const res = await getMTDCounts({ userId: this.selectedUserId });
            const retailingCount = Number(res?.retailingCount || 0);
            const officialCount = Number(res?.officialCount || 0);
            const leaveCount = Number(res?.leaveCount || 0);
            const totalCount = retailingCount + officialCount + leaveCount;
            const avgRetailingHours = res?.avgRetailingHours || 0;
            const avgTotalHours = res?.avgTotalHours || 0;

            this.mtdData = { retailingCount, officialCount, leaveCount, totalCount, avgRetailingHours, avgTotalHours };
            this.mtdVisits = res?.mtdVisits ? JSON.parse(res.mtdVisits) : [];
            this.mtdLastRefreshed = new Date().toLocaleString();
        } catch (err) {
            console.error('Error loading MTD:', err);
            this.mtdError = 'Unable to load MTD data';
        } finally {
            this.mtdLoading = false;
            this.isHistoryLocked = lockState;
        }

        console.log('loadMTD history count:', this.history.length);
    }

    async handleMTDRefresh() {
    if (!this.selectedUserId) return;

    this.isHistoryLocked = true;
    this.mtdLastRefreshed = 'Refreshing...';

    await this.loadMTD();

    this.mtdLastRefreshed = new Date().toLocaleString();

    this.isHistoryLocked = false;

    console.log('handleMTDRefresh history count:', this.history.length);
}


    async handleTabActive(event) {
        const active = event?.detail?.value;
        if (!active) return;
        this.activeDistributorTab = active;
        if (active === 'mtd') await this.loadMTD();
    }

handleWhatsApp(event) {
    event.stopPropagation();
    const phone = event.currentTarget.dataset.phone;
    if (phone) {
        const link = document.createElement('a');
        link.href = `https://wa.me/${phone}`;
        link.target = "_blank";
        link.rel = "noopener noreferrer";
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }
}


    handleCall(event) {
        event.stopPropagation();
        const phone = event.currentTarget.dataset.phone;
        if (phone) window.location.href = `tel:${phone}`;
    }

    resetToDashboard() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Custom_Dashboard' }
        });
        this.isAllFieldMode = false;
    }

    stopClick(event) {
    event.stopImmediatePropagation();
    event.stopPropagation();
    }

    get roleOptions() {
    return this.allEmployRoles.map(r => ({ label: r, value: r }));
}

handleSearch(event) {
    this.searchKey = event.target.value.toLowerCase();
    this.applyFilters();
}

handleRoleFilterChange(event) {
    this.selectedRoles = event.detail.value;
    this.applyFilters();
}

applyFilters() {
    let list = [...(this.userListAllFieldUsers || [])];

    const search = (this.searchKey || '').toLowerCase().trim();
    const selectedUserId = this.tempSelectedUserId;   // <-- Use temp values
    const selectedRoles = this.selectedRoles || [];

    // 1️⃣ USER FILTER (highest priority)
    if (selectedUserId) {
        list = list.filter(u => u.Id === selectedUserId);
    }

    // 2️⃣ SEARCH FILTER
    if (search) {
        list = list.filter(u =>
            (u.Name && u.Name.toLowerCase().includes(search)) ||
            ((u.Employee_Role__c || '').toLowerCase().includes(search))
        );
    }

    // 3️⃣ ROLE FILTER
    if (selectedRoles.length > 0) {
        const rolesLower = selectedRoles.map(r => (r || '').toLowerCase());
        list = list.filter(u =>
            rolesLower.includes((u.Employee_Role__c || '').toLowerCase())
        );
    }

    this.filteredUsers = list;
    this.calculateCounts();

    console.log('applyFilters history count:', this.history.length);
}




get roleOptionsWithSelected() {
    const rolesSet = new Set();
    this.userListAllFieldUsers.forEach(u => {
        if (u.Employee_Role__c) {
            rolesSet.add(u.Employee_Role__c);
        }
    });
    return Array.from(rolesSet).map(r => ({
        label: r,
        value: r,
        selected: this.selectedRoles.includes(r)
    }));
}



handleCheckboxChange(event) {
    const value = event.target.dataset.value;
    const role = this.roleOptions.find(r => r.value === value);
    if (role) {
        role.selected = event.target.checked;

        // Update temporary selection array
        if (event.target.checked) {
            if (!this.tempSelectedRoles.includes(value)) {
                this.tempSelectedRoles.push(value);
            }
        } else {
            this.tempSelectedRoles = this.tempSelectedRoles.filter(r => r !== value);
        }
    }
}

handleRoleCheckboxChange(event) {
    const value = event.target.dataset.value;
    if (event.target.checked) {
        if (!this.tempSelectedRoles.includes(value)) {
            this.tempSelectedRoles.push(value);
        }
    } else {
        this.tempSelectedRoles = this.tempSelectedRoles.filter(r => r !== value);
    }
}


applyRoleFilter() {
    // Apply role filter
    this.selectedRoles = [...this.tempSelectedRoles];

    let list = [...(this.userListAllFieldUsers || [])];

    // Filter by selected roles
    if (this.selectedRoles && this.selectedRoles.length > 0) {
        const sel = this.selectedRoles.map(r => r.toLowerCase());
        list = list.filter(u => sel.includes((u.Employee_Role__c || '').toLowerCase()));
    }

    // If a user is selected
    if (this.tempSelectedUserId && this.tempSelectedUserId != null) {
        this.selectedUserId = this.tempSelectedUserId;       // Sync main selection
        this.selectedUserName = this.tempSelectedUserName;

        this.loadSubordinatesForSelectedUser(this.tempSelectedUserId)
            .then(() => {
                if (this.selectedRoles.length > 0) {
                    this.filteredUsers = this.filteredUsers.filter(u =>
                        this.selectedRoles.map(r => r.toLowerCase()).includes((u.Employee_Role__c || '').toLowerCase())
                    );
                }
                this.updateRoleUserOptions();
            })
            .catch(err => console.error(err));
    } 
    
    // CASE: User removed → CLEAR SELECTION
    else {
        this.selectedUserId = '';
        this.selectedUserName = '';

        this.filteredUsers = list;
        this.updateRoleUserOptions();
    }

    this.roleFilterVisible = false;
    this.calculateCounts();
}



updateRoleUserOptions() {
    if (!this.roleUserSearchKey) {
        // If no search input, clear the picklist
        this.roleUserOptions = [];
        return;
    }

    // Otherwise, show matching users
    const list = [...this.filteredUsers];
    this.roleUserOptions = list
        .filter(u => (u.Name || '').toLowerCase().includes(this.roleUserSearchKey))
        .map(u => ({ Id: u.Id, Name: u.Name }));
}



clearRoleFilter() {
    this.tempSelectedRoles = [];
    this.selectedRoles = [];
    this.tempSelectedUserId = '';
    this.tempSelectedUserName = '';
    this.roleUserSearchKey = '';
    this.searchKey = '';

    this.filteredUsers = [...(this.userListAllFieldUsers || [])];
    this.roleUserOptions = []; // ensure picklist cleared
    this.calculateCounts();

    this.roleFilterVisible = false;
}


toggleRoleFilter() {
    if (!this.userListAllFieldUsers || !this.userListAllFieldUsers.length) return;
    this.roleFilterVisible = !this.roleFilterVisible;
}


// --- add helper: push a view-aware snapshot into history ---
pushHistoryForView() {
    if (this.isHistoryLocked) return;
    // If we are already on distributor, don't push again
    // (prevents duplicate entries if user clicks inside distributor)
    if (this.showDistributorPage) return;

    if (this.isAllFieldMode) {
        // snapshot the All Field Users view
        this.history.push({
            view: 'allField',
            parentUserId: this.parentUserId,
            userListAllFieldUsers: [...(this.userListAllFieldUsers || [])],
            filteredUsers: [...(this.filteredUsers || [])]
        });
    } else {
        // snapshot the main view
        this.history.push({
            view: 'main',
            parentUserId: this.parentUserId,
            userList: [...(this.userList || [])]
        });
    }
}

// --- update handleVisitClick to push snapshot before opening distributor ---


openRoleFilter() {
        this.tempSelectedRoles = [...this.selectedRoles];  // backup
        this.roleFilterVisible = true;
    }


closeRoleFilter() {
        this.roleFilterVisible = false;
    }


// 1. Total = Retail + Official + Leave
get computedTotal() {
    return (this.totalRetailers || 0) + (this.totalOfficial || 0) + (this.totalLeave || 0);
}

get retailWidthStyle() {
    return `width: ${(this.totalRetailers / this.computedTotal) * 100}%;`;
}

get officialWidthStyle() {
    return `width: ${(this.totalOfficial / this.computedTotal) * 100}%;`;
}

get leaveWidthStyle() {
    return `width: ${(this.totalLeave / this.computedTotal) * 100}%;`;
}


// Inside your class
showVisitTile(u) {
    // Only show if they have a visit today AND are not on leave
    return u.hasVisitToday && (!u.leaveCount || u.leaveCount === 0);
}

handleRoleUserSearch(event) {
    this.roleUserSearchKey = event.target.value.toLowerCase();

    // When user clears the search text
    if (!this.roleUserSearchKey || this.roleUserSearchKey.trim() === '') {
        this.roleUserOptions = [];

        // 🔥 IMPORTANT: Reset user selection
        this.tempSelectedUserId = null;
        this.tempSelectedUserName = null;

        return;
    }

    // Filter user list for suggestions
    this.roleUserOptions = (this.userListAllFieldUsers || []).filter(u =>
        (u.Name || '').toLowerCase().includes(this.roleUserSearchKey)
    );
}


handleRoleUserSelect(event) {
    const selectedUserId = event.currentTarget.dataset.userid;
    if (!selectedUserId) return;

    const selectedUser = (this.userListAllFieldUsers || []).find(u => u.Id === selectedUserId);
    if (!selectedUser) return;

    this.tempSelectedUserId = selectedUser.Id;
    this.tempSelectedUserName = selectedUser.Name;
    this.roleUserSearchKey = selectedUser.Name;
    this.roleUserOptions = [];
}

updateRolesForFilteredUsers() {
    const rolesSet = new Set();
    (this.filteredUsers || []).forEach(u => {
        if (u.Employee_Role__c) rolesSet.add(u.Employee_Role__c);
    });

    this.allEmployRoles = Array.from(rolesSet).map(r => ({ label: r, value: r }));
    // Keep selection if still present
    this.tempSelectedRoles = this.tempSelectedRoles.filter(r => rolesSet.has(r));
}


async loadSubordinatesForSelectedUser(userId) {
        const res = await getSubordinatesincludeself({ parentUserId: userId });
        const users = Array.isArray(res) ? res : (res.users || []);

        if (!users.length) {
            this.filteredUsers = [];
            this.resetCounts();
            return;
        }

        const userIds = users.map(u => u.Id);
        const counts = await getUserCounts({ userIds });
        const countsMap = new Map();
        counts.forEach(c => countsMap.set(c.userId, c));

        const preparedUsers = users.map(u => {
            const c = countsMap.get(u.Id) || {};
            return {
                ...u,
                Employee_Role__c: u.Employee_Role__c || 'No Role',
                retailCount: c.retailCount || 0,
                officialCount: c.officialCount || 0,
                leaveCount: c.leaveCount || 0,
orderValue: c.orderValue ? Number(c.orderValue.toFixed(2)) : 0,
                hasVisitToday: (c.retailCount || 0) > 0,
                hasLeaveOnly: (c.leaveCount || 0) > 0 && !(c.retailCount > 0),
                showTile: ((c.retailCount || 0) > 0) || ((c.leaveCount || 0) > 0 && !(c.retailCount > 0)),
                beatName: c.beatName || null,
                totalUsers: 0,
                retailerAddress: c.retailerAddress || 'N/A',
                showRetailer: c.retailerAddress ? true : false
            };
        });

        this.filteredUsers = [...preparedUsers];
        this.calculateCounts();
    }

saveState() {
    const state = {
        history: this.history,
        parentUserId: this.parentUserId,
        isAllFieldMode: this.isAllFieldMode,
        showDistributorPage: this.showDistributorPage,

        // timeline / MTD restore
        selectedUserId: this.selectedUserId,
        selectedUserName: this.selectedUserName,
        activeDistributorTab: this.activeDistributorTab,

        userList: this.userList,
        userListAllFieldUsers: this.userListAllFieldUsers
    };

    sessionStorage.setItem('dailySummaryState', JSON.stringify(state));
}


    
    
}