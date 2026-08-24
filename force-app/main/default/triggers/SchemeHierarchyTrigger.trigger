trigger SchemeHierarchyTrigger on Scheme_Hierarchy__c (before insert, before update) {
    SchemeHierarchyTriggerHandler.validate(Trigger.new);
}