public with sharing class InvoiceDiscountValidator {

    // Called from the Invoice trigger (before insert / before update)
    public static void enforceFromHeader(List<Invoice__c> newInvoices) {
        Set<Id> invIds = new Set<Id>();
        for (Invoice__c inv : newInvoices) {
            if (inv.Id != null) invIds.add(inv.Id);
        }

        // which invoices have at least one SKU-wise % entered
        Map<Id, Boolean> hasSku = new Map<Id, Boolean>();
        if (!invIds.isEmpty()) {
            for (Invoice_Line_Item__c li : [
                SELECT Invoice__c, SKU_Discount_Percent__c
                FROM Invoice_Line_Item__c
                WHERE Invoice__c IN :invIds
            ]) {
                if (li.SKU_Discount_Percent__c != null && li.SKU_Discount_Percent__c != 0) {
                    hasSku.put(li.Invoice__c, true);
                }
            }
        }

        for (Invoice__c inv : newInvoices) {
            Boolean overallSet = inv.Discount_2__c != null && inv.Discount_2__c != 0;
            Boolean skuSet      = hasSku.get(inv.Id) == true;

            if (overallSet && inv.Discount_2__c < 0) {
                inv.addError('Discount cannot be negative.');
                continue;
            }
            if (overallSet && skuSet) {
                inv.addError('Overall Discount and SKU-wise Discount cannot be applied together. Please clear one before saving.');
                continue;
            }
            inv.Discount_Mode__c = skuSet ? 'SKU_Wise' : (overallSet ? 'Overall' : 'None');
        }
    }

    // Called from the Invoice Line Item trigger (before insert / before update)
    public static void enforceFromLineItems(List<Invoice_Line_Item__c> newLines) {
        Set<Id> invIds = new Set<Id>();
        for (Invoice_Line_Item__c li : newLines) {
            if (li.Invoice__c != null) invIds.add(li.Invoice__c);
        }
        if (invIds.isEmpty()) return;

        Map<Id, Invoice__c> parents = new Map<Id, Invoice__c>([
            SELECT Id, Discount_2__c FROM Invoice__c WHERE Id IN :invIds
        ]);

        for (Invoice_Line_Item__c li : newLines) {
            if (li.SKU_Discount_Percent__c == null || li.SKU_Discount_Percent__c == 0) continue;

            if (li.SKU_Discount_Percent__c < 0) {
                li.addError('Discount cannot be negative.');
                continue;
            }
            Invoice__c parent = parents.get(li.Invoice__c);
            if (parent != null && parent.Discount_2__c != null && parent.Discount_2__c != 0) {
                li.addError('Overall Discount and SKU-wise Discount cannot be applied together. Please clear one before saving.');
            }
        }
    }
}