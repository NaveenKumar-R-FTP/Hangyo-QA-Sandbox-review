/*
Created By : Fuzail 
Description : Updating the GNR status on Order based on The GRN Button and Order Line Item and Invoices.

     * Main method to update GRN Status on Order__c based on Invoice Line Items
     * Handles both after insert and after update scenarios
     * Logic:
     * - If GRN quantity >= Order Line Item quantity = Fully GRN
     * - If GRN quantity > 0 but < Order Line Item quantity = Partially GRN
     * - If no GRN quantity = --None--
    
Created Date : 28/11/2025
Last Modified Date : 01/12/2025
*/

public class GRNStatusController {
    
    
    public static void updateGRNStatus(List<Invoice_Line_Item__c> invoiceLineItems, Map<Id, Invoice_Line_Item__c> oldMap) {
        if (invoiceLineItems == null || invoiceLineItems.isEmpty()) {
            return;
        }
        
        try {
            // Collect Invoice IDs that need GRN processing
            Set<Id> invoiceIds = new Set<Id>();
            
            for (Invoice_Line_Item__c ili : invoiceLineItems) {
                if (ili.Invoice__c != null) {
                    invoiceIds.add(ili.Invoice__c);
                }
            }
            
            if (invoiceIds.isEmpty()) {
                return;
            }
            
            // Step 1: Fetch all Invoices with their Order IDs
            Map<Id, Invoice__c> invoiceMap = new Map<Id, Invoice__c>(
                [SELECT Id, Order__c , Under_SS_Invoice__c FROM Invoice__c WHERE Id IN :invoiceIds]
            );
            
            // Step 2: Get all related Order IDs
            Set<Id> orderIds = new Set<Id>();
            for (Invoice__c inv : invoiceMap.values()) {
                if (inv.Under_SS_Invoice__c != null) {
                    orderIds.add(inv.Under_SS_Invoice__c);
                }else{
                    orderIds.add(inv.Order__c);
                }
            }
            System.debug('orderIds:- ' + orderIds);
            
            if (orderIds.isEmpty()) {
                return;
            }
            
            // Step 3: Fetch Order records with related Order Line Items
            Map<Id, Order__c> ordersMap = new Map<Id, Order__c>(
                [SELECT Id, GRN_Status__c, RecordTypeId,
                        (SELECT Id, Ordered_Quantity__c, Products__c FROM Order_Line_Items__r)
                 FROM Order__c 
                 WHERE Id IN :orderIds 
                 AND (RecordType.Name = 'Primary Order' OR RecordType.Name = 'Under SS Order')]
            );
            
            if (ordersMap.isEmpty()) {
                return;
            }
            
            // Step 4: Fetch all Invoice Line Items for these Orders
            Map<Id, List<Invoice_Line_Item__c>> orderToInvoiceLineItems = new Map<Id, List<Invoice_Line_Item__c>>();
            
            for (Invoice_Line_Item__c ili : [
                SELECT Id, Invoice__c, Invoice__r.Order__c, Product__c, Received_Quantity__c , Invoice__r.Under_SS_Invoice__c
                FROM Invoice_Line_Item__c
                WHERE (Invoice__r.Order__c IN :orderIds OR Invoice__r.Under_SS_Invoice__c IN :orderIds)
            ]) {
                Id orderId = ili.Invoice__r.Under_SS_Invoice__c != null ? ili.Invoice__r.Under_SS_Invoice__c : ili.Invoice__r.Order__c;
                System.debug('orderId:- ' + orderId);
                if (!orderToInvoiceLineItems.containsKey(orderId)) {
                    orderToInvoiceLineItems.put(orderId, new List<Invoice_Line_Item__c>());
                }
                orderToInvoiceLineItems.get(orderId).add(ili);
            }
            
            // Step 5: Calculate GRN Status for each Order
            List<Order__c> ordersToUpdate = new List<Order__c>();
            
            for (Id orderId : ordersMap.keySet()) {
                Order__c order = ordersMap.get(orderId);
                
                // Get total Order Line Item quantity
                Decimal totalOrderLineItemQty = 0;
                for (Order_Line_Item__c oli : order.Order_Line_Items__r) {
                    totalOrderLineItemQty += oli.Ordered_Quantity__c != null ? oli.Ordered_Quantity__c : 0;
                }
                
                // Get total GRNed quantity from all invoice line items
                Decimal totalGRNedQty = 0;
                List<Invoice_Line_Item__c> orderInvoiceLineItems = orderToInvoiceLineItems.get(orderId);
                
                if (orderInvoiceLineItems != null) {
                    for (Invoice_Line_Item__c ili : orderInvoiceLineItems) {
                        // Using Quantity__c - CHANGE THIS FIELD NAME once you identify the actual GRN field
                        if (ili.Received_Quantity__c != null && ili.Received_Quantity__c > 0) {
                            totalGRNedQty += ili.Received_Quantity__c;
                        }
                    }
                }
                
                // Determine new GRN Status
                String newGRNStatus = '--None--';
                
                if (totalGRNedQty > 0) {
                    if (totalGRNedQty >= totalOrderLineItemQty) {
                        newGRNStatus = 'Fully GRN';
                    } else {
                        newGRNStatus = 'Partially GRN';
                    }
                }
                
                // Update only if status changed
                if (newGRNStatus != order.GRN_Status__c) {
                    Order__c orderToUpdate = new Order__c(Id = orderId);
                    orderToUpdate.GRN_Status__c = newGRNStatus;
                    ordersToUpdate.add(orderToUpdate);
                }
            }
            
            // Step 6: Update Orders
            if (!ordersToUpdate.isEmpty()) {
                update ordersToUpdate;
            }
            
        } catch (Exception e) {
            System.debug('ERROR in GRNStatusController.updateGRNStatus: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
        }
    }
}