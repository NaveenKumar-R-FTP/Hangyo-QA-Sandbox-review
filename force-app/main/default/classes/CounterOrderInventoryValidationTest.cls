@isTest
public class CounterOrderInventoryValidationTest {
    @isTest
    static void testGetOrderRecord() {
        Account acc = new Account(
            Name = 'Test Distributor',
            RecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Distributor' AND SObjectType = 'Account' LIMIT 1].Id,
            Phone = '123-456-7890'
        );
        insert acc;
        
        Product__c product1 = new Product__c(Name = 'Product 1', IsActive__c = true);
        Product__c product2 = new Product__c(Name = 'Product 2', IsActive__c = true);
        insert new List<Product__c>{product1, product2};
             
        Order__c primaryOrder = new Order__c(
            AccountId__c = acc.Id,
            EffectiveDate__c = Date.today(),
            Total_Quantity__c = 100,
            Total_Order_Value__c = 2000,
            Discount_Amount_Order__c = 200 ,
            Status__c = 'Delivered',
            RecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Counter Order' AND SObjectType = 'Order__c' LIMIT 1].Id
        );
        insert primaryOrder;
        
        // Create Order Line Items for the Order
        Order_Line_Item__c orderLine11 = new Order_Line_Item__c(
            Order__c = primaryOrder.Id,
            Products__c = product1.Id,
            Product_Price__c = 20,
            Ordered_Quantity__c = 50 
        );

        Order_Line_Item__c orderLine12 = new Order_Line_Item__c(
            Order__c = primaryOrder.Id,
            Products__c = product2.Id,
            Product_Price__c = 30,
            Ordered_Quantity__c = 50
        );
        insert new List<Order_Line_Item__c>{orderLine11, orderLine12};
        
        // Create inventory records for the products
        Inventory__c inv1 = new Inventory__c(Product__c = product1.Id, Quantity_in_hand__c = 25, Distributor_Name__c = acc.Id);
        insert inv1;
        
        /*Inventory__c inv2 = new Inventory__c(Product__c = product2.Id, Quantity_in_hand__c = 200, Distributor_Name__c = acc.Id);
        insert inv2;*/
        
        Map<Id, Order__c> oldOrderMap = new Map<Id, Order__c>();
        oldOrderMap.put(primaryOrder.Id, new Order__c(Status__c = 'Order Placed'));
        
        Test.startTest();
        CounterOrderInventoryValidation.checkInventory(new List<Order__c>{primaryOrder}, oldOrderMap);
        Test.stopTest();
    }
}