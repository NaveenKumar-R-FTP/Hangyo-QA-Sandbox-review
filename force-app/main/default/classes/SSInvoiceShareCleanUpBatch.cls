public class SSInvoiceShareCleanUpBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        /*Date twoDaysAgo = Date.today().addDays(-2);
        Date oneDayAgo = Date.today().addDays(-5);*/
        DateTime startDate = DateTime.newInstance(2026, 4, 10, 0, 0, 0); // 10 April 2026
        DateTime endDate = DateTime.newInstance(2026, 4, 16, 0, 0, 0);   // 16 April 2026

        String soql = 
            'SELECT Id, Name, Under_SS__c, Under_SS__r.Name, RecordType.Name ' +
            'FROM Invoice__c ' +
            'WHERE RecordType.Name = \'Secondary Invoice Under SS\' ' +
            'AND Under_SS__c != NULL AND Transaction_Type_Purchase__c != NULL AND Transaction_Type_Sale__c != NULL ';
    
        if (!Test.isRunningTest()) {
            //soql += 'AND LastModifiedDate >= :oneDayAgo';
            soql += 'AND CreatedDate >= :startDate ' + 'AND LastModifiedDate < :endDate';
            return Database.getQueryLocator(soql);
        } else {
            return Database.getQueryLocator(soql);
        }
    }

    public void execute(Database.BatchableContext bc, List<Invoice__c> scope) {
        Map<Id,Id> userSSwithInvoiceId = new Map<Id,Id>{};
        for(Invoice__c inv : scope){
            userSSwithInvoiceId.put(inv.Under_SS__c , inv.Id);
        }
        
        Map<Id, Id> underSsToPartnerUserMap = new Map<Id, Id>();
        List<User> partnerUsers = [
            SELECT Id , AccountId FROM User 
            WHERE AccountId IN : userSSwithInvoiceId.keySet() AND IsPartner = TRUE
        ];
        
        for (User usr : partnerUsers) {
            underSsToPartnerUserMap.put(usr.AccountId, usr.Id);
        }
        
        // Fetch all sharing rows for the invoice in scope
        List<Invoice__Share> sharesToDelete = new List<Invoice__Share>();
    
        List<Invoice__Share> existingShares = [
            SELECT Id, ParentId, UserOrGroupId
            FROM Invoice__Share
            WHERE ParentId IN :userSSwithInvoiceId.values() AND AccessLevel != 'All'
        ];
    
        // Loop through each sharing row
        for (Invoice__Share sh : existingShares) {
    
            // Get the Invoice’s Under_SS__c (Account)
            Id invoiceId = sh.ParentId;
    
            Id underSsAccount = null;
            for (Id accId : userSSwithInvoiceId.keySet()) {
                if (userSSwithInvoiceId.get(accId) == invoiceId) {
                    underSsAccount = accId;
                    break;
                }
            }
    
            // Partner user for this invoice
            Id expectedPartnerUser = underSsToPartnerUserMap.get(underSsAccount);
    
            // If shared to someone else → mark for deletion
            if (sh.UserOrGroupId != expectedPartnerUser) {
                sharesToDelete.add(sh);
            }
        }
    
        // Delete invalid sharing rows
        if (!sharesToDelete.isEmpty()) {
            delete sharesToDelete;
        }
        
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Batch Completed');
    }
}