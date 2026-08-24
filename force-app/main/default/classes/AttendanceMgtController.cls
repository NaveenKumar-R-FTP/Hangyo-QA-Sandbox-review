/**
* Class Name  : AttendanceMgtController
* Test Class  : AttendanceMgtControllerTest
* author      : Shyam
* CreatedDate : 05-12-24
* Description : This is to create "Attendance" OR "Employee Leave Application" & its child "Leave Applications" record.
Its also updating the "Employee LeaveAllowance" record for a user whoose Leave application got "Approved" by its Manager.
* */

public with sharing class AttendanceMgtController {
    private static Boolean hasUpdated = false; // Prevent multiple updates

    //Fetch available Leave for the logged on User
    @AuraEnabled(cacheable=true)
    public static Employee_Leave_Allowance__c getLeaveBalancesForUser() {
        return [
            SELECT Available_Sick_Leave__c, Available_Earned_Leave__c, Available_Casual_Leave__c, Available_Maternity_Leave__c
            FROM Employee_Leave_Allowance__c
            WHERE User__c = :UserInfo.getUserId()
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }
    //Fetch attendance for the logged on User with Present/ Leave status
    @AuraEnabled(cacheable=true)
    public static Boolean checkAttendanceForToday() {
        return ![
            SELECT Id
            FROM Attendance__c
            WHERE date__c = :Date.today() 
            AND User__c = :UserInfo.getUserId()
            AND (Status__c = 'Present' OR Status__c = 'Leave')
            LIMIT 1
        ].isEmpty();
    }
    
    //Fetch attendance for the for the logged on User
    @AuraEnabled(cacheable=true)
    public static List<Attendance__c> attendanceList(){
        List<Attendance__c> attList = new List<Attendance__c>();
        attList = [SELECT Id,Status__c,Location__c , Automatic_Attendance_Record__c , Attendance_Applied_on__c , EOD_Date_Time__c
            FROM Attendance__c
            WHERE date__c = :Date.today() 
            AND User__c = :UserInfo.getUserId()            
            LIMIT 1];
       /*if(!attList.isEmpty()){
            return attList;
        }
        return null;*/
            return attList; // 
  }
      //Fetch Leave application for the logged on User
      @AuraEnabled(cacheable=true)
    public static List<Leave_Application__c> getLeaveApplicationRecords() {
        return [SELECT Id, Name, Start_Date__c, End_Date__c, Approval_Statuses__c FROM Leave_Application__c 
                WHERE User__c = :UserInfo.getUserId() 
                AND Approval_Status__c != 'Rejected'
                AND Start_Date__c = Today
                LIMIT 1
               ];
    }
    //Create attendance record for the logged on User
    /*@AuraEnabled
    public static String markAttendance(Attendance__c attendanceApp) {
        try {
            Attendance__c existingAttendance = getExistingAttendanceRecord();
            
            if (existingAttendance != null) {
                if (existingAttendance.Status__c == 'Absent' && existingAttendance.Automatic_Attendance_Record__c == true) {
                    // Use the status coming from UI (Present / Leave / Present Half Day)
                    System.debug('attendanceApp.Status__c:-' + attendanceApp.Status__c);
                    existingAttendance.Status__c = attendanceApp.Status__c;
                    existingAttendance.Automatic_Attendance_Record__c = false;
    
                    // Copy other fields from the UI input
                    existingAttendance.Work__c = attendanceApp.Work__c;
                    existingAttendance.Description__c = attendanceApp.Description__c;
                    existingAttendance.Date_of_attendance__c = System.Today();
                    existingAttendance.Location__Latitude__s = attendanceApp.Location__Latitude__s;
                    existingAttendance.Location__Longitude__s = attendanceApp.Location__Longitude__s;

                    update existingAttendance;
                    return existingAttendance.Id;
                }
                updateAttendanceRecord(existingAttendance, attendanceApp);
                return existingAttendance.Id;
            }

            attendanceApp.Status__c = 'Present';
            attendanceApp.Date_of_attendance__c = System.Today();
            insert attendanceApp;           
            //return 'success';
            return attendanceApp.Id;
        } catch (Exception e) {
            return 'error';
        }
    }
    //Check already exist attendance record for the logged on User
    private static Attendance__c getExistingAttendanceRecord() {
        List<Attendance__c> attendanceList = [
            SELECT Id, Status__c, Leave_Period__c, Work__c, Description__c, Date_of_attendance__c, 
            Reason_For_Leave__c, Leave_Date__c , Automatic_Attendance_Record__c
            FROM Attendance__c
            WHERE User__c = :UserInfo.getUserId()
            AND (Date_of_attendance__c = :System.Today() OR Leave_Date__c = :System.Today())
            LIMIT 1
        ];
        return attendanceList.isEmpty() ? null : attendanceList[0];
    }
    //Update exisiting attendance record for the logged on User
    private static void updateAttendanceRecord(Attendance__c existingAttendance, Attendance__c attendanceApp) {
        System.debug('Enter updateAttendanceRecord');       
        if (existingAttendance.Status__c == 'Present Half Day') {
            existingAttendance.Status__c = 'Present Half Day';
        } 
        else {
            System.debug('Enter else in updateAttendanceRecord'); 
            // Otherwise, check for 'Leave' or 'Present' status, and if 'Half Day' leave is present
            if (existingAttendance.Leave_Period__c == 'Half Day' && 
                (existingAttendance.Status__c == 'Leave' || existingAttendance.Status__c == 'Present')) {                
                existingAttendance.Status__c = 'Present Half Day';
            }
            else if (existingAttendance.Status__c == 'Leave' && existingAttendance.Leave_Period__c != 'Half Day') {
                existingAttendance.Status__c = 'Leave';
            }
            System.debug('existingAttendance.Status__c:-' + existingAttendance.Status__c); 
        }
        existingAttendance.Work__c = attendanceApp.Work__c;
        existingAttendance.Description__c = attendanceApp.Description__c;
        existingAttendance.Date_of_attendance__c = System.Today();
        existingAttendance.Location__Latitude__s = attendanceApp.Location__Latitude__s;
        existingAttendance.Location__Longitude__s = attendanceApp.Location__Longitude__s;

        if (existingAttendance.Date_of_attendance__c == null) {
            existingAttendance.Leave_Period__c = attendanceApp.Leave_Period__c;
            existingAttendance.Leave_For__c = attendanceApp.Leave_For__c;
            existingAttendance.Leave_Type__c = attendanceApp.Leave_Type__c;            
            existingAttendance.Location__Latitude__s = attendanceApp.Location__Latitude__s;
            existingAttendance.Location__Longitude__s = attendanceApp.Location__Longitude__s;

        }
        update existingAttendance;
    }*/
    @AuraEnabled
    public static String markAttendance(Attendance__c attendanceApp) {
        try {
            Attendance__c existingAttendance = getExistingAttendanceRecord();
            
            // Determine status based on current time
            String timeBasedStatus = getTimeBasedStatus();
    
            if (existingAttendance != null) {
                if (existingAttendance.Status__c == 'Absent' && existingAttendance.Automatic_Attendance_Record__c == true) {
                    existingAttendance.Status__c = timeBasedStatus;
                    existingAttendance.Automatic_Attendance_Record__c = false;
    
                    existingAttendance.Work__c = attendanceApp.Work__c;
                    existingAttendance.Description__c = attendanceApp.Description__c;
                    existingAttendance.Date_of_attendance__c = System.Today();
                    existingAttendance.Location__Latitude__s = attendanceApp.Location__Latitude__s;
                    existingAttendance.Location__Longitude__s = attendanceApp.Location__Longitude__s;
    
                    update existingAttendance;
                    return existingAttendance.Id;
                }
                updateAttendanceRecord(existingAttendance, attendanceApp, timeBasedStatus);
                return existingAttendance.Id;
            }
    
            // New attendance record
            attendanceApp.Status__c = timeBasedStatus;
            attendanceApp.Date_of_attendance__c = System.Today();
            insert attendanceApp;
            return attendanceApp.Id;
    
        } catch (Exception e) {
            return 'error: ' + e.getMessage();
        }
    }
    
    // Returns status based on the time of marking attendance
    private static String getTimeBasedStatus() {
        Datetime nowGMT = Datetime.now();
        String orgTimezone = UserInfo.getTimeZone().getID();
    
        // Let Salesforce handle timezone conversion natively
        String localTimeStr = nowGMT.format('HH:mm', orgTimezone);
        List<String> parts = localTimeStr.split(':');
    
        Integer currentHour   = Integer.valueOf(parts[0]);
        Integer currentMinute = Integer.valueOf(parts[1]);
        Integer totalMinutes  = (currentHour * 60) + currentMinute;
    
        Integer cutoffPresent  = 9  * 60 + 30; // 9:30 AM  = 570 mins
        Integer cutoffLate     = 9  * 60 + 45; // 9:45 AM  = 585 mins
        Integer cutoffHalfDay  = 12 * 60 + 30; // 12:30 PM = 750 mins
    
        if (totalMinutes < cutoffPresent) {
            return 'Present';
        } else if (totalMinutes < cutoffLate) {
            return 'Late';
        } else if (totalMinutes < cutoffHalfDay) {
            return 'Present Half Day';
        } else {
            return 'Present Half Day / Absent';
        }
    }
    
    // Check already existing attendance record for the logged-on User
    private static Attendance__c getExistingAttendanceRecord() {
        List<Attendance__c> attendanceList = [
            SELECT Id, Status__c, Leave_Period__c, Work__c, Description__c, Date_of_attendance__c,
                   Reason_For_Leave__c, Leave_Date__c, Automatic_Attendance_Record__c
            FROM Attendance__c
            WHERE User__c = :UserInfo.getUserId()
            AND (Date_of_attendance__c = :System.Today() OR Leave_Date__c = :System.Today())
            LIMIT 1
        ];
        return attendanceList.isEmpty() ? null : attendanceList[0];
    }
    
    // Update existing attendance record for the logged-on User
    private static void updateAttendanceRecord(Attendance__c existingAttendance, Attendance__c attendanceApp, String timeBasedStatus) {
        System.debug('Enter updateAttendanceRecord');
    
        if (existingAttendance.Status__c == 'Present Half Day') {
            existingAttendance.Status__c = 'Present Half Day';
        } else {
            if (existingAttendance.Leave_Period__c == 'Half Day' &&
                (existingAttendance.Status__c == 'Leave' || existingAttendance.Status__c == 'Present')) {
                existingAttendance.Status__c = 'Present Half Day';
            } else if (existingAttendance.Status__c == 'Leave' && existingAttendance.Leave_Period__c != 'Half Day') {
                existingAttendance.Status__c = 'Leave';
            } /*else {
                // Apply time-based status for all other cases
                existingAttendance.Status__c = timeBasedStatus;
            }*/
        }
    
        System.debug('existingAttendance.Status__c:- ' + existingAttendance.Status__c);
    
        existingAttendance.Work__c = attendanceApp.Work__c;
        existingAttendance.Description__c = attendanceApp.Description__c;
        existingAttendance.Date_of_attendance__c = System.Today();
        existingAttendance.Location__Latitude__s = attendanceApp.Location__Latitude__s;
        existingAttendance.Location__Longitude__s = attendanceApp.Location__Longitude__s;
    
        if (existingAttendance.Date_of_attendance__c == null) {
            existingAttendance.Leave_Period__c  = attendanceApp.Leave_Period__c;
            existingAttendance.Leave_For__c     = attendanceApp.Leave_For__c;
            existingAttendance.Leave_Type__c    = attendanceApp.Leave_Type__c;
            existingAttendance.Location__Latitude__s  = attendanceApp.Location__Latitude__s;
            existingAttendance.Location__Longitude__s = attendanceApp.Location__Longitude__s;
        }
    
        update existingAttendance;
    }
    //Leave application validations
    @AuraEnabled
    public static String addLeaveApplication(Leave_Application__c leaveApplication) {
        if (leaveApplication == null) {
            throw new AuraHandledException('Leave Application data is invalid.');
        }

        try {
            Date leaveDate = leaveApplication.Start_Date__c;
              // Fetch existing (Full Day) leave applications for  the same date (same employee)
            If(leaveApplication.Leave_Period__c == 'Full Day'){
            List<Leave_Application__c> existingLeavesForDay = [
                SELECT Id, Leave_Period__c, Leave_For__c
                FROM Leave_Application__c
                WHERE User__c = :leaveApplication.User__c
                AND Start_Date__c = :leaveDate
                AND Approval_status__c != 'Rejected'
                AND (
                     Leave_Period__c = 'Full Day'  OR Leave_Period__c = 'Half Day')
                LIMIT 1
            ];
            
            if (!existingLeavesForDay.isEmpty()) {
                throw new AuraHandledException('You already have a leave application for this day.');
            }
        }
            
            // Fetch existing (Half Day) leave applications for  the same date (same employee)
            If(leaveApplication.Leave_Period__c == 'Half Day'){
            List<Leave_Application__c> existingLeavesForDay = [
                SELECT Id, Leave_Period__c, Leave_For__c
                FROM Leave_Application__c
                WHERE User__c = :leaveApplication.User__c
                AND Start_Date__c = :leaveDate
                AND Approval_status__c != 'Rejected'
                //AND (Leave_For__c = :leaveApplication.Leave_For__c )
                AND (
                 Leave_Period__c = 'Full Day'
                 OR (
                     Leave_Period__c = 'Half Day'
                     AND Leave_For__c = :leaveApplication.Leave_For__c
                 ))
                LIMIT 1
            ];
            
            if (!existingLeavesForDay.isEmpty()) {
                throw new AuraHandledException('You already have a leave application for this day.');
            }
        }
            
            validateCasualLeaveLimit(leaveApplication);
            validateSickAndCasualLeaveCombination(leaveApplication);

            Employee_Leave_Application__c employeeLeaveApp = createEmployeeLeaveApplication(leaveApplication);
            leaveApplication.Employee_Leave_Application__c = employeeLeaveApp.Id;
            insert leaveApplication;

            updateLeaveBalances(leaveApplication);

            employeeLeaveApp.Submit_For_Approval__c = true;
            update employeeLeaveApp;
            
            //return 'success';
            return employeeLeaveApp.Id;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug('Error in addLeaveApplication: ' + e.getMessage());
            return 'error';
        }
    }
    //Leave application validations (for Casual Leave Limit)
    private static void validateCasualLeaveLimit(Leave_Application__c leaveApplication) {
        if (leaveApplication.Leave_Types__c == 'Casual Leave') {
            Date firstDayOfMonth = Date.newInstance(leaveApplication.Start_Date__c.year(), leaveApplication.Start_Date__c.month(), 1);
            Date lastDayOfMonth = firstDayOfMonth.addMonths(1).addDays(-1);

           // Query Leave Applications within the month for the current user and Leave Type 'Casual Leave'
            List<Leave_Application__c> existingLeaveApplications = [
                SELECT Number_Of_days__c, Leave_Period__c
                FROM Leave_Application__c
                WHERE User__c = :UserInfo.getUserId()
                AND Start_Date__c >= :firstDayOfMonth
                AND Start_Date__c <= :lastDayOfMonth
                AND Leave_Types__c = 'Casual Leave'
                AND Approval_statuses__c != 'Rejected'
            ];
            
            // Sum existing casual leave applications for the month
            Decimal totalExistingCasualLeaveDays = 0;
            for (Leave_Application__c leave : existingLeaveApplications) {
             
                totalExistingCasualLeaveDays += leave.Number_of_Days__c;
            }            
           
            
            // Check if the sum of new leave days exceeds the limit
            Decimal newLeaveDays = leaveApplication.Leave_Period__c == 'Full Day' ? 1 : 0.5;
            Decimal newTotalCasualLeaveDays = totalExistingCasualLeaveDays + newLeaveDays;
            
            if (newTotalCasualLeaveDays  > 2) {  
                throw new AuraHandledException('You can only take 2 Casual Leaves for a month.');
            }
    }
    }
    //Leave application validations (For Sick & Casual combinations)
    private static void validateSickAndCasualLeaveCombination(Leave_Application__c leaveApplication) {
        if (leaveApplication.Leave_Period__c == 'Half Day' && 
            (leaveApplication.Leave_Types__c == 'Sick Leave' || leaveApplication.Leave_Types__c == 'Casual Leave')) {

            List<Leave_Application__c> existingLeaves = [
                SELECT Id, Leave_Types__c
                FROM Leave_Application__c
                WHERE User__c = :UserInfo.getUserId()
                AND Start_Date__c = :leaveApplication.Start_Date__c
                AND Leave_Period__c = 'Half Day'
                AND Leave_Types__c IN ('Sick Leave', 'Casual Leave')
            ];

            for (Leave_Application__c existingLeave : existingLeaves) {
                if (existingLeave.Leave_Types__c != leaveApplication.Leave_Types__c) {
                    throw new AuraHandledException('You cannot combine sick and casual leave in one day.');
                }
            }
        }
    }
    //Create new employee leave applications
    private static Employee_Leave_Application__c createEmployeeLeaveApplication(Leave_Application__c leaveApplication) {
        Employee_Leave_Application__c employeeLeaveApp = new Employee_Leave_Application__c(
            User__c = leaveApplication.User__c,
            Leave_Type__c = leaveApplication.Leave_Types__c,
            Reason_For_Leave__c = leaveApplication.Reason_For_Leave__c,
            Approval_Status__c = 'Submit for Approval'
        );
        insert employeeLeaveApp;
        return employeeLeaveApp;
    }
    //Update the leave balance for the Users.
    private static void updateLeaveBalances(Leave_Application__c leaveApplication) {
        Employee_Leave_Allowance__c leaveAllowance = [
            SELECT Id, Used_Casual_Leave__c, Total_Casual_Leave__c, Used_Sick_Leave__c, Total_Sick_Leave__c, Used_Earned_Leave__c, Total_Earned_Leave__c
            FROM Employee_Leave_Allowance__c
            WHERE User__c = :UserInfo.getUserId()
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Decimal leaveDays = leaveApplication.Leave_Period__c == 'Full Day' ? 1 : 0.5;
        
         if (leaveApplication.Leave_Types__c == 'Casual Leave') {
            leaveAllowance.Used_Casual_Leave__c += leaveDays;
            if (leaveAllowance.Used_Casual_Leave__c > leaveAllowance.Total_Casual_Leave__c) {
                throw new AuraHandledException('You do not have enough Casual Leave balance available.');
            }
        } else if (leaveApplication.Leave_Types__c == 'Earned Leave') {
                    leaveAllowance.Used_Earned_Leave__c += leaveDays;
                    if (leaveAllowance.Total_Earned_Leave__c < leaveAllowance.Used_Earned_Leave__c) {
                        throw new AuraHandledException('You do not have enough Earned Leave balance available.');
                    }
        } else if (leaveApplication.Leave_Types__c == 'Sick Leave') {
            leaveAllowance.Used_Sick_Leave__c += leaveDays;
        }

        update leaveAllowance;
    }    
    
    //Upload File for Present    
      @AuraEnabled
    public static void uploadSelfie(Id latestAttendanceId, String base64Image) {
        try {
            if (String.isEmpty(base64Image) || latestAttendanceId == null) {
                throw new AuraHandledException('Invalid data for selfie upload.');
            }

            // Convert base64 to Blob
            Blob fileBody = EncodingUtil.base64Decode(base64Image);

            // Create ContentVersion (File)
            ContentVersion cv = new ContentVersion(
                Title = 'Attendance Selfie ' + latestAttendanceId,
                PathOnClient = 'selfie.jpg',
                VersionData = fileBody
            );
            insert cv;

            // Fetch ContentDocumentId
            Id contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;

            // Associate with Attendance record
            ContentDocumentLink cdl = new ContentDocumentLink(
                ContentDocumentId = contentDocumentId,
                LinkedEntityId = latestAttendanceId,
                ShareType = 'V'
            );
            insert cdl;
        } catch (Exception e) {
            throw new AuraHandledException('Selfie upload failed: ' + e.getMessage());
        }
    }

    //Upload file for Leave
    @AuraEnabled
    public static void uploadfile(String latestAttendanceId, String base64Image) {
        if (String.isEmpty(latestAttendanceId) || String.isEmpty(base64Image)) {
        throw new AuraHandledException('Invalid input: Employee Leave Application ID or file is missing.');
        }
        try {            
                
                // Clean the base64Image (remove the 'data:image/*;base64,' part if present)
                String base64Data = base64Image;
                if (base64Data.contains('base64,')) {
                    base64Data = base64Data.substring(base64Data.indexOf('base64,') + 7);
                }
                
                // Create the ContentVersion (file upload)
                String fileName = 'Selfie_' + DateTime.now().format('yyyyMMddHHmmss') + '.jpg';
                ContentVersion cv = new ContentVersion();
                cv.Title = fileName;
                cv.PathOnClient = fileName;
                cv.VersionData = EncodingUtil.base64Decode(base64Data); // Decode the base64 image
                insert cv;
                
                // Retrieve ContentDocumentId to associate it with the Attendance record
                ContentDocument contentDoc = [SELECT Id FROM ContentDocument WHERE Id IN (SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id) LIMIT 1];
                if (contentDoc == null) {
                    throw new AuraHandledException('Error retrieving ContentDocument for the uploaded file.');
                }
                
                // Link the content document to the Attendance record
                ContentDocumentLink cdl = new ContentDocumentLink();
                cdl.ContentDocumentId = contentDoc.Id;
                cdl.LinkedEntityId = latestAttendanceId;
                cdl.ShareType = 'V'; // View permission
                insert cdl;            
                
            
            
        }catch (Exception e) {
            // Log the exception message for better debugging
            throw new AuraHandledException('Error uploading selfie: ' + e.getMessage());
        }
    }
    
    // EOD submit: server time + EOD geolocation (separate from check-in Location__).
    @AuraEnabled
    public static void updateEODDateTime(Id attendanceRecordId, Decimal latitude, Decimal longitude) {
        if (attendanceRecordId == null) {
            throw new AuraHandledException('Attendance record Id is required.');
        }
        if (latitude == null || longitude == null) {
            throw new AuraHandledException('EOD location is required. Enable GPS and try again.');
        }
        try {
            List<Attendance__c> attList = [
                SELECT Id, EOD_Date_Time__c
                FROM Attendance__c
                WHERE Id = :attendanceRecordId
                LIMIT 1
            ];
            if (attList.isEmpty()) {
                throw new AuraHandledException('Attendance record not found or you do not have access to it.');
            }
            Attendance__c att = attList[0];
            att.EOD_Date_Time__c = Datetime.now();
            att.EOD_Location__Latitude__s = latitude;
            att.EOD_Location__Longitude__s = longitude;
            update att;
        } catch (QueryException e) {
            throw new AuraHandledException('Invalid object or field: ' + e.getMessage());
        } catch (DmlException e) {
            throw new AuraHandledException('Update failed: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

     @AuraEnabled(cacheable=false)
public static Boolean updateEOFDfield() {
    
    try {

        updateEOFDfieldAsync();
        return true;
    } catch (Exception ex) {
        return false;
    }
}

@future
public static void updateEOFDfieldAsync() {
    try {
        List<Attendance__c> attList = [SELECT Id, EOD_Date_Time__c 
                                       FROM Attendance__c 
                                       WHERE CreatedDate = TODAY 
                                       LIMIT 1];
        if (!attList.isEmpty()) {
            for (Attendance__c att : attList) {
                att.EOD_Date_Time__c = DateTime.now();
            }
            update attList; // Runs asynchronously, avoiding governor limits
        } else {
            System.debug('No records found for today');
        }
    } catch (DmlException de) {
        System.debug('DML Exception in async method: ' + de.getMessage());
    }
}
}