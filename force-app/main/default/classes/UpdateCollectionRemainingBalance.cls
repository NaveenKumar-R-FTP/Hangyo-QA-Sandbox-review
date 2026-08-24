global class UpdateCollectionRemainingBalance implements Database.Batchable<SObject>, Database.Stateful {

    // To store collections to update in execute method
    global List<Collection__c> collectionsToUpdate = new List<Collection__c>();

    // Start method: query all invoices with at least one collection
    global Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
            SELECT Id, Invoice_Amount__c,
                   (SELECT Id, Total_Amount__c , CreatedDate FROM Collections__r ORDER BY CreatedDate ASC, Id ASC)
            FROM Invoice__c
            WHERE Collected_Amount__c > 0
        ]);
    }

    // Execute method: process each batch of invoices
    global void execute(Database.BatchableContext BC, List<Invoice__c> scope) {
        for(Invoice__c inv : scope){
            Decimal remainingPayable = inv.Invoice_Amount__c;
            
            if(inv.Collections__r != null && !inv.Collections__r.isEmpty()){
                for(Collection__c col : inv.Collections__r){
                    remainingPayable -= col.Total_Amount__c;
                    col.Remaining_Balance__c = remainingPayable;
                    collectionsToUpdate.add(col);
                }
            }
        }

        // Update collections in bulk
        if(!collectionsToUpdate.isEmpty()){
            update collectionsToUpdate;
            collectionsToUpdate.clear(); // clear for next batch
        }
    }

    // Finish method
    global void finish(Database.BatchableContext BC) {
        System.debug('Batch job completed. Collections updated.');
    }
}