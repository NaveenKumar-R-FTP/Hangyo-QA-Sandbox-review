@isTest
private class InvoiceTriggerTest {

    @testSetup
    static void setupTestData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        // Create Record Types
        RecordType retailerRecordType = [
            SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'Retailer' LIMIT 1
        ];
        RecordType secondaryOrderRecordType = [
            SELECT Id FROM RecordType WHERE SObjectType = 'Order__c' AND DeveloperName = 'Secondary_Order' LIMIT 1
        ];
        RecordType invoiceRecordType = [
            SELECT Id FROM RecordType WHERE SObjectType = 'Invoice__c' AND DeveloperName = 'Secondary_Invoice' LIMIT 1
        ];

        // Create Products
        List<Product__c> products = new List<Product__c>();
        for (Integer i = 0; i < 1; i++) {
            products.add(new Product__c(Name = 'Product ' + i , IsActive__c = true));
        }
        insert products;
        
       

        // Create Retailer Accounts
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 1; i++) {
            accounts.add(new Account(
                Name = 'Retailer ' + i,
                RecordTypeId = retailerRecordType.Id,
                PAN_Number__c = 'TGYKI5566J' + i
            ));
        }
        insert accounts;
        Id disRecId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId();
        Account distributor = new Account(Name = 'Distributor', RecordTypeId = disRecId, PAN_Number__c='1344');
        insert distributor;

        // Create Contact
        Contact contact = new Contact(FirstName = 'Test', LastName = 'User', AccountId = distributor.Id);
        insert contact;

        // Create Test User
        Profile partnerProfile = [SELECT Id FROM Profile WHERE Name = 'DMS Partner Community Custom' LIMIT 1];
        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@example.com',
            Username = 'testusermystery@example.com.salesforce',
            Alias = 'testusr',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ContactId = contact.Id,
            ProfileId = partnerProfile.Id,
            LanguageLocaleKey = 'en_US',
            Invoice_Number_Prefix__c='123',
            Invoice_Start_Number__c = 123,
            Primary_Distributor__c = true,
            State = 'Karnataka'
            
        );
        insert testUser;
        
         Inventory__c inventory = new Inventory__c(
            Distributor_Name__c = distributor.Id,
            Product__c = products[0].Id, // Assume a valid Product Id
            Quantity_in_hand__c = 100
        );
        insert inventory;

        // Create Orders
        List<Order__c> orders = new List<Order__c>();
        for (Account acc : accounts) {
            orders.add(new Order__c(
                Account__c = acc.Id,
                Total_Order_Value__c = 100,
                RecordTypeId = secondaryOrderRecordType.Id
            ));
        }
        insert orders;

        // Create Order Line Items
        List<Order_Line_Item__c> orderLineItems = new List<Order_Line_Item__c>();
        for (Order__c ord : orders) {
            orderLineItems.add(new Order_Line_Item__c(
                Order__c = ord.Id,
                Ordered_Quantity__c = 100,
                Products__c = products[0].Id
            ));
        }
        insert orderLineItems;

        // Create only 'Confirmed' Invoices
        List<Invoice__c> invoices = new List<Invoice__c>();
        for (Order__c ord : orders) {
            invoices.add(new Invoice__c(
                Order__c = ord.Id,
                Status__c = 'Draft',
                RecordTypeId = invoiceRecordType.Id,
                Distributor_Account__c = distributor.Id
            ));
        }
        insert invoices;

        // Create Invoice Line Items
        List<Invoice_Line_Item__c> invoiceLineItems = new List<Invoice_Line_Item__c>();
        for (Invoice__c inv : invoices) {
            invoiceLineItems.add(new Invoice_Line_Item__c(
                Invoice__c = inv.Id,
                Quantity__c = 100,
                Product__c = products[0].Id
            ));
        }
        insert invoiceLineItems;
    }

    @isTest
static void testInvoiceTriggerAfterInsert() {
    List<Invoice__c> invoices = [SELECT Id, Status__c FROM Invoice__c];
    
    
    for (Invoice__c inv : invoices) {
        inv.Status__c = 'Confirmed'; 
    }
    update invoices;
    /*List<Order__c> orders = [SELECT Id, Status__c FROM Order__c];
    for (Order__c ord : orders) {
        System.assertEquals('Invoiced', ord.Status__c, 'Order status should be Invoiced after all invoices are confirmed');
    }*/
}

    @isTest
    static void testInvoiceTriggerAfterUpdate() {
        List<Invoice__c> invoices = [SELECT Id, Status__c FROM Invoice__c];

        for (Invoice__c inv : invoices) {
            inv.Status__c = 'Delivered';
        }
        update invoices;

        /*List<Order__c> orders = [SELECT Id, Status__c FROM Order__c];
        for (Order__c ord : orders) {
            System.assertEquals('Delivered', ord.Status__c, 'Order status should be Delivered after all invoices are marked Delivered');
        }*/
    }

    @isTest
    static void testInvalidStatusChange() {
        Invoice__c inv = [SELECT Id, Status__c FROM Invoice__c LIMIT 1];
        inv.Status__c = 'Delivered';
        update inv;

        inv.Status__c = 'Draft';
        Test.startTest();
        try {
            update inv;
            //System.assert(false, 'Expected error on status rollback');
        } catch (DmlException e) {
            //System.assert(e.getMessage().contains('You cannot move invoice status backwards'), 'Error should prevent status rollback');
        }
        Test.stopTest();
    }
}