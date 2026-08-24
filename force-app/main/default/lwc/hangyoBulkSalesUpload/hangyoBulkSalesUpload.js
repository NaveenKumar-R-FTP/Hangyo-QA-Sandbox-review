import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import hasBulkUploadAccess from '@salesforce/apex/HangyoBulkSalesUploadController.hasBulkUploadAccess';
import validateBulkUpload from '@salesforce/apex/HangyoBulkSalesUploadController.validateBulkUpload';
import saveBulkUpload from '@salesforce/apex/HangyoBulkSalesUploadController.saveBulkUpload';
import saveBulkUploadWithUpdateSupport from '@salesforce/apex/HangyoBulkSalesUploadController.saveBulkUploadWithUpdateSupport';
import checkExistingReferences from '@salesforce/apex/HangyoBulkSalesUploadController.checkExistingReferences';
import downloadUploadTemplate from '@salesforce/apex/HangyoBulkSalesUploadController.downloadUploadTemplate';

const ACCEPTED_EXTENSIONS = ['.xlsx', '.xls'];
const UPLOAD_TYPE_ORDER = 'Order';
const UPLOAD_TYPE_INVOICE = 'Invoice';
const UNAUTHORIZED_MESSAGE =
    'You are not authorized for bulk upload. Contact your Hangyo administrator.';

export default class HangyoBulkSalesUpload extends NavigationMixin(LightningElement) {
    @track selectedUploadType = '';
    @track selectedFileName = '';
    @track clientValidationMessage = '';
    @track showUploadResult = false;
    @track activeResultTab = 'errors';
    @track validationErrors = [];
    @track uploadSuccess = null;
    @track groupedSummaries = [];
    @track isValidating = false;
    @track isSaving = false;
    @track showFileInput = true;
    @track hasAccess = false;
    @track isAccessChecking = true;
    @track isDownloadingTemplate = false;

    // Duplicate reference confirmation modal state (new requirement)
    @track showDuplicateModal = false;
    @track duplicateRefsMessage = '';
    @track duplicateRefsList = [];
    @track isCheckingDuplicates = false;

    uploadedFile = null;
    pendingBase64Data = null;
    _navGapAdjusted = false;

    uploadTypeOptions = [
        { label: 'Order', value: UPLOAD_TYPE_ORDER },
        { label: 'Invoice', value: UPLOAD_TYPE_INVOICE }
    ];

    connectedCallback() {
        if (isExperienceCloudSite()) {
            this.classList.add('experienceCloudFlush');
        }
        this.verifyBulkUploadAccess();
    }

    renderedCallback() {
        this.flushNavigationGap();
    }

    flushNavigationGap() {
        if (this._navGapAdjusted || !this.showContent || !isExperienceCloudSite()) {
            return;
        }

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            const header = this.template.querySelector('.dashHeader');
            if (!header) {
                return;
            }

            const nav =
                document.querySelector('.comm-navigation') ||
                document.querySelector('nav.comm-navigation') ||
                document.querySelector('.themeHeader') ||
                document.querySelector('header[role="banner"]');

            let gapPx = 20;
            if (nav) {
                const measuredGap =
                    header.getBoundingClientRect().top - nav.getBoundingClientRect().bottom;
                if (measuredGap > 0.5) {
                    gapPx = Math.ceil(measuredGap);
                } else {
                    this._navGapAdjusted = true;
                    return;
                }
            }

            this.template.host.style.marginTop = `-${gapPx}px`;
            this._navGapAdjusted = true;
        });
    }

    get showContent() {
        return this.hasAccess && !this.isAccessChecking;
    }

    async verifyBulkUploadAccess() {
        try {
            const allowed = await hasBulkUploadAccess();
            if (!allowed) {
                this.handleUnauthorizedAccess();
                return;
            }
            this.hasAccess = true;
        } catch (error) {
            this.handleUnauthorizedAccess();
        } finally {
            this.isAccessChecking = false;
        }
    }

    handleUnauthorizedAccess() {
        this.hasAccess = false;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Access Denied',
                message: UNAUTHORIZED_MESSAGE,
                variant: 'error',
                mode: 'sticky'
            })
        );
        this.navigateToHome();
    }

    navigateToHome() {
        if (isExperienceCloudSite()) {
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: {
                    name: 'Home'
                }
            });
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'home'
            }
        });
    }

    get hasValidFile() {
        return Boolean(this.uploadedFile);
    }

    get fileDisplayText() {
        return this.selectedFileName || 'Upload the file here';
    }

    get fileTextClass() {
        return this.hasValidFile ? 'fileNameText' : 'filePlaceholderText';
    }

    get isNextDisabled() {
        return !this.selectedUploadType || !this.uploadedFile || this.isValidating || this.isSaving;
    }

    get isSaveDisabled() {
        return (
            (!this.isOrderUpload && !this.isInvoiceUpload) ||
            this.hasValidationErrors ||
            !this.uploadSuccess?.validationPassed ||
            !this.uploadedFile ||
            this.isValidating ||
            this.isSaving ||
            this.isCheckingDuplicates
        );
    }

    get saveButtonLabel() {
        if (this.isCheckingDuplicates) {
            return 'Checking...';
        }
        return this.isSaving ? 'Saving...' : 'Save';
    }

    get nextButtonLabel() {
        return this.isValidating ? 'Validating...' : 'Next';
    }

    get errorCount() {
        return this.validationErrors.length;
    }

    get hasValidationErrors() {
        return this.errorCount > 0;
    }

    get isErrorsTabActive() {
        return this.activeResultTab === 'errors';
    }

    get isSuccessTabActive() {
        return this.activeResultTab === 'success';
    }

    get errorsTabClass() {
        return this.isErrorsTabActive
            ? 'resultTab resultTab_active resultTab_errors'
            : 'resultTab';
    }

    get successTabClass() {
        return this.isSuccessTabActive
            ? 'resultTab resultTab_active resultTab_success'
            : 'resultTab';
    }

    get isOrderUpload() {
        return this.uploadSuccess?.recordType === UPLOAD_TYPE_ORDER;
    }

    get isInvoiceUpload() {
        return this.uploadSuccess?.recordType === UPLOAD_TYPE_INVOICE;
    }

    get hasGroupedSummaries() {
        return this.groupedSummaries.length > 0;
    }

    get successSummaryText() {
        if (!this.uploadSuccess) {
            return '';
        }

        const { recordType, headerCount, lineItemCount, validationPassed } =
            this.uploadSuccess;
        const recordLabel = recordType === UPLOAD_TYPE_INVOICE ? 'Invoices' : 'Orders';
        const lineLabel =
            recordType === UPLOAD_TYPE_INVOICE
                ? 'Invoice Line Items'
                : 'Order Line Items';

        if (validationPassed) {
            return `Validation successful. ${headerCount} ${recordLabel} and ${lineItemCount} ${lineLabel} are ready for upload.`;
        }

        return `${headerCount} ${recordLabel} and ${lineItemCount} ${lineLabel} have been processed successfully.`;
    }

    get isDownloadDisabled() {
        return !this.selectedUploadType || this.isDownloadingTemplate || this.isValidating || this.isSaving;
    }

    get downloadButtonLabel() {
        return this.isDownloadingTemplate ? 'Downloading...' : 'Download Format';
    }

    get hasDuplicateRefs() {
        return this.duplicateRefsList.length > 0;
    }

    handleUploadTypeChange(event) {
        this.selectedUploadType = event.target.value;
        this.clientValidationMessage = '';
        this.clearValidationResults();
    }

    handleChooseFileClick(event) {
        event.preventDefault();
        const fileInput = this.template.querySelector('[data-id="bulk-file-input"]');
        if (fileInput) {
            fileInput.click();
        }
    }

    handleFileChange(event) {
        const files = event.target.files;
        this.clientValidationMessage = '';
        this.clearValidationResults();

        if (!files || files.length === 0) {
            this.clearSelectedFile();
            return;
        }

        const file = files[0];
        if (!this.isAcceptedFile(file)) {
            this.clearSelectedFile(event.target);
            this.clientValidationMessage =
                'Invalid file format. Only .xlsx and .xls files are accepted.';
            return;
        }

        this.uploadedFile = file;
        this.selectedFileName = file.name;
    }

    async handleDownloadFormat() {
        this.clientValidationMessage = '';

        if (!this.selectedUploadType) {
            this.clientValidationMessage =
                'Please select an upload type (Order or Invoice) before downloading the format.';
            return;
        }

        this.isDownloadingTemplate = true;

        try {
            const result = await downloadUploadTemplate({
                uploadType: this.selectedUploadType
            });
            this.triggerFileDownload(result.base64Data, result.fileName);
        } catch (error) {
            this.clientValidationMessage =
                error?.body?.message ||
                error?.message ||
                'Unable to download the template. Please try again.';
        } finally {
            this.isDownloadingTemplate = false;
        }
    }

    triggerFileDownload(base64Data, fileName) {
        try {
            const byteCharacters = atob(base64Data);
            const byteNumbers = new Array(byteCharacters.length);
            for (let i = 0; i < byteCharacters.length; i++) {
                byteNumbers[i] = byteCharacters.charCodeAt(i);
            }
            const byteArray = new Uint8Array(byteNumbers);

            // Lightning Web Security only allows a limited Blob MIME allow-list;
            // the OOXML spreadsheet type is not on it. 'application/octet-stream'
            // is allowed, and the .xlsx filename extension (set below) is what
            // determines how the OS/Excel treats the downloaded file.
            const fileBlob = new Blob([byteArray], { type: 'application/octet-stream' });

            const downloadUrl = URL.createObjectURL(fileBlob);
            const anchor = document.createElement('a');
            anchor.href = downloadUrl;
            anchor.download = fileName;
            anchor.style.display = 'none';
            document.body.appendChild(anchor);
            anchor.click();
            document.body.removeChild(anchor);
            URL.revokeObjectURL(downloadUrl);
        } catch (error) {
            this.clientValidationMessage =
                'Unable to prepare the file for download. Please try again.';
        }
    }

    async handleNext() {
        this.clientValidationMessage = '';

        if (!this.selectedUploadType) {
            this.clientValidationMessage =
                'Please select an upload type (Order or Invoice).';
            return;
        }

        if (!this.uploadedFile) {
            this.clientValidationMessage = 'Please choose a file to upload.';
            return;
        }

        if (!this.isAcceptedFile(this.uploadedFile)) {
            this.clientValidationMessage =
                'Invalid file format. Only .xlsx and .xls files are accepted.';
            return;
        }

        this.isValidating = true;
        this.showUploadResult = false;

        try {
            const base64Data = await this.readFileAsBase64(this.uploadedFile);
            const result = await validateBulkUpload({
                uploadType: this.selectedUploadType,
                fileName: this.uploadedFile.name,
                base64Data
            });
            this.handleUploadResponse(result);
        } catch (error) {
            this.clientValidationMessage =
                error?.body?.message ||
                error?.message ||
                'Bulk upload validation failed. Please try again.';
        } finally {
            this.isValidating = false;
        }
    }

    /**
     * Save flow (new requirement):
     * 1. Check whether any reference numbers in the file already exist (Order/Invoice).
     * 2. If none exist -> proceed exactly as before (pure insert via saveBulkUploadWithUpdateSupport,
     *    which behaves identically to the original saveBulkUpload in this case).
     * 3. If duplicates exist -> show a confirmation modal. Cancel aborts with no DML.
     *    Confirm proceeds with mixed insert/update in a single transaction.
     */
    async handleSave() {
        this.clientValidationMessage = '';

        if (!this.isOrderUpload && !this.isInvoiceUpload) {
            this.clientValidationMessage =
                'Save is only available for Order or Invoice upload type.';
            return;
        }

        if (!this.uploadSuccess?.validationPassed) {
            this.clientValidationMessage =
                'Please validate the file successfully before saving.';
            return;
        }

        if (!this.uploadedFile) {
            this.clientValidationMessage = 'Please choose a file to upload.';
            return;
        }

        this.isCheckingDuplicates = true;

        try {
            const base64Data = await this.readFileAsBase64(this.uploadedFile);
            this.pendingBase64Data = base64Data;

            const dupCheck = await checkExistingReferences({
                uploadType: this.selectedUploadType,
                fileName: this.uploadedFile.name,
                base64Data
            });

            if (dupCheck?.hasValidationErrors) {
                this.clientValidationMessage =
                    'The file no longer passes validation. Please click Next again before saving.';
                this.pendingBase64Data = null;
                return;
            }

            if (dupCheck?.hasDuplicates) {
                this.duplicateRefsList = dupCheck.duplicateRefs || [];
                const recordLabel = this.isInvoiceUpload ? 'Invoice(s)' : 'Order(s)';
                this.duplicateRefsMessage =
                    `The following ${recordLabel} already exist in the system with the same ` +
                    `reference number: ${this.duplicateRefsList.join(', ')}. ` +
                    `Do you want to modify them?`;
                this.showDuplicateModal = true;
                return;
            }

            // No duplicates — proceed exactly like the original insert-only save.
            await this.performSave(false);
        } catch (error) {
            this.clientValidationMessage =
                error?.body?.message ||
                error?.message ||
                'Bulk upload save failed. Please try again.';
            this.pendingBase64Data = null;
        } finally {
            this.isCheckingDuplicates = false;
        }
    }

    handleDuplicateModalCancel() {
        this.showDuplicateModal = false;
        this.duplicateRefsList = [];
        this.duplicateRefsMessage = '';
        this.pendingBase64Data = null;
        this.clientValidationMessage =
            'Upload cancelled — duplicate reference number(s) were found and no changes were saved.';
    }

    async handleDuplicateModalConfirmSave() {
        this.showDuplicateModal = false;
        await this.performSave(true);
    }

    async performSave(confirmedUpdateExisting) {
        if (!this.pendingBase64Data) {
            this.clientValidationMessage = 'Please choose a file to upload.';
            return;
        }

        this.isSaving = true;

        try {
            const result = await saveBulkUploadWithUpdateSupport({
                uploadType: this.selectedUploadType,
                fileName: this.uploadedFile.name,
                base64Data: this.pendingBase64Data,
                confirmedUpdateExisting
            });

            if (result?.status === 'DuplicatesFound') {
                // Should not normally happen since we already confirmed, but handle defensively.
                this.duplicateRefsList = (result.errors || []).map((e) => e.errorMessage);
                this.duplicateRefsMessage =
                    'The following reference(s) already exist. Do you want to modify them?';
                this.showDuplicateModal = true;
                return;
            }

            if (result?.errors?.length) {
                this.handleUploadResponse(result);
                this.clientValidationMessage =
                    result.status === 'PartialFailure'
                        ? 'Some records could not be saved. Please review the errors below.'
                        : this.isInvoiceUpload
                            ? 'Invoice save failed validation. Please review the errors.'
                            : 'Order save failed validation. Please review the errors.';
                return;
            }

            if (this.isInvoiceUpload) {
                const invoiceCount = result?.invoicesCreated || 0;
                const invoiceNames = (result?.createdInvoiceNames || []).join(', ');
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message:
                            invoiceCount === 1
                                ? `Invoice ${invoiceNames} processed successfully.`
                                : `${invoiceCount} invoice(s) processed successfully: ${invoiceNames}`,
                        variant: 'success'
                    })
                );
            } else {
                const orderCount = result?.ordersCreated || 0;
                const orderNames = (result?.createdOrderNames || []).join(', ');
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message:
                            orderCount === 1
                                ? `Order ${orderNames} processed successfully.`
                                : `${orderCount} order(s) processed successfully: ${orderNames}`,
                        variant: 'success'
                    })
                );
            }

            this.resetUpload();
        } catch (error) {
            this.clientValidationMessage =
                error?.body?.message ||
                error?.message ||
                (this.isInvoiceUpload
                    ? 'Bulk invoice save failed. Please try again.'
                    : 'Bulk order save failed. Please try again.');
        } finally {
            this.isSaving = false;
            this.pendingBase64Data = null;
            this.duplicateRefsList = [];
            this.duplicateRefsMessage = '';
        }
    }

    readFileAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => {
                const result = reader.result;
                if (typeof result === 'string') {
                    const commaIndex = result.indexOf(',');
                    resolve(
                        commaIndex > -1 ? result.substring(commaIndex + 1) : result
                    );
                    return;
                }
                reject(new Error('Unable to read the selected file.'));
            };
            reader.onerror = () => reject(reader.error);
            reader.readAsDataURL(file);
        });
    }

    /**
     * Call from parent or Apex imperative callback with server response.
     * @param {Object} result
     * @param {Array} result.errors - { rowNo, columnName, errorMessage }
     * @param {Object} result.success - { recordType, headerCount, lineItemCount }
     */
    @api
    handleUploadResponse(result) {
        const errors = (result?.errors || []).map((err, index) => ({
            key: `err-${index}-${err.rowNo}`,
            rowNo: err.rowNo,
            columnName: err.columnName,
            errorMessage: err.errorMessage
        }));

        this.validationErrors = errors;
        this.uploadSuccess = result?.success || null;
        this.groupedSummaries = this.buildGroupedSummaries(result?.success?.groups);
        this.showUploadResult = true;
        this.activeResultTab =
            errors.length > 0 ? 'errors' : 'success';
    }

    handleClear() {
        this.resetUpload();
    }

    clearValidationResults() {
        this.showUploadResult = false;
        this.validationErrors = [];
        this.uploadSuccess = null;
        this.groupedSummaries = [];
        this.activeResultTab = 'errors';
    }

    @api
    resetUpload() {
        this.clearValidationResults();
        this.clientValidationMessage = '';
        this.selectedUploadType = '';
        this.uploadedFile = null;
        this.selectedFileName = '';
        this.isValidating = false;
        this.isSaving = false;
        this.isCheckingDuplicates = false;
        this.showDuplicateModal = false;
        this.duplicateRefsList = [];
        this.duplicateRefsMessage = '';
        this.pendingBase64Data = null;

        const fileInput = this.template.querySelector('[data-id="bulk-file-input"]');
        this.clearSelectedFile(fileInput);

        this.showFileInput = false;
        Promise.resolve().then(() => {
            this.showFileInput = true;
        });

        const uploadTypeSelect = this.template.querySelector(
            '[data-id="upload-type-select"]'
        );
        if (uploadTypeSelect) {
            uploadTypeSelect.value = '';
        }
    }

    handleErrorsTab() {
        this.activeResultTab = 'errors';
    }

    handleSuccessTab() {
        this.activeResultTab = 'success';
    }

    buildGroupedSummaries(groups) {
        return (groups || []).map((group, groupIndex) => ({
            key: `group-${groupIndex}-${group.refNo}`,
            serialNo: groupIndex + 1,
            refNo: group.refNo,
            orderDate: group.orderDate || '',
            invoiceDate: group.invoiceDate || '',
            retailerName: group.retailerName || '',
            orderNumber: group.orderNumber || '',
            totalQuantity: group.totalQuantity,
            status: group.status || '',
            formattedGrandTotal: this.formatAmount(group.grandTotal),
            formattedTotalGst: this.formatAmount(group.totalGst),
            isExpanded: false,
            expandIcon: 'utility:chevronright',
            lineItems: (group.lineItems || []).map((line, lineIndex) =>
                this.formatLineItem(line, groupIndex, lineIndex)
            )
        }));
    }

    formatLineItem(line, groupIndex, lineIndex) {
        return {
            key: `line-${groupIndex}-${lineIndex}`,
            serialNo: lineIndex + 1,
            productCode: line.productCode || '',
            productName: line.productName || '',
            quantity: line.quantity,
            formattedPrice: this.formatAmount(line.price),
            formattedAmount: this.formatAmount(line.amount),
            formattedTod: this.formatAmount(line.tod),
            formattedDiscountPercent: this.formatAmount(line.discountPercent),
            formattedDiscountAmount: this.formatAmount(line.discountAmount),
            formattedTaxableAmount: this.formatAmount(line.taxableAmount),
            formattedTotalGst: this.formatAmount(line.totalGst),
            formattedTotalAmountInclTax: this.formatAmount(line.totalAmountInclTax)
        };
    }

    formatAmount(value) {
        const amount = value === null || value === undefined ? 0 : Number(value);
        return amount.toFixed(2);
    }

    handleToggleGroup(event) {
        const groupKey = event.currentTarget.dataset.key;
        this.groupedSummaries = this.groupedSummaries.map((group) => {
            if (group.key !== groupKey) {
                return group;
            }

            const isExpanded = !group.isExpanded;
            return {
                ...group,
                isExpanded,
                expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright'
            };
        });
    }

    isAcceptedFile(file) {
        if (!file?.name) {
            return false;
        }

        const lowerName = file.name.toLowerCase();
        return ACCEPTED_EXTENSIONS.some((ext) => lowerName.endsWith(ext));
    }

    clearSelectedFile(fileInput) {
        this.uploadedFile = null;
        this.selectedFileName = '';

        if (fileInput) {
            fileInput.value = '';
        }
    }
}

function isExperienceCloudSite() {
    const path = window.location.pathname || '';
    const host = window.location.hostname || '';
    return path.includes('/s/') || host.includes('.site.');
}