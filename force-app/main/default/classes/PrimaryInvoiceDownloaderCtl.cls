//created by fuzail 
public class PrimaryInvoiceDownloaderCtl {

    public Id invoiceId { get; set; }
    public User dmsUserInfo { get; set; }
    public List<InvoiceWrapper> invoiceWrappers { get; set; }
    public Decimal discountPercent { get; set; }
    public Decimal totalInvoiceAmount { get; set; }
    public Decimal roundOff { get; set; }
    
    public String companyName {
        get {
            if (invoiceWrappers != null && !invoiceWrappers.isEmpty()) {
                return invoiceWrappers[0].invoice.Seller_Name__c;
            }
            return '';
        }
    }
    public String sellerGstin {
        get {
            if (invoiceWrappers != null && !invoiceWrappers.isEmpty()) {
                return invoiceWrappers[0].invoice.Seller_GSTIN__c;
            }
            return '';
        }
    }

    public PrimaryInvoiceDownloaderCtl() {

        invoiceId = ApexPages.currentPage().getParameters().get('id');
        invoiceWrappers = new List<InvoiceWrapper>();

        Id userId = UserInfo.getUserId();
        User loggedInUser = [
            SELECT Id, AccountId
            FROM User
            WHERE Id = :userId
        ];

        Decimal totalDiscount = 0;

        if (invoiceId != null) {

            List<Invoice__c> invoices = [
                SELECT Id, Name, Invoice_Number__c, Status__c, Invoice_Date__c,
                       Distributor_Account__c, Beat__c,Sub_Total__c,Order__r.Ordered_By__r.MobilePhone,
                       Distributor_Account__r.Id,
                       Distributor_Account__r.Name,
                       Distributor_Account__r.ShippingStreet,
                       Distributor_Account__r.ShippingCity,
                       Distributor_Account__r.ShippingState,
                       Distributor_Account__r.ShippingPostalCode,
                       Distributor_Account__r.ShippingCountry,
                       Distributor_Account__r.BillingStreet,
                       Distributor_Account__r.BillingCity,
                       Distributor_Account__r.BillingState,
                       Distributor_Account__r.BillingPostalCode,
                       Distributor_Account__r.BillingCountry,
                       Distributor_Account__r.Owners_Number__c,
                       Distributor_Account__r.GSTIN__c,
                       Distributor_Account__r.FSSAI__c,
                       Distributor_Account__r.Beats_Name__r.Name,
                       Retailer_Account__r.Beats_Name__r.Name,
                       Order__r.Ordered_By__r.Name,
                       Retailer_Account__r.Name,
                       Retailer_Account__r.Phone,
                       Retailer_Account__r.Primary_Address_1__c,
                       Retailer_Account__r.GSTIN__c,
                       Retailer_Account__r.FSSAI__c,
                       Credit_Period__c,
                       Retailer_Account__r.Ship_To_Address_1__c,
                       Total_Quantity__c,
                       Invoice_Amount__c,
                       Total_GST__c,
                       TCS_Amount__c,
                       Invoice_Amount_In_Words__c,
                       Taxable_Amount__c,
                       SGST__c, SGST_Amount__c,
                       CGST__c, CGST_Amount__c,
                       IGST__c, IGST_Amount__c,
                       Total_Discount1__c,
                       Total_Discount_2__c,
                       Total_Discount__c,
                       Total_Discount_Percent__c,
                       Discount_2__c,
                       Discount__c,
                       Seller_Name__c,
                       Seller_GSTIN__c,
                       RecordType.DeveloperName
                FROM Invoice__c
                WHERE Id = :invoiceId
                AND RecordType.DeveloperName = 'Primary_Invoice'
            ];

            for (Invoice__c inv : invoices) {

                List<Invoice_Line_Item__c> lineItems = [
                    SELECT Price__c, Product__c, Quantity__c, Total_Amount__c,
                           Product__r.Name, MRP__c,
                           Discount__c,
                           Total_Discount__c, Amount_Excl_Tax__c , Total_Amount_Incl_Tax__c , 
                           CGST_Amount__c, SGST_Amount__c,
                           IGST_Amount__c, Tax__c , Total_Tax__c
                    FROM Invoice_Line_Item__c
                    WHERE Invoice__c = :inv.Id
                ];
                //added by fuzail to check debug logs
                System.debug('=== LINE ITEMS DEBUG ===');
for (Invoice_Line_Item__c li : lineItems) {
    System.debug('Line Item ID: ' + li.Id);
    System.debug('Product: ' + li.Product__r.Name);
    System.debug('Discount__c: ' + li.Discount__c);
    System.debug('Total_Discount__c: ' + li.Total_Discount__c);
}
System.debug('=== END DEBUG ===');

                dmsUserInfo = [
                    SELECT Id, Name, CompanyName, Phone, MobilePhone, Email,
                           FullPhotoUrl, SmallPhotoUrl, MediumPhotoUrl,
                           GSTIN__c, PAN_Number__c,
                           Invoice_Number_Prefix__c, Invoice_Start_Number__c,
                           State, Notes__c, Terms_and_Conditions__c,
                           Contact.AccountId, Contact.Account.Name,
                           UPI_ID__c, UPI_QR_CODE__c,
                           Bank_Name__c, Bank_Account_Number__c,
                           IFSC_Code__c,
                           Contact.Account.BillingStreet,
                           Contact.Account.BillingCity,
                           Contact.Account.BillingState,
                           Contact.Account.BillingPostalCode,
                           Contact.Account.BillingCountry,
                           Contact.Account.Phone_1__c,
                           Contact.Account.FSSAI__c
                    FROM User
                    WHERE AccountId = :loggedInUser.AccountId
                    AND Primary_Distributor__c = true
                    LIMIT 1
                ];

                invoiceWrappers.add(new InvoiceWrapper(inv, lineItems));

                if (inv.Discount__c != null && inv.Discount__c > 0) {
                    totalDiscount = inv.Discount__c;
                }

                Decimal taxableAmount = inv.Taxable_Amount__c != null ? inv.Taxable_Amount__c : 0;
                Decimal totalSubTotal = inv.Sub_Total__c != null ? inv.Sub_Total__c : 0;
                Decimal beforeRoundOff = taxableAmount + totalSubTotal;

                if (beforeRoundOff > 0) {
                    totalInvoiceAmount = Math.round(beforeRoundOff);
                    roundOff = totalInvoiceAmount - beforeRoundOff;
                } else {
                    totalInvoiceAmount = 0;
                    roundOff = 0;
                }
            }

            Decimal totalAmount = 0;
            for (Invoice_Line_Item__c li :
                [SELECT Total_Amount__c FROM Invoice_Line_Item__c WHERE Invoice__c = :invoiceId AND Total_Amount__c !=null]
            ) {
                totalAmount += li.Total_Amount__c;
            }

            if (totalAmount > 0 && totalDiscount > 0) {
                discountPercent = (totalDiscount / totalAmount) * 100;
            } else {
                discountPercent = 0;
            }

            if (!invoices.isEmpty()) {
                String filename = invoices[0].Invoice_Number__c + '.PDF';
                ApexPages.currentPage().getHeaders()
                    .put('Content-Disposition', 'attachment; filename="' + filename + '"');
            }
        }
    }

    public class InvoiceWrapper {
        public Invoice__c invoice { get; set; }
        public List<Invoice_Line_Item__c> invoiceLineItems { get; set; }

        public InvoiceWrapper(Invoice__c invoice, List<Invoice_Line_Item__c> lineItems) {
            this.invoice = invoice;
            this.invoiceLineItems = lineItems;
        }
    }
}