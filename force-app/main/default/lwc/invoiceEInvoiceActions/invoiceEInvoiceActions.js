// Added by Hari - E-Invoice / E-Way Bill action buttons LWC for Invoice Detail page
import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import IRN_FIELD from '@salesforce/schema/Invoice__c.IRN_Number__c';
import EWB_NUMBER_FIELD from '@salesforce/schema/Invoice__c.EWB__c';
import STATUS_FIELD from '@salesforce/schema/Invoice__c.Status__c';
import getInvoiceEInvoiceFields from '@salesforce/apex/InvoiceEInvoiceController.getInvoiceEInvoiceFields';
import generateEInvoice from '@salesforce/apex/InvoiceEInvoiceController.generateEInvoice';
import generateEWayBill from '@salesforce/apex/InvoiceEInvoiceController.generateEWayBill';
import getEInvoicePdfContentDocumentId from '@salesforce/apex/InvoiceEInvoiceController.getEInvoicePdfContentDocumentId';
import getEwayBillPdfContentDocumentId from '@salesforce/apex/InvoiceEInvoiceController.getEwayBillPdfContentDocumentId';
import getCygnetPdfAttachmentFlags from '@salesforce/apex/InvoiceEInvoiceController.getCygnetPdfAttachmentFlags';

const FIELDS = [IRN_FIELD, EWB_NUMBER_FIELD, STATUS_FIELD];

export default class InvoiceEInvoiceActions extends LightningElement {
    @api recordId;
    @track _recordIdFromUrl = null; // Added by Hari - fallback when recordId not passed by page
    @track irn = '';
    @track ewbNumber = '';
    @track statusApproved = false;
    @track isLoading = false;
    @track _dataLoaded = false;
    // Added by hari - True when a linked ContentDocument title matches Cygnet E-Invoice / E-Way Bill PDF (hide download buttons)
    @track hasEInvoicePdfFile = false;
    @track hasEwayBillPdfFile = false;

    // Added by Hari - Use recordId from page or from URL (Experience Cloud, same as invoiceCollection)
    get effectiveRecordId() {
        return this.recordId || this._recordIdFromUrl;
    }

    // Added by Hari - Fallback: get recordId from query string or from URL path (e.g..../invoice/a0SBg00000150M5MAM/...)
    connectedCallback() {
        const queryParams = new URLSearchParams(window.location.search);
        let idFromUrl = queryParams.get('recordId');
        if (!idFromUrl && typeof window !== 'undefined' && window.location && window.location.pathname) {
            const path = window.location.pathname;
            const parts = path.split('/').filter(Boolean);
            const invoiceIdx = parts.indexOf('invoice');
            if (invoiceIdx >= 0 && parts.length > invoiceIdx + 1) {
                const segment = parts[invoiceIdx + 1];
                if (/^[a-zA-Z0-9]{15}$|^[a-zA-Z0-9]{18}$/.test(segment)) {
                    idFromUrl = segment;
                }
            }
        }
        if (idFromUrl) this._recordIdFromUrl = idFromUrl;
    }

    // Added by Hari - Load IRN_Number__c and EWB__c for visibility logic
    @wire(getRecord, { recordId: '$effectiveRecordId', fields: FIELDS })
    wiredRecord({ error, data }) {
        if (data) {
            this.irn = getFieldValue(data, IRN_FIELD) != null ? String(getFieldValue(data, IRN_FIELD)) : '';
            this.ewbNumber = getFieldValue(data, EWB_NUMBER_FIELD) != null ? String(getFieldValue(data, EWB_NUMBER_FIELD)) : '';
            const status = getFieldValue(data, STATUS_FIELD);
            // Added by Hari - Button visibility on delivered status
            const s = status != null ? String(status).toLowerCase() : '';
            this.statusApproved = s === 'confirmed' || s === 'delivered';
            this._dataLoaded = true;
            this.loadPdfAttachmentFlags();
        }
        if (error) {
            this._dataLoaded = true;
            this.showToast('Error', 'Could not load invoice fields.', 'error');
        }
    }

    // Added by hari - Refresh flags from Files (ContentDocumentLink) for download button visibility
    async loadPdfAttachmentFlags() {
        const id = this.effectiveRecordId;
        if (!id) return;
        try {
            const flags = await getCygnetPdfAttachmentFlags({ invoiceId: id });
            this.hasEInvoicePdfFile = !!(flags && flags.hasEInvoicePdf === true);
            this.hasEwayBillPdfFile = !!(flags && flags.hasEwayBillPdf === true);
        } catch (e) {
            this.hasEInvoicePdfFile = false;
            this.hasEwayBillPdfFile = false;
        }
    }

    // Added by Hari - Button visibility on delivered status (Confirmed or Delivered)
    get showGenerateEInvoice() {
        return this._dataLoaded && this.statusApproved && !this.irn;
    }

    get showDownloadEInvoicePdf() {
        // Required workflow: show BOTH download buttons only after E-Way Bill is generated.
        return this._dataLoaded && this.statusApproved && !!this.irn && !!this.ewbNumber && !this.hasEInvoicePdfFile;
    }

    get showGenerateEWayBill() {
        return this._dataLoaded && this.statusApproved && !!this.irn && !this.ewbNumber;
    }

    get showDownloadEWayBillPdf() {
        return this._dataLoaded && this.statusApproved && !!this.ewbNumber && !this.hasEwayBillPdfFile;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    // Added by Hari - Generate E-Invoice action (calls Apex for integration)
    async handleGenerateEInvoice() {
        const id = this.effectiveRecordId;
        if (!id || this.isLoading) return;
        this.isLoading = true;
        try {
            await generateEInvoice({ invoiceId: id });
            this.showToast('Success', 'Successful validation. E-Invoice generation started. Please refresh the page in a few seconds to see the result.', 'success');
            await this.refreshInvoiceData();
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Failed to generate E-Invoice.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Added by Hari - Download E-Invoice PDF: trigger export/attach via Apex; stay on page — toast only (no new tab)
    async handleDownloadEInvoicePdf() {
        const id = this.effectiveRecordId;
        if (!id) return;
        try {
            const contentDocId = await getEInvoicePdfContentDocumentId({ invoiceId: id });
            if (contentDocId) {
                this.showToast(
                    'E-Invoice PDF',
                    'Your E-Invoice PDF is being downloaded and will be attached to the Files section shortly. Please refresh the page.',
                    'success'
                );
                await this.loadPdfAttachmentFlags();
            } else {
                this.showToast('Error', 'Could not get E-Invoice PDF.', 'error');
            }
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Failed to download E-Invoice PDF.', 'error');
        }
    }

    // Added by Hari - Generate E-Way Bill action (calls Apex for integration)
    async handleGenerateEWayBill() {
        const id = this.effectiveRecordId;
        if (!id || this.isLoading) return;
        this.isLoading = true;
        try {
            await generateEWayBill({ invoiceId: id });
            this.showToast('Success', 'Successful validation. E-Way Bill generation started. Please refresh the page in a few seconds to see the result.', 'success');
            await this.refreshInvoiceData();
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Failed to generate E-Way Bill.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Added by Hari - Download E-Way Bill PDF: same UX as E-Invoice — toast only, no new tab
    async handleDownloadEWayBillPdf() {
        const id = this.effectiveRecordId;
        if (!id) return;
        try {
            const contentDocId = await getEwayBillPdfContentDocumentId({ invoiceId: id });
            if (contentDocId) {
                this.showToast(
                    'E-Way Bill PDF',
                    'Your E-Way Bill PDF is being downloaded and will be attached to the Files section shortly. Please refresh the page.',
                    'success'
                );
                await this.loadPdfAttachmentFlags();
            } else {
                this.showToast('Error', 'Could not get E-Way Bill PDF.', 'error');
            }
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Failed to download E-Way Bill PDF.', 'error');
        }
    }

    // Added by Hari - Refresh IRN/EWB after generate so button visibility updates
    async refreshInvoiceData() {
        const id = this.effectiveRecordId;
        if (!id) return;
        try {
            const data = await getInvoiceEInvoiceFields({ invoiceId: id });
            if (data) {
                this.irn = data.irn || '';
                this.ewbNumber = data.ewbNumber || '';
                this.statusApproved = data.statusApproved === true;
            }
            await this.loadPdfAttachmentFlags();
        } catch (e) {
            // Optional: re-wire or leave as is
        }
    }
}