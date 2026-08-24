global class ArchiveInventoryAdjustmentsBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
   
    global Database.QueryLocator start(Database.BatchableContext bc) {

        Datetime cutoffDate = System.now().addDays(-90);

        return Database.getQueryLocator([
            SELECT Id,
                   Name,
                   CreatedDate
            FROM Inventory_Adjustment__c 
            WHERE CreatedDate < :cutoffDate
        ]);
    }

    global void execute(Database.BatchableContext bc,List<Inventory_Adjustment__c> scope) {


        String requestBody =JSON.serialize(scope);

        HttpRequest request = new HttpRequest();

        request.setEndpoint(
            'callout:Azure_Archive'
            + '/api/salesforce/archive'
        );

        request.setMethod('POST');

        request.setHeader(
            'Content-Type',
            'application/json'
        );

        request.setBody(requestBody);

        request.setTimeout(120000);

        Http http = new Http();

        HttpResponse response = http.send(request);

        if (response.getStatusCode() < 200 ||
            response.getStatusCode() >= 300) {

           system.debug('Error while Archiving');
        }

        
    }

    global void finish(Database.BatchableContext bc) {

        System.debug('Salesforce archival completed.');
    }

    
}