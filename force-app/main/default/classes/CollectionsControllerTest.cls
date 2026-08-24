@isTest
public class CollectionsControllerTest {

    @isTest
    static void testGetRetailersOptions() {
        // Set up test data
        Id disRecId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId();
        Account distributor = new Account(Name = 'Distributor', recordtypeId = disRecId);
        insert distributor;
		Contact contact = new Contact(FirstName = 'Test', LastName = 'User', AccountId = distributor.Id);
        insert contact;
        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'hangyouser@example.com',
            Username = 'testuserMystery@example.com.salesforce',
            Alias = 'testusr',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ContactId = contact.Id,
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'DMS Partner Community Custom' LIMIT 1].Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser;
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
        
        // Insert the custom setting
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        Account retailer = new Account(Name = 'Retailer', Distributor__c = distributor.Id);
        insert retailer;
		
        System.runAs(testUser) {
        // Test the method
        Test.startTest();
        List<Account> retailers = CollectionsController.getretailersOptions();
        Test.stopTest();

        // Assert results
        System.assertEquals(1, retailers.size(), 'There should be 1 retailer returned');
        System.assertEquals('Retailer', retailers[0].Name, 'The retailer name should be "Retailer"');
        }
    }

    @isTest
    static void testGetDeliveredInvoices() {
        // Set up test data
        Id disRecId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId();
        Account distributor = new Account(Name = 'Distributor', recordtypeId = disRecId);
        insert distributor;
		Contact contact = new Contact(FirstName = 'Test', LastName = 'User', AccountId = distributor.Id);
        insert contact;
        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'hangyouser@example.com',
            Username = 'hangyouser@example.com.salesforce',
            Alias = 'testusr',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ContactId = contact.Id,
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'DMS Partner Community Custom' LIMIT 1].Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser;
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
		
        Id retailerRecId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId();
        
        // Insert the custom setting
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        Account retailer = new Account(Name = 'Retailer', Distributor__c = distributor.Id, recordtypeid = retailerRecId);
        insert retailer;
		
        Id secondaryInvoiceRecordTypeId = Schema.SObjectType.Invoice__c.getRecordTypeInfosByName().get('Secondary Invoice').getRecordTypeId();
        
        Invoice__c invoice = new Invoice__c(
            Invoice_Number__c = 'INV001',
            recordtypeId = secondaryInvoiceRecordTypeId,
            Distributor_Account__c = distributor.Id,
            Retailer_Account__c = retailer.Id,
            Status__c = 'Delivered',
            Invoice_Amount__c = 100.00,
            Invoice_Date__c = Date.today()
        );
        insert invoice;
		System.runAs(testUser) {
        // Test the method
        Test.startTest();
        List<Invoice__c> invoices = CollectionsController.getDeliveredInvoices(retailer.Id);
        Test.stopTest();

        // Assert results
        //System.assertEquals(1, invoices.size(), 'There should be 1 invoice returned');
        //System.assertEquals('INV001', invoices[0].Invoice_Number__c, 'The invoice number should be "INV001"');
        }
    }

    @isTest
    static void testValidCreditNotes() {
        // Set up test data
        Id disRecId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId();
        Account distributor = new Account(Name = 'Distributor', recordtypeId = disRecId);
        insert distributor;
		Contact contact = new Contact(FirstName = 'Test', LastName = 'User', AccountId = distributor.Id);
        insert contact;
        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'hangyouser@example.com',
            Username = 'hangyouser@example.com.salesforce',
            Alias = 'testusr',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ContactId = contact.Id,
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'DMS Partner Community Custom' LIMIT 1].Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser;
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
        
        // Insert the custom setting
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;

        Account retailer = new Account(Name = 'Retailer', Distributor__c = distributor.Id);
        insert retailer;

        Credit_Note__c creditNote = new Credit_Note__c(
            Retailer__c = retailer.Id,
            Total_Credit_amount__c = 100.00,
            Status__c = 'Active'
        );
        insert creditNote;

        // Test the method
        Test.startTest();
        List<Credit_Note__c> creditNotes = CollectionsController.validCreditNotes(retailer.Id);
        Test.stopTest();

        // Assert results
        System.assertEquals(1, creditNotes.size(), 'There should be 1 credit note returned');
        System.assertEquals('Active', creditNotes[0].Status__c, 'The credit note status should be "Open"');
    }

    
    
    @isTest
    static void testSaveInvoiceCollection() {
        // Set up test data
        Id disRecId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId();
        Account distributor = new Account(Name = 'Distributor', recordtypeId = disRecId);
        insert distributor;
		Contact contact = new Contact(FirstName = 'Test', LastName = 'User', AccountId = distributor.Id);
        insert contact;
        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@example.com',
            Username = 'hangyouser@example.com.salesforce',
            Alias = 'testusr',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ContactId = contact.Id,
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'DMS Partner Community Custom' LIMIT 1].Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser;
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
        
        // Insert the custom setting
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;

        Account retailer = new Account(Name = 'Retailer', Distributor__c = distributor.Id);
        insert retailer;

        Invoice__c invoice = new Invoice__c(
            Invoice_Number__c = 'INV001',
            Distributor_Account__c = distributor.Id,
            Retailer_Account__c = retailer.Id,
            Status__c = 'Delivered',
            Invoice_Amount__c = 100.00,
            Invoice_Date__c = Date.today()
        );
        insert invoice;

        Credit_Note__c creditNote = new Credit_Note__c(
            Retailer__c = retailer.Id,
            Total_Credit_amount__c = 50.00,
            Status__c = 'Active'
        );
        insert creditNote;

        // Prepare collection data
        List<CollectionsController.CollectionDataWrapper> collectionData = new List<CollectionsController.CollectionDataWrapper>();
        CollectionsController.CollectionDataWrapper data = new CollectionsController.CollectionDataWrapper();
        data.invoiceId = invoice.Id;
        data.amountCollected = 50.00;
        data.payableBalance = 50.00;
        collectionData.add(data);

        Map<String, Object> chequeData = new Map<String, Object>();
        chequeData.put('chequeNumber', 'CH12345');
        chequeData.put('chequeDate', '2025-01-28');
        chequeData.put('branchName', 'Test Branch');
        chequeData.put('isChequeCleared', false);

        // Test the method
        Test.startTest();
        CollectionsController.getInvoiceStatus(invoice.Id);
        CollectionsController.saveInvoiceCollection(invoice.Id,50, retailer.Id, 'Cash', Date.today(), 50.00, chequeData , 'test');
        Test.stopTest();

        // Assert results
        List<Collection__c> collections = [SELECT Id, Invoice__c, Amount_Collected__c, Credit_Amount_Used__c FROM Collection__c];
        System.assertEquals(1, collections.size(), 'There should be 1 collection record');
        System.assertEquals(50.00, collections[0].Amount_Collected__c, 'The amount collected should be 50');
        System.assertEquals(50.00, collections[0].Credit_Amount_Used__c, 'The credit amount used should be 50');
    }
}