public class SecondaryInvoiceDownloaderCtl {
    public Id invoiceId { get; set; } 
    public User dmsUserInfo { get; set; }
    public List<InvoiceWrapper> invoiceWrappers { get; set;}
    public Decimal discountPercent { get; set;}
    public Decimal totalInvoiceAmount { get; set;}
    public Decimal roundOff { get; set;} // added by Fuzail - Property to store round off value
    public String freeOfferMessage { get; set;} // Modern Trade free-goods scheme message, shown next to CGST
    public List<AppliedSchemeDisplay> appliedQuantityDiscountSchemes { get; set;}
    // Drives whether the "Scheme" column shows at all on the item table — most invoices
    // never use a Purchase Quantity Discount scheme, so the column is hidden entirely
    // (not just blank) to keep the table from crowding the page.
    public Boolean hasSchemeDiscount {
        get { return appliedQuantityDiscountSchemes != null && !appliedQuantityDiscountSchemes.isEmpty(); }
    }

    public SecondaryInvoiceDownloaderCtl() {
        
        invoiceId = ApexPages.currentPage().getParameters().get('id');
        invoiceWrappers = new List<InvoiceWrapper>();
        Id userId                       =   UserInfo.getUserId();
        User loggedInUser = [SELECT Id, AccountId FROM User WHERE Id = :UserInfo.getUserId()];
    
        // Check if logged-in user has an AccountId
        if (loggedInUser.AccountId == null) {
            System.debug('No AccountId found for the logged-in user.');
            // Exit if there's no AccountId
        }
        system.debug('dmsUserInfo'+dmsUserInfo);
        Set<Id> invoiceIds = new Set<Id>();
        system.debug('invoiceId'+invoiceId);
        
        Decimal totalDiscount = 0;
        if (invoiceId != null) {
        
            // ── MODIFIED: removed the (SELECT ... FROM Reimbursement_Lines__r)
            // subquery from this main query. That subquery works fine on every
            // direct browser load of this page, but throws
            // "SObject row was retrieved via SOQL without querying the
            // requested field" specifically when this page is rendered via
            // PageReference.getContent() (as InvoicePDFWrapperController does) —
            // a known Salesforce limitation with relationship subqueries inside
            // readOnly="true" pages invoked that way. Fetching the reimbursement
            // lines as a completely separate top-level query below avoids the
            // issue entirely, since a plain query result has no relationship-
            // field-tracking ambiguity.
            List<Invoice__c> invoices = [SELECT Id, Invoice_Number__c, Status__c , Invoice_Date__c,Distributor_Account__c ,Distributor_Account__r.FSSAI__c,Beat__c,Retailer_Account__r.Beats_Name__r.Name,Order__r.Ordered_By__r.Name, Order__r.Ordered_By__r.MobilePhone , Retailer_Account__r.Name, Retailer_Account__r.Retailer_Code__c , Retailer_Account__r.Phone,Retailer_Account__r.Primary_Address_1__c,Retailer_Account__r.GSTIN__c,Retailer_Account__r.FSSAI__c,Credit_Period__c,Retailer_Account__r.Ship_To_Address_1__c,
                                         Under_SS__r.Name,Under_SS__r.Phone,Under_SS__r.Primary_Address_1__c,Under_SS__r.GSTIN__c,Under_SS__r.FSSAI__c,Under_SS__r.Ship_To_Address_1__c,
                                         Total_Quantity__c,Invoice_Amount__c,Total_GST__c,TCS_Amount__c,Invoice_Amount_In_Words__c,Taxable_Amount__c,TCS__c,SGST__c,SGST_Amount__c,CGST__c,CGST_Amount__c,IGST__c,IGST_Amount__c,
                                         Retailer_Account__r.BillingStreet, Retailer_Account__r.BillingCity,Retailer_Account__r.BillingState,Retailer_Account__r.BillingPostalCode,Retailer_Account__r.BillingCountry,Retailer_Account__r.Owners_Number__c,
                                         Retailer_Account__r.ShippingStreet, Retailer_Account__r.ShippingCity,Retailer_Account__r.ShippingState,Retailer_Account__r.ShippingPostalCode,Retailer_Account__r.ShippingCountry,Retailer_Account__r.ShippingAddress,
                                         Under_SS__r.BillingStreet, Under_SS__r.BillingCity,Under_SS__r.BillingState,Under_SS__r.BillingPostalCode,Under_SS__r.BillingCountry,Under_SS__r.Owners_Number__c,
                                         Under_SS__r.ShippingStreet, Under_SS__r.ShippingCity,Under_SS__r.ShippingState,Under_SS__r.ShippingPostalCode,Under_SS__r.ShippingCountry,Under_SS__r.ShippingAddress,
                                        Total_Discount1__c,Total_Discount_2__c,Total_Discount__c,Total_Discount_Percent__c , Discount_2__c,Value_Scheme_Applied__c,Value_Scheme_Discount__c,Value_Scheme_Applied__r.Name, Remarks__c, Total_Reimbursement_Applied__c, Net_Payable__c
FROM Invoice__c WHERE Id = :invoiceId];
            system.debug('invoices'+invoices);
            for (Invoice__c inv : invoices) {
                // Fetch associated line items for the invoice
                List<Invoice_Line_Item__c> lineItems = [SELECT Price__c, Product__c, Quantity__c, Total_Amount__c,Product__r.Name, Product__r.Product_Code__c, Product__r.Category_Code__c, Product__r.Per_Pieces__c, MRP__c,Discount_2__c,Discount_1__c,Scheme_Discount_Amount__c,Total_Discount__c,CGST_Amount__c,IGST_Amount__c,SGST_Amount__c, Total_Tax__c , Tax__c,Is_Promotional__c, Quantity_Scheme_Applied__c, Quantity_Scheme_Applied__r.Name, Quantity_Scheme_Applied__r.Discount_Percentage__c, Quantity_Scheme_Applied__r.Type__c, Parent_Product__c FROM Invoice_Line_Item__c WHERE Invoice__c = :inv.Id];
                system.debug('lineItems'+lineItems);

                // Modern Trade free-goods scheme — bold message shown next to CGST.
                freeOfferMessage = ModernTradeSchemeService.getFreeOfferMessage(lineItems);

                // Purchase Quantity Discount scheme(s) applied — see SchemeEvaluationService
                // for the shared logic (also used by SecondaryInvoicePdfController and
                // DeliveryPlanInvoiceController).
                appliedQuantityDiscountSchemes = SchemeEvaluationService.getAppliedQuantityDiscountSchemes(lineItems);

                // ── ADDED: separate top-level query for reimbursement lines,
                // replacing the subquery that caused the getContent() failure.
                List<Invoice_Reimbursement_Line__c> reimbursementLines = [
                    SELECT Amount_Applied__c, Retailer_Reimbursement_Scheme__r.Scheme_Definition__r.Name
                    FROM Invoice_Reimbursement_Line__c
                    WHERE Invoice__c = :inv.Id
                ];

                // Create wrapper for each invoice and its line items
                if (inv.Under_SS__c != null){
                    dmsUserInfo = [Select Id, Name, CompanyName, Phone, MobilePhone, Email, FullPhotoUrl, SmallPhotoUrl, MediumPhotoUrl,GSTIN__c, PAN_Number__c, Invoice_Number_Prefix__c, Invoice_Start_Number__c, State, Notes__c,Terms_and_Conditions__c, Contact.AccountId,Contact.Account.Name,UPI_ID__c,UPI_QR_CODE__c,Bank_Name__c,Bank_Account_Number__c,IFSC_Code__c,
                           Contact.Account.BillingStreet,Contact.Account.BillingCity,Contact.Account.FSSAI__c,Contact.Account.BillingState,Contact.Account.BillingPostalCode,Contact.Account.BillingCountry,Contact.Account.Phone_1__c FROM User WHERE AccountId=:inv.Distributor_Account__c AND Primary_Distributor__c = true LIMIT 1];
                }else{
                    dmsUserInfo = [Select Id, Name, CompanyName, Phone, MobilePhone, Email, FullPhotoUrl, SmallPhotoUrl, MediumPhotoUrl,GSTIN__c, PAN_Number__c, Invoice_Number_Prefix__c, Invoice_Start_Number__c, State, Notes__c,Terms_and_Conditions__c, Contact.AccountId,Contact.Account.Name,UPI_ID__c,UPI_QR_CODE__c,Bank_Name__c,Bank_Account_Number__c,IFSC_Code__c,
                           Contact.Account.BillingStreet,Contact.Account.BillingCity,Contact.Account.FSSAI__c,Contact.Account.BillingState,Contact.Account.BillingPostalCode,Contact.Account.BillingCountry,Contact.Account.Phone_1__c FROM User WHERE AccountId=:loggedInUser.AccountId AND Primary_Distributor__c = true LIMIT 1];
                }
                invoiceWrappers.add(new InvoiceWrapper(inv, lineItems, reimbursementLines));
                if(inv.Total_Discount__c > 0){
                    totalDiscount = inv.Total_Discount__c;
                }
                
                // added by Fuzail - Calculate round off based on Taxable Value + Total GST (best practice)
                Decimal taxableAmount = (inv.Taxable_Amount__c != null) ? inv.Taxable_Amount__c : 0;
                Decimal totalGST = (inv.Total_GST__c != null) ? inv.Total_GST__c : 0;
                Decimal beforeRoundOff = taxableAmount + totalGST;
                
                if(beforeRoundOff > 0) {
                    totalInvoiceAmount = Math.round(beforeRoundOff);
                    roundOff = totalInvoiceAmount - beforeRoundOff;
                } else if(inv.Invoice_Amount__c != null && inv.Invoice_Amount__c > 0) {
                    // Fallback to Invoice_Amount__c if Taxable + GST is not available
                    totalInvoiceAmount = Math.round(inv.Invoice_Amount__c);
                    roundOff = totalInvoiceAmount - inv.Invoice_Amount__c;
                } else {
                    totalInvoiceAmount = 0;
                    roundOff = 0; // added by Fuzail
                }
            }
            
            Decimal totalAmount = 0;
            for(Invoice_Line_Item__c inv : [SELECT Id , Total_Amount__c FROM Invoice_Line_Item__c WHERE Invoice__c = :invoiceId]){
                totalAmount = totalAmount + inv.Total_Amount__c;
            }
            if(totalAmount > 0 && totalDiscount > 0){
                discountPercent = (totalDiscount/totalAmount)*100;
            }else{
                discountPercent = 0; 
            }
            
            if(!invoices.isEmpty()){
                String filename = invoices[0].Invoice_Number__c + '.PDF';
                ApexPages.currentPage().getHeaders().put('Content-Disposition', 'attachment; filename="' + filename + '"');
            } 
        }   
    }
    
    public class InvoiceWrapper {
        public Invoice__c invoice { get; set; }
        public List<Invoice_Line_Item__c> invoiceLineItems { get; set; }
        // ── ADDED: reimbursement lines as their own list, no longer a subquery
        public List<Invoice_Reimbursement_Line__c> reimbursementLines { get; set; }

        // Constructor to initialize the invoice and line items
        public InvoiceWrapper(Invoice__c invoice, List<Invoice_Line_Item__c> lineItems, List<Invoice_Reimbursement_Line__c> reimbursementLines) {
            this.invoice = invoice;
            this.invoiceLineItems = lineItems;
            this.reimbursementLines = reimbursementLines;
      }
    }     
}