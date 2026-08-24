public without sharing class MigrationDeleteScheduler implements Schedulable {

    private static final Integer MAX_CONCURRENT_JOBS = 2;
    private static final String CRON_EVERY_30_MIN = '0 0/30 * * * ?';
    private static final String JOB_NAME = 'Migration Delete Batch Driver';

    public void execute(SchedulableContext sc) {
        List<Azure_Archive_Config__mdt> enabled = [
            SELECT Object_API_Name__c, Batch_Scope_Size__c
            FROM Azure_Archive_Config__mdt
            WHERE Migration_Delete_Enabled__c = true
            ORDER BY Order__c ASC
        ];

        Integer launched = 0;
        for (Azure_Archive_Config__mdt cfg : enabled) {
            if (launched >= MAX_CONCURRENT_JOBS) {
                break;
            }
            Integer scopeSize = (cfg.Batch_Scope_Size__c == null || cfg.Batch_Scope_Size__c <= 0)
                ? 200
                : Integer.valueOf(cfg.Batch_Scope_Size__c);
            Database.executeBatch(new MigrationDeleteBatch(cfg.Object_API_Name__c), scopeSize);
            launched++;
        }
    }

    public static Id scheduleRecurring() {
        List<CronTrigger> existing = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
            AND State != 'DELETED'
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }
        return System.schedule(JOB_NAME, CRON_EVERY_30_MIN, new MigrationDeleteScheduler());
    }
}