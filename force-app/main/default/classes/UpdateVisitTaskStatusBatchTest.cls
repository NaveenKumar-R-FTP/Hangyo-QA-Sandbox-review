/**
* Test Class  : UpdateVisitTaskStatusBatchTest
* author      : Shyam
* CreatedDate : 22-01-24
* Description : Test class for class 'UpdateVisitTaskStatusBatch'.
                
* */
@isTest
public class UpdateVisitTaskStatusBatchTest {
    @isTest
    static void testBatchExecution() {
        insert new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        
        // Create an Account with Record Type 'Retailer'
        RecordType retailerRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1];
        Account retailerAccount = new Account(
            Name = 'Test Retailer Account',
            PAN_Number__c = 'NANAJ4545',
            RecordTypeId = retailerRecordType.Id
        );
        insert retailerAccount;
        
        // Create a Visit associated with the Retailer Account
        Visit__c visit = new Visit__c(
            Account__c = retailerAccount.Id
        );
        insert visit;
        
        // Create test data for Visit_Task__c with Account__c set
        Visit_Task__c task1 = new Visit_Task__c(
            Status__c = 'In Progress',
            Visit__c = visit.Id,
            Account__c = retailerAccount.Id,
            Task_Planned_Date__c = Date.today().addDays(-1)
        );
        Visit_Task__c task2 = new Visit_Task__c(
            Status__c = 'Completed- Order',
            Visit__c = visit.Id,
            Account__c = retailerAccount.Id,
            Task_Planned_Date__c = Date.today().addDays(-1)
        );
        Visit_Task__c task3 = new Visit_Task__c(
            Status__c = 'In Progress',
            Visit__c = visit.Id,
            Account__c = retailerAccount.Id,
            Task_Planned_Date__c = Date.today().addDays(-1)
        );
        insert new List<Visit_Task__c>{task1, task2, task3};
        
        // Verify the records are inserted
        System.assertEquals(3, [SELECT COUNT() FROM Visit_Task__c]);
        
        // Execute the batch
        Test.startTest();
        UpdateVisitTaskStatusBatch batch = new UpdateVisitTaskStatusBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verify that the status of task1 and task3 is updated to 'Cancelled'
        task1 = [SELECT Status__c FROM Visit_Task__c WHERE Id = :task1.Id];
        task2 = [SELECT Status__c FROM Visit_Task__c WHERE Id = :task2.Id];
        task3 = [SELECT Status__c FROM Visit_Task__c WHERE Id = :task3.Id];
        
        System.assertEquals('Cancelled', task1.Status__c);
    }
}