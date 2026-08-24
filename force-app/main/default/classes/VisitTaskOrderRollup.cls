/*
Created By : Fuzail 
Description : Rolling up amount + count of Orders To Visit Tasks
Created Date : 25/11/2025
Last Modified Date: 26/11/2025
*/

public class VisitTaskOrderRollup {

    public static void rollUp(List<Order__c> newList) {

        // Collect Visit Task IDs
        Set<Id> visitTaskIds = new Set<Id>();
        for (Order__c o : newList) {
            if (o.Visit_Task__c != null) {
                visitTaskIds.add(o.Visit_Task__c);
            }
        }

        if (visitTaskIds.isEmpty()) return;

        // Query and SUM + COUNT using Aggregate SOQL
        List<Visit_Task__c> vtToUpdate = new List<Visit_Task__c>();

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

            Visit_Task__c vt = new Visit_Task__c(
                Id = (Id) aggr.get('vtId'),
                Total_Order_Amount__c = (Decimal) aggr.get('total'),
                Count_Of_Orders__c = (Integer) aggr.get('orderCount')
            );

            vtToUpdate.add(vt);
        }

        // For Visit Tasks that had no matching orders, set total = 0 AND count = 0
        for (Id vtId : visitTaskIds) {
            Boolean found = false;

            for (Visit_Task__c v : vtToUpdate) {
                if (v.Id == vtId) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                vtToUpdate.add(new Visit_Task__c(
                    Id = vtId,
                    Total_Order_Amount__c = 0,
                    Count_Of_Orders__c = 0
                ));
            }
        }

        // Update all Visit Task records
        if (!vtToUpdate.isEmpty()) {
            update vtToUpdate;
        }
    }
}