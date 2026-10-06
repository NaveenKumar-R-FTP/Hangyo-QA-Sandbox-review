trigger AssetMappingTrigger on Asset_Mapping__c (before insert, before update, after insert, after update) {

    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        AssetMappingTriggerHandler.validateDuplicateMapping(Trigger.new, Trigger.oldMap);
    }

    if (AssetMappingTriggerHandler.isRunning) return;
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        AssetMappingTriggerHandler.isRunning = true;
        AssetMappingTriggerHandler.updateDistributor(Trigger.new, Trigger.oldMap);
        AssetMappingTriggerHandler.setAccountsBranded(Trigger.new, Trigger.oldMap);
        AssetMappingTriggerHandler.isRunning = false;
    }
}