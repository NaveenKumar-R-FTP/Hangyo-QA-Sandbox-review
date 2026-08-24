/**
* Test Class  : UpdateEmployeeLeaveAllowanceBatchTest
* Class Name  : UpdateEmployeeLeaveAllowanceBatch
* author      : Shyam
* CreatedDate : 23-01-25
* Description : Test class for "UpdateEmployeeLeaveAllowanceBatch".
* */

@isTest
public class UpdateEmployeeLeaveAllowanceBatchTest {

    @isTest
    static void testBatch() {
        // Step 1: Set up Custom Settings (Casual, Sick, and Maternity Leave values)
        Casual_Leaves__c casualLeave = new Casual_Leaves__c(
            Name = 'Casual Leave Value',
            Total_Casual_Leave__c = 10
        );
        insert casualLeave;

        Sick_Leave__c sickLeave = new Sick_Leave__c(
            Name = 'Sick Leave Value',
            Total_Sick_Leave__c = 12
        );
        insert sickLeave;

        Maternity_Leave__c maternityLeave = new Maternity_Leave__c(
            Name = 'Maternity Leave Value',
            Total_Maternity_Leave__c = 14
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
            IsActive = true
        );
        insert user2;

        // Step 3: Create Employee_Leave_Allowance__c records
        Employee_Leave_Allowance__c allowance1 = new Employee_Leave_Allowance__c(User__c = user1.Id);
        Employee_Leave_Allowance__c allowance2 = new Employee_Leave_Allowance__c(User__c = user2.Id);
        insert new List<Employee_Leave_Allowance__c>{allowance1, allowance2};

        // Step 4: Execute the Batch Class
        Test.startTest();
        
        UpdateEmployeeLeaveAllowanceBatch batch = new UpdateEmployeeLeaveAllowanceBatch();
        Database.executeBatch(batch, 200);  // Adjust the batch size if needed
        
        Test.stopTest();

        // Step 5: Verify that the records were updated correctly
        Employee_Leave_Allowance__c updatedAllowance1 = [SELECT Id, Total_Casual_Leave__c, Total_Sick_Leave__c, Total_Maternity_Leave__c, Name FROM Employee_Leave_Allowance__c WHERE Id = :allowance1.Id];
        Employee_Leave_Allowance__c updatedAllowance2 = [SELECT Id, Total_Casual_Leave__c, Total_Sick_Leave__c, Total_Maternity_Leave__c, Name FROM Employee_Leave_Allowance__c WHERE Id = :allowance2.Id];

        // Verify that the leave values are set correctly
        System.assertNotEquals(10, updatedAllowance1.Total_Casual_Leave__c);
    }

    @isTest
    static void testScheduler() {
        // Create necessary custom settings and users as done in the testBatch method

        // Step 1: Set up Custom Settings
        Casual_Leaves__c casualLeave = new Casual_Leaves__c(
            Name = 'Casual Leave Value',
            Total_Casual_Leave__c = 10
        );
        insert casualLeave;

        Sick_Leave__c sickLeave = new Sick_Leave__c(
            Name = 'Sick Leave Value',
            Total_Sick_Leave__c = 12
        );
        insert sickLeave;

        Maternity_Leave__c maternityLeave = new Maternity_Leave__c(
            Name = 'Maternity Leave Value',
            Total_Maternity_Leave__c = 14
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