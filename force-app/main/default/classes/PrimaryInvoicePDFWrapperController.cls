//created by Fuzail 
public class PrimaryInvoicePDFWrapperController {

    public String pdfBase64 { get; private set; }
    public String invoiceName { get; private set; }
    public Boolean shouldRedirect { get; private set; }
    public String redirectUrl { get; private set; }

    public PrimaryInvoicePDFWrapperController() {

        Id recordId = ApexPages.currentPage().getParameters().get('id');
        System.debug('recordId:- ' + recordId);
        
        Invoice__c invoice;

        if(recordId != null){
            invoice = [
                SELECT Id , Name, Status__c, OwnerId,Distributor_Account__r.Id
                FROM Invoice__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            invoiceName = invoice.Name != null ? invoice.Name : 'Invoice';

            User ownerUser = [
                SELECT Draft_Invoice_Download__c
                FROM User
                WHERE Id = :invoice.OwnerId
                LIMIT 1
            ];
    
            if (invoice.Status__c == 'Draft' && !ownerUser.Draft_Invoice_Download__c) {
                shouldRedirect = true;
                redirectUrl = '/' + recordId;
                return;
            }
    
            PageReference pdfPage = Page.PrimaryInvoiceDownloaderVF;
            pdfPage.getParameters().put('id', recordId);
    
            if (!Test.isRunningTest()) {
                Blob pdfBlob = pdfPage.getContent();
                pdfBase64 = EncodingUtil.base64Encode(pdfBlob);
            } else {
                pdfBase64 = 'TEST_BASE64_STRING';
            }
       }      
    }
}