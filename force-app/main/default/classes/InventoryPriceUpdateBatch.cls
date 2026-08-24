/*
Created By : Fuzail 
Created Date : 12/01/2026
Batch Class Name : InventoryPriceUpdateBatch
Description : Update the Inventory Product Rate Record based on the Price Book entries and type
*/
public class InventoryPriceUpdateBatch implements Database.Batchable<SObject> {
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT Id, Product__c, Distributor_Name__r.Primary_State__c, Distributor_Name__r.Record_type_Name__c FROM Inventory__c WHERE Product__c != NULL AND Distributor_Name__c != NULL AND Product_Rate__c = null'
        );
    }
    public void execute(Database.BatchableContext bc, List<Inventory__c> scope) {
        Set<Id> productIds = new Set<Id>();
        Set<String> states = new Set<String>();
        for (Inventory__c i : scope) {
            productIds.add(i.Product__c);
            if (i.Distributor_Name__r.Primary_State__c != null)
                states.add(i.Distributor_Name__r.Primary_State__c);
        }
        Map<String, Id> priceBookMap = new Map<String, Id>();
        for (Price_Book__c pb : [
            SELECT Id, Name
            FROM Price_Book__c
            WHERE Name IN :states
        ]) {
            priceBookMap.put(pb.Name, pb.Id);
        }
        Map<String, Price_Book_Entry__c> pbeMap = new Map<String, Price_Book_Entry__c>();
        for (Price_Book_Entry__c pbe : [
            SELECT Id,
                   Product__c,
                   Price_Book__c,
                   Type__c,
                   PTD__c,
                   PTSS__c
            FROM Price_Book_Entry__c
            WHERE isActive__c = true
              AND Product__c IN :productIds
              AND Price_Book__c IN :priceBookMap.values()
        ]) {
            pbeMap.put(
                pbe.Product__c + '-' + pbe.Price_Book__c + '-' + pbe.Type__c,
                pbe
            );
        }
        List<Inventory__c> updateList = new List<Inventory__c>();
        for (Inventory__c i : scope) {
            String typeVal;
            if (i.Distributor_Name__r.Record_type_Name__c == 'Super Stockist') {
                typeVal = 'Super Stockist';
            } else {
                //typeVal = String.valueOf(i.Distributor_Name__r.Distributor_Type__c);removed by Fuzail
                typeVal = 'Direct Distributor';
            }
            Id pbId = priceBookMap.get(i.Distributor_Name__r.Primary_State__c);
            if (pbId != null) {
                Price_Book_Entry__c pbe = pbeMap.get(
                    i.Product__c + '-' + pbId + '-' + typeVal
                );
                if (pbe != null) {
                    if (typeVal == 'Super Stockist') {
                        i.Product_Rate__c = pbe.PTSS__c;
                    } else {
                        i.Product_Rate__c = pbe.PTD__c;
                    }
                    updateList.add(i);
                }
            }
        }
        if (!updateList.isEmpty()) {
            update updateList;
        }
    }
    public void finish(Database.BatchableContext bc) {}
}