global class BatchUpdateLastConfirmedInvoiceDate implements Database.Batchable<SObject>, Database.Stateful {

    // Fixed date range: 1st August 2025 → today
    Date startDate = Date.newInstance(2025, 8, 1);
    Date endDate = System.today();

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Invoice_Date__c, Status__c, Retailer_Account__c, Under_SS__c
            FROM Invoice__c
            WHERE CreatedDate >= :startDate
              AND CreatedDate <= :endDate
              AND (Retailer_Account__c != null OR Under_SS__c != null)
              AND Status__c IN ('Confirmed', 'Delivered')
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Invoice__c> scope) {
        Map<Id, Date> accToLatestDate = new Map<Id, Date>();

        for (Invoice__c inv : scope) {
            Id accId;
            if (inv.Retailer_Account__c != null)
                accId = inv.Retailer_Account__c;
            else if (inv.Under_SS__c != null)
                accId = inv.Under_SS__c;

            if (accId != null && inv.Invoice_Date__c != null) {
                if (!accToLatestDate.containsKey(accId) || inv.Invoice_Date__c > accToLatestDate.get(accId)) {
                    accToLatestDate.put(accId, inv.Invoice_Date__c);
                }
            }
        }

        // Prepare Accounts to update
        List<Account> accToUpdate = new List<Account>();
        for (Id accId : accToLatestDate.keySet()) {
            accToUpdate.add(new Account(
                Id = accId,
                Last_Confirmed_Invoice_Date__c = accToLatestDate.get(accId)
            ));
        }

        if (!accToUpdate.isEmpty()) {
            try {
                update accToUpdate;
            } catch (Exception e) {
                System.debug('Error updating Accounts: ' + e.getMessage());
            }
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('✅ Batch completed: Updated Last Confirmed Invoice Date (1 Aug 2025 → Today).');
    }
}