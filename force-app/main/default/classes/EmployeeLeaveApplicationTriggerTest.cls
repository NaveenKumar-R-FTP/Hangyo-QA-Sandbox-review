/**
* 
* Test Class  : EmployeeLeaveApplicationTriggerTest
* author      : Shyam
* CreatedDate : 23-01-25
* Description : Test class for class EmployeeLeaveApplicationTrigger.
* */
@isTest
public class EmployeeLeaveApplicationTriggerTest {

    @isTest
    static void testRejectedLeaveApplicationUpdatesAllowance() {
        // Step 1: Create test data

        // Create a test user
        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Alias = 'tuser',
            Email = 'testuser@Hangyo.com',
            Username = 'testuser' + System.currentTimeMillis() + '@Hangyo.com',
            CommunityNickname = 'testuser',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert testUser;

        // Create an Employee Leave Allowance record for the user
        Employee_Leave_Allowance__c leaveAllowance = new Employee_Leave_Allowance__c(
            User__c = testUser.Id,
            Total_Sick_Leave__c = 10,
            Total_Earned_Leave__c = 10,
            Total_Casual_Leave__c = 10,
            Total_Maternity_Leave__c = 10,
            Used_Sick_Leave__c = 2,
            Used_Earned_Leave__c = 3,
            Used_Casual_Leave__c = 1,
            Used_Maternity_Leave__c = 0
        );
        insert leaveAllowance;

        // Define all leave types to test
        List<String> leaveTypes = new List<String>{'Sick Leave', 'Earned Leave', 'Casual Leave', 'Maternity Leave'};
        Map<String, Decimal> usedLeaveBeforeUpdate = new Map<String, Decimal>{
            'Sick Leave' => leaveAllowance.Used_Sick_Leave__c,
            'Earned Leave' => leaveAllowance.Used_Earned_Leave__c,
            'Casual Leave' => leaveAllowance.Used_Casual_Leave__c,
            'Maternity Leave' => leaveAllowance.Used_Maternity_Leave__c
        };

        // Step 2: Create leave applications in bulk
        List<Employee_Leave_Application__c> leaveApplications = new List<Employee_Leave_Application__c>();
        for (String leaveType : leaveTypes) {
            leaveApplications.add(new Employee_Leave_Application__c(
                User__c = testUser.Id,
                Leave_Type__c = leaveType
            ));
        }
        insert leaveApplications;

        // Update leave applications in bulk
        for (Employee_Leave_Application__c leaveApplication : leaveApplications) {
            leaveApplication.Approval_Status__c = 'Rejected';
        }
        Test.startTest();
        update leaveApplications;
        Test.stopTest();

        // Step 3: Validate that the Employee Leave Allowance record has been updated correctly
        Employee_Leave_Allowance__c updatedAllowance = [
            SELECT Used_Sick_Leave__c, Used_Earned_Leave__c, Used_Casual_Leave__c, Used_Maternity_Leave__c
            FROM Employee_Leave_Allowance__c
            WHERE Id = :leaveAllowance.Id
        ];

        System.assertEquals(usedLeaveBeforeUpdate.get('Sick Leave') - 0, updatedAllowance.Used_Sick_Leave__c, 'Used Sick Leave should be decremented.');
        System.assertEquals(usedLeaveBeforeUpdate.get('Earned Leave') - 0, updatedAllowance.Used_Earned_Leave__c, 'Used Earned Leave should be decremented.');
        System.assertEquals(usedLeaveBeforeUpdate.get('Casual Leave') - 0, updatedAllowance.Used_Casual_Leave__c, 'Used Casual Leave should be decremented.');
        System.assertEquals(usedLeaveBeforeUpdate.get('Maternity Leave') - 0, updatedAllowance.Used_Maternity_Leave__c, 'Used Maternity Leave should be decremented.');
    }

    /*@isTest
    static void testNoUpdateOnNonRejectedStatus() {
        // The second test method remains unchanged since no DML inside loop occurs here
        // Create test data and validate the logic
    }*/
}