/**
* ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
* Class Name      : AccountBrandedBackfillBatch
* Description     : Recalculates Account.Is_Branded__c across the whole org.
*
*                   Branded means the account currently holds an active deep freezer
*                   (Asset_Mapping__c) or active branding material (Branding_Asset__c).
*                   Because it recalculates rather than only setting the flag on, it
*                   also clears accounts that were wrongly marked branded.
*
*                   Safe to re-run at any time - AccountBrandingService only writes
*                   where the flag actually differs.
*
* Usage           : Database.executeBatch(new AccountBrandedBackfillBatch(), 200);
* ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
*/
public without sharing class AccountBrandedBackfillBatch implements Database.Batchable<SObject>, Database.Stateful {

    private Integer accountsProcessed = 0;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Every account is in scope: some need branding set, others cleared.
        return Database.getQueryLocator([SELECT Id FROM Account]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        Set<Id> accountIds = new Set<Id>();
        for (Account acc : scope) {
            accountIds.add(acc.Id);
        }
        AccountBrandingService.recalculate(accountIds);
        accountsProcessed += accountIds.size();
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'AccountBrandedBackfillBatch complete. Accounts evaluated: ' + accountsProcessed);
    }
}