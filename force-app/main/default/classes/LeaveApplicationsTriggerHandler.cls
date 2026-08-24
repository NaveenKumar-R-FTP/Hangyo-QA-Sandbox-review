/**
* Class Name  : LeaveApplicationsTriggerHandler
* Test Class  :LeaveApplicationTriggerTest
* author      : Shyam
* CreatedDate : 15-12-24
* Description : This is to Create & Update Attendance record for a user whoose Leave application got approved by its Manager
* */

/*public with sharing class LeaveApplicationsTriggerHandler {
   
      public static void createAttendanceForApprovedLeave(List<Leave_Application__c> leaveApplications) {
        List<Attendance__c> attendanceRecordsToInsert = new List<Attendance__c>();
        List<Attendance__c> attendanceRecordsToUpdate = new List<Attendance__c>();
        
        // Collect User__c and Leave Dates for querying existing Attendance__c records
        Set<Id> userIds = new Set<Id>();
        Set<Date> leaveDates = new Set<Date>();

        for (Leave_Application__c leaveApp : leaveApplications) {
            if (leaveApp.Approval_Status__c == 'Approved' && leaveApp.Start_Date__c != null && leaveApp.End_Date__c != null) {
                userIds.add(leaveApp.User__c);
                Date currentDate = leaveApp.Start_Date__c;
                while (currentDate <= leaveApp.End_Date__c) {
                    leaveDates.add(currentDate);
                    currentDate = currentDate.addDays(1);
                }
            }
        }

        // Query existing Attendance__c records for the given User__c and Leave Dates
        Map<String, Attendance__c> existingAttendanceMap = new Map<String, Attendance__c>();
        if (!userIds.isEmpty() && !leaveDates.isEmpty()) {
            List<Attendance__c> existingRecords = [
                SELECT Id, User__c, Leave_Date__c, Date_of_Attendance__c, Leave_Application__c,Description__c 
                FROM Attendance__c
                WHERE User__c IN :userIds
                AND (Leave_Date__c IN :leaveDates OR Date_of_Attendance__c IN :leaveDates)
            ];

            for (Attendance__c att : existingRecords) {
                // Create a unique key based on User__c and Leave_Date__c (or Date_of_Attendance__c)
                String key = att.User__c + '_' + (att.Leave_Date__c != null ? att.Leave_Date__c : att.Date_of_Attendance__c);
                existingAttendanceMap.put(key, att);
            }
        }

        // Process leave applications
        for (Leave_Application__c leaveApp : leaveApplications) {
            if (leaveApp.Approval_Status__c == 'Approved' && leaveApp.Start_Date__c != null && leaveApp.End_Date__c != null) {
                Date currentDate = leaveApp.Start_Date__c;
                while (currentDate <= leaveApp.End_Date__c) {
                    String key = leaveApp.User__c + '_' + currentDate;

                    if (existingAttendanceMap.containsKey(key)) {
                        // Update existing Attendance__c record
                        Attendance__c existingRecord = existingAttendanceMap.get(key);
                        existingRecord.Leave_Application__c = leaveApp.Id;
                        existingRecord.Leave_Date__c = leaveApp.Start_Date__c;
                        existingRecord.Reason_For_Leave__c = leaveApp.Reason_For_Leave__c;
                        existingRecord.Leave_Type__c = leaveApp.Leave_Types__c;
                        existingRecord.Leave_Period__c = leaveApp.Leave_Period__c;
                        existingRecord.Leave_For__c = leaveApp.Leave_For__c;
                        //Check the Leave Application visit period and update the Attendance Status.
                        if(leaveApp.Leave_Period__c == 'Half Day'){ 
                            existingRecord.Status__c = 'Present Half Day';
                        }else{
                            existingRecord.Status__c = 'Leave';
                        }
                        attendanceRecordsToUpdate.add(existingRecord);
                    } else {
                        // Create new Attendance__c record
                        Attendance__c attendance = new Attendance__c();
                        attendance.Status__c = 'Leave';
                        attendance.Leave_Type__c = leaveApp.Leave_Types__c;
                        attendance.Leave_Period__c = leaveApp.Leave_Period__c;
                        attendance.Leave_For__c = leaveApp.Leave_For__c;
                        attendance.Leave_Date__c = currentDate;
                        attendance.Description__c = leaveApp.Description__c;
                        attendance.Reason_For_Leave__c = leaveApp.Reason_For_Leave__c;
                        attendance.Leave_Application_Number__c = leaveApp.Name;
                        attendance.User__c = leaveApp.User__c;
                        attendance.Leave_Application__c = leaveApp.Id;
                        attendanceRecordsToInsert.add(attendance);
                    }
                    currentDate = currentDate.addDays(1);
                }
            }
        }

        // Perform DML operations
        if (!attendanceRecordsToUpdate.isEmpty()) {
            try {
                update attendanceRecordsToUpdate;
            } catch (DmlException e) {
                throw new DmlException('Error updating Attendance__c records: ' + e.getMessage());
                //System.debug('Error while updating Attendance__c records: ' + e.getMessage());
            }
        }

        if (!attendanceRecordsToInsert.isEmpty()) {
            try {
                insert attendanceRecordsToInsert;
            } catch (DmlException e) {
                throw new DmlException('Error updating Attendance__c records: ' + e.getMessage());
                //System.debug('Error while inserting Attendance__c records: ' + e.getMessage());
            }
        }
    }
   
}*/
/**
* Class Name  : LeaveApplicationsTriggerHandler
* Test Class  : LeaveApplicationTriggerTest
* author      : Shyam
* CreatedDate : 15-12-24
* Description : Handles creating and updating Attendance records for approved Leave Applications.
*/

public with sharing class LeaveApplicationsTriggerHandler {

    public static void createAttendanceForApprovedLeave(List<Leave_Application__c> leaveApplications) {
        if (leaveApplications == null || leaveApplications.isEmpty()) {
            return;
        }

        Set<Id> userIds = new Set<Id>();
        Set<Date> leaveDates = new Set<Date>();
        prepareUserIdsAndLeaveDates(leaveApplications, userIds, leaveDates);

        Map<String, Attendance__c> existingAttendanceMap = fetchExistingAttendanceRecords(userIds, leaveDates);

        // Create a processing context to encapsulate parameters
        AttendanceProcessingContext context = new AttendanceProcessingContext(existingAttendanceMap);

        processLeaveApplications(leaveApplications, context);

        performDmlOperations(context.attendanceRecordsToInsert, context.attendanceRecordsToUpdate);
    }

    private static void prepareUserIdsAndLeaveDates(List<Leave_Application__c> leaveApplications, Set<Id> userIds, Set<Date> leaveDates) {
        for (Leave_Application__c leaveApp : leaveApplications) {
            if (leaveApp.Approval_Status__c == 'Approved' && leaveApp.Start_Date__c != null && leaveApp.End_Date__c != null) {
                userIds.add(leaveApp.User__c);
                Date currentDate = leaveApp.Start_Date__c;
                while (currentDate <= leaveApp.End_Date__c) {
                    leaveDates.add(currentDate);
                    currentDate = currentDate.addDays(1);
                }
            }
        }
    }

    private static Map<String, Attendance__c> fetchExistingAttendanceRecords(Set<Id> userIds, Set<Date> leaveDates) {
        Map<String, Attendance__c> existingAttendanceMap = new Map<String, Attendance__c>();

        if (!userIds.isEmpty() && !leaveDates.isEmpty()) {
            List<Attendance__c> existingRecords = [
                SELECT Id, User__c, Leave_Date__c, Date_of_Attendance__c, Leave_Application__c, Description__c,Status__c 
                FROM Attendance__c
                WHERE User__c IN :userIds
                AND (Leave_Date__c IN :leaveDates OR Date_of_Attendance__c IN :leaveDates)
            ];

            for (Attendance__c att : existingRecords) {
                String key = att.User__c + '_' + (att.Leave_Date__c != null ? att.Leave_Date__c : att.Date_of_Attendance__c);
                existingAttendanceMap.put(key, att);
            }
        }

        return existingAttendanceMap;
    }

    private static void processLeaveApplications(List<Leave_Application__c> leaveApplications, AttendanceProcessingContext context) {
        for (Leave_Application__c leaveApp : leaveApplications) {
            if (leaveApp.Approval_Status__c == 'Approved' && leaveApp.Start_Date__c != null && leaveApp.End_Date__c != null) {
                Date currentDate = leaveApp.Start_Date__c;
                while (currentDate <= leaveApp.End_Date__c) {
                    String key = leaveApp.User__c + '_' + currentDate;

                    if (context.existingAttendanceMap.containsKey(key)) {
                        updateExistingAttendance(context.existingAttendanceMap.get(key), leaveApp, context.attendanceRecordsToUpdate);
                    } else {
                        createNewAttendance(currentDate, leaveApp, context.attendanceRecordsToInsert);
                    }

                    currentDate = currentDate.addDays(1);
                }
            }
        }
    }

    private static void updateExistingAttendance(Attendance__c existingRecord, Leave_Application__c leaveApp, List<Attendance__c> attendanceRecordsToUpdate) {
        System.debug('existingRecord:- ' + existingRecord);
        System.debug('leaveApp:- ' + leaveApp);
        System.debug('attendanceRecordsToUpdate:- ' + attendanceRecordsToUpdate);
        existingRecord.Leave_Application__c = leaveApp.Id;
        existingRecord.Leave_Date__c = leaveApp.Start_Date__c;
        existingRecord.Reason_For_Leave__c = leaveApp.Reason_For_Leave__c;
        existingRecord.Leave_Type__c = leaveApp.Leave_Types__c;
        existingRecord.Leave_Period__c = leaveApp.Leave_Period__c;
        existingRecord.Leave_For__c = leaveApp.Leave_For__c;
        if (leaveApp.Leave_Period__c == 'Half Day' && 
            (leaveApp.Leave_For__c == 'First Half' || leaveApp.Leave_For__c == 'Second Half')) {
            System.debug('Enter if statement line 204:- ');
            if (existingRecord.Status__c == 'Present Half Day') {
                System.debug('Enter if statement line 206:- ');
                existingRecord.Status__c = 'Leave'; // Second half-day makes it a full leave
            } else {
                existingRecord.Status__c = 'Present Half Day'; // First half-day being applied
            }
        
        } else {
            existingRecord.Status__c = 'Leave'; // Full Day or other types
        }
        System.debug('existingRecord.Status__c:- '+existingRecord.Status__c);
        //existingRecord.Status__c = leaveApp.Leave_Period__c == 'Half Day' ? 'Present Half Day' : 'Leave';

        attendanceRecordsToUpdate.add(existingRecord);
    }

    private static void createNewAttendance(Date currentDate, Leave_Application__c leaveApp, List<Attendance__c> attendanceRecordsToInsert) {
        Attendance__c attendance = new Attendance__c();
        //attendance.Status__c = 'Leave';
        attendance.Status__c = leaveApp.Leave_Period__c == 'Half Day' &&  leaveApp.Leave_Period__c != Null ? 'Present Half Day' : 'Leave';
        attendance.Leave_Type__c = leaveApp.Leave_Types__c;
        attendance.Leave_Period__c = leaveApp.Leave_Period__c;
        attendance.Leave_For__c = leaveApp.Leave_For__c;
        attendance.Leave_Date__c = currentDate;
        attendance.Description__c = leaveApp.Description__c;
        attendance.Reason_For_Leave__c = leaveApp.Reason_For_Leave__c;
        attendance.Leave_Application_Number__c = leaveApp.Name;
        attendance.User__c = leaveApp.User__c;
        attendance.Leave_Application__c = leaveApp.Id;

        attendanceRecordsToInsert.add(attendance);
    }

    private static void performDmlOperations(List<Attendance__c> attendanceRecordsToInsert, List<Attendance__c> attendanceRecordsToUpdate) {
        System.debug('performDmlOperations');
        if (!attendanceRecordsToUpdate.isEmpty()) {
            try {
                System.debug('Enter if statment at line 241');
                update attendanceRecordsToUpdate;
                List<Attendance__c> attendanceList = [SELECT Id , Status__c FROM Attendance__c WHERE User__c = '005H1000005YJMXIA4' ORDER BY LastModifiedById DESC LIMIT 1];
                System.debug('attendanceList:- ' +attendanceList);
            } catch (DmlException e) {
                throw new DmlException('Error updating Attendance__c records: ' + e.getMessage());
            }
        }

        if (!attendanceRecordsToInsert.isEmpty()) {
            try {
                insert attendanceRecordsToInsert;
            } catch (DmlException e) {
                throw new DmlException('Error inserting Attendance__c records: ' + e.getMessage());
            }
        }
    }

    // Helper class to encapsulate processing context
    private class AttendanceProcessingContext {
        public Map<String, Attendance__c> existingAttendanceMap;
        public List<Attendance__c> attendanceRecordsToInsert = new List<Attendance__c>();
        public List<Attendance__c> attendanceRecordsToUpdate = new List<Attendance__c>();

        public AttendanceProcessingContext(Map<String, Attendance__c> existingAttendanceMap) {
            this.existingAttendanceMap = existingAttendanceMap;
        }
    }
}