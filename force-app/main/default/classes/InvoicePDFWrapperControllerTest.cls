@isTest
public class InvoicePDFWrapperControllerTest {

    @isTest
    static void testInvoiceWithDraftStatus() {
        // Create a draft invoice
        Invoice__c draftInvoice = new Invoice__c(Name = 'Draft Invoice', Status__c = 'Draft');
        insert draftInvoice;

        // Set page and parameter
        Test.setCurrentPage(Page.SecondaryInvoiceDownloader);
        ApexPages.currentPage().getParameters().put('id', draftInvoice.Id);

        Test.startTest();
        InvoicePDFWrapperController controller = new InvoicePDFWrapperController();
        Test.stopTest();

        // Assertions
        System.assertEquals('Draft Invoice', controller.invoiceName);
        System.assertEquals(true, controller.shouldRedirect);
        System.assertEquals('/' + draftInvoice.Id, controller.redirectUrl);
        System.assertEquals(null, controller.pdfBase64); // PDF not generated for Draft
    }

    @isTest
    static void testInvoiceWithConfirmedStatus() {
        // Create a confirmed invoice
        Invoice__c confirmedInvoice = new Invoice__c(Name = 'Confirmed Invoice', Status__c = 'Confirmed');
        insert confirmedInvoice;

        // Set page and parameter
        Test.setCurrentPage(Page.SecondaryInvoiceDownloader);
        ApexPages.currentPage().getParameters().put('id', confirmedInvoice.Id);

        Test.startTest();
        InvoicePDFWrapperController controller = new InvoicePDFWrapperController();
        Test.stopTest();

        // Assertions
        System.assertEquals('Confirmed Invoice', controller.invoiceName);
        System.assertNotEquals(null, controller.pdfBase64); // Should be "TEST_BASE64_STRING" in test context
        System.assertEquals('TEST_BASE64_STRING', controller.pdfBase64);
    }
}