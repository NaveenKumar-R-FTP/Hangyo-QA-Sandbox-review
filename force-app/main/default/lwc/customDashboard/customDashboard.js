import { LightningElement, track } from 'lwc';
import USER_ID from '@salesforce/user/Id';

export default class UserHierarchyParent extends LightningElement {
    
    @track userId = USER_ID;
    @track refreshLabel = "Just now";
    refreshTimer;

    connectedCallback() {
        this.startTimer();
    }

    startTimer() {
        let minutes = 0;
        this.refreshLabel = "Just now";

        this.refreshTimer = setInterval(() => {
            minutes++;
            if(minutes === 1) this.refreshLabel = "1 min ago";
            else this.refreshLabel = `${minutes} mins ago`;
        }, 60000); // updates every 1 min
    }

    handleRefresh() {
        window.location.reload();  // HARD REFRESH
    }

    disconnectedCallback() {
        clearInterval(this.refreshTimer);
    }
}