/**
* Class Name : ApplyLeaveController
* Test Class  : ApplyLeaveControllerTest
* author      : Shyam
* CreatedDate : 05-12-24
* Description : This is to create "Employee Leave Application" & its child "Leave Applications" record.
Its also updating the "Employee LeaveAllowance" record for a user whoose Leave application got "Approved" by its Manager.
* */

public with sharing class ApplyLeaveController {
    @AuraEnabled(cacheable = true)
    public static Employee_Leave_Allowance__c getLeaveBalancesForUser() {
        return fetchLeaveAllowanceForUser(UserInfo.getUserId());
    }
    
    @AuraEnabled
    public static String saveLeaveApplication(List<Leave_Application__c> leaveApplications) {
        try {
            validateLeaveApplications(leaveApplications);
            
            Employee_Leave_Application__c employeeLeaveApp = createEmployeeLeaveApplication(leaveApplications);
            employeeLeaveApp.Approval_Status__c = 'Submit for Approval';
            insert employeeLeaveApp;
            
            associateLeaveApplicationsWithEmployeeLeaveApp(leaveApplications, employeeLeaveApp.Id);
            insert leaveApplications;
            
            employeeLeaveApp.Submit_For_Approval__c = true;
            update employeeLeaveApp;
            
            updateLeaveBalances(leaveApplications);
            
            //return 'Leave applications submitted successfully, and leave balance updated!';
            return employeeLeaveApp.Id;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void uploadSelfie(String leaveApplicationId, String base64Image) {        
         if (String.isEmpty(leaveApplicationId) || String.isEmpty(base64Image)) {
        throw new AuraHandledException('Invalid input: Employee Leave Application ID or file is missing.');
        }
        
        try {
            if (leaveApplicationId == null) {
                throw new AuraHandledException('No Leave Application record found for the provided AttendanceId.');
            }
            
            ContentVersion contentVersion = uploadContent(base64Image);
            linkContentWithAttendance(contentVersion.Id, leaveApplicationId);
        } catch (Exception e) {
            throw new AuraHandledException('Error uploading selfie: ' + e.getMessage());
        }
    }
    
    // Helper Methods
    private static Employee_Leave_Allowance__c fetchLeaveAllowanceForUser(Id userId) {
        return [
            SELECT Available_Sick_Leave__c, Available_Earned_Leave__c, Available_Casual_Leave__c, Available_Maternity_Leave__c,
            Used_Sick_Leave__c, Used_Earned_Leave__c, Used_Casual_Leave__c, Used_Maternity_Leave__c,
            Total_Sick_Leave__c, Total_Earned_Leave__c, Total_Casual_Leave__c, Total_Maternity_Leave__c
            FROM Employee_Leave_Allowance__c
            WHERE User__c = :userId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }
    
    /*private static void validateLeaveApplications(List<Leave_Application__c> leaveApplications) {
         // Check for leave applications on the same day
        for (Leave_Application__c leaveApp : leaveApplications) {
            Date leaveDate = leaveApp.Start_Date__c;
            
            // Fetch existing (Full Day) leave applications for  the same date (same employee)
            If(leaveApp.Leave_Period__c == 'Full Day'){
            List<Leave_Application__c> existingLeavesForDay = [
                SELECT Id, Leave_Period__c, Leave_For__c
                FROM Leave_Application__c
                WHERE User__c = :leaveApp.User__c
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
            If(leaveApp.Leave_Period__c == 'Half Day'){
            List<Leave_Application__c> existingLeavesForDay = [
                SELECT Id, Leave_Period__c, Leave_For__c
                FROM Leave_Application__c
                WHERE User__c = :leaveApp.User__c
                AND Start_Date__c = :leaveDate
                AND Approval_status__c != 'Rejected'
                 AND (
                 Leave_Period__c = 'Full Day'
                 OR (
                     Leave_Period__c = 'Half Day'
                     AND Leave_For__c = :leaveApp.Leave_For__c
                 ))
                LIMIT 1
            ];
            
            if (!existingLeavesForDay.isEmpty()) {
                throw new AuraHandledException('You already have a leave application for this day.');
            }
        }
            
        }
        
        
        
        Date firstDayOfMonth = leaveApplications[0].Start_date__c.toStartOfMonth();
        Date lastDayOfMonth = firstDayOfMonth.addMonths(1).addDays(-1);
        
        List<Leave_Application__c> existingLeaves = fetchExistingLeaveApplications(
            firstDayOfMonth, lastDayOfMonth, 'Casual Leave'
        );
        
        Decimal totalCasualLeaveDays = calculateTotalLeaveDays(existingLeaves);
        Decimal newCasualLeaveDays = calculateNewLeaveDays(leaveApplications, 'Casual Leave');
        
        if (totalCasualLeaveDays + newCasualLeaveDays > 2) {
            throw new AuraHandledException('You can only take 2 Casual Leaves for a month.');
        }
        
        checkForHalfDayCombinations(leaveApplications);
    }
    */
    
    private static void validateLeaveApplications(List<Leave_Application__c> leaveApplications) {
    // Step 1: Prepare sets for query filtering
    Set<Id> userIds = new Set<Id>();
    Set<Date> leaveDates = new Set<Date>();
    Set<String> halfDayKeys = new Set<String>();

    for (Leave_Application__c leaveApp : leaveApplications) {
        if (leaveApp.User__c != null && leaveApp.Start_Date__c != null) {
            userIds.add(leaveApp.User__c);
            leaveDates.add(leaveApp.Start_Date__c);
            if (leaveApp.Leave_Period__c == 'Half Day' && leaveApp.Leave_For__c != null) {
                halfDayKeys.add(leaveApp.User__c + '_' + leaveApp.Start_Date__c + '_' + leaveApp.Leave_For__c);
            }
        }
    }

    // Step 2: Query all possible existing leave records once
    List<Leave_Application__c> existingLeaves = [
        SELECT Id, Leave_Period__c, Leave_For__c, User__c, Start_Date__c, Approval_status__c
        FROM Leave_Application__c
        WHERE User__c IN :userIds
            AND Start_Date__c IN :leaveDates
            AND Approval_status__c != 'Rejected'
    ];

    // Step 3: Build maps for quick lookups
    Map<String, Leave_Application__c> fullDayMap = new Map<String, Leave_Application__c>();
    Map<String, Leave_Application__c> halfDayMap = new Map<String, Leave_Application__c>();

    for (Leave_Application__c existing : existingLeaves) {
        String key = existing.User__c + '_' + existing.Start_Date__c;
        if (existing.Leave_Period__c == 'Full Day') {
            fullDayMap.put(key, existing);
        } else if (existing.Leave_Period__c == 'Half Day' && existing.Leave_For__c != null) {
            String halfKey = key + '_' + existing.Leave_For__c;
            halfDayMap.put(halfKey, existing);
        }
    }

    // Step 4: Perform validations (same logic as before)
    for (Leave_Application__c leaveApp : leaveApplications) {
        Date leaveDate = leaveApp.Start_Date__c;
        String key = leaveApp.User__c + '_' + leaveDate;

        // Full Day conflict check
        if (leaveApp.Leave_Period__c == 'Full Day') {
            if (
                fullDayMap.containsKey(key) ||
                halfDayMap.containsKey(key + '_Morning') ||
                halfDayMap.containsKey(key + '_Afternoon')
            ) {
                throw new AuraHandledException('You already have a leave application for this day.');
            }
        }

        // Half Day conflict check
        if (leaveApp.Leave_Period__c == 'Half Day') {
            String halfKey = key + '_' + leaveApp.Leave_For__c;
            if (
                fullDayMap.containsKey(key) ||
                halfDayMap.containsKey(halfKey)
            ) {
                throw new AuraHandledException('You already have a leave application for this day.');
            }
        }
    }

    // Step 5: Casual Leave monthly limit check (same as before)
    Date firstDayOfMonth = leaveApplications[0].Start_Date__c.toStartOfMonth();
    Date lastDayOfMonth = firstDayOfMonth.addMonths(1).addDays(-1);

    List<Leave_Application__c> existingCasualLeaves = fetchExistingLeaveApplications(
        firstDayOfMonth, lastDayOfMonth, 'Casual Leave'
    );

    Decimal totalCasualLeaveDays = calculateTotalLeaveDays(existingCasualLeaves);
    Decimal newCasualLeaveDays = calculateNewLeaveDays(leaveApplications, 'Casual Leave');

    if (totalCasualLeaveDays + newCasualLeaveDays > 2) {
        throw new AuraHandledException('You can only take 2 Casual Leaves for a month.');
    }

    checkForHalfDayCombinations(leaveApplications);
}

    private static List<Leave_Application__c> fetchExistingLeaveApplications(Date startDate, Date endDate, String leaveType) {
        return [
            SELECT Number_Of_days__c
            FROM Leave_Application__c
            WHERE User__c = :UserInfo.getUserId()
            AND Start_Date__c >= :startDate
            AND Start_Date__c <= :endDate
            AND Leave_Types__c = :leaveType
            AND Approval_status__c != 'Rejected'
        ];
    }
    
    private static Decimal calculateTotalLeaveDays(List<Leave_Application__c> leaveApplications) {
        Decimal totalDays = 0;
        for (Leave_Application__c leave : leaveApplications) {
            totalDays += leave.Number_Of_Days__c;
        }
        return totalDays;
    }
    
    private static Decimal calculateNewLeaveDays(List<Leave_Application__c> leaveApplications, String leaveType) {
        Decimal totalDays = 0;
        for (Leave_Application__c leave : leaveApplications) {
            if (leave.Leave_Types__c == leaveType) {
                totalDays += (leave.Leave_Period__c == 'Full Day' ? 1 : 0.5);
            }
        }
        return totalDays;
    }
    
    private static void checkForHalfDayCombinations(List<Leave_Application__c> leaveApplications) {
        Set<Date> halfDayDates = new Set<Date>();
        for (Leave_Application__c leave : leaveApplications) {
            if (leave.Leave_Period__c == 'Half Day' && 
                (leave.Leave_Types__c == 'Sick Leave' || leave.Leave_Types__c == 'Casual Leave')) {
                    if (halfDayDates.contains(leave.Start_date__c)) {
                        throw new AuraHandledException('You cannot combine Sick and Casual Leave for Half Day.');
                    }
                    halfDayDates.add(leave.Start_date__c);
                }
        }
    }
    
    private static Employee_Leave_Application__c createEmployeeLeaveApplication(List<Leave_Application__c> leaveApplications) {
        return new Employee_Leave_Application__c(
            User__c = leaveApplications[0].User__c,
            Leave_Type__c = leaveApplications[0].Leave_Types__c,
            Reason_For_Leave__c = leaveApplications[0].Reason_For_Leave__c,
            Approval_Status__c = 'Submit for Approval'
        );
    }
    
    private static void associateLeaveApplicationsWithEmployeeLeaveApp(
        List<Leave_Application__c> leaveApplications, Id employeeLeaveAppId
    ) {
        for (Leave_Application__c leaveApp : leaveApplications) {
            leaveApp.Employee_Leave_Application__c = employeeLeaveAppId;
        }
    }
    
    private static void updateLeaveBalances(List<Leave_Application__c> leaveApplications) {
        
        Employee_Leave_Allowance__c leaveAllowance = fetchLeaveAllowanceForUser(UserInfo.getUserId());
         Integer maternityLeaveRecordCount = fetchMaternityLeaveRecordCount(UserInfo.getUserId());
        for (Leave_Application__c leaveApp : leaveApplications) {
            Decimal leaveDays = (leaveApp.Leave_Period__c == 'Full Day' ? 1 : 0.5);
            
            if (leaveApp.Leave_Types__c == 'Casual Leave') {
                leaveAllowance.Used_Casual_Leave__c += leaveDays;
                if (leaveAllowance.Used_Casual_Leave__c > leaveAllowance.Total_Casual_Leave__c) {
                    throw new AuraHandledException('You do not have enough Casual Leave balance.');
                }
            }else if (leaveApp.Leave_Types__c == 'Earned Leave') {
                leaveAllowance.Used_Earned_Leave__c += leaveDays;
                if (leaveAllowance.Total_Earned_Leave__c < leaveAllowance.Used_Earned_Leave__c) {
                    throw new AuraHandledException('You do not have enough Earned Leave balance available.');
                }
            } else if (leaveApp.Leave_Types__c == 'Sick Leave') {
                leaveAllowance.Used_Sick_Leave__c += leaveDays;
            }else if (leaveApp.Leave_Types__c == 'Maternity Leave') {
                leaveAllowance.Used_Maternity_Leave__c = + maternityLeaveRecordCount;
            }
        }
        update leaveAllowance;
    }
    
    private static Integer fetchMaternityLeaveRecordCount(Id userId) {
    return [SELECT COUNT()
            FROM Employee_Leave_Application__c
            WHERE Leave_Type__c = 'Maternity Leave' 
            AND User__c = :userId
            AND Approval_status__c != 'Rejected'
           ];
}
    
       
    private static ContentVersion uploadContent(String base64Image) {
        String cleanBase64Data = base64Image.contains('base64,') ? 
            base64Image.substring(base64Image.indexOf('base64,') + 7) : base64Image;
        
        ContentVersion cv = new ContentVersion();
        cv.Title = 'Selfie_' + DateTime.now().format('yyyyMMddHHmmss') + '.jpg';
        cv.PathOnClient = cv.Title;
        cv.VersionData = EncodingUtil.base64Decode(cleanBase64Data);
        insert cv;
        return cv;
    }
    
    private static void linkContentWithAttendance(Id contentVersionId, Id leaveApplicationId) {
        ContentDocument contentDoc = [
            SELECT Id FROM ContentDocument WHERE Id IN (
                SELECT ContentDocumentId FROM ContentVersion WHERE Id = :contentVersionId
            ) LIMIT 1
        ];
        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = contentDoc.Id;
        cdl.LinkedEntityId = leaveApplicationId;
        cdl.ShareType = 'V';
        insert cdl;
    }
}