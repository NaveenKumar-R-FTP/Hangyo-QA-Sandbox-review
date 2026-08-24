@isTest
public class OrderTriggerHandlerTest {
    
    @testSetup
    static void setupTestData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
 // Create a Retailer Account Record Type
        RecordType retailerRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'Retailer' LIMIT 1];
        RecordType secondaryOrderRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Order__c' AND DeveloperName = 'Secondary_Order' LIMIT 1];

     

        // Create Test Accounts (Retailers)
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 2; i++) {
            accounts.add(new Account(
                Name = 'Retailer ' + i,
                RecordTypeId = retailerRecordType.Id,
                 PAN_Number__c='TGYKI5566J'+i
            ));
        }
        insert accounts;

        // Create Test Orders
        List<Order__c> orders = new List<Order__c>();
        for (Account acc : accounts) {
            for (Integer j = 0; j < 3; j++) { // 3 Orders per Account
                orders.add(new Order__c(
                    Account__c = acc.Id,
                    Total_Order_Value__c = 100 * (j + 1),
                    RecordTypeId = secondaryOrderRecordType.Id
                   
                ));
            }
        }
        insert orders;
    }

    @isTest
    static void testUpdateAverageOrderValue() {
        // Retrieve test data
        List<Order__c> testOrders = [SELECT Id, Account__c FROM Order__c];
        
        // Call the handler method
        Test.startTest();
        OrderTriggerHandler.updateAverageOrderValue(testOrders);
        Test.stopTest();
        
        // Verify if average order value was correctly updated
        List<Account> updatedAccounts = [SELECT Id, Average_Order_Value__c FROM Account];

        for (Account acc : updatedAccounts) {
            System.assert(acc.Average_Order_Value__c > 0, 'Average Order Value should be greater than 0');
        }
    }

    @isTest
    static void testNoOrdersScenario() {
        // Create a new Account without orders
        Account acc = new Account(Name = 'No Orders Retailer',
                 PAN_Number__c='TGYKI5566J');
        insert acc;

        // Call the handler with an empty order list
        Test.startTest();
        OrderTriggerHandler.updateAverageOrderValue(new List<Order__c>());
        Test.stopTest();

        // Verify the account's Average Order Value is not updated
        Account updatedAcc = [SELECT Id, Average_Order_Value__c FROM Account WHERE Id = :acc.Id LIMIT 1];
        System.assertEquals(null, updatedAcc.Average_Order_Value__c, 'Average Order Value should be null for accounts with no orders');
    }
    
    
      @isTest
    static void testUpdateUnderssOrderStatus() {
        RecordType underSSRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Order__c' AND DeveloperName = 'Under_SS_Order' LIMIT 1];
        RecordType underSSSecondaryRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Order__c' AND DeveloperName = 'Under_SS_Secondary_Order' LIMIT 1];

        Account testAcc = new Account(Name = 'SS Retailer', PAN_Number__c = 'SS12345');
        insert testAcc;

        // Create Parent Order
        Order__c parentOrder = new Order__c(
            Account__c = testAcc.Id,
            RecordTypeId = underSSRecordType.Id,
          Status__c = 'Order Placed'
        );
        insert parentOrder;

        // Create Child Order with different status
        Order__c childOrder = new Order__c(
            Account__c = testAcc.Id,
            RecordTypeId = underSSSecondaryRecordType.Id,
            Status__c = 'Order Placed',
            Under_SS_Order__c = parentOrder.Id
           // Record_Type_Name__c = 'Under SS Secondary Order'
        );
        insert childOrder;

        // Run method
        Test.startTest();
        childOrder.Status__c='Invoiced';
        update childOrder;
        OrderTriggerHandler.updateUnderssOrderStatus(new List<Order__c>{ childOrder });
        Test.stopTest();

        // Validate that parent order's status was updated to match child
        Order__c updatedParent = [SELECT Status__c FROM Order__c WHERE Id = :parentOrder.Id];
        System.assertEquals('Invoiced', updatedParent.Status__c, 'Parent order status should match the child order status.');
    }
}