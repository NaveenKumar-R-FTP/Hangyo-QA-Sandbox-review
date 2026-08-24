/**
* Test Class  : ScheduleUpdateVisitTaskStatusTest
* author      : Shyam
* CreatedDate : 24-01-25
* Description : Test class for class 'ScheduleUpdateVisitTaskStatus'.
                
* */
@isTest
public class ScheduleUpdateVisitTaskStatusTest {
    @isTest
    static void testSchedulerExecution() {
        // Create an Account with Record Type 'Retailer'
        RecordType retailerRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1];
        Account retailerAccount = new Account(
            Name = 'Test Retailer Account',
            PAN_Number__c = 'KSHA1515',
            RecordTypeId = retailerRecordType.Id
        );
        insert retailerAccount;

        // Create a Visit associated with the Retailer Account
        Visit__c visit = new Visit__c(
            Account__c = retailerAccount.Id
        );
        insert visit;

        // Create test data for Visit_Task__c
        Visit_Task__c task1 = new Visit_Task__c(
            Status__c = 'In Progress',
            Visit__c = visit.Id,
            Account__c = retailerAccount.Id
        );
        Visit_Task__c task2 = new Visit_Task__c(
            Status__c = 'Completed- Order',
            Visit__c = visit.Id,
            Account__c = retailerAccount.Id
        );
        Visit_Task__c task3 = new Visit_Task__c(
            Status__c = 'In Progress',
            Visit__c = visit.Id,
            Account__c = retailerAccount.Id
        );
        insert new List<Visit_Task__c>{task1, task2, task3};

        // Verify the records are inserted
        System.assertEquals(3, [SELECT COUNT() FROM Visit_Task__c]);

        // Define a cron expression and schedule the job
        String cronExpression = '0 0 12 * * ?'; // Run at 12:00 PM every day
        String jobName = 'Test Update Visit Task Status Job';

        Test.startTest();
        // Schedule the job
        System.schedule(jobName, cronExpression, new ScheduleUpdateVisitTaskStatus());
        Test.stopTest();

        // Verify that the batch job executed successfully by checking the task statuses
        task1 = [SELECT Status__c FROM Visit_Task__c WHERE Id = :task1.Id];
        task2 = [SELECT Status__c FROM Visit_Task__c WHERE Id = :task2.Id];
        task3 = [SELECT Status__c FROM Visit_Task__c WHERE Id = :task3.Id];

    }
}