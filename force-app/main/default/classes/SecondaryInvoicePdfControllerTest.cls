@isTest
private class SecondaryInvoicePdfControllerTest {

    @testSetup
    static void setupData() {
        // Pre-seed so GenerateRetailerCreationCode's trigger logic never
        // hits its null-latestCode edge case on ANY Account insert below.
        if (RetailerCodeSetting__c.getInstance('SF') == null) {
            insert new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 1000);
        }

        Id productRT  = [SELECT Id FROM RecordType WHERE SObjectType = 'Product__c' AND DeveloperName = 'Product' LIMIT 1].Id;
        Id retailerRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1].Id;

        Account distAcc = new Account(
            Name = 'Test Distributor Account SecPdf',
            Primary_State__c = 'Karnataka',
            BillingState = 'Karnataka',
            BillingCity = 'Bengaluru',
            BillingPostalCode = '560001',
            BillingCountry = 'India'
        );
        insert distAcc;

        Contact con = new Contact(LastName = 'TestDistContactSecPdf', AccountId = distAcc.Id);
        insert con;

        Profile pf = [SELECT Id FROM Profile WHERE Name = 'DMS Partner Community Custom' LIMIT 1];
        User dmsUser = new User(
            FirstName = 'Test',
            LastName = 'DistributorSecPdf',
            Email = 'testdistsecpdf' + DateTime.now().getTime() + '@example.com',
            Username = 'testdistsecpdf' + DateTime.now().getTime() + '@example.com',
            Alias = 'tdistsp',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = pf.Id,
            ContactId = con.Id,
            Invoice_Number_Prefix__c = 'TSP',
            Invoice_Start_Number__c = 1,
            Primary_Distributor__c = true
        );
        insert dmsUser;

        Account retailerAcc = new Account(
            Name = 'Test Retailer Account SecPdf',
            RecordTypeId = retailerRT,
            Primary_State__c = 'Karnataka'
        );
        insert retailerAcc;

        Product__c prod = new Product__c(
            Name = 'Test Secondary Product PDF',
            RecordTypeId = productRT,
            IsActive__c = true,
            Secondary_Product__c = true,
            MRP__c = 100,
            Image_Long__c = 'https://example.com/img.png',
            Unit_of_Measure__c = 'EA',
            Product_Brand__c = 'Test Brand',
            Category_Code__c = '9876',
            Category_Name__c = 'Test Category',
            Product_Code__c = '9876',
            Per_Pieces__c = 10
        );
        insert prod;

        Invoice__c invoice = new Invoice__c(
            Invoice_Number__c = 'INV-SECPDF-001',
            Invoice_Date__c = Date.today(),
            Retailer_Account__c = retailerAcc.Id,
            Distributor_Account__c = distAcc.Id,
            // InvoiceSharingTrigger (already live in Production, not in this local
            // checkout) auto-creates an Invoice__Share for partner users whose
            // AccountId matches Under_SS__c — setting this is what makes the invoice
            // actually visible to our community test user below, same as production.
            Under_SS__c = distAcc.Id,
            Invoice_Amount__c = 500.00,
            Status__c = 'Confirmed'
        );
        insert invoice;

        Invoice_Line_Item__c line = new Invoice_Line_Item__c(
            Invoice__c = invoice.Id,
            Product__c = prod.Id,
            Quantity__c = 3,
            Price__c = 100,
            Total_Amount__c = 300
        );
        insert line;
    }

    @isTest
    static void testSecondaryInvoicePdfControllerLoadsData() {
        User u = [SELECT Id FROM User WHERE Email LIKE 'testdistsecpdf%' LIMIT 1];
        Invoice__c invoice = [SELECT Id FROM Invoice__c LIMIT 1];
        Account retailerAcc = [SELECT Id FROM Account WHERE Name = 'Test Retailer Account SecPdf' LIMIT 1];
        Account distAcc = [SELECT Id FROM Account WHERE Name = 'Test Distributor Account SecPdf' LIMIT 1];

        System.runAs(u) {
            Test.startTest();
            // Explicitly establish a current page reference before touching its
            // parameters — relying on the implicit default PageReference (never set)
            // is fragile; this is the standard, reliable pattern for testing
            // Visualforce controllers that read URL parameters.
            Test.setCurrentPageReference(new PageReference('/apex/SecondaryInvoicePdf'));
            ApexPages.currentPage().getParameters().put('invoiceId', invoice.Id);
            ApexPages.currentPage().getParameters().put('distributorId', distAcc.Id);
            ApexPages.currentPage().getParameters().put('retailerId', retailerAcc.Id);

            // Diagnostic: confirm the parameter actually round-trips before blaming
            // the controller itself for the "no rows" failure.
            System.assertEquals(
                String.valueOf(invoice.Id),
                ApexPages.currentPage().getParameters().get('invoiceId'),
                'invoiceId param should round-trip through ApexPages.currentPage()'
            );

            // Diagnostic: confirm the invoice is actually queryable as this running
            // user via the exact same plain-SOQL shape the controller uses.
            List<Invoice__c> diagnosticCheck = [SELECT Id, Under_SS__c FROM Invoice__c WHERE Id = :invoice.Id];
            System.assertEquals(1, diagnosticCheck.size(), 'The seeded invoice should be queryable as this user via plain SOQL.');

            SecondaryInvoicePdfController controller = new SecondaryInvoicePdfController();
            Test.stopTest();

            System.assertNotEquals(null, controller.dmsUserInfo, 'Should resolve the primary distributor user.');
            System.assertNotEquals(null, controller.invLineItem, 'Should load line items for the invoice.');
            System.assertEquals(30, controller.totalUnit, '3 boxes at 10 pieces each should total 30 pieces, not 3.');
        }
    }

    @isTest
    static void testGeneratePDFCreatesContentVersionAndLink() {
        // Not wrapped in System.runAs() — generatePDF() takes all its inputs as
        // explicit parameters (no UserInfo.getUserId()/AccountId lookups like the
        // rest of this class), so there's no reason to run it as the restricted
        // portal user, and doing so hit Salesforce's stricter Files/Content sharing
        // model for Community users instead of testing the method's actual logic.
        Invoice__c invoice = [SELECT Id, Invoice_Number__c FROM Invoice__c LIMIT 1];
        Account distAcc = [SELECT Id FROM Account WHERE Name = 'Test Distributor Account SecPdf' LIMIT 1];
        Account retailerAcc = [SELECT Id FROM Account WHERE Name = 'Test Retailer Account SecPdf' LIMIT 1];

        Test.startTest();
        String contentVersionId = SecondaryInvoicePdfController.generatePDF(invoice, distAcc.Id, retailerAcc.Id);
        Test.stopTest();

        System.assertNotEquals(null, contentVersionId, 'Should return the new ContentVersion Id.');
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :invoice.Id];
        System.assertEquals(1, links.size(), 'Should attach exactly one ContentDocumentLink to the invoice.');
    }

    @isTest
    static void testGeneratePDFReplacesExistingContentDocument() {
        Invoice__c invoice = [SELECT Id, Invoice_Number__c FROM Invoice__c LIMIT 1];
        Account distAcc = [SELECT Id FROM Account WHERE Name = 'Test Distributor Account SecPdf' LIMIT 1];
        Account retailerAcc = [SELECT Id FROM Account WHERE Name = 'Test Retailer Account SecPdf' LIMIT 1];

        // Generate once so a ContentDocument already exists, then generate again to
        // exercise the "delete the old one before attaching the new one" branch.
        SecondaryInvoicePdfController.generatePDF(invoice, distAcc.Id, retailerAcc.Id);

        Test.startTest();
        String secondContentVersionId = SecondaryInvoicePdfController.generatePDF(invoice, distAcc.Id, retailerAcc.Id);
        Test.stopTest();

        System.assertNotEquals(null, secondContentVersionId);
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :invoice.Id];
        System.assertEquals(1, links.size(), 'Old ContentDocument should be deleted and replaced with exactly one new link, not two.');
    }
}