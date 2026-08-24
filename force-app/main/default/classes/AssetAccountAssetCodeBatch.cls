public class AssetAccountAssetCodeBatch implements Database.Batchable<SObject> {
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id 
            FROM Account 
            WHERE RecordType.DeveloperName = 'Retailer'
            AND Id IN (SELECT Retailer__c FROM Asset_Mapping__c WHERE Active__c = true)
        ]);
    }
    
    public void execute(Database.BatchableContext bc, List<Account> scope) {
        Set<Id> accountIds = new Set<Id>();
        for(Account acc : scope) {
            accountIds.add(acc.Id);
        }
        
        Map<Id, Integer> accountAssetCountMap = new Map<Id, Integer>();
        Map<Id, List<String>> accountAssetCodeMap = new Map<Id, List<String>>();
        
        for(Asset_Mapping__c mapping : [
            SELECT Id, Retailer__c, Asset_Master__r.OEM_Serial_Number__c
            FROM Asset_Mapping__c
            WHERE Retailer__c IN :accountIds
            AND Active__c = true
        ]) {
            Id accId = mapping.Retailer__c;
            accountAssetCountMap.put(accId, accountAssetCountMap.containsKey(accId) 
                ? accountAssetCountMap.get(accId) + 1 
                : 1);
            if(!accountAssetCodeMap.containsKey(accId)) {
                accountAssetCodeMap.put(accId, new List<String>());
            }
            if(mapping.Asset_Master__r.OEM_Serial_Number__c != null) {
                accountAssetCodeMap.get(accId).add(mapping.Asset_Master__r.OEM_Serial_Number__c);
            }
        }
        
        List<Account> accountsToUpdate = new List<Account>();
        for(Id accId : accountIds) {
            Integer countVal = accountAssetCountMap.containsKey(accId) 
                ? accountAssetCountMap.get(accId) 
                : 0;
            List<String> codes = accountAssetCodeMap.get(accId);
            String allCodes = (codes != null && !codes.isEmpty()) 
                ? String.join(codes, ', ') 
                : null;
            accountsToUpdate.add(new Account(
                Id = accId,
                Number_of_Assets__c = countVal,
                Asset_Code__c = allCodes
            ));
        }
        if(!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('Batch completed: Number_of_Assets__c and Asset_Code__c updated for all Retailer Accounts.');
    }
}