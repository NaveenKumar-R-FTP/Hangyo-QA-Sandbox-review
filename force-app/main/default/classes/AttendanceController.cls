public without sharing class AttendanceController {

    @AuraEnabled(cacheable=true)
    public static Boolean checkTodayAttendancePresent() {
        // Get today's date in the org's timezone
        Date today = Date.today();

        // Query Attendance__c for current user, today's date, and Status__c = 'Present'
        Integer countRecords = [
            SELECT COUNT()
            FROM Attendance__c
            WHERE User__c = :UserInfo.getUserId()
            AND Date__c = :today
            AND (Status__c = 'Present' OR Status__c = 'Present Half Day')
        ];

        // Return true if at least one matching record exists
        return countRecords > 0;
    }
}