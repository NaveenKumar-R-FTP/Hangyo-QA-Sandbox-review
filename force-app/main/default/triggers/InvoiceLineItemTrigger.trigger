trigger InvoiceLineItemTrigger on Invoice_Line_Item__c (before insert, before update) {
// (1) Discount 2 — SKU-wise vs Overall mutual exclusivity
    InvoiceDiscountValidator.enforceFromLineItems(Trigger.new);

    // (2) Discount 2 — convert the SKU-wise % into the Discount_2__c amount the tax calc below uses
    for (Invoice_Line_Item__c item : Trigger.new) {
        if (item.SKU_Discount_Percent__c != null && item.SKU_Discount_Percent__c != 0) {
            Decimal base = item.Total_Amount__c != null ? item.Total_Amount__c : 0;
            item.Discount_2__c = (base * item.SKU_Discount_Percent__c / 100).setScale(2, System.RoundingMode.HALF_UP);
        }
    }
    Set<Id> invoiceIds = new Set<Id>();

    for (Invoice_Line_Item__c item : Trigger.new) {
        if (item.Invoice__c != null) {
            invoiceIds.add(item.Invoice__c);
        }
    }

    // Query Invoice records with tax percentages, Price_Type__c and Origin__c —
    // the latter two are needed to detect the Counter Invoice + MRP case, which uses a
    // different (extraction) formula from every other invoice (add-on-top formula).
    Map<Id, Invoice__c> invoiceMap = new Map<Id, Invoice__c>(
        [SELECT Id, CGST__c, SGST__c, IGST__c, Price_Type__c, Origin__c
         FROM Invoice__c WHERE Id IN :invoiceIds]
    );

    for (Invoice_Line_Item__c item : Trigger.new) {
        if (item.Invoice__c != null && invoiceMap.containsKey(item.Invoice__c)) {
            Invoice__c inv = invoiceMap.get(item.Invoice__c);
            if((inv.CGST__c!= null && inv.CGST__c >0) || (inv.SGST__c!= null && inv.SGST__c >0) || (inv.IGST__c!= null && inv.IGST__c >0)){
                Decimal discount1 = item.Discount_1__c != null ? item.Discount_1__c : 0;
                Decimal discount2 = item.Discount_2__c != null ? item.Discount_2__c : 0;
                Decimal schemeDiscount = item.Scheme_Discount_Amount__c != null ? item.Scheme_Discount_Amount__c : 0;
                Decimal totalAmount = item.Total_Amount__c != null ? item.Total_Amount__c : 0;
                Decimal amountAfterDiscount = totalAmount - (discount1 + discount2 + schemeDiscount);

                Decimal cgst = inv.CGST__c != null ? inv.CGST__c : 0;
                Decimal sgst = inv.SGST__c != null ? inv.SGST__c : 0;
                Decimal igst = inv.IGST__c != null ? inv.IGST__c : 0;

                // Legal requirement: MRP is tax-inclusive under Indian Legal Metrology rules —
                // the price already contains GST. Per Finance's clarification, GST must still
                // be calculated and shown (for GST return filing) but EXTRACTED from within
                // the MRP amount rather than added on top, so the Net Amount lands back on the
                // original MRP-based amount instead of exceeding it. This applies ONLY to
                // Counter Invoices with Price_Type__c = MRP — Dealer Price and every Secondary
                // Order/Invoice keep the normal add-on-top formula below unchanged.
                Boolean isMrpCounterInvoice = inv.Price_Type__c == 'MRP' && inv.Origin__c == 'Counter Invoice';

                if (isMrpCounterInvoice) {
                    Decimal totalRatePercent = cgst + sgst + igst;
                    // Extract the taxable base out of the tax-inclusive amount.
                    item.Tax__c = totalRatePercent > 0
                        ? (amountAfterDiscount / (1 + (totalRatePercent / 100))).setScale(2, RoundingMode.HALF_UP)
                        : amountAfterDiscount.setScale(2, RoundingMode.HALF_UP);
                } else {
                    // Normal (add-on-top) formula — taxable base is the amount as-is.
                    item.Tax__c = amountAfterDiscount;
                }

                Decimal tax = item.Tax__c != null ? item.Tax__c : 0;

                // Correct percentage calculation
                item.CGST_Amount__c = ((tax * cgst) / 100).setScale(2, RoundingMode.HALF_UP);
                item.SGST_Amount__c = ((tax * sgst) / 100).setScale(2, RoundingMode.HALF_UP);
                item.IGST_Amount__c = ((tax * igst) / 100).setScale(2, RoundingMode.HALF_UP);

                item.CGST_Percentage__c = cgst;
                item.SGST_Percentage__c = cgst;
                item.IGST_Percentage__c = igst;
            }

        }
    }
}