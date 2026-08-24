@isTest
public class GRNUpdaterControllerTest {

    @isTest
    static void testGetOrderLineItems() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Order__c order = new Order__c(Account__c = acc.Id, Total_Quantity__c = 10);
        insert order;

        Product__c prod = new Product__c(Name = 'Test Product', Image__c = 'TestURL');
        insert prod;

        Order_Line_Item__c oli = new Order_Line_Item__c(
            Order__c = order.Id,
            Products__c = prod.Id,
            Ordered_Quantity__c = 5
        );
        insert oli;

        Test.startTest();
        List<GRNUpdaterController.OrderLineItemWrapper> result = GRNUpdaterController.getOrderLineItems(order.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(1, result.size(), 'Should return one item');
        System.assertEquals(oli.Id, result[0].Id, 'Wrapper ID should match');
        System.assertEquals(prod.Name, result[0].ProductName, 'Product name should match');
    }

    @isTest
    static void testCalculateTotals() {
        List<GRNUpdaterController.OrderLineItemWrapper> lineItems = new List<GRNUpdaterController.OrderLineItemWrapper>();

        GRNUpdaterController.OrderLineItemWrapper item1 = new GRNUpdaterController.OrderLineItemWrapper();
        item1.Quantity = 5;
        item1.UpdatedQuantity = 3;
        lineItems.add(item1);

        GRNUpdaterController.OrderLineItemWrapper item2 = new GRNUpdaterController.OrderLineItemWrapper();
        item2.Quantity = 10;
        item2.UpdatedQuantity = 7;
        lineItems.add(item2);

        Test.startTest();
        Map<String, Decimal> totals = GRNUpdaterController.calculateTotals(null, lineItems);
        Test.stopTest();

        System.assertEquals(15, totals.get('Total_Quantity__c'), 'Total quantity should be correct');
        System.assertEquals(10, totals.get('UpdatedQuantitySum'), 'Updated quantity sum should be correct');
    }

    @isTest
    static void testSubmitGRN() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Order__c order = new Order__c(Account__c = acc.Id, Total_Quantity__c = 10);
        insert order;

        Product__c prod = new Product__c(Name = 'Test Product', Image__c = 'TestURL');
        insert prod;

        Order_Line_Item__c oli = new Order_Line_Item__c(Order__c = order.Id, Products__c = prod.Id, Ordered_Quantity__c = 5);
        insert oli;

        List<GRNUpdaterController.OrderLineItemWrapper> lineItems = new List<GRNUpdaterController.OrderLineItemWrapper>();
        GRNUpdaterController.OrderLineItemWrapper wrapper = new GRNUpdaterController.OrderLineItemWrapper();
        wrapper.Id = oli.Id;
        wrapper.Quantity = 5;
        wrapper.UpdatedQuantity = 3;
        wrapper.Comment = 'Updated Quantity';
        lineItems.add(wrapper);

        String jsonLineItems = JSON.serialize(lineItems);

        Test.startTest();
        GRNUpdaterController.submitGRN(order.Id, jsonLineItems, '3');
        Test.stopTest();

        System.assert([SELECT COUNT() FROM Good_receipt_notes__c WHERE Order__c = :order.Id] > 0, 'GRN should be created');
    }
    
  @isTest
static void testCheckExistingGRN() {
    // Create a test Account
    Account acc = new Account(Name = 'Test Account');
    insert acc;

    // Create a test Order
    Order__c order = new Order__c(Account__c = acc.Id);
    insert order;

    // Fetch Record Type Developer Name (if applicable)
    String recordTypeName = [SELECT RecordType.DeveloperName FROM Order__c WHERE Id = :order.Id LIMIT 1].RecordType.DeveloperName;

    // Test without GRN record
    Map<String, Object> resultWithoutGRN = GRNUpdaterController.checkExistingGRN(order.Id);
    System.assertEquals(false, resultWithoutGRN.get('grnExists'), 'GRN should not exist initially');
    System.assertEquals(recordTypeName, resultWithoutGRN.get('recordTypeName'), 'RecordType should match');

    // Create a test Good_receipt_notes__c record
    Good_receipt_notes__c grn = new Good_receipt_notes__c(Order__c = order.Id);
    insert grn;

    // Test after creating GRN record
    Map<String, Object> resultWithGRN = GRNUpdaterController.checkExistingGRN(order.Id);
    System.assertEquals(true, resultWithGRN.get('grnExists'), 'GRN should exist after insertion');
    System.assertEquals(recordTypeName, resultWithGRN.get('recordTypeName'), 'RecordType should still match');
}

}