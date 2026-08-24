@isTest
private class UpdateInvoiceSchedulerTest {

    @testSetup
    static void setupData() {
        // ---- Record Types ----
        Id retailerRT = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId();
        Id productRT  = Schema.SObjectType.Product__c.getRecordTypeInfosByName().get('Product').getRecordTypeId();
        Id invoiceRT  = Schema.SObjectType.Invoice__c.getRecordTypeInfosByName().get('Secondary Invoice').getRecordTypeId();
        
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        // ---- Retailer Account ----
        Account retailer = new Account(
            Name = 'Test Retailer',
            RecordTypeId = retailerRT,
            Primary_State__c = 'Maharashtra'
        );
        insert retailer;

        // ---- Product ----
        Product__c prod = new Product__c(
            Name = 'Test Product',
            Product_Code__c = 'TP-001',
            RecordTypeId = productRT,
            IsActive__c = true
        );
        insert prod;

        // ---- Custom Price Book (State Specific) ----
        Price_Book__c priceBook = new Price_Book__c(
            Name = 'Maharashtra',
            IsActive__c = true
        );
        insert priceBook;

        // ---- Price Book Entry ----
        Price_Book_Entry__c pbe = new Price_Book_Entry__c(
            Product__c = prod.Id,
            Price_Book__c = priceBook.Id,
            PTR__c = 100.50,
            IsActive__c = true
        );
        insert pbe;

        // ---- Order ----
        Order__c ord = new Order__c(
            Account__c = retailer.Id
            //CreatedDate = System.now().addDays(-3) // Before cutoff
        );
        insert ord;
        Datetime customCreatedDate = Datetime.newInstance(2025, 9, 22, 16, 59, 0);
        Test.setCreatedDate(ord.Id, customCreatedDate);

        // ---- Invoice ----
        Invoice__c inv = new Invoice__c(
            Name = 'Test Invoice',
            Order__c = ord.Id,
            Retailer_Account__c = retailer.Id,
            RecordTypeId = invoiceRT
           // CreatedDate = System.now() // After cutoff
        );
        insert inv;
        Test.setCreatedDate(inv.Id, System.now());
        // ---- Invoice Line Item ----
        Invoice_Line_Item__c line = new Invoice_Line_Item__c(
            Invoice__c = inv.Id,
            Product__c = prod.Id,
            Quantity__c = 5,
            Discount_1__c = 10,
            Discount_2__c = 5
        );
        insert line;

        // ---- Tax Setting ----
        Order_Tax_Value__c tax = new Order_Tax_Value__c(
            Name = 'General GST Settings',
            CGST__c = 9,
            SGST__c = 9,
            IGST__c = 18
        );
        insert tax;
    }

    @isTest
    static void testSchedulerExecution() {
        Test.startTest();

        // Run scheduler once
        String cron = '0 0 0 * * ?'; // midnight
        System.schedule('Test UpdateInvoiceScheduler', cron, new UpdateInvoiceScheduler());

        Test.stopTest();

      
    }
}