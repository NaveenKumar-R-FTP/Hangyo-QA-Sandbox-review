import { LightningElement, track, wire } from 'lwc';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import LEAVE_APPLICATION_OBJECT from '@salesforce/schema/Leave_Application__c';
import LEAVE_TYPE_FIELD from '@salesforce/schema/Leave_Application__c.Leave_Types__c';
import LEAVE_PERIOD_FIELD from '@salesforce/schema/Leave_Application__c.Leave_Period__c';
import LEAVE_FOR_FIELD from '@salesforce/schema/Leave_Application__c.Leave_For__c';
import saveLeaveApplication from '@salesforce/apex/ApplyLeaveController.saveLeaveApplication';
import getLeaveBalancesForUser from '@salesforce/apex/ApplyLeaveController.getLeaveBalancesForUser';
import uploadSelfie from '@salesforce/apex/ApplyLeaveController.uploadSelfie';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';
import { refreshApex } from '@salesforce/apex';

export default class LeaveApplicationForm extends LightningElement {
    @track leaveBalances = {};
    @track leaveTypeOptions = [];
    @track leaveType = '';
    @track leavePeriodOptions = [];
    @track leavePeriod = '';
    @track leaveForOptions = [];
    @track leaveFor = '';
    @track startDate = '';    
    @track endDate = '';
    @track isLeaveValid = true;
    @track reason = '';
    @track showLeaveFor = false; // Track visibility of Leave For field
    @track fileName = '';
    @track leaveDates = [];
    @track isUploading = false;
    @track leaveApplicationId = '';
    @track DisabledSubmit = false;
    @track isLoading = false;
    isDataRefreshed = false;
    wiredLeaveData;

    // Connected call back with Get Leave balance methos
    connectedCallback() {
        this.getLeaveBalancesForUser();
        this.fetchLeaveBalances(); 
         //refresh
        if (navigator.userAgent.includes('SalesforceMobileSDK') && !this.isDataRefreshed) {
            this.isDataRefreshed = true; // Prevent multiple refreshes
            this.handleRefresh();
        }
    }

    // ✅ Handle Refresh for Pull-to-Refresh
    async handleRefresh() {

        try {
                await  refreshApex(this.wiredLeaveData);  

                getLeaveBalancesForUser()
                .then(result => {
                    this.wiredLeaveData = result;
                })
                .catch(error => {
            this.showToast('Error', 'Error fetching latest leave applications.', 'error');

                });

        } catch (error) {            
            this.showToast('Error', 'Error refreshing data.', 'error');
        }
    }
// Wire function to fetch employee leave allowance
@wire(getLeaveBalancesForUser)
wiredLeaveBalances(result) {
    // Store the response data in the component's wiredLeaveData property
    this.wiredLeaveData = result;
    // Check if data is returned successfully
    if (result.data) {
        this.showToast('Success', 'Leave balances fetched successfully!', 'success');
    } else if (result.error) {
        // Handle error case
        this.showToast('Error', 'Failed to fetch leave balances. Please try again later.', 'error');
    }
}

 // Method to fetch leave balances directly, used for manual call (in handleRefresh)
 fetchLeaveBalances() {
    getLeaveBalancesForUser()
        .then(balances => {
            this.wiredLeaveData = balances;
                    this.showToast('Success', 'Initial Leave balances fetched successfully!', 'success');

        })
        .catch(error => {
        
           this.showToast('Error', 'Failed to fetch leave balances. Please contact support.', 'error');
        });
}
    // This will fetch the available leave for that user
    getLeaveBalancesForUser() {
        getLeaveBalancesForUser()
            .then(balances => {
                this.leaveBalances = balances;
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'Employee Leave Allowance is not available for you, Please contact your manager.',
                        variant: 'error'
                    })
                );
                return;
            });
    }


    // Fetch Object Metadata
    @wire(getObjectInfo, { objectApiName: LEAVE_APPLICATION_OBJECT })
    objectInfo;
   

    // Fetch Leave Type Picklist Values Dynamically
    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: LEAVE_TYPE_FIELD })
    wiredLeaveTypeValues({ error, data }) {
        if (data) {
            this.leaveTypeOptions = data.values;
        } else if (error) {
                       this.showToast('Error', 'Error fetching leave type picklist values.', 'error');

        }
    }

    // Fetch Leave Period Picklist Values Dynamically
    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: LEAVE_PERIOD_FIELD })
    wiredLeavePeriodValues({ error, data }) {
        if (data) {
            this.leavePeriodOptions = data.values;
        } else if (error) {
                                   this.showToast('Error', 'Error fetching leave period picklist values.', 'error');

        }
    }

    // Fetch Leave For Picklist Values Dynamically (Visible only for Half Day Leave Period)
    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: LEAVE_FOR_FIELD })
    wiredLeaveForValues({ error, data }) {
        if (data) {
            this.leaveForOptions = data.values;
        } else if (error) {
                                               this.showToast('Error', 'Error fetching leave for picklist values.', 'error');

        }
    }

    // Handle input change event on leave application form
    handleInputChange(event) {
        const field = event.target.name;
        if (field === 'leaveType') {
            this.leaveType = event.target.value; 
            
                if (this.startDate && this.endDate) {
                    this.calculateLeaveDates();   // Calculation of dynamic list of date from start & end date
                }
                // If leave type is "Maternity Leave," disable the End Date field
                if (this.leaveType === 'Maternity Leave') {
                    this.isEndDateDisabled = true;
                    this.calculateMaternityEndDate();     // Calculation of dynamic list of date from start  date for maternity leave type
                } else {
                    this.isEndDateDisabled = false;
                }
            } else if (field === 'startDate') {
                this.startDate = event.target.value;
    
                if (this.leaveType === 'Maternity Leave') {
                    this.calculateMaternityEndDate();    // Calculation of dynamic list of date from start  date for maternity leave type
                }
                if (this.startDate && this.endDate) {
                    this.checkDateValidity();           // Check Leave Type & Leave days validity
                }
            
        } else if (field === 'reason') {
            this.reason = event.target.value;
        }  else if (field === 'endDate') {
            this.endDate = event.target.value;
            this[field] = event.target.value;

        if (this.startDate && this.endDate) {
            this.checkDateValidity();
            this.calculateLeaveDates();
            
        }
        }
       
            else if (field === 'leavePeriod') {
            this.leavePeriod = event.target.value;
    
            // Show Leave For field only if Leave Period is "Half Day"
            this.showLeaveFor = this.leavePeriod === 'Half Day';
    
            // Clear Leave For value if Leave Period is not "Half Day"
            if (!this.showLeaveFor) {
                this.leaveFor = '';
            }
        } else if (field === 'leaveFor') {
            this.leaveFor = event.target.value;
        }

    }

    // Helper method to check if the dates are valid
    checkDateValidity() {
        const start = new Date(this.startDate);
        const end = new Date(this.endDate);

        if (!this.startDate || !this.endDate) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Validation Error',
                    message: 'Please provide "End Date" & "Start Date".',
                    variant: 'error',
                })                
            );
                this.isLoading = false;
                this.clearForm();
                this.fileName = '';
                this.leaveDates = [];
                this.DisabledSubmit = false;
            return; // If either is missing, don't proceed with the validation
        }
    
        if (start > end) {
            // Optionally reset the end date to prevent invalid submission
            this.endDate = ''; 
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Validation Error',
                    message: '"End Date" must be greater than "Start Date".',
                    variant: 'error',
                })
            );
            this.isLoading = false;
                this.clearForm();
                this.fileName = '';
                this.leaveDates = [];
                this.DisabledSubmit = false;

        }        

        
    }

     // Handle individual leave details changes
     handleLeaveDetailChange(event) {
        const index = event.target.dataset.index; // Identify the date index
        const field = event.target.name;         // Field name (leavePeriod or leaveFor)
        const value = event.target.value;        // Updated value
    
        // Update the corresponding field in the leaveDates array
        const updatedLeaveDates = [...this.leaveDates]; // Create a shallow copy of the leaveDates array

        const updatedDate = { ...updatedLeaveDates[index] }; // Clone the current date entry at the specific index
    
        if (field === 'leavePeriod') {
            updatedDate.leavePeriod = value;
    
            // Show Leave For field only if Leave Period is "Half Day"
            updatedDate.showLeaveFor = value === 'Half Day';
    
            // Clear Leave For value if Leave Period is not "Half Day"
            if (!updatedDate.showLeaveFor) {
                updatedDate.leaveFor = '';
            }
        } else if (field === 'leaveFor') {
            updatedDate.leaveFor = value;
        }
        updatedLeaveDates[index] = updatedDate;

    // Set the updated array back to the leaveDates state
    this.leaveDates = updatedLeaveDates;


    }

    //Maternity Leave End date calculation on basis of start date
    calculateMaternityEndDate() {
        if (this.startDate) {
            const startDateObj = new Date(this.startDate);
            let weeksToAdd;

            if (this.leaveBalances.Used_Maternity_Leave__c < 2) {
                weeksToAdd = 26;
            } else {
                weeksToAdd = 12;
            }

            const endDateObj = new Date(startDateObj);
            endDateObj.setDate(endDateObj.getDate() + weeksToAdd * 7); // Add weeks in days
            // Format the end date to yyyy-mm-dd
            this.endDate = endDateObj.toISOString().split('T')[0];
        }
    }


    // Function to calculate dates excluding Sundays
    calculateLeaveDates() {
        const start = new Date(this.startDate);
        const end = new Date(this.endDate);  
        this.leaveDates = [];    
        const indianDateFormatter = new Intl.DateTimeFormat('en-IN', {
            day: '2-digit',
            month: 'short',
            year: 'numeric'
        });
    
        for (let date = new Date(start); date <= end; date.setDate(date.getDate() + 1)) {
            if (date.getDay() !== 0) { // Exclude Sundays (0 is Sunday)
                this.leaveDates.push({
                    rawDate: new Date(date), // Store raw Date object
                    formattedDate: indianDateFormatter.format(new Date(date)), // Format date
                    leavePeriod: 'Full Day', // Default Leave Period
                    leaveFor: '',            // Default Leave For
                    showLeaveFor: false      // Initially hide Leave For
                });
            }
        }
    }

    // File upload/ change event
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
                    const base64 = compressedDataUrl.split(',')[1];
                    this.selfieFile = base64;
               
                };
            };
            
            
            reader.readAsDataURL(file); // Read the file as a base64 data URL
        }
    }    

    // Handle submission of Employee Leave Application record
    handleSubmit() {
        this.isLoading = true;
        this.DisabledSubmit = true;
        
        // Null check for Leave Type
        if (!this.leaveType) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Validation Error',
                    message: 'Please provide "Leave Type".',
                    variant: 'error',
                })
            );
            this.isLoading = false;
                this.clearForm();
                this.fileName = '';
                this.leaveDates = [];
                this.DisabledSubmit = false;
            
        
            return; // If either is missing, don't proceed with the validation
        }


        //Null check for Leave Dates
        if (!this.startDate || !this.endDate) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Validation Error',
                    message: 'Please provide "End Date" & "Start Date".',
                    variant: 'error',
                })
            );
            this.isLoading = false;
                this.clearForm();
                this.fileName = '';
                this.leaveDates = [];
                this.DisabledSubmit = false;
     
            return; // If either is missing, don't proceed with the validation
        }
        
        if (this.startDate && this.endDate && this.leaveType === 'Maternity Leave') {
            this.calculateLeaveDates();
        }
        if (!this.isLeaveValid) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Validation Error',
                    message: 'Please resolve validation errors before submitting.',
                    variant: 'error',
                })
            );
                this.isLoading = false;
                this.clearForm();
                this.fileName = '';
                this.leaveDates = [];
                this.DisabledSubmit = false;
            return;
        }
        const leaveApplications = this.leaveDates.map(date => ({
            Leave_Types__c: this.leaveType,
            Leave_Period__c: date.leavePeriod,  
            Leave_For__c: date.leaveFor,        
            Start_Date__c: date.rawDate,       
            End_Date__c: date.rawDate,         
            Reason_For_Leave__c: this.reason,
            User__c: USER_ID
        }));

            // Call Apex method to save the records
            saveLeaveApplication({ leaveApplications })
            .then(result => {
                let leaveApplications = result;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Leave application created successfully.',
                        variant: 'success'
                    })
                );
                 if (this.selfieFile) {
                    this.uploadSelfie(result);
                       
                            setTimeout(() => {
                                window.location.reload();
                            }, 100);
                        
                }
                setTimeout(() => {
                    window.location.reload();
                }, 100); 
            })
            .catch((error) => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body.message,
                        variant: 'error'
                    })
                );
                this.isLoading = false;
                this.clearForm();
                this.fileName = '';
                this.leaveDates = [];
                this.DisabledSubmit = false;
            });
    }

    //Attach the uploaded file to the created record
    uploadSelfie(leaveApplicationId) {
    
            // Call the uploadSelfie method
            uploadSelfie({ 
                leaveApplicationId: leaveApplicationId, 
                base64Image: this.selfieFile,
            })
            .then(() => {
                // Additional success handling if needed
            })
            .catch((error) => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body ? error.body.message : 'Selfie upload failed.',
                        variant: 'error'
                    })
                );
            });
      
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }

    // Clear form after toast message
    clearForm() {
        this.leaveType = '';
        this.leavePeriod = '';
        this.leaveFor = '';
        this.startDate = '';
        this.endDate = '';
        this.reason = '';
        this.showLeaveFor = false; // Reset the Leave For field visibility
    }
}