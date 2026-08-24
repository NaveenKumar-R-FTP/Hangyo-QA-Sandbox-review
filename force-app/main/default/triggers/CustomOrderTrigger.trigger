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
            // Example: Update quantity in hand or any other specific logic
            UpdateQuantityInHand.getOrderRecord(Trigger.new, Trigger.oldMap);
            
            //Written by ashwini-14/04/2025 to update the status of order where if we update order status of secondary order then corresponding underss order status need to get update
            OrderTriggerHandler.updateUnderssOrderStatus(Trigger.new);
            
        }
    }
    
    if (Trigger.isBefore && Trigger.isUpdate) {
        CounterOrderInventoryValidation.checkInventory(Trigger.new, Trigger.oldMap);
    }
}