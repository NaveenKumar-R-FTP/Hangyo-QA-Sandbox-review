trigger SchemeApplicabilityTrigger on Scheme_Applicability__c (before insert, before update) {
    SchemeApplicabilityTriggerHandler.normalizeAndValidate(Trigger.new);
}