/**
* Test Class  : MonthlyExpenseClaimSchedulerTest
* Class Name : MonthlyExpenseClaimSchedulerJob
* author      : Shyam
* CreatedDate : 22-01-24
* Description : Test class for "MonthlyExpenseClaimSchedulerTest".
* ModifiedDate: 08-07-25(Gleveta)
* */
@isTest
private class MonthlyExpenseClaimSchedulerTest {
    
    @isTest
static void testCreateMonthlyExpenseClaim() {
    // Step 1: Set up test data
    Id sfaProfileId = [SELECT Id FROM Profile WHERE Name = 'SFA Profile' LIMIT 1].Id;
    
    List<User> testUsers = new List<User>{
        new User(
            FirstName = 'John',
            LastName = 'Doe',
            Alias = 'jdoe',
            Email = 'jdoe@example.com',
            Username = 'jdoe@example.com.test',
            ProfileId = sfaProfileId,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Employee_Role__c='SSO'
        ),
        new User(
            FirstName = 'Jane',
            LastName = 'Smith',
            Alias = 'jsmith',
            Email = 'jsmith@example.com',
            Username = 'jsmith@example.com.test',
            ProfileId = sfaProfileId,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Employee_Role__c='SSO'
        )
    };
    insert testUsers;

    // Step 2: Call the method to test
    Test.startTest();
    MonthlyExpenseClaimScheduler.createMonthlyExpenseClaim();
    Test.stopTest();

    // Step 3: Validate results
    List<Expense_Claim__c> expenseClaims = [
        SELECT Name, Start_Date__c, End_Date__c, User__c
        FROM Expense_Claim__c
        WHERE User__c IN :testUsers
    ];

    System.assertEquals(2, expenseClaims.size(), 'Two expense claims should be created.');

    // Bulk query users and create a lookup map
    Map<Id, User> userMap = new Map<Id, User>();
    for (User u : [SELECT Id, FirstName, LastName FROM User WHERE Id IN :testUsers]) {
        userMap.put(u.Id, u);
    }

    // Validate each expense claim
    String monthName = MonthlyExpenseClaimScheduler.getMonthName(Date.today().month());
    String year = String.valueOf(Date.today().year());
    Date firstDayOfMonth = Date.newInstance(Date.today().year(), Date.today().month(), 1);
    Date lastDayOfMonth = Date.newInstance(Date.today().year(), Date.today().month(), Date.daysInMonth(Date.today().year(), Date.today().month()));

    for (Expense_Claim__c expenseClaim : expenseClaims) {
        User associatedUser = userMap.get(expenseClaim.User__c);
        String expectedName = monthName + '-' + year + '-Expense Claim For-' + associatedUser.FirstName + ' ' + associatedUser.LastName;

        System.assertEquals(expectedName, expenseClaim.Name, 'The expense claim name should match the expected format.');
        System.assertEquals(firstDayOfMonth, expenseClaim.Start_Date__c, 'Start date should be the first day of the month.');
        System.assertEquals(lastDayOfMonth, expenseClaim.End_Date__c, 'End date should be the last day of the month.');
    }
}


    @isTest
    static void testSchedulerJob() {
        // Step 1: Set up test data
        User testUser = new User(
            FirstName = 'John',
            LastName = 'Doe',
            Alias = 'jdoe',
            Email = 'jdoe@example.com',
            Username = 'jdoe@example.com.test',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'SFA Profile' LIMIT 1].Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Employee_Role__c='SSO'
        );
        insert testUser;

        // Step 2: Schedule the job
        String cronExp = '0 0 0 1 * ?'; // Every month at midnight on the first day
        String jobName = 'TestMonthlyExpenseClaimSchedulerJob';

        Test.startTest();
        Id jobId = System.schedule(jobName, cronExp, new MonthlyExpenseClaimSchedulerJob());
         // Id jobId2 = System.schedule(jobName, cronExp, new DailyExpenseSchedulerJob());
        Test.stopTest();

        // Step 3: Validate the scheduled job
        CronTrigger scheduledJob = [SELECT Id, CronExpression, State FROM CronTrigger WHERE Id = :jobId];
        System.assertNotEquals(null, scheduledJob, 'The scheduled job should exist.');
        System.assertEquals('WAITING', scheduledJob.State, 'The job should be in a WAITING state.');
        System.assertEquals(cronExp, scheduledJob.CronExpression, 'The cron expression should match the scheduled job.');
    }
        @isTest
    static void testSchedulerJob1() {
        // Step 1: Set up test data
        User testUser = new User(
            FirstName = 'John',
            LastName = 'Doe',
            Alias = 'jdoe',
            Email = 'jdoe@example.com',
            Username = 'jdoe@example.com.test',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'SFA Profile' LIMIT 1].Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Employee_Role__c='SSO'
        );
        insert testUser;

        // Step 2: Schedule the job
        String cronExp = '0 0 0 1 * ?'; // Every month at midnight on the first day
        String jobName = 'TestMonthlyExpenseClaimSchedulerJob';

        Test.startTest();
      //  Id jobId = System.schedule(jobName, cronExp, new MonthlyExpenseClaimSchedulerJob());
         Id jobId = System.schedule(jobName, cronExp, new DailyExpenseSchedulerJob());
        Test.stopTest();

        // Step 3: Validate the scheduled job
        CronTrigger scheduledJob = [SELECT Id, CronExpression, State FROM CronTrigger WHERE Id = :jobId];
        System.assertNotEquals(null, scheduledJob, 'The scheduled job should exist.');
        System.assertEquals('WAITING', scheduledJob.State, 'The job should be in a WAITING state.');
        System.assertEquals(cronExp, scheduledJob.CronExpression, 'The cron expression should match the scheduled job.');
    }
}