import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSubordinateHierarchy from '@salesforce/apex/OutletSummaryController.getSubordinateHierarchy';
import getBulkOutletSummary from '@salesforce/apex/OutletSummaryController.getBulkOutletSummary';
import getSubordinatesincludeself from '@salesforce/apex/OutletSummaryController.getSubordinatesincludeself';
import getUserOwnMetricsOnly from '@salesforce/apex/OutletSummaryController.getUserOwnMetricsOnly';

import { CurrentPageReference } from 'lightning/navigation';
import userId from '@salesforce/user/Id';

export default class OutletSummaryDetails extends NavigationMixin(LightningElement) {

    @api parentUserId;

    // All-field mode trackers
    @track isAllFieldMode = false;
    @track allFieldUsers = [];
    @track filteredAllFieldUsers = [];

    // Hierarchy mode trackers
    @track users = [];
    @track loading = false;
    @track noData = false;
    @track lastRefreshed = 'Never';
    @track period = 'FTD';   // default only when parent does NOT pass value

    // Breadcrumb
    @track breadcrumb = [];

    // Search and filter properties
    @track searchKey = '';
    @track roleFilterVisible = false;
    @track selectedRoles = [];
    @track roleOptions = [];

    periodOptions = ['FTD', 'MTD'];

    currentUserId = userId;
    currentLevelUserId = null;
    history = [];

    month = new Date().getMonth() + 1;
    year = new Date().getFullYear();

    // internal flags
    _pullDownInit = false;
    _initialLoadComplete = false;

    @track currentUserMetrics = {
    Id: '',
    Name: '',
    Role: '',
    Employee_Role__c: '',
    distributors: 0,
    beats: 0,
    outlets: 0,
    outletPlanned: 0,
    upc: 0,
    utc: 0,
    totalTC: 0,
    zeroOrderCount: 0,
    productiveCalls: 0,
    coveragePct: 0,
    productivity: 0,
    netValue: 0
};


    /* -----------------------------------------
       GETTERS
    -------------------------------------------- */
    get formattedSelectedRoles() {
        return this.selectedRoles.join(', ');
    }

    /* -----------------------------------------
       HANDLE URL STATE
    -------------------------------------------- */
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef) return;

        const state = pageRef.state || {};
        const urlParams = {};

        let hasIncoming = false;

        if (state.c__parentUserId) {
            urlParams.parentUserId = state.c__parentUserId;
            this.currentLevelUserId = state.c__parentUserId;
            hasIncoming = true;
        }

        if (state.c__periodType) {
            const p = String(state.c__periodType).toUpperCase();
            if (p === 'FTD' || p === 'MTD') {
                urlParams.periodType = p;
                this.period = p;
                hasIncoming = true;
                this.updateSelectValue();
            } else {
                urlParams.periodType = state.c__periodType;
            }
        }

        sessionStorage.setItem('outletSummaryDetailsURLParams', JSON.stringify(urlParams));

        if (this._initialLoadComplete && hasIncoming) {
            const reloadUser = this.currentLevelUserId || this.currentUserId;
            if (this.isAllFieldMode) {
                this.handleAllFieldClick();
            } else {
                this.loadUserData(reloadUser);
            }
        }
    }

    /* -----------------------------------------
       RESTORE STATE ON PAGE LOAD
    -------------------------------------------- */
    connectedCallback() {
        const urlParamsStr = sessionStorage.getItem('outletSummaryDetailsURLParams');
        let urlParams = {};

        if (urlParamsStr) {
            try {
                urlParams = JSON.parse(urlParamsStr) || {};
            } catch (e) {
                console.warn('Could not parse URL params:', e);
                urlParams = {};
            }
        }

        const saved = sessionStorage.getItem('outletSummaryDetailsState');
        let savedState = {};

        if (saved) {
            try {
                savedState = JSON.parse(saved);
                this.history = savedState.history || [];
                this.currentLevelUserId = savedState.currentLevelUserId || this.currentUserId;
                this.breadcrumb = savedState.breadcrumb || [];
                this.isAllFieldMode = !!savedState.isAllFieldMode;
                this.allFieldUsers = savedState.allFieldUsers || [];
                this.filteredAllFieldUsers = savedState.filteredAllFieldUsers || [];
                this.searchKey = savedState.searchKey || '';
                this.selectedRoles = savedState.selectedRoles || [];
            } catch (e) {
                console.warn('Could not parse saved outletSummaryDetailsState', e);
                savedState = {};
            }
        }

        if (Object.keys(urlParams).length > 0) {
            if (urlParams.parentUserId) {
                this.currentLevelUserId = urlParams.parentUserId;
            }

            if (urlParams.periodType) {
                const p = String(urlParams.periodType).toUpperCase();
                if (p === 'FTD' || p === 'MTD') {
                    this.period = p;
                } else {
                    this.period = savedState.period || 'FTD';
                }
            } else {
                this.period = savedState.period || 'FTD';
            }
        } else {
            this.currentLevelUserId = savedState.currentLevelUserId || this.currentUserId;
            this.period = savedState.period || 'FTD';
        }

        console.log('Initial state - period:', this.period, 'userId:', this.currentLevelUserId);

        // If in All Field Mode, restore filtered list
        if (this.isAllFieldMode && this.allFieldUsers.length > 0) {
            this.prepareRoleOptions();
            this.applyFilters();
        } else {
            this.loadUserData(this.currentLevelUserId);
        }
        
        this.updateRefreshTime();
        this._initialLoadComplete = true;
        
        setTimeout(() => this.updateSelectValue(), 100);
    }

    updateSelectValue() {
        const selectElement = this.template.querySelector('.period-select');
        if (selectElement && this.period) {
            selectElement.value = this.period;
        }
    }

    renderedCallback() {
        if (!this._pullDownInit) {
            this.enablePullDownRefresh();
            this._pullDownInit = true;
        }
        
        if (this._initialLoadComplete) {
            this.updateSelectValue();
        }
    }

    /* -----------------------------------------
       Helpers
    --------------------------------------------*/
    formatNumber(v) {
        if (v === null || v === undefined) return '0';
        if (typeof v === 'number') {
            return Number.isInteger(v) ? v.toString() : v.toFixed(2);
        }
        return String(v);
    }

    resolveUserIdFromRecord(u) {
        if (!u) return null;
        return u.userId || u.Id || u.id || u.UserId || u.USERID || u.User_Id__c || u.Id__c || null;
    }

    lookupSummaryForUser(summaryMap, u) {
        if (!summaryMap) return {};
        const maybe = this.resolveUserIdFromRecord(u);

        if (!maybe) return {};

        if (summaryMap[maybe]) return summaryMap[maybe];
        if (summaryMap[String(maybe)]) return summaryMap[String(maybe)];

        if (u && (u.Id || u.Id__c) && (u.Id !== maybe) && summaryMap[u.Id]) {
            return summaryMap[u.Id];
        }

        if (u && (u.Id || u.Id__c) && summaryMap[String(u.Id || u.Id__c)]) {
            return summaryMap[String(u.Id || u.Id__c)];
        }

        return {};
    }

    /* -----------------------------------------
       Prepare Role Options from All Field Users
    --------------------------------------------*/
    prepareRoleOptions() {
        if (!this.allFieldUsers || this.allFieldUsers.length === 0) {
            this.roleOptions = [];
            return;
        }

        const rolesSet = new Set();
        this.allFieldUsers.forEach(user => {
            if (user.Employee_Role__c) {
                rolesSet.add(user.Employee_Role__c);
            }
            if (user.Role && user.Role !== user.Employee_Role__c) {
                rolesSet.add(user.Role);
            }
        });

        const uniqueRoles = Array.from(rolesSet).sort();
        this.roleOptions = uniqueRoles.map(role => ({
            label: role,
            value: role,
            selected: this.selectedRoles.includes(role)
        }));
    }

    /* -----------------------------------------
       SEARCH AND FILTER FOR ALL FIELD USERS
    -------------------------------------------- */
    // Handle search input
    handleSearch(event) {
        this.searchKey = event.target.value;
        this.applyFilters();
    }

    // Toggle role filter popup
    toggleRoleFilter() {
        // Create a fresh copy of role options with current selected status
        this.roleOptions = this.roleOptions.map(option => ({
            ...option,
            selected: this.selectedRoles.includes(option.value)
        }));
        this.roleFilterVisible = !this.roleFilterVisible;
    }

    // Close role filter
    closeRoleFilter() {
        this.roleFilterVisible = false;
    }

    // Handle role checkbox change
    handleRoleCheckboxChange(event) {
        const role = event.target.dataset.value;
        const isChecked = event.target.checked;
        
        // Update the roleOptions array
        this.roleOptions = this.roleOptions.map(option => {
            if (option.value === role) {
                return { ...option, selected: isChecked };
            }
            return option;
        });
    }

    // Apply role filter
    applyRoleFilter() {
        this.selectedRoles = this.roleOptions
            .filter(option => option.selected)
            .map(option => option.value);
        
        this.roleFilterVisible = false;
        this.applyFilters();
        this.saveState();
    }

    // Clear all filters
    clearRoleFilter() {
        this.searchKey = '';
        this.selectedRoles = [];
        this.roleOptions = this.roleOptions.map(option => ({
            ...option,
            selected: false
        }));
        this.filteredAllFieldUsers = [...this.allFieldUsers];
        this.roleFilterVisible = false;
        this.saveState();
    }

    // Apply all filters (search + role)
    applyFilters() {
        if (!this.allFieldUsers || this.allFieldUsers.length === 0) {
            this.filteredAllFieldUsers = [];
            this.noData = true;
            return;
        }

        let filtered = this.allFieldUsers;
        
        // Apply search filter
        if (this.searchKey) {
            const searchTerm = this.searchKey.toLowerCase();
            filtered = filtered.filter(user => 
                (user.Name && user.Name.toLowerCase().includes(searchTerm)) ||
                (user.Role && user.Role.toLowerCase().includes(searchTerm)) ||
                (user.Employee_Role__c && user.Employee_Role__c.toLowerCase().includes(searchTerm))
            );
        }
        
        // Apply role filter
        if (this.selectedRoles.length > 0) {
            filtered = filtered.filter(user => 
                this.selectedRoles.includes(user.Employee_Role__c) ||
                this.selectedRoles.includes(user.Role)
            );
        }
        
        this.filteredAllFieldUsers = filtered;
        
        // Update noData flag
        this.noData = filtered.length === 0;
    }

    /* -----------------------------------------
       Chunk Array Helper for Large Data Sets
    --------------------------------------------*/
    chunkArray(array, chunkSize) {
        const chunks = [];
        for (let i = 0; i < array.length; i += chunkSize) {
            chunks.push(array.slice(i, i + chunkSize));
        }
        return chunks;
    }

    /* -----------------------------------------
       MAIN LOADER (hierarchy)
    -------------------------------------------- */
    async loadUserData(userId) {
    this.loading = true;
    this.noData = false;
    this.users = [];

    try {
        const uid = userId || this.currentUserId;
        console.log('Loading data for user:', uid, 'with period:', this.period);

        // Fetch current user's own metrics first
        try {
            const currentUserMetricsMap = await getUserOwnMetricsOnly({
                userIds: [uid],
                periodType: this.period
            });
            
            if (currentUserMetricsMap && currentUserMetricsMap[uid]) {
                const userMetrics = currentUserMetricsMap[uid];
                this.currentUserMetrics = {
                    Id: uid,
                    Name: this.currentUserMetrics.Name || 'Current User',
                    Role: this.currentUserMetrics.Role || 'Loading...',
                    distributors: userMetrics.distributors ?? 0,
                    beats: userMetrics.beats ?? 0,
                    outlets: userMetrics.outlets ?? 0,
                    outletPlanned: userMetrics.totalTC ?? 0,
                    upc: userMetrics.upc ?? 0,
                    utc: userMetrics.utc ?? 0,
                    totalTC: userMetrics.totalTC ?? 0,
                    zeroOrderCount: userMetrics.zeroOrderCount ?? 0,
                    productiveCalls: userMetrics.productiveCalls ?? 0,
                    coveragePct: userMetrics.coveragePct ?? 0,
                    productivity: userMetrics.productivity ?? 0,
                    netValue: userMetrics.netValue ?? 0
                };
            }
        } catch (metricsError) {
            console.error('Error fetching current user metrics:', metricsError);
        }

        // Fetch hierarchy for direct reports
        const hierarchy = await getSubordinateHierarchy({
            userId: uid,
            monthNum: this.month,
            yearNum: this.year
        });

        if (!hierarchy || !hierarchy.directReports || hierarchy.directReports.length === 0) {
            this.noData = true;
            this.currentLevelUserId = uid;
            
            // Update current user info from hierarchy if available
            if (hierarchy && hierarchy.currentUser) {
                const name = hierarchy.currentUser.userName || hierarchy.currentUser.Name || 'Unknown';
                const userIdVal = hierarchy.currentUser.userId || hierarchy.currentUser.Id || uid;
                this.updateBreadcrumb(userIdVal, name);
                
                // Update current user name/role
                this.currentUserMetrics.Name = name;
                this.currentUserMetrics.Role = hierarchy.currentUser.userRole || 'No Role';
            }
            
            this.saveState();
            this.loading = false;
            return;
        }

        const userIds = hierarchy.directReports
            .map(r => r.userId || r.Id || r.Id__c || r.id)
            .filter(Boolean);

        const summary = await getBulkOutletSummary({
            userIds: userIds,
            periodType: this.period
        }) || {};

        console.log('Summary data received:', summary);

        this.users = hierarchy.directReports.map(r => {
            const s = this.lookupSummaryForUser(summary, r);
            const userIdVal = r.userId || r.Id || r.Id__c || null;

            return {
                Id: userIdVal,
                Name: r.userName || r.Name || '',
                Role: r.userRole || r.Role || 'No Role',
                distributors: s.distributors ?? 0,
                beats: s.beats ?? 0,
                outlets: s.outlets ?? 0,
                outletPlanned: s.outletPlanned ?? 0,
                upc: s.upc ?? 0,
                utc: s.totalTC ?? 0
            };
        });

        this.currentLevelUserId = uid;

        // Update current user info from hierarchy
        if (hierarchy.currentUser) {
            const name = hierarchy.currentUser.userName || hierarchy.currentUser.Name || 'Unknown';
            const userIdVal = hierarchy.currentUser.userId || hierarchy.currentUser.Id || uid;
            this.updateBreadcrumb(userIdVal, name);
            
            // Update current user name/role
            this.currentUserMetrics.Name = name;
            this.currentUserMetrics.Role = hierarchy.currentUser.userRole || 'No Role';
        }

    } catch (err) {
        console.error('Error in loadUserData:', err);
        this.noData = true;
    } finally {
        this.loading = false;
        this.updateRefreshTime();
        this.saveState();
        this.updateSelectValue();
    }
}


    /* -----------------------------------------
       ALL FIELD USERS
    -------------------------------------------- */
    async handleAllFieldClick() {
        console.log('=== handleAllFieldClick START ===');

        this.isAllFieldMode = true;
        this.loading = true;
        
        // Reset filters
        this.searchKey = '';
        this.selectedRoles = [];
        this.roleOptions = [];

        try {
            const parentId = this.currentLevelUserId || this.currentUserId;

            // 1️⃣ Fetch ALL subordinates
            let allSubordinates;
            try {
                allSubordinates = await getSubordinatesincludeself({ parentUserId: parentId });
                console.log('All subordinates fetched:', allSubordinates);
            } catch (subError) {
                console.error('Error fetching subordinates:', subError);
                allSubordinates = [];
            }
            
            if (!allSubordinates || allSubordinates.length === 0) {
                this.allFieldUsers = [];
                this.filteredAllFieldUsers = [];
                this.noData = true;
                this.loading = false;
                return;
            }

            // Filter out current user
            const subordinates = allSubordinates.filter(u => {
                const userId = u.Id || u.userId;
                return userId !== parentId;
            });
            
            if (subordinates.length === 0) {
                this.allFieldUsers = [];
                this.filteredAllFieldUsers = [];
                this.noData = true;
                this.loading = false;
                return;
            }

            const userIds = subordinates.map(u => u.Id || u.userId).filter(Boolean);
            console.log('Processing', userIds.length, 'subordinates');

            // 2️⃣ Chunk the user IDs to avoid hitting limits
            const chunkSize = 50;
            const chunks = this.chunkArray(userIds, chunkSize);
            let allSummary = {};

            // Process chunks sequentially
            for (let i = 0; i < chunks.length; i++) {
                const chunk = chunks[i];
                console.log(`Processing chunk ${i + 1}/${chunks.length} with ${chunk.length} users`);
                
                try {
                    const chunkSummary = await getUserOwnMetricsOnly({
                        userIds: chunk,
                        periodType: this.period
                    });
                    
                    if (chunkSummary) {
                        // Merge chunk results
                        Object.keys(chunkSummary).forEach(key => {
                            allSummary[key] = chunkSummary[key];
                        });
                    }
                } catch (chunkError) {
                    console.error(`Error in chunk ${i + 1}:`, chunkError);
                    // Continue with next chunk
                }
                
                // Small delay between chunks to avoid overwhelming server
                if (i < chunks.length - 1) {
                    await new Promise(resolve => setTimeout(resolve, 100));
                }
            }

            console.log('Final summary data:', allSummary);

            // 3️⃣ Build final list
            const finalUsers = subordinates.map(u => {
                const userId = u.Id || u.userId;
                const userIdStr = String(userId);
                const s = allSummary[userIdStr] || {};
                
                return {
                    Id: userId,
                    Name: u.Name || u.userName || '',
                    Role: u.Role || u.userRole || 'No Role',
                    Employee_Role__c: u.Employee_Role__c || '',
                    distributors: s.distributors ?? 0,
                    beats: s.beats ?? 0,
                    outlets: s.outlets ?? 0,
                    outletPlanned: 0,
                    upc: s.upc ?? 0,
                    utc: s.utc ?? 0,
                    totalTC: s.totalTC ?? 0,
                    zeroOrderCount: s.zeroOrderCount ?? 0,
                    productiveCalls: s.productiveCalls ?? 0,
                    coveragePct: s.coveragePct ?? 0,
                    productivity: s.productivity ?? 0,
                    netValue: s.netValue ?? 0
                };
            });

            this.allFieldUsers = finalUsers;
            this.filteredAllFieldUsers = [...finalUsers];
            
            // Prepare role options
            this.prepareRoleOptions();
            
            // Apply any existing filters
            this.applyFilters();
            
            console.log('Final users list created:', finalUsers.length, 'users');
            this.noData = finalUsers.length === 0;

        } catch (err) {
            console.error('handleAllFieldClick error:', err);
            console.error('Error details:', err.message, err.stack);
            this.noData = true;
            
            // Simple fallback: just show user list without metrics
            try {
                const parentId = this.currentLevelUserId || this.currentUserId;
                const allSubordinates = await getSubordinatesincludeself({ parentUserId: parentId });
                
                if (allSubordinates && allSubordinates.length > 0) {
                    const subordinates = allSubordinates.filter(u => {
                        const userId = u.Id || u.userId;
                        return userId !== parentId;
                    });
                    
                    const fallbackUsers = subordinates.map(u => ({
                        Id: u.Id || u.userId,
                        Name: u.Name || u.userName || '',
                        Role: u.Role || u.userRole || 'No Role',
                        Employee_Role__c: u.Employee_Role__c || '',
                        distributors: 0,
                        beats: 0,
                        outlets: 0,
                        outletPlanned: 0,
                        upc: 0,
                        utc: 0
                    }));
                    
                    this.allFieldUsers = fallbackUsers;
                    this.filteredAllFieldUsers = [...fallbackUsers];
                    this.prepareRoleOptions();
                    this.applyFilters();
                }
            } catch (fallbackErr) {
                console.error('Fallback also failed:', fallbackErr);
            }
        } finally {
            this.loading = false;
            this.saveState();
            console.log('=== handleAllFieldClick END ===');
        }
    }

    handleAllFieldBack() {
        this.isAllFieldMode = false;
        this.saveState();
        this.updateSelectValue();
    }

    /* -----------------------------------------
       PERIOD SWITCH (FTD / MTD)
    -------------------------------------------- */
    handlePeriodChange(event) {
        const newPeriod = event?.target?.value ? String(event.target.value).toUpperCase() : this.period;
        if (newPeriod !== 'FTD' && newPeriod !== 'MTD') {
            console.warn('Unknown period requested:', newPeriod);
            return;
        }

        this.period = newPeriod;
        console.log('Period changed to:', this.period);
        this.saveState();
        this.updateSelectValue();

        if (this.isAllFieldMode) {
            this.handleAllFieldClick();
        } else {
            this.loadUserData(this.currentLevelUserId);
        }
    }

    /* -----------------------------------------
       REFRESH BUTTON
    -------------------------------------------- */
    handleRefresh() {
        this.lastRefreshed = 'Refreshing...';
        if (this.isAllFieldMode) {
            this.handleAllFieldClick();
        } else {
            this.loadUserData(this.currentLevelUserId);
        }
    }

    /* -----------------------------------------
       DRILL DOWN CLICK
    -------------------------------------------- */
    onUserClick(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) return;

        this.history.push({
            currentLevelUserId: this.currentLevelUserId,
            users: this.users,
            period: this.period
        });

        this.loadUserData(id);
    }

    /* -----------------------------------------
       GO BACK
    -------------------------------------------- */
    handleGoBack() {
        sessionStorage.removeItem('outletSummaryDetailsState');
        sessionStorage.removeItem('outletSummaryDetailsURLParams');
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Custom_Dashboard' }
        });
    }

    /* -----------------------------------------
       BREADCRUMB HELPERS
    --------------------------------------------*/
    updateBreadcrumb(userId, userName) {
        if (!userId) return;

        const index = this.breadcrumb.findIndex(b => b.userId === userId);

        if (index === -1) {
            this.breadcrumb = this.breadcrumb.map(b => ({ ...b, showSeparator: true }));
            this.breadcrumb.push({
                userId,
                userName,
                showSeparator: this.breadcrumb.length > 0
            });
        } else {
            this.breadcrumb = this.breadcrumb.slice(0, index + 1)
                .map((b, i) => ({ ...b, showSeparator: i > 0 }));
        }

        this.saveState();
    }

    handleBreadcrumbClick(event) {
        const uid = event.currentTarget.dataset.userid;
        if (uid) {
            this.loadUserData(uid);
        }
    }

    /* -----------------------------------------
       STATE PERSISTENCE
    -------------------------------------------- */
   saveState() {
    try {
        sessionStorage.setItem(
            'outletSummaryDetailsState',
            JSON.stringify({
                history: this.history,
                currentLevelUserId: this.currentLevelUserId,
                period: this.period,
                breadcrumb: this.breadcrumb,
                isAllFieldMode: this.isAllFieldMode,
                allFieldUsers: this.allFieldUsers,
                filteredAllFieldUsers: this.filteredAllFieldUsers,
                searchKey: this.searchKey,
                selectedRoles: this.selectedRoles,
                currentUserMetrics: this.currentUserMetrics
            })
        );
    } catch (e) {
        console.warn('Unable to save state:', e);
    }
}


    updateRefreshTime() {
        this.lastRefreshed = new Date().toLocaleString();
    }

    /* -----------------------------------------
       PULL-DOWN-TO-REFRESH
    --------------------------------------------*/
    enablePullDownRefresh() {
        let startY = 0;
        let pulling = false;

        this.template.addEventListener('touchstart', (e) => {
            if (!e.touches || e.touches.length === 0) return;
            startY = e.touches[0].clientY;
        });

        this.template.addEventListener('touchmove', (e) => {
            if (!e.touches || e.touches.length === 0) return;
            const y = e.touches[0].clientY;
            if ((y - startY) > 100 && window.scrollY === 0) {
                pulling = true;
            }
        });

        this.template.addEventListener('touchend', () => {
            if (pulling) {
                pulling = false;
                this.handleRefresh();
            }
        });
    }
}