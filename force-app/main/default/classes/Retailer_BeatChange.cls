public class Retailer_BeatChange {

    public static void retailerOwnerUpdate(Set<Id> accountIds) {
        // Fetch updated accounts with new beat
        List<Account> accountsToUpdate = new List<Account>();
        List<Asset__c> assetsToUpdate = new List<Asset__c>();

        // Map of BeatId to its Owner and Distributor
        Map<Id, Beat__c> beatMap = new Map<Id, Beat__c>();

        // Query Retailer Accounts and their new Beat
        List<Account> retailerAccounts = [
            SELECT Id, Beats_Name__c, 
                   Beats_Name__r.OwnerId, 
                   Beats_Name__r.Distributor_Name__c,
                   Record_type_Name__c
            FROM Account 
            WHERE Id IN :accountIds AND Record_type_Name__c = 'Retailer'
        ];

        // Prepare Beat Map
        Set<Id> beatIds = new Set<Id>();
        for (Account acc : retailerAccounts) {
            if (acc.Beats_Name__c != null) {
                beatIds.add(acc.Beats_Name__c);
            }
        }

        if (!beatIds.isEmpty()) {
            beatMap = new Map<Id, Beat__c>(
                [SELECT Id, OwnerId, Distributor_Name__c FROM Beat__c WHERE Id IN :beatIds]
            );
        }

        // Prepare updated Retailer Accounts
        for (Account acc : retailerAccounts) {
            if (acc.Beats_Name__c != null && beatMap.containsKey(acc.Beats_Name__c)) {
                Beat__c beat = beatMap.get(acc.Beats_Name__c);
                acc.OwnerId = beat.OwnerId;
                acc.Distributor__c = beat.Distributor_Name__c;
                accountsToUpdate.add(acc);
            }
        }

        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }

        // Fetch and update related Assets
        Map<Id, Account> updatedAccountsMap = new Map<Id, Account>(accountsToUpdate);

        List<Asset__C> relatedAssets = [
            SELECT Id, Retailer_Account__c, OwnerId, Distributor_Name__c 
            FROM Asset__c 
            WHERE Retailer_Account__c IN :updatedAccountsMap.keySet()
        ];

        for (Asset__c ast : relatedAssets) {
            Account acc = updatedAccountsMap.get(ast.Retailer_Account__c);
            ast.OwnerId = acc.OwnerId;
            ast.Distributor_Name__c = acc.Distributor__c;
            assetsToUpdate.add(ast);
        }

        if (!assetsToUpdate.isEmpty()) {
            update assetsToUpdate;
        }
    }
}