@isTest
public class SecondaryOrderHandlerTest {
    
    @testSetup
    static void setupTestData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        // Query Record Type for Secondary Order (instead of inserting it)
        RecordType secondaryOrderRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Secondary_Order' AND SObjectType = 'Order__c' LIMIT 1];
		
        // Create test Account
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
		Id productRecordTypeId = [ 
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Product' AND SObjectType = 'Product__c' 
            LIMIT 1 
        ].Id;
		Id disRecId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId();
        Account distributor = new Account(Name = 'Distributor', recordtypeId = disRecId);
        insert distributor;
        Id retailerId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId();
        Account retailer = new Account(Name = 'Distributor', recordtypeId = disRecId);
        insert retailer;
        Product__c testProduct = new Product__c(
            Name = 'Test Product',
            IsActive__c = true,
            Primary_Product__c = true,
            RecordTypeId = productRecordTypeId,
            Rate_Value__c = 100,
            Unit_of_Measure__c = 'kg',
            Product_Brand__c = 'TestBrand',
            Image__c = 'test_image1.jpg,test_image2.jpg'
        );
        insert testProduct;
        // Create Test Order
        Order__c testOrder = new Order__c(
            
            AccountId__c = distributor.Id,
            Account__c = retailer.Id,
            RecordTypeId = secondaryOrderRT.Id // Using the queried RecordType
        );
        insert testOrder;

        // Create Test Order Line Items
        List<Order_Line_Item__c> orderItems = new List<Order_Line_Item__c>();
        for (Integer i = 0; i < 3; i++) {
            orderItems.add(new Order_Line_Item__c(
                Order__c = testOrder.Id,
                Ordered_Quantity__c = 10 + i,
                Product_Price__c = 100.00,
                Products__c = testProduct.Id
                
            ));
        }
        insert orderItems;
    }

    @isTest
    static void testFetchOrderAndLineItems() {
        Test.startTest();

        // Retrieve test order
        Order__c testOrder = [SELECT Id, Name FROM Order__c LIMIT 1];
		List<Order_Line_Item__c> testOrderItems = [Select Id, Name from Order_Line_Item__c where Order__c=: testOrder.Id];
        // Call fetchOrderAndLineItems method
        SecondaryOrderHandler.OrderData orderData = SecondaryOrderHandler.fetchOrderAndLineItems(testOrder.Id);
		SecondaryOrderHandler.ordfetchOrderAndLineItems(testOrder.Id);
        SecondaryOrderHandler.ordfetchSecondaryOrder(testOrder.Id);
        //SecondaryInvoiceHandler.InvoiceData invdata = SecondaryInvoiceHandler.getInvoiceData(testOrder,testOrderItems );
        // Assertions
        System.assertNotEquals(orderData, null, 'OrderData should not be null');
        System.assertNotEquals(orderData.order, null, 'Order should be fetched');
        System.assertEquals(orderData.order.Name, testOrder.Name, 'Order Name should match');
        System.assertNotEquals(orderData.orderItems, null, 'Order Items should be fetched');
        System.assertEquals(orderData.orderItems.size(), 3, 'Three order line items should be retrieved');

        Test.stopTest();
    }
    
    

}