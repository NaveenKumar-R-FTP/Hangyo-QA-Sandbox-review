import { LightningElement, track,wire } from 'lwc';
import getInvoiceLineItems from '@salesforce/apex/ReturnProcessorController.getInvoiceLineItems';
import saveReturns from '@salesforce/apex/ReturnProcessorController.saveReturns';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference } from 'lightning/navigation';
import { NavigationMixin } from 'lightning/navigation';

export default class ReturnProcessor extends NavigationMixin( LightningElement ) {

@track returnAmt;
@track invoiceData = {}; 
@track invoiceLineItems = [];
@track isSubmitting = false;
@track columns = [
    { label: 'Product Name', fieldName: 'productName', type: 'text' },
    { label: 'Quantity', fieldName: 'quantity', type: 'number' },
    { label: 'Damage', fieldName: 'damage', type: 'number', editable: true },
    { label: 'Reuse', fieldName: 'reuse', type: 'number', editable: true },
    { label: 'Return Amount', fieldName: 'returnAmount', type: 'currency' },
    // JSON looks like: {invoice=Invoice__c:{Id=a0DH1000002xRsQMAU, Name=Inv 123, Invoice_Amount__c=4602.00, Status__c=Confirmed, CreatedDate=2024-12-30 09:59:39, Total_Quantity__c=45}, lineItems=(InvoiceLineItemWrapper:[damage=0, lineItemId=a0IH1000002MHqqMAG, price=100.00, productName=a0JH1000005g6WiMAI, quantity=15, returnAmount=0, reuse=0, unitPrice=1500.00], InvoiceLineItemWrapper:[damage=0, lineItemId=a0IH1000002MHqvMAG, price=70.00, productName=a0JH1000005g6WiMAI, quantity=20, returnAmount=0, reuse=0, u
];

@track errorMessage = '';
@track totalQuantity = 0;
@track totalAmount = 0;
@track cgst = 0;
@track sgst = 0;
@track igst = 0;
@track grandTotal = 0;
recordId; // Capture the record ID from the Invoice Details page.

    @wire(CurrentPageReference)
    getPageReference(pageRef) {
        console.log('currentPageReferenceeference: ',pageRef);
        if (pageRef) {
            this.recordId = pageRef.state.recordId;
                
            console.log('Record ID from Page Reference: ', this.recordId);
            this.initializeData();
            // Fetch data once recordId is available

        //  this.fetchInvoiceLineItems();
        }
    }

    async initializeData() {
        try {
            await this.fetchInvoiceLineItems();
        } catch (error) {
            console.error('Error initializing data:', error);
            this.showToast('Error', 'Failed to load tax settings', 'error');
        }
    }

    async fetchInvoiceLineItems() {
        console.log('Fetching invoice line items for recordId: ', this.recordId);
        try {
            const data = await getInvoiceLineItems({ invoiceId: this.recordId });
            console.log('Fetched invoice: ', data.invoice);

            this.invoiceData = {
                Invoice_Number__c : data.invoice.Invoice_Number__c,
                Taxable_Amount__c : data.invoice.Taxable_Amount__c.toFixed(2),
                Invoice_Amount__c : data.invoice.Invoice_Amount__c.toFixed(2),
            };

            // Store tax rates directly from invoice
            this.cgstRate = data.invoice.CGST__c || 0;
            this.sgstRate = data.invoice.SGST__c || 0;
            this.igstRate = data.invoice.IGST__c || 0;

            // Map over the lineItems array
            this.invoiceLineItems = data.lineItems.map(item => ({
                lineItemId: item.lineItemId,
                productName: item.productName,
                quantity: item.quantity,
                damage: item.damage,
                reuse: item.reuse,
                prodId: item.prodId,
                returnAmount: 0,
                unitPrice: item.unitPrice
            }));

            console.log('Mapped invoice line items: ', JSON.stringify(this.invoiceLineItems));
        } catch (error) {
            console.error('Error fetching invoice line items:', error);
            if (error.body?.message === 'Returns already exist for this invoice.') {
                this.showToast('Error', 'Returns already exist for this invoice.', 'error');
                this.redirectToPreviousPage();
            } else if (error.body?.message === 'Invoice not delivered') {
                this.showToast('Error', 'Returns can be created only after the invoice is delivered', 'error');
                this.redirectToPreviousPage();
            } else if (error.body?.message === 'Returns not allowed for primary invoices') {
                this.showToast('Error', 'Returns can be created only for secondary Orders', 'error');
                this.redirectToPreviousPage();
            }
        }
    }

//handles changes in damages and reuse values
handleInputChange(event) {
    const { name, value, dataset } = event.target;
    const index = dataset.index;
    
    console.log('return amount', JSON.stringify(this.invoiceLineItems));

    let sanitizedValue = Number(value);
    // if (sanitizedValue < 0) {
    //     sanitizedValue = 0; // Reset to zero if negative
    //     event.target.value = 0; // Update input field in UI
    // }
    // added by Hari: only clamp negative for reuse; damage may be negative
    if (name === 'reuse' && sanitizedValue < 0) {
        sanitizedValue = 0;
        event.target.value = 0;
    }

    // Update the respective row's value
    this.invoiceLineItems = this.invoiceLineItems.map((item, idx) => {
        if (parseInt(index, 10) === idx) {
            const updatedItem = {
                ...item,
                [name]: sanitizedValue, // Update damage or reuse
            };

            let totalEntered = updatedItem.damage + updatedItem.reuse;

            // Highlight field if totalEntered > quantity
            updatedItem.errorClass = totalEntered > updatedItem.quantity ? 'error-field' : '';

            updatedItem.returnAmount = totalEntered * updatedItem.unitPrice;
            return updatedItem;
        }
        return item;
    });

    this.calculateSummary();
}

    //summary calculation
    calculateSummary() {
        this.totalQuantity = this.invoiceLineItems.reduce((sum, item) => sum + item.damage + item.reuse, 0);
        const totalamt = this.invoiceLineItems.reduce((sum, item) => sum + item.returnAmount, 0);

        this.totalAmount = totalamt.toFixed(2);

        if (this.cgstRate > 0 && this.sgstRate > 0) {
            this.cgst = (totalamt * (this.cgstRate / 100)).toFixed(2);
            this.sgst = (totalamt * (this.sgstRate / 100)).toFixed(2);
            this.igst = 0;
            this.grandTotal = (totalamt + parseFloat(this.cgst) + parseFloat(this.sgst)).toFixed(2);
        } else if (this.igstRate > 0) {
            this.igst = (totalamt * (this.igstRate / 100)).toFixed(2);
            this.cgst = 0;
            this.sgst = 0;
            this.grandTotal = (totalamt + parseFloat(this.igst)).toFixed(2);
        }
    }
   
    // Close the entire tab or redirect to a different page (Community Portal specific)
    handleCloseTab() {
        this.invoiceData = {}; 
        this.invoiceLineItems = [];
        
    }
    get isSubmitDisabled() {
        return this.totalQuantity === 0 || this.isSubmitting;
    }

// Submit the returns
/*async handleSubmit() {
        console.log('this.invoiceLineItems',JSON.stringify(this.invoiceLineItems));
         console.log('this.invoiceLineItems', JSON.stringify(this.invoiceLineItems));

    let totalAvailableQuantity = this.invoiceLineItems.reduce((sum, item) => sum + item.quantity, 0);
    console.log('Total Available Quantity:', totalAvailableQuantity);
    console.log('Total Return Quantity:', this.totalQuantity);

    let isError = false;

    // Validate each row
    this.invoiceLineItems = this.invoiceLineItems.map(item => {
        let totalEntered = item.damage + item.reuse;
        let errorClass = '';

        if (totalEntered > item.quantity) {
            isError = true;
            errorClass = 'error-field'; // Add CSS class for highlighting
        }

        return { ...item, errorClass };
    });

    // Validation: Ensure return quantity does not exceed available quantity
    if (this.totalQuantity > totalAvailableQuantity) {
        this.showToast('Error', 'Total return quantity is higher than the available quantity.', 'error');
        return; // Stop execution and prevent saving
    }

    // If any line item has an issue, prevent saving and show error message
    if (isError) {
        this.showToast('Error', 'Some return quantities exceed available quantities.', 'error');
        return;
    }
        
    let formattedItems = this.invoiceLineItems.map(item => ({
        lineItemId: item.lineItemId,
        productName: item.productName,
        quantity: item.quantity,
        damage: item.damage,
        reuse: item.reuse,
        returnAmount: item.returnAmount,
        prodId:item.prodId,
        unitPrice: item.unitPrice
    }));
    console.log('formattedItems',JSON.stringify(formattedItems));
    const jsonPayload = JSON.stringify(formattedItems);
        try {

        await saveReturns({

            invoiceId: this.recordId,

            totalQuantity: this.totalQuantity,

            totalAmount: this.totalAmount,

            cgst: this.cgst,

            sgst: this.sgst,

            igst: this.igst,

            jsonlineItems: jsonPayload

        });

        this.showToast('Success', 'Returns saved successfully', 'success');
        this[NavigationMixin.Navigate]({
        type: 'standard__recordPage',
        attributes: {
            recordId: this.recordId, // The record ID to navigate 
            objectApiName: 'Invoice__c', // API name
            actionName: 'view' // The action to perform (view = record detail page)
        }
    });

    } catch (error) {
        console.error('Save error:', error);
        let errorMessage = error.body?.message || 'Unknown error';
        if (error.body && error.body.message ==='Returns already exist for this invoice.') {
            this.showToast('Error', 'Returns already exist for this invoice.', 'error');
            
        }
      else {
            this.showToast('Error', 'Error saving returns: ' + errorMessage, 'error');
        }
    }
}*/

async handleSubmit() {
    this.isSubmitting = true;
    console.log('this.invoiceLineItems', JSON.stringify(this.invoiceLineItems));
    console.log('this.invoiceLineItems', JSON.stringify(this.invoiceLineItems));

    let totalAvailableQuantity = this.invoiceLineItems.reduce((sum, item) => sum + item.quantity, 0);
    console.log('Total Available Quantity:', totalAvailableQuantity);
    console.log('Total Return Quantity:', this.totalQuantity);

    let isError = false;

    // Validate each row
    this.invoiceLineItems = this.invoiceLineItems.map(item => {
        let totalEntered = item.damage + item.reuse;
        let errorClass = '';

        if (totalEntered > item.quantity) {
            isError = true;
            errorClass = 'error-field';
        }

        return { ...item, errorClass };
    });

    // Validation: Ensure return quantity does not exceed available quantity
    if (this.totalQuantity > totalAvailableQuantity) {
        this.showToast('Error', 'Total return quantity is higher than the available quantity.', 'error');
        this.isSubmitting = false;
        return;
    }

    // If any line item has an issue, prevent saving and show error message
    if (isError) {
        this.showToast('Error', 'Some return quantities exceed available quantities.', 'error');
        this.isSubmitting = false;
        return;
    }

    let formattedItems = this.invoiceLineItems.map(item => ({
        lineItemId: item.lineItemId,
        productName: item.productName,
        quantity: item.quantity,
        damage: item.damage,
        reuse: item.reuse,
        returnAmount: item.returnAmount,
        prodId: item.prodId,
        unitPrice: item.unitPrice
    }));
    console.log('formattedItems', JSON.stringify(formattedItems));
    const jsonPayload = JSON.stringify(formattedItems);

    try {
        await saveReturns({
            invoiceId: this.recordId,
            totalQuantity: this.totalQuantity,
            totalAmount: this.totalAmount,
            cgst: this.cgst,
            sgst: this.sgst,
            igst: this.igst,
            jsonlineItems: jsonPayload
        });

        this.showToast('Success', 'Returns saved successfully', 'success');
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: 'Invoice__c',
                actionName: 'view'
            }
        });

    } catch (error) {
        this.isSubmitting = false;
        console.error('Save error:', error);
        let errorMessage = error.body?.message || 'Unknown error';
        if (error.body && error.body.message === 'Returns already exist for this invoice.') {
            this.showToast('Error', 'Returns already exist for this invoice.', 'error');
        } else {
            this.showToast('Error', 'Error saving returns: ' + errorMessage, 'error');
        }
    }
}


// Utility for showing toast messages
showToast(title, message, variant) {
    const evt = new ShowToastEvent({ title, message, variant });
    this.dispatchEvent(evt);
}
//returns to old page specific for community
redirectToPreviousPage() {
        setTimeout(() => {
            window.history.back();
        }, 1300);
    }
}