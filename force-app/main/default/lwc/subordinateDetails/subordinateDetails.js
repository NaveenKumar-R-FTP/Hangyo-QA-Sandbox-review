import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import USER_NAME_FIELD from '@salesforce/schema/User.Name';
import USER_ROLE_ID from '@salesforce/schema/User.UserRole.Name';
import getSubordinateHierarchy from '@salesforce/apex/HangyoDashboardController.getSubordinateHierarchy';
import getSubordinatesincludeself from '@salesforce/apex/HangyoDashboardController.getSubordinatesnosameroleusers';
import { NavigationMixin } from 'lightning/navigation';

export default class SubordinateDetails extends NavigationMixin(LightningElement) {

    @track breadcrumb = [];
    @track currentUser = {
        userId: '',
        userName: '',
        userRole:'',
        actualAmount: 0,
        targetAmount: 0,
        actualFormatted: '₹0',
        targetFormatted: '₹0'
    };
    @track directReports = [];
    @track loading = true;
    @track noSubordinates = false;

    @track history = [];
    @track isAllFieldMode = false;
    @track filteredUsers = [];
    @track userListAllFieldUsers = [];

    @track searchKey = '';
    @track roleFilterVisible = false;
    @track selectedRoles = [];
    @track roleUserOptions = [];
    @track roleUserSearchKey = '';
    @track tempSelectedUserId = null;
    @track tempSelectedUserName = null;
    @track tempSelectedRoles = [];
    @track baseFilteredUsers = [];

    // New internal flag to indicate we've already restored state and triggered the proper initial load
    restoredFromSession = false;

    month = new Date().getMonth() + 1;
    year = new Date().getFullYear();

    // --- WIRE: only populate user metadata (do NOT call loadUserData here) ---
    @wire(getRecord, { recordId: USER_ID, fields: [USER_NAME_FIELD, USER_ROLE_ID] })
    wiredUser({ error, data }) {
        if (data) {
            const userName = getFieldValue(data, USER_NAME_FIELD);
            const userRoleId = getFieldValue(data, USER_ROLE_ID);
            // Only set metadata; do not call loadUserData here (that overwrites restored state on refresh)
            this.currentUser.userName = userName || this.currentUser.userName || 'Current User';
            this.currentUser.userId = USER_ID;
            this.currentUser.userRole = userRoleId || this.currentUser.userRole || 'No Role';
        } else if (error) {
            console.error('Error loading user data:', error);
            // keep currentUser values (connectedCallback will trigger actual load)
            this.currentUser.userName = this.currentUser.userName || 'Current User';
            this.currentUser.userId = this.currentUser.userId || USER_ID;
        }
    }

    connectedCallback() {
//sessionStorage.removeItem('subordinateDashboardState');
        // Try restore saved state
        const savedStateRaw = sessionStorage.getItem('subordinateDashboardState');
        if (savedStateRaw) {
            try {
                const state = JSON.parse(savedStateRaw);
                this.breadcrumb = state.breadcrumb || [];
                // Merge currentUser with defaults so userId is present
                this.currentUser = Object.assign(this.currentUser || {}, state.currentUser || {});
                this.directReports = state.directReports || [];
                this.isAllFieldMode = state.isAllFieldMode || false;
                this.filteredUsers = state.filteredUsers || [];
                this.userListAllFieldUsers = state.userListAllFieldUsers || [];
                this.selectedRoles = state.selectedRoles || [];
                this.tempSelectedUserId = state.tempSelectedUserId || null;
                this.tempSelectedUserName = state.tempSelectedUserName || null;

                // mark that we restored
                this.restoredFromSession = true;

                // Load fresh numbers for the restored userId (keeps you in drill-down on refresh)
                // If restored state didn't contain currentUser.userId, fall back to USER_ID
                const loadId = (this.currentUser && this.currentUser.userId) ? this.currentUser.userId : USER_ID;
                // call loadUserData for the restored user so the numbers are current
                this.loadUserData(loadId);
                return; // done
            } catch (e) {
                console.warn('Could not parse saved subordinateDashboardState, ignoring.', e);
                // fallthrough to normal initial load
            }
        }

        // No saved state -> normal initial load for root user
        this.loadUserData(USER_ID);
    }

    /*formatCurrency(v) {
        if (v === null || v === undefined) return '₹0';
        const num = Number(v);
        return '₹' + num.toLocaleString('en-IN', { maximumFractionDigits: 2 });
    }*/

   formatCurrency(v) {
    const num = Number(v || 0);

    if (num >= 10000000) {          // 1 Crore
        return '₹' + (num / 10000000).toFixed(1).replace(/\.0$/, '') + 'Cr';
    }
    if (num >= 100000) {            // 1 Lakh
        return '₹' + (num / 100000).toFixed(1).replace(/\.0$/, '') + 'L';
    }
    if (num >= 1000) {              // 1 Thousand
        return '₹' + (num / 1000).toFixed(1).replace(/\.0$/, '') + 'K';
    }

    // Below 1000 → normal ₹ currency
    return '₹' + num.toLocaleString('en-IN', { maximumFractionDigits: 2 });
}

    async loadUserData(userId) {
        this.loading = true;
        this.noSubordinates = false;

        try {
            const result = await getSubordinateHierarchy({ 
                userId: userId, 
                monthNum: this.month, 
                yearNum: this.year 
            });

            if (result && result.currentUser) {
                const actual = result.currentUser.actualAmount || 0;
                const target = result.currentUser.targetAmount || 0;
                this.currentUser = {
                    userId: result.currentUser.userId || userId,
                    userName: result.currentUser.userName || this.currentUser.userName,
                    userRole: result.currentUser.userRole || this.currentUser.userRole,
                    actualAmount: result.currentUser.actualAmount || 0,
                    targetAmount: result.currentUser.targetAmount || 0,
                    actualFormatted: this.formatCurrency(result.currentUser.actualAmount),
                    targetFormatted: this.formatCurrency(result.currentUser.targetAmount),
                    targetVsActual: target > 0 ? ((actual / target) * 100).toFixed(2) : 0
                };

                // Update breadcrumb (this also saves state below)
                this.updateBreadcrumb(this.currentUser);

                // Process direct reports
                if (result.directReports && result.directReports.length > 0) {
                    this.directReports = result.directReports.map(report => {
                        const performance = report.targetAmount > 0 ? 
                            Math.round((report.actualAmount / report.targetAmount) * 100) : 0;
    
                            const targetVsActual = report.targetAmount > 0 ?
                            ((report.actualAmount / report.targetAmount) * 100).toFixed(2) : 0;

                        return {
                            userId: report.userId,
                            userName: report.userName || 'Unknown User',
                            userRole: report.userRole || 'No Role',
                            actualAmount: report.actualAmount || 0,
                            targetAmount: report.targetAmount || 0,
                            actualFormatted: this.formatCurrency(report.actualAmount),
                            targetFormatted: this.formatCurrency(report.targetAmount),
                            performance: performance,
                            performanceClass: this.getPerformanceClass(performance),
                            progressStyle: `width:${performance > 100 ? 100 : performance}%;`,
                            keyBar: report.userId + '_bar',
                            targetvsactuals: targetVsActual
                        };
                    });
                    this.noSubordinates = false;
                } else {
                    this.directReports = [];
                    this.noSubordinates = true;
                }
            } else {
                this.noSubordinates = true;
            }

        } catch (error) {
            console.error('Error loading user data:', error);
            this.noSubordinates = true;
        }

        this.loading = false;

        // Save state after loading (so refresh will restore this drill-down)
        this.saveStateToSession();
    }

    updateBreadcrumb(user) {
        const userIndex = this.breadcrumb.findIndex(item => item.userId === user.userId);
        
        if (userIndex === -1) {
            // Add to breadcrumb with showSeparator flag
            const newBreadcrumb = this.breadcrumb.map((item, index) => {
                return { ...item, showSeparator: true };
            });
            
            newBreadcrumb.push({
                userId: user.userId,
                userName: user.userName,
                showSeparator: this.breadcrumb.length > 0 // Show separator if not first item
            });
            
            this.breadcrumb = newBreadcrumb;
        } else {
            // Truncate breadcrumb to this point
            const truncatedBreadcrumb = this.breadcrumb.slice(0, userIndex + 1);
            
            // Update showSeparator flags
            this.breadcrumb = truncatedBreadcrumb.map((item, index) => {
                return { ...item, showSeparator: index > 0 };
            });
        }

        // IMPORTANT: save immediately so refresh keeps updated breadcrumb
        this.saveStateToSession();
    }

    get performancePercentage() {
        if (this.currentUser.targetAmount > 0) {
            return Math.round((this.currentUser.actualAmount / this.currentUser.targetAmount) * 100);
        }
        return 0;
    }

    get hasDirectReports() {
        return this.directReports.length > 0;
    }

    getPerformanceClass(performance) {
        let baseClass = 'kpi-value';
        if (performance >= 100) return `${baseClass} performance-high`;
        if (performance >= 75) return `${baseClass} performance-medium`;
        return `${baseClass} performance-low`;
    }

    handleSubordinateClick(event) {
        const userId = event.currentTarget.dataset.userid;
        if (userId) {
            // Optionally you can push history or breadcrumb here, but loadUserData will call updateBreadcrumb
            this.loadUserData(userId);
        }
    }

    handleBreadcrumbClick(event) {
        const userId = event.currentTarget.dataset.userid;
        if (userId) {
            this.loadUserData(userId);
        }
    }

  async handleAllFiledClick() {
    console.log('=== handleAllFiledClick START ===');

    this.isAllFieldMode = true;
    this.history.push({ parentUserId: USER_ID });
    console.log('History after push:', this.history);

    try {
        console.log('Calling Apex: getSubordinatesincludeself with parentUserId =', USER_ID);
        const res = await getSubordinatesincludeself({ parentUserId: USER_ID });
        console.log('Apex response:', res);

        // Parse users array
        let users = Array.isArray(res) ? res : (res.users || []);
        console.log('Parsed users array:', users);

        if (!users.length) {
            console.warn('No users returned from Apex.');
            this.userListAllFieldUsers = [];
            this.filteredUsers = [];
            return;
        }

        // Debug: show all returned IDs
        console.log('All returned user IDs:', users.map(u => u.userId || u.Id));

        // Exclude parent user
        users = users.filter(u => (u.userId || u.Id) !== USER_ID);
        console.log('Users after removing parent:', users);

        if (!users.length) {
            console.warn('All users were filtered out (parent only).');
            this.userListAllFieldUsers = [];
            this.filteredUsers = [];
            return;
        }

        const preparedUsers = users.map(u => {
            const actual = u.actualAmount || u.TotalOrderValue || 0;
            const target = u.targetAmount || u.SecondaryTarget || 0;

            const performance = target > 0 ? Math.round((actual / target) * 100) : 0;

            const prepared = {
                ...u,
                Name: u.Name || '',
                Role: u.Role || 'No Role',
                Phone: u.Phone || null,

                // Raw numbers
                actualAmount: actual,
                targetAmount: target,
                totalOrderValue: actual,
                secondarySalesTarget: target,

                // Formatted numbers
                actualFormatted: this.formatCurrency(actual),
                targetFormatted: this.formatCurrency(target),
                totalOrderFormatted: this.formatCurrency(actual),
                secondaryTargetFormatted: this.formatCurrency(target),

                performance: performance,
                performanceClass: this.getPerformanceClass(performance),
                progressStyle: `width:${performance > 100 ? 100 : performance}%;`,
                keyBar: (u.userId || u.Id) + '_bar'
            };

            console.log('Prepared user:', prepared);
            return prepared;
        });

        this.userListAllFieldUsers = preparedUsers;
        this.filteredUsers = [...preparedUsers];
        console.log('All Field Users Loaded:', this.filteredUsers.length);
        console.log('Filtered Users:', this.filteredUsers);

    } catch (err) {
        console.error('ERROR handleAllFiledClick:', err);
    }

    console.log('=== handleAllFiledClick END ===');

    this.loading = false;
    this.saveStateToSession();
    console.log('Loading set to false, state saved to session.');
}



    handleAllFieldBack(event) {
        this.isAllFieldMode = false;
        this.saveStateToSession();
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

    handleRoleUserSearch(event) {
        this.roleUserSearchKey = event.target.value.toLowerCase();

        if (!this.roleUserSearchKey || this.roleUserSearchKey.trim() === '') {
            this.roleUserOptions = [];

            this.tempSelectedUserId = null;
            this.tempSelectedUserName = null;

            return;
        }

        this.roleUserOptions = (this.userListAllFieldUsers || []).filter(u =>
            (u.Name || '').toLowerCase().includes(this.roleUserSearchKey)
        );
    }

    handleRoleUserSelect(event) {
        const selectedUserId = event.currentTarget.dataset.userid;
        if (!selectedUserId) return;

        const selectedUser = (this.userListAllFieldUsers || []).find(
            u => u.userId === selectedUserId || u.Id === selectedUserId
        );

        if (!selectedUser) return;

        this.tempSelectedUserId = selectedUser.userId || selectedUser.Id;
        this.tempSelectedUserName = selectedUser.Name;

        this.roleUserSearchKey = selectedUser.Name;

        this.roleUserOptions = [];
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

    handleSearch(event) {
        this.searchKey = event.target.value.toLowerCase();
        this.applyAllFilters();
    }

    toggleRoleFilter() {
        this.tempSelectedRoles = [...this.selectedRoles];
        this.roleFilterVisible = !this.roleFilterVisible;
    }

    closeRoleFilter() {
        this.roleFilterVisible = false;
    }

    handleRoleCheckboxChange(event) {
        const role = event.target.dataset.value;

        if (event.target.checked) {
            if (!this.tempSelectedRoles.includes(role)) {
                this.tempSelectedRoles.push(role);
            }
        } else {
            this.tempSelectedRoles = this.tempSelectedRoles.filter(r => r !== role);
        }
    }

    applyRoleFilter() {
        this.selectedRoles = [...this.tempSelectedRoles];

        let list = [...(this.userListAllFieldUsers || [])];

        if (this.selectedRoles.length > 0) {
            const roleLower = this.selectedRoles.map(r => r.toLowerCase());
            list = list.filter(u =>
                roleLower.includes((u.Employee_Role__c || '').toLowerCase())
            );
        }

        if (this.tempSelectedUserId) {
            this.loadSubordinatesForSelectedUser(this.tempSelectedUserId)
                .then(() => {
                    if (this.selectedRoles.length > 0) {
                        const roleLower = this.selectedRoles.map(r => r.toLowerCase());
                        this.filteredUsers = this.filteredUsers.filter(u =>
                            roleLower.includes((u.Employee_Role__c || '').toLowerCase())
                        );
                    }
                    this.roleFilterVisible = false;
                    this.saveStateToSession();
                });
            return;
        }

        this.filteredUsers = list;
        this.roleFilterVisible = false;
        this.saveStateToSession();
    }

    async loadSubordinatesForSelectedUser(userId) {
        const res = await getSubordinatesincludeself({ parentUserId: userId });
        const users = Array.isArray(res) ? res : (res.users || []);

        if (!users.length) {
            this.filteredUsers = [];
            this.saveStateToSession();
            return;
        }

        const preparedUsers = users.map(u => {
            const actual = u.actualAmount || u.TotalOrderValue || 0;
            const target = u.targetAmount || u.SecondaryTarget || 0;

            const performance = target > 0 ? Math.round((actual / target) * 100) : 0;

            return {
                ...u,
                Name: u.Name || '',
                Role: u.Role || 'No Role',
                Phone: u.Phone || null,

                // Raw numbers
                actualAmount: actual,
                targetAmount: target,
                totalOrderValue: actual,        // alias for clarity
                secondarySalesTarget: target,   // alias for clarity

                // Formatted numbers
                actualFormatted: this.formatCurrency(actual),
                targetFormatted: this.formatCurrency(target),
                totalOrderFormatted: this.formatCurrency(actual),
                secondaryTargetFormatted: this.formatCurrency(target),

                performance: performance,
                performanceClass: this.getPerformanceClass(performance),
                progressStyle: `width:${performance > 100 ? 100 : performance}%;`,
                keyBar: u.userId + '_bar' 
            };
        });

        this.filteredUsers = [...preparedUsers];
        this.saveStateToSession();
    }

    clearRoleFilter() {
        this.selectedRoles = [];
        this.tempSelectedRoles = [];
        this.tempSelectedUserId = null;
        this.tempSelectedUserName = null;
        this.roleUserSearchKey = '';
        this.filteredUsers = [...this.userListAllFieldUsers];
        this.saveStateToSession();
    }

    applyAllFilters() {
        let list = [...this.userListAllFieldUsers];

        if (this.searchKey) {
            list = list.filter(u =>
                (u.Name || '').toLowerCase().includes(this.searchKey) ||
                (u.Employee_Role__c || '').toLowerCase().includes(this.searchKey)
            );
        }

        if (this.selectedRoles.length > 0) {
            list = list.filter(u =>
                this.selectedRoles.includes(u.Employee_Role__c)
            );
        }

        if (this.tempSelectedUserId) {
            list = list.filter(u => u.Id === this.tempSelectedUserId);
        }

        this.filteredUsers = list;
        this.saveStateToSession();
    }

    handleBack() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Custom_Dashboard' }
        });
    }

    get kpiProgressStyle() {
        const pct = this.performancePercentage > 100 ? 100 : this.performancePercentage;
        return `width:${pct}%;`;
    }

    saveStateToSession() {
        const state = {
            breadcrumb: this.breadcrumb,
            currentUser: this.currentUser,
            directReports: this.directReports,
            isAllFieldMode: this.isAllFieldMode,
            filteredUsers: this.filteredUsers,
            userListAllFieldUsers: this.userListAllFieldUsers,
            selectedRoles: this.selectedRoles,
            tempSelectedUserId: this.tempSelectedUserId,
            tempSelectedUserName: this.tempSelectedUserName
        };
        try {
            sessionStorage.setItem('subordinateDashboardState', JSON.stringify(state));
        } catch (e) {
            // sessionStorage can throw if quota exceeded or in certain browsers; log and continue
            console.warn('Could not save subordinateDashboardState to sessionStorage', e);
        }
    }

}