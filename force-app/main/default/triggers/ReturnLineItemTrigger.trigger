trigger ReturnLineItemTrigger on Return_Line_item__c (after insert) {
    
   if (Trigger.isAfter && Trigger.isInsert) {
        List<Return_Line_item__c> validLineItems = new List<Return_Line_item__c>();
        for (Return_Line_item__c returnLine : Trigger.new) {
            if (returnLine.Reuse_count__c != null && returnLine.Return__c != null) {
                validLineItems.add(returnLine);
            }
        }
        if (!validLineItems.isEmpty()) {
            UpdateInventoryRecord.updateInventorySecondaryReturn(validLineItems);
        }
    }

}