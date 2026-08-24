import { LightningElement , wire  , track} from 'lwc';
import getBeatsForOrderDate from '@salesforce/apex/VisitSummaryPdfRecord.getBeatsForOrderDate';
import fetchVisitSummaryDetail from '@salesforce/apex/VisitSummaryPdfRecord.fetchVisitSummaryDetail';
import getDistributorName from '@salesforce/apex/VisitSummaryPdfRecord.getDistributorName';
import generatePdfAndContentUrl from '@salesforce/apex/VisitSummaryPdfRecord.generatePdfAndContentUrl';
import {NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class GenerateVisitSummaryPdf extends NavigationMixin(LightningElement) {
    orderDate = '';
    pdfUrl;
    //isButtonDisabled = true;
    @track selectedBeat = '';
    @track beatOptions = [];
    isBeatDisabled = true; // Initially disable the Beat field
    @track beatOptions = []; // Store the filtered beats here
    distributor = '';
    orders = [];
    @track pdfId;
    distributorRecordId = '';

    connectedCallback() {
        this.orderDate = '';
        this.selectedBeat = '';
    }

    handleOrderDateChange(event){
        this.orderDate = event.target.value;
        if (this.orderDate) {
            this.fetchBeatsForDate();  
        }
    }

    fetchBeatsForDate() {
        getBeatsForOrderDate({ orderDate: this.orderDate })
        .then((result) => {
            if (result && result.length > 0) {
                const uniqueBeats = result.filter((beat, index, self) => 
                    index === self.findIndex((b) => b.Beat__c === beat.Beat__c) // Using Beat__c to determine uniqueness
                );
                // Map the unique beats to the beatOptions array
                this.beatOptions = uniqueBeats.map(beat => ({
                    label: beat.Beat__r?.Name, // Assuming 'Name' is the field for the beat name
                    value: beat.Beat__c // Assuming 'Id' is the field for beat identifier
                }));
                this.isBeatDisabled = false; // Enable the Beat field when beats are available
                this.showToast('', 'Please select the beat', 'Success');
            } else {
                this.beatOptions = [];
                this.isBeatDisabled = true; // Disable the Beat field if no beats are found
                this.showToast('Error', 'No beat available for the selected date', 'error');
            }
        })
        .catch((error) => {
            this.showToast('Error', 'Error fetching beats:', 'error');
            this.beatOptions = [];
            this.isBeatDisabled = true;
        });
    }

    handleBeatChange(event) {
        this.selectedBeat = event.target.value;
        if (this.selectedBeat) {
            // Call the method to fetch distributor based on selected beat ID
            this.fetchDistributorName(this.selectedBeat);
            
        }
    }

    fetchDistributorName(selectedBeatId){
        getDistributorName({ beatId: selectedBeatId})
        .then((result) => {
            if(result.length > 0){
                this.distributorRecordId = result;
                this.fetchOrderDeatil(this.distributorRecordId);
                this.generatePdfConent();
            }

        })
        .catch((error) => {
            this.showToast('Error', 'No distributor available for the selected beat', 'error');
        });
    }

    fetchOrderDeatil(distributorId) {
        fetchVisitSummaryDetail({ distributorId: distributorId , orderDate : this.orderDate})
        .then((result) => {
            if(result.length > 0){
                this.showToast('', 'Order for the selected date is fetched. Please click download button', 'Success');
                this.orders = result;
                //this.generatePdfConent();
            }else{
                this.showToast('Error', 'No order available for the selected date', 'error');
                this.orderDate = '';
                this.selectedBeat = '';
                this.isBeatDisabled = true;
            }
        })
        .catch((error) => {
            this.showToast('Error', 'Error', 'error');
            
        });
    }

    generatePdfConent(){
        generatePdfAndContentUrl({ distributorId: this.distributorRecordId , orderDate : this.orderDate})
        .then((result) => {
            if (result) {
                this.pdfId = result;

            }
        })
        .catch((error) => {
           this.showToast('Error', `${error}`, 'error');    
        });
    }

    handleOpenPdf() {
        if(this.orderDate == '' || this.selectedBeat == ''){
            this.showToast('Error', 'Please select the order date & beat', 'error');
        }else{
            if (this.pdfId) {
                this[NavigationMixin.Navigate]({
                    type: "standard__recordPage",
                    attributes: {
                        recordId: this.pdfId, // Use the stored ContentVersion ID
                        objectApiName: "ContentDocument",
                        actionName: "view"
                    }
                });
                this.navigateBackToRecordPage();
            }else{
                this.showToast('Error', 'No order exists', 'error');
            }
            
        }
    }

    backToVisitPage(){
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',  
            attributes: {
                apiName: 'My_Visit_Tasks'
            }
        });
    }

    navigateBackToRecordPage(){
        this.orderDate = '';
        this.orders = [];
        //this.isButtonDisabled = true;
        this.isBeatDisabled = true;
        this.selectedBeat = '';
    }

    showToast(tilte, message, variant) {
        const event = new ShowToastEvent({
            title: tilte,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
}