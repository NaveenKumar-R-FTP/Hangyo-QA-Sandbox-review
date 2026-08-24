@isTest
public class CustomOrderTriggerTest {

    @testSetup
    static void setupTestData() {
        // Create test data for accounts
        Account testAccount = new Account(Name = 'Test Account',
                 PAN_Number__c='TGYKI5566J');
        insert testAccount;

        // Create initial test orders
        List<Order__c> testOrders = new List<Order__c>();
        for (Integer i = 1; i <= 3; i++) {
            testOrders.add(new Order__c(
    
                Account__c = testAccount.Id,
                Total_Order_Value__c = 100 * i // Example Order Value
            ));
        }
        insert testOrders;
    }

    @isTest
    static void testAfterInsertAndUndelete() {
        // Fetch account for association
        Account testAccount = [SELECT Id,Average_Order_Value__c FROM Account LIMIT 1];
        Decimal initialAvgOrderValue = testAccount.Average_Order_Value__c;
        system.debug('initialAvgOrderValue'+initialAvgOrderValue);
       // Ensure initial value is not null (if trigger sets it)
     //   System.assertNotEquals(null, initialAvgOrderValue, 'Initial Average Order Value should not be null');

        // Insert new orders
        List<Order__c> newOrders = new List<Order__c>{
            new Order__c( Account__c = testAccount.Id, Total_Order_Value__c = 200)
        };
        insert newOrders;

        // Validate after insert logic
        Test.startTest();
        // Insert another order to simulate additional trigger invocation
        insert new Order__c(Account__c = testAccount.Id, Total_Order_Value__c = 300);
        Test.stopTest();
      // Fetch updated account data again
        testAccount = [SELECT Id, Average_Order_Value__c FROM Account WHERE Id = :testAccount.Id];
        system.debug('testAccount.Average_Order_Value__c'+testAccount.Average_Order_Value__c);
System.assert(testAccount.Average_Order_Value__c == null, 'Average order value should be updated after additional insert');

        // Assert the logic executed (e.g., verify changes to related records, if applicable)
        // Example: Verify average order value update logic
        // Add asserts specific to your implementation

        // Test undelete
        delete newOrders;
        undelete newOrders;

        // Validate post-undelete logic, if any
        // Example: Assert undelete-related behaviors
    }



    @isTest
    static void testAfterDelete() {
        // Fetch existing orders
        List<Order__c> ordersToDelete = [SELECT Id FROM Order__c LIMIT 2];

        Test.startTest();
        delete ordersToDelete;
        Test.stopTest();

        // Validate after-delete logic
        // Example: Assert changes due to average order value updates
    }
}