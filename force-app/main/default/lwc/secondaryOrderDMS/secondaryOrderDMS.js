import { LightningElement , track } from 'lwc';
import getAllRetailer from '@salesforce/apex/SecondaryOrderDMSController.getAllRetailer';
import {ShowToastEvent} from 'lightning/platformShowToastEvent';

export default class SecondaryOrderDMS extends LightningElement {
    @track showOrderTable = false;
    @track showRetailerTable = true;
    @track searchRetailerValue = '';
    @track retailerData = [];
    @track SelectedRetailers = [];
    @track retailerPrimaryState = [];

    @track retailerColumns = [
        { label: 'Retailer Name', fieldName: 'Name' },
        { label: 'Phone', fieldName: 'Owners_Number__c' },
        { label: 'Beat Name', fieldName: 'BeatName' } // Lookup field display
    ];

    //Connected call back to get all beat for the logged in User
    connectedCallback() {
        this.fetchRetailer();
    }

    fetchRetailer() {
        getAllRetailer({ 'searchValue': this.searchRetailerValue })
            .then(result => {
                console.log('result ', result);

                // Flatten Beat Name lookup field
                this.retailerData = result.map(row => ({
                    ...row,
                    BeatName: row.Beats_Name__r ? row.Beats_Name__r.Name : ''
                }));

                console.log('retailerData ', this.retailerData);
            })
            .catch(error => {
                this.showToast('Error', 'Error fetching Retailer', 'error');
                console.error('Error fetching Retailer:', error);
            });
    }


    handleSearch(event){
        this.searchRetailerValue = event.target.value;
        this.fetchRetailer();
    }

    handleRetailerSelection(event) {
        const selected = event.detail.selectedRows;
        console.log('Selected Rows:', JSON.stringify(selected));

        if (selected.length > 0) {
            let lastSelected = selected[selected.length - 1];
            if (!lastSelected.id && !lastSelected.Id) {
                return;
            }
            // Store the last selected row ID
            this.SelectedRetailers = [lastSelected.id || lastSelected.Id];
            this.retailerPrimaryState = lastSelected.Primary_State__c;
            console.log('Selected Row ID:', JSON.stringify(this.SelectedRetailers));
        } else {
            this.SelectedRetailers = [];
            console.log('No selection');
        }
    }

    handleNext(){
        if (this.SelectedRetailers.length === 0) {
            this.showToast('Error', 'Select Retailer', 'error');
        } else if(!this.retailerPrimaryState){
            this.showToast('Error', 'Primary state is missing for the selected retailer', 'error');
        } else {
            this.showRetailerTable = false;
            this.showOrderTable = true;
        }
    }

    handleOrderChange(event){
        this.showOrderTable = event.detail;
        this.showRetailerTable = !this.showOrderTable;
    }

    //Toast message
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title,
            message,
            variant,
        });
        this.dispatchEvent(evt);
    }
}