/**
* Test Class  : TestCreateEmployeeLeaveAllowance
* Class Name  : CreateEmployeeLeaveAllowance
* author      : Mirza
* CreatedDate : 23-01-25
* Description : Test class for "CreateEmployeeLeaveAllowance".
* */

@isTest
public class TestCreateEmployeeLeaveAllowance {

    @isTest
    static void testBatch() {
        // Step 1: Set up Custom Settings (Casual, Sick, and Maternity Leave values)
        Casual_Leaves__c casualLeave = new Casual_Leaves__c(
            Name = 'Casual Leave Value',
            Total_Casual_Leave__c = 10.0
        );
        insert casualLeave;

        Sick_Leave__c sickLeave = new Sick_Leave__c(
            Name = 'Sick Leave Value',
            Total_Sick_Leave__c = 12.0
        );
        insert sickLeave;

        Maternity_Leave__c maternityLeave = new Maternity_Leave__c(
            Name = 'Maternity Leave Value',
            Total_Maternity_Leave__c = 14.0
        );
        insert maternityLeave;

        // Step 2: Create test users (active)
        User user1 = new User(
            Alias = 'Sam',
            Email = 'Samsahaw1@hangyo.com',
            ProfileId = UserInfo.getProfileId(),
            Username = 'Samsahaw1@hangyo.com',
            FirstName = 'John',
            LastName = 'Doe',
            LanguageLocaleKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            Employee_Role__c = 'SSO',
            IsActive = true
        );
        insert user1;

        User user2 = new User(
            Alias = 'JaneSmt',
            Email = 'janesmith1@hangyo.com',
            ProfileId = UserInfo.getProfileId(),
            Username = 'janesmith1@hangyo.com',
            FirstName = 'Jane',
            LastName = 'Smith',
            LanguageLocaleKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            Employee_Role__c = 'SSO',
            IsActive = true
        );
        insert user2;

        // Step 3: Execute the Batch Class
        Test.startTest();
        
        //UpdateEmployeeLeaveAllowanceBatch batch = new UpdateEmployeeLeaveAllowanceBatch();
        //Database.executeBatch(batch, 200);  // Adjust the batch size if needed
        CreateEmployeeLeaveAllowance.employeeLeaveAllowanceMethod();
        
        Test.stopTest();

        // Step 4: Verify that the records were updated correctly
        Employee_Leave_Allowance__c leaveAllowances = [SELECT Id, User__c, Total_Casual_Leave__c, Total_Sick_Leave__c, Total_Maternity_Leave__c, Used_Casual_Leave__c, Used_Sick_Leave__c, Used_Earned_Leave__c, Name FROM Employee_Leave_Allowance__c LIMIT 1];
        
        System.assertEquals(10, leaveAllowances.Total_Casual_Leave__c);
    }

    @isTest
    static void testScheduler() {
        // Create necessary custom settings and users as done in the testBatch method

        // Step 1: Set up Custom Settings
        Casual_Leaves__c casualLeave = new Casual_Leaves__c(
            Name = 'Casual Leave Value',
            Total_Casual_Leave__c = 10.0
        );
        insert casualLeave;

        Sick_Leave__c sickLeave = new Sick_Leave__c(
            Name = 'Sick Leave Value',
            Total_Sick_Leave__c = 12.0
        );
        insert sickLeave;

        Maternity_Leave__c maternityLeave = new Maternity_Leave__c(
            Name = 'Maternity Leave Value',
            Total_Maternity_Leave__c = 14.0
        );
        insert maternityLeave;

        // Step 2: Create test users (active)
        User user1 = new User(
            Alias = 'Sam',
            Email = 'Samsahaw1@hangyo.com',
            ProfileId = UserInfo.getProfileId(),
            Username = 'Samsahaw1@hangyo.com',
            FirstName = 'John',
            LastName = 'Doe',
            LanguageLocaleKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            Employee_Role__c = 'SSO',
            IsActive = true
        );
        insert user1;

        User user2 = new User(
            Alias = 'JaneSmt',
            Email = 'janesmith1@hangyo.com',
            ProfileId = UserInfo.getProfileId(),
            Username = 'janesmith1@hangyo.com',
            FirstName = 'Jane',
            LastName = 'Smith',
            LanguageLocaleKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            Employee_Role__c = 'SSO',
            IsActive = true
        );
        insert user2;

        // Step 3: Create Employee_Leave_Allowance__c records
        Employee_Leave_Allowance__c allowance1 = new Employee_Leave_Allowance__c(User__c = user1.Id);
        Employee_Leave_Allowance__c allowance2 = new Employee_Leave_Allowance__c(User__c = user2.Id);
        insert new List<Employee_Leave_Allowance__c>{allowance1, allowance2};

        // Step 4: Schedule the batch job
        String cronExp = '0 0 0 1 1 ? *';  // Runs on 1st January of every year
        ScheduleEmployeeLeaveUpdate scheduler = new ScheduleEmployeeLeaveUpdate();
        String jobId = System.schedule('Leave Update Job', cronExp, scheduler);

        // Step 5: Verify the job is scheduled
        CronTrigger ct = [SELECT Id, State FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals('WAITING', ct.State);
    }
}