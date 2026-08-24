@isTest
public class ReturnsInvoiceVFControllerTest {

    @isTest
    static void testReturnsInvoiceVFController() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        // Create test accounts
        Account retailerAccount = new Account(Name = 'Retailer Account', Phone = '1234567890', Email__c = 'retailer@example.com');
        insert retailerAccount;

        Account distributorAccount = new Account(Name = 'Distributor Account', Phone = '0987654321', Email__c = 'distributor@example.com', Code__c = 'D123');
        insert distributorAccount;

        // Create a product
        Product__c prod = new Product__c(IsActive__c = true, Model_Name__c = 'Star', Product_Brand__c = 'CONE');
        insert prod;

        // Create order
        Order__c order = new Order__c(AccountId__c = retailerAccount.Id, Total_Order_Value__c = 100, Account__c = distributorAccount.Id);
        insert order;

        // Create invoice with tax values
        Invoice__c invoice = new Invoice__c(
            Order__c = order.Id,
            Invoice_Date__c = Date.today(),
            Invoice_Number__c = 'INV123',
            Retailer_Account__c = retailerAccount.Id,
            Distributor_Account__c = distributorAccount.Id,
            CGST_Amount__c = 9.00,
            SGST_Amount__c = 9.00,
            IGST_Amount__c = 0.00,
            CGST__c = 9,
            SGST__c = 9,
           
            Invoice_Amount_In_Words__c = 'One Hundred Eighteen Rupees'
        );
        insert invoice;

        // Create return record
        Returns__c returnRecord = new Returns__c(Order__c = order.Id, Invoice__c = invoice.Id);
        insert returnRecord;

        // Create return line item
        Return_Line_Item__c returnItem = new Return_Line_Item__c(
            Return__c = returnRecord.Id,
            Product__c = prod.Id,
            Total_returns__c = 5,
            Return_Amount__c = 100.00,
            Unit_Price__c = 20.00
        );
        insert returnItem;

        // Create custom setting for GST
        Order_tax_value__c gstSetting = new Order_tax_value__c(
            Name = 'General GST Settings',
            CGST__c = 9,
            SGST__c = 9,
            IGST__c = 18
        );
        insert gstSetting;

        Test.startTest();

        // Simulate VF page request
        ApexPages.currentPage().getParameters().put('recordId', returnRecord.Id);
        ReturnsInvoiceVFController controller = new ReturnsInvoiceVFController();

        Test.stopTest();

        // Assertions
        System.assertNotEquals(controller.order, null, 'Order should not be null');
        System.assertNotEquals(controller.invoice, null, 'Invoice should not be null');
        System.assertNotEquals(controller.orderItems, null, 'Order Items should not be null');
        System.assertEquals(controller.orderItems.size(), 1, 'There should be 1 return item');

        System.assertEquals(controller.totalQuantity, 5, 'Total quantity should be 5');
        System.assertEquals(controller.subtotal, 100.00, 'Subtotal should be 100.00');
        //System.assertEquals(controller.cgst, 9.00, 'CGST should be 9% of subtotal');
        //System.assertEquals(controller.sgst, 9.00, 'SGST should be 9% of subtotal');
        System.assertEquals(controller.total, 118.00, 'Total should be 118.00');
        System.assertNotEquals(controller.amountInWords, null, 'Amount in words should not be null');
    }
}