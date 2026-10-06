import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import { showToast } from 'c/dmsUtility';
import cancelInvoice from '@salesforce/apex/InvoiceCancellationService.cancelInvoice';
import STATUS_FIELD from '@salesforce/schema/Invoice__c.Status__c';
import IRN_FIELD from '@salesforce/schema/Invoice__c.IRN_Number__c';
import invoiceHasGRN from '@salesforce/apex/InvoiceEditWindow.invoiceHasGRN';

export default class InvoiceCancelButton extends LightningElement {
    @api recordId;
    showConfirm = false;
    isCancelling = false;
        invoiceStatus;
    irnNumber;
    hasGRN = false;

    connectedCallback() {
        invoiceHasGRN({ invoiceId: this.recordId })
            .then((res) => { this.hasGRN = res === true; })
            .catch(() => { this.hasGRN = false; });
    }

    @wire(getRecord, { recordId: '$recordId', fields: [STATUS_FIELD, IRN_FIELD] })

    wiredInvoice({ data }) {
                if (data) {
            this.invoiceStatus = getFieldValue(data, STATUS_FIELD);
            this.irnNumber = getFieldValue(data, IRN_FIELD);
        }
    }

        get hasEInvoice() {
        return this.irnNumber != null && this.irnNumber !== '';
    }
    get canCancel() {
        // #4: no Cancel option once an E-Invoice (IRN) has been generated
        return this.invoiceStatus && this.invoiceStatus !== 'Cancelled';
    }
        // Once the Under SS distributor completes the GRN, the Super Stockist can no longer edit.
    get canEdit() { return !this.hasGRN; }
    get editUrl() { return '/dms/s/edit-invoice?recordId=' + this.recordId; }
    get collectionUrl() { return '/dms/s/invoicecollection?recordId=' + this.recordId; }
    get returnsUrl() { return '/dms/s/secondaryreturns?recordId=' + this.recordId; }
    get downloadUrl() { return '/dms/s/download-invoice?recordId=' + this.recordId; }

    openConfirm() { this.showConfirm = true; }
    closeConfirm() { this.showConfirm = false; }

    confirmCancel() {
        this.isCancelling = true;
        cancelInvoice({ invoiceId: this.recordId })
            .then(() => {
                this.isCancelling = false;
                this.showConfirm = false;
             this.dispatchEvent(showToast('Success', 'Invoice cancelled successfully.', [], 'success', ''));
                // RefreshEvent is unreliable in Experience Cloud - reload to reflect the new status, stock and collections
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => { window.location.reload(); }, 700);
            })
                        .catch((error) => {
                this.isCancelling = false;
                this.showConfirm = false;
                const msg = (error && error.body && error.body.message) ? error.body.message : 'Unable to cancel the invoice.';
                this.dispatchEvent(showToast('Error', msg, [], 'error', 'sticky'));
            });
    }
}