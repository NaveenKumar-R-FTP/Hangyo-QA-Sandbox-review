public without sharing class CounterInvoiceController {

    @AuraEnabled(cacheable=true)
    public static String fetchDistributorData() {
        Id userId = UserInfo.getUserId();
        Id distributorAccId = getDistributorAccountId(userId);
        List<ContactDataWrapper> result = new List<ContactDataWrapper>();
        if (distributorAccId != null) {
            Account acc = [
                SELECT Id, Name, BillingState, BillingCity, BillingPostalCode, BillingCountry, Primary_State__c
                FROM Account WHERE Id = :distributorAccId LIMIT 1
            ];
            ContactDataWrapper w = new ContactDataWrapper();
            w.ConBillingState      = acc.BillingState;
            w.ConBillingCity       = acc.BillingCity;
            w.ConBillingPostalCode = acc.BillingPostalCode;
            w.ConBillingCountry    = acc.BillingCountry;
            w.PrimaryState         = acc.Primary_State__c;
            result.add(w);
        }
        return JSON.serialize(result);
    }

    @AuraEnabled
    public static String fetchProducts(String searchValue, String brandFilter,
                                       String stockFilter, String searchBy,
                                       String priceType) {
        Id userId           = UserInfo.getUserId();
        Id distributorAccId = getDistributorAccountId(userId);

        String primaryState = '';
        if (distributorAccId != null) {
            Account acc = [SELECT Primary_State__c FROM Account WHERE Id = :distributorAccId LIMIT 1];
            primaryState = acc.Primary_State__c != null ? acc.Primary_State__c : '';
        }

        Id productRecordTypeId = [
            SELECT Id FROM RecordType
            WHERE DeveloperName = 'Product' AND SObjectType = 'Product__c' LIMIT 1
        ].Id;

        String query = 'SELECT Id, Name, IsActive__c, DisplayURL__c, Image_Long__c, ' +
                       'MRP__c, Quantity__c, Unit_of_Measure__c, Category_Code__c, ' +
                       'Category_Name__c, Product_Code__c, Product_Brand__c ' +
                       'FROM Product__c WHERE IsActive__c = True AND Secondary_Product__c = TRUE ' +
                       'AND RecordTypeId = :productRecordTypeId';

        String codeSearchPattern = null;
        if (String.isBlank(searchBy)) searchBy = 'Name';

        if (String.isNotBlank(searchValue)) {
            if (searchBy == 'Code') {
                codeSearchPattern = searchValue.trim() + '%';
                query += ' AND Category_Code__c LIKE :codeSearchPattern';
            } else {
                searchValue = '%' + searchValue + '%';
                query += ' AND Name LIKE :searchValue';
            }
        }
        if (String.isNotBlank(brandFilter)) {
            query += ' AND Product_Brand__c LIKE :brandFilter';
        }

        // Per-distributor product restriction (deny list) — hides specific products from
        // specific distributors. Distributors with no Product_Restriction__c records are
        // completely unaffected.
        Set<Id> deniedProductIds = ProductRestrictionService.getDeniedProductIds(distributorAccId);
        if (!deniedProductIds.isEmpty()) {
            query += ' AND Id NOT IN :deniedProductIds';
        }

        query += ' ORDER BY Name ASC';

        List<Product__c> productList = Database.query(query);

        Set<Id> productIds = new Set<Id>();
        for (Product__c p : productList) productIds.add(p.Id);

        Map<Id, Decimal> productIdToQtyMap = new Map<Id, Decimal>();
        if (distributorAccId != null && !productIds.isEmpty()) {
            for (Inventory__c inv : [
                SELECT Product__c, Quantity_in_Hand__c FROM Inventory__c
                WHERE Distributor_Name__c = :distributorAccId AND Product__c IN :productIds
            ]) {
                productIdToQtyMap.put(inv.Product__c, inv.Quantity_in_Hand__c);
            }
        }

        Map<Id, Decimal> productIdToPTRMap = new Map<Id, Decimal>();
        if (priceType == 'Dealer Price' && !productIds.isEmpty() && String.isNotBlank(primaryState)) {
            for (Price_Book_Entry__c pbe : [
                SELECT Product__c, PTR__c FROM Price_Book_Entry__c
                WHERE Product__c IN :productIds AND Type__c = 'Retailer'
                AND Region__r.Name = :primaryState AND isActive__c = true
            ]) {
                productIdToPTRMap.put(pbe.Product__c, pbe.PTR__c);
            }
        }

        List<ProductDataWrapper> productWrapper = new List<ProductDataWrapper>();
        for (Product__c master : productList) {
            if (master.IsActive__c == true && master.Image_Long__c != null && master.Image_Long__c != '') {
                ProductDataWrapper pw = new ProductDataWrapper();
                pw.productId               = master.Id;
                pw.productShortDescription = master.Name;
                pw.productBrand            = master.Product_Brand__c;
                pw.sellebleSKU             = '';
                pw.uom                     = master.Unit_of_Measure__c;

                if (priceType == 'Dealer Price' && productIdToPTRMap.containsKey(master.Id)) {
                    pw.productListPrice  = productIdToPTRMap.get(master.Id);
                    pw.productOfferPrice = productIdToPTRMap.get(master.Id);
                    pw.productMRP        = master.MRP__c;
                } else {
                    pw.productListPrice  = master.MRP__c;
                    pw.productOfferPrice = master.MRP__c;
                    pw.productMRP        = master.MRP__c;
                }

               pw.productImages       = master.Image_Long__c.split(',');
pw.productDisplayImage = pw.productImages[0];
pw.availableQuantity   = productIdToQtyMap.containsKey(master.Id)
                         ? Integer.valueOf(productIdToQtyMap.get(master.Id)) : 0;
// Counter sales are always within the distributor's own state — set both
// to the same value so the intra-state (CGST+SGST) tax path is used correctly.
pw.retailerState       = primaryState;
pw.distributorState    = primaryState;
productWrapper.add(pw);
            }
        }

        if (stockFilter == 'Available Stock') {
            List<ProductDataWrapper> filtered = new List<ProductDataWrapper>();
            for (ProductDataWrapper pw : productWrapper) {
                if (pw.availableQuantity > 0) filtered.add(pw);
            }
            return JSON.serialize(filtered);
        }
        return JSON.serialize(productWrapper);
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Decimal> getTaxRates() {
        Map<String, Decimal> taxRates = new Map<String, Decimal>();
        Order_tax_value__c taxSetting = [
            SELECT SGST__c, IGST__c, CGST__c FROM Order_tax_value__c
            WHERE Name = 'General GST Settings' LIMIT 1
        ];
        if (taxSetting != null) {
            taxRates.put('CGST', taxSetting.CGST__c);
            taxRates.put('SGST', taxSetting.SGST__c);
            taxRates.put('IGST', taxSetting.IGST__c);
        }
        return taxRates;
    }

    @AuraEnabled
    public static OrderResponse createCounterOrder(String productsFromCart, String orderSummary) {
        try {
            List<CartProductWrapper.ProductWrapper> cartItems =
                (List<CartProductWrapper.ProductWrapper>) JSON.deserialize(
                    productsFromCart, List<CartProductWrapper.ProductWrapper>.class);

            CounterOrderSummaryWrapper summary =
                (CounterOrderSummaryWrapper) JSON.deserialize(orderSummary, CounterOrderSummaryWrapper.class);

            Id userId           = UserInfo.getUserId();
            Id distributorAccId = getDistributorAccountId(userId);

            Id retailerAccId = [
                SELECT Id FROM Account
                WHERE Name = 'Counter Sales Customer' AND RecordType.Name = 'Retailer' LIMIT 1
            ].Id;

            RecordType orderRT = [
                SELECT Id FROM RecordType WHERE SObjectType = 'Order__c' AND Name = 'Counter Order' LIMIT 1
            ];

            Order__c order = new Order__c();
            order.Account__c             = retailerAccId;
            order.AccountId__c           = distributorAccId;
            order.Ordered_By__c          = userId;
            order.EffectiveDate__c       = System.today();
            order.Status__c              = 'Order Placed';
            order.Type__c                = 'Counter Order';
            order.RecordTypeId           = orderRT.Id;
            order.Customer_Name__c       = summary.firstName + ' ' + summary.lastName;
            order.Customer_Phone__c      = summary.phone;
            order.Customer_Email__c      = summary.email;
            order.Customer_Address__c    = (String.isNotBlank(summary.addressLine) ? summary.addressLine + ' , ' : '')
                                           + summary.city + ' - ' + summary.postalCode;
            order.State__c               = summary.state;
            order.Country__c             = summary.country;
            order.Company__c             = summary.company;
            order.GSTIN__c               = summary.gstin;
            order.Total_order_value__c   = summary.totalPrice;
            order.Price_Excluding_Tax__c = summary.totalPriceExcludingTax;
            order.Total_Quantity__c      = summary.totalQuantity;
            order.totalCGST__c           = summary.totalCGST;
            order.totalSGST__c           = summary.totalSGST;
            order.totalIGST__c           = summary.totalIGST;
            String saleTypeVal  = String.isNotBlank(summary.saleType)  ? summary.saleType  : 'Cash Sales';
String priceTypeVal = String.isNotBlank(summary.priceType) ? summary.priceType : 'MRP';
order.Sale_Type__c = saleTypeVal;
order.Price_Type__c = priceTypeVal;
// Description__c kept in the legacy 'Type: X | Price: Y' format for backward
// compatibility with any code/reports still reading it directly; new code
// should read Sale_Type__c / Price_Type__c instead.
order.Description__c = 'Type: ' + saleTypeVal + ' | Price: ' + priceTypeVal;
            insert order;

            RecordType lineRT = [
                SELECT Id FROM RecordType
                WHERE SObjectType = 'Order_Line_Item__c' AND Name = 'Counter Order Line Item' LIMIT 1
            ];

            List<Order_Line_Item__c> lineItems = new List<Order_Line_Item__c>();
            for (CartProductWrapper.ProductWrapper item : cartItems) {
                Order_Line_Item__c li = new Order_Line_Item__c();
                li.Order__c            = order.Id;
                li.RecordTypeId        = lineRT.Id;
                li.Products__c         = item.productId;
                li.Ordered_Quantity__c = item.quantity;
                li.Product_Price__c    = item.productOfferPrice;
                lineItems.add(li);
            }
            insert lineItems;

            OrderResponse resp = new OrderResponse();
            resp.status  = 'Success';
            resp.orderId = order.Id;
            return resp;
        } catch (Exception e) {
            throw buildAuraException(e.getMessage());
        }
    }

    @AuraEnabled
    public static InvoiceResponse createCounterInvoice(Id orderId) {
        try {
            // Check if invoice already exists for this order to avoid duplicates
            List<Invoice__c> existing = [
                SELECT Id FROM Invoice__c WHERE Order__c = :orderId LIMIT 1
            ];
            if (!existing.isEmpty()) {
                System.debug('MRP_DEBUG: createCounterInvoice SHORT-CIRCUIT — invoice already exists for orderId=' + orderId + ', returning existing invoiceId=' + existing[0].Id + ' WITHOUT recalculating anything.');
                InvoiceResponse resp = new InvoiceResponse();
                resp.status    = 'Success';
                resp.invoiceId = existing[0].Id;
                return resp;
            }

            Order__c order = [
                SELECT Id, Name, AccountId__c, Account__c, Customer_Name__c, Customer_Phone__c,
                       Customer_Email__c, Customer_Address__c, State__c, Country__c,
                       Company__c, GSTIN__c, EffectiveDate__c, Sale_Type__c, Price_Type__c
                FROM Order__c WHERE Id = :orderId LIMIT 1
            ];

            User loggedInUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            User dmsUser = [
                SELECT Id, Name, AccountId, GSTIN__c, Invoice_Number_Prefix__c, Invoice_Start_Number__c,
                       Contact.Account.Id, Contact.Account.Primary_State__c
                FROM User WHERE AccountId = :loggedInUser.AccountId LIMIT 1
            ];

            String distState  = dmsUser.Contact?.Account?.Primary_State__c;
            String custState  = order.State__c;
            Boolean sameState = String.isNotBlank(distState) && String.isNotBlank(custState)
                                && distState.equalsIgnoreCase(custState);

            Order_tax_value__c taxSetting = [
                SELECT CGST__c, SGST__c, IGST__c FROM Order_tax_value__c
                WHERE Name = 'General GST Settings' LIMIT 1
            ];

            String invoiceNumber = generateInvoiceNumber(dmsUser);

            Id invoiceRT = Schema.SObjectType.Invoice__c
                           .getRecordTypeInfosByDeveloperName()
                           .get('Secondary_Invoice').getRecordTypeId();

            Invoice__c invoice = new Invoice__c();
            invoice.RecordTypeId           = invoiceRT;
            invoice.Order__c               = orderId;
            invoice.Distributor_Account__c = order.AccountId__c;
            invoice.Name                   = invoiceNumber;
            invoice.Invoice_Number__c      = invoiceNumber;
            invoice.Invoice_Date__c        = System.today();
            invoice.Status__c              = 'Draft';
            invoice.Origin__c              = 'Counter Invoice';
            invoice.Place_of_Supply__c     = distState;
            // Legal requirement: MRP is tax-inclusive under Indian Legal Metrology rules —
            // no GST is charged separately when Price_Type__c = MRP. This must be zeroed
            // here, BEFORE the Invoice_Line_Item__c records are inserted below, because
            // this org has a line-item-level trigger (InvoiceLineItemTrigger — not part of
            // this class, exists only in the org, not in this source) that independently
            // stamps each line's own CGST_Amount__c/SGST_Amount__c/IGST_Amount__c/
            // Total_Tax__c fields from the PARENT Invoice__c's CGST__c/SGST__c/IGST__c rate
            // fields at insert time. If those rate fields are left non-zero here, the
            // trigger bakes in non-zero per-line GST amounts that nothing afterward
            // clears — even though the invoice-level amount fields get correctly zeroed
            // by saveInvoice(). Zeroing the rates here (not just the amounts later) is
            // what makes the trigger itself compute zero.
            Boolean isMrpAtCreation        = order.Price_Type__c == 'MRP';
            invoice.CGST__c                = (!isMrpAtCreation && sameState) ? taxSetting.CGST__c : 0;
            invoice.SGST__c                = (!isMrpAtCreation && sameState) ? taxSetting.SGST__c : 0;
            invoice.IGST__c                = (!isMrpAtCreation && !sameState) ? taxSetting.IGST__c : 0;
            // Sale_Type__c / Price_Type__c: kept as a one-time copy for backward
            // compatibility (this field couldn't be deleted/converted — see
            // Sale_Type_Live__c / Price_Type_Live__c for a value that always mirrors
            // the Order live and can never go stale; prefer those for anything new).
            invoice.Sale_Type__c           = order.Sale_Type__c;
            invoice.Price_Type__c          = order.Price_Type__c;
            System.debug('MRP_DEBUG: createCounterInvoice orderId=' + orderId
                + ' order.Price_Type__c=[' + order.Price_Type__c + ']'
                + ' isMrpAtCreation=' + isMrpAtCreation
                + ' sameState=' + sameState
                + ' distState=[' + distState + '] custState=[' + custState + ']'
                + ' -> invoice.CGST__c=' + invoice.CGST__c
                + ' invoice.SGST__c=' + invoice.SGST__c
                + ' invoice.IGST__c=' + invoice.IGST__c);
            insert invoice;

            List<Order_Line_Item__c> orderLines = [
                SELECT Products__c, Ordered_Quantity__c, Product_Price__c, Products__r.MRP__c
                FROM Order_Line_Item__c WHERE Order__c = :orderId
            ];

            List<Invoice_Line_Item__c> invLines = new List<Invoice_Line_Item__c>();
            for (Order_Line_Item__c ol : orderLines) {
                Invoice_Line_Item__c il = new Invoice_Line_Item__c();
                il.Invoice__c      = invoice.Id;
                il.Product__c      = ol.Products__c;
                il.Quantity__c     = ol.Ordered_Quantity__c;
                il.Price__c        = ol.Product_Price__c;
                il.MRP__c          = ol.Products__r.MRP__c;
                il.Total_Amount__c = ol.Ordered_Quantity__c * ol.Product_Price__c;
                il.Discount_1__c   = 0;
                invLines.add(il);
            }
            insert invLines;

            InvoiceResponse resp = new InvoiceResponse();
            resp.status    = 'Success';
            resp.invoiceId = invoice.Id;
            return resp;
        } catch (Exception e) {
            throw buildAuraException(e.getMessage());
        }
    }

    @AuraEnabled
    public static CounterInvoiceData loadInvoiceData(Id invoiceId) {
        try {
            CounterInvoiceData data = new CounterInvoiceData();

            Invoice__c inv = [
                SELECT Id, Name, Invoice_Number__c, Invoice_Date__c, Status__c,
                       Order__c, Distributor_Account__c, CGST__c, SGST__c, IGST__c,
                       CGST_Amount__c, SGST_Amount__c, IGST_Amount__c,
                       Taxable_Amount__c, Total_GST__c, Invoice_Amount__c,
                       Invoice_Amount_In_Words__c, Total_Quantity__c,
                       Place_of_Supply__c, Credit_Period__c, Payment_Status__c,
                       Price_Type__c, Sale_Type__c
                FROM Invoice__c WHERE Id = :invoiceId LIMIT 1
            ];

                        if (!InvoiceEditWindow.isEditable(inv)) {
                data.message = 'This invoice is locked. The 2-day edit window has closed or the invoice is cancelled.';
                return data;
            }

            User loggedInUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            User dmsUser = [
                SELECT Id, Name, CompanyName, Phone, MobilePhone, Email,
                       MediumPhotoUrl, GSTIN__c, PAN_Number__c, State, Notes__c,
                       Bank_Name__c, Bank_Account_Number__c, IFSC_Code__c, UPI_ID__c,
                       Terms_and_Conditions__c,
                       Contact.Account.BillingStreet, Contact.Account.BillingCity,
                       Contact.Account.BillingState, Contact.Account.BillingPostalCode,
                       Contact.Account.BillingCountry, Contact.Account.Name,
                       Contact.Account.Phone_1__c, Contact.Account.FSSAI__c,
                       Contact.Account.Primary_State__c
                FROM User WHERE AccountId = :loggedInUser.AccountId LIMIT 1
            ];

            Order__c order = [
                SELECT Customer_Name__c, Customer_Phone__c, Customer_Email__c,
                       Customer_Address__c, State__c, GSTIN__c, Company__c,
                       Sale_Type__c, Price_Type__c
                FROM Order__c WHERE Id = :inv.Order__c LIMIT 1
            ];

            List<Invoice_Line_Item__c> lineItems = [
                SELECT Id, Product__c, Product__r.Name, Quantity__c, Price__c,
                  Total_Amount__c, MRP__c, Discount_1__c, Discount_2__c, SKU_Discount_Percent__c
                FROM Invoice_Line_Item__c WHERE Invoice__c = :invoiceId
                ORDER BY Product__r.Name ASC
            ];

            Set<Id> productIds = new Set<Id>();
            for (Invoice_Line_Item__c li : lineItems) productIds.add(li.Product__c);

            Map<Id, Decimal> stockMap = new Map<Id, Decimal>();
            for (Inventory__c inv2 : [
                SELECT Product__c, Quantity_in_hand__c FROM Inventory__c
                WHERE Product__c IN :productIds AND Distributor_Name__c = :loggedInUser.AccountId
            ]) {
                stockMap.put(inv2.Product__c, inv2.Quantity_in_hand__c);
            }

            data.dmsUser   = dmsUser;
            data.invoice   = inv;
            data.order     = order;
            data.lineItems = lineItems;
            data.stockMap  = stockMap;
            data.message   = 'Success';
            return data;
        } catch (Exception e) {
            throw buildAuraException(e.getMessage());
        }
    }

    @AuraEnabled
    public static InvoiceResponse saveInvoice(Invoice__c invoice,
                                              List<Invoice_Line_Item__c> lineItems,
                                              List<Id> deletedIds) {
        try {
            for (Invoice_Line_Item__c li : lineItems) {
                Decimal discount1 = li.Discount_1__c != null ? li.Discount_1__c : 0;
                Decimal discount2 = li.Discount_2__c != null ? li.Discount_2__c : 0;
                Decimal gross    = (li.Quantity__c != null && li.Price__c != null)
                                   ? li.Quantity__c * li.Price__c : 0;
                if ((discount1 + discount2) > gross) {
                    throw buildAuraException(
                        'Discount cannot exceed line item amount.');
                }
            }

            if (!deletedIds.isEmpty()) {
                delete [SELECT Id FROM Invoice_Line_Item__c WHERE Id IN :deletedIds];
            }

            // Legal requirement: MRP is tax-inclusive under Indian Legal Metrology rules —
            // the price already contains GST, so no GST is shown/charged separately when
            // Price_Type__c = MRP. Non-MRP price types (e.g. Dealer Price) keep the normal
            // calculation — GST added on top of taxableAmount.
            //
            // IMPORTANT — this must be committed to the invoice's CGST__c/SGST__c/IGST__c
            // rate fields BEFORE "upsert lineItems" below, not just applied to the amount
            // fields afterward. This org has a line-item-level trigger
            // (InvoiceLineItemTrigger — not part of this class, exists only in the org, not
            // in this source) that independently stamps each Invoice_Line_Item__c's own
            // CGST_Amount__c/SGST_Amount__c/IGST_Amount__c/Total_Tax__c fields from the
            // PARENT Invoice__c's CGST__c/SGST__c/IGST__c rate fields whenever a line item
            // is inserted/updated. If those rate fields are still non-zero in the database
            // at the moment the line items are upserted, the trigger bakes in stale
            // non-zero GST on every line — which is exactly why the invoice-level totals
            // and HSN summary were correctly showing 0 while the PDF's per-line "Tax Amt"
            // and "Net Amt" columns kept showing the old forward-calculated GST.
            Boolean isMrp = invoice.Price_Type__c == 'MRP';
            System.debug('MRP_DEBUG: saveInvoice invoiceId=' + invoice.Id
                + ' invoice.Price_Type__c=[' + invoice.Price_Type__c + ']'
                + ' isMrp=' + isMrp
                + ' invoice.CGST__c(before)=' + invoice.CGST__c
                + ' invoice.SGST__c(before)=' + invoice.SGST__c
                + ' invoice.IGST__c(before)=' + invoice.IGST__c);
            if (isMrp) {
                invoice.CGST__c = 0;
                invoice.SGST__c = 0;
                invoice.IGST__c = 0;
                update invoice;
            }

            // NOTE: Total_Amount__c intentionally stays gross-minus-Discount_1__c only here
            // (matching its pre-existing semantics elsewhere in this org — e.g. the "Basic
            // Amt" column on CounterInvoicePdf, which shows gross). Invoice_Line_Item__c's
            // own Tax__c field already independently computes true taxable value as
            // Total_Amount__c - Discount_2__c, so subtracting Discount_2__c again inside
            // Total_Amount__c itself would cause it to be double-counted once Tax__c
            // re-subtracts it. Discount_2__c is still persisted per line via the upsert
            // below — it just isn't folded into Total_Amount__c a second time.
            //
            // The invoice-level taxableAmount aggregate (used for CGST/SGST/IGST and
            // Invoice_Amount__c below) DOES need Discount_2__c subtracted though, since it
            // has to match what Tax__c computes per line — otherwise the invoice header
            // totals would ignore Discount 2 entirely.
            Decimal taxableAmount = 0;
            for (Invoice_Line_Item__c li : lineItems) {
                if (li.Invoice__c == null) li.Invoice__c = invoice.Id;
                Decimal discount1  = li.Discount_1__c != null ? li.Discount_1__c : 0;
                Decimal discount2  = li.Discount_2__c != null ? li.Discount_2__c : 0;
                li.Total_Amount__c = (li.Quantity__c * li.Price__c) - discount1;
                taxableAmount     += li.Total_Amount__c - discount2;
            }
            upsert lineItems;

            Decimal cgstPct  = isMrp ? 0 : (invoice.CGST__c != null ? invoice.CGST__c : 0);
            Decimal sgstPct  = isMrp ? 0 : (invoice.SGST__c != null ? invoice.SGST__c : 0);
            Decimal igstPct  = isMrp ? 0 : (invoice.IGST__c != null ? invoice.IGST__c : 0);

            Decimal cgstAmt  = (taxableAmount * cgstPct) / 100;
            Decimal sgstAmt  = (taxableAmount * sgstPct) / 100;
            Decimal igstAmt  = (taxableAmount * igstPct) / 100;
            Decimal totalGST = cgstAmt + sgstAmt + igstAmt;
            Decimal invoiceAmt = Math.round(taxableAmount + totalGST);

            invoice.Taxable_Amount__c = roundNum(taxableAmount);
            invoice.CGST_Amount__c    = roundNum(cgstAmt);
            invoice.SGST_Amount__c    = roundNum(sgstAmt);
            invoice.IGST_Amount__c    = roundNum(igstAmt);
            invoice.Total_GST__c      = roundNum(totalGST);
            invoice.Invoice_Amount__c = invoiceAmt;
            invoice.Total_Quantity__c = getTotalQty(lineItems);
            update invoice;

            InvoiceResponse resp = new InvoiceResponse();
            resp.status    = 'Success';
            resp.invoiceId = invoice.Id;
            return resp;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw buildAuraException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String confirmInvoice(Id invoiceId) {
        try {
            Invoice__c inv = [
                SELECT Id, Status__c, Distributor_Account__c, Order__c
                FROM Invoice__c WHERE Id = :invoiceId LIMIT 1
            ];
            if (inv.Status__c != 'Draft') {
                throw buildAuraException('Only Draft invoices can be confirmed.');
            }

            List<Invoice_Line_Item__c> lines = [
                SELECT Product__c, Quantity__c FROM Invoice_Line_Item__c WHERE Invoice__c = :invoiceId
            ];

            Set<Id> productIds = new Set<Id>();
            for (Invoice_Line_Item__c li : lines) productIds.add(li.Product__c);

            Map<Id, Inventory__c> inventoryMap = new Map<Id, Inventory__c>();
            for (Inventory__c invt : [
                SELECT Id, Product__c, Quantity_in_hand__c FROM Inventory__c
                WHERE Distributor_Name__c = :inv.Distributor_Account__c AND Product__c IN :productIds
            ]) {
                inventoryMap.put(invt.Product__c, invt);
            }

            for (Invoice_Line_Item__c li : lines) {
                Inventory__c stock = inventoryMap.get(li.Product__c);
                if (stock == null || stock.Quantity_in_hand__c < li.Quantity__c) {
                    throw buildAuraException('Insufficient stock for one or more products.');
                }
            }

            List<Inventory__c> toUpdate = new List<Inventory__c>();
            for (Invoice_Line_Item__c li : lines) {
                Inventory__c stock = inventoryMap.get(li.Product__c);
                stock.Quantity_in_hand__c -= li.Quantity__c;
                toUpdate.add(stock);
            }
            update toUpdate;

            // Use Database.update with allOrNone=false to bypass InvoiceTrigger
            // attempting to set 'Invoiced' status on Counter Order (invalid picklist value)
            inv.Status__c = 'Confirmed';
            Database.SaveResult sr = Database.update(inv, false);
            if (!sr.isSuccess()) {
                for (Database.Error err : sr.getErrors()) {
                    if (!err.getMessage().contains('INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST')) {
                        throw buildAuraException(err.getMessage());
                    }
                }
            }

            return 'Success';
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw buildAuraException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String cancelInvoice(Id invoiceId) {
        try {
            Invoice__c inv = [
                SELECT Id, Status__c, Distributor_Account__c
                FROM Invoice__c WHERE Id = :invoiceId LIMIT 1
            ];
            if (inv.Status__c != 'Confirmed') {
                throw buildAuraException('Only Confirmed invoices can be cancelled.');
            }

            List<Invoice_Line_Item__c> lines = [
                SELECT Product__c, Quantity__c FROM Invoice_Line_Item__c WHERE Invoice__c = :invoiceId
            ];

            Set<Id> productIds = new Set<Id>();
            for (Invoice_Line_Item__c li : lines) productIds.add(li.Product__c);

            Map<Id, Inventory__c> inventoryMap = new Map<Id, Inventory__c>();
            for (Inventory__c invt : [
                SELECT Id, Product__c, Quantity_in_hand__c FROM Inventory__c
                WHERE Distributor_Name__c = :inv.Distributor_Account__c AND Product__c IN :productIds
            ]) {
                inventoryMap.put(invt.Product__c, invt);
            }

            List<Inventory__c> toUpdate = new List<Inventory__c>();
            for (Invoice_Line_Item__c li : lines) {
                Inventory__c stock = inventoryMap.get(li.Product__c);
                if (stock != null) {
                    stock.Quantity_in_hand__c += li.Quantity__c;
                    toUpdate.add(stock);
                }
            }
            update toUpdate;

            // Use Database.update with allOrNone=false to bypass trigger errors
            inv.Status__c = 'Cancelled';
            Database.SaveResult sr = Database.update(inv, false);
            if (!sr.isSuccess()) {
                for (Database.Error err : sr.getErrors()) {
                    if (!err.getMessage().contains('INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST')) {
                        throw buildAuraException(err.getMessage());
                    }
                }
            }

            return 'Success';
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw buildAuraException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Map<Id, Decimal> getStockByProducts(List<Id> productIds) {
        Map<Id, Decimal> stockMap = new Map<Id, Decimal>();
        if (productIds == null || productIds.isEmpty()) return stockMap;
        User u = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        for (Inventory__c inv : [
            SELECT Product__c, Quantity_in_hand__c FROM Inventory__c
            WHERE Product__c IN :productIds AND Distributor_Name__c = :u.AccountId
        ]) {
            stockMap.put(inv.Product__c, inv.Quantity_in_hand__c);
        }
        return stockMap;
    }

    @AuraEnabled(cacheable=true)
    public static List<ProductSearchDTO> getProductsWithStock(String searchKey) {
        if (String.isBlank(searchKey)) return new List<ProductSearchDTO>();
        User u = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (u.AccountId == null) return new List<ProductSearchDTO>();

        String key = '%' + String.escapeSingleQuotes(searchKey) + '%';
        List<Inventory__c> invList = [
            SELECT Product__c, Product__r.Name, Quantity_in_hand__c FROM Inventory__c
            WHERE Distributor_Name__c = :u.AccountId AND Quantity_in_hand__c > 0
            AND Product__r.Name LIKE :key ORDER BY Product__r.Name LIMIT 50
        ];

        // Per-distributor product restriction (deny list).
        Set<Id> deniedProductIds = ProductRestrictionService.getDeniedProductIds(u.AccountId);

        Map<Id, Decimal> stockMap = new Map<Id, Decimal>();
        Map<Id, String>  nameMap  = new Map<Id, String>();
        for (Inventory__c inv : invList) {
            if (inv.Product__c == null || deniedProductIds.contains(inv.Product__c)) continue;
            Decimal current = stockMap.containsKey(inv.Product__c) ? stockMap.get(inv.Product__c) : 0;
            stockMap.put(inv.Product__c, current + (inv.Quantity_in_hand__c != null ? inv.Quantity_in_hand__c : 0));
            if (!nameMap.containsKey(inv.Product__c) && inv.Product__r != null) {
                nameMap.put(inv.Product__c, inv.Product__r.Name);
            }
        }

        List<ProductSearchDTO> result = new List<ProductSearchDTO>();
        for (Id pid : stockMap.keySet()) {
            result.add(new ProductSearchDTO(pid, nameMap.get(pid), stockMap.get(pid)));
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getPriceForProduct(Id productId, String priceType) {
        Map<String, Object> result = new Map<String, Object>();
        if (productId == null) { result.put('price', 0); result.put('mrp', 0); return result; }

        Product__c prod = [SELECT MRP__c FROM Product__c WHERE Id = :productId LIMIT 1];
        result.put('mrp', prod.MRP__c != null ? prod.MRP__c : 0);

        if (priceType == 'Dealer Price') {
            User u = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            Account acc = [SELECT Primary_State__c FROM Account WHERE Id = :u.AccountId LIMIT 1];
            String state = acc.Primary_State__c != null ? acc.Primary_State__c : '';
            List<Price_Book_Entry__c> pbeList = [
                SELECT PTR__c FROM Price_Book_Entry__c
                WHERE Product__c = :productId AND Type__c = 'Retailer'
                AND Region__r.Name = :state AND isActive__c = true LIMIT 1
            ];
            result.put('price', !pbeList.isEmpty() && pbeList[0].PTR__c != null
                                ? pbeList[0].PTR__c : prod.MRP__c);
        } else {
            result.put('price', prod.MRP__c != null ? prod.MRP__c : 0);
        }
        return result;
    }

    private static Id getDistributorAccountId(Id userId) {
        Id conId = [SELECT ContactId FROM User WHERE Id = :userId LIMIT 1].ContactId;
        if (conId == null) return null;
        Contact con = [SELECT AccountId FROM Contact WHERE Id = :conId LIMIT 1];
        return con.AccountId;
    }

    private static String generateInvoiceNumber(User dmsUser) {
        String prefix    = String.isNotBlank(dmsUser.Invoice_Number_Prefix__c)
                           ? dmsUser.Invoice_Number_Prefix__c : 'CI';
        Integer startNum = dmsUser.Invoice_Start_Number__c != null
                           ? Integer.valueOf(dmsUser.Invoice_Start_Number__c) : 1;
        // Use AccountId directly from the User record — more reliable than Contact.Account.Id
        Id distributorAccountId = dmsUser.AccountId;
        return calculateNextInvoiceNumber(distributorAccountId, prefix, startNum);
    }

    private static String calculateNextInvoiceNumber(Id dmsUserAccountId, String invPrefix, Integer startNum) {
        // Use FOR UPDATE to lock the account record and prevent duplicate invoice numbers
        // when multiple invoices are created simultaneously
        Account distAcc = [
            SELECT Id, Last_Invoice_Number__c
            FROM Account
            WHERE Id = :dmsUserAccountId
            FOR UPDATE
        ];

        Integer nextInvNumber;
        if (distAcc.Last_Invoice_Number__c == null) {
            // First time - look at existing invoices
            List<Invoice__c> invList = [
                SELECT Invoice_Number__c FROM Invoice__c
                WHERE Distributor_Account__c = :dmsUserAccountId
                AND RecordType.DeveloperName != 'Primary_Invoice'
                AND (Origin__c = null OR Origin__c != 'Counter Invoice')
                ORDER BY CreatedDate DESC LIMIT 1
            ];
            Integer prefixLength = invPrefix.length();
            nextInvNumber = (!invList.isEmpty()
                             ? Integer.valueOf((invList[0].Invoice_Number__c).right(10 - prefixLength)) + 1
                             : startNum);
        } else {
            nextInvNumber = Integer.valueOf(distAcc.Last_Invoice_Number__c) + 1;
        }

        // Save the last used number back to Account
        distAcc.Last_Invoice_Number__c = nextInvNumber;
        update distAcc;

        Integer prefixLength   = invPrefix.length();
        Integer paddingCounter = 10 - (prefixLength + String.valueOf(nextInvNumber).length());
        if (paddingCounter < 0) paddingCounter = 0;
        String padding = '';
        for (Integer i = 1; i <= paddingCounter; i++) {
            padding = padding + '0';
        }
        return (invPrefix + padding + nextInvNumber);
    }

    private static Decimal roundNum(Decimal num) {
        return Math.round(num * 100) / 100.0;
    }

    // AuraHandledException has a well-known Salesforce quirk: passing a message to
    // the constructor does NOT make getMessage() return it — the platform hides the
    // real message from the client (and often from server-side logs/tests too) unless
    // setMessage() is called explicitly afterward. That quirk is what caused
    // saveInvoice()/cancelInvoice() to surface as unexplained, message-less
    // AuraHandledExceptions. Route every throw through this helper so the message is
    // always actually populated.
    private static AuraHandledException buildAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    private static Integer getTotalQty(List<Invoice_Line_Item__c> lines) {
        // lineItems arrive from the LWC as flat records (Product__c is just an Id, no
        // Product__r populated), so Per_Pieces__c must be bulk-fetched here rather than
        // read off the line. Quantity__c is in whatever unit was ordered (e.g. boxes),
        // not pieces — multiply by Per_Pieces__c so Total_Quantity__c (shown on the
        // Counter Invoice PDF) is always in actual pieces, e.g. 3 boxes at 12/13/15
        // pieces each = 40, not 3. Falls back to 1 per line if Per_Pieces__c is
        // missing/zero, so this can't break for products without it configured.
        Set<Id> productIds = new Set<Id>();
        for (Invoice_Line_Item__c li : lines) {
            if (li.Product__c != null) productIds.add(li.Product__c);
        }

        Map<Id, Decimal> perPiecesMap = new Map<Id, Decimal>();
        if (!productIds.isEmpty()) {
            for (Product__c p : [SELECT Id, Per_Pieces__c FROM Product__c WHERE Id IN :productIds]) {
                perPiecesMap.put(p.Id, p.Per_Pieces__c);
            }
        }

        Decimal total = 0;
        for (Invoice_Line_Item__c li : lines) {
            if (li.Quantity__c == null) continue;
            Decimal perPiecesVal = li.Product__c != null ? perPiecesMap.get(li.Product__c) : null;
            Decimal perPieces = (perPiecesVal != null && perPiecesVal > 0) ? perPiecesVal : 1;
            total += li.Quantity__c * perPieces;
        }
        return Integer.valueOf(total);
    }

    public class ProductDataWrapper {
       @AuraEnabled public String productId;
@AuraEnabled public List<String> productImages;
@AuraEnabled public String productDisplayImage;
@AuraEnabled public String productShortDescription;
@AuraEnabled public String productBrand;
@AuraEnabled public String sellebleSKU;
@AuraEnabled public Decimal productListPrice;
@AuraEnabled public Decimal productOfferPrice;
@AuraEnabled public Decimal productMRP;
@AuraEnabled public Integer productQuantity;
@AuraEnabled public Integer availableQuantity;
@AuraEnabled public String uom;
@AuraEnabled public String retailerState;
@AuraEnabled public String distributorState;
        public ProductDataWrapper() {
            productImages     = new List<String>();
            productQuantity   = 0;
            availableQuantity = 0;
        }
    }

    public class ContactDataWrapper {
        @AuraEnabled public String ConBillingState;
        @AuraEnabled public String ConBillingCity;
        @AuraEnabled public String ConBillingPostalCode;
        @AuraEnabled public String ConBillingCountry;
        @AuraEnabled public String PrimaryState;
    }

    public class OrderResponse {
        @AuraEnabled public String status;
        @AuraEnabled public String orderId;
    }

    public class InvoiceResponse {
        @AuraEnabled public String status;
        @AuraEnabled public String invoiceId;
    }

    public class CounterInvoiceData {
        @AuraEnabled public User dmsUser;
        @AuraEnabled public Invoice__c invoice;
        @AuraEnabled public Order__c order;
        @AuraEnabled public List<Invoice_Line_Item__c> lineItems;
        @AuraEnabled public Map<Id, Decimal> stockMap;
        @AuraEnabled public String message;
    }

    public class ProductSearchDTO {
        @AuraEnabled public Id Id;
        @AuraEnabled public String Name;
        @AuraEnabled public Decimal Stock;
        public ProductSearchDTO(Id id, String name, Decimal stock) {
            this.Id    = id;
            this.Name  = name;
            this.Stock = stock;
        }
    }

    public class CounterOrderSummaryWrapper {
        public String firstName;
        public String lastName;
        public String email;
        public String phone;
        public String addressLine;
        public String city;
        public String postalCode;
        public String state;
        public String country;
        public String company;
        public String gstin;
        public String saleType;
        public String priceType;
        public Decimal totalPrice;
        public Decimal totalPriceExcludingTax;
        public Integer totalQuantity;
        public Decimal totalCGST;
        public Decimal totalSGST;
        public Decimal totalIGST;
    }
}