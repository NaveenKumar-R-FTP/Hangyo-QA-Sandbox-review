/**
* Class Name  : AttendanceValidations
* Test Class  : AttendanceValidationsTest
* author      : Shyam
* CreatedDate : 15-01-24
* Description : This is to add validation while creating "Attendance" record.
                
* */
public with sharing class AttendanceValidations {
    
 @AuraEnabled(cacheable=true)
    public static Boolean getLeaveBalancesForUsers(Date startDate, String userId) {
        if (startDate == null || String.isBlank(userId)) {
            throw new AuraHandledException('Start Date and User ID are required.');
        }

        // Calculate the first and last day of the month for the given start date
        Date firstDayOfMonth = Date.newInstance(startDate.year(), startDate.month(), 1);
        Date lastDayOfMonth = firstDayOfMonth.addMonths(1).addDays(-1);

        //System.debug('firstDayOfMonth=' + firstDayOfMonth);
        //System.debug('lastDayOfMonth=' + lastDayOfMonth);

        // Query Leave_Application__c records within the month for the user
        List<Leave_Application__c> leaveApplications = [
            SELECT Number_Of_Days__c
            FROM Leave_Application__c
            WHERE User__c = :userId
            AND Start_Date__c >= :firstDayOfMonth
            AND Start_Date__c <= :lastDayOfMonth
            AND Leave_Types__c = 'Casual Leave'
            AND Approval_statuses__c != 'Rejected'
        ];

        // Calculate the total Number_Of_Days__c for the month
        Decimal totalDays = 0;
        for (Leave_Application__c leave : leaveApplications) {
            totalDays += leave.Number_Of_Days__c;
        }

        // Check if the total days exceed the limit
        if (totalDays + 0.5 > 2) {
            return false; // Validation failed
        }
        return true; // Validation passed
    }
}