@isTest
public class ExportExcelControllerTest {
    
    @isTest
    public static void testExportExcelController() {
        Account acc = new Account(
            Name = 'Test Distributor',
            RecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Distributor' AND SObjectType = 'Account' LIMIT 1].Id,
            Phone = '123-456-7890'
        );
        insert acc;
        
        Product__c product1 = new Product__c(Name = 'Product 1', IsActive__c = true);
        Product__c product2 = new Product__c(Name = 'Product 2', IsActive__c = true);
        insert new List<Product__c>{product1, product2};
        
        //Secondary Order record  
        Order__c order = new Order__c(
            AccountId__c = acc.Id,
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

        // Step 2: Set the orderId parameter for the controller
        Test.startTest();
        PageReference pageRef = Page.ExportExcel; // Replace with your actual Visualforce page name
        pageRef.getParameters().put('Id', order.Id);
        Test.setCurrentPage(pageRef);
        
        // Step 3: Create an instance of ExportExcelController
        ExportExcelController controller = new ExportExcelController();
        
        // Step 4: Validate the results
        // Check that the orderId is correctly set
        System.assertNotEquals(null, controller.orderId, 'orderId should not be null');
        System.assertEquals(order.Id, controller.orderId, 'orderId should match the expected order Id');
        
        // Check if orders list is populated
        System.assertNotEquals(null, controller.orders, 'Orders should not be null');
        System.assertEquals(1, controller.orders.size(), 'There should be one order in the orders list');
        
        // Check if the orderLineItems list is populated
        System.assertNotEquals(null, controller.orderLineItems, 'Order line items should not be null');
        System.assertEquals(2, controller.orderLineItems.size(), 'There should be two order line items');
        
        // Check the generated filename
        String filename = controller.orders[0].Name + '_OrderDetails.xls';
        String contentDisposition = ApexPages.currentPage().getHeaders().get('Content-Disposition');
        System.assert(contentDisposition.contains(filename), 'The filename in Content-Disposition should match the expected filename');
        
        Test.stopTest();
    }
}