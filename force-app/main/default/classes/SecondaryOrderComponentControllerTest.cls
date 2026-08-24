@isTest
public class SecondaryOrderComponentControllerTest {
    @isTest
    public static void test(){
        // Create a test Account
        List<Id> retailerSelected = new List<Id>();
        
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        Id distributorRecordType = [ 
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Distributor' AND SObjectType = 'Account' 
            LIMIT 1 
        ].Id;
        Account testDistributor = new Account(Name = 'Test distributor', RecordTypeId=distributorRecordType , PAN_Number__c = '248001' , Primary_State__c = 'Karnataka');
        insert testDistributor;
        
        Id retailerRecordType = [ 
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Retailer' AND SObjectType = 'Account' 
            LIMIT 1 
        ].Id;
        Account testRetailer = new Account(Name = 'Test Retailer', RecordTypeId=retailerRecordType , PAN_Number__c = '248001' , Primary_State__c = 'Karnataka' , Distributor__c = testDistributor.Id);
        insert testRetailer;
        //added by fuzail - Ensure retailer account has an OwnerId for generateProposal method
        testRetailer.OwnerId = UserInfo.getUserId();
        update testRetailer;
        retailerSelected.add(testRetailer.Id);

        // Create a test Contact associated with the Account
        Contact testContact = new Contact(LastName = 'Test Contact', AccountId = testDistributor.Id);
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
            Focus_Product__c = True,
            RecordTypeId = productRecordType,
            Primary_Product__c = true
        );
        insert testProduct;
        
        List<String> excludedProductIds=new List<String>();
        Product__c testProduct2 = new Product__c(
            Name = 'Test Product1',
            IsActive__c = true,
            Secondary_Product__c = true,
            RecordTypeId = productRecordType,
            Rate_Value__c = 100,
            Unit_of_Measure__c = 'kg',
            Product_Brand__c = 'TestBrand1',
            Focus_Product__c = True,
            Image_Long__c = 'test_image1.jpg,test_image2.jpg'
        );
        insert testProduct2;
        excludedProductIds.add(testProduct2.Id);

        Region__c region = new Region__c(
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
        insert testPriceBookEntry;
        
         // Create a test Order_tax_value__c record
        Order_tax_value__c taxSetting = new Order_tax_value__c(
            Name = 'General GST Settings',
            SGST__c = 9,
            IGST__c = 12,
            CGST__c = 9
        );
        insert taxSetting;
        
        Inventory__c inv = new Inventory__c(
            Product__c = testProduct2.Id,
            Quantity_in_hand__c = 50,
            Distributor_Name__c = testDistributor.Id
        );
        insert inv;
        
        Inventory__c inv1 = new Inventory__c(
            Product__c = testProduct.Id,
            Quantity_in_hand__c = 50,
            Distributor_Name__c = testDistributor.Id
        );
        insert inv1;
        
        System.runAs(testUser) {
            // Call the fetchProducts method
            Test.startTest();
            
            //String result = SecondaryOrderComponentController.fetchProducts('Test', 'Test Brand',retailerSelected , 'Available Stock');
            //SecondaryOrderComponentController.fetchFocusedProducts('Test', 'Test Brand',excludedProductIds , retailerSelected ,'Available Stock');
            //added by fuzail
            String result = SecondaryOrderComponentController.fetchProducts('Test', 'Test Brand',retailerSelected , 'Available Stock', 'Name');
            SecondaryOrderComponentController.fetchFocusedProducts('Test', 'Test Brand',excludedProductIds , retailerSelected ,'Available Stock', 'Name');
            //added by fuzail - Updated productsFromCart JSON to include all required fields for CartProductWrapper.ProductWrapper
            String productsFromCart = '[{"productId":"'+testProduct.Id+'","productIdForCart":"'+testProduct.Id+'Cart","productImage":"&lt;p&gt;&lt;img src=&quot;/dms/servlet/rtaImage?eid=a0JH1000005g6pO&amp;feoid=00NH100000CY6ZE&amp;refid=0EMH10000008Lkd&quot; alt=&quot;AlphonsoMango.jpg&quot;&gt;&lt;/img&gt;&lt;/p&gt;","quantity":1,"productName":"Hangyo distributor product 4","productBrand":"Family Pack","productFullName":"Hangyo distributor product 4","productListPrice":80,"productOfferPrice":80,"prodmeasure":"KG","isPromotional":false,"selectedSchemeId":null,"parentProductId":null,"discountPercentage":null},{"productId":"'+testProduct.Id+'","productIdForCart":"'+testProduct.Id+'Cart","productImage":"&lt;p&gt;&lt;img src=&quot;/dms/servlet/rtaImage?eid=a0JH1000005g6pQ&amp;feoid=00NH100000CY6ZE&amp;refid=0EMH10000008Lks&quot; alt=&quot;ButterScotchBurst.jpg&quot;&gt;&lt;/img&gt;&lt;/p&gt;","quantity":2,"productName":"Hangyo distributor product 6","productBrand":"Combos","productFullName":"Hangyo distributor product 6","productListPrice":100,"productOfferPrice":100,"prodmeasure":"E","isPromotional":false,"selectedSchemeId":null,"parentProductId":null,"discountPercentage":null}]';
            String orderSummary = '{"totalItems":2,"totalPrice":"330.40","totalDiscount":0,"totalOrderValue":280,"totalQuantity":3,"totalSGST":"25.20","totalCGST":"25.20","totalIGST":"0.00"}';
            String orderComment = 'Test Order Comment';
            SecondaryOrderComponentController.generateProposal(productsFromCart, retailerSelected, orderSummary, orderComment);
            SecondaryOrderComponentController.getTaxRates(testRetailer.Primary_State__c , testDistributor.Primary_State__c);
            Test.stopTest();

            // Verify the result
            System.assertNotEquals(null, result, 'The result should not be null');
            List<SecondaryOrderComponentController.ProductDataWrapper> productWrapperList = (List<SecondaryOrderComponentController.ProductDataWrapper>) JSON.deserialize(result, List<SecondaryOrderComponentController.ProductDataWrapper>.class);
        }
    }
}