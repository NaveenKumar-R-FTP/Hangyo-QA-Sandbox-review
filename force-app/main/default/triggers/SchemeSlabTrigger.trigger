trigger SchemeSlabTrigger on Scheme_Slab__c (before insert, before update) {
    SchemeSlabTriggerHandler.validateSlabs(Trigger.new);
}