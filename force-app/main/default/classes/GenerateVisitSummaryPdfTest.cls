@isTest
public class GenerateVisitSummaryPdfTest {
    
    @isTest
    static void testGenerateVisitSummaryPdf() {
        // Step 1: Set up test data (Accounts, Orders, and Order Line Items)
        
        // Create a test Account for Distributor
        Account acc = new Account(
            Name = 'Test Distributor',
            RecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Distributor' AND SObjectType = 'Account' LIMIT 1].Id,
            Owners_Number__c = '123-456-7890'
        );
        insert acc;
        
        Product__c pro = new Product__c(Name = 'Product A');
        Product__c pro1 = new Product__c(Name = 'Product B');
        insert new List<Product__c>{pro, pro1};

        // Create an Order for that Account
        Order__c order = new Order__c(
            AccountId__c = acc.Id,
            EffectiveDate__c = Date.today(),
            Total_Quantity__c = 100,
            Total_Order_Value__c = 2000,
            Discount_Amount_Order__c = 200 , 
            RecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Secondary Order' AND SObjectType = 'Order__c' LIMIT 1].Id ,
            Type__c = 'Field Order'
        );
        insert order;

        // Create Order Line Items for the Order
        Order_Line_Item__c orderLine1 = new Order_Line_Item__c(
            Order__c = order.Id,
            Products__c = pro.Id,
            Product_Price__c = 20,
            Ordered_Quantity__c = 50 
        );

        Order_Line_Item__c orderLine2 = new Order_Line_Item__c(
            Order__c = order.Id,
            Products__c = pro1.Id,
            Product_Price__c = 30,
            Ordered_Quantity__c = 50
        );
        insert new List<Order_Line_Item__c>{orderLine1, orderLine2};

        // Step 2: Set up Visualforce page parameters
        Test.setCurrentPageReference(Page.VisitSummaryPdfPage); // Replace with the correct page name
        ApexPages.currentPage().getParameters().put('distributorId', acc.Id);
        ApexPages.currentPage().getParameters().put('orderDate', String.valueOf(order.EffectiveDate__c));

        // Step 3: Create instance of GenerateVisitSummaryPdf and verify values
        GenerateVisitSummaryPdf controller = new GenerateVisitSummaryPdf();

        // Step 4: Assert that values are set correctly
        System.assertEquals('Test Distributor', controller.distributorName);
        System.assertEquals('123-456-7890', controller.distributorPhone);
        System.assertEquals(1, controller.orders.size()); // There should be 1 order in this test
        System.assertEquals(2, controller.orders[0].Order_Line_Items__r.size()); // There should be 2 line items for the order
        System.assertEquals('Product A', controller.orders[0].Order_Line_Items__r[0].Products__r.Name);
        System.assertEquals('Product B', controller.orders[0].Order_Line_Items__r[1].Products__r.Name);
        
        // Step 5: Verify the formatted date
        System.assertEquals(Date.today().format(), controller.formattedOrderDate);
    }
}