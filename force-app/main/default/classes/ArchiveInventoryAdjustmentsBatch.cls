global class ArchiveInventoryAdjustmentsBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful, Schedulable {

    private Integer totalProcessed = 0;
    private Integer totalArchived = 0;
    private Integer totalFailed = 0;
    private List<String> errorMessages = new List<String>();

    global Database.QueryLocator start(Database.BatchableContext bc) {
        Azure_Archive_Config__mdt confg = Azure_Archive_Config__mdt.getInstance('Inventory_Adjustment');

        Date cutoffDate = Date.today().addDays(-(Integer)confg.Retention_Days__c);

        Map<String, Schema.SObjectField> fieldMap = Inventory_Adjustment__c.SObjectType.getDescribe().fields.getMap();
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
                        ' FROM Inventory_Adjustment__c ';
        if(!String.isBlank(confg.Closed_State_Values__c)){
            query += (String)confg.Closed_State_Values__c;
        }

        return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext bc,List<Inventory_Adjustment__c> scope) {
        DateTime archivedTimestamp = DateTime.now();
        List<Inventory_Adjustment__c> inventoryAdjustmentsToUpdate = new List<Inventory_Adjustment__c>();
        totalProcessed += scope.size();

        ArchiveConnectorService.SendResult r = ArchiveConnectorService.send('Inventory_Adjustment__c', scope, bc.getJobId());

        if (r.success) {
            System.debug('success:-' + r.success);
            try {
                System.debug('scope:-' + scope);
                System.debug('archivedIds:-' + r.archivedIds);
                for (Inventory_Adjustment__c item : scope) {
                    if(r.archivedIds.contains(item.id)){
                        inventoryAdjustmentsToUpdate.add(new Inventory_Adjustment__c(
                            Id = item.Id,
                            Archived__c = true,
                            Archived_Date__c = archivedTimestamp
                        ));
                    }
                }
                totalArchived += inventoryAdjustmentsToUpdate.size();
                //TriggerBypass.bypassed.add('Inventory_Adjustment__c'); // bypass ON (inventory adjustment triggers)
                Database.update(inventoryAdjustmentsToUpdate, false);

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

    global void finish(Database.BatchableContext bc) {
        System.debug('Archival job completed.');
        Archival_Job_Log__c ajl = new Archival_Job_Log__c(
            Archive_Batch_Id__c   = bc.getJobId(),
            Archived_Object__c    = 'Inventory_Adjustment__c',
            Error_Message__c      = errorMessages.isEmpty() ? null : String.join(errorMessages, '; '),
            Total_Archived__c     = totalArchived,
            Total_Failed__c       = totalFailed,
            Total_Processed__c    = totalProcessed
        );
        insert ajl;
    }

     global void execute(SchedulableContext sc) {
        Database.executeBatch(new ArchiveInventoryAdjustmentsBatch(), 200);
    }
}