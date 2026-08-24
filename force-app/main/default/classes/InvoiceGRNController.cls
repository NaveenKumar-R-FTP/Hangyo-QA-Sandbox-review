// InvoiceGRNController.cls
public without sharing class InvoiceGRNController {
    
    @AuraEnabled
    public static Map<String, Object> checkExistingGRN(Id invoiceId) {
        Map<String, Object> response = new Map<String, Object>();
        
        // Check if GRN already processed
        Integer grnCount = [SELECT COUNT() FROM Good_receipt_notes__c WHERE Invoice__c = :invoiceId];
        response.put('grnExists', grnCount > 0);
        
        return response;
    }

    @AuraEnabled
   public static List<InvoiceLineWrapper> getInvoiceLineItems(Id invoiceId) {
    List<InvoiceLineWrapper> wrappers = new List<InvoiceLineWrapper>();

    // Query Invoice with necessary fields
    Invoice__c inv = [
        SELECT Order__c, Under_SS_Invoice__c, RecordType.DeveloperName 
        FROM Invoice__c 
        WHERE Id = :invoiceId
    ];

    Map<Id, Order_Line_Item__c> orderProductsMap = new Map<Id, Order_Line_Item__c>();
    Map<Id, Decimal> previousQuantities = new Map<Id, Decimal>();

    if (inv.RecordType.DeveloperName == 'Primary_Invoice') {
        // Query Order Line Items based on Order__c
        for (Order_Line_Item__c oli : [
            SELECT Id, Products__c, Ordered_Quantity__c 
            FROM Order_Line_Item__c 
            WHERE Order__c = :inv.Order__c
        ]) {
            orderProductsMap.put(oli.Products__c, oli);
        }

        // Query previous confirmed quantities based on Order__c
        for (AggregateResult ar : [
            SELECT Product__c, SUM(Received_Quantity__c) total 
            FROM Invoice_Line_Item__c 
            WHERE Invoice__r.Order__c = :inv.Order__c 
              AND Good_receipt_note__c != null 
            GROUP BY Product__c
        ]) {
            previousQuantities.put((Id)ar.get('Product__c'), (Decimal)ar.get('total'));
        }

    } else if (inv.RecordType.DeveloperName == 'Secondary_Invoice_Under_SS') {
        // Query Order Line Items based on Under_SS_Invoice__c
        for (Order_Line_Item__c oli : [
            SELECT Id, Products__c, Ordered_Quantity__c 
            FROM Order_Line_Item__c 
            WHERE Order__c = :inv.Under_SS_Invoice__c
        ]) {
            orderProductsMap.put(oli.Products__c, oli);
        }

        // Query previous confirmed quantities based on Under_SS_Invoice__c
        for (AggregateResult ar : [
            SELECT Product__c, SUM(Received_Quantity__c) total 
            FROM Invoice_Line_Item__c 
            WHERE Invoice__r.Under_SS_Invoice__c = :inv.Under_SS_Invoice__c 
              AND Good_receipt_note__c != null 
            GROUP BY Product__c
        ]) {
            previousQuantities.put((Id)ar.get('Product__c'), (Decimal)ar.get('total'));
        }
    }

    // Process current invoice line items
    for (Invoice_Line_Item__c ili : [
        SELECT Id, Product__c, Product__r.Name, Product__r.Image_Long__c,
               Quantity__c, GRN_Comment__c 
        FROM Invoice_Line_Item__c 
        WHERE Invoice__c = :invoiceId
    ]) {
        InvoiceLineWrapper wrapper = new InvoiceLineWrapper();
        wrapper.Id = ili.Id;
        wrapper.ProductId = ili.Product__c;
        wrapper.ProductName = ili.Product__r.Name;
        wrapper.ProductImageURL = ili.Product__r.Image_Long__c;
        wrapper.OrderQuantity = orderProductsMap.containsKey(ili.Product__c) 
            ? orderProductsMap.get(ili.Product__c).Ordered_Quantity__c 
            : 0;
        wrapper.PreviousConfirmedQuantity = previousQuantities.containsKey(ili.Product__c) 
            ? previousQuantities.get(ili.Product__c) 
            : 0;
        wrapper.CurrentInvoiceQuantity = ili.Quantity__c;

        wrappers.add(wrapper);
    }

    return wrappers;
}


    @AuraEnabled
    public static void submitGRN(Id invoiceId, String jsonLineItems,String updatedQuan) {
        List<InvoiceLineWrapper> wrappers = (List<InvoiceLineWrapper>)JSON.deserialize(
            jsonLineItems, 
            List<InvoiceLineWrapper>.class
        );

 List<Good_receipt_notes__c> grnRecords = new List<Good_receipt_notes__c>();
        Map<Id, Id> grnIdMap = new Map<Id, Id>();
         List<Invoice__c> inv = new List<Invoice__c>();
        inv=[SELECT Order__c, Total_Quantity__c, Under_SS_Invoice__c, RecordType.DeveloperName 
    FROM Invoice__c WHERE Id = :invoiceId];
       
   // Invoice__c inv = [SELECT Order__c FROM Invoice__c WHERE Id = :invoiceId];
        
      // Create GRN record
        Good_receipt_notes__c grn = new Good_receipt_notes__c();
        if (inv[0].RecordType.DeveloperName == 'Secondary_Invoice_Under_SS') {
    grn.Order__c = inv[0].Under_SS_Invoice__c;
} else if (inv[0].RecordType.DeveloperName == 'Primary_Invoice') {
    grn.Order__c = inv[0].Order__c;
}
        grn.Total_Changed_Quantity__c = Decimal.valueOf(updatedQuan);
        grn.Total_Quantity__c = inv[0].Total_Quantity__c;
        grn.Invoice__c = invoiceId;
        grnRecords.add(grn);
        insert grn;
    


        
        List<Invoice_Line_Item__c> toUpdate = new List<Invoice_Line_Item__c>();
        for (InvoiceLineWrapper wrapper : wrappers) {
            toUpdate.add(new Invoice_Line_Item__c(
                Id = wrapper.Id,
                Received_Quantity__c = wrapper.ReceivedQuantity,
                GRN_Comment__c = wrapper.Comment,
               Good_receipt_note__c = grn.id
            ));
        }
        
        update toUpdate;
        
        
       
    }
    
    public class InvoiceLineWrapper {
        @AuraEnabled public Id Id;
        @AuraEnabled public Id ProductId;
        @AuraEnabled public String ProductName;
        @AuraEnabled public String ProductImageURL;
        @AuraEnabled public Decimal OrderQuantity;
        @AuraEnabled public Decimal PreviousConfirmedQuantity;
        @AuraEnabled public Decimal CurrentInvoiceQuantity;
        @AuraEnabled public Decimal ReceivedQuantity;
        @AuraEnabled public String Comment;
    }
}