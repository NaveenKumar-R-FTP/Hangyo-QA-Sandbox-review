trigger RetailerTargetTrigger on Retailer_Target__c (after insert, after update, after delete, after undelete) {
  if (Trigger.isAfter) {
        // Collect Account IDs only if AccountId is NOT null
        if (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete) {
       
            RetailerTargetTriggerHandler.updateAmountOnAccount(trigger.new);
        } 
    // For Delete
        else if (Trigger.isDelete) {
            RetailerTargetTriggerHandler.updateAmountOnAccount(trigger.new);
        }
        
    }
}