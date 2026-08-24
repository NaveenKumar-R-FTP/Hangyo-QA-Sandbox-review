public class InvoicePDFWrapperController {

    public String pdfBase64 { get; private set; }
    public String invoiceName { get; private set; }
    public Boolean shouldRedirect { get; private set; }
    public String redirectUrl { get; private set; } 
    public InvoicePDFWrapperController() {
        Id recordId = ApexPages.currentPage().getParameters().get('id'); 
        Invoice__c invoice = [SELECT Name, Status__c , RecordType.Name , OwnerId FROM Invoice__c WHERE Id = :recordId LIMIT 1];
        invoiceName = invoice.Name != null ? invoice.Name : 'Invoice';
        User ownerUser = [SELECT Id , Draft_Invoice_Download__c FROM User WHERE Id = :invoice.OwnerId LIMIT 1];
 
        if (invoice.Status__c == 'Draft' && !ownerUser.Draft_Invoice_Download__c) {
            shouldRedirect = true; 
            // Construct the standard detail page URL
            redirectUrl = '/' + recordId;
            return;
        }
        
        PageReference pdfPage;
        if(invoice.RecordType.Name == 'Secondary Invoice'){
            pdfPage = Page.SecondaryInvoiceDownloader;
            pdfPage.getParameters().put('id', recordId);
        }else if(invoice.RecordType.Name == 'Secondary Invoice Under SS'){
            pdfPage = Page.SecondaryUnderSsInvoiceDownloader;
            pdfPage.getParameters().put('id', recordId);
        }
        
        if (!Test.isRunningTest()) {
            Blob pdfBlob = pdfPage.getContent();
            pdfBase64 = EncodingUtil.base64Encode(pdfBlob);
        } else {
            pdfBase64 = 'TEST_BASE64_STRING';
        }
    }
}