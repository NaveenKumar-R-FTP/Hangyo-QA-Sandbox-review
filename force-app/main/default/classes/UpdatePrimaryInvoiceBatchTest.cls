@isTest
public class UpdatePrimaryInvoiceBatchTest {

    @testSetup
    static void setupData() {
        // Get Primary Invoice Record Type
        RecordType rt = [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = 'Invoice__c'
            AND DeveloperName = 'Primary_Invoice'
            LIMIT 1
        ];

        // Create sample invoices
        List<Invoice__c> listInv = new List<Invoice__c>();
        for (Integer i = 0; i < 5; i++) {
            listInv.add(new Invoice__c(
                Name = 'Test Invoice ' + i,
                RecordTypeId = rt.Id,
                Billing_Date__c = Date.today().addDays(-i),
                Invoice_Total__c = 500 + i
            ));
        }
        insert listInv;
    }

    @isTest
    static void testBatchRun() {
        Test.startTest();
        Database.executeBatch(new UpdatePrimaryInvoiceBatch(), 200);
        Test.stopTest();

        List<Invoice__c> results = [
            SELECT Billing_Date__c, Invoice_Date__c,
                   Invoice_Total__c, Invoice_Amount__c
            FROM Invoice__c
        ];

        for (Invoice__c inv : results) {
            System.assertEquals(inv.Billing_Date__c, inv.Invoice_Date__c,
                'Invoice_Date__c must match Billing_Date__c');
            System.assertEquals(inv.Invoice_Total__c, inv.Invoice_Amount__c,
                'Invoice_Amount__c must match Invoice_Total__c');
        }
    }
}