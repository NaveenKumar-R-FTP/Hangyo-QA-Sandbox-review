/*
 Created By : Fuzail
 Class Name : AccountOwnerSyncHandler
 Description : Updating the Assets OwnerId Related to the Account when changing the Account Owner .
 Created Date : 05/01/2026
*/
public class AccountOwnerSyncHandler {
    public static void syncRetailerAssetOwners(List<Account> newList,Map<Id, Account> oldMap){
        // Null Check 
        if (newList == null || oldMap == null) {
            return;
        }
        // Changing Account Owner 
        Map<Id, Id> accountToOwnerMap = new Map<Id, Id>();
        for (Account acc : newList) {
            if (!oldMap.containsKey(acc.Id)) {
                continue;
            }
            Account oldAcc = oldMap.get(acc.Id);
            // Owner changed
            if (acc.OwnerId != oldAcc.OwnerId) {
                accountToOwnerMap.put(acc.Id, acc.OwnerId);
            }
        }
        if (accountToOwnerMap.isEmpty()) {
            return;
        }
        List<Asset__c> assetsToUpdate = new List<Asset__c>();
		// For Retailers
        List<Asset__c> retailerAssets = [
            SELECT Id, OwnerId, Retailer_Account__c
            FROM Asset__c
            WHERE Retailer_Account__c IN :accountToOwnerMap.keySet()
        ];
        for (Asset__c asset : retailerAssets) {
            asset.OwnerId = accountToOwnerMap.get(asset.Retailer_Account__c);
            asset.Salesman__c = accountToOwnerMap.get(asset.Retailer_Account__c);
            assetsToUpdate.add(asset);
        }
        //For Distributor 
        List<Asset__c> distributorAssets = [
            SELECT Id, OwnerId, Distributor_Name__c, Retailer_Account__c
            FROM Asset__c
            WHERE Distributor_Name__c IN :accountToOwnerMap.keySet()
              AND Retailer_Account__c = NULL
        ];
        for (Asset__c asset : distributorAssets) {
            asset.OwnerId = accountToOwnerMap.get(asset.Distributor_Name__c);
            asset.Salesman__c = accountToOwnerMap.get(asset.Distributor_Name__c);
            assetsToUpdate.add(asset);
        }
        if (!assetsToUpdate.isEmpty()) {
            update assetsToUpdate;
        }
    }
}