@isTest
public class CounterOrderProductPageControllerTest {

    @testSetup
    static void createTestData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        // Create a test Account
        Id accountRecordType = [ 
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Retailer' AND SObjectType = 'Account' 
            LIMIT 1 
        ].Id;
        Account testAccount = new Account(Name = 'Counter Sales Customer', RecordTypeId=accountRecordType , PAN_Number__c = '248001');
        insert testAccount;

        // Create a test Contact associated with the Account
        Contact testContact = new Contact(LastName = 'Test Contact', AccountId = testAccount.Id);
        insert testContact;

        // Create a test User associated with the Contact
        Profile p = [SELECT Id FROM Profile WHERE Name = 'DMS Partner Community Custom'];
        User testUser = new User(
            Alias = 'testUser',
            Email = 'testuser1@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testuser1@hangyoWierd.com',
            ContactId = testContact.Id
        );
        insert testUser;

        Id productRecordType = [ 
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Product' AND SObjectType = 'Product__c' 
            LIMIT 1 
        ].Id;

        // Create a test Product
        Product__c testProduct = new Product__c(
            Name = 'Test Product',
            IsActive__c = true,
            DisplayURL__c = 'http://example.com',
            Image__c = 'http://example.com/image.jpg',
            Image_Long__c = 'http://example.com/image1.jpg,http://example.com/image2.jpg',
            Unit_of_Measure__c = 'kg',
            Category_Code__c = 'TestCategory',
            Category_Name__c = 'Test Category',
            Product_Brand__c = 'Test Brand',
            RecordTypeId = productRecordType,
            Primary_Product__c = true
        );
        insert testProduct;

        /*Region__c region = new Region__c(
            Name = 'Karnataka'
        );
        insert region;
        
        // Create test Price Book
        Price_Book__c testPriceBook = new Price_Book__c(
            Name = 'Karnataka',
            isActive__c = true,
            Region__r = new Region__c(Name = 'Karnataka')
        );
        insert testPriceBook;

        // Create Price Book Entry
        Price_Book_Entry__c testPriceBookEntry = new Price_Book_Entry__c(
            Product__c = testProduct.Id,
            Price_Book__c = testPriceBook.Id,
            PTD__c = 100.00,
            Type__c = 'Retailer',
            isActive__c = true , 
            PTR__c=768
        );
        insert testPriceBookEntry;*/
    }

    // Test method for fetchProducts
    @isTest
    static void testFetchProducts() {
        // Create test data
        //createTestData();

        // Get the test user
        User testUser = [SELECT Id FROM User WHERE UserName = 'testuser1@hangyoWierd.com'];

        // Run as the test user
        System.runAs(testUser) {
            // Call the fetchProducts method
            Test.startTest();
            String result = CounterOrderProductPageController.fetchProducts('Test', 'Test Brand' , 'Available Stock', 'Name');
            Test.stopTest();

            // Verify the result
            System.assertNotEquals(null, result, 'The result should not be null');
            List<CounterOrderProductPageController.ProductDataWrapper> productWrapperList = (List<CounterOrderProductPageController.ProductDataWrapper>) JSON.deserialize(result, List<CounterOrderProductPageController.ProductDataWrapper>.class);
        }
    }

 @isTest
static void testGenerateProposal() {
    // Create test data
    //createTestData();

    // Get the test user
    User testUser = [SELECT Id FROM User WHERE UserName = 'testuser1@hangyoWierd.com'];

    // Run as the test user
    System.runAs(testUser) {
        // Fetch the test product
        Product__c testProduct = [SELECT Id FROM Product__c LIMIT 1];

       
        // Create the order summary data
        CounterOrderProductPageController.OrderSummaryWrapper orderSummaryData = new CounterOrderProductPageController.OrderSummaryWrapper();
        orderSummaryData.totalItems = 2;
        orderSummaryData.totalPrice = 330.40;
        orderSummaryData.totalDiscount = 0;
        orderSummaryData.totalOrderValue = 280;
        orderSummaryData.totalQuantity = 3;
     //   orderSummaryData.totalSGST = 25.20;
     //   orderSummaryData.totalCGST = 25.20;
     //   orderSummaryData.totalIGST = 0.00;
// Define the valid cart data (productsFromCart)
        String productsFromCart = '[{"productId":"'+testProduct.Id+'","productIdForCart":"'+testProduct.Id+'Cart","productImage":"&lt;p&gt;&lt;img src=&quot;/dms/servlet/rtaImage?eid=a0JH1000005g6pO&amp;feoid=00NH100000CY6ZE&amp;refid=0EMH10000008Lkd&quot; alt=&quot;AlphonsoMango.jpg&quot;&gt;&lt;/img&gt;&lt;/p&gt;","quantity":1,"productName":"Hangyo distributor product 4","productBrand":"Family Pack","productFullName":"Hangyo distributor product 4","productListPrice":80,"productOfferPrice":80,"prodmeasure":"KG"},{"productId":"'+testProduct.Id+'","productIdForCart":"'+testProduct.Id+'Cart","productImage":"&lt;p&gt;&lt;img src=&quot;/dms/servlet/rtaImage?eid=a0JH1000005g6pQ&amp;feoid=00NH100000CY6ZE&amp;refid=0EMH10000008Lks&quot; alt=&quot;ButterScotchBurst.jpg&quot;&gt;&lt;/img&gt;&lt;/p&gt;","quantity":2,"productName":"Hangyo distributor product 6","productBrand":"Combos","productFullName":"Hangyo distributor product 6","productListPrice":100,"productOfferPrice":100,"prodmeasure":"E"}]';

        // Define the orderSummary data
        String orderSummary = '{"totalItems":2,"totalPrice":"330.40","totalDiscount":0,"totalOrderValue":280,"totalQuantity":3,"totalSGST":"25.20","totalCGST":"25.20","totalIGST":"0.00"}';
        
        // Serialize the order summary to JSON
      //  String orderSummary = JSON.serialize(orderSummaryData);
        System.debug('orderSummary: ' + orderSummary); // Debug the JSON string
 System.debug('productsFromCart: ' + productsFromCart); // Debug the JSON string
        // Define the visitIdSelected and orderComment
       // String visitIdSelected = 'TestVisitId';
        String orderComment = 'Test Order Comment';

        // Call the generateProposal method
        Test.startTest();
        CounterOrderProductPageController.OrderResponse response = CounterOrderProductPageController.generateProposal(productsFromCart, '', orderSummary, orderComment);
        Test.stopTest();

        // Verify the response
        System.assertEquals('Success', response.status, 'The status should be Success');
        System.assertNotEquals(null, response.ordid, 'The order ID should not be null');

        // Verify the created Order and Order Line Items
        Order__c createdOrder = [SELECT Id, Total_order_value__c, Description__c FROM Order__c WHERE Id = :response.ordid];
        System.assertEquals(330.40, createdOrder.Total_order_value__c, 'The total order value should match');
        System.assertEquals('Test Order Comment', createdOrder.Description__c, 'The order comment should match');

        List<Order_Line_Item__c> orderLineItems = [SELECT Id, Ordered_Quantity__c, Product_Price__c FROM Order_Line_Item__c WHERE Order__c = :response.ordid];
        System.assertEquals(2, orderLineItems.size(), 'There should be two order line items');
        System.assertEquals(1, orderLineItems[0].Ordered_Quantity__c, 'The ordered quantity for the first product should match');
        System.assertEquals(2, orderLineItems[1].Ordered_Quantity__c, 'The ordered quantity for the second product should match');
    }
}
       @isTest
    public static void testGetTaxRates() {
        //createTestData();
         // Create a test Order_tax_value__c record
    Order_tax_value__c taxSetting = new Order_tax_value__c(
        Name = 'General GST Settings',
        SGST__c = 9,
        IGST__c = 12,
        CGST__c = 9
    );
    insert taxSetting;
        
        // Call getTaxRates method
        Test.startTest();
        Map<String, Decimal> taxRates = CounterOrderProductPageController.getTaxRates();
        Test.stopTest();

        // Validate the result
        System.assertEquals(9.0, taxRates.get('CGST'), 'CGST rate mismatch');
        System.assertEquals(9.0, taxRates.get('SGST'), 'SGST rate mismatch');
    }

    
}