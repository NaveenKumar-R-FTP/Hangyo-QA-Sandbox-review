trigger CaseTrigger on Case__c (after update) {
    TriggerExecutionController__c setting = 
        TriggerExecutionController__c.getInstance('CaseTrigger');
    if (setting != null && !setting.Is_Active__c) return;
    
    if (Trigger.isAfter && Trigger.isUpdate) {
        // Runs inline with the real oldMap. Going through AssetTransferQueueable
        // would skip it, because that job only picks up Sync__c = true records.
        CaseTriggerHandler.setAccountsBranded(Trigger.new, Trigger.oldMap);
        CaseTriggerHandler.untagReturnedBrandingAssets(Trigger.new, Trigger.oldMap);

        Set<Id> caseIds = new Set<Id>();
        for (Case__c c : Trigger.new) {
            caseIds.add(c.Id);
        }
        if (!caseIds.isEmpty()) {
            System.enqueueJob(new AssetTransferQueueable(caseIds));
        }
    }
}