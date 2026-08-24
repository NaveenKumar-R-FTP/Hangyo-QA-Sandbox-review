import { LightningElement,wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAllBeats from '@salesforce/apex/VisitSchedulerController.getAllBeats';
import getRetailersByBeat from '@salesforce/apex/VisitSchedulerController.getRetailersByBeat';
import createVisitsApex from '@salesforce/apex/VisitSchedulerController.createVisits';
import {NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';


export default class VisitScheduler extends NavigationMixin(LightningElement) {
    @track fromDate = '';
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

  wiredBeatsResult;
  connectedCallback() {
        this.fetchBeats();
    }

  async fetchBeats() {
    try {
        // Add { disableCache: true } to bypass caching
        const result = await getAllBeats({}, { disableCache: true });
        this.beatData = [...result];
        this.filteredBeatData = [...result];
    }  catch (error) {
            this.showToast('Error', 'Error fetching Beats', 'error');
        }
    }

    // Expose method to be called on refresh
    async handleRefresh() {
        await this.fetchBeats();
    }

    // This will be automatically called by Salesforce in Spring '24+ when pull-down refresh is used
    async refresh() {
        await this.handleRefresh();
    }

    //Connectd callback to get all beats
    /*connectedCallback() {      
        getAllBeats()
            .then(result => {
                this.beatData = result;
                this.filteredBeatData = result;
            })
            .catch(error => {
                this.showToast('Error', 'Error fetching Beats', 'error');
                /*console.error('Error fetching Beats:', error);*/
      /*      });
    }*/

    // Date selection on which Visit & Visit Task to be created
   /* handleFromDateChange(event) {
        this.fromDate = event.target.value;
    }*/

        handleFromDateChange(event) {
            const selectedDate = new Date(event.target.value);
            const today = new Date();
            
            // Set the time of today to 00:00 to only compare the date part
            today.setHours(0, 0, 0, 0);
        
            // Compare the selected date with today's date
            if (selectedDate < today) {
                // Show error toast if the selected date is less than today
                this.showToast('Error', 'You can not select the past date.', 'error');
                this.fromDate = ''; 
                // Also, clear the input element value manually with 2 sec delay
                setTimeout(() => {
                    const dateInput = this.template.querySelector('lightning-input');
                    if (dateInput) {
                        dateInput.value = ''; // Reset the input field's value
                    }
                }, 2000); 
            } else {
                this.fromDate = event.target.value; // Set the selected date if it's valid
            }
        }

    // Selection of beat 
    handleBeatSelection(event) {
    const selectedRows = event.detail.selectedRows;
        if (event.detail.selectedRows.length > 1) {
            this.showToast('Error', 'You can only select one Beat at a time.', 'error');
            this.template.querySelector('lightning-datatable').selectedRows = [];
            this.selectedBeat = '';
            this.selectedRows = []; 
        } else {
            this.selectedBeat = event.detail.selectedRows[0]?.Id;
            this.loadRetailers();
        }
    }
        /*handleBeatSelection(event) {
            const selected = event.detail.selectedRows;
            console.log('Selected Rows:', JSON.stringify(selected));
    
            if (selected.length > 0) {
                let lastSelected = selected[selected.length - 1];
                if (!lastSelected.id && !lastSelected.Id) {
                    return;
                }
    
                // Store the last selected row ID
                this.selectedBeat = [lastSelected.id || lastSelected.Id];
                console.log('Selected Row ID:', JSON.stringify(this.selectedBeat)); // Should print the selected ID
            } else {
                this.selectedBeat = [];
                console.log('No selection');
            }
        }*/

    // Load retailers in datatable
    loadRetailers() {
        if (this.selectedBeat) {
            console.log('this.selectedBeat:- ',this.selectedBeat);
            getRetailersByBeat({ beatId: this.selectedBeat })
                .then(result => {
                    console.log('result:- ',result);
                    this.retailerData = result;
                    this.filteredRetailerData = result;
                    this.selectedRetailers = result.map(row => row.Id); // Auto-select all

                })
                .catch(error => {
                    this.showToast('Error', 'Error fetching Retailers', 'error');
                    console.error('Error fetching Retailers:', error);
                });
        }
    }

    //Handle the row selections
    handleRowSelection(event) {
        this.selectedRetailers = this.filteredRetailerData.map(row => row.Id);
    }

    //Handle the Beat search by search key
    handleSearch(event) {
        const query = event.target.value.toLowerCase();
        this.filteredBeatData = this.beatData.filter(beat =>
            beat.Name.toLowerCase().includes(query)
        );
    }

    // Search retailer with search key
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

    // Handle Back Icon action
    handleBackIconClick(){
            this.showOptions = true;
            this.showBeatsTable = true;
            this.showRetailerTable = false;
            //this.selectedRetailers = []
            this.selectedBeat = '';
            this.selectedRows = []; 

    }

    //Handle Back button
    handleBack(){
                window.history.back();
            }

    //Handle Next button
    handleNext() {
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

    // Create the Visit & Visit task for selected Date, Beat & Retailers...
    //Here we are redirecting to My Visit Tab on Mobile
    createVisits() {
    this.isButtonDisabled = true;

    if (!this.fromDate || this.selectedRetailers.length === 0) {
        this.showToast('Error', 'Please select a date and at least one retailer.', 'error');
        this.isButtonDisabled = false;
        return;
    }

    createVisitsApex({ 
        retailerIds: this.selectedRetailers, 
        visitDate: this.fromDate, 
        beatId: this.selectedBeat 
    })
    .then(() => {
        this.showToast('Success', 'Visit & Visit Task are created successfully!', 'success');
        this.showOptions = true;
        this.showBeatsTable = true;
        this.showRetailerTable = false;
        this.resetComponent();

        // Navigate after short delay to let the toast show
        setTimeout(() => {
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: {
                    apiName: 'My_Visit_Tasks'
                }
            });
        }, 100); // Optional delay to show the toast
    })
    .catch(error => {
        if (error.body.message.includes('A visit already exists')) {
            this.showToast('Error', 'A visit already exists for the selected date.', 'error');
        } else {
            this.showToast('Error', 'Error creating visits', 'error');
        }
        this.isButtonDisabled = false;
    });
}

    // Create the Visit & Visit task for selected Date, Beat & Retailers...
    //Here we are redirecting to same page
    createVisitsAndNew(){
        this.isButtonDisabled = true;
        if (!this.fromDate || this.selectedRetailers.length === 0) {
            this.showToast('Error', 'Please select a date and at least one retailer.', 'error');
            this.isButtonDisabled = false;
            return;
        }
        //calling apex
        createVisitsApex({ 
            retailerIds: this.selectedRetailers, 
            visitDate: this.fromDate, 
            beatId: this.selectedBeat 
        })
            .then(() => {
                this.showToast('Success', 'Visit & Visit Task are created successfully!', 'success');
                this.showOptions = true;
                this.showBeatsTable = true;
                this.showRetailerTable = false;
                this.resetComponent();
            })
            .catch(error => {
                if (error.body.message.includes('A visit already exists')) {
                    this.showToast('Error', 'A visit already exists for the selected date.', 'error');
                } else {
                this.showToast('Error', 'Error creating visits', 'error');
                }
                /*console.error('Error creating visits:', error);*/
                this.isButtonDisabled = false;
            });
    }
    //Reset the component
    resetComponent() {
        this.fromDate = '';
        this.selectedBeat = '';
        this.selectedRetailers = [];
        this.showOptions = true;
        this.showBeatsTable = true;
        this.showRetailerTable = false;
        this.filteredBeatData = this.beatData;
        this.filteredRetailerData = [];
         this.isButtonDisabled = false;
        this.selectedRows = []; 
    }

    // Show toast message
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title,
            message,
            variant,
        });
        this.dispatchEvent(evt);
    }

    // Prevent checkbox selection changes
preventRowSelection(row) {
    return false; // This disables user interaction with checkboxes
}
}