public without sharing class SchemeEvaluationService {

     public static Map<Id, Decimal> getDistributorStockForProducts(Set<Id> productIds) {
        Map<Id, Decimal> stockMap = new Map<Id, Decimal>();
    
        if (productIds == null || productIds.isEmpty()) {
            return stockMap;
        }
    
        // Resolve distributor via User → Contact → Account
        User u = [
            SELECT Contact.AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
    
        if (u.Contact == null || u.Contact.AccountId == null) {
            return stockMap; // safety
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

    @AuraEnabled
    public static List<QuantitySchemeModalWrapper> getqualityScheme(
        Id productId,
        Id buyerAccountId,
        String buyerRegion,
        Boolean isUnderSS
    ) {
        try {
            System.debug('▶ productId=' + productId);
            System.debug('▶ buyerAccountId=' + buyerAccountId);
            System.debug('▶ buyerRegion=' + buyerRegion);
    
            if (productId == null || buyerAccountId == null || String.isBlank(buyerRegion)) {
                throw new AuraHandledException('Missing required inputs');
            }
        Date today = System.today();
    
        /* ------------------------------------------------------------
            Fetch active Quantity Schemes for the product
           ------------------------------------------------------------ */
        List<Scheme__c> schemes = [
            SELECT Id, Name,
                   Minimum_Purchase_Quantity__c,
                   Promotion_Quantity__c,
                   Discount_Percentage__c,
                   Product__c,
                   Other_Product__c,
                   Type__c,
            	   Retailer_Scheme__c,
           		   Under_SS_Scheme__c
            FROM Scheme__c
            WHERE Product__c = :productId
              AND Is_Active__c = true
              AND RecordType.DeveloperName = 'Quantity_scheme'
              AND Scheme_Start_Date__c <= :today
              AND Scheme_End_Date__c >= :today
        ];
    
        if (schemes.isEmpty()) {
            return new List<QuantitySchemeModalWrapper>();
        }
    
        /* ------------------------------------------------------------
            Fetch Scheme Hierarchy
           ------------------------------------------------------------ */
        Set<Id> schemeIds = new Set<Id>();
        for (Scheme__c s : schemes) {
            schemeIds.add(s.Id);
        }  
        Map<Id, List<Scheme_Hierarchy__c>> hierarchyByScheme =
            new Map<Id, List<Scheme_Hierarchy__c>>();
    
       for (Scheme_Hierarchy__c sh : [
            SELECT Scheme__c, Account__c, Region__c,Region__r.Name, Distributor__c, Hub__c
            FROM Scheme_Hierarchy__c
            WHERE Scheme__c IN :schemeIds
              AND IsActive__c = true
        ]) {
            if (!hierarchyByScheme.containsKey(sh.Scheme__c)) {
                hierarchyByScheme.put(
                    sh.Scheme__c,
                    new List<Scheme_Hierarchy__c>()
                );
            }

            hierarchyByScheme.get(sh.Scheme__c).add(sh);
        }

        // Step 5: resolve buyer's Distributor/Hub once, outside the scheme loop.
        Account buyerAcc = resolveBuyerDistributorInfo(buyerAccountId);
        Id buyerDistributorId = buyerAcc != null ? buyerAcc.Distributor__c : null;
        String buyerHub = (buyerAcc != null && buyerAcc.Distributor__r != null)
            ? buyerAcc.Distributor__r.Hub__c : null;


        /* ------------------------------------------------------------
			Filter schemes by Account / Region applicability
           ------------------------------------------------------------ */
        List<QuantitySchemeModalWrapper> response = new List<QuantitySchemeModalWrapper>();

        for (Scheme__c scheme : schemes) {

            // Retailer / SS eligibility
             	if (isUnderSS && !scheme.Under_SS_Scheme__c) continue;
    			if (!isUnderSS && !scheme.Retailer_Scheme__c) continue;

            List<Scheme_Hierarchy__c> hierarchy = hierarchyByScheme.get(scheme.Id);

            // Global scheme (no hierarchy records)
            if (hierarchy == null || hierarchy.isEmpty()) {
                response.add(buildWrapper(scheme));
                continue;
            }

            // Apply hierarchy resolution
            if (isSchemeApplicable(hierarchy, buyerAccountId, buyerRegion, buyerDistributorId, buyerHub)) {
                response.add(buildWrapper(scheme));
            }
        }
            
       	 return response;
            } catch (Exception e) {
                System.debug(' Error in getqualityScheme: ' + e.getMessage());
                throw new AuraHandledException(
                    'Quantity Scheme Error: ' + e.getMessage()
                );
    		}
    }
    
    // Backward-compatible 3-arg overload — Account/Region resolution only, no
    // Distributor/Hub. Kept so existing callers (and existing tests that call
    // isSchemeApplicable directly) don't need to change. Delegates to the 5-arg
    // overload below with null Distributor/Hub, which is exactly the old behavior.
    public static Boolean isSchemeApplicable(
        List<Scheme_Hierarchy__c> records,
        Id buyerAccountId,
        String buyerRegion
    ) {
        return isSchemeApplicable(records, buyerAccountId, buyerRegion, null, null);
    }

    // Step 5: extended to also resolve Distributor and Hub level hierarchy rows,
    // in addition to the original Account/Region resolution. A Scheme_Hierarchy__c
    // row now matches on whichever single field is populated (Account__c [+Region__c],
    // Region__c only, Distributor__c only, or Hub__c only) — Scheme_Holder_Type__c
    // itself is not read here, it's just an admin-UX field; matching is still driven
    // by which lookup/picklist field actually has a value, same pattern as before.
    public static Boolean isSchemeApplicable(
        List<Scheme_Hierarchy__c> records,
        Id buyerAccountId,
        String buyerRegion,
        Id buyerDistributorId,
        String buyerHub
    ) {
        Boolean accountRegionMatch = false;
        Boolean accountOnlyMatch   = false;
        Boolean regionOnlyMatch    = false;
        Boolean distributorMatch   = false;
        Boolean hubMatch           = false;

        for (Scheme_Hierarchy__c sh : records) {

            if (sh.Account__c != null &&
                sh.Region__c != null &&
                sh.Account__c == buyerAccountId &&
                sh.Region__r != null &&
               	sh.Region__r.Name == buyerRegion) {

                accountRegionMatch = true;
            }
            else if (sh.Account__c != null &&
                     sh.Account__c == buyerAccountId &&
                     sh.Region__c == null) {

                accountOnlyMatch = true;
            }
            else if (sh.Region__c != null &&
                     //sh.Region__c == buyerRegion &&
                     sh.Region__r != null &&
               		 sh.Region__r.Name == buyerRegion &&
                     sh.Account__c == null) {

                regionOnlyMatch = true;
            }
            else if (sh.Distributor__c != null &&
                     buyerDistributorId != null &&
                     sh.Distributor__c == buyerDistributorId) {

                distributorMatch = true;
            }
            else if (sh.Hub__c != null &&
                     String.isNotBlank(buyerHub) &&
                     sh.Hub__c == buyerHub) {

                hubMatch = true;
            }
        }

        // Defensive check per decision log §1.13 — a retailer should never
        // legitimately match more than one active hierarchy level for the same
        // scheme at once (Region/Hub/Distributor/Retailer assignment is supposed
        // to be exclusive per retailer). This doesn't block evaluation (the OR
        // below still applies, so the scheme still resolves correctly either way)
        // — it just surfaces data drift for an admin to investigate rather than
        // silently hiding it.
        Integer matchCount = (accountRegionMatch ? 1 : 0) + (accountOnlyMatch ? 1 : 0)
            + (regionOnlyMatch ? 1 : 0) + (distributorMatch ? 1 : 0) + (hubMatch ? 1 : 0);
        if (matchCount > 1) {
            String schemeIdForLog = records.isEmpty() ? null : records[0].Scheme__c;
            System.debug(LoggingLevel.WARN,
                'isSchemeApplicable: retailer matched multiple active hierarchy levels ' +
                'for the same scheme (' + schemeIdForLog + ') — possible data drift, see ' +
                'decision log §1.13. accountRegionMatch=' + accountRegionMatch +
                ' accountOnlyMatch=' + accountOnlyMatch + ' regionOnlyMatch=' + regionOnlyMatch +
                ' distributorMatch=' + distributorMatch + ' hubMatch=' + hubMatch);
        }

        return accountRegionMatch || accountOnlyMatch || regionOnlyMatch || distributorMatch || hubMatch;
    }

    // Step 5: resolves the buyer's Distributor and that Distributor's Hub in ONE query
    // per outer method call (not per scheme/per hierarchy row), so isSchemeApplicable()
    // can check Distributor/Hub hierarchy levels without a governor-limit-risking query
    // inside a loop. Returns null if the Account doesn't exist or has no Distributor set.
    private static Account resolveBuyerDistributorInfo(Id buyerAccountId) {
        if (buyerAccountId == null) {
            return null;
        }
        List<Account> accs = [
            SELECT Id, Distributor__c, Distributor__r.Hub__c
            FROM Account
            WHERE Id = :buyerAccountId
            LIMIT 1
        ];
        return accs.isEmpty() ? null : accs[0];
    }

    private static QuantitySchemeModalWrapper buildWrapper(Scheme__c s) {

        QuantitySchemeModalWrapper w = new QuantitySchemeModalWrapper();
    
        w.schemeId   = s.Id;
        w.schemeName = s.Name;
        w.minQty     = s.Minimum_Purchase_Quantity__c;
        w.minQty = s.Minimum_Purchase_Quantity__c != null ? s.Minimum_Purchase_Quantity__c : 0;
        w.promoQty   = s.Promotion_Quantity__c;
        w.discountPercentage = s.Discount_Percentage__c;
        w.schemeType = s.Type__c;
    
        return w;
    }
    
   /* public class QuantitySchemeModalWrapper {

        @AuraEnabled public Id      schemeId;
        @AuraEnabled public String  schemeName;
        @AuraEnabled public Decimal minQty;
        @AuraEnabled public Decimal promoQty;
        @AuraEnabled public Decimal discountPercentage;
        @AuraEnabled public String  schemeType;
        @AuraEnabled public String  displayMessage;
        @AuraEnabled public Boolean isEligible;
    
       
        public QuantitySchemeModalWrapper() {
            this.isEligible = false;
            this.displayMessage = '';
        }
   
        public void evaluateEligibility(Decimal selectedQty) {
    
            if (selectedQty == null || minQty == null) {
                this.isEligible = false;
                this.displayMessage = '';
                return;
            }
    
            if (selectedQty >= minQty) {
                this.isEligible = true;
    
                if (promoQty != null && promoQty > 0) {
                    this.displayMessage =
                        'Eligible for ' + promoQty + ' promotional quantity';
                } else if (discountPercentage != null && discountPercentage > 0) {
                    this.displayMessage =
                        'Eligible for ' + discountPercentage + '% discount';
                } else {
                    this.displayMessage = 'Scheme applicable';
                }
    
            } else {
                Decimal remaining = minQty - selectedQty;
                this.isEligible = false;
                this.displayMessage =
                    'Add ' + remaining + ' more qty to unlock this scheme';
            }
        }
    }*/
    
    	@AuraEnabled
    public static List<CartProductWrapper.ProductWrapper> applyQuantityScheme(
        List<CartProductWrapper.ProductWrapper> cartItems,
        Id buyerAccountId,
        String buyerRegion,
        Id selectedSchemeId,
        Boolean isUnderSS
    ) {
        List<CartProductWrapper.ProductWrapper> promos =
            new List<CartProductWrapper.ProductWrapper>();
    
        if (cartItems == null || cartItems.isEmpty() || selectedSchemeId == null) {
            return promos;
        }
    
        /* -------------------------------------------------
            Fetch Scheme
           ------------------------------------------------- */
        Scheme__c scheme = [
            SELECT Id,
                   Product__c,
                   Other_Product__c,
                   Promotion_Quantity__c,
                   Discount_Percentage__c,
                   Minimum_Purchase_Quantity__c,
                   Type__c
            FROM Scheme__c
            WHERE Id = :selectedSchemeId
            LIMIT 1
        ];
    
        /* -------------------------------------------------
            Find Base Product in Cart
           ------------------------------------------------- */
        CartProductWrapper.ProductWrapper base;
        for (CartProductWrapper.ProductWrapper item : cartItems) {
            if (item.productId == scheme.Product__c) {
                base = item;
                break;
            }
        }
    
        if (base == null ||
            base.quantity < scheme.Minimum_Purchase_Quantity__c) {
            return promos;
        }

        // Purchase Quantity Discount: this type discounts the purchased quantity itself
        // (handled client-side in createSecondaryOrderComponentDms.js by reducing the
        // base line's own price — same pattern as the existing TOD discount) rather than
        // adding a separate bonus/promo line. Nothing to build here; return empty so any
        // caller that still hits this method for this type is a safe no-op.
        if (scheme.Type__c == 'Purchase Quantity Discount') {
            return promos;
        }

        Boolean isOtherProductScheme =
            scheme.Type__c != null &&
            scheme.Type__c.startsWith('Other Product');
    
        /* -------------------------------------------------
            Resolve Retailer Price Book (PTR)
           ------------------------------------------------- */
        
        List<Account> retailerList = [
            SELECT Id, Primary_State__c
            FROM Account
            WHERE Id = :buyerAccountId
            LIMIT 1
        ];
        
        if (retailerList.isEmpty()) {
            throw new AuraHandledException(
                'Buyer Account not found or not accessible'
            );
        }

		Account retailer = retailerList[0];
        
        List<Price_Book__c> pbList = [
            SELECT Id
            FROM Price_Book__c
            WHERE isActive__c = true
            AND Region__r.Name = :buyerRegion
            LIMIT 1
        ];
        
        if (pbList.isEmpty()) {
            throw new AuraHandledException(
                'No active Price Book found for region: ' + buyerRegion
            );
        }
        
        Price_Book__c pb = pbList[0];

    
        String priceType = isUnderSS ? 'Under Super Stockist' : 'Retailer';
        Map<Id, Decimal> ptrPriceMap = new Map<Id, Decimal>();
        for (Price_Book_Entry__c pbe : [
            SELECT Product__c, PTR__c
            FROM Price_Book_Entry__c
            WHERE Price_Book__c = :pb.Id
            AND Type__c = :priceType
            AND PTR__c != null
        ]) {
            ptrPriceMap.put(pbe.Product__c, pbe.PTR__c);
        }
            /* -------------------------------------------------
           Resolve Promo Product & Base Price
           ------------------------------------------------- */
        Id promoProductId;
        Decimal promoBasePrice;
        Product__c otherProduct;
    
        if (isOtherProductScheme) {
            otherProduct = [
                SELECT Id, Name, Product_Brand__c, Unit_of_Measure__c,MRP__c,HSN__c
                FROM Product__c
                WHERE Id = :scheme.Other_Product__c
                LIMIT 1
            ];
    
            promoProductId = otherProduct.Id;
            /*promoBasePrice = ptrPriceMap.containsKey(promoProductId)
                ? ptrPriceMap.get(promoProductId)
                : 0;*/
            if (ptrPriceMap.containsKey(promoProductId)) {
                promoBasePrice = ptrPriceMap.get(promoProductId);
            } else {
                // fallback safety
                promoBasePrice = isOtherProductScheme
                    ? otherProduct.MRP__c   // or MRP field
                    : base.productOfferPrice;
            }
        } else {
            promoProductId = base.productId;
            promoBasePrice = base.productOfferPrice;
        }
    
         Set<Id> stockProductIds = new Set<Id>{promoProductId};

		Map<Id, Decimal> stockMap = getDistributorStockForProducts(stockProductIds);
    

        /* -------------------------------------------------
       		Create Promo Line
           ------------------------------------------------- */
        CartProductWrapper.ProductWrapper promo =
            new CartProductWrapper.ProductWrapper();
    
        promo.productId = promoProductId;
        promo.productIdForCart = promoProductId + '_PROMO';
        promo.parentProductId = base.productId;
        promo.isPromotional = true;
        promo.selectedSchemeId = scheme.Id;
        promo.discountPercentage = scheme.Discount_Percentage__c;
        //promo.quantity = Integer.valueOf(scheme.Promotion_Quantity__c);
        promo.isReadOnly = true;
        //promo.promoMinQty = scheme.Minimum_Purchase_Quantity__c;
        Integer baseQty = base.quantity;
        Integer minQty  = Integer.valueOf(scheme.Minimum_Purchase_Quantity__c);
        Integer promoPerSlab = Integer.valueOf(scheme.Promotion_Quantity__c);
        
        // How many times scheme applies
        Integer slabCount = (minQty > 0) ? (baseQty / minQty) : 0;
        
        // Total promo quantity
        Integer totalPromoQty = slabCount * promoPerSlab;
        
        promo.quantity = totalPromoQty;
        promo.promoMinQty = scheme.Minimum_Purchase_Quantity__c;
    	promo.availableStockQuantity = stockMap.containsKey(promoProductId)? Integer.valueOf(stockMap.get(promoProductId)) : 0;
        /* -------------------------------------------------
            Populate UI Fields
           ------------------------------------------------- */
        if (isOtherProductScheme && otherProduct != null) {
            promo.productName = otherProduct.Name;
            promo.productBrand = otherProduct.Product_Brand__c;
            promo.prodmeasure = otherProduct.Unit_of_Measure__c;
            //promo.availableStockQuantity = 0;
            promo.mrp = otherProduct.MRP__c; 
            promo.hsn = otherProduct.HSN__c;
        } else {
            promo.productName = safeStr(base.productName, base.productFullName);
            promo.productBrand = base.productBrand;
            promo.prodmeasure = base.prodmeasure;
            //promo.availableStockQuantity = base.availableStockQuantity;
            promo.mrp = base.mrp;
            promo.hsn = base.hsn;
        }
    
        /* -------------------------------------------------
            Pricing Logic (FREE vs DISCOUNTED)
           ------------------------------------------------- */
        promo.productListPrice = promoBasePrice;
    
        if (scheme.Discount_Percentage__c == null ||
            scheme.Discount_Percentage__c == 100) {
    
            // FREE PRODUCT
            promo.productOfferPrice = 0;
            promo.unittotalPrice = 0;
    
        } else {
    
            // DISCOUNTED PRODUCT (Same + Other)
            promo.productOfferPrice =
                promoBasePrice * (1 - (scheme.Discount_Percentage__c / 100));
    
            promo.unittotalPrice =
                promo.productOfferPrice * promo.quantity;
        }
    
        promo.isFreePromo = scheme.Discount_Percentage__c == null || scheme.Discount_Percentage__c == 100;
        promos.add(promo);
        return promos;
    }


    // Purchase Quantity Discount schemes don't touch Price__c (Rate stays at the full
    // list price on the invoice) — the discount is captured separately per line in the
    // stored Scheme_Discount_Amount__c field (same pattern as Discount_1__c/TOD). This
    // scans an invoice's line items, finds any linked to a scheme of that Type via
    // Quantity_Scheme_Applied__c, and returns one entry per DISTINCT scheme (summed
    // across every line that used it) with the already-persisted rupee amount saved.
    // Requires the line items to have been queried with Quantity_Scheme_Applied__r.Name,
    // .Discount_Percentage__c, .Type__c, and Scheme_Discount_Amount__c.
    public static List<AppliedSchemeDisplay> getAppliedQuantityDiscountSchemes(List<Invoice_Line_Item__c> lineItems) {
        Map<Id, AppliedSchemeDisplay> schemeMap = new Map<Id, AppliedSchemeDisplay>();
        if (lineItems == null) return new List<AppliedSchemeDisplay>();

        for (Invoice_Line_Item__c li : lineItems) {
            if (li.Is_Promotional__c == true) continue;
            if (li.Quantity_Scheme_Applied__c == null || li.Quantity_Scheme_Applied__r == null) continue;
            if (li.Quantity_Scheme_Applied__r.Type__c != 'Purchase Quantity Discount') continue;

            Decimal discountPercent = li.Quantity_Scheme_Applied__r.Discount_Percentage__c != null
                                     ? li.Quantity_Scheme_Applied__r.Discount_Percentage__c : 0;

            Decimal savedTotal = li.Scheme_Discount_Amount__c != null ? li.Scheme_Discount_Amount__c : 0;
            if (savedTotal <= 0) continue;

            Id schemeId = li.Quantity_Scheme_Applied__c;
            if (schemeMap.containsKey(schemeId)) {
                AppliedSchemeDisplay existing = schemeMap.get(schemeId);
                existing.discountAmount = (existing.discountAmount + savedTotal).setScale(2, RoundingMode.HALF_UP);
            } else {
                AppliedSchemeDisplay disp = new AppliedSchemeDisplay();
                disp.schemeName = li.Quantity_Scheme_Applied__r.Name;
                disp.discountPercent = discountPercent;
                disp.discountAmount = savedTotal.setScale(2, RoundingMode.HALF_UP);
                schemeMap.put(schemeId, disp);
            }
        }
        return schemeMap.values();
    }

    private static String safeStr(String value, String fallback) {
        return String.isNotBlank(value) ? value : fallback;
    }

    private static Integer safeInt(Integer value, Integer fallback) {
        return value != null ? value : fallback;
    }

    // One cart line's worth of data, sent up from createSecondaryOrderComponentDms.js so
    // Flat Discount schemes can be scoped to matched Product/Brand lines (Scheme_Applicability__c)
    // instead of the whole cart. lineAmount mirrors calculateOrderSummary()'s own math
    // (productOfferPrice * quantity, only counted when productListPrice > 0) so a scheme
    // with no applicability rows (global scheme) still sums to exactly totalCartPrice.
    public class CartLineWrapper {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productBrand;
        @AuraEnabled public Decimal lineAmount;
    }

    // Mirrors SchemeApplicabilityTriggerHandler.normalizeBrand() — kept as a separate
    // private copy here (rather than a shared utility) so this class has no compile-time
    // dependency on the trigger handler; the normalization rule itself (trim/upper/collapse
    // whitespace) must stay identical between the two for brand matching to work.
    private static String normalizeBrand(String rawBrand) {
        return rawBrand.trim().toUpperCase().replaceAll('\\s+', ' ');
    }

    // Computes the qualifying (matched) pre-tax subtotal for one scheme, per the
    // "Discount base" decision (§1.1 of the decision log): scope to Product/Brand rows in
    // Scheme_Applicability__c when the scheme has any, otherwise fall back to the whole
    // cart total so schemes with no applicability rows keep behaving as global schemes
    // (unchanged, pre-existing behavior).
    private static Decimal computeQualifyingSubtotal(Id schemeId, List<CartLineWrapper> cartLines, Decimal wholeCartTotal) {
        List<Scheme_Applicability__c> rows = [
            SELECT Product__c, Brand_Key__c
            FROM Scheme_Applicability__c
            WHERE Scheme__c = :schemeId
        ];

        if (rows.isEmpty()) {
            return wholeCartTotal;
        }

        Set<Id> productIds = new Set<Id>();
        Set<String> brandKeys = new Set<String>();
        for (Scheme_Applicability__c row : rows) {
            if (row.Product__c != null) {
                productIds.add(row.Product__c);
            }
            if (row.Brand_Key__c != null) {
                brandKeys.add(row.Brand_Key__c);
            }
        }

        Decimal qualifying = 0;
        if (cartLines != null) {
            for (CartLineWrapper line : cartLines) {
                if (line == null || line.lineAmount == null) {
                    continue;
                }
                Boolean productMatch = line.productId != null && productIds.contains(line.productId);
                Boolean brandMatch = String.isNotBlank(line.productBrand)
                    && brandKeys.contains(normalizeBrand(line.productBrand));
                if (productMatch || brandMatch) {
                    qualifying += line.lineAmount;
                }
            }
        }
        return qualifying;
    }

    @AuraEnabled
    public static AppliedValueSchemeWrapper getAppliedValueScheme(String valueSchemId) {
    
        Scheme__c s = [
            SELECT Discount_Amount__c,
                   Discount_Percentage__c,
                   Other_Product__c,
            	   Other_Product_Quantity__c,
                   Type__c,Cart_Amount__c
            FROM Scheme__c
            WHERE Id = :valueSchemId
            LIMIT 1
        ];
    
        AppliedValueSchemeWrapper w = new AppliedValueSchemeWrapper();
        w.discountAmount = s.Discount_Amount__c;
        w.discountPercentage = s.Discount_Percentage__c;
        w.freeProductId = s.Other_Product__c;
        w.schemeType = s.Type__c;
        w.promoQty = s.Other_Product_Quantity__c;
        w.cartAmount = s.Cart_Amount__c;

        return w;
    }

    // Separate method (NOT an overload — Salesforce does not allow overloading
    // @AuraEnabled methods) used when the caller already knows the cart total
    // (Flat Discount schemes need this to resolve which slab applies). The
    // original getAppliedValueScheme(String) above is left untouched — it's
    // still called with just an Id by
    // SchemeEvaluationServiceTest.testGetAppliedValueScheme() and by existing
    // JS callers that don't pass a cart total.
    @AuraEnabled
    public static AppliedValueSchemeWrapper getAppliedValueSchemeForCart(Id valueSchemId, Decimal cartTotal, String cartLinesJson) {
        // cartLines is accepted as a JSON string rather than a typed List<CartLineWrapper>
        // parameter — Experience Cloud's Aura remoting layer does not reliably deserialize
        // complex nested object-list parameters for @AuraEnabled methods (every field came
        // through null in production testing, 2026-08-20), so we deserialize manually here
        // instead of relying on automatic parameter binding.
        List<CartLineWrapper> cartLines = String.isBlank(cartLinesJson)
            ? null
            : (List<CartLineWrapper>) JSON.deserialize(cartLinesJson, List<CartLineWrapper>.class);

        // Queried as a List rather than a single-row assignment on purpose: the
        // scheme this method was called for may have been deleted or deactivated
        // out from under an already-applied cart (e.g. a stale valueSchemFinalId
        // restored from localStorage after the underlying Scheme__c record was
        // removed). A single-row `Scheme__c s = [...]` assignment throws
        // System.QueryException on zero rows, which the LWC callers' .catch()
        // blocks only logged — never actually clearing the applied scheme — so a
        // deleted/deactivated scheme's name and discount amount stayed frozen on
        // the cart/invoice forever. Returning an "empty" wrapper here instead lets
        // the existing !hasDiscountAmount && !hasDiscountPercentage branch already
        // present in every caller correctly self-heal by clearing the scheme, the
        // same way it already does for "cart total dropped below every slab."
        List<Scheme__c> schemes = [
            SELECT Discount_Amount__c,
                   Discount_Percentage__c,
                   Other_Product__c,
                   Other_Product_Quantity__c,
                   Type__c, Cart_Amount__c
            FROM Scheme__c
            WHERE Id = :valueSchemId
            LIMIT 1
        ];

        AppliedValueSchemeWrapper w = new AppliedValueSchemeWrapper();
        if (schemes.isEmpty()) {
            return w;
        }
        Scheme__c s = schemes[0];
        w.freeProductId = s.Other_Product__c;
        w.schemeType = s.Type__c;
        w.promoQty = s.Other_Product_Quantity__c;
        w.cartAmount = s.Cart_Amount__c;

        if (s.Type__c == 'Flat Discount') {
            List<Scheme_Slab__c> slabs = [
                SELECT For_Amount__c, Cash_Discount__c, Discount_Percent__c
                FROM Scheme_Slab__c
                WHERE Scheme__c = :valueSchemId
                ORDER BY For_Amount__c ASC
            ];

            // Scoped to matched Product/Brand lines when the scheme has
            // Scheme_Applicability__c rows; falls back to the whole cart total (cartTotal)
            // for schemes with none, so existing global schemes are unaffected.
            Decimal qualifyingSubtotal = computeQualifyingSubtotal(valueSchemId, cartLines, cartTotal);
            Scheme_Slab__c bestSlab = getBestSlabForAmount(slabs, qualifyingSubtotal);

            if (bestSlab != null) {
                w.discountAmount = bestSlab.Cash_Discount__c;
                w.discountPercentage = bestSlab.Discount_Percent__c;
                // A % discount must be computed against the qualifying (scoped) subtotal,
                // not the whole cart — otherwise a scheme scoped to specific SKUs via
                // Scheme_Applicability__c ends up discounting unrelated line items too.
                // See decision log, 2026-08-21.
                w.qualifyingSubtotal = qualifyingSubtotal;
            }
        } else {
            w.discountAmount = s.Discount_Amount__c;
            w.discountPercentage = s.Discount_Percentage__c;
        }

        return w;
    }

    @AuraEnabled(cacheable=true)
    public static CartProductWrapper.ProductWrapper getProductForValueScheme(Id productId) {
    
        Product__c p = [
            SELECT Id,
                   Name,
                   Product_Brand__c,
                   Unit_of_Measure__c,
                   MRP__c, HSN__c
            FROM Product__c
            WHERE Id = :productId
            LIMIT 1
        ];
    
        Set<Id> stockProductIds = new Set<Id>{productId};

		Map<Id, Decimal> stockMap = getDistributorStockForProducts(stockProductIds);
    

        CartProductWrapper.ProductWrapper w =
            new CartProductWrapper.ProductWrapper();
    
        w.productId = p.Id;
        w.productName = p.Name;
        w.productBrand = p.Product_Brand__c;
        w.prodmeasure = p.Unit_of_Measure__c;
        w.availableStockQuantity =  stockMap.containsKey(productId)? Integer.valueOf(stockMap.get(productId)): 0;
        w.mrp = p.MRP__c;
        w.productListPrice = 0;
        w.productOfferPrice = 0;
        w.unittotalPrice = 0;
        w.hsn = p.HSN__c;
    
        return w;
    }
    
    //This method is to getAppliedValueSchemeName
    
    @AuraEnabled
    public static  String getAppliedValueSchemeName(String valueSchemActiveId) {
        // Query for Scheme record
        Scheme__c schRec = [SELECT Id,Name, Cart_Amount__c, Discount_Amount__c, Discount_Percentage__c 
                            FROM Scheme__c 
                            WHERE Id = :valueSchemActiveId 
                            LIMIT 1];
        
        
        
        return schRec.Name;
    }
    
    @AuraEnabled
    public static List<SchemeDetailsWrapper> getvalueScheme(
        Decimal totalCartPrice,
        String cartLinesJson,
        Id buyerAccountId,
        String buyerRegion,
        Boolean isUnderSS
    ) {
        // cartLines is accepted as a JSON string rather than a typed List<CartLineWrapper>
        // parameter — Experience Cloud's Aura remoting layer does not reliably deserialize
        // complex nested object-list parameters for @AuraEnabled methods (every field came
        // through null in production testing, 2026-08-20), so we deserialize manually here
        // instead of relying on automatic parameter binding.
        List<CartLineWrapper> cartLines = String.isBlank(cartLinesJson)
            ? null
            : (List<CartLineWrapper>) JSON.deserialize(cartLinesJson, List<CartLineWrapper>.class);

        List<SchemeDetailsWrapper> response = new List<SchemeDetailsWrapper>();
    
        if (totalCartPrice == null || buyerAccountId == null || String.isBlank(buyerRegion)) {
            return response;
        }
    
        Date today = System.today();
       
        List<Scheme__c> schemes = [
            SELECT Id, Name,
                   Cart_Amount__c,
                   Discount_Amount__c,
                   Discount_Percentage__c,
                   Other_Product__c,
                   Type__c,Other_Product_Quantity__c,
                   Retailer_Scheme__c,
                   Under_SS_Scheme__c
            FROM Scheme__c
            WHERE Is_Active__c = true
              AND RecordType.DeveloperName = 'Value_Scheme'
              AND Scheme_Start_Date__c <= :today
              AND Scheme_End_Date__c >= :today
              AND (Cart_Amount__c != null OR Type__c = 'Flat Discount')
        ];

        if (schemes.isEmpty()) return response;

        // Fetch hierarchy
        Set<Id> schemeIds = new Set<Id>();
        for (Scheme__c s : schemes) schemeIds.add(s.Id);

        Map<Id, List<Scheme_Hierarchy__c>> hierarchyMap = new Map<Id, List<Scheme_Hierarchy__c>>();
        for (Scheme_Hierarchy__c sh : [
            SELECT Scheme__c, Account__c, Region__r.Name, Distributor__c, Hub__c
            FROM Scheme_Hierarchy__c
            WHERE Scheme__c IN :schemeIds
              AND IsActive__c = true
        ]) {
            if (!hierarchyMap.containsKey(sh.Scheme__c)) {
                hierarchyMap.put(sh.Scheme__c, new List<Scheme_Hierarchy__c>());
            }
            hierarchyMap.get(sh.Scheme__c).add(sh);
        }

        // Step 5: resolve buyer's Distributor/Hub once, outside the scheme loop.
        Account buyerAccVS = resolveBuyerDistributorInfo(buyerAccountId);
        Id buyerDistributorIdVS = buyerAccVS != null ? buyerAccVS.Distributor__c : null;
        String buyerHubVS = (buyerAccVS != null && buyerAccVS.Distributor__r != null)
            ? buyerAccVS.Distributor__r.Hub__c : null;

        // Fetch slabs for Flat Discount schemes only — ordered ascending by
        // For_Amount__c so getBestSlabForAmount() can pick the best match.
        Set<Id> flatDiscountSchemeIds = new Set<Id>();
        for (Scheme__c s : schemes) {
            if (s.Type__c == 'Flat Discount') {
                flatDiscountSchemeIds.add(s.Id);
            }
        }

        Map<Id, List<Scheme_Slab__c>> slabsByScheme = new Map<Id, List<Scheme_Slab__c>>();
        if (!flatDiscountSchemeIds.isEmpty()) {
            for (Scheme_Slab__c slab : [
                SELECT Scheme__c, For_Amount__c, Cash_Discount__c, Discount_Percent__c
                FROM Scheme_Slab__c
                WHERE Scheme__c IN :flatDiscountSchemeIds
                ORDER BY For_Amount__c ASC
            ]) {
                if (!slabsByScheme.containsKey(slab.Scheme__c)) {
                    slabsByScheme.put(slab.Scheme__c, new List<Scheme_Slab__c>());
                }
                slabsByScheme.get(slab.Scheme__c).add(slab);
            }
        }

        // Build response
        for (Scheme__c s : schemes) {

            // Retailer / SS applicability
            if (isUnderSS && !s.Under_SS_Scheme__c) continue;
            if (!isUnderSS && !s.Retailer_Scheme__c) continue;

            // Hierarchy check
            List<Scheme_Hierarchy__c> hierarchy = hierarchyMap.get(s.Id);
            if (hierarchy != null && !hierarchy.isEmpty()) {
                Boolean hierarchyMatch = isSchemeApplicable(hierarchy, buyerAccountId, buyerRegion, buyerDistributorIdVS, buyerHubVS);
                if (!hierarchyMatch) {
                    continue;
                }
            }

            Boolean eligible;

            if (s.Type__c == 'Flat Discount') {
                // Eligible once the QUALIFYING (matched Product/Brand) subtotal clears at
                // least the lowest slab's For Amount — falls back to the whole cart total
                // for schemes with no Scheme_Applicability__c rows (global schemes).
                Decimal qualifyingSubtotal = computeQualifyingSubtotal(s.Id, cartLines, totalCartPrice);
                Scheme_Slab__c bestSlab = getBestSlabForAmount(slabsByScheme.get(s.Id), qualifyingSubtotal);
                eligible = bestSlab != null;
            } else {
                eligible = totalCartPrice >= s.Cart_Amount__c;
            }

            SchemeDetailsWrapper wrapper = new SchemeDetailsWrapper(
                s.Id,
                s.Name,
                eligible,
                false,
                s.Other_Product_Quantity__c
            );
            response.add(wrapper);
        }

        return response;
    }

    // Returns the highest-For_Amount__c slab whose For_Amount__c is <= cartTotal
    // (the best slab the cart currently qualifies for), or null if the cart total
    // doesn't clear even the lowest slab. Assumes slabs is already ordered
    // ascending by For_Amount__c (as queried above and in getAppliedValueScheme),
    // so the last qualifying slab in the list is the best one.
    private static Scheme_Slab__c getBestSlabForAmount(List<Scheme_Slab__c> slabs, Decimal cartTotal) {
        if (slabs == null || slabs.isEmpty() || cartTotal == null) {
            return null;
        }
        Scheme_Slab__c best;
        for (Scheme_Slab__c slab : slabs) {
            if (slab.For_Amount__c != null && cartTotal >= slab.For_Amount__c) {
                best = slab;
            }
        }
        return best;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getEligibleQuantitySchemeProductIds — bulk eligibility check used by the
    // order/cart page to decide, PER PRODUCT ROW, whether the "Apply Quantity
    // Scheme" button should even be shown. Mirrors getqualityScheme()'s
    // retailer/region hierarchy filtering exactly, but for many products in one
    // call instead of one Apex round-trip per row, and without the minQty
    // eligibility (that's a runtime/quantity concern shown inside the modal,
    // not a button-visibility concern). Returns only the product Ids that have
    // at least one active Quantity_scheme applicable to this buyer.
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static List<Id> getEligibleQuantitySchemeProductIds(
        List<Id> productIds,
        Id buyerAccountId,
        String buyerRegion,
        Boolean isUnderSS
    ) {
        // AuraEnabled methods can't return Set<Id> directly (unsupported return
        // type for Aura/LWC serialization) — dedup internally with a Set, then
        // convert to a List right before returning.
        Set<Id> eligibleProductIds = new Set<Id>();

        if (productIds == null || productIds.isEmpty()
            || buyerAccountId == null || String.isBlank(buyerRegion)) {
            return new List<Id>(eligibleProductIds);
        }

        Date today = System.today();

        List<Scheme__c> schemes = [
            SELECT Id, Product__c, Retailer_Scheme__c, Under_SS_Scheme__c
            FROM Scheme__c
            WHERE Product__c IN :productIds
              AND Is_Active__c = true
              AND RecordType.DeveloperName = 'Quantity_scheme'
              AND Scheme_Start_Date__c <= :today
              AND Scheme_End_Date__c >= :today
        ];

        if (schemes.isEmpty()) {
            return new List<Id>(eligibleProductIds);
        }

        Set<Id> schemeIds = new Set<Id>();
        for (Scheme__c s : schemes) {
            schemeIds.add(s.Id);
        }

        Map<Id, List<Scheme_Hierarchy__c>> hierarchyByScheme = new Map<Id, List<Scheme_Hierarchy__c>>();
        for (Scheme_Hierarchy__c sh : [
            SELECT Scheme__c, Account__c, Region__c, Region__r.Name, Distributor__c, Hub__c
            FROM Scheme_Hierarchy__c
            WHERE Scheme__c IN :schemeIds
              AND IsActive__c = true
        ]) {
            if (!hierarchyByScheme.containsKey(sh.Scheme__c)) {
                hierarchyByScheme.put(sh.Scheme__c, new List<Scheme_Hierarchy__c>());
            }
            hierarchyByScheme.get(sh.Scheme__c).add(sh);
        }

        // Step 5: resolve buyer's Distributor/Hub once, outside the scheme loop.
        Account buyerAccEQ = resolveBuyerDistributorInfo(buyerAccountId);
        Id buyerDistributorIdEQ = buyerAccEQ != null ? buyerAccEQ.Distributor__c : null;
        String buyerHubEQ = (buyerAccEQ != null && buyerAccEQ.Distributor__r != null)
            ? buyerAccEQ.Distributor__r.Hub__c : null;

        for (Scheme__c scheme : schemes) {
            if (eligibleProductIds.contains(scheme.Product__c)) {
                continue; // already confirmed eligible via another matching scheme
            }

            if (isUnderSS && !scheme.Under_SS_Scheme__c) continue;
            if (!isUnderSS && !scheme.Retailer_Scheme__c) continue;

            List<Scheme_Hierarchy__c> hierarchy = hierarchyByScheme.get(scheme.Id);

            if (hierarchy == null || hierarchy.isEmpty()) {
                eligibleProductIds.add(scheme.Product__c);
                continue;
            }

            if (isSchemeApplicable(hierarchy, buyerAccountId, buyerRegion, buyerDistributorIdEQ, buyerHubEQ)) {
                eligibleProductIds.add(scheme.Product__c);
            }
        }

        return new List<Id>(eligibleProductIds);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hasEligibleValueScheme — same idea as getEligibleQuantitySchemeProductIds,
    // but for the cart-level "Apply Value Scheme" button: is there ANY active
    // Value_Scheme applicable to this buyer's retailer/region at all, regardless
    // of whether the current cart total already clears the threshold (that's a
    // separate "not eligible yet" message shown inside the modal after click).
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static Boolean hasEligibleValueScheme(
        Id buyerAccountId,
        String buyerRegion,
        Boolean isUnderSS
    ) {
        if (buyerAccountId == null || String.isBlank(buyerRegion)) {
            return false;
        }

        Date today = System.today();

        List<Scheme__c> schemes = [
            SELECT Id, Retailer_Scheme__c, Under_SS_Scheme__c
            FROM Scheme__c
            WHERE Is_Active__c = true
              AND RecordType.DeveloperName = 'Value_Scheme'
              AND Scheme_Start_Date__c <= :today
              AND Scheme_End_Date__c >= :today
              AND (Cart_Amount__c != null OR Type__c = 'Flat Discount')
        ];

        if (schemes.isEmpty()) {
            return false;
        }

        Set<Id> schemeIds = new Set<Id>();
        for (Scheme__c s : schemes) {
            schemeIds.add(s.Id);
        }

        Map<Id, List<Scheme_Hierarchy__c>> hierarchyMap = new Map<Id, List<Scheme_Hierarchy__c>>();
        for (Scheme_Hierarchy__c sh : [
            SELECT Scheme__c, Account__c, Region__r.Name, Distributor__c, Hub__c
            FROM Scheme_Hierarchy__c
            WHERE Scheme__c IN :schemeIds
              AND IsActive__c = true
        ]) {
            if (!hierarchyMap.containsKey(sh.Scheme__c)) {
                hierarchyMap.put(sh.Scheme__c, new List<Scheme_Hierarchy__c>());
            }
            hierarchyMap.get(sh.Scheme__c).add(sh);
        }

        // Step 5: resolve buyer's Distributor/Hub once, outside the scheme loop.
        Account buyerAccHE = resolveBuyerDistributorInfo(buyerAccountId);
        Id buyerDistributorIdHE = buyerAccHE != null ? buyerAccHE.Distributor__c : null;
        String buyerHubHE = (buyerAccHE != null && buyerAccHE.Distributor__r != null)
            ? buyerAccHE.Distributor__r.Hub__c : null;

        for (Scheme__c s : schemes) {
            System.debug('=== HE loop scheme=' + s.Id + ' isUnderSS=' + isUnderSS + ' Under_SS_Scheme__c=' + s.Under_SS_Scheme__c + ' Retailer_Scheme__c=' + s.Retailer_Scheme__c);
            if (isUnderSS && !s.Under_SS_Scheme__c) continue;
            if (!isUnderSS && !s.Retailer_Scheme__c) continue;

            List<Scheme_Hierarchy__c> hierarchy = hierarchyMap.get(s.Id);
            System.debug('=== HE scheme=' + s.Id + ' hierarchyRows=' + (hierarchy == null ? 0 : hierarchy.size())
                + ' buyerDistributorIdHE=' + buyerDistributorIdHE + ' buyerHubHE=' + buyerHubHE);

            if (hierarchy == null || hierarchy.isEmpty()) {
                return true;
            }
            Boolean matchHE = isSchemeApplicable(hierarchy, buyerAccountId, buyerRegion, buyerDistributorIdHE, buyerHubHE);
            System.debug('=== HE isSchemeApplicable match=' + matchHE);
            if (matchHE) {
                return true;
            }
        }

        System.debug('=== HE falling through to false, schemes.size()=' + schemes.size());
        return false;
    }
}