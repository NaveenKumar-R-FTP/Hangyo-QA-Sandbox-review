import { LightningElement, track, wire } from 'lwc';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import ATTENDANCE_OBJECT from '@salesforce/schema/Attendance__c';
import STATUS_FIELD from '@salesforce/schema/Attendance__c.Status__c';
import WORK_FIELD from '@salesforce/schema/Attendance__c.Work__c';
import markAttendance from '@salesforce/apex/AttendanceMgtController.markAttendance';
import uploadSelfie from '@salesforce/apex/AttendanceMgtController.uploadSelfie';
import getAllowedWorkTypesForCurrentUser from '@salesforce/apex/RoleWorkTypeController.getAllowedWorkTypesForCurrentUser';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';
 
export default class Attendance extends LightningElement {

    //Added for selfie
    @track isCameraOn = false;
    photoURL = null;
    videoStream = null;
    //End of Selfie

    @track StatusOptions = [];
    @track status = 'Present';
    @track WorkTypeOptions = [];
    @track workType = '';
    @track leaveDate = '';
    @track dateofattendance = '';
    @track selfieFile;
    @track fileName = '';
    @track progressValue = 0;
    @track isUploading = false;
    @track latestAttendanceId = '';
    @track latitude = '';
    @track longitude = '';
    @track isSubmitDisabled = false;
    locationChecked = false;
    @track isLoading = false;
 
    // Fetch Object Metadata
    @wire(getObjectInfo, { objectApiName: ATTENDANCE_OBJECT })
    objectInfo;
 
    // Fetch Status Picklist Values
    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: STATUS_FIELD })
    wiredStatusValues({ error, data }) {
        if (data) {
            this.StatusOptions = data.values;
        } else if (error) {
                        this.showToast('Error', 'Error fetching status picklist values.', 'error');

        }
    }
 
    // Fetch Work Type Picklist Values
    /*@wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: WORK_FIELD })
    wiredWorkTypeValues({ error, data }) {
        if (data) {
            this.WorkTypeOptions = data.values;
        } else if (error) {
                                    this.showToast('Error', 'Error fetching work type picklist values.', 'error');

        }
    }*/

    @wire(getAllowedWorkTypesForCurrentUser)
    wiredAllowedTypes({ error, data }) {
        if (data) {
            // Transform List<String> → [{label, value}] format for lightning-combobox
            this.WorkTypeOptions = data.map(item => ({
                label: item.trim(),
                value: item.trim()
            }));
            console.log('this.WorkTypeOptions:- ', JSON.stringify(this.WorkTypeOptions));
        } else if (error) {
            this.showToast('Error', 'Error fetching allowed work types.', 'error');
        }
    }
    
    
    //Start Camera on click of Upload Selfie
    async startCamera() {
        this.isCameraOn = true; // Show camera UI
        this.photoURL = null;
        this.selfieFile = null;
        try {
            this.videoStream = await navigator.mediaDevices.getUserMedia({
                video: { facingMode: "user" } // Force front camera
            });
            this.template.querySelector('.video-feed').srcObject = this.videoStream;
        } catch (error) {
                                                this.showToast('Error', 'Camera access denied.', 'error');

            this.isCameraOn = false;
        }
    }

    //Capture Photo 
    capturePhoto() {
        const video = this.template.querySelector('.video-feed');
        const canvas = this.template.querySelector('.hidden-canvas');
        const context = canvas.getContext('2d');

        canvas.width = video.videoWidth;
        canvas.height = video.videoHeight;
        context.drawImage(video, 0, 0, canvas.width, canvas.height);

        this.photoURL = canvas.toDataURL('image/png'); // Save captured image
        
        // Scale down image (50% size)
        const width = video.videoWidth * 0.5; 
        const height = video.videoHeight * 0.5;
        canvas.width = width;
        canvas.height = height;
    
        // Draw scaled-down image on canvas
        context.drawImage(video, 0, 0, width, height);
    
        // Compress image (reduce quality to 0.7)
        canvas.toBlob((blob) => {
            const reader = new FileReader();
            reader.readAsDataURL(blob);
            reader.onloadend = () => {
                this.selfieFile = reader.result.split(',')[1]; // Extract base64 data
                
                this.stopCamera();
            };
        }, 'image/jpeg', 0.7); // Set image type & quality (0.7 = 70% quality)
        this.stopCamera(); // Turn off camera after capture
    }

    //Stop Once Photo is Clicked
    stopCamera() {
        if (this.videoStream) {
            this.videoStream.getTracks().forEach(track => track.stop()); // Stop camera
        }
        this.isCameraOn = false; // Hide camera UI
    }

    //Handle input change event
    handleInputChange(event) {
        const field = event.target.name;
        if (field === 'status') {
            this.status = event.target.value;
        } else if (field === 'dateofattendance') {
            this.dateofattendance = event.target.value;
        } else if (field === 'workType') {
            this.workType = event.target.value;
        }
    }
         
    
    handleSubmit() {
        this.isLoading = true;
        this.isSubmitDisabled = true;
    
        // Validation for work type and selfie
        if (!this.workType || !this.selfieFile) {
            this.isLoading = false;
        this.isSubmitDisabled = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Please fill the work type and upload your selfie.',
                    variant: 'error'
                })
            );
            
            return;          
        }
    
        // Get location first before inserting the attendance record
        this.getLocation();              
    }
    
    // Get current location and save attendance
    async getLocation() {
        try {
            await new Promise((resolve) => setTimeout(resolve, 1000)); // Simulating a delay
            await this.getCurrentLocationDataForCheckIn();
            this.saveAttendanceRecord();
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Location Error',
                    message: error.message || 'There was a problem verifying your location.',
                    variant: 'error'
                })
            );
        }
    }
    
    // Save attendance record and upload selfie
    async saveAttendanceRecord() {
        this.isLoading = true; 
        const attendanceApp = {
            Status__c: this.status,
            Work__c: this.workType,
            Date_of_attendance__c: this.dateofattendance,
            Leave_Date__c: this.leaveDate, // Optional if leave date is empty
            User__c: USER_ID,
            Location__Latitude__s: this.latitude, // Include location
            Location__Longitude__s: this.longitude
        };
    
        // Call Apex method to save the attendance record
        markAttendance({ attendanceApp })
            .then((result) => {
                this.latestAttendanceId = result; // Capture the new attendance record ID
    
                // If selfie is uploaded, trigger upload
                if (this.selfieFile) {
                    this.uploadSelfie(this.latestAttendanceId);
                }
                this.isLoading = false; 
                this.isSubmitDisabled = false;
    
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Attendance marked successfully!',
                        variant: 'success'
                    })
                );
                this.isSubmitDisabled = false;
                setTimeout(() => {
                    window.location.reload();
                }, 100); 
    
            })
            .catch((error) => {
                this.isLoading = false; 
                this.isSubmitDisabled = false;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'There was an issue saving your attendance.',
                        variant: 'error'
                    })
                );
                this.isSubmitDisabled = false;
            });
    }              
                
                async getCurrentLocationDataForCheckIn(){
                    return new Promise((resolve, reject) => {
                        if (navigator.geolocation) {
                            navigator.geolocation.getCurrentPosition(
                                (position) => {
                                    this.latitude = position.coords.latitude;
                                    this.longitude = position.coords.longitude;
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
                                            errorMessage = 'Turn on the location Manually if it’s not already enabled and try again.';
                                            break;
                                        case error.UNKNOWN_ERROR:
                                        default:
                                            errorMessage = 'An unknown error occurred while retrieving location.';
                                            break;
                                    }
                    this.showToast('Error', errorMessage, 'error');

                                    setTimeout(() => {
                                        window.location.reload();
                                    }, 100);
                                    reject(new Error(errorMessage));
                                },
                                { enableHighAccuracy: true, timeout: 10000} // Ensure timeout is handled

                            );
                        } else {
                            setTimeout(() => {
                                window.location.reload();
                            }, 100);
                            reject(new Error('Geolocation is not supported by this browser.'));
                        }
                    });
                }
            
            uploadSelfie(latestAttendanceId) {
                uploadSelfie({
                    latestAttendanceId: latestAttendanceId,
                    base64Image: this.selfieFile
                })
                .then(() => {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Success',
                            message: 'Selfie uploaded successfully!',
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
                      

           
           
    // Clear form
    clearForm() {
        this.status = 'Present';
        this.workType = '';
        this.dateofattendance = '';
        this.selfieFile = null;
        this.template.querySelector('input[type="file"]').value = '';
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

}