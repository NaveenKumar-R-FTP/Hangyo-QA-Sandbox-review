/**
* Class Name  : SecondaryOrderComponentController
* Test Class  : SecondaryOrderComponentControllerTest
* author      : Mirza
* CreatedDate : 04-03-25
* Description : Created for to fetchProducts,save Order and Orderline items and Etc, Used in 'CreateSecondaryOrderComponentDms' Component
* */
public without sharing class SecondaryOrderComponentController {
    
    @AuraEnabled
    public static String fetchProducts(String searchValue ,String brandFilter,List<Id> retailerSelected,String stockFilter, String searchBy){
        System.debug('searchValue=>' + searchValue);
        List<Product__c> productList = new List<Product__c>();
        List<ProductDataWrapper> productWrapper = new List<ProductDataWrapper>();
        Set<Id> productIds = new Set<Id>();
        
        //to fetch distributor primary state
        Id userId = UserInfo.getUserId();
        Id distributorAccId;
        Id conId = [SELECT ContactId FROM User WHERE Id = :userId].ContactId;
        if (conId !=null){
            Contact contact = [SELECT AccountId FROM Contact WHERE Id = :conId LIMIT 1];
            
            if (contact.AccountId != null) {
                distributorAccId=contact.AccountId;
            }
        }
        
        String distributorUserState = '';
        if(distributorAccId != NULL){
            Account distributorAcc= [SELECT Id,Primary_State__c FROM Account WHERE Id =: distributorAccId];
            distributorUserState = distributorAcc.Primary_State__c;
        }
        
        String retailerUserState ='';
        Account retailerAcc= [SELECT Id,Primary_State__c FROM Account WHERE Id IN: retailerSelected];
        retailerUserState = retailerAcc.Primary_State__c;
        System.debug('retailerUserState :-'+retailerUserState);
        Map<String, Id> pricebookMap = new Map<String, Id>();
        Id selectedPricebookId;

        for (Price_Book__c pb : [SELECT Id, Name ,Region__r.name FROM Price_Book__c WHERE isActive__c = TRUE]) {
            pricebookMap.put(pb.Region__c, pb.Id); // Store pricebook by Region__c
            if (pb.Region__r.name == retailerUserState) {
                selectedPricebookId = pb.Id;
            }
        }
        System.debug('selectedPricebookId :-'+selectedPricebookId);
        
        if (selectedPricebookId == null) {
            System.debug('No valid pricebook found for retailerUserState: ' + retailerUserState);
            return JSON.serialize(new List<ProductDataWrapper>());
        }
        
        Map<Id, Set<Price_Book_Entry__c>> productPriceBookMap = new Map<Id, Set<Price_Book_Entry__c>>();
        Map<Id, Decimal> stateSpecificPriceMap = new Map<Id, Decimal>();
        
        List<Price_Book_Entry__c> priceEntries = [SELECT Product__c, PTR__c, Price_Book__c FROM Price_Book_Entry__c 
            WHERE isActive__c = TRUE  AND Price_Book__c = :selectedPricebookId AND Type__c = 'Retailer'
        ];
        System.debug('priceEntries :-'+priceEntries);
        
        for (Price_Book_Entry__c pbe : priceEntries) {
            if (!productPriceBookMap.containsKey(pbe.Product__c)) {
                productPriceBookMap.put(pbe.Product__c, new Set<Price_Book_Entry__c>());
            }
            productPriceBookMap.get(pbe.Product__c).add(pbe);
            productIds.add(pbe.Product__c);
            // Store price for the state-matching pricebook
            /*if (pbe.Price_Book__c == selectedPricebookId) {
                Decimal roundedPTR = pbe.PTR__c.setScale(2, System.RoundingMode.HALF_UP);
                stateSpecificPriceMap.put(pbe.Product__c, roundedPTR);
            }*/
            if (pbe.Price_Book__c == selectedPricebookId) {
                if (pbe.PTR__c != null) {
                    Decimal roundedPTR = pbe.PTR__c.setScale(2, System.RoundingMode.HALF_UP);
                    stateSpecificPriceMap.put(pbe.Product__c, roundedPTR);
                } else {
                    System.debug('PTR__c is NULL for Product ' + pbe.Product__c + ' in Pricebook ' + pbe.Price_Book__c);            
                    stateSpecificPriceMap.put(pbe.Product__c, 0);
                }
            }

        }
        System.debug('productIds :-'+productIds);
        System.debug('productPriceBookMap :-'+productPriceBookMap);
        
        Id productRecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Product' AND SObjectType = 'Product__c' LIMIT 1].Id;
        if (productIds.isEmpty()) {
            return JSON.serialize(productWrapper);
        }
        String query = 'SELECT Id, Name, IsActive__c, DisplayURL__c, Focus_Product__c, Image__c, ' +
            'Validity_Start_Date__c, Validity_End_Date__c, Unit_of_Measure__c,MRP__c ,' +
            'Category_Code__c, Category_Name__c, Product_Code__c , Product_Brand__c, Image_Long__c ' +
            'FROM Product__c WHERE Id IN :productIds AND IsActive__c = TRUE ' +
            'AND Secondary_Product__c = TRUE AND RecordTypeId = :productRecordTypeId';
        
        String codeSearchPattern = null;
        if (String.isBlank(searchBy)) {
            searchBy = 'Name';
        }
        if (String.isNotBlank(searchValue)) {
            if (searchBy == 'Code') {
                codeSearchPattern = searchValue.trim() + '%';
                query += ' AND Category_Code__c LIKE :codeSearchPattern';
            } else {
                searchValue = '%' + searchValue + '%';
                query += ' AND (Name LIKE :searchValue OR Product_Brand__c LIKE :searchValue)';
            }
        } else {
            query += ' AND (Name != null AND Product_Brand__c != null)';
        }
        if (brandFilter != null && brandFilter != '' && brandFilter != 'Available Stock') {
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

        productList = Database.query(query);
        system.debug('productList123'+productList);
        
        //Query inventory by distributor and product
        Map<Id, Decimal> productIdToQtyMap = new Map<Id, Decimal>();
        if (distributorAccId != null && !productIds.isEmpty()) {
            for (Inventory__c inv : [
                SELECT Product__c, Quantity_in_Hand__c 
                FROM Inventory__c 
                WHERE Distributor_Name__c = :distributorAccId 
                AND Product__c IN :productIds
            ]) {
                productIdToQtyMap.put(inv.Product__c, inv.Quantity_in_Hand__c);
            }
        }
        
        for(Product__c master : productList){
            ProductDataWrapper pw = new ProductDataWrapper();
            pw.productId = master.Id;
            if (master.IsActive__c && master.Image_Long__c != null && master.Image_Long__c !='') {
                Decimal availableQty = productIdToQtyMap.containsKey(master.Id) ? productIdToQtyMap.get(master.Id) : 0;
                if (stockFilter == 'Available Stock' && availableQty <= 0) {
                    continue; // skip products with zero stock
                }
                pw.productShortDescription = master.Name;
                pw.productBrand = master.Product_Brand__c;
                pw.sellebleSKU = '';
                // Get price dynamically from selected state pricebook (or set to 0)
                pw.productListPrice = stateSpecificPriceMap.containsKey(master.Id) ? stateSpecificPriceMap.get(master.Id) : 0;
                pw.productOfferPrice = pw.productListPrice; 
                pw.productMrp = master.MRP__c;
                pw.productImages=master.Image_Long__c.split(',');
                pw.productDisplayImage = master.Image_Long__c.split(',')[0];
                pw.retailerState=retailerUserState;
                pw.distributorState=distributorUserState;
                pw.uom=master.Unit_of_Measure__c;
                pw.focusProduct = master.Focus_Product__c; // Add Focus_Product__c to the wrapper
                pw.productCode = master.Product_Code__c;
                
                //Set quantity in hand if available
                if (productIdToQtyMap.containsKey(master.Id)) {
                    pw.availableQuantity = Integer.valueOf(productIdToQtyMap.get(master.Id));
                } else {
                    pw.availableQuantity = 0;
                }
                productWrapper.add(pw);
            }  
        }
        return JSON.serialize(productWrapper);
    }
    
    @AuraEnabled
    public static String fetchFocusedProducts(String searchValue ,String brandFilter, List<String> excludedProductIds,List<Id> retailerSelected,String stockFilter, String searchBy){
        
        List<Product__c> productList = new List<Product__c>();
        List<ProductDataWrapper> productWrapper = new List<ProductDataWrapper>();
        Set<Id> productIds = new Set<Id>();
        //to fetch distributor primary state
        Id userId = UserInfo.getUserId();
        Id distributorAccId;
        Id conId = [SELECT ContactId FROM User WHERE Id = :userId].ContactId;
        // Query the account via the contact associated with the user
        if (conId !=null){
            Contact contact = [
                SELECT AccountId 
                FROM Contact 
                WHERE Id = :conId
                LIMIT 1
            ];
            
            // Retrieve the account if the contact has one
            if (contact.AccountId != null) {
                distributorAccId=contact.AccountId;
            }
        }
        
        String distributorUserState = '';
        if(distributorAccId != NULL){
            Account distributorAcc= [SELECT Id,Primary_State__c FROM Account WHERE Id =: distributorAccId];
            distributorUserState = distributorAcc.Primary_State__c;
        }
        
        //to fetch retailer primary state
        String retailerUserState ='';
        Account retailerAcc= [SELECT Id,Primary_State__c FROM Account WHERE Id IN: retailerSelected];
        retailerUserState = retailerAcc.Primary_State__c;
        System.debug('retailerUserState :-'+retailerUserState);
        // Fetch all active Pricebooks
        Map<String, Id> pricebookMap = new Map<String, Id>();
        
        Id selectedPricebookId;
        
        for (Price_Book__c pb : [SELECT Id, Name ,Region__r.name FROM Price_Book__c WHERE isActive__c = TRUE]) {
            pricebookMap.put(pb.Region__c, pb.Id); // Store pricebook by Region__c
            // Set the selected pricebook if the region matches userState
            if (pb.Region__r.name == retailerUserState) {
                selectedPricebookId = pb.Id;
            }  
        }
        // If no specific pricebook is found, exit early
        if (selectedPricebookId == null) {
            return JSON.serialize(new List<ProductDataWrapper>());
        }
        // Fetch all Active Price Book Entries
        Map<Id, Set<Price_Book_Entry__c>> productPriceBookMap = new Map<Id, Set<Price_Book_Entry__c>>();
        Map<Id, Decimal> stateSpecificPriceMap = new Map<Id, Decimal>();
        
        List<Price_Book_Entry__c> priceEntries = [
            SELECT Product__c, PTR__c, Price_Book__c 
            FROM Price_Book_Entry__c 
            WHERE isActive__c = TRUE  AND Price_Book__c = :selectedPricebookId AND Type__c = 'Retailer'
        ];
        for (Price_Book_Entry__c pbe : priceEntries) {
            if (!productPriceBookMap.containsKey(pbe.Product__c)) {
                productPriceBookMap.put(pbe.Product__c, new Set<Price_Book_Entry__c>());
            }
            productPriceBookMap.get(pbe.Product__c).add(pbe);
            productIds.add(pbe.Product__c);
            // Store price for the state-matching pricebook
            /*if (pbe.Price_Book__c == selectedPricebookId) {
                Decimal roundedPTR = pbe.PTR__c.setScale(2, System.RoundingMode.HALF_UP);
                stateSpecificPriceMap.put(pbe.Product__c, roundedPTR);
            }*/
            if (pbe.Price_Book__c == selectedPricebookId) {

                if (pbe.PTR__c != null) {
                    Decimal roundedPTR =
                        pbe.PTR__c.setScale(2, System.RoundingMode.HALF_UP);
                    stateSpecificPriceMap.put(pbe.Product__c, roundedPTR);
                } else {
                    // Optional: log or default
                    System.debug(
                        'PTR__c is NULL for Product ' + pbe.Product__c +
                        ' in Pricebook ' + pbe.Price_Book__c
                    );
            
                    // Decide business behavior:
                    stateSpecificPriceMap.put(pbe.Product__c, 0);
                }
            }
        }
        
        // Get Product Record Type ID
        Id productRecordTypeId = [
            SELECT Id FROM RecordType 
            WHERE Name = 'Product' AND SObjectType = 'Product__c' 
            LIMIT 1
        ].Id;
        // Query Products (Fetch only products with active pricebook entries)
        if (productIds.isEmpty()) {
            return JSON.serialize(productWrapper);
        }
        String query = 'SELECT Id, Name, IsActive__c, DisplayURL__c, Focus_Product__c, Image__c, ' +
            'Validity_Start_Date__c, Validity_End_Date__c, Unit_of_Measure__c, MRP__c,' +
            'Category_Code__c, Category_Name__c, Product_Code__c , Product_Brand__c, Image_Long__c ' +
            'FROM Product__c WHERE Id IN :productIds AND IsActive__c = TRUE ' +
            'AND Secondary_Product__c = TRUE AND Focus_Product__c = True AND RecordTypeId = :productRecordTypeId';
        
        // added by Fuzail - Search By Name or Code (same as fetchProducts); bind var in scope for Database.query()
        String codeSearchPatternFocus = null;
        if (String.isBlank(searchBy)) {
            searchBy = 'Name';
        }
        if (String.isNotBlank(searchValue)) {
            if (searchBy == 'Code') {
                codeSearchPatternFocus = searchValue.trim() + '%';
                query += ' AND Product_Code__c LIKE :codeSearchPatternFocus';
            } else {
                searchValue = '%' + searchValue + '%';
                query += ' AND (Name LIKE :searchValue OR Product_Brand__c LIKE :searchValue)';
            }
        }
        if (brandFilter != null && brandFilter != '' && brandFilter != 'Available Stock') {
            query += ' AND Product_Brand__c LIKE :brandFilter';
        }
        
        // Exclude products that are already in the cart
        if (excludedProductIds != null && excludedProductIds.size() > 0) {
            query += ' AND Id NOT IN :excludedProductIds';
        }

        // Per-distributor product restriction (deny list).
        Set<Id> deniedProductIds = ProductRestrictionService.getDeniedProductIds(distributorAccId);
        if (!deniedProductIds.isEmpty()) {
            query += ' AND Id NOT IN :deniedProductIds';
        }

        query += ' ORDER BY Name ASC';

        productList = Database.query(query);

        //Query inventory by distributor and product
        Map<Id, Decimal> productIdToQtyMap = new Map<Id, Decimal>();
        if (distributorAccId != null && !productIds.isEmpty()) {
            for (Inventory__c inv : [
                SELECT Product__c, Quantity_in_Hand__c 
                FROM Inventory__c 
                WHERE Distributor_Name__c = :distributorAccId 
                AND Product__c IN :productIds
            ]) {
                productIdToQtyMap.put(inv.Product__c, inv.Quantity_in_Hand__c);
            }
        }
        
        for(Product__c master : productList){
            ProductDataWrapper pw = new ProductDataWrapper();
            pw.productId = master.Id;
            if(master.IsActive__c && master.Image_Long__c != null && master.Image_Long__c !=''){
                Decimal availableQty = productIdToQtyMap.containsKey(master.Id) ? productIdToQtyMap.get(master.Id) : 0;
                if (stockFilter == 'Available Stock' && availableQty <= 0) {
                    continue; // skip products with zero stock
                }
                pw.productShortDescription = master.Name;
                pw.productBrand = master.Product_Brand__c;
                pw.sellebleSKU = '';
                // Get price dynamically from selected state pricebook (or set to 0)
                pw.productListPrice = stateSpecificPriceMap.containsKey(master.Id) ? stateSpecificPriceMap.get(master.Id) : 0;
                pw.productOfferPrice = pw.productListPrice; 
                pw.productMrp = master.MRP__c;
                pw.productImages=master.Image_Long__c.split(',');
                pw.productDisplayImage = master.Image_Long__c.split(',')[0];
                pw.retailerState=retailerUserState;
                pw.distributorState=distributorUserState;
                pw.uom=master.Unit_of_Measure__c;
                pw.focusProduct = master.Focus_Product__c; // Add Focus_Product__c to the wrapper
                pw.productCode = master.Product_Code__c;
                
                //Set quantity in hand if available
                if (productIdToQtyMap.containsKey(master.Id)) {
                    pw.availableQuantity = Integer.valueOf(productIdToQtyMap.get(master.Id));
                } else {
                    pw.availableQuantity = 0;
                }
                productWrapper.add(pw);
            } 
        }
        return JSON.serialize(productWrapper);
    }
    
    //Method for Generating the Proposals
    @AuraEnabled
    public static OrderResponse generateProposal(String productsFromCart, List<Id> retailerSelected, String orderSummary,String orderComment){
        try {
            List<CartProductWrapper.ProductWrapper> mainData = new List<CartProductWrapper.ProductWrapper>();
            mainData = (List<CartProductWrapper.ProductWrapper>)JSON.deserialize(productsFromCart, List<CartProductWrapper.ProductWrapper>.class);
            
            OrderSummaryWrapper orderSummaryData = new OrderSummaryWrapper();
            OrderResponse response = new OrderResponse();
            orderSummaryData = (OrderSummaryWrapper)JSON.deserialize(orderSummary, OrderSummaryWrapper.class);
            RecordType rt = [
                SELECT Id 
                FROM RecordType 
                WHERE SObjectType = 'Order__c' 
                AND Name = 'Secondary Order' 
                LIMIT 1
            ];
            // Get the current user's ID
            // Get the current user's ID
            Id userId = UserInfo.getUserId();
            System.debug('userId Id==>'+UserInfo.getUserId());
            List<Account> retailerAccList = [SELECT Id, Name, RecordType.Name,OwnerId,Primary_State__c FROM Account WHERE Id IN: retailerSelected AND RecordType.Name = 'Retailer' LIMIT 1];
            System.debug('Account Id==>'+retailerAccList);
            
            //Fetch the distributor for the current user
            Id distributorAccId;
            Id conId = [SELECT ContactId FROM User WHERE Id = :userId].ContactId;
            // Query the account via the contact associated with the user
            if (conId !=null){
                Contact contact = [
                    SELECT AccountId 
                    FROM Contact 
                    WHERE Id = :conId
                    LIMIT 1
                ];
                // Retrieve the account if the contact has one
                if (contact.AccountId != null) {
                    distributorAccId=contact.AccountId;
                }
            }
            
            Order__c order = new Order__c();
            if(retailerAccList.size()>0){
                System.debug('Retailer Account Id==>'+retailerAccList);
                order.Account__c = retailerAccList[0].Id;
            }
            if(distributorAccId != NULL){
                System.debug('Distributor Account Id==>'+distributorAccId);
                order.AccountId__c = distributorAccId;
            }
            System.debug('retailerAccList[0].OwnerId==>'+retailerAccList[0].OwnerId);
            //order.Ordered_By__c = UserInfo.getUserId();
            order.Ordered_By__c = retailerAccList[0].OwnerId;
            order.Description__c = orderComment;
            order.Total_order_value__c = orderSummaryData.totalPrice;
            //order.EffectiveDate__c = System.Today();
            if (String.isNotBlank(orderSummaryData.orderDate)) {
                order.EffectiveDate__c = Date.valueOf(orderSummaryData.orderDate);
            } else {
                order.EffectiveDate__c = System.Today();
            }
            order.Status__c = 'Order Placed';
            //order.Total_Discount__c = orderSummaryData.totalDiscount;
            order.Total_Quantity__c = orderSummaryData.totalQuantity;
            order.Type__c='DMS';
            order.RecordTypeId=rt.Id;
            // Persist the actual Sale Type / Price Type the distributor placed the order under —
            // previously these were never written here, so every DMS Secondary Order silently
            // fell back to the field's default value regardless of what was shown on screen.
            order.Sale_Type__c = String.isNotBlank(orderSummaryData.saleType) ? orderSummaryData.saleType : 'Cash Sales';
            order.Price_Type__c = String.isNotBlank(orderSummaryData.priceType) ? orderSummaryData.priceType : 'MRP';
            if(orderSummaryData.valuseSchemeIdOnOrder!=null &&orderSummaryData.valuseSchemeIdOnOrder!=''){
                order.Value_Scheme_Applied__c=orderSummaryData.valuseSchemeIdOnOrder;
            }
            if(orderSummaryData.valueSchemeDiscount!=null){
                order.Value_Scheme_Discount__c= orderSummaryData.valueSchemeDiscount;
            }
            
            if(orderSummaryData.totalDiscountRupees!=null){
                order.Discount_Amount_Order__c=orderSummaryData.totalDiscountRupees;
            }
            if(orderSummaryData.subTotal!=null){
                order.Sub_Total__c=orderSummaryData.subTotal;
            }
            if(orderSummaryData.totalOrderValue!=null){
                order.Price__c=orderSummaryData.totalOrderValue;
            }
            if(orderSummaryData.totalOrderValue!=null){
                order.Price__c=orderSummaryData.totalOrderValue;
            }
            if(orderSummaryData.totalSGST!=null){
                order.totalSGST__c=orderSummaryData.totalSGST;
            }
            if(orderSummaryData.totalCGST!=null){
                order.totalCGST__c=orderSummaryData.totalCGST;
            }
            if(orderSummaryData.totalIGST!=null){
                order.totalIGST__c=orderSummaryData.totalIGST;
            }
            insert order;
            
            
            Set<Id> productIds = new Set<Id>();
            for (CartProductWrapper.ProductWrapper proData : mainData) {
                productIds.add(proData.productId);
            }
            
            Map<Id, Product__c> productMap = new Map<Id, Product__c>(
                [SELECT Id, Rate_Value__c,Unit_of_Measure__c FROM Product__c WHERE Id IN :productIds]);
            
            RecordType rtOl = [
                SELECT Id 
                FROM RecordType 
                WHERE SObjectType = 'Order_Line_Item__c' 
                AND Name = 'Secondary Order Line Item' 
                LIMIT 1
            ];
            
            Order_Line_Item__c orderLineItem;
            List<Order_Line_Item__c> orderLineItemList = new List<Order_Line_Item__c>();
            for(CartProductWrapper.ProductWrapper proData : mainData){
                orderLineItem = new Order_Line_Item__c ();
                orderLineItem.Order__c  = order.Id;
                orderLineItem.RecordTypeId=rtOl.Id;
                orderLineItem.Products__c = proData.productId;   
                orderLineItem.Ordered_Quantity__c   = proData.quantity;
                //orderLineItem.Product_Price__c = proData.productOfferPrice;
                if (proData.isPromotional == true) {
                    orderLineItem.Product_Price__c = proData.productListPrice;
                } else {
                    orderLineItem.Product_Price__c = proData.productOfferPrice;
                }
                orderLineItem.Quantity_Scheme__c = proData.selectedSchemeId; // Correctly reference selectedScheme
                orderLineItem.Is_Promotional__c = proData.isPromotional;
                orderLineItem.Parent_Product__c = proData.parentProductId;
                orderLineItem.Discount_Percentage__c = proData.discountPercentage;
                orderLineItemList.add(orderLineItem);
            }
            insert orderLineItemList;
            
            response.status ='Success';
            response.ordid =order.id;
            return response;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Decimal> getTaxRates(String retailerPrimaryState , String distributorPrimaryState) {
        // Retrieve tax rates from the custom setting based on the state
        Map<String, Decimal> taxRates = new Map<String, Decimal>();
        Order_tax_value__c taxSetting = [SELECT Name , SGST__c, IGST__c, CGST__c FROM Order_tax_value__c WHERE Name = 'General GST Settings' LIMIT 1];
        if(retailerPrimaryState.equalsIgnoreCase(distributorPrimaryState)){
            taxRates.put('CGST', taxSetting.CGST__c);
            taxRates.put('SGST', taxSetting.SGST__c);
        }else{
            taxRates.put('IGST', taxSetting.IGST__c);
        }
        return taxRates;
    }
    
    @AuraEnabled(cacheable=true)
    public static Boolean isOrderDateAllowed() {
        User currentUser = [SELECT Allow_Order_Date_Backdate__c FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        return currentUser.Allow_Order_Date_Backdate__c;
    }
    
    public class ProductDataWrapper{
        @AuraEnabled public String productId{get;set;}
        @AuraEnabled public List<String> productImages{get;set;}
        @AuraEnabled public String productDisplayImage{get;set;}
        @AuraEnabled public String productShortDescription{get;set;}
        @AuraEnabled public String productBrand{get;set;}
        @AuraEnabled public String productLongDescription{get;set;}
        @AuraEnabled public String productReference{get;set;}      
        @AuraEnabled public String sellebleSKU {get;set;}
        @AuraEnabled public Decimal productListPrice{get;set;}
        @AuraEnabled public Integer productQuantity { get; set; }
        @AuraEnabled public Integer availableQuantity { get; set; }
        @AuraEnabled public Decimal productOfferPrice{get;set;}
        @AuraEnabled public Decimal productMrp{get;set;}
        @AuraEnabled public Decimal percentageValue {get;set;}
        @AuraEnabled public Boolean offerIsThere {get;set;}
        @AuraEnabled public String retailerState {get;set;}
        @AuraEnabled public String distributorState {get;set;}
        @AuraEnabled public String uom {get;set;}
        @AuraEnabled public Boolean focusProduct {get;set;}
        @AuraEnabled public String productCode {get;set;}
        
        // Add selectedScheme field
        //  @AuraEnabled public String selectedScheme { get; set; }
        // New field to store the scheme ID
        //  @AuraEnabled public String selectedSchemeId { get; set; }
        
        
        public ProductDataWrapper(){
            productImages = new List<String>();
            productQuantity = 0;
            availableQuantity = 0;
        }
    }
    
    public class OrderResponse {
        @AuraEnabled public String status;  // To return 'success' or other status
        @AuraEnabled public String ordid;  // To return the orderId
    }
    
    public class OrderSummaryWrapper{
        public Integer totalItems;  //0
        public decimal totalPrice;  //0
        public decimal totalDiscount;   //0
        public decimal totalOrderValue; //0
        public Integer totalQuantity;   //0
        public String valuseSchemeIdOnOrder;   //0
        public decimal totalDiscountRupees;   //0
        public decimal totalDiscountGiverByUser;
        public decimal subTotal;   //0
        public decimal totalSGST;
        public decimal totalCGST;
        public decimal totalIGST;
        public String orderDate;
        public decimal valueSchemeDiscount;
        public String saleType;
        public String priceType;
        public OrderSummaryWrapper parse(String json){
            return (OrderSummaryWrapper) System.JSON.deserialize(json, OrderSummaryWrapper.class);
        }
    }
}