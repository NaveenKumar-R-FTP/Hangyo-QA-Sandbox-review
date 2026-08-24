trigger ClaimHeaderTrigger on Claim_Header__c (before insert,before update,after insert, after update) {
TriggerDispatcher.run(new ClaimHeaderTriggerHandler(), 'ClaimHeaderTrigger');
}