public class AssetTriggerHandler {
    public static void updateAccountAssetCount(
        List<Asset__c> newList,
        List<Asset__c> oldList
    ) {
        
        if (newList == null && oldList == null) {
            return;
        }
        // Collect both Retailer and Distributor Account Ids
        Set<Id> accountIds = new Set<Id>();
        if (newList != null) {
            for (Asset__c a : newList) {
                if (a.Retailer_Account__c != null) {
                    accountIds.add(a.Retailer_Account__c);
                }
                if (a.Distributor_Name__c != null) {
                    accountIds.add(a.Distributor_Name__c);
                }
            }
        }
        if (oldList != null) {
            for (Asset__c a : oldList) {
                if (a.Retailer_Account__c != null) {
                    accountIds.add(a.Retailer_Account__c);
                }
                if (a.Distributor_Name__c != null) {
                    accountIds.add(a.Distributor_Name__c);
                }
            }
        }
        if (accountIds.isEmpty()) {
            return;
        }
        // Maps to store counts and asset codes
        Map<Id, Integer> accountAssetCountMap = new Map<Id, Integer>();
        Map<Id, List<String>> accountAssetCodeMap = new Map<Id, List<String>>();
        
        // Query assets linked to either Retailer or Distributor
        for (Asset__c asset : [
            SELECT Id,
                   Retailer_Account__c,
                   Distributor_Name__c,
                   Asset_Code__c
            FROM Asset__c
            WHERE Retailer_Account__c IN :accountIds
               OR Distributor_Name__c IN :accountIds
        ]) {
            // Priority logic: If both Retailer and Distributor are present, count only for Retailer
            Id targetAccountId = null;
            
            if (asset.Retailer_Account__c != null) {
                // Retailer takes priority
                targetAccountId = asset.Retailer_Account__c;
            } else if (asset.Distributor_Name__c != null) {
                // Only count for Distributor if Retailer is null
                targetAccountId = asset.Distributor_Name__c;
            }
            
            // Update count and codes for the target account
            if (targetAccountId != null) {
                accountAssetCountMap.put(
                    targetAccountId,
                    accountAssetCountMap.containsKey(targetAccountId)
                        ? accountAssetCountMap.get(targetAccountId) + 1
                        : 1
                );
                
                if (!accountAssetCodeMap.containsKey(targetAccountId)) {
                    accountAssetCodeMap.put(targetAccountId, new List<String>());
                }
                
                if (asset.Asset_Code__c != null) {
                    accountAssetCodeMap.get(targetAccountId).add(asset.Asset_Code__c);
                }
            }
        }
        
        // Prepare Account updates
        List<Account> accountsToUpdate = new List<Account>();
        for (Id accId : accountIds) {
            Integer countVal = accountAssetCountMap.containsKey(accId)
                ? accountAssetCountMap.get(accId)
                : 0;
            List<String> codes = accountAssetCodeMap.get(accId);
            String allCodes =
                (codes != null && !codes.isEmpty())
                ? String.join(codes, ', ')
                : null;
            accountsToUpdate.add(new Account(
                Id = accId,
                Number_of_Assets__c = countVal,
                Asset_Code__c = allCodes
            ));
        }
        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
    }
}