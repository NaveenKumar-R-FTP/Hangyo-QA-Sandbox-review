public class DownloadInvoiceController {
    
    @AuraEnabled
    public static String invoiceData(String invoiceId) {
        Invoice__c invoice = [
            SELECT Id, Status__c, Origin__c, OwnerId
            FROM Invoice__c
            WHERE Id = :invoiceId
            LIMIT 1
        ];

        if (invoice.Status__c == 'Draft') {
            // Some distributors (flagged via User.Draft_Invoice_Download__c on the
            // invoice's owner) are allowed to download an invoice even while it's still
            // Draft — same bypass InvoicePDFWrapperController already honors. Without
            // this check, every Draft invoice was blocked here for everyone, with no way
            // for those specific users to get through.
            User ownerUser = [
                SELECT Id, Draft_Invoice_Download__c
                FROM User
                WHERE Id = :invoice.OwnerId
                LIMIT 1
            ];
            if (!ownerUser.Draft_Invoice_Download__c) {
                return 'Draft';
            }
        }

        if (invoice.Origin__c == 'Counter Invoice') {
            return 'CounterInvoice';
        } else {
            return 'Success';
        }
    }
}