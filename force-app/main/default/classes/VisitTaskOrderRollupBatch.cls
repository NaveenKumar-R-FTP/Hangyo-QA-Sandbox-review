/*
Created By : Fuzail 
Description : Batch class to rollup amount + count of Orders to Visit Tasks
Created Date : 26/11/2025
Last Modified Date: 27/11/2025
*/
global class VisitTaskOrderRollupBatch implements Database.Batchable<sObject> {
    
    global Database.QueryLocator start(Database.BatchableContext bc) {
        Date startDate = Date.newInstance(2025, 11, 1); // November 1, 2025
        return Database.getQueryLocator([
            SELECT Id, Name, Total_Order_Amount__c, Physical_Visit_Order_Value__c, 
                   No_of_Physical_Visit_Order_Taken__c, Tele_Visit_Order_Value__c, 
                   No_Of_Tele_Visit_Order_Taken__c
            FROM Visit_Task__c 
            WHERE (CreatedDate >= :startDate
            OR CreatedDate <= TODAY)
            AND Status__c = 'Completed - Order'
        ]);
    }
    
    global void execute(Database.BatchableContext bc, List<Visit_Task__c> scope) {
        // Collect Visit Task IDs from scope
        Set<Id> visitTaskIds = new Set<Id>();
        for (Visit_Task__c vt : scope) {
            visitTaskIds.add(vt.Id);
        }
        
        if (visitTaskIds.isEmpty()) return;
        
        // Query and SUM + COUNT using Aggregate SOQL
        Map<Id, Visit_Task__c> vtToUpdateMap = new Map<Id, Visit_Task__c>();
        
        for (AggregateResult aggr : [
            SELECT 
                Visit_Task__c vtId,
                SUM(Total_Order_Value__c) total,
                COUNT(Id) orderCount
            FROM Order__c
            WHERE Visit_Task__c IN :visitTaskIds
            AND RecordType.Name = 'Secondary Order'
            AND Type__c = 'Field Order'
            GROUP BY Visit_Task__c
        ]) {
            Id vtId = (Id) aggr.get('vtId');
            Visit_Task__c vt = new Visit_Task__c(
                Id = vtId,
                Total_Order_Amount__c = (Decimal) aggr.get('total'),
                Count_Of_Orders__c = (Integer) aggr.get('orderCount')
            );
            vtToUpdateMap.put(vtId, vt);
        }
        
        // For Visit Tasks that had no matching orders, set total = 0 AND count = 0
        for (Id vtId : visitTaskIds) {
            if (!vtToUpdateMap.containsKey(vtId)) {
                vtToUpdateMap.put(vtId, new Visit_Task__c(
                    Id = vtId,
                    Total_Order_Amount__c = 0,
                    Count_Of_Orders__c = 0
                ));
            }
        }
        
        // Update all Visit Task records
        if (!vtToUpdateMap.isEmpty()) {
            update vtToUpdateMap.values();
        }
    }
    
    global void finish(Database.BatchableContext bc) {
        System.debug('VisitTaskOrderRollupBatch completed successfully');
    }
    
}