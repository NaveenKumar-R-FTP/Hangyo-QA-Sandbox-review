@isTest
public class UpdateInventoryRecordTest {
    
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
        
        // Create Invoice Line Items for the Order
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
        Inventory__c inv2 = new Inventory__c(Product__c = product2.Id, Quantity_in_hand__c = 200, Distributor_Name__c = acc.Id);
        insert new List<Inventory__c>{inv1, inv2};
        
        Returns__c secReturn = new Returns__c(
            Order__c = secOrder.Id,
            Invoice__c = secInvoice.Id,
            Total_return_quantity__c = 5
        );
        insert secReturn;
        
        Return_Line_item__c returnLine11 = new Return_Line_item__c(
            Return__c = secReturn.Id,
            Product__c = product1.Id,
            Total_returns__c = 5 ,
            Reuse_count__c = 5
        );
        
        Return_Line_item__c returnLine12 = new Return_Line_item__c(
            Return__c = secReturn.Id,
            Product__c = product2.Id,
            Total_returns__c = 5 ,
            Reuse_count__c = 5
        );
        insert new List<Return_Line_item__c>{returnLine11, returnLine12};
        
        /*Test.startTest();
        UpdateInventoryRecord.updateInventorySecondaryReturn(new List<Return_Line_item__c>{returnLine11});
        Test.stopTest();*/
        
        // Assert inventory updates
        Inventory__c updatedInv1 = [SELECT Quantity_in_hand__c FROM Inventory__c WHERE Id = :inv1.Id];
        Inventory__c updatedInv2 = [SELECT Quantity_in_hand__c FROM Inventory__c WHERE Id = :inv2.Id];
        System.assertEquals(105, updatedInv1.Quantity_in_hand__c, 'Inventory for product1 should increase by 5');
        System.assertEquals(205, updatedInv2.Quantity_in_hand__c, 'Inventory for product2 should increase by 5');
    }
}