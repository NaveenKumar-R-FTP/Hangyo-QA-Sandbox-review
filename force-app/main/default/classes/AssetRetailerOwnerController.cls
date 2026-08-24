/*
 Created By : Fuzail 
 Class Name : AssetRetailerOwnerController
 Description :Synchronizes Asset__c ownership and Salesman__c with the owner of the related Retailer Account whenever the retailer mapping changes.
 Created Date : 05/01/2026
*/
public class AssetRetailerOwnerController {
    public static void syncSalesmanWithRetailerOwner(List<Asset__c> newList,Map<Id, Asset__c> oldMap ){
        Set<Id> retailerAccountIds = new Set<Id>();
        // Find records where Retailer_Account__c changed
        for (Asset__c newAsset : newList) {
            Asset__c oldAsset = oldMap.get(newAsset.Id);
            if (newAsset.Retailer_Account__c != oldAsset.Retailer_Account__c
                && newAsset.Retailer_Account__c != null) {
                retailerAccountIds.add(newAsset.Retailer_Account__c);
                retailerAccountIds.add(oldMap.get(newAsset.Id).Retailer_Account__c);
            }
        }
        if (retailerAccountIds.isEmpty()) {
            return;
        }
         // Fetch Account Owners
        Map<Id, Account> accountMap = new Map<Id, Account>(
            [
                SELECT Id, OwnerId
                FROM Account
                WHERE Id IN :retailerAccountIds
            ]
        );
        // Update Salesman__c and OwnerId
        for (Asset__c asset : newList) {
            Asset__c oldAsset = oldMap.get(asset.Id);
            if (asset.Retailer_Account__c != oldAsset.Retailer_Account__c
                && asset.Retailer_Account__c != null
                && accountMap.containsKey(asset.Retailer_Account__c)) {
                Id accountOwnerId = accountMap.get(asset.Retailer_Account__c).OwnerId;
                asset.Salesman__c = accountOwnerId;
                asset.OwnerId     = accountOwnerId;
            }
        }
    }
}