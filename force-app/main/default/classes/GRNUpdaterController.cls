/**
* @File Name : GRNUpdaterController .cls
* @Description :
* @Author :
* @Last Modified By :
* @Last Modified On : December 28, 2024
* @Modification Log :
*==============================================================================
* Ver | Date | Author | Modification
*==============================================================================
* 1.0 | December 28, 2024 |   | Initial Version
**/

public with sharing class GRNUpdaterController {
    
    public class OrderLineItemWrapper {
        @AuraEnabled public String Comment;   // To store the comment
        @AuraEnabled public String Id;
        @AuraEnabled public String ProductImageURL;
        @AuraEnabled public String ProductName;
        @AuraEnabled public Decimal Quantity;
        @AuraEnabled public Decimal UpdatedQuantity;
        @AuraEnabled public String totalamt;
        // To store the updated quantity
        
    }
    
    @AuraEnabled(cacheable=true)
    public static List<OrderLineItemWrapper> getOrderLineItems(Id orderId) {
        List<OrderLineItemWrapper> wrappers = new List<OrderLineItemWrapper>();
        
        for (Order_Line_Item__c item : [
            SELECT Id, Ordered_Quantity__c,Total_Amount__c, Products__r.Name, Products__r.Image__c,Products__r.Image_Long__c
            FROM Order_Line_Item__c
            WHERE Order__c = :orderId
        ]) {
            OrderLineItemWrapper wrapper = new OrderLineItemWrapper();
            wrapper.Id = item.Id;
            system.debug(' wrapper.IdI-  '+ wrapper.Id);
            wrapper.ProductName = item.Products__r.Name;
            wrapper.ProductImageURL = item.Products__r.Image_Long__c;
            System.debug('ProductImageURL' +item.Products__r.Image_Long__c);
            wrapper.Quantity = item.Ordered_Quantity__c;
            wrapper.totalamt = String.valueOf(item.Total_Amount__c);
            wrapper.UpdatedQuantity=0;
            wrapper.Comment='';
            wrappers.add(wrapper);
        }
        return wrappers;
    }

      @AuraEnabled(cacheable=true)
    public static Map<String, Object> checkExistingGRN(Id orderId) {
        Map<String, Object> resultMap = new Map<String, Object>();
        
        // Check if GRN exists for the given order
        Boolean grnExists = [SELECT COUNT() FROM Good_receipt_notes__c WHERE Order__c = :orderId] > 0;
        resultMap.put('grnExists', grnExists);
        
        // Fetch the Order record along with its RecordType
        Order__c orderRecord = [SELECT Id, RecordType.DeveloperName FROM Order__c WHERE Id = :orderId LIMIT 1];

        if (orderRecord != null) {
            resultMap.put('recordTypeName', orderRecord.RecordType.DeveloperName);
        } else {
            resultMap.put('recordTypeName', null);
        }
        
        return resultMap;
    }

    @AuraEnabled
    public static Map<String, Decimal> calculateTotals(Id orderId, List<OrderLineItemWrapper> lineItems) {
        Decimal totalOrderValue = 0;
        Decimal totalQuantity = 0;
        Decimal updatedQuantitySum = 0;
        
        for (OrderLineItemWrapper item : lineItems) {
            // totalOrderValue += item.totalamt;
            totalQuantity += item.Quantity;
            updatedQuantitySum += item.UpdatedQuantity;
        }
        
        return new Map<String, Decimal>{
            'Total_Order_Value__c' => totalOrderValue,
                'Total_Quantity__c' => totalQuantity,
                'UpdatedQuantitySum' => updatedQuantitySum
                };
                    }
    
    @AuraEnabled
    public static void submitGRN(Id orderId,String jsonLineItems,String updatedQuan) {
        system.debug('orderId  '+orderId);
        System.debug('Order Id: ' + orderId);
        System.debug('Received JSON Line Items: ' + jsonLineItems);
        List<Order__c> ordrDetail = new List<Order__c>();
        ordrDetail=[SELECT id,Total_Quantity__c,Name,Status__c FROM Order__c where Id = :orderId];
        if (String.isBlank(jsonLineItems)) {
            throw new AuraHandledException('No line items received.');
        }
        
       
         List<OrderLineItemWrapper> lineItems = new List<OrderLineItemWrapper>();
        try {
            lineItems = (List<OrderLineItemWrapper>) JSON.deserialize(jsonLineItems, List<OrderLineItemWrapper>.class);
        } catch (Exception e) {
            System.debug('Error deserializing JSON: ' + e.getMessage());
            throw new AuraHandledException('Failed to process line items.');
        }
        
        System.debug('Deserialized Line Items: ' + JSON.serialize(lineItems));
        List<Good_receipt_notes__c> grnRecords = new List<Good_receipt_notes__c>();
        Map<Id, Id> grnIdMap = new Map<Id, Id>();
         RecordType rt = [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = 'Order__c' 
            AND Name = 'Primary Order' 
            LIMIT 1
        ];
        
        // for (OrderLineItemWrapper item : lineItems) {}
        Good_receipt_notes__c grn = new Good_receipt_notes__c();
        grn.Order__c = orderId;
        grn.Total_Changed_Quantity__c = Decimal.valueOf(updatedQuan);
        grn.Total_Quantity__c = ordrDetail[0].Total_Quantity__c;
        grnRecords.add(grn);
        insert grn;
        
        // insert grnRecords;
        
        /* Map inserted GRNs to respective Order Line Items
for (Integer i = 0; i < grnRecords.size(); i++) {
grnIdMap.put(lineItems[i].Id, grnRecords[i].Id);
}*/
        Order__c oOrder= new Order__c();
        oOrder.id=orderId;
     //   oOrder.Recordtypeid= rt.id;
        update oOrder;
        // Update Order Line Items
        List<Order_Line_Item__c> orderLineItemsToUpdate = new List<Order_Line_Item__c>();
        system.debug('lineItems  '+lineItems);
        for (OrderLineItemWrapper item : lineItems) {
            Order_Line_Item__c oli = new Order_Line_Item__c();
            oli.Id = item.Id;
            system.debug('id of QLI-  '+item.id);
            oli.Updated_quanity__c = item.UpdatedQuantity;
            oli.GRN_Comment__c = item.Comment;
            oli.Good_receipt_note__c = grn.id;
            orderLineItemsToUpdate.add(oli);
        }
        
        update orderLineItemsToUpdate;
    }
    
}