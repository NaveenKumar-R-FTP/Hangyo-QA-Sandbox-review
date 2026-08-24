@isTest
public class InvoiceGRNControllerTest {

    @isTest
    static void testCheckExistingGRN() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Order__c order = new Order__c(Account__c = acc.Id, Total_Quantity__c = 50);
        insert order;

        Invoice__c invoice = new Invoice__c(Order__c = order.Id, RecordTypeId = Schema.SObjectType.Invoice__c.getRecordTypeInfosByDeveloperName().get('Primary_Invoice').getRecordTypeId());
        insert invoice;

        // Check before GRN exists
        Map<String, Object> resultBefore = InvoiceGRNController.checkExistingGRN(invoice.Id);
        System.assertEquals(false, resultBefore.get('grnExists'), 'GRN should not exist at first.');

        // Create GRN record to simulate existing
        Good_receipt_notes__c grn = new Good_receipt_notes__c(Order__c = order.Id, Invoice__c = invoice.Id);
        insert grn;

        // Check after GRN exists
        Map<String, Object> resultAfter = InvoiceGRNController.checkExistingGRN(invoice.Id);
        System.assertEquals(true, resultAfter.get('grnExists'), 'GRN should exist after insertion.');
    }

    @isTest
    static void testGetInvoiceLineItems() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Order__c order = new Order__c(Account__c = acc.Id, Total_Quantity__c = 20);
        insert order;

        Product__c prod = new Product__c(Name = 'Test Product', Image_Long__c = 'http://example.com/img.png');
        insert prod;

        Order_Line_Item__c oli = new Order_Line_Item__c(Order__c = order.Id, Products__c = prod.Id, Ordered_Quantity__c = 10);
        insert oli;

        Invoice__c invoice = new Invoice__c(Order__c = order.Id, RecordTypeId = Schema.SObjectType.Invoice__c.getRecordTypeInfosByDeveloperName().get('Primary_Invoice').getRecordTypeId());
        insert invoice;

        Invoice_Line_Item__c ili = new Invoice_Line_Item__c(Invoice__c = invoice.Id, Product__c = prod.Id, Quantity__c = 5);
        insert ili;

        Test.startTest();
        List<InvoiceGRNController.InvoiceLineWrapper> wrappers = InvoiceGRNController.getInvoiceLineItems(invoice.Id);
        Test.stopTest();

        System.assertEquals(1, wrappers.size(), 'Should return one invoice line item');
        System.assertEquals(prod.Id, wrappers[0].ProductId, 'Product Id should match');
        System.assertEquals(prod.Name, wrappers[0].ProductName, 'Product Name should match');
        System.assertEquals(oli.Ordered_Quantity__c, wrappers[0].OrderQuantity, 'Order quantity should match');
    }

    @isTest
    static void testSubmitGRN() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Order__c order = new Order__c(Account__c = acc.Id, Total_Quantity__c = 50);
        insert order;

        Product__c prod = new Product__c(Name = 'Test Product', Image_Long__c = 'http://example.com/img.png');
        insert prod;

        Order_Line_Item__c oli = new Order_Line_Item__c(Order__c = order.Id, Products__c = prod.Id, Ordered_Quantity__c = 20);
        insert oli;

        Invoice__c invoice = new Invoice__c(Order__c = order.Id, Total_Quantity__c = 20, RecordTypeId = Schema.SObjectType.Invoice__c.getRecordTypeInfosByDeveloperName().get('Primary_Invoice').getRecordTypeId());
        insert invoice;

        Invoice_Line_Item__c ili = new Invoice_Line_Item__c(Invoice__c = invoice.Id, Product__c = prod.Id, Quantity__c = 5);
        insert ili;

        // Create wrapper list
        List<InvoiceGRNController.InvoiceLineWrapper> wrapperList = new List<InvoiceGRNController.InvoiceLineWrapper>();

        InvoiceGRNController.InvoiceLineWrapper wrapper = new InvoiceGRNController.InvoiceLineWrapper();
        wrapper.Id = ili.Id;
        wrapper.ProductId = prod.Id;
        wrapper.ProductName = prod.Name;
        wrapper.ReceivedQuantity = 5;
        wrapper.Comment = 'All good';
        wrapperList.add(wrapper);

        String jsonLineItems = JSON.serialize(wrapperList);

        Test.startTest();
        InvoiceGRNController.submitGRN(invoice.Id, jsonLineItems, '5');
        Test.stopTest();

        Good_receipt_notes__c grn = [SELECT Id, Invoice__c FROM Good_receipt_notes__c WHERE Invoice__c = :invoice.Id LIMIT 1];
        System.assertNotEquals(null, grn, 'GRN should have been created.');

        Invoice_Line_Item__c updatedIli = [SELECT Received_Quantity__c, GRN_Comment__c FROM Invoice_Line_Item__c WHERE Id = :ili.Id];
        System.assertEquals(5, updatedIli.Received_Quantity__c, 'Received quantity should be updated.');
        System.assertEquals('All good', updatedIli.GRN_Comment__c, 'Comment should match.');
    }
}