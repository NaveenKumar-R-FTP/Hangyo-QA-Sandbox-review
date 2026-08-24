public class UpdateRetailerAndAssetOwner {
    
    public static void syncOwnerAndEmployee(List<Beat__c> newList, Map<Id, Beat__c> oldMap) {
        for (Beat__c beat : newList) {
            Beat__c oldBeat = oldMap.get(beat.Id);

            Boolean ownerChanged = beat.OwnerId != oldBeat.OwnerId;
            Boolean employeeChanged = beat.Employee_Name__c != oldBeat.Employee_Name__c;

            // If OwnerId changed → update Employee__c to match
            if (ownerChanged && !employeeChanged) {
                beat.Employee_Name__c = beat.OwnerId;
            }
            // If Employee__c changed → update OwnerId to match
            else if (employeeChanged && !ownerChanged) {
                beat.OwnerId = beat.Employee_Name__c;
            }
        }
    }
    
    public static void retailerAndAssetOwnerUpdate(Set<Id> beatIds) {
        if (beatIds == null || beatIds.isEmpty()) return;

        // Get Beats
        Map<Id, Beat__c> beatMap = new Map<Id, Beat__c>(
            [SELECT Id, OwnerId, Distributor_Name__c FROM Beat__c WHERE Id IN :beatIds]
        );

        // Get Retailers related to Beats
        List<Account> retailers = [
            SELECT Id, OwnerId, Beats_Name__c, Distributor__c
            FROM Account
            WHERE Beats_Name__c IN :beatIds AND Record_type_Name__c = 'Retailer'
        ];
        
        List<Account> retailersWithOwnerChange = new List<Account>();
        List<Account> retailersWithOnlyDistributorChange = new List<Account>();
        
        Map<Id, Id> retailerOldOwnerMap = new Map<Id, Id>();
        for (Account retailer : retailers) {
            retailerOldOwnerMap.put(retailer.Id, retailer.OwnerId);
        }
        
        Set<Id> retailerIds = new Set<Id>();
        Map<Id, Id> retailerToDistributorMap = new Map<Id, Id>();
        
        // Prepare updates
        for (Account retailer : retailers) {
            Beat__c beat = beatMap.get(retailer.Beats_Name__c);
            if (beat == null) continue;
        
            Boolean ownerChanged = retailer.OwnerId != beat.OwnerId;
            Boolean distributorChanged = beat.Distributor_Name__c != null && retailer.Distributor__c != beat.Distributor_Name__c;
        
            if (ownerChanged) {
                retailer.OwnerId = beat.OwnerId;
                if (distributorChanged) {
                    retailer.Distributor__c = beat.Distributor_Name__c;
                }
                retailersWithOwnerChange.add(retailer);
            } else if (distributorChanged) {
                retailer.Distributor__c = beat.Distributor_Name__c;
                retailersWithOnlyDistributorChange.add(retailer);
            }
        
            retailerIds.add(retailer.Id);
            retailerToDistributorMap.put(retailer.Id, retailer.Distributor__c);
        }
        
        //Group retailers by original → new OwnerId
        Map<String, List<Account>> groupedRetailers = new Map<String, List<Account>>();
        for (Account acc : retailersWithOwnerChange) {
            Id oldOwnerId = retailerOldOwnerMap.get(acc.Id);
            String key = oldOwnerId + '-' + acc.OwnerId;
        
            if (!groupedRetailers.containsKey(key)) {
                groupedRetailers.put(key, new List<Account>());
            }
            groupedRetailers.get(key).add(acc);
        }
        
        List<Account> allRetailersToUpdate = new List<Account>();
        for (List<Account> groupAccount : groupedRetailers.values()) {
            allRetailersToUpdate.addAll(groupAccount);
        }
        
        if (!allRetailersToUpdate.isEmpty()) {
            Database.update(allRetailersToUpdate, false); // false = allow partial success
        }
        
        //Update retailers where only Distributor__c changed (safe to bulk update)
        if (!retailersWithOnlyDistributorChange.isEmpty()) {
            try {
                update retailersWithOnlyDistributorChange;
            } catch (DmlException e) {
                System.debug('Retailer Distributor update failed: ' + e.getMessage());
            }
        }
        
        // Map to hold Retailer → new Owner
        Map<Id, Id> retailerNewOwnerMap = new Map<Id, Id>();
        for (Account acc : retailers) {
            retailerNewOwnerMap.put(acc.Id, acc.OwnerId);
        }

        //Get Assets related to the updated Retailers
        List<Asset__c> assetsToUpdate = [
            SELECT Id, OwnerId, Retailer_Account__c, Distributor_Name__c 
            FROM Asset__c 
            WHERE Retailer_Account__c IN :retailerIds
        ];
    
        for (Asset__c asset : assetsToUpdate) {
            Id newOwnerId = retailerNewOwnerMap.get(asset.Retailer_Account__c);
            if (asset.OwnerId != newOwnerId) {
                asset.OwnerId = newOwnerId;
                asset.Salesman__c = newOwnerId; // Optional custom field
            }

            Id newDistributorId = retailerToDistributorMap.get(asset.Retailer_Account__c);
            if (asset.Distributor_Name__c != newDistributorId) {
                asset.Distributor_Name__c = newDistributorId;
            }
        }

        if (!assetsToUpdate.isEmpty()) {
            update assetsToUpdate;
        }
    }
    
    public static void updateDistributorOwnerFromBeat(Set<Id> beatIds) {
        if (beatIds == null || beatIds.isEmpty()) return;

        // Fetch Beats with Distributor
        Map<Id, Beat__c> beatMap = new Map<Id, Beat__c>(
            [SELECT Id, OwnerId, Employee_Name__c, Distributor_Name__c
             FROM Beat__c
             WHERE Id IN :beatIds
                   AND Distributor_Name__c != null]
        );

        // Collect Distributor Ids
        Set<Id> distributorIds = new Set<Id>();
        for (Beat__c b : beatMap.values()) {
            distributorIds.add(b.Distributor_Name__c);
        }

        if (distributorIds.isEmpty()) {
            return;
        }

        // Fetch Distributor Accounts
        Map<Id, Account> distributorMap = new Map<Id, Account>(
            [SELECT Id, OwnerId
             FROM Account
             WHERE Id IN :distributorIds]
             // Add RecordType filter here if applicable
        );

        List<Account> distributorsToUpdate = new List<Account>();

        for (Beat__c b : beatMap.values()) {
            Account dist = distributorMap.get(b.Distributor_Name__c);
            if (dist == null) continue;

            // Decide which field to drive the owner from (OwnerId or Employee_Name__c)
            Id desiredOwnerId = b.OwnerId;
            // If you prefer Employee_Name__c, comment above line and uncomment below:
            // Id desiredOwnerId = b.Employee_Name__c;

            if (desiredOwnerId != null && dist.OwnerId != desiredOwnerId) {
                dist.OwnerId = desiredOwnerId;
                distributorsToUpdate.add(dist);
            }
        }

        if (!distributorsToUpdate.isEmpty()) {
            Database.update(distributorsToUpdate, false); // allow partial success
        }
    }
}