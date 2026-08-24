public class ClaimHeaderTriggerHandler implements ITriggerHandler {

    public static Boolean TriggerDisabled = false;
    
    public Boolean isDisabled() {
        return TriggerDisabled;
    }

    public void BeforeInsert(List<sObject> newList) {
        // No logic needed
    }

    public void AfterInsert(List<sObject> newList, Map<Id, sObject> newMap) {
        // No logic needed
    }

    public void BeforeUpdate(
        List<sObject> newList, 
        Map<Id, sObject> newMap,
        List<sObject> oldList, 
        Map<Id, sObject> oldMap
    ) {
         List<Claim_Header__c> newRecords = (List<Claim_Header__c>) newList;
        Map<Id, Claim_Header__c> oldRecords = (Map<Id, Claim_Header__c>) oldMap;

        if (newRecords != null) {
            ClaimHeaderTriggerHelper.enforceApprovalComments(newRecords, oldRecords);
        }
    }

    public void AfterUpdate(
        List<sObject> newList, 
        Map<Id, sObject> newMap,
        List<sObject> oldList, 
        Map<Id, sObject> oldMap
    ) {
       
    }

    public void BeforeDelete(List<sObject> oldList , Map<Id, sObject> oldMap) {
        // No logic needed
    }

    public void AfterDelete(List<sObject> oldList , Map<Id, sObject> oldMap) {
        // No logic needed
    }

    public void AfterUnDelete(List<sObject> newList, Map<Id, sObject> newMap) {
        // No logic needed
    }
}