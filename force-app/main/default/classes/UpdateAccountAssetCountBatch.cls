public class UpdateAccountAssetCountBatch implements Database.Batchable<SObject> {
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT Id FROM Account WHERE RecordType.DeveloperName IN (\'Distributor\', \'SuperStockist\')'
        );
    }
    
    public void execute(Database.BatchableContext bc, List<Account> scope) {
        Set<Id> accountIds = new Set<Id>();
        for(Account acc : scope) {
            accountIds.add(acc.Id);
        }
        
        // Aggregate asset counts from Asset_Mapping__c
        Map<Id, Integer> accountAssetCountMap = new Map<Id, Integer>();
        for(AggregateResult ar : [
            SELECT Distributor__c accId, COUNT(Id) total
            FROM Asset_Mapping__c
            WHERE Distributor__c IN :accountIds
            AND Retailer__c = null
            AND Active__c = true
            GROUP BY Distributor__c
        ]) {
            accountAssetCountMap.put((Id)ar.get('accId'), (Integer)ar.get('total'));
        }
        
        // Prepare accounts for update
        List<Account> accountsToUpdate = new List<Account>();
        for(Id accId : accountIds) {
            Integer countVal = accountAssetCountMap.containsKey(accId) 
                ? accountAssetCountMap.get(accId) 
                : 0;
            accountsToUpdate.add(new Account(
                Id = accId,
                Number_of_Assets__c = countVal
            ));
        }
        
        if(!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('Batch completed: Number_of_Assets__c updated for all accounts.');
    }
}