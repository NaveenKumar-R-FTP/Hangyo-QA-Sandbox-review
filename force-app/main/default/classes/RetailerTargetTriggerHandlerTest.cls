@isTest
public class RetailerTargetTriggerHandlerTest {
    
    @isTest
    static void testUpdateAmountOnAccount() {
        // Step 1: Create test data
         // Query for the RecordType Id for 'Retailer'
        String recordTypeName = 'Retailer';
        RecordType recordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = :recordTypeName LIMIT 1];
        // Create an Account
        Account testAccount = new Account(Name = 'Test Account', RecordTypeId = recordType.Id,
                 PAN_Number__c='TGYKI5566J');
        insert testAccount;

        // Create Retailer_Target__c records, leaving out MonthYear__c if it's a formula field
        Retailer_Target__c target1 = new Retailer_Target__c(
            Retailer__c = testAccount.Id,
            Amount__c = '5000'
            // No need to set MonthYear__c, Salesforce will populate it automatically if it's a formula field
        );
        
        Retailer_Target__c target2 = new Retailer_Target__c(
            Retailer__c = testAccount.Id,
            Amount__c = '5000'
            // No need to set MonthYear__c
        );
        
        insert new List<Retailer_Target__c>{ target1, target2 };

        // Step 2: Invoke the method to update account's Monthly Target
        Test.startTest();
        
        // Manually invoke the handler method
        RetailerTargetTriggerHandler.updateAmountOnAccount(new List<Retailer_Target__c>{ target1, target2 });
        
        Test.stopTest();

        // Step 3: Verify the results
        // Fetch the updated account record
        Account updatedAccount = [SELECT Monthly_Target__c FROM Account WHERE Id = :testAccount.Id];

        // Assert that the Monthly_Target__c field is updated correctly for the current month
        System.assertEquals(5000, updatedAccount.Monthly_Target__c, 'Monthly Target should be updated to 5000 for the current month');
    }
}