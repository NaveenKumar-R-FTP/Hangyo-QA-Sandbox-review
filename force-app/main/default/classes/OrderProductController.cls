/**
* Class Name  : OrderProductController
* Test Class  : OrderProductControllerTest
* author      : Ashwini
* CreatedDate : 31-12-24
* Description : Created for to fetchProducts,save Order and Orderline items and Etc, Used in 'CreateOrderComponent' Component
* */

public without sharing class OrderProductController {
    //This method is to fetchProducts to show products
    @AuraEnabled
    public static String fetchProducts(String searchValue ,String brandFilter,String visitTaskIdSelected){
        
        List<Product__c> productList = new List<Product__c>();
        List<ProductDataWrapper> productWrapper = new List<ProductDataWrapper>();
        Set<Id> productIds = new Set<Id>();
        
        String userState ='';
        Visit_Task__c visitTask = [SELECT Id,Account__c FROM Visit_Task__c WHERE Id = :visitTaskIdSelected LIMIT 1];
        Account acc= [select id,Primary_State__c,Distributor__c,Distributor__r.Primary_State__c from Account where Id=:visitTask.Account__c];
               
        String rtlrState    =   String.isNotBlank(acc.Primary_State__c) ? acc.Primary_State__c : '';
        String  distState  =   String.isNotBlank(acc.Distributor__r.Primary_State__c) ? acc.Distributor__r.Primary_State__c : '';      
        String taxComp = (String.isNotBlank(distState) && String.isNotBlank(rtlrState) && distState.equalsIgnoreCase(rtlrState))? 'state matching': 'state not matching';
               
        // Fetch all active Pricebooks
        Map<String, Id> pricebookMap = new Map<String, Id>();
        Id selectedPricebookId;
        
        for (Price_Book__c pb : [SELECT Id, Name ,Region__r.name FROM Price_Book__c WHERE isActive__c = TRUE]) {
            pricebookMap.put(pb.Region__c, pb.Id); // Store pricebook by Region__c
            // Set the selected pricebook if the region matches userState
            if (pb.Region__r.name == rtlrState) {
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
            if (pbe.Price_Book__c == selectedPricebookId) {
                Decimal roundedPTR = pbe.PTR__c.setScale(2, System.RoundingMode.HALF_UP);
                
                stateSpecificPriceMap.put(pbe.Product__c, roundedPTR);
            }
        }
        
        
        
        // Get Product Record Type ID
        Id productRecordTypeId = [
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Product' AND SObjectType = 'Product__c' 
            LIMIT 1
        ].Id;
        // Query Products (Fetch only products with active pricebook entries)
        if (productIds.isEmpty()) {
            return JSON.serialize(productWrapper);
        }
        String query = 'SELECT Id, Name, IsActive__c, DisplayURL__c, Focus_Product__c, Image__c, ' +
            'Validity_Start_Date__c, Validity_End_Date__c, Unit_of_Measure__c, ' +
            'Category_Code__c, Category_Name__c, Product_Code__c , Product_Brand__c, Image_Long__c, MRP__c ' +
            'FROM Product__c WHERE Id IN :productIds AND IsActive__c = TRUE ' +
            'AND Secondary_Product__c = TRUE AND RecordTypeId = :productRecordTypeId';
        
        if (searchValue != null && searchValue != '') {
            searchValue = '%' + searchValue + '%';  
            query += ' AND (Name LIKE :searchValue OR Product_Brand__c LIKE :searchValue)';   
        }
        if (brandFilter != null && brandFilter != '') {
            query += ' AND Product_Brand__c LIKE :brandFilter';
        }

        // Per-distributor product restriction (deny list).
        Set<Id> deniedProductIds = ProductRestrictionService.getDeniedProductIds(acc.Distributor__c);
        if (!deniedProductIds.isEmpty()) {
            query += ' AND Id NOT IN :deniedProductIds';
        }

        query += ' ORDER BY Name ASC';
        productList = Database.query(query);
        
        // Fetch inventory for distributor
        Map<Id, Decimal> distributorInventoryMap = new Map<Id, Decimal>();
        if (acc.Distributor__c != null) {
            for (Inventory__c inv : [SELECT Product__c, Quantity_in_Hand__c 
                                     FROM Inventory__c 
                                     WHERE Distributor_Name__c = :acc.Distributor__c AND Product__c IN :productIds]) {
                distributorInventoryMap.put(inv.Product__c, inv.Quantity_in_Hand__c);
            }
        }        
        System.debug('distributorInventoryMap:- '+distributorInventoryMap);
        
        // Get allowed product codes from custom label
        Set<String> allowedProductCodes = new Set<String>();
        if (String.isNotBlank(Label.Product_Code)) {
            allowedProductCodes.addAll(Label.Product_Code.split(',')); // Assuming CSV format in custom label
        }
        System.debug('allowedProductCodes:- '+allowedProductCodes);
        
        for(Product__c master : productList){
            ProductDataWrapper pw = new ProductDataWrapper();
            pw.productId = master.Id;
            if (master.IsActive__c && master.Image_Long__c != null && master.Image_Long__c !='') {                
                pw.productShortDescription = master.Name;
                pw.productBrand = master.Product_Brand__c;               
                pw.sellebleSKU = '';
                // Get price dynamically from selected state pricebook (or set to 0)
                pw.productListPrice = stateSpecificPriceMap.containsKey(master.Id) ? stateSpecificPriceMap.get(master.Id) : 0;
                pw.productOfferPrice = pw.productListPrice;                 
                pw.productImages=master.Image_Long__c.split(',');
                pw.productDisplayImage = master.Image_Long__c.split(',')[0];
                pw.state=taxComp;
                pw.productMRP = master.MRP__c;
                pw.uom=master.Unit_of_Measure__c;
                pw.focusProduct = master.Focus_Product__c; // Add Focus_Product__c to the wrapper
                pw.productCode = master.Product_Code__c;
                // Only add availableQuantity if product code is in custom label
                if (allowedProductCodes.contains(master.Product_Code__c)) {
                    pw.availableQuantity = distributorInventoryMap.containsKey(master.Id) 
                                           ? Integer.valueOf(distributorInventoryMap.get(master.Id)) 
                                           : 0;
                    pw.availableQuantitySent = true;
                }else{
                    pw.availableQuantitySent = false;
                }
                productWrapper.add(pw);               
            }            
        }
        return JSON.serialize(productWrapper);
    }
    
    //This method is to fetchFocusedProducts to show products
    
    @AuraEnabled
    public static String fetchFocusedProducts(String searchValue ,String brandFilter, List<String> excludedProductIds,String visitTaskIdSelected){
        
        List<Product__c> productList = new List<Product__c>();
        List<ProductDataWrapper> productWrapper = new List<ProductDataWrapper>();
        Set<Id> productIds = new Set<Id>();
        String userState ='';
        Visit_Task__c visitTask = [SELECT Id,Account__c FROM Visit_Task__c WHERE Id = :visitTaskIdSelected LIMIT 1];
        Account acc= [select id,Primary_State__c,Distributor__c,Distributor__r.Primary_State__c from Account where Id=:visitTask.Account__c];
            
        String rtlrState    =   String.isNotBlank(acc.Primary_State__c) ? acc.Primary_State__c : '';
        String  distState  =   String.isNotBlank(acc.Distributor__r.Primary_State__c) ? acc.Distributor__r.Primary_State__c : '';      
        String taxComp = (String.isNotBlank(distState) && String.isNotBlank(rtlrState) && distState.equalsIgnoreCase(rtlrState))? 'state matching': 'state not matching';
                
        // Fetch all active Pricebooks
        Map<String, Id> pricebookMap = new Map<String, Id>();
                
        Id selectedPricebookId;        
        for (Price_Book__c pb : [SELECT Id, Name ,Region__r.name FROM Price_Book__c WHERE isActive__c = TRUE]) {
            pricebookMap.put(pb.Region__c, pb.Id); // Store pricebook by Region__c
            // Set the selected pricebook if the region matches userState
            if (pb.Region__r.name == rtlrState) {
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
            if (pbe.Price_Book__c == selectedPricebookId) {
                Decimal roundedPTR = pbe.PTR__c.setScale(2, System.RoundingMode.HALF_UP);
                
                stateSpecificPriceMap.put(pbe.Product__c, roundedPTR);
            }
        }
        
        // Get Product Record Type ID
        Id productRecordTypeId = [
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Product' AND SObjectType = 'Product__c' 
            LIMIT 1
        ].Id;
        
        // Query Products (Fetch only products with active pricebook entries)
        if (productIds.isEmpty()) {
            return JSON.serialize(productWrapper);
        }
        String query = 'SELECT Id, Name, IsActive__c, DisplayURL__c, Focus_Product__c, Image__c, ' +
            'Validity_Start_Date__c, Validity_End_Date__c, Unit_of_Measure__c, ' +
            'Category_Code__c, Category_Name__c, Product_Code__c , Product_Brand__c, Image_Long__c, MRP__c ' +
            'FROM Product__c WHERE Id IN :productIds AND IsActive__c = TRUE ' +
            'AND Secondary_Product__c = TRUE AND Focus_Product__c = True AND RecordTypeId = :productRecordTypeId';
        
        if (searchValue != null && searchValue != '') {
            searchValue = '%' + searchValue + '%';  
            query += ' AND (Name LIKE :searchValue OR Product_Brand__c LIKE :searchValue)';  
        }
        if (brandFilter != null && brandFilter != '') {
            query += ' AND Product_Brand__c LIKE :brandFilter';
        }
        
        // Exclude products that are already in the cart
        if (excludedProductIds != null && excludedProductIds.size() > 0) {
            query += ' AND Id NOT IN :excludedProductIds';
        }

        // Per-distributor product restriction (deny list).
        Set<Id> deniedProductIds = ProductRestrictionService.getDeniedProductIds(acc.Distributor__c);
        if (!deniedProductIds.isEmpty()) {
            query += ' AND Id NOT IN :deniedProductIds';
        }

        query += ' ORDER BY Name ASC';

        productList = Database.query(query);
        
        // Fetch inventory for distributor
        Map<Id, Decimal> distributorInventoryMap = new Map<Id, Decimal>();
        if (acc.Distributor__c != null) {
            for (Inventory__c inv : [SELECT Product__c, Quantity_in_Hand__c 
                                     FROM Inventory__c 
                                     WHERE Distributor_Name__c = :acc.Distributor__c AND Product__c IN :productIds]) {
                distributorInventoryMap.put(inv.Product__c, inv.Quantity_in_Hand__c);
            }
        }
        
        // Get allowed product codes from custom label
        Set<String> allowedProductCodes = new Set<String>();
        if (String.isNotBlank(Label.Product_Code)) {
            allowedProductCodes.addAll(Label.Product_Code.split(',')); // Assuming CSV format in custom label
        }
        
        for(Product__c master : productList){
            ProductDataWrapper pw = new ProductDataWrapper();
            pw.productId = master.Id;
            if(master.IsActive__c && master.Image_Long__c != null && master.Image_Long__c !=''){
                pw.productShortDescription = master.Name;
                pw.productBrand = master.Product_Brand__c;                
                pw.sellebleSKU = '';
                // Get price dynamically from selected state pricebook (or set to 0)
                pw.productListPrice = stateSpecificPriceMap.containsKey(master.Id) ? stateSpecificPriceMap.get(master.Id) : 0;
                pw.productOfferPrice = pw.productListPrice;                 
                pw.productImages=master.Image_Long__c.split(',');
                pw.productDisplayImage = master.Image_Long__c.split(',')[0];
                pw.state=taxComp; 
                pw.productMRP = master.MRP__c;
                pw.uom=master.Unit_of_Measure__c;
                pw.focusProduct = master.Focus_Product__c; // Add Focus_Product__c to the wrapper
                pw.productCode = master.Product_Code__c;
                // Only add availableQuantity if product code is in custom label
                if (allowedProductCodes.contains(master.Product_Code__c)) {
                    pw.availableQuantity = distributorInventoryMap.containsKey(master.Id) 
                                           ? Integer.valueOf(distributorInventoryMap.get(master.Id)) 
                                           : 0;
                    pw.availableQuantitySent = true;
                }else{
                    pw.availableQuantitySent = false;
                }              
                productWrapper.add(pw);               
            }            
        }       
        return JSON.serialize(productWrapper);
    }
    
    public class VisitTaskContextWrapper {
        @AuraEnabled public Id selectedAccountId;
        @AuraEnabled public String buyerRegion;
        @AuraEnabled public Id retailerId;
        @AuraEnabled public String retailerName;
    }

    @AuraEnabled(cacheable=true)
    public static VisitTaskContextWrapper getVisitTaskContext(Id visitTaskId) {

        if (visitTaskId == null) {
            throw new AuraHandledException('visitTaskId is required');
        }

        Visit_Task__c vt = [
            SELECT Id,
                   Account__c,
                   Account__r.Name,
                   Retailer__c,
                   Retailer__r.Name,
                   Retailer__r.Primary_State__c
            FROM Visit_Task__c
            WHERE Id = :visitTaskId
            LIMIT 1
        ];

        VisitTaskContextWrapper ctx = new VisitTaskContextWrapper();
        ctx.selectedAccountId = vt.Retailer__c; // ✅ Retailer Account
        ctx.buyerRegion = vt.Retailer__r != null
            ? vt.Retailer__r.Primary_State__c
            : null;

        ctx.retailerId = vt.Retailer__c;
        ctx.retailerName = vt.Retailer__r != null ? vt.Retailer__r.Name : null;

        return ctx;
    }
    
    //This method is to getAllActiveQualityScheme
    @AuraEnabled
    public static List<Scheme__c> getAllActiveQualityScheme() {
        
        
        List<Scheme__c> schlist = [SELECT Id, Name, Product__c,Promotion_Quantity__c, Minimum_Purchase_Quantity__c,Product__r.Name, Scheme_Start_Date__c, Scheme_End_Date__c, Is_Active__c, RecordTypeId, RecordType.Name, Scheme_Details__c 
                                   FROM Scheme__c 
                                   WHERE Scheme_Start_Date__c != null 
                                   AND Scheme_End_Date__c != null 
                                   AND Is_Active__c = true 
                                   AND RecordType.Name = 'Quantity scheme' AND Product__c!=null];
        
        return schlist;
    }
    //This method is to getAllActiveValueScheme
    @AuraEnabled
    public static List<Scheme__c> getAllActiveValueScheme() {
        
        
        List<Scheme__c> schlist = [
            SELECT Id, Name, Scheme_Start_Date__c, Scheme_End_Date__c,
            Cart_Amount__c, Discount_Amount__c, Discount_Percentage__c,
            Is_Active__c, RecordTypeId, RecordType.Name, Scheme_Details__c
            FROM Scheme__c
            WHERE Scheme_Start_Date__c != null
            AND Scheme_End_Date__c != null
            AND Is_Active__c = true
            AND RecordType.Name = 'Value scheme' 
        ];
        
        return schlist;
    }

    //This method is to getProductsWithSchemes
    
    @AuraEnabled(cacheable=true)
    public static Map<Id, List<Map<String, Object>>> getProductsWithSchemes() {
        
        
        // Query active schemes with necessary fields
        List<Scheme__c> schlist = [
            SELECT Id, Product__c, Scheme_Details__c, Minimum_Purchase_Quantity__c 
            FROM Scheme__c
            WHERE Scheme_Start_Date__c != null 
            AND Scheme_End_Date__c != null 
            AND Is_Active__c = true 
            AND RecordType.Name = 'Quantity scheme'
        ];
        
        // Map to hold product ID to a list of scheme details with Minimum_Purchase_Quantity__c
        Map<Id, List<Map<String, Object>>> productToSchemeMap = new Map<Id, List<Map<String, Object>>>();
        
        for (Scheme__c scheme : schlist) {
            if (scheme.Product__c != null) {
                if (!productToSchemeMap.containsKey(scheme.Product__c)) {
                    productToSchemeMap.put(scheme.Product__c, new List<Map<String, Object>>());
                }
                
                // Create a map for each scheme containing the Id, details, and minimum purchase quantity
                Map<String, Object> schemeMap = new Map<String, Object>();
                schemeMap.put('Id', scheme.Id); // Add the Scheme Id
                schemeMap.put('SchemeDetails', scheme.Scheme_Details__c);
                schemeMap.put('MinimumPurchaseQuantity', scheme.Minimum_Purchase_Quantity__c);
                
                // Add the scheme map to the product's scheme list
                productToSchemeMap.get(scheme.Product__c).add(schemeMap);
            }
        }
        
        // Log result
        if (productToSchemeMap.isEmpty()) {
            system.debug('No active schemes found.');
        } else {
            system.debug('Active schemes: ' + productToSchemeMap);
        }
        
        return productToSchemeMap;
    }
    //This method is to create order
    
    //Method for Generating the Proposals
    @AuraEnabled
    public static OrderResponse generateProposal(String productsFromCart, String visitIdSelected, String orderSummary,String orderComment){
        try {
            
            
            
            List<CartProductWrapper.ProductWrapper> mainData = new List<CartProductWrapper.ProductWrapper>();
            mainData = (List<CartProductWrapper.ProductWrapper>)JSON.deserialize(productsFromCart, List<CartProductWrapper.ProductWrapper>.class);
            System.debug('mainData-->'+mainData);
            
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
            Id userId = UserInfo.getUserId();
            Id accId;
            
            
            Order__c order = new Order__c();
            order.Ordered_By__c = UserInfo.getUserId();
            order.Description__c = orderComment;
            order.Total_order_value__c = orderSummaryData.totalPrice;
            order.EffectiveDate__c = System.Today();
            order.Status__c = 'Order Placed';  
            order.Total_Discount__c = orderSummaryData.totalDiscount;
            order.Total_Quantity__c = orderSummaryData.totalQuantity;
            order.Type__c='Field Order';
            order.RecordTypeId=rt.Id;
            if (String.isNotBlank(orderSummaryData.valuseSchemeIdOnOrder)) {
                order.Value_Scheme_Applied__c = Id.valueOf(orderSummaryData.valuseSchemeIdOnOrder);
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
            ///
            //
            if(orderSummaryData.totalSGST!=0){
                order.totalSGST__c=orderSummaryData.totalSGST;
            }
            if(orderSummaryData.totalCGST!=0){
                order.totalCGST__c=orderSummaryData.totalCGST;
            }
            if(orderSummaryData.totalIGST!=0){
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
                
                if (String.isNotBlank(proData.selectedSchemeId)) {
                    orderLineItem.Quantity_Scheme__c = Id.valueOf(proData.selectedSchemeId);
                }                
                orderLineItem.Is_Promotional__c = (proData.isPromotional== true);
                orderLineItem.Parent_Product__c = proData.parentProductId;
                orderLineItem.Discount_Percentage__c = proData.discountPercentage;
                
                orderLineItemList.add(orderLineItem);
                
            }
            insert orderLineItemList;
            
            // Retrieve the order based on criteria
            
            
            
            Visit_Task__c  visitTask= new Visit_Task__c ();
            visitTask.id=visitIdSelected;
            visitTask.Order_Placed__c=true;
            visitTask.OrderCustom__c =order.id;
            //visitTask.Status__c = 'Completed - Order';
            update visitTask;
            
            Visit_Task__c  vt=[select id,Retailer__c,Retailer__r.Primary_State__c, Distributor__c,Visit__c from Visit_Task__c where id=:visitIdSelected limit 1];
            
            Order__c orderVar = new Order__c();
            orderVar.id=order.id;
            orderVar.Account__c = vt.Retailer__c;
            orderVar.AccountId__c = vt.Distributor__c;
            orderVar.Visit_Task__c = vt.id;
            orderVar.Visit__c = vt.Visit__c;
            update orderVar;
            //Added by Supriya to include Order sharing via apex - where Order is shared with distributor matching with order distributor
            //shareOrderWithDistributor(orderVar);
            if(orderVar!=null){
                shareOrderWithDistributorContacts(orderVar);
            }
            
                    
            response.status ='Success';
            response.ordid =order.id;
            
            return response;
            
        } catch (Exception e) {
            
            
            throw new AuraHandledException(e.getMessage());
        }
    }
    public static void shareOrderWithDistributorContacts(Order__c order) {
        // Validate Order record
        if (order == null || order.AccountId__c == null) {
            System.debug('Invalid Order or Distributor Account is null.');
            return;
        }
        
        // Fetch all Contacts linked to the Distributor
        List<Contact> distributorContacts = [
            SELECT Id, AccountId, Email, (SELECT Id FROM Users) 
            FROM Contact 
            WHERE AccountId = :order.AccountId__c
        ];
        
        if (distributorContacts.isEmpty()) {
            System.debug('No Contacts found for Distributor: ' + order.AccountId__c);
            return;
        }
        
        // Collect all related Users (Contacts who have a Community/Portal User)
        List<Order__Share> shares = new List<Order__Share>();
        for (Contact contact : distributorContacts) {
            if (contact.Users.isEmpty()) {
                continue; // Skip contacts without an associated User
            }
            
            for (User user : contact.Users) {
                Order__Share share = new Order__Share();
                share.ParentId = order.Id;
                share.UserOrGroupId = user.Id; // Sharing with the User related to Contact
                share.AccessLevel = 'Edit'; // Change to 'Edit' if needed
                share.RowCause = Schema.Order__Share.RowCause.Manual;
                shares.add(share);
            }
        }
        
        // Insert sharing records
        if (!shares.isEmpty()) {
            try {
                insert shares;
                System.debug('Order shared successfully with Distributor Contacts.');
            } catch (DmlException e) {
                System.debug('Error while sharing Order: ' + e.getMessage());
            }
        } else {
            System.debug('No valid Users found for Distributor Contacts.');
        }
    }
        
    //Wrapper for the Product Data
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
        @AuraEnabled public Decimal productOfferPrice{get;set;}
        @AuraEnabled public Decimal productMRP{get;set;}   // ✅ NEW
        @AuraEnabled public Decimal percentageValue {get;set;}
        @AuraEnabled public Boolean offerIsThere {get;set;}
        @AuraEnabled public String state {get;set;}
        @AuraEnabled public String uom {get;set;}
        @AuraEnabled public Boolean focusProduct {get;set;}
        @AuraEnabled public String productCode {get;set;}
        @AuraEnabled public Integer availableQuantity { get; set; }
        @AuraEnabled public Boolean availableQuantitySent { get; set; }
    
        public ProductDataWrapper(){
            productImages = new List<String>();
            productQuantity = 0;
        }
    }
    public class OrderResponse {
        @AuraEnabled public String status;  // To return 'success' or other status
        @AuraEnabled public String ordid;  // To return the orderId
    }
    
    //
    //Generated by AdminBooster
    //
    
    public class OrderSummaryWrapper{
        public Integer totalItems;  //0
        public decimal totalPrice;  //0
        public decimal totalDiscount;   //0
        public decimal totalOrderValue; //0
        public Integer totalQuantity;   //0
        public String valuseSchemeIdOnOrder;   //0
        public decimal totalDiscountRupees;   //0
        public decimal subTotal;   //0
        public decimal totalSGST;
        public decimal totalCGST;
        public decimal totalIGST;
        public decimal valueSchemeDiscount;
        
        public OrderSummaryWrapper parse(String json){
            return (OrderSummaryWrapper) System.JSON.deserialize(json, OrderSummaryWrapper.class);
        }
    }
}