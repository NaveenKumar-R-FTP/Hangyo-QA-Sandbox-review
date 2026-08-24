@isTest
public without sharing class InvoiceAPITest {
    @testSetup
    static void setupTestData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 155716.00);
            insert setting;
        // Create sample Accounts (Distributors)
        Account distributor = new Account(Name='Test Distributor', Code__c='D123',PAN_Number__c='ABCD');
        insert distributor;
        
        // Create sample Order
        Order__c order = new Order__c(OwnerId=UserInfo.getUserId());
        insert order;
        
        // Create sample Product
        Product__c product = new Product__c(Name='Sample Product', Product_Code__c='P123');
        insert product;
        
        // Create sample Invoice
        Invoice__c invoice = new Invoice__c(Name='INV123', Distributor_Account__c=distributor.Id, Order__c=order.Id);
        insert invoice;
    }
    
    @isTest
    static void testLoadPriceDataFromSAP() {
        // Prepare test data
        List<InvoiceAPI.InvoiceInfo> invoiceData = new List<InvoiceAPI.InvoiceInfo>();
        InvoiceAPI.InvoiceInfo invoice = new InvoiceAPI.InvoiceInfo();
        invoice.invoice_no = 'INV123';
        invoice.customer_code = 'D123';
        invoice.order_ref = [SELECT Name FROM Order__C LIMIT 1].Name;
        invoice.supplier_code = 'SUP456';
        invoice.BillingDate = '2024-01-01';
        invoice.subtotal = '100.00';
        invoice.tax_amt = '10.00';
        invoice.origin = 'Online';
        invoice.total = '110.00';
        
        InvoiceAPI.InvoiceItem item = new InvoiceAPI.InvoiceItem();
        item.prd_code = 'P123';
        item.qty = '2';
        item.uom = 'Unit';
        item.unit_price = '50.00';
        item.mrp = '55.00';
        item.margin = '5.00';
        item.discount = '0.00';
        item.subtotal = '100.00';
        item.tax_code = 'GST';
        item.tax = '10.00';
        item.total = '110.00';
        item.tax_lines = new List<InvoiceAPI.TaxLine>();
        InvoiceAPI.TaxLine txl1 = new InvoiceAPI.TaxLine();
            txl1.name = 'SGST';
            txl1.pct = '0.7';
            txl1.amt='100';
        item.tax_lines.add(txl1);
        InvoiceAPI.TaxLine txl2 = new InvoiceAPI.TaxLine();
            txl2.name = 'CGST';
            txl2.pct = '0.7';
            txl2.amt='100';
        item.tax_lines.add(txl2);
        InvoiceAPI.TaxLine txl3 = new InvoiceAPI.TaxLine();
            txl3.name = 'IGST';
            txl3.pct = '0.7';
            txl3.amt='100';
        item.tax_lines.add(txl3);

        invoice.items = new List<InvoiceAPI.InvoiceItem>{item};
        invoiceData.add(invoice);
        
        Test.startTest();
        InvoiceAPI.InvoiceResponseData response = InvoiceAPI.loadPriceDataFromSAP(invoiceData);
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(response, null, 'Response should not be null');
        //System.assertEquals(response.data.size(), 1, 'One invoice should be processed');
       // System.assertEquals(response.data[0].items.size(), 1, 'One line item should be processed');
        //System.assertEquals(response.data[0].items[0].status, 'Success', 'Line item should be created');
    }
    
    @isTest
    static void testLoadPriceDataWithEmptyList() {
        Test.startTest();
        InvoiceAPI.InvoiceResponseData response = InvoiceAPI.loadPriceDataFromSAP(new List<InvoiceAPI.InvoiceInfo>());
        Test.stopTest();
        
        // Assertions
        System.assertNotEquals(response, null, 'Response should not be null');
        System.assertEquals(response.data.size(), 1, 'Response should contain one entry');
        System.assertEquals(response.data[0].status, 'Failure', 'Response should indicate empty request');
    }
}