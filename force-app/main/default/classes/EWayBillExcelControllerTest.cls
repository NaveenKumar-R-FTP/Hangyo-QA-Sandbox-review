/**
* Class Name  : EWayBillExcelControllerTest
* Author      : Mirza
* CreatedDate : 02-05-25
* Description : Created test class for EWayBillExcelController
* */
@isTest
public class EWayBillExcelControllerTest {
    @isTest
    static void testEWayBillExcelController() {
        // Create test Account (Distributor)
        Account distributor = new Account(
            Name = 'Test Distributor',
            BillingStreet = '123 Test Street',
            BillingCity = 'Test City',
            BillingPostalCode = '123456',
            BillingState = 'Test State',
            ShippingState = 'Test State',
            GSTIN__c = '22AAAAA0000A1Z5'
        );
        insert distributor;

        // Create RecordType for Invoice
        Id invoiceRecordType = [ 
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Secondary_Invoice' AND SObjectType = 'Invoice__c' 
            LIMIT 1 
        ].Id;

        // Create Invoice__c with line items
        Invoice__c invoice = new Invoice__c(
            Name = 'INV-001',
            Invoice_Date__c = Date.today(),
            Distributor_Account__c = distributor.Id,
            RecordTypeId = invoiceRecordType
        );
        insert invoice;

        // Create Invoice Line Item
        Invoice_Line_Item__c lineItem = new Invoice_Line_Item__c(
            Invoice__c = invoice.Id,
            Quantity__c = 5,
            Price__c = 100.00,
            CGST_Amount__c = 9.0,
            SGST_Amount__c = 9.0,
            IGST_Amount__c = 0.0,
            Total_Amount__c = 118.0
        );
        insert lineItem;
        
        Delivery_Plan__c deliveryPlan = new Delivery_Plan__c(
            Driver_Name__c = 'Test Driver',
            Driver_Number__c = '9888978878',
            Vehicle_Number__c = '1233',
            Date__c = Date.Today()
        );
        insert deliveryPlan;
        
        Delivery_Plan_Items__c deliveryPlanItem = new Delivery_Plan_Items__c(
            Invoices__c = invoice.Id,
            Delivery_Plan__c = deliveryPlan.Id
        );
        insert deliveryPlanItem;
        
        PageReference pageRef = Page.EWayBillExcel; // Replace with actual Visualforce Page name
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('Id', deliveryPlan.Id);
        
        Test.startTest();
        EWayBillExcelController controller = new EWayBillExcelController();
        Test.stopTest();
        
        // Assert invoices are fetched
        System.assertNotEquals(null, controller.invoiceList, 'Invoice list should not be null');
        System.assert(controller.invoiceList.size() > 0, 'Invoice list should contain at least one record');
        System.assertEquals(deliveryPlan.Id, controller.deliveryPlanId, 'Delivery Plan ID should match');
        System.assert(controller.currentDate != null, 'Current date should be set');
        
        // Optionally check the filename in header
        String contentDisposition = ApexPages.currentPage().getHeaders().get('Content-Disposition');
        System.assert(contentDisposition.contains('_EWayBill'), 'Filename should be set in header');
        
    }
}