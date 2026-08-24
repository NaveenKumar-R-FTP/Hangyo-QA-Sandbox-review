import { LightningElement , track } from 'lwc';
import getAllBeats from '@salesforce/apex/UpdateRetailerBeatController.getAllBeats';
import getAllRetailer from '@salesforce/apex/UpdateRetailerBeatController.getAllRetailer';
import updateRetailerRecord from '@salesforce/apex/UpdateRetailerBeatController.updateRetailerRecord';
import {ShowToastEvent} from 'lightning/platformShowToastEvent';

export default class UpdateRetailerBeat extends LightningElement {
    @track beatData = [];
    @track filteredBeatData = []; // To store filtered beat data based on search
    @track showBeatTable = true;
    @track showRetailerTable = false;
    selectedBeatId = '';
    @track searchBeatValue = '';
    @track searchRetailerValue = '';
    @track retailerData = [];
    @track selectedBeatRows = [];
    @track selectedBeatDistributor = '';
    @track selectedRetailers = [];
    @track selectedRows = [];
    
    @track beatColumns = [
        { label: 'Beat Name', fieldName: 'Name' },
        { label: 'Territory', fieldName: 'Territory__c' }
    ];

    @track retailerColumns = [
        { label: 'Retailer Name', fieldName: 'Name' },
        { label: 'Phone', fieldName: 'Owners_Number__c' }
    ];

    //Connected call back to get all beat for the logged in User
    connectedCallback() {
        this.fetchBeats();
        this.fetchRetailer();
    }

    fetchBeats() {
        getAllBeats({'searchValue':this.searchBeatValue})
        .then(result => {
            this.beatData = result;
        })
        .catch(error => {
            this.showToast('Error', 'Error fetching Beats', 'error');
            console.error('Error fetching Beats:', error);
        });
    }

    handleSearch(event){
        this.searchBeatValue = event.target.value;
        this.fetchBeats();
    }

    // Handler for selecting a beat
    /*handleBeatSelection = event => {         
        var selectedRows=event.detail.selectedRows;         
        if(selectedRows.length>1) {             
            var el = this.template.querySelector('lightning-datatable');             
            selectedRows=el.selectedRows=el.selectedRows.slice(1);   
            //selectedRows=el.selectedRows = [selectedRows[0]];        
            event.preventDefault();             
            return;         
        } 
        this.selectedBeatRows = event.detail.selectedRows[0]?.Id;
        console.log('selectedBeatRows: ', this.selectedBeatRows);
    }*/

    handleBeatSelection(event) {
        const selected = event.detail.selectedRows;
        console.log('Selected Rows:', JSON.stringify(selected));

        if (selected.length > 0) {
            let lastSelected = selected[selected.length - 1];
            if (!lastSelected.id && !lastSelected.Id) {
                return;
            }

            // Store the last selected row ID
            this.selectedBeatRows = [lastSelected.id || lastSelected.Id];
            this.selectedBeatDistributor = lastSelected.Distributor_Name__c;
            console.log('Selected Row ID:', JSON.stringify(this.selectedBeatRows));
            console.log('Selected Beat Distributor:', this.selectedBeatDistributor); // Should print the selected ID
        } else {
            this.selectedBeatRows = [];
            console.log('No selection');
        }
    }



    handleNext(){
        console.log('this.selectedBeatRows',JSON.stringify(this.selectedBeatRows));
        if (!this.selectedBeatRows || this.selectedBeatRows.length === 0) {
            this.showToast('Error', 'Select Beat', 'error');
        } else if (!this.selectedBeatDistributor) {
            this.showToast('Error', 'No distributor exists for the selected beat', 'error');
        } else {
            this.showBeatTable = false;
            this.showRetailerTable = true;
        }
    }

    fetchRetailer() {
        getAllRetailer({'searchValue':this.searchRetailerValue})
        .then(result => {
            this.retailerData = result;
        })
        .catch(error => {
            this.showToast('Error', 'Error fetching Retailer', 'error');
            console.error('Error fetching Retailer:', error);
        });
    }

    handleRetailerSearch(event){
        this.searchRetailerValue = event.target.value;
        this.fetchRetailer();
    }

    handleRetailerSelection(event) {
        //this.selectedRetailers = event.detail.selectedRows.map(row => row.Id);
        //console.log('selectedRetailers: ', this.selectedRetailers);
        const selectedRows = event.detail.selectedRows;
        this.selectedRetailers = [];

        selectedRows.forEach(row => {
            console.log('Retailer distributor: ',row.Distributor__c);
            if (row.Distributor__c === this.selectedBeatDistributor) {
                this.selectedRetailers.push(row.Id);
            } else {
                //alert('Selected retailer does not match the distributor for the beat!');
                this.showToast('Error', 'Selected retailer does not match the distributor for the beat!', 'error');
            }
        });

        console.log('selectedRetailers: ', this.selectedRetailers);
    }

    handleBackIconClick(){
        this.showBeatTable = true;
        this.showRetailerTable = false;
    }

    updateBeat(){
        if(this.selectedBeatRows == '' || this.selectedRetailers.length === 0){
            this.showToast('Error', 'Select Beat and Retailer', 'error');
        }else{
            updateRetailerRecord({beatId : this.selectedBeatRows , retailerId : this.selectedRetailers})
            .then(result => {
                if(result == 'Success'){
                    this.showToast('Success', 'Retailer record has been updated!', 'success');
                    this.showBeatsTable = true;
                    this.showRetailerTable = false;
                    this.resetComponent();                
                    //this.handleBackOnMyVisitTask();
                    setTimeout(() => {
                        location.reload(); 
                    },10);
                }
            })
            .catch(error => {
                this.showToast('Error', 'Error while updating retailer', 'error');
                console.error('Error while updating retailer:', error);
            });
        }
    }

    //Reset the values
    resetComponent() {
        this.selectedBeat = '';
        this.selectedRetailers = [];
        this.showBeatsTable = true;
        this.showRetailerTable = false;
        this.selectedBeatRows = [];
        this.selectedRetailers = [];
        this.selectedRows = []; 
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