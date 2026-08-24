import { LightningElement, track} from 'lwc';
import fetchInvoicesByOrder from '@salesforce/apex/ClaimController.fetchInvoicesByOrder';
import getTypePicklistValues from '@salesforce/apex/ClaimController.getTypePicklistValues';
import saveExpenseClaim from '@salesforce/apex/ClaimController.saveExpenseClaim';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFieldHelpTexts from '@salesforce/apex/ClaimController.getFieldHelpTexts';



export default class ClaimForm extends LightningElement {
   // @track orderSearchTerm = '';
   // @track orders = [];
   // @track selectedOrderId;
    @track primaryPurchase = 0; // holds the primary purchase value
    @track secondarySales = 0; // holds the secondary purchase value
    @track showSections = false; //handles template visibility
    @track errorMessage = ''; // used to show any errors
// below variables used to take inputs from users
    @track dealerDiscount = 0;
    @track productComplaint = 0;
    @track transportSupport = 0;
    @track freezerSubsidy = 0;
    @track schemes = 0;
    @track eventSalesDiscounts = 0;
    @track institutionalDiscounts = 0;
    @track coldRoomSupport = 0;
    @track approvedSpecialClaims = 0;
    @track specialClaimType = '';
    @track specialClaimOptions = [];
   // formattedMonth;
    @track selectedMonth; // holds the month selected by user

    // Fetch picklist values for Type__c
  
      @track typePicklistValues = [];
 helpTexts = {};// holds the help text for every field

//fetches picklist fields and the required help texts dynamically from expense calim object
    connectedCallback() {
        getTypePicklistValues()
            .then((data) => {
                this.typePicklistValues = data.map((value) => ({
                    label: value,
                    value: value
                }));
            })
            .catch((error) => {
                console.error('Error fetching picklist values from Apex:', error);
                this.typePicklistValues = []; // Gracefully handle errors
            });

            const fields = ['Dealer_Discount__c', 'Product_Complaint__c', 'Outstation_Transport_Support__c', 'Freezer_subsidy_Repairs__c', 
                        'Schemes__c', 'Stall_Rents_Event_Sales_Discounts__c', 'Party_Orders_institutional_Discounts__c', 
                        'Cold_Room_Support__c', 'Approved_Special_claims_if_any__c', 'Special_Claim_Type__c'];

        
        getFieldHelpTexts({ objectApiName: 'Expense_Claim__c', fieldApiNames: fields })
            .then((result) => {
                this.helpTexts = result;
                console.log('texts', this.helpTexts);
            })
            .catch((error) => {
                console.error('Error fetching field help texts from Apex:', error);
                this.helpTexts = {}; // Gracefully handle errors
            });
    }

   // used to capture the date entered by user and fetchs values from controller
   handleInputChangeDate(event) {
       this.selectedMonth = event.target.value; // Captures YYYY-MM format
    console.log('selectedMonth',this.selectedMonth);
    if (this.selectedMonth) {
    this.errorMessage = null; // Clear error
            this.fetchInvoiceDetails();}
            else if (!this.selectedMonth) {
this.showSections = false;
             }
     }

    fetchInvoiceDetails() {
        fetchInvoicesByOrder({ formattedMonth: this.selectedMonth })
            .then((result) => {
                if (result.primaryPurchase === 0 && result.secondarySales === 0) {
                    this.errorMessage = 'No invoices found for the selected month.';
                    this.showSections = false;
                } else {
                    this.primaryPurchase = result.primaryPurchase;
                    this.secondarySales = result.secondarySales;
                    this.errorMessage = '';
                    this.showSections = true;
                }
            })
            .catch((error) => {
                console.error('Error fetching invoice details:', error);
            });
    }
//used to take input from fields from user and store in track variables
    handleInputChange(event) {
        const field = event.target.name;
        this[field] = event.target.value;
    }
//this method submits and creates a claim record
    handleSubmit() {
        const claimDetails = {
            orderId: this.selectedOrderId,
            primaryPurchase: this.primaryPurchase,
            secondarySales: this.secondarySales,
            dealerDiscount: this.dealerDiscount,
            productComplaint: this.productComplaint,
            transportSupport: this.transportSupport,
            freezerSubsidy: this.freezerSubsidy,
            schemes: this.schemes,
            eventSalesDiscounts: this.eventSalesDiscounts,
            institutionalDiscounts: this.institutionalDiscounts,
            coldRoomSupport: this.coldRoomSupport,
            approvedSpecialClaims: this.approvedSpecialClaims,
            specialClaimType: this.specialClaimType,
        };
        let serializedData = JSON.stringify(claimDetails);
 // const jsonPayload = JSON.stringify(claimDetails);
        saveExpenseClaim({ claimDataStr: serializedData })
            .then(result => {
                  console.log('Result:', JSON.stringify(result));
                if (result.includes('Error')) {
                    this.showToastMessage('Error', result, 'error'); // Show error toast if message contains 'Error'
                } else {
                    this.showToastMessage('Success', result, 'success'); // Show success toast if claim was saved
                    this.resetForm();
                }
            })
            .catch(error => {
                this.showToastMessage('Error', 'Error saving claim: ' + error.body.message, 'error');
            });
    }

    // Helper method to show toast messages
    showToastMessage(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'dismissable', // Optionally set to 'dismissable'
        });
        this.dispatchEvent(event);
    }

//used to reset the form after save
    resetForm() {
        this.selectedOrderId = '';
        this.primaryPurchase = 0;
        this.secondarySales = 0;
        this.showSections = false;
        this.errorMessage = '';
        this.dealerDiscount = 0;
        this.productComplaint = 0;
        this.transportSupport = 0;
        this.freezerSubsidy = 0;
        this.schemes = 0;
        this.eventSalesDiscounts = 0;
        this.institutionalDiscounts = 0;
        this.coldRoomSupport = 0;
        this.approvedSpecialClaims = 0;
        this.specialClaimType = '';
    }
}