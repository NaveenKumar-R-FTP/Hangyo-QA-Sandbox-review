@isTest
private class DownloadInvoiceControllerTest {

    // Any Account not using the Retailer record type — avoids triggering
    // GenerateRetailerCreationCode via AccountTrigger, which NPEs when there's no
    // RetailerCodeSetting__c / existing Retailer accounts in an isolated test context.
    // Not relevant to what's being tested here; DownloadInvoiceController only needs a
    // valid Account for the Invoice__c.Retailer_Account__c lookup.
    private static Id nonRetailerRecordTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId();
    }

    @isTest
    static void testDraftInvoiceReturnsDraft() {
        Account testAccount = new Account(Name = 'Test Account Draft', RecordTypeId = nonRetailerRecordTypeId());
        insert testAccount;

        Invoice__c invoice = new Invoice__c(
            Invoice_Number__c = 'INV-DRAFT-001',
            Invoice_Date__c = Date.today(),
            Retailer_Account__c = testAccount.Id,
            Invoice_Amount__c = 500.00,
            Status__c = 'Draft'
        );
        insert invoice;

        Test.startTest();
        String result = DownloadInvoiceController.invoiceData(invoice.Id);
        Test.stopTest();

        System.assertEquals('Draft', result, 'A Draft invoice should return Draft regardless of Origin__c.');
    }

    @isTest
    static void testDraftInvoiceWithOwnerBypassFlagReturnsNonDraft() {
        Account testAccount = new Account(Name = 'Test Account Draft Bypass', RecordTypeId = nonRetailerRecordTypeId());
        insert testAccount;

        // Whoever owns this invoice has the Draft_Invoice_Download__c override checked,
        // so the Draft block should be bypassed for it — mirrors the same flag
        // InvoicePDFWrapperController already honors for specific distributors.
        User currentUser = [SELECT Id, Draft_Invoice_Download__c FROM User WHERE Id = :UserInfo.getUserId()];
        currentUser.Draft_Invoice_Download__c = true;
        update currentUser;

        Invoice__c invoice = new Invoice__c(
            Invoice_Number__c = 'INV-DRAFT-BYPASS-001',
            Invoice_Date__c = Date.today(),
            Retailer_Account__c = testAccount.Id,
            Invoice_Amount__c = 500.00,
            Status__c = 'Draft',
            OwnerId = UserInfo.getUserId()
        );
        insert invoice;

        Test.startTest();
        String result = DownloadInvoiceController.invoiceData(invoice.Id);
        Test.stopTest();

        System.assertNotEquals('Draft', result, 'A Draft invoice owned by a user with Draft_Invoice_Download__c=true should bypass the Draft block.');
    }

    @isTest
    static void testConfirmedCounterInvoiceReturnsCounterInvoice() {
        Account testAccount = new Account(Name = 'Test Account Counter', RecordTypeId = nonRetailerRecordTypeId());
        insert testAccount;

        Invoice__c invoice = new Invoice__c(
            Invoice_Number__c = 'INV-CTR-001',
            Invoice_Date__c = Date.today(),
            Retailer_Account__c = testAccount.Id,
            Invoice_Amount__c = 750.00,
            Status__c = 'Confirmed',
            Origin__c = 'Counter Invoice'
        );
        insert invoice;

        Test.startTest();
        String result = DownloadInvoiceController.invoiceData(invoice.Id);
        Test.stopTest();

        System.assertEquals('CounterInvoice', result, 'A non-Draft invoice with Origin__c = Counter Invoice should return CounterInvoice.');
    }

    @isTest
    static void testConfirmedNonCounterInvoiceReturnsSuccess() {
        Account testAccount = new Account(Name = 'Test Account Success', RecordTypeId = nonRetailerRecordTypeId());
        insert testAccount;

        Invoice__c invoice = new Invoice__c(
            Invoice_Number__c = 'INV-SUC-001',
            Invoice_Date__c = Date.today(),
            Retailer_Account__c = testAccount.Id,
            Invoice_Amount__c = 1000.00,
            Status__c = 'Confirmed',
            Origin__c = 'Secondary Invoice'
        );
        insert invoice;

        Test.startTest();
        String result = DownloadInvoiceController.invoiceData(invoice.Id);
        Test.stopTest();

        System.assertEquals('Success', result, 'A non-Draft invoice with any other Origin__c should return Success.');
    }
}