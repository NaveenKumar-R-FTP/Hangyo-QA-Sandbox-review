public without sharing class UpdateInventoryRecord {
    
    public static void updateInventorySecondaryReturn(List<Return_Line_item__c> returnLineItemList){
        Set<Id> productId = new Set<Id>();
        Map<String,Decimal> productMap = new Map<String,Decimal>();
        List<Inventory__c> updateInventory = new List<Inventory__c>();
        List<Inventory_Adjustment__c> createInventoryAdjustment = new List<Inventory_Adjustment__c>();
        String distributorName;
        String invoiceId;
        String returnId;
        
        if(returnLineItemList.size() > 0){
            for(Return_Line_item__c returnLine : returnLineItemList){
                if(returnLine.Reuse_count__c != null){
                    productId.add(returnLine.Product__c);
                    productMap.put(returnLine.Product__c , returnLine.Reuse_count__c);
                    returnId = returnLine.Return__c;
                }
            }
        }
        
        if(returnId != Null){
            for(Returns__c returnList : [SELECT Id , Name , Order__r.AccountId__c , Invoice__c FROM Returns__c WHERE Id =: returnId]){
                distributorName = returnList.Order__r.AccountId__c;
                invoiceId = returnList.Invoice__c;
            }
        }
        
        Inventory_Adjustment__c newInventory;
        for(Inventory__c inv : [SELECT Id , Name , Product__c , Quantity_in_hand__c FROM Inventory__c WHERE Product__c IN: productId AND Distributor_Name__c =: distributorName]){
            inv.Quantity_in_hand__c = inv.Quantity_in_hand__c + productMap.get(inv.Product__c);
            
            newInventory = new Inventory_Adjustment__c();
            newInventory.Quantity__c =  productMap.get(inv.Product__c);
            newInventory.Inventory__c = inv.Id;
            newInventory.Product__c = inv.Product__c;
            newInventory.Type__c = 'Increment';
            newInventory.Secondary_Return__c = returnId;
            newInventory.Secondary_Invoice_transaction__c = invoiceId;
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
}