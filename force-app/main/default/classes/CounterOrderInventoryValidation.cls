public class CounterOrderInventoryValidation {
    
    public static void checkInventory(List<Order__c> orderList , Map<Id, Order__c> oldOrderMap){
        Set<Id> orderId = new Set<Id>();
        Set<Id> productId = new Set<Id>();
        Map<String, Inventory__c> inventoryMap = new Map<String, Inventory__c>();
        Map<Id, Order__c> orderMap = new Map<Id, Order__c>();
        String distributorName;
        for(Order__c ord:orderList){
            if(ord.Status__c == 'Delivered' && oldOrderMap.get(ord.Id).Status__c != 'Delivered'){
                orderId.add(ord.Id);
                orderMap.put(ord.Id, ord);
                distributorName = ord.AccountId__c;
            }
        }
        
        if (!orderId.isEmpty()){
            List<Order_Line_Item__c> orderLineItems = [
                SELECT Id, Order__c, Products__c, Products__r.Name ,Ordered_Quantity__c,Order__r.AccountId__c
                FROM Order_Line_Item__c
                WHERE Order__c IN: orderId AND Order__r.Record_Type_Name__c = 'Counter Order'
            ];
            
            for(Order_Line_Item__c lineItem : orderLineItems){
                if(lineItem.Products__c != null || lineItem.Order__r.AccountId__c != null){
                    productId.add(lineItem.Products__c);
                }
            }
            
            for (Inventory__c invt : [SELECT Id, Distributor_Name__c, Product__c, Quantity_in_hand__c FROM Inventory__c WHERE Distributor_Name__c =:distributorName AND Product__c IN: productId]){
                inventoryMap.put(invt.Product__c , invt);
            }
            
            for (Order_Line_Item__c lineItem : orderLineItems){
                Inventory__c matchingInventory = inventoryMap.get(lineItem.Products__c);
                Order__c targetOrder = orderMap.get(lineItem.Order__c);
                if(matchingInventory == null){
                    targetOrder.addError('No matching inventory found for Distributor ' 
                    + lineItem.Order__r.AccountId__c + ' and Product ' + lineItem.Products__c);
                }else if(matchingInventory.Quantity_in_hand__c < lineItem.Ordered_Quantity__c){
                    targetOrder.addError('Insufficient inventory for ' 
                    + lineItem.Products__r.Name + '. Available: ' + matchingInventory.Quantity_in_hand__c + 
                    ', Required: ' + lineItem.Ordered_Quantity__c);
                }
            }
        }
    }

}