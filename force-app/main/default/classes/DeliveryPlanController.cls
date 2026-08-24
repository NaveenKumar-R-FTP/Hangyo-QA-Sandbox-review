public with sharing class DeliveryPlanController { 
    
    //To capture delivery plan from DMS
    @AuraEnabled
    public static String saveDeliveryPlan(String deliveryPlanJson, String selectedInvoicesJson,String aggregatedProductsJson) {
        try {
            // Deserialize the deliveryPlan JSON string to a Delivery_Plan__c object
            Delivery_Plan__c deliveryPlan = (Delivery_Plan__c) JSON.deserialize(deliveryPlanJson, Delivery_Plan__c.class);
            
            // Deserialize the selectedInvoices JSON string to a List of Ids
            List<Id> selectedInvoiceIds = (List<Id>) JSON.deserialize(selectedInvoicesJson, List<Id>.class);
            
            // Deserialize the aggregated products JSON string to a List of Map<String, Object>
            // Deserialize the aggregated products JSON string
            List<Object> aggregatedProductsRaw = (List<Object>) JSON.deserializeUntyped(aggregatedProductsJson);
            List<Map<String, Object>> aggregatedProducts = new List<Map<String, Object>>();
            for (Object obj : aggregatedProductsRaw) {
                aggregatedProducts.add((Map<String, Object>) obj);
            }
            system.debug('deliveryPlan'+deliveryPlan);
            system.debug('selectedInvoiceIds'+selectedInvoiceIds);
            system.debug('Picklist'+aggregatedProducts);
            // Insert the Delivery Plan record
            insert deliveryPlan;
            
            // Create a list for junction records
            List<Delivery_Plan_Items__c> deliveryItems = new List<Delivery_Plan_Items__c>();
            
            // For each selected invoice, create a Delivery_Plan_Items__c record
            for (Id invoiceId : selectedInvoiceIds) {
                Delivery_Plan_Items__c deliveryItem = new Delivery_Plan_Items__c();
                deliveryItem.Delivery_Plan__c = deliveryPlan.Id;
                deliveryItem.Invoices__c = invoiceId;
                
                deliveryItems.add(deliveryItem);
            }
            
            // Insert the junction records
            if (!deliveryItems.isEmpty()) {
                insert deliveryItems;
            }
            
            // Create a list for Picklist__c records
            List<Picklist__c> picklistItems = new List<Picklist__c>();
            for (Map<String, Object> product : aggregatedProducts) {
                Picklist__c picklistItem = new Picklist__c();
                picklistItem.Delivery_Plan__c = deliveryPlan.Id;
                picklistItem.Product__c = (String) product.get('productId'); // Ensure the client sends Product__c Ids
                picklistItem.Quantity__c = (Decimal) product.get('totalQuantity');
                picklistItem.UOM__c = (String)product.get('uom');
                picklistItem.Gross_Amount__c = Decimal.valueOf((String) product.get('totalPrice'));
                picklistItem.Unit_Price__c = (Decimal) product.get('unitPrice');
                picklistItems.add(picklistItem);
            }
            if (!picklistItems.isEmpty()) {
                insert picklistItems;
            }
            
            return deliveryPlan.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving record: ' + e.getMessage());
        }
    }
    
        
    @AuraEnabled(cacheable=true)
public static Map<String, Id> getInvoiceRecordTypeIds() {
    Map<String, Id> recordTypeMap = new Map<String, Id>();

    Map<String, Schema.RecordTypeInfo> rtMap = Schema.SObjectType.Invoice__c.getRecordTypeInfosByName();

    if (rtMap.containsKey('Secondary Invoice')) {
        recordTypeMap.put('SecondaryInvoice', rtMap.get('Secondary Invoice').getRecordTypeId());
    }
    if (rtMap.containsKey('Secondary Invoice Under SS')) {
        recordTypeMap.put('SecondaryInvoiceUnderSS', rtMap.get('Secondary Invoice Under SS').getRecordTypeId());
    }

    return recordTypeMap;
}
    
    //To fetch all confirmed invoice of the logged in distributor
    @AuraEnabled
    public static List<Invoice__c> getConfirmedInvoices() {
        try {
            // Get the current user's details (Distributor_Account__c)
            user usr = [SELECT contactid, AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            
           
            List<Invoice__c> invoicelist = new List<Invoice__c>();
            
            Id superStockistRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Super Stockist').getRecordTypeId();

            //contact con = [SELECT Id, AccountId FROM Contact WHERE Id=:usr.contactid];
            
            // Get the RecordTypeId for Secondary_Invoice    
            Id secondaryInvoiceRecordTypeId = Schema.SObjectType.Invoice__c.getRecordTypeInfosByName().get('Secondary Invoice').getRecordTypeId();
            Id secondaryUndesSSInvoiceRecordTypeId = Schema.SObjectType.Invoice__c.getRecordTypeInfosByName().get('Secondary Invoice Under SS').getRecordTypeId();
            
            if(usr.AccountId != NULL){
                // Check if user's Account is a Super Stockist
                Boolean isSuperStockist = [
                    SELECT Id FROM Account 
                    WHERE Id = :usr.AccountId 
                    AND RecordTypeId = :superStockistRecordTypeId
                    LIMIT 1
                ].size() > 0;
                
                // Build query
                invoicelist = [
                    SELECT Id,RecordTypeId, Invoice_Number__c, Retailer_Account__c, Retailer_Account__r.Name,Under_SS__c,Under_SS__r.name,
                    Beat__c, Invoice_Amount__c, Total_Quantity__c,
                    (SELECT 
                     Id, 
                     Invoice__c, 
                     Price__c, 
                     Product__r.Name, 
                     Product__r.Unit_of_Measure__c, 
                     Product__r.Crate_Conversion__c,
                     Quantity__c 
                     FROM Invoice_Line_Items__r)
                    FROM Invoice__c 
                    WHERE (Status__c = 'Confirmed' OR Status__c = 'Draft')
                    AND Distributor_Account__c = :usr.AccountId
                    AND RecordTypeId IN :(
                        isSuperStockist ? 
                        new List<Id>{secondaryInvoiceRecordTypeId, secondaryUndesSSInvoiceRecordTypeId} : 
                        new List<Id>{secondaryInvoiceRecordTypeId}
                    )
                    ORDER BY Invoice_Number__c DESC
                ];     
            }
            return invoicelist;
        } catch (Exception e) {
                      System.debug(e.getMessage());
            System.debug(e.getLineNumber());
            throw new AuraHandledException('Error fetching invoices: ' + e.getMessage());
      
        }
    }

    
    // Fetch Delivery Plan details, including associated picklist records
    @AuraEnabled
    public static Map<String, Object> getDeliveryPlanForEdit(Id deliveryPlanId) {
        try {
            // Fetch the Delivery Plan record
            Delivery_Plan__c deliveryPlan = [
                SELECT Id, Name, Date__c, Driver_Name__c, Driver_Number__c, Vehicle_Number__c
                FROM Delivery_Plan__c
                WHERE Id = :deliveryPlanId
                LIMIT 1
            ];
            
            // Fetch related picklist records
            List<Picklist__c> picklistItems = [
                SELECT Id, Product__c, Product__r.Name, Quantity__c, Product__r.Crate_Conversion__c, UOM__c 
                FROM Picklist__c
                WHERE Delivery_Plan__c = :deliveryPlanId
            ];
            
            // Fetch related invoice junction records
            List<Delivery_Plan_Items__c> deliveryItems = [
                SELECT Id, Invoices__c, Invoices__r.Id
                FROM Delivery_Plan_Items__c
                WHERE Delivery_Plan__c = :deliveryPlanId
            ];
            
            List<Invoice__c> confirmedInvoices = new List<Invoice__c>();
            
            // Loop through each Delivery Plan Item to fetch associated Invoice and Invoice Line Items
            for (Delivery_Plan_Items__c dl : deliveryItems) {
                // Fetch the related invoice with its line items
                confirmedInvoices.addAll([
                    SELECT Id, Invoice_Number__c, Retailer_Account__c, Retailer_Account__r.Name,Under_SS__c,Under_SS__r.name,
                    Beat__c, Invoice_Amount__c, Total_Quantity__c,RecordTypeId,
                    (SELECT Id, Invoice__c, Price__c, Product__r.Name, Product__r.Unit_of_Measure__c, Product__r.Crate_Conversion__c, Quantity__c 
                     FROM Invoice_Line_Items__r)
                    FROM Invoice__c
                    WHERE Id = :dl.Invoices__c
                ]);
            }
            
            
            // Prepare the response
            Map<String, Object> result = new Map<String, Object>();
            result.put('deliveryPlan', deliveryPlan);
            result.put('picklistItems', picklistItems);
            result.put('selectedInvoices', deliveryItems);
            result.put('confirmedInvoices', confirmedInvoices);
            
            return result;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching delivery plan: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static String updateDeliveryPlan(String deliveryPlanJson, String selectedInvoicesJson, String aggregatedProductsJson) {
        try {
            // Deserialize the deliveryPlan JSON string to a Delivery_Plan__c object
            Delivery_Plan__c deliveryPlan = (Delivery_Plan__c) JSON.deserialize(deliveryPlanJson, Delivery_Plan__c.class);
            
            // Deserialize the selectedInvoices JSON string to a List of Ids
            List<Id> selectedInvoiceIds = (List<Id>) JSON.deserialize(selectedInvoicesJson, List<Id>.class);
            
            // Deserialize the aggregated products JSON string to a List of Map<String, Object>
            List<Object> aggregatedProductsRaw = (List<Object>) JSON.deserializeUntyped(aggregatedProductsJson);
            List<Map<String, Object>> aggregatedProducts = new List<Map<String, Object>>();
            for (Object obj : aggregatedProductsRaw) {
                aggregatedProducts.add((Map<String, Object>) obj);
            }
            
            // Update the Delivery Plan record
            update deliveryPlan;
            
            // Fetch existing Delivery Plan Items
            Set<Id> existingInvoiceIds = new Set<Id>();
            List<Delivery_Plan_Items__c> existingDeliveryItems = [
                SELECT Id, Invoices__c
                FROM Delivery_Plan_Items__c
                WHERE Delivery_Plan__c = :deliveryPlan.Id
            ];
            for (Delivery_Plan_Items__c item : existingDeliveryItems) {
                existingInvoiceIds.add(item.Invoices__c);
            }
            
            // Identify and insert new Delivery Plan Items
            List<Delivery_Plan_Items__c> newDeliveryItems = new List<Delivery_Plan_Items__c>();
            for (Id invoiceId : selectedInvoiceIds) {
                if (!existingInvoiceIds.contains(invoiceId)) {
                    Delivery_Plan_Items__c newItem = new Delivery_Plan_Items__c();
                    newItem.Delivery_Plan__c = deliveryPlan.Id;
                    newItem.Invoices__c = invoiceId;
                    newDeliveryItems.add(newItem);
                }
            }
            if (!newDeliveryItems.isEmpty()) {
                insert newDeliveryItems;
            }
            
            // Fetch existing Picklist__c records related to the Delivery Plan
            List<Picklist__c> existingPicklistItems = [
                SELECT Id, Product__c, Quantity__c
                FROM Picklist__c
                WHERE Delivery_Plan__c = :deliveryPlan.Id
            ];
            if (!existingPicklistItems.isEmpty()) {
                delete existingPicklistItems;
            }
            // Create a list for Picklist__c records
            List<Picklist__c> picklistItems = new List<Picklist__c>();
            for (Map<String, Object> product : aggregatedProducts) {
                Picklist__c picklistItem = new Picklist__c();
                picklistItem.Delivery_Plan__c = deliveryPlan.Id;
                picklistItem.Product__c = (String) product.get('productId'); // Ensure the client sends Product__c Ids
                picklistItem.Quantity__c = (Decimal) product.get('totalQuantity');
                picklistItem.UOM__c = (String)product.get('uom');
                picklistItem.Gross_Amount__c = Decimal.valueOf((String) product.get('totalPrice'));
                picklistItem.Unit_Price__c = (Decimal) product.get('unitPrice');
                picklistItems.add(picklistItem);
            }
            if (!picklistItems.isEmpty()) {
                insert picklistItems;
            }
            // Create a map for quick lookup of existing Picklist__c records by Product__c
            /*Map<Id, Picklist__c> existingPicklistMap = new Map<Id, Picklist__c>();
            for (Picklist__c picklist : existingPicklistItems) {
                existingPicklistMap.put(picklist.Product__c, picklist);
            }
            
            // Create lists for records to update and insert
            List<Picklist__c> picklistToUpdate = new List<Picklist__c>();
            List<Picklist__c> picklistToInsert = new List<Picklist__c>();
            
            for (Map<String, Object> product : aggregatedProducts) {
                Id productId = (Id) product.get('productId');
                Decimal newQuantity = (Decimal) product.get('totalQuantity');
                String uom = (String) product.get('Uom');
                
                // Check if a picklist item already exists for this product
                if (existingPicklistMap.containsKey(productId)) {
                    // Update the existing record
                    Picklist__c existingPicklist = existingPicklistMap.get(productId);
                    existingPicklist.Quantity__c = newQuantity; // Update quantity
                    existingPicklist.UOM__c = uom; // Update UOM if necessary
                    picklistToUpdate.add(existingPicklist);
                } else {
                    // Create a new picklist item for unmatched products
                    Picklist__c newPicklist = new Picklist__c();
                    newPicklist.Delivery_Plan__c = deliveryPlan.Id;
                    newPicklist.Product__c = productId;
                    newPicklist.Quantity__c = newQuantity;
                    newPicklist.UOM__c = uom;
                    picklistToInsert.add(newPicklist);
                }
            }
            
            // Perform DML operations
            if (!picklistToUpdate.isEmpty()) {
                update picklistToUpdate;
            }
            if (!picklistToInsert.isEmpty()) {
                insert picklistToInsert;
            }*/
            
            return deliveryPlan.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error updating delivery plan: ' + e.getMessage());
        }
    }
    
 @AuraEnabled
    public static void deleteInvoice(Id invoiceId) {
        
        try {
            List<Delivery_Plan_Items__c> dpItemDeleteList = new List<Delivery_Plan_Items__c>();
            //If there are delivery plan items related to the invoice ID then delete.
            dpItemDeleteList = [SELECT Id FROM Delivery_Plan_Items__c WHERE Invoices__c = :invoiceId];
            if (!dpItemDeleteList.isEmpty()) {
                delete dpItemDeleteList; 
            }
            
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting invoice: ' + e.getMessage());
        }
	}  
}