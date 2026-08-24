/*
Class Name : UpdateBeatRetailerCountBatch
Test Class Name : UpdateBeatRetailerCountBatchTest
Written By : Fuzail
Created Date : 22/12/2025
Last Modified Date: 22/12/2025
*/ 
public class UpdateBeatRetailerCountBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext bc) {

    Id retailerRtId = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('Retailer')
        .getRecordTypeId();

    return Database.getQueryLocator([
        SELECT Id
        FROM Beat__c
        WHERE Id IN (
            SELECT Beats_Name__c
            FROM Account
            WHERE RecordTypeId = :retailerRtId
            AND Is_Active__c = true
            AND Beats_Name__c != null
        )
    ]);
}
    


    public void execute(Database.BatchableContext bc, List<Beat__c> scope) {

         Set<Id> beatIds = new Set<Id>();
         for (Beat__c beat : scope) {
         if (beat != null && beat.Id != null) {
         beatIds.add(beat.Id);
            }
         }

        if (beatIds.isEmpty()) {
        return;
       }

        // Aggregate Retailer count per Beat
        Map<Id, Integer> beatRetailerCountMap = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Beats_Name__c beatId, COUNT(Id) total
            FROM Account
			WHERE Record_type_Name__c = 'Retailer'
			AND Is_Active__c = true
			AND Beats_Name__c IN :beatIds
			GROUP BY Beats_Name__c
        ]) {
            beatRetailerCountMap.put(
                (Id) ar.get('beatId'),
                (Integer) ar.get('total')
            );
        }

        // Prepare Beats for update
        List<Beat__c> beatsToUpdate = new List<Beat__c>();
        for (Id beatId : beatIds) {
            Integer countVal = beatRetailerCountMap.get(beatId);
            if (countVal == null) {
            countVal = 0;
            }


            beatsToUpdate.add(new Beat__c(
                Id = beatId,
                Number_Of_Retailers__c = countVal
            ));
        }

        if (!beatsToUpdate.isEmpty()) {
            update beatsToUpdate;
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Batch completed: Number_Of_Retailers__c updated for all Beats.');
    }
}