@isTest
public class ExportInvoiceToExcelControllerTest {
    
    @isTest
    public static void testExportInvoiceToExcelController(){
        Account acc = new Account(
            Name = 'Test Distributor',
            RecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Distributor' AND SObjectType = 'Account' LIMIT 1].Id,
            Phone = '123-456-7890'
        );
        insert acc;
        
        Account accRetailer = new Account(
            Name = 'Test Retailer',
            RecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Retailer' AND SObjectType = 'Account' LIMIT 1].Id,
            Phone = '123-456-7890'
        );
        insert accRetailer;
        
        Product__c product1 = new Product__c(Name = 'Product 1', IsActive__c = true);
        Product__c product2 = new Product__c(Name = 'Product 2', IsActive__c = true);
        insert new List<Product__c>{product1, product2};
        
        //Secondary Order record  
        Order__c order = new Order__c(
            AccountId__c = acc.Id,
            Account__c = accRetailer.Id,
            EffectiveDate__c = Date.today(),
            Total_Quantity__c = 100,
            Total_Order_Value__c = 2000,
            Status__c = 'Delivered',
            RecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Secondary Order' AND SObjectType = 'Order__c' LIMIT 1].Id
        );
        insert order;
        
        // Create Order Line Items for the Order
        Order_Line_Item__c orderLine1 = new Order_Line_Item__c(
            Order__c = order.Id,
            Products__c = product1.Id,
            Product_Price__c = 20,
            Ordered_Quantity__c = 50 
        );

        Order_Line_Item__c orderLine2 = new Order_Line_Item__c(
            Order__c = order.Id,
            Products__c = product2.Id,
            Product_Price__c = 30,
            Ordered_Quantity__c = 50
        );
        insert new List<Order_Line_Item__c>{orderLine1, orderLine2};
            
        Invoice__c secInvoice = new Invoice__c(
            Name = 'INV0000900',
            Order__c = order.Id,
            Distributor_Account__c = acc.Id,
            Invoice_Number__c = 'INV0000900',
            Total_Quantity__c = 100,
            RecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Secondary Invoice' AND SObjectType = 'Invoice__c' LIMIT 1].Id ,
            Status__c = 'Confirmed'
        );
        insert secInvoice;
        
        // Create Order Line Items for the Order
        Invoice_Line_Item__c invoiceLine11 = new Invoice_Line_Item__c(
            Invoice__c = secInvoice.Id,
            Product__c = product1.Id,
            Quantity__c = 50 
        );

        Invoice_Line_Item__c invoiceLine12 = new Invoice_Line_Item__c(
            Invoice__c = secInvoice.Id,
            Product__c = product2.Id,
            Quantity__c = 50
        );
        insert new List<Invoice_Line_Item__c>{invoiceLine11, invoiceLine12};

        // Step 2: Set the orderId parameter for the controller
        Test.startTest();
        PageReference pageRef = Page.ExportExcel; // Replace with your actual Visualforce page name
        pageRef.getParameters().put('Id', secInvoice.Id);
        Test.setCurrentPage(pageRef);
        
        // Step 3: Create an instance of ExportExcelController
        ExportInvoiceToExcelController controller = new ExportInvoiceToExcelController();
        
        // Step 4: Validate the results
        // Check that the orderId is correctly set
        System.assertNotEquals(null, controller.invoiceId, 'orderId should not be null');
        System.assertEquals(secInvoice.Id, controller.invoiceId, 'orderId should match the expected order Id');
        
        // Check if orders list is populated
        System.assertNotEquals(null, controller.invoices, 'Orders should not be null');
        System.assertEquals(1, controller.invoices.size(), 'There should be one order in the orders list');
        
        // Check if the orderLineItems list is populated
        System.assertNotEquals(null, controller.invoiceLineItems, 'Order line items should not be null');
        System.assertEquals(2, controller.invoiceLineItems.size(), 'There should be two order line items');
        
        // Check the generated filename
        String filename = controller.invoices[0].Invoice_Number__c + '_InvoiceDetails.xls';
        String contentDisposition = ApexPages.currentPage().getHeaders().get('Content-Disposition');
        System.assert(contentDisposition.contains(filename), 'The filename in Content-Disposition should match the expected filename');
        
        Test.stopTest();
    }
        
}