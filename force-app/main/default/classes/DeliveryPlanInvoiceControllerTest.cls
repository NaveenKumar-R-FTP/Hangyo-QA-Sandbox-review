@isTest
private class DeliveryPlanInvoiceControllerTest {

    @testSetup
    static void setupTestData() {
        // Insert the custom setting
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        // Create a test Account
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
        
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
            Image__c = 'test_image1.jpg,test_image2.jpg',
            MRP__c = 10
        );
        insert testProduct;
        Scheme__c valueScheme;
        List<RecordType> valueSchemeRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Value_scheme' AND SObjectType = 'Scheme__c' LIMIT 1];
        if (!valueSchemeRT.isEmpty()) {
            valueScheme = new Scheme__c(
                Name = 'Test Value Scheme',
                RecordTypeId = valueSchemeRT[0].Id,
                Scheme_Start_Date__c = Date.today().addDays(-1),
                Scheme_End_Date__c = Date.today().addDays(30),
                Cart_Amount__c = 100,
                Discount_Percentage__c = 10
            );
            insert valueScheme;
        }

        // Create a test Invoice
        Invoice__c testInvoice = new Invoice__c(
            Invoice_Number__c = 'INV-001',
            Invoice_Date__c = Date.today(),
            Retailer_Account__c = testAccount.Id,
            Invoice_Amount__c = 1000.00,
            Value_Scheme_Applied__c = valueScheme.Id
        );
        insert testInvoice;

        // Create test Invoice Line Items
        Invoice_Line_Item__c testLineItem = new Invoice_Line_Item__c(
            Invoice__c = testInvoice.Id,
            Product__c = testProduct.Id, // Replace with a valid Product Id
            Quantity__c = 10,
            Price__c = 100.00,
            Total_Amount__c = 1000.00
        );
        insert testLineItem;
        
         /* ---------------- Delivery Plan ---------------- */
        Delivery_Plan__c plan = new Delivery_Plan__c(
            Driver_Name__c = 'Test Driver',
            Vehicle_Number__c = 'KA100'
        );
        insert plan;
        
        /* ---------------- Delivery Plan Item ---------------- */
        Delivery_Plan_Items__c planItem = new Delivery_Plan_Items__c(
            Delivery_Plan__c = plan.Id,
            Invoices__c = testInvoice.Id
        );
        insert planItem;
    }

    @isTest
    static void testController() {
        // Set up the test context for a Visualforce page
        Test.startTest();
        
        // Mock page parameter
        ApexPages.currentPage().getParameters().put('id', [SELECT Id FROM Delivery_Plan__c LIMIT 1].Id);
        ApexPages.currentPage().getParameters().put('deliveryPlanId', [SELECT Id FROM Delivery_Plan__c LIMIT 1].Id);
        ApexPages.currentPage().getParameters().put('distributorId', [SELECT Id FROM User LIMIT 1].Id);
        ApexPages.currentPage().getParameters().put('retailerId', [SELECT Id FROM Account LIMIT 1].Id);
        
        Invoice__c invoiceObj = [SELECT Id,Invoice_Number__c FROM Invoice__c LIMIT 1];
        Id disId = [SELECT Id FROM User LIMIT 1].Id;
        Id retailerId = [SELECT Id FROM Account LIMIT 1].Id;
        Delivery_Plan__c DeliverPlanObj = [SELECT Id,Name FROM Delivery_Plan__c LIMIT 1];
        
        // Instantiate controller
        DeliveryPlanInvoiceController controller = new DeliveryPlanInvoiceController();
        Test.stopTest();
    }
}