public with sharing class ReturnsInvoiceVFController {
    public Order__c order { get; set; }
    public Invoice__c invoice { get; set; }
    public Returns__c returnRecord { get; set; }
    public List<Return_Line_Item__c> orderItems { get; set; }
    public Decimal subtotal { get; set; }
    public Decimal cgst { get; set; }
    public Decimal sgst { get; set; }
    public Decimal igst { get; set; }
    public Decimal cgstPercent { get; set; }
    public Decimal sgstPercent { get; set; }
    public Decimal igstPercent { get; set; }
    public Decimal total { get; set; }
    public Integer totalQuantity { get; set; }
    public String amountInWords { get; set; }
     public String Salesperson { get; set; }

    public ReturnsInvoiceVFController() {
        Id recordId = ApexPages.currentPage().getParameters().get('recordId');
        system.debug('recordId- '+recordId);
        Salesperson = UserInfo.getName();
    
        // Fetch the return record
        returnRecord = [
            SELECT 
                Name,
                CreatedDate,
                Order__c,
                Invoice__r.Invoice_Date__c, 
                Invoice__r.Beat__c,
                Invoice__r.Invoice_Number__c, 
                Invoice__r.Retailer_Account__c,
                Invoice__r.Distributor_Account__r.Code__c,
                Invoice__r.Distributor_Account__c,
                Invoice__r.Invoice_Amount_In_Words__c,
                Invoice__r.SGST_Amount__c,
                Invoice__r.IGST_Amount__c,
                Invoice__r.CGST_Amount__c,
                Invoice__r.Under_SS__r.Name
            FROM Returns__c 
            WHERE Id = :recordId
            LIMIT 1
        ]; 
    
        String filename = returnRecord.Name + '_returns_invoice.PDF';
        ApexPages.currentPage().getHeaders().put('Content-Disposition', 'attachment; filename="' + filename + '"');
    
        // Fetch the order and invoice
        order = [SELECT Id, Name, AccountId__r.Name, AccountId__r.Phone, AccountId__r.Email__c,
                        Account__r.Name, Account__r.Phone, Account__r.Email__c , EffectiveDate__c , Ordered_By__r.Name
                 FROM Order__c
                 WHERE Id = :returnRecord.Order__c];
    
        invoice = [SELECT Id, Invoice_Date__c, Retailer_Account__r.Email__c, Retailer_Account__r.GSTIN__c,
                          Under_SS__r.GSTIN__c, Under_SS__r.Email__c, Under_SS__r.Owners_Number__c,
                          Distributor_Account__r.Owners_Number__c, Distributor_Account__r.GSTIN__c,
                          Under_SS__r.Name, SGST_Amount__c, IGST_Amount__c, CGST_Amount__c,
                          Invoice_Number__c, Retailer_Account__c, Retailer_Account__r.Name,
                          Retailer_Account__r.Owners_Number__c, Retailer_Account__r.Outlet_Email__c,
                          Distributor_Account__r.Code__c, Distributor_Account__r.Name, Distributor_Account__r.Phone,
                          Distributor_Account__r.Email__c, Beat__c,
                          CGST__c, SGST__c, IGST__c  // ✅ Added tax % fields from Invoice
                   FROM Invoice__c
                   WHERE Id = :returnRecord.Invoice__c];
    
        // Fetch return line items
        orderItems = [
            SELECT 
                Id, 
                Product__c, 
                Total_returns__c, 
                Return_Amount__c, 
                Product__r.Name,
                Unit_Price__c,
                Product__r.Unit_of_Measure__c 
            FROM Return_Line_Item__c 
            WHERE Return__c = :recordId
        ];
    
        // Calculate subtotal and totalQuantity
        totalQuantity = 0;
        subtotal = 0;
        for (Return_Line_Item__c item : orderItems) {
            totalQuantity += (item.Total_returns__c != null) ? Integer.valueOf(item.Total_returns__c) : 0;
            subtotal += (item.Return_Amount__c != null) ? item.Return_Amount__c : 0;
        }
    
        //Tax calculation directly from Invoice values
        cgstPercent = invoice.CGST__c != null ? invoice.CGST__c : 0;
        sgstPercent = invoice.SGST__c != null ? invoice.SGST__c : 0;
        igstPercent = invoice.IGST__c != null ? invoice.IGST__c : 0;
    
        if ((invoice.CGST__c != null && invoice.CGST__c > 0) && 
            (invoice.SGST__c != null && invoice.SGST__c > 0)) {
            cgst = (subtotal * cgstPercent) / 100;
            sgst = (subtotal * sgstPercent) / 100;
            total = subtotal + cgst + sgst;
        } else if (invoice.IGST__c != null && invoice.IGST__c > 0) {
            igst = (subtotal * igstPercent) / 100;
            total = subtotal + igst;
        } else {
            total = subtotal;
        }
    
        amountInWords = NumberToWordsUtility.numberToWordsInINR(total);
    }


    // Utility method to convert amount to words
    private String convertToWords(Decimal amount) {
        // Simplified 
        return 'cool';
        //return (new EnglishNumberToWords().convert(amount.round()));
    }
}