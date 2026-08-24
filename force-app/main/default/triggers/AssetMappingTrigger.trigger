trigger AssetMappingTrigger on Asset_Mapping__c (after insert, after update) {
    if (AssetMappingTriggerHandler.isRunning) return;
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        AssetMappingTriggerHandler.isRunning = true;
        AssetMappingTriggerHandler.updateDistributor(Trigger.new, Trigger.oldMap);
        AssetMappingTriggerHandler.setAccountsBranded(Trigger.new, Trigger.oldMap);
        AssetMappingTriggerHandler.isRunning = false;
    }
}