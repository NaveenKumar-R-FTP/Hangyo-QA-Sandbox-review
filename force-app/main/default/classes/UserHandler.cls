public without sharing class UserHandler {
    
    // Trigger handler method to check that only one primary distributor is checked
    public static void enforceSinglePrimaryDistributor(List<User> users) {
        Set<Id> partnerAccountIds = new Set<Id>();

        // Collect Partner Account Ids from records being inserted or updated
        for (User usr : users) {
            if (usr.Primary_Distributor__c == true && usr.AccountId != null) {
                partnerAccountIds.add(usr.AccountId);
            }
        }

        if (partnerAccountIds.isEmpty()) {
            return;
        }

        // Query existing users with Primary_Distributor__c = true for the same Partner Accounts
        Map<Id, User> existingPrimaryDistributors = new Map<Id, User>();
        List<User> existingUsers = [SELECT Id, AccountId 
                                    FROM User 
                                    WHERE AccountId IN :partnerAccountIds 
                                    AND Primary_Distributor__c = true];

        for (User existingUser : existingUsers) {
            existingPrimaryDistributors.put(existingUser.AccountId, existingUser);
        }

        // Validate if another user already has Primary_Distributor__c = true
        for (User usr : users) {
            if (usr.Primary_Distributor__c == true) {
                User existingUser = existingPrimaryDistributors.get(usr.AccountId);

                if (existingUser != null && existingUser.Id != usr.Id) {
                    usr.addError('Only one user can be set as the Primary User for this Partner Account.');
                }
            }
        }
    }
}