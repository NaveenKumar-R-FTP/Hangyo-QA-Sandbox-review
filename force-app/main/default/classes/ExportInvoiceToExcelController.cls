public class ExportInvoiceToExcelController {
    
    public Id invoiceId { get; set; }
    public List<Invoice__c> invoices { get; set; }
    public List<Invoice_Line_Item__c> invoiceLineItems { get; set; }
    public String retailerName { get; set; }
    
    public ExportInvoiceToExcelController(){
        invoiceId = ApexPages.currentPage().getParameters().get('Id');
        System.debug('invoiceId=> ' + invoiceId);
        if(invoiceId != null){
            invoices = [SELECT Id, Invoice_Number__c , Invoice_Date__c , Retailer_Account__r.Name, Under_SS__r.Name , Invoice_Amount__c , Total_Quantity__c FROM Invoice__c WHERE Id =: invoiceId LIMIT 1];
            if(invoices[0].Retailer_Account__r.Name != null){
                retailerName = invoices[0].Retailer_Account__r.Name;
            }else{
                retailerName = invoices[0].Under_SS__r.Name;
            }
            invoiceLineItems = [SELECT Id,Name, Product__r.Name, Price__c , Quantity__c, Total_Amount__c FROM Invoice_Line_Item__c WHERE Invoice__c = :invoiceId];
        }
        // Dynamically set the filename based on the order's name
        String filename = invoices[0].Invoice_Number__c + '_InvoiceDetails.xls';
        ApexPages.currentPage().getHeaders().put('Content-Disposition', 'attachment; filename="' + filename + '"');
    }
}