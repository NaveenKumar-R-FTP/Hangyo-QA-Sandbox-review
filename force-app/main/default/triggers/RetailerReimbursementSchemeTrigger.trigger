trigger RetailerReimbursementSchemeTrigger on Retailer_Reimbursement_Scheme__c (before insert, before update) {

    // ─────────────────────────────────────────────────────────────────────────
    // On INSERT: capture whatever Balance__c was first set to, into
    // Initial_Balance__c. This runs regardless of whether the record was
    // created via Data Loader bulk insert, the UI, or the API — so
    // "how much was originally assigned" is always correct, with no
    // reliance on remembering to fill in a second column during upload.
    // ─────────────────────────────────────────────────────────────────────────
    if (Trigger.isBefore && Trigger.isInsert) {
        for (Retailer_Reimbursement_Scheme__c alloc : Trigger.new) {
            if (alloc.Initial_Balance__c == null) {
                alloc.Initial_Balance__c = alloc.Balance__c == null ? 0 : alloc.Balance__c;
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // On UPDATE: lock Initial_Balance__c so it can never be changed after
    // creation, even by accident (e.g. someone editing the record directly
    // in Setup). This keeps the reporting math trustworthy long-term.
    // ─────────────────────────────────────────────────────────────────────────
    if (Trigger.isBefore && Trigger.isUpdate) {
        for (Retailer_Reimbursement_Scheme__c alloc : Trigger.new) {
            Retailer_Reimbursement_Scheme__c oldAlloc = Trigger.oldMap.get(alloc.Id);
            if (alloc.Initial_Balance__c != oldAlloc.Initial_Balance__c) {
                alloc.Initial_Balance__c.addError(
                    'Initial Balance cannot be changed once set — it is a historical record.'
                );
            }
        }
    }
}