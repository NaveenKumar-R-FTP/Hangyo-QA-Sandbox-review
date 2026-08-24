import { LightningElement, track, wire } from 'lwc';
import getLeaveApplicationRecords from '@salesforce/apex/AttendanceMgtController.getLeaveApplicationRecords';
import getLeaveBalancesForUser from '@salesforce/apex/AttendanceMgtController.getLeaveBalancesForUser';
import getAttendance from '@salesforce/apex/AttendanceMgtController.attendanceList';
// Added by hari - use AttendanceMgtController.updateEODDateTime for EOD_Date_Time__c; EODController for logged-in user EOD details
import updateEODDateTime from '@salesforce/apex/AttendanceMgtController.updateEODDateTime';
// Added by hari - uses same Dheeraj-testing logic: null = current user, or pass targetUserId for that user's EOD
import getDailyPerformanceForUserEOD from '@salesforce/apex/EODController.getDailyPerformanceForUserEOD';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class AttendanceMaster extends LightningElement {

    @track isPresentView = false; 
    @track isLeaveView = false; 
    @track isPresentMarked = false; 
    @track isAbsentMarked = false;
    @track currentDate;     
    @track leaveApplications;   
    @track attendanceMessage = ''; 
    leaveRecords = [];
    wiredLeaveData;
    wiredLeaveStatus;
    wiredAttendanceResult;
    isDataRefreshed = false;
    // Added by hari - EOD modal state; form data auto-populated from EODController for logged-in user
    @track isEODModalOpen = false;
    @track currentAttendanceId = null;
    @track isEODSubmitLoading = false;
    @track isEODLoading = false;
    @track isEODSubmitted = false;
    @track eodFormData = {
        scheduledCalls: '', totalCalls: '', productiveCalls: '', notVisitedOutlet: '',
        newOutletOnboarded: '', dfTransfer: '', distributorVisit: '', firstCheckInTime: '',
        lastCheckOutTime: '', totalTimeSpent: '', totalOrderValue: ''
    };

    // Added by hari - after EOD submit: show this message instead of Present message; Leave button hidden when true
    get displayMessage() {
        return this.isEODSubmitted && !this.isAbsentMarked ? 'EOD has been submitted for today. Your attendance and end-of-day summary are recorded.' : this.attendanceMessage;
    }
    get showLeaveButton() {
        return !this.isAbsentMarked && !this.isEODSubmitted;
    }
    get showEODButton() {
        return this.isPresentMarked && !this.isEODSubmitted;
    }

     // Connected callback for getting today's date & refreshing data in mobile
     connectedCallback() {
        const today = new Date();
        this.currentDate = this.formatDate(today);

        if (navigator.userAgent.includes('SalesforceMobileSDK') && !this.isDataRefreshed) {
            this.isDataRefreshed = true; // Prevent multiple refreshes
            this.handleRefresh();
        }
    }

    // Handle Refresh for Pull-to-Refresh
    async handleRefresh() {

        try {
            await Promise.all([
                refreshApex(this.wiredLeaveData),
                refreshApex(this.wiredAttendanceResult)
            ]);

            // Explicitly re-fetch data to ensure LWC updates
            getAttendance()
                .then(data => {
                    this.isEODSubmitted = false;
                    if (data.length > 0) {
                        let attendanceRecord = data[0];
                        // Added by hari - keep current attendance Id for EOD after refresh
                        this.currentAttendanceId = attendanceRecord.Id;
                        console.log('attendanceRecord.Attendance_Applied_on__c:-',attendanceRecord.Attendance_Applied_on__c);
                        const appliedTime = this.formatTime(attendanceRecord.Attendance_Applied_on__c);
                        console.log('appliedTime:-',appliedTime);
                        if(attendanceRecord.Status__c == 'Leave'){ // Both button disabled
                            this.isPresentMarked = true;
                            this.isEODSubmitted = true;
                            this.isAbsentMarked = true;
                            this.attendanceMessage = `Your attendance is marked as Leave for today (applied at ${appliedTime}).`;
                        }else if(attendanceRecord.Status__c == 'Absent'){ // Absent disabled and Leave show
                            this.isPresentMarked = false;
                            this.isAbsentMarked = false; 
                        }else if(attendanceRecord.Status__c == 'Present'){ // Present disabled and Leave show
                            this.isPresentMarked = true;
                            this.isAbsentMarked = false;
                            this.attendanceMessage = `Your attendance is marked as Present for today (applied at ${appliedTime}).`;
                            console.log('attendanceRecord.EOD_Date_Time__c line 94:- ' , attendanceRecord.EOD_Date_Time__c);
                            if (attendanceRecord.EOD_Date_Time__c) this.isEODSubmitted = true;                            
                        }else if(attendanceRecord.Status__c == 'Late'){ // Late disabled and Leave show
                            this.isPresentMarked = true;
                            this.isAbsentMarked = false;
                            this.attendanceMessage = `Your attendance is marked as Late for today (applied at ${appliedTime}).`;
                            console.log('attendanceRecord.EOD_Date_Time__c line 94:- ' , attendanceRecord.EOD_Date_Time__c);
                            if (attendanceRecord.EOD_Date_Time__c) this.isEODSubmitted = true;                            
                        }else if(attendanceRecord.Status__c == 'Present Half Day / Absent'){ // Hide Present button; show EOD and Leave buttons
                            this.isPresentMarked = true;
                            this.isAbsentMarked = false;
                            this.attendanceMessage = `Your attendance is marked as Present (Half Day/ Absent) for today (applied at ${appliedTime}).`;
                            
                        }else if(attendanceRecord.Status__c == 'Present Half Day' && attendanceRecord.Location__c !=null){ // Present disabled and Leave show
                            this.isPresentMarked = true;
                            this.isAbsentMarked = false;
                            this.attendanceMessage = `Your attendance is marked as Present (Half Day) for today (applied at ${appliedTime}).`;
                            console.log('attendanceRecord.EOD_Date_Time__c line 100:- ' , attendanceRecord.EOD_Date_Time__c);
                            if (attendanceRecord.EOD_Date_Time__c) this.isEODSubmitted = true;
                        }
                    } 
                      else{
                          this.showToast('Info', 'No attendance record found for today.', 'info');
                    }    
                })
                .catch(error => {
                                this.showToast('Error', 'Error fetching latest attendance.', 'error');

                });

            getLeaveApplicationRecords()
                .then(data => {
                    this.leaveApplications = data;
                })
                .catch(error => {
                                                    this.showToast('Error', 'Error fetching latest leave applications.', 'error');

                });

            /*this.showToast('Success', 'Data refreshed successfully!', 'success');*/
        } catch (error) {
            this.showToast('Error', 'Error refreshing data.', 'error');
        }
    }
    

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    //Proper date format to show on UI
    formatDate(date) {
        const options = { day: '2-digit', month: 'short', year: 'numeric' };
        return new Intl.DateTimeFormat('en-GB', options).format(date); // Use en-GB to get date format like "16 Dec 2024"
    }


      // Get Employee Leave Applications
      @wire(getLeaveApplicationRecords)
      wiredLeaveApplications(result) {
          this.wiredLeaveData = result;
          if (result.data) {
              this.leaveApplications = result.data;
          } else if (result.error) {
                        this.showToast('Error', 'Error fetching leave applications.', 'error');

          }
      }
  
      // Get Attendance Status
      @wire(getAttendance)
      wiredAttendance(result) {
          this.wiredAttendanceResult = result;
          if (result.data) {
              if (result.data.length > 0) {
                this.isEODSubmitted = false;
                let attendanceRecord = result.data[0];
                // Added by hari - store current attendance Id for EOD submit
                this.currentAttendanceId = attendanceRecord.Id;
                console.log('attendanceRecord.Attendance_Applied_on__c:-',attendanceRecord.Attendance_Applied_on__c);
                const appliedTime = this.formatTime(attendanceRecord.Attendance_Applied_on__c);
                console.log('appliedTime:-',appliedTime);
                if(attendanceRecord.Status__c == 'Leave'){ // Both button disabled
                    this.isPresentMarked = true;
                    this.isEODSubmitted = true;
                    this.isAbsentMarked = true;
                    //this.attendanceMessage = 'Your attendance is already marked as Leave for today (applied at ${appliedTime}).';
                    this.attendanceMessage = `Your attendance is marked as Leave for today (applied at ${appliedTime}).`;
                }else if(attendanceRecord.Status__c == 'Absent'){ // Absent disabled and Leave show
                    this.isPresentMarked = false;
                    this.isAbsentMarked = false; 
                }else if(attendanceRecord.Status__c == 'Present'){ // Present disabled and Leave show
                    this.isPresentMarked = true;
                    this.isAbsentMarked = false;
                    this.attendanceMessage = `Your attendance is marked as Present for today (applied at ${appliedTime}).`;
                    if (attendanceRecord.EOD_Date_Time__c){
                        this.isEODSubmitted = true;
                    }
                }else if(attendanceRecord.Status__c == 'Late'){ // Present disabled and Leave show
                    this.isPresentMarked = true;
                    this.isAbsentMarked = false;
                    this.attendanceMessage = `Your attendance is marked as Late for today (applied at ${appliedTime}).`;
                    if (attendanceRecord.EOD_Date_Time__c){
                        this.isEODSubmitted = true;
                    }
                }else if(attendanceRecord.Status__c == 'Present Half Day / Absent'){ // Hide Present button; show EOD and Leave buttons
                    this.isPresentMarked = true;
                    this.isAbsentMarked = false;
                    this.attendanceMessage = `Your attendance is marked as Present (Half Day/ Absent) for today (applied at ${appliedTime}).`;

                }else if(attendanceRecord.Status__c == 'Present Half Day' && attendanceRecord.Location__c !=null){ // Present disabled and Leave show
                    this.isPresentMarked = true;
                    this.isAbsentMarked = false;
                    this.attendanceMessage = `Your attendance is marked as Present (Half Day) for today (applied at ${appliedTime}).`;
                    console.log('attendanceRecord.EOD_Date_Time__c line 182:- ' , attendanceRecord.EOD_Date_Time__c);
                    if (attendanceRecord.EOD_Date_Time__c) this.isEODSubmitted = true;
                }
              } else {
                  this.isPresentMarked = false;
                  this.isAbsentMarked = false;
              }
          } else if (result.error) {
                        this.showToast('Error', 'Error retrieving attendance.', 'error');

          }
      }

  

    // Handle Present button click
    handlePresentClick() {
        this.isPresentView = true;
        this.isLeaveView = false;
    }

    // Added by hari - Open EOD modal and auto-populate 11 metrics from EODController for current logged-in user
    handleEODClick() {
        this.isEODModalOpen = true;
        this.eodFormData = {
            scheduledCalls: '', totalCalls: '', productiveCalls: '', notVisitedOutlet: '',
            newOutletOnboarded: '', dfTransfer: '', distributorVisit: '', firstCheckInTime: '',
            lastCheckOutTime: '', totalTimeSpent: '', totalOrderValue: ''
        };
        this.isEODLoading = true;
        getDailyPerformanceForUserEOD({ targetUserId: null })
            .then((data) => {
                this.eodFormData = {
                    scheduledCalls: data.scheduledCalls != null ? String(data.scheduledCalls) : '',
                    totalCalls: data.totalCalls != null ? String(data.totalCalls) : '',
                    productiveCalls: data.productiveCalls != null ? String(data.productiveCalls) : '',
                    notVisitedOutlet: data.notVisitedOutlet != null ? String(data.notVisitedOutlet) : '',
                    newOutletOnboarded: data.newOutletOnboarded != null ? String(data.newOutletOnboarded) : '',
                    dfTransfer: data.dfTransfer != null ? String(data.dfTransfer) : '',
                    distributorVisit: data.distributorVisit != null ? String(data.distributorVisit) : '',
                    firstCheckInTime: this._timeStringToHHmm(data.firstCheckInTime),
                    lastCheckOutTime: this._timeStringToHHmm(data.lastCheckOutTime),
                    totalTimeSpent: data.totalTimeSpent || '',
                    totalOrderValue: data.totalOrderValue != null ? String(data.totalOrderValue) : ''
                };
                this.isEODLoading = false;
                if (data.message) {
                    this.showToast('Warning', data.message, 'warning');
                }
            })
            .catch((error) => {
                this.isEODLoading = false;
                const errMsg = (error && error.body && error.body.message) ? error.body.message : (error && error.message) ? error.message : 'Error loading EOD details.';
                this.showToast('Error', errMsg, 'error');
            });
    }

    // Added by hari - Convert EODController time string (e.g. "9:00 AM") to HH:mm for lightning-input type="time"
    _timeStringToHHmm(str) {
        if (!str || typeof str !== 'string') return '';
        const s = str.trim();
        if (!s) return '';
        const match = s.match(/^(\d{1,2}):(\d{2})\s*(AM|PM)$/i);
        if (!match) return s;
        let h = parseInt(match[1], 10);
        const m = match[2];
        if (match[3].toUpperCase() === 'PM' && h !== 12) h += 12;
        if (match[3].toUpperCase() === 'AM' && h === 12) h = 0;
        return (h < 10 ? '0' : '') + h + ':' + m;
    }

    // Added by hari - Close EOD modal on Cancel
    handleEODModalCancel() {
        this.isEODModalOpen = false;
    }

    // Added by hari - Capture user input for each EOD metric field (supports lightning-input and lightning-textarea)
    handleEODFieldChange(event) {
        const field = event.target.dataset.metric;
        if (field) {
            const value = event.detail !== undefined && event.detail.value !== undefined ? event.detail.value : event.target.value;
            this.eodFormData = { ...this.eodFormData, [field]: value };
        }
    }

    /**
     * EOD-only: read device GPS when user submits End of Day (not used for Present/Leave).
     * @returns {Promise<{ latitude: number, longitude: number }>}
     */
    _fetchEodGpsLocation() {
        return new Promise((resolve, reject) => {
            if (!navigator.geolocation) {
                reject(new Error('Geolocation is not supported on this device.'));
                return;
            }
            navigator.geolocation.getCurrentPosition(
                (position) => {
                    const latitude = position?.coords?.latitude;
                    const longitude = position?.coords?.longitude;
                    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
                        reject(new Error('Could not read GPS coordinates.'));
                        return;
                    }
                    resolve({ latitude, longitude });
                },
                (geoError) => {
                    const message =
                        geoError?.message ||
                        'Location permission denied or unavailable. Enable location to submit EOD.';
                    reject(new Error(message));
                },
                { enableHighAccuracy: true, timeout: 20000, maximumAge: 0 }
            );
        });
    }

    // Submit EOD: fetch GPS, then save EOD_Date_Time__c + EOD_Location__c on Attendance__c.
    async handleEODModalSubmit() {
        if (!this.currentAttendanceId) {
            this.showToast('Error', 'No attendance record found for today.', 'error');
            return;
        }
        this.isEODSubmitLoading = true;
        try {
            const { latitude, longitude } = await this._fetchEodGpsLocation();
            await updateEODDateTime({
                attendanceRecordId: this.currentAttendanceId,
                latitude,
                longitude
            });
            this.showToast(
                'Success',
                'EOD has been submitted for today. EOD date-time and location have been captured.',
                'success'
            );
            this.isEODModalOpen = false;
            this.isEODSubmitted = true;
            refreshApex(this.wiredAttendanceResult);
        } catch (error) {
            const errMsg =
                error && error.body && error.body.message
                    ? error.body.message
                    : error && error.message
                      ? error.message
                      : 'Error submitting EOD.';
            this.showToast('Error', errMsg, 'error');
        } finally {
            this.isEODSubmitLoading = false;
        }
    }

    // Handle Leave button click
    handleLeaveClick() {
        this.isPresentView = false; 
        this.isLeaveView = true; 

        //Check if Employee Leave Allowance is available Or not for logged in User
        getLeaveBalancesForUser()
        .then(result => {
            if (!result || 
                (!result.Available_Sick_Leave__c &&
                !result.Available_Earned_Leave__c &&
                !result.Available_Casual_Leave__c &&
                !result.Available_Maternity_Leave__c)) {
                
                this.showToast('Error', 'No leave balance available!', 'error');
            } else {
                this.isPresentView = false;
                this.isLeaveView = true;
            }
        })
        .catch(error => {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Employee Leave Allowance is not available for you, Please contact your manager.',
                    variant: 'error'
                })
            );
            setTimeout(() => {
                window.location.reload();
            }, 10);
           
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

        formatTime(dateTimeString) {
            console.log('dateTimeString:- ' , dateTimeString);
            if (!dateTimeString) {
                return '';
            }
            const dt = new Date(dateTimeString);

            return dt.toLocaleTimeString('en-IN', {
                hour: '2-digit',
                minute: '2-digit',
                hour12: true
            });
        }   
}