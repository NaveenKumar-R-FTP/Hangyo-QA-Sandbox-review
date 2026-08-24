public without sharing class SecondaryInvoiceHandler {
    
    public static String invoiceFields      =   'CGST__c, CGST_Amount__c, Credit_Period__c, ' +
                                                'Distributor_Account__c, Due_Date__c, ' +
                                                'IGST__c, IGST_Amount__c, Invoice_Amount__c, Invoice_Amount_In_Words__c, Invoice_Date__c, Invoice_Number__c, ' +
                                                'Order__c, Discount_1__c, Discount_2__c ,' +
                                                'Payment_Status__c, Place_of_Supply__c, ' +
                                                'Retailer_Account__c,Under_SS__c, ' +
                                                'SGST__c, SGST_Amount__c, Status__c, ' +
                                                'Taxable_Amount__c, TCS__c, TCS_Amount__c, Total_GST__c, Total_Quantity__c,' +
                                                'Id, Name,RecordTypeId, Value_Scheme_Applied__c,Value_Scheme_Discount__c, ' +
                                                'Total_Reimbursement_Applied__c, Price_Type__c, Sale_Type__c';

    // Quantity_Scheme_Applied__r.Name/Discount_Percentage__c/Type__c added so the LWC can
    // show which scheme was applied and at what % — needed for the new "Purchase Quantity
    // Discount" scheme type, which (unlike bonus-quantity schemes) doesn't add a visible
    // separate line item, so without these fields there was no way to tell a scheme had
    // been applied at all.
    // NOTE: Discount_Percentage__c is NOT a real field on Invoice_Line_Item__c (confirmed
    // via Object Manager — only Discount__c, Discount_2__c, Scheme_Discount_Amount__c,
    // Total_Discount__c exist there; Discount_Percentage__c only exists on
    // Order_Line_Item__c). A prior attempt to add it here to fix TOD-on-reload was based
    // on a bad assumption and broke every test/query that runs this SOQL — reverted.
    public static String invoiceItemFields  =   'Id, Invoice__c, Invoice__r.Status__c, Price__c, Product__c, Product__r.Name, Product__r.Product_Code__c, Product__r.Category_Code__c, Product__r.Per_Pieces__c, Product__r.Product_Brand__c, Quantity__c, Total_Amount__c, MRP__c , Discount_2__c , Discount_1__c, Scheme_Discount_Amount__c, Is_Promotional__c, Quantity_Scheme_Applied__c, Quantity_Scheme_Applied__r.Name, Quantity_Scheme_Applied__r.Discount_Percentage__c, Quantity_Scheme_Applied__r.Type__c, Promo_Min_Qty__c,Parent_Product__c';

    public static String STATE_TAX          =   'State Tax';
    public static string CENTRAL_TAX        =   'Central Tax';

    // ─────────────────────────────────────────────────────────────────────────
    // HELPER: Compute MRP-per-piece for a product and return whether it is
    //         eligible for TOD (Trade/Order Discount), i.e. mrp-per-piece >= 20.
    //   MRP per piece = MRP__c / Per_Pieces__c   (if Per_Pieces__c is not null/0)
    //   MRP per piece = MRP__c                   (if Per_Pieces__c is null or 0)
    // ─────────────────────────────────────────────────────────────────────────
    private static Boolean isTodEligible(Decimal mrp, Decimal perPieces) {
        if (mrp == null) return false;
        Decimal mrpPerPiece = (perPieces != null && perPieces > 0)
                              ? (mrp / perPieces)
                              : mrp;
        return mrpPerPiece >= 20;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // HELPER: Build padded invoice number from prefix + number
    // ─────────────────────────────────────────────────────────────────────────
    private static String buildInvoiceNumber(String invPrefix, Integer num) {
        Integer padLen = 10 - invPrefix.length() - String.valueOf(num).length();
        String padding = '0'.repeat(padLen > 0 ? padLen : 0);
        return invPrefix + padding + num;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CORE: Generate next invoice number using Invoice_Sequence__c with 
    //       FOR UPDATE lock to prevent duplicates under concurrent saves.
    //       Called ONLY from saveInvoice() — never during draft creation.
    // ─────────────────────────────────────────────────────────────────────────
    private static String generateNextInvoiceNumber(Id distributorAccountId) {
        // Fetch distributor user config
        List<User> userList = [
            SELECT Id, 
                   Invoice_Number_Prefix__c, 
                   Invoice_Start_Number__c,
                   Reset_Invoice_Sequence__c
            FROM User
            WHERE AccountId = :distributorAccountId
            AND IsActive = true
            AND Primary_Distributor__c = true
            LIMIT 1
        ];

        if (userList.isEmpty()) {
            throw new AuraHandledException(
                'Distributor configuration missing. Cannot generate invoice number. ' +
                'Please contact System Administrator.'
            );
        }

        User dist = userList[0];

        if (String.isBlank(dist.Invoice_Number_Prefix__c)) {
            throw new AuraHandledException(
                'Update the "Invoice Number Prefix" in your Profile to continue creating new Invoices!'
            );
        }

        if (dist.Invoice_Start_Number__c == null) {
            throw new AuraHandledException(
                'Update the "Invoice Start Number" in your Profile to continue creating new Invoices!'
            );
        }

        Integer startNum    = Integer.valueOf(dist.Invoice_Start_Number__c);
        Boolean isReset     = dist.Reset_Invoice_Sequence__c == true;
        Integer nextNum;

        try {
            List<Invoice_Sequence__c> seqList = [
                SELECT Id, Last_Number__c
                FROM Invoice_Sequence__c
                WHERE Distributor_Account__c = :distributorAccountId LIMIT 1
                FOR UPDATE
                
            ];

            Invoice_Sequence__c seq;

            if (isReset) {
                // Reset flag set — restart sequence from configured start number
                nextNum = startNum;
                seq = seqList.isEmpty()
                    ? new Invoice_Sequence__c(Distributor_Account__c = distributorAccountId)
                    : seqList[0];
            } else if (seqList.isEmpty()) {
                // No sequence record yet — first invoice for this distributor
                nextNum = startNum;
                seq     = new Invoice_Sequence__c(
                    Distributor_Account__c = distributorAccountId
                );
            } else {
                // Normal flow — increment last used number
                seq     = seqList[0];
                nextNum = Integer.valueOf(seq.Last_Number__c) + 1;
            }

            // Persist the new counter value — releases lock on commit
            seq.Last_Number__c = nextNum;
            upsert seq;

            // Clear reset flag AFTER sequence is safely saved
            if (isReset) {
                dist.Reset_Invoice_Sequence__c = false;
                update dist;
            }

        } catch (QueryException e) {
            if (e.getMessage().contains('UNABLE_TO_LOCK_ROW')) {
                throw new AuraHandledException(
                    'Another invoice is being saved simultaneously. ' +
                    'Please try again in a moment.'
                );
            }
            throw new AuraHandledException(
                'Error generating invoice number: ' + e.getMessage()
            );
        }

        return buildInvoiceNumber(dist.Invoice_Number_Prefix__c, nextNum);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getInvoiceData — unchanged logic, createNewInvoice no longer 
    // assigns invoice number (assigned at save time)
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static InvoiceData getInvoiceData(Order__c order, List<Order_Line_Item__c> orderItemsList) {
        if(order == null || order.Id == null) return null;
        
        InvoiceData oInvData = new InvoiceData();
        try {
            Id Under_SS_Secondary_OrderId = Schema.SObjectType.Order__c.getRecordTypeInfosByDeveloperName().get('Under_SS_Secondary_Order').getRecordTypeId();
            Id Secondary_OrderId          = Schema.SObjectType.Order__c.getRecordTypeInfosByDeveloperName().get('Secondary_Order').getRecordTypeId();
            Id Counter_OrderId            = Schema.SObjectType.Order__c.getRecordTypeInfosByDeveloperName().get('Counter_Order').getRecordTypeId();
            
            List<Order__c> underSSorder = [SELECT Under_SS_Distributor_ID__c FROM Order__c WHERE Id = :order.Id];
            Id underSSOrderId;
            if (!underSSorder.isEmpty()) {
                underSSOrderId = underSSorder[0].Under_SS_Distributor_ID__c;
            }

            // Getting Distributor User Information
            User distributor = DmsUserProfile.fetchDMSUser();
            System.debug('Avengers' + distributor.Contact.Account.BillingStreet);

            // Getting Retailer Account Information
            System.debug('OrderSupr' + order);
            Account retailer = new Account();
            if (order.Account__c != null && (order.RecordTypeId == Secondary_OrderId || order.RecordTypeId == Counter_OrderId)) {
                retailer = RetailerAccountHandler.getRetailerAccount(order.Account__c);
            } else if (underSSOrderId != null && order.RecordTypeId == Under_SS_Secondary_OrderId) {
                retailer = RetailerAccountHandler.getUnderSSAccount(underSSOrderId);
                System.debug('Supriya retailer2' + retailer);
            }

            if (retailer == null || distributor == null) { return null; }

            String distState = String.isNotBlank(distributor.Contact.Account.Primary_State__c) ? distributor.Contact.Account.Primary_State__c : '';
            String rtlrState = resolveBuyerState(order, retailer, Counter_OrderId);
            String taxComp   = (String.isNotBlank(distState) && String.isNotBlank(rtlrState) && distState.equalsIgnoreCase(rtlrState)) ? 'state matching' : 'state not matching';

            // Fetch or create invoice — number NOT assigned here anymore
            Invoice__c invoice = fetchInvoice(order.Id);
            if (invoice == null) {
                invoice = createNewInvoice(
                    order,
                    distributor.Contact.AccountId,
                    distributor.Invoice_Number_Prefix__c,
                    Integer.valueOf(distributor.Invoice_Start_Number__c),
                    taxComp,
                    distState
                );
            }

            Invoice_Line_Item__c[] invItems = invoice.Id != null 
                ? fetchInvLineItems(new Set<Id>{invoice.Id}) 
                : null;

            oInvData.dmsUser         = distributor;
            oInvData.retailerAccount = retailer;
            oInvData.invoice         = invoice;
            oInvData.invoiceItems    = invItems;

            System.debug('oInvData retailerAccount*** ' + oInvData.retailerAccount);
            System.debug('oInvData dmsUser*** '         + oInvData.dmsUser);
            System.debug('oInvData invoice*** '         + invoice);
            System.debug('oInvData invoiceItems*** '    + oInvData.invoiceItems);

            return (oInvData.retailerAccount == null || oInvData.dmsUser == null || 
                    oInvData.invoice == null || oInvData.invoiceItems == null) ? null : oInvData;

        } catch (Exception e) {
            System.debug('Exception***' + e.getMessage() + ' ' + e.getLineNumber() + ' ' + e.getCause());
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // fetchInvoice — unchanged
    // ─────────────────────────────────────────────────────────────────────────
    public static Invoice__c fetchInvoice(Id recordId) {
        String objName  = String.valueOf(recordId.getSObjectType());
        String filter   = objName == 'Order__c' ? 'Order__c = :recordId' : 'Id = :recordId';
        String queryStr = 'SELECT ' + invoiceFields + ' FROM Invoice__c WHERE ' + filter + ' LIMIT 1';
        
        Map<String, Object> bindVarMap = new Map<String, Object>{'recordId' => recordId};
        System.debug('fetchInvoice queryStr*** ' + queryStr);
        
        List<Invoice__c> invList = Utility.soqlQuery(queryStr, bindVarMap, AccessLevel.USER_MODE);
        System.debug('fetchInvoice invoice*** ' + invList.size() + ' ' + invList);
        return invList.size() == 1 ? invList[0] : null;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getDraftInvoice — unchanged
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static InvoiceData getDraftInvoice(Id recordId) {
        try {
            if (recordId == null) {
                throw new AuraHandledException('Record Id is required.');
            }

            InvoiceData oInvData = new InvoiceData();

            String filter   = 'Order__c = :recordId AND Status__c = \'Draft\'';
            String queryStr = 'SELECT ' + invoiceFields + ' FROM Invoice__c WHERE ' + filter + ' LIMIT 1';

            Map<String, Object> bindVarMap = new Map<String, Object>{'recordId' => recordId};

            List<Invoice__c> invList = Utility.soqlQuery(queryStr, bindVarMap, AccessLevel.USER_MODE);
            System.debug('DraftInvoice invoice*** ' + invList.size() + ' ' + invList);
            Invoice__c invoice = (invList != null && !invList.isEmpty()) ? invList[0] : null;

            if (invoice == null) {
                oInvData.message = 'No draft invoice available.';
                return oInvData;
            }

            Id underSSSecondaryInvoiceRTId = Schema.SObjectType.Invoice__c.getRecordTypeInfosByDeveloperName().get('Secondary_Invoice_Under_SS').getRecordTypeId();
            Id secondaryInvoiceRTId        = Schema.SObjectType.Invoice__c.getRecordTypeInfosByDeveloperName().get('Secondary_Invoice').getRecordTypeId();

            List<Invoice__c> underSSInvoice = [SELECT Under_SS__c FROM Invoice__c WHERE Id = :invoice.Id];
            Id underSSInvoiceId;
            if (!underSSInvoice.isEmpty()) {
                underSSInvoiceId = underSSInvoice[0].Under_SS__c;
            }

            User distributor    = DmsUserProfile.fetchDMSUser();
            Account retailer    = new Account();

            if (invoice.Retailer_Account__c != null && invoice.RecordTypeId == secondaryInvoiceRTId) {
                retailer = RetailerAccountHandler.getRetailerAccount(invoice.Retailer_Account__c);
            } else if (underSSInvoiceId != null && invoice.RecordTypeId == underSSSecondaryInvoiceRTId) {
                retailer = RetailerAccountHandler.getUnderSSAccount(underSSInvoiceId);
            }

            if (distributor == null || retailer == null) {
                oInvData.message = 'Distributor or Retailer is null';
                return oInvData;
            }

            String distState = String.isNotBlank(distributor.Contact.Account.Primary_State__c) ? distributor.Contact.Account.Primary_State__c : '';
            String rtlrState = String.isNotBlank(retailer.Primary_State__c) ? retailer.Primary_State__c : '';
            String taxComp   = (String.isNotBlank(distState) && String.isNotBlank(rtlrState) &&
                                distState.equalsIgnoreCase(rtlrState)) ? 'state matching' : 'state not matching';

            System.debug('Tax Component: ' + taxComp);

            Invoice_Line_Item__c[] invItems = fetchInvLineItems(new Set<Id>{invoice.Id});

            Set<Id> productIds = new Set<Id>();
            for (Invoice_Line_Item__c item : invItems) {
                if (item.Product__c != null) {
                    productIds.add(item.Product__c);
                }
            }

            Map<Id, Decimal> stockMap   = getStockByProducts(new List<Id>(productIds));
            oInvData.stockByProduct     = stockMap;
            oInvData.dmsUser            = distributor;
            oInvData.retailerAccount    = retailer;
            oInvData.invoice            = invoice;
            oInvData.invoiceItems       = invItems;
            oInvData.message            = 'Draft invoice found.';

            return oInvData;

        } catch (Exception ex) {
            System.debug('Exception in getDraftInvoice: ' + ex.getMessage());
            throw new AuraHandledException('Failed to fetch draft invoice: ' + ex.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // createInvoiceData — unchanged logic
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static InvoiceData createInvoiceData(Order__c order, List<Order_Line_Item__c> orderItemsList) {
        String valueSchemeName;
        if (order.Value_Scheme_Applied__c != null) {
            Scheme__c s = [SELECT Name FROM Scheme__c WHERE Id = :order.Value_Scheme_Applied__c LIMIT 1];
            valueSchemeName = s.Name;
        }

        Id Under_SS_Secondary_OrderId = Schema.SObjectType.Order__c.getRecordTypeInfosByDeveloperName().get('Under_SS_Secondary_Order').getRecordTypeId();
        Id Secondary_OrderId          = Schema.SObjectType.Order__c.getRecordTypeInfosByDeveloperName().get('Secondary_Order').getRecordTypeId();
        Id Counter_OrderId            = Schema.SObjectType.Order__c.getRecordTypeInfosByDeveloperName().get('Counter_Order').getRecordTypeId();

        System.debug('Under_SS_Secondary_OrderId' + Under_SS_Secondary_OrderId + 
                     'Secondary_OrderId' + Secondary_OrderId + 
                     'Under_SS_Distributor_ID__c' + order.Under_SS_Distributor_ID__c);

        List<Order__c> underSSorder = [SELECT Under_SS_Distributor_ID__c FROM Order__c WHERE Id = :order.Id];
        Id underSSOrderId;
        if (!underSSorder.isEmpty()) {
            underSSOrderId = underSSorder[0].Under_SS_Distributor_ID__c;
        }

        InvoiceData oInvData = new InvoiceData();
        try {
            if (order == null || order.Id == null) {
                oInvData.message = 'No Order found! Invoice cannot be generated!';
                return oInvData;
            } else if (orderItemsList == null || orderItemsList.isEmpty()) {
                oInvData.message = 'No Order Line Items found! Invoice cannot be generated!';
                return oInvData;
            } else if (order.Account__c == null && (order.RecordTypeId == Secondary_OrderId || order.RecordTypeId == Counter_OrderId)) {
                oInvData.message = 'Retailer information missing on Order to generate Invoice.';
                return oInvData;
            } else if (underSSOrderId == null && order.RecordTypeId == Under_SS_Secondary_OrderId) {
                oInvData.message = 'Under SS information missing on Order to generate Invoice.';
                return oInvData;
            }

            User loggedInUser = [SELECT Id, AccountId FROM User WHERE Id = :UserInfo.getUserId()];
            if (loggedInUser.AccountId == null) {
                System.debug('No AccountId found for the logged-in user.');
            }

            List<User> dmsUserList = [
                SELECT Id, Name, CompanyName, Phone, MobilePhone, Email, 
                       FullPhotoUrl, SmallPhotoUrl, MediumPhotoUrl,
                       GSTIN__c, PAN_Number__c, Invoice_Number_Prefix__c, 
                       Invoice_Start_Number__c, State, Notes__c,
                       Bank_Name__c, Bank_Account_Number__c, IFSC_Code__c, 
                       UPI_ID__c, UPI_QR_CODE__c,
                       Contact.Account.BillingStreet, Contact.Account.BillingCity,
                       Contact.Account.BillingState, Contact.Account.BillingPostalCode,
                       Contact.Account.BillingCountry, Terms_and_Conditions__c, 
                       Contact.AccountId, Contact.Account.Name, AccountId, 
                       Primary_Distributor__c,
                       Contact.Account.Phone_1__c, Contact.Account.FSSAI__c, 
                       Contact.Account.Primary_State__c
                FROM User
                WHERE AccountId = :loggedInUser.AccountId
                AND Primary_Distributor__c = true
                LIMIT 1
            ];

            User distributor = dmsUserList.size() == 1 ? dmsUserList[0] : null;

            Account retailer = new Account();
            if (order.Account__c != null && (order.RecordTypeId == Secondary_OrderId || order.RecordTypeId == Counter_OrderId)) {
                retailer = RetailerAccountHandler.getRetailerAccount(order.Account__c);
            } else if (underSSOrderId != null && order.RecordTypeId == Under_SS_Secondary_OrderId) {
                retailer = RetailerAccountHandler.getUnderSSAccount(underSSOrderId);
                System.debug('Supriya retailer' + retailer);
            }

            if (retailer == null) {
                oInvData.message = 'Error fetching Retailer/Under SS information, Contact System Administrator.';
                return null;
            } else if (distributor == null) {
                oInvData.message = 'Error fetching Distributor information, Contact System Administrator to make you as a primary distributor.';
                return oInvData;
            } else if (distributor.Invoice_Number_Prefix__c == null) {
                oInvData.message = 'Update the "Invoice Number Prefix" in your Profile, to continue creating new Invoices!';
                return oInvData;
            } else if (distributor.Invoice_Start_Number__c == null) {
                oInvData.message = 'Update the "Invoice Start Number" in your Profile, to continue creating new Invoices!';
                return oInvData;
            }

            String distState = String.isNotBlank(distributor.Contact.Account.Primary_State__c) ? distributor.Contact.Account.Primary_State__c : '';
            String rtlrState = resolveBuyerState(order, retailer, Counter_OrderId);
            String taxComp   = (String.isNotBlank(distState) && String.isNotBlank(rtlrState) &&
                                distState.equalsIgnoreCase(rtlrState)) ? 'state matching' : 'state not matching';

            // Creates invoice WITHOUT invoice number — assigned at save time
            Invoice__c invoice = createNewInvoice(
                order,
                distributor.Contact.AccountId,
                distributor.Invoice_Number_Prefix__c,
                Integer.valueOf(distributor.Invoice_Start_Number__c),
                taxComp,
                distState
            );

            // Fetch product-level discounts
            Map<String, Decimal> productDiscountMap = new Map<String, Decimal>();
            List<Discount__c> prodDiscounts = new List<Discount__c>();

            if (order.RecordTypeId == Secondary_OrderId && order.Account__c != null) {
                prodDiscounts = [
                    SELECT Product__c, Product_Code__c, Discount_Percentage__c
                    FROM Discount__c
                    WHERE Product__c != NULL
                    AND Account__c = :order.Account__c
                    AND Start_Date__c <= :System.today()
                    AND End_Date__c >= :System.today()
                ];
            } else if (order.RecordTypeId == Under_SS_Secondary_OrderId && underSSOrderId != null) {
                prodDiscounts = [
                    SELECT Product__c, Product_Code__c, Discount_Percentage__c
                    FROM Discount__c
                    WHERE Product__c != NULL
                    AND Account__c = :underSSOrderId
                    AND Start_Date__c <= :System.today()
                    AND End_Date__c >= :System.today()
                ];
            }

            System.debug('prodDiscounts:- ' + prodDiscounts);
            if (!prodDiscounts.isEmpty()) {
                for (Discount__c pd : prodDiscounts) {
                    if (pd.Product__c != null) {
                        System.debug('pd.Discount_Percentage__c:- ' + pd.Discount_Percentage__c);
                        productDiscountMap.put(pd.Product__c, pd.Discount_Percentage__c);
                    }
                }
            }

            List<Object> invItems   = new List<Object>();
            List<Invoice__c> invoiceList = fetchOrderInvoices(order.Id);

            if (invoiceList == null) {
                System.debug('***Inside No Invoice Found***');
                invItems = createNewInvoiceItems(orderItemsList, null, productDiscountMap);
                System.debug('***Inside No Invoice Found*** ' + invoice + ' ' + invItems.size() + ' ' + invItems);
            } else {
                System.debug('***Inside Invoice Found***');
                Set<Id> invIdSet = new Set<Id>();
                for (Invoice__c oInv : invoiceList) {
                    invIdSet.add(oInv.Id);
                }
                Invoice_Line_Item__c[] iliLst = fetchInvLineItems(invIdSet);
                if (iliLst == null) {
                    invItems = createNewInvoiceItems(orderItemsList, null, productDiscountMap);
                    System.debug('***Inside Invoice Found but no line items***' + invItems.size() + ' ' + invItems);
                } else {
                    Map<String, Integer> iliProdMap = new Map<String, Integer>();
                    for (Invoice_Line_Item__c oILI : iliLst) {
                        if (oILI.Invoice__r.Status__c != 'Draft') {
                            Integer quantity = oILI.Quantity__c != null ? Integer.valueOf(oILI.Quantity__c) : 0;
                            if (!iliProdMap.containsKey(oILI.Product__c)) {
                                iliProdMap.put(oILI.Product__c, quantity);
                            } else {
                                iliProdMap.put(oILI.Product__c, iliProdMap.get(oILI.Product__c) + quantity);
                            }
                        }
                    }
                    invItems = createNewInvoiceItems(orderItemsList, iliProdMap, productDiscountMap);
                    System.debug('***Inside Invoice Found and line items***' + iliProdMap.size() + ' ' + iliProdMap);
                }
            }

            oInvData.dmsUser             = distributor;
            oInvData.retailerAccount     = retailer;
            oInvData.invoice             = invoice;
            oInvData.invoiceItems        = invItems;
            oInvData.message             = distributor == null ? 'Error getting your profile details, please contact system admin!' :
                                           retailer == null    ? 'Error getting retailer details, please contact system admin!' :
                                           invoice == null     ? 'Error creating new Invoice, please contact system admin!' :
                                           invItems == null    ? 'Order fullfilled. Try with different order!' :
                                           'Success';
            oInvData.valueSchemeId       = order.Value_Scheme_Applied__c;
            oInvData.valueSchemeName     = valueSchemeName;
            oInvData.valueSchemeDiscount = order.Value_Scheme_Discount__c;

            System.debug('oInvData*** ' + oInvData);
            return oInvData;

        } catch (Exception e) {
            System.debug('Exception***' + e.getMessage() + ' ' + e.getLineNumber() + ' ' + e.getCause());
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // fetchOrderInvoices — unchanged
    // ─────────────────────────────────────────────────────────────────────────
    public static List<Invoice__c> fetchOrderInvoices(Id orderId) {
        String queryStr                = 'SELECT ' + invoiceFields + ' FROM Invoice__c WHERE Order__c = :orderId';
        Map<String, Object> bindVarMap = new Map<String, Object>{'orderId' => orderId};
        System.debug('fetchOrderInvoices queryStr*** ' + queryStr);
        List<Invoice__c> invList       = Utility.soqlQuery(queryStr, bindVarMap, AccessLevel.USER_MODE);
        System.debug('fetchOrderInvoices invoice*** ' + invList.size() + ' ' + invList);
        return invList.size() > 0 ? invList : null;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // fetchInvLineItems — unchanged
    // ─────────────────────────────────────────────────────────────────────────
    public static List<Invoice_Line_Item__c> fetchInvLineItems(Set<Id> invoiceIdSet) {
        String queryStr = 'SELECT ' + invoiceItemFields + 
                          ' FROM Invoice_Line_Item__c WHERE Invoice__c IN: invoiceIdSet' +
                          ' ORDER BY Product__r.Product_Brand__c, Product__r.Name ASC';
        Map<String, Object> bindVarMap  = new Map<String, Object>{'invoiceIdSet' => invoiceIdSet};
        System.debug('fetchInvLineItems queryStr*** ' + queryStr);
        List<Invoice_Line_Item__c> invItemList = Utility.soqlQuery(queryStr, bindVarMap, AccessLevel.USER_MODE);
        System.debug('fetchInvLineItems invItemList*** ' + invItemList.size() + ' ' + invItemList);
        return invItemList.size() > 0 ? invItemList : null;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // resolveBuyerState — NEW
    // For Counter Orders, "retailer" is always the same shared placeholder Account
    // (Name = 'Counter Sales Customer') used for every single walk-in customer — it has
    // no meaningful Primary_State__c of its own. The actual one-time customer's state is
    // captured directly on the Order (State__c), entered on the Contact Information step
    // of the Counter Order flow. So for Counter Orders we read State__c off the Order
    // (re-queried fresh, not trusted from the client-supplied `order` param) instead of
    // the placeholder retailer Account's state. Regular Secondary Orders (and Under_SS
    // Secondary Orders) keep using the real retailer Account's Primary_State__c, since
    // that account genuinely represents a specific retailer with its own state.
    // This directly fixes a bug where the Counter Order cart screen (which reads the
    // typed-in customer state) showed CGST/SGST, while the invoice — reading the blank
    // placeholder Account's state instead — always fell back to IGST.
    // ─────────────────────────────────────────────────────────────────────────
    private static String resolveBuyerState(Order__c order, Account retailer, Id counterOrderId) {
        if (order.RecordTypeId == counterOrderId) {
            List<Order__c> freshOrder = [SELECT State__c FROM Order__c WHERE Id = :order.Id];
            return (!freshOrder.isEmpty() && String.isNotBlank(freshOrder[0].State__c)) ? freshOrder[0].State__c : '';
        }
        return (retailer != null && String.isNotBlank(retailer.Primary_State__c)) ? retailer.Primary_State__c : '';
    }

    // ─────────────────────────────────────────────────────────────────────────
    // createNewInvoice — MODIFIED
    // Invoice_Number__c intentionally left null here.
    // Number is assigned only inside saveInvoice() at actual save time,
    // preventing gaps when users cancel without saving.
    // calculateNextInvoiceNumber() is no longer called here.
    // ─────────────────────────────────────────────────────────────────────────
    public static Invoice__c createNewInvoice(Order__c order, Id dmsUserAccountId, String invPrefix, Integer startNum, String taxComp, String state) {
        System.debug('Taxsupriya' + taxComp + 'State' + state);

        Id Under_SS_Secondary_OrderId = Schema.SObjectType.Order__c.getRecordTypeInfosByDeveloperName().get('Under_SS_Secondary_Order').getRecordTypeId();
        Id Secondary_OrderId          = Schema.SObjectType.Order__c.getRecordTypeInfosByDeveloperName().get('Secondary_Order').getRecordTypeId();
        Id Counter_OrderId            = Schema.SObjectType.Order__c.getRecordTypeInfosByDeveloperName().get('Counter_Order').getRecordTypeId();

        Id underSSOrderId;
        Id underSS_OrdId;
        Date today = System.today();

        List<Discount__c> discountList = new List<Discount__c>();
        Discount__c discount1Obj;
        Decimal discountPercent = 0;

        // Price_Type__c is re-queried fresh here (not trusted from the client-supplied
        // `order` parameter) so this check is reliable regardless of whether the caller's
        // in-memory Order__c happens to carry that field.
        List<Order__c> underSSorder = [SELECT Under_SS_Distributor_ID__c, Under_SS_Order__c, Price_Type__c, Sale_Type__c FROM Order__c WHERE Id = :order.Id];
        if (!underSSorder.isEmpty()) {
            underSSOrderId = underSSorder[0].Under_SS_Distributor_ID__c;
            underSS_OrdId  = underSSorder[0].Under_SS_Order__c;
        }
        String freshPriceType = !underSSorder.isEmpty() ? underSSorder[0].Price_Type__c : null;
        String freshSaleType  = !underSSorder.isEmpty() ? underSSorder[0].Sale_Type__c  : null;

        Id recTypeId;
        if (order.RecordTypeId == Secondary_OrderId || order.RecordTypeId == Counter_OrderId) {
            recTypeId    = Schema.SObjectType.Invoice__c.getRecordTypeInfosByDeveloperName().get('Secondary_Invoice').getRecordTypeId();
            discountList = [
                SELECT Id, Account__c, Discount_Percentage__c 
                FROM Discount__c 
                WHERE Product__c = NULL 
                AND Account__c = :order.Account__c 
                AND Start_Date__c <= :today 
                AND End_Date__c >= :today 
                LIMIT 1
            ];
            if (!discountList.isEmpty()) {
                discount1Obj = discountList[0];
                if (discount1Obj.Discount_Percentage__c != null) {
                    discountPercent = discount1Obj.Discount_Percentage__c;
                }
            }
        } else if (order.RecordTypeId == Under_SS_Secondary_OrderId) {
            recTypeId    = Schema.SObjectType.Invoice__c.getRecordTypeInfosByDeveloperName().get('Secondary_Invoice_Under_SS').getRecordTypeId();
            discountList = [
                SELECT Id, Account__c, Discount_Percentage__c 
                FROM Discount__c 
                WHERE Product__c = NULL 
                AND Account__c = :underSSOrderId 
                AND Start_Date__c <= :today 
                AND End_Date__c >= :today 
                LIMIT 1
            ];
            System.debug('discountList' + discountList);
            if (!discountList.isEmpty()) {
                discount1Obj = discountList[0];
                if (discount1Obj.Discount_Percentage__c != null) {
                    discountPercent = discount1Obj.Discount_Percentage__c;
                }
            }
        }

        Decimal sGST = 0;
        Decimal cGST = 0;
        Decimal iGST = 0;
        String taxInfo;
        Order_tax_value__c tax = Order_tax_value__c.getInstance('General GST Settings');
        if (taxComp == 'state matching') {
            sGST    = tax.SGST__c;
            cGST    = tax.CGST__c;
            taxInfo = 'State Tax Applied';
        } else {
            iGST    = tax.IGST__c;
            taxInfo = 'Central Tax Applied.\n\nReason: Either eligible for Central Tax or State Tax not found';
        }

        // Legal requirement: MRP is tax-inclusive under Indian Legal Metrology rules — the
        // price already contains GST. Per Finance's clarification, GST must still be
        // calculated and shown on the invoice (for GST return filing) — it must NOT be
        // zeroed out. Instead it is EXTRACTED from within the MRP (taxable value = amount
        // / (1 + rate%)) so the Net Amount lands back on the original MRP-based amount
        // instead of adding GST on top of it. That extraction happens per-line in
        // InvoiceLineItemTrigger.trigger, gated on Origin__c == 'Counter Invoice' &&
        // Price_Type__c == 'MRP'. Here we keep the normal computed rate (no zeroing) —
        // the rate fields (SGST__c/CGST__c/IGST__c) are just the applicable percentage,
        // same as Dealer Price; only the downstream per-line formula differs.
        //
        // IMPORTANT: per explicit business decision, MRP-extraction applies ONLY to
        // Counter Orders/Invoices. Regular Secondary Orders (and Under_SS Secondary
        // Orders) must always be taxed normally (added on top) regardless of
        // Price_Type__c — do not touch that flow.
        Boolean isMrp = freshPriceType == 'MRP' && order.RecordTypeId == Counter_OrderId;
        if (isMrp) {
            taxInfo = 'MRP is tax-inclusive — GST shown is extracted from the MRP, not added on top.';
        }

        // ── KEY CHANGE: Invoice_Number__c = null, Name = temp placeholder ──
        // Real invoice number is assigned in saveInvoice() only when the user
        // actually confirms and saves — preventing gaps from cancellations.
        Invoice__c oInv = new Invoice__c(
            Order__c               = order.Id,
            Name                   = 'DRAFT-' + order.Id,  // temp placeholder
            Distributor_Account__c = order.AccountId__c,
            Retailer_Account__c    = (order.Account__c != null) ? order.Account__c : null,
            Under_SS__c            = (underSSOrderId != null) ? underSSOrderId : null,
            Under_SS_Invoice__c    = (underSS_OrdId != null) ? underSS_OrdId : null,
            Status__c              = 'Draft',
            RecordTypeId           = recTypeId,
            Invoice_Number__c      = null,     // ← assigned at save time only
            Invoice_Date__c        = System.today(),
            SGST__c                = sGST,
            CGST__c                = cGST,
            IGST__c                = iGST,
            Tax_Information__c     = taxInfo,
            Discount_1__c          = discountPercent,
            Price_Type__c          = freshPriceType,
            Sale_Type__c           = freshSaleType,
            Origin__c               = (order.RecordTypeId == Counter_OrderId) ? 'Counter Invoice' : null
        );
        return oInv;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // createNewInvoiceItems — unchanged
    // ─────────────────────────────────────────────────────────────────────────
    public static List<Object> createNewInvoiceItems(
            List<Order_Line_Item__c> orderItemList,
            Map<String, Integer> invLineItemProdMap,
            Map<String, Decimal> productDiscountMap) {

        List<Object> invLineItemsList = new List<Object>();
        User loggedInUser = [SELECT Id, AccountId FROM User WHERE Id = :UserInfo.getUserId()];

        Set<String> productIds = new Set<String>();
        for (Order_Line_Item__c oOLI : orderItemList) {
            if (oOLI.Products__c != null) {
                productIds.add(oOLI.Products__c);
            }
        }

        Map<String, Inventory__c> inventoryMap = new Map<String, Inventory__c>();
        if (!productIds.isEmpty()) {
            for (Inventory__c inv : [
                SELECT Product__c, Quantity_in_hand__c
                FROM Inventory__c
                WHERE Product__c IN :productIds
                AND Distributor_Name__r.Id = :loggedInUser.AccountId
            ]) {
                inventoryMap.put(inv.Product__c, inv);
            }
        }

        Map<Id, Product__c> productDetailMap = new Map<Id, Product__c>();
        if (!productIds.isEmpty()) {
            for (Product__c prod : [
                SELECT Id, MRP__c, Per_Pieces__c, Product_Brand__c
                FROM Product__c
                WHERE Id IN :productIds
            ]) {
                productDetailMap.put(prod.Id, prod);
            }
        }

        // Client-constructed Order_Line_Item__c records passed in from the LWC don't carry
        // the Quantity_Scheme__r relationship, so a fresh (never-yet-saved) invoice built
        // from an order wouldn't otherwise know a Purchase Quantity Discount scheme's name/
        // %/type until after the first Save + reload. Fetch it here so schemeDiscountAmt can
        // be computed correctly (and "Scheme Applied" shown) even on the very first preview.
        Set<Id> schemeIds = new Set<Id>();
        for (Order_Line_Item__c oOLI : orderItemList) {
            if (oOLI.Quantity_Scheme__c != null) {
                schemeIds.add(oOLI.Quantity_Scheme__c);
            }
        }
        Map<Id, Scheme__c> schemeDetailMap = new Map<Id, Scheme__c>();
        if (!schemeIds.isEmpty()) {
            for (Scheme__c s : [
                SELECT Id, Name, Discount_Percentage__c, Type__c
                FROM Scheme__c
                WHERE Id IN :schemeIds
            ]) {
                schemeDetailMap.put(s.Id, s);
            }
        }

        for (Order_Line_Item__c oOLI : orderItemList) {
            if (oOLI.Products__c != null) {
                Map<String, Object> fieldMap = new Map<String, Object>();

                Integer invQuantity = (invLineItemProdMap != null && invLineItemProdMap.containsKey(oOLI.Products__c))
                    ? invLineItemProdMap.get(oOLI.Products__c) : 0;
                Integer ordQuantity = Integer.valueOf(oOLI.Ordered_Quantity__c == null
                    ? 0
                    : (invQuantity > 0
                        ? Math.max(0, oOLI.Ordered_Quantity__c - invQuantity)
                        : oOLI.Ordered_Quantity__c));

                if (ordQuantity == 0) continue;

                Product__c prodDetail = productDetailMap.get(oOLI.Products__c);
                Decimal prodMRP       = (prodDetail != null) ? prodDetail.MRP__c : null;
                Decimal perPieces     = (prodDetail != null) ? prodDetail.Per_Pieces__c : null;
                Boolean todEligible   = isTodEligible(prodMRP, perPieces);
                System.debug('TOD eligibility for product ' + oOLI.Products__c
                             + ' | MRP=' + prodMRP + ' | Pieces=' + perPieces
                             + ' | Eligible=' + todEligible);

                Boolean isPromo = oOLI.Is_Promotional__c == true;
                Decimal unitPrice = oOLI.Product_Price__c != null ? oOLI.Product_Price__c : 0;
                Decimal discountPercent = 0;

                // Purchase Quantity Discount: the cart/order page now stores
                // Product_Price__c ALREADY reduced by the scheme % (Rate must visibly
                // drop there per business requirement). The Invoice Rate must still show
                // the FULL undiscounted price with the discount broken out separately
                // into Scheme_Discount_Amount__c below — so reconstruct the full price
                // here using the scheme's Discount_Percentage__c before it's used as
                // Price__c or as the base for the scheme discount amount calculation.
                Scheme__c cartAppliedScheme = (!isPromo && oOLI.Quantity_Scheme__c != null)
                    ? schemeDetailMap.get(oOLI.Quantity_Scheme__c) : null;
                Boolean isQtyDiscountScheme = cartAppliedScheme != null
                    && cartAppliedScheme.Type__c == 'Purchase Quantity Discount';
                if (isQtyDiscountScheme) {
                    Decimal schemePercentForPrice = cartAppliedScheme.Discount_Percentage__c != null
                        ? cartAppliedScheme.Discount_Percentage__c : 0;
                    if (schemePercentForPrice > 0 && schemePercentForPrice < 100) {
                        unitPrice = (unitPrice / (1 - (schemePercentForPrice / 100))).setScale(2, RoundingMode.HALF_UP);
                    }
                }

                if (isPromo) {
                    discountPercent = (oOLI.Discount_Percentage__c != null) ? oOLI.Discount_Percentage__c : 100;
                } else if (todEligible) {
                    if (productDiscountMap != null && productDiscountMap.containsKey(oOLI.Products__c)) {
                        discountPercent = productDiscountMap.get(oOLI.Products__c);
                    }
                }

                Decimal discountAmount = unitPrice * discountPercent / 100;
                Decimal netPrice       = unitPrice - discountAmount;
                Decimal totalAmount    = unitPrice * ordQuantity;
                Decimal netAmount      = netPrice * ordQuantity;

                fieldMap.put('Is_Promotional__c',          isPromo);
                fieldMap.put('Quantity_Scheme_Applied__c',  oOLI.Quantity_Scheme__c);

                // Purchase Quantity Discount scheme — computed fresh here (same forward-math
                // shape as SchemeEvaluationService/secondaryInvoice.js) so it's correct on the
                // very first preview, before any Save + reload would otherwise populate it via
                // the real Quantity_Scheme_Applied__r SOQL relationship.
                if (!isPromo && oOLI.Quantity_Scheme__c != null && schemeDetailMap.containsKey(oOLI.Quantity_Scheme__c)) {
                    Scheme__c appliedScheme = schemeDetailMap.get(oOLI.Quantity_Scheme__c);
                    if (appliedScheme.Type__c == 'Purchase Quantity Discount') {
                        Decimal schemePercent = appliedScheme.Discount_Percentage__c != null ? appliedScheme.Discount_Percentage__c : 0;
                        Decimal schemeDiscountAmt = (unitPrice * ordQuantity * schemePercent / 100).setScale(2, RoundingMode.HALF_UP);
                        fieldMap.put('Scheme_Discount_Amount__c', schemeDiscountAmt);

                        Map<String, Object> schemeInfo = new Map<String, Object>();
                        schemeInfo.put('Name', appliedScheme.Name);
                        schemeInfo.put('Discount_Percentage__c', appliedScheme.Discount_Percentage__c);
                        schemeInfo.put('Type__c', appliedScheme.Type__c);
                        fieldMap.put('Quantity_Scheme_Applied__r', schemeInfo);
                    }
                }

                if (isPromo && oOLI.Parent_Product__c != null) {
                    fieldMap.put('Parent_Product__c', oOLI.Parent_Product__c);
                }

                fieldMap.put('Product__c',           oOLI.Products__c);
                fieldMap.put('ProductName',           oOLI.Products__r.Name);
                fieldMap.put('Quantity__c',           ordQuantity);
                fieldMap.put('Price__c',              unitPrice);
                fieldMap.put('Total_Amount__c',       totalAmount);
                fieldMap.put('Discount_Percentage__c', discountPercent);
                fieldMap.put('Net_Price__c',          netPrice.setScale(2));
                fieldMap.put('Net_Amount__c',         netAmount.setScale(2));
                fieldMap.put('MRP__c',                oOLI.Products__r.MRP__c);
                fieldMap.put('isTodEligible',         todEligible);
                // Needed so a Flat Discount Value Scheme scoped to a Brand (via
                // Scheme_Applicability__c) can be evaluated from live invoice line data —
                // see buildCartLinesForInvoice() usage in getvalueSchemeFromOrder()/
                // getAppliedValueSchemeForOrder() below.
                fieldMap.put('Product_Brand__c',      prodDetail != null ? prodDetail.Product_Brand__c : null);

                Decimal currentStock = inventoryMap.containsKey(oOLI.Products__c)
                    ? inventoryMap.get(oOLI.Products__c).Quantity_in_hand__c
                    : 0;
                fieldMap.put('CurrentStock', currentStock);

                System.debug('fieldMap*** ' + fieldMap);
                invLineItemsList.add(JSON.deserializeUntyped(JSON.serialize(fieldMap)));
            }
        }

        System.debug('invLineItemsList*** ' + invLineItemsList.size());
        return invLineItemsList.size() > 0 ? invLineItemsList : null;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // calculateNextInvoiceNumber — KEPT for backward compatibility only.
    // No longer called internally. Invoice numbers are now generated via
    // generateNextInvoiceNumber() inside saveInvoice().
    // ─────────────────────────────────────────────────────────────────────────
    public static String calculateNextInvoiceNumber(Id dmsUserAccountId, String invPrefix, Integer startNum) {
        System.debug('***calculateNextInvoiceNumber is deprecated. Use generateNextInvoiceNumber() instead.***');
        return generateNextInvoiceNumber(dmsUserAccountId);
    }

    public static String getTaxComponent(String distributorState, String retailerState) {
        System.debug('distributorState' + distributorState + 'retailerState' + retailerState);
        String stateCode = 'KA';
        String state     = 'Karnataka';
        String distState = distributorState.equalsIgnoreCase(stateCode) || distributorState.equalsIgnoreCase(state) ? state : distributorState;
        String rtlrState = retailerState.equalsIgnoreCase(stateCode)    || retailerState.equalsIgnoreCase(state)    ? state : retailerState;
        return distState.equalsIgnoreCase(rtlrState) ? 'State Tax' : 'Central Tax';
    }

    // ─────────────────────────────────────────────────────────────────────────
    // saveInvoiceAndLineItems — unchanged signature, saveInvoice handles number
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static InvoiceData saveInvoiceAndLineItems(Invoice__c invoice, String invItemList, List<Id> deletedItemIds) {
        try {
            List<Invoice_Line_Item__c> invList =
                (List<Invoice_Line_Item__c>) JSON.deserialize(invItemList, List<Invoice_Line_Item__c>.class);

            InvoiceData oInvData = new InvoiceData();
            System.debug('save invoice***' + invoice);
            System.debug('save invoice line items***' + invList.size() + invList);
            System.debug('deletedItemIds' + deletedItemIds);

            if (!deletedItemIds.isEmpty()) {
                deleteInvoiceLineItem(deletedItemIds);
            }

            oInvData.invoice      = saveInvoice(invoice);
            oInvData.invoiceItems = saveInvoiceItems(oInvData.invoice.Id, invList);
            return oInvData;

        } catch (Exception e) {
            System.debug('Enter Catch Block:- ' + e.getMessage());
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // saveInvoice — MODIFIED (core change)
    //
    // 1. If Invoice_Number__c is blank (new invoice being saved for first time):
    //    → Call generateNextInvoiceNumber() which uses FOR UPDATE on
    //      Invoice_Sequence__c to safely assign next sequential number.
    // 2. If Invoice_Number__c already exists (re-save / edit of saved invoice):
    //    → Skip number generation entirely. No double increment.
    // 3. Reset sequence flag is handled inside generateNextInvoiceNumber().
    // ─────────────────────────────────────────────────────────────────────────
    public static Invoice__c saveInvoice(Invoice__c invoice) {
        invoice.Discount_1__c = null;

        // Only generate invoice number if not already assigned
        // This guard prevents re-incrementing on edits to saved invoices
        if (String.isBlank(invoice.Invoice_Number__c)) {
            if (invoice.Distributor_Account__c == null) {
                throw new AuraHandledException(
                    'Distributor Account missing on Invoice. Cannot generate invoice number.'
                );
            }
            String invoiceNumber      = generateNextInvoiceNumber(invoice.Distributor_Account__c);
            invoice.Invoice_Number__c = invoiceNumber;
            invoice.Name              = invoiceNumber;
        }

        upsert invoice;
        return invoice;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // saveInvoiceItems — unchanged
    // ─────────────────────────────────────────────────────────────────────────
    public static List<Object> saveInvoiceItems(Id invoiceId, List<Invoice_Line_Item__c> invItemList) {
        System.debug('before save invItemList*** ' + invItemList.size() + ' ' + invItemList);
        for (Invoice_Line_Item__c oLineItem : invItemList) {
            if (oLineItem.Invoice__c == null) {
                oLineItem.Invoice__c = invoiceId;
            }
        }
        upsert invItemList;
        invItemList = fetchInvLineItems(new Set<Id>{invoiceId});
        return invItemList;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getProductName — unchanged
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static ProductWrapper getProductName(Id productId, Id accountId) {
        System.debug('productId:- ' + productId);
        System.debug('accountId:- ' + accountId);
        try {
            String  productName     = '';
            Decimal discountPercent = 0;
            Date    today           = Date.today();

            Product__c product = [
                SELECT Name, MRP__c, Per_Pieces__c
                FROM Product__c
                WHERE Id = :productId
                LIMIT 1
            ];
            productName = product.Name;

            Boolean todEligible = isTodEligible(product.MRP__c, product.Per_Pieces__c);
            System.debug('TOD eligible (getProductName): ' + todEligible
                         + ' | MRP=' + product.MRP__c + ' | Pieces=' + product.Per_Pieces__c);

            if (todEligible) {
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
                System.debug('TOD not eligible for product ' + productId + '. No discount applied.');
            }

            return new ProductWrapper(productName, discountPercent, todEligible);

        } catch (Exception e) {
            throw new AuraHandledException('Error fetching product details: ' + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getMRPByProduct — unchanged
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static Decimal getMRPByProduct(String productId) {
        if (productId == null) { return 0; }
        Product__c product = [SELECT MRP__c FROM Product__c WHERE Id = :productId LIMIT 1];
        return (product != null && product.MRP__c != null) ? product.MRP__c : 0;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getPriceByProduct — unchanged
    // ─────────────────────────────────────────────────────────────────────────
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
            pEntry = [
                SELECT PTD__c FROM Price_Book_Entry__c
                WHERE Product__c = :productId
                AND Region__r.Name = :state
                AND Type__c = 'Direct Distributor'
                LIMIT 1
            ];
            if (!pEntry.isEmpty()) { price = pEntry[0].PTD__c; }
        } else if (accountType == 'Retailer') {
            pEntry = [
                SELECT PTR__c FROM Price_Book_Entry__c
                WHERE Product__c = :productId
                AND Region__r.Name = :state
                AND Type__c = 'Retailer'
                LIMIT 1
            ];
            if (!pEntry.isEmpty()) { price = pEntry[0].PTR__c; }
        }

        User loggedInUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        List<Inventory__c> invList = [
            SELECT Quantity_in_hand__c FROM Inventory__c
            WHERE Product__c = :productId
            AND Distributor_Name__c = :loggedInUser.AccountId
            LIMIT 1
        ];
        if (!invList.isEmpty() && invList[0].Quantity_in_hand__c != null) {
            stock = invList[0].Quantity_in_hand__c;
        }

        result.put('price', price);
        result.put('stockInHand', stock);
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getStockByProducts — unchanged
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static Map<Id, Decimal> getStockByProducts(List<Id> productIds) {
        Map<Id, Decimal> stockMap = new Map<Id, Decimal>();
        User loggedInUser = [SELECT Id, AccountId FROM User WHERE Id = :UserInfo.getUserId()];
        if (productIds == null || productIds.isEmpty()) { return stockMap; }
        for (Inventory__c inv : [
            SELECT Product__c, Quantity_in_hand__c
            FROM Inventory__c
            WHERE Product__c IN :productIds
            AND Distributor_Name__r.Id = :loggedInUser.AccountId
        ]) {
            stockMap.put(inv.Product__c, inv.Quantity_in_hand__c);
        }
        return stockMap;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // deleteInvoiceLineItem — unchanged
    // ─────────────────────────────────────────────────────────────────────────
    public static void deleteInvoiceLineItem(List<Id> invoiceLineItemId) {
        System.debug('InvoiceLineItem Id: ' + invoiceLineItemId);
        try {
            if (invoiceLineItemId == null || invoiceLineItemId.isEmpty()) {
                throw new AuraHandledException('Invoice Line Item Id(s) are required.');
            }
            List<Invoice_Line_Item__c> invoiceLineItemList = [
                SELECT Id FROM Invoice_Line_Item__c WHERE Id IN :invoiceLineItemId
            ];
            delete invoiceLineItemList;
        } catch (Exception ex) {
            System.debug('Error deleting Invoice Line Item: ' + ex.getMessage());
            throw new AuraHandledException('Unable to delete the Invoice Line Item(s): ' + ex.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getProductsWithStock — unchanged
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<ProductSearchDTO> getProductsWithStock(String searchKey, String searchBy) {
        try {
            if (String.isBlank(searchKey)) { return new List<ProductSearchDTO>(); }

            User loggedInUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            if (loggedInUser == null || loggedInUser.AccountId == null) { return new List<ProductSearchDTO>(); }
            if (String.isBlank(searchBy)) { searchBy = 'Name'; }

            List<Inventory__c> invList = new List<Inventory__c>();

            if (searchBy == 'Code') {
                String codeSearchPattern = String.escapeSingleQuotes(searchKey.trim()) + '%';
                invList = [
                    SELECT Product__c, Product__r.Name, Product__r.Category_Code__c, Quantity_in_hand__c
                    FROM Inventory__c
                    WHERE Distributor_Name__c = :loggedInUser.AccountId
                    AND Quantity_in_hand__c > 0
                    AND Product__r.Category_Code__c LIKE :codeSearchPattern
                    ORDER BY Product__r.Name
                    LIMIT 50
                ];
            } else {
                String searchPattern = '%' + String.escapeSingleQuotes(searchKey) + '%';
                invList = [
                    SELECT Product__c, Product__r.Name, Quantity_in_hand__c
                    FROM Inventory__c
                    WHERE Distributor_Name__c = :loggedInUser.AccountId
                    AND Quantity_in_hand__c > 0
                    AND Product__r.Name LIKE :searchPattern
                    ORDER BY Product__r.Name
                    LIMIT 50
                ];
            }

            // Per-distributor product restriction (deny list).
            Set<Id> deniedProductIds = ProductRestrictionService.getDeniedProductIds(loggedInUser.AccountId);

            Map<Id, Decimal> productStock   = new Map<Id, Decimal>();
            Map<Id, String>  productNameMap = new Map<Id, String>();

            for (Inventory__c inv : invList) {
                if (inv.Product__c == null || deniedProductIds.contains(inv.Product__c)) continue;
                Decimal current = productStock.containsKey(inv.Product__c) ? productStock.get(inv.Product__c) : 0;
                Decimal add     = inv.Quantity_in_hand__c == null ? 0 : inv.Quantity_in_hand__c;
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

    // ─────────────────────────────────────────────────────────────────────────
    // resolveBuyerFromOrder — unchanged
    // ─────────────────────────────────────────────────────────────────────────
    private static Map<String, Object> resolveBuyerFromOrder(Id orderId) {
        Id secondaryRT = Schema.SObjectType.Order__c.getRecordTypeInfosByDeveloperName().get('Secondary_Order').getRecordTypeId();
        Id underSSRT   = Schema.SObjectType.Order__c.getRecordTypeInfosByDeveloperName().get('Under_SS_Secondary_Order').getRecordTypeId();

        Order__c ord = [
            SELECT Id, RecordTypeId, Account__c,
                   Account__r.Primary_State__c,
                   Under_SS_Order__r.AccountId__c,
                   Under_SS_Order__r.AccountId__r.Primary_State__c
            FROM Order__c
            WHERE Id = :orderId
            LIMIT 1
        ];

        Id     buyerAccountId;
        String buyerRegion;
        Boolean isUnderSS = false;

        if (ord.RecordTypeId == secondaryRT) {
            buyerAccountId = ord.Account__c;
            buyerRegion    = ord.Account__r.Primary_State__c;
            isUnderSS      = false;
        } else if (ord.RecordTypeId == underSSRT) {
            buyerAccountId = ord.Under_SS_Order__r.AccountId__c;
            buyerRegion    = ord.Under_SS_Order__r.AccountId__r.Primary_State__c;
            isUnderSS      = true;
        }

        if (buyerAccountId == null || String.isBlank(buyerRegion)) {
            throw new AuraHandledException('Unable to resolve Buyer Account / Region from Order');
        }

        return new Map<String, Object>{
            'buyerAccountId' => buyerAccountId,
            'buyerRegion'    => buyerRegion,
            'isUnderSS'      => isUnderSS
        };
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scheme methods — unchanged
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static List<QuantitySchemeModalWrapper> getqualitySchemeFromOrder(Id productId, Id orderId) {
        Map<String, Object> buyerInfo = resolveBuyerFromOrder(orderId);
        return SchemeEvaluationService.getqualityScheme(
            productId,
            (Id) buyerInfo.get('buyerAccountId'),
            (String) buyerInfo.get('buyerRegion'),
            (Boolean) buyerInfo.get('isUnderSS')
        );
    }

    @AuraEnabled
    public static List<CartProductWrapper.ProductWrapper> applyQuantitySchemeFromOrder(
            List<CartProductWrapper.ProductWrapper> cartItems,
            Id orderId,
            Id selectedSchemeId) {
        Map<String, Object> buyerInfo = resolveBuyerFromOrder(orderId);
        return SchemeEvaluationService.applyQuantityScheme(
            cartItems,
            (Id) buyerInfo.get('buyerAccountId'),
            (String) buyerInfo.get('buyerRegion'),
            selectedSchemeId,
            (Boolean) buyerInfo.get('isUnderSS')
        );
    }

    @AuraEnabled
    public static List<SchemeDetailsWrapper> getvalueSchemeFromOrder(Decimal totalAmount, Id orderId, String cartLinesJson) {
        Map<String, Object> buyerInfo = resolveBuyerFromOrder(orderId);

        // Prefer the LIVE cart lines the LWC sends (built from its current, possibly
        // user-edited invoice line items — see buildCartLinesForInvoice() in
        // secondaryInvoice.js) so a Flat Discount scheme scoped via
        // Scheme_Applicability__c (Product__c/Brand_Key__c) resolves against what the
        // invoice ACTUALLY shows right now, not the original Order as placed. Falling back
        // to re-querying Order_Line_Item__c only covers the (rare) case the caller has no
        // live line data yet — e.g. before the invoice items have loaded. Re-querying the
        // Order here previously meant quantity edits made on the invoice screen were
        // silently ignored: changing a line's quantity and re-applying kept resolving the
        // stale, pre-edit slab. See decision log, 2026-08-21.
        String linesJson = String.isNotBlank(cartLinesJson) ? cartLinesJson : null;
        if (linesJson == null) {
            List<SchemeEvaluationService.CartLineWrapper> fallbackLines = buildCartLinesForOrder(orderId);
            linesJson = fallbackLines == null ? null : JSON.serialize(fallbackLines);
        }

        return SchemeEvaluationService.getvalueScheme(
            totalAmount,
            linesJson,
            (Id) buyerInfo.get('buyerAccountId'),
            (String) buyerInfo.get('buyerRegion'),
            (Boolean) buyerInfo.get('isUnderSS')
        );
    }

    // Mirrors createSecondaryOrderComponentDms.js's buildCartLinesForSchemeEvaluation(),
    // just built server-side from Order_Line_Item__c instead of client-side cart state
    // (this Order-based invoice flow has no equivalent client-side cart array to read
    // from). Promotional/free lines are excluded, matching the client-side builder's
    // behavior (productListPrice > 0 gate).
    private static List<SchemeEvaluationService.CartLineWrapper> buildCartLinesForOrder(Id orderId) {
        List<Order_Line_Item__c> lines = [
            SELECT Products__c, Product_Price__c, Ordered_Quantity__c, Is_Promotional__c,
                   Products__r.Product_Brand__c
            FROM Order_Line_Item__c
            WHERE Order__c = :orderId
        ];
        if (lines.isEmpty()) {
            return null;
        }

        List<SchemeEvaluationService.CartLineWrapper> result = new List<SchemeEvaluationService.CartLineWrapper>();
        for (Order_Line_Item__c line : lines) {
            if (line.Is_Promotional__c == true || line.Products__c == null) {
                continue;
            }
            SchemeEvaluationService.CartLineWrapper w = new SchemeEvaluationService.CartLineWrapper();
            w.productId = line.Products__c;
            w.productBrand = line.Products__r != null ? line.Products__r.Product_Brand__c : null;
            Decimal qty = line.Ordered_Quantity__c != null ? line.Ordered_Quantity__c : 0;
            Decimal price = line.Product_Price__c != null ? line.Product_Price__c : 0;
            w.lineAmount = price * qty;
            result.add(w);
        }
        return result.isEmpty() ? null : result;
    }

    // Companion to getvalueSchemeFromOrder() above — used by applyValueSchemeOnInvoice()/
    // restoreValueSchemeThreshold() in secondaryInvoice.js so the ACTUAL applied discount
    // (Scheme_Slab__c-resolved for Flat Discount schemes) is used here too, instead of the
    // old getAppliedValueScheme(String) which only reads Scheme__c.Discount_Amount__c/
    // Discount_Percentage__c directly — those fields are blank for a Flat Discount scheme
    // (its discount lives on Scheme_Slab__c), so applying used to silently give 0 discount.
    @AuraEnabled
    public static AppliedValueSchemeWrapper getAppliedValueSchemeForOrder(
            Id valueSchemId, Id orderId, Decimal cartTotal, String cartLinesJson) {
        // See getvalueSchemeFromOrder() above — prefer the live cart lines the LWC sends
        // (reflecting any quantity edits made on the invoice screen) over re-querying the
        // original Order_Line_Item__c records, which was silently ignoring those edits.
        String linesJson = String.isNotBlank(cartLinesJson) ? cartLinesJson : null;
        if (linesJson == null) {
            List<SchemeEvaluationService.CartLineWrapper> fallbackLines = buildCartLinesForOrder(orderId);
            linesJson = fallbackLines == null ? null : JSON.serialize(fallbackLines);
        }
        return SchemeEvaluationService.getAppliedValueSchemeForCart(
            valueSchemId,
            cartTotal,
            linesJson
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Inner Classes — unchanged
    // ─────────────────────────────────────────────────────────────────────────
    public class InvoiceData {
        @AuraEnabled public User            dmsUser;
        @AuraEnabled public Account         retailerAccount;
        @AuraEnabled public Invoice__c      invoice;
        @AuraEnabled public List<Object>    invoiceItems;
        @AuraEnabled public String          message;
        @AuraEnabled public Map<Id, Decimal> stockByProduct;
        @AuraEnabled public Id              valueSchemeId;
        @AuraEnabled public String          valueSchemeName;
        @AuraEnabled public Decimal         valueSchemeDiscount;
    }

    public class ProductPriceWrapper {
        @AuraEnabled public Decimal mrp   { get; set; }
        @AuraEnabled public Decimal price { get; set; }
    }

    public class ProductWrapper {
        @AuraEnabled public String  name;
        @AuraEnabled public Decimal discount;
        @AuraEnabled public Boolean isTodEligible;

        public ProductWrapper(String name, Decimal discount, Boolean isTodEligible) {
            this.name          = name;
            this.discount      = discount;
            this.isTodEligible = isTodEligible;
        }
    }

    public class ProductSearchDTO {
        @AuraEnabled public Id      Id;
        @AuraEnabled public String  Name;
        @AuraEnabled public Decimal Stock;

        public ProductSearchDTO(Id id, String name, Decimal stock) {
            this.Id    = id;
            this.Name  = name;
            this.Stock = stock;
        }
    }

}   // End of class SecondaryInvoiceHandler