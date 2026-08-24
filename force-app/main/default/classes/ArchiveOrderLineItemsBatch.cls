global class ArchiveOrderLineItemsBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
   
    global Database.QueryLocator start(Database.BatchableContext bc) {

    Date cutoffDate = Date.today().addDays(-90);

    Map<String, Schema.SObjectField> fieldMap = Order_Line_Item__c.SObjectType.getDescribe().fields.getMap();
        
     
    List<String> fieldNames = new List<String>();

    for (String fieldName : fieldMap.keySet()) {
        fieldNames.add(fieldName);
    }

    String query = 'SELECT ' + String.join(fieldNames, ',') +' FROM Order_Line_Item__c' +' WHERE Archived__c = false' + ' AND CreatedDate < ' + String.valueOf(cutoffDate) +
    ' AND (Order__r.Status__c = \'Delivered\'' +
    ' OR Order__r.GRN_Status__c = \'Fully GRN\')';

    return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext bc,List<Order_Line_Item__c> scope) {


        ArchiveConnectorService.SendResult r =  ArchiveConnectorService.send('Order_Line_Item__c', scope, bc.getJobId());        


        if(r.success){
            List<Order_Line_Item__c> itemsToUpdate = new List<Order_Line_Item__c>();
            Set<Id> orderIdSet = new set<Id>();
            for(Order_Line_Item__c item : scope){
                item.Archived__c = true;
                item.Archived_Date__c = DateTime.now();
                itemsToUpdate.add(item);
                orderIdSet.add(item.Order__c);
            }
            if(!itemsToUpdate.isEmpty()){
                update itemsToUpdate;
            }
            List<Order__c> ordList = new List<Order__c>();
            for(Order__c ord : [SELECT Id,Sum_of_Ordered_Quantity__c,Snapshot_Sum_of_Ordered_Quantity__c FROM Order__c WHERE Id IN : orderIdSet]){
                ord.Snapshot_Sum_of_Ordered_Quantity__c = ord.Sum_of_Ordered_Quantity__c;
                ordList.add(ord);
            }
            if(!ordList.isEmpty()){
                update ordList;
            }
        }

     else  {

            System.debug('Error while Archiving'+r.errorMessage);
        }

       
    }

    global void finish(Database.BatchableContext bc) {

        System.debug('Salesforce archival completed.');
    }

    
}