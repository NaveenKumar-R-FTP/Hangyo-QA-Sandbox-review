import { LightningElement, track } from 'lwc';
import invoiceData from '@salesforce/apex/DownloadInvoiceController.invoiceData';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class DownloadInvoice extends NavigationMixin(LightningElement) {

    @track recordId;

    connectedCallback() {
        const queryParams = new URLSearchParams(window.location.search);
        this.recordId = queryParams.get('recordId');
        if (this.recordId) {
            this.fetchInvoiceDetails();
        } else {
            this.showToast('Error', 'No record ID provided in the URL.', 'error');
        }
    }

    fetchInvoiceDetails() {
        invoiceData({ invoiceId: this.recordId })
        .then((result) => {
            if (result === 'Draft') {
                this.showToast('Error', 'Invoice status is Draft. Kindly confirm it to download invoice.', 'error');
                this.navigateToRecordPage();
            } else if (result === 'CounterInvoice') {
                window.open(window.location.origin + '/apex/CounterInvoicePdf?id=' + this.recordId, '_blank');
                // Navigate back to invoice record after opening PDF
                this.navigateToRecordPage();
            } else {
                window.open(window.location.origin + '/apex/InvoicePDFWrapper?id=' + this.recordId, '_blank');
                // Navigate back to invoice record after opening PDF
                this.navigateToRecordPage();
            }
        })
        .catch((error) => {
            this.showToast('Error', error.body ? error.body.message : 'Error downloading invoice', 'error');
            this.navigateToRecordPage();
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    navigateToRecordPage() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: 'Invoice__c',
                actionName: 'view'
            }
        });
    }
}