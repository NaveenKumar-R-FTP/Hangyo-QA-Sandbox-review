@isTest
private class PrimaryInvoicePDFWrapperControllerTest {

    @testSetup
    static void setupData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        // Create Account (Distributor)
        Account acc = new Account(Name = 'Test Distributor');
        insert acc;

        // Create two users:
        // 1. User without draft download permission
        // 2. User with draft download permission

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User userNoPermission = new User(
            FirstName = 'No',
            LastName = 'Permission',
            Email = 'nopermission@test.com',
            Username = 'nopermission' + System.currentTimeMillis() + '@test.com',
            Alias = 'noperm',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            LanguageLocaleKey = 'en_US',
            Draft_Invoice_Download__c = false
        );

        User userWithPermission = new User(
            FirstName = 'With',
            LastName = 'Permission',
            Email = 'withpermission@test.com',
            Username = 'withpermission' + System.currentTimeMillis() + '@test.com',
            Alias = 'wperm',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            LanguageLocaleKey = 'en_US',
            Draft_Invoice_Download__c = true
        );

        insert new List<User>{ userNoPermission, userWithPermission };

        // Draft Invoice (Owned by user WITHOUT permission)
        Invoice__c draftInvoice = new Invoice__c(
            Name = 'Draft Invoice',
            Status__c = 'Draft',
            OwnerId = userNoPermission.Id,
            Distributor_Account__c = acc.Id
        );
        insert draftInvoice;

        // Approved Invoice (Owned by user WITH permission)
        Invoice__c approvedInvoice = new Invoice__c(
            Name = 'Approved Invoice',
            Status__c = 'Confirmed',
            OwnerId = userWithPermission.Id,
            Distributor_Account__c = acc.Id
        );
        insert approvedInvoice;
    }


    // ✅ Test redirect logic (Draft + No Permission)
    @isTest
    static void testDraftInvoiceRedirect() {

        Invoice__c draftInvoice = [
            SELECT Id FROM Invoice__c WHERE Status__c = 'Draft' LIMIT 1
        ];

        Test.startTest();

        ApexPages.currentPage().getParameters().put('id', draftInvoice.Id);

        PrimaryInvoicePDFWrapperController controller =
            new PrimaryInvoicePDFWrapperController();

        Test.stopTest();

        System.assertEquals(true, controller.shouldRedirect);
        System.assertEquals('/' + draftInvoice.Id, controller.redirectUrl);
        System.assertEquals(null, controller.pdfBase64);
    }


    // ✅ Test PDF generation logic (Non-Draft)
    @isTest
    static void testApprovedInvoicePDFGeneration() {

        Invoice__c approvedInvoice = [
            SELECT Id FROM Invoice__c WHERE Status__c = 'Confirmed' LIMIT 1
        ];

        Test.startTest();

        ApexPages.currentPage().getParameters().put('id', approvedInvoice.Id);

        PrimaryInvoicePDFWrapperController controller =
            new PrimaryInvoicePDFWrapperController();

        Test.stopTest();
    }


    // ✅ Test Draft but user HAS permission
    @isTest
    static void testDraftInvoiceWithPermission() {

        User userWithPermission = [
            SELECT Id FROM User WHERE Draft_Invoice_Download__c = true LIMIT 1
        ];

        Account acc = [SELECT Id FROM Account LIMIT 1];

        Invoice__c draftAllowed = new Invoice__c(
            Name = 'Draft Allowed',
            Status__c = 'Draft',
            OwnerId = userWithPermission.Id,
            Distributor_Account__c = acc.Id
        );
        insert draftAllowed;

        Test.startTest();

        ApexPages.currentPage().getParameters().put('id', draftAllowed.Id);

        PrimaryInvoicePDFWrapperController controller =
            new PrimaryInvoicePDFWrapperController();

        Test.stopTest();

    }
}