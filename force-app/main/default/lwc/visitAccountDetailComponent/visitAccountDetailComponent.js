import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getVisitTaskDetails from '@salesforce/apex/VisitController.getVisitTaskDetails';
import savePurposeOfVisitData  from '@salesforce/apex/VisitController.savePurposeOfVisitData';
import getVisitTaskRecord  from '@salesforce/apex/VisitController.getVisitTaskRecord';
import getVisitTaskCompleteRecord  from '@salesforce/apex/VisitController.getVisitTaskCompleteRecord';
import getVisitTaskReson  from '@salesforce/apex/VisitController.getVisitTaskReson';
import getVisitTaskStartCallRecord  from '@salesforce/apex/VisitController.getVisitTaskStartCallRecord';
import getVisitTaskOrderPlacedRecord  from '@salesforce/apex/VisitController.getVisitTaskOrderPlacedRecord';
import checkAllAssetsAudited from '@salesforce/apex/CaseScreenController.checkAllAssetsAudited';
import checkAllBrandingAudited from '@salesforce/apex/CaseScreenController.checkAllBrandingAudited';
import saveCheckOutRecord  from '@salesforce/apex/VisitController.saveCheckOutRecord';
import saveEndCallRecord  from '@salesforce/apex/VisitController.saveEndCallRecord';
import updateRetailerLocation  from '@salesforce/apex/VisitController.updateRetailerLocation';
import saveStartCallLocationTimeRecord  from '@salesforce/apex/VisitController.saveStartCallLocationTimeRecord';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import saveVisitTask from '@salesforce/apex/VisitController.saveVisitTask';
import saveSelifeData from '@salesforce/apex/VisitController.saveSelifeData';
import saveNoOrderData from '@salesforce/apex/VisitController.saveNoOrderData';
import searchUser from '@salesforce/apex/VisitController.searchUser';
import ACCOUNT_LOCATION_UNAVAILABLE from '@salesforce/label/c.Account_Location_Unavailable';
import BEYOND_50  from '@salesforce/label/c.Beyong_50';
import Retailer_Location_Update_Message  from '@salesforce/label/c.Retailer_Location_Update_Message';
import Sefie_Capture  from '@salesforce/label/c.Sefie_Capture';
import checkTodayVisitTask  from '@salesforce/apex/VisitController.checkTodayVisitTask';
import checkAnyVisitTaskStatus from '@salesforce/apex/VisitTaskController.checkAnyVisitTaskStatus';
import checkUserChecking from '@salesforce/apex/VisitTaskController.checkUserChecking';
import getCurrentVisitRecord from '@salesforce/apex/VisitController.getCurrentVisitRecord';
import removeCheckInDateTime from '@salesforce/apex/VisitController.removeCheckInDateTime';
import checkAllAuditedForOrder from '@salesforce/apex/CaseScreenController.checkAllAuditedForOrder';

const READINGS_TO_AVERAGE  = 5;       
const READING_TIMEOUT_MS   = 20000;   
const MAX_READING_ACCURACY = 150;
const MIN_FINISH_ACCURACY  = 75;

function weightedAverage(readings) {
    const totalW = readings.reduce((s, r) => s + r.weight, 0);
    const lat    = readings.reduce((s, r) => s + r.lat * r.weight, 0) / totalW;
    const lng    = readings.reduce((s, r) => s + r.lng * r.weight, 0) / totalW;
    return [lat, lng];
}

function bestAccuracy(readings) {
    return Math.min(...readings.map(r => r.accuracy));
}

export default class visitAccountDetailComponent extends NavigationMixin(LightningElement) {
    @track visit = {};
    @track outletPhotoUrl = '';
    @track isLoading = false;
    @api recordId; 
    @track latitude;
    @track longitude;
    @track locationCaptured = false;
    @track currentRecId;
    @track isCheckInActive = false;
    @track isSaveDisabled = true;
    @track IsUnproductive = false;
    selfieData;
    isSaveDisabled = true; 
    @track progressValue = 0;
    @track fileName = '';  
    @track fileType = '';
  isCollapsed = true;
isComCollpased=true;
    showparentcomponent = false;
    @track showchildcomponent = false;
    @track isMainComponent = false;
    @track isDistanceIsMore= false; 
    @track isRetailerUpdate = false;
    @track isDistanceIsMoreMessage= ''; 
    _accountId;
    //Mark Unproductive
    @track selectedReason;
    @track selectedVisit;
    @track isLoading = false;
    @track showChildComponent = false;
    @track isCheckInActive = false; 
    selectedUser = '';  // For storing the selected user in the lookup
    @track isCheckInPopUp = false; 
    @track isCheckInSuccess = false;
    @track   isPurpose=false;
    @track isCheckInDone = false;
    @track isCheckOutDisabled = true; // Set this to true initially to disable the button
    @track   isStartCall=false;
    @track   isCompleted=false;
    @track   isrecordStart=false;
    @track   isrecordComplete=false;
    @track   isreasonExist=false;
    @track   isStartRecordCall=false;
    @track   isOrderPlacedVisit=false;
    @track   isviewOrder=false;
@track visitId ;
_accountId;
recordId = '';
@track twoButtonClick=false;
@track competitorbuttonclick=false;
@track competitorinfo;
@track callbackFlow;
//to show flow of assests DX managment
 flowApiName = '';
 //to show and hide the flow screen
  @track renderFlow=false;
  @track showFlowWindow = false;
  @track visitedSchemeCheck;
  @track visitedViewOrderCheck;
  @track visitedQuanitySchemeCheck;
  @track visitedValueSchemeCheck;
  @track visitedShowProductList;
  @track  visitedShowFocusedProductList;
  @track  visitedCartPage;
  @track  visitedNoOrder;
  @track searchQuery = '';  // Search query input
  @track filteredUserOptions = [];  // Filtered options based on search query
  @track userOptions = [];  // All users fetched from Apex
  @track selectedUser = null; // Selected user ID
  @track isChildComponenet=false;
  //Added for selfie
    @track isCameraOn = false;
    photoURL = null;
    videoStream = null;
    //End of Selfie
  @track checkInDoneToTriggerFlow = false;

  currentVisitTask;
/*-----26/3/2026-------*/
  @track showCaseAsset = false;
@track selectedScreen = '';
@track isCaseAssetScreen = true;
@track isBrandingScreen = false;
@track isenableMappedAsset = false;
@track retailerId;




handleOpen(event) {
    const type = event.detail;

    this.showCaseAsset = true;

    this.isCaseScreen = type === 'case';
    this.isAssetScreen = type === 'asset';
    this.isBrandingScreen = false;
    this.isCaseAssetScreen = false;
}

// Branding audit opens the same way Mapped Asset does - the panel replaces
// the button grid rather than rendering underneath it. Viewing is never gated;
// the panel itself decides whether the audit may be submitted.
handleOpenBranding() {
    this.showCaseAsset = true;
    this.isCaseScreen = false;
    this.isAssetScreen = false;
    this.isBrandingScreen = true;
    this.isCaseAssetScreen = false;
}

handlegoBack() {
    this.showCaseAsset = false;
    this.isCaseScreen = false;
    this.isAssetScreen = false;
    this.isBrandingScreen = false;
     this.isCaseAssetScreen = true;
}




 /*------------*/ 
  
   
//This method will be called when component loaded
       
       connectedCallback() {
        this.checkInDoneToTriggerFlow = localStorage.getItem('checkInDoneToTriggerFlow');
        const urlParams = new URLSearchParams(window.location.search);
 
        this.visitId = urlParams.get('visitid');
        if (this.visitId) {
        // Persist visitId in sessionStorage
        localStorage.setItem('visitId', this.visitId);
        this.showChildComponent = true;
        } else {
            // Read visitId from sessionStorage if not available in URL
            this.visitId = localStorage.getItem('visitId');
            if (this.visitId) {
                this.showChildComponent = true;
            }
        }
        this.visitedSchemeCheck = localStorage.getItem('visitedScheme');
        this.visitedQuanitySchemeCheck = localStorage.getItem('visitedQuantityScheme');
        this.visitedValueSchemeCheck = localStorage.getItem('visitedValueScheme');

        if (this.visitedSchemeCheck || this.visitedQuanitySchemeCheck || this.visitedValueSchemeCheck) {
            this.twoButtonClick = true;
            this.isMainComponent=true;
        }
        this.visitedViewOrderCheck = localStorage.getItem('visitedViewOrder');
        if (this.visitedViewOrderCheck) {
            this.isviewOrder = true;
            this.isMainComponent=true;
        }
        this.visitedShowProductList = localStorage.getItem('visitedShowProductList');
        if (this.visitedShowProductList) {
            this.isChildComponenet = true;
            this.isMainComponent=true;
        }
        this.competitorinfo = localStorage.getItem('competitorinfo');
        if (this.competitorinfo) {
            this.competitorbuttonclick = true;
            this.isMainComponent=true;
        }
        this.visitedShowFocusedProductList = localStorage.getItem('visitedShowFocusedProduct');
        if (this.visitedShowFocusedProductList) {
            this.isChildComponenet = true;
            this.isMainComponent=true;
        }
        this.visitedCartPage = localStorage.getItem('visitedCartPage');
        if (this.visitedCartPage) {
            this.isChildComponenet = true;
            this.isMainComponent=true;
        }
  
        this.visitedNoOrder = localStorage.getItem('visitedNoOrder');
        if (this.visitedNoOrder) {
            this.IsUnproductive = true;
  
        }
        this.visitedSelfieCheck = localStorage.getItem('visitedSelfie');
        if (this.visitedSelfieCheck) {
            this.isCheckInSuccess = true;
            this.isMainComponent=true;
  
        }
        this.visitedPurposeCheck = localStorage.getItem('visitedPurposeVisit');
        if (this.visitedPurposeCheck) {
            this.isPurpose = true;
            this.isMainComponent=true;
            this.fetchUsers();
  
        }
        this.callbackFlow = localStorage.getItem('toggleFlow');
        if (this.callbackFlow) {
            this.renderFlow = true;
            this.showFlowWindow= true;
            this.flowApiName=this.callbackFlow;
        }
     
        this.recordId = window.sessionStorage.getItem('visitId');
        this.currentRecId = this.visitId;  
       /*this.fetchVisitRecord();//this.isrecordStart=true; 
       this.fetchVisitCompleteRecord();//this.isrecordComplete=true;
       this.fetchVisitReason();//this.isreasonExist=true;
       this.fetchStartCallVisit();//this.isStartRecordCall=true;
       this.fetchVisitOrderPlacedRecord(); //this.isOrderPlacedVisit=true;*/
       this.fetchCurrentRecord();
       window.sessionStorage.setItem('isFromOrderPage','Yes');

       this.loadVisitTaskDetails();
  

       }
    fetchCurrentRecord(){
        getCurrentVisitRecord({ visitTaskRecordId: this.currentRecId})
            .then(record => {
                
                this.currentVisitTask = record;
				this.isrecordStart=(this.currentVisitTask.Purpose_of_Visit__c || this.currentVisitTask.Start_Call_Time__c)?true:false
				this.isrecordComplete=(this.currentVisitTask.Checked_Out_Time__c || this.currentVisitTask.End_Call_Time__c)?true:false;
				this.isreasonExist =(this.currentVisitTask.Unproductive_Reasons__c)?true:false;
				this.isStartRecordCall = (this.currentVisitTask.Start_Call_Time__c)?true:false;
				this.isOrderPlacedVisit = (this.currentVisitTask.Order_Placed__c == true)?true:false;
				
				// Set isCheckInDone based on Status, Checked_In_Time, or Purpose_of_Visit
				if (this.currentVisitTask.Status__c === 'In-Progress' || this.currentVisitTask.Checked_In_Time__c || this.currentVisitTask.Purpose_of_Visit__c) {
					this.isCheckInDone = true;
					// added by Fuzail - Enable Check-Out button only if order is placed OR no order reason exists
					this.isCheckOutDisabled = !(this.isOrderPlacedVisit || this.isreasonExist);
					if (this.currentVisitTask.Status__c === 'In-Progress') {
						this.isrecordStart = true;
					}
				} else {
					this.isCheckInDone = false;
					this.isCheckOutDisabled = true;
				}
            })
            .catch(error => {
                this.showToast(
                    'Error',
                    error?.body?.message || 'Error loading visit details.',
                    'error'
                );            
            });
    }
 //This method will show the competitor info capture component
    competitorbuttonclicked(){

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
                 this.competitorbuttonclick=true;
                 this.isMainComponent=true;
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

         //This method will show the scheme component
  twoSchemesClick(){
    this.twoButtonClick=true;
    this.isMainComponent=true;
    }
    //This method will show the component for latest orders
    loadLatestOrders(){
        this.isviewOrder=true;
        this.isMainComponent=true;
    }
//This method will be called from connectedcallback in order to check start call clicked or not
    fetchStartCallVisit() {
        const visitIdToPass = this.visitId;  
        if (visitIdToPass) {
            getVisitTaskStartCallRecord({ visitTaskRecordId: visitIdToPass })
                .then(result => {
                    if (result) {
                        this.isStartRecordCall=true;
                    }

                })
                .catch(error => {
                    this.showToast(
                        'Error',
                        error?.body?.message || 'Error loading visit details.',
                        'error'
                    );
                });
        }
    }

    //This method will be called from connectedcallback in order to show visit action
    fetchVisitRecord() {
        const visitIdToPass = this.visitId;  
        if (visitIdToPass) {
            getVisitTaskRecord({ visitTaskRecordId: visitIdToPass })
                .then(result => {
                    if (result) {
                        this.isrecordStart=true;
                    }

                })
                .catch(error => {
                    this.showToast(
                        'Error',
                        error?.body?.message || 'Error loading visit details.',
                        'error'
                    );            
                    });
        }
    }

        //This method will be called from connectedcallback in order to check order placed for Visit task or not

    fetchVisitOrderPlacedRecord() {
        const visitIdToPass = this.visitId;  
        if (visitIdToPass) {
            getVisitTaskOrderPlacedRecord({ visitTaskRecordId: visitIdToPass })
                .then(result => {
                    if (result) {
                        this.isOrderPlacedVisit=true;
                        // added by Fuzail - Enable Check-Out button when order is placed
                        if (this.isCheckInDone && !this.isrecordComplete) {
                            this.isCheckOutDisabled = false;
                        }
                    }

                })
                .catch(error => {
                    this.showToast(
                        'Error',
                        error?.body?.message || 'Error loading visit details.',
                        'error'
                    );                
                });
        }
    }

            //This method will be called from connectedcallback in order to check  Visit task completed or not

    fetchVisitCompleteRecord() {
        const visitIdToPass = this.visitId;  
        if (visitIdToPass) {
            getVisitTaskCompleteRecord({ visitTaskRecordId: visitIdToPass })
                .then(result => {
                    if (result) {
                        this.isrecordComplete=true;
                    }

                })
                .catch(error => {
                    this.showToast(
                        'Error',
                        error?.body?.message || 'Error loading visit details.',
                        'error'
                    );           
                       });
        }
    }
                //This method will be called from connectedcallback in order to check No order button clicked or not

    fetchVisitReason() {
        const visitIdToPass = this.visitId;  
        if (visitIdToPass) {
            getVisitTaskReson({ visitTaskRecordId: visitIdToPass })
                .then(result => {
                    if (result) {
                        this.isreasonExist=true;
                    }

                })
                .catch(error => {
                    this.showToast(
                        'Error',
                        error?.body?.message || 'Error loading visit details.',
                        'error'
                    );               
                  });
        }
    }
//This method will be called to show Visit task record

    get isButtonSection() {
        return this.isCheckInActive || this.IsUnproductive || this.showchildcomponent; // Returns true if either condition is true
    }
//This method will be called to show options for No order

    get options() {
        return [
            { label: 'Shop closed', value: 'Shop closed' },
            { label: 'Not interested - pricing / quality issue', value: 'Not interested - pricing / quality issue' },
            { label: 'Not interested - competing products / brands available  ', value: 'Not interested - competing products / brands available  ' },
            { label: 'Old stock available', value: 'Old stock available' },
            { label: 'Owner not available', value: 'Owner not available' },
            { label: 'Joint Visit', value: 'Joint Visit' },
            { label: 'Order on Next Visit', value: 'Order on Next Visit' },
            { label: 'Place Order Tomorrow', value: 'Place Order Tomorrow' }
        ];
    }
//This method will be called to show options for purposeOfVisit

    get purposeOfVisit() {
        return [
            { label: 'Individual visit', value: 'Individual visit' },
            { label: 'Joint visit', value: 'Joint visit' }
        ];
    }

       // Handle the change in selected user (for lookup)
       handleUserLookupChange(event) {
        this.selectedUserId  = event.detail.value;
    }

       // Check if 'Joint visit' is selected
       get isJointVisit() {
        return this.selectedVisit === 'Joint visit';
    }
    @wire(CurrentPageReference)
    pageRef;    
    
    @api
    get accountId() {
        return this._accountId;
    }

    set accountId(value) {
        this._accountId = value;
      
        this.loadVisitTaskDetails();
       // this.loadVisitTasks();
    }


//This method will be called to show Retailer information section

    get isRetailer() {
        return this.visit && this.visit.recordTypeName === 'Retailer';
    }


//This method will be called to show visit task retailer section

    loadVisitTaskDetails() {
        

        if (this._accountId) {
            getVisitTaskDetails({ visitTaskRecordId: this._accountId })
                .then(result => {

                    this.visit = result || {};
                    this.retailerId = this.visit.accountIdMap;

                console.log('RetailerId:', this.retailerId);
                  
                })
                .catch(error => {
                    this.showToast(
                        'Error',
                        error?.body?.message || 'Error loading visit details.',
                        'error'
                    );               
                  });
        }
    }
    
 //This method will be called to show all visit tasks

    handleBack() {
        // Dispatch back event to parent component (visitListView1)
        const backEvent = new CustomEvent('back');
        this.dispatchEvent(backEvent);
    }
    
     //This method will be called to get location details after start call clicked

    handleStartCallMethod() {
        this.isLoading = true;
        checkTodayVisitTask()
            .then(result => {
                if (result) {
                    const visitInfo = JSON.parse(result);
                    const retailerName = visitInfo.retailerName || 'Retailer';
                    const retailerCode = visitInfo.retailerCode ? `[${visitInfo.retailerCode}]` : '';

                    this.showToast(
                        'Error',
                        `You cannot proceed as you must first check out or end the ongoing call for ${retailerName} ${retailerCode}.`,
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
                this.showToast('Error','Error in checking Visit Task: ' + error.body.message,'error');
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
                    // mode: 'sticky'
                })
            );
        }
    }
     //This method will be called to save location details in database after start call clicked

    handleStartCallLocationSave(){
        this.isLoading=true;
        // Call Apex method to save the visit task record
        saveStartCallLocationTimeRecord({
            visitId: this.visitId,
            latitude: this.latitude.toString(),
            longitude: this.longitude.toString(),
            accuracy: this.accuracy            // FIX 3B: pass accuracy for audit coverage
        })
        .then((result) => {
            if (result) {
                this.showToast('Success', 'Start call Location has been Captured Successfully', 'success');
                this.isLoading=false;
                this.isStartCall=true;
                this.isCheckInDone=true
            }
        })
        .catch((error) => {
            this.showToast('Error', 'Error in updating Start call location in Visit Task.', 'error');
            this.isLoading=false;
        });
    }

//This method will be called when No order back  button called

backAction(){
    this.IsUnproductive = false;
    localStorage.removeItem(`visitedNoOrder`); 
   // window.location.reload();

}
        
 

//This method will be called to show toast message

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(evt);
    }

   
  
//This method will be called when check in button called and capture location
    /*handleCheckInMethod(event) {
        this.isLoading=true;
        checkTodayVisitTask()
        .then(result => {
            if (result === true) {
                this.showToast('Error', 'You cannot proceed as you must first check out from the previous outlet or end the ongoing call.', 'error');
                this.isLoading=false;         
            } else if (result === false) {
                // this.showToast('Success', 'All assets have been audited.', 'success');
                this.isLoading=false;
                // Show popup first  
                this.isCheckInPopUp = true;       
                const visitIdToPass = this.visitId;         
                // Start location verification
                this.verifyLocation(visitIdToPass);
            }else {
                // Handle unexpected result (e.g., null or undefined)
                this.showToast('Error', 'Unexpected response from checking Todays VisitTask.', 'error');
                this.isLoading = false;
            }
        })
        .catch(error => {
            this.showToast('Error', 'Error in checking Todays VisitTask' + error.body.message, 'error');
            this.isLoading=false;
        }); 
    }*/

    handleCheckInMethod(event) {
        this.isLoading = true;
        checkTodayVisitTask()
        .then(result => {
            if (result) {
                const visitInfo    = JSON.parse(result);
                const retailerName = visitInfo.retailerName || 'Retailer';
                const retailerCode = visitInfo.retailerCode ? `[${visitInfo.retailerCode}]` : '';
                this.showToast('Error', `You cannot proceed as you must first check out or end the ongoing call for ${retailerName} ${retailerCode}.`, 'error');
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
            await this.getCurrentLocationDataForCheckIn();
            this.handleVisitTaskRecord(finalVisitId);
            this.isCheckInPopUp = false;
            localStorage.setItem('visitedSelfie', true);
        } catch (error) {
            this.isCheckInPopUp = false;
            localStorage.removeItem('visitedSelfie');
            this.dispatchEvent(new ShowToastEvent({
                title: 'Location Error',
                message: error.message || 'There was a problem verifying your location.',
                variant: 'error'
            }));
        }
    }

    /*async getCurrentLocationDataForCheckIn() {
        if (!navigator.geolocation) {
            throw new Error('Geolocation is not supported by this browser.');
        }

        if (navigator.permissions) {
            let permState;
            try {
                const perm = await navigator.permissions.query({ name: 'geolocation' });
                permState = perm.state;
            } catch (e) {
                // Permissions API unavailable on this browser — continue without check
            }
            if (permState === 'denied') {
                throw new Error(
                    'Location permission is blocked. Enable it in your browser ' +
                    'and OS settings, then try again.'
                );
            }
        }

        return new Promise((resolve, reject) => {  // FIX 3.2: plain (non-async) executor
            const readings = [];
            let watchId;

            const finish = (lat, lng, accuracy, snapshot) => {
                navigator.geolocation.clearWatch(watchId);

                if (accuracy > MIN_FINISH_ACCURACY) {
                    return reject(new Error(
                        'GPS accuracy is too poor right now (' + Math.round(accuracy) + ' m). ' +
                        'Move to an open area and try again.'
                    ));
                }

                this.latitude  = lat;
                this.longitude = lng;
                localStorage.setItem('latitude', this.latitude);
                localStorage.setItem('longitude', this.longitude);

                this.accuracy = accuracy;

                const best = snapshot.reduce((a, b) => a.accuracy <= b.accuracy ? a : b);
                this.locationTimestamp = best.timestamp;

                resolve();
            };

            const hardTimeout = setTimeout(() => {
                if (snapshot.length > 0) {
                    // Use whatever filtered readings arrived before the timeout
                    const [lat, lng]  = weightedAverage(snapshot);
                    const accuracy    = bestAccuracy(snapshot); // FIX 3.3: shared helper
                    finish(lat, lng, accuracy, snapshot);
                } else {
                    navigator.geolocation.clearWatch(watchId); // clean up before rejecting
                    // FIX #6: Replace reload with a descriptive error the caller surfaces via Retry
                    reject(new Error(
                        'Could not obtain a GPS fix in time. ' +
                        'Ensure location is enabled and try again.'
                    ));
                }
            }, READING_TIMEOUT_MS);

            watchId = navigator.geolocation.watchPosition(
                (position) => {
                    const acc = position.coords.accuracy;

                    // FIX #2: Discard any individual reading worse than MAX_READING_ACCURACY
                    if (acc > MAX_READING_ACCURACY) return; // keep watching for better fix

                    readings.push({
                        lat:       position.coords.latitude,
                        lng:       position.coords.longitude,
                        accuracy:  acc,
                        timestamp: position.timestamp, 
                        weight:    1 / (acc || 1)
                    });

                    if (readings.length >= READINGS_TO_AVERAGE) {
                        clearTimeout(hardTimeout);
                        const snapshot       = readings.slice(); 
                        const [lat, lng]     = weightedAverage(snapshot);
                        const accuracy       = bestAccuracy(snapshot); 
                        finish(lat, lng, accuracy, snapshot);
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
                            errorMessage = 'Turn on location manually if it\'s not already enabled and try again.';
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
    }*/

    async getCurrentLocationDataForCheckIn() {
        if (!navigator.geolocation) {
            throw new Error('Geolocation is not supported by this browser.');
        }

        if (navigator.permissions) {
            let permState;
            try {
                const perm = await navigator.permissions.query({ name: 'geolocation' });
                permState = perm.state;
            } catch (e) {
                // Permissions API unavailable on this browser — continue without check
            }
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
            let isFinished = false; // Guard to prevent multiple resolve/reject calls

            const finish = (lat, lng, accuracy, snapshot) => {
                if (isFinished) return;
                isFinished = true;

                if (watchId != null) {
                    navigator.geolocation.clearWatch(watchId);
                }
                clearTimeout(hardTimeout);

                if (accuracy > MIN_FINISH_ACCURACY) {
                    return reject(new Error(
                        'GPS accuracy is too poor right now (' + Math.round(accuracy) + ' m). ' +
                        'Move to an open area and try again.'
                    ));
                }

                this.latitude  = lat;
                this.longitude = lng;
                localStorage.setItem('latitude', this.latitude);
                localStorage.setItem('longitude', this.longitude);

                this.accuracy = accuracy;

                try {
                    const best = snapshot.reduce((a, b) => a.accuracy <= b.accuracy ? a : b);
                    this.locationTimestamp = best.timestamp;
                } catch (e) {
                    this.locationTimestamp = Date.now();
                }

                resolve();
            };

            // FIX: 'snapshot' is now correctly derived from 'readings' inside the timeout callback
            const hardTimeout = setTimeout(() => {
                if (isFinished) return;
                isFinished = true;

                if (watchId != null) {
                    navigator.geolocation.clearWatch(watchId);
                }

                // Use a snapshot copy of whatever readings arrived before timeout
                const snapshot = readings.slice();

                if (snapshot.length > 0) {
                    const [lat, lng] = weightedAverage(snapshot);
                    const accuracy   = bestAccuracy(snapshot);

                    if (accuracy > MIN_FINISH_ACCURACY) {
                        reject(new Error(
                            'GPS accuracy is too poor right now (' + Math.round(accuracy) + ' m). ' +
                            'Move to an open area and try again.'
                        ));
                        return;
                    }

                    this.latitude  = lat;
                    this.longitude = lng;
                    localStorage.setItem('latitude', this.latitude);
                    localStorage.setItem('longitude', this.longitude);
                    this.accuracy = accuracy;

                    try {
                        const best = snapshot.reduce((a, b) => a.accuracy <= b.accuracy ? a : b);
                        this.locationTimestamp = best.timestamp;
                    } catch (e) {
                        this.locationTimestamp = Date.now();
                    }

                    resolve();
                } else {
                    reject(new Error(
                        'Could not obtain a GPS fix in time. ' +
                        'Ensure location is enabled and try again.'
                    ));
                }
            }, READING_TIMEOUT_MS);

            try {
                watchId = navigator.geolocation.watchPosition(
                    (position) => {
                        if (isFinished) return;

                        const acc = position.coords.accuracy;

                        // Discard any individual reading worse than MAX_READING_ACCURACY
                        if (acc > MAX_READING_ACCURACY) return;

                        readings.push({
                            lat:       position.coords.latitude,
                            lng:       position.coords.longitude,
                            accuracy:  acc,
                            timestamp: position.timestamp,
                            weight:    1 / (acc || 1)
                        });

                        if (readings.length >= READINGS_TO_AVERAGE) {
                            const snapshot   = readings.slice();
                            const [lat, lng] = weightedAverage(snapshot);
                            const accuracy   = bestAccuracy(snapshot);
                            finish(lat, lng, accuracy, snapshot);
                        }
                    },
                    (error) => {
                        if (isFinished) return;
                        isFinished = true;

                        clearTimeout(hardTimeout);
                        if (watchId != null) {
                            navigator.geolocation.clearWatch(watchId);
                        }

                        let errorMessage;
                        switch (error.code) {
                            case error.PERMISSION_DENIED:
                                errorMessage = 'Location permission was denied. Please enable location access.';
                                break;
                            case error.POSITION_UNAVAILABLE:
                                errorMessage = 'Location information is unavailable.';
                                break;
                            case error.TIMEOUT:
                                errorMessage = 'Turn on location manually if it\'s not already enabled and try again.';
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
            } catch (e) {
                // watchPosition itself threw (extremely rare, e.g. internal browser error)
                if (!isFinished) {
                    isFinished = true;
                    clearTimeout(hardTimeout);
                    reject(new Error('Failed to start location watch: ' + (e.message || 'Unknown error')));
                }
            }
        });
    }


//This method will be called to save check in details

handleVisitTaskRecord(finalVisitId) {
    // Call Apex method to save the visit task record
    saveVisitTask({
        visitId: this.visitId,
        latitude: this.latitude.toString(),
        longitude: this.longitude.toString(),
        accuracy: this.accuracy            // FIX 3B: pass accuracy to enable passive backfill in Apex
    })
    .then((result) => {
        if (result === 'success') {
            this.showToast('Success', 'Check In Location has been Captured Successfully.', 'success');
            this.isMainComponent=true;
            this.isCheckInSuccess=true;
        
            this.isCheckInDone=true;
            this.checkInDoneToTriggerFlow = true;
            localStorage.setItem('checkInDoneToTriggerFlow', true);
            // Start camera with error handling
            this.startCamera().catch((error) => {
                console.error('Error starting camera:', error);
                // Camera error is already handled in startCamera with toast
            });
        } else if (result.includes(ACCOUNT_LOCATION_UNAVAILABLE)) {
            localStorage.removeItem(`visitedSelfie`); 
            this.showToast('Error', ACCOUNT_LOCATION_UNAVAILABLE, 'error');
        } else if(result.includes('retailerLocationUpdate=true')){
            this.isRetailerUpdate = true;
            this.isDistanceIsMoreMessage = Retailer_Location_Update_Message;
        } else if(result.includes(BEYOND_50)){
            this.isDistanceIsMore = true;
            this.isDistanceIsMoreMessage = BEYOND_50;
        } else{
            this.showToast('Error', result, 'error');
        }
    })
    .catch((error) => {
        this.showToast('Error', 'An unexpected error occurred. Please try again.', 'error');
    });
}
//This method will be called to close distance more popup

handleCloseModal(){
    this.isDistanceIsMore=false;
    this.isRetailerUpdate=false;
    this.isMainComponent=false;
    this.isCheckInDone=false;
    localStorage.removeItem(`visitedSelfie`); 
    
}

/*handleUpdateRetailerLocation(){
    updateRetailerLocation({
        visitId: this.visitId,
        latitude: this.latitude.toString(),
        longitude: this.longitude.toString()
    })
    .then((result) => {
        if (result === 'success') {
            this.showToast('Success', 'Retailer location has been updated successfully.', 'success');
            this.handleCloseModal();
        }
    })
    .catch((error) => {
        this.showToast('Error', 'An unexpected error occurred. Please try again.', 'error');
    });
}*/

    async handleUpdateRetailerLocation() {
        this.isLoading = true;
        try {
            await this.getCurrentLocationDataForCheckIn();
        } catch (error) {
            this.isLoading = false;
            this.dispatchEvent(
                new ShowToastEvent({title: 'Location Error', message: error.message || 'There was a problem verifying your location.',
                    variant: 'error'})
            );
            return;
        }

        updateRetailerLocation({visitId:   this.visitId,latitude:  this.latitude.toString(),longitude: this.longitude.toString(), accuracy:  this.accuracy})
        .then((result) => {
            if (result === 'success') {
                this.showToast('Success', 'Retailer location has been updated successfully.', 'success');
                this.handleCloseModal();
            } else {
                this.showToast('Error', result, 'error');
            }
            this.isLoading = false;
        })
        .catch((error) => {
            this.showToast('Error', 'An unexpected error occurred. Please try again.', 'error');
            this.isLoading = false;
        });
    }

//This method will be called for  SelfieFile details

   handleSelfieFileChange(event) {
    const visitIdToPass = this.visitId;  
    window.sessionStorage.setItem('visitId', this.visitId);
    const file = event.target.files[0];   
    if (file) {
        const reader = new FileReader();       
        // Load file as Data URL
        reader.onload = (e) => {
            const img = new Image();
            img.src = e.target.result;           
            // Once the image is loaded
            img.onload = () => {
                // Create a canvas element
                const canvas = document.createElement('canvas');
                const ctx = canvas.getContext('2d');
                
                // Set desired compression scale (50% of the original size)
                const width = img.width * 0.5;
                const height = img.height * 0.5;
                
                canvas.width = width;
                canvas.height = height;
                ctx.drawImage(img, 0, 0, width, height);
                const compressedDataUrl = canvas.toDataURL(file.type, 0.7); // Compress with 70% quality
                const base64 = compressedDataUrl.split(',')[1];               
                this.selfieData = base64;
                this.fileName = file.name;           
                this.fileType = file.type;               
                this.checkIfSelfieSaveEnabled(); // Check if save should be enabled
            };
        };        
        // Track upload progress
        reader.onprogress = (event) => {
            if (event.lengthComputable) {
                this.progressValue = Math.round((event.loaded / event.total) * 100);
            }
        };
        reader.readAsDataURL(file);  // Read file as Data URL for image compression
    }   
}

    //This method will be called to  save SelfieFile details
    handleSelfieSave() {
        if (!this.selfieData ) {
            this.showToast('Error', 'Please capture selfie before saving.', 'error');
            return;
        }
        this.isLoading=true;
        const visitIdToPass = this.visitId; 
        saveSelifeData({
            visitId: visitIdToPass,
            base64Image: this.selfieData
            
        })
        .then(() => {
            this.showToast('Success', 'Selfie is captured and saved successfully.', 'success');
            this.isLoading = false;
            this.isMainComponent=true;
            this.isCheckInPopUp=false;
            this.isCheckInSuccess=false;
            this.isPurpose=true;
            localStorage.setItem('visitedPurposeVisit', true);
            localStorage.removeItem(`visitedSelfie`); 
        })
        .catch(error => {
            this.showToast('Error', 'Failed to save data.', 'error');
        });
    }

    checkIfSelfieSaveEnabled() {
        // Enable the Save button if selfie are captured
        if (this.selfieData) {
            this.isSaveDisabled = false;
        }
    }

    // Visit Task Id for child components - same resolution the check-out path uses.
    get currentVisitTaskId() {
        return this.recordId != null ? this.recordId : this.visitId;
    }

    // Reason resolved from the saved record first, then the in-memory /
    // localStorage copy used before the record is re-fetched.
    get unproductiveReason() {
        return (this.currentVisitTask && this.currentVisitTask.Unproductive_Reasons__c)
            || this.selectedReason
            || localStorage.getItem('selectedReason');
    }

    proceedToCheckout() {
        this.isLoading = false;
        const visitIdToPass = this.visitId;
        this.verifyCheckoutLocation(visitIdToPass);
        localStorage.removeItem(`checkInDoneToTriggerFlow`);
        this.checkInDoneToTriggerFlow = false;
    }

    //This method will be called to  save check out location details
    handleCheckOutMethod(){
        this.isLoading=true;
        if (!this.selectedReason) {
            const storedReason = localStorage.getItem('selectedReason');
            if (storedReason) {
                this.selectedReason = storedReason;
            }
        }
        // No Order visits with these reasons skip BOTH the freezer and the branding audit
        const reason = this.unproductiveReason;
        if (reason === 'Shop closed' || reason === 'Joint Visit') {
            this.showToast('Success', 'Skipping audit check', 'success');
            this.proceedToCheckout();
            return;
        }
        const visitTaskRecordId = this.recordId != null ? this.recordId : this.visitId;
        checkAllAssetsAudited({ visitTaskId: visitTaskRecordId })
        .then(result => {
            if (result === 'VISIT_AUDITED') {
                this.showToast('Success', 'All assets have been audited.', 'success');
            } else if (result === 'MONTH_AUDITED') {
                this.showToast('Success', 'This asset has already been audited in the last 30 days.', 'success');
            } else {
                this.showToast('Error', 'Some assets are missing an audit.', 'error');
                this.isLoading = false;
                return null;
            }
            // Freezer audit is clear - now gate on the mapped branding audit
            return checkAllBrandingAudited({ visitTaskId: visitTaskRecordId })
                .then(brandingResult => {
                    if (brandingResult === 'VISIT_AUDITED') {
                        this.proceedToCheckout();
                    } else if (brandingResult === 'NOT_AUDITED') {
                        this.showToast('Error', 'Please complete the Mapped Branding audit before check-out.', 'error');
                        this.isLoading = false;
                    } else {
                        this.showToast('Error', 'Could not verify the Mapped Branding audit. Please try again.', 'error');
                        this.isLoading = false;
                    }
                });
        })
        .catch(error => {
            this.showToast('Error', 'Error checking audit status: ' + error.body.message, 'error');
            this.isLoading=false;
        });
    }

    async verifyCheckoutLocation(finalVisitId) {
        try {
            // Simulate verifying location asynchronously
            await new Promise((resolve) => setTimeout(resolve, 3000)); // Simulating a delay

            // Get location data
            await this.getCurrentLocationDataForCheckIn();

            // Once location data is fetched successfully, call handleVisitTaskRecord
            this.handleCheckOutRecord(finalVisitId);

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
                    // mode: 'sticky'
                })
            );
        }
    }

    // Handle the change in selected purpose of visit
    handlePurposeOfVisitChange(event) {
        this.selectedVisit = event.detail.value;
    }

    //This method will be called to  save PurposeVisit details
    handlePurposeVisitSave(event){
        const visitTaskIdToPass = this.visitId;   
        if(this.selectedVisit==''||this.selectedVisit==null){
            this.showToast('Error', 'Please select purpose of Visit.', 'error');
            return;
        }
        if(this.selectedVisit=='Joint visit' && (this.selectedUser==''||this.selectedUser==null)){
            this.showToast('Error', 'Please select User from dropdown for Joint visit.', 'error');
            return;
        }
        let latitude = this.latitude;
        let longitude = this.longitude;
        if (!latitude || !longitude) {
            latitude = localStorage.getItem('latitude');
            longitude = localStorage.getItem('longitude');
        }
        savePurposeOfVisitData({
            visitTaskId: visitTaskIdToPass,
            reason: this.selectedVisit,
            userId: this.selectedUser,
            latitude: latitude,
            longitude: longitude,
            accuracy: this.accuracy            // FIX 3B: pass accuracy for audit coverage
        })
        .then(() => {
            this.showToast('Success', 'Purpose of Visit is saved successfully.', 'success');
            this.isMainComponent=false;        
            this.isPurpose=false;
            this.isrecordStart=false;
            this.isCheckInDone=true;      
            localStorage.removeItem(`visitedPurposeVisit`); 
            localStorage.removeItem('latitude');
            localStorage.removeItem('longitude');
        })
        .catch(error => {
            this.showToast('Error', 'Error in updating Visit Task Record.', 'error');      
        });
    }

    //This method will be called to  save CheckOutRecord details
    handleCheckOutRecord(finalVisitId) {
        this.isLoading=true;
        // Call Apex method to save the visit task record
        saveCheckOutRecord({
            visitId: this.visitId,
            latitude: this.latitude.toString(),
            longitude: this.longitude.toString(),
            accuracy: this.accuracy            // FIX 3B: pass accuracy for audit coverage
        })
        .then((result) => {
            if (result) {
                this.showToast('Success', 'Check Out Location has been Captured Successfully', 'success');
                this.isLoading=false;
                this.isMainComponent=false;
                this.isCheckInDone=false;
                this.isCompleted=false;
                this.isrecordStart=false;
                this.isStartRecordCall=false;
                this.fetchVisitCompleteRecord();//this.isrecordComplete=true;
                localStorage.removeItem(`selectedReason`);
            }
        })
        .catch((error) => {
            this.showToast('Error', 'Error in updating checkout location in Visit Task.', 'error');
            this.isLoading=false;
        });
    }

    //This method will be called to handleReasonChange
    handleReasonChange(event) {
        this.selectedReason = event.detail.value;
        localStorage.setItem('selectedReason', this.selectedReason);
    }

    //This method will be called to handlePurposeOfVisit
    handlePurposeOfVisitChange(event) {
        this.selectedVisit = event.detail.value;
        if (this.isJointVisit) {
            this.fetchUsers();
        }
    }

    //This method will be called when NoOrder button clicked
    handleNoOrder() {
        checkUserChecking({ currentVisitTaskId: this.visitId, actionType: 'NoOrder' })
        .then((result) => {
            if (result.isAllowed) {
                localStorage.setItem('visitedNoOrder', true);
                this.IsUnproductive = true;
            } else {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: result.errorMessage,
                    variant: 'error'
                }));
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

    //This method will be called to save NoOrder details
    handleNoOrderSave(event){
        const visitTaskIdToPass = this.visitId;
        saveNoOrderData({
            visitTaskId: visitTaskIdToPass,
            reason:this.selectedReason
            
        })
        .then(() => {
            this.showToast('Success', 'Unproductive reason saved successfully.', 'success');
            this.isMainComponent=false;        
            this.IsUnproductive=false;
            this.isCheckInDone=false;
            this.isCheckOutDisabled = false; // Enable "Check-Out" button after check-in is done
            this.isenableMappedAsset = true;
            this.isreasonExist=true;
            this.isStartCall=false;
            this.fetchVisitRecord();//this.isrecordStart=true;
            this.fetchStartCallVisit();//this.isStartRecordCall=true;
            localStorage.removeItem(`visitedNoOrder`); 
        })
        .catch(error => {
            this.showToast('Error', 'Error in Saving Unproductive Reason.', 'error');       
        });
    }

    //This method will be called when back button clicked from selfie page
    closeActionCheckIn() {
        const visitTaskIdToPass = this.visitId;
        this.isLoading=true;
        this.isCheckInSuccess = false;
        this.isMainComponent=false;
        this.isCheckInDone=false;
        localStorage.removeItem(`visitedSelfie`); 
        
        removeCheckInDateTime({ visitTaskRecordId: visitTaskIdToPass})
        .then(() => {
            // Always stop loading after response
            this.isLoading = false;
        })
        .catch((error) => {
            this.isLoading = false;
            this.showToast('Error', 'Error in removing Check-In Details in Visit Task.', 'error');
        });
    }

    //This method will be called when create order button clicked
   /* handleCreateOrderMethod(){
        this.isMainComponent=true;
        this.isChildComponenet=true;

    }*/

   async handleCreateOrderMethod() {

    
    this.isLoading = true;

    const visitTaskRecordId = this.recordId != null ? this.recordId : this.visitId;

    try {

        const result = await checkAllAuditedForOrder({ visitTaskId: visitTaskRecordId });

        console.log('AUDIT STATUS:', result);

        if (result === 'YOU_CAN_PLACE_ORDER_WITHIN_30_DAYS') {

            this.showToast(
                'Error',
                'Order can only be placed within 30 days of the last audit.',
                'error'
            );

            this.isLoading = false;
            return;
        }

        // ✅ ALLOW ORDER
        
        this.isLoading = false;

    } catch (error) {

        this.showToast(
            'Error',
            error?.body?.message || 'Error checking audit status',
            'error'
        );

        this.isLoading = false;
    }
    this.isMainComponent = true;
        this.isChildComponenet = true;
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
            console.log('this.filteredUserOptions**1332*',this.filteredUserOptions);
        } else {
            // If the search query is empty, show all users
            this.filteredUserOptions = [...this.userOptions];
            console.log('this.filteredUserOptions**12*',this.filteredUserOptions);
        }
    }

    //This method will be called to  fetchUsers for join visit
    fetchUsers() {
        console.log('Enter fetchUsers method');
        searchUser()
        .then((result) => {
            console.log('result:- '+result);
            this.userOptions = result.map(user => ({
                label: `${user.Name}`, // Display Name and Email    label: `${user.Name} (${user.Email})`, // Display Name and Email

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

    // Handle selecting a user from the list
    handleSelectUser(event) {
        const selectedUserId = event.target.dataset.id; // Get the selected user ID
        const selectedUser = this.filteredUserOptions.find(user => user.value === selectedUserId);

        if (selectedUser) {
            this.searchQuery = selectedUser.label; // Set the user label in the input field
            this.filteredUserOptions = []; // Optionally clear the list after selection
            this.selectedUser = selectedUser.value; // Set selected user ID for further use
    
            // Optionally call a method to fetch more details about the user
        }
    }

    //This method will be called to  clearSearch box 
    clearSearchQuery() {
        this.searchQuery = ''; // Reset the search query
        this.filteredUserOptions = []; // Show all users
        this.selectedUser = null; // Clear any selected user
    }

    //Added by Ajay to dynamically pass visit task id to the flow
    get flowInputVariables(){
        return[
            {
                name: 'recordId',
                type: 'String',
                value: this.visitId
            }

        ];
    }


    // Added by Ajay to handle the state change of flow and control the rendering of flow
    handleStatusChange(event) {
        const status = event.detail.status;
        if (status === 'FINISHED') {
         
            this.dispatchEvent(new CloseActionScreenEvent());
            this.renderFlow = false;
          
            localStorage.removeItem(`toggleFlow`); 
            this.showToast('Success', '', 'success'); // Show success toast
             this.showFlowWindow= false;
            // Additional logic,hide the Flow or trigger another action
        } else if (status === 'ERROR') {
            this.showToast('Error', 'The flow encountered an error.', 'error');

        }
    }

   /* handleClick(event) {
        const flowName = event.target.dataset.flow;
        checkUserChecking({ currentVisitTaskId: this.visitId , actionType: 'DFAction' })
        .then((result) => {
            if (result.isAllowed) {
                this.flowApiName = flowName;
                this.renderFlow = true;
                this.showFlowWindow = true;
                localStorage.setItem('toggleFlow', this.flowApiName);
            } else {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: result.errorMessage,
                    variant: 'error'
                }));
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

    handleClickTaggedDF(event){
        this.flowApiName = event.target.dataset.flow; // Get flow API name from button
        this.renderFlow = true;
        this.showFlowWindow= true;
        localStorage.setItem('toggleFlow', this.flowApiName);
    }*/

    handleCloseFlow() {
        localStorage.removeItem('toggleFlow'); 
        this.renderFlow = false;
        this.showFlowWindow= false;
        //window.location.reload();
    }

    //This method will be called to  save check out location details
    handleEndCallMethod(){
        this.isLoading=true;
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
                    // mode: 'sticky'
                })
            );
        }
    }
    
    //This methos used to update the end call location and time on visittask
    handleEndCallRecord(finalVisitId) {
    this.isLoading=true;
        // Call Apex method to save the visit task record
        saveEndCallRecord({
            visitId: this.visitId,
            latitude: this.latitude.toString(),
            longitude: this.longitude.toString(),
            accuracy: this.accuracy            // FIX 3B: pass accuracy for audit coverage
        })
        .then((result) => {    
            if (result) {
                this.showToast('Success', 'End Call Location has been Captured Successfully', 'success');
                this.isLoading=false;
                this.isMainComponent=false;
                this.isCheckInDone=false;
                this.isCompleted=false;
                this.isrecordStart=false;
                this.isStartRecordCall=false;
                this.isrecordComplete=true;
                this.fetchVisitCompleteRecord();//this.isrecordComplete=true;
            }    
        })
        .catch((error) => {
            this.showToast('Error', 'Error in updating End Call location in Visit Task.', 'error');
            this.isLoading=false;
        });
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
    
    @track visitTaskIdTest1;
    @api callMeFromParentTest(visitTaskIdTest) {
        this.visitTaskIdTest1 = visitTaskIdTest;
        this._accountId=this.visitTaskIdTest1;
        this.loadVisitTaskDetails();
    }     
}