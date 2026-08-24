import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation'; 
import getInvoiceStatus from '@salesforce/apex/CollectionsController.getInvoiceStatus';
import saveInvoiceCollection from '@salesforce/apex/CollectionsController.saveInvoiceCollection';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class InvoiceCollection extends NavigationMixin(LightningElement) {
    @track recordId; // Record ID fetched from the URL
    @track showError = false; // Controls the error popup
    @track showComponent = false; // Controls visibility of the main component
    @track invoices = {};
    @track formattedDate;
    errorMessage = ''; // Stores the error message dynamically
     @track paymentMethodOptions = [];

allPaymentMethods = [
    { label: 'Cash', value: 'Cash' },
    { label: 'Online', value: 'Online' },
    { label: 'Cheque', value: 'Cheque' },
    { label: 'Credit Only', value: 'Credit Only' }
];
    @track selectedPaymentMethod = '';
    @track paymentDate = new Date().toISOString().split('T')[0]; // Set default to today
    @track isCheque = false;
    @track creditNotes = [];
    @track isCreditUse = false;
    @track isAmountEntered = true;
    @track narration = '';
    @track amountCollected = 0.0;
    @track creditAmountEntered = 0.0;
    @track totalCreditAmount = '';
    @track totalCreditNotes = '';
    @track payableBalance = '';
    @track isAmountDisabled = false;
    @track chequeDetails = {
        chequeNumber: '',
        chequeDate: new Date().toISOString().split('T')[0],
        branchName: '',
        isChequeCleared: false
    };

    
    //Added by Ajay for condition rendering the retailer or underr SS name
    get isSecondaryInvoiceUnderSS() {
        return this.invoices?.RecordType?.DeveloperName === 'Secondary_Invoice_Under_SS';
    }
       //Dynamic payment method change -Ajay
updatePaymentOptions(excludeCreditOnly) {
    if (excludeCreditOnly) {
        this.paymentMethodOptions = this.allPaymentMethods.filter(option => option.value !== 'Credit Only');
    } else {
        this.paymentMethodOptions = [...this.allPaymentMethods];
    }
}
    get totalCollectionAmount() {
        const total = this.isCreditUse 
            ? Number(this.amountCollected) + Number(this.creditAmountEntered) 
            : Number(this.amountCollected);
        return total.toFixed(2);
    }
    get isCreditboxDisabled() { 
        console.log('this.totalPayableBalance***',this.totalPayableBalance);
        // Disable the checkbox if totalPayableBalance is 0
        /*if (Number(this.payableBalance) === 0) {
            this.isCreditUse = false; // Uncheck the checkbox
            return true; // Disable the checkbox
        }*/
        if(Number(this.totalCreditAmount) === 0){
            this.isCreditUse = false;
            
            return true;
        }
        return false;
    }

     // Function to format date as DD-MM-YYYY
     formatDate(dateString) {
        if (!dateString) return ''; // Handle empty date
        let dateObj = new Date(dateString);
        let day = String(dateObj.getDate()).padStart(2, '0'); // Ensure two-digit day
        let month = dateObj.toLocaleString('default', { month: 'short' }); // Month in words (e.g., Jan, Feb)

        let year = dateObj.getFullYear();
        return `${day}-${month}-${year}`;
    }

    connectedCallback() {
        const queryParams = new URLSearchParams(window.location.search);
        this.recordId = queryParams.get('recordId');

        // If a recordId is found, fetch its status
        if (this.recordId) {
            this.fetchInvoiceData();
        } else {
            this.showErrorPopup('No record ID provided in the URL.');
        }
    }

    fetchInvoiceData() {
        getInvoiceStatus({ invoiceId: this.recordId })
        .then((data) => {
            console.log('Fetched invoice data:', data);
            if (data && data.Status__c === 'Delivered' && data.Total_Payable_Balance__c!= 0) {
                const isUnderSS = data?.RecordType?.DeveloperName === 'Secondary_Invoice_Under_SS';
                this.showComponent = true;
                this.invoices = data;
                this.formattedDate = this.formatDate(data.Invoice_Date__c);
                this.updatePaymentOptions(true);
                if (isUnderSS) {
                    // --- Logic for Secondary_Invoice_Under_SS ---
                    this.totalCreditAmount = data?.Under_SS__r?.Total_Credit_Amount__c || 0;
                    this.totalCreditNotes = data?.Under_SS__r?.Total_Available_Credit_Notes__c || 0;
                    console.log('this.totalCreditAmount 2', this.totalCreditAmount);
                } else { 
              this.totalCreditAmount = data?.Retailer_Account__r?.Total_Credit_Amount__c || 0;
                this.totalCreditNotes = data?.Retailer_Account__r?.Total_Available_Credit_Notes__c || 0;
                console.log('this.invoices',this.invoices);
            }
        }else if(data && data.Total_Payable_Balance__c === 0){
                const successEvent = new ShowToastEvent({
                    title: 'Error',
                    message: `Payable balance is 0, no outstanding amount left to be collected.`,
                    variant: 'Error',
                });
                this.dispatchEvent(successEvent);

                

                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: this.recordId,
                        objectApiName: 'Invoice__c', // Object API Name
                        actionName: 'view'
                    }
                });
            } else {
                const successEvent = new ShowToastEvent({
                    title: 'Error',
                    message: `Collection can be raised for delivered invoices only.`,
                    variant: 'Error',
                });
                this.dispatchEvent(successEvent);

                

                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: this.recordId,
                        objectApiName: 'Invoice__c', // Object API Name
                        actionName: 'view'
                    }
                });
            }
        })
        .catch((error) => {
            console.error('Error fetching invoice status:', error);
            
        });
    }
    handleCreditAmountEntered(event){ 
        let enteredAmount = event.target.value;
        if (parseFloat(enteredAmount) > parseFloat(this.invoices.Total_Payable_Balance__c)) {
            //enteredAmount = this.invoices.Total_Payable_Balance__c; // Set it to invoices.Total_Payable_Balance__c amount if greater
            enteredAmount = 0.0;
            const toastEvent = new ShowToastEvent({
                title: 'Invalid Credit Amount',
                message: `Entered credit amount is greater than the total payable balance.`,
                variant: 'error',
            });
            this.dispatchEvent(toastEvent); // Show an error toast message
        }
        if (parseFloat(enteredAmount) > parseFloat(this.totalCreditAmount)) {
            //enteredAmount = this.totalCreditAmount; // Set it to credit amount if greater
            enteredAmount = 0.0;
            const toastEvent = new ShowToastEvent({
                title: 'Invalid Credit Amount',
                message: `Entered credit amount is greater than the available credit amount.`,
                variant: 'error',
            });
            this.dispatchEvent(toastEvent); // Show an error toast message
        }
        this.creditAmountEntered = enteredAmount;
        const invoiceAmount = parseFloat(this.invoices.Total_Payable_Balance__c) || 0;
        const collectedAmount = parseFloat(this.amountCollected) || 0;
        const credAmt = parseFloat(this.creditAmountEntered) || 0;
        const totalcollection = collectedAmount + credAmt;
        this.payableBalance = (invoiceAmount - totalcollection).toFixed(2); 
       // this.payableBalance = invoiceAmount - enteredAmount; 
    }
    handleAmountChange(event) {
            let enteredAmount = event.target.value;
            // Ensure amount collected is not greater than invoice amount
            if (parseFloat(enteredAmount) > parseFloat(this.invoices.Total_Payable_Balance__c)) {
                enteredAmount =0.0; // Set it to invoice amount if greater
                const toastEvent = new ShowToastEvent({
                    title: 'Invalid Amount',
                    message: `Amount collected cannot exceed the invoice amount of ${this.invoices.Total_Payable_Balance__c}.`,
                    variant: 'error',
                });
                this.dispatchEvent(toastEvent); // Show an error toast message
            }
            
            // Update amountCollected
            this.amountCollected = enteredAmount;
            const invoiceAmount = parseFloat(this.invoices.Total_Payable_Balance__c) || 0;
            const collectedAmount = parseFloat(this.amountCollected) || 0;
            const credAmt = parseFloat(this.creditAmountEntered) || 0;
            const totalcollection = collectedAmount + credAmt;
            this.payableBalance = (invoiceAmount - totalcollection).toFixed(2); 
        
            
    }

    handlePaymentMethodChange(event) {
            this.selectedPaymentMethod = event.target.value;
            this.isCheque = this.selectedPaymentMethod === 'Cheque';
               const invoiceAmount = parseFloat(this.invoices.Total_Payable_Balance__c) || 0;
            const collectedAmount = parseFloat(this.amountCollected) || 0;
            const credAmt = parseFloat(this.creditAmountEntered) || 0;
           // const totalcollection = collectedAmount + credAmt;         
            console.log('Selected Payment Method:', this.selectedPaymentMethod);
            if(this.selectedPaymentMethod === 'Credit Only'){
            this.amountCollected = 0.0;
            this.isAmountDisabled = true;
            this.payableBalance = (invoiceAmount - credAmt).toFixed(2); 

        }
        else if(this.selectedPaymentMethod !== 'Credit Only'){
        this.isAmountDisabled = false;
        }
        }
    
    handleInputChange(event) {
        const field = event.target.dataset.field;
        this.chequeDetails[field] = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
    }
    handlePaymentDateChange(event) {
        this.paymentDate = event.target.value;
        console.log('Selected Payment Date:', this.paymentDate);
    }
    handleNarrationChange(event){
        this.narration = event.target.value;
        console.log('narration value:- ',this.narration);
    }
    handleCreditUse(event) {
            this.isCreditUse = event.target.checked;
            this.amountCollected = 0.0;
            if(this.isCreditUse == true){
                this.isAmountEntered = false;
                this.updatePaymentOptions(false); // Include all
               
                if((this.invoices.Total_Payable_Balance__c > this.totalCreditAmount) && this.totalCreditAmount!=0){
                    this.creditAmountEntered = this.totalCreditAmount;
                    this.amountCollected = Number((this.invoices.Total_Payable_Balance__c - this.totalCreditAmount).toFixed(2));
                }else if((this.invoices.Total_Payable_Balance__c < this.totalCreditAmount) && this.totalCreditAmount!=0){
                    this.creditAmountEntered = this.invoices.Total_Payable_Balance__c;
                    this.amountCollected = 0.0;
                }else if(this.totalCreditAmount == 0){
                    this.amountCollected = this.invoices.Total_Payable_Balance__c;
                }
            }else{
                this.isAmountEntered = true;
                this.creditAmountEntered = 0.0;
                const invoiceAmount = parseFloat(this.invoices.Total_Payable_Balance__c) || 0;
                const collectedAmount = parseFloat(this.amountCollected) || 0;
                const credAmt = parseFloat(this.creditAmountEntered) || 0;
                const totalcollection = collectedAmount + credAmt;
                this.payableBalance = (invoiceAmount - totalcollection).toFixed(2);  
                //this.payableBalance = this.amountCollected || 0 ;
            }
            
        }
    showErrorPopup(message) {
        this.showError = true;
        this.errorMessage = message;
    }
    // Handle saving the collection
    handleSaveCollection() {
        if (this.recordId) {
            console.log('selectedPaymentMethod sup',this.selectedPaymentMethod);
            console.log('paymentDate',this.paymentDate);
            console.log('totalCreditsUsable',this.totalCreditsUsable);
            /*if(this.selectedPaymentMethod == '' || this.amountCollected == '' || this.paymentDate == ''){
                this.showToast('Error', 'Please fill in payment method, payment date and amount collected.', 'error');
                return;
            }*/
           if(this.selectedPaymentMethod != '' && this.selectedPaymentMethod != 'Credit Only' && this.amountCollected == ''){
            this.showToast('Error', 'Please fill in the payment date and amount collected.', 'error');
            return;
           }
           if(this.amountCollected == 0 && this.totalCollectionAmount == 0){
            this.showToast('Error', 'Amount collected or Credit Amount must be greater than 0.', 'error');
            return;
           }
           if(this.selectedPaymentMethod == '' && this.amountCollected != ''){
            this.showToast('Error', 'Please fill in the payment method.', 'error');
            return;
           }
            if(this.selectedPaymentMethod == 'Cheque'){
                console.log('this.chequeDetails.chequeNumber',this.chequeDetails.chequeNumber);
                console.log('this.chequeDetails.chequeDate',this.chequeDetails.chequeDate);
                console.log('this.chequeDetails.branchName',this.chequeDetails.branchName);
                if (!this.chequeDetails.chequeNumber || !this.chequeDetails.chequeDate || !this.chequeDetails.branchName) {
                    this.showToast('Error', 'Please fill in cheque number,cheque date and branch name.', 'error');
                    return;
                }
            }
             if(this.totalCollectionAmount >this.invoices.Total_Payable_Balance__c ){
                this.showToast('Error', 'Total collection cannot exceed the current outstanding amount.', 'error');
            return;
}
     if(this.selectedPaymentMethod != 'Credit Only' &&  this.amountCollected == 0.0){
         this.showToast(
        'Error',
        `Amount collected cannot be 0 when payment method is ${this.selectedPaymentMethod}`,
        'error'
    );

     }
            console.log('this.recordId',this.recordId);
            console.log('this.amountCollected',this.amountCollected);
            console.log('this.payableBalance',this.payableBalance);
            console.log('this.selectedRetailer',this.invoices.Retailer_Account__c);
            console.log('this.totalCreditsUsable',this.totalCreditsUsable);
            console.log('this.creditAmountEntered',this.creditAmountEntered);
            
            saveInvoiceCollection({
                invoiceId: this.recordId,
                amountCollected: this.amountCollected,
                payableBalance: this.payableBalance,
                selectedRetailer: this.invoices.RecordType.DeveloperName === 'Secondary_Invoice_Under_SS'
                    ? this.invoices.Under_SS__c
                    : this.invoices.Retailer_Account__c,
                paymentMethod: this.selectedPaymentMethod,
                paymentDate: this.paymentDate,
                creditAmountToBeUsed: this.creditAmountEntered,
                chequeData: this.chequeDetails,
                narrationData:this.narration
            })
                .then(() => {
                    // Show success message
                    const successEvent = new ShowToastEvent({
                        title: 'Success',
                        message: `Collection have been recorded.`,
                        variant: 'success',
                    });
                    this.dispatchEvent(successEvent);
                    this[NavigationMixin.Navigate]({
                        type: 'standard__recordPage',
                        attributes: {
                            recordId: this.recordId,
                            objectApiName: 'Invoice__c', // Object API Name
                            actionName: 'view'
                        }
                    });
                })
                .catch((error) => {
                    // Show error message
                    const errorEvent = new ShowToastEvent({
                        title: 'Error',
                        message: error.body.message || 'An error occurred while saving the collection.',
                        variant: 'error',
                    });
                    this.dispatchEvent(errorEvent);
                });
        } else {
            const errorEvent = new ShowToastEvent({
                title: 'Error',
                message: 'Please select at least one invoice.',
                variant: 'error',
            });
            this.dispatchEvent(errorEvent);
        }
    }
    handleClose() {
        this.showError = false;
        window.history.back(); // Navigate back to the previous page
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}