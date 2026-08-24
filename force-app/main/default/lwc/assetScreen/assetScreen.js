import { LightningElement, api, track, wire } from 'lwc';
import getAssets from '@salesforce/apex/CaseScreenController.getAssets';
import getUnproductiveReason from '@salesforce/apex/CaseScreenController.getUnproductiveReason';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import ASSET_AUDIT_OBJECT from '@salesforce/schema/Asset_Audit__c';
import REASON_FIELD from '@salesforce/schema/Asset_Audit__c.Reason__c';
import createAssetAudit from '@salesforce/apex/CaseScreenController.createAssetAudit';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getBarcodeScanner } from 'lightning/mobileCapabilities';
import defaultImage from '@salesforce/resourceUrl/defaultImage';

export default class AssetScreen extends LightningElement {
    @api visitTaskId;
    @track showScannedDetail = false;
    @track assets = [];
    @track showSkipModal = false;
    @track selectedReason = '';
    @track selectedAssetMappingId;
    @track showScanPopup = false;
    @track scannedAsset = null;
    @track searchReason = '';
    @track showReasonDropdown = false;
    @track reasonOptions = [];
    @track showManualEntry = false;
    @track manualSerial = '';
    @track scannedValue = '';
    @api isFromCheckout = false;
    @track isLoading = false;
       isSkipEnabled = false;
    unproductiveReason = '';
    scanner;
    recordTypeId;

    // ================= INIT =================
    connectedCallback() {
        this.loadAssets();
        this.scanner = getBarcodeScanner();
        this.loadUnproductiveReason();
    }

    // ================= LOAD UNPRODUCTIVE REASON =================
    loadUnproductiveReason() {
        if (!this.visitTaskId) return;
        getUnproductiveReason({ visitTaskId: this.visitTaskId })
            .then(reason => {
                const allowed = ['Shop closed', 'Joint Visit'];
                this.isSkipEnabled = reason && allowed.includes(reason);
                this.unproductiveReason = reason || '';
            })
            .catch(error => {
                console.error('Error loading unproductive reason:', error);
                this.isSkipEnabled = false;
            });
    }

    // ================= LOAD ASSETS =================
    get noAssets() {
        return !this.assets || this.assets.length === 0;
    }

    loadAssets() {
        this.isLoading = true;
        getAssets({ visitTaskId: this.visitTaskId })
            .then(result => {
                this.assets = result.map(a => ({
                    ...a,
                    isAuditedToday: a.isAuditedToday,
                    isSkipped: a.isSkipped,
                    isScanned: a.isScanned,
                    status: a.active ? 'Active' : 'Deactivate',
                    cardClass: a.isAuditedToday ? 'asset-card asset-card-gray' : 'asset-card',
                    finalImage: a.imageUrl ? a.imageUrl : defaultImage
                }));
                this.isLoading = false;
            })
            .catch(error => {
                console.error(error);
                this.showError(error, 'Something went wrong');
            });
    }

    // ================= WIRE =================
    @wire(getObjectInfo, { objectApiName: ASSET_AUDIT_OBJECT })
    objectInfo({ data }) {
        if (data) this.recordTypeId = data.defaultRecordTypeId;
    }

    @wire(getPicklistValues, { recordTypeId: '$recordTypeId', fieldApiName: REASON_FIELD })
    picklistHandler({ data }) {
        if (data) this.reasonOptions = data.values;
    }

    // ================= SKIP =================
   handleSkipClick(event) {
    if (!this.isSkipEnabled) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Not Allowed',
            message: 'Skip is only allowed when visit reason is Shop closed or Joint Visit.',
            variant: 'warning'
        }));
        return;
    }
    this.selectedAssetMappingId = event.currentTarget.dataset.id;
    // Submit directly without showing modal
    createAssetAudit({
        mappingId: this.selectedAssetMappingId,
        reason: null,
        type: 'SKIP',
        visitTaskId: this.visitTaskId
    })
    .then(() => {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Success',
            message: 'Asset Audit Created',
            variant: 'success'
        }));
        this.updateAssetStatus('SKIPPED');
    })
    .catch(error => {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Warning',
            message: error.body.message,
            variant: 'warning'
        }));
    });
}

    handleReasonClick() {
        this.showReasonDropdown = true;
    }

    handleReasonSearch(event) {
        this.searchReason = event.target.value.toLowerCase();
        this.showReasonDropdown = true;
    }

   get filteredReasons() {
    const allowed = ['Shop Closed', 'Joint Visit'];
    return allowed.filter(r => r.toLowerCase().includes(this.searchReason));
}
    selectReason(event) {
        this.selectedReason = event.currentTarget.dataset.value;
        this.searchReason = this.selectedReason;
        this.showReasonDropdown = false;
    }

    clearReason() {
        this.selectedReason = '';
        this.searchReason = '';
        this.showReasonDropdown = true;
    }

    closeModal() {
        this.showSkipModal = false;
        this.showReasonDropdown = false;
        document.body.style.overflow = 'auto';
    }

   handleSkipSubmit() {
    if (!this.selectedReason) {
        this.selectedReason = this.unproductiveReason;
    }

        if (!this.selectedAssetMappingId) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Asset Audit Failed',
                variant: 'error'
            }));
            return;
        }
        createAssetAudit({
            mappingId: this.selectedAssetMappingId,
            reason: this.selectedReason,
            type: 'SKIP',
            visitTaskId: this.visitTaskId
        })
        .then(() => {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Asset Audit Created',
                variant: 'success'
            }));
            this.updateAssetStatus('SKIPPED');
            this.showSkipModal = false;
        })
        .catch(error => {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Warning',
                message: error.body.message,
                variant: 'warning'
            }));
        });
    }

    // ================= UPDATE STATUS =================
    updateAssetStatus(type) {
        this.assets = this.assets.map(a => {
            if (a.mappingId === this.selectedAssetMappingId || a.mappingId === this.scannedAsset?.mappingId) {
                return {
                    ...a,
                    isAuditedToday: true,
                    auditType: type,
                    isSkipped: type === 'SKIPPED',
                    isScanned: type === 'SCANNED',
                    cardClass: a.isAuditedToday ? 'asset-card asset-card-gray' : 'asset-card'
                };
            }
            return a;
        });
    }

    // ================= NAVIGATION =================
    handleBack() {
        if (this.showScannedDetail) {
            this.showScannedDetail = false;
            return;
        }
        if (this.showSkipModal) {
            this.showSkipModal = false;
        } else {
            this.dispatchEvent(new CustomEvent('back'));
        }
    }

    // ================= SCAN =================
    handleScanClick(event) {
    this.selectedAssetMappingId = event.currentTarget.dataset.id;
    this.scanner = getBarcodeScanner();
    this.showScanPopup = true;
    document.body.style.overflow = 'hidden';
}

  handleScanNow() {
    if (!this.scanner || !this.scanner.isAvailable()) {
        this.showScanPopup = false;
        this.showManualEntry = true;
        return;
    }
    const scanningOptions = {
        cameraFacing: 'BACK',
        showSuccessCheckMark: true,
        enableBulkScan: false,
        enableMultiScan: false,
        enableScanLine: true
    };
    this.scanner.scan(scanningOptions)
        .then(results => {
            this.scanner.dismiss();
            this.processScannedBarcodes(results);
        })
        .catch(error => {
            this.scanner.dismiss();
            this.processError(error);
            this.showError(error, 'Something went wrong');
        });
}

    processScannedBarcodes(results) {
        if (results && results.length > 0) {
            const scanned = results[0].value;
            this.scannedValue = scanned;
            this.handleScanSuccess(scanned);
        } else {
            console.warn('No barcode found');
        }
    }

    processError(error) {
        if (error.code === 'USER_DISMISSED') {
            console.log('User terminated scanning session.');
        } else {
            console.error(error);
        }
    }

    handleManualFill() {
        this.showScanPopup = false;
        this.showManualEntry = true;
        document.body.style.overflow = 'hidden';
    }

    handleManualInput(event) {
        this.manualSerial = event.target.value;
    }

    handleManualNext() {
    if (!this.manualSerial) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message: 'Please enter QR Code Number',
            variant: 'error'
        }));
        return;
    }
    const matchedAsset = this.assets.find(a =>
        a.qrCode?.toLowerCase().trim() === this.manualSerial?.toLowerCase().trim()
    );
    if (matchedAsset) {
        // Validate scanned asset matches the selected asset
        if (matchedAsset.mappingId !== this.selectedAssetMappingId) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Entered QR code does not match the selected asset. Please enter the correct QR code.',
                variant: 'error'
            }));
            return;
        }
        this.scannedAsset = matchedAsset;
        this.showManualEntry = false;
        this.showScannedDetail = true;
        this.showScanPopup = false;
        this.manualSerial = null;
    } else {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message: 'Asset not found',
            variant: 'error'
        }));
    }
}
    handleCancelScan() {
        this.showScanPopup = false;
        this.showManualEntry = false;
        document.body.style.overflow = 'hidden';
    }

    handleScanSuccess(scannedValue) {
    const matchedAsset = this.assets.find(a =>
        a.qrCode?.toLowerCase().trim() === scannedValue?.toLowerCase().trim()
    );
    console.log('scannedValue:', scannedValue);
    console.log('matchedAsset:', matchedAsset);
    console.log('matchedAsset.mappingId:', matchedAsset?.mappingId);
    console.log('selectedAssetMappingId:', this.selectedAssetMappingId);
    if (matchedAsset) {
        // Validate scanned asset matches the selected asset
        if (matchedAsset.mappingId !== this.selectedAssetMappingId) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Scanned QR code does not match the selected asset. Please scan the correct asset.',
                variant: 'error'
            }));
            return;
        }
        this.scannedAsset = matchedAsset;
        this.showScannedDetail = true;
        this.showScanPopup = false;
    } else {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message: 'No matching asset found',
            variant: 'error'
        }));
    }
}

    // ================= AUDIT =================
    get attributeList() {
        if (!this.scannedAsset || !this.scannedAsset.attributes) return [];
        return Object.keys(this.scannedAsset.attributes).map(key => ({
            label: key,
            value: this.scannedAsset.attributes[key]
        }));
    }

    handleAuditClick() {
        if (!this.selectedAssetMappingId && !this.scannedAsset) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'No asset selected',
                variant: 'error'
            }));
            return;
        }
        const mappingId = this.scannedAsset ? this.scannedAsset.mappingId : this.selectedAssetMappingId;
        createAssetAudit({
            mappingId: mappingId,
            reason: null,
            type: 'SCAN',
            visitTaskId: this.visitTaskId
        })
        .then(() => {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Asset Audit Created',
                variant: 'success'
            }));
            this.updateAssetStatus('SCANNED');
            this.showScannedDetail = false;
        })
        .catch(error => {
            console.error(error);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Warning',
                message: error.body.message,
                variant: 'warning'
            }));
        });
    }

    // ================= ERROR =================
    showError(error, fallback) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message: error?.body?.message || fallback,
            variant: 'error'
        }));
    }
}