public without sharing class UnderSsOrderComponentController {

    // ─── Record Type Developer Names ────────────────────────────────────────────
    private static final String UNDERSS_ORDER_RT     = 'Under_SS_Order';
    private static final String UNDERSS_SEC_ORDER_RT = 'Under_SS_Secondary_Order';
    private static final String UNDERSS_OLI_RT       = 'UnderSS_Order_Line_Item';
    private static final String UNDERSS_SEC_OLI_RT   = 'Under_SS_Secondary_Order_Line_Item';

    // ── Record Type Id cache (avoids repeated SOQL in same transaction) ─────────
    private static Map<String, Id> rtCache = new Map<String, Id>();

    private static Id getRecordTypeId(String sObjectType, String developerName) {
        String key = sObjectType + ':' + developerName;
        if (!rtCache.containsKey(key)) {
            rtCache.put(key, [SELECT Id FROM RecordType WHERE SObjectType = :sObjectType AND DeveloperName = :developerName LIMIT 1].Id);
        }
        return rtCache.get(key);
    }

    @AuraEnabled
    public static String fetchProducts(String searchValue,String brandFilter,List<Id> retailerSelected,String stockFilter,String searchBy){
        try {
            List<ProductDataWrapper> productWrapper = new List<ProductDataWrapper>();

            Id distributorAccId = resolveAccountForCurrentUser();
            if (distributorAccId == null) { return JSON.serialize(productWrapper); }

            String distributorUserState = getAccountState(distributorAccId);
            String retailerUserState    = '';

            List<Account> retailerAccs = [
                SELECT Id, Primary_State__c FROM Account WHERE Id IN :retailerSelected LIMIT 1
            ];
            if (!retailerAccs.isEmpty()) { retailerUserState = retailerAccs[0].Primary_State__c; }

            Id selectedPricebookId = resolvePricebookForState(retailerUserState);
            if (selectedPricebookId == null) {
                System.debug('No pricebook found for state: ' + retailerUserState);
                return JSON.serialize(productWrapper);
            }

            Map<Id, Decimal> stateSpecificPriceMap = new Map<Id, Decimal>();
            Set<Id>          productIds            = new Set<Id>();

            for (Price_Book_Entry__c pbe : [
                SELECT Product__c, PTD__c
                FROM   Price_Book_Entry__c
                WHERE  isActive__c   = TRUE
                AND    Price_Book__c = :selectedPricebookId
                AND    Type__c       = 'Direct Distributor'
            ]) {
                productIds.add(pbe.Product__c);
                stateSpecificPriceMap.put(
                    pbe.Product__c,
                    pbe.PTD__c != null ? pbe.PTD__c.setScale(2, System.RoundingMode.HALF_UP) : 0
                );
            }

            if (productIds.isEmpty()) { return JSON.serialize(productWrapper); }

            Id productRecordTypeId = getRecordTypeId('Product__c', 'Product');
            String query =
                'SELECT Id, Name, IsActive__c, Focus_Product__c, Unit_of_Measure__c, MRP__c, ' +
                'Category_Code__c, Product_Code__c, Product_Brand__c, Image_Long__c, Crate_Conversion__c ' +
                'FROM Product__c ' +
                'WHERE Id IN :productIds AND IsActive__c = TRUE ' +
                'AND Under_SS__c = TRUE AND RecordTypeId = :productRecordTypeId';

            String codeSearchPattern = null;
            if (String.isBlank(searchBy)) { searchBy = 'Name'; }

            if (String.isNotBlank(searchValue)) {
                if (searchBy == 'Code') {
                    codeSearchPattern = searchValue.trim() + '%';
                    query += ' AND Category_Code__c LIKE :codeSearchPattern';
                } else {
                    searchValue = '%' + searchValue + '%';
                    query += ' AND (Name LIKE :searchValue OR Product_Brand__c LIKE :searchValue)';
                }
            }
            if (String.isNotBlank(brandFilter) && brandFilter != 'Available Stock') {
                query += ' AND Product_Brand__c LIKE :brandFilter';
            }

            // Per-distributor product restriction (deny list).
            Set<Id> deniedProductIds = ProductRestrictionService.getDeniedProductIds(distributorAccId);
            if (!deniedProductIds.isEmpty()) {
                query += ' AND Id NOT IN :deniedProductIds';
            }

            query += ' ORDER BY Name ASC';

            List<Product__c>  productList  = Database.query(query);
            Map<Id, Decimal>  inventoryMap = getInventoryMap(distributorAccId, productIds);

            for (Product__c p : productList) {
                if (String.isBlank(p.Image_Long__c)) { continue; }
                Decimal availableQty = inventoryMap.containsKey(p.Id) ? inventoryMap.get(p.Id) : 0;
                if (stockFilter == 'Available Stock' && availableQty <= 0) { continue; }

                ProductDataWrapper pw      = new ProductDataWrapper();
                pw.productId               = p.Id;
                pw.productShortDescription = p.Name;
                pw.productBrand            = p.Product_Brand__c;
                pw.productListPrice        = stateSpecificPriceMap.containsKey(p.Id)
                    ? stateSpecificPriceMap.get(p.Id) : 0;
                pw.productOfferPrice       = pw.productListPrice;
                pw.productMrp              = p.MRP__c;
                pw.productImages           = p.Image_Long__c.split(',');
                pw.productDisplayImage     = pw.productImages[0];
                pw.retailerState           = retailerUserState;
                pw.distributorState        = distributorUserState;
                pw.uom                     = p.Unit_of_Measure__c;
                pw.focusProduct            = p.Focus_Product__c;
                pw.productCode             = p.Product_Code__c;
                pw.availableQuantity       = Integer.valueOf(availableQty);
                pw.crateConversion         = p.Crate_Conversion__c != null ? p.Crate_Conversion__c : 0;
                productWrapper.add(pw);
            }
            return JSON.serialize(productWrapper);

        } catch (Exception e) {
            System.debug('fetchProducts error: ' + e.getMessage() + ' | Line: ' + e.getLineNumber());
            return JSON.serialize(new List<ProductDataWrapper>());
        }
    }

    @AuraEnabled
    public static String fetchFocusedProducts(String searchValue,String brandFilter,List<String> excludedProductIds,List<Id> retailerSelected,String stockFilter,String searchBy){
        try {
            List<ProductDataWrapper> productWrapper = new List<ProductDataWrapper>();

            Id     distributorAccId  = resolveAccountForCurrentUser();
            String distributorState  = getAccountState(distributorAccId);
            String retailerUserState = '';

            List<Account> retailerAccs = [
                SELECT Id, Primary_State__c FROM Account WHERE Id IN :retailerSelected LIMIT 1
            ];
            if (!retailerAccs.isEmpty()) { retailerUserState = retailerAccs[0].Primary_State__c; }

            Id selectedPricebookId = resolvePricebookForState(retailerUserState);
            if (selectedPricebookId == null) { return JSON.serialize(productWrapper); }

            Map<Id, Decimal> stateSpecificPriceMap = new Map<Id, Decimal>();
            Set<Id>          productIds            = new Set<Id>();

            for (Price_Book_Entry__c pbe : [
                SELECT Product__c, PTD__c FROM Price_Book_Entry__c WHERE isActive__c   = TRUE
                AND Price_Book__c = :selectedPricebookId AND Type__c = 'Direct Distributor'
            ]) {
                productIds.add(pbe.Product__c);
                stateSpecificPriceMap.put(
                    pbe.Product__c,
                    pbe.PTD__c != null ? pbe.PTD__c.setScale(2, System.RoundingMode.HALF_UP) : 0
                );
            }

            if (productIds.isEmpty()) { return JSON.serialize(productWrapper); }

            Id productRecordTypeId = getRecordTypeId('Product__c', 'Product');
            String query =
                'SELECT Id, Name, IsActive__c, Focus_Product__c, Unit_of_Measure__c, MRP__c, ' +
                'Category_Code__c, Product_Code__c, Product_Brand__c, Image_Long__c, Crate_Conversion__c ' +
                'FROM Product__c ' +
                'WHERE Id IN :productIds AND IsActive__c = TRUE ' +
                'AND Under_SS__c = TRUE AND Focus_Product__c = TRUE ' +
                'AND RecordTypeId = :productRecordTypeId';

            String codeFocusPattern = null;
            if (String.isBlank(searchBy)) { searchBy = 'Name'; }

            if (String.isNotBlank(searchValue)) {
                if (searchBy == 'Code') {
                    codeFocusPattern = searchValue.trim() + '%';
                    query += ' AND Category_Code__c LIKE :codeFocusPattern';
                } else {
                    searchValue = '%' + searchValue + '%';
                    query += ' AND (Name LIKE :searchValue OR Product_Brand__c LIKE :searchValue)';
                }
            }
            if (String.isNotBlank(brandFilter) && brandFilter != 'Available Stock') {
                query += ' AND Product_Brand__c LIKE :brandFilter';
            }
            if (excludedProductIds != null && !excludedProductIds.isEmpty()) {
                query += ' AND Id NOT IN :excludedProductIds';
            }

            // Per-distributor product restriction (deny list).
            Set<Id> deniedProductIds = ProductRestrictionService.getDeniedProductIds(distributorAccId);
            if (!deniedProductIds.isEmpty()) {
                query += ' AND Id NOT IN :deniedProductIds';
            }

            query += ' ORDER BY Name ASC';

            List<Product__c>  productList  = Database.query(query);
            Map<Id, Decimal>  inventoryMap = getInventoryMap(distributorAccId, productIds);

            for (Product__c p : productList) {
                if (String.isBlank(p.Image_Long__c)) { continue; }
                Decimal availableQty = inventoryMap.containsKey(p.Id) ? inventoryMap.get(p.Id) : 0;
                if (stockFilter == 'Available Stock' && availableQty <= 0) { continue; }

                ProductDataWrapper pw      = new ProductDataWrapper();
                pw.productId               = p.Id;
                pw.productShortDescription = p.Name;
                pw.productBrand            = p.Product_Brand__c;
                pw.productListPrice        = stateSpecificPriceMap.containsKey(p.Id)
                    ? stateSpecificPriceMap.get(p.Id) : 0;
                pw.productOfferPrice       = pw.productListPrice;
                pw.productMrp              = p.MRP__c;
                pw.productImages           = p.Image_Long__c.split(',');
                pw.productDisplayImage     = pw.productImages[0];
                pw.retailerState           = retailerUserState;
                pw.distributorState        = distributorState;
                pw.uom                     = p.Unit_of_Measure__c;
                pw.focusProduct            = p.Focus_Product__c;
                pw.productCode             = p.Product_Code__c;
                pw.availableQuantity       = Integer.valueOf(availableQty);
                pw.crateConversion         = p.Crate_Conversion__c != null ? p.Crate_Conversion__c : 0;
                productWrapper.add(pw);
            }
            return JSON.serialize(productWrapper);

        } catch (Exception e) {
            System.debug('fetchFocusedProducts error: ' + e.getMessage() + ' | Line: ' + e.getLineNumber());
            return JSON.serialize(new List<ProductDataWrapper>());
        }
    }

    @AuraEnabled
    public static OrderResponse generateProposal(String productsFromCart,List<Id> retailerSelected,String orderSummary,String orderComment){
        try {
            UnderSsOrderResult result = createUnderSsOrder(productsFromCart, retailerSelected, orderSummary, orderComment);

            Id ssSecOrderId = createSsSecondaryOrder(result);

            OrderResponse response = new OrderResponse();
            response.status        = 'Success';
            response.underSsOrdId  = result.underSsOrderId;
            response.ordid         = ssSecOrderId;
            return response;

        } catch (Exception e) {
            System.debug('generateProposal error: ' + e.getMessage() + ' Line: ' + e.getLineNumber());
            throw new AuraHandledException(e.getMessage() + ' | Line: ' + e.getLineNumber());
        }
    }

    public static UnderSsOrderResult createUnderSsOrder(String productsFromCart, List<Id> retailerSelected,String orderSummary,String orderComment){
        List<CartProductWrapper.ProductWrapper> cartItems =
            (List<CartProductWrapper.ProductWrapper>) JSON.deserialize(
                productsFromCart, List<CartProductWrapper.ProductWrapper>.class
            );
        OrderSummaryWrapper summaryData = (OrderSummaryWrapper) JSON.deserialize(orderSummary, OrderSummaryWrapper.class);

        // ── Resolve SS (logged-in) account ───────────────────────────────────────
        Id ssDistributorAccId = resolveAccountForCurrentUser();
        if (ssDistributorAccId == null) {
            throw new AuraHandledException('Unable to identify Super Stockist account.');
        }
        String ssState = getAccountState(ssDistributorAccId);

        // ── Capture SS user Id in sync context (always correct here) ─────────────
        Id ssUserId = UserInfo.getUserId();

        // ── Validate Under SS account belongs to this SS ─────────────────────────
        List<Account> underSsAccounts = [
            SELECT Id, Name, Primary_State__c, Super_Stockist_Name__c, Distributor_Type__c
            FROM   Account
            WHERE  Id IN :retailerSelected
            AND    Distributor_Type__c    = 'Under Super Stockist'
            AND    Super_Stockist_Name__c = :ssDistributorAccId
            LIMIT  1
        ];
        if (underSsAccounts.isEmpty()) {
            throw new AuraHandledException('Selected Under SS distributor is not tagged to the logged-in Super Stockist.');
        }
        Account underSsAccount = underSsAccounts[0];
        String  underSsState   = underSsAccount.Primary_State__c;

        Id underSsCommunityUserId = resolvePortalUserViaContact(underSsAccount.Id);
        if (underSsCommunityUserId == null) {
            throw new AuraHandledException('No active community user found for the Under SS distributor.');
        }

        Date effectiveDate = String.isNotBlank(summaryData.orderDate) ? Date.valueOf(summaryData.orderDate) : System.today();

        Order__c underSsOrder               = new Order__c();
        underSsOrder.RecordTypeId           = getRecordTypeId('Order__c', UNDERSS_ORDER_RT);
        underSsOrder.OwnerId                = underSsCommunityUserId;   // portal user — needs SYSTEM_MODE
        underSsOrder.Ordered_By__c          = underSsCommunityUserId;
        underSsOrder.AccountId__c           = underSsAccount.Id;
        underSsOrder.Super_Stockist_Name__c = ssDistributorAccId;
        underSsOrder.Description__c         = orderComment;
        underSsOrder.Total_order_value__c   = summaryData.totalPrice;
        underSsOrder.Sub_Total__c           = summaryData.subTotal;
        underSsOrder.EffectiveDate__c       = effectiveDate;
        underSsOrder.Status__c              = 'Order Placed';
        underSsOrder.Total_Quantity__c      = summaryData.totalQuantity;
        underSsOrder.Total_Discount__c      = summaryData.totalDiscount;
        underSsOrder.Type__c                = 'Under Super Stockist';
        underSsOrder.totalCGST__c           = summaryData.totalCGST;
        underSsOrder.totalSGST__c           = summaryData.totalSGST;
        underSsOrder.totalIGST__c           = summaryData.totalIGST;
        applyOrderFinancials(underSsOrder, summaryData);

        ElevatedDmlExecutor dml = new ElevatedDmlExecutor();
        dml.insertOrder(underSsOrder);

        Id underSsOliRtId = getRecordTypeId('Order_Line_Item__c', UNDERSS_OLI_RT);
        dml.insertLineItems(buildLineItems(cartItems, underSsOrder.Id, underSsOliRtId));

        UnderSsOrderResult result = new UnderSsOrderResult();
        result.underSsOrderId     = underSsOrder.Id;
        result.underSsUserId      = underSsCommunityUserId;
        result.ssDistributorAccId = ssDistributorAccId;
        result.ssUserId           = ssUserId;   // SS internal user captured above
        result.ssState            = ssState;
        result.underSsState       = underSsState;
        result.productsFromCart   = productsFromCart;
        result.orderSummary       = orderSummary;
        result.orderComment       = orderComment;
        return result;
    }

    public static Id createSsSecondaryOrder(UnderSsOrderResult underSsResult) {
        List<CartProductWrapper.ProductWrapper> cartItems =
            (List<CartProductWrapper.ProductWrapper>) JSON.deserialize(
                underSsResult.productsFromCart,
                List<CartProductWrapper.ProductWrapper>.class
            );
        OrderSummaryWrapper summaryData = (OrderSummaryWrapper) JSON.deserialize(underSsResult.orderSummary, OrderSummaryWrapper.class);

        Date effectiveDate = String.isNotBlank(summaryData.orderDate) ? Date.valueOf(summaryData.orderDate) : System.today();

        Order__c ssSecOrder               = new Order__c();
        ssSecOrder.RecordTypeId           = getRecordTypeId('Order__c', UNDERSS_SEC_ORDER_RT);
        ssSecOrder.OwnerId                = underSsResult.ssUserId;           // SS internal user
        ssSecOrder.Ordered_By__c          = underSsResult.underSsUserId;      // Under SS portal user
        ssSecOrder.AccountId__c           = underSsResult.ssDistributorAccId; // SS account
        ssSecOrder.Under_SS_Order__c      = underSsResult.underSsOrderId;     // linked to primary
        ssSecOrder.Placed_via_Under_SS__c = true;
        ssSecOrder.Type__c                = 'DMS';
        ssSecOrder.Description__c         = underSsResult.orderComment;
        ssSecOrder.Total_order_value__c   = summaryData.totalPrice;
        ssSecOrder.Sub_Total__c           = summaryData.subTotal;
        ssSecOrder.EffectiveDate__c       = effectiveDate;
        ssSecOrder.Status__c              = 'Order Placed';
        ssSecOrder.Total_Quantity__c      = summaryData.totalQuantity;
        ssSecOrder.Total_Discount__c      = summaryData.totalDiscount;
        ssSecOrder.totalCGST__c           = summaryData.totalCGST;
        ssSecOrder.totalSGST__c           = summaryData.totalSGST;
        ssSecOrder.totalIGST__c           = summaryData.totalIGST;
        applyOrderFinancials(ssSecOrder, summaryData);

        ElevatedDmlExecutor dml = new ElevatedDmlExecutor();
        dml.insertOrder(ssSecOrder);

        Id secOliRtId = getRecordTypeId('Order_Line_Item__c', UNDERSS_SEC_OLI_RT);
        dml.insertLineItems(buildLineItems(cartItems, ssSecOrder.Id, secOliRtId));

        return ssSecOrder.Id;
    }

    public without sharing class ElevatedDmlExecutor {

        public void insertOrder(Order__c ord) {
            if (ord == null) {
                throw new AuraHandledException('ElevatedDmlExecutor: cannot insert a null Order__c.');
            }
            Database.SaveResult sr = Database.insert(ord, AccessLevel.SYSTEM_MODE);
            if (!sr.isSuccess()) {
                String errors = '';
                for (Database.Error err : sr.getErrors()) {
                    errors += err.getMessage() + ' (StatusCode: ' + err.getStatusCode() + ') ';
                    System.debug('ElevatedDmlExecutor.insertOrder error: '
                        + err.getMessage() + ' | StatusCode: ' + err.getStatusCode());
                }
                throw new AuraHandledException('Order insert failed: ' + errors.trim());
            }
        }

        public void insertLineItems(List<Order_Line_Item__c> lineItems) {
            if (lineItems == null || lineItems.isEmpty()) { return; }
            List<Database.SaveResult> results =
                Database.insert(lineItems, false, AccessLevel.SYSTEM_MODE);
            String errors = '';
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    for (Database.Error err : results[i].getErrors()) {
                        errors += 'Row ' + i + ': ' + err.getMessage()
                            + ' (StatusCode: ' + err.getStatusCode() + ') ';
                        System.debug('ElevatedDmlExecutor.insertLineItems error row ' + i
                            + ': ' + err.getMessage()
                            + ' | StatusCode: ' + err.getStatusCode());
                    }
                }
            }
            if (String.isNotBlank(errors)) {
                throw new AuraHandledException('Line item insert failed: ' + errors.trim());
            }
        }
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Decimal> getTaxRates(String retailerPrimaryState,String distributorPrimaryState){
        Map<String, Decimal> taxRates = new Map<String, Decimal>();
        Order_tax_value__c taxSetting = Order_tax_value__c.getValues('General GST Settings');

        if (taxSetting == null) {
            taxSetting = new Order_tax_value__c(CGST__c = 0, SGST__c = 0, IGST__c = 0);
        }

        Boolean isSameState = String.isNotBlank(retailerPrimaryState) && String.isNotBlank(distributorPrimaryState) &&
            retailerPrimaryState.equalsIgnoreCase(distributorPrimaryState);
        System.debug('isSameState:- ' + isSameState);

        if (isSameState) {
            System.debug('taxSetting:- ' + taxSetting.CGST__c);
            System.debug('taxSetting:- ' + taxSetting.SGST__c);
            taxRates.put('CGST', taxSetting.CGST__c);
            taxRates.put('SGST', taxSetting.SGST__c);
        } else {
            System.debug('taxSetting:- ' + taxSetting.IGST__c);
            taxRates.put('IGST', taxSetting.IGST__c);
        }
        return taxRates;
    }

    private static Id resolveAccountForCurrentUser() {
        User u = [SELECT Id, ContactId, AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (u.ContactId != null) {
            List<Contact> cons = [SELECT AccountId FROM Contact WHERE Id = :u.ContactId LIMIT 1];
            if (!cons.isEmpty() && cons[0].AccountId != null) { return cons[0].AccountId; }
        }
        return u.AccountId;
    }

    private static String getAccountState(Id accountId) {
        if (accountId == null) { return ''; }
        List<Account> accs = [SELECT Primary_State__c FROM Account WHERE Id = :accountId LIMIT 1];
        return accs.isEmpty() ? '' : (accs[0].Primary_State__c != null ? accs[0].Primary_State__c : '');
    }

    private static Id resolvePricebookForState(String state) {
        if (String.isBlank(state)) { return null; }
        Id regionalId;
        Id panIndiaId;
        for (Price_Book__c pb : [SELECT Id, Region__r.Name FROM Price_Book__c WHERE isActive__c = TRUE]){
            if (pb.Region__r != null && pb.Region__r.Name == state) {
                regionalId = pb.Id;
                break;
            } else if (pb.Region__r == null && panIndiaId == null) {
                panIndiaId = pb.Id;
            }
        }
        return regionalId != null ? regionalId : panIndiaId;
    }

    private static Map<Id, Decimal> getInventoryMap(Id distributorAccId, Set<Id> productIds) {
        Map<Id, Decimal> inventoryMap = new Map<Id, Decimal>();
        if (distributorAccId == null || productIds.isEmpty()) { return inventoryMap; }
        for (Inventory__c inv : [
            SELECT Product__c, Quantity_in_Hand__c FROM Inventory__c
            WHERE Distributor_Name__c = :distributorAccId AND Product__c IN :productIds
        ]) {
            inventoryMap.put(inv.Product__c, inv.Quantity_in_Hand__c);
        }
        return inventoryMap;
    }

    public static Id resolvePortalUserViaContact(Id accountId) {
        if (accountId == null) { return null; }
        List<User> portalUsers = [
            SELECT Id, Name, IsActive, ContactId, UserType, Primary_Distributor__c FROM User
            WHERE AccountId = :accountId AND IsActive  = true
            AND ContactId != null AND UserType IN ('PowerPartner', 'CSPLitePortal', 'CustomerSuccess')
            ORDER BY Primary_Distributor__c DESC
            LIMIT  1
        ];
        return portalUsers.isEmpty() ? null : portalUsers[0].Id;
    }

    private static TaxResult calculateTax(String state1, String state2, Decimal subTotal) {
        TaxResult tax = new TaxResult();
        if (subTotal == null) { subTotal = 0; }

        Order_tax_value__c setting;
        try {
            setting = [SELECT CGST__c, SGST__c, IGST__c FROM   Order_tax_value__c WHERE  Name = 'General GST Settings' LIMIT  1];
        } catch (QueryException e) {
            setting = new Order_tax_value__c(CGST__c = 0, SGST__c = 0, IGST__c = 0);
        }

        Boolean isSameState = String.isNotBlank(state1) && String.isNotBlank(state2) && state1.equalsIgnoreCase(state2);

        if (isSameState) {
            tax.cgst = (subTotal * (setting.CGST__c != null ? setting.CGST__c : 0)) / 100;
            tax.sgst = (subTotal * (setting.SGST__c != null ? setting.SGST__c : 0)) / 100;
            tax.igst = 0;
        } else {
            tax.igst = (subTotal * (setting.IGST__c != null ? setting.IGST__c : 0)) / 100;
            tax.cgst = 0;
            tax.sgst = 0;
        }
        return tax;
    }

    private static void applyOrderFinancials(Order__c ord, OrderSummaryWrapper data) {
        if (String.isNotBlank(data.valuseSchemeIdOnOrder)) {
            ord.Value_Scheme_Applied__c  = data.valuseSchemeIdOnOrder;
        }
        if (data.valueSchemeDiscount != null) {
            ord.Value_Scheme_Discount__c = data.valueSchemeDiscount;
        }
        if (data.totalDiscountRupees != null) {
            ord.Discount_Amount_Order__c = data.totalDiscountRupees;
        }
    }

    private static List<Order_Line_Item__c> buildLineItems(List<CartProductWrapper.ProductWrapper> cartItems,Id orderId,Id recordTypeId){
        List<Order_Line_Item__c> items = new List<Order_Line_Item__c>();
        for (CartProductWrapper.ProductWrapper p : cartItems) {
            Decimal linePrice = (p.isPromotional == true)
                ? (p.productListPrice != null ? p.productListPrice : p.productOfferPrice)
                : p.productOfferPrice;

            items.add(new Order_Line_Item__c(
                Order__c = orderId,
                RecordTypeId = recordTypeId,
                Products__c = p.productId,
                Ordered_Quantity__c = p.quantity,
                Product_Price__c = linePrice,
                Quantity_Scheme__c = p.selectedSchemeId,
                Is_Promotional__c = (p.isPromotional == true),
                Parent_Product__c = p.parentProductId,
                Discount_Percentage__c = p.discountPercentage
            ));
        }
        return items;
    }

    public class ProductDataWrapper {
        @AuraEnabled public String productId { get; set; }
        @AuraEnabled public List<String> productImages { get; set; }
        @AuraEnabled public String productDisplayImage { get; set; }
        @AuraEnabled public String productShortDescription { get; set; }
        @AuraEnabled public String productBrand { get; set; }
        @AuraEnabled public String sellebleSKU { get; set; }
        @AuraEnabled public Decimal productListPrice { get; set; }
        @AuraEnabled public Decimal productOfferPrice { get; set; }
        @AuraEnabled public Decimal productMrp { get; set; }
        @AuraEnabled public Integer availableQuantity { get; set; }
        @AuraEnabled public Integer productQuantity { get; set; }
        @AuraEnabled public String retailerState { get; set; }
        @AuraEnabled public String distributorState { get; set; }
        @AuraEnabled public String uom { get; set; }
        @AuraEnabled public Boolean focusProduct { get; set; }
        @AuraEnabled public String productCode { get; set; }
        @AuraEnabled public Decimal crateConversion;

        public ProductDataWrapper() {
            productImages = new List<String>();
            productQuantity = 0;
            availableQuantity = 0;
        }
    }

    public class OrderResponse {
        @AuraEnabled public String status;
        @AuraEnabled public String ordid;        
        @AuraEnabled public String underSsOrdId; 
    }

    public class OrderSummaryWrapper {
        public Integer totalItems;
        public Decimal totalPrice;
        public Decimal totalDiscount;
        public Decimal totalOrderValue;
        public Decimal subTotal;
        public Integer totalQuantity;
        public Decimal totalSGST;
        public Decimal totalCGST;
        public Decimal totalIGST;
        public Decimal totalDiscountRupees;
        public Decimal totalDiscountGivenByUser;
        public Decimal valueSchemeDiscount;
        public String  valuseSchemeIdOnOrder;
        public String  orderDate;
        public String  totalCrates;
    }

    public class UnderSsOrderResult {
        public Id underSsOrderId;
        public Id underSsUserId;
        public Id ssDistributorAccId;
        public Id ssUserId;
        public String ssState;
        public String underSsState;
        public String productsFromCart;
        public String orderSummary;
        public String orderComment;
    }

    private class TaxResult {
        public Decimal cgst = 0;
        public Decimal sgst = 0;
        public Decimal igst = 0;
    }
}