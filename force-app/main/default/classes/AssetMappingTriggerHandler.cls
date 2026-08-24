public class AssetMappingTriggerHandler {
    public static Boolean isRunning = false;
    
    public static void updateDistributor(List<Asset_Mapping__c> newMappings, Map<Id, Asset_Mapping__c> oldMap) {
        Set<Id> retailerIds = new Set<Id>();
        List<Asset_Mapping__c> mappingsToProcess = new List<Asset_Mapping__c>();
        
        for (Asset_Mapping__c am : newMappings) {
            Asset_Mapping__c oldAm = oldMap != null ? oldMap.get(am.Id) : null;
            if (am.Retailer__c != null && 
                (oldAm == null || am.Retailer__c != oldAm.Retailer__c)) {
                retailerIds.add(am.Retailer__c);
                mappingsToProcess.add(am);
            }
        }
        
        if (!retailerIds.isEmpty()) {
            Map<Id, Id> retailerToDistributor = new Map<Id, Id>();
            for (Account acc : [
                SELECT Id, Distributor__c
                FROM Account
                WHERE Id IN :retailerIds
                AND Distributor__c != null
            ]) {
                retailerToDistributor.put(acc.Id, acc.Distributor__c);
            }
            
            if (!retailerToDistributor.isEmpty()) {
                List<Asset_Mapping__c> mappingsToUpdate = new List<Asset_Mapping__c>();
                for (Asset_Mapping__c am : mappingsToProcess) {
                    Id distributorId = retailerToDistributor.get(am.Retailer__c);
                    if (distributorId != null && distributorId != am.Distributor__c) {
                        mappingsToUpdate.add(new Asset_Mapping__c(
                            Id = am.Id,
                            Distributor__c = distributorId
                        ));
                    }
                }
                if (!mappingsToUpdate.isEmpty()) {
                    update mappingsToUpdate;
                }
            }
        }
        
        // Update Number_of_Assets__c on distributor accounts
        Set<Id> distributorIds = new Set<Id>();
        for (Asset_Mapping__c am : newMappings) {
            if (am.Distributor__c != null) distributorIds.add(am.Distributor__c);
            if (oldMap != null && oldMap.get(am.Id)?.Distributor__c != null) {
                distributorIds.add(oldMap.get(am.Id).Distributor__c);
            }
        }
        if (!distributorIds.isEmpty()) {
            Map<Id, Integer> countMap = new Map<Id, Integer>();
            for (AggregateResult ar : [
                SELECT Distributor__c accId, COUNT(Id) total
                FROM Asset_Mapping__c
                WHERE Distributor__c IN :distributorIds
                AND Retailer__c = null
                AND Active__c = true
                GROUP BY Distributor__c
            ]) {
                countMap.put((Id)ar.get('accId'), (Integer)ar.get('total'));
            }
            List<Account> accountsToUpdate = new List<Account>();
            for (Id distId : distributorIds) {
                accountsToUpdate.add(new Account(
                    Id = distId,
                    Number_of_Assets__c = countMap.containsKey(distId) ? countMap.get(distId) : 0
                ));
            }
            update accountsToUpdate;
        }
        
        // Update Number_of_Assets__c on retailer accounts
        Set<Id> retailerAccountIds = new Set<Id>();
        for (Asset_Mapping__c am : newMappings) {
            if (am.Retailer__c != null) retailerAccountIds.add(am.Retailer__c);
            if (oldMap != null && oldMap.get(am.Id)?.Retailer__c != null) {
                retailerAccountIds.add(oldMap.get(am.Id).Retailer__c);
            }
        }
        if (!retailerAccountIds.isEmpty()) {
            Map<Id, Integer> retailerCountMap = new Map<Id, Integer>();
            for (AggregateResult ar : [
                SELECT Retailer__c accId, COUNT(Id) total
                FROM Asset_Mapping__c
                WHERE Retailer__c IN :retailerAccountIds
                AND Active__c = true
                GROUP BY Retailer__c
            ]) {
                retailerCountMap.put((Id)ar.get('accId'), (Integer)ar.get('total'));
            }
            List<Account> retailersToUpdate = new List<Account>();
            for (Id retId : retailerAccountIds) {
                retailersToUpdate.add(new Account(
                    Id = retId,
                    Number_of_Assets__c = retailerCountMap.containsKey(retId) ? retailerCountMap.get(retId) : 0
                ));
            }
            update retailersToUpdate;
        }
        
        // Update Number_of_Assets__c on super stockist accounts
        Set<Id> ssIds = new Set<Id>();
        for (Asset_Mapping__c am : newMappings) {
            if (am.Super_Stockist__c != null) ssIds.add(am.Super_Stockist__c);
            if (oldMap != null && oldMap.get(am.Id)?.Super_Stockist__c != null) {
                ssIds.add(oldMap.get(am.Id).Super_Stockist__c);
            }
        }
        if (!ssIds.isEmpty()) {
            Map<Id, Integer> ssCountMap = new Map<Id, Integer>();
            for (AggregateResult ar : [
                SELECT Super_Stockist__c accId, COUNT(Id) total
                FROM Asset_Mapping__c
                WHERE Super_Stockist__c IN :ssIds
                AND Active__c = true
                GROUP BY Super_Stockist__c
            ]) {
                ssCountMap.put((Id)ar.get('accId'), (Integer)ar.get('total'));
            }
            List<Account> ssToUpdate = new List<Account>();
            for (Id ssId : ssIds) {
                ssToUpdate.add(new Account(
                    Id = ssId,
                    Number_of_Assets__c = ssCountMap.containsKey(ssId) ? ssCountMap.get(ssId) : 0
                ));
            }
            update ssToUpdate;
        }
    }
    /**
     * Recalculates Is_Branded__c for every account these mappings touch. Passing
     * oldMap matters: a freezer moved away from an outlet has to clear that
     * outlet's flag, not just set the new one.
     *
     * Historic records are handled once by AccountBrandedBackfillBatch.
     */
    public static void setAccountsBranded(
        List<Asset_Mapping__c> newMappings,
        Map<Id, Asset_Mapping__c> oldMap
    ) {
        AccountBrandingService.recalculate(
            AccountBrandingService.accountIdsFromMappings(newMappings, oldMap)
        );
    }

public static void validateDuplicateMapping(List<Asset_Mapping__c> newMappings, Map<Id, Asset_Mapping__c> oldMap) {
        Set<Id> assetMasterIds = new Set<Id>();
        Set<Id> newMappingIds = new Set<Id>();
        
        for (Asset_Mapping__c am : newMappings) {
            if (am.Asset_Master__c != null && am.Active__c == true) {
                assetMasterIds.add(am.Asset_Master__c);
            }
            if (am.Id != null) newMappingIds.add(am.Id);
        }
        
        if (assetMasterIds.isEmpty()) return;
        
        Map<Id, Asset_Mapping__c> existingActive = new Map<Id, Asset_Mapping__c>();
        for (Asset_Mapping__c existing : [
            SELECT Id, Asset_Master__c, Retailer__r.Name, Distributor__r.Name
            FROM Asset_Mapping__c
            WHERE Asset_Master__c IN :assetMasterIds
            AND Active__c = true
            AND Id NOT IN :newMappingIds
        ]) {
            existingActive.put(existing.Asset_Master__c, existing);
        }
        
        for (Asset_Mapping__c am : newMappings) {
            if (am.Active__c == true && am.Asset_Master__c != null
                && existingActive.containsKey(am.Asset_Master__c)) {
                Asset_Mapping__c existing = existingActive.get(am.Asset_Master__c);
                String location = existing.Retailer__r?.Name != null 
                    ? existing.Retailer__r.Name 
                    : existing.Distributor__r?.Name;
                am.addError('This QR code is already actively mapped to "' + location 
                    + '". Please deactivate the existing mapping first.');
            }
        }
    }
}