/**
* @File Name : CompetitorLineItemController.cls
* @Description : Handles creating Competitor and Competitor Line Item records
* @Author :Ajay
* @Last Modified By :
* @Last Modified On :
**/

public with sharing class CompetitorLineItemController {

    /**
     * Method to create a Competitor record along with its Line Items
     * @param visitTaskId The Id of the Visit_Task__c record (passed from another component)
     * @param lineItems List of line items to create
     * @return Created Competitor__c record with its line items
     */
    @AuraEnabled
    public static Competitor__c createCompetitorWithLineItems(Id visitTaskId, List<LineItemWrapper> lineItems) {
        List<Visit_Task__c> visitTask = new List<Visit_Task__c>();
        Id RetailerId;
        if (visitTaskId == null || lineItems == null || lineItems.isEmpty()) {
system.debug('Invalid input: Visit Task ID and line items are required');
        }
        else{
            RetailerId = [SELECT id,Retailer__c from Visit_Task__c WHERE ID = :visitTaskId].Retailer__c;
        }

        // Step 1: Create Competitor Record
        Competitor__c competitor = new Competitor__c(
            Visit_Task__c = visitTaskId,
            Retailer_Account__c = RetailerId
        );

        insert competitor;

        // Step 2: Prepare Competitor Line Item Records
        List<Competitor_Line_Item__c> recordsToInsert = new List<Competitor_Line_Item__c>();

        for (LineItemWrapper item : lineItems) {
            if (item.quantity == null || item.quantity <= 0) {
                throw new AuraHandledException('Quantity must be greater than 0 for all selected brands.');
            }

            Competitor_Line_Item__c newRecord = new Competitor_Line_Item__c(
                Competitor_Information__c = competitor.Id,
                Brand__c = item.brand,
                Quantity__c = item.quantity,
                Description__c = item.description
            );
            recordsToInsert.add(newRecord);
        }

        // Insert Competitor Line Items
        if (!recordsToInsert.isEmpty()) {
            insert recordsToInsert;
        }

        return competitor; // Return created Competitor record
    }

    /**
     * Wrapper class to represent line item data sent from LWC
     */
    public class LineItemWrapper {
        @AuraEnabled
        public String brand { get; set; } // Selected Brand
        @AuraEnabled
        public Decimal quantity { get; set; } // Quantity entered by the user
        @AuraEnabled
        public String description { get; set; } // Optional description
    }
}