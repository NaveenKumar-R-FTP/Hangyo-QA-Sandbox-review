global class ArchiveVisitTasksBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful, Schedulable {

    private Integer totalProcessed = 0;
    private Integer totalArchived = 0;
    private Integer totalFailed = 0;
    private List<String> errorMessages = new List<String>();

    global Database.QueryLocator start(Database.BatchableContext bc) {
        Azure_Archive_Config__mdt confg = Azure_Archive_Config__mdt.getInstance('Visit_Task');

        Date cutoffDate = Date.today().addDays(-(Integer)confg.Retention_Days__c);

        Map<String, Schema.SObjectField> fieldMap = Visit_Task__c.SObjectType.getDescribe().fields.getMap();
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
                        ' FROM Visit_Task__c ';
        if(!String.isBlank(confg.Closed_State_Values__c)){
            query += (String)confg.Closed_State_Values__c;
        }

        return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext bc,List<Visit_Task__c> scope) {
        DateTime archivedTimestamp = DateTime.now();
        Set<Id> visitIdSet = new Set<Id>();
        List<Visit_Task__c> visitTasksToUpdate = new List<Visit_Task__c>();
        List<Visit__c> visitsToUpdate = new List<Visit__c>();
        totalProcessed += scope.size();

        ArchiveConnectorService.SendResult r = ArchiveConnectorService.send('Visit_Task__c', scope, bc.getJobId());

        if (r.success) {
            System.debug('success:-' + r.success);
            try {
                System.debug('scope:-' + scope);
                System.debug('archivedIds:-' + r.archivedIds);
                for (Visit_Task__c item : scope) {
                    if(r.archivedIds.contains(item.id)){
                        visitIdSet.add(item.Visit__c);
                        visitTasksToUpdate.add(new Visit_Task__c(
                            Id = item.Id,
                            Archived__c = true,
                            Archived_Date__c = archivedTimestamp
                        ));
                    }
                }
                totalArchived += visitTasksToUpdate.size();
                TriggerBypass.bypassed.add('Visit_Task__c');   // bypass ON (visit task triggers)
                TriggerBypass.bypassed.add('Visit__c');       // bypass ON (visit triggers)
                Database.update(visitTasksToUpdate, false);
                
                for(Visit__c v : [SELECT Id, Count_of_Completed_No_Order_Task__c, Count_of_Cancelled_Task__c, Count_of_Completed_Order_Task__c,
                                   Count_of_In_Progress_Task__c, Count_of_Not_Started_Task__c, Total_Ad_Hoc_Visits__c,
                                   Total_Check_In_and_Check_Out_Time__c, Total_Planned_Visit__c, Total_Tasks_for_Visit__c
                                   FROM Visit__c WHERE Id IN :visitIdSet]){
                    v.Snapshot_Count_Completed_No_Order_Task__c   = v.Count_of_Completed_No_Order_Task__c;
                    v.Snapshot_Count_of_Cancelled_Task__c         = v.Count_of_Cancelled_Task__c;
                    v.Snapshot_Count_of_Completed_Order_Task__c   = v.Count_of_Completed_Order_Task__c;
                    v.Snapshot_Count_of_In_Progress_Task__c       = v.Count_of_In_Progress_Task__c;
                    v.Snapshot_Count_of_Not_Started_Task__c       = v.Count_of_Not_Started_Task__c;
                    v.Snapshot_Total_Ad_Hoc_Visit__c              = v.Total_Ad_Hoc_Visits__c;
                    v.Snapshot_Total_Check_In_Check_Out_Time__c   = v.Total_Check_In_and_Check_Out_Time__c;
                    v.Snapshot_Total_Planned_Visit__c             = v.Total_Planned_Visit__c;
                    v.Snapshot_Total_Tasks_for_Visit__c           = v.Total_Tasks_for_Visit__c;
                    visitsToUpdate.add(v);
                }

                if(!visitsToUpdate.isEmpty()){
                    update visitsToUpdate;
                }

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
            Archived_Object__c    = 'Visit_Task__c',
            Error_Message__c      = errorMessages.isEmpty() ? null : String.join(errorMessages, '; '),
            Total_Archived__c     = totalArchived,
            Total_Failed__c       = totalFailed,
            Total_Processed__c    = totalProcessed
        );
        insert ajl;
    }

     global void execute(SchedulableContext sc) {
        Database.executeBatch(new ArchiveVisitTasksBatch(), 200);
    }
}