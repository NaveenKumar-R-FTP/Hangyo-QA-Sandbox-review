public without sharing class ArchivedRecordDeletionBatch implements Database.Batchable<SObject>, Database.Stateful {

    private static final Integer DEFAULT_SCOPE_SIZE = 200;
    private static final Integer DEFAULT_SOFT_ARCHIVE_DAYS = 7;
    private static final String DEFAULT_ARCHIVED_FIELD = 'Archived__c';
    private static final String DEFAULT_ARCHIVED_DATE_FIELD = 'Archived_Date__c';

    private final Azure_Archive_Config__mdt cfg;
    private final String objectApiName;
    private final String archivedFieldApiName;
    private final String archivedDateFieldApiName;
    private final Integer scopeSize;

    // Stateful accumulators - survive across every execute() chunk.
    private Integer recordsDeletedThisRun = 0;
    private Integer recordsFailedThisRun = 0;
    private final List<String> chunkErrors = new List<String>();
    private final Datetime jobStart = Datetime.now();

    /** Preferred entry point: pass the object's API name, config is looked up. */
    public ArchivedRecordDeletionBatch(String objectApiName) {
        this(loadConfig(objectApiName));
    }

    /** Test / advanced entry point: inject the mdt row directly. */
    @TestVisible
    ArchivedRecordDeletionBatch(Azure_Archive_Config__mdt injectedCfg) {
        if (injectedCfg == null) {
            throw new MigrationDeleteException(
                'No Azure_Archive_Config__mdt record found/provided for this object.');
        }

        this.cfg = injectedCfg;
        this.objectApiName = cfg.Object_API_Name__c;

        if (!isEnabled()) {
            throw new MigrationDeleteException(
                'Migration_Delete_Enabled__c is false for ' + objectApiName + '. Aborting batch.');
        }

        this.scopeSize = (cfg.Batch_Scope_Size__c != null)
            ? (Integer) cfg.Batch_Scope_Size__c
            : DEFAULT_SCOPE_SIZE;

        this.archivedFieldApiName = resolveOptionalField('Archived_Field_API_Name__c', DEFAULT_ARCHIVED_FIELD);
        this.archivedDateFieldApiName = resolveOptionalField('Archived_Date_Field_API_Name__c', DEFAULT_ARCHIVED_DATE_FIELD);

        validateObjectAndFields();
    }

    private static Azure_Archive_Config__mdt loadConfig(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            throw new MigrationDeleteException('objectApiName is required.');
        }

        List<Azure_Archive_Config__mdt> rows = [
            SELECT Object_API_Name__c, Batch_Scope_Size__c, Migration_Delete_Enabled__c,
                   Soft_Archive_Days__c, Order__c
            FROM Azure_Archive_Config__mdt
            WHERE Object_API_Name__c = :objectApiName
            LIMIT 1
        ];

        if (rows.isEmpty()) {
            throw new MigrationDeleteException(
                'No Azure_Archive_Config__mdt record found for Object_API_Name__c = ' + objectApiName);
        }

        return rows[0];
    }

    /**
     * Reads an optional override field off the mdt record via describe, so this
     * class still compiles/works even before those two optional fields exist.
     */
    private String resolveOptionalField(String mdtFieldApiName, String defaultValue) {
        Map<String, Schema.SObjectField> mdtFields =
            Azure_Archive_Config__mdt.SObjectType.getDescribe().fields.getMap();

        if (!mdtFields.containsKey(mdtFieldApiName)) {
            return defaultValue;
        }

        Object val = cfg.get(mdtFieldApiName);
        String strVal = (val == null) ? null : String.valueOf(val);
        return String.isBlank(strVal) ? defaultValue : strVal;
    }

    /** Fail fast with a clear message rather than a cryptic malformed-query error. */
    private void validateObjectAndFields() {
        Schema.DescribeSObjectResult objDescribe = describeObject(objectApiName);
        if (objDescribe == null) {
            throw new MigrationDeleteException('Unknown/inaccessible object: ' + objectApiName);
        }
        Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();
        if (!fieldMap.containsKey(archivedFieldApiName)) {
            throw new MigrationDeleteException(
                objectApiName + ' has no field ' + archivedFieldApiName +
                ' - set Archived_Field_API_Name__c on the config record.');
        }
        if (!fieldMap.containsKey(archivedDateFieldApiName)) {
            throw new MigrationDeleteException(
                objectApiName + ' has no field ' + archivedDateFieldApiName +
                ' - set Archived_Date_Field_API_Name__c on the config record.');
        }
        if (!objDescribe.isDeletable()) {
            throw new MigrationDeleteException(
                'Running user/context does not have delete access on ' + objectApiName);
        }
    }

    private Schema.DescribeSObjectResult describeObject(String apiName) {
        Schema.SObjectType sType = Schema.getGlobalDescribe().get(apiName);
        return (sType == null) ? null : sType.getDescribe();
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime cutoff = jobStart.addDays(-getSoftArchiveDays());

        String query =
            'SELECT Id, ' + archivedFieldApiName + ', ' + archivedDateFieldApiName +
            ' FROM ' + String.escapeSingleQuotes(objectApiName) +
            ' WHERE ' + archivedFieldApiName + ' = true' +
            ' AND ' + archivedDateFieldApiName + ' != null' +
            ' AND ' + archivedDateFieldApiName + ' < :cutoff' +
            ' ORDER BY Id ASC';

        System.debug('MigrationDeleteBatch running for: ' + objectApiName);
        System.debug('Query: ' + query);
        System.debug('cutoff (' + archivedDateFieldApiName + ' <): ' + cutoff);

        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (scope.isEmpty()) {
            return;
        }

        List<Id> recordIds = new List<Id>();
        for (SObject rec : scope) {
            recordIds.add(rec.Id);
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

    /** Exposed so scheduler/dispatcher classes can reuse the resolved scope size. */
    public Integer getScopeSize() {
        return scopeSize;
    }

    public String getObjectApiName() {
        return objectApiName;
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
            Archived_Object__c  = objectApiName,
            Error_Message__c    = errorSummary,
            Total_Archived__c   = 0,
            Total_Failed__c     = recordsFailedThisRun,
            Total_Processed__c  = recordsDeletedThisRun + recordsFailedThisRun,
            Deletion_Batch__c   = true
        );
        insert ajl;
    }

    public class MigrationDeleteException extends Exception {}
}