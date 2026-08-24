import { LightningElement, track, wire } from 'lwc';
import getLeaveBalancesForUser from '@salesforce/apex/AttendanceMgtController.getLeaveBalancesForUser';
import addLeaveApplication from '@salesforce/apex/AttendanceMgtController.addLeaveApplication';
import uploadfile from '@salesforce/apex/AttendanceMgtController.uploadfile';
import getLeaveBalancesForUsers from '@salesforce/apex/AttendanceValidations.getLeaveBalancesForUsers';
import USER_ID from '@salesforce/user/Id';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class AttendanceMgt extends LightningElement {
    @track leaveBalances;

    @track leaveTypeOptions = [
        { label: 'Sick Leave', value: 'Sick Leave' },
        { label: 'Earned Leave', value: 'Earned Leave' },
        { label: 'Casual Leave', value: 'Casual Leave' }
    ];
    @track leavePeriodOptions = [
        { label: 'Half Day', value: 'Half Day' },
        { label: 'Full Day', value: 'Full Day' }
    ];
    @track leaveForOptions = [
        { label: 'First Half', value: 'First Half' },
        { label: 'Second Half', value: 'Second Half' }
    ];
   
    @track selectedLeaveType = '';
    @track selectedLeavePeriod = '';
    @track selectedLeaveFor = '';
    @track reason = '';
    @track fileName = '';
    @track isUploading = false;
    @track latestAttendanceId = '';
    wiredLeaveBalances;
    startDate = '';
    endDate = '';
    @track isLeaveValid = true;

    //Show leave balance for selected Leave type for logged in User
        get filteredLeaveBalance() {
        if (this.leaveBalances && this.selectedLeaveType) {
            let balance;
            switch (this.selectedLeaveType) {
                case 'Sick Leave':
                    balance = ''; //this.leaveBalances.Available_Sick_Leave__c;
                    break;
                case 'Earned Leave':
                    balance = this.leaveBalances.Available_Earned_Leave__c;
                    break;
                case 'Casual Leave':
                    balance = this.leaveBalances.Available_Casual_Leave__c;
                    break;
                case 'Maternity Leave':
                    balance = this.leaveBalances.Available_Maternity_Leave__c;
                    break;
                default:
                    balance = 0; // Default to 0 if undefined
            }
            return balance !== undefined && balance !== null ? balance : 0;
        }
        return 0;
    }

    //Get leave balance for logged in User
    @wire(getLeaveBalancesForUser)
    wiredBalances(result) {
        this.wiredLeaveBalances = result;
        const { data, error } = result;
        if (data) {
            this.leaveBalances = data;
        } else if (error) {
                        this.showToast('Error', 'Error fetching leave balances.', 'error');

        }
    }

    //Handle Leave type slection event
    handleLeaveTypeChange(event) {
        this.selectedLeaveType = event.target.value;
        if (this.startDate && this.selectedLeaveType === 'Casual Leave') {
            this.validateLeaveApplication();
        } 
    }

    //Handle Leave Period slection event
    handleLeavePeriodChange(event) {
        this.selectedLeavePeriod = event.target.value;
        if(this.selectedLeavePeriod === 'Half Day'){
            this.showLeaveFor = true;
        }else if (this.selectedLeavePeriod === 'Full Day'){
            this.showLeaveFor = false;
        }
    }

    //Handle Leave For slection event
    handleLeaveForChange(event) {
        this.selectedLeaveFor = event.target.value;
    }

    //Handle Leave Description event
    handleDescriptionChange(event) {
        this.reason = event.target.value;
        
    }

    // Connected callback to get Todays date 
    connectedCallback() {
        /* Get todays date in 'YYYY-MM-DD' format*/
        const today = new Date();
        const formattedDate = today.toISOString().split('T')[0];
        this.startDate = formattedDate;
        this.endDate = formattedDate;
    }

    //Handle file uploads
    handleFileChange(event) {
        const file = event.target.files[0];
        
        if (file) {
            this.fileName = file.name;
            const reader = new FileReader();
            reader.onload = (e) => {
                const img = new Image();
                img.src = e.target.result;
                
                // Once the image is loaded
                img.onload = () => {
                    const canvas = document.createElement('canvas');
                    const ctx = canvas.getContext('2d');
                    const width = img.width * 0.5; // Scale down image
                    const height = img.height * 0.5;
                    canvas.width = width;
                    canvas.height = height;
                    ctx.drawImage(img, 0, 0, width, height);
                    const compressedDataUrl = canvas.toDataURL(file.type, 0.7); 
                    //this.selfieFile = compressedDataUrl.split(',')[1];
                    const base64 = compressedDataUrl.split(',')[1];
                    this.selfieFile = base64;
                    //this.selfieFile = this.fileName;                    

                    this.isUploading = false; 
                };
            };
            
            
            reader.readAsDataURL(file); // Read the file as a base64 data URL
        }
    }

    // Check existing leaves and validate the leaves 
    validateLeaveApplication() {
        const startDate = new Date(this.startDate);

        getLeaveBalancesForUsers({ 
            startDate: startDate, 
            userId: 'USER_ID' 
        })
            .then(result => {
                this.isLeaveValid = result;
                if (!this.isLeaveValid) {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Validation Error',
                            message: 'You have already tooks 2 Casual Leave for this Month.',
                            variant: 'error',
                        })
                    );
                }
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body.message,
                        variant: 'error',
                    })
                );
            });
    }
    
    // Submit to create the leave application for Todays date 
    handleSubmit() {
        // Validate inputs
        if (!this.selectedLeaveType) {
            this.showToast('Error', 'Please select a leave type.', 'error');
            return;
        }
        if (!this.selectedLeavePeriod) {
            this.showToast('Error', 'Please select a leave period.', 'error');
            return;
        }if (this.selectedLeavePeriod === 'Half Day' && !this.selectedLeaveFor) {
            this.showToast('Error', 'Please select Leave For (First Half or Second Half).', 'error');
            return;
        }


        // Prepare the leave application data
        const leaveApplication = {
            //Status__c: this.selectedStatus,
            Leave_Types__c: this.selectedLeaveType,
            Leave_Period__c: this.selectedLeavePeriod,
            Leave_For__c: this.selectedLeaveFor,
            Reason_For_Leave__c: this.reason,
            Start_Date__c: this.startDate,
            End_Date__c: this.endDate,
            User__c: USER_ID
        };

        if (this.startDate && this.leaveType === 'Casual Leave') {
            this.validateLeaveApplication();
        } 

        // Call Apex to save the Leave Application
        addLeaveApplication({ leaveApplication })
            .then((result) => {
                this.showToast('Success', 'Leave application submitted successfully!', 'success');
                if (this.selfieFile) {
                    this.uploadfile(result);
                       
                            setTimeout(() => {
                                window.location.reload();
                            }, 100);
                        
                }
                setTimeout(() => {
                    window.location.reload();
                }, 100); 
                return refreshApex(this.wiredLeaveBalances);
            })
            .catch((error) => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body.message,
                        variant: 'error'
                    })
                );
            });
    }

    //Attached the uploaded file to the latest created Employee leave application record
    uploadfile(latestAttendanceId) {
    
        // Call the uploadfile method
        uploadfile({ 
            latestAttendanceId: latestAttendanceId, 
            base64Image: this.selfieFile,
        })
        .then(() => {
            // Additional success handling if needed
        })
        .catch((error) => {
            console.error('Error in uploadfile:', error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error.body ? error.body.message : 'File upload failed.',
                    variant: 'error'
                })
            );
        });
  
}

//Clear form
    clearForm() {
        this.selectedLeaveType = '';
        this.selectedLeavePeriod = '';
        this.selectedLeaveFor = '';
        this.reason = '';
    }

    //Sho Toast event
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}