public class UpdatePrimaryInvoiceBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Billing_Date__c, Invoice_Total__c
            FROM Invoice__c
            WHERE RecordType.DeveloperName = 'Primary_Invoice'
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Invoice__c> invoices) {
        for (Invoice__c inv : invoices) {
            inv.Invoice_Date__c = inv.Billing_Date__c;
            inv.Invoice_Amount__c = inv.Invoice_Total__c;
        }
        update invoices;
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('UpdatePrimaryInvoiceBatch completed.');
    }
}