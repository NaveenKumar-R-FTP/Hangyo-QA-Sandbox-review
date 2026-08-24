public class DeliveryPlanInvoiceController {

    public Id deliveryPlanId { get; set; } 
    public User dmsUserInfo { get; set; }
    public List<InvoiceWrapper> invoiceWrappers { get; set; }

    public DeliveryPlanInvoiceController() {

        deliveryPlanId = ApexPages.currentPage().getParameters().get('id');
        invoiceWrappers = new List<InvoiceWrapper>();
        Id userId = UserInfo.getUserId();

        User loggedInUser = [
            SELECT Id, AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
        
        System.debug('loggedInUser.AccountId:- ' + loggedInUser.AccountId);

        /*if (loggedInUser.AccountId == null) {
            System.debug('No AccountId found for the logged-in user.');
            return;
        }*/

        // Primary distributor for logged-in user
        dmsUserInfo = [
            SELECT Id, Name, CompanyName, Phone, MobilePhone, Email,
                   FullPhotoUrl, SmallPhotoUrl, MediumPhotoUrl,
                   GSTIN__c, PAN_Number__c, Invoice_Number_Prefix__c,
                   Invoice_Start_Number__c, State, Notes__c,
                   Terms_and_Conditions__c,
                   Contact.AccountId, Contact.Account.Name,
                   UPI_ID__c, UPI_QR_CODE__c,
                   Bank_Name__c, Bank_Account_Number__c, IFSC_Code__c,
                   Contact.Account.BillingStreet,
                   Contact.Account.BillingCity,
                   Contact.Account.BillingState,
                   Contact.Account.BillingPostalCode,
                   Contact.Account.BillingCountry,
                   Contact.Account.Phone_1__c
            FROM User
            WHERE AccountId = :loggedInUser.AccountId
              AND Primary_Distributor__c = true
            LIMIT 1
        ];

        if (deliveryPlanId == null) return;

        Set<Id> invoiceIds = new Set<Id>();
        String filename = '';

        for (Delivery_Plan_Items__c dpi : [
            SELECT Invoices__c, Delivery_Plan__r.Name
            FROM Delivery_Plan_Items__c
            WHERE Delivery_Plan__c = :deliveryPlanId
        ]) {
            filename = dpi.Delivery_Plan__r.Name + '.PDF';
            if (dpi.Invoices__c != null) {
                invoiceIds.add(dpi.Invoices__c);
            }
        }

        if (invoiceIds.isEmpty()) return;

        List<Invoice__c> invoices = [
            SELECT Id, Invoice_Number__c, Invoice_Date__c,
                   Credit_Period__c,
                   Retailer_Account__r.Name,
                   Retailer_Account__r.BillingStreet,
                   Retailer_Account__r.BillingCity,
                   Retailer_Account__r.BillingState,
                   Retailer_Account__r.BillingPostalCode,
                   Retailer_Account__r.BillingCountry,
                   Retailer_Account__r.GSTIN__c,
                   Retailer_Account__r.FSSAI__c,
                   Retailer_Account__r.Retailer_Code__c,
                   Retailer_Account__r.Owners_Number__c,
                   Retailer_Account__r.Beats_Name__r.Name,
                   Order__r.Ordered_By__r.Name,
                   Order__r.Ordered_By__r.MobilePhone,
                   Under_SS__r.Name,
                   Under_SS__r.BillingStreet,
                   Under_SS__r.BillingCity,
                   Under_SS__r.BillingState,
                   Under_SS__r.BillingPostalCode,
                   Under_SS__r.BillingCountry,
                   Under_SS__r.GSTIN__c,
                   Under_SS__r.FSSAI__c,
                   Under_SS__r.Owners_Number__c,
                   Distributor_Account__c,Distributor_Account__r.FSSAI__c,
                   Total_Quantity__c,
                   Invoice_Amount__c,
                   Invoice_Amount_In_Words__c,
                   Taxable_Amount__c,
                   Total_GST__c,
                   CGST__c, CGST_Amount__c,
                   SGST__c, SGST_Amount__c,
                   IGST__c, IGST_Amount__c,
                   Total_Discount1__c,
                   Total_Discount_2__c,
                   Total_Discount__c,
                   Total_Discount_Percent__c,
                Value_Scheme_Applied__c,
                   Value_Scheme_Applied__r.Name,
                   Value_Scheme_Discount__c,
                   Remarks__c,
                   Total_Reimbursement_Applied__c,
                   Net_Payable__c
            FROM Invoice__c
            WHERE Id IN :invoiceIds
        ];

        for (Invoice__c inv : invoices) {

            // Invoice line items
                        List<Invoice_Line_Item__c> lineItems = [
                SELECT Price__c, Product__c, Product__r.Name,
                       Product__r.Product_Code__c, Product__r.Category_Code__c, Product__r.Per_Pieces__c,
                       Quantity__c, Total_Amount__c,
                       MRP__c, Discount_1__c, Discount_2__c, Scheme_Discount_Amount__c,
                       Total_Discount__c,
                       CGST_Amount__c, SGST_Amount__c, IGST_Amount__c,
                       Tax__c, Is_Promotional__c,Total_Tax__c,
                       Quantity_Scheme_Applied__c, Quantity_Scheme_Applied__r.Name,
                       Quantity_Scheme_Applied__r.Discount_Percentage__c, Quantity_Scheme_Applied__r.Type__c,
                       Parent_Product__c
                FROM Invoice_Line_Item__c
                WHERE Invoice__c = :inv.Id
            ];

            // Modern Trade free-goods scheme — bold message shown next to CGST.
            // Per-wrapper (not a single controller-level property) since a Delivery Plan
            // bundles multiple invoices on one PDF, each needing its own message.
            String freeOfferMessage = ModernTradeSchemeService.getFreeOfferMessage(lineItems);

            // Purchase Quantity Discount scheme(s) applied — same reasoning, per-wrapper.
            List<AppliedSchemeDisplay> appliedQuantityDiscountSchemes =
                SchemeEvaluationService.getAppliedQuantityDiscountSchemes(lineItems);

            // Separate top-level query, not a subquery — avoids the exact
            // readOnly + relationship-subquery issue we hit this morning
            // on the main Secondary Invoice PDF, in case this page is ever
            // rendered via a getContent()-based wrapper in the future.
            List<Invoice_Reimbursement_Line__c> reimbursementLines = [
                SELECT Amount_Applied__c, Retailer_Reimbursement_Scheme__r.Scheme_Definition__r.Name
                FROM Invoice_Reimbursement_Line__c
                WHERE Invoice__c = :inv.Id
            ];

            // Switch distributor if Under SS invoice
            if (inv.Under_SS__c != null) {
                dmsUserInfo = [
                    SELECT Id, Name, CompanyName, Phone, MobilePhone, Email,
                           FullPhotoUrl, SmallPhotoUrl, MediumPhotoUrl,
                           GSTIN__c, PAN_Number__c,
                           State, Notes__c, Terms_and_Conditions__c,
                           Contact.AccountId, Contact.Account.Name,
                           UPI_ID__c, UPI_QR_CODE__c,
                           Bank_Name__c, Bank_Account_Number__c, IFSC_Code__c,
                           Contact.Account.BillingStreet,
                           Contact.Account.BillingCity,
                           Contact.Account.BillingState,
                           Contact.Account.BillingPostalCode,
                           Contact.Account.BillingCountry,
                           Contact.Account.Phone_1__c
                    FROM User
                    WHERE AccountId = :inv.Distributor_Account__c
                      AND Primary_Distributor__c = true
                    LIMIT 1
                ];
            }

            /* ---------------- Per Invoice Calculation ---------------- */

            Decimal taxableAmount = inv.Taxable_Amount__c != null ? inv.Taxable_Amount__c : 0;
            Decimal totalGST = inv.Total_GST__c != null ? inv.Total_GST__c : 0;
            Decimal beforeRoundOff = taxableAmount + totalGST;

            Decimal totalInvoiceAmount;
            Decimal roundOff;

            if (beforeRoundOff > 0) {
                totalInvoiceAmount = Math.round(beforeRoundOff);
                roundOff = totalInvoiceAmount - beforeRoundOff;
            } else if (inv.Invoice_Amount__c != null && inv.Invoice_Amount__c > 0) {
                totalInvoiceAmount = Math.round(inv.Invoice_Amount__c);
                roundOff = totalInvoiceAmount - inv.Invoice_Amount__c;
            } else {
                totalInvoiceAmount = 0;
                roundOff = 0;
            }

            InvoiceWrapper wrapper = new InvoiceWrapper(inv, lineItems, reimbursementLines);
            wrapper.totalInvoiceAmount = totalInvoiceAmount;
            wrapper.roundOff = roundOff;
            wrapper.freeOfferMessage = freeOfferMessage;
            wrapper.appliedQuantityDiscountSchemes = appliedQuantityDiscountSchemes;

            invoiceWrappers.add(wrapper);
        }

        ApexPages.currentPage().getHeaders().put(
            'Content-Disposition',
            'attachment; filename="' + filename + '"'
        );
    }

    /* ===================== WRAPPER ===================== */

 public class InvoiceWrapper {
        public Invoice__c invoice { get; set; }
        public List<Invoice_Line_Item__c> invoiceLineItems { get; set; }
        public List<Invoice_Reimbursement_Line__c> reimbursementLines { get; set; }
        public Decimal totalInvoiceAmount { get; set; }
        public Decimal roundOff { get; set; }
        public String freeOfferMessage { get; set; } // Modern Trade free-goods scheme message, shown next to CGST
        public List<AppliedSchemeDisplay> appliedQuantityDiscountSchemes { get; set; }
        // Drives whether the "Scheme" column shows at all on this invoice's item table —
        // most invoices never use a Purchase Quantity Discount scheme, so the column is
        // hidden entirely (not just blank) to keep the table from crowding the page.
        public Boolean hasSchemeDiscount {
            get { return appliedQuantityDiscountSchemes != null && !appliedQuantityDiscountSchemes.isEmpty(); }
        }

        public InvoiceWrapper(Invoice__c invoice, List<Invoice_Line_Item__c> lineItems, List<Invoice_Reimbursement_Line__c> reimbursementLines) {
            this.invoice = invoice;
            this.invoiceLineItems = lineItems;
            this.reimbursementLines = reimbursementLines;
        }
    }
}