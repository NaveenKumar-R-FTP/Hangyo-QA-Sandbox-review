/*
Class Name : BeatTriggerHandler
Test Class Name : BeatTriggerHandlerTest
Written By : Fuzail
Created Date : 22/12/2025
Last Modified Date: 22/12/2025
*/
public class BeatTriggerHandler {

    public static void updateRetailerCount(
        List<Account> newList,
        List<Account> oldList
    ) {
        
        if ((newList == null || newList.isEmpty()) 
       && (oldList == null || oldList.isEmpty())) {
       return;
       }
        Set<Id> beatIds = new Set<Id>();

        // Collect Beat Ids from new records
        if (newList != null) {
            for (Account acc : newList) {
                if (acc.Beats_Name__c != null) {
                    beatIds.add(acc.Beats_Name__c);
                }
            }
        }

        // Collect Beat Ids from old records (important for re-parenting & delete)
        if (oldList != null) {
            for (Account acc : oldList) {
                if (acc.Beats_Name__c != null) {
                    beatIds.add(acc.Beats_Name__c);
                }
            }
        }

        if (beatIds.isEmpty()) {
            return;
        }

        // Fetch Retailer RecordType Id (safe & best practice)
        Id retailerRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Retailer')
            .getRecordTypeId();

        // Map: Beat Id → Retailer Count
        Map<Id, Integer> beatRetailerCountMap = new Map<Id, Integer>();

        // Query all Retailer Accounts under these Beats
        for (Account acc : [
            SELECT Id, Beats_Name__c
            FROM Account
            WHERE Beats_Name__c IN :beatIds
            AND RecordTypeId = :retailerRtId
            AND Is_Active__c = true
        ]) {
            Id beatId = acc.Beats_Name__c;
            beatRetailerCountMap.put(
                beatId,
                beatRetailerCountMap.containsKey(beatId)
                    ? beatRetailerCountMap.get(beatId) + 1
                    : 1
            );
        }

        // Prepare Beat records for update
        List<Beat__c> beatsToUpdate = new List<Beat__c>();
        for (Id beatId : beatIds) {
            if (beatId == null) {
               continue;
              }

             Integer retailerCount = beatRetailerCountMap.get(beatId);            
             if (retailerCount == null) {
             retailerCount = 0;
               }

            beatsToUpdate.add(new Beat__c(
                Id = beatId,
                Number_Of_Retailers__c = retailerCount
            ));
        }

        if (!beatsToUpdate.isEmpty()) {
            update beatsToUpdate;
        }
    }
}