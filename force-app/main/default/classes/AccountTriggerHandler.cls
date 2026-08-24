public class AccountTriggerHandler {
    public static void handleSuperStockistSharing(List<Account> newAccounts, Map<Id, Account> oldMap) {
        Set<Id> ssAccountIds = new Set<Id>();
        List<Account> accountsToProcess = new List<Account>();
        
        // Identify changed Accounts (logic is correct)
        for (Account acc : newAccounts) {
            Account oldAcc = (oldMap != null) ? oldMap.get(acc.Id) : null;
            if (oldAcc == null) { // Insert
                if (acc.Super_Stockist_Name__c != null) {
                    accountsToProcess.add(acc);
                    ssAccountIds.add(acc.Super_Stockist_Name__c);
                }
            } else { // Update
                if (acc.Super_Stockist_Name__c != oldAcc.Super_Stockist_Name__c) {
                    accountsToProcess.add(acc);
                    if (oldAcc.Super_Stockist_Name__c != null) ssAccountIds.add(oldAcc.Super_Stockist_Name__c);
                    if (acc.Super_Stockist_Name__c != null) ssAccountIds.add(acc.Super_Stockist_Name__c);
                }
            }
        }
        if (accountsToProcess.isEmpty()) return;
        
        // Validate Super Stockist Accounts (correct)
        Map<Id, Account> validSSAccounts = new Map<Id, Account>([
            SELECT Id FROM Account
            WHERE Id IN :ssAccountIds
            AND RecordType.DeveloperName = 'SuperStockist'
            AND IsPartner = true
        ]);
        
        // Get Portal Users for valid Super Stockists (correct)
        Map<Id, List<User>> accountIdToPortalUsers = new Map<Id, List<User>>();
        if (!validSSAccounts.isEmpty()) {
            for (User usr : [
                SELECT Id, Contact.AccountId
                FROM User
                WHERE Contact.AccountId IN :validSSAccounts.keySet()
                AND IsPortalEnabled = true
            ]) {
                Id accountId = usr.Contact.AccountId;
                if (!accountIdToPortalUsers.containsKey(accountId)) {
                    accountIdToPortalUsers.put(accountId, new List<User>());
                }
                accountIdToPortalUsers.get(accountId).add(usr);
            }
        }
        
        // Prepare sharing changes
        Map<Id, Set<Id>> accountToOldUserIds = new Map<Id, Set<Id>>(); // Track user-account pairs for deletion
        List<AccountShare> sharesToCreate = new List<AccountShare>();
        
        for (Account acc : accountsToProcess) {
            // SAFE: Handle null oldMap for inserts
            Account oldAcc = (oldMap != null) ? oldMap.get(acc.Id) : null;
            Id oldSSId = (oldAcc != null) ? oldAcc.Super_Stockist_Name__c : null;
            Id newSSId = acc.Super_Stockist_Name__c;
            
            // Remove old sharing ONLY for this account
            if (oldSSId != null && validSSAccounts.containsKey(oldSSId)) {
                List<User> oldUsers = accountIdToPortalUsers.get(oldSSId);
                if (oldUsers != null) {
                    // Track which users to remove FROM THIS ACCOUNT
                    accountToOldUserIds.put(acc.Id, new Set<Id>());
                    for (User u : oldUsers) {
                        accountToOldUserIds.get(acc.Id).add(u.Id);
                    }
                }
            }
            
            // Add new sharing
            if (newSSId != null && validSSAccounts.containsKey(newSSId)) {
                List<User> newUsers = accountIdToPortalUsers.get(newSSId);
                if (newUsers != null) {
                    for (User u : newUsers) {
                        sharesToCreate.add(createShare(acc.Id, u.Id));
                    }
                }
            }
        }
        
        // Delete OLD shares (using tracked account-user pairs)
        deleteExistingShares(accountToOldUserIds);
        
        // Insert NEW shares with error logging
        if (!sharesToCreate.isEmpty()) {
            Database.SaveResult[] results = Database.insert(sharesToCreate, false);
            // Add error logging here (e.g., send to monitoring system)
        }
    }
    
    // Create share record (unchanged)
    private static AccountShare createShare(Id accountId, Id userId) {
        return new AccountShare(
            AccountId = accountId,
            UserOrGroupId = userId,
            AccountAccessLevel = 'Edit',
            OpportunityAccessLevel = 'None',
            CaseAccessLevel = 'None',
            RowCause = Schema.AccountShare.RowCause.Manual
        );
    }
    
    // Delete shares using account-specific user IDs
    private static void deleteExistingShares(Map<Id, Set<Id>> accountToUserIds) {
        if (accountToUserIds.isEmpty()) return;
        
        List<AccountShare> sharesToDelete = new List<AccountShare>();
        for (AccountShare share : [
            SELECT Id, AccountId, UserOrGroupId
            FROM AccountShare
            WHERE AccountId IN :accountToUserIds.keySet()
            AND RowCause = 'Manual'
        ]) {
            // Delete ONLY if user ID matches the tracked list for this account
            if (accountToUserIds.get(share.AccountId).contains(share.UserOrGroupId)) {
                sharesToDelete.add(share);
            }
        }
        
        if (!sharesToDelete.isEmpty()) {
            delete sharesToDelete;
        }
    }
}