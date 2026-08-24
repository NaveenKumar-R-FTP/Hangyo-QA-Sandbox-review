/*
Purpose: Controller for product listing and order generation in a customer portal
Features:
- Product search with pricebook integration
- Order proposal generation with async processing
- Tax-aware order calculations
- SAP integration
*/
public without sharing class ProductListingComponentControllerPortal {
    //region Constants and Configuration
    // Custom exception for order processing errors
    public class OrderException extends Exception {}
    
    // Record type identifiers
    private static final String PRIMARY_ORDER_RT = 'Primary_Order';
    private static final String PRIMARY_OLI_RT = 'Primary_Order_Line_Item';
    private static final String UNDERSS_ORDER_RT = 'Under_SS_Order';
    private static final String UNDERSS_OLT_RT = 'UnderSS_Order_Line_Item';
    
    private static final String UNDERSS_SECONDARY_ORDER_RT = 'Under_SS_Secondary_Order';
    private static final String UNDERSS_SECONDARY_OLT_RT = 'Under_SS_Secondary_Order_Line_Item';
    // Mapping of account types to price book entry types
    private static final Map<String, String> ACCOUNT_TO_PBE_TYPE = new Map<String, String>{
        'Distributor' => 'Direct Distributor',
            'SuperStockist' => 'Super Stockist'
            };
                //endregion
                
                //region Main Public Methods
                
                /**
* @description Fetches active products with pricing for the current user's context
* @param searchValue Search term for product name filtering
* @param brandFilter Filter for product brand
* @return JSON string of ProductDataWrapper list
* @note Cacheable for performance optimization in LWC
*/
                // added by Fuzail - extended fetchProducts with searchBy
                // searchBy: 'Name' = default (Name/Brand search), 'Code' = Product_Code__c starts with typed value
                @AuraEnabled(cacheable=true)
                public static String fetchProducts(String searchValue, String brandFilter, String searchBy) {
                    try {
                        // Get user context with account and location details
                        UserContext ctx = getUserContext();
                        if (!isValidContext(ctx)) return JSON.serialize(new List<ProductDataWrapper>());
                        
                        // added by Fuzail - Under SS detection for product visibility logic
                        // When logged-in Experience user is Under Super Stockist (Distributor_Type__c = 'Under Super Stockist'),
                        // show products where Product__c.Under_SS__c = TRUE (instead of Primary_Product__c).
                        SchemeContext schemeCtx = getSchemeContext();
                        Boolean isUnderSS = schemeCtx != null && schemeCtx.isUnderSSDistributor == true;

                        // Resolve appropriate pricebook based on account type and region
                        PriceBookContext pbCtx = getPriceBookContext(ctx);
                        if (pbCtx == null) return JSON.serialize(new List<ProductDataWrapper>());
                        
                        // Retrieve active product prices from pricebook
                        Map<Id, Decimal> productPrices = getActivePrices(pbCtx);
                        if (productPrices.isEmpty()) return JSON.serialize(new List<ProductDataWrapper>());
                        
                        // Build and return formatted product data
                        return JSON.serialize(buildProductWrapper(
                            queryProducts(productPrices.keySet(), searchValue, brandFilter, searchBy, isUnderSS, ctx.accountId),
                            productPrices,
                            ctx.userState,
                            ctx.accountId
                        ));
                    } catch (Exception e) {
                        handleException('fetchProducts', e);
                        return JSON.serialize(new List<ProductDataWrapper>());
                    }
                }
    
    /**
* @description Initiates order generation process with async processing
* @param productsFromCart JSON string of CartProductWrapper list
* @param orderSummary JSON string of OrderSummaryWrapper
* @param orderComment User comments for the order
* @return OrderResponse with process status
* @note Uses Queueable for async processing to handle governor limits
*/
    @AuraEnabled
    public static OrderResponse generateProposal(String productsFromCart, String orderSummary, String orderComment) {
        try {
            OrderSummaryWrapper summaryData = parseOrderSummary(orderSummary);
            List<CartProductWrapper.ProductWrapper> products = 
                (List<CartProductWrapper.ProductWrapper>)JSON.deserialize(
                    productsFromCart, 
                    List<CartProductWrapper.ProductWrapper>.class
                );
            
            
            Order__c order = createBaseOrder(summaryData, orderComment);
            insert order; // Ensure primary order is inserted first
            
            // ✅ Immediately queue async processing for the primary order
            System.enqueueJob(new OrderProcessingQueueable(
                productsFromCart,
                orderSummary,
                orderComment,
                order.Id,
                UserInfo.getUserId()
            ));
            // ✅ Check for Under Super Stockist condition
            UnderSSOrderResult underSSResult = getUnderSSOrderRecordTypeValue();
            // ✅ Create base order record and insert it first

            
            
            // ✅ If UnderSSOrder is applicable, create & insert Secondary Order
            if (underSSResult.isUnderSSOrder) { 
                //   shareOrderWithDistributorUsers(order);
                
                Order__c orderUnderSSSecOrd = createBaseOrderUnderSSSecOrd(summaryData, orderComment, order.Id);
                insert orderUnderSSSecOrd;
                
                // ✅ Queue async processing for the secondary order
                System.enqueueJob(new OrderProcessingQueueable(
                    productsFromCart,
                    orderSummary,
                    orderComment,
                    orderUnderSSSecOrd.Id,
                    UserInfo.getUserId()
                ));
            }
            return new OrderResponse(true, 'Order processing started', order.Id);
        } catch (Exception e) {
            handleException('generateProposal', e);
            throw new AuraHandledException('Order failed: ' + e.getMessage());
        }
    }
    //endregion
    
    
    //region Helper Classes
    
    /**
* @description Contains user context information for pricing and regional logic
*/
    private class UserContext {
        public Id accountId;         // Related Account ID
        public String userState;     // Account's primary state
        public String accountType;   // Account record type (Distributor/Super_Stockist)
    }
    
    /**
* @description Contains pricebook configuration details
*/
    private class PriceBookContext {
        public Id pricebookId;       // Active pricebook ID
        public String entryType;     // Pricebook entry type from ACCOUNT_TO_PBE_TYPE mapping
    }
    //endregion
    
    //region Context Methods
    
    /**
* @description Retrieves user context with account details
* @return UserContext populated with account information
* @note Uses single query with null safety checks
*/
    private static UserContext getUserContext() {
        UserContext ctx = new UserContext();
        User u = [SELECT Contact.AccountId, Contact.Account.Primary_State__c, 
                  Contact.Account.RecordType.DeveloperName 
                  FROM User 
                  WHERE Id = :UserInfo.getUserId() 
                  LIMIT 1];
        
        if (u.Contact?.Account != null) {
            ctx.accountId = u.Contact.Account.Id;
            ctx.userState = u.Contact.Account.Primary_State__c;
            ctx.accountType = u.Contact.Account.RecordType.DeveloperName;
        }
        return ctx;
    }
    
    /**
* @description Determines appropriate pricebook based on account type and region
* @param ctx User context containing account details
* @return PriceBookContext with resolved pricebook ID and entry type
* @note Prioritizes regional pricebooks, falls back to 'Pan India'
*/
    private static PriceBookContext getPriceBookContext(UserContext ctx) {
        PriceBookContext pbCtx = new PriceBookContext();
        pbCtx.entryType = ACCOUNT_TO_PBE_TYPE.get(ctx.accountType);
        if (pbCtx.entryType == null) return null;
        
        List<Price_Book__c> pricebooks = [
            SELECT Id FROM Price_Book__c 
            WHERE isActive__c = TRUE 
            AND (Region__r.Name = :ctx.userState OR Name LIKE 'Pan India%')
            ORDER BY Region__r.Name NULLS LAST  // Prioritize regional over pan-India
            LIMIT 1];
        
        pbCtx.pricebookId = !pricebooks.isEmpty() ? pricebooks[0].Id : null;
        return pbCtx;
    }
    //endregion
    
    //region Price Management
    
    /**
* @description Retrieves active product prices from pricebook
* @param pbCtx Pricebook context information
* @return Map<Id, Decimal> of Product__c IDs to prices
* @note Uses WITH SECURITY_ENFORCED for FLS/CRUD checks
*/
    private static Map<Id, Decimal> getActivePrices(PriceBookContext pbCtx) {
        Map<Id, Decimal> prices = new Map<Id, Decimal>();
        
        for (Price_Book_Entry__c pbe : [
            SELECT Product__c, PTD__c, PTSS__c 
            FROM Price_Book_Entry__c 
            WHERE Price_Book__c = :pbCtx.pricebookId 
            AND Type__c = :pbCtx.entryType 
            AND isActive__c = true
            WITH SECURITY_ENFORCED
        ]) {
            if (pbCtx.entryType == 'Super Stockist') {
                if(pbe.PTSS__c != null){
                prices.put(pbe.Product__c, pbe.PTSS__c);
                }
            } 
            else if (pbCtx.entryType == 'Direct Distributor') {
                if(pbe.PTD__c != null){
                prices.put(pbe.Product__c, pbe.PTD__c);
                }
            }
            // Add additional account types here if needed
        }
        
        return prices;
    }
    //endregion
    
    //region Product Query
    
    /**
* @description Dynamic product query with search filters
* @param productIds Set of valid product IDs from pricebook
* @param search Search term for product name
* @param brand Brand filter value
* @return List<Product__c> matching criteria
* @note Uses String.escapeSingleQuotes for basic injection protection
*/
    // added by Fuzail - added searchBy to support Name / Code filter
    private static List<Product__c> queryProducts(Set<Id> productIds, String search, String brand, String searchBy, Boolean isUnderSS, Id distributorAccId) {
        String query = 'SELECT Id, Name, Image_Long__c, Product_Brand__c, Unit_of_Measure__c,MRP__c, IsActive__c,Crate_Conversion__c , Minimum_Order_Quantity__c, Product_Code__c , Category_Code__c ' +
            'FROM Product__c WHERE Id IN :productIds AND IsActive__c = TRUE' + 
            ' AND RecordType.DeveloperName = \'Product\'';

        // OLD visibility logic (kept for reference)
        // query += ' AND Primary_Product__c = TRUE';

        // added by Fuzail - Under SS product visibility logic
        // If the logged-in Experience user is Under Super Stockist, show ONLY products where Under_SS__c is checked.
        // Otherwise, keep the old behavior (show ONLY products where Primary_Product__c is checked).
        if (isUnderSS == true) {
            query += ' AND Under_SS__c = TRUE';
        } else {
            query += ' AND Primary_Product__c = TRUE';
        }
        
        // added by Fuzail - Search By Name or Code
        // OLD LOGIC (kept for reference):
        // if (String.isNotBlank(search)) {
        //     String searchPattern = '%' + search + '%';
        //     query += ' AND (Name LIKE :searchPattern OR Product_Brand__c LIKE :searchPattern)';
        // }
        String codeSearchPattern = null;
        if (String.isBlank(searchBy)) {
            searchBy = 'Name';
        }
        if (String.isNotBlank(search)) {
            if (searchBy == 'Code') {
                // When user chooses Search By → Code, match product codes starting with typed digits
                codeSearchPattern = search.trim() + '%';
                query += ' AND Category_Code__c LIKE :codeSearchPattern';
            } else {
                String searchPattern = '%' + search + '%';
                query += ' AND (Name LIKE :searchPattern OR Product_Brand__c LIKE :searchPattern)';
            }
        }
        if (String.isNotBlank(brand)) {
            query += ' AND Product_Brand__c LIKE \'%' + String.escapeSingleQuotes(brand) + '%\'';
        }

        // Per-distributor product restriction (deny list).
        Set<Id> deniedProductIds = ProductRestrictionService.getDeniedProductIds(distributorAccId);
        if (!deniedProductIds.isEmpty()) {
            query += ' AND Id NOT IN :deniedProductIds';
        }

        query += ' ORDER BY Name ASC';

        return Database.query(query);
    }
    //endregion
    
    //region Data Transformation
    
    /**
* @description Creates UI-ready product data wrappers
* @param products List of Product__c records
* @param prices Map of product prices
* @param state User's state for tax/display purposes
* @return List<ProductDataWrapper> formatted for LWC
*/
    private static List<ProductDataWrapper> buildProductWrapper(List<Product__c> products, 
                                                                Map<Id, Decimal> prices, 
                                                                String state , String distributorAccId) {
                                                                    Set<Id> productIds = new Set<Id>();
                                                                    for (Product__c p : products) {
                                                                        productIds.add(p.Id);
                                                                    }
                                                                    
                                                                    Account acc = [SELECT Id , Name , Record_type_Name__c , Distributor_Type__c
                                                                                           FROM Account WHERE Id =: distributorAccId
                                                                                           LIMIT 1];
                                                                    
                                                                    Boolean showMOQ = (acc.Record_type_Name__c == 'Distributor' && acc.Distributor_Type__c == 'Under Super Stockist'
                                                                                       ? False : True);
                                                                
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
                                                                    
                                                                    List<ProductDataWrapper> wrappers = new List<ProductDataWrapper>();
                                                                    for (Product__c p : products) {
                                                                        if (String.isBlank(p.Image_Long__c)) continue;
                                                                        
                                                                        Decimal minOrderQuantity = p.Minimum_Order_Quantity__c != null ? p.Minimum_Order_Quantity__c : 0;
                                                                        Decimal inventoryQty = productIdToQtyMap.containsKey(p.Id) ? productIdToQtyMap.get(p.Id) : 0;
                                                                        wrappers.add(new ProductDataWrapper(
                                                                            p.Id,
                                                                            p.Name,
                                                                            p.Product_Brand__c,
                                                                            prices.get(p.Id),
                                                                            p.Unit_of_Measure__c,
                                                                            p.Image_Long__c.split(','),
                                                                            state,
                                                                            p.MRP__c,
                                                                            minOrderQuantity,
                                                                            p.Crate_Conversion__c,
                                                                            inventoryQty,
                                                                            showMOQ
                                                                        ));
                                                                    }
                                                                    return wrappers;
                                                                }
    //endregion
    
    //region Order Processing Queueable
    
    /**
* @description Handles async order processing for governor limit management
* @note Implements Database.AllowsCallouts for SAP integration
*/
    public class OrderProcessingQueueable implements Queueable, Database.AllowsCallouts {
        private final String productsFromCart;
        private final String orderSummaryJSON;
        private final String orderComment;
        private final Id orderId;
        private final Id userId;
        
        public OrderProcessingQueueable(String products, String summary, String comment, Id ordId, Id uId) {
            this.productsFromCart = products;
            this.orderSummaryJSON = summary;
            this.orderComment = comment;
            this.orderId = ordId;
            this.userId = uId;
        }
        
        public void execute(QueueableContext context) {
            try {
                List<CartProductWrapper.ProductWrapper> products = 
                    (List<CartProductWrapper.ProductWrapper>)JSON.deserialize(
                        this.productsFromCart, 
                        List<CartProductWrapper.ProductWrapper>.class
                    );
                System.debug('Products--->'+ products);
                UnderSSOrderResult underSSResult = getUnderSSOrderRecordTypeValue(); // Get the result object
                Id underSSRecordTypeId = getUnderSSOrderRecordTypeId(); 
                // Fetch the record type of the order
                Order__c orderRecord = [SELECT Id, RecordTypeId FROM Order__c WHERE Id = :this.orderId LIMIT 1];
                
                // Determine record type ID for "Secondary"
                Id secondaryRecordTypeId = getUnderssSecondaryOrderRecordTypeId(); 
                if (orderRecord.RecordTypeId != secondaryRecordTypeId) {
                    List<Order_Line_Item__c> items = createOrderItems(
                        products, 
                        this.orderId, 
                        underSSResult.isUnderSSOrder ? getUnderSSOLIRecordTypeId() : getOLIRecordTypeId() // Use the Boolean value
                        
                    );
                    insert items;
                }
                
                
                // Insert secondary order items only if the order has a "Secondary" record type
                if (orderRecord.RecordTypeId == secondaryRecordTypeId) {
                    List<Order_Line_Item__c> itemsSec = createOrderItems(
                        products, 
                        this.orderId, 
                        getUnderssSecondaryOLIRecordTypeId()
                    );
                    insert itemsSec;
                }               
                // Skip SAP integration in test context
                if (!Test.isRunningTest() && 
                    orderRecord.RecordTypeId != secondaryRecordTypeId && 
                    orderRecord.RecordTypeId != underSSRecordTypeId) {
                        SalesOrderAPI.pushPrimaryOrderstoSAP(this.orderId);
                    }
            } catch (Exception e) {
                System.debug('Order processing failed: ' + e.getMessage());
                // TODO: Add error notification system
            }
        }
    }
    //endregion
    
    //region Order Creation Helpers
    
    /**
* @description Creates base order record with summary data
* @param summary Parsed order summary data
* @param comment User-provided order comments
* @return Order__c ready for insertion
*/
    private static Order__c createBaseOrder(OrderSummaryWrapper summary, String comment) {
        UnderSSOrderResult underSSResult = getUnderSSOrderRecordTypeValue();
         Boolean isSameState = false;
         // Fetch user's account and Super Stockist's account states
        if(underSSResult.isUnderSSOrder){
        User currentUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId()];
        Account userAccount = [SELECT Primary_State__c FROM Account WHERE Id = :currentUser.AccountId LIMIT 1];
        Account superStockistAccount = [SELECT Primary_State__c FROM Account WHERE Id = :underSSResult.superStockistAccountId LIMIT 1];
        
       // Boolean isSameState = userAccount.Primary_State__c == superStockistAccount.Primary_State__c;
       
if(userAccount.Primary_State__c != null && superStockistAccount.Primary_State__c != null) {
    isSameState = userAccount.Primary_State__c.equalsIgnoreCase(superStockistAccount.Primary_State__c);
}
        }
Order_tax_value__c taxSetting;
            try {
                taxSetting = [SELECT CGST__c, SGST__c , IGST__c FROM Order_tax_value__c WHERE Name = 'General GST Settings' LIMIT 1];
            } catch (QueryException e) {
                taxSetting = new Order_tax_value__c(CGST__c=0, SGST__c=0,IGST__c =0);
            }
        
        
        Decimal totalCGST = 0;
        Decimal totalSGST = 0;
        Decimal totalIGST = 0;
        Decimal subTotal = summary.totalOrderValue;
        Decimal totalOrderValue = subTotal;
        
        if (isSameState) {
            
            
            
            totalCGST = (subTotal * taxSetting.CGST__c) / 100;
            totalSGST = (subTotal * taxSetting.SGST__c) / 100;
            totalOrderValue += totalCGST + totalSGST;
        } else {
           
            totalIGST = (subTotal * taxSetting.IGST__c) / 100;
            totalOrderValue += totalIGST;
        }
        
        return new Order__c(
            Ordered_By__c = UserInfo.getUserId(),
            Description__c = comment,
            Total_order_value__c = summary.totalPrice,
            Sub_Total__c = summary.totalOrderValue,
            EffectiveDate__c = System.today(),
            Status__c = 'Order Placed',
            Total_Discount__c = summary.totalDiscount,
            Total_Quantity__c = summary.totalQuantity,
            Total_Crate__c = summary.totalCrates,
            AccountId__c = getAccountId(),
            RecordTypeId = underSSResult.isUnderSSOrder ? getUnderssOrderRecordTypeId() : getOrderRecordTypeId(),
            Super_Stockist_Name__c=underSSResult.isUnderSSOrder ? underSSResult.superStockistAccountId : null,
            totalSGST__c = underSSResult.isUnderSSOrder ? totalSGST : summary.totalSGST,
            totalCGST__c = underSSResult.isUnderSSOrder ? totalCGST : summary.totalCGST,
            totalIGST__c = underSSResult.isUnderSSOrder ? totalIGST : summary.totalIGST,
            Type__c=underSSResult.isUnderSSOrder ? 'Under Super Stockist' : null,
          	Value_Scheme_Applied__c = summary.valuseSchemeIdOnOrder,
            Value_Scheme_Discount__c = summary.valueSchemeDiscount
           
            
        );
         
    }
        //This method is for underss secondary order creation

    private static Order__c createBaseOrderUnderSSSecOrd(OrderSummaryWrapper summary, String comment,String ordId) {
        UnderSSOrderResult underSSResult = getUnderSSOrderRecordTypeValue();
        system.debug('underSSResult.primaryDistributorUserId&&&'+underSSResult.primaryDistributorUserId);
        //Added by Ajay to fix tax w.r.t ss and under ss priamry states
        // Fetch user's account and Super Stockist's account states
         Boolean isSameState = false;
          if(underSSResult.isUnderSSOrder){
        User currentUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId()];
        Account userAccount = [SELECT Primary_State__c FROM Account WHERE Id = :currentUser.AccountId LIMIT 1];
        Account superStockistAccount = [SELECT Primary_State__c FROM Account WHERE Id = :underSSResult.superStockistAccountId LIMIT 1];
        
       // Boolean isSameState = userAccount.Primary_State__c == superStockistAccount.Primary_State__c;
       
if(userAccount.Primary_State__c != null && superStockistAccount.Primary_State__c != null) {
    isSameState = userAccount.Primary_State__c.equalsIgnoreCase(superStockistAccount.Primary_State__c);
}
          }
Order_tax_value__c taxSetting;
            try {
                taxSetting = [SELECT CGST__c, SGST__c , IGST__c FROM Order_tax_value__c WHERE Name = 'General GST Settings' LIMIT 1];
            } catch (QueryException e) {
                taxSetting = new Order_tax_value__c(CGST__c=0, SGST__c=0,IGST__c =0);
            }
        
        
        Decimal totalCGST = 0;
        Decimal totalSGST = 0;
        Decimal totalIGST = 0;
        Decimal subTotal = summary.totalOrderValue;
        Decimal totalOrderValue = subTotal;
        
        if (isSameState) {
            
            
            
            totalCGST = (subTotal * taxSetting.CGST__c) / 100;
            totalSGST = (subTotal * taxSetting.SGST__c) / 100;
            totalOrderValue += totalCGST + totalSGST;
        } else {
           
            totalIGST = (subTotal * taxSetting.IGST__c) / 100;
            totalOrderValue += totalIGST;
        }
        
        return new Order__c(
            Ordered_By__c = UserInfo.getUserId(),
            Description__c = comment,
            Total_order_value__c = summary.totalPrice,
            Sub_Total__c = summary.totalOrderValue,
            EffectiveDate__c = System.today(),
            Status__c = 'Order Placed',
            Total_Discount__c = summary.totalDiscount,
            Total_Quantity__c = summary.totalQuantity,
            Total_Crate__c = summary.totalCrates,
            AccountId__c = underSSResult.superStockistAccountId,  // Use Super_Stockist_Name__c instead of getAccountId()
            RecordTypeId = getUnderssSecondaryOrderRecordTypeId(),
            totalSGST__c = totalSGST,
            totalCGST__c = totalCGST,
            totalIGST__c = totalIGST,
            Under_SS_Order__c=ordId,
            Placed_via_Under_SS__c=true,
            OwnerId= underSSResult.primaryDistributorUserId,
            Type__c='DMS',
            Value_Scheme_Applied__c = summary.valuseSchemeIdOnOrder,
            Value_Scheme_Discount__c = summary.valueSchemeDiscount
            
            
        );
    }
   
    /**
* @description Creates order line items from cart products
* @param products List of cart product wrappers
* @param orderId Parent order ID
* @param rtId Record type ID for line items
* @return List<Order_Line_Item__c> ready for insertion
*/
    private static List<Order_Line_Item__c> createOrderItems(List<CartProductWrapper.ProductWrapper> products, 
                                                             Id orderId, Id rtId) {
                                                     System.debug('createOrderItems CartProductWrapper.ProductWrapper --'+products);
                                                                 List<Order_Line_Item__c> items = new List<Order_Line_Item__c>();
                                                                 for (CartProductWrapper.ProductWrapper p : products) {
                                                                      Decimal price;
                                                                     if (p.isPromotional == true) {
                                                                         price = p.productListPrice != null ? p.productListPrice : p.productOfferPrice;
                                                                     } else {
                                                                         price = p.productOfferPrice;
                                                                     }
                                                                     items.add(new Order_Line_Item__c(
                                                                         Order__c = orderId,
                                                                         RecordTypeId = rtId,
                                                                         Products__c = p.productId,
                                                                         Ordered_Quantity__c = p.quantity,
                                                                         //Product_Price__c = p.productOfferPrice,
                                                                         //Product_Price__c = p.isPromotional ? p.productListPrice : p.productOfferPrice,

                                                                         Product_Price__c = price,
                                                                         Quantity_Scheme__c  = p.selectedSchemeId,
                                                                         Is_Promotional__c   =  (p.isPromotional == true),
                                                                         Parent_Product__c   = p.parentProductId,
                                                                         Discount_Percentage__c = p.discountPercentage
                                                                     ));
                                                                 }
                                                                 return items;
                                                             }
    
 
    //endregion
    
    //region Utility Methods
    
    private static Id getOLIRecordTypeId() {
        return [SELECT Id FROM RecordType WHERE DeveloperName = :PRIMARY_OLI_RT LIMIT 1].Id;
    }
    
    private static Id getOrderRecordTypeId() {
        return [SELECT Id FROM RecordType WHERE DeveloperName = :PRIMARY_ORDER_RT LIMIT 1].Id;
    }
    private static Id getAccountId() {
        return [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId()].AccountId;
    }
    private static Id getUnderssOrderRecordTypeId() {
        return [SELECT Id FROM RecordType WHERE DeveloperName = :UNDERSS_ORDER_RT LIMIT 1].Id;
    }
    private static Id getUnderSSOLIRecordTypeId() {
        return [SELECT Id FROM RecordType WHERE DeveloperName = :UNDERSS_OLT_RT LIMIT 1].Id;
    }
        //This method is for underss in order to understand whether the record is of type underss
    private static UnderSSOrderResult getUnderSSOrderRecordTypeValue() {
        try {
            system.debug(UserInfo.getName());
            User ut = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            
            if (ut.AccountId == null) {
                return new UnderSSOrderResult(false, null,null);
            }
            
            Account acc = [SELECT Id,Name, Super_Stockist_Name__c,Super_Stockist_Name__r.Primary_State__c,Primary_State__c, Distributor_Type__c FROM Account WHERE Id = :ut.AccountId LIMIT 1];
            // Fetch users for Super Stockist account
            List<User> users = [
                SELECT Id, Name, Primary_Distributor__c 
                FROM User 
                WHERE AccountId = :acc.Super_Stockist_Name__c
            ];

            // Find the user with Primary_Distributor__c = true
            User primaryDistributorUser;
            for (User u : users) {
                if (u.Primary_Distributor__c) {
                    primaryDistributorUser = u;
                    break;
                }
            }

            Boolean isUnderSSOrder = (acc.Super_Stockist_Name__c != null && acc.Distributor_Type__c == 'Under Super Stockist');
         /*   if(acc.Super_Stockist_Name__r.Primary_State__c != acc.Primary_State__c ){
                 Order_tax_value__c taxSetting = [SELECT Name , SGST__c, IGST__c, CGST__c FROM Order_tax_value__c WHERE Name = 'General GST Settings' LIMIT 1];
                
            }*/
            
            System.debug('UnderSSOrderResult => isUnderSSOrder: ' + isUnderSSOrder + 
                         ', superStockistAccountId: ' + acc.Super_Stockist_Name__c + 
                         ', secOrdOwner (Primary Distributor User Id): ' + 
                         (primaryDistributorUser != null ? primaryDistributorUser.Id : 'null'));
            return new UnderSSOrderResult(isUnderSSOrder, acc.Super_Stockist_Name__c, primaryDistributorUser != null ? primaryDistributorUser.Id : null);
            
        } catch (Exception e) {
            System.debug('Error in getUnderSSOrderRecordTypeValue: ' + e.getMessage());
            System.debug('Error in getUnderSSOrderRecordTypeValue: ' + e.getlinenumber());
            return new UnderSSOrderResult(false, null,null);
        }
    }
    
    private static Id getUnderssSecondaryOrderRecordTypeId() {
        return [SELECT Id FROM RecordType WHERE DeveloperName = :UNDERSS_SECONDARY_ORDER_RT LIMIT 1].Id;
    }
    private static Id getUnderssSecondaryOLIRecordTypeId() {
        return [SELECT Id FROM RecordType WHERE DeveloperName = :UNDERSS_SECONDARY_OLT_RT  LIMIT 1].Id;
    }
    //endregion
    
    //region Wrapper Classes
    
    /**
* @description UI product data wrapper with display formatting
*/
    public class ProductDataWrapper {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productShortDescription;
        @AuraEnabled public String productBrand;
        @AuraEnabled public Decimal productListPrice;
        @AuraEnabled public Decimal productOfferPrice;
        @AuraEnabled public String[] productImages;
        @AuraEnabled public Decimal productMrp;
        @AuraEnabled public String productDisplayImage;
        @AuraEnabled public String state;
        @AuraEnabled public String uom;
        @AuraEnabled public Decimal crateconversion;
        @AuraEnabled public Decimal inventoryQty;
        @AuraEnabled public Decimal minOrderQuantity;
        @AuraEnabled public Boolean showMOQ;
        
        public ProductDataWrapper(Id pId, String name, String brand, Decimal price, 
                                  String unit, String[] images, String state , Decimal MrpValue,Decimal minOrderQuantity ,
                                  Decimal ConversionValue, Decimal inventoryQty , Boolean showMOQ) {
                                      this.productId = pId;
                                      this.productShortDescription = name;
                                      this.productBrand = brand;
                                      this.productListPrice = price;
                                      this.productOfferPrice = price.setScale(2);
                                      this.productImages = images;
                                      this.productDisplayImage = !images.isEmpty() ? images[0] : null;
                                      this.uom = unit;
                                      this.state = state;
                                      this.productMrp = MrpValue;
                                      this.crateconversion=ConversionValue;
                                      this.inventoryQty = inventoryQty;
                                      this.minOrderQuantity = minOrderQuantity;
                                      this.showMOQ = showMOQ;
                                  }
    }
    
    /**
* @description Order processing response structure
*/
    public class OrderResponse {
        @AuraEnabled public Boolean isSuccess;
        @AuraEnabled public String message;
        @AuraEnabled public Id ordid;
        
        public OrderResponse(Boolean success, String msg, Id orderId) {
            this.isSuccess = success;
            this.message = msg;
            this.ordid = orderId;
        }
    }
    //This wrapper is for underss in order to understand whether the record is of type underss
    public class UnderSSOrderResult {
        public Boolean isUnderSSOrder;
        public Id superStockistAccountId;
        public Id primaryDistributorUserId ;
        
        public UnderSSOrderResult(Boolean isUnderSSOrder, Id superStockistAccountId,Id primaryDistributorUserId) {
            this.isUnderSSOrder = isUnderSSOrder;
            this.superStockistAccountId = superStockistAccountId;
            this.primaryDistributorUserId = primaryDistributorUserId;
            
        }
    }
    /**
* @description Contains order summary calculations
*/
    public class OrderSummaryWrapper {
        @AuraEnabled public Integer totalItems;
        @AuraEnabled public Decimal totalPrice;
        @AuraEnabled public Decimal totalDiscount;
        @AuraEnabled public Decimal totalOrderValue;
        @AuraEnabled public Integer totalQuantity;
        @AuraEnabled public Decimal totalSGST;
        @AuraEnabled public Decimal totalCGST;
        @AuraEnabled public Decimal totalIGST;
        @AuraEnabled public String totalCrates;
        @AuraEnabled public String valuseSchemeIdOnOrder;   //0
        @AuraEnabled public decimal totalDiscountRupees; 
        @AuraEnabled public decimal valueSchemeDiscount;
    }
    //endregion
    
    //region Support Methods
    
    private static OrderSummaryWrapper parseOrderSummary(String jsonData) {
        return (OrderSummaryWrapper) JSON.deserialize(jsonData, OrderSummaryWrapper.class);
    }
    
    private static Boolean isValidContext(UserContext ctx) {
        return ctx.accountId != null && ctx.userState != null && ctx.accountType != null;
    }
    
    private static void handleException(String methodName, Exception e) {
        System.debug('Error in ' + methodName + ': ' + e.getMessage() + ' Line: ' + e.getLineNumber());
    }
    //endregion

    @AuraEnabled(cacheable=true)
    public static Map<String, Decimal> getTaxRates(String state) {
        //added to resolve Null pointer exception
        if (String.isBlank(state)) {
            state = 'Others';
        }
        // Retrieve tax rates from the custom setting based on the state
        UnderSSOrderResult underSSResult = getUnderSSOrderRecordTypeValue();
         Boolean isSameState = false;
         if(underSSResult.isUnderSSOrder){
         User currentUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId()];
        Account userAccount = [SELECT Primary_State__c FROM Account WHERE Id = :currentUser.AccountId LIMIT 1];
        Account superStockistAccount = [SELECT Primary_State__c FROM Account WHERE Id = :underSSResult.superStockistAccountId LIMIT 1];
        
       // Boolean isSameState = userAccount.Primary_State__c == superStockistAccount.Primary_State__c;
       
if(userAccount.Primary_State__c != null && superStockistAccount.Primary_State__c != null) {
    isSameState = userAccount.Primary_State__c.equalsIgnoreCase(superStockistAccount.Primary_State__c);
}
         }
Order_tax_value__c taxSettingSS;
            try {
                taxSettingSS = [SELECT CGST__c, SGST__c , IGST__c FROM Order_tax_value__c WHERE Name = 'General GST Settings' LIMIT 1];
            } catch (QueryException e) {
                taxSettingSS = new Order_tax_value__c(CGST__c=0, SGST__c=0,IGST__c =0);
            }
        
        String stateName='';
        system.debug(state);
        /*if(state == 'Karnataka' ||state == 'KA'){
            stateName = 'Karnataka';
        }else{
            stateName = 'Others';
        }*/
        if(String.isNotBlank(state) &&(state.equalsIgnoreCase('Karnataka') ||state.equalsIgnoreCase('KA'))){
            stateName = 'Karnataka';
        }else{
            stateName = 'Others';
        }
        Map<String, Decimal> taxRates = new Map<String, Decimal>();
        Order_tax_value__c taxSetting = [SELECT Name , SGST__c, IGST__c, CGST__c FROM Order_tax_value__c WHERE Name =: stateName LIMIT 1];
        system.debug(taxSetting);
        if(isSameState && underSSResult.isUnderSSOrder){
            taxRates.put('CGST', taxSettingSS.CGST__c);
            taxRates.put('SGST', taxSettingSS.SGST__c);
            taxRates.put('SS',1);
        }
        else if(underSSResult.isUnderSSOrder && !isSameState ){
             taxRates.put('IGST', taxSettingSS.IGST__c); // Default value, change as needed
             taxRates.put('SS',0);
        }
        else if (taxSetting.Name == 'Karnataka' && !underSSResult.isUnderSSOrder) {
            taxRates.put('CGST', taxSetting.CGST__c);
            taxRates.put('SGST', taxSetting.SGST__c);
            taxRates.put('DD',1);
        } else {
            taxRates.put('IGST', taxSetting.IGST__c); // Default value, change as needed
            taxRates.put('DD',0);
        }
        return taxRates;
    }
    
    private class SchemeContext {
        Id accountId;
        String region;
        Boolean isUnderSSDistributor;
    }

    private static SchemeContext getSchemeContext() {

        SchemeContext ctx = new SchemeContext();
    
        User u = [
            SELECT AccountId,
                   ContactId,
                   Contact.AccountId,
                   Contact.Account.Primary_State__c,
                   Contact.Account.RecordType.DeveloperName,
                   Contact.Account.Distributor_Type__c,
                   Contact.Account.Super_Stockist_Name__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
    
        Account acc;
    
        // Community-safe resolution
        if (u.ContactId != null && u.Contact.AccountId != null) {
            acc = u.Contact.Account;
        } else if (u.AccountId != null) {
            acc = [
                SELECT Id,
                       Primary_State__c,
                       RecordType.DeveloperName,
                       Distributor_Type__c,
                       Super_Stockist_Name__c
                FROM Account
                WHERE Id = :u.AccountId
                LIMIT 1
            ];
        } else {
            return ctx; // No account → no schemes
        }
    
        ctx.accountId = acc.Id;
        ctx.region = acc.Primary_State__c;
    
        ctx.isUnderSSDistributor =
            acc.RecordType.DeveloperName == 'Distributor'
            && acc.Distributor_Type__c == 'Under Super Stockist'
            && acc.Super_Stockist_Name__c != null;
    
        return ctx;
    }
    
    @AuraEnabled(cacheable=true)
    public static Boolean isUnderSSUser() {
        SchemeContext ctx = getSchemeContext();
        return ctx != null && ctx.isUnderSSDistributor == true;
    }

    @AuraEnabled
    public static List<QuantitySchemeModalWrapper> getqualityScheme(Id productId) {
        try {
            System.debug(' productId=' + productId);
    
             if (productId == null) {
                throw new AuraHandledException('Product Id is required');
            }

    		SchemeContext ctx = getSchemeContext();
            System.debug(' SchemeContext.accountId=' + ctx.accountId);
            System.debug(' SchemeContext.region=' + ctx.region);
            System.debug(' SchemeContext.isUnderSSDistributor=' + ctx.isUnderSSDistributor);

            // Only Primary Distributor under SS can see schemes
            if (!ctx.isUnderSSDistributor || ctx.accountId == null || ctx.region == null) {
                return new List<QuantitySchemeModalWrapper>();
            }
        Date today = System.today();
        Boolean isUnderSS = ctx.isUnderSSDistributor;
    
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
              AND Under_SS_Scheme__c = true
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
            
            if (isUnderSS) {
                // Primary Distributor under SS
                if (!scheme.Under_SS_Scheme__c) {
                    continue;
                }
            } else {
                // Normal Distributor / Retailer
                if (!scheme.Retailer_Scheme__c) {
                    continue;
                }
            }
    
            List<Scheme_Hierarchy__c> hierarchy = hierarchyByScheme.get(scheme.Id);
    
            // Global scheme (no hierarchy records)
            if (hierarchy == null || hierarchy.isEmpty()) {
                response.add(buildWrapper(scheme));
                continue;
            }
    
            // Apply hierarchy resolution
            if (isSchemeApplicable(hierarchy, ctx.accountId, ctx.region)) {
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
    
    private static Boolean isSchemeApplicable(
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
    
    public class QuantitySchemeModalWrapper {

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
    
        /* ------------------------------------------------------------
           Helper to compute UX messaging based on cart quantity
           (call this from JS OR future Apex enhancement)
           ------------------------------------------------------------ */
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
    }

   	@AuraEnabled
    public static List<CartProductWrapper.ProductWrapper> applyQuantityScheme(
        List<CartProductWrapper.ProductWrapper> cartItems,
        Id selectedSchemeId
    ) {
        List<CartProductWrapper.ProductWrapper> promos =
            new List<CartProductWrapper.ProductWrapper>();
    
        // -------------------------------------------------
        // Resolve Scheme Context (Under SS only)
        // -------------------------------------------------
        SchemeContext ctx = getSchemeContext();
        if (!ctx.isUnderSSDistributor) {
            return promos;
        }
    
        if (cartItems == null || cartItems.isEmpty() || selectedSchemeId == null) {
            return promos;
        }
    
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
    
        Boolean isOtherProductScheme =
            scheme.Type__c != null &&
            scheme.Type__c.startsWith('Other Product');
    
        // -------------------------------------------------
        // Resolve PriceBook Context
        // -------------------------------------------------
        UserContext userCtx = getUserContext();
        PriceBookContext pbCtx = getPriceBookContext(userCtx);
        if (pbCtx == null) {
            return promos;
        }
    
        Map<Id, Decimal> priceMap = getActivePrices(pbCtx);
    
        // -------------------------------------------------
        // Resolve Promo Product + Base Price
        // -------------------------------------------------
        Decimal promoBasePrice;
        Id promoProductId = scheme.Product__c;
        Product__c otherProduct;
    
        if (isOtherProductScheme) {
            otherProduct = [
                SELECT Id, Name, Product_Brand__c, Unit_of_Measure__c
                FROM Product__c
                WHERE Id = :scheme.Other_Product__c
                LIMIT 1
            ];
    
            promoProductId = otherProduct.Id;
            promoBasePrice = priceMap.containsKey(promoProductId)
                ? priceMap.get(promoProductId)
                : 0;
        } else {
            promoProductId = base.productId;
            promoBasePrice = base.productOfferPrice;
        }
    
         Set<Id> stockProductIds = new Set<Id>{promoProductId};

		Map<Id, Decimal> stockMap = SchemeEvaluationService.getDistributorStockForProducts(stockProductIds);
        // -------------------------------------------------
        // Create Promo Line
        // -------------------------------------------------
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
        promo.availableStockQuantity = stockMap.containsKey(promoProductId)? Integer.valueOf(stockMap.get(promoProductId)) : 0;
        Integer baseQty = base.quantity;
        Integer minQty  = Integer.valueOf(scheme.Minimum_Purchase_Quantity__c);
        Integer promoPerSlab = Integer.valueOf(scheme.Promotion_Quantity__c);
        
        // How many times scheme applies
        Integer slabCount = (minQty > 0) ? (baseQty / minQty) : 0;
        
        // Total promo quantity
        Integer totalPromoQty = slabCount * promoPerSlab;
        
        promo.quantity = totalPromoQty;
        promo.promoMinQty = scheme.Minimum_Purchase_Quantity__c;
    
        // -------------------------------------------------
        // Populate UI Fields
        // -------------------------------------------------
        if (isOtherProductScheme && otherProduct != null) {
            promo.productName = otherProduct.Name;
            promo.productBrand = otherProduct.Product_Brand__c;
            promo.prodmeasure = otherProduct.Unit_of_Measure__c;
           // promo.availableStockQuantity = stockMap.containsKey(promoProductId)? Integer.valueOf(stockMap.get(promoProductId)) : 0;
        } else {
            promo.productName = safeStr(base.productName, base.productFullName);
            promo.productBrand = base.productBrand;
            promo.prodmeasure = base.prodmeasure;
            //promo.availableStockQuantity = base.availableStockQuantity;
        }
    
        // -------------------------------------------------
        // Pricing Logic (FREE vs DISCOUNTED)
        // -------------------------------------------------
        promo.productListPrice = promoBasePrice;
    
        if (scheme.Discount_Percentage__c == null ||
            scheme.Discount_Percentage__c == 100) {
    
            // FREE PRODUCT
            promo.productOfferPrice = 0;
            promo.unittotalPrice = 0;
    
        } else {
    
            // DISCOUNTED PRODUCT (SAME + OTHER)
            promo.productOfferPrice =
                promoBasePrice * (1 - (scheme.Discount_Percentage__c / 100));
    
            promo.unittotalPrice =
                promo.productOfferPrice * promo.quantity;
        }
    
        promos.add(promo);
        return promos;
    }



    private static String safeStr(String value, String fallback) {
        return String.isNotBlank(value) ? value : fallback;
    }
    
    private static Integer safeInt(Integer value, Integer fallback) {
        return value != null ? value : fallback;
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


    public class AppliedValueSchemeWrapper {
        @AuraEnabled
        public Decimal discountAmount { get; set; }
        @AuraEnabled
        public Decimal discountPercentage { get; set; }
        @AuraEnabled
        public String freeProductId { get; set; }
        @AuraEnabled
        public String schemeType { get; set; }
        @AuraEnabled public Decimal promoQty;
        
    }
    
    @AuraEnabled
    public static AppliedValueSchemeWrapper getAppliedValueScheme(String valueSchemId) {
    
        Scheme__c s = [
            SELECT Discount_Amount__c,
                   Discount_Percentage__c,
                   Other_Product__c,
            	   Other_Product_Quantity__c,
                   Type__c
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
    
        return w;
    }
    
    @AuraEnabled(cacheable=true)
    public static CartProductWrapper.ProductWrapper getProductForValueScheme(Id productId) {
    
        Product__c p = [
            SELECT Id,
                   Name,
                   Product_Brand__c,
                   Unit_of_Measure__c,
                   Rate_Value__c
            FROM Product__c
            WHERE Id = :productId
            LIMIT 1
        ];
    
         Set<Id> stockProductIds = new Set<Id>{productId};

		Map<Id, Decimal> stockMap = SchemeEvaluationService.getDistributorStockForProducts(stockProductIds);
        CartProductWrapper.ProductWrapper w =
            new CartProductWrapper.ProductWrapper();
    
        w.productId = p.Id;
        w.productName = p.Name;
        w.productBrand = p.Product_Brand__c;
        w.prodmeasure = p.Unit_of_Measure__c;
        w.availableStockQuantity = stockMap.containsKey(productId)? Integer.valueOf(stockMap.get(productId)): 0;
        w.productListPrice = p.Rate_Value__c;
        w.productOfferPrice = 0;
        w.unittotalPrice = 0;
    
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
    
       public class SchemeDetailsWrapper {
        @AuraEnabled
        public String id { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public Boolean isMatchExist { get; set; }
        @AuraEnabled
        public Boolean isApplied { get; set; }
        @AuraEnabled public Decimal promoQty;

        
        public SchemeDetailsWrapper(String id, String name, Boolean isMatchExist, Boolean isApplied, Decimal promoQty) {
            this.id = id;
            this.name = name;
            this.isMatchExist = isMatchExist;
            this.isApplied = isApplied;
            this.promoQty = promoQty;
        }
    }
    
    @AuraEnabled
    public static List<SchemeDetailsWrapper> getvalueScheme(Decimal totalCartPrice) {
         try {
        List<SchemeDetailsWrapper> response = new List<SchemeDetailsWrapper>();
    
         if (totalCartPrice == null) {
                throw new AuraHandledException('totalCartPrice is required');
            }

    		SchemeContext ctx = getSchemeContext();
             System.debug('ValueScheme ctx => ' +
                    'accountId=' + ctx.accountId +
                    ', region=' + ctx.region +
                    ', isUnderSS=' + ctx.isUnderSSDistributor
                );

            //  Only Primary Distributor under SS can see schemes
            if (!ctx.isUnderSSDistributor || ctx.accountId == null || ctx.region == null) {
                return new List<SchemeDetailsWrapper>();
            }
    
        Date today = System.today();
    
       	Boolean isUnderSS = ctx.isUnderSSDistributor;	
    
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
              AND Under_SS_Scheme__c = true
              AND Scheme_Start_Date__c <= :today
              AND Scheme_End_Date__c >= :today
              AND Cart_Amount__c != null
        ];
    
        if (schemes.isEmpty()) return response;
    
        //  Fetch hierarchy
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
    
        //  Build response
        for (Scheme__c s : schemes) {
    
            //  Retailer / SS applicability
            if (isUnderSS) {
                // Primary Distributor under SS
                if (!s.Under_SS_Scheme__c) {
                    continue;
                }
            } else {
                // Normal Distributor / Retailer
                if (!s.Retailer_Scheme__c) {
                    continue;
                }
            }
    
            //  Hierarchy check
            List<Scheme_Hierarchy__c> hierarchy = hierarchyMap.get(s.Id);
            if (hierarchy != null && !hierarchy.isEmpty()) {
                if (!isSchemeApplicable(hierarchy, ctx.accountId, ctx.region)) {
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
      	}catch (Exception e) {
         	System.debug('❌ getvalueScheme ERROR: ' + e.getMessage());
            throw new AuraHandledException('Value Scheme Error: ' + e.getMessage());
    	}
    }

}