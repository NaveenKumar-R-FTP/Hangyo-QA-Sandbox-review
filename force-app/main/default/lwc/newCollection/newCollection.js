import { LightningElement, wire, track } from 'lwc';
import getRetailers from '@salesforce/apex/CollectionsController.getretailersOptions';
import getDeliveredInvoices from '@salesforce/apex/CollectionsController.getDeliveredInvoices';
import saveInvoiceCollection from '@salesforce/apex/CollectionsController.saveInvoiceCollection';
import validCreditNotes from '@salesforce/apex/CollectionsController.validCreditNotes';
import { NavigationMixin } from 'lightning/navigation'; 
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class NewCollection extends NavigationMixin(LightningElement) {
    @track retailerOptions = []; 
    @track filteredRetailerOptions = []; 
    @track searchTerm = '';
    @track showDropdown = false;
    @track searchKey = '';
    @track invoices = [];
    @track selectedRetailer = '';
    @track selectedRetailers = [];
    @track selectedRetailerId = ''; 
    @track selectedInvoiceIds = []; // Array to hold selected invoice IDs

    // Wrapper to store the invoice data for collection
    @track amountCollected = 0.0;
    @track creditAmountEntered = 0.0;
    @track totalCreditAmount = '';
    @track totalCreditNotes = '';
    @track isModalOpen = false; // To control modal visibility
    @track invoiceToUpdate = null;
   @track isAmountDisabled = false;
   @track paymentMethodOptions = [];

allPaymentMethods = [
    { label: 'Cash', value: 'Cash' },
    { label: 'Online', value: 'Online' },
    { label: 'Cheque', value: 'Cheque' },
    { label: 'Credit Only', value: 'Credit Only' }
];

    @track selectedPaymentMethod = '';
    @track selectedTotalPayableBalance = 0.0;
    @track paymentDate = new Date().toISOString().split('T')[0]; // Set default to today
    @track narration = '';
    @track isCheque = false;    
    @track creditNotes = [];
    @track isCreditUse = false;
    @track chequeDetails = {
        chequeNumber: '',
        chequeDate: new Date().toISOString().split('T')[0],
        branchName: '',
        isChequeCleared: false
    };

    retailerColumns = [
        { label: 'Customer Name', fieldName: 'label', type: 'text' },
        { label: 'Customer Phone', fieldName: 'phone', type: 'phone' },
        { label: 'Customer Type', fieldName: 'type', type: 'text' }         
        
    ];

    // Fetch retailers
    @wire(getRetailers)
    wiredRetailers({ error, data }) {
        if (data) {
            this.retailerOptions = data.map(retailer => ({
                label: retailer.Name,
                value: retailer.Id,
                phone: retailer.Owners_Number__c,
                type: retailer.RecordType.Name === 'Distributor' ? 'Under SS' : retailer.RecordType.Name
            }));
            console.log('Opt',JSON.stringify(this.retailerOptions));
            this.filteredRetailerOptions = this.retailerOptions;
        } else if (error) {
            console.error('Error fetching retailers:', error);
        }
    }

    //Dynamic payment method change -Ajay
updatePaymentOptions(excludeCreditOnly) {
    if (excludeCreditOnly) {
        this.paymentMethodOptions = this.allPaymentMethods.filter(option => option.value !== 'Credit Only');
    } else {
        this.paymentMethodOptions = [...this.allPaymentMethods];
    }
}
    //Search change 
    // Handle search input
    handleRetailerSearch(event) {
        this.searchKey = event.target.value.toLowerCase();
        this.filteredRetailerOptions = this.retailerOptions.filter(retailer =>
            retailer.label.toLowerCase().includes(this.searchKey)
        );
    }

    // Handle retailer selection in datatable
    handleRetailerSelection(event) {
        const selectedRows = event.detail.selectedRows;
        
        if (selectedRows.length > 0) {
            this.selectedRetailerId = selectedRows[0].value;  // Store the first selected retailer's Id
            this.selectedRetailer = selectedRows[0].label; // Store the name (optional)
            this.selectedRetailers = [this.selectedRetailerId]; 
            this.invoices = [];
        // Fetch delivered invoices for the selected retailer
        getDeliveredInvoices({ retailerId: this.selectedRetailerId}) 
            .then((data) => {
                if (data.length > 0) {
                   const isUnderSS = data[0]?.RecordType?.DeveloperName === 'Secondary_Invoice_Under_SS';
                    //to check the recordtype and depending on that which field to fetch will be determined added by Ajay
                    // Assign total credit amount from the first invoice's related Retailer_Account__r object
                    if (isUnderSS) {
                        // --- Logic for Secondary_Invoice_Under_SS ---
                        this.totalCreditAmount = data[0]?.Under_SS__r?.Total_Credit_Amount__c || 0;
                        this.totalCreditNotes = data[0]?.Under_SS__r?.Total_Available_Credit_Notes__c || 0;
                        console.log('this.totalCreditAmount 2', this.totalCreditAmount);
                    } else {
                    this.totalCreditAmount = data[0]?.Retailer_Account__r?.Total_Credit_Amount__c || 0;
                    this.totalCreditNotes = data[0]?.Retailer_Account__r?.Total_Available_Credit_Notes__c || 0;
                    console.log('this.totalCreditAmount 22',this.totalCreditAmount);
                } 
            }else {
                    this.totalCreditAmount = 0; // No data, reset to 0
                    this.totalCreditNotes = 0;
                    console.log('No Invoice');
                    this.invoices = [];
                    const toastEvent = new ShowToastEvent({
                        title: 'No Invoices',
                        message: `No delivered invoices for selected retailer: ${this.selectedRetailer}.`,
                        variant: 'error',
                    });
                    this.dispatchEvent(toastEvent);
                    return;
                }
                this.invoices = data.map((invoice) => ({
                    ...invoice,
                    amountCollected: '', // Initialize with empty value
                    formattedDate: this.formatDate(invoice.Invoice_Date__c)
                }));
                console.log('this.invoices',JSON.stringify(this.invoices));
            })
            .catch((error) => {
                console.error('Error fetching invoices:', error);
            });
        } else {
            this.selectedRetailerId = '';  // Reset if no selection
            this.selectedRetailer = '';
            this.selectedRetailers = [];
        }
    
        console.log('Selected Retailer ID:', this.selectedRetailerId);
        console.log('Selected Retailer Name:', this.selectedRetailer);
    }
    //End search

    get totalAmount() {
        return this.invoices.reduce((sum, invoice) => sum + parseFloat(invoice.Invoice_Amount__c || 0), 0).toFixed(2);
    }
    get totalCurrentOutstanding() {
        return this.invoices.reduce((sum, invoice) => sum + parseFloat(invoice.Total_Payable_Balance__c || 0), 0).toFixed(2);
    }
    
    // Get total payable balance (sum of invoice amount - amount collected)
    get totalPayableBalance() {
        return this.invoices.reduce((sum, invoice) => sum + parseFloat(invoice.payableBalance || 0), 0).toFixed(2);
    }
    get isCreditDisabled() {
        console.log('this.totalCreditAmount',this.totalCreditAmount);
        return this.totalCreditAmount === 0;
    }
    
    
    get totalCollectionAmount() {
        
        const total = Number(this.amountCollected) + Number(this.creditAmountEntered) || Number(this.amountCollected);
        return total.toFixed(2);
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
    
    

    

    handlePaymentDateChange(event) {
        this.paymentDate = event.target.value;
        console.log('Selected Payment Date:', this.paymentDate);
    }

    handleNarrationChange(event){
        this.narration = event.target.value;
        console.log('narration value:- ',this.narration);
    }

    handlePaymentMethodChange(event) {
        this.selectedPaymentMethod = event.target.value;
        this.isCheque = this.selectedPaymentMethod === 'Cheque';
       /* if(this.selectedPaymentMethod == 'Credit Only'){
            if(this.totalCollected > this.totalCreditAmount){
                const event = new ShowToastEvent({
                    title: 'Warning',
                    message: 'You do not have sufficient credit amount',
                    variant: 'error',
                });
            this.dispatchEvent(event); 
            return;
            }else{
                console.log('Credit Applied');
                this.fetchCreditNotes();
            }

        }*/
        if(this.selectedPaymentMethod === 'Credit Only'){
            this.amountCollected = 0.0;
            this.isAmountDisabled = true;

        }
        else if(this.selectedPaymentMethod !== 'Credit Only'){
        this.isAmountDisabled = false;
        }
        else{
            this.creditNotes = [];
        }
        console.log('Selected Payment Method:', this.selectedPaymentMethod);
    }

    handleInputChange(event) {
        const field = event.target.dataset.field;
        this.chequeDetails[field] = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
    }

    fetchCreditNotes() {
        console.log('this.selectedRetailerId',this.selectedRetailer);
        validCreditNotes({ retailerId: this.selectedRetailer })
            .then((data) => {
                this.creditNotes = data;
            })
            .catch((error) => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error fetching credit notes',
                        message: error.body.message,
                        variant: 'error',
                    })
                );
            });
    }
    
    // Handle retailer selection and load invoices
    handleChange(event) {
        this.selectedRetailer = event.target.value;
        this.invoices = [];
        // Fetch delivered invoices for the selected retailer
        getDeliveredInvoices({ retailerId: this.selectedRetailer })
            .then((data) => {
                if (data.length > 0) {
                    // Assign total credit amount from the first invoice's related Retailer_Account__r object
                    // Assign total credit amount from the first invoice's related Retailer_Account__r object
                    if (isUnderSS) {
                        // --- Logic for Secondary_Invoice_Under_SS ---
                        this.totalCreditAmount = data[0]?.Under_SS__r?.Total_Credit_Amount__c || 0;
                        this.totalCreditNotes = data[0]?.Under_SS__r?.Total_Available_Credit_Notes__c || 0;
                        console.log('this.totalCreditAmount 2', this.totalCreditAmount);
                    } else{
                    this.totalCreditAmount = data[0]?.Retailer_Account__r?.Total_Credit_Amount__c || 0;
                    this.totalCreditNotes = data[0]?.Retailer_Account__r?.Total_Available_Credit_Notes__c || 0;
                    console.log('this.totalCreditAmount 2',this.totalCreditAmount);
                } 
                }
                else {
                    this.totalCreditAmount = 0; // No data, reset to 0
                    this.totalCreditNotes = 0;
                    console.log('No Invoice');
                    this.invoices = [];
                    const toastEvent = new ShowToastEvent({
                        title: 'No Invoices',
                        message: `No delivered invoices for selected retailer: ${this.selectedRetailer}.`,
                        variant: 'error',
                    });
                    this.dispatchEvent(toastEvent);
                    return;
                }
                this.invoices = data.map((invoice) => ({
                    ...invoice,
                    amountCollected: '', // Initialize with empty value
                    formattedDate: this.formatDate(invoice.Invoice_Date__c)
                }));
                console.log('this.invoices',JSON.stringify(this.invoices));
            })
            .catch((error) => {
                console.error('Error fetching invoices:', error);
            });
    }

    // Handle "Select" button click for a specific invoice
    handleSelectClick(event) {
        
        console.log('inside modal');
        const invoiceId = event.target.dataset.invoiceId;
        this.recordId = invoiceId;
        
        const selectedInvoice = this.invoices.find(invoice => invoice.Id === invoiceId);
        //total payable balance
        if (selectedInvoice) {
            this.selectedPaymentMethod = '';
            this.selectedTotalPayableBalance = selectedInvoice.Total_Payable_Balance__c;
            //100 > 50
            if((this.selectedTotalPayableBalance > this.totalCreditAmount) && this.totalCreditAmount!=0){
                this.creditAmountEntered = this.totalCreditAmount;
                this.amountCollected = Number((this.selectedTotalPayableBalance - this.totalCreditAmount).toFixed(2));
                 this.updatePaymentOptions(false); // Include all
                 this.isAmountDisabled = false;
                //this.selectedPaymentMethod = 'Cash';
            }else if((this.selectedTotalPayableBalance < this.totalCreditAmount) && this.totalCreditAmount!=0){
                this.creditAmountEntered = this.selectedTotalPayableBalance;
                 this.updatePaymentOptions(false);
                 this.selectedPaymentMethod = 'Credit Only';
                this.amountCollected = 0.0;
                this.isAmountDisabled = true;
                 this.updatePaymentOptions(false); // Include all
            }else if(this.totalCreditAmount == 0){
                this.amountCollected = this.selectedTotalPayableBalance;
                   this.updatePaymentOptions(true); // Exclude 'Credit Only'
                   this.isAmountDisabled = false; 
                //this.selectedPaymentMethod = 'Cash';
            }
            if(this.amountCollected != 0){
                this.selectedPaymentMethod = 'Cash';
            }
            console.log('Selected Total Payable Balance:', this.selectedTotalPayableBalance);
        } else {
            console.error('Invoice not found!');
        }
    
        this.isModalOpen = true;
    }
       

    
    handleCreditAmountEntered(event){
            let enteredAmount = event.target.value;
            if (parseFloat(enteredAmount) > parseFloat(this.selectedTotalPayableBalance)) {
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
            const invoiceAmount = parseFloat(this.selectedTotalPayableBalance) || 0;
            console.log('invoiceAmount',invoiceAmount);
            this.payableBalance = invoiceAmount - enteredAmount; 
        }

    
    
    handleAmountChange(event) {
            let enteredAmount = event.target.value;
            // Ensure amount collected is not greater than invoice amount
            if (parseFloat(enteredAmount) > parseFloat(this.selectedTotalPayableBalance)) {
                enteredAmount = 0.0; // Set it to invoice amount if greater
                const toastEvent = new ShowToastEvent({
                    title: 'Invalid Amount',
                    message: `Amount collected cannot exceed the invoice amount of ${this.selectedTotalPayableBalance}.`,
                    variant: 'error',
                });
                this.dispatchEvent(toastEvent); // Show an error toast message
            }
            
            // Update amountCollected
            this.amountCollected = enteredAmount;
            const invoiceAmount = parseFloat(this.selectedTotalPayableBalance) || 0;
            const collectedAmount = parseFloat(this.amountCollected) || 0;
            const credAmt = parseFloat(this.creditAmountEntered) || 0;
            const totalcollection = collectedAmount + credAmt;
            this.payableBalance = invoiceAmount - totalcollection; 
        
            
    }   

    // Handle modal close action
    handleCloseModal() {
        if (this.invoiceToUpdate) {
            this.invoiceToUpdate.amountCollected = this.amountCollected || 0 ; // Save the collected amount
           
        }
        this.isModalOpen = false;
        this.isCheque = false;
         this.creditAmountEntered = 0;//Initialize with 0
         this.resetChequeDetails();
    }   
    // Handle saving the collection
        handleSaveCollection() {
            if (this.recordId) {
                console.log('selectedPaymentMethod sup',this.selectedPaymentMethod);
                console.log('paymentDate',this.paymentDate);
                console.log('totalCreditsUsable',this.totalCreditsUsable);
                
               if(this.selectedPaymentMethod != '' && this.selectedPaymentMethod != 'Credit Only'  && this.amountCollected == ''){
                this.showToast('Error', 'Please fill in the payment date and amount collected.', 'error');
                return;
               }
               if(this.selectedPaymentMethod == '' && this.amountCollected != ''){
                this.showToast('Error', 'Please fill in the payment method.', 'error');
                return;
               }
               if(this.amountCollected == 0 && this.totalCollectionAmount == 0){
                this.showToast('Error', 'Amount collected or Credit Amount must be greater than 0.', 'error');
                return;
               }
               if(this.totalCollectionAmount > this.selectedTotalPayableBalance){
                this.showToast('Error', 'Total collected amount cannot exceed the total outstanding amount', 'error');
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
                console.log('this.recordId',this.recordId);
                console.log('this.amountCollected',this.amountCollected);
                console.log('this.payableBalance',this.payableBalance);
                console.log('this.selectedRetailer',this.invoices.Retailer_Account__c);
                console.log('this.totalCreditsUsable',this.totalCreditsUsable);
                console.log('this.creditAmountEntered',this.creditAmountEntered);
                if(this.creditAmountEntered == ''){
                    this.creditAmountEntered = 0;
                }
                saveInvoiceCollection({ invoiceId: this.recordId,amountCollected:this.amountCollected , payableBalance:this.payableBalance,selectedRetailer: this.selectedRetailerId,paymentMethod: this.selectedPaymentMethod, paymentDate: this.paymentDate, creditAmountToBeUsed: this.creditAmountEntered,chequeData: this.chequeDetails , narrationData:this.narration })
                    .then(() => {
                        // Show success message
                        const successEvent = new ShowToastEvent({
                            title: 'Success',
                            message: `Collection have been recorded.`,
                            variant: 'success',
                        });
                        this.dispatchEvent(successEvent);
                        this.creditAmountEntered = 0;//Initialize with 0
                 this.resetChequeDetails();
                        this.handleCloseModal();
                        getDeliveredInvoices({ retailerId: this.selectedRetailerId })
            .then((data) => {
                if (data.length > 0) {
                    const isUnderSS = data[0]?.RecordType?.DeveloperName === 'Secondary_Invoice_Under_SS';
                    //to check the recordtype and depending on that which field to fetch will be determined added by Ajay
                    // Assign total credit amount from the first invoice's related Retailer_Account__r object
                    if (isUnderSS) {
                        // --- Logic for Secondary_Invoice_Under_SS ---
                        this.totalCreditAmount = data[0]?.Under_SS__r?.Total_Credit_Amount__c || 0;
                        this.totalCreditNotes = data[0]?.Under_SS__r?.Total_Available_Credit_Notes__c || 0;
                        console.log('this.totalCreditAmount 2', this.totalCreditAmount);
                    } else {
                    this.totalCreditAmount = data[0]?.Retailer_Account__r?.Total_Credit_Amount__c || 0;
                    this.totalCreditNotes = data[0]?.Retailer_Account__r?.Total_Available_Credit_Notes__c || 0;
                    console.log('this.totalCreditAmount 22',this.totalCreditAmount);
                } 
                }else {
                    this.totalCreditAmount = 0; // No data, reset to 0
                    this.totalCreditNotes = 0;
                    console.log('No Invoice');
                    this.invoices = [];
                    const toastEvent = new ShowToastEvent({
                        title: 'No Invoices',
                        message: `No delivered invoices for selected retailer: ${this.selectedRetailer}.`,
                        variant: 'error',
                    });
                    this.dispatchEvent(toastEvent);
                    return;
                }
                this.invoices = data.map((invoice) => ({
                    ...invoice,
                    amountCollected: '',
                     formattedDate: this.formatDate(invoice.Invoice_Date__c) // Initialize with empty value
                }));
                
            })
            .catch((error) => {
                console.error('Error fetching invoices:', error);
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
    


    handleClose(){
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Collection__c', // API name of your object
                actionName: 'list'
            },
            state: {
                filterName: 'Default' // You can specify a custom view if needed
            }
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
//used to reset checque details on cancel or save -added by Ajay
    resetChequeDetails() {
    this.chequeDetails = {
        chequeNumber: '',
        chequeDate: new Date().toISOString().split('T')[0],  // Reset to today's date
        branchName: '',
        isChequeCleared: false
    };
}
}