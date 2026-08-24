import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getBrandingAssets from '@salesforce/apex/CaseScreenController.getBrandingAssets';
import getBrandingAssetPhotos from '@salesforce/apex/CaseScreenController.getBrandingAssetPhotos';
import getBrandingAuditStatus from '@salesforce/apex/CaseScreenController.getBrandingAuditStatus';
import getBrandingAuditWindow from '@salesforce/apex/CaseScreenController.getBrandingAuditWindow';
import submitBrandingAudit from '@salesforce/apex/CaseScreenController.submitBrandingAudit';
import defaultImage from '@salesforce/resourceUrl/defaultImage';

const MAX_FILE_BYTES = 5 * 1024 * 1024;

export default class MappedBranding extends LightningElement {
    @api visitTaskId;
    @api isCheckInDone = false;
    // Unproductive_Reasons__c on the visit task, resolved by the parent.
    @api unproductiveReason;
    @track lines = [];
    error;
    lineError = '';
    loaded = false;
    saving = false;

    // Viewing the assets is never restricted. These only decide whether the
    // audit FORM is offered.
    @track auditDue = false;
    @track alreadySubmitted = false;
    @track visitNumber = 0;
    @track visitsUntilDue = 0;
    @track windowLoaded = false;
    @track windowError = '';

    conditionOptions = [
        { label: 'Present', value: 'Present' },
        { label: 'Damage',  value: 'Damage'  },
        { label: 'Missing', value: 'Missing' }
    ];

    @wire(getBrandingAssets, { visitTaskId: '$visitTaskId' })
    wiredAssets({ data, error }) {
        if (data) {
            this.lines = data.map((a, i) => ({
                index: i,
                assetId: a.Id,
                mediaType: a.Media_Type__c,
                subMedia: a.Media_Sub_Type__c,
                // The photo captured at installation, falling back to the request
                // photo. Installation_Photo__c cannot be used here - it is an
                // IMAGE() formula returning HTML, which LWC will not inject.
                assetImage: a.Installation_Image_URL__c || a.Request_Image_URL__c || defaultImage,
                assetImageFallback: this.renditionUrl(
                    a.Installation_Image_URL__c || a.Request_Image_URL__c
                ),
                audited: false,
                lastAuditedText: '',
                condition: '',
                remarks: '',
                photoUrl: '',   // full data URI, preview only
                base64: '',     // payload - data: prefix stripped
                fileName: ''
            }));
            this.error = undefined;
            this.loaded = true;
            this.loadPhotos();
            this.loadAuditStatus();
            this.loadAuditWindow();
        } else if (error) {
            this.error = (error.body && error.body.message) || 'Unable to load mapped branding.';
            this.loaded = true;
        }
    }

    // Photos arrive separately as data: URIs - see getBrandingAssetPhotos. Failing
    // to load them leaves the URL/placeholder already on each card.
    loadPhotos() {
        getBrandingAssetPhotos({ visitTaskId: this.visitTaskId })
            .then(photos => {
                if (!photos) return;
                this.lines = this.lines.map(l =>
                    photos[l.assetId] ? { ...l, assetImage: photos[l.assetId] } : l
                );
            })
            .catch(() => { /* keep whatever the card already shows */ });
    }

    // "Audited" reflects THIS visit; the date is the most recent audit whenever
    // it happened, so a card can read "not audited yet" but still show a history.
    loadAuditStatus() {
        getBrandingAuditStatus({ visitTaskId: this.visitTaskId })
            .then(statuses => {
                if (!statuses) return;
                this.lines = this.lines.map(l => {
                    const s = statuses[l.assetId];
                    if (!s) return l;
                    return {
                        ...l,
                        audited: !!s.auditedThisVisit,
                        lastAuditedText: this.formatAuditDate(s.lastAuditDate)
                    };
                });
            })
            .catch(() => { /* status is informational - never block the audit */ });
    }

    loadAuditWindow() {
        getBrandingAuditWindow({ visitTaskId: this.visitTaskId })
            .then(window => {
                if (!window) return;
                this.auditDue = !!window.auditDue;
                this.alreadySubmitted = !!window.alreadySubmitted;
                this.visitNumber = window.visitNumber;
                this.visitsUntilDue = window.visitsUntilDue;
                this.windowError = '';
                this.windowLoaded = true;
            })
            .catch(() => {
                // Could not tell - withhold the form rather than allow an audit
                // that the check-out gate will not accept. Viewing is unaffected.
                this.windowError = 'Could not check whether the branding audit is due on this visit.';
                this.windowLoaded = true;
            });
    }

    /**
     * Every condition that must hold before an audit may be SUBMITTED. Viewing
     * the assets is never gated on any of these.
     */
    get canAudit() {
        return this.windowLoaded
            && !this.windowError
            && this.auditDue
            && !this.alreadySubmitted
            && !this.isExemptVisit
            && !!this.isCheckInDone;
    }

    /**
     * The same two reasons handleCheckOutMethod treats as exempt: a closed shop
     * cannot be inspected, and a joint visit is waved through at check-out. If
     * the audit is not required to leave the outlet, it must not be filed here
     * either - otherwise the audit record claims an inspection that never happened.
     */
    get isExemptVisit() {
        return this.unproductiveReason === 'Shop closed'
            || this.unproductiveReason === 'Joint Visit';
    }

    // Warnings look different from the ordinary "not due yet" notice.
    get noticeClass() {
        return this.isExemptVisit ? 'audit-notice audit-warning' : 'audit-notice';
    }

    // Most specific reason first, so the rep is told the thing they can act on.
    get auditNotice() {
        if (!this.windowLoaded) return '';
        if (this.windowError) return this.windowError;
        if (this.alreadySubmitted) {
            return 'The branding audit for this visit has already been submitted.';
        }
        if (this.isExemptVisit) {
            return 'This visit is marked "' + this.unproductiveReason
                + '". The branding audit is not required and cannot be submitted for this visit.';
        }
        if (!this.auditDue) {
            const visits = this.visitsUntilDue;
            return 'Branding audit is due every 3rd visit. The next audit is due in ' + visits
                + (visits === 1 ? ' visit.' : ' visits.');
        }
        if (!this.isCheckInDone) {
            return 'Please check in before submitting the branding audit.';
        }
        return '';
    }

    get showAuditNotice() { return !this.canAudit && !!this.auditNotice; }

    formatAuditDate(value) {
        if (!value) return '';
        const d = new Date(value);
        if (isNaN(d.getTime())) return '';
        return 'Last Audited: ' + d.toLocaleDateString('en-GB');
    }

    /**
     * Second address for the same file. The stored link is the shepherd DOWNLOAD
     * servlet, which most orgs render fine inside an <img>; where it does not,
     * renditionDownload serves the same version as a plain image. We try the
     * stored link first and fall back to this on error, so neither endpoint has
     * to be assumed correct. Returns null for external (non-shepherd) URLs.
     */
    renditionUrl(url) {
        if (!url) return null;
        const match = url.match(/\/sfc\/servlet\.shepherd\/version\/download\/([a-zA-Z0-9]{15,18})/);
        if (!match) return null;
        return url.substring(0, url.indexOf('/sfc/')) +
            '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' +
            match[1];
    }

    /**
     * Photos degrade in two steps: stored URL -> rendition URL -> placeholder.
     * A stub or corrupt file (there are some 70-byte PNGs in QA) therefore shows
     * the placeholder rather than a broken-image icon.
     */
    handleImageError(event) {
        const img = event.target;
        const index = parseInt(img.dataset.index, 10);
        const line = this.lines[index];
        if (img.dataset.stage !== 'fallback' && line && line.assetImageFallback) {
            img.dataset.stage = 'fallback';
            img.src = line.assetImageFallback;
            return;
        }
        img.src = defaultImage;
    }

    // Every per-line flag the template needs is computed here - templates can't
    // evaluate expressions, so showPhoto is resolved into the exact branches used.
    get displayLines() {
        return this.lines.map(l => {
            const showPhoto = l.condition === 'Damage';
            return {
                ...l,
                showPhoto,
                showAddPhoto: showPhoto && !l.photoUrl,
                showPreview: showPhoto && !!l.photoUrl,
                showLastAudited: !!l.lastAuditedText,
                // Nothing to explain when the branding is simply there; Damage and
                // Missing both need a reason recorded.
                remarksRequired: !!l.condition && l.condition !== 'Present'
            };
        });
    }

    get hasAssets() { return this.lines && this.lines.length > 0; }
    get isEmpty()   { return this.loaded && !this.error && !this.hasAssets; }

    // ================= EXPAND / LIGHTBOX =================
    @track expandedImage = '';
    get showExpanded() { return !!this.expandedImage; }

    handleExpandImage(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const line = this.lines[index];
        if (!line) return;
        this.expandedImage = event.currentTarget.dataset.kind === 'photo'
            ? line.photoUrl
            : line.assetImage;
    }

    handleCloseExpanded() { this.expandedImage = ''; }

    // The parent owns the screen swap - this component only reports that it is done.
    handleBack() { this.dispatchEvent(new CustomEvent('back')); }

    // ================= FIELD HANDLERS =================
    updateLine(index, changes) {
        const updated = [...this.lines];
        updated[index] = { ...updated[index], ...changes };
        this.lines = updated;
    }

    handleCondition(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const condition = event.detail.value;
        const changes = { condition };
        // Moving off Damage discards a photo that no longer applies.
        if (condition !== 'Damage') {
            changes.photoUrl = '';
            changes.base64 = '';
            changes.fileName = '';
        }
        this.updateLine(index, changes);
        this.lineError = '';
    }

    handleRemarks(event) {
        const index = parseInt(event.target.dataset.index, 10);
        this.updateLine(index, { remarks: event.target.value });
        this.lineError = '';
    }

    // ================= PHOTO (DAMAGE ONLY) =================
    handlePhotoClick(event) {
        const index = event.currentTarget.dataset.index;
        const input = Array.from(this.template.querySelectorAll('input[data-type="branding-photo"]'))
            .find(i => i.dataset.index === index);
        if (input) input.click();
    }

    async handlePhotoChange(event) {
        // Hold on to the element before awaiting. This handler is async, and once
        // it resumes the DOM event has been recycled - event.target is then null,
        // so touching it in the finally below throws
        // "Cannot set properties of null (setting 'value')".
        const input = event.target;
        if (!input) return;

        const index = parseInt(input.dataset.index, 10);
        const file = input.files && input.files[0];
        if (!file) return;

        this.lineError = '';
        try {
            if (!['image/jpeg', 'image/png'].includes(file.type)) {
                this.lineError = 'Only JPG/PNG allowed';
                return;
            }
            if (file.size > MAX_FILE_BYTES) {
                this.lineError = `File is too large (${(file.size / (1024 * 1024)).toFixed(1)} MB). Must be under 5 MB.`;
                return;
            }
            const compressed = await this.compressToJpegWithQuality(file, 1.5);
            this.updateLine(index, {
                photoUrl: compressed,
                base64: compressed.split(',')[1],
                fileName: file.name.replace(/\.[^/.]+$/, '.jpg')
            });
        } catch (err) {
            this.lineError = 'Image processing failed';
        } finally {
            if (input) input.value = null;
        }
    }

    handleRemovePhoto(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        this.updateLine(index, { photoUrl: '', base64: '', fileName: '' });
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

    // ================= SUBMIT =================
    // Everything is wrapped: an uncaught throw here reaches the LWC error
    // boundary, which shows the user a bare "component error" and hides the cause.
    handleSubmit() {
        try {
            this.doSubmit();
        } catch (err) {
            this.saving = false;
            this.fail('Could not submit audit: ' + (err && err.message ? err.message : err));
        }
    }

    doSubmit() {
        if (!this.canAudit) {
            this.fail(this.auditNotice || 'The branding audit cannot be submitted on this visit.');
            return;
        }
        for (const l of this.lines) {
            if (!l.condition) {
                this.fail('Select a condition for every asset.');
                return;
            }
            // Remarks are optional when the branding is Present.
            if (l.condition !== 'Present' && (!l.remarks || !l.remarks.trim())) {
                this.fail('Enter remarks for every asset marked ' + l.condition + '.');
                return;
            }
            if (l.condition === 'Damage' && !l.base64) {
                this.fail('Add a photo for every asset marked Damage.');
                return;
            }
        }

        this.saving = true;
        const payload = this.lines.map(l => ({
            brandingAssetId: l.assetId,
            mediaType: l.mediaType,
            subMedia: l.subMedia,
            condition: l.condition,
            remarks: l.remarks,
            fileName: l.fileName || null,
            base64: l.base64 || null
        }));

        submitBrandingAudit({ visitTaskId: this.visitTaskId, lines: payload })
            .then(() => {
                this.toast('Success', 'Branding audit submitted.', 'success');
                this.saving = false;
                // Close the form immediately - a double tap must not file a second audit.
                this.alreadySubmitted = true;
                this.handleBack();
            })
            .catch(err => {
                this.saving = false;
                this.fail('Could not submit audit: ' + this.describeError(err));
            });
    }

    // Apex errors, page-level errors and plain JS errors all arrive shaped
    // differently; show whichever text actually exists rather than a generic line.
    describeError(err) {
        if (!err) return 'unknown error';
        if (err.body) {
            if (err.body.message) return err.body.message;
            if (err.body.pageErrors && err.body.pageErrors.length) {
                return err.body.pageErrors.map(e => e.message).join('; ');
            }
            if (Array.isArray(err.body) && err.body.length) return err.body[0].message;
        }
        return err.message || err.statusText || JSON.stringify(err);
    }

    fail(message) {
        this.lineError = message;
        this.toast('Error', message, 'error');
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}