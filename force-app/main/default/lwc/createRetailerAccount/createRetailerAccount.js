// createRetailerAccount.js
import {LightningElement,api,track,wire} from 'lwc';
import {NavigationMixin} from 'lightning/navigation';
import checkDuplicateOwnerNumber from '@salesforce/apex/RetailerAccountController.checkDuplicateOwnerNumber';
import createAccount from '@salesforce/apex/RetailerAccountController.createAccount';
import getDistributorFromVisitTask from '@salesforce/apex/RetailerAccountController.getDistributorFromVisitTask';
import uploadSelfie from '@salesforce/apex/RetailerAccountController.uploadSelfie';
import {ShowToastEvent} from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import ACCOUNT_OBJECT from '@salesforce/schema/Account';
import STATE_VALUES from '@salesforce/label/c.State_Values'; 
import getBeatsForCurrentUser from '@salesforce/apex/RetailerAccountController.getBeatsForCurrentUser';
import OUTLETS_TYPE_FIELD from '@salesforce/schema/Account.Outlets_Type__c';
import OUTLETS_CHANNEL from '@salesforce/schema/Account.Outlets_Channel__c';

// --- Geolocation capture constants (Part 1 fix) ---
const READINGS_TO_AVERAGE  = 5;
const READING_TIMEOUT_MS   = 20000;
const MAX_READING_ACCURACY = 100;   // per-reading hard reject (metres)
const MIN_FINISH_ACCURACY  = 50;    // final guard (metres)

function weightedAverage(readings) {
    const totalW = readings.reduce((s, r) => s + r.weight, 0);
    const lat    = readings.reduce((s, r) => s + r.lat * r.weight, 0) / totalW;
    const lng    = readings.reduce((s, r) => s + r.lng * r.weight, 0) / totalW;
    return [lat, lng];
}

function bestAccuracy(readings) {
    return Math.min(...readings.map(r => r.accuracy));
}
// --- End geolocation constants ---


export default class CreateRetailerAccount extends NavigationMixin(LightningElement) {
    userId = USER_ID;
    @track hasShippingAddress = false;
    @api visitTaskId;
    @track beatOptions = [];
    @track beatName = '';
    // Form Fields
    @track retailerName = '';
    @track ownerName = '';
    @track ownerNumber = '';
    @track retailerType = '';
    @track outletChannel = '';
    @track gstin = '';
    @track pan = '';
    @track fssai = '';
    @track address = {
        street: '',
        city: '',
        province: '', // State
        postalCode: '',
        country: ''
    };

    @track shippingAddress = {
        street: '',
        city: '',
        country: '',
        province: '',
        postalCode: ''
    };

    // Image Capture
    @track isCameraOn = false;
    @track photoURL = null;
    videoStream = null;
    @track selfieFile;

    // Location Search
    @track searchKey = '';
    @track results = [];
    @track selectedLocation = '';
    timeout;

    // Picklist Options
    @track retailerTypeOptions = [];
    @track outletChannelOptions = [];
    @track retailerStateOptions = [];

    // System Properties
    distributorId;
    latitude;
    longitude;
    accuracy; // tracks GPS accuracy of the captured fix
    locationTimestamp;
    recordTypeId;
    @track duplicateError = false;
    @track isLoading = false;

    connectedCallback() {
        this.loadSavedData();
        this.getDistributor();
        this.getStateValues();
        this.loadBeats(); 
    }

    handleShippingCheckbox(event) {
        this.hasShippingAddress = event.target.checked;
    }

    @wire(getObjectInfo, { objectApiName: ACCOUNT_OBJECT })
    objectInfoHandler({ data, error }) {
        if (data) {
            const rtInfos = data.recordTypeInfos;
            for (const rtId in rtInfos) {
                if (rtInfos[rtId].name === 'Retailer') {
                    this.recordTypeId = rtId;
                    break;
                }
            }
        } 
    }

    @wire(getPicklistValues, {
        recordTypeId: '$recordTypeId',
        fieldApiName: OUTLETS_TYPE_FIELD
    })
    wiredOutletTypeValues({ data, error }) {
        if (data) {
            this.retailerTypeOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));
        } else if (error) {
            console.error('Error loading Outlet Type picklist', error);
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$recordTypeId',
        fieldApiName: OUTLETS_CHANNEL
    })
    wiredOutletChannelValues({ data, error }) {
        if (data) {
            this.outletChannelOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));
        } else if (error) {
            console.error('Error loading Outlet Channel picklist', error);
        }
    }

    // Local Storage Handling
    get storageKey() {
        return `retailerAccountDraft_${this.userId}`;
    }
    // NEW METHOD TO LOAD BEAT OPTIONS
    loadBeats() {
        getBeatsForCurrentUser()
            .then(result => {
                this.beatOptions = result.map(item => ({
                    label: item.Name,
                    value: item.Id
                }));
            })
            .catch(error => {
                throw this.showToast('Error', error.body?.message || 'Error loading beats', 'error') || error;

            });
    }

    // NEW METHOD TO HANDLE BEAT SELECTION
    handleBeatChange(event) {
        this.beatName = event.detail.value;
        this.saveData();
    }

    saveData() {
        const dataToSave = {
            retailerName: this.retailerName,
            ownerName: this.ownerName,
            ownerNumber: this.ownerNumber,
            retailerType: this.retailerType,
            outletChannel:this.outletChannel,
            gstin: this.gstin,
            pan: this.pan,
            beat:  this.beatName,
            beatName: this.beatName,
            fssai: this.fssai,
            address: {
                ...this.address
            },
            searchKey: this.searchKey,
            selectedLocation: this.selectedLocation,
            selfieFile: this.selfieFile,
            photoURL: this.photoURL
        };
        localStorage.setItem(this.storageKey, JSON.stringify(dataToSave));
    }

    loadSavedData() {
        const savedData = JSON.parse(localStorage.getItem(this.storageKey));
        if (savedData) {
            this.retailerName = savedData.retailerName || '';
            this.ownerName = savedData.ownerName || '';
            this.ownerNumber = savedData.ownerNumber || '';
            this.retailerType = savedData.retailerType || '';
            this.gstin = savedData.gstin || '';
            this.pan = savedData.pan || '';
             this.beatName = savedData.beat || ''; 
            this.fssai = savedData.fssai || '';
            this.address = savedData.address || {
                ...this.address
            };
            this.searchKey = savedData.searchKey || '';
            this.selectedLocation = savedData.selectedLocation || '';
            this.selfieFile = savedData.selfieFile || null;
            this.photoURL = savedData.photoURL || null;
        }
    }


    get mapMarkers() {
        return [{
            location: {
                Latitude: this.latitude,
                Longitude: this.longitude
            },
            title: 'Retailer Location',
            description: 'Retailer location based on coordinates'
        }];
    }

    get mapCenter() {
        return {
            latitude: this.latitude,
            longitude: this.longitude
        };
    }

    openInGoogleMaps() {
        const url = `https://www.google.com/maps/search/?api=1&query=${this.latitude},${this.longitude}`;
        window.open(url, '_blank');
    }


    // Address Handling
    handleAddressChange(event) {
        this.address = {
            ...this.address,
            ...event.detail
        };
        this.saveData();
    }

    handleShippingAddressChange(event) {
        this.shippingAddress = {
            ...this.shippingAddress,
            ...event.detail
        };
    }

    setLoading(loading) {
        this.isLoading = loading;
    }

    // Reset input validity
    resetValidity(fieldName) {
        const input = this.template.querySelector(`lightning-input[data-field="${fieldName}"]`);
        if (input) {
            input.setCustomValidity('');
            input.reportValidity();
        }
    }

    // Get state values from custom label
    getStateValues() {
        this.retailerStateOptions = STATE_VALUES.split(',').map(item => ({
            label: item.trim(),
            value: item.trim()
        }));        
    }    

    handleSelect(event) {
        const selectedText = event.target.innerText;
        const selectedData = this.results.find(place => place.display_name === selectedText);
        const addr = selectedData.address || {};

        this.address = {
            street: addr.road || '',
            city: addr.city || addr.town || addr.village || '',
            province: addr.state || '',
            postalCode: addr.postcode || '',
            country: addr.country || ''
        };

        this.selectedLocation = selectedText;
        this.searchKey = selectedText;
        this.results = [];
        this.saveData();
    }

    // Image Capture Functions
    async startCamera() {
        try {
            this.isCameraOn = true;
            this.videoStream = await navigator.mediaDevices.getUserMedia({
                video: {
                    facingMode: "environment"
                }
            });
            this.template.querySelector('.video-feed').srcObject = this.videoStream;
        } catch (error) {
            this.isCameraOn = false;
            throw this.showToast('Error', error.body?.message || "Camera error:", 'error') || error;
        }
    }

    capturePhoto() {
        const video = this.template.querySelector('.video-feed');
        const canvas = this.template.querySelector('.hidden-canvas');
        const context = canvas.getContext('2d');

        canvas.width = video.videoWidth;
        canvas.height = video.videoHeight;
        context.drawImage(video, 0, 0, canvas.width, canvas.height);

        canvas.toBlob((blob) => {
            const reader = new FileReader();
            reader.readAsDataURL(blob);
            reader.onloadend = () => {
                this.selfieFile = reader.result.split(',')[1];
                this.photoURL = URL.createObjectURL(blob);
                this.stopCamera();
                this.saveData();
            };
        }, 'image/jpeg', 0.7);
    }

    stopCamera() {
        if (this.videoStream) {
            this.videoStream.getTracks().forEach(track => track.stop());
        }
        this.isCameraOn = false;
    }

    // Validation and Submission
    validateForm() {
        let isValid = true;
        let missingFields = [];
        let firstInvalidInput = null;

        const inputs = this.template.querySelectorAll('lightning-input, lightning-combobox');
        inputs.forEach(input => {
            if (input.required && !input.value) {
                input.setCustomValidity('This field is required');
                input.reportValidity();
                isValid = false;
                missingFields.push(input.label);
                if (!firstInvalidInput) firstInvalidInput = input;
            } else {
                input.setCustomValidity('');
                input.reportValidity();
            }
        });

        // Billing state
        if (!this.address.province) {
            isValid = false;
            missingFields.push('Billing State');
        }

        // Shipping state if checkbox is checked
        if (this.hasShippingAddress && !this.shippingAddress.province) {
            isValid = false;
            missingFields.push('Shipping State');
        }

        // Phone number
        if (!/^\d{10}$/.test(this.ownerNumber)) {
            isValid = false;
            missingFields.push('Phone Number (10 digits)');
        }

        // Retailer image
        if (!this.photoURL) {
            isValid = false;
            missingFields.push('Retailer Image');
        }

        // **Outlet Channel mandatory**
        if (!this.outletChannel) {
            isValid = false;
            missingFields.push('Outlet Channel');
        }

        if (!isValid) {
            this.showToast(
                'Missing or Invalid Fields',
                `Please check the following: ${missingFields.join(', ')}`,
                'error'
            );
            if (firstInvalidInput) firstInvalidInput.focus();
        }
        return isValid;
    }

    async handleSave() {
        try {
            const accountData = {
                Name: this.retailerName,
                Owners_Name__c: this.ownerName,
                Owners_Number__c: this.ownerNumber,
                Outlets_Type__c: this.retailerType,
                Outlets_Channel__c: this.outletChannel,
                GSTIN__c: this.gstin,
                PAN_Number__c: this.pan,
                FSSAI__c: this.fssai,

                // Billing address
                BillingStreet: this.address.street,
                BillingCity: this.address.city,
                BillingState: this.address.province,
                BillingPostalCode: this.address.postalCode,
                BillingCountry: this.address.country,

                Latitude__c: this.latitude,
                Longitude__c: this.longitude,
                Capture_Accuracy__c: this.accuracy,   // persist GPS accuracy at creation time
                RecordTypeId: this.recordTypeId,
                Beats_Name__c: this.beatName,
                Distributor__c: this.distributorId,

                // Primary Address 1 (Billing full string)
                Primary_Address_1__c: [
                    this.address.street,
                    this.address.city,
                    this.address.province,
                    this.address.postalCode,
                    this.address.country
                ].filter(part => part).join(', '),

                // Checkbox flag
                Has_Shipping_Address__c: this.hasShippingAddress,

                //Always include shipping details
                ShippingStreet: this.shippingAddress.street,
                ShippingCity: this.shippingAddress.city,
                ShippingState: this.shippingAddress.province,
                ShippingPostalCode: this.shippingAddress.postalCode,
                ShippingCountry: this.shippingAddress.country,

                // Primary Address 2 (Shipping full string)
                Primary_Address_2__c: [
                    this.shippingAddress.street,
                    this.shippingAddress.city,
                    this.shippingAddress.province,
                    this.shippingAddress.postalCode,
                    this.shippingAddress.country
                ].filter(part => part).join(', ')
            };

            const isDuplicate = await checkDuplicateOwnerNumber({
                ownerNumber: this.ownerNumber
            });
            if (isDuplicate) {
                this.showToast('Error', 'Owner Number already exists!', 'error');
                this.duplicateError = true;
                return;
            }

            const accountId = await createAccount({
                accountData
            });
            await this.uploadSelfie(accountId);
            localStorage.removeItem(this.storageKey);
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: accountId,
                    actionName: 'view'
                }
            });
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Error saving account', 'error');
            throw error; // Propagate the error
        }
    }
    handleBack() {
        localStorage.removeItem(this.storageKey); // Clear draft after save
     //   window.location.href = 'salesforce1://navigation/home';

this[NavigationMixin.Navigate]({
    type: 'standard__namedPage',
    attributes: {
        pageName: 'home' // lower-case 'home' for standard home page
    }
});
   

    }


    // Helper Methods
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }

    // getLocation method
    async getLocation() {
        try {
            await new Promise((resolve) => setTimeout(resolve, 1000));
            await this.getCurrentLocationDataForCheckIn();
            await this.handleSave(); // Added await
        } catch (error) {
            this.showToast('Location Error', error.message || 'Error verifying location', 'error');
            throw error; // Propagate the error
        }
    }

    // --- REPLACED METHOD (Part 1 fix): watchPosition + 5-sample weighted average ---
    async getCurrentLocationDataForCheckIn() {
        if (!navigator.geolocation) {
            throw new Error('Geolocation is not supported by this browser.');
        }

        if (navigator.permissions) {
            let permState;
            try {
                const perm = await navigator.permissions.query({ name: 'geolocation' });
                permState = perm.state;
            } catch (e) { /* Permissions API unavailable — continue */ }
            if (permState === 'denied') {
                throw new Error(
                    'Location permission is blocked. Enable it in your browser ' +
                    'and OS settings, then try again.'
                );
            }
        }

        return new Promise((resolve, reject) => {
            const readings = [];
            let watchId;

            const finish = (lat, lng, acc, snapshot) => {
                navigator.geolocation.clearWatch(watchId);
                if (acc > MIN_FINISH_ACCURACY) {
                    return reject(new Error(
                        'GPS accuracy is too poor right now (' + Math.round(acc) + ' m). ' +
                        'Move to an open area and try again.'
                    ));
                }
                this.latitude          = lat;
                this.longitude         = lng;
                this.accuracy          = acc;
                const best = snapshot.reduce((a, b) => a.accuracy <= b.accuracy ? a : b);
                this.locationTimestamp = best.timestamp;
                resolve();
            };

            const hardTimeout = setTimeout(() => {
                if (readings.length > 0) {
                    const snapshot = readings.slice();
                    const [lat, lng] = weightedAverage(snapshot);
                    finish(lat, lng, bestAccuracy(snapshot), snapshot);
                } else {
                    navigator.geolocation.clearWatch(watchId);
                    reject(new Error(
                        'Could not obtain a GPS fix in time. ' +
                        'Ensure location is enabled and try again.'
                    ));
                }
            }, READING_TIMEOUT_MS);

            watchId = navigator.geolocation.watchPosition(
                (position) => {
                    const acc = position.coords.accuracy;
                    if (acc > MAX_READING_ACCURACY) return;  // per-reading reject

                    readings.push({
                        lat:       position.coords.latitude,
                        lng:       position.coords.longitude,
                        accuracy:  acc,
                        timestamp: position.timestamp,
                        weight:    1 / (acc || 1)
                    });

                    if (readings.length >= READINGS_TO_AVERAGE) {
                        clearTimeout(hardTimeout);
                        const snapshot = readings.slice();
                        const [lat, lng] = weightedAverage(snapshot);
                        finish(lat, lng, bestAccuracy(snapshot), snapshot);
                    }
                },
                (error) => {
                    clearTimeout(hardTimeout);
                    navigator.geolocation.clearWatch(watchId);
                    let errorMessage;
                    switch (error.code) {
                        case error.PERMISSION_DENIED:
                            errorMessage = 'Location permission was denied. Please enable location access.';
                            break;
                        case error.POSITION_UNAVAILABLE:
                            errorMessage = 'Location information is unavailable.';
                            break;
                        case error.TIMEOUT:
                            errorMessage = "Turn on location manually if it's not already enabled and try again.";
                            break;
                        default:
                            errorMessage = 'An unknown error occurred while retrieving location.';
                    }
                    reject(new Error(errorMessage));
                },
                {
                    enableHighAccuracy: true,
                    maximumAge:         0,
                    timeout:            READING_TIMEOUT_MS + 1000
                }
            );
        });
    }
    // --- END REPLACED METHOD ---


    
    async getDistributor() {
        if (this.visitTaskId) {
            this.distributorId = await getDistributorFromVisitTask({
                visitTaskId: this.visitTaskId
            });
        }
    }



    executeChecks() {
        if (!this.validateForm()) return;

        this.setLoading(true);
        this.getLocation()
            .catch(error => {
                this.showToast('Error', error.body?.message || 'An error occurred during save', 'error');
            })
            .finally(() => {
                this.setLoading(false);
            });
    }


    uploadSelfie(latestAccountId) {
        uploadSelfie({
                latestAccountId: latestAccountId,
                base64Image: this.selfieFile
            })
            .then(() => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Image uploaded successfully!',
                        variant: 'success'
                    })
                );
                setTimeout(() => {
                    window.location.reload();
                }, 10);
            })
            .catch((error) => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'Selfie upload failed.',
                        variant: 'error'
                    })
                );
            });
        this.isSubmitDisabled = false;
    }

    handleNameChange(event) {
        this.retailerName = event.target.value;
        // Reset validity for retailer name input
        const nameInput = this.template.querySelector('lightning-input[data-field="retailerName"]');
        if (nameInput) {
            nameInput.setCustomValidity('');
            nameInput.reportValidity();
        }
        this.saveData();
    }
    handleOwnerNameChange(event) {
        this.ownerName = event.target.value;
        this.saveData(); // Save selfie data
    }

    handleOwnerNumberChange(event) {
        let raw = event.target.value;
        let cleaned = raw.replace(/\D/g, ''); // Remove non-digits
        this.ownerNumber = cleaned;
        console.log('ownerNumber***',this.ownerNumber);

        this.duplicateError = false;
        // Reset validity for owner number input
        const ownerNumberInput = this.template.querySelector('lightning-input[data-field="ownerNumber"]');
        if (ownerNumberInput) {
            ownerNumberInput.setCustomValidity('');
            ownerNumberInput.reportValidity();
        }
        this.saveData();
    }

    handleRetailerTypeChange(event) {
        this.retailerType = event.target.value;
        // Reset validity for retailer type combobox
        const retailerTypeCombo = this.template.querySelector('lightning-combobox[data-field="retailerType"]');
        if (retailerTypeCombo) {
            retailerTypeCombo.setCustomValidity('');
            retailerTypeCombo.reportValidity();
        }
        this.saveData();
    }

    handleOutletChannelChange(event) {
        this.outletChannel = event.target.value;
        const outletChannelCombo = this.template.querySelector('lightning-combobox[data-field="outletChannel"]');
        if (outletChannelCombo) {
            outletChannelCombo.setCustomValidity('');
            outletChannelCombo.reportValidity();
        }
        this.saveData();
    }

    handleGstinChange(event) {
        this.gstin = event.target.value;
        this.saveData(); // Save selfie data
    }
    handlePANChange(event) {
        this.pan = event.target.value;
        this.saveData(); // Save selfie data
    }
    handleFSSAIChange(event) {
        this.fssai = event.target.value;
        this.saveData(); // Save selfie data
    }

}