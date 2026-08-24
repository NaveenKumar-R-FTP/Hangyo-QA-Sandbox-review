public without sharing class EditSecondaryInvoiceHandler {
    
    public static String invoiceFields      =   'CGST__c, CGST_Amount__c, Credit_Period__c, ' +
                                                'Distributor_Account__c, Due_Date__c, ' +
                                                'IGST__c, IGST_Amount__c, Invoice_Amount__c, Invoice_Amount_In_Words__c, Invoice_Date__c, Invoice_Number__c, ' +
                                                'Order__c, Order__r.Type__c, Order__r.Description__c, Order__r.Sale_Type__c, Order__r.Price_Type__c, Discount_1__c , Discount_2__c ,' +
                                                'Payment_Status__c, Place_of_Supply__c, ' +
                                                'Retailer_Account__c, Under_SS__c, ' +
                                                'SGST__c, SGST_Amount__c, Status__c, ' +
                                                'Taxable_Amount__c, TCS__c, TCS_Amount__c, Total_GST__c, Total_Quantity__c,' +
                                                'Id, Name, Value_Scheme_Applied__c,Value_Scheme_Discount__c, ' +
                                                'Total_Reimbursement_Applied__c';

    // Quantity_Scheme_Applied__r.Name/Discount_Percentage__c/Type__c added so the LWC can
    // show which scheme was applied and at what % — same reasoning as
    // SecondaryInvoiceHandler.cls's invoiceItemFields.
    // NOTE: Discount_Percentage__c is NOT a real field on Invoice_Line_Item__c (confirmed
    // via Object Manager — only Discount__c, Discount_2__c, Scheme_Discount_Amount__c,
    // Total_Discount__c exist there; Discount_Percentage__c only exists on
    // Order_Line_Item__c). A prior attempt to add it here to fix TOD-on-reload was based
    // on a bad assumption and broke every test/query that runs this SOQL — reverted.
    public static String invoiceItemFields  =   'Id, Invoice__c, Invoice__r.Status__c, Price__c, Product__c, Product__r.Name, Product__r.Product_Code__c, Product__r.Category_Code__c, Product__r.Per_Pieces__c, Quantity__c, Total_Amount__c, MRP__c , Discount_2__c , SKU_Discount_Percent__c , Discount_1__c, Scheme_Discount_Amount__c, Is_Promotional__c, Quantity_Scheme_Applied__c, Quantity_Scheme_Applied__r.Name, Quantity_Scheme_Applied__r.Discount_Percentage__c, Quantity_Scheme_Applied__r.Type__c, Promo_Min_Qty__c,Parent_Product__c';

    public static String STATE_TAX          =   'State Tax';

    public static string CENTRAL_TAX        =   'Central Tax';

    // ─────────────────────────────────────────────────────────────────────────
    // MODIFIED: isTodEligible (replaces the old isTodBlockedByMrp helpers)
    //
    // Old implementation used raw MRP__c directly:
    //   private static final Decimal TOD_MRP_THRESHOLD = 20;
    //   public static Boolean isTodBlockedByMrp(Decimal mrp) {
    //       return mrp != null && mrp <= TOD_MRP_THRESHOLD;
    //   }
    //
    // New implementation mirrors SecondaryInvoiceHandler exactly:
    //   MRP per piece = MRP__c / Per_Pieces__c  (when Per_Pieces__c is not null/0)
    //   MRP per piece = MRP__c                  (when Per_Pieces__c is null or 0)
    //   TOD eligible  = MRP per piece > 20
    //
    // All callers updated to use isTodEligible() instead of !isTodBlockedByMrp().
    // ─────────────────────────────────────────────────────────────────────────
    public static Boolean isTodEligible(Decimal mrp, Decimal perPieces) {
        if (mrp == null) return false;
        Decimal mrpPerPiece = (perPieces != null && perPieces > 0)
                              ? (mrp / perPieces)
                              : mrp;
        return mrpPerPiece >= 20;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MODIFIED: applyTodMrpRuleToInvoiceLine
    //
    // Old: used isTodBlockedByMrp(line.MRP__c) — raw MRP, no Per_Pieces__c.
    // New: must look up Per_Pieces__c from Product__c to apply the correct gate.
    //      Because this helper is called per-line (not in bulk), we accept an
    //      optional perPieces argument; callers that already have the value pass
    //      it in directly. The bulk variant below fetches it once for all lines.
    // ─────────────────────────────────────────────────────────────────────────
    public static void applyTodMrpRuleToInvoiceLine(Invoice_Line_Item__c line, Decimal perPieces) {
        if (line == null || line.Is_Promotional__c == true) {
            return;
        }
        if (!isTodEligible(line.MRP__c, perPieces)) {
            line.Discount_1__c = 0;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MODIFIED: applyTodMrpRuleToInvoiceLineItems (bulk variant)
    //
    // Old: called applyTodMrpRuleToInvoiceLine(line) with only MRP, no pieces.
    // New: bulk-fetches Per_Pieces__c for all products in one SOQL, then
    //      applies the correct per-piece gate to every non-promotional line.
    // ─────────────────────────────────────────────────────────────────────────
    public static void applyTodMrpRuleToInvoiceLineItems(List<Invoice_Line_Item__c> items) {
        if (items == null || items.isEmpty()) {
            return;
        }

        // Collect product IDs
        Set<Id> productIds = new Set<Id>();
        for (Invoice_Line_Item__c line : items) {
            if (line.Product__c != null) {
                productIds.add(line.Product__c);
            }
        }

        // Bulk-fetch Per_Pieces__c (single SOQL — governor-limit safe)
        Map<Id, Decimal> perPiecesMap = new Map<Id, Decimal>();
        for (Product__c prod : [
            SELECT Id, Per_Pieces__c
            FROM Product__c
            WHERE Id IN :productIds
        ]) {
            perPiecesMap.put(prod.Id, prod.Per_Pieces__c);
        }

        for (Invoice_Line_Item__c line : items) {
            Decimal perPieces = perPiecesMap.get(line.Product__c);
            applyTodMrpRuleToInvoiceLine(line, perPieces);
        }
    }

    @AuraEnabled
    public static InvoiceData createInvoiceData(String invoiceId) {
        System.debug('invoiceId:- ' + invoiceId);
        Id Under_SS_Secondary_invoiceId        =   Schema.SObjectType.Invoice__c.getRecordTypeInfosByDeveloperName().get('Secondary_Invoice_Under_SS').getRecordTypeId();
        Id Secondary_InvoiceId                 =   Schema.SObjectType.Invoice__c.getRecordTypeInfosByDeveloperName().get('Secondary_Invoice').getRecordTypeId();
        
        List<Invoice__c> underSSinvoice = new List<Invoice__c>();
        Id underSSInvoiceId;
        underSSinvoice = [Select Under_SS__c from Invoice__c WHERE Id =: invoiceId];
        if(!underSSinvoice.isEmpty()){
           underSSInvoiceId =  underSSinvoice[0].Under_SS__c;
        }
        InvoiceData oInvData    =   new InvoiceData();
        
        try {
            Invoice__c invoiceData = [SELECT Id , Retailer_Account__c , Status__c , Invoice_Date__c , Order__c , Order__r.EffectiveDate__c, RecordTypeId FROM Invoice__c WHERE RecordType.DeveloperName IN ('Secondary_Invoice_Under_SS', 'Secondary_Invoice') AND Id =: invoiceId LIMIT 1];
            if(invoiceId == null) {
                oInvData.message = 'No Invoice found!';
                return oInvData;
            } else if(invoiceData.Retailer_Account__c == null && invoiceData.RecordTypeId == Secondary_InvoiceId){
                oInvData.message = 'Retailer information missing on Invoice';
                return oInvData;
            }
            else if(underSSInvoiceId == null && invoiceData.RecordTypeId == Under_SS_Secondary_invoiceId){
                oInvData.message = 'Under SS information missing on Invoice';
                return oInvData;
                }else if(!InvoiceEditWindow.isEditable(invoiceData)){
                oInvData.message = 'This invoice is locked. The 2-day edit window has closed or the invoice is cancelled.';
                return oInvData;
            }
            if(invoiceData.Order__c != null) {
                oInvData.orderDate = invoiceData.Order__r.EffectiveDate__c;
            }
            
            User loggedInUser = [SELECT Id, AccountId  FROM User WHERE Id = :UserInfo.getUserId()];
        
            if (loggedInUser.AccountId == null) {
                System.debug('No AccountId found for the logged-in user.');
            }
        	List<User> dmsUserList = new List<User>();
            
            dmsUserList = [Select Id, Name, CompanyName, Phone, MobilePhone, Email, FullPhotoUrl, SmallPhotoUrl, MediumPhotoUrl,
                            GSTIN__c, PAN_Number__c, Invoice_Number_Prefix__c, Invoice_Start_Number__c, State, Notes__c,
                            Bank_Name__c, Bank_Account_Number__c, IFSC_Code__c, UPI_ID__c, UPI_QR_CODE__c,
                            Contact.Account.BillingStreet,Contact.Account.BillingCity,Contact.Account.BillingState,Contact.Account.BillingPostalCode,
                            Contact.Account.BillingCountry,Terms_and_Conditions__c, Contact.AccountId,Contact.Account.Name,AccountId,Primary_Distributor__c,
                           Contact.Account.Phone_1__c,Contact.Account.FSSAI__c,Contact.Account.Primary_State__c FROM User WHERE AccountId=:loggedInUser.AccountId LIMIT 1];
        
            User distributor = dmsUserList.size() == 1 ? dmsUserList[0] : null;
            Account retailer = new Account();
            
            if(invoiceData.Retailer_Account__c != null && invoiceData.RecordTypeId == Secondary_InvoiceId){
                retailer    =   RetailerAccountHandler.getRetailerAccount(invoiceData.Retailer_Account__c);
            }else if(underSSInvoiceId != null && invoiceData.RecordTypeId == Under_SS_Secondary_invoiceId){
                System.debug('underSSInvoiceId:-' + underSSInvoiceId);
                retailer =   RetailerAccountHandler.getUnderSSAccount(underSSInvoiceId);  
                System.debug('retailer:-' + retailer);
            }
            
            if(retailer == null) {
                oInvData.message = 'Error fetching Retailer/Under SS information, Contact System Administrator.';
                return null;
            } else if (distributor == null) { 
                oInvData.message = 'Error fetching Distributor information, Contact System Administrator to make you as a primary distributor.';
                return oInvData; 
            } 
            
            String distState    =   String.isNotBlank(distributor.Contact.Account.Primary_State__c) ? distributor.Contact.Account.Primary_State__c : '';
            String rtlrState    =   String.isNotBlank(retailer.Primary_State__c) ? retailer.Primary_State__c : '';
            String taxComp = (String.isNotBlank(distState) && String.isNotBlank(rtlrState) && distState.equalsIgnoreCase(rtlrState))? 'state matching': 'state not matching';

            List<Object> invItems   =   new List<Object>();
            Invoice__c invoiceList = fetchInvoiceData(invoiceId);
            System.debug('invoiceList:- ' + invoiceList);
            if(invoiceList != null) {
                invItems = fetchInvLineItems(invoiceId);
            
                // ── MODIFIED: apply bulk TOD/MRP gate (uses Per_Pieces__c now) ──
                // Old: called applyTodMrpRuleToInvoiceLine(item) per line using raw MRP
                // New: applyTodMrpRuleToInvoiceLineItems bulk-fetches Per_Pieces__c
                //      and applies the correct mrp-per-piece > 20 gate in one pass
                if (invItems != null && !invItems.isEmpty()) {
                    List<Invoice_Line_Item__c> lineItems = new List<Invoice_Line_Item__c>();
                    Set<Id> productIds = new Set<Id>();
                    for (Object itemObj : invItems) {
                        Invoice_Line_Item__c item = (Invoice_Line_Item__c) itemObj;
                        lineItems.add(item);
                        if (item.Product__c != null) {
                            productIds.add(item.Product__c);
                        }
                    }
                    applyTodMrpRuleToInvoiceLineItems(lineItems); // applies per-piece gate + zeros Discount_1__c where ineligible

                    // Fetch stock data
                    Map<Id, Decimal> stockMap = getStockByProducts(new List<Id>(productIds));
                    oInvData.stockByProduct = stockMap;
                }
            }

            System.debug('invItems:- ' + invItems);
            oInvData.dmsUser            =   distributor;
            oInvData.retailerAccount    =   retailer;
            oInvData.invoice            =   invoiceList;
            oInvData.invoiceItems       =   invItems;
            oInvData.message            =   distributor == null ? 'Error getting your profile details, please contact system admin!' : 
                                            retailer == null ? 'Error getting retailer details, please contact system admin!' :
                                            'Success';
            System.debug('oInvData*** ' + oInvData);
            return oInvData;
        } catch (Exception e) {
            System.debug('Exception***' + e.getMessage() + ' ' + e.getLineNumber() + ' ' + e.getCause());
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    public static Invoice__c fetchInvoiceData(Id invoiceId) {
        String queryStr = 'SELECT ' + invoiceFields + ' FROM Invoice__c WHERE Id = :invoiceId LIMIT 1';
        Map<String, Object> bindVarMap = new Map<String, Object> {'invoiceId' => invoiceId};
        System.debug('fetchInvoiceData queryStr*** ' + queryStr);
        
        List<Invoice__c> invoiceList = (List<Invoice__c>) Utility.soqlQuery(queryStr, bindVarMap, AccessLevel.USER_MODE);
        return invoiceList.isEmpty() ? null : invoiceList[0];
    }   //End of fetchInvoice()
    
    public static List<Invoice_Line_Item__c> fetchInvLineItems(Id invoiceId) {
        String queryStr                 =   'SELECT ' + invoiceItemFields + ' FROM Invoice_Line_Item__c WHERE Invoice__c = :invoiceId ORDER BY Product__r.Product_Brand__c , Product__r.Name ASC';
        Map<String, Object> bindVarMap  =   new Map<String, Object> {'invoiceId' => invoiceId};
        System.debug('fectchInvLineItems queryStr*** ' + queryStr);
        List<Invoice_Line_Item__c> invItemList  =   Utility.soqlQuery(queryStr,bindVarMap,AccessLevel.USER_MODE);
        System.debug('fectchInvLineItems invItemList*** ' + invItemList.size() + ' ' + invItemList);
        return invItemList.size() > 0 ? invItemList : null; 
    }   //End of fectchInvLineItems()
    
    public static void deleteInvoiceLineItem(List<Id> invoiceLineItemId) {
        System.debug('InvoiceLineItem Id: ' + invoiceLineItemId);
        
        try {
            if (invoiceLineItemId == null || invoiceLineItemId.isEmpty()) {
                throw new AuraHandledException('Invoice Line Item Id(s) are required.');
            }
            List<Invoice_Line_Item__c> invoiceLineItemList = [SELECT Id FROM Invoice_Line_Item__c WHERE Id IN :invoiceLineItemId];
            delete invoiceLineItemList;
    
        } catch (Exception ex) {
            System.debug('Error deleting Invoice Line Item: ' + ex.getMessage());
            throw new AuraHandledException('Unable to delete the Invoice Line Item(s): ' + ex.getMessage());
        }
    }
    
    @AuraEnabled
    public static InvoiceData saveInvoiceAndLineItems(Invoice__c invoice, List<Invoice_Line_Item__c> invItemList,List<Id> deletedItemIds){
        InvoiceEditWindow.assertEditable(invoice.Id);
        try {
            InvoiceData oInvData = new InvoiceData();
            System.debug('save invoice***' + invoice);
            System.debug('save invoice line items***' + invItemList.size() + invItemList);
            system.debug('deletedItemIds'+deletedItemIds);
            if(!deletedItemIds.isEmpty()){
                deleteInvoiceLineItem(deletedItemIds);
            }
            // Save the side being CLEARED first, so the mutual-exclusivity validator
            // never sees a stale header-vs-line conflict mid-transaction.
            // Overall discount set -> line SKU %s are cleared: persist lines first, then header.
            // Otherwise (SKU-wise or no discount): persist header first, then lines.
            Boolean overallMode = invoice.getPopulatedFieldsAsMap().containsKey('Discount_2__c')
                && invoice.Discount_2__c != null && invoice.Discount_2__c != 0;
            if (overallMode) {
                oInvData.invoiceItems = saveInvoiceItems(invoice.Id, invItemList);
                oInvData.invoice      = saveInvoice(invoice);
            } else {
            oInvData.invoice = saveInvoice(invoice);
            oInvData.invoiceItems = saveInvoiceItems(oInvData.invoice.Id,invItemList);
            }
            return oInvData;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        
        }
    }   //End of saveInvoiceAndLineItems()
    
    public static Invoice__c saveInvoice(Invoice__c invoice) {
        invoice.Discount_1__c = null;

                update invoice;
        return invoice;
    }   //End of saveInvoice()

    // ─────────────────────────────────────────────────────────────────────────
    // MODIFIED: saveInvoiceItems
    //
    // Old: called applyTodMrpRuleToInvoiceLine(oLineItem) per line using raw MRP
    //      (no Per_Pieces__c awareness).
    // New: collects all lines first, then calls applyTodMrpRuleToInvoiceLineItems
    //      which bulk-fetches Per_Pieces__c and applies the correct per-piece gate
    //      in a single SOQL call before the upsert.  Same bulk treatment is
    //      applied to the lines returned after the upsert.
    // ─────────────────────────────────────────────────────────────────────────
    public static List<Object> saveInvoiceItems(Id invoiceId, List<Invoice_Line_Item__c> invItemList) {
        System.debug('before save invItemList*** ' + invItemList.size() + ' ' + invItemList);

        for (Invoice_Line_Item__c oLineItem : invItemList) {
            if (oLineItem.Invoice__c == null) {
                oLineItem.Invoice__c = invoiceId;
            }
        }

        // Apply per-piece TOD gate before persisting (single bulk SOQL)
        applyTodMrpRuleToInvoiceLineItems(invItemList);

        upsert invItemList;

        invItemList = fetchInvLineItems(invoiceId);
        if (invItemList != null) {
            // Normalize returned lines as well
            applyTodMrpRuleToInvoiceLineItems(invItemList);
        }
        return invItemList;
    }   //End of saveInvoiceItems()

    // ─────────────────────────────────────────────────────────────────────────
    // MODIFIED: getProductName  (ProductWrapper)
    //
    // Old: queried only MRP__c; used raw MRP in isTodBlockedByMrp(product.MRP__c).
    // New: queries MRP__c AND Per_Pieces__c; calls isTodEligible(mrp, perPieces)
    //      for the correct per-piece gate, exactly mirroring SecondaryInvoiceHandler.
    //      Also adds isTodEligible boolean to ProductWrapper so the LWC can
    //      gate discount1Amt when adding/editing line items.
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static ProductWrapper getProductName(Id productId, Id accountId) {
        System.debug('productId:- ' + productId);
        System.debug('accountId:- ' + accountId);
        try {
            String productName = '';
            Decimal discountPercent = 0;
            Date today = Date.today();
            
            // MODIFIED: added Per_Pieces__c to the product query
            Product__c product = [
                SELECT Name, MRP__c, Per_Pieces__c
                FROM Product__c
                WHERE Id = :productId
                LIMIT 1
            ];
            productName = product.Name;

            // MODIFIED: use isTodEligible(mrp, perPieces) instead of isTodBlockedByMrp(mrp)
            Boolean todEligible = isTodEligible(product.MRP__c, product.Per_Pieces__c);
            System.debug('TOD eligible (getProductName edit): ' + todEligible
                         + ' | MRP=' + product.MRP__c + ' | Pieces=' + product.Per_Pieces__c);

            if (todEligible) {
                // Try to fetch product-level discount first
                List<Discount__c> productDiscountList = [
                    SELECT Id, Discount_Percentage__c 
                    FROM Discount__c 
                    WHERE Product__c = :productId 
                    AND Account__c = :accountId 
                    AND Start_Date__c <= :today 
                    AND End_Date__c >= :today 
                    LIMIT 1
                ];
                
                if (!productDiscountList.isEmpty() && productDiscountList[0].Discount_Percentage__c != null) {
                    discountPercent = productDiscountList[0].Discount_Percentage__c;
                    System.debug('Product-level discount applied: ' + discountPercent);
                } else {
                    // Fallback: get retailer-level discount (no product condition)
                    List<Discount__c> retailerDiscountList = [
                        SELECT Id, Discount_Percentage__c 
                        FROM Discount__c 
                        WHERE Product__c = NULL 
                        AND Account__c = :accountId 
                        AND Start_Date__c <= :today 
                        AND End_Date__c >= :today 
                        LIMIT 1
                    ];
                    
                    if (!retailerDiscountList.isEmpty() && retailerDiscountList[0].Discount_Percentage__c != null) {
                        discountPercent = retailerDiscountList[0].Discount_Percentage__c;
                        System.debug('Retailer-level discount applied: ' + discountPercent);
                    }
                }
            } else {
                // MRP per piece ≤ 20 → no TOD applicable; discountPercent stays 0
                System.debug('TOD not eligible for product ' + productId + '. No discount applied.');
            }

            // MODIFIED: pass todEligible as third constructor argument
            return new ProductWrapper(productName, discountPercent, todEligible);
    
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching product details: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Decimal getMRPByProduct(String productId) {
       	if (productId == null) {
        	return 0;
   		}
    	Product__c product = [SELECT MRP__c FROM Product__c WHERE Id = :productId LIMIT 1];
    	if (product != null && product.MRP__c != null) {
        	return product.MRP__c;
    	}
    	return 0; 
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getPriceByProduct(String productId, String state, String accountType) {
        Map<String, Object> result = new Map<String, Object>();
        Decimal price = 0;
        Decimal stock = 0;
        
        if (productId == null) {
            result.put('price', 0);
            result.put('stockInHand', 0);
            return result;
        }
    
        List<Price_Book_Entry__c> pEntry = new List<Price_Book_Entry__c>();
        if (accountType == 'Under Super Stockist') {
            pEntry = [SELECT PTD__c 
                      FROM Price_Book_Entry__c 
                      WHERE Product__c = :productId 
                        AND Region__r.Name = :state 
                        AND Type__c ='Direct Distributor' 
                      LIMIT 1];
            if (!pEntry.isEmpty()) {
                price = pEntry[0].PTD__c;
            }
        } else if (accountType == 'Retailer') {
            pEntry = [SELECT PTR__c 
                      FROM Price_Book_Entry__c 
                      WHERE Product__c = :productId 
                        AND Region__r.Name = :state 
                        AND Type__c= 'Retailer' 
                      LIMIT 1];
            if (!pEntry.isEmpty()) {
                price = pEntry[0].PTR__c;
            }
        }
    
        User loggedInUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        List<Inventory__c> invList = [SELECT Quantity_in_hand__c 
                                      FROM Inventory__c 
                                      WHERE Product__c = :productId 
                                        AND Distributor_Name__c = :loggedInUser.AccountId 
                                      LIMIT 1];
        if (!invList.isEmpty() && invList[0].Quantity_in_hand__c != null) {
            stock = invList[0].Quantity_in_hand__c;
        }
    
        result.put('price', price);
        result.put('stockInHand', stock);
        return result;
    }
    
	@AuraEnabled(cacheable=true)
	public static Map<Id, Decimal> getStockByProducts(List<Id> productIds) {
        System.debug('productIds:- ' + productIds);
    	Map<Id, Decimal> stockMap = new Map<Id, Decimal>();
		User loggedInUser = [SELECT Id, AccountId FROM User WHERE Id = :UserInfo.getUserId()];
        if (productIds == null || productIds.isEmpty()) {
            return stockMap;
        }
        for (Inventory__c inv : [SELECT Product__c, Quantity_in_hand__c FROM Inventory__c WHERE Product__c IN :productIds AND Distributor_Name__r.Id =:loggedInUser.AccountId]) {
            stockMap.put(inv.Product__c, inv.Quantity_in_hand__c);
        }
    	return stockMap;								
	}

    public Class InvoiceData {
        @AuraEnabled public User dmsUser;
        @AuraEnabled public Account retailerAccount;
        @AuraEnabled public Invoice__c invoice;
        @AuraEnabled public List<Object> invoiceItems;
        @AuraEnabled public String message;
        @AuraEnabled public Map<Id, Decimal> stockByProduct;
        @AuraEnabled public Date orderDate;
    }

	public class ProductPriceWrapper {
        @AuraEnabled public Decimal mrp { get; set; }
        @AuraEnabled public Decimal price { get; set; }
    }
    
    // ── MODIFIED: added isTodEligible field (mirrors SecondaryInvoiceHandler.ProductWrapper) ──
    public class ProductWrapper {
        @AuraEnabled public String name;
        @AuraEnabled public Decimal discount;
        @AuraEnabled public Boolean isTodEligible;
        
        public ProductWrapper(String name, Decimal discount, Boolean isTodEligible) {
            this.name         = name;
            this.discount     = discount;
            this.isTodEligible = isTodEligible;
        }
    }
    
    public class ProductSearchDTO {
        @AuraEnabled public Id Id;
        @AuraEnabled public String Name;
        @AuraEnabled public Decimal Stock;
    
        public ProductSearchDTO(Id id, String name, Decimal stock) {
            this.Id   = id;
            this.Name = name;
            this.Stock = stock;
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<ProductSearchDTO> getProductsWithStock(String searchKey) {
        try {
            if (String.isBlank(searchKey)) {
                return new List<ProductSearchDTO>();
            }
    
            User loggedInUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            if (loggedInUser == null || loggedInUser.AccountId == null) {
                return new List<ProductSearchDTO>();
            }
    
            String key = '%' + String.escapeSingleQuotes(searchKey) + '%';
    
            List<Inventory__c> invList = [
                SELECT Product__c, Product__r.Name, Quantity_in_hand__c
                FROM Inventory__c
                WHERE Distributor_Name__c = :loggedInUser.AccountId
                  AND Quantity_in_hand__c > 0
                  AND Product__r.Name LIKE :key
                ORDER BY Product__r.Name
                LIMIT 50
            ];
    
            Map<Id, Decimal> productStock   = new Map<Id, Decimal>();
            Map<Id, String>  productNameMap = new Map<Id, String>();
    
            for (Inventory__c inv : invList) {
                if (inv.Product__c == null) continue;
                Decimal current = productStock.containsKey(inv.Product__c) ? productStock.get(inv.Product__c) : 0;
                Decimal add = inv.Quantity_in_hand__c == null ? 0 : inv.Quantity_in_hand__c;
                productStock.put(inv.Product__c, current + add);
                if (!productNameMap.containsKey(inv.Product__c) && inv.Product__r != null) {
                    productNameMap.put(inv.Product__c, inv.Product__r.Name);
                }
            }
    
            List<ProductSearchDTO> result = new List<ProductSearchDTO>();
            for (Id pid : productStock.keySet()) {
                result.add(new ProductSearchDTO(pid, productNameMap.get(pid), productStock.get(pid)));
            }
            return result;
        } catch (Exception ex) {
            System.debug('Error in getProductsWithStock: ' + ex.getMessage());
            return new List<ProductSearchDTO>();
        }
    }
    
    public static Map<Id, Decimal> getDistributorStockForProducts(Set<Id> productIds) {
        Map<Id, Decimal> stockMap = new Map<Id, Decimal>();
    
        if (productIds == null || productIds.isEmpty()) {
            return stockMap;
        }
    
        User u = [
            SELECT Contact.AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
    
        if (u.Contact == null || u.Contact.AccountId == null) {
            return stockMap;
        }
    
        Id distributorAccountId = u.Contact.AccountId;
    
        for (Inventory__c inv : [
            SELECT Product__c, Quantity_in_hand__c
            FROM Inventory__c
            WHERE Product__c IN :productIds
            AND Distributor_Name__r.Id = :distributorAccountId
        ]) {
            stockMap.put(inv.Product__c, inv.Quantity_in_hand__c);
        }
    
        return stockMap;
    }

   	private static Map<String, Object> resolveBuyerFromInvoice(Id invoiceId) {
        Invoice__c inv = [
            SELECT Id,
                   Retailer_Account__c,
                   Retailer_Account__r.Primary_State__c,
                   Under_SS__c,
                   Under_SS__r.Primary_State__c
            FROM Invoice__c
            WHERE Id = :invoiceId
            LIMIT 1
        ];
    
        Id     buyerAccountId;
        String buyerRegion;
        Boolean isUnderSS = false;
    
        if (inv.Retailer_Account__c != null) {
            buyerAccountId = inv.Retailer_Account__c;
            buyerRegion    = inv.Retailer_Account__r.Primary_State__c;
            isUnderSS      = false;
        } else if (inv.Under_SS__c != null) {
            buyerAccountId = inv.Under_SS__c;
            buyerRegion    = inv.Under_SS__r.Primary_State__c;
            isUnderSS      = true;
        }
    
        if (buyerAccountId == null || String.isBlank(buyerRegion)) {
            throw new AuraHandledException('Unable to resolve Buyer Account / Region from Invoice');
        }
    
        return new Map<String, Object>{
            'buyerAccountId' => buyerAccountId,
            'buyerRegion'    => buyerRegion,
            'isUnderSS'      => isUnderSS
        };
    }
    
    @AuraEnabled
    public static List<QuantitySchemeModalWrapper> getqualitySchemeFromOrder(Id productId, Id invoiceId) {
        Map<String, Object> buyerInfo = resolveBuyerFromInvoice(invoiceId);
        return SchemeEvaluationService.getqualityScheme(
            productId,
            (Id)     buyerInfo.get('buyerAccountId'),
            (String) buyerInfo.get('buyerRegion'),
            (Boolean)buyerInfo.get('isUnderSS')
        );
    }
    
    @AuraEnabled
    public static List<CartProductWrapper.ProductWrapper> applyQuantitySchemeFromOrder(
            List<CartProductWrapper.ProductWrapper> cartItems, Id invoiceId, Id selectedSchemeId) {
        Map<String, Object> buyerInfo = resolveBuyerFromInvoice(invoiceId);
        return SchemeEvaluationService.applyQuantityScheme(
            cartItems,
            (Id)     buyerInfo.get('buyerAccountId'),
            (String) buyerInfo.get('buyerRegion'),
            selectedSchemeId,
            (Boolean)buyerInfo.get('isUnderSS')
        );
    }
    
    @AuraEnabled
    public static List<SchemeDetailsWrapper> getvalueSchemeFromOrder(Decimal totalAmount, Id invoiceId) {
        Map<String, Object> buyerInfo = resolveBuyerFromInvoice(invoiceId);
        return SchemeEvaluationService.getvalueScheme(
            totalAmount,
            (Id)     buyerInfo.get('buyerAccountId'),
            (String) buyerInfo.get('buyerRegion'),
            (Boolean)buyerInfo.get('isUnderSS')
        );
    }
}