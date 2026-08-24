import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAllBeats from '@salesforce/apex/ChangeBeatController.getAllBeats';
import getRetailersByBeat from '@salesforce/apex/ChangeBeatController.getRetailersByBeat';
import createVisitsApex from '@salesforce/apex/ChangeBeatController.createVisits';
import {NavigationMixin } from 'lightning/navigation';


export default class BeatChange extends NavigationMixin(LightningElement) {
    @track fromDate = '';    
    @track formattedTodayDate = '';
    @track selectedBeat = '';
    @track selectedRows = [];
    @track selectedRetailers = [];
    @track showOptions = true;
    @track showDates = true;
    @track showBeatsTable = true;
    @track showRetailerTable = false;
    @track beatData = []; 
    @track filteredBeatData = [];
    @track retailerData = []; 
    @track filteredRetailerData = [];
    @track beatColumns = [
        { label: 'Beat Name', fieldName: 'Name' },
        { label: 'Territory', fieldName: 'Territory__c' }
    ];
    @track retailerColumns = [
        { label: 'Retailer Name', fieldName: 'Name' },
        { label: 'Phone', fieldName: 'Owners_Number__c' }
    ];

    @track isButtonDisabled = false;

    //Connected call back to get all beat for the logged in User
    connectedCallback() {
        getAllBeats()
            .then(result => {
                this.beatData = result;
                this.filteredBeatData = result;
            })
            .catch(error => {
                this.showToast('Error', 'Error fetching Beats', 'error');
            });

            this.setDefaultDate();
    }

    //Set default date as Today (Dynamically)
    setDefaultDate() {
        const today = new Date();
        this.formattedTodayDate = this.formatDateInIndianStyle(today);
        this.fromDate = this.formatDateForSalesforce(today);
    }
    
    //Format (Indian) todays date for showing on UI
    formatDateInIndianStyle(date) {
        const options = { day: '2-digit', month: 'short', year: 'numeric' };
        const formattedDate = new Intl.DateTimeFormat('en-IN', options).format(date);
        const [day, month, year] = formattedDate.split(' ');
        return `${day}-${month}-${year}`;
    }

    //Format Todays date for salesforce operation 
    formatDateForSalesforce(date) {
        // Format the date in 'YYYY-MM-DD' format for Salesforce
        const year = date.getFullYear();
        const month = (date.getMonth() + 1).toString().padStart(2, '0'); // Adding leading zero if necessary
        const day = date.getDate().toString().padStart(2, '0'); // Adding leading zero if necessary
    
        // Return the date in 'YYYY-MM-DD' format
        return `${year}-${month}-${day}`;
    }

    // Handle Beat selection event
    handleBeatSelection(event) {
    const selectedRows = event.detail.selectedRows;

    if (selectedRows.length > 1) {
        this.showToast('Error', 'You can only select one Beat at a time.', 'error');
        this.template.querySelector('lightning-datatable').selectedRows = [];
        this.selectedBeat = '';
        this.selectedRows = [];
    } else if (selectedRows.length === 1) {
        this.selectedBeat = selectedRows[0].Id;
        this.loadRetailers();
    } else {
        // This block handles the case when user deselects the selected beat
        this.selectedBeat = '';
        this.selectedRows = [];
        this.retailerData = [];
        this.filteredRetailerData = [];
        this.selectedRetailers = [];
    }
}
  
    //Get all retailer for selected Beat & Logged in User
    loadRetailers() {
        if (this.selectedBeat) {
            getRetailersByBeat({ beatId: this.selectedBeat })
                .then(result => {
                    this.retailerData = result;
                    this.filteredRetailerData = result;
                    this.selectedRetailers = result.map(row => row.Id); // Auto-select all

                })
                .catch(error => {
                    this.showToast('Error', 'Error fetching Retailers', 'error');
                });
        }
    }

    //Handle Row selections from the datatable
    handleRowSelection(event) {
        this.selectedRetailers = this.filteredRetailerData.map(row => row.Id);
    }

    // Handle search event (for Beat) input
    handleSearch(event) {
        const query = event.target.value.toLowerCase();
        this.filteredBeatData = this.beatData.filter(beat =>
            beat.Name.toLowerCase().includes(query)
        );
    }
    
    // Handle search event (for Retailer) input
    handleSearchRetailer(event) {
        const query = event.target.value.toLowerCase();

    if (query) {
        this.filteredRetailerData = this.retailerData.filter(retailer =>
            retailer.Name.toLowerCase().includes(query)
        );
    } else {
        this.filteredRetailerData = [...this.retailerData];
    }

    // Automatically select all filtered retailers
    this.selectedRetailers = this.filteredRetailerData.map(retailer => retailer.Id);
    }

   // Handle Back click to navigate user on my visit page
    handleBackOnMyVisitTask(){
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',  
            attributes: {
                apiName: 'My_Visit_Tasks' 
            }
        });
    }
 
    // Handle Back click to navigate user on First page of Beat change component
    handleBackIconClick() {
    this.showOptions = true;
    this.showBeatsTable = true;
    this.showRetailerTable = false;

    this.selectedRetailers = [];
    this.selectedBeat = '';
    this.retailerData = [];
    this.filteredRetailerData = [];

    // Clear beat selection in the datatable UI
    const datatable = this.template.querySelector('lightning-datatable');
    if (datatable) {
        datatable.selectedRows = [];
    }
}
    // Moving for second page on Beat change component
    handleNext() {
        this.setDefaultDate();
        if (this.showOptions && !this.fromDate) {
            this.showToast('Error', 'Please select a date before proceeding.', 'error');
        } else if (this.showBeatsTable && !this.selectedBeat) {
            this.showToast('Error', 'Please select a Beat before proceeding.', 'error');
        } else {
            this.showOptions = false;
            this.showBeatsTable = false;
            this.showRetailerTable = true;
        }
    }

    //Handle creation of New Visit, Visit Task Record & navigating on My Visit Page (Mobile)
    createVisits() {
        this.isButtonDisabled = true;
        if (!this.fromDate || this.selectedRetailers.length === 0) {
            this.showToast('Error', 'Please select at least one retailer.', 'error');
            this.isButtonDisabled = false;
            return;
        }

        this.isButtonDisabled = true;

        createVisitsApex({ 
            retailerIds: this.selectedRetailers, 
            visitDate: this.fromDate, 
            beatId: this.selectedBeat 
        })
            .then(() => {
                this.isButtonDisabled = true;
                this.showToast('Success', 'Visit & Visit Task are created successfully!', 'success');
                this.showOptions = true;
                this.showBeatsTable = true;
                this.showRetailerTable = false;
                this.resetComponent();                
                this.handleBackOnMyVisitTask();
                window.sessionStorage.setItem('shouldRefreshVisitData', 'true');
                setTimeout(() => {
                    this[NavigationMixin.Navigate]({
                        type: 'standard__navItemPage',
                        attributes: {
                            apiName: 'My_Visit_Tasks'
                        }
                    });
                
                    setTimeout(() => {
                        window.location.reload();
                    }, 500); // Give some time to complete navigation before refresh
                }, 100); 
            })
            .catch(error => {
                this.showToast('Error', 'Error creating visits', 'error');
                this.isButtonDisabled = false;
            });

    }

    //Reset the values
    resetComponent() {
        this.fromDate = '';
        this.selectedBeat = '';
        this.selectedRetailers = [];
        this.showOptions = true;
        this.showBeatsTable = true;
        this.showRetailerTable = false;
        this.filteredBeatData = this.beatData;
        this.filteredRetailerData = [];
    }
// Toast message
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title,
            message,
            variant,
        });
        this.dispatchEvent(evt);
    }
}