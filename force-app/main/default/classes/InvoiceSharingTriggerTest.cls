@isTest
private class InvoiceSharingTriggerTest {
    
    @testSetup
    static void setupTestData() {
        // Create test Account
        Id disRecId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId();
        Account distributor = new Account(Name = 'Distributor', RecordTypeId = disRecId, PAN_Number__c='1344');
        insert distributor;

        // Create Contact
        Contact contact = new Contact(FirstName = 'Test', LastName = 'User', AccountId = distributor.Id);
        insert contact;

        // Create Test User
        Profile partnerProfile = [SELECT Id FROM Profile WHERE Name = 'DMS Partner Community Custom' LIMIT 1];
        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@example.com',
            Username = 'testusermystery@example.com.salesforce',
            Alias = 'testusr',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ContactId = contact.Id,
            ProfileId = partnerProfile.Id,
            LanguageLocaleKey = 'en_US',
            Invoice_Number_Prefix__c='123',
            Invoice_Start_Number__c = 123,
            Primary_Distributor__c = true,
            State = 'Karnataka'
            
        );
        insert testUser;

        // Create Product
        Id productRecordTypeId = [SELECT Id FROM RecordType WHERE DeveloperName = 'Product' AND SObjectType = 'Product__c' LIMIT 1].Id;
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
        
        // Create Retailer Account
        Id retailerRecId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId();
        Account retailer = new Account(Name = 'Retailer', Distributor__c = distributor.Id, RecordTypeId = retailerRecId,Primary_State__c='Karnataka',PAN_Number__c='1344');
        insert retailer;
		
        RecordType secondaryOrderRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Secondary_Order' AND SObjectType = 'Order__c' LIMIT 1];
        // Create Test Order
        Order__c testOrder = new Order__c(Account__c = retailer.Id,AccountId__c =distributor.ID,RecordTypeId = secondaryOrderRT.Id );
        insert testOrder;

        // Create Test Order Line Items
        List<Order_Line_Item__c> orderItems = new List<Order_Line_Item__c>();
        for (Integer i = 0; i < 3; i++) {
            orderItems.add(new Order_Line_Item__c(Order__c = testOrder.Id,Products__c =testProduct.Id,Ordered_Quantity__c =10,Product_Price__c=10));
        }
        insert orderItems;
        
        Invoice__c invoice1 = new Invoice__c(
            Invoice_Number__c = '111',
            Distributor_Account__c = distributor.Id,
            Status__c = 'Confirmed'
        );
        Invoice__c invoice2 = new Invoice__c(
            Invoice_Number__c = '000',
            Distributor_Account__c = distributor.Id,
            Status__c = 'Confirmed'
        );
        insert new List<Invoice__c>{ invoice1, invoice2 };
            
            Invoice_Line_Item__c testLineItem = new Invoice_Line_Item__c(
            Invoice__c = invoice1.Id,
            Product__c = testProduct.Id, // Replace with a valid Product Id
            Quantity__c = 10,
            Price__c = 100.00,
            Total_Amount__c = 1000.00
        );
        insert testLineItem;
        
        
        Order_Tax_Value__c taxSetting = new Order_Tax_Value__c(
            Name = 'Karnataka', // Name is mandatory for List Custom Settings
            CGST__c = 9.0,   // Example tax percentages
            SGST__c = 9.0,
            IGST__c = 18.0
        );
        insert taxSetting;
    }

    @isTest
    static void testInvoiceSharing() {
        // Get the test Account and Partner User
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Distributor' LIMIT 1];
        User partnerUser = [SELECT Id FROM User WHERE AccountId = :testAccount.Id AND IsPartner = TRUE LIMIT 1];

        // Create an Invoice associated with the Account
        Invoice__c testInvoice = new Invoice__c(Name = 'Test Invoice', Under_SS__c = testAccount.Id);
        insert testInvoice;

        // Verify that the sharing record was created
        Test.startTest();
        List<Invoice__Share> shares = [SELECT Id, UserOrGroupId, AccessLevel FROM Invoice__Share WHERE ParentId = :testInvoice.Id];
        Test.stopTest();

        // Assertions
        System.assertEquals(1, shares.size(), 'One sharing record should be created');
        System.assertEquals(partnerUser.Id, shares[0].UserOrGroupId, 'Invoice should be shared with the Partner User');
        System.assertEquals('Read', shares[0].AccessLevel, 'Sharing access should be Read');
    }
}