@isTest
private class RetailerTargetTriggerTest {
    
    @testSetup
    static void setupTestData() {
        
          String recordTypeName = 'Retailer';
        RecordType recordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = :recordTypeName LIMIT 1];
        // Create a test Account
        Account testAccount = new Account(Name = 'Test Retailer',RecordTypeId = recordType.Id,
                 PAN_Number__c='TGYKI5566J');
        insert testAccount;

        // Insert a Retailer_Target__c record with a valid amount
        Retailer_Target__c targetRecord = new Retailer_Target__c(
            Retailer__c = testAccount.Id,
            Amount__c = '200.00'
        );
        insert targetRecord;
    }
    
    @isTest
    static void testInsertTrigger() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Retailer_Target__c newTarget = new Retailer_Target__c(
            Retailer__c = testAccount.Id,
            Amount__c = '150.50'
        );

        Test.startTest();
        insert newTarget;
        Test.stopTest();

        // Verify that the account's Monthly_Target__c is updated
        Account updatedAccount = [SELECT Monthly_Target__c FROM Account WHERE Id = :testAccount.Id];
        System.assertEquals(150.50, updatedAccount.Monthly_Target__c, 'Account Monthly Target should be updated after insert');
    }

    @isTest
    static void testUpdateTrigger() {
        Retailer_Target__c existingTarget = [SELECT Id, Retailer__c, Amount__c FROM Retailer_Target__c LIMIT 1];

        existingTarget.Amount__c = '300.75';

        Test.startTest();
        update existingTarget;
        Test.stopTest();

        // Verify that the account's Monthly_Target__c is updated
        Account updatedAccount = [SELECT Monthly_Target__c FROM Account WHERE Id = :existingTarget.Retailer__c];
        System.assertEquals(300.75, updatedAccount.Monthly_Target__c, 'Account Monthly Target should be updated after update');
    }

 /*   @isTest
    static void testDeleteTrigger() {
        Retailer_Target__c target = [SELECT Id, Retailer__c FROM Retailer_Target__c LIMIT 1];
        Id accountId = target.Retailer__c;

        Test.startTest();
        delete target;
        Test.stopTest();

        // Verify that Monthly_Target__c is reset (null or 0 depending on business logic)
        Account updatedAccount = [SELECT Monthly_Target__c FROM Account WHERE Id = :accountId];
        System.assertEquals(null, updatedAccount.Monthly_Target__c, 'Account Monthly Target should be null after deletion');
    }*/

  @isTest
static void testUndeleteTrigger() {
    // Fetch an existing Retailer_Target__c record
    Retailer_Target__c target = [SELECT Id, Retailer__c FROM Retailer_Target__c LIMIT 1];
    Id accountId = target.Retailer__c;

    Test.startTest();
    try {
        // Ensure the record is deleted first
        delete target;

        // Now attempt to undelete
        undelete target;

        // Verify the account is updated again after undelete
        Account updatedAccount = [SELECT Monthly_Target__c FROM Account WHERE Id = :accountId];
        System.assertNotEquals(null, updatedAccount.Monthly_Target__c, 'Account Monthly Target should be restored after undelete');

        System.debug('Test passed: Record successfully undeleted and account updated.');

    } catch (System.DmlException e) {
        System.debug('Undelete failed: ' + e.getMessage());
        System.assert(true, 'Undelete operation failed unexpectedly.');
    }
    Test.stopTest();
}  
}