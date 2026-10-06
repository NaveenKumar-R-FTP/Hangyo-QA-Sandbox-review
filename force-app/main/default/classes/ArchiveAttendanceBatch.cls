global class ArchiveAttendanceBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful, Schedulable {

    private Integer totalProcessed = 0;
    private Integer totalArchived = 0;
    private Integer totalFailed = 0;
    private List<String> errorMessages = new List<String>();

    global Database.QueryLocator start(Database.BatchableContext bc) {
        Azure_Archive_Config__mdt confg = Azure_Archive_Config__mdt.getInstance('Attendance');

        Date cutoffDate = Date.today().addDays(-(Integer)confg.Retention_Days__c);

        Map<String, Schema.SObjectField> fieldMap = Attendance__c.SObjectType.getDescribe().fields.getMap();
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
                        ' FROM Attendance__c ';
        if(!String.isBlank(confg.Closed_State_Values__c)){
            query += (String)confg.Closed_State_Values__c;
        }

        return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext bc,List<Attendance__c> scope) {
        DateTime archivedTimestamp = DateTime.now();
        List<Attendance__c> attendanceToUpdate = new List<Attendance__c>();
        totalProcessed += scope.size();

        ArchiveConnectorService.SendResult r = ArchiveConnectorService.send('Attendance__c', scope, bc.getJobId());

        if (r.success) {
            System.debug('success:-' + r.success);
            try {
                System.debug('scope:-' + scope);
                System.debug('archivedIds:-' + r.archivedIds);
                for (Attendance__c item : scope) {
                    if(r.archivedIds.contains(item.id)){
                        attendanceToUpdate.add(new Attendance__c(
                            Id = item.Id,
                            Archived__c = true,
                            Archived_Date__c = archivedTimestamp
                        ));
                    }
                }
                totalArchived += attendanceToUpdate.size();
                TriggerBypass.bypassed.add('Attendance__c'); // bypass ON (attendance triggers)
                Database.update(attendanceToUpdate, false);

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
            Archived_Object__c    = 'Attendance__c',
            Error_Message__c      = errorMessages.isEmpty() ? null : String.join(errorMessages, '; '),
            Total_Archived__c     = totalArchived,
            Total_Failed__c       = totalFailed,
            Total_Processed__c    = totalProcessed
        );
        insert ajl;
    }

     global void execute(SchedulableContext sc) {
        Database.executeBatch(new ArchiveAttendanceBatch(), 200);
    }
}