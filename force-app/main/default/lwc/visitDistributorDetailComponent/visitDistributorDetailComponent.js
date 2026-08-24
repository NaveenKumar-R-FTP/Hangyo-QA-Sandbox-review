// added by fuzail - Distributor component with same functionality as Retailer component
import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getVisitTaskDetails from '@salesforce/apex/VisitController.getVisitTaskDetails';
import saveVisitTask from '@salesforce/apex/VisitController.saveVisitTask';
import saveCheckOutRecord from '@salesforce/apex/VisitController.saveCheckOutRecord';
import saveNoOrderData from '@salesforce/apex/VisitController.saveNoOrderData';
import updateStatusForTransferDF from '@salesforce/apex/VisitController.updateStatusForTransferDF';
import checkTodayVisitTask from '@salesforce/apex/VisitController.checkTodayVisitTask';
import checkUserChecking from '@salesforce/apex/VisitTaskController.checkUserChecking';
import getCurrentVisitRecord from '@salesforce/apex/VisitController.getCurrentVisitRecord';
import updateRetailerLocation from '@salesforce/apex/VisitController.updateRetailerLocation';
import saveStartCallLocationTimeRecord from '@salesforce/apex/VisitController.saveStartCallLocationTimeRecord';
import saveEndCallRecord from '@salesforce/apex/VisitController.saveEndCallRecord';
import checkAnyVisitTaskStatus from '@salesforce/apex/VisitTaskController.checkAnyVisitTaskStatus';
import saveSelifeData from '@salesforce/apex/VisitController.saveSelifeData';
import savePurposeOfVisitData from '@salesforce/apex/VisitController.savePurposeOfVisitData';
import searchUser from '@salesforce/apex/VisitController.searchUser';
import removeCheckInDateTime from '@salesforce/apex/VisitController.removeCheckInDateTime';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import checkAllAssetsAudited from '@salesforce/apex/CaseScreenController.checkAllAssetsAudited';
import checkAllBrandingAudited from '@salesforce/apex/CaseScreenController.checkAllBrandingAudited';
import ACCOUNT_LOCATION_UNAVAILABLE from '@salesforce/label/c.Account_Location_Unavailable';
import BEYOND_50 from '@salesforce/label/c.Beyong_50';
import Retailer_Location_Update_Message from '@salesforce/label/c.Retailer_Location_Update_Message';

export default class VisitDistributorDetailComponent extends NavigationMixin(LightningElement) {
    @track visit = {};
    @track isLoading = false;
    @api accountId;
    @api visitId;
    @track latitude;
    @track longitude;
    @track locationCaptured = false;
    @track isCheckInActive = false;
    @track isCheckInDone = false;
    @track isCheckOutDisabled = true;
    @track IsUnproductive = false;
    @track selectedReason = '';
    @track otherReason = ''; // For "Other" reason input field
    @track isreasonExist = false;
    @track isCheckInPopUp = false;
    @track isCheckInSuccess = false;
    @track isDistanceIsMore = false;
    @track isRetailerUpdate = false;
    @track isDistanceIsMoreMessage = '';
    @track flowApiName = '';
    @track renderFlow = false;
    @track showFlowWindow = false;
    @track isMainComponent = false;
    @track isButtonSection = false;
    @track isCompleted = false;
    @track isrecordStart = false;
    @track isrecordComplete = false;
    @track isStartCall = false;
    @track isStartRecordCall = false;
    @track isOrderPlacedVisit = false;
    @track isviewOrder = false;
    @track twoButtonClick = false;
    @track competitorbuttonclick = false;
    @track isChildComponenet = false;
    @track isPurpose = false;
    @track selectedVisit = '';
    @track selectedUser = null;
    @track searchQuery = '';
    @track filteredUserOptions = [];
    @track userOptions = [];
    @track isCameraOn = false;
    @track photoURL = null;
    @track selfieData;
    @track isSaveDisabled = true;
    @track progressValue = 0;
    @track fileName = '';
    @track fileType = '';
    @track checkInDoneToTriggerFlow = false;
    @track isTransferDFCompleted = false;
    @track isCaseScreen = false;
    @track isAssetScreen = false;
    @track isBrandingScreen = false;
    @track distributorId = '';
    videoStream = null;
    _accountId;

    // added by fuzail - Unproductive reason options for radio group (Distributor specific)
    get options() {
        return [
            { label: 'Shop closed', value: 'Shop closed' },
            { label: 'Stock Audit', value: 'Stock Audit' },
            { label: 'Assset Transfer', value: 'Asset Transfer' },
            { label: 'Assset Audit', value: 'Asset Audit' },
            { label: 'Distributor Visit', value: 'Distributor Visit' }
        ];
    }

    // Check if "Other" is selected to show the Other_Reason__c field
    get showOtherReasonField() {
        return this.selectedReason === 'Other';
    }
    get showCaseOrAsset() {
        return this.isCaseScreen || this.isAssetScreen || this.isBrandingScreen;
    }

    // Reason resolved the same way the retailer component does, so the branding
    // panel applies the identical Shop closed / Joint Visit exemption.
    get unproductiveReason() {
        return (this.currentVisitTask && this.currentVisitTask.Unproductive_Reasons__c)
            || this.selectedReason
            || localStorage.getItem('selectedReason');
    }get showOtherReasonField() {
        return this.selectedReason === 'Other';
    }

    connectedCallback() {
        this.checkInDoneToTriggerFlow = localStorage.getItem('checkInDoneToTriggerFlow');
        const urlParams = new URLSearchParams(window.location.search);
        
        // Get visitId from URL first, then fallback to localStorage
        this.visitId = urlParams.get('visitid') || urlParams.get('visitId') || this.visitId || localStorage.getItem('visitId');
        
        if (this.visitId) {
            localStorage.setItem('visitId', this.visitId);
        }
        
        this._accountId = this.accountId || this.visitId;
        
        // Fetch visit record FIRST to get the correct state before loading UI
        this.fetchVisitRecord().then(() => {
            // Load visit details after we have the correct state
            this.loadVisitTaskDetails();
            
            // Check if we're in the middle of "No Order" flow
            const visitedNoOrderCheck = localStorage.getItem('visitedNoOrder');
            if (visitedNoOrderCheck) {
                this.IsUnproductive = true;
                this.isMainComponent = true;
            } else if ((this.isrecordStart && this.isCheckInDone) || this.isCheckInDone) {
                // Visit is already checked in - clear all localStorage flags and show normal view
                localStorage.removeItem('visitedPurposeVisit');
                localStorage.removeItem('visitedSelfie');
                localStorage.removeItem('checkInDoneToTriggerFlow');
                this.isPurpose = false;
                this.isCheckInSuccess = false;
                this.isMainComponent = false;
            } else {
                // Visit is not in progress yet - check if we're in the middle of a flow
                const visitedPurposeCheck = localStorage.getItem('visitedPurposeVisit');
                if (visitedPurposeCheck) {
                    // We're in the purpose of visit step
                    this.isPurpose = true;
                    this.isMainComponent = true;
                    this.fetchUsers();
                } else {
                    // Check if we're in the middle of selfie capture
                    const visitedSelfieCheck = localStorage.getItem('visitedSelfie');
                    if (visitedSelfieCheck) {
                        this.isCheckInSuccess = true;
                        this.isMainComponent = true;
                    }
                }
            }
        });
        
        window.sessionStorage.setItem('isFromOrderPage', 'Yes');
    }

    get accountIdGetter() {
        return this._accountId;
    }

    set accountIdGetter(value) {
        this._accountId = value;
        if (this._accountId) {
            this.loadVisitTaskDetails();
        }
    }

    loadVisitTaskDetails() {
        if (this._accountId) {
            getVisitTaskDetails({ visitTaskRecordId: this._accountId })
                .then(result => {
                    this.visit = result || {};
                    this.distributorId = result?.distributorId || '';
                })
                .catch(error => {
                    this.showToast('Error', error?.body?.message || 'Error loading visit details.', 'error');
                });
        }
    }

    fetchVisitRecord() {
        return new Promise((resolve, reject) => {
            if (this.visitId) {
                getCurrentVisitRecord({ visitTaskRecordId: this.visitId })
                    .then(record => {
                        if (record) {
                            // Check if status is In-Progress first - this takes precedence
                            if (record.Status__c === 'In-Progress') {
                                this.isCheckInDone = true;
                                this.isrecordStart = true;
                            } else if (record.Checked_In_Time__c) {
                                this.isCheckInDone = true;
                            } else {
                                this.isCheckInDone = false;
                            }
                            
                            this.isreasonExist = record.Unproductive_Reasons__c ? true : false;
                            // Set isrecordStart based on status or other indicators
                            if (!this.isrecordStart) {
                                this.isrecordStart = (record.Purpose_of_Visit__c || record.Start_Call_Time__c) ? true : false;
                            }
                            // If Purpose_of_Visit or Start_Call_Time exists, check-in is done
                            if (record.Purpose_of_Visit__c || record.Start_Call_Time__c) {
                                this.isCheckInDone = true;
                            }
                            
                            this.isrecordComplete = (record.Checked_Out_Time__c || record.End_Call_Time__c) ? true : false;
                            this.isCompleted = this.isrecordComplete;
                            this.isStartRecordCall = (record.Start_Call_Time__c) ? true : false;
                            this.isOrderPlacedVisit = (record.Order_Placed__c == true) ? true : false;
                            
                            if (this.isreasonExist) {
                                this.selectedReason = record.Unproductive_Reasons__c;
                            }
                            
                            // Check if Transfer DF was completed from localStorage
                            const transferDFCompleted = localStorage.getItem(`transferDFCompleted_${this.visitId}`);
                            if (transferDFCompleted === 'true') {
                                this.isTransferDFCompleted = true;
                            }
                            
                            // added by Fuzail - Check-Out button should always be enabled in distributor component
                            // Validation will show error message if unproductive reason is not provided
                            if (this.isCheckInDone && !this.isrecordComplete) {
                                this.isCheckOutDisabled = false; // Always enable Check-Out button
                            } else {
                                this.isCheckOutDisabled = true; // Disable only if not checked in or already completed
                            }
                        }
                        resolve();
                    })
                    .catch(error => {
                        console.error('Error fetching visit record:', error);
                        reject(error);
                    });
            } else {
                resolve();
            }
        });
    }

    handleCheckInMethod(event) {
        this.isLoading = true;
        checkTodayVisitTask()
            .then(result => {
                if (result) {
                    const visitInfo = JSON.parse(result);
                    const distributorName = visitInfo.retailerName || 'Distributor';
                    const distributorCode = visitInfo.retailerCode ? `[${visitInfo.retailerCode}]` : '';

                    this.showToast(
                        'Error',
                        `You cannot proceed as you must first check out for ${distributorName} ${distributorCode}.`,
                        'error'
                    );
                    this.isLoading = false;
                } else {
                    this.isLoading = false;
                    this.isCheckInPopUp = true;
                    const visitIdToPass = this.visitId;
                    this.verifyLocation(visitIdToPass);
                }
            })
            .catch(error => {
                this.showToast('Error', 'Error in checking Today\'s Visit Task: ' + error.body.message, 'error');
                this.isLoading = false;
            });
    }

    async verifyLocation(finalVisitId) {
        try {
            // Simulate verifying location asynchronously
            await new Promise((resolve) => setTimeout(resolve, 3000)); // Simulating a delay

            // Get location data
            await this.getCurrentLocationDataForCheckIn();

            // Once location data is fetched successfully, call handleVisitTaskRecord
            this.handleVisitTaskRecord(finalVisitId);

            // Hide the popup after success
            this.isCheckInPopUp = false;
            localStorage.setItem('visitedSelfie', true);
        } catch (error) {
            // Handle any errors during location retrieval
            this.isCheckInPopUp = false; // Close popup on error
            localStorage.removeItem('visitedSelfie');

            // Show an error popup to the user
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Location Error',
                    message: error.message || 'There was a problem verifying your location.',
                    variant: 'error',
                })
            );
        }
    }

    async getCurrentLocationDataForCheckIn() {
        return new Promise((resolve, reject) => {
            if (navigator.geolocation) {
                navigator.geolocation.getCurrentPosition(
                    (position) => {
                        this.latitude = position.coords.latitude;
                        this.longitude = position.coords.longitude;
                        localStorage.setItem('latitude', this.latitude);
                        localStorage.setItem('longitude', this.longitude);
                        resolve(); // Resolve the promise when location data is retrieved
                    },
                    (error) => {
                        let errorMessage = 'Could not retrieve location.';
                        switch (error.code) {
                            case error.PERMISSION_DENIED:
                                errorMessage = 'Location permission was denied. Please enable location access.';
                                break;
                            case error.POSITION_UNAVAILABLE:
                                errorMessage = 'Location information is unavailable.';
                                break;
                            case error.TIMEOUT:
                                errorMessage = 'Turn on the location Manually if it\'s not already enabled and try again.';
                                break;
                            case error.UNKNOWN_ERROR:
                            default:
                                errorMessage = 'An unknown error occurred while retrieving location.';
                                break;
                        }

                        this.showToast('Error', errorMessage, 'error');
                        window.location.reload();

                        reject(new Error(errorMessage));
                    },
                    { enableHighAccuracy: true, timeout: 15000 } // Ensure timeout is handled
                );
            } else {
                window.location.reload();

                reject(new Error('Geolocation is not supported by this browser.'));
            }
        });
    }

    handleVisitTaskRecord(finalVisitId) {
        this.showToast('Debug', 'Lat:' + this.latitude + ' Lng:' + this.longitude + ' VID:' + this.visitId, 'info');
       saveVisitTask({
            visitId: this.visitId,
            latitude: this.latitude.toString(),
            longitude: this.longitude.toString()
        })
            .then((result) => {
                this.showToast('Debug Result', result, 'info');
                if (result === 'success') {
                    this.showToast('Success', 'Check In Location has been Captured Successfully.', 'success');
                    this.isMainComponent = true;
                    this.isCheckInSuccess = true;
                    this.isCheckInDone = true;
                    this.checkInDoneToTriggerFlow = true;
                    localStorage.setItem('checkInDoneToTriggerFlow', true);
                    // Start camera with error handling
                    this.startCamera().catch((error) => {
                        console.error('Error starting camera:', error);
                        // Camera error is already handled in startCamera with toast
                    });
                } else if (result.includes(ACCOUNT_LOCATION_UNAVAILABLE)) {
                    localStorage.removeItem('visitedSelfie');
                    this.showToast('Error', ACCOUNT_LOCATION_UNAVAILABLE, 'error');
                } else if (result.includes('retailerLocationUpdate=true')) {
                    this.isRetailerUpdate = true;
                    this.isDistanceIsMoreMessage = Retailer_Location_Update_Message;
                } else if (result.includes(BEYOND_50)) {
                    this.isDistanceIsMore = true;
                    this.isDistanceIsMoreMessage = BEYOND_50;
                } else {
                    this.showToast('Error', result, 'error');
                }
            })
            .catch((error) => {
                this.showToast('Error', 'An unexpected error occurred. Please try again.', 'error');
            });
    }

    handleCheckOutMethod() {
        if (!this.isreasonExist) {
            this.showToast('Error', 'Please Provide the Unproductive Reason to Check Out.', 'error');
            return;
        }
        
        this.isLoading = true;
        if (!this.selectedReason) {
            const storedReason = localStorage.getItem('selectedReason');
            if (storedReason) {
                this.selectedReason = storedReason;
            }
        }
        
        // The freezer audit is still skipped for distributor visits, as before.
        // The branding audit is gated the same way as on a retailer visit.
        const reason = this.unproductiveReason;
        if (reason === 'Shop closed' || reason === 'Joint Visit') {
            this.isLoading = false;
            this.verifyCheckoutLocation(this.visitId);
            return;
        }

        checkAllBrandingAudited({ visitTaskId: this.visitId })
            .then(result => {
                this.isLoading = false;
                if (result === 'VISIT_AUDITED') {
                    this.verifyCheckoutLocation(this.visitId);
                } else if (result === 'NOT_AUDITED') {
                    this.showToast('Error', 'Please complete the Mapped Branding audit before check-out.', 'error');
                } else {
                    this.showToast('Error', 'Could not verify the Mapped Branding audit. Please try again.', 'error');
                }
            })
            .catch(error => {
                this.isLoading = false;
                this.showToast('Error', 'Error checking audit status: ' + (error?.body?.message || ''), 'error');
            });
    }

    async verifyCheckoutLocation(finalVisitId) {
        try {
            await new Promise((resolve) => setTimeout(resolve, 3000));
            await this.getCurrentLocationDataForCheckIn();
            this.handleCheckOutRecord(finalVisitId);
            this.isCheckInPopUp = false;
        } catch (error) {
            this.isCheckInPopUp = false;
            this.showToast('Location Error', error.message || 'There was a problem verifying your location.', 'error');
        }
    }

    handleCheckOutRecord(finalVisitId) {
        this.isLoading = true;
        saveCheckOutRecord({
            visitId: this.visitId,
            latitude: this.latitude.toString(),
            longitude: this.longitude.toString()
        })
            .then(() => {
                this.showToast('Success', 'Check Out Location has been Captured Successfully.', 'success');
                this.isLoading = false;
                this.isCheckInDone = false;
                this.isCheckOutDisabled = true;
                this.isrecordComplete = true; // Mark as completed so Transfer DF/Tag DF buttons are disabled
                this.fetchVisitRecord();
            })
            .catch((error) => {
                this.showToast('Error', 'Error in updating Check Out location in Visit Task.', 'error');
                this.isLoading = false;
            });
    }

    handleNoOrder() {
        checkUserChecking({ currentVisitTaskId: this.visitId, actionType: 'NoOrder' })
            .then((result) => {
                if (result.isAllowed) {
                    localStorage.setItem('visitedNoOrder', true);
                    this.IsUnproductive = true;
                    this.isMainComponent = true; // Hide main component, show unproductive page
                } else {
                    this.showToast('Error', result.errorMessage, 'error');
                }
            })
            .catch((error) => {
                this.showToast('Error', error.body.message, 'error');
            });
    }

    handleNoOrderSave(event) {
        const visitTaskIdToPass = this.visitId;
        if (!this.selectedReason) {
            this.showToast('Error', 'Please select an unproductive reason.', 'error');
            return;
        }
        
        // Validate Other_Reason__c if "Other" is selected
        if (this.selectedReason === 'Other' && !this.otherReason) {
            this.showToast('Error', 'Please enter a reason for "Other".', 'error');
            return;
        }
        
        saveNoOrderData({
            visitTaskId: visitTaskIdToPass,
            reason: this.selectedReason,
            otherReason: this.selectedReason === 'Other' ? this.otherReason : null
        })
            .then(() => {
                this.showToast('Success', 'Unproductive reason saved successfully.', 'success');
                this.isMainComponent = false;
                this.IsUnproductive = false;
                this.isreasonExist = true;
                this.isStartCall = false;
                // Clear otherReason after saving
                this.otherReason = '';
                // added by Fuzail - Check-Out button should always be enabled in distributor component
                if (this.isCheckInDone && !this.isrecordComplete) {
                    this.isCheckOutDisabled = false; // Always enable Check-Out button
                }
                this.fetchVisitRecord(); // this.isrecordStart=true;
                localStorage.removeItem('visitedNoOrder');
            })
            .catch(error => {
                this.showToast('Error', 'Error in Saving Unproductive Reason.', 'error');
            });
    }

    handleReasonChange(event) {
        this.selectedReason = event.detail.value;
        // Clear otherReason when changing selection
        if (this.selectedReason !== 'Other') {
            this.otherReason = '';
        }
    }

    handleOtherReasonChange(event) {
        this.otherReason = event.target.value;
    }

    backAction() {
        this.IsUnproductive = false;
        this.isMainComponent = false; // Show main component again
        this.selectedReason = '';
        this.otherReason = '';
        localStorage.removeItem('visitedNoOrder');
    }

    handleCancelUnproductive() {
        this.IsUnproductive = false;
        this.selectedReason = '';
        this.otherReason = '';
    }

    handleStatusChange(event) {
        const status = event.detail.status;
        if (status === 'FINISHED' || status === 'FINISHED_SCREEN') {
            // Check if this was the Transfer DF flow (Distributor version)
            if (this.flowApiName === 'Transfer_DF_Distributor') {
                this.isTransferDFCompleted = true;
                // Store in localStorage to persist across page refreshes
                localStorage.setItem(`transferDFCompleted_${this.visitId}`, 'true');
                // Status will be updated only when user clicks Check-Out, not here
            }
            // added by Fuzail - Check-Out button should always be enabled in distributor component
            if (this.isCheckInDone && !this.isrecordComplete) {
                this.isCheckOutDisabled = false; // Always enable Check-Out button
            }
            this.handleCloseFlow();
            this.showToast('Success', '', 'success');
        } else if (status === 'ERROR') {
            this.showToast('Error', 'The flow encountered an error.', 'error');
        }
    }

    //Added by Ajay to dynamically pass visit task id to the flow
    get flowInputVariables() {
        return [
            {
                name: 'recordId',
                type: 'String',
                value: this.visitId
            }
        ];
    }

    handleClick(event) {
        const flowName = event.target.dataset.flow;
        checkUserChecking({ currentVisitTaskId: this.visitId, actionType: 'DFAction' })
            .then((result) => {
                if (result.isAllowed) {
                    this.flowApiName = flowName;
                    this.renderFlow = true;
                    this.showFlowWindow = true;
                    localStorage.setItem('toggleFlow', this.flowApiName);
                } else {
                    this.showToast('Error', result.errorMessage, 'error');
                }
            })
            .catch((error) => {
                this.showToast('Error', error.body.message, 'error');
            });
    }

    handleCloseFlow() {
        localStorage.removeItem('toggleFlow');
        this.renderFlow = false;
        this.showFlowWindow = false;
    }

    handleClickTaggedDF(event) {
        this.flowApiName = event.target.dataset.flow; // Get flow API name from button
        this.renderFlow = true;
        this.showFlowWindow = true;
        localStorage.setItem('toggleFlow', this.flowApiName);
    }

    //This method will show the scheme component
    twoSchemesClick() {
        this.twoButtonClick = true;
        this.isMainComponent = true;
    }

    //This method will show the component for latest orders
    loadLatestOrders() {
        this.isviewOrder = true;
        this.isMainComponent = true;
    }

    //This method will be called when create order button clicked
    handleCreateOrderMethod() {
        this.isMainComponent = true;
        this.isChildComponenet = true;
    }

    //This method will show the competitor info capture component
    competitorbuttonclicked() {
        checkAnyVisitTaskStatus({ currentVisitTaskId: this.visitId })
            .then((result) => {
                if (result) {
                    // Show validation if another Visit Task is in-progress
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Error',
                        message: 'You cannot proceed because the current visit task is either Not Started or Cancelled.',
                        variant: 'error'
                    }));
                } else {
                    this.competitorbuttonclick = true;
                    this.isMainComponent = true;
                }
            })
            .catch((error) => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error.body.message,
                    variant: 'error'
                }));
            });
    }

    //This method will be called to get location details after start call clicked
    handleStartCallMethod() {
        this.isLoading = true;
        checkTodayVisitTask()
            .then(result => {
                if (result) {
                    const visitInfo = JSON.parse(result);
                    const distributorName = visitInfo.retailerName || 'Distributor';
                    const distributorCode = visitInfo.retailerCode ? `[${visitInfo.retailerCode}]` : '';

                    this.showToast(
                        'Error',
                        `You cannot proceed as you must first check out or end the ongoing call for ${distributorName} ${distributorCode}.`,
                        'error'
                    );
                    this.isLoading = false;
                } else {
                    // No active visit found — proceed normally
                    this.isLoading = false;
                    this.isCheckInPopUp = true;
                    const visitIdToPass = this.visitId;
                    this.verifyStartCallLocation();
                }
            })
            .catch(error => {
                this.showToast('Error', 'Error in checking Today\'s Visit Task: ' + error.body.message, 'error');
                this.isLoading = false;
            });
    }

    async verifyStartCallLocation() {
        try {
            // Simulate verifying location asynchronously
            await new Promise((resolve) => setTimeout(resolve, 3000)); // Simulating a delay

            // Get location data
            await this.getCurrentLocationDataForCheckIn();

            // Once location data is fetched successfully, call handleVisitTaskRecord
            this.handleStartCallLocationSave();

            // Hide the popup after success
            this.isCheckInPopUp = false;
        } catch (error) {
            // Handle any errors during location retrieval
            this.isCheckInPopUp = false; // Close popup on error

            // Show an error popup to the user
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Location Error',
                    message: error.message || 'There was a problem verifying your location.',
                    variant: 'error',
                })
            );
        }
    }

    //This method will be called to save location details in database after start call clicked
    handleStartCallLocationSave() {
        this.isLoading = true;
        // Call Apex method to save the visit task record
        saveStartCallLocationTimeRecord({
            visitId: this.visitId,
            latitude: this.latitude.toString(),
            longitude: this.longitude.toString()
        })
            .then((result) => {
                if (result) {
                    this.showToast('Success', 'Start call Location has been Captured Successfully', 'success');
                    this.isLoading = false;
                    this.isStartCall = true;
                    this.isCheckInDone = true;
                }
            })
            .catch((error) => {
                this.showToast('Error', 'Error in updating Start call location in Visit Task.', 'error');
                this.isLoading = false;
            });
    }

    //This method will be called to save check out location details
    handleEndCallMethod() {
        // Validate that either Unproductive Reason OR Transfer DF is completed before allowing end call
        if (!this.isreasonExist && !this.isTransferDFCompleted) { // added by Fuzail - Check both conditions
            this.showToast('Error', 'Please Provide the Unproductive Reason to Check Out.', 'error'); // added by Fuzail - Updated error message
            return;
        }
        
        this.isLoading = true;
        // added by Ajay to prevent end call before all df audit is complete
        //omit the check if shop is closed
        this.showToast('Success', 'Audit skipped due to the user starting a call.', 'success');
        this.isLoading = false;
        const visitIdToPass = this.visitId;
        this.verifyEndCallLocation(visitIdToPass);
    }

    //This method used when End call clicked and to get the location
    async verifyEndCallLocation(finalVisitId) {
        try {
            // Simulate verifying location asynchronously
            await new Promise((resolve) => setTimeout(resolve, 3000)); // Simulating a delay

            // Get location data
            await this.getCurrentLocationDataForCheckIn();

            // Once location data is fetched successfully, call handleVisitTaskRecord
            this.handleEndCallRecord(finalVisitId);

            // Hide the popup after success
            this.isCheckInPopUp = false;
        } catch (error) {
            // Handle any errors during location retrieval
            this.isCheckInPopUp = false; // Close popup on error

            // Show an error popup to the user
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Location Error',
                    message: error.message || 'There was a problem verifying your location.',
                    variant: 'error',
                })
            );
        }
    }

    //This method used to update the end call location and time on visittask
    handleEndCallRecord(finalVisitId) {
        this.isLoading = true;
        // Call Apex method to save the visit task record
        saveEndCallRecord({
            visitId: this.visitId,
            latitude: this.latitude.toString(),
            longitude: this.longitude.toString()
        })
            .then((result) => {
                if (result) {
                    this.showToast('Success', 'End Call Location has been Captured Successfully', 'success');
                    this.isLoading = false;
                    this.isMainComponent = false;
                    this.isCheckInDone = false;
                    this.isCompleted = false;
                    this.isrecordStart = false;
                    this.isStartRecordCall = false;
                    this.isrecordComplete = true; // Mark as completed so Transfer DF/Tag DF buttons are disabled
                }
            })
            .catch((error) => {
                this.showToast('Error', 'Error in updating End Call location in Visit Task.', 'error');
                this.isLoading = false;
            });
    }

    handleCreateCase() {
        this.isCaseScreen = true;
        this.isAssetScreen = false;
        this.isBrandingScreen = false;
    }
    handleMappedAssets() {
        this.isAssetScreen = true;
        this.isCaseScreen = false;
        this.isBrandingScreen = false;
    }
    handleOpenBranding() {
        this.isBrandingScreen = true;
        this.isCaseScreen = false;
        this.isAssetScreen = false;
    }
    handleGoBack() {
        this.isCaseScreen = false;
        this.isAssetScreen = false;
        this.isBrandingScreen = false;
    }
    handleBack() {
        const backEvent = new CustomEvent('back');
        this.dispatchEvent(backEvent);
    }
    
    handleCloseModal() {
        this.isDistanceIsMore = false;
        this.isRetailerUpdate = false;
        this.isMainComponent = false;
        this.isCheckInDone = false;
        localStorage.removeItem('visitedSelfie');
    }

    handleUpdateRetailerLocation() {
        updateRetailerLocation({
            visitId: this.visitId,
            latitude: this.latitude.toString(),
            longitude: this.longitude.toString()
        })
            .then((result) => {
                if (result === 'success') {
                    this.showToast('Success', 'Distributor location has been updated successfully.', 'success');
                    this.handleCloseModal();
                }
            })
            .catch((error) => {
                this.showToast('Error', 'An unexpected error occurred. Please try again.', 'error');
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }

    //This method will be called when back button clicked from selfie page
    closeActionCheckIn() {
        const visitTaskIdToPass = this.visitId;
        this.isLoading = true;
        this.isCheckInSuccess = false;
        this.isMainComponent = false;
        this.isCheckInDone = false;
        localStorage.removeItem('visitedSelfie');

        removeCheckInDateTime({ visitTaskRecordId: visitTaskIdToPass })
            .then(() => {
                // Always stop loading after response
                this.isLoading = false;
            })
            .catch((error) => {
                this.isLoading = false;
                this.showToast('Error', 'Error in removing Check-In Details in Visit Task.', 'error');
            });
    }

    //This method will be called to save SelfieFile details
    handleSelfieSave() {
        if (!this.selfieData) {
            this.showToast('Error', 'Please capture selfie before saving.', 'error');
            return;
        }
        this.isLoading = true;
        const visitIdToPass = this.visitId;
        saveSelifeData({
            visitId: visitIdToPass,
            base64Image: this.selfieData
        })
            .then(() => {
                this.showToast('Success', 'Selfie is captured and saved successfully.', 'success');
                this.isLoading = false;
                this.isMainComponent = true;
                this.isCheckInPopUp = false;
                this.isCheckInSuccess = false;
                this.isPurpose = true;
                localStorage.setItem('visitedPurposeVisit', true);
                localStorage.removeItem('visitedSelfie');
                // Fetch visit record to update UI state
                this.fetchVisitRecord();
            })
            .catch(error => {
                this.showToast('Error', 'Failed to save data.', 'error');
                this.isLoading = false;
            });
    }

    checkIfSelfieSaveEnabled() {
        // Enable the Save button if selfie are captured
        if (this.selfieData) {
            this.isSaveDisabled = false;
        }
    }

    //Start Camera on click of Upload Selfie
    async startCamera() {
        this.isCameraOn = true; // Show camera UI
        this.photoURL = null;
        this.selfieFile = null;
        try {
            // Check if mediaDevices is available
            if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
                throw new Error('Camera API is not supported in this browser.');
            }

            this.videoStream = await navigator.mediaDevices.getUserMedia({
                video: { facingMode: "user" } // Force front camera
            });
            
            // Wait for the next render cycle to ensure video element exists
            await new Promise(resolve => setTimeout(resolve, 100));
            
            const videoElement = this.template.querySelector('.video-feed');
            if (!videoElement) {
                throw new Error('Video element not found in DOM.');
            }
            
            videoElement.srcObject = this.videoStream;
            
            // Wait for video metadata to load before proceeding
            return new Promise((resolve, reject) => {
                const timeout = setTimeout(() => {
                    reject(new Error('Video stream timeout. Please try again.'));
                }, 10000);
                
                videoElement.onloadedmetadata = () => {
                    clearTimeout(timeout);
                    resolve();
                };
                
                videoElement.onerror = (error) => {
                    clearTimeout(timeout);
                    reject(new Error('Error loading video stream.'));
                };
            });
        } catch (error) {
            this.isCameraOn = false;
            // Stop any tracks if stream was created
            if (this.videoStream) {
                this.videoStream.getTracks().forEach(track => track.stop());
                this.videoStream = null;
            }

            this.showToast(
                'Camera Access Error',
                error?.message || 'Unable to access the camera. Please try again.',
                'error'
            );
            
            // Re-throw to allow caller to handle if needed
            throw error;
        }
    }

    //Capture Photo
    capturePhoto() {
        try {
            const video = this.template.querySelector('.video-feed');
            const canvas = this.template.querySelector('.hidden-canvas');
            
            // Validate video element exists and is ready
            if (!video) {
                this.showToast('Error', 'Video element not found. Please try again.', 'error');
                return;
            }
            
            if (!canvas) {
                this.showToast('Error', 'Canvas element not found. Please try again.', 'error');
                return;
            }
            
            // Check if video has valid dimensions
            if (!video.videoWidth || !video.videoHeight || 
                video.videoWidth === 0 || video.videoHeight === 0) {
                this.showToast('Error', 'Video is not ready. Please wait a moment and try again.', 'error');
                return;
            }
            
            // Check if video is actually playing/ready
            if (video.readyState < 2) { // HAVE_CURRENT_DATA = 2
                this.showToast('Error', 'Video stream is not ready. Please wait a moment and try again.', 'error');
                return;
            }

            const context = canvas.getContext('2d');
            if (!context) {
                this.showToast('Error', 'Could not get canvas context. Please try again.', 'error');
                return;
            }

            // Scale down image (50% size) - do this first to avoid large canvas
            const width = Math.floor(video.videoWidth * 0.5);
            const height = Math.floor(video.videoHeight * 0.5);
            canvas.width = width;
            canvas.height = height;

            // Draw scaled-down image on canvas
            context.drawImage(video, 0, 0, width, height);

            // Create preview URL from scaled canvas
            this.photoURL = canvas.toDataURL('image/png');

            // Compress image (reduce quality to 0.7)
            canvas.toBlob((blob) => {
                if (!blob) {
                    this.showToast('Error', 'Failed to capture image. Please try again.', 'error');
                    return;
                }
                
                const reader = new FileReader();
                reader.onloadend = () => {
                    try {
                        if (reader.result) {
                            this.selfieData = reader.result.split(',')[1]; // Extract base64 data
                        } else {
                            throw new Error('Failed to read image data.');
                        }
                    } catch (error) {
                        this.showToast('Error', 'Error processing image. Please try again.', 'error');
                    }
                    
                    this.stopCamera(); // Stop camera after successful capture
                };
                
                reader.onerror = () => {
                    this.showToast('Error', 'Error reading image file. Please try again.', 'error');
                };
                
                reader.readAsDataURL(blob);
            }, 'image/jpeg', 0.7); // Set image type & quality (0.7 = 70% quality)
            
        } catch (error) {
            console.error('Error capturing photo:', error);
            this.showToast('Error', 'An error occurred while capturing the photo. Please try again.', 'error');
            this.stopCamera(); // Stop camera on error
        }
    }

    //Stop Once Photo is Clicked
    stopCamera() {
        if (this.videoStream) {
            this.videoStream.getTracks().forEach(track => track.stop()); // Stop camera
        }
        this.isCameraOn = false; // Hide camera UI
    }

    // Handle the change in selected purpose of visit
    handlePurposeOfVisitChange(event) {
        this.selectedVisit = event.detail.value;
        if (this.isJointVisit) {
            this.fetchUsers();
        }
    }

    // Check if 'Joint visit' is selected
    get isJointVisit() {
        return this.selectedVisit === 'Joint visit';
    }

    //This method will be called to show options for purposeOfVisit
    get purposeOfVisit() {
        return [
            { label: 'Individual visit', value: 'Individual visit' },
            { label: 'Joint visit', value: 'Joint visit' }
        ];
    }

    //This method will be called to save PurposeVisit details
    handlePurposeVisitSave(event) {
        const visitTaskIdToPass = this.visitId;
        if (this.selectedVisit == '' || this.selectedVisit == null) {
            this.showToast('Error', 'Please select purpose of Visit.', 'error');
            return;
        }
        if (this.selectedVisit == 'Joint visit' && (this.selectedUser == '' || this.selectedUser == null)) {
            this.showToast('Error', 'Please select User from dropdown for Joint visit.', 'error');
            return;
        }
        let latitude = this.latitude;
        let longitude = this.longitude;
        if (!latitude || !longitude) {
            latitude = localStorage.getItem('latitude');
            longitude = localStorage.getItem('longitude');
        }
        this.isLoading = true;
        savePurposeOfVisitData({
            visitTaskId: visitTaskIdToPass,
            reason: this.selectedVisit,
            userId: this.selectedUser,
            latitude: latitude,
            longitude: longitude
        })
            .then(() => {
                this.showToast('Success', 'Purpose of Visit is saved successfully.', 'success');
                this.isLoading = false;
                this.isMainComponent = false;
                this.isPurpose = false;
                localStorage.removeItem('visitedPurposeVisit');
                localStorage.removeItem('latitude');
                localStorage.removeItem('longitude');
                localStorage.removeItem('checkInDoneToTriggerFlow');
                this.checkInDoneToTriggerFlow = false;
                // Fetch visit record to update status and UI - this will show "In Progress" status and set all flags correctly
                this.fetchVisitRecord().then(() => {
                    // Force re-render by ensuring check-in state is correct
                    if (this.isCheckInDone) {
                        this.isCheckOutDisabled = false;
                    }
                });
            })
            .catch(error => {
                this.showToast('Error', 'Error in updating Visit Task Record.', 'error');
                this.isLoading = false;
            });
    }

    //This method will be called to fetchUsers for join visit
    fetchUsers() {
        console.log('Enter fetchUsers method');
        searchUser()
            .then((result) => {
                console.log('result:- ' + result);
                this.userOptions = result.map(user => ({
                    label: `${user.Name}`, // Display Name
                    value: user.Id  // Use Id as the value
                }));
            })
            .catch((error) => {
                this.showToast(
                    'Error',
                    error?.body?.message || 'Error fetching users.',
                    'error'
                );
            });
    }

    // Handle search input change
    handleSearchChange(event) {
        this.searchQuery = event.target.value.trim();
        // Clear the filtered options and selected user if the input is empty
        if (!this.searchQuery) {
            this.filteredUserOptions = []; // Clear the list
            this.selectedUser = null;
            return;
        }
        // Filter the options based on the search query
        if (this.searchQuery) {
            this.filteredUserOptions = this.userOptions.filter(user =>
                user.label.toLowerCase().includes(this.searchQuery.toLowerCase())
            );
        } else {
            // If the search query is empty, show all users
            this.filteredUserOptions = [...this.userOptions];
        }
    }

    // Handle selecting a user from the list
    handleSelectUser(event) {
        const selectedUserId = event.target.dataset.id; // Get the selected user ID
        const selectedUser = this.filteredUserOptions.find(user => user.value === selectedUserId);

        if (selectedUser) {
            this.searchQuery = selectedUser.label; // Set the user label in the input field
            this.filteredUserOptions = []; // Optionally clear the list after selection
            this.selectedUser = selectedUser.value; // Set selected user ID for further use
        }
    }

    //This method will be called to clearSearch box 
    clearSearchQuery() {
        this.searchQuery = ''; // Reset the search query
        this.filteredUserOptions = []; // Show all users
        this.selectedUser = null; // Clear any selected user
    }
}