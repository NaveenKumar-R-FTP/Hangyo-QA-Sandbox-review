import { LightningElement, track } from 'lwc';
import getRetailers from '@salesforce/apex/CreateNewVisitTaskContoller.getRetailers';
import getLatestVisit from '@salesforce/apex/CreateNewVisitTaskContoller.getLatestVisit';
import createVisitAndTasks from '@salesforce/apex/CreateNewVisitTaskContoller.createVisitAndTasks';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class CreateNewVisits extends NavigationMixin(LightningElement) {
    @track searchKey = '';
    @track retailers = [];
    @track selectedRetailers = [];
    @track showCreateVisitForm = true;
    @track isLoading = false;
    @track isButtonDisabled = false;
    @track latestVisit = null;
    // added by fuzail - Track selected type (Retailer or Distributor)
    @track selectedType = 'Retailer';

    // added by fuzail - Options for the type dropdown filter
    typeOptions = [
        { label: 'Retailer', value: 'Retailer' },
        { label: 'Distributor', value: 'Distributor' }
    ];

    @track columns = [
        { label: 'Retailer Name', fieldName: 'name' },
        { label: 'Beat Name', fieldName: 'beatName' }
    ];

    // added by fuzail - Dynamic search label based on selected type
    get searchLabel() {
        return this.selectedType === 'Distributor' 
            ? 'Distributor Name' 
            : 'Retailer Name/Beat Names';
    }

    // added by fuzail - Dynamic table title based on selected type
    get tableTitle() {
        return this.selectedType === 'Distributor' 
            ? 'Select one Distributor' 
            : 'Select one Retailer';
    }

    connectedCallback() {
        this.fetchLatestVisit();
        // added by fuzail - Initialize columns based on default type
        this.updateColumns();
        this.fetchRetailers();
    }

    // renderedCallback() {
    //     this.fetchLatestVisit();
    //     //this.fetchRetailers();
    // }

    fetchLatestVisit() {
        this.isLoading = true;
        getLatestVisit()
            .then((result) => {
                this.isLoading = false;
                if (result) {
                    this.latestVisit = result;
                } else {
                    this.showCreateVisitForm = true;
                }
            })
            .catch((error) => {
                this.isLoading = false;
                this.showToast('Error', 'There was an error fetching the latest visit.', 'error');
            });
    }

    // added by fuzail - Handle type filter change (Retailer/Distributor)
    handleTypeChange(event) {
        this.selectedType = event.detail.value;
        this.searchKey = '';
        this.selectedRetailers = [];
        this.updateColumns();
        this.fetchRetailers();
    }

    // added by fuzail - Update columns dynamically: hide Beat Name for Distributor
    updateColumns() {
        if (this.selectedType === 'Distributor') {
            this.columns = [
                { label: 'Distributor Name', fieldName: 'name' }
            ];
        } else {
            this.columns = [
                { label: 'Retailer Name', fieldName: 'name' },
                { label: 'Beat Name', fieldName: 'beatName' }
            ];
        }
    }

    handleRetailerNameBeatNameChange(event) {
        this.searchKey = event.target.value;
        this.fetchRetailers();
    }

    handleRowSelection(event) {
        const selected = event.detail.selectedRows;
        if (selected.length > 0) {
            const lastSelected = selected[selected.length - 1];
            this.selectedRetailers = [lastSelected.id || lastSelected.Id];
        } else {
            this.selectedRetailers = [];
        }
    }

    fetchRetailers() {
        this.isLoading = true;
        // added by fuzail - Pass recordTypeName to fetch Retailers or Distributors
        getRetailers({ searchKey: this.searchKey, recordTypeName: this.selectedType })
            .then(result => {
                this.isLoading = false;
                this.retailers = result.map(record => ({
                    id: record.Id,
                    name: record.Name,
                    beatName: record.Beats_Name__r ? record.Beats_Name__r.Name : 'No Beat'
                }));
            })
            .catch(error => {
                this.isLoading = false;
                // added by fuzail - Context-aware error messages
                const errorMessage = this.selectedType === 'Distributor' 
                    ? 'Error fetching distributors' 
                    : 'Error fetching retailers';
                this.showToast('Error', errorMessage, 'error');
            });
    }

    handleSave() {
        this.isButtonDisabled = true;

        if (this.selectedRetailers.length === 0) {
            // added by fuzail - Context-aware validation message
            const errorMessage = this.selectedType === 'Distributor' 
                ? 'Please select at least one distributor.' 
                : 'Please select at least one retailer.';
            this.showToast('Error', errorMessage, 'error');
            this.isButtonDisabled = false;
            return;
        }

        createVisitAndTasks({ retailerIds: this.selectedRetailers })
            .then(() => {
                this.showToast('Success', 'Visit and Visit Tasks created successfully.', 'success');
                
                setTimeout(() => {
                    this[NavigationMixin.Navigate]({
                        type: 'standard__navItemPage',
                        attributes: { apiName: 'My_Visit_Tasks' },   
                    });
                    window.location.reload();
                }, 100);
            })
            .catch((error) => {
                this.showToast('Error', error.body.message, 'error');
                this.isButtonDisabled = false;
            });
    }

    handleBackIconClick() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'My_Visit_Tasks' }
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }
}