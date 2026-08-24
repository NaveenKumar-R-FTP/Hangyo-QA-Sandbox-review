public without sharing class UpdateQuantityInHand {
    
    //Method to decrement inventory for counter order record type
    public static void getOrderRecord(List<Order__c> orderList , Map<Id, Order__c> oldOrderMap){
        Set<Id> orderId = new Set<Id>();
        Set<Id> productId = new Set<Id>();
        Map<String,Decimal> productMap = new Map<String,Decimal>();
        Map<String,String> productRecord = new Map<String,String>();
        List<Inventory__c> updateInventory = new List<Inventory__c>();
        List<Inventory_Adjustment__c> createInventoryAdjustment = new List<Inventory_Adjustment__c>();
        String orderName;
        String distributorName;
        for(Order__c ord:orderList){
            if(ord.Status__c == 'Delivered' && oldOrderMap.get(ord.Id).Status__c != 'Delivered'){
                orderId.add(ord.Id); 
                orderName = ord.Id;
                distributorName = ord.AccountId__c;
            }
        }
        System.debug('distributorName==> ' + distributorName);
        
        for(Order_Line_Item__c orderLine : [SELECT Id , Ordered_Quantity__c , Products__c , Updated_quanity__c ,Order__r.Record_Type_Name__c , Order__c FROM Order_Line_Item__c WHERE Order__c IN: orderId AND Products__c != NULL AND Order__r.Record_Type_Name__c = 'Counter Order']){
            productId.add(orderLine.Products__c);
            productRecord.put(orderLine.Products__c,orderLine.Order__r.Record_Type_Name__c);
            if(orderLine.Updated_quanity__c != NULL){
                productMap.put(orderLine.Products__c , orderLine.Updated_quanity__c);
            }else{
                productMap.put(orderLine.Products__c , orderLine.Ordered_Quantity__c);
            }
        }
        System.debug('productMap==> ' + productMap);
        
        Inventory_Adjustment__c newInventory;
        for(Inventory__c inv : [SELECT Id , Name , Product__c , Quantity_in_hand__c FROM Inventory__c WHERE Product__c IN: productId AND Distributor_Name__c =: distributorName]){
            if(productRecord.get(inv.Product__c) == 'Counter Order'){
                inv.Quantity_in_hand__c = inv.Quantity_in_hand__c - productMap.get(inv.Product__c);
                
                newInventory = new Inventory_Adjustment__c();
                newInventory.Quantity__c =  productMap.get(inv.Product__c);
                newInventory.Inventory__c = inv.Id;
                newInventory.Product__c = inv.Product__c;
                newInventory.Type__c = 'Decrement';
                newInventory.Secondary_invoice__c = orderName;
                newInventory.Adjustment_Date__c = Date.today();
                createInventoryAdjustment.add(newInventory);
            }
            updateInventory.add(inv);
        }
        System.debug('updateInventory==> ' + updateInventory);
        
        if(updateInventory.size()>0){
            Update updateInventory;
        }
        
        if(createInventoryAdjustment.size()>0){
            insert createInventoryAdjustment;
        }
    }
    
    //Method to decrement inventory for secondary invoice record type
    public static void updateSecondaryInvoiceQuantity(List<Invoice__c> invoiceList , Map<Id, Invoice__c> oldInvoiceMap){
        Id secInvoiceRecordType = [SELECT Id FROM RecordType WHERE DeveloperName = 'Secondary_Invoice' AND SObjectType = 'Invoice__c' LIMIT 1].Id;
        Id underSsRecordType = [SELECT Id FROM RecordType WHERE DeveloperName = 'Secondary_Invoice_Under_SS' AND SObjectType = 'Invoice__c' LIMIT 1].Id;
        Set<Id> invoiceId = new Set<Id>();
        Set<Id> productId = new Set<Id>();
        Map<String,Decimal> productMap = new Map<String,Decimal>();
        List<Inventory__c> updateInventory = new List<Inventory__c>();
        List<Inventory_Adjustment__c> createInventoryAdjustment = new List<Inventory_Adjustment__c>();
        List<Id> accountIdList = new List<Id>();
        String invoiceName;
        String distributorName;
        String underSsName;
        for(Invoice__c inv:invoiceList){
            if(inv.Status__c == 'Confirmed' && oldInvoiceMap.get(inv.Id).Status__c != 'Confirmed' && (inv.RecordTypeId == secInvoiceRecordType || inv.RecordTypeId == underSsRecordType)){
                invoiceId.add(inv.Id); 
                invoiceName = inv.Id;
                distributorName = inv.Distributor_Account__c;
            }
        }
        System.debug('distributorName==> ' + distributorName);
        
        for(Invoice_Line_Item__c invoiceLine : [SELECT Id , Quantity__c , Product__c , Invoice__r.RecordTypeId FROM Invoice_Line_Item__c WHERE Invoice__c IN: invoiceId AND Product__c != NULL]){
            productId.add(invoiceLine.Product__c);
            //productRecord.put(orderLine.Products__c,orderLine.Order__r.Record_Type_Name__c);
            if(invoiceLine.Quantity__c != NULL){
                //productMap.put(invoiceLine.Product__c , invoiceLine.Quantity__c);
                if (invoiceLine.Quantity__c != null) {
                    if (productMap.containsKey(invoiceLine.Product__c)) {
                        productMap.put(invoiceLine.Product__c,
                            productMap.get(invoiceLine.Product__c) + invoiceLine.Quantity__c
                        );
                    } else {
                        productMap.put(invoiceLine.Product__c, invoiceLine.Quantity__c);
                    }
                }

                /*if(productMap.containsKey(invoiceLine.Product__c)){
                    Decimal quantity = productMap.get(invoiceLine.Product__c) + invoiceLine.Quantity__c;
                    productMap.put(invoiceLine.Product__c , quantity);
                }else{
                    productMap.put(invoiceLine.Product__c , invoiceLine.Quantity__c);
                }*/
            }
        }
        System.debug('productMap==> ' + productMap);
        
        Inventory_Adjustment__c newInventory;
        for(Inventory__c inv : [SELECT Id , Name , Product__c , Quantity_in_hand__c FROM Inventory__c WHERE Product__c IN: productId AND Distributor_Name__c =: distributorName]){
            inv.Quantity_in_hand__c = inv.Quantity_in_hand__c - productMap.get(inv.Product__c);
            
            newInventory = new Inventory_Adjustment__c();
            newInventory.Quantity__c =  productMap.get(inv.Product__c);
            newInventory.Inventory__c = inv.Id;
            newInventory.Product__c = inv.Product__c;
            newInventory.Type__c = 'Decrement';
            newInventory.Secondary_Invoice_transaction__c = invoiceName;
            newInventory.Adjustment_Date__c = Date.today();
            createInventoryAdjustment.add(newInventory);
            updateInventory.add(inv);
        }
        System.debug('updateInventory==> ' + updateInventory);
        
        if(updateInventory.size()>0){
            Update updateInventory;
        }
        
        if(createInventoryAdjustment.size()>0){
            insert createInventoryAdjustment;
        }
    }
    
    //Method to increment inventory for primary invoice record type
    public static void updatePrimaryInvoiceQuantity(List<Invoice_Line_Item__c> invLineItemList , Map<Id, Invoice_Line_Item__c> oldInvLineItemMap){
        Id priInvoiceRecordType = [SELECT Id FROM RecordType WHERE DeveloperName = 'Primary_Invoice' AND SObjectType = 'Invoice__c' LIMIT 1].Id;
        Id underSsRecordType = [SELECT Id FROM RecordType WHERE DeveloperName = 'Secondary_Invoice_Under_SS' AND SObjectType = 'Invoice__c' LIMIT 1].Id;
        Set<Id> invoiceId = new Set<Id>();
        Set<Id> productId = new Set<Id>();
        Map<String,Decimal> productMap = new Map<String,Decimal>();
        List<Inventory__c> updateInventory = new List<Inventory__c>();
        List<Inventory__c> newInventory = new List<Inventory__c>();
        List<Inventory_Adjustment__c> createInventoryAdjustment = new List<Inventory_Adjustment__c>();
        String invoiceName;
        String distributorName;
        for(Invoice_Line_Item__c invLineItem : invLineItemList){
            System.debug('invLineItem.Received_Quantity__c==> '+invLineItem.Received_Quantity__c);
            System.debug('oldInvLineItemMap.get(invLineItem.Id).Received_Quantity__c==> '+oldInvLineItemMap.get(invLineItem.Id).Received_Quantity__c);
            System.debug('invLineItem.Good_receipt_note__c==> '+invLineItem.Good_receipt_note__c);
            if(invLineItem.Invoice__c != Null && invLineItem.Received_Quantity__c != Null && oldInvLineItemMap.get(invLineItem.Id).Received_Quantity__c != invLineItem.Received_Quantity__c && invLineItem.Good_receipt_note__c != Null){
                invoiceName = invLineItem.Invoice__c;
                productId.add(invLineItem.Product__c);
                if(productMap.containsKey(invLineItem.Product__c)){
                    Decimal quantity = productMap.get(invLineItem.Product__c) + invLineItem.Received_Quantity__c;
                    productMap.put(invLineItem.Product__c , quantity);
                }else{
                    productMap.put(invLineItem.Product__c , invLineItem.Received_Quantity__c);
                }
            }
        }
        System.debug('productMap==> ' + productMap);
        
        if(invoiceName != Null){
            for(Invoice__c inv : [SELECT Id , Distributor_Account__c , Under_SS__c , RecordTypeId FROM Invoice__c WHERE Id =: invoiceName AND (RecordTypeId =: priInvoiceRecordType OR RecordTypeId =:underSsRecordType)]){
                invoiceId.add(inv.Id);
                if(inv.RecordTypeId == priInvoiceRecordType){
                    distributorName = inv.Distributor_Account__c;
                }
                if(inv.RecordTypeId == underSsRecordType){
                    distributorName = inv.Under_SS__c;
                }
            }
        }
        System.debug('distributorName==> ' + distributorName);
        Map<String,Inventory__c> existingInventoryMap = new Map<String,Inventory__c>();
        for(Inventory__c inv : [SELECT Id , Name , Product__c , Quantity_in_hand__c FROM Inventory__c WHERE Product__c IN: productId AND Distributor_Name__c =: distributorName]){
            existingInventoryMap.put(inv.Product__c , inv);
        }
        System.debug('existingInventoryMap==> '+existingInventoryMap);
        
        Inventory_Adjustment__c newInventoryAdjustment;
        Inventory__c updateInventoryRecord;
        Inventory__c newInventoryRecord;
        for(Id proId : productId){
            newInventoryAdjustment = new Inventory_Adjustment__c();
            Inventory__c inventoryRecord = existingInventoryMap.get(proId);
            if(existingInventoryMap.containsKey(proId)){
                updateInventoryRecord = new Inventory__c();
                System.debug('productMap.get(proId)==> '+productMap.get(proId));
                System.debug('existingInventoryMap.get(proId)==> '+existingInventoryMap.get(proId));
                updateInventoryRecord.Id = inventoryRecord.Id;
                //updateInventoryRecord.Quantity_in_hand__c = (inventoryRecord.Quantity_in_hand__c != null ? updateInventoryRecord.Quantity_in_hand__c : 0) + productMap.get(proId);
                updateInventoryRecord.Quantity_in_hand__c = inventoryRecord.Quantity_in_hand__c + productMap.get(proId);
                    
                updateInventory.add(updateInventoryRecord);
                
                newInventoryAdjustment.Inventory__c = inventoryRecord.Id;
            }else{
                newInventoryRecord = new Inventory__c();
                newInventoryRecord.Distributor_Name__c = distributorName;
                newInventoryRecord.Product__c = proId;
                newInventoryRecord.Quantity_in_hand__c = productMap.get(proId);
                
                newInventory.add(newInventoryRecord);
            }
            
            newInventoryAdjustment.Quantity__c =  productMap.get(proId);
            newInventoryAdjustment.Product__c = proId;
            newInventoryAdjustment.Type__c = 'Increment';
            newInventoryAdjustment.Primary_Invoice_transaction__c = invoiceName;
            newInventoryAdjustment.Adjustment_Date__c = Date.today();
            createInventoryAdjustment.add(newInventoryAdjustment);
        }
        System.debug('updateInventory==> ' + updateInventory);
        System.debug('newInventory==> ' + newInventory);
        
        if(newInventory.size()>0){
            insert newInventory;
            
            Map<Id, Id> prodToInventoryIdMap = new Map<Id, Id>();
            for (Inventory__c newInv : newInventory) {
                prodToInventoryIdMap.put(newInv.Product__c, newInv.Id);
            }
            for (Inventory_Adjustment__c adj : createInventoryAdjustment) {
                if (adj.Inventory__c == null && prodToInventoryIdMap.containsKey(adj.Product__c)) {
                    adj.Inventory__c = prodToInventoryIdMap.get(adj.Product__c);
                }
            }
        }
          
        if(updateInventory.size()>0){
            Update updateInventory;
        }
        
        if(createInventoryAdjustment.size()>0){
            insert createInventoryAdjustment;
        }
    }
}