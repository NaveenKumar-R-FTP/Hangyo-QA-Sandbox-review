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
            SELECT Scheme__c, Account__c, Region__c,Region__r.Name
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
            if (isSchemeApplicable(hierarchy, buyerAccountId, buyerRegion)) {
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
    
    public static Boolean isSchemeApplicable(
        List<Scheme_Hierarchy__c> records,
        Id buyerAccountId,
        String buyerRegion
    ) {
        Boolean accountRegionMatch = false;
        Boolean accountOnlyMatch   = false;
        Boolean regionOnlyMatch    = false;
    
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
        }
    
        return accountRegionMatch || accountOnlyMatch || regionOnlyMatch;
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
        Id buyerAccountId,
        String buyerRegion,
        Boolean isUnderSS
    ) {
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
              AND Cart_Amount__c != null
        ];
    
        if (schemes.isEmpty()) return response;
    
        // Fetch hierarchy
        Set<Id> schemeIds = new Set<Id>();
        for (Scheme__c s : schemes) schemeIds.add(s.Id);
    
        Map<Id, List<Scheme_Hierarchy__c>> hierarchyMap = new Map<Id, List<Scheme_Hierarchy__c>>();
        for (Scheme_Hierarchy__c sh : [
            SELECT Scheme__c, Account__c, Region__r.Name
            FROM Scheme_Hierarchy__c
            WHERE Scheme__c IN :schemeIds
              AND IsActive__c = true
        ]) {
            if (!hierarchyMap.containsKey(sh.Scheme__c)) {
                hierarchyMap.put(sh.Scheme__c, new List<Scheme_Hierarchy__c>());
            }
            hierarchyMap.get(sh.Scheme__c).add(sh);
        }
    
        // Build response
        for (Scheme__c s : schemes) {
    
            // Retailer / SS applicability
            if (isUnderSS && !s.Under_SS_Scheme__c) continue;
            if (!isUnderSS && !s.Retailer_Scheme__c) continue;
    
            // Hierarchy check
            List<Scheme_Hierarchy__c> hierarchy = hierarchyMap.get(s.Id);
            if (hierarchy != null && !hierarchy.isEmpty()) {
                if (!isSchemeApplicable(hierarchy, buyerAccountId, buyerRegion)) {
                    continue;
                }
            }
    
            Boolean eligible = totalCartPrice >= s.Cart_Amount__c;
    
            response.add(
                new SchemeDetailsWrapper(
                    s.Id,
                    s.Name,
                    eligible,
                    false,
                    s.Other_Product_Quantity__c
                )
            );
        }
    
        return response;
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
            SELECT Scheme__c, Account__c, Region__c, Region__r.Name
            FROM Scheme_Hierarchy__c
            WHERE Scheme__c IN :schemeIds
              AND IsActive__c = true
        ]) {
            if (!hierarchyByScheme.containsKey(sh.Scheme__c)) {
                hierarchyByScheme.put(sh.Scheme__c, new List<Scheme_Hierarchy__c>());
            }
            hierarchyByScheme.get(sh.Scheme__c).add(sh);
        }

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

            if (isSchemeApplicable(hierarchy, buyerAccountId, buyerRegion)) {
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
              AND Cart_Amount__c != null
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
            SELECT Scheme__c, Account__c, Region__r.Name
            FROM Scheme_Hierarchy__c
            WHERE Scheme__c IN :schemeIds
              AND IsActive__c = true
        ]) {
            if (!hierarchyMap.containsKey(sh.Scheme__c)) {
                hierarchyMap.put(sh.Scheme__c, new List<Scheme_Hierarchy__c>());
            }
            hierarchyMap.get(sh.Scheme__c).add(sh);
        }

        for (Scheme__c s : schemes) {
            if (isUnderSS && !s.Under_SS_Scheme__c) continue;
            if (!isUnderSS && !s.Retailer_Scheme__c) continue;

            List<Scheme_Hierarchy__c> hierarchy = hierarchyMap.get(s.Id);

            if (hierarchy == null || hierarchy.isEmpty()) {
                return true;
            }
            if (isSchemeApplicable(hierarchy, buyerAccountId, buyerRegion)) {
                return true;
            }
        }

        return false;
    }
}