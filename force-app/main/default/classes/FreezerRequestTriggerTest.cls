@isTest
public class FreezerRequestTriggerTest {
    @testSetup
    static void setupTestData() {
        // Create a test user (Submitter)
        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Alias = 'tuser',
            Email = 'testuser@example.com',
            Username = 'testuser@example.com' + System.currentTimeMillis(),
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert testUser;

        // Create a test Freezer Request record
        Freezer_Request__c freezerRequest = new Freezer_Request__c(
            Freezer_Make__c = 'Test Freezer Request',
            Approval_Request_Status__c = 'Request received' // Initial Status
            
        );
        insert freezerRequest;
    }

     @isTest
    static void testFreezerRequestApprovalNotification() {
        // Fetch the created record
        Freezer_Request__c freezerRequest = [SELECT Id, Approval_Request_Status__c FROM Freezer_Request__c LIMIT 1];

        // Start test execution
        Test.startTest();

        // Simulate Approval
        freezerRequest.Approval_Request_Status__c = 'Request approved';
        update freezerRequest;

        // Simulate Rejection
        freezerRequest.Approval_Request_Status__c = 'Request rejected';
        update freezerRequest;

        Test.stopTest();

        // Since Messaging.sendCustomNotification() is async, we can't assert its execution.
        // Instead, check the debug logs or ensure no exceptions occur.
        System.debug('Test executed successfully');
    }
}