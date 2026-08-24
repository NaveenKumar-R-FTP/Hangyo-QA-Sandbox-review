// invoiceGrnUpdater.js
import { LightningElement, api, track, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getInvoiceLineItems from '@salesforce/apex/InvoiceGRNController.getInvoiceLineItems';
import checkExistingGRN from '@salesforce/apex/InvoiceGRNController.checkExistingGRN';
import submitGRN from '@salesforce/apex/InvoiceGRNController.submitGRN';
import { NavigationMixin } from 'lightning/navigation';
import { CurrentPageReference } from 'lightning/navigation';

const INVOICE_FIELDS = [
    'Invoice__c.Name', 
    'Invoice__c.Status__c',
    'Invoice__c.Order__r.Name',
    'Invoice__c.RecordType.DeveloperName',
    'Invoice__c.Invoice_Date__c',
    'Invoice__c.Under_SS_Invoice__r.Name'
];

export default class InvoiceGrnUpdater extends NavigationMixin(LightningElement) {
    recordId;
    @track invoiceDetails;
    @track invoiceLineItems = [];
    @track receivedQuantitySum = 0;
    @track isSubmitDisabled = false;

    @wire(CurrentPageReference)
    getPageReference(pageRef) {
        if (pageRef && pageRef.state) {
            this.recordId = pageRef.state.recordId;
        }
    }

   @wire(getRecord, { recordId: '$recordId', fields: INVOICE_FIELDS })
wiredInvoice({ error, data }) {
    if (data) {
        const recordType = data.fields.RecordType?.value?.fields?.DeveloperName?.value;
        let linkedName = '';

        if (recordType === 'Primary_Invoice') {
            linkedName = data.fields.Order__r?.displayValue || data.fields.Order__r?.value?.fields?.Name?.value;
        } else if (recordType === 'Secondary_Invoice_Under_SS') {
            linkedName = data.fields.Under_SS_Invoice__r?.displayValue || data.fields.Under_SS_Invoice__r?.value?.fields?.Name?.value;
        }

        this.invoiceDetails = {
            Name: data.fields.Name.value,
            Status__c: data.fields.Status__c.value,
            RecordTypeDeveloperName: recordType,
            Order__c: linkedName,
            Invoice_Date__c: data.fields.Invoice_Date__c.value
        };

        const { Status__c } = this.invoiceDetails;

        if (recordType === 'Primary_Invoice') {
            if (Status__c !== 'Cancelled') {
                this.loadInvoiceLineItems();
            } else {
                this.showToast('Error', 'GRN cannot be created for cancelled primary invoices.', 'error');
                this.isSubmitDisabled = true;
                this.redirectToPreviousPage();
            }
            //this.loadInvoiceLineItems();
        } else if (recordType === 'Secondary_Invoice_Under_SS') {
            if (Status__c === 'Confirmed' || Status__c === 'Delivered') {
                this.loadInvoiceLineItems();
            } else {
                this.showToast('Error', 'Only confirmed/delivered Under SS invoices are allowed.', 'error');
                this.isSubmitDisabled = true;
                this.redirectToPreviousPage();
            }
        } else {
            this.showToast('Error', 'This feature is only available for Non Cancelled Primary Invoices or Confirmed Secondary Invoices Under SS.', 'error');
            this.isSubmitDisabled = true;
            this.redirectToPreviousPage();
        }

    } else if (error) {
        this.showToast('Error', 'Failed to fetch invoice details: ' + error.body?.message, 'error');
    }
}


    /*loadInvoiceLineItems() {
        checkExistingGRN({ invoiceId: this.recordId })
            .then(data => {
                if (data.grnExists) {
                    this.showToast('Error', 'GRN already processed for this invoice', 'error');
                    this.redirectToPreviousPage();
                    return;
                }

                getInvoiceLineItems({ invoiceId: this.recordId })
                    .then(items => {
                        this.invoiceLineItems = items.map(item => ({
                            ...item,
                            ReceivedQuantity: item.CurrentInvoiceQuantity || 0,
                            Comment: item.Comments__c || '',
                        }));
                        this.calculateReceivedQuantitySum();
                    })
                    .catch(error => {
                        this.showToast('Error', 'Error loading line items', 'error');
                    });
            })
            .catch(error => {
                this.showToast('Error', 'Validation failed', 'error');
            });
    }*/

    loadInvoiceLineItems() {
        checkExistingGRN({ invoiceId: this.recordId })
            .then(data => {
                if (data.grnExists) {
                    this.showToast('Error', 'GRN already processed for this invoice', 'error');
                    this.isSubmitDisabled = true;
                    this.redirectToPreviousPage();
                    return;
                }

                getInvoiceLineItems({ invoiceId: this.recordId })
                    .then(items => {
                        this.invoiceLineItems = items.map((item, index) => ({
                            ...item,
                            serialNumber: index + 1,  // ✅ Serial number added here
                            ReceivedQuantity: item.CurrentInvoiceQuantity || 0,
                            Comment: item.Comments__c || '',
                        }));
                        this.calculateReceivedQuantitySum();
                    })
                    .catch(error => {
                        this.showToast('Error', 'Error loading line items', 'error');
                    });
            })
            .catch(error => {
                this.showToast('Error', 'Validation failed', 'error');
            });
    }

    get formattedInvoiceDate() {
    if(this.invoiceDetails && this.invoiceDetails.Invoice_Date__c) {
        let date = new Date(this.invoiceDetails.Invoice_Date__c);
        return `${date.getDate().toString().padStart(2, '0')}-${(date.getMonth()+1).toString().padStart(2, '0')}-${date.getFullYear()}`;
    }
    return '';
}

    handleQuantityChange(event) {
        const itemId = event.target.dataset.id;
        const value = event.target.value;
        this.invoiceLineItems = this.invoiceLineItems.map(item =>
            item.Id === itemId ? { ...item, ReceivedQuantity: value } : item
        );
        this.calculateReceivedQuantitySum();
    }

    handleCommentChange(event) {
        const itemId = event.target.dataset.id;
        const value = event.target.value;
        this.invoiceLineItems = this.invoiceLineItems.map(item =>
            item.Id === itemId ? { ...item, Comment: value } : item
        );
    }

    calculateReceivedQuantitySum() {
        this.receivedQuantitySum = this.invoiceLineItems.reduce(
            (sum, item) => sum + (parseFloat(item.ReceivedQuantity) || 0),
            0
        );
    }

    handleSubmit() {
        const isValid = this.validateAllQuantities();
        if (!isValid) return;

        this.isSubmitDisabled = true;

        const jsonPayload = JSON.stringify(this.invoiceLineItems);
        submitGRN({
            invoiceId: this.recordId,
            jsonLineItems: jsonPayload,
             updatedQuan: this.receivedQuantitySum
        })
        .then(() => {
            this.showToast('Success', 'GRN updated successfully', 'success');
            this.navigateToInvoiceView();
        })
        .catch(error => {
            this.showToast('Error', error.body.message, 'error');
        });
    }

   validateAllQuantities() {
    let isValid = true;
    this.invoiceLineItems.forEach(item => {
        const receivedStr = item.ReceivedQuantity;
        const received = parseFloat(receivedStr);
        const available = parseFloat(item.CurrentInvoiceQuantity) || 0;

        if (receivedStr === '' || receivedStr === null || receivedStr === undefined) {
            this.showToast('Error', `Received quantity is required for ${item.ProductName}`, 'error');
            isValid = false;
        } else if (received < 0) {
            this.showToast('Error', `Received quantity cannot be negative for ${item.ProductName}`, 'error');
            isValid = false;
        } else if (received > available) {
            this.showToast('Error', `Received quantity cannot exceed current invoice quantity for ${item.ProductName}`, 'error');
            isValid = false;
        }
    });
    return isValid;
}


    navigateToInvoiceView() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: 'Invoice__c',
                actionName: 'view'
            }
        });
    }

     showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    redirectToPreviousPage() {
        setTimeout(() => {
            window.history.back();
        }, 1200);
    }
}