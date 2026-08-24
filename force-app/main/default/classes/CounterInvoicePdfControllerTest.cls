@isTest
private class CounterInvoicePdfControllerTest {

    @testSetup
    static void setupData() {
        // Pre-seed so GenerateRetailerCreationCode's trigger logic never
        // hits its null-latestCode edge case on ANY Account insert below.
        if (RetailerCodeSetting__c.getInstance('SF') == null) {
            insert new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 1000);
        }

        Id productRT     = [SELECT Id FROM RecordType WHERE SObjectType = 'Product__c' AND DeveloperName = 'Product' LIMIT 1].Id;
        Id retailerRT    = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1].Id;
        Id counterOrdRT  = [SELECT Id FROM RecordType WHERE SObjectType = 'Order__c' AND Name = 'Counter Order' LIMIT 1].Id;
        Id counterLineRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Order_Line_Item__c' AND Name = 'Counter Order Line Item' LIMIT 1].Id;

        Account distAcc = new Account(
            Name = 'Test Distributor Account PDF',
            Primary_State__c = 'Karnataka',
            BillingState = 'Karnataka',
            BillingCity = 'Bengaluru',
            BillingPostalCode = '560001',
            BillingCountry = 'India'
        );
        insert distAcc;

        Contact con = new Contact(LastName = 'TestDistContactPDF', AccountId = distAcc.Id);
        insert con;

        Profile pf = [SELECT Id FROM Profile WHERE Name = 'DMS Partner Community Custom' LIMIT 1];
        User dmsUser = new User(
            FirstName = 'Test',
            LastName = 'DistributorPDF',
            Email = 'testdistpdf' + DateTime.now().getTime() + '@example.com',
            Username = 'testdistpdf' + DateTime.now().getTime() + '@example.com',
            Alias = 'tdistpdf',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = pf.Id,
            ContactId = con.Id,
            Invoice_Number_Prefix__c = 'TCP',
            Invoice_Start_Number__c = 1,
            Primary_Distributor__c = true
        );
        insert dmsUser;

        Account counterCustomer = new Account(
            Name = 'Counter Sales Customer PDF',
            RecordTypeId = retailerRT,
            Primary_State__c = 'Karnataka'
        );
        insert counterCustomer;

        Product__c prod = new Product__c(
            Name = 'Test Counter Product PDF',
            RecordTypeId = productRT,
            IsActive__c = true,
            Secondary_Product__c = true,
            MRP__c = 100,
            Image_Long__c = 'https://example.com/img.png',
            Unit_of_Measure__c = 'EA',
            Product_Brand__c = 'Test Brand',
            Category_Code__c = '5678',
            Category_Name__c = 'Test Category',
            Product_Code__c = '5678',
            Per_Pieces__c = 12
        );
        insert prod;

        Region__c region = new Region__c(Name = 'Karnataka');
        insert region;

        Price_Book_Entry__c pbe = new Price_Book_Entry__c(
            Product__c = prod.Id,
            Region__c = region.Id,
            Type__c = 'Retailer',
            PTR__c = 80,
            isActive__c = true
        );
        insert pbe;

        Order_tax_value__c tax = new Order_tax_value__c(
            Name = 'General GST Settings',
            CGST__c = 9,
            SGST__c = 9,
            IGST__c = 18
        );
        insert tax;

        Inventory__c inv = new Inventory__c(
            Product__c = prod.Id,
            Distributor_Name__c = distAcc.Id,
            Quantity_in_hand__c = 50
        );
        insert inv;

        Order__c order = new Order__c(
            Account__c = counterCustomer.Id,
            AccountId__c = distAcc.Id,
            Ordered_By__c = dmsUser.Id,
            EffectiveDate__c = System.today(),
            Status__c = 'Order Placed',
            Type__c = 'Counter Order',
            RecordTypeId = counterOrdRT,
            Customer_Name__c = 'Walk In Customer',
            Customer_Phone__c = '9999999999',
            State__c = 'Karnataka',
            Country__c = 'India',
            Description__c = 'Type: Cash Sales | Price: MRP'
        );
        insert order;

        Order_Line_Item__c line = new Order_Line_Item__c(
            Order__c = order.Id,
            RecordTypeId = counterLineRT,
            Products__c = prod.Id,
            Ordered_Quantity__c = 2,
            Product_Price__c = 100
        );
        insert line;
    }

    @isTest
    static void testCounterInvoicePdfControllerLoadsWrappers() {
        User u = [SELECT Id FROM User WHERE Email LIKE 'testdistpdf%' LIMIT 1];
        Id invoiceId;

        System.runAs(u) {
            Order__c order = [SELECT Id FROM Order__c LIMIT 1];

            CounterInvoiceController.InvoiceResponse invResp =
                CounterInvoiceController.createCounterInvoice(order.Id);
            System.assertEquals('Success', invResp.status);
            invoiceId = invResp.invoiceId;
        }

        System.runAs(u) {
            Test.startTest();
            ApexPages.currentPage().getParameters().put('id', invoiceId);
            CounterInvoicePdfController controller = new CounterInvoicePdfController();
            Test.stopTest();

            System.assertEquals(1, controller.invoiceWrappers.size(), 'Should load exactly one invoice wrapper for the given id.');
            System.assertNotEquals(null, controller.dmsUserInfo, 'Should resolve the primary distributor user for the PDF header.');
            System.assertNotEquals(null, controller.invoiceWrappers[0].invoiceLineItems, 'Should load line items for the invoice.');
        }
    }

    @isTest
    static void testCounterInvoicePdfControllerWithNoIdDoesNothing() {
        Test.startTest();
        CounterInvoicePdfController controller = new CounterInvoicePdfController();
        Test.stopTest();

        System.assert(controller.invoiceWrappers.isEmpty(), 'With no id parameter, no wrappers should be loaded.');
    }
}