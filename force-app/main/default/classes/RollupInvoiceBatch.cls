public class RollupInvoiceBatch implements Database.Batchable<SObject>, Database.Stateful {

    // Query only Primary Invoice records
    public Database.QueryLocator start(Database.BatchableContext bc) {

        Id primaryRecTypeId = Schema.SObjectType.Invoice__c
                               .getRecordTypeInfosByDeveloperName()
                               .get('Primary_Invoice')
                               .getRecordTypeId();

        return Database.getQueryLocator([
            SELECT Id
            FROM Invoice__c
            WHERE RecordTypeId = :primaryRecTypeId
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Invoice__c> scope) {

        Set<Id> invoiceIds = new Set<Id>();
        for (Invoice__c inv : scope) {
            invoiceIds.add(inv.Id);
        }

        // Fetch line items for these invoices
        List<Invoice_Line_Item__c> lineItems = [
            SELECT Invoice__c,
                   CGST_Amount__c,
                   SGST_Amount__c,
                   IGST_Amount__c,
                   Quantity__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c IN :invoiceIds
        ];

        // Rollup values
        Map<Id, AggregateValues> aggMap = new Map<Id, AggregateValues>();

        for (Invoice_Line_Item__c li : lineItems) {
            if (!aggMap.containsKey(li.Invoice__c)) {
                aggMap.put(li.Invoice__c, new AggregateValues());
            }

            AggregateValues a = aggMap.get(li.Invoice__c);

            a.cgst += (li.CGST_Amount__c == null ? 0 : li.CGST_Amount__c);
            a.sgst += (li.SGST_Amount__c == null ? 0 : li.SGST_Amount__c);
            a.igst += (li.IGST_Amount__c == null ? 0 : li.IGST_Amount__c);
            a.qty  += (li.Quantity__c == null ? 0 : li.Quantity__c);
        }

        // Prepare Invoice updates
        List<Invoice__c> invUpdates = new List<Invoice__c>();

        for (Invoice__c inv : scope) {
            if (aggMap.containsKey(inv.Id)) {
                AggregateValues a = aggMap.get(inv.Id);

                inv.CGST_Amount__c = a.cgst;
                inv.SGST_Amount__c = a.sgst;
                inv.IGST_Amount__c = a.igst;
                inv.Total_Quantity__c = a.qty;
                //inv.Discount_Total__c = a.discount;

                invUpdates.add(inv);
            }
        }

        if (!invUpdates.isEmpty()) {
            update invUpdates;
        }
    }

    public void finish(Database.BatchableContext bc) {
        // Optional email or logging
    }

    // Helper class for aggregation
    public class AggregateValues {
        public Decimal cgst = 0;
        public Decimal sgst = 0;
        public Decimal igst = 0;
        public Decimal qty = 0;
        public Decimal discount = 0;
    }
}