/**
 *   System.schedule('Migration Delete - Invoice Line Item',
 *       '0 0 2 * * ?',
 *       new MigrationDeleteScheduler('Invoice_Line_Item__c'));
 */
public without sharing class MigrationDeleteScheduler implements Schedulable {

    private final String objectApiName;

    public MigrationDeleteScheduler(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            throw new ArchivedRecordDeletionBatch.MigrationDeleteException('objectApiName is required.');
        }
        this.objectApiName = objectApiName;
    }

    public void execute(SchedulableContext sc) {
        ArchivedRecordDeletionBatch batch = new ArchivedRecordDeletionBatch(objectApiName);
        Database.executeBatch(batch, batch.getScopeSize());
    }
}