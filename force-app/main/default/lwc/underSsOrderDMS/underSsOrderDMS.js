import { LightningElement, track } from 'lwc';
import getAllUnderSs from '@salesforce/apex/UnderSsOrderDMSController.getAllUnderSs';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class UnderSsOrderDMS extends LightningElement {
    @track showOrderTable = false;
    @track showUnderSsTable = true;
    @track searchRetailerValue = '';
    @track retailerData = [];
    @track SelectedRetailers = [];
    @track retailerPrimaryState = '';
    @track retailerColumns = [
        { label: 'Retailer Name', fieldName: 'Name' },
        { label: 'Phone', fieldName: 'Owners_Number__c' }
    ];

    connectedCallback() {
        this.fetchUnderSs();
    }

    fetchUnderSs() {
        getAllUnderSs({ searchValue: this.searchRetailerValue })
            .then(result => {
                console.log('result ', result);
                // BUG FIX: result.map was corrupted as markdown links — fixed to plain JS
                this.retailerData = result.map(row => ({ ...row }));
                console.log('retailerData ', this.retailerData);
            })
            .catch(error => {
                this.showToast('Error', 'Error fetching Retailer', 'error');
                console.error('Error fetching Retailer:', error);
            });
    }

    handleSearch(event) {
        // BUG FIX: event.target was corrupted as a markdown link
        this.searchRetailerValue = event.target.value;
        this.fetchUnderSs();
    }

    handleRetailerSelection(event) {
        const selected = event.detail.selectedRows;
        console.log('Selected Rows:', JSON.stringify(selected));

        if (selected.length > 0) {
            let lastSelected = selected[selected.length - 1];

            // BUG FIX: lastSelected.id / lastSelected.Id were markdown-link corrupted
            if (!lastSelected.id && !lastSelected.Id) {
                return;
            }

            this.SelectedRetailers = [lastSelected.id || lastSelected.Id];
            this.retailerPrimaryState = lastSelected.Primary_State__c;
            console.log('Selected Row ID:', JSON.stringify(this.SelectedRetailers));
        } else {
            this.SelectedRetailers = [];
            console.log('No selection');
        }
    }

    handleNext() {
        if (this.SelectedRetailers.length === 0) {
            this.showToast('Error', 'Select Retailer', 'error');
        } else if (!this.retailerPrimaryState) {
            this.showToast('Error', 'Primary state is missing for the selected retailer', 'error');
        } else {
            this.showUnderSsTable = false;
            this.showOrderTable = true;
        }
    }

    handleOrderChange(event) {
        this.showOrderTable = event.detail;
        this.showUnderSsTable = !this.showOrderTable;
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({ title, message, variant });
        this.dispatchEvent(evt);
    }
}