// Full pipeline walkthrough test - Arul - 5 Aug 2026
import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCaseTypes from '@salesforce/apex/CaseScreenController.getCaseTypes';
import getCases from '@salesforce/apex/CaseScreenController.getCases';
import getDynamicFields from '@salesforce/apex/CaseScreenController.getDynamicFields';
import saveCase from '@salesforce/apex/CaseScreenController.saveCase';
import getCaseFields from '@salesforce/apex/CaseScreenController.getCaseFields';
import uploadFiles from '@salesforce/apex/CaseScreenController.uploadFiles';
import getDistributorId from '@salesforce/apex/CaseScreenController.getDistributorId';
import getAssets from '@salesforce/apex/CaseScreenController.getAssets';
import checkNewAssetCode from '@salesforce/apex/CaseScreenController.checkNewAssetCode';
import getAssetsByAccount from '@salesforce/apex/CaseScreenController.getAssetsByAccount';
import getRetailersByUser from '@salesforce/apex/CaseScreenController.getRetailersByUser';
import getDistributorsByUser from '@salesforce/apex/CaseScreenController.getDistributorsByUser';
import checkAssetCodeInMaster from '@salesforce/apex/CaseScreenController.checkAssetCodeInMaster';
import { getBarcodeScanner } from 'lightning/mobileCapabilities';
import checkSerialNumber from '@salesforce/apex/CaseScreenController.checkSerialNumber';
import submitInstallation from '@salesforce/apex/CaseScreenController.submitInstallation';
import getMediaLineOptions from '@salesforce/apex/CaseScreenController.getMediaLineOptions';
import getAccountRecordType from '@salesforce/apex/CaseScreenController.getAccountRecordType';
import saveCaseWithLines from '@salesforce/apex/CaseScreenController.saveCaseWithLines';
import getRetailerBrandingAssets from '@salesforce/apex/CaseScreenController.getRetailerBrandingAssets';
import hasPendingReturnCase from '@salesforce/apex/CaseScreenController.hasPendingReturnCase';
import USER_ID from '@salesforce/user/Id';

// Statuses shown under the completed tab. Kept in sync with
// CaseScreenController.COMPLETED_STATUSES. Lowercase for case-insensitive match.
const COMPLETED_STATUSES = ['approved', 'installation pending', 'installed', 'completed', 'closed'];
const INSTALLATION_PENDING = 'installation pending';
// One photo only - for the case request and for the installation proof.
const MAX_PHOTOS = 1;
// OEM / asset code length bounds, inclusive.
const MIN_ASSET_CODE_LENGTH = 13;
const MAX_ASSET_CODE_LENGTH = 20;
// Case type that captures several media items instead of a single one.
const INVENTORY_CASE_TYPE = 'Branding & Marketing Asset Inventory Management';
// Old transfer type, repurposed as the Branding Return Case.
const RETURN_CASE_TYPE = 'Branding & Marketing Asset transfer Request';

export default class CaseScreen extends LightningElement {
    @api visitTaskId;
    @api isCheckInDone;
    @api distributorId;
    @track selectedTab = 'Open';
    @track searchKey = '';
    @track showPopup = false;
    @track searchType = '';
    @track selectedType = '';
    @track selectedTypeLabel = '';
    @track showTypeDropdown = false;
    @track isFormScreen = false;
    @track caseTypes = [];
    @track cases = [];
    @track isDetailScreen = false;
    @track isHideAddIcon = true;
    @track selectedCase = {};
    @track caseFieldsArray = [];
    @track dynamicFields = [];
    @track formData = {};
    @track uploadedFiles = [];
    @track installImages = [];
    @track installError = '';
    @track mediaLines = [];
    @track mediaTypeOptions = [];
    @track mediaSubTypeOptions = [];
    @track mediaLineError = '';
    @track fileError = '';
    @track isSubmitting = false;
    @track isLoading = false;
    caseId;
    @track isRefreshing = false;
@track typeSearchQuery = '';
    @track userRetailers = [];
    @track userDistributors = [];
    @track showNewAssetScanPopup = false;
    @track showSerialScanPopup = false;
    scanner;
    _retailerId;

    /**
     * A record page hands the component one account id with no indication of its
     * type, so a distributor used to land in retailerId and show up in the Retailer
     * field. Resolve the record type and route it to the right context instead of
     * trusting which property it arrived in.
     */
    @api
    set retailerId(value) {
        this._retailerId = value;
        if (value) this.resolveAccountContext(value);
    }
    get retailerId() {
        return this._retailerId;
    }

    async resolveAccountContext(accountId) {
        try {
            const recordType = await getAccountRecordType({ accountId });
            if (recordType === 'Distributor' || recordType === 'SuperStockist') {
                // Not a retailer - move it across so it renders in Distributor.
                this._retailerId = null;
                this.distributorId = accountId;
                this.formData = { ...this.formData, Distributor__c: accountId };
                return;
            }
            // Retailer (or unknown): keep it and derive its distributor.
            this.fetchDistributor(accountId, 'Distributor__c');
        } catch (error) {
            // Fall back to the previous behaviour rather than blocking the form.
            this.fetchDistributor(accountId, 'Distributor__c');
        }
    }

    // ================= INIT =================
    connectedCallback() {
        this.loadCases();
        this.loadCaseTypes();
        if (!this.visitTaskId) {
            this.loadUserRetailersAndDistributors();
        }
        this.scanner = getBarcodeScanner();
    }

    // ================= LOAD USER RETAILERS AND DISTRIBUTORS =================
    async loadUserRetailersAndDistributors() {
        try {
            const [retailers, distributors] = await Promise.all([
                getRetailersByUser(),
                getDistributorsByUser()
            ]);
            this.userRetailers = retailers || [];
            this.userDistributors = distributors || [];
        } catch (error) {}
    }

    // ================= COMMON ERROR =================
    showError(title, error) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message: error?.body?.message || error?.message || 'Unknown error',
            variant: 'error'
        }));
    }

    // ================= LOAD CASES =================
    async loadCases() {
        try {
            this.isLoading = true;
            const result = await getCases({ visitTaskId: this.visitTaskId });
            if (!result || result.length === 0) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Warning',
                    message: 'Cases are not Found',
                    variant: 'Warning'
                }));
                this.isLoading = false;
                return;
            }
            setTimeout(() => {
                this.cases = result.map(rec => {
                    let retailers = [];
                    let statusValue = rec.Status__c ? rec.Status__c.trim() : '';
                    if (rec.Retailer__r && rec.Retailer__r.Name) {
                        retailers.push({ label: 'Retailer', value: rec.Retailer__r.Name });
                    }
                    if (rec.Retailer_Transfer_From__r && rec.Retailer_Transfer_From__r.Name) {
                        retailers.push({ label: 'From', value: rec.Retailer_Transfer_From__r.Name });
                    }
                    if (rec.Retailer_Transfer_To__r && rec.Retailer_Transfer_To__r.Name) {
                        retailers.push({ label: 'To', value: rec.Retailer_Transfer_To__r.Name });
                    }
                    return {
                        id: rec.Id,
                        caseNumber: rec.Name,
                        type: rec.Case_Type__r ? rec.Case_Type__r.Name : '',
                        retailers: retailers,
                        createdBy: rec.CreatedBy ? rec.CreatedBy.Name : '',
                        createdById: rec.CreatedById,
                        status: statusValue,
                        tabstatus: COMPLETED_STATUSES.includes(statusValue.toLowerCase()) ? 'Approved' : 'Open',
                        statusClass: this.getStatusClass(statusValue)
                    };
                });
                this.isRefreshing = false;
            }, 0);
            this.isLoading = false;
        } catch (error) {
            this.isRefreshing = false;
            this.isLoading = false;
            this.showError('Error fetching cases', error);
        }
    }

    // ================= LOAD CASE TYPES =================
    async loadCaseTypes() {
        try {
            let types = await getCaseTypes();
            if (!this.visitTaskId) {
                types = types.filter(t =>
                    t.label !== 'Existing outlet Asset Code Change Request' &&
                    t.label !== 'Asset Tagging Request'
                );
            }
            this.caseTypes = types;
        } catch (error) {
            this.showError('Error fetching case types', error);
        }
    }

    // ================= BRANDING RETURN CASE =================
    @track brandingAssetOptions = [];
    @track selectedBrandingAssetId = '';
    @track brandingAssetError = '';
    brandingAssetsById = {};

    get isReturnCaseType() {
        return this.selectedTypeLabel === RETURN_CASE_TYPE;
    }

    async loadRetailerBrandingAssets() {
        this.brandingAssetOptions = [];
        this.selectedBrandingAssetId = '';
        this.brandingAssetError = '';
        this.brandingAssetsById = {};
        if (!this.retailerId) {
            this.brandingAssetError = 'No retailer on this case - branding assets cannot be listed.';
            return;
        }
        try {
            const assets = await getRetailerBrandingAssets({ retailerId: this.retailerId });
            this.brandingAssetsById = {};
            this.brandingAssetOptions = (assets || []).map(a => {
                this.brandingAssetsById[a.Id] = a;
                // "Asset ID - Media Type - Sub Media"
                return {
                    label: [a.Name, a.Media_Type__c, a.Media_Sub_Type__c].filter(Boolean).join(' - '),
                    value: a.Id
                };
            });
            if (this.brandingAssetOptions.length === 0) {
                this.brandingAssetError = 'This outlet has no active branding assets to return.';
            }
        } catch (error) {
            this.brandingAssetError = (error.body && error.body.message) || 'Could not load branding assets.';
        }
    }

    async handleBrandingAssetChange(event) {
        const assetId = event.detail.value;
        this.selectedBrandingAssetId = assetId;
        this.brandingAssetError = '';

        const asset = this.brandingAssetsById[assetId];
        if (!asset) return;

        // Branding_Asset__c.Media_Sub_Type__c -> Case__c.Media_Sub_type__c (lowercase t)
        this.formData = {
            ...this.formData,
            Branding_Asset__c: asset.Id,
            Asset_ID__c: asset.Name,
            Media_Type__c: asset.Media_Type__c,
            Media_Sub_type__c: asset.Media_Sub_Type__c
        };

        try {
            const pending = await hasPendingReturnCase({ brandingAssetId: assetId });
            if (pending) {
                this.brandingAssetError = 'A pending return case already exists for this asset';
                this.selectedBrandingAssetId = '';
                this.formData = {
                    ...this.formData,
                    Branding_Asset__c: null, Asset_ID__c: null,
                    Media_Type__c: null, Media_Sub_type__c: null
                };
            }
        } catch (error) {
            this.brandingAssetError = (error.body && error.body.message) || 'Could not check for existing return cases.';
        }
    }

    // ================= MEDIA LINES (Inventory Management) =================
    get isInventoryCaseType() {
        return this.selectedTypeLabel === INVENTORY_CASE_TYPE;
    }

    // Lines are rendered from this, with the index baked in so each row can
    // identify itself on change/remove.
    get mediaLinesForDisplay() {
        return this.mediaLines.map((line, i) => ({
            ...line,
            index: i,
            rowLabel: `Item ${i + 1}`,
            isRemovable: this.mediaLines.length > 1,
            hasPhoto: !!line.photoUrl,
            subTypeOptions: this.subTypeOptionsFor(line.mediaType)
        }));
    }

    // Sub types narrow to the chosen media type once parent dependencies are
    // configured on the picklist records. Until then no option carries a parent,
    // so the full list is shown rather than an empty dropdown.
    subTypeOptionsFor(mediaType) {
        const dependent = this.mediaSubTypeOptions.filter(o => o.parent);
        if (dependent.length === 0) return this.mediaSubTypeOptions;
        if (!mediaType) return [];
        return dependent.filter(o => o.parent === mediaType);
    }

    // Add Line only appears once every existing line is complete, so the user
    // fills one row at a time as asked.
    get canAddMediaLine() {
        return this.mediaLines.length > 0 && this.mediaLines.every(l => this.isMediaLineComplete(l));
    }

    // Every field on an item is mandatory, photo included.
    isMediaLineComplete(line) {
        return !!line.mediaType && !!line.mediaSubType && !!line.photoUrl &&
               line.quantity !== null && line.quantity !== undefined &&
               String(line.quantity).trim() !== '' && Number(line.quantity) > 0;
    }

    async loadMediaLineOptions() {
        try {
            const result = await getMediaLineOptions();
            this.mediaTypeOptions = (result.mediaTypes || []).map(o => ({ label: o.label, value: o.value }));
            this.mediaSubTypeOptions = (result.mediaSubTypes || []).map(o => ({
                label: o.label, value: o.value, parent: o.parent
            }));
        } catch (error) {
            this.showError('Error loading media options', error);
        }
    }

    resetMediaLines() {
        // Always start with exactly one blank line.
        this.mediaLines = [this.blankMediaLine()];
        this.mediaLineError = '';
    }

    blankMediaLine() {
        return { mediaType: '', mediaSubType: '', quantity: '', photoUrl: '', photoName: '' };
    }

    handleMediaLinePhotoClick(event) {
        const index = event.currentTarget.dataset.index;
        const input = Array.from(this.template.querySelectorAll('input[data-type="media-line-photo"]'))
            .find(i => i.dataset.index === index);
        if (input) input.click();
    }

    async handleMediaLinePhotoChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const file = event.target.files && event.target.files[0];
        if (!file) return;

        this.mediaLineError = '';
        try {
            if (!['image/jpeg', 'image/png'].includes(file.type)) {
                this.mediaLineError = 'Only JPG/PNG allowed';
                return;
            }
            if (file.size > 5 * 1024 * 1024) {
                this.mediaLineError = `File is too large (${(file.size / (1024 * 1024)).toFixed(1)} MB). Must be under 5 MB.`;
                return;
            }
            const compressed = await this.compressToJpegWithQuality(file, 1.5);
            const updated = [...this.mediaLines];
            updated[index] = {
                ...updated[index],
                photoUrl: compressed,
                photoName: file.name.replace(/\.[^/.]+$/, '.jpg')
            };
            this.mediaLines = updated;
        } catch (error) {
            this.mediaLineError = 'Image processing failed';
        } finally {
            event.target.value = null;
        }
    }

    handleRemoveMediaLinePhoto(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const updated = [...this.mediaLines];
        updated[index] = { ...updated[index], photoUrl: '', photoName: '' };
        this.mediaLines = updated;
    }

    handleMediaLineChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const fieldName = event.target.dataset.field;
        const value = event.detail?.value !== undefined ? event.detail.value : event.target.value;

        const updated = [...this.mediaLines];
        updated[index] = { ...updated[index], [fieldName]: value };
        // Changing the media type invalidates a sub type that belonged to the old one.
        if (fieldName === 'mediaType') {
            const stillValid = this.subTypeOptionsFor(value)
                .some(o => o.value === updated[index].mediaSubType);
            if (!stillValid) updated[index].mediaSubType = '';
        }
        this.mediaLines = updated;
        this.mediaLineError = '';
    }

    handleAddMediaLine() {
        if (!this.canAddMediaLine) {
            this.mediaLineError = 'Complete the current item before adding another.';
            return;
        }
        this.mediaLines = [...this.mediaLines, this.blankMediaLine()];
        this.mediaLineError = '';
    }

    handleRemoveMediaLine(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        if (this.mediaLines.length <= 1) return;
        this.mediaLines = this.mediaLines.filter((_, i) => i !== index);
        this.mediaLineError = '';
    }

    // ================= INSTALLATION STEP =================
    // Only the person who raised the case can close out the installation, and
    // only while it is sitting at Installation Pending.
    get showInstallationSection() {
        const status = (this.selectedCase.status || '').trim().toLowerCase();
        return status === INSTALLATION_PENDING &&
               this.selectedCase.createdById === USER_ID;
    }

    get hasInstallImages() {
        return this.installImages.length > 0;
    }

    handleInstallPhotoClick(event) {
        event.preventDefault();
        const input = this.template.querySelector('.install-box input[type="file"]');
        if (input) input.click();
    }

    async handleInstallFileChange(event) {
        const target = event.target;
        const files = target && target.files;
        if (!files || files.length === 0) return;

        this.installError = '';
        for (const file of files) {
            if (this.installImages.length >= MAX_PHOTOS) {
                this.installError = 'Only one photo is allowed. Remove the existing photo first.';
                break;
            }
            if (!['image/jpeg', 'image/png'].includes(file.type)) {
                this.installError = 'Only JPG/PNG allowed';
                continue;
            }
            if (file.size > 5 * 1024 * 1024) {
                this.installError = `File is too large (${(file.size / (1024 * 1024)).toFixed(1)} MB). Must be under 5 MB.`;
                continue;
            }
            try {
                const compressed = await this.compressToJpegWithQuality(file, 1.5);
                this.installImages = [...this.installImages, {
                    id: `${Date.now()}_${this.installImages.length}`,
                    url: compressed,
                    fileName: file.name.replace(/\.[^/.]+$/, '.jpg')
                }];
            } catch (error) {
                this.installError = 'Image processing failed';
            }
        }
        if (target) target.value = null;
    }

    removeInstallImage(event) {
        const id = event.currentTarget.dataset.id;
        this.installImages = this.installImages.filter(img => img.id !== id);
        this.installError = '';
    }

    async handleMarkInstalled() {
        if (this.isSubmitting) return;

        // Photo is mandatory — the case cannot move to Installed without proof.
        if (this.installImages.length === 0) {
            this.installError = 'Please upload a photo of the installed asset before submitting.';
            return;
        }

        this.isSubmitting = true;
        this.installError = '';
        try {
            // One call: uploads the photo, records it on the case, then moves to
            // Installed. If the upload fails the case stays at Installation
            // Pending so the raiser can retry rather than closing without proof.
            await submitInstallation({
                caseId: this.caseId,
                files: this.installImages.map(img => ({
                    fileName: img.fileName,
                    base64: img.url.split(',')[1]
                }))
            });

            this.selectedCase = { ...this.selectedCase, status: 'Installed' };
            this.installImages = [];
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Installation submitted. Case marked as Installed.',
                variant: 'success'
            }));
            this.isDetailScreen = false;
            this.isHideAddIcon = true;
            await this.loadCases();
        } catch (error) {
            this.showError('Could not submit the installation', error);
        } finally {
            this.isSubmitting = false;
        }
    }

    // ================= STATUS CLASS =================
    getStatusClass(status) {
        if (!status) return 'status other';
        const normalized = status.trim().toLowerCase();
        if (normalized === 'approved') return 'status approved';
        if (normalized === 'installation pending') return 'status installation-pending';
        if (normalized === 'installed') return 'status installed';
        if (normalized === 'open') return 'status open';
        return 'status other';
    }

    // ================= GET DISTRIBUTOR =================
    async fetchDistributor(retailerId, distributorFieldApi) {
        try {
            const distributorId = await getDistributorId({ retailerId });
            this.formData = { ...this.formData, [distributorFieldApi]: distributorId };
            this.dynamicFields = this.dynamicFields.map(f => {
                if (f.apiName === distributorFieldApi) {
                    return {
                        ...f,
                        value: distributorId,
                        isDisabled: f.apiName === 'Distributor_Transfer_To__c' ? false : (this.retailerId ? true : false),
                        key: `${f.apiName}_${Date.now()}`
                    };
                }
                return f;
            });
        } catch (error) {}
    }

    // ================= NAVIGATION =================
    get showBackButton() {
        if (this.visitTaskId && !this.isFormScreen && !this.isDetailScreen) return true;
        return this.isFormScreen || this.isDetailScreen;
    }
    get backButtonClass() {
        return this.showBackButton ? 'back-container' : 'back-container hidden';
    }
    handleBack() {
        if (this.isDetailScreen) {
            this.isDetailScreen = false;
            this.isHideAddIcon = true;
        } else if (this.isFormScreen) {
            this.isFormScreen = false;
            this.isHideAddIcon = true;
        } else {
            this.dispatchEvent(new CustomEvent('back'));
        }
        this.formData = {};
        this.dynamicFields = [];
        this.uploadedFiles = [];
        this.installImages = [];
        this.installError = '';
        this.isSubmitting = false;
    }
    openCaseDetail(event) {
        const caseId = event.currentTarget.dataset.id;
        this.caseId = caseId;
        this.selectedCase = this.cases.find(c => c.id === caseId) || {};
        this.installImages = [];
        this.installError = '';
        getCaseFields({ caseId: caseId })
            .then(result => {
                const priorityFields = [
                    'Retailer__c', 'Distributor__c', 'Warehouse__c',
                    'Retailer_Transfer_From__c', 'Distributor_Transfer_From__c',
                    'Warehouse_Transfer_From__c', 'Retailer_Transfer_To__c',
                    'Distributor_Transfer_To__c', 'Warehouse_Transfer_To__c'
                ];
                let sortedFields = [...result];
                sortedFields.sort((a, b) => {
                    const indexA = priorityFields.indexOf(a.apiName);
                    const indexB = priorityFields.indexOf(b.apiName);
                    if (indexA !== -1 && indexB !== -1) return indexA - indexB;
                    if (indexA !== -1) return -1;
                    if (indexB !== -1) return 1;
                    return 0;
                });
                this.caseFieldsArray = sortedFields.filter(f => f.displayValue !== null && f.displayValue !== undefined && f.displayValue !== '');
            })
            .catch(() => {});
        this.isDetailScreen = true;
        this.isHideAddIcon = false;
    }

    // ================= SEARCH =================
    handleSearch(event) {
        this.searchKey = event.target.value.trim().toLowerCase();
    }
    get filteredCases() {
        return this.cases.filter(c => {
            const matchesStatus = c.tabstatus === this.selectedTab;
            return matchesStatus && (
                String(c.caseNumber).toLowerCase().includes(this.searchKey) ||
                String(c.type).toLowerCase().includes(this.searchKey)
            );
        });
    }
    showOpen() { this.selectedTab = 'Open'; }
    showClosed() { this.selectedTab = 'Approved'; }
    get openTabClass() { return this.selectedTab === 'Open' ? 'active-tab' : 'tab'; }
    get closedTabClass() { return this.selectedTab === 'Approved' ? 'active-tab' : 'tab'; }

    // ================= POPUP =================
    openPopup() {
        this.showPopup = true;
        document.body.style.overflow = 'hidden';
        this.searchType = '';
        this.selectedType = '';
        this.formData = {};
        this.dynamicFields = [];
        this.uploadedFiles = [];
        this.isSubmitting = false;
    }
    closePopup() {
    this.showPopup = false;
    document.body.style.overflow = 'auto';
    this.searchType = '';
    this.selectedType = '';
    this.typeSearchQuery = '';
    this.showTypeDropdown = false;
}

    // ================= TYPE SEARCH =================
    handleInputClick() { this.showTypeDropdown = true; }
   handleTypeSearch(event) {
    this.searchType = event.target.value;
    this.typeSearchQuery = event.target.value.toLowerCase();
    this.showTypeDropdown = true;
}
    get filteredTypes() {
    return this.caseTypes.filter(t => t.label.toLowerCase().includes(this.typeSearchQuery || ''));
}
    selectType(event) {
        const label = event.currentTarget.dataset.label;
        const value = event.currentTarget.dataset.value;
        this.selectedType = value;
        this.selectedTypeLabel = label;
        this.searchType = label;
        this.showTypeDropdown = false;

        if (label === INVENTORY_CASE_TYPE) {
            this.resetMediaLines();
            this.loadMediaLineOptions();
        } else {
            this.mediaLines = [];
        }

        if (label === RETURN_CASE_TYPE) {
            this.loadRetailerBrandingAssets();
        } else {
            this.brandingAssetOptions = [];
            this.selectedBrandingAssetId = '';
            this.brandingAssetError = '';
        }
    }
    clearSelection() {
    this.selectedType = '';
    this.selectedTypeLabel = '';
    this.searchType = '';
    this.typeSearchQuery = '';
    this.showTypeDropdown = true;
    this.mediaLines = [];
    this.mediaLineError = '';
}

    // ================= LOAD FORM =================
    async handleSubmit() {
        const mapping = {
            'Retailer__c': 'Distributor__c',
            'Retailer_Transfer_From__c': 'Distributor_Transfer_From__c'
        };
        for (let retailerField in mapping) {
            const retailerValue = this.formData[retailerField] !== undefined ? this.formData[retailerField] : this.retailerId;
            if (retailerValue) {
                await this.fetchDistributor(retailerValue, mapping[retailerField]);
            }
        }
        if (!this.selectedType) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Warning',
                message: 'Please select the case type',
                variant: 'warning'
            }));
            return;
        }
        if (!this.isCheckInDone &&
            (this.searchType === 'Existing outlet Asset Code Change Request' ||
             this.searchType === 'Asset Tagging Request')) {
            this.showError('Error', { message: 'Please complete check-in before proceeding with this case type.' });
            return;
        }
        this.formData = { ...this.formData, Case_Type__c: this.selectedType };
        if (this.distributorId && !this.retailerId) {
            this.formData = { ...this.formData, Distributor_Transfer_From__c: this.distributorId };
        }
        try {
            const result = await getDynamicFields({ caseType: this.searchType });
            if (!result || result.length === 0) {
                this.showError('Error', { message: 'This case type is not applicable' });
                return;
            }
            const retailerFields = ['Retailer__c', 'Retailer_Transfer_From__c', 'Retailer_Transfer_To__c'];
            const retailerDistributorMap = {
                'Retailer__c': 'Distributor__c',
                'Retailer_Transfer_From__c': 'Distributor_Transfer_From__c',
                'Retailer_Transfer_To__c': 'Distributor_Transfer_To__c'
            };
            this.dynamicFields = result.map(f => {
                let filterCriteria = null;
                if (f.apiName === 'Retailer__c' || f.apiName === 'Retailer_Transfer_From__c' || f.apiName === 'Retailer_Transfer_To__c') {
                    filterCriteria = { criteria: [{ fieldPath: 'RecordType.DeveloperName', operator: 'eq', value: 'Retailer' }] };
                } else if (f.apiName === 'Warehouse__c' || f.apiName === 'Warehouse_Transfer_From__c' || f.apiName === 'Warehouse_Transfer_To__c') {
                    filterCriteria = { criteria: [{ fieldPath: 'RecordType.DeveloperName', operator: 'eq', value: 'Warehouse' }] };
               } else if (f.apiName === 'Distributor__c' || f.apiName === 'Distributor_Transfer_From__c' || f.apiName === 'Distributor_Transfer_To__c') {
                    filterCriteria = { criteria: [{ fieldPath: 'RecordType.DeveloperName', operator: 'eq', value: 'Distributor' }, { fieldPath: 'RecordType.DeveloperName', operator: 'eq', value: 'SuperStockist' }], filterLogic: '1 OR 2' };
                }

                // ================= OUTSIDE VISIT: CONVERT LOOKUP TO PICKLIST FOR USER RETAILERS =================
                // Skipped when the case is raised from inside an account: that
                // account is the answer, so it must be pre-filled and locked rather
                // than replaced by a free choice of the user's own retailers.
                if (!this.visitTaskId && !this.retailerId && !this.distributorId &&
                    (f.apiName === 'Retailer_Transfer_From__c' || f.apiName === 'Retailer__c') &&
                    this.userRetailers.length > 0) {
                    return {
                        ffId: f.ffId, apiName: f.apiName, label: f.label,
                        isHidden: f.apiName === 'Retailer__c' ? false : true,
                        required: f.required,
                        isControlling: f.isControlling,
                        isPicklist: true, isLookup: false, isText: false,
                        isNumber: false, isDate: false, isRadio: false, isFile: false,
                        options: this.userRetailers,
                        value: null,
                        isDisabled: false,
                        filter: null,
                        key: `${f.apiName}_${Date.now()}`,
                        images: []
                    };
                }

                // ================= OUTSIDE VISIT: CONVERT LOOKUP TO PICKLIST FOR USER DISTRIBUTORS =================
                // Same exception as retailers above - account context wins.
                if (!this.visitTaskId && !this.retailerId && !this.distributorId &&
                    (f.apiName === 'Distributor_Transfer_From__c' || f.apiName === 'Distributor__c' ||
                     f.apiName === 'Distributor_Transfer_To__c') &&
                    this.userDistributors.length > 0) {
                    return {
                        ffId: f.ffId, apiName: f.apiName, label: f.label,
                        isHidden: true,
                        required: f.required,
                        isControlling: f.isControlling,
                        isPicklist: true, isLookup: false, isText: false,
                        isNumber: false, isDate: false, isRadio: false, isFile: false,
                        options: this.userDistributors,
                        value: null,
                        isDisabled: false,
                        filter: null,
                        key: `${f.apiName}_${Date.now()}`,
                        images: []
                    };
                }

                if (retailerFields.includes(f.apiName)) {
                    const distributorField = retailerDistributorMap[f.apiName];
                    let retailerValue;
                    if (this.formData[f.apiName] !== undefined) {
                        retailerValue = this.formData[f.apiName];
                    } else if (f.apiName === 'Retailer__c' || f.apiName === 'Retailer_Transfer_From__c') {
                        retailerValue = this.retailerId || null;
                    } else {
                        retailerValue = null;
                    }
                    let distributorValue;
                    if (this.formData[distributorField] !== undefined) {
                        distributorValue = this.formData[distributorField];
                    } else if (f.apiName === 'Retailer__c' || f.apiName === 'Retailer_Transfer_From__c') {
                        distributorValue = this.distributorId || null;
                    } else {
                        distributorValue = null;
                    }
                    this.formData = { ...this.formData, [f.apiName]: retailerValue, [distributorField]: distributorValue };
                                            return {
                                              ffId: f.ffId, apiName: f.apiName, label: f.label,
                        isHidden: f.apiName === 'Scrap__c' || f.apiName === 'Transferred_to_warehouse__c' ||
                            f.apiName === 'Retailer_Transfer_To__c' ||
                            f.apiName === 'Distributor_Transfer_From__c' || f.apiName === 'Distributor_Transfer_To__c' ||
                            (f.apiName === 'Retailer_Transfer_From__c' && this.distributorId && !this.retailerId) ||
                            (f.apiName === 'Retailer__c' && this.distributorId && !this.retailerId),
                        required: (f.apiName === 'Retailer__c' && this.distributorId && !this.retailerId) ? false : f.required,
                        lookupObject: f.lookupObject, options: f.options,
                        isControlling: f.isControlling, value: retailerValue,
                        isDisabled: this.retailerId ? (f.apiName === 'Retailer_Transfer_To__c' ? false : !!retailerValue) : false,
                        filter: filterCriteria, key: `${f.apiName}_${Date.now()}`, images: [],
                        ...this.getFieldTypeFlags(f.type)
                    };
                }

                if (Object.values(retailerDistributorMap).includes(f.apiName)) {
                    const distributorValue = this.formData[f.apiName] !== undefined ? this.formData[f.apiName] : null;
                    return {
                        ffId: f.ffId, apiName: f.apiName, label: f.label,
                        isHidden: f.apiName === 'Scrap__c' || f.apiName === 'Transferred_to_warehouse__c' ||
                            f.apiName === 'Retailer_Transfer_From__c' || f.apiName === 'Retailer_Transfer_To__c' ||
                            f.apiName === 'Distributor_Transfer_From__c' || f.apiName === 'Distributor_Transfer_To__c',
                        required: f.required, lookupObject: f.lookupObject, options: f.options,
                        isControlling: f.isControlling, filter: filterCriteria,
                        // Raised from inside a distributor account: show that account.
                        value: (this.distributorId && !this.retailerId &&
                                (f.apiName === 'Distributor_Transfer_From__c' || f.apiName === 'Distributor__c'))
                            ? this.distributorId : distributorValue,
                        isDisabled: f.apiName === 'Distributor_Transfer_To__c' ? false : true,
                        key: `${f.apiName}_${Date.now()}`, images: [],
                        ...this.getFieldTypeFlags(f.type)
                    };
                }

                return {
                    ffId: f.ffId, apiName: f.apiName, label: f.label,
                    isHidden: f.apiName === 'Scrap__c' || f.apiName === 'Transferred_to_warehouse__c' ||
                            f.apiName === 'Retailer_Transfer_From__c' || f.apiName === 'Retailer_Transfer_To__c' ||
                            f.apiName === 'Distributor_Transfer_To__c' ||
                            (f.apiName === 'Distributor_Transfer_From__c' && !(this.distributorId && !this.retailerId)),
                    required: (f.apiName === 'Retailer__c' && this.distributorId && !this.retailerId) ? false : f.required,
                    lookupObject: f.lookupObject, options: f.options,
                    isControlling: f.isControlling, filter: filterCriteria,
                    isScannable: f.apiName === 'New_Asset_Code__c' || f.apiName === 'Serial_Number__c',
                    isScanOnly: f.apiName === 'New_Asset_Code__c' &&
                        (this.searchType === 'Asset Tagging Request' ||
                         this.searchType === 'Existing outlet Asset Code Change Request'),
                    isDisabled: f.apiName === 'Old_Asset_Code__c',
                    value: (f.apiName === 'Distributor_Transfer_From__c' && this.distributorId && !this.retailerId) ? this.distributorId : null,
                    key: `${f.apiName}_${Date.now()}`, images: [],
                    ...this.getFieldTypeFlags(f.type)
                };
            });

            // ================= LOAD QR CODES FOR ASSET COMPLAINT =================
            if (this.searchType === 'Asset Complaint Request') {
                try {
                    const retailerId = this.retailerId || this.formData['Retailer__c'] || null;
                    const distributorId = this.distributorId || null;
                    if (retailerId || distributorId) {
                        const assets = await getAssetsByAccount({
                            retailerId: retailerId,
                            distributorId: retailerId ? null : distributorId
                        });
                        if (assets && assets.length > 0) {
                            const qrOptions = assets.filter(a => a.qrCode).map(a => ({ label: a.qrCode, value: a.qrCode }));
                            this.dynamicFields = this.dynamicFields.map(f => {
                                if (f.apiName === 'OEM_serial_number__c') {
                                    return { ...f, isPicklist: true, isText: false, options: qrOptions };
                                }
                                return f;
                            });
                        }
                    }
                } catch (error) {}
            }

            // ================= AUTO FILL ASSET DATA =================
            if (this.searchType === 'Existing outlet Asset Code Change Request') {
                try {
                    const assets = await getAssets({ visitTaskId: this.visitTaskId });
                    if (assets && assets.length > 0) {
                        const activeAssets = assets.filter(a => a.active);
                        if (activeAssets.length === 0) {
                            this.showError('Error', { message: 'No active assets found. Cannot proceed with Asset Code Change.' });
                            this.showPopup = false;
                            return;
                        }
                        if (activeAssets.length === 1) {
                            const asset = activeAssets[0];
                            const attr = asset.attributes || {};
                            const make = attr['Make'] || '';
                            const model = attr['Model'] || '';
                            const capacity = attr['Capacity'] || '';
                            this.formData = { ...this.formData, Old_Asset_Code__c: asset.qrCode };
                            let makeValue = null;
                            this.dynamicFields = this.dynamicFields.map(f => {
                                if (f.apiName === 'Old_Asset_Code__c') return { ...f, value: asset.qrCode };
                                if (f.apiName === 'Make__c' && f.options) {
                                    const selected = f.options.find(opt => opt.label?.trim().toLowerCase() === make?.trim().toLowerCase());
                                    makeValue = selected ? selected.value : null;
                                    this.formData = { ...this.formData, Make__c: selected ? selected.label : null };
                                    return { ...f, value: makeValue };
                                }
                                return f;
                            });
                            this.dynamicFields = [...this.dynamicFields];
                            const makeField = this.dynamicFields.find(f => f.apiName === 'Make__c');
                            let modelValue = null;
                            if (makeField && makeValue) {
                                await this.loadDependentFields(makeValue, makeField.ffId);
                                await new Promise(r => setTimeout(r, 300));
                                const modelFieldAfter = this.dynamicFields.find(f => f.apiName === 'Model__c');
                                if (modelFieldAfter?.options) {
                                    this.dynamicFields = this.dynamicFields.map(f => {
                                        if (f.apiName === 'Model__c') {
                                            const selected = f.options.find(opt => opt.label?.trim().toLowerCase() === model?.trim().toLowerCase());
                                            modelValue = selected ? selected.value : null;
                                            this.formData = { ...this.formData, Model__c: selected ? selected.label : null };
                                            return { ...f, value: modelValue };
                                        }
                                        return f;
                                    });
                                    this.dynamicFields = [...this.dynamicFields];
                                }
                            }
                            if (modelValue) {
                                const modelField = this.dynamicFields.find(f => f.apiName === 'Model__c');
                                await this.loadDependentFields(modelValue, modelField.ffId);
                                await new Promise(r => setTimeout(r, 300));
                                let capFieldAfter = this.dynamicFields.find(f => f.apiName === 'Capacity__c');
                                if (!capFieldAfter?.options || capFieldAfter.options.length === 0) {
                                    capFieldAfter = { ...capFieldAfter, options: this.allCapacityOptions || [] };
                                    this.dynamicFields = this.dynamicFields.map(f => f.apiName === 'Capacity__c' ? capFieldAfter : f);
                                    this.dynamicFields = [...this.dynamicFields];
                                }
                                this.dynamicFields = this.dynamicFields.map(f => {
                                    if (f.apiName === 'Capacity__c' && f.options) {
                                        const selected = f.options.find(opt => opt.label?.trim().toLowerCase() === capacity?.trim().toLowerCase());
                                        const capValue = selected ? selected.value : null;
                                        this.formData = { ...this.formData, Capacity__c: selected ? selected.label : null };
                                        return { ...f, value: capValue };
                                    }
                                    return f;
                                });
                                this.dynamicFields = [...this.dynamicFields];
                            }
                        } else {
                            const qrOptions = activeAssets.map(a => ({ label: a.qrCode, value: a.qrCode }));
                            this.dynamicFields = this.dynamicFields.map(f => {
                                if (f.apiName === 'Old_Asset_Code__c') {
                                    return { ...f, isText: false, isPicklist: true, options: qrOptions, isDisabled: false, value: null };
                                }
                                return f;
                            });
                            this._assetsByQR = {};
                            activeAssets.forEach(a => { this._assetsByQR[a.qrCode] = a; });
                        }
                    } else {
                        this.showError('Error', { message: 'No assets found. Cannot proceed with Asset Code Change.' });
                        this.showPopup = false;
                        return;
                    }
                } catch (error) {}
            }

            // ================= LOAD QR CODE OPTIONS FOR ASSET TRANSFER =================
            if (this.searchType === 'Asset Transfer Request') {
                try {
                    let assets = [];
                    if (this.visitTaskId) {
                        assets = await getAssets({ visitTaskId: this.visitTaskId });
                    } else {
                        const retailerId = this.formData['Retailer_Transfer_From__c'] || this.retailerId || null;
                        const distributorId = this.formData['Distributor_Transfer_From__c'] || this.formData['Distributor__c'] || null;
                        assets = await getAssetsByAccount({ retailerId: retailerId, distributorId: distributorId });
                    }
                    if (assets && assets.length > 0) {
                        const qrOptions = assets.filter(a => a.qrCode).map(a => ({ label: a.qrCode, value: a.qrCode }));
                        this.dynamicFields = this.dynamicFields.map(f => {
                            if (f.apiName === 'OEM_serial_number__c') {
                                return { ...f, isText: false, isPicklist: true, options: qrOptions };
                            }
                            return f;
                        });
                    }
                    if (this.visitTaskId) {
                        const allowedInsideVisit = this.distributorId && !this.retailerId
                            ? ['Scrap', 'Distributor to Outlet', 'Distributor to Distributor']
                            : ['Outlet to Outlet', 'Outlet to Distributor', 'Scrap'];
                        this.dynamicFields = this.dynamicFields.map(f => {
                            if (f.apiName === 'Request_type__c' && f.options) {
                                return {
                                    ...f,
                                    options: f.options.filter(opt => allowedInsideVisit.includes(opt.label))
                                };
                            }
                            return f;
                        });
                    }
                } catch (error) {}
            }

       

            // ================= AUTO-POPULATE DISTRIBUTOR FOR DISTRIBUTOR VISITS =================
            if (this.distributorId && !this.retailerId) {
                this.formData = { ...this.formData, Distributor_Transfer_From__c: this.distributorId };
            }

            this.showPopup = false;
            this.isFormScreen = true;
            this.isHideAddIcon = false;
        } catch (error) {
            this.showError('Error loading form', error);
        }
    }

    // ================= FIELD TYPE =================
    getFieldTypeFlags(type) {
        const t = type ? type.toLowerCase() : '';
        return {
            isText: ['text', 'textarea', 'email', 'phone', 'gst', 'fssai', 'pincode', 'barcode'].includes(t),
            isNumber: ['number', 'currency'].includes(t),
            isDate: t === 'date',
            isPicklist: t === 'picklist',
            isLookup: t === 'lookup',
            isRadio: t === 'radio',
            isFile: t === 'file'
        };
    }

    // ================= FORM INPUT =================
    handleInputChange(event) {
        const fieldName = event.target.name;
        const value = event.detail?.value !== undefined ? event.detail.value : event.target.value;
        if (fieldName === 'Expected_delivery_date__c') {
            const selectedDate = new Date(value);
            const today = new Date();
            today.setHours(0, 0, 0, 0);
            selectedDate.setHours(0, 0, 0, 0);
            if (selectedDate <= today) {
                this.showError('Error', { message: 'Today and past dates are not allowed' });
                event.target.value = null;
                return;
            }
        }
        if (fieldName === 'PIN_Code__c') {
            const pinRegex = /^[0-9]{6}$/;
            if (!pinRegex.test(value)) {
                event.target.setCustomValidity('Pin code should contain only 6 digit numbers');
                event.target.reportValidity();
                return;
            } else {
                event.target.setCustomValidity('');
                event.target.reportValidity();
            }
        }
        const ffId = event.target.dataset.id;
        let selectedLabel = '';
        const field = this.dynamicFields.find(f => f.apiName === fieldName);
        if (field && field.options) {
            const selectedOption = field.options.find(opt => opt.value === value);
            if (selectedOption) selectedLabel = selectedOption.label;
        }
        const lookupAsPicklistFields = [
            'Retailer__c', 'Retailer_Transfer_From__c', 'Retailer_Transfer_To__c',
            'Distributor__c', 'Distributor_Transfer_From__c', 'Distributor_Transfer_To__c'
        ];
        this.formData = {
            ...this.formData,
            [fieldName]: (selectedLabel && !lookupAsPicklistFields.includes(fieldName)) ? selectedLabel : value
        };

        // ================= OUTSIDE VISIT: AUTO POPULATE DISTRIBUTOR WHEN RETAILER SELECTED =================
        if (!this.visitTaskId &&
            (fieldName === 'Retailer_Transfer_From__c' || fieldName === 'Retailer__c') && value) {
            const distField = fieldName === 'Retailer__c' ? 'Distributor__c' : 'Distributor_Transfer_From__c';
            this.fetchDistributor(value, distField);
            getAssetsByAccount({ retailerId: value, distributorId: null })
                .then(assets => {
                    if (assets && assets.length > 0) {
                        const qrOptions = assets.filter(a => a.qrCode).map(a => ({ label: a.qrCode, value: a.qrCode }));
                        this.dynamicFields = this.dynamicFields.map(f => {
                            if (f.apiName === 'OEM_serial_number__c') {
                                return { ...f, isText: false, isPicklist: true, options: qrOptions };
                            }
                            return f;
                        });
                    }
                })
                .catch(() => {});
        }

        // ================= LOAD QR CODES FOR ASSET COMPLAINT =================
        if (fieldName === 'Retailer__c' && value && this.searchType === 'Asset Complaint Request') {
            getAssetsByAccount({ retailerId: value, distributorId: null })
                .then(assets => {
                    if (assets && assets.length > 0) {
                        const qrOptions = assets.filter(a => a.qrCode).map(a => ({ label: a.qrCode, value: a.qrCode }));
                        this.dynamicFields = this.dynamicFields.map(f => {
                            if (f.apiName === 'OEM_serial_number__c') {
                                return { ...f, isPicklist: true, isText: false, options: qrOptions };
                            }
                            return f;
                        });
                    }
                })
                .catch(() => {});
        }

        // ================= OUTSIDE VISIT: LOAD ASSETS WHEN DISTRIBUTOR SELECTED =================
        if (!this.visitTaskId &&
            (fieldName === 'Distributor_Transfer_From__c' || fieldName === 'Distributor__c') && value) {
            getAssetsByAccount({ retailerId: null, distributorId: value })
                .then(assets => {
                    if (assets && assets.length > 0) {
                        const qrOptions = assets.filter(a => a.qrCode).map(a => ({ label: a.qrCode, value: a.qrCode }));
                        this.dynamicFields = this.dynamicFields.map(f => {
                            if (f.apiName === 'OEM_serial_number__c') {
                                return { ...f, isText: false, isPicklist: true, options: qrOptions };
                            }
                            return f;
                        });
                    }
                })
                .catch(() => {});
        }

        this.dynamicFields = this.dynamicFields.map(f => {
            if (f.apiName === fieldName) return { ...f, value: value };
            return f;
        });

        // ================= REQUEST TYPE LOGIC =================
        if (fieldName === 'Request_type__c') {
            const selectedRequestType = selectedLabel || value;
            this.dynamicFields = this.dynamicFields.map(f => {
                if (f.apiName === 'Scrap__c') {
                    return { ...f, isHidden: selectedRequestType !== 'Scrap', isDisabled: false };
                }
                if (f.apiName === 'Transferred_to_warehouse__c') return { ...f, isHidden: true };
                let hideTransferFields = true;
                if (selectedRequestType === 'Outlet to Outlet' &&
                    (f.apiName === 'Retailer_Transfer_From__c' || f.apiName === 'Retailer_Transfer_To__c' ||
                     f.apiName === 'Distributor_Transfer_To__c')) {
                    hideTransferFields = false;
                }
                if (selectedRequestType === 'Outlet to Distributor' &&
                    (f.apiName === 'Retailer_Transfer_From__c' || f.apiName === 'Distributor_Transfer_To__c')) {
                    hideTransferFields = false;
                }
                if (selectedRequestType === 'Distributor to Distributor' &&
                    (f.apiName === 'Distributor_Transfer_From__c' || f.apiName === 'Distributor_Transfer_To__c')) {
                    hideTransferFields = false;
                }
               if (selectedRequestType === 'Distributor to Outlet' &&
                    (f.apiName === 'Distributor_Transfer_From__c' || f.apiName === 'Retailer_Transfer_To__c')) {
                    hideTransferFields = false;
                }
                if (selectedRequestType === 'Scrap') {
                if (this.distributorId && !this.retailerId) {
                    if (f.apiName === 'Distributor_Transfer_From__c') hideTransferFields = false;
                } else {
                    if (f.apiName === 'Retailer_Transfer_From__c' ||
                        f.apiName === 'Distributor_Transfer_From__c') hideTransferFields = false;
                }
            }
             if (f.apiName === 'Retailer_Transfer_From__c' || f.apiName === 'Retailer_Transfer_To__c' ||
                    f.apiName === 'Distributor_Transfer_From__c' || f.apiName === 'Distributor_Transfer_To__c') {
                    const isDistributorVisit = this.distributorId && !this.retailerId;
                    if (isDistributorVisit && f.apiName === 'Retailer_Transfer_From__c') {
                        return { ...f, isHidden: true };
                    }
                    return {
                        ...f,
                        isHidden: hideTransferFields,
                        required: !hideTransferFields ? true : f.required,
                        key: !hideTransferFields ? `${f.apiName}_${Date.now()}` : f.key
                    };
                }
                return f;
            });
            
            // ================= LOAD ASSETS FOR DISTRIBUTOR REQUESTS =================
            if (selectedRequestType === 'Distributor to Distributor' || selectedRequestType === 'Distributor to Outlet') {
                const distFromId = this.formData['Distributor_Transfer_From__c'] || null;
                if (distFromId) {
                    getAssetsByAccount({ retailerId: null, distributorId: distFromId })
                        .then(assets => {
                            if (assets && assets.length > 0) {
                                const qrOptions = assets.filter(a => a.qrCode).map(a => ({ label: a.qrCode, value: a.qrCode }));
                                this.dynamicFields = this.dynamicFields.map(f => {
                                    if (f.apiName === 'OEM_serial_number__c') {
                                        return { ...f, isText: false, isPicklist: true, options: qrOptions };
                                    }
                                    return f;
                                });
                            }
                        })
                        .catch(() => {});
                }
            }

            // ================= LOAD ASSETS FOR SCRAP =================
            if (selectedRequestType === 'Scrap') {
                const retailerFromId = this.formData['Retailer_Transfer_From__c'] || this.retailerId || null;
                const distFromId = this.formData['Distributor_Transfer_From__c'] || null;
                if (retailerFromId || distFromId) {
                    getAssetsByAccount({
                        retailerId: retailerFromId,
                        distributorId: retailerFromId ? null : distFromId
                    })
                        .then(assets => {
                            if (assets && assets.length > 0) {
                                const qrOptions = assets.filter(a => a.qrCode).map(a => ({ label: a.qrCode, value: a.qrCode }));
                                this.dynamicFields = this.dynamicFields.map(f => {
                                    if (f.apiName === 'OEM_serial_number__c') {
                                        return { ...f, isText: false, isPicklist: true, options: qrOptions };
                                    }
                                    return f;
                                });
                            }
                        })
                        .catch(() => {});
                }
            }
            this.loadDependentFields(value, ffId);
        }

        // ================= SCRAP FIELD LOGIC =================
        if (fieldName === 'Scrap__c') {
            const selectedScrap = selectedLabel || value;
            this.dynamicFields = this.dynamicFields.map(f => {
                if (f.apiName === 'Transferred_to_warehouse__c') {
                    return { ...f, isHidden: selectedScrap !== 'Transferred to warehouse' };
                }
                return f;
            });
        }

        const controllingField = this.dynamicFields.find(f => f.apiName === fieldName);
        if (controllingField && controllingField.isControlling && fieldName !== 'Request_type__c') {
            let resetStarted = false;
            this.dynamicFields = this.dynamicFields.map(f => {
                if (f.ffId === ffId) { resetStarted = true; return f; }
                if (resetStarted && f.isPicklist) {
                    this.formData[f.apiName] = null;
                    return { ...f, value: null, options: [] };
                }
                return f;
            });
            this.loadDependentFields(value, ffId);
        }
    }

    loadDependentFields(value, ffId) {
        getDynamicFields({ caseType: this.searchType, selectedId: value, ffId: ffId })
            .then(result => {
                let updatedFields = [...this.dynamicFields];
                result.forEach(depField => {
                    let index = updatedFields.findIndex(f => f.ffId === depField.ffId);
                    if (index !== -1 && depField.options && depField.options.length > 0) {
                        updatedFields[index] = { ...updatedFields[index], options: depField.options };
                    }
                });
               if (this.visitTaskId && this.searchType === 'Asset Transfer Request') {
                const allowedInsideVisit = this.distributorId && !this.retailerId
                    ? ['Scrap', 'Distributor to Outlet', 'Distributor to Distributor']
                    : ['Outlet to Outlet', 'Outlet to Distributor', 'Scrap'];
                this.dynamicFields = this.dynamicFields.map(f => {
                    if (f.apiName === 'Request_type__c' && f.options) {
                            return {
                                ...f,
                                options: f.options.filter(opt => allowedInsideVisit.includes(opt.label))
                            };
                        }
                        return f;
                    });
                }
                this.dynamicFields = updatedFields;
            })
            .catch(() => {});
    }

    handleLookupChange(event) {
        const fieldName = event.target.name;
        const value = event.detail.recordId;
        const mapping = {
            'Retailer__c': 'Distributor__c',
            'Retailer_Transfer_From__c': 'Distributor_Transfer_From__c',
            'Retailer_Transfer_To__c': 'Distributor_Transfer_To__c'
        };
        this.formData = { ...this.formData, [fieldName]: value };
        if (mapping[fieldName]) {
            const distributorField = mapping[fieldName];
            if (!value) {
                this.formData = { ...this.formData, [fieldName]: null, [distributorField]: null };
                this.dynamicFields = this.dynamicFields.map(f => {
                    if (f.apiName === fieldName) return { ...f, value: null, key: `${f.apiName}_${Date.now()}` };
                    if (f.apiName === distributorField) {
                        return {
                            ...f, value: null, displayValue: null,
                            isDisabled: f.apiName === 'Distributor_Transfer_To__c' ? false : (this.retailerId ? true : false),
                            key: `${f.apiName}_${Date.now()}`
                        };
                    }
                    return f;
                });
                this.dynamicFields = JSON.parse(JSON.stringify(this.dynamicFields));
                setTimeout(() => {
                    const pickers = this.template.querySelectorAll('lightning-record-picker');
                    pickers.forEach(p => { if (p.name === distributorField) p.clearSelection(); });
                }, 0);
                return;
            }
            this.dynamicFields = [...this.dynamicFields];
            this.fetchDistributor(value, distributorField);
        }

        // ================= LOAD QR CODES WHEN FROM FIELDS SELECTED =================
        if ((fieldName === 'Retailer_Transfer_From__c' || fieldName === 'Distributor_Transfer_From__c') &&
            value && this.searchType === 'Asset Transfer Request') {
            const isRetailer = fieldName === 'Retailer_Transfer_From__c';
            getAssetsByAccount({
                retailerId: isRetailer ? value : null,
                distributorId: isRetailer ? null : value
            })
                .then(assets => {
                    if (assets && assets.length > 0) {
                        const qrOptions = assets.filter(a => a.qrCode).map(a => ({ label: a.qrCode, value: a.qrCode }));
                        this.dynamicFields = this.dynamicFields.map(f => {
                            if (f.apiName === 'OEM_serial_number__c') {
                                return { ...f, isText: false, isPicklist: true, options: qrOptions };
                            }
                            return f;
                        });
                    }
                })
                .catch(() => {});
        }

        // ================= LOAD QR CODES FOR ASSET COMPLAINT =================
        if (fieldName === 'Retailer__c' && value && this.searchType === 'Asset Complaint Request') {
            getAssetsByAccount({ retailerId: value, distributorId: null })
                .then(assets => {
                    if (assets && assets.length > 0) {
                        const qrOptions = assets.filter(a => a.qrCode).map(a => ({ label: a.qrCode, value: a.qrCode }));
                        this.dynamicFields = this.dynamicFields.map(f => {
                            if (f.apiName === 'OEM_serial_number__c') {
                                return { ...f, isPicklist: true, options: qrOptions };
                            }
                            return f;
                        });
                    }
                })
                .catch(() => {});
        }
    }

    // ================= NEW ASSET CODE SCAN =================
    handleNewAssetScan() {
        if (this.scanner && this.scanner.isAvailable()) {
            this.scanner.scan({ cameraFacing: 'BACK', enableScanLine: true })
                .then(results => {
                    this.scanner.dismiss();
                    if (results && results.length > 0) {
                        const scanned = results[0].value;
                        this.validateAndSetNewAssetCode(scanned);
                    }
                })
                .catch(() => {});
        } else {
            this.showNewAssetScanPopup = true;
        }
    }
    handleNewAssetManualInput(event) {
        this._pendingNewAssetCode = event.target.value;
    }
    handleNewAssetManualSubmit() {
        this.validateAndSetNewAssetCode(this._pendingNewAssetCode);
        this.showNewAssetScanPopup = false;
    }
    async validateAndSetNewAssetCode(code) {
        if (!code) return;
        if (!code.startsWith('HIPL')) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'New Asset Code must start with HIPL',
                variant: 'error'
            }));
            return;
        }
        if (code.length < MIN_ASSET_CODE_LENGTH || code.length > MAX_ASSET_CODE_LENGTH) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: `New Asset Code must be between ${MIN_ASSET_CODE_LENGTH} and ${MAX_ASSET_CODE_LENGTH} characters`,
                variant: 'error'
            }));
            return;
        }
        try {
            const masterResult = await checkAssetCodeInMaster({ assetCode: code });
            if (masterResult === 'DUPLICATE_MASTER') {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: 'This QR code already exists in Asset Master',
                    variant: 'error'
                }));
                return;
            }
            const caseResult = await checkNewAssetCode({ assetCode: code });
            if (caseResult !== 'OK') {
                const parts = caseResult.split(':');
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: `Asset Code already exists in case ${parts[1]} with status "${parts[2]}"`,
                    variant: 'error'
                }));
                return;
            }
            this.formData = { ...this.formData, New_Asset_Code__c: code };
            this.dynamicFields = this.dynamicFields.map(f => {
                if (f.apiName === 'New_Asset_Code__c') return { ...f, value: code };
                return f;
            });
        } catch (error) {
            this.showError('Error', error);
        }
    }

    // ================= SERIAL NUMBER SCAN =================
    handleSerialScan() {
        if (this.scanner && this.scanner.isAvailable()) {
            this.scanner.scan({ cameraFacing: 'BACK', enableScanLine: true })
                .then(results => {
                    this.scanner.dismiss();
                    if (results && results.length > 0) {
                        const scanned = results[0].value;
                        this.setSerialNumber(scanned);
                    }
                })
                .catch(() => {});
        } else {
            this.showSerialScanPopup = true;
        }
    }
    handleSerialManualInput(event) {
        this._pendingSerialNumber = event.target.value;
    }
    handleSerialManualSubmit() {
        this.setSerialNumber(this._pendingSerialNumber);
        this.showSerialScanPopup = false;
    }
    setSerialNumber(value) {
        if (!value) return;
        this.formData = { ...this.formData, Serial_Number__c: value };
        this.dynamicFields = this.dynamicFields.map(f => {
            if (f.apiName === 'Serial_Number__c') return { ...f, value: value };
            return f;
        });
    }
    closeNewAssetScanPopup() { this.showNewAssetScanPopup = false; }
    closeSerialScanPopup() { this.showSerialScanPopup = false; }

    // ================= FIELD SCAN HANDLER =================
    handleFieldScan(event) {
        const fieldName = event.currentTarget.dataset.field;
        if (fieldName === 'New_Asset_Code__c') {
            this.handleNewAssetScan();
        } else if (fieldName === 'Serial_Number__c') {
            this.handleSerialScan();
        }
    }

    // ================= SAVE =================
    async handleSave() {
        if (this.isSubmitting) return;
        this.isSubmitting = true;
        this.isLoading = true;
        const allValid = [
            ...this.template.querySelectorAll('lightning-input'),
            ...this.template.querySelectorAll('lightning-combobox'),
            ...this.template.querySelectorAll('lightning-radio-group'),
            ...this.template.querySelectorAll('lightning-record-picker')
        ];
        let isValid = true;
        allValid.forEach(field => {
            if (!field.checkValidity()) {
                field.reportValidity();
                isValid = false;
            }
        });
        this.dynamicFields.forEach(f => {
            if (f.isHidden) return;
            if (f.isFile && f.required && (!f.images || f.images.length === 0)) {
                isValid = false;
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Warning',
                    message: `${f.label} is required`,
                    variant: 'warning'
                }));
                this.isSubmitting = false;
                this.isLoading = false;
            }
            if (!f.isFile && f.required) {
                const val = this.formData[f.apiName];
                if (val === null || val === undefined || val === '') {
                    isValid = false;
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Warning',
                        message: `${f.label} is required`,
                        variant: 'warning'
                    }));
                    this.isSubmitting = false;
                    this.isLoading = false;
                }
            }
        });
        if (!isValid) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Warning',
                message: 'Please fill all required fields',
                variant: 'Warning'
            }));
            this.isSubmitting = false;
            this.isLoading = false;
            return;
        }

        // ================= ASSET TRANSFER MANDATORY VALIDATION =================
        if (this.searchType === 'Asset Transfer Request') {
            const requestType = this.formData['Request_type__c'];
            if (!requestType) {
                isValid = false;
                this.dispatchEvent(new ShowToastEvent({ title: 'Warning', message: 'Request Type is required', variant: 'warning' }));
                this.isSubmitting = false;
                this.isLoading = false;
            }
            if (requestType === 'Outlet to Outlet' &&
                (!this.formData['Retailer_Transfer_To__c'] || this.formData['Retailer_Transfer_To__c'] === '')) {
                isValid = false;
                this.dispatchEvent(new ShowToastEvent({ title: 'Warning', message: 'Retailer (Transfer To) is required', variant: 'warning' }));
                this.isSubmitting = false;
                this.isLoading = false;
            }
            if (requestType === 'Outlet to Distributor' &&
                (!this.formData['Distributor_Transfer_To__c'] || this.formData['Distributor_Transfer_To__c'] === '')) {
                isValid = false;
                this.dispatchEvent(new ShowToastEvent({ title: 'Warning', message: 'Distributor (Transfer To) is required', variant: 'warning' }));
                this.isSubmitting = false;
                this.isLoading = false;
            }
           if (requestType === 'Distributor to Outlet' &&
                (!this.formData['Retailer_Transfer_To__c'] || this.formData['Retailer_Transfer_To__c'] === '')) {
                isValid = false;
                this.dispatchEvent(new ShowToastEvent({ title: 'Warning', message: 'Retailer (Transfer To) is required', variant: 'warning' }));
                this.isSubmitting = false;
                this.isLoading = false;
            }
            if (requestType === 'Distributor to Distributor' &&
                (!this.formData['Distributor_Transfer_To__c'] || this.formData['Distributor_Transfer_To__c'] === '')) {
                isValid = false;
                this.dispatchEvent(new ShowToastEvent({ title: 'Warning', message: 'Distributor (Transfer To) is required', variant: 'warning' }));
                this.isSubmitting = false;
                this.isLoading = false;
            }
            
            if (requestType === 'Scrap' &&
                (!this.formData['Retailer_Transfer_From__c'] || this.formData['Retailer_Transfer_From__c'] === '') &&
                (!this.formData['Distributor_Transfer_From__c'] || this.formData['Distributor_Transfer_From__c'] === '')) {
                isValid = false;
                this.dispatchEvent(new ShowToastEvent({ title: 'Warning', message: 'Transfer From is required for Scrap', variant: 'warning' }));
                this.isSubmitting = false;
                this.isLoading = false;
            }
            if (!isValid) return;
        }

        const visibleFields = this.dynamicFields.filter(f => !f.isHidden).map(f => f.apiName);
        let filteredFormData = {};
        visibleFields.forEach(field => {
            if (this.formData[field] !== undefined) filteredFormData[field] = this.formData[field];
        });
        const alwaysIncludeFields = ['Case_Type__c'];
        // The Branding Return Case writes these straight into formData from the
        // asset selector. They are not Form_Field__c rows for this case type, so
        // the visibleFields filter above would otherwise drop them and the case
        // would insert with no branding asset.
        if (this.isReturnCaseType) {
            alwaysIncludeFields.push('Branding_Asset__c', 'Asset_ID__c', 'Media_Type__c', 'Media_Sub_type__c');
        }
        alwaysIncludeFields.forEach(field => {
            if (this.formData[field] !== undefined) filteredFormData[field] = this.formData[field];
        });

        try {
            // ================= DUPLICATE CHECK FOR EXISTING ASSET CODE CHANGE =================
            if (this.searchType === 'Existing outlet Asset Code Change Request' && filteredFormData.New_Asset_Code__c) {
                const dupResult = await checkNewAssetCode({ assetCode: filteredFormData.New_Asset_Code__c });
                if (dupResult !== 'OK') {
                    const parts = dupResult.split(':');
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Error',
                        message: `Asset Code ${filteredFormData.New_Asset_Code__c} already exists in case ${parts[1]} with status "${parts[2]}". Cannot proceed.`,
                        variant: 'error'
                    }));
                    this.isSubmitting = false;
                    this.isLoading = false;
                    return;
                }
            }

            // ================= DUPLICATE CHECK FOR ASSET ADDITION =================
            if (this.searchType === 'Asset Tagging Request' && filteredFormData.New_Asset_Code__c) {
                const masterResult = await checkAssetCodeInMaster({ assetCode: filteredFormData.New_Asset_Code__c });
                if (masterResult === 'DUPLICATE_MASTER') {
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Error',
                        message: 'This QR code already exists in Asset Master. Please use a different code.',
                        variant: 'error'
                    }));
                    this.isSubmitting = false;
                    this.isLoading = false;
                    return;
                }
                if (masterResult === 'INVALID_PREFIX') {
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Error',
                        message: 'New Asset Code must start with HIPL',
                        variant: 'error'
                    }));
                    this.isSubmitting = false;
                    this.isLoading = false;
                    return;
                }
            }

            // ================= DUPLICATE CHECK FOR SERIAL NUMBER =================
            if ((this.searchType === 'Asset Tagging Request' ||
                 this.searchType === 'Existing outlet Asset Code Change Request') &&
                 filteredFormData.Serial_Number__c) {
                const serialResult = await checkSerialNumber({ serialNumber: filteredFormData.Serial_Number__c });
                if (serialResult !== 'OK') {
                    if (serialResult === 'DUPLICATE_MASTER') {
                        this.dispatchEvent(new ShowToastEvent({
                            title: 'Error',
                            message: 'This Serial Number already exists in Asset Master.',
                            variant: 'error'
                        }));
                    } else {
                        const parts = serialResult.split(':');
                        this.dispatchEvent(new ShowToastEvent({
                            title: 'Error',
                            message: `Serial Number already exists in case ${parts[1]} with status "${parts[2]}".`,
                            variant: 'error'
                        }));
                    }
                    this.isSubmitting = false;
                    this.isLoading = false;
                    return;
                }
            }

            if (this.isReturnCaseType) {
                if (this.brandingAssetError) {
                    this.isSubmitting = false; this.isLoading = false;
                    return;
                }
                if (!this.selectedBrandingAssetId) {
                    this.brandingAssetError = 'Select the branding asset being returned.';
                    this.isSubmitting = false; this.isLoading = false;
                    return;
                }
                // Re-check at submit: another rep may have raised one meanwhile.
                const pending = await hasPendingReturnCase({ brandingAssetId: this.selectedBrandingAssetId });
                if (pending) {
                    this.brandingAssetError = 'A pending return case already exists for this asset';
                    this.isSubmitting = false; this.isLoading = false;
                    return;
                }
            }

            let caseId;
            if (this.isInventoryCaseType) {
                const completeLines = this.mediaLines.filter(l => this.isMediaLineComplete(l));
                if (completeLines.length === 0) {
                    this.mediaLineError = 'Add at least one complete media item before submitting.';
                    this.isSubmitting = false;
                    this.isLoading = false;
                    return;
                }
                caseId = await saveCaseWithLines({
                    formData: filteredFormData,
                    lines: completeLines.map(l => ({
                        mediaType: l.mediaType,
                        mediaSubType: l.mediaSubType,
                        quantity: l.quantity,
                        photoName: l.photoName,
                        // Strip the data: prefix - Apex expects raw base64.
                        photoBase64: l.photoUrl ? l.photoUrl.split(',')[1] : null
                    }))
                });
            } else {
                caseId = await saveCase({ formData: filteredFormData });
            }
            let hasImages = this.dynamicFields.some(f => f.isFile && f.images && f.images.length > 0);
            if (hasImages) await this.uploadImages(caseId);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: this.isReturnCaseType
                    ? 'Branding asset Vendor transfer has been initiated.'
                    : 'Case Created Successfully',
                variant: 'success'
            }));
            this.formData = {};
            this.dynamicFields = [];
            this.isFormScreen = false;
            this.isHideAddIcon = true;
            this.loadCases();
        } catch (error) {
            this.showError('Error saving case', error);
            this.isSubmitting = false;
        } finally {
            this.isLoading = false;
        }
    }

   openCamera(event) {
    const index = event.currentTarget.dataset.index;
    const allInputs = Array.from(this.template.querySelectorAll('input[data-type="camera"]'));
    const input = allInputs.find(i => i.dataset.index === index);
    if (input) input.click();
}

    async handleFileChange(event) {
        const target = event.target;
        if (!target) return;
        const container = target.closest('[data-field]');
        if (!container) return;
        const index = container.dataset.index;
        const files = target.files;
        if (!files || files.length === 0) return;
        let field = this.dynamicFields[index];
        if (!field.images) field.images = [];
        if (field.images.length + files.length > MAX_PHOTOS) {
            this.showError('Error', { message: 'Only one photo is allowed. Remove the existing photo first.' });
            return;
        }
        this.fileError = '';
        const getSize = (base64) => (base64.length * 3) / 4;
        for (const file of files) {
            const alreadyExists = field.images.some(img => img.fileName === file.name);
            if (alreadyExists) continue;
            if (field.images.length >= MAX_PHOTOS) { this.showError('Error', { message: 'Only one photo is allowed. Remove the existing photo first.' }); continue; }
            if (!['image/jpeg', 'image/png'].includes(file.type)) { this.showError('Error', { message: 'Only JPG/PNG allowed' }); continue; }
            if (file.size > 5 * 1024 * 1024) {
                this.showError('Error', { message: `File is too large (${(file.size / (1024 * 1024)).toFixed(1)} MB). File size must be less than 5 MB.` });
                continue;
            }
            try {
                const compressed = await this.compressToJpegWithQuality(file, 1.5);
                let currentSize = field.images.reduce((total, img) => total + getSize(img.url), 0);
                let totalSize = currentSize + getSize(compressed);
                if (totalSize > 1.5 * 1024 * 1024) { this.showError('Error', { message: 'Total images must be under 1.5 MB' }); continue; }
                const newImage = { id: Date.now() + Math.random(), url: compressed, fileName: file.name.replace(/\.[^/.]+$/, ".jpg") };
                field.images = [...field.images, newImage];
                this.dynamicFields[index] = { ...field, hasPhoto: field.images.length >= MAX_PHOTOS };
                this.dynamicFields = [...this.dynamicFields];
            } catch (error) {
                this.showError('Error', { message: 'Image processing failed' });
            }
        }
        if (target) target.value = null;
    }

    compressToJpegWithQuality(file, maxSizeMB = 1.5) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = (e) => {
                const img = new Image();
                img.onload = () => {
                    try {
                        const canvas = document.createElement('canvas');
                        const ctx = canvas.getContext('2d');
                        const MAX_WIDTH = 800;
                        const scale = MAX_WIDTH / img.width;
                        canvas.width = MAX_WIDTH;
                        canvas.height = img.height * scale;
                        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
                        let quality = 0.9;
                        let compressed = '';
                        let size = 0;
                        const maxBytes = maxSizeMB * 1024 * 1024;
                        do {
                            compressed = canvas.toDataURL('image/jpeg', quality);
                            size = (compressed.length * 3) / 4;
                            quality -= 0.1;
                        } while (size > maxBytes && quality > 0.2);
                        resolve(compressed);
                    } catch (err) { reject(err); }
                };
                img.onerror = reject;
                img.src = e.target.result;
            };
            reader.onerror = reject;
            reader.readAsDataURL(file);
        });
    }

    removeImage(event) {
        const id = event.currentTarget.dataset.id;
        const index = event.currentTarget.dataset.index;
        let field = this.dynamicFields[index];
        const updatedImages = field.images.filter(img => img.id != id);
        this.dynamicFields[index] = {
            ...field,
            images: updatedImages,
            hasPhoto: updatedImages.length >= MAX_PHOTOS
        };
        this.dynamicFields = [...this.dynamicFields];
        this.fileError = '';
    }

    async uploadImages(caseId) {
        this.uploadedFiles = [];
        this.dynamicFields.forEach(f => {
            if (f.isFile && f.images) {
                f.images.forEach(img => {
                    this.uploadedFiles.push({ fileName: img.fileName, base64: img.url.split(',')[1] });
                });
            }
        });
        await uploadFiles({ caseId: caseId, files: this.uploadedFiles });
    }
}