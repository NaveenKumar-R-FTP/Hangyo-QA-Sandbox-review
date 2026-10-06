global class ArchiveOrderLineItemsBatch implements Database.Batchable<SObject>, Database.AllowsCallouts,  Database.Stateful, Schedulable  {
   
    private Integer totalProcessed = 0;
    private Integer totalArchived = 0; 
    private Integer totalFailed = 0; 
    private List<String> errorMessages = new List<String>(); 
    
    
    global Database.QueryLocator start(Database.BatchableContext bc) {  
        Azure_Archive_Config__mdt confg = Azure_Archive_Config__mdt.getInstance('Order_Line_Item');
        
        Date cutoffDate = Date.today().addDays(-(Integer)confg.Retention_Days__c);
        
        Map<String, Schema.SObjectField> fieldMap = Order_Line_Item__c.SObjectType.getDescribe().fields.getMap();
        Set<String> excludedFields = new Set<String>{
            'LastActivityDate', 'LastReferencedDate', 'LastViewedDate', 'RecordVisibilityId', 'UserRecordAccessId'
        };  
     
        List<String> fieldNames = new List<String>();
    
        for (String fieldName : fieldMap.keySet()) {
            if(!excludedFields.contains(fieldName)){
                    fieldNames.add(fieldName);
            }
        }
                        
        String query = 'SELECT ' + String.join(fieldNames, ',') +
                        ' FROM Order_Line_Item__c ';
        if(!String.isBlank(confg.Closed_State_Values__c)){
            query += (String)confg.Closed_State_Values__c;
        }                    
                             
        return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext bc, List<Order_Line_Item__c> scope) {
        DateTime archivedTimestamp = DateTime.now();
        Set<Id> orderIdSet = new Set<Id>();
        List<Order_Line_Item__c> oliToUpdate = new List<Order_Line_Item__c>();
        List<Order_Line_Item__c> archivedItems = new List<Order_Line_Item__c>();
        totalProcessed += scope.size();
            
        ArchiveConnectorService.SendResult r = ArchiveConnectorService.send('Order_Line_Item__c', scope, bc.getJobId());
    
        if (r.success) {
            try {
                for (Order_Line_Item__c item : scope) {            
                    if(r.archivedIds.contains(item.id)){
                        orderIdSet.add(item.Order__c);
                        oliToUpdate.add(new Order_Line_Item__c(
                            Id = item.Id,
                            Archived__c = true,
                            Archived_Date__c = archivedTimestamp
                        ));
                        archivedItems.add(item);                        
                    }
                }        
                totalArchived+= oliToUpdate.size();
                Database.update(oliToUpdate, false);
        
                Map<Id, Order__c> orderMap = new Map<Id, Order__c>(
                    [SELECT Id, Name, Sum_of_Ordered_Quantity__c, Snapshot_Sum_of_Ordered_Quantity__c 
                     FROM Order__c WHERE Id IN :orderIdSet]
                );

                /*List<Order__c> ordList = new List<Order__c>();
                for (Order__c ord : orderMap.values()) {
                    if (ord.Snapshot_Sum_of_Ordered_Quantity__c == null) {
                        ord.Snapshot_Sum_of_Ordered_Quantity__c = ord.Sum_of_Ordered_Quantity__c;
                        ordList.add(ord);
                    }
                }
                if (!ordList.isEmpty()) {
                    update ordList;
                }

                createArchivalLogs(archivedItems, orderMap, r, bc.getJobId(), archivedTimestamp);*/

            } catch (DmlException e) {
                for (Integer i = 0; i < e.getNumDml(); i++) {
                    System.debug('DML Error ' + i + ': ' + e.getDmlMessage(i));
                    System.debug('Status Code: ' + e.getDmlStatusCode(i));
                    System.debug('Fields: ' + e.getDmlFieldNames(i));
                }
            }
        } else {
            System.debug('Error while Archiving: ' + r.errorMessage);
            totalFailed += scope.size();
            errorMessages.add(r.errorCode + '-' + r.errorMessage);            
        }
    }

    /*private void createArchivalLogs(List<Order_Line_Item__c> archivedItems, Map<Id, Order__c> orderMap,
                                     ArchiveConnectorService.SendResult r, Id jobId, DateTime archivedTimestamp) {

        if (archivedItems == null || archivedItems.isEmpty()) {
            return;
        }

        List<Archival_Log__c> logsToInsert = new List<Archival_Log__c>();

        for (Order_Line_Item__c item : archivedItems) {
            Order__c parentOrder = (item.Order__c != null) ? orderMap.get(item.Order__c) : null;

            logsToInsert.add(new Archival_Log__c(
                Archived_Record_Id__c   = item.Id,
                Archived_Object__c      = 'Order_Line_Item__c',
                Parent_Record_Id__c     = item.Order__c,
                Parent_Record_Name__c   = (parentOrder != null) ? parentOrder.Name : null,
                Parent_Object__c        = 'Order__c',
                Original_CreatedDate__c = item.CreatedDate,
                Original_CreatedById__c = item.CreatedById,
                Archive_Batch_Id__c     = String.valueOf(jobId),
                Archived_Location__c    = r.archiveLocation,
                Checksum__c             = r.checksum,
                Soft_Archived_Date__c   = archivedTimestamp,
                Status__c               = 'Soft-Archived'
            ));
        }

        List<Database.SaveResult> saveResults = Database.insert(logsToInsert, false);
        for (Integer i = 0; i < saveResults.size(); i++) {
            if (!saveResults[i].isSuccess()) {
                for (Database.Error err : saveResults[i].getErrors()) {
                    System.debug('Archival_Log__c insert failed for OLI Id '
                        + logsToInsert[i].Archived_Record_Id__c + ': '
                        + err.getStatusCode() + ' - ' + err.getMessage());
                }
            }
        }
    }*/

    global void finish(Database.BatchableContext bc) {
        System.debug('Archival job completed.');
        Archival_Job_Log__c ajl = new Archival_Job_Log__c(
            Archive_Batch_Id__c   = bc.getJobId(),
            Archived_Object__c    = 'Order_Line_Item__c',
            Error_Message__c      = errorMessages.isEmpty() ? null : String.join(errorMessages, '; '),
            Total_Archived__c     = totalArchived,
            Total_Failed__c       = totalFailed,
            Total_Processed__c    = totalProcessed
        );
        insert ajl;
    }
     global void execute(SchedulableContext sc) {
        Database.executeBatch(new ArchiveOrderLineItemsBatch(), 200);
    }
}