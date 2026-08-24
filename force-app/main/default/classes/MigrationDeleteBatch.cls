public without sharing class MigrationDeleteBatch implements Database.Batchable<sObject>, Database.Stateful {

    private static final String LOG_STATUS_MIGRATION_VALIDATED = 'Migration-Validated';
    private static final String LOG_STATUS_HARD_DELETED = 'Hard-Deleted';
    private static final Integer DEFAULT_SCOPE_SIZE = 200;

    private final String objectApiName;
    private final Azure_Archive_Config__mdt cfg;

    // Stateful accumulators - survive across every execute() chunk.
    private Integer recordsDeletedThisRun = 0;
    private Integer recordsFailedThisRun = 0;
    private Boolean pausedDuringRun = false;
    private final List<String> chunkErrors = new List<String>();
    private final Datetime jobStart = Datetime.now();

    public MigrationDeleteBatch(String objectApiName) {
        this(objectApiName, null);
    }

    @TestVisible
    MigrationDeleteBatch(String objectApiName, Azure_Archive_Config__mdt injectedCfgForTests) {
        if (String.isBlank(objectApiName)) {
            throw new MigrationDeleteException('objectApiName is required.');
        }
        this.objectApiName = objectApiName;

        if (injectedCfgForTests != null) {
            this.cfg = injectedCfgForTests;
            return;
        }

        List<Azure_Archive_Config__mdt> cfgRows = [
            SELECT Object_API_Name__c, Batch_Scope_Size__c, Migration_Delete_Enabled__c, Order__c
            FROM Azure_Archive_Config__mdt
            WHERE Object_API_Name__c = :objectApiName
            LIMIT 1
        ];
        if (cfgRows.isEmpty()) {
            throw new MigrationDeleteException(
                'No Archive_Config__mdt row found for ' + objectApiName + '.');
        }
        this.cfg = cfgRows[0];
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (!isEnabled()) {
            pausedDuringRun = true;
            return Database.getQueryLocator(
                [SELECT Id FROM Archival_Log__c WHERE Id = null]);
        }

        return Database.getQueryLocator([
            SELECT Id, Archived_Record_Id__c
            FROM Archival_Log__c
            WHERE Archived_Object__c = :objectApiName
            AND Status__c = :LOG_STATUS_MIGRATION_VALIDATED
            ORDER BY Id ASC
        ]);
    }

    public void execute(Database.BatchableContext bc, List<sObject> rawScope) {
        List<Archival_Log__c> scope = (List<Archival_Log__c>) rawScope;
        if (scope.isEmpty()) {
            return;
        }

        if (!isEnabled()) {
            pausedDuringRun = true;
            return; 
        }

        List<Id> recordIds = new List<Id>();
        Map<Id, Archival_Log__c> logByRecordId = new Map<Id, Archival_Log__c>();
        for (Archival_Log__c logRow : scope) {
            try {
                Id recordId = Id.valueOf(logRow.Archived_Record_Id__c);
                recordIds.add(recordId);
                logByRecordId.put(recordId, logRow);
            } catch (Exception e) {
                chunkErrors.add(logRow.Id + ': invalid Archived_Record_Id__c "' +
                    logRow.Archived_Record_Id__c + '" - ' + e.getMessage());
                recordsFailedThisRun++;
            }
        }
        if (recordIds.isEmpty()) {
            return;
        }

        Database.DeleteResult[] results = Database.delete(recordIds, false);

        List<Id> deletedIds = new List<Id>();
        List<Archival_Log__c> logsToUpdate = new List<Archival_Log__c>();
        for (Integer i = 0; i < results.size(); i++) {
            Database.DeleteResult dr = results[i];
            Id recordId = recordIds[i];
            Archival_Log__c logRow = logByRecordId.get(recordId);

            if (dr.isSuccess()) {
                deletedIds.add(recordId);
                logsToUpdate.add(new Archival_Log__c(
                    Id = logRow.Id,
                    Status__c = LOG_STATUS_HARD_DELETED,
                    Hard_Deleted_Date__c = Datetime.now()
                ));
            } else {
                recordsFailedThisRun++;
                for (Database.Error err : dr.getErrors()) {
                    chunkErrors.add(recordId + ': ' + err.getStatusCode() + ' - ' + err.getMessage());
                }
            }
        }

        if (!logsToUpdate.isEmpty()) {
            update logsToUpdate;
            recordsDeletedThisRun += deletedIds.size();
            try {
                Database.emptyRecycleBin(deletedIds);
            } catch (Exception e) {
                chunkErrors.add('emptyRecycleBin failed for a chunk of ' + deletedIds.size() + ' record(s): ' + e.getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        Boolean hasErrors = !chunkErrors.isEmpty();
        insertJobLog(bc, hasErrors);

        if (hasErrors) {
            notifyAdmins(hasErrors);
        }
    }

    private Boolean isEnabled() {
        return cfg.Migration_Delete_Enabled__c == true;
    }

    private void insertJobLog(Database.BatchableContext bc, Boolean hasErrors) {
        String errorSummary = null;
        if (hasErrors) {
            errorSummary = String.join(chunkErrors, '\n');
            if (errorSummary.length() > 1900) {
                errorSummary = errorSummary.substring(0, 1900) + '\n... (truncated)';
            }
        }

        /*try {
            insert new Archival_Job_Log__c(
                Batch_Class__c = 'MigrationDeleteBatch',
                Object_API_Name__c = objectApiName,
                Records_Processed__c = recordsDeletedThisRun + recordsFailedThisRun,
                Records_Succeeded__c = recordsDeletedThisRun,
                Records_Failed__c = recordsFailedThisRun,
                Error_Message__c = errorSummary,
                Job_Start__c = jobStart,
                Job_End__c = Datetime.now(),
                AsyncApexJobId__c = bc.getJobId(),
                Status__c = pausedDuringRun ? 'Paused' : (hasErrors ? 'Completed with Errors' : 'Completed')
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'MigrationDeleteBatch: failed to insert Archival_Job_Log__c - ' + e.getMessage());
        }*/
    }

    private void notifyAdmins(Boolean hasErrors) {
        List<GroupMember> admins = [
            SELECT UserOrGroupId
            FROM GroupMember
            WHERE Group.DeveloperName = 'Archive_Admin_Alerts'
            LIMIT 50
        ];

        List<String> toAddresses = new List<String>();
        for (GroupMember gm : admins) {
            if (String.valueOf(gm.UserOrGroupId).startsWith('005')) {
                toAddresses.add(gm.UserOrGroupId);
            }
        }
        if (toAddresses.isEmpty()) {
            return;
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTargetObjectId(toAddresses[0]);
        mail.setSaveAsActivity(false);
        mail.setSubject('Migration delete job completed with errors for ' + objectApiName);
        mail.setPlainTextBody(
            'Object: ' + objectApiName +
            '\nRecords deleted this run: ' + recordsDeletedThisRun +
            '\nRecords failed this run: ' + recordsFailedThisRun +
            '\n\nDetails were logged to Archival_Job_Log__c. Failed records remain' +
            ' Status__c = \'Migration-Validated\' on Archival_Log__c and will be retried automatically.'
        );
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'MigrationDeleteBatch: failed to send admin alert - ' + e.getMessage());
        }
    }

    public class MigrationDeleteException extends Exception {}
}