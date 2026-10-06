trigger CaseTrigger on Case__c (before update, after update) {
    TriggerExecutionController__c setting = 
        TriggerExecutionController__c.getInstance('CaseTrigger');
    if (setting != null && !setting.Is_Active__c) return;
    
    // Approval-process field updates bypass validation rules, so the vendor
    // requirement has to be enforced here or Mahesh can approve past it.
    if (Trigger.isBefore && Trigger.isUpdate) {
        CaseTriggerHandler.requireVendorBeforeApproval(Trigger.new, Trigger.oldMap);
    }

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