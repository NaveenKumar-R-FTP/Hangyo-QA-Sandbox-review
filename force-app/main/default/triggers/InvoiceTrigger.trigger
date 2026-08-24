trigger InvoiceTrigger on Invoice__c (before insert, before update, after insert, after update) {

// Discount 2 — mutual exclusivity + mode flag (runs before insert & before update)
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        InvoiceDiscountValidator.enforceFromHeader(Trigger.new);
    }
        // R2: on insert as Confirmed, set Invoice Date to the confirmation (server) date
    if (Trigger.isBefore && Trigger.isInsert) {
        for (Invoice__c inv : Trigger.new) {
            if (inv.Status__c == 'Confirmed') {
                inv.Invoice_Date__c = System.today();
            }
        }
    } // added by Manasa
    
    // Inventory Section 
    if (Trigger.isAfter && Trigger.isUpdate){
        UpdateQuantityInHand.updateSecondaryInvoiceQuantity(Trigger.new, Trigger.oldMap);
    }
    // End Of Inventory Section
    
    // Section used for updating order status based on Invoice status, Order line item quantity and Invoice line item quantity
    /* User should not be allowed to move backwards from Delivered to Confirmed Or Draft or Confirmed to Draft*/
    Set<Id> invoiceIdsToCheck = new Set<Id>();
    if (Trigger.isBefore && Trigger.isUpdate) {
        for (Invoice__c inv : Trigger.new) {
            Invoice__c oldInv = Trigger.oldMap.get(inv.Id);
            
            String oldStatus = oldInv.Status__c;
            String newStatus = inv.Status__c;
            
            // Prevent backward movement
            if ((oldStatus == 'Delivered' && (newStatus == 'Confirmed' || newStatus == 'Draft')) ||
                (oldStatus == 'Confirmed' && newStatus == 'Draft')) {
                    inv.addError('You cannot move invoice status backwards from ' + oldStatus + ' to ' + newStatus + '.');
                }
            // New validation: Collect invoices moving to Confirmed
            if (newStatus == 'Confirmed' && oldStatus != 'Confirmed') {
                invoiceIdsToCheck.add(inv.Id);
            }
                        // R2: on first move to Confirmed, set Invoice Date to the confirmation (server) date
            if (newStatus == 'Confirmed' && oldStatus != 'Confirmed') {
                inv.Invoice_Date__c = System.today();
            }
            // R2: once Confirmed/Delivered, Invoice Date is the immutable window base — lock it
            if ((oldStatus == 'Confirmed' || oldStatus == 'Delivered')
                && inv.Invoice_Date__c != oldInv.Invoice_Date__c) {
                inv.Invoice_Date__c = oldInv.Invoice_Date__c;
            }
        }
    }
    
    if (!invoiceIdsToCheck.isEmpty()) {
        // Step 1: Fetch related Invoice Line Items
        List<Invoice_Line_Item__c> invoiceLineItems = [
            SELECT Id, Invoice__c, Product__c,Product__r.Name, Quantity__c, Invoice__r.Distributor_Account__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c IN :invoiceIdsToCheck
        ];
        
        // Step 2: Prepare to fetch Inventory__c
        Set<String> distributorProductKeys = new Set<String>();
        Map<String, Invoice_Line_Item__c> keyToLineItem = new Map<String, Invoice_Line_Item__c>();
        Set<String> productKeys = new Set<String>();
        String distributorId;
        
        for (Invoice_Line_Item__c lineItem : invoiceLineItems) {
            if (lineItem.Product__c == null || lineItem.Invoice__r.Distributor_Account__c == null) continue;
            
            String key = lineItem.Invoice__r.Distributor_Account__c + '-' + lineItem.Product__c;
            distributorProductKeys.add(key);
            productKeys.add(lineItem.Product__c);
            distributorId = lineItem.Invoice__r.Distributor_Account__c;
            keyToLineItem.put(lineItem.Id, lineItem);
        }
        
        // Step 3: Fetch Inventory records
        Map<String, Inventory__c> inventoryMap = new Map<String, Inventory__c>();
        for (Inventory__c invt : [
            SELECT Id, Distributor_Name__c, Product__c, Quantity_in_hand__c
            FROM Inventory__c
            WHERE Distributor_Name__c =: distributorId AND Product__c IN: productKeys
        ]) {
            String key = invt.Distributor_Name__c + '-' + invt.Product__c;
            if (distributorProductKeys.contains(key)) {
                inventoryMap.put(key, invt);
            }
        }
        
        // Step 4: Validate quantities
        for (Invoice_Line_Item__c lineItem : invoiceLineItems) {
            String key = lineItem.Invoice__r.Distributor_Account__c + '-' + lineItem.Product__c;
            Inventory__c matchingInventory = inventoryMap.get(key);
            
            if (matchingInventory == null) {
                Trigger.newMap.get(lineItem.Invoice__c).addError('No matching inventory found for Product ' + lineItem.Product__r.Name + ' for the distributor') ;
            } else if (matchingInventory.Quantity_in_hand__c < lineItem.Quantity__c) {
                Trigger.newMap.get(lineItem.Invoice__c).addError('Insufficient inventory for ' 
                    + lineItem.Product__r.Name + '. Available: ' + matchingInventory.Quantity_in_hand__c + 
                    ', Required: ' + lineItem.Quantity__c);
            }
        }
        
    }     
if (!invoiceIdsToCheck.isEmpty()) {
        MultiSchemeReimbursementService.applyLinesOnConfirm(invoiceIdsToCheck);
    }
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {   
        Set<Id> orderIds = new Set<Id>();
        
        for (Invoice__c inv : Trigger.new) {
            if (inv.Order__c != null &&
                (inv.Status__c == 'Confirmed' || inv.Status__c == 'Delivered')) {
                    orderIds.add(inv.Order__c);
                }
        }
        
        if (orderIds.isEmpty()) return;
        
        // Step 1: Ordered quantity per Product per Order
        Map<Id, Map<Id, Decimal>> orderToOrderedProducts = new Map<Id, Map<Id, Decimal>>();
        for (AggregateResult ar : [
            SELECT Order__c oId, Products__c prodId, SUM(Ordered_Quantity__c) qty
            FROM Order_Line_Item__c
            WHERE Order__c IN :orderIds
            GROUP BY Order__c, Products__c
        ]) {
            Id orderId = (Id) ar.get('oId');
            Id productId = (Id) ar.get('prodId');
            Decimal qty = (Decimal) ar.get('qty');
            if (productId == null) continue;
            
            if (!orderToOrderedProducts.containsKey(orderId)) {
                orderToOrderedProducts.put(orderId, new Map<Id, Decimal>());
            }
            orderToOrderedProducts.get(orderId).put(productId, qty);
        }
        
        // Step 2: Invoiced quantity per Product per Order
        Map<Id, Map<Id, Decimal>> orderToInvoicedProducts = new Map<Id, Map<Id, Decimal>>();
        for (AggregateResult ar : [
            SELECT Invoice__r.Order__c oId, Product__c prodId, SUM(Quantity__c) qty
            FROM Invoice_Line_Item__c
            WHERE Invoice__r.Order__c IN :orderIds
            AND Invoice__r.Status__c IN ('Confirmed', 'Delivered')
            GROUP BY Invoice__r.Order__c, Product__c
        ]) {
            Id orderId = (Id) ar.get('oId');
            Id productId = (Id) ar.get('prodId');
            Decimal qty = (Decimal) ar.get('qty');
            if (productId == null) continue;
            
            if (!orderToInvoicedProducts.containsKey(orderId)) {
                orderToInvoicedProducts.put(orderId, new Map<Id, Decimal>());
            }
            orderToInvoicedProducts.get(orderId).put(productId, qty);
        }
        
        // Step 3: Fetch all invoices for the orders
        Map<Id, List<Invoice__c>> orderToInvoices = new Map<Id, List<Invoice__c>>();
        for (Invoice__c inv : [
            SELECT Id, Order__c, Status__c
            FROM Invoice__c
            WHERE Order__c IN :orderIds
        ]) {
            if (!orderToInvoices.containsKey(inv.Order__c)) {
                orderToInvoices.put(inv.Order__c, new List<Invoice__c>());
            }
            orderToInvoices.get(inv.Order__c).add(inv);
        }
        
        // Step 4: Evaluate and update order statuses
        List<Order__c> ordersToUpdate = new List<Order__c>();
        
        for (Id orderId : orderIds) {
            Map<Id, Decimal> orderedMap = orderToOrderedProducts.get(orderId);
            Map<Id, Decimal> invoicedMap = orderToInvoicedProducts.get(orderId);
            
            if (orderedMap == null || orderedMap.isEmpty()) continue;
            
            // Count only matching products
            Boolean hasMatchingProduct = false;
            Boolean fullyInvoiced = true;
            
            for (Id productId : orderedMap.keySet()) {
                Decimal orderedQty = orderedMap.get(productId);
                Decimal invoicedQty = (invoicedMap != null && invoicedMap.containsKey(productId)) ? invoicedMap.get(productId) : 0;
                
                if (invoicedQty > 0) {
                    hasMatchingProduct = true;
                }
                
                if (invoicedQty < orderedQty) {
                    fullyInvoiced = false;
                }
            }
            
            // Evaluate invoice statuses for that order
            Boolean allDelivered = true;
            for (Invoice__c inv : orderToInvoices.get(orderId)) {
                if (inv.Status__c != 'Delivered') {
                    allDelivered = false;
                    break;
                }
            }
            
            Order__c ordToUpdate = new Order__c(Id = orderId);
            
            if (!hasMatchingProduct) {
                continue; // don't update the order at all
            } else if (!fullyInvoiced) {
                ordToUpdate.Status__c = 'Partially Invoiced';
            } else if (fullyInvoiced && allDelivered) {
                ordToUpdate.Status__c = 'Delivered';
            } else if (fullyInvoiced) {
                ordToUpdate.Status__c = 'Invoiced';
            }
            
            ordersToUpdate.add(ordToUpdate);
        }
        
        if (!ordersToUpdate.isEmpty()) {
            update ordersToUpdate;
        }
    }

}