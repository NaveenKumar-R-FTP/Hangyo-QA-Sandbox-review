public without sharing class MigrationDeleteBatch implements Database.Batchable<sObject>, Database.Stateful, Schedulable {

    private static final String OBJECT_API_NAME = 'Order_Line_Item__c';
    private static final Integer DEFAULT_SCOPE_SIZE = 200;
    private static final Integer DEFAULT_SOFT_ARCHIVE_DAYS = 7;

    private final Azure_Archive_Config__mdt cfg;

    // Stateful accumulators - survive across every execute() chunk.
    private Integer recordsDeletedThisRun = 0;
    private Integer recordsFailedThisRun = 0;
    private final List<String> chunkErrors = new List<String>();
    private final Datetime jobStart = Datetime.now();

    public MigrationDeleteBatch() {
        this(null);
    }

    @TestVisible
    MigrationDeleteBatch(Azure_Archive_Config__mdt injectedCfgForTests) {
        if (injectedCfgForTests != null) {
            this.cfg = injectedCfgForTests;
            return;
        }

        List<Azure_Archive_Config__mdt> cfgRows = [
            SELECT Object_API_Name__c, Batch_Scope_Size__c, Migration_Delete_Enabled__c,
                   Soft_Archive_Days__c, Order__c
            FROM Azure_Archive_Config__mdt
            WHERE Object_API_Name__c = :OBJECT_API_NAME
            LIMIT 1
        ];
        
        this.cfg = cfgRows[0];

        if (!isEnabled()) {
            throw new MigrationDeleteException(
                'Migration_Delete_Enabled__c is false for ' + OBJECT_API_NAME + '. Aborting batch.');
        }
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime cutoff = jobStart.addDays(-getSoftArchiveDays());

        System.debug('MigrationDeleteBatch running for: ' + OBJECT_API_NAME);
        System.debug('cutoff (Archived_Date__c <): ' + cutoff);

        return Database.getQueryLocator([
            SELECT Id, Archived__c, Archived_Date__c
            FROM Order_Line_Item__c
            WHERE Archived__c = true
            AND Archived_Date__c != null
            AND Archived_Date__c < :cutoff
            ORDER BY Id ASC
        ]);
    }

    public void execute(Database.BatchableContext bc, List<sObject> rawScope) {
        List<Order_Line_Item__c> scope = (List<Order_Line_Item__c>) rawScope;
        if (scope.isEmpty()) {
            return;
        }

        List<Id> recordIds = new List<Id>();
        for (Order_Line_Item__c oli : scope) {
            recordIds.add(oli.Id);
        }

        Database.DeleteResult[] results = Database.delete(recordIds, false);

        List<Id> deletedIds = new List<Id>();
        for (Integer i = 0; i < results.size(); i++) {
            Database.DeleteResult dr = results[i];
            Id recordId = recordIds[i];

            if (dr.isSuccess()) {
                deletedIds.add(recordId);
            } else {
                recordsFailedThisRun++;
                for (Database.Error err : dr.getErrors()) {
                    chunkErrors.add(recordId + ': ' + err.getStatusCode() + ' - ' + err.getMessage());
                }
            }
        }

        if (!deletedIds.isEmpty()) {
            recordsDeletedThisRun += deletedIds.size();
            try {
                Database.emptyRecycleBin(deletedIds);
            } catch (Exception e) {
                chunkErrors.add('emptyRecycleBin failed for a chunk of ' +
                    deletedIds.size() + ' record(s): ' + e.getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        Boolean hasErrors = !chunkErrors.isEmpty();
        insertJobLog(bc, hasErrors);
    }

    private Boolean isEnabled() {
        return cfg.Migration_Delete_Enabled__c == true;
    }

    private Integer getSoftArchiveDays() {
        return (cfg.Soft_Archive_Days__c != null)
            ? (Integer) cfg.Soft_Archive_Days__c
            : DEFAULT_SOFT_ARCHIVE_DAYS;
    }

    private void insertJobLog(Database.BatchableContext bc, Boolean hasErrors) {
        String errorSummary = null;
        if (hasErrors) {
            errorSummary = String.join(chunkErrors, '\n');
            if (errorSummary.length() > 1900) {
                errorSummary = errorSummary.substring(0, 1900) + '\n... (truncated)';
            }
        }

        Archival_Job_Log__c ajl = new Archival_Job_Log__c(
            Archive_Batch_Id__c = bc.getJobId(),
            Archived_Object__c  = OBJECT_API_NAME,
            Error_Message__c    = errorSummary,
            Total_Archived__c   = 0,
            Total_Failed__c     = recordsFailedThisRun,
            Total_Processed__c  = recordsDeletedThisRun + recordsFailedThisRun,
            Deletion_Batch__c   = true
        );
        insert ajl;
    }

    public class MigrationDeleteException extends Exception {}
    
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new MigrationDeleteBatch(), 200);
    }
}