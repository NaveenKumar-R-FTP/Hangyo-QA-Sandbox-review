public class InvoiceLineItemRollupHandler {

    public static void rollup(List<Invoice_Line_Item__c> lineItems, Map<Id, Invoice_Line_Item__c> oldMap) {

        // Collect all invoice Ids from new values
        Set<Id> invoiceIds = new Set<Id>();
        for(Invoice_Line_Item__c li : lineItems){
            if(li.Invoice__c != null){
                invoiceIds.add(li.Invoice__c);
            }
        }

        // Also collect old parent IDs if lookup was changed (for update/delete)
        if(oldMap != null){
            for(Invoice_Line_Item__c oldLi : oldMap.values()){
                if(oldLi.Invoice__c != null){
                    invoiceIds.add(oldLi.Invoice__c);
                }
            }
        }

        if(invoiceIds.isEmpty()) return;

        // Query invoices to check record type
        Map<Id, Invoice__c> primaryInvoices = new Map<Id, Invoice__c>(
            [
                SELECT Id
                FROM Invoice__c
                WHERE Id IN :invoiceIds
                AND RecordType.DeveloperName = 'Primary_Invoice'
            ]
        );

        if(primaryInvoices.isEmpty()) return;

        // Only rollup for these invoice IDs
        Set<Id> primaryInvoiceIds = primaryInvoices.keySet();

        // Query all line items of only primary invoices
        List<Invoice_Line_Item__c> allLineItems = [
            SELECT Id, Invoice__c, CGST_Amount__c, SGST_Amount__c, IGST_Amount__c, Quantity__c, Discount__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c IN :primaryInvoiceIds
        ];

        // Aggregation bucket
        Map<Id, AggregateValues> aggMap = new Map<Id, AggregateValues>();
        for(Id invId : primaryInvoiceIds){
            aggMap.put(invId, new AggregateValues());
        }

        // Rollup logic
        for(Invoice_Line_Item__c li : allLineItems){
            AggregateValues a = aggMap.get(li.Invoice__c);
            a.cgst += (li.CGST_Amount__c == null ? 0 : li.CGST_Amount__c);
            a.sgst += (li.SGST_Amount__c == null ? 0 : li.SGST_Amount__c);
            a.igst += (li.IGST_Amount__c == null ? 0 : li.IGST_Amount__c);
            a.qty  += (li.Quantity__c == null ? 0 : li.Quantity__c);
        }

        // Prepare updates
        List<Invoice__c> invoicesToUpdate = new List<Invoice__c>();
        for(Id invId : aggMap.keySet()){
            AggregateValues a = aggMap.get(invId);
            invoicesToUpdate.add(new Invoice__c(
                Id = invId,
                CGST_Amount__c = a.cgst,
                SGST_Amount__c = a.sgst,
                IGST_Amount__c = a.igst,
                Total_Quantity__c = a.qty
            ));
        }

        update invoicesToUpdate;
    }

    // Helper class
    public class AggregateValues {
        public Decimal cgst = 0;
        public Decimal sgst = 0; // small fix: SGST variable name
        public Decimal igst = 0;
        public Decimal qty = 0;
        //public Decimal discount = 0;
    }
}