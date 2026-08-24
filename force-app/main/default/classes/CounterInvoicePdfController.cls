public without sharing class CounterInvoicePdfController {

    public Id invoiceId { get; set; }
    public User dmsUserInfo { get; set; }
    public List<InvoiceWrapper> invoiceWrappers { get; set; }
    public Decimal discountPercent { get; set; }
    public Decimal totalInvoiceAmount { get; set; }
    public Decimal roundOff { get; set; }
    public String freeOfferMessage { get; set; }

    public CounterInvoicePdfController() {
        invoiceId     = ApexPages.currentPage().getParameters().get('id');
        invoiceWrappers = new List<InvoiceWrapper>();

        if (invoiceId == null) return;

        User loggedInUser = [SELECT Id, AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        List<Invoice__c> invoices = [
            SELECT Id, Name, Invoice_Number__c, Status__c, Invoice_Date__c,
                   Distributor_Account__c, Distributor_Account__r.FSSAI__c,
                   Credit_Period__c,
                   Total_Quantity__c, Invoice_Amount__c, Total_GST__c,
                   Invoice_Amount_In_Words__c, Taxable_Amount__c,
                   SGST__c, SGST_Amount__c, CGST__c, CGST_Amount__c,
                   IGST__c, IGST_Amount__c,
                   Total_Discount1__c, Total_Discount_2__c,
                   Total_Discount__c, Total_Discount_Percent__c,
                   Value_Scheme_Discount__c,
                   // Order fields for counter invoice customer info
                   Order__c,
                   Order__r.Customer_Name__c,
                   Order__r.Customer_Phone__c,
                   Order__r.Customer_Address__c,
                   Order__r.GSTIN__c,
                   Order__r.Company__c,
                   Order__r.State__c,
                   Order__r.Description__c,
                   Order__r.Sale_Type__c,
                   Order__r.Price_Type__c,
                   Order__r.Ordered_By__r.Name,
                   Order__r.Ordered_By__r.MobilePhone
            FROM Invoice__c
            WHERE Id = :invoiceId
        ];

        Decimal totalDiscount = 0;

        for (Invoice__c inv : invoices) {
            List<Invoice_Line_Item__c> lineItems = [
                SELECT Price__c, Product__c, Quantity__c, Total_Amount__c,
                       Product__r.Name, Product__r.Product_Code__c, Product__r.Category_Code__c,
                       Product__r.Per_Pieces__c,
                       MRP__c, Discount_1__c, Discount_2__c,
                       CGST_Amount__c, IGST_Amount__c, SGST_Amount__c,
                       Total_Tax__c, Tax__c
                FROM Invoice_Line_Item__c
                WHERE Invoice__c = :inv.Id
            ];

            // Modern Trade free-goods scheme — bold message shown next to CGST on the PDF.
            freeOfferMessage = ModernTradeSchemeService.getFreeOfferMessage(lineItems);

            // Fetch DMS user info from distributor account
            dmsUserInfo = [
                SELECT Id, Name, CompanyName, Phone, MobilePhone, Email,
                       MediumPhotoUrl, GSTIN__c, PAN_Number__c, State, Notes__c,
                       Terms_and_Conditions__c, UPI_ID__c, UPI_QR_CODE__c,
                       Bank_Name__c, Bank_Account_Number__c, IFSC_Code__c,
                       Contact.Account.Name,
                       Contact.Account.BillingStreet, Contact.Account.BillingCity,
                       Contact.Account.BillingState, Contact.Account.BillingPostalCode,
                       Contact.Account.BillingCountry, Contact.Account.Phone_1__c,
                       Contact.Account.FSSAI__c
                FROM User
                WHERE AccountId = :inv.Distributor_Account__c
                AND Primary_Distributor__c = true
                LIMIT 1
            ];

            invoiceWrappers.add(new InvoiceWrapper(inv, lineItems));

            if (inv.Total_Discount__c != null && inv.Total_Discount__c > 0) {
                totalDiscount = inv.Total_Discount__c;
            }

            // Calculate round off
            Decimal taxableAmount  = inv.Taxable_Amount__c != null ? inv.Taxable_Amount__c : 0;
            Decimal totalGST       = inv.Total_GST__c != null ? inv.Total_GST__c : 0;
            Decimal beforeRoundOff = taxableAmount + totalGST;

            if (beforeRoundOff > 0) {
                totalInvoiceAmount = Math.round(beforeRoundOff);
                roundOff           = totalInvoiceAmount - beforeRoundOff;
            } else if (inv.Invoice_Amount__c != null && inv.Invoice_Amount__c > 0) {
                totalInvoiceAmount = Math.round(inv.Invoice_Amount__c);
                roundOff           = totalInvoiceAmount - inv.Invoice_Amount__c;
            } else {
                totalInvoiceAmount = 0;
                roundOff           = 0;
            }
        }

        // Calculate discount percent
        Decimal totalAmount = 0;
        for (Invoice_Line_Item__c li : [
            SELECT Total_Amount__c FROM Invoice_Line_Item__c WHERE Invoice__c = :invoiceId
        ]) {
            totalAmount += li.Total_Amount__c != null ? li.Total_Amount__c : 0;
        }
        discountPercent = (totalAmount > 0 && totalDiscount > 0)
                          ? (totalDiscount / totalAmount) * 100 : 0;

        // Set PDF filename
        if (!invoices.isEmpty()) {
            String filename = invoices[0].Invoice_Number__c + '.PDF';
            ApexPages.currentPage().getHeaders().put('Content-Disposition', 'inline; filename="' + filename + '"');
        }
    }

    public class InvoiceWrapper {
        public Invoice__c invoice { get; set; }
        public List<LineItemDisplay> invoiceLineItems { get; set; }

        // Sum of displayBasicAmt / displayDiscount across all line items — computed here
        // instead of via a VF apex:variable accumulator loop, for the same reason as
        // extractionFactor below (plain Apex, no page-side formula surface).
        public Decimal totalBasicAmt { get; set; }
        public Decimal totalDiscountDisplay { get; set; }

        // For Counter Invoice + MRP with a non-zero GST rate, this is 1 + rate% —
        // dividing Rate/Basic Amt/Discount by it extracts the tax-exclusive value.
        // For everything else it's 1, so Rate/Basic Amt/Discount are unchanged from today.
        public Decimal extractionFactor { get; private set; }

        public InvoiceWrapper(Invoice__c invoice, List<Invoice_Line_Item__c> lineItems) {
            this.invoice = invoice;

            Decimal totalRatePercent = (invoice.CGST__c != null ? invoice.CGST__c : 0)
                                     + (invoice.SGST__c != null ? invoice.SGST__c : 0)
                                     + (invoice.IGST__c != null ? invoice.IGST__c : 0);
            Boolean isMrpCounter = invoice.Order__r != null
                                 && invoice.Order__r.Price_Type__c == 'MRP'
                                 && totalRatePercent > 0;
            this.extractionFactor = isMrpCounter ? (1 + (totalRatePercent / 100)) : 1;

            this.invoiceLineItems     = new List<LineItemDisplay>();
            this.totalBasicAmt        = 0;
            this.totalDiscountDisplay = 0;

            for (Invoice_Line_Item__c li : lineItems) {
                LineItemDisplay display = new LineItemDisplay(li, this.extractionFactor);
                this.invoiceLineItems.add(display);
                this.totalBasicAmt        += display.displayBasicAmt;
                this.totalDiscountDisplay += display.displayDiscount;
            }
            this.totalBasicAmt        = this.totalBasicAmt.setScale(2, RoundingMode.HALF_UP);
            this.totalDiscountDisplay = this.totalDiscountDisplay.setScale(2, RoundingMode.HALF_UP);
        }
    }

    // Wraps a single Invoice_Line_Item__c with pre-computed, tax-extracted display values.
    // Basic Amt, Rate, and Discount are each independently divided by the same
    // extractionFactor (1 for everything except Counter Invoice + MRP), so that
    // displayBasicAmt − displayDiscount reconstructs exactly to Tax__c (the taxable base
    // InvoiceLineItemTrigger already computed). Doing this math here instead of as VF
    // apex:variable formulas avoids the page-compile issue that was blocking deploy.
    public class LineItemDisplay {
        public Invoice_Line_Item__c rec { get; set; }
        public Decimal displayRate { get; set; }
        public Decimal displayBasicAmt { get; set; }
        public Decimal displayDiscount { get; set; }
        public Decimal lineNetAmt { get; set; }

        public LineItemDisplay(Invoice_Line_Item__c li, Decimal extractionFactor) {
            this.rec = li;

            Decimal factor        = extractionFactor != null && extractionFactor != 0 ? extractionFactor : 1;
            Decimal price         = li.Price__c != null ? li.Price__c : 0;
            Decimal totalAmount   = li.Total_Amount__c != null ? li.Total_Amount__c : 0;
            Decimal discount1     = li.Discount_1__c != null ? li.Discount_1__c : 0;
            Decimal discount2     = li.Discount_2__c != null ? li.Discount_2__c : 0;
            Decimal tax           = li.Tax__c != null ? li.Tax__c : 0;
            Decimal cgstAmt       = li.CGST_Amount__c != null ? li.CGST_Amount__c : 0;
            Decimal sgstAmt       = li.SGST_Amount__c != null ? li.SGST_Amount__c : 0;
            Decimal igstAmt       = li.IGST_Amount__c != null ? li.IGST_Amount__c : 0;

            this.displayRate     = (price / factor).setScale(2, RoundingMode.HALF_UP);
            this.displayBasicAmt = (totalAmount / factor).setScale(2, RoundingMode.HALF_UP);
            this.displayDiscount = ((discount1 + discount2) / factor).setScale(2, RoundingMode.HALF_UP);
            this.lineNetAmt      = (tax + cgstAmt + sgstAmt + igstAmt).setScale(2, RoundingMode.HALF_UP);
        }
    }
}