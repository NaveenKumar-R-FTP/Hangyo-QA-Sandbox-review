trigger CustomOrderTrigger on Order__c (after insert, after update, after delete, after undelete , before update) {
    if (Trigger.isAfter) {
        // Handle Insert, Update, and Undelete events
        if (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete) {
            // Update the average order value for relevant accounts
            OrderTriggerHandler.updateAverageOrderValue(Trigger.new);
            // UpdateQuantityInHand.getOrderRecord(Trigger.new, Trigger.oldMap);
			//  ADDED BY FUZAIL — Rollup Orders to Visit Task
            VisitTaskOrderRollup.rollUp(Trigger.new);           
        }          
        
        // Handle Insert, Update, and Undelete events
        if (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete) {
            // Update Retailer data when Order is created or updated
            OrderTriggerHandler.updateRetailerOrderData(Trigger.new);
        }
        // Handle Delete event
        if (Trigger.isDelete) {
            // Update Retailer data on deletion of Order
            OrderTriggerHandler.updateRetailerOrderData(Trigger.old);
        }
        
        
        
        // Handle Delete event
        if (Trigger.isDelete) {
            // Update the average order value for relevant accounts on deletion
            OrderTriggerHandler.updateAverageOrderValue(Trigger.old);
			
            //  ADDED BY FUZAIL — Rollup Orders to Visit Task
            VisitTaskOrderRollup.rollUp(Trigger.old); 
        }
        
                // Handle Update-specific logic
        if (Trigger.isUpdate) {
            // Counter-order stock is now managed entirely at the INVOICE level
            // (updateSecondaryInvoiceQuantity deducts on invoice Confirm, restoreOnCancel restores
            // on cancel, reconcileOnEdit reconciles edits). Deducting again here when the order
            // flips to Delivered double-counted the same counter stock and drove it negative.
            // UpdateQuantityInHand.getOrderRecord(Trigger.new, Trigger.oldMap);
            
            //Written by ashwini-14/04/2025 to update the status of order where if we update order status of secondary order then corresponding underss order status need to get update
            OrderTriggerHandler.updateUnderssOrderStatus(Trigger.new);
            
        }
    }
    
       if (Trigger.isBefore && Trigger.isUpdate) {
        // Counter-order stock is validated at invoice Confirm (InvoiceTrigger's inventory check),
        // not again when the order flips to Delivered. Re-validating here against stock the invoice
        // already consumed produced a false "Insufficient inventory... Available: 0, Required: 1"
        // and blocked Mark-as-Complete, so this order-level re-validation is disabled.
        // CounterOrderInventoryValidation.checkInventory(Trigger.new, Trigger.oldMap);
    }
}