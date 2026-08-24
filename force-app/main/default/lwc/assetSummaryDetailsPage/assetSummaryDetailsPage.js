import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import userId from '@salesforce/user/Id';

import getSummaryForUser from '@salesforce/apex/AssetSummaryController.getSummaryForUser';
import getAllFieldSubordinates from '@salesforce/apex/AssetSummaryController.getAllFieldSubordinates';

export default class AssetSummaryDetails extends NavigationMixin(LightningElement) {

    // Main lists
    @track userList = [];
    @track allFieldList = [];
    @track baseAllFieldList = []; // For search filtering
    
    // Current user metrics
    @track currentUserMetrics = {
        userId: '',
        name: '',
        role: '',
        totalDF: 0,
        billedDF: 0,
        zeroBillingDF: 0,
        throughput: 0
    };

    // Flags
    @track loading = false;
    @track noData = false;
    @track isAllFieldMode = false;

    // UI State
    @track breadcrumb = [];
    @track lastRefreshed = 'Never';

    // Search
    @track searchKey = '';
    @track roleFilterVisible = false;
    @track selectedRoles = [];
    @track tempSelectedRoles = [];

    // Drill-down state
    history = [];
    currentUserId = userId;

    /* -----------------------------------------
       RESTORE URL PARAMETERS
    -------------------------------------------- */
    @wire(CurrentPageReference)
    urlHandler(ref) {
        if (ref?.state?.c__uid) {
            this.currentUserId = ref.state.c__uid;
        }
    }

    /* -----------------------------------------
       ON LOAD
    -------------------------------------------- */
    connectedCallback() {
        const saved = sessionStorage.getItem('assetSummaryState');

        if (saved) {
            try {
                const st = JSON.parse(saved);
                this.currentUserId = st.currentUserId || this.currentUserId;
                this.history = st.history || [];
                this.breadcrumb = st.breadcrumb || [];
                this.isAllFieldMode = st.isAllFieldMode || false;
                this.searchKey = st.searchKey || '';
                this.selectedRoles = st.selectedRoles || [];
                // Restore current user metrics if saved
                if (st.currentUserMetrics) {
                    this.currentUserMetrics = st.currentUserMetrics;
                }
            } catch (e) {
                console.warn('Could not parse saved state:', e);
            }
        }

        if (!this.isAllFieldMode) {
            this.loadUserData(this.currentUserId);
        }
    }

    /* -----------------------------------------
       LOAD USER DATA
    -------------------------------------------- */
    async loadUserData(uid) {
        this.loading = true;
        this.userList = [];
        this.noData = false;

        try {
            // Get current user's summary (individual metrics + rolled-up subordinates)
            const result = await getSummaryForUser({ userId: uid });
            
            // Set current user metrics (INDIVIDUAL metrics for current user)
            this.currentUserMetrics = {
                userId: result.userId,
                name: result.name || 'Current User',
                role: result.role || 'No Role',
                totalDF: result.totalDF || 0,
                billedDF: result.billedDF || 0,
                zeroBillingDF: result.zeroBillingDF || 0,
                throughput: result.throughput || 0
            };

            // Update breadcrumb
            this.updateBreadcrumb(result.userId, result.name);

            // Set direct subordinates (ROLLED-UP metrics for each subordinate)
            if (result.subordinates && result.subordinates.length > 0) {
                this.userList = result.subordinates.map(sub => ({
                    userId: sub.userId,
                    name: sub.name,
                    role: sub.role,
                    totalDF: sub.totalDF || 0,
                    billedDF: sub.billedDF || 0,
                    zeroBillingDF: sub.zeroBillingDF || 0,
                    throughput: sub.throughput || 0
                }));
            } else {
                this.noData = true;
            }

            this.currentUserId = uid;

        } catch (err) {
            console.error('Error loading asset data:', err);
            this.noData = true;
        }

        this.loading = false;
        this.updateRefreshTime();
        this.saveState();
    }

    /* -----------------------------------------
       LOAD ALL FIELD USERS (ENTIRE HIERARCHY)
    -------------------------------------------- */
    async handleAllFieldClick() {
        this.isAllFieldMode = true;
        this.allFieldList = [];
        this.baseAllFieldList = [];
        this.searchKey = '';
        this.loading = true;

        try {
            // Get all field users with INDIVIDUAL metrics
            const allUsers = await getAllFieldSubordinates({ 
                userId: userId 
            });

            // Filter out the current user (logged-in user)
            const filteredUsers = allUsers.filter(user => user.userId !== userId);
            
            if (filteredUsers.length > 0) {
                this.allFieldList = filteredUsers.map(user => ({
                    userId: user.userId,
                    name: user.name,
                    role: user.role,
                    phone: user.phone,
                    totalDF: user.totalDF || 0,
                    billedDF: user.billedDF || 0,
                    zeroBillingDF: user.zeroBillingDF || 0,
                    throughput: user.throughput || 0
                }));
                
                this.baseAllFieldList = [...this.allFieldList];
                this.noData = false;
            } else {
                this.noData = true;
            }

        } catch (e) {
            console.error('All Field error:', e);
            this.noData = true;
        }

        this.loading = false;
        this.saveState();
    }

    handleAllFieldBack() {
        this.isAllFieldMode = false;
        this.searchKey = '';
        this.selectedRoles = [];
        this.saveState();
    }

    /* -----------------------------------------
       SEARCH FUNCTIONALITY
    -------------------------------------------- */
    handleSearch(event) {
        this.searchKey = event.target.value.toLowerCase();
        this.applyFilters();
    }

    handleKeyUp(event) {
        if (event.key === 'Enter') {
            this.searchKey = event.target.value.toLowerCase();
            this.applyFilters();
        }
    }

    applyFilters() {
        let filtered = [...this.baseAllFieldList];

        // Apply search
        if (this.searchKey) {
            filtered = filtered.filter(user =>
                (user.name && user.name.toLowerCase().includes(this.searchKey)) ||
                (user.role && user.role.toLowerCase().includes(this.searchKey))
            );
        }

        // Apply role filters
        if (this.selectedRoles.length > 0) {
            filtered = filtered.filter(user =>
                this.selectedRoles.includes(user.role)
            );
        }

        this.allFieldList = filtered;
        this.noData = filtered.length === 0;
    }

    /* -----------------------------------------
       ROLE FILTER
    -------------------------------------------- */
    toggleRoleFilter() {
        this.roleFilterVisible = !this.roleFilterVisible;
        if (this.roleFilterVisible) {
            this.tempSelectedRoles = [...this.selectedRoles];
        }
    }

    closeRoleFilter() {
        this.roleFilterVisible = false;
    }

    handleRoleCheckboxChange(event) {
        const role = event.target.dataset.value;
        const isChecked = event.target.checked;

        if (isChecked) {
            if (!this.tempSelectedRoles.includes(role)) {
                this.tempSelectedRoles.push(role);
            }
        } else {
            this.tempSelectedRoles = this.tempSelectedRoles.filter(r => r !== role);
        }
    }

    applyRoleFilter() {
        this.selectedRoles = [...this.tempSelectedRoles];
        this.applyFilters();
        this.roleFilterVisible = false;
    }

    clearRoleFilter() {
        this.selectedRoles = [];
        this.tempSelectedRoles = [];
        this.applyFilters();
        this.roleFilterVisible = false;
    }

    get roleOptions() {
        const rolesSet = new Set();
        this.baseAllFieldList.forEach(user => {
            if (user.role) {
                rolesSet.add(user.role);
            }
        });
        return Array.from(rolesSet).map(role => ({
            label: role,
            value: role,
            selected: this.selectedRoles.includes(role)
        }));
    }

    /* -----------------------------------------
       DRILL DOWN
    -------------------------------------------- */
    async handleUserClick(e) {
        const uid = e.currentTarget.dataset.userid;
        if (!uid) return;

        this.history.push({
            userId: this.currentUserId,
            userList: [...this.userList],
            breadcrumb: [...this.breadcrumb],
            currentUserMetrics: {...this.currentUserMetrics}
        });

        this.currentUserId = uid;
        await this.loadUserData(uid);

        this.saveState();
    }

    /* -----------------------------------------
       BACK
    -------------------------------------------- */
    handleGoBack() {
        if (!this.history.length) {
            this.navigateToDashboard();
            return;
        }

        const prev = this.history.pop();

        this.currentUserId = prev.userId;
        this.userList = prev.userList;
        this.breadcrumb = prev.breadcrumb;
        this.currentUserMetrics = prev.currentUserMetrics || this.currentUserMetrics;

        this.saveState();
    }

    /* -----------------------------------------
       BREADCRUMB
    -------------------------------------------- */
    updateBreadcrumb(uid, name) {
        const idx = this.breadcrumb.findIndex(b => b.userId === uid);

        if (idx === -1) {
            this.breadcrumb = this.breadcrumb.map(b => ({ ...b, showSeparator: true }));
            this.breadcrumb.push({
                userId: uid,
                userName: name,
                showSeparator: this.breadcrumb.length > 0
            });
        } else {
            this.breadcrumb = this.breadcrumb
                .slice(0, idx + 1)
                .map((b, i) => ({ ...b, showSeparator: i > 0 }));
        }
    }

    handleBreadcrumbClick(e) {
        const uid = e.currentTarget.dataset.userid;
        if (uid) this.loadUserData(uid);
    }

    /* -----------------------------------------
       REFRESH
    -------------------------------------------- */
    handleRefresh() {
        if (this.isAllFieldMode) {
            this.handleAllFieldClick();
        } else {
            this.loadUserData(this.currentUserId);
        }
    }

    updateRefreshTime() {
        this.lastRefreshed = new Date().toLocaleString();
    }

    /* -----------------------------------------
       NAVIGATION
    -------------------------------------------- */
    navigateToDashboard() {
        sessionStorage.removeItem('assetSummaryState');

        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Custom_Dashboard' }
        });
    }

    /* -----------------------------------------
       STATE SAVE
    -------------------------------------------- */
    saveState() {
        sessionStorage.setItem(
            "assetSummaryState",
            JSON.stringify({
                currentUserId: this.currentUserId,
                history: this.history,
                breadcrumb: this.breadcrumb,
                isAllFieldMode: this.isAllFieldMode,
                searchKey: this.searchKey,
                selectedRoles: this.selectedRoles,
                currentUserMetrics: this.currentUserMetrics
            })
        );
    }
}