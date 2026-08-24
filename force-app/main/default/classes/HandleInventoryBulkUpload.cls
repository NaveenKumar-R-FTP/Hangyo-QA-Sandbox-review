public class HandleInventoryBulkUpload {

    public static void inventoryBulkUpload(List<Invoice_Line_Item__c> invoiceLines){

        if (invoiceLines == null || invoiceLines.isEmpty()) {
            return;
        }

        Set<Id> invoiceIds = new Set<Id>();

        for (Invoice_Line_Item__c line : invoiceLines) {
            if (line.Invoice__c != null) {
                invoiceIds.add(line.Invoice__c);
            }
        }

        if (invoiceIds.isEmpty()) {
            return;
        }

        Id secInvoiceRecordType =
            Schema.SObjectType.Invoice__c.getRecordTypeInfosByDeveloperName().get('Secondary_Invoice').getRecordTypeId();

        Map<Id, Invoice__c> invoiceMap = new Map<Id, Invoice__c>(
                [
                    SELECT Id, Name, Status__c, RecordTypeId, Distributor_Account__c
                    FROM Invoice__c WHERE Id IN :invoiceIds
                ]
            );

        Set<Id> productIds = new Set<Id>();
        Set<Id> distributorIds = new Set<Id>();
        Map<String, Decimal> quantityMap = new Map<String, Decimal>();

        for (Invoice_Line_Item__c line : invoiceLines) {
            Invoice__c inv = invoiceMap.get(line.Invoice__c);

            if (inv == null ||
                inv.Status__c != 'Confirmed' ||
                inv.RecordTypeId != secInvoiceRecordType ||
                inv.Distributor_Account__c == null ||
                line.Product__c == null ||
                line.Quantity__c == null) {
                continue;
            }

            productIds.add(line.Product__c);
            distributorIds.add(inv.Distributor_Account__c);
            String key = inv.Distributor_Account__c + '-' + line.Product__c;
            Decimal existingQty = quantityMap.containsKey(key) ? quantityMap.get(key) : 0;
            quantityMap.put(key,existingQty + line.Quantity__c);
        }

        if (quantityMap.isEmpty()) {
            return;
        }

        Map<String, Inventory__c> inventoryMap = new Map<String, Inventory__c>();

        for (Inventory__c inv : [
            SELECT Id, Product__c, Distributor_Name__c, Quantity_in_hand__c FROM Inventory__c
            WHERE Product__c IN :productIds AND Distributor_Name__c IN :distributorIds
        ]) {

            String key = inv.Distributor_Name__c + '-' + inv.Product__c;
            inventoryMap.put(key, inv);
        }

        List<Inventory__c> inventoriesToUpdate = new List<Inventory__c>();

        for (String key : quantityMap.keySet()) {
            if (inventoryMap.containsKey(key)) {
                Inventory__c inventory = inventoryMap.get(key);

                Decimal deductionQty = quantityMap.get(key);
                inventory.Quantity_in_hand__c -= deductionQty;
                inventoriesToUpdate.add(inventory);
            }
        }

        List<Inventory_Adjustment__c> adjustments = new List<Inventory_Adjustment__c>();

        for (Invoice_Line_Item__c line : invoiceLines) {
            Invoice__c inv = invoiceMap.get(line.Invoice__c);

            if (inv == null ||
                inv.Status__c != 'Confirmed' ||
                inv.RecordTypeId != secInvoiceRecordType ||
                inv.Distributor_Account__c == null ||
                line.Product__c == null ||
                line.Quantity__c == null) {
                continue;
            }

            String key = inv.Distributor_Account__c + '-' + line.Product__c;

            if (inventoryMap.containsKey(key)) {
                Inventory__c inventory = inventoryMap.get(key);

                Inventory_Adjustment__c adjustment = new Inventory_Adjustment__c();
                adjustment.Quantity__c = line.Quantity__c;
                adjustment.Inventory__c = inventory.Id;
                adjustment.Product__c = line.Product__c;
                adjustment.Type__c = 'Decrement';
                adjustment.Secondary_Invoice_transaction__c = inv.Id;
                adjustment.Adjustment_Date__c = Date.today();
                adjustments.add(adjustment);
            }
        }

        if (!inventoriesToUpdate.isEmpty()) {
            update inventoriesToUpdate;
        }

        if (!adjustments.isEmpty()) {
            insert adjustments;
        }
    }
}