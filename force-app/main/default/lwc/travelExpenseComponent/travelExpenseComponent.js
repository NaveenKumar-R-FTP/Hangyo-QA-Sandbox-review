import { LightningElement, wire, api,track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getUserRoleAndEntitlements from '@salesforce/apex/ExpenseController.getUserRoleAndEntitlements';
import saveExpense from '@salesforce/apex/ExpenseController.saveExpense';
import validateExpense from '@salesforce/apex/ExpenseController.validateExpense';

import getClassACities from '@salesforce/apex/ExpenseController.getClassACities';
import { NavigationMixin } from 'lightning/navigation';
 
export default class ExpenseForm extends NavigationMixin(LightningElement) {
    @api recordId;
    @api createdRecordId;
    @track fileName = '';
    @track isFileUploaded = false;
    @track isButtonDisabled = false;    
    @track isLoading = false;
    @track entitlementMap = {};


    @track showWarningModal = false;
@track warningMessage = '';
pendingExpenseData = null;
// List of user role
    userRoleOptions = [
        { label: 'SO', value: 'SO' },
        { label: 'SSO', value: 'SSO' },
        { label: 'ASM', value: 'ASM' },
        { label: 'RSM', value: 'RSM' },
        { label: 'ZSM', value: 'ZSM' }
    ];
   // @track expenseTypeOptions = [
     //   { label: 'Travel', value: 'Travel_Expense_Request' },
        //{ label: 'Accommodation', value: 'Accommodation Request' },
  //      { label: 'Miscellaneous', value: 'Miscellaneous Request' }
   // ];
    accommodationTypeOptions = [
        { label: 'Class A cities', value: 'Class A cities' },
        { label: 'Other Cities', value: 'Other Cities' }
    ];
 
    @track userRole = '';
    @track expenseType = '';
    @track transportType = '';
    @track accommodationType = '';
    @track classACity = '';
    @track otherCity = '';
    @track miscExpenseDetails = '';
    @track amount = 0;
    @track bikeRun = 0;
    @track expenseDate = '';
    @track errorMessage = '';
    @track showError = false;
    @track transportTypeOptions = [];

 
    acceptedFormats = ['.pdf', '.png', '.jpg', '.jpeg', '.docx', '.xlsx'];
    uploadedFileIds = [];
    showFileUpload = false;
     today = new Date().toISOString().split('T')[0]; // Used for max attribute

    classACityOptions = [];
 
    // Modified getter to exclude Miscellaneous Request for Transport Type visibility
    get isTransportTypeVisible() {
        return this.expenseType !== 'Miscellaneous Request' && ['Travel_Expense_Request', 'Miscellaneous Request'].includes(this.expenseType);
    }
 
    // New getter to check if Expense Type is Miscellaneous Request
    get isMiscellaneousRequest() {
        return this.expenseType === 'Miscellaneous Request';
    }
    // New getter to check if Expense Type is Accommodation Request
    get isAccommodationRequest() {
        return this.expenseType === 'Accommodation Request';
    }
    // New getter to check if accommodation Type is Class A cities
    get isClassACitiesSelected() {
            return this.expenseType === 'Accommodation Request' && this.accommodationType === 'Class A cities';

    }
    // New getter to check if accommodation Type is Other cities
    get isOtherCitiesSelected() {
         return this.expenseType === 'Accommodation Request' && this.accommodationType === 'Other Cities';

    }
    // New getter to check if Bike Or Car is Selected
    get isBikeCarSelected() {
        return (
            this.expenseType === 'Travel_Expense_Request' &&
            ['Bike', 'Car'].includes(this.transportType)
        );
    }

@track expenseTypeOptions = [];

@wire(getUserRoleAndEntitlements)
wiredEntitlements({ error, data }) {
    if (data) {
        this.userRole = data.userRole;
 let options = [];
       

        if (data.bikeAllowanceAmount && data.bikeAllowanceAmount > 0) {
            options.push({ label: 'Bike', value: 'Bike' });
        }
        if (data.carAllowanceAmount && data.carAllowanceAmount > 0) {
            options.push({ label: 'Car', value: 'Car' });
        }
        if (data.flightAllowance) {
            options.push({ label: 'Flight', value: 'Flight' });
        }
        if (data.trainAllowanceAmount && data.trainAllowanceAmount > 0) {
            options.push({ label: 'Train', value: 'Train' });
        }
        if (data.busAllowanceAmount && data.busAllowanceAmount > 0) {
            options.push({ label: 'Bus', value: 'Bus' });
        }
        
        this.transportTypeOptions = [...options];

        // 🔁 Rebuild expenseTypeOptions dynamically
        this.expenseTypeOptions = [
            { label: 'Travel', value: 'Travel_Expense_Request' },
            { label: 'Miscellaneous', value: 'Miscellaneous Request' }
        ];

        if (
            (data.classACitiesAmount && data.classACitiesAmount > 0) &&
            (data.otherCitiesAmount && data.otherCitiesAmount > 0)
        ) {
            this.expenseTypeOptions.splice(1, 0, { label: 'Accommodation', value: 'Accommodation Request' }); // insert in middle
        }

      

    }  else if (error) {
    this.isButtonDisabled = true;
    let errorMessage = 'Unexpected error occurred. Please try again later.';
    
    if (error && error.body && error.body.message) {
        errorMessage = error.body.message;

        // Optional: Customize based on error keywords
        if (errorMessage.includes('No entitlement assigned')) {
            errorMessage = 'No entitlement assigned for your role. Please contact the administrator.';
        } else if (errorMessage.includes('No approver assigned')) {
            errorMessage = 'No approver assigned to your role. Please contact the administrator.';
        }
    }

    this.showToast('Error', errorMessage, 'error');
    console.error(JSON.stringify(error));
}
}



    // Check the User roll & assign the thing accordingly
  /*  @wire(getUserRole)
    userRoleHandler({ data, error }) {
        if (data) {
            this.userRole = data;
            if (this.userRole !== 'SO') {
                this.expenseTypeOptions = [
                    { label: 'Travel', value: 'Travel_Expense_Request' },
                    { label: 'Accommodation', value: 'Accommodation Request' },
                    { label: 'Miscellaneous', value: 'Miscellaneous Request' }
                ];
            }
            // Update transport type options based on user role
            if (['SO', 'SSO', 'ASM'].includes(this.userRole)) {
                this.transportTypeOptions = [
                    { label: 'Bus', value: 'Bus' },
                    { label: 'Train', value: 'Train' },
                    { label: 'Bike', value: 'Bike' }
                ];
            } else if (['RSM', 'ZSM'].includes(this.userRole)) {
                this.transportTypeOptions = [
                    { label: 'Bus', value: 'Bus' },
                    { label: 'Train', value: 'Train' },
                    { label: 'Car', value: 'Car' },
                    { label: 'Flight', value: 'Flight' }
                ];
            }
        } else if (error) {
            this.showToast('Error', 'Error fetching user role.', 'error');
        }
    }*/
   // Gte list of class A cities
    @wire(getClassACities)
    classACityHandler({ data, error }) {
        if (data) {
            this.classACityOptions = data.map(option => ({
                label: option.label,
                value: option.value
            }));
        } else if (error) {
            this.showToast('Error', 'Error fetching Class A cities.', 'error');
        }
    }

    //Handle expense type input event
    handleExpenseTypeChange(event) {
        this.expenseType = event.detail.value;
        this.showFileUpload = true;
        this.transportType = '';
        this.amount = 0;
        this.bikeRun = 0;
        this.classACity = '';
        this.otherCity = '';
        this.miscExpenseDetails='';

    }
   //Handle Accommodation type input event
   handleAccommodationTypeChange(event) {
    this.accommodationType = event.detail.value;
    this.classACity = '';
    this.otherCity = '';
    if (this.isClassACitiesSelected) {
        // Re-fetch Class A cities when "Class A cities" is selected
        getClassACities()
            .then(data => {
                this.classACityOptions = data.map(option => ({
                    label: option.label,
                    value: option.value
                }));
            })
            .catch(error => {
                this.showToast('Error', 'Error fetching Class A cities.', 'error');
            });
    } else {
        // Clear Class A city options if "Other Cities" is selected
        this.classACityOptions = [];
    }
}
   //Handle Class A City input event
    handleClassACityChange(event) {
        this.classACity = event.detail.value;
    }
   //Handle Other City input event
    handleOtherCityChange(event) {
        this.otherCity = event.detail.value;
    }
   //Handle Expense details input event
    handlemiscExpenseDetailsChange(event){
        this.miscExpenseDetails = event.detail.value;
    }
   //Handle transport Type input event
    handleTransportTypeChange(event) {
        this.transportType = event.detail.value;
        this.amount = 0;
        this.bikeRun = 0;
    }
   //Handle Bike Or Car run input event
    handleBikeCarRunChange(event){
        this.bikeRun = parseFloat(event.detail.value) || 0;
    }
      //Handle Amount input event
    handleAmountChange(event) {
        this.amount = parseFloat(event.detail.value) || 0;
        
       /* const amountField = this.template.querySelector("[data-id='amountField']");
        amountField.setCustomValidity('');
 
        console.log('expenseType =' +this.expenseType);
        console.log('userRole =' +this.userRole);
        console.log('accommodationType =' +this.accommodationType);
        console.log('amount =' +this.amount);
        console.log('otherCity =' +this.otherCity);    
 
 
        if (
            this.expenseType === 'Travel_Expense_Request' &&
            ['Bus', 'Train'].includes(this.transportType) &&
            this.amount > 1500
        ) {
            amountField.setCustomValidity('Maximum 1500 rupees allowed for Bus/Train travel.');
        } else if(
            ['SSO', 'ASM'].includes(this.userRole) &&
            this.expenseType === 'Accommodation Request' &&
            this.accommodationType === 'Class A cities' &&
            this.amount > 1500
        ) {
            amountField.setCustomValidity('Maximum 1500 rupees allowed for Accommodation.');
        } else if(
            ['RSM'].includes(this.userRole) &&
            this.expenseType === 'Accommodation Request' &&
            this.accommodationType === 'Class A cities' &&
            this.amount > 2500
        ) {
            amountField.setCustomValidity('Maximum 2500 rupees allowed for Accommodation.');
        } else if(
            ['ZSM'].includes(this.userRole) &&
            this.expenseType === 'Accommodation Request' &&
            this.accommodationType === 'Class A cities' &&
            this.amount > 4000
        ) {
            amountField.setCustomValidity('Maximum 4000 rupees allowed for Accommodation.');
        } else  if(
            ['SSO', 'ASM'].includes(this.userRole) &&
            this.expenseType === 'Accommodation Request' &&
            this.accommodationType === 'Other Cities' &&
            this.amount > 1200
        ) {
            amountField.setCustomValidity('Maximum 1200 rupees allowed for Accommodation.');
        } else if(
            ['RSM'].includes(this.userRole) &&
            this.expenseType === 'Accommodation Request' &&
            this.accommodationType === 'Other Cities' &&
            this.amount > 2000
        ) {
            amountField.setCustomValidity('Maximum 2000 rupees allowed for Accommodation.');
        } else if(
            ['ZSM'].includes(this.userRole) &&
            this.expenseType === 'Accommodation Request' &&
            this.accommodationType === 'Other Cities' &&
            this.amount > 3000
        ) {
            amountField.setCustomValidity('Maximum 3000 rupees allowed for Accommodation.');
        }        
        amountField.reportValidity();*/
    }    
 
  handleExpenseDateChange(event) {
    this.expenseDate = event.detail.value;
    const today = new Date().toISOString().split('T')[0];

    if (this.expenseDate > today) {
        this.showError = true;
        this.errorMessage = 'Expense Date cannot be a future date.';
    } else {
        this.showError = false;
        this.errorMessage = '';
    }
}
     // Handle file upload start (show the spinner and block operations)
     handleFileUploadStart(event) {
        this.isFileUploaded = false;  // Reset file uploaded state to false
    }
   
   //Handle uploadedFiles input event
    handleFileUploadFinished(event) {
        this.isLoading = true;
        const uploadedFiles = event.detail.files;
        if (uploadedFiles && uploadedFiles.length > 0) {
            this.fileName = uploadedFiles[0].name;
            this.uploadedFileIds = uploadedFiles.map(file => file.documentId);
            this.isFileUploaded = true;
            /*this.showToast('Success', 'File uploaded successfully', 'success');*/
        } else {
            this.showToast('Error', 'File upload failed', 'error');
        }        
    }
   
   //Handle uploadedFiles input event
    
   //Handle save expense record
   /* saveExpenseRecord() {
        saveExpense({
            userRole: this.userRole,
            expenseType: this.expenseType,
            transportType: this.transportType,
            accommodationType: this.accommodationType,
            classACity: this.classACity,
            otherCity: this.otherCity,
            miscExpenseDetails: this.miscExpenseDetails,
            amount: this.amount,
            bikeRun: this.bikeRun,
            expenseDate: this.expenseDate,
            uploadedFileIds: this.uploadedFileIds,
            recordId: this.recordId
        })
            .then(result => {
                this.createdRecordId = result;
                this.showToast('Success', 'Expense Created Successfully.', 'success');
                    // Navigate to the "My Expenses" list view
                this[NavigationMixin.Navigate]({
                    type: 'standard__objectPage',
                    attributes: {
                        objectApiName: 'Expense__c',
                        actionName: 'list'
                    },
                    state: {
                        filterName: 'My_Expenses' // Developer Name of the list view
                    }
                });
               
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            });
    }*/
 

  // Modified save process
    async validateAndSave() {

        this.showError = false;
        this.errorMessage = '';
 
        if (!this.expenseType) {
            this.showToast('Error', 'Expense Type is required.', 'error');
            return;
        }
 
        if (this.isTransportTypeVisible && !this.transportType) {
            this.showToast('Error', 'Transport Type is required.', 'error');
            return;
        }
 
        if (this.isAccommodationRequest && !this.accommodationType) {
            this.showToast('Error', 'Accommodation Type is required.', 'error');
            return;
        }
 
        if (this.isClassACitiesSelected && !this.classACity) {
            this.showToast('Error', 'Please select a Class A City.', 'error');
            return;
        }
 
        if (this.isOtherCitiesSelected && !this.otherCity) {
            this.showToast('Error', 'Please enter a city for Other Cities.', 'error');
            return;
        }
 
        if (this.isBikeCarSelected && this.bikeRun <= 0) {
            this.showToast('Error', 'Distance traveled (Km) should be greater than zero.', 'error');
            return;
        }
 
        if (!this.isBikeCarSelected && (!this.amount || this.amount <= 0) ) {
            this.showToast('Error', 'Amount should be greater than zero.', 'error');
            return;
        }
 
       
 
        if (!this.expenseDate) {
            this.showToast('Error', 'Expense Date is required.', 'error');
            return;
        }
       
        if (!this.isFileUploaded) {
            this.showToast('Error', 'Please upload a valid file first.', 'error');
            return;
        }
 
        

        // Gather data for validation
        const validationData = {
            userRole: this.userRole,
            expenseType: this.expenseType,
            transportType: this.transportType,
            accommodationType: this.accommodationType,
            amount: this.amount,
            bikeRun: this.bikeRun
        };

        try {
        const result = await validateExpense(validationData);
        console.log('Validation result:', JSON.stringify(result));
if (result && result.errorMessage) {
   if (result.blockSave) {
        this.showToast('Error', result.errorMessage, 'error');
        return; // 🚫 prevent save
    } else {              
          this.warningMessage = result.errorMessage;
           this.showWarningModal = true;
            } 
            }else {
                // No warnings - proceed with save
                 await this.saveExpenseRecord();
            }
        } catch (error) {
            this.showToast('Error', error.body.message, 'error');
                console.error('Save Expense Error:', JSON.stringify(error));
        console.error('Error object:', error);
        }
    }

            // Save expense record with file upload (if any)
async saveExpenseRecord() {
    this.isButtonDisabled = true;
    this.showError = false;
    this.errorMessage = '';

    // Gather expense data
    const expenseData = {
        userRole: this.userRole,
        expenseType: this.expenseType,
        transportType: this.transportType,
        accommodationType: this.accommodationType,
        classACity: this.classACity,
        otherCity: this.otherCity,
        miscExpenseDetails: this.miscExpenseDetails,
        amount: this.amount,
        bikeRun: this.bikeRun,
        expenseDate: this.expenseDate,
        uploadedFileIds: this.uploadedFileIds,
        recordId: this.recordId
    };

    try {
                const result = await saveExpense(expenseData);

        if (result.errorMessage) {
            
            this.warningMessage = result.errorMessage;
            this.pendingExpenseData = expenseData;
            this.showWarningModal = true;
        } else {
            // No warning - proceed normally
            this.createdRecordId = result.expenseId;
            this.showToast('Success', 'Expense Created Successfully.', 'success');
            this.resetForm();
            this.navigateAfterSave();
        }
    } catch (error) {
        this.showToast('Error', error.body.message, 'error');
            console.error('Save Expense Error:', JSON.stringify(error));
        console.error('Error object:', error);
    } finally {
        this.isButtonDisabled = false;
    }
}

// Add modal handlers
async handleProceed() {
    
       await this.saveExpenseRecord();
    
    this.showWarningModal = false;
    this.showToast('Success', 'Expense submitted for approval!', 'success');
    this.resetForm();
    this.navigateAfterSave();
}

handleCancel() {
    this.showWarningModal = false;
    this.pendingExpenseData = null;
    this.warningMessage = '';
    // Optional: Re-enable form here if needed
}
  // Function to navigate after save
   navigateAfterSave() {        
        window.location.href = '/lightning/o/Expense__c/list?filterName=My_Expenses';
    }
    // Function to navigate after save
   /* navigateAfterSave() {        
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Expense__c',
                actionName: 'list'
            },
            state: {
                filterName: 'My_Expenses' // Developer Name of the list view
            }
        });
    }*/
 
//Reset the form
    resetForm() {
        this.expenseType = '';
        this.transportType = '';
        this.accommodationType = '';
        this.classACity = '';
        this.otherCity = '';
        this.miscExpenseDetails = '';
        this.amount = 0;
        this.bikeRun = 0;
        this.expenseDate = '';
        this.uploadedFileIds = [];
        this.showFileUpload = true;
        this.classACityOptions = [];
        this.fileName = '';
    }
// Show toast
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}