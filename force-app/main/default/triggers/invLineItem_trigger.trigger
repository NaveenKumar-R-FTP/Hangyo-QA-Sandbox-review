trigger invLineItem_trigger on Invoice_Line_Item__c (After Insert,After update , after delete, after undelete) {
    
    if (Trigger.isAfter && Trigger.isUpdate){
        UpdateQuantityInHand.updatePrimaryInvoiceQuantity(Trigger.new , Trigger.oldMap);

	// NEW FUNCTIONALITY - Added by Fuzail - Update GRN Status on Order (Update)
        GRNStatusController.updateGRNStatus(Trigger.new, Trigger.oldMap);

    }
   // Added By Fuzail
	/*if (Trigger.isAfter && Trigger.isInsert){
        // NEW FUNCTIONALITY - Added by Fuzail - Update GRN Status on Order (Insert)
        GRNStatusController.updateGRNStatus(Trigger.new, null);
    }*/
    
    if (Trigger.isAfter){
        if(Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete){
            InvoiceLineItemRollupHandler.rollup(Trigger.new, Trigger.oldMap);
        }
        if(Trigger.isDelete){
            InvoiceLineItemRollupHandler.rollup(Trigger.old, null);
        }
        
        if(Trigger.isInsert){
            Set<Id> invoiceIds = new Set<Id>();

            for (Invoice_Line_Item__c invLine : Trigger.new) {
                if (invLine.Invoice__c != null) {
                    invoiceIds.add(invLine.Invoice__c);
                }
            }
            
            if(invoiceIds.size() > 0){
                Map<Id, Invoice__c> invoiceMap = new Map<Id, Invoice__c>(
                [SELECT Id,Ref_Invoice_No_Data_Upload__c,Data_Upload__c,Status__c FROM Invoice__c 
                 WHERE Id IN :invoiceIds AND Ref_Invoice_No_Data_Upload__c != NULL AND Data_Upload__c != NULL AND Status__c = 'Confirmed']);
        
                List<Invoice_Line_Item__c> eligibleLines = new List<Invoice_Line_Item__c>();      
                for (Invoice_Line_Item__c invLine : Trigger.new) {        
                    Invoice__c inv = invoiceMap.get(invLine.Invoice__c);        
                    if (inv != null && inv.Ref_Invoice_No_Data_Upload__c != null && inv.Data_Upload__c != null && inv.Status__c == 'Confirmed') {       
                        eligibleLines.add(invLine);
                    }
                }
            
                if (!eligibleLines.isEmpty()) {
                    HandleInventoryBulkUpload.inventoryBulkUpload(eligibleLines);
                }
            }
        }
    }
}