@isTest
private class SecondaryInvoiceDownloaderCtlTest {

    @testSetup
    static void setupRetailerCodeSetting() {
        List<RetailerCodeSetting__c> existing = [SELECT Id FROM RetailerCodeSetting__c WHERE Name = 'SF' LIMIT 1];
        if (existing.isEmpty()) {
            insert new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        }
    }

    @isTest
    static void testConstructor_ConfirmedInvoiceWithReimbursementLine() {
        Account distributorAcc = new Account(Name = 'Test Distributor CtlTest');
        insert distributorAcc;

        Contact distributorContact = new Contact(
            LastName  = 'TestDistContact',
            AccountId = distributorAcc.Id
        );
        insert distributorContact;

        Profile p = [SELECT Id FROM Profile WHERE Name = 'DMS Partner Community Custom' LIMIT 1];
        User distributorUser = new User(
            FirstName          = 'Test',
            LastName            = 'Distributor',
            Email               = 'testdistributor' + Math.random() + '@example.com.qatest',
            Username            = 'testdistributor' + Math.random() + '@example.com.qatest',
            Alias               = 'tdist1',
            TimeZoneSidKey      = 'Asia/Kolkata',
            LocaleSidKey        = 'en_US',
            EmailEncodingKey    = 'UTF-8',
            LanguageLocaleKey   = 'en_US',
            ProfileId           = p.Id,
            ContactId            = distributorContact.Id,
            Primary_Distributor__c   = true,
            Invoice_Number_Prefix__c = 'TST',
            Invoice_Start_Number__c  = 1
        );
        insert distributorUser;

        Id retailerRTId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId();
        Account retailerAcc = new Account(
            Name              = 'Test Retailer CtlTest',
            RecordTypeId      = retailerRTId,
            Primary_State__c  = 'Karnataka'
        );
        insert retailerAcc;

        Id secondaryInvoiceRT = Schema.SObjectType.Invoice__c.getRecordTypeInfosByDeveloperName().get('Secondary_Invoice').getRecordTypeId();
        Invoice__c inv = new Invoice__c(
            Name                   = 'TEST-INV-CTLTEST',
            Distributor_Account__c = distributorAcc.Id,
            Retailer_Account__c    = retailerAcc.Id,
            Under_SS__c            = distributorAcc.Id,   // ← forces the branch that looks up dmsUserInfo by Distributor_Account__c directly, avoiding any dependency on which user is running this test
            RecordTypeId           = secondaryInvoiceRT,
            Status__c              = 'Confirmed',
            Invoice_Date__c        = System.today()
        );
        insert inv;

        Reimbursement_Scheme_Definition__c def = new Reimbursement_Scheme_Definition__c(
            Name          = 'Test Scheme CtlTest',
            Start_Date__c = System.today().addDays(-1),
            End_Date__c   = System.today().addDays(10)
        );
        insert def;

        Retailer_Reimbursement_Scheme__c alloc = new Retailer_Reimbursement_Scheme__c(
            Account__c           = retailerAcc.Id,
            Scheme_Definition__c = def.Id,
            Balance__c            = 500
        );
        insert alloc;

        insert new Invoice_Reimbursement_Line__c(
            Invoice__c                       = inv.Id,
            Retailer_Reimbursement_Scheme__c = alloc.Id,
            Amount_Applied__c                = 200
        );

        Test.setCurrentPage(Page.SecondaryInvoiceDownloader);
        ApexPages.currentPage().getParameters().put('id', inv.Id);

        Test.startTest();
        SecondaryInvoiceDownloaderCtl controller = new SecondaryInvoiceDownloaderCtl();
        Test.stopTest();

        System.assertEquals(1, controller.invoiceWrappers.size());
        System.assertEquals(1, controller.invoiceWrappers[0].reimbursementLines.size());
        System.assertEquals(200, controller.invoiceWrappers[0].reimbursementLines[0].Amount_Applied__c);
    }

    @isTest
    static void testConstructor_NoInvoiceIdParam() {
        Test.setCurrentPage(Page.SecondaryInvoiceDownloader);

        Test.startTest();
        SecondaryInvoiceDownloaderCtl controller = new SecondaryInvoiceDownloaderCtl();
        Test.stopTest();

        System.assertEquals(0, controller.invoiceWrappers.size());
    }
}