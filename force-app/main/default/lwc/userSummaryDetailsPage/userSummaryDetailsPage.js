import { LightningElement, track, wire } from 'lwc';
import getSubordinateUsers from '@salesforce/apex/UserHierarchyService.getDirectSubordinates';
import getAttendanceSummary from '@salesforce/apex/UserHierarchyController.getAttendanceSummary';
import getLeaveUsersfirst from '@salesforce/apex/UserHierarchyController.getLeaveUsersfirst';
import getRetailingDetails from '@salesforce/apex/UserHierarchyController.getRetailingDetails';
import getAllAttendanceRecords from '@salesforce/apex/UserHierarchyController.getAllAttendanceRecords';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';

export default class UserSummaryDetailsPage extends NavigationMixin(LightningElement) {
    @track leaveUsers = [];
    @track halfDayUsers = [];
    @track retailUsers = [];
    @track absentUsers = [];
    @track presentUsers = [];

    @track subordinateUsers = [];
    @track totalUsers = 0;
    @track absentCount = 0;
    @track presentCount = 0;
    @track officialCount = 0;
    @track retailingCount = 0;

    @track activeTab = 'leave';
    @track noSubordinates = false;

    history = [];
    parentId;
    isLoaded = false;

    /* --------------------------
       REMOVE PARENT / CLICKED USER
    --------------------------- */
    filterOutParent(arr, userId) {
        return arr.filter(
            item => item.userId !== userId && item.visitorId !== userId
        );
    }

    connectedCallback() {
        const storedHistory = sessionStorage.getItem('userHistory');
        if (storedHistory) {
            this.history = JSON.parse(storedHistory);

            const last = this.history[this.history.length - 1];
            if (last && last.parentId && !this.parentId) {
                this.parentId = last.parentId;
                this.activeTab = last.activeTab;
            }
        }
    }

    @wire(CurrentPageReference)
    setPageReference(currentPageReference) {
        if (currentPageReference && currentPageReference.state) {
            const idFromUrl = currentPageReference.state.c__parentId;

            if (idFromUrl) {
                this.parentId = idFromUrl;
            } else if (!this.parentId && this.history.length > 0) {
                this.parentId = this.history[this.history.length - 1].parentId;
            }

            if (this.parentId) {
                this.loadData();
            }
        }
    }

    /* --------------------------
          LOAD INITIAL DATA
    --------------------------- */
    async loadData() {
        if (!this.parentId) return;

        try {
            const res = await getSubordinateUsers({ parentUserId: this.parentId });
            this.subordinateUsers = res?.users || [];

            if (!this.subordinateUsers.some(u => u.Id === this.parentId)) {
                this.subordinateUsers.push({
                    Id: this.parentId,
                    Name: res?.parentUserName || 'Parent User',
                    IsParent: true
                });
            }

            this.totalUsers = this.subordinateUsers.length;
            const ids = this.subordinateUsers.map(u => u.Id);
            if (!ids.length) return;

            const today = new Date().toISOString().split('T')[0];
            
            // Get attendance summary for counts
            const summary = await getAttendanceSummary({ userIds: ids, forDate: today });
            
            this.absentCount = summary?.Absent || 0;
            this.presentCount = summary?.Present || 0;
            this.officialCount = summary?.['Official Work'] || 0;
            this.retailingCount = summary?.Retailing || 0;

            /* GET ALL ATTENDANCE RECORDS FOR ABSENT AND PRESENT */
            const allAttendance = await getAllAttendanceRecords({ 
                userIds: ids, 
                forDate: today 
            });
            
            console.log('All attendance records:', JSON.stringify(allAttendance));
            
            /* ABSENT USERS */
            this.absentUsers = allAttendance
                .filter(r => r.Status__c === 'Absent')
                .map(r => ({
                    id: r.Id,
                    userId: r.User__c,
                    name: `${r.User__r?.FirstName || ''} ${r.User__r?.LastName || ''}`.trim(),
                    date: r.Date__c,
                    status: r.Status__c
                }));

            console.log('Absent users:', this.absentUsers.length);

            /* PRESENT USERS */
            this.presentUsers = allAttendance
                .filter(r => r.Status__c === 'Present')
                .map(r => ({
                    id: r.Id,
                    userId: r.User__c,
                    name: `${r.User__r?.FirstName || ''} ${r.User__r?.LastName || ''}`.trim(),
                    date: r.Date__c,
                    status: r.Status__c,
                    workType: r.Work__c
                }));

            console.log('Present users:', this.presentUsers.length);

            /* LEAVE & HALF DAY */
            this.leaveUsers = allAttendance
                .filter(r => r.Status__c === 'Leave')
                .map(r => ({
                    id: r.Id,
                    userId: r.User__c,
                    name: `${r.User__r?.FirstName || ''} ${r.User__r?.LastName || ''}`.trim(),
                    date: r.Date__c
                }));

            this.halfDayUsers = allAttendance
                .filter(r => r.Status__c === 'Present Half Day')
                .map(r => ({
                    id: r.Id,
                    userId: r.User__c,
                    name: `${r.User__r?.FirstName || ''} ${r.User__r?.LastName || ''}`.trim(),
                    date: r.Date__c
                }));

            /* RETAIL */
            const retailRes = await getRetailingDetails({ userIds: ids });
            this.retailUsers = retailRes.map(v => ({
                id: v.Id,
                visitorId: v.Visitor_Name__c,
                name: `${v.Visitor_Name__r?.FirstName || ''} ${v.Visitor_Name__r?.LastName || ''}`.trim(),
                beat: v.Beat__r?.Name || 'N/A',
                retailerAddress: v.Visit_Tasks__r?.[0]?.Retailer_Address_New__c || 'N/A',
                showRetailer: v.Visit_Tasks__r?.[0]?.Retailer_Address_New__c ? true : false
            }));

            /* REMOVE parentId FROM ALL LISTS */
            this.leaveUsers = this.filterOutParent(this.leaveUsers, this.parentId);
            this.halfDayUsers = this.filterOutParent(this.halfDayUsers, this.parentId);
            this.retailUsers = this.filterOutParent(this.retailUsers, this.parentId);
            this.absentUsers = this.filterOutParent(this.absentUsers, this.parentId);
            this.presentUsers = this.filterOutParent(this.presentUsers, this.parentId);

            this.isLoaded = true;

        } catch (error) {
            console.error('Load error:', JSON.stringify(error));
        }
    }

    /* --------------------------
          TABS
    --------------------------- */
    get isLeaveTab() { return this.activeTab === 'leave'; }
    get isHalfDayTab() { return this.activeTab === 'halfDay'; }
    get isRetailTab() { return this.activeTab === 'retail'; }
    get isAbsentTab() { return this.activeTab === 'absent'; }
    get isPresentTab() { return this.activeTab === 'present'; }

    get hasSubordinates() { return !this.noSubordinates; }
    get canGoBack() { return this.history && this.history.length > 0; }

    setLeaveTab() { this.activeTab = 'leave'; }
    setHalfDayTab() { this.activeTab = 'halfDay'; }
    setRetailTab() { this.activeTab = 'retail'; }
    setAbsentTab() { this.activeTab = 'absent'; }
    setPresentTab() { this.activeTab = 'present'; }

    /* --------------------------
           GO BACK FUNCTION
    --------------------------- */
    goBack() {
        if (this.history.length > 0) {
            const prev = this.history.pop();
            sessionStorage.setItem('userHistory', JSON.stringify(this.history));

            this.parentId = prev.parentId;
            this.activeTab = prev.activeTab;

            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: { apiName: 'User_Summary_Details' },
                state: { c__parentId: prev.parentId, t: Date.now() }
            });

        } else {
            this.parentId = null;
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: { apiName: 'User_Summary_Details' },
                state: { t: Date.now() }
            });
        }
    }

    /* --------------------------
            USER CLICK DRILL
    --------------------------- */
    async handleUserClick(event) {
        const clickedUserId = event.currentTarget.dataset.userid;

        if (clickedUserId === this.parentId) return;

        this.history.push({
            leaveUsers: [...this.leaveUsers],
            halfDayUsers: [...this.halfDayUsers],
            retailUsers: [...this.retailUsers],
            absentUsers: [...this.absentUsers],
            presentUsers: [...this.presentUsers],
            parentId: this.parentId,
            activeTab: this.activeTab
        });

        sessionStorage.setItem('userHistory', JSON.stringify(this.history));

        try {
            const subResult = await getSubordinateUsers({ parentUserId: clickedUserId });
            const subUserIds = (subResult?.users || []).map(u => u.Id);

            if (!subUserIds.length) {
                this.leaveUsers = [];
                this.halfDayUsers = [];
                this.retailUsers = [];
                this.absentUsers = [];
                this.presentUsers = [];
                this.noSubordinates = true;
                return;
            }

            this.noSubordinates = false;
            this.leaveUsers = [];
            this.halfDayUsers = [];
            this.retailUsers = [];
            this.absentUsers = [];
            this.presentUsers = [];

            const today = new Date().toISOString().split('T')[0];
            const allAttendance = await getAllAttendanceRecords({ 
                userIds: subUserIds, 
                forDate: today 
            });

            /* LEAVE */
            this.leaveUsers = allAttendance
                .filter(l => l.Status__c === 'Leave')
                .map(l => ({
                    id: l.Id,
                    userId: l.User__c,
                    name: `${l.User__r?.FirstName || ''} ${l.User__r?.LastName || ''}`.trim(),
                    date: l.Date__c
                }));

            /* HALF DAY */
            this.halfDayUsers = allAttendance
                .filter(l => l.Status__c === 'Present Half Day')
                .map(l => ({
                    id: l.Id,
                    userId: l.User__c,
                    name: `${l.User__r?.FirstName || ''} ${l.User__r?.LastName || ''}`.trim(),
                    date: l.Date__c
                }));

            /* ABSENT */
            this.absentUsers = allAttendance
                .filter(l => l.Status__c === 'Absent')
                .map(l => ({
                    id: l.Id,
                    userId: l.User__c,
                    name: `${l.User__r?.FirstName || ''} ${l.User__r?.LastName || ''}`.trim(),
                    date: l.Date__c
                }));

            /* PRESENT */
            this.presentUsers = allAttendance
                .filter(l => l.Status__c === 'Present' )
                .map(l => ({
                    id: l.Id,
                    userId: l.User__c,
                    name: `${l.User__r?.FirstName || ''} ${l.User__r?.LastName || ''}`.trim(),
                    date: l.Date__c,
                    workType: l.Work__c
                }));

            /* RETAIL */
            const retailList = await getRetailingDetails({ userIds: subUserIds });
            this.retailUsers = retailList.map(r => ({
                id: r.Id,
                visitorId: r.Visitor_Name__c,
                name: `${r.Visitor_Name__r?.FirstName || ''} ${r.Visitor_Name__r?.LastName || ''}`.trim(),
                beat: r.Beat__r?.Name || '',
                retailerAddress: r.Visit_Tasks__r?.[0]?.Retailer_Address_New__c || '',
                showRetailer: r.Visit_Tasks__r?.[0]?.Retailer_Address_New__c ? true : false
            }));

            /* REMOVE clicked user from all lists */
            this.leaveUsers = this.filterOutParent(this.leaveUsers, clickedUserId);
            this.halfDayUsers = this.filterOutParent(this.halfDayUsers, clickedUserId);
            this.retailUsers = this.filterOutParent(this.retailUsers, clickedUserId);
            this.absentUsers = this.filterOutParent(this.absentUsers, clickedUserId);
            this.presentUsers = this.filterOutParent(this.presentUsers, clickedUserId);

            this.activeTab = 'leave';

        } catch (error) {
            console.error('Drill-down Error:', JSON.stringify(error));
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'User_Summary_Details' },
            state: { c__parentId: clickedUserId, t: Date.now() }
        });
    }

    resetToDashboard() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Custom_Dashboard' }
        });
    }

    /* --------------------------
            TAB BUTTON CSS
    --------------------------- */
    get leaveButtonClass() {
        return this.activeTab === 'leave' ? 'active-tab' : '';
    }

    get halfDayButtonClass() {
        return this.activeTab === 'halfDay' ? 'active-tab' : '';
    }

    get retailButtonClass() {
        return this.activeTab === 'retail' ? 'active-tab' : '';
    }

    get absentButtonClass() {
        return this.activeTab === 'absent' ? 'active-tab' : '';
    }

    get presentButtonClass() {
        return this.activeTab === 'present' ? 'active-tab' : '';
    }
}