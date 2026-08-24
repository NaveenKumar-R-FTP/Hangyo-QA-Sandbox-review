@isTest
public with sharing class CompetitorLineItemControllerTest {

    /**
     * Test method for createCompetitorWithLineItems
     */
    @isTest
    static void testCreateCompetitorWithLineItems() {
        // Step 1: Create test data
        Account retailer = new Account(Name = 'Test Retailer',PAN_Number__c = 'asd55');
        insert retailer;
        
         Visit__c visit = new Visit__c();
        insert visit;
            
        Visit_Task__c visitTask = new Visit_Task__c(Retailer__c = retailer.Id,Visit__c = visit.Id);
        insert visitTask;
        
        // Create list of LineItemWrapper
        List<CompetitorLineItemController.LineItemWrapper> lineItems = new List<CompetitorLineItemController.LineItemWrapper>();
        
        CompetitorLineItemController.LineItemWrapper item1 = new CompetitorLineItemController.LineItemWrapper();
        item1.brand = 'Brand A';
        item1.quantity = 10;
        item1.description = 'Test description';
        
        CompetitorLineItemController.LineItemWrapper item2 = new CompetitorLineItemController.LineItemWrapper();
        item2.brand = 'Brand B';
        item2.quantity = 5;
        item2.description = 'Another description';
        
        lineItems.add(item1);
        lineItems.add(item2);
        
        Test.startTest();
        // Step 2: Call the method under test
        Competitor__c competitor = CompetitorLineItemController.createCompetitorWithLineItems(visitTask.Id, lineItems);
        Test.stopTest();
        
        // Step 3: Assertions
        System.assertNotEquals(null, competitor, 'Competitor record should be created.');
        System.assertEquals(visitTask.Id, competitor.Visit_Task__c, 'Competitor should be linked to the correct Visit Task.');
        System.assertEquals(retailer.Id, competitor.Retailer_Account__c, 'Competitor should be linked to the correct Retailer.');
        
        // Verify Competitor Line Items
        List<Competitor_Line_Item__c> insertedLineItems = [SELECT Id, Brand__c, Quantity__c, Description__c FROM Competitor_Line_Item__c WHERE Competitor_Information__c = :competitor.Id];
        System.assertEquals(2, insertedLineItems.size(), 'There should be two Competitor Line Items created.');
        
        System.assertEquals('Brand A', insertedLineItems[0].Brand__c, 'First line item brand should be Brand A.');
        System.assertEquals(10, insertedLineItems[0].Quantity__c, 'First line item quantity should be 10.');
        System.assertEquals('Test description', insertedLineItems[0].Description__c, 'First line item description should match.');
    }
}