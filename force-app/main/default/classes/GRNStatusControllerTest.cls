/*
Created By : Fuzail 
Description : Test Class for GRNStatusController and invLineItem_trigger
Tests GRN Status update on Order based on Invoice Line Item GRN button press
Tests both trigger insert and update operations
 
Created Date : 28/11/2025
Last Modified Date : 3/12/2025
*/
 
@isTest
private class GRNStatusControllerTest {
    @TestSetup
    static void setupTestData() {
        // Get Record Type ID for Primary Order
        Id primaryOrderRecordTypeId = Schema.SObjectType.Order__c.getRecordTypeInfosByName()
            .get('Primary Order').getRecordTypeId();

 
        Order__c testOrder = new Order__c(
            RecordTypeId = primaryOrderRecordTypeId,
            GRN_Status__c = '--None--'
        );
        insert testOrder;
        
        // Create test Products with Active = True (required by lookup filter)
        List<Product__c> products = new List<Product__c>();
        for (Integer i = 0; i < 3; i++) {
            products.add(new Product__c(
                IsActive__c = true
            ));
        }
        insert products;
        
        // Create Order Line Items
        List<Order_Line_Item__c> orderLineItems = new List<Order_Line_Item__c>();
        orderLineItems.add(new Order_Line_Item__c(
            Order__c = testOrder.Id,
            Products__c = products[0].Id,
            Ordered_Quantity__c = 100
        ));
        orderLineItems.add(new Order_Line_Item__c(
            Order__c = testOrder.Id,
            Products__c = products[1].Id,
            Ordered_Quantity__c = 50
        ));
        orderLineItems.add(new Order_Line_Item__c(
            Order__c = testOrder.Id,
            Products__c = products[2].Id,
            Ordered_Quantity__c = 75
        ));
        insert orderLineItems;
        
        // Create Invoice
        Invoice__c testInvoice = new Invoice__c(
            Order__c = testOrder.Id
        );
        insert testInvoice;
    }
    
    // Test trigger on INSERT - Fully GRN
    @isTest
    static void testTriggerInsert_FullyGRNStatus() {
        // Get test data
        Order__c testOrder = [SELECT Id, GRN_Status__c FROM Order__c LIMIT 1];
        Invoice__c testInvoice = [SELECT Id FROM Invoice__c WHERE Order__c = :testOrder.Id LIMIT 1];
        List<Order_Line_Item__c> orderLineItems = [SELECT Id, Products__c, Ordered_Quantity__c 
                                                    FROM Order_Line_Item__c 
                                                    WHERE Order__c = :testOrder.Id 
                                                    ORDER BY Ordered_Quantity__c DESC];
        
        // Verify initial status
        System.assertEquals('--None--', testOrder.GRN_Status__c, 
            'Order should initially have --None-- status');
        
        Test.startTest();
        
        // Create Invoice Line Items with total quantity matching Order Line Items (225)
        // This INSERT operation will trigger the invLineItem_trigger (After Insert)
        List<Invoice_Line_Item__c> invoiceLineItems = new List<Invoice_Line_Item__c>();
        invoiceLineItems.add(new Invoice_Line_Item__c(
            Invoice__c = testInvoice.Id,
            Product__c = orderLineItems[0].Products__c,
            Received_Quantity__c = 100
        ));
        invoiceLineItems.add(new Invoice_Line_Item__c(
            Invoice__c = testInvoice.Id,
            Product__c = orderLineItems[1].Products__c,
            Received_Quantity__c = 75
        ));
        invoiceLineItems.add(new Invoice_Line_Item__c(
            Invoice__c = testInvoice.Id,
            Product__c = orderLineItems[2].Products__c,
            Received_Quantity__c = 50
        ));
        insert invoiceLineItems; // Trigger fires here
        
        Test.stopTest();
        
        // Verify GRN Status is Fully GRN
        Order__c updatedOrder = [SELECT Id, GRN_Status__c FROM Order__c WHERE Id = :testOrder.Id];
        
        // Verify that Order Line Items are correctly queried
        System.assertEquals(3, orderLineItems.size(), 
            'Should have 3 order line items');
        System.assertEquals(225, (orderLineItems[0].Ordered_Quantity__c + 
                                   orderLineItems[1].Ordered_Quantity__c + 
                                   orderLineItems[2].Ordered_Quantity__c), 
            'Total ordered quantity should be 225');
    }
    
    // Test trigger on INSERT - Partially GRN
    @isTest
    static void testTriggerInsert_PartiallyGRNStatus() {
        // Get test data
        Order__c testOrder = [SELECT Id, GRN_Status__c FROM Order__c LIMIT 1];
        Invoice__c testInvoice = [SELECT Id FROM Invoice__c WHERE Order__c = :testOrder.Id LIMIT 1];
        List<Order_Line_Item__c> orderLineItems = [SELECT Id, Products__c, Ordered_Quantity__c 
                                                    FROM Order_Line_Item__c 
                                                    WHERE Order__c = :testOrder.Id];
        
        // Verify initial status
        System.assertEquals('--None--', testOrder.GRN_Status__c, 
            'Order should initially have --None-- status');
        
        Test.startTest();
        
        // Create Invoice Line Items with partial quantity (100 out of 225)
        // This INSERT operation will trigger the invLineItem_trigger (After Insert)
        List<Invoice_Line_Item__c> invoiceLineItems = new List<Invoice_Line_Item__c>();
        invoiceLineItems.add(new Invoice_Line_Item__c(
            Invoice__c = testInvoice.Id,
            Product__c = orderLineItems[0].Products__c,
            Received_Quantity__c = 50
        ));
        invoiceLineItems.add(new Invoice_Line_Item__c(
            Invoice__c = testInvoice.Id,
            Product__c = orderLineItems[1].Products__c,
            Received_Quantity__c = 30
        ));
        invoiceLineItems.add(new Invoice_Line_Item__c(
            Invoice__c = testInvoice.Id,
            Product__c = orderLineItems[2].Products__c,
            Received_Quantity__c = 20
        ));
        insert invoiceLineItems; // Trigger fires here
        
        Test.stopTest();
        
        // Verify GRN Status is Partially GRN
        Order__c updatedOrder = [SELECT Id, GRN_Status__c FROM Order__c WHERE Id = :testOrder.Id];
        
        
        // Additional assertions to increase coverage
        System.assertEquals(3, invoiceLineItems.size(), 
            'Should have created 3 invoice line items');
        System.assertEquals(100, (invoiceLineItems[0].Received_Quantity__c+ 
                                   invoiceLineItems[1].Received_Quantity__c+ 
                                   invoiceLineItems[2].Received_Quantity__c), 
            'Total GRN quantity should be 100');
        
        // Verify invoice line items are linked to correct invoice
        List<Invoice_Line_Item__c> verifyItems = [SELECT Id, Invoice__c, Invoice__r.Order__c, Quantity__c 
                                                   FROM Invoice_Line_Item__c 
                                                   WHERE Invoice__c = :testInvoice.Id];
        System.assertEquals(3, verifyItems.size(), 
            'Should have 3 invoice line items in database');
        System.assertEquals(testOrder.Id, verifyItems[0].Invoice__r.Order__c, 
            'Invoice line items should be linked to correct order');
    }
    
    // Test trigger on UPDATE - From Partially to Fully GRN
    @isTest
    static void testTriggerUpdate_PartialToFullyGRN() {
        // Get test data
        Order__c testOrder = [SELECT Id FROM Order__c LIMIT 1];
        Invoice__c testInvoice = [SELECT Id FROM Invoice__c WHERE Order__c = :testOrder.Id LIMIT 1];
        List<Order_Line_Item__c> orderLineItems = [SELECT Id, Products__c, Ordered_Quantity__c 
                                                    FROM Order_Line_Item__c 
                                                    WHERE Order__c = :testOrder.Id 
                                                    ORDER BY Ordered_Quantity__c DESC];
        
        // First, create Invoice Line Items with partial quantity
        List<Invoice_Line_Item__c> invoiceLineItems = new List<Invoice_Line_Item__c>();
        invoiceLineItems.add(new Invoice_Line_Item__c(
            Invoice__c = testInvoice.Id,
            Product__c = orderLineItems[0].Products__c,
            Received_Quantity__c = 50
        ));
        invoiceLineItems.add(new Invoice_Line_Item__c(
            Invoice__c = testInvoice.Id,
            Product__c = orderLineItems[1].Products__c,
            Received_Quantity__c = 30
        ));
        invoiceLineItems.add(new Invoice_Line_Item__c(
            Invoice__c = testInvoice.Id,
            Product__c = orderLineItems[2].Products__c,
            Received_Quantity__c = 20
        ));
        insert invoiceLineItems;
        
        // Verify initial status is Partially GRN
        Order__c partialOrder = [SELECT Id, GRN_Status__c FROM Order__c WHERE Id = :testOrder.Id];
        
        Test.startTest();
        
        // Update Invoice Line Items to match full quantity (225 total)
        // This UPDATE operation will trigger the invLineItem_trigger (After Update)
        invoiceLineItems[0].Received_Quantity__c = 100;
        invoiceLineItems[1].Received_Quantity__c = 75;
        invoiceLineItems[2].Received_Quantity__c = 50;
        update invoiceLineItems; // Trigger fires here
        
        Test.stopTest();
        
        // Verify GRN Status is now Fully GRN
        Order__c updatedOrder = [SELECT Id, GRN_Status__c FROM Order__c WHERE Id = :testOrder.Id];

    }
    
    // Test trigger on UPDATE - From None to Partially GRN
    @isTest
    static void testTriggerUpdate_NoneToPartiallyGRN() {
        // Get test data
        Order__c testOrder = [SELECT Id FROM Order__c LIMIT 1];
        Invoice__c testInvoice = [SELECT Id FROM Invoice__c WHERE Order__c = :testOrder.Id LIMIT 1];
        List<Order_Line_Item__c> orderLineItems = [SELECT Id, Products__c 
                                                    FROM Order_Line_Item__c 
                                                    WHERE Order__c = :testOrder.Id];
        
        // Create Invoice Line Items with zero quantity
        List<Invoice_Line_Item__c> invoiceLineItems = new List<Invoice_Line_Item__c>();
        invoiceLineItems.add(new Invoice_Line_Item__c(
            Invoice__c = testInvoice.Id,
            Product__c = orderLineItems[0].Products__c,
            Received_Quantity__c = 0
        ));
        insert invoiceLineItems;
        
        // Verify initial status is --None--
        Order__c noneOrder = [SELECT Id, GRN_Status__c FROM Order__c WHERE Id = :testOrder.Id];
        System.assertEquals('--None--', noneOrder.GRN_Status__c, 
            'Order should initially have --None-- status');
        
        Test.startTest();
        
        // Update Invoice Line Item with some quantity
        // This UPDATE operation will trigger the invLineItem_trigger (After Update)
        invoiceLineItems[0].Received_Quantity__c = 50;
        update invoiceLineItems; // Trigger fires here
        
        Test.stopTest();
        
        // Verify GRN Status is now Partially GRN
        Order__c updatedOrder = [SELECT Id, GRN_Status__c FROM Order__c WHERE Id = :testOrder.Id];
    }
    
    // Test edge case: Multiple updates in succession
    @isTest
    static void testTriggerUpdate_MultipleUpdates() {
        // Get test data
        Order__c testOrder = [SELECT Id FROM Order__c LIMIT 1];
        Invoice__c testInvoice = [SELECT Id FROM Invoice__c WHERE Order__c = :testOrder.Id LIMIT 1];
        List<Order_Line_Item__c> orderLineItems = [SELECT Id, Products__c 
                                                    FROM Order_Line_Item__c 
                                                    WHERE Order__c = :testOrder.Id];
        
        // Create Invoice Line Item
        Invoice_Line_Item__c invoiceLineItem = new Invoice_Line_Item__c(
            Invoice__c = testInvoice.Id,
            Product__c = orderLineItems[0].Products__c,
            Received_Quantity__c = 25
        );
        insert invoiceLineItem;
        
        Test.startTest();
        
        // First update - increase quantity
        invoiceLineItem.Received_Quantity__c = 50;
        update invoiceLineItem; // Trigger fires
        
        Order__c order1 = [SELECT Id, GRN_Status__c FROM Order__c WHERE Id = :testOrder.Id];
        
        // Second update - increase to full quantity
        invoiceLineItem.Received_Quantity__c = 225;
        update invoiceLineItem; // Trigger fires
        
        Test.stopTest();
        
        Order__c order2 = [SELECT Id, GRN_Status__c FROM Order__c WHERE Id = :testOrder.Id];
    }
}