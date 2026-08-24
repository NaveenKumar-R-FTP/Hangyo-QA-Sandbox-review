/**
* Test Class  : LeaveApplicationTriggerTest
* Trigger Name: LeaveApplicationTrigger
* Class Name  : LeaveApplicationsTriggerHandler
* author      : Shyam
* CreatedDate : 23-01-25
* Description : This is test class for trigger "LeaveApplicationTrigger" & it handler
* */
@isTest
public class LeaveApplicationTriggerTest {

    private static User getTestUser() {
        return [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    }

    private static Employee_Leave_Application__c createEmployee(User user) {
        Employee_Leave_Application__c emp = new Employee_Leave_Application__c(User__c = user.Id);
        insert emp;
        return emp;
    }

    @isTest
    static void testFullDayLeaveCreation() {
        User user = getTestUser();
        Employee_Leave_Application__c emp = createEmployee(user);

        Leave_Application__c leave = new Leave_Application__c(
            Employee_Leave_Application__c = emp.Id,
            User__c = user.Id,
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addDays(2),
            Approval_Status__c = 'Submit for Approval',
            Leave_Types__c = 'Sick Leave',
            Leave_Period__c = 'Full Day',
            Leave_For__c = 'Medical Checkup',
            Description__c = 'Test leave',
            Reason_For_Leave__c = 'Medical'
        );
        insert leave;

        leave.Approval_Status__c = 'Approved';
        update leave;

        List<Attendance__c> records = [SELECT Status__c, Leave_Application__c FROM Attendance__c WHERE Leave_Application__c = :leave.Id];
        System.assertEquals(3, records.size(), 'Should create 3 attendance records.');
        for (Attendance__c rec : records) {
            System.assertEquals('Leave', rec.Status__c);
        }
    }

    @isTest
    static void testHalfDayLeaveFirstHalf() {
        User user = getTestUser();
        Employee_Leave_Application__c emp = createEmployee(user);

        Leave_Application__c leave = new Leave_Application__c(
            Employee_Leave_Application__c = emp.Id,
            User__c = user.Id,
            Start_Date__c = Date.today(),
            End_Date__c = Date.today(),
            Approval_Status__c = 'Submit for Approval',
            Leave_Types__c = 'Casual Leave',
            Leave_Period__c = 'Half Day',
            Leave_For__c = 'First Half',
            Description__c = 'Half day test',
            Reason_For_Leave__c = 'Personal'
        );
        insert leave;

        leave.Approval_Status__c = 'Approved';
        update leave;

        List<Attendance__c> records = [SELECT Status__c, Leave_Period__c, Leave_For__c FROM Attendance__c WHERE Leave_Application__c = :leave.Id];
        System.assertEquals(1, records.size());
        System.assertEquals('Present Half Day', records[0].Status__c);
    }

    @isTest
    static void testUpdateFromHalfDayToFullLeave() {
        User user = getTestUser();
        Employee_Leave_Application__c emp = createEmployee(user);

        // Insert existing record with Present Half Day
        Attendance__c existing = new Attendance__c(
            User__c = user.Id,
            Leave_Date__c = Date.today(),
            Status__c = 'Present Half Day',
            Description__c = 'Existing record'
        );
        insert existing;

        Leave_Application__c leave = new Leave_Application__c(
            Employee_Leave_Application__c = emp.Id,
            User__c = user.Id,
            Start_Date__c = Date.today(),
            End_Date__c = Date.today(),
            Approval_Status__c = 'Submit for Approval',
            Leave_Types__c = 'Annual Leave',
            Leave_Period__c = 'Half Day',
            Leave_For__c = 'Second Half',
            Description__c = 'Completing full leave',
            Reason_For_Leave__c = 'Travel'
        );
        insert leave;

        leave.Approval_Status__c = 'Approved';
        update leave;

        Attendance__c updated = [SELECT Status__c FROM Attendance__c WHERE Leave_Application__c = :leave.Id LIMIT 1];
        System.assertEquals('Leave', updated.Status__c, 'Status should be updated to Leave from Half Day');
    }

    @isTest
    static void testIncompleteLeaveDataNoInsert() {
        User user = getTestUser();
        Employee_Leave_Application__c emp = createEmployee(user);

        Leave_Application__c leave = new Leave_Application__c(
            Employee_Leave_Application__c = emp.Id,
            User__c = user.Id,
            Start_Date__c = Date.today(),
            End_Date__c = null,
            Approval_Status__c = 'Approved',
            Leave_Types__c = 'Unpaid Leave',
            Leave_Period__c = 'Half Day',
            Leave_For__c = 'First Half',
            Description__c = 'Missing end date',
            Reason_For_Leave__c = 'Errand'
        );
        insert leave;

        leave.Description__c = 'Still invalid';
        update leave;

        List<Attendance__c> records = [SELECT Id FROM Attendance__c WHERE Leave_Application__c = :leave.Id];
        System.assertEquals(0, records.size(), 'No attendance records should be created with missing end date');
    }

    @isTest
    static void testNoTriggerExecutionOnSameApprovalStatus() {
        User user = getTestUser();
        Employee_Leave_Application__c emp = createEmployee(user);

        Leave_Application__c leave = new Leave_Application__c(
            Employee_Leave_Application__c = emp.Id,
            User__c = user.Id,
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addDays(1),
            Approval_Status__c = 'Approved',
            Leave_Types__c = 'Sick Leave',
            Leave_Period__c = 'Full Day',
            Leave_For__c = 'Medical',
            Description__c = 'Initial'
        );
        insert leave;

        leave.Description__c = 'No change in status';
        update leave; // Same status, should not trigger

        List<Attendance__c> records = [SELECT Id FROM Attendance__c WHERE Leave_Application__c = :leave.Id];
        System.assertEquals(0, records.size(), 'No attendance records because approval status did not change');
    }
}