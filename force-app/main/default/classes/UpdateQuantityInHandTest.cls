@isTest
public class UpdateQuantityInHandTest {
    @isTest
    static void testGetOrderRecord() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        Account acc = new Account(
            Name = 'Test Distributor',
            RecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Distributor' AND SObjectType = 'Account' LIMIT 1].Id,
            Phone = '123-456-7890'
        );
        insert acc;
        
        Product__c product1 = new Product__c(Name = 'Product 1', IsActive__c = true);
        Product__c product2 = new Product__c(Name = 'Product 2', IsActive__c = true);
        insert new List<Product__c>{product1, product2};
             
        Order__c primaryOrder = new Order__c(
            AccountId__c = acc.Id,
            EffectiveDate__c = Date.today(),
            Total_Quantity__c = 100,
            Total_Order_Value__c = 2000,
            Discount_Amount_Order__c = 200 ,
            Status__c = 'Delivered',
            RecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Counter Order' AND SObjectType = 'Order__c' LIMIT 1].Id
        );
        insert primaryOrder;
        
        // Create Order Line Items for the Order
        Order_Line_Item__c orderLine11 = new Order_Line_Item__c(
            Order__c = primaryOrder.Id,
            Products__c = product1.Id,
            Product_Price__c = 20,
            Ordered_Quantity__c = 50 
        );

        Order_Line_Item__c orderLine12 = new Order_Line_Item__c(
            Order__c = primaryOrder.Id,
            Products__c = product2.Id,
            Product_Price__c = 30,
            Ordered_Quantity__c = 50
        );
        insert new List<Order_Line_Item__c>{orderLine11, orderLine12};
        
        // Create inventory records for the products
        Inventory__c inv1 = new Inventory__c(Product__c = product1.Id, Quantity_in_hand__c = 100, Distributor_Name__c = acc.Id);
        insert inv1;
        
        Inventory__c inv2 = new Inventory__c(Product__c = product2.Id, Quantity_in_hand__c = 200, Distributor_Name__c = acc.Id);
        insert inv2;
        
        Map<Id, Order__c> oldOrderMap = new Map<Id, Order__c>();
        oldOrderMap.put(primaryOrder.Id, new Order__c(Status__c = 'Order Placed'));
        
        Test.startTest();
        UpdateQuantityInHand.getOrderRecord(new List<Order__c>{primaryOrder}, oldOrderMap);
        Test.stopTest();
        
        Inventory__c updatedInv1 = [SELECT Quantity_in_hand__c FROM Inventory__c WHERE Id = :inv1.Id];
        //Inventory__c updatedInv2 = [SELECT Quantity_in_hand__c FROM Inventory__c WHERE Id = :inv2.Id];
        
        System.assertEquals(50, updatedInv1.Quantity_in_hand__c, 'Quantity in hand for Product 1 should be updated');
        List<Inventory_Adjustment__c> inventoryAdjustments = [SELECT Quantity__c, Type__c, Primary_Related_transaction__c, Secondary_invoice__c FROM Inventory_Adjustment__c];
        
        System.assertEquals(2, inventoryAdjustments.size(), 'There should be two inventory adjustment records');
    }
    
    @isTest
    static void testUpdateSecondaryInvoiceQuantity(){
        Account acc = new Account(
            Name = 'Test Distributor',
            RecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Distributor' AND SObjectType = 'Account' LIMIT 1].Id,
            Phone = '123-456-7890'
        );
        insert acc;
        
        Product__c product1 = new Product__c(Name = 'Product 1', IsActive__c = true);
        Product__c product2 = new Product__c(Name = 'Product 2', IsActive__c = true);
        insert new List<Product__c>{product1, product2};
             
        Order__c secOrder = new Order__c(
            AccountId__c = acc.Id,
            EffectiveDate__c = Date.today(),
            Total_Quantity__c = 100,
            Total_Order_Value__c = 2000,
            Discount_Amount_Order__c = 200 ,
            Status__c = 'Order Placed',
            RecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Secondary Order' AND SObjectType = 'Order__c' LIMIT 1].Id
        );
        insert secOrder;
        
        // Create Order Line Items for the Order
        Order_Line_Item__c orderLine11 = new Order_Line_Item__c(
            Order__c = secOrder.Id,
            Products__c = product1.Id,
            Product_Price__c = 20,
            Ordered_Quantity__c = 50 
        );

        Order_Line_Item__c orderLine12 = new Order_Line_Item__c(
            Order__c = secOrder.Id,
            Products__c = product2.Id,
            Product_Price__c = 30,
            Ordered_Quantity__c = 50
        );
        insert new List<Order_Line_Item__c>{orderLine11, orderLine12};
        
        Invoice__c secInvoice = new Invoice__c(
            Name = 'INV0000900',
            Order__c = secOrder.Id,
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
        
        // Create inventory records for the products
        Inventory__c inv1 = new Inventory__c(Product__c = product1.Id, Quantity_in_hand__c = 100, Distributor_Name__c = acc.Id);
        insert inv1;
        
        Inventory__c inv2 = new Inventory__c(Product__c = product2.Id, Quantity_in_hand__c = 200, Distributor_Name__c = acc.Id);
        insert inv2;
        
        Map<Id, Invoice__c> oldOrderMap = new Map<Id, Invoice__c>();
        oldOrderMap.put(secInvoice.Id, new Invoice__c(Status__c = 'Draft'));
        
        Test.startTest();
        UpdateQuantityInHand.updateSecondaryInvoiceQuantity(new List<Invoice__c>{secInvoice}, oldOrderMap);
        Test.stopTest();
    }
    
    @isTest
    static void testupdatePrimaryInvoiceQuantity(){
        Account acc = new Account(
            Name = 'Test Distributor',
            RecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Distributor' AND SObjectType = 'Account' LIMIT 1].Id,
            Phone = '123-456-7890'
        );
        insert acc;
        
        Product__c product1 = new Product__c(Name = 'Product 1', IsActive__c = true);
        Product__c product2 = new Product__c(Name = 'Product 2', IsActive__c = true);
        insert new List<Product__c>{product1, product2};
             
        Order__c secOrder = new Order__c(
            AccountId__c = acc.Id,
            EffectiveDate__c = Date.today(),
            Total_Quantity__c = 100,
            Total_Order_Value__c = 2000,
            Discount_Amount_Order__c = 200 ,
            Status__c = 'Order Placed',
            RecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Secondary Order' AND SObjectType = 'Order__c' LIMIT 1].Id
        );
        insert secOrder;
        
        // Create Order Line Items for the Order
        Order_Line_Item__c orderLine11 = new Order_Line_Item__c(
            Order__c = secOrder.Id,
            Products__c = product1.Id,
            Product_Price__c = 20,
            Ordered_Quantity__c = 50 
        );

        Order_Line_Item__c orderLine12 = new Order_Line_Item__c(
            Order__c = secOrder.Id,
            Products__c = product2.Id,
            Product_Price__c = 30,
            Ordered_Quantity__c = 50
        );
        insert new List<Order_Line_Item__c>{orderLine11, orderLine12};
        
        Invoice__c secInvoice = new Invoice__c(
            Name = 'INV0000900',
            Order__c = secOrder.Id,
            Distributor_Account__c = acc.Id,
            Invoice_Number__c = 'INV0000900',
            Total_Quantity__c = 100,
            RecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Primary Invoice' AND SObjectType = 'Invoice__c' LIMIT 1].Id ,
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
            
        Map<Id, Invoice_Line_Item__c> oldOrderMap = new Map<Id, Invoice_Line_Item__c>();
        oldOrderMap.put(invoiceLine11.Id , invoiceLine11);
        oldOrderMap.put(invoiceLine12.Id , invoiceLine12);
        
        Good_receipt_notes__c grn = new Good_receipt_notes__c(
            Total_Changed_Quantity__c = 50,
            Total_Quantity__c = 100 ,
            Order__c = secOrder.Id,
            Invoice__c = secInvoice.Id
        );
        insert grn;
        
        Invoice_Line_Item__c updateInvoiceLine11 = new Invoice_Line_Item__c(
            Id = invoiceLine11.Id , 
            Received_Quantity__c = 25,
            Good_receipt_note__c = grn.Id
        );

        Invoice_Line_Item__c updateInvoiceLine12 = new Invoice_Line_Item__c(
            Id = invoiceLine12.Id , 
            Received_Quantity__c = 25,
            Good_receipt_note__c = grn.Id
        );
        update new List<Invoice_Line_Item__c>{updateInvoiceLine11, updateInvoiceLine12};
        
        // Create inventory records for the products
        /*Inventory__c inv1 = new Inventory__c(Product__c = product1.Id, Quantity_in_hand__c = 100, Distributor_Name__c = acc.Id);
        insert inv1;
        
        Inventory__c inv2 = new Inventory__c(Product__c = product2.Id, Quantity_in_hand__c = 200, Distributor_Name__c = acc.Id);
        insert inv2;*/
        
        Test.startTest();
        UpdateQuantityInHand.updatePrimaryInvoiceQuantity(new List<Invoice_Line_Item__c>{updateInvoiceLine12}, oldOrderMap);
        Test.stopTest();
    }
}