/**
* Test Class  : AttendanceMgtControllerTest
* author      : Shyam
* CreatedDate : 22-01-25
* Description : This is test class for "AttendanceValidations".
* */
@isTest
public class AttendanceValidationsTest {

    @isTest
    static void testGetLeaveBalancesForUsersValidLeaveBalance() {
        // Setup test data for leave applications within the same month
        User testUser = [SELECT Id FROM User WHERE Username = :UserInfo.getUserName() LIMIT 1];
        Employee_Leave_Application__c leaveMaster = new Employee_Leave_Application__c(
            User__c = testUser.Id
            );
        insert leaveMaster;

        // Creating Leave Application records for the user
        Leave_Application__c leave1 = new Leave_Application__c(
            User__c = testUser.Id,
            Employee_Leave_Application__c = leaveMaster.Id,
            Leave_Types__c = 'Casual Leave',
            Start_Date__c = Date.today()
        );
        insert leave1;

        Leave_Application__c leave2 = new Leave_Application__c(
            User__c = testUser.Id,
            Leave_Types__c = 'Casual Leave',
            Employee_Leave_Application__c = leaveMaster.Id,
            Start_Date__c = Date.today().addDays(2)
        );
        insert leave2;

        Test.startTest();
        Boolean result = AttendanceValidations.getLeaveBalancesForUsers(Date.today(), testUser.Id);
        Test.stopTest();

        // Assert that the result is true since the total leave balance does not exceed the limit
        System.assert(result, 'The leave balance should be valid');
    }

    @isTest
    static void testGetLeaveBalancesForUsersExceedsLeaveLimit() {
        // Setup test data for leave applications within the same month
        User testUser = [SELECT Id FROM User WHERE Username = :UserInfo.getUserName() LIMIT 1];
        Employee_Leave_Application__c leaveMaster = new Employee_Leave_Application__c(
            User__c = testUser.Id
            );
        insert leaveMaster;
        // Creating Leave Application records for the user
        Leave_Application__c leave1 = new Leave_Application__c(
            User__c = testUser.Id,
            Employee_Leave_Application__c = leaveMaster.Id,
            Leave_Types__c = 'Casual Leave',
            Start_Date__c = Date.today()
        );
        insert leave1;

        Test.startTest();
        Boolean result = AttendanceValidations.getLeaveBalancesForUsers(Date.today(), testUser.Id);
        Test.stopTest();

        System.assert(result, 'The leave balance should be valid');

    }

    @isTest
    static void testGetLeaveBalancesForUsersInvalidStartDate() {
        // Simulate the case where the start date is invalid (null)
        User testUser = [SELECT Id FROM User WHERE Username = :UserInfo.getUserName() LIMIT 1];
        
        try {
            Test.startTest();
            AttendanceValidations.getLeaveBalancesForUsers(null, testUser.Id);
            Test.stopTest();
            System.assert(false, 'An exception should have been thrown due to invalid startDate');
        } catch (AuraHandledException e) {
            System.assert(true, 'An exception should have been thrown due to invalid startDate');
        }
    }

    @isTest
    static void testGetLeaveBalancesForUsersInvalidUserId() {
        // Simulate the case where the userId is invalid (blank)
        try {
            Test.startTest();
            AttendanceValidations.getLeaveBalancesForUsers(Date.today(), '');
            Test.stopTest();
            System.assert(false, 'An exception should have been thrown due to invalid userId');
        } catch (AuraHandledException e) {
            System.assert(true, 'An exception should have been thrown due to invalid userId');
        }
    }

    @isTest
    static void testGetLeaveBalancesForUsersNoLeaveApplications() {
        // Simulate the case where there are no leave applications for the user
        User testUser = [SELECT Id FROM User WHERE Username = :UserInfo.getUserName() LIMIT 1];

        Test.startTest();
        Boolean result = AttendanceValidations.getLeaveBalancesForUsers(Date.today(), testUser.Id);
        Test.stopTest();

        // Assert that the result is true because there are no leave applications to check
        System.assert(result, 'No leave applications should result in valid leave balance');
    }
}