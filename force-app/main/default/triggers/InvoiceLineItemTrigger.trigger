trigger InvoiceLineItemTrigger on Invoice_Line_Item__c (before insert, before update, after insert, after update, after delete) {
    
    if (!TriggerBypass.isBypassed('Invoice_Line_Item__c')){
        if (Trigger.isBefore) {
            // R2: block line add/modify once the 2-day window has closed or the invoice is cancelled
            InvoiceEditWindow.enforceLinesEditable(Trigger.new);
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
                        Boolean isMrpCounterInvoice = inv.Price_Type__c == 'MRP' && inv.Origin__c == 'Counter Invoice';
                        if (isMrpCounterInvoice) {
                            Decimal totalRatePercent = cgst + sgst + igst;
                            item.Tax__c = totalRatePercent > 0
                                ? (amountAfterDiscount / (1 + (totalRatePercent / 100))).setScale(2, RoundingMode.HALF_UP)
                                : amountAfterDiscount.setScale(2, RoundingMode.HALF_UP);
                        } else {
                            item.Tax__c = amountAfterDiscount;
                        }
                        Decimal tax = item.Tax__c != null ? item.Tax__c : 0;
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
    
        if (Trigger.isAfter) {
            if (Trigger.isDelete) {
                UpdateQuantityInHand.reconcileOnEdit(null, Trigger.oldMap);
            } else {
                UpdateQuantityInHand.reconcileOnEdit(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
            }
        }
    }
}