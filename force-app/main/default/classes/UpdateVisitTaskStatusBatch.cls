/**
* Class Name  : UpdateVisitTaskStatusBatch
* Test Class  : UpdateVisitTaskStatusBatchTest
* author      : Shyam
* CreatedDate : 15-01-25
* Description : This is to made the all Visit Tasks status as Cancelled If they are not Completed.
                
* */
public class UpdateVisitTaskStatusBatch implements Database.Batchable<SObject> {
    
    public String query;

    public UpdateVisitTaskStatusBatch() {
        query = 'SELECT Id, Status__c,Retailer__c,Account__c, Visit__r.Status__c FROM Visit_Task__c WHERE Status__c  NOT IN (\'Completed - Order\', \'Completed - No Order\') AND Account__c != NULL AND Task_Planned_Date__c < TODAY';
    }
    // Start method
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(query); 
    }

    // Execute method 
    public void execute(Database.BatchableContext bc, List<Visit_Task__c> scope) {
        List<Visit_Task__c> tasksToUpdate = new List<Visit_Task__c>();
        Set<Id> visitIds = new Set<Id>(); // To track unique Visit Ids
        List<Visit__c> visitsToUpdate = new List<Visit__c>(); // List to update Visit__c records


        // Loop through the records in the scope
        for (Visit_Task__c task : scope) {
            // Set the status to "Cancelled" if it doesn't match the allowed statuses
            task.Status__c = 'Cancelled';
            task.Account__c = task.Retailer__c;
            tasksToUpdate.add(task);
            
            // Add the Visit Id to the set (to ensure uniqueness)
            if (task.Visit__r != null && !visitIds.contains(task.Visit__r.Id)) {
                visitIds.add(task.Visit__r.Id); // Add unique Visit Id
                Visit__c visit = new Visit__c(
                    Id = task.Visit__r.Id,
                    Status__c = 'Completed' // Update Visit's status to 'Completed'
                );
                visitsToUpdate.add(visit);
            }
        }

        // Update the Visit_Task__c records
        if (!tasksToUpdate.isEmpty()) {
            update tasksToUpdate;
        }

        // Update the Visit__c records (only if there's at least one Visit to update)
        if (!visitsToUpdate.isEmpty()) {
            update visitsToUpdate;
        }
    }


    // Finish method
    public void finish(Database.BatchableContext bc) {
        System.debug('Batch finished at ' + System.now());
    }
}