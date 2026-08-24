@isTest
private class ReturnProcessorControllerTest {
    
    @testSetup
    static void setupTestData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting; 
        
        // Create test Account
        Account testAccount = new Account(Name='Test Account');
        insert testAccount;
        
        // Create test Order
        Order__c testOrder = new Order__c(Account__c = testAccount.Id, Status__c = 'Order Placed');
        insert testOrder;
        
             Order_Line_Item__c testOrderLI = new Order_Line_Item__c(Order__c =testOrder.id);
        insert testOrderLI;
                  Id invoiceRecTypeId = [ 
    SELECT Id FROM RecordType 
    WHERE DeveloperName = 'Secondary_Invoice' AND SObjectType = 'Invoice__c' 
    LIMIT 1 
].Id;
        
        
        // Create test Invoice
        Invoice__c testInvoice = new Invoice__c(
            Name = 'INV-001', 
            Invoice_Amount__c = 1000, 
            Status__c = 'Delivered',
            Total_Quantity__c = 35, 
            Taxable_Amount__c = 900, 
            Order__c = testOrder.Id,
            Retailer_Account__c = testAccount.Id,
            RecordTypeId=invoiceRecTypeId
        );
        insert testInvoice;
        
          Id productRecordTypeId = [ 
    SELECT Id FROM RecordType 
    WHERE DeveloperName = 'Product' AND SObjectType = 'Product__c' 
    LIMIT 1 
].Id;
        
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

        // Create test Invoice Line Items
        List<Invoice_Line_Item__c> lineItems = new List<Invoice_Line_Item__c>();
        for (Integer i = 0; i < 2; i++) {
            lineItems.add(new Invoice_Line_Item__c(
                Invoice__c = testInvoice.Id,
                Product__c = testProduct.Id, // Using Account Id for test purposes
                Quantity__c = 10 + i,
                Price__c = 50,
                Total_Amount__c = (10 + i) * 50
            ));
        }
        insert lineItems;
    }
    
    @isTest
    static void testGetInvoiceLineItems() {
        // Fetch test invoice
        Invoice__c testInvoice = [SELECT Id FROM Invoice__c LIMIT 1];

        Test.startTest();
        // Call the method
        Map<String, Object> result = ReturnProcessorController.getInvoiceLineItems(testInvoice.Id);
        Test.stopTest();

        // Assert results
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.containsKey('invoice'), 'Response should contain invoice');
        System.assert(result.containsKey('lineItems'), 'Response should contain line items');
        List<Object> lineItems = (List<Object>) result.get('lineItems');
        System.assertEquals(2, lineItems.size(), 'There should be 2 line items');
    }

    @isTest
    static void testSaveReturns() {
        // Fetch test invoice
        Invoice__c testInvoice = [SELECT Id, Order__c FROM Invoice__c LIMIT 1];
        Order_Line_Item__c testoli = [SELECT Id FROM Order_Line_Item__c LIMIT 1];
        Product__c prod = [SELECT Id FROM Product__c LIMIT 1];

        // Create JSON string for line items
        String jsonLineItems = '[{"lineItemId":"'+testoli.id+'","productName":"Hangyo distributor product 1","quantity":1,"damage":1,"reuse":0,"returnAmount":100,"prodId":"'+prod.id+'","unitPrice":100}]';
        
        Test.startTest();
        // Call the method
        ReturnProcessorController.saveReturns(
            testInvoice.Id,
            10,  // totalQuantity
            100, // totalAmount
            10,  // cgst
            5,   // sgst
            2, 
            jsonLineItems
        );
        Test.stopTest();

        // Query inserted records
        Returns__c insertedReturn = [SELECT Id, Total_Return_Quantity__c FROM Returns__c WHERE Invoice__c = :testInvoice.Id LIMIT 1];
        System.assertNotEquals(null, insertedReturn, 'Return record should be inserted');
        System.assertEquals(10, insertedReturn.Total_Return_Quantity__c, 'Total quantity should match');

        List<Return_Line_item__c> returnLineItems = [SELECT Id FROM Return_Line_item__c WHERE Return__c = :insertedReturn.Id];
        System.assert(returnLineItems.size() > 0, 'Return line items should be inserted');

        Credit_Note__c creditNote = [SELECT Id, Total_Returns_Qty__c FROM Credit_Note__c WHERE Invoice__c = :testInvoice.Id LIMIT 1];
        System.assertNotEquals(null, creditNote, 'Credit note should be created');
        System.assertEquals(10, creditNote.Total_Returns_Qty__c, 'Credit note return quantity should match');
    }
}