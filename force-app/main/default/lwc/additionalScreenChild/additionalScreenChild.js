import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHierarchyWithMetrics from '@salesforce/apex/UserHierarchyDataController.getHierarchyWithMetrics';
import USER_ID from '@salesforce/user/Id';

export default class AdditionalHierarchy extends NavigationMixin(LightningElement) {
    @track selectedUser = { metrics: this.getEmptyMetrics() };
    @track subordinates = [];
    @track isLoading = false;
    userStack = [];

    connectedCallback() {
        const savedState = sessionStorage.getItem('hierarchyState');
        if (savedState) {
            const state = JSON.parse(savedState);
            this.selectedUser = state.selectedUser;
            this.subordinates = state.subordinates;
            this.userStack = state.userStack;
        } else {
            this.loadHierarchy(USER_ID);
        }
    }

    getEmptyMetrics() {
        return { plannedCount: 0, lpcCount: "0.00", tlcCount: 0, netPay: 0, qty: 0 };
    }

    // --- FIX FOR LPC AND UNDEFINED ERRORS ---
    formatMetrics(m) {
        const metrics = m || {};
        const planned = metrics.plannedCount || 0;
        const tlc = metrics.tlcCount || 0;
        
        return {
            plannedCount: planned,
            tlcCount: tlc,
            netPay: (metrics.netPay || 0).toLocaleString(), // Formats as 1,000.00
            qty: metrics.qty || 0,
            // LPC calculation with divide-by-zero check
            lpcCount: planned > 0 ? (tlc / planned).toFixed(2) : "0.00"
        };
    }

    loadHierarchy(userId) {
        this.isLoading = true;
        getHierarchyWithMetrics({ rootUserId: userId })
            .then(resp => {
                if (resp && resp.parentUser) {
                    const parent = resp.parentUser;
                    
                    if (this.selectedUser && this.selectedUser.id && this.selectedUser.id !== parent.userId) {
                        this.userStack.push({ ...this.selectedUser, subordinates: this.subordinates });
                    }

                    this.selectedUser = {
                        id: parent.userId,
                        name: parent.userName,
                        role: parent.roleName,
                        metrics: this.formatMetrics(parent.metrics)
                    };

                    this.subordinates = (parent.directSubordinates || []).map(u => ({
                        id: u.userId,
                        name: u.userName,
                        role: u.roleName,
                        metrics: this.formatMetrics(u.metrics)
                    }));

                    this.saveState();
                }
                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error loading hierarchy:', error);
                this.isLoading = false;
            });
    }

    saveState() {
        sessionStorage.setItem('hierarchyState', JSON.stringify({
            selectedUser: this.selectedUser,
            subordinates: this.subordinates,
            userStack: this.userStack
        }));
    }

    handleSubClick(event) {
        this.loadHierarchy(event.currentTarget.dataset.id);
    }

    handleGoBack() {
        if (this.userStack.length > 0) {
            const last = this.userStack.pop();
            this.selectedUser = last;
            this.subordinates = last.subordinates || [];
            this.saveState();
        } else {
            sessionStorage.removeItem('hierarchyState');
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: { apiName: 'Custom_Dashboard' }
            });
        }
    }
}