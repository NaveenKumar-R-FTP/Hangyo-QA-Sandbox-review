/**
* @File Name : ReturnProcessorController .cls
* @Description :
* @Author :
* @Last Modified By :
* @Last Modified On : January 7, 2025
* @Modification Log :
*==============================================================================
* Ver | Date | Author | Modification
*==============================================================================
* 1.0 | January 7, 2025 |   | Initial Version
**/

public without sharing class ReturnProcessorController {

    //fetch the invoice line items from the invoice
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getInvoiceLineItems(Id invoiceId) {
        Map<String, Object> response = new Map<String, Object>();
        System.debug('Fetching invoice line items for invoiceId: ' + invoiceId);
    
        try {
            // Check if a return record already exists for this invoice
            Integer existingReturnsCount = [
                SELECT COUNT() 
                FROM Returns__c 
                WHERE Invoice__c = :invoiceId
            ];
            if (existingReturnsCount > 0 && invoiceId != null) {
                throw new AuraHandledException('Returns already exist for this invoice.');
            }
    
            // Query the Invoice and its related Invoice Line Items
            Invoice__c invoice = [
                SELECT Id, Name, Invoice_Amount__c, RecordType.DeveloperName, Status__c, CreatedDate, 
                       Total_Quantity__c, Taxable_Amount__c, Order__c, Invoice_Number__c,
                       CGST__c, SGST__c, IGST__c,
                       (SELECT Id, Product__c, Product__r.Name, Quantity__c, Price__c, Total_Amount__c 
                        FROM Invoice_Line_Items__r)
                FROM Invoice__c
                WHERE Id = :invoiceId
            ];
    
            if (invoice.Status__c != 'Delivered') {
                throw new AuraHandledException('Invoice not delivered');
            }
            if (invoice.RecordType.DeveloperName == 'Primary_Invoice') {
                throw new AuraHandledException('Returns not allowed for primary invoices');
            }
    
            // Build line items wrapper list
            List<InvoiceLineItemWrapper> lineItems = new List<InvoiceLineItemWrapper>();
            for (Invoice_Line_Item__c lineItem : invoice.Invoice_Line_Items__r) {
                lineItems.add(new InvoiceLineItemWrapper(
                    lineItem.Id, 
                    lineItem.Product__r.Name, 
                    lineItem.Quantity__c, 
                    0, // Default Damage
                    0, // Default Reuse
                    0, // Default Return Amount
                    lineItem.Product__c,
                    lineItem.Price__c.setScale(2) 
                ));
            }
    
            // ✅ Just send invoice and line items
            response.put('invoice', invoice);
            response.put('lineItems', lineItems);
    
            System.debug('Response: ' + response);
            return response;
    
        } catch (AuraHandledException e) {
            throw e; 
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching invoice or line items: ' + e.getMessage());
        }
    }

    //creates a returns,credit note record
	@AuraEnabled
    public static void saveReturns(Id invoiceId, Decimal totalQuantity, Decimal totalAmount, Decimal cgst, Decimal sgst, Decimal igst , String jsonlineItems) {
        try {
            // Check again for existing returns to prevent concurrent creation
            Integer existingReturnsCount = [SELECT COUNT() FROM Returns__c WHERE Invoice__c = :invoiceId];
            if (existingReturnsCount > 0 && invoiceId != null ) {
                throw new AuraHandledException('Returns already exist for this invoice.');
            }
            List<Returns__c> returnsToInsert = new List<Returns__c>();
            List<Return_Line_item__c> returnLineItemsToInsert = new List<Return_Line_item__c>();
            List<InvoiceLineItemWrapper> lineItems = new List<InvoiceLineItemWrapper>();
             
            Invoice__c invoice = [
                SELECT Id, Name,RecordType.DeveloperName,Under_SS__c, Invoice_Amount__c, Status__c,Retailer_Account__c, CreatedDate, Total_Quantity__c,Taxable_Amount__c,Order__c FROM Invoice__c
                WHERE Id = :invoiceId
            ];
    
            // Create the main return record
            Returns__c returnRecord = new Returns__c();
            returnRecord.Invoice__c = invoiceId;
            returnRecord.Total_Return_Quantity__c = totalQuantity;
            returnRecord.Return_Amount__c = totalAmount;
            returnRecord.CGST__c = cgst;
            returnRecord.SGST__c = sgst;
            returnRecord.IGST__c = igst;
            returnRecord.Order__c= invoice.Order__c;
    
            insert returnRecord; // Insert the return record first
            system.debug('jsonlineItems  '+jsonlineItems);
            // Create return line items
             try {
                lineItems = (List<InvoiceLineItemWrapper>) JSON.deserialize(jsonlineItems, List<InvoiceLineItemWrapper>.class);
            } catch (Exception e) {
                System.debug('Error deserializing JSON: ' + e.getMessage());
                throw new AuraHandledException('Failed to process line items.');
            }
           for (InvoiceLineItemWrapper lineItem : lineItems) {
                if (lineItem.damage > 0 || lineItem.reuse > 0) { // Only store relevant records
                    Return_Line_item__c returnLineItem = new Return_Line_item__c();
                    returnLineItem.Return__c = returnRecord.Id; // Associate with the return
                    returnLineItem.Product__c = lineItem.prodId;
                    returnLineItem.Damage_Count__c = lineItem.damage;
                    returnLineItem.Unit_Price__c = lineItem.unitPrice;
                    returnLineItem.Reuse_Count__c = lineItem.reuse;
                    returnLineItem.Total_returns__c = lineItem.damage + lineItem.reuse;
                    returnLineItem.Return_Amount__c = lineItem.returnAmount;
    
                    returnLineItemsToInsert.add(returnLineItem);
                }
            }
            
    
            if (!returnLineItemsToInsert.isEmpty()) {
                insert returnLineItemsToInsert;
            }
              // Create and save the Credit Note record
            Credit_Note__c creditNote = new Credit_Note__c();
            if (invoice.RecordType.DeveloperName == 'Secondary_Invoice') {
                creditNote.Retailer__c = invoice.Under_SS__c;
            } else {
                creditNote.Retailer__c = invoice.Retailer_Account__c;
            }
                     if (invoice.RecordType.DeveloperName == 'Secondary_Invoice_Under_SS') {
                creditNote.Retailer__c = invoice.Under_SS__c;
            } else {
                creditNote.Retailer__c = invoice.Retailer_Account__c;
            }
            creditNote.Invoice__c = invoiceId; // Associate with the invoice
            creditNote.Total_Returns_Qty__c = totalQuantity; // Set the total return quantity
            creditNote.Total_Credit_Amount__c = totalAmount; // Set the total credit amount
            creditNote.CGST__c = cgst;
            creditNote.SGST__c = sgst;
            creditNote.IGST__c = igst;
            creditNote.Returns__c = returnRecord.Id;
            
            insert creditNote; // Insert the credit note
        }
        catch (AuraHandledException e) {
            throw e; // Rethrow handled exception
        } 
        catch (Exception e) {
            throw new AuraHandledException('Error saving returns: ' + e.getMessage());
        }
    }


 // Wrapper class for returning structured data to LWC
public class InvoiceLineItemWrapper {
    @AuraEnabled public Id lineItemId;
    @AuraEnabled public String productName; // Or String, depending on your schema
    @AuraEnabled public Decimal quantity;
    @AuraEnabled public Integer damage;
    @AuraEnabled public Integer reuse;
     @AuraEnabled public Id prodId;
    @AuraEnabled public Decimal returnAmount;
   
    @AuraEnabled public Decimal unitPrice;
   // [{"lineItemId":"a0IH1000002MHqqMAG","productName":"Hangyo test 2","quantity":15,"damage":0,"reuse":1,"returnAmount":100,"unitPrice":100},{"lineItemId":"a0IH1000002MHqvMAG","productName":"Hangyo test 2","quantity":20,"damage":1,"reuse":2,"returnAmount":210,"unitPrice":70}
 public InvoiceLineItemWrapper() {}
    // Correct Constructor
    public InvoiceLineItemWrapper(
        Id lineItemId,
        String productName, // Change to String if `Product__c` is not an Id
        Decimal quantity,
        Integer damage,
        Integer reuse,
        Decimal returnAmount,
        Id prodId,
        Decimal unitPrice
    ) {
        this.lineItemId = lineItemId;
        this.productName = productName;
        this.quantity = quantity;
        this.damage = damage;
        this.reuse = reuse;
        this.returnAmount = returnAmount;
        this.prodId = prodId;
        this.unitPrice = unitPrice;
    }
}


}