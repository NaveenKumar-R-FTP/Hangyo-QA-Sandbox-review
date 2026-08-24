import { LightningElement, api, track } from 'lwc';
import getSubordinateUsers from '@salesforce/apex/UserHierarchyService.getSubordinatesincludeself';
import getAttendanceSummary from '@salesforce/apex/UserHierarchyController.getAttendanceSummary';
import { NavigationMixin } from 'lightning/navigation';

export default class userSummary extends NavigationMixin(LightningElement) {
    @api parentUserId;

    @track subordinateUsers = [];
    @track absentCount = 0;
    @track leaveCount= 0;
    @track presentCount = 0;
    @track officialCount = 0;
    @track retailingCount = 0;
    @track totalUsers = 0;

    @track showDetailsModal = false;
    @track leaveUsers = [];
    @track halfDayUsers = [];
    @track retailUsers = [];

    @track subUsers = [];
    @track showSubUsers = false;
    loaded = false;

    connectedCallback() {
        console.log('connectedCallback fired');
        console.log('Received parentUserId:', this.parentUserId);
        this.loadData();
    }

    loadData() {
        console.log('Fetching Subordinate Users...');
        getSubordinateUsers({ parentUserId: this.parentUserId })
            .then(res => {
                console.log('Subordinates Result Wrapper:', JSON.stringify(res));

                this.subordinateUsers = res?.users || [];

                if (this.parentUserId && !this.subordinateUsers.some(u => u.Id === this.parentUserId)) {
                    this.subordinateUsers.push({
                        Id: this.parentUserId,
                        Name: res?.parentUserName || 'Parent User',
                        IsParent: true
                    });
                }

                console.log('Users Including Parent:', this.subordinateUsers.length);
                this.totalUsers = this.subordinateUsers.length;

                const ids = this.subordinateUsers.map(u => u.Id);
                if (!ids.length) {
                    this.loaded = true;
                    return;
                }

                const today = new Date();
                const onlyDate = today.toISOString().split('T')[0];

                console.log('Calling getAttendanceSummary with IDs:', ids);

                return getAttendanceSummary({
                    userIds: ids,
                    forDate: onlyDate
                });
            })
            .then(summary => {
                if (!summary) return;

                console.log('Attendance Summary:', JSON.stringify(summary));

                this.absentCount = summary.Absent || 0;
                this.leaveCount = summary.Leave || 0;
                this.presentCount = summary.Present || 0;
                this.officialCount = summary['Official Work'] || 0;
                this.retailingCount = summary.Retailing || 0;

                this.loaded = true;
            })
            .catch(err => {
                console.error('Error loading data:', JSON.stringify(err));
                this.loaded = true;
            });
    }

navigateToDetails() {
    console.log('Navigating to User_Summary_Details tab with parentId:', this.parentUserId);
    this[NavigationMixin.Navigate]({
        type: 'standard__navItemPage',
        attributes: {
            apiName: 'User_Summary_Details'
        },
        state: {
            c__parentId: this.parentUserId
        }
    });
}

handleCloseDetails() {
    this.showDetailsModal = false;
}


    openSubUsers(event) {
        const userId = event.currentTarget.dataset.userid;
        getSubordinateUsers({ parentUserId: userId })
            .then(res => {
                this.subUsers = res?.users || [];
                this.showSubUsers = true;
            })
            .catch(err => console.error('Error fetching sub users:', JSON.stringify(err)));
    }

    get absentWidth() {
        return `width: ${this.totalUsers ? (this.absentCount / this.totalUsers) * 100 : 0}%`;
    }
      get leaveWidth() {
        return `width: ${this.totalUsers ? (this.leaveCount / this.totalUsers) * 100 : 0}%`;
    }
    get presentWidth() {
        return `width: ${this.totalUsers ? (this.presentCount / this.totalUsers) * 100 : 0}%`;
    }
    get officialWidth() {
        return `width: ${this.totalUsers ? (this.officialCount / this.totalUsers) * 100 : 0}%`;
    }
    get retailingWidth() {
        return `width: ${this.totalUsers ? (this.retailingCount / this.totalUsers) * 100 : 0}%`;
    }
    
    isValidRetailer(addr) {
        return addr && addr.toUpperCase() !== 'N/A';
    }

}