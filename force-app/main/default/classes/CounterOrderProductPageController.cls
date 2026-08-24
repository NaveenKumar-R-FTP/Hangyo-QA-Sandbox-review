public without sharing class CounterOrderProductPageController {
    
    @AuraEnabled(cacheable= true)
    public static String fetchDistributorData(){
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
        
        List<ContactDataWrapper> ContactWrapper = new List<ContactDataWrapper>();
        if(distributorAccId != NULL){
            Account acc = [SELECT Id , Name , BillingState , BillingCity , BillingPostalCode , BillingCountry FROM Account WHERE Id =: distributorAccId];
            ContactDataWrapper pw = new ContactDataWrapper();
            //pw.ConName = acc.Name;
            pw.ConBillingState = acc.BillingState;
            pw.ConBillingCity = acc.BillingCity;
            pw.ConBillingPostalCode = acc.BillingPostalCode;
            pw.ConBillingCountry = acc.BillingCountry;
            ContactWrapper.add(pw);
        }
        return JSON.serialize(ContactWrapper);
    }
    
    // added by Fuzail - extended fetchProducts with stockFilter + searchBy
    // searchBy: 'Name' = normal search (old behaviour: Name / Product_Brand__c),
    //           'Code' = search by Product_Code__c (starts with, e.g. 5300105)
    @AuraEnabled
    public static String fetchProducts(String searchValue, String brandFilter, String stockFilter, String searchBy) {
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
        
        List<Product__c> productList = new List<Product__c>();
        List<ProductDataWrapper> productWrapper = new List<ProductDataWrapper>();
        Id productRecordTypeId = [
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Product' AND SObjectType = 'Product__c' 
            LIMIT 1
        ].Id;
        
        String query = 'SELECT Id, Name, CreatedDate, IsActive__c, DisplayURL__c, Focus_Product__c, Image_Long__c, Validity_Start_Date__c, Validity_End_Date__c, MRP__c, Quantity__c, Unit_of_Measure__c, Category_Code__c, Category_Name__c, Product_Code__c, Product_Brand__c FROM Product__c WHERE IsActive__c = True AND Secondary_Product__c = TRUE AND RecordTypeId = :productRecordTypeId';
        
        // added by Fuzail - Search By (Name / Code) for counter order search
        // OLD LOGIC (commented, preserved for reference):
        // if (searchValue != null && searchValue != '') {
        //     searchValue = '%' + searchValue + '%';  
        //     query += ' AND (Name LIKE :searchValue OR Product_Brand__c LIKE :searchValue)'; 
        // }
        String codeSearchPattern = null;
        if (String.isBlank(searchBy)) {
            searchBy = 'Name';
        }
        if (String.isNotBlank(searchValue)) {
            if (searchBy == 'Code') {
                // When user chooses Search By -> Code:
                // match Category_Code__c that starts with typed value (e.g. 53, 5300105)
                codeSearchPattern = searchValue.trim() + '%';
                query += ' AND Category_Code__c LIKE :codeSearchPattern';
            } else {
                // Default Name search: same as old behaviour (Name / Product_Brand__c contains term)
                searchValue = '%' + searchValue + '%';  
                query += ' AND (Name LIKE :searchValue OR Product_Brand__c LIKE :searchValue)'; 
            }
        }
        if (brandFilter != null && brandFilter != '') {
            query += ' AND Product_Brand__c LIKE :brandFilter';
        }

        // Per-distributor product restriction (deny list).
        Set<Id> deniedProductIds = ProductRestrictionService.getDeniedProductIds(distributorAccId);
        if (!deniedProductIds.isEmpty()) {
            query += ' AND Id NOT IN :deniedProductIds';
        }

        query += ' ORDER BY Name ASC';

        productList = Database.query(query);
        System.debug('productList:- '+productList);
        
        // Step 2: Build product ID set for inventory query
        Set<Id> productIds = new Set<Id>();
        for (Product__c p : productList) {
            productIds.add(p.Id);
        }
    
        // Step 3: Query inventory by distributor and product
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
        
        // Step 4: Wrap product data
        for (Product__c master : productList) {
            if (master.IsActive__c == true && master.Image_Long__c != null && master.Image_Long__c != '') {
                ProductDataWrapper pw = new ProductDataWrapper();
                pw.productId = master.Id;
                pw.productShortDescription = master.Name;
                pw.productBrand = master.Product_Brand__c;
                pw.sellebleSKU = '';
                pw.productListPrice = master.MRP__c;
                pw.productOfferPrice = master.MRP__c;
                pw.productImages = master.Image_Long__c.split(',');
                pw.productDisplayImage = pw.productImages[0];
                pw.uom = master.Unit_of_Measure__c;
    
                // Step 5: Set quantity in hand if available
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
    public static OrderResponse generateProposal(String productsFromCart, String visitIdSelected, String orderSummary,String orderComment){
        System.debug('orderSummary:- '+ orderSummary);
        try {
            List<CartProductWrapper.ProductWrapper> mainData = new List<CartProductWrapper.ProductWrapper>();
            mainData = (List<CartProductWrapper.ProductWrapper>)JSON.deserialize(productsFromCart, List<CartProductWrapper.ProductWrapper>.class);
            OrderSummaryWrapper orderSummaryData = new OrderSummaryWrapper();
            OrderResponse response = new OrderResponse();
            orderSummaryData = (OrderSummaryWrapper)JSON.deserialize(orderSummary, OrderSummaryWrapper.class);
            System.debug('orderSummaryData:- '+ orderSummaryData);
            RecordType rt = [
                SELECT Id 
                FROM RecordType 
                WHERE SObjectType = 'Order__c' 
                AND Name = 'Counter Order' 
                LIMIT 1
            ];
            System.debug('RecordType Id==>'+rt.Id);
            // Get the current user's ID
            Id userId = UserInfo.getUserId();
            System.debug('userId Id==>'+UserInfo.getUserId());
            Id retailerAccId = [SELECT Id, Name, RecordType.Name FROM Account WHERE Name = 'Counter Sales Customer' AND RecordType.Name = 'Retailer' LIMIT 1].Id;
            System.debug('Account Id==>'+retailerAccId);
            
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
            if(retailerAccId != NULL){
                System.debug('Retailer Account Id==>'+retailerAccId);
                order.Account__c = retailerAccId;
            }
            if(distributorAccId != NULL){
                System.debug('Distributor Account Id==>'+distributorAccId);
                order.AccountId__c = distributorAccId;
            }
            order.Ordered_By__c = UserInfo.getUserId();
            order.Description__c = orderComment;
            System.debug('Comment'+order.Description__c );
            order.Total_order_value__c = orderSummaryData.totalPrice;
            order.Price_Excluding_Tax__c = orderSummaryData.totalPriceExcludingTax;
            order.EffectiveDate__c = System.Today();
            order.Status__c = 'Order Placed';   
            order.Discount_Amount_Order__c = orderSummaryData.totalDiscount;
            order.Total_Quantity__c = orderSummaryData.totalQuantity;
            order.Price__c=orderSummaryData.totalPrceBeforeDiscount;
            order.Type__c = 'Counter Order'; 
            order.totalSGST__c = orderSummaryData.totalSGST;
            order.totalCGST__c = orderSummaryData.totalCGST;
            order.totalIGST__c = orderSummaryData.totalIGST;
            order.Sub_Total__c = orderSummaryData.totalOrderValue;
            order.RecordTypeId=rt.Id;
            order.Customer_Name__c = orderSummaryData.firstName + ' ' + orderSummaryData.lastName;
            order.Customer_Phone__c = orderSummaryData.phone;
            order.Customer_Email__c = orderSummaryData.email;
            order.Customer_Address__c = (orderSummaryData.addressLine != '' ? orderSummaryData.addressLine + ' , ' : '') + orderSummaryData.city + ' - ' + orderSummaryData.postalcode;
            order.State__c = orderSummaryData.state;
            order.Country__c = orderSummaryData.country;
            order.Company__c = orderSummaryData.company;
            order.GSTIN__c = orderSummaryData.gstin;
            insert order;
            
            Set<Id> productIds = new Set<Id>();
            for (CartProductWrapper.ProductWrapper proData : mainData) {
                productIds.add(proData.productId);
            }
            
            Map<Id, Product__c> productMap = new Map<Id, Product__c>(
                [SELECT Id, Rate_Value__c,Unit_of_Measure__c FROM Product__c WHERE Id IN :productIds]);
            
            
            RecordType rt1 = [
                SELECT Id 
                FROM RecordType 
                WHERE SObjectType = 'Order_Line_Item__c' 
                AND Name = 'Counter Order Line Item' 
                LIMIT 1
            ];
            Order_Line_Item__c orderLineItem;
            List<Order_Line_Item__c> orderLineItemList = new List<Order_Line_Item__c>();
            for(CartProductWrapper.ProductWrapper proData : mainData){
                orderLineItem = new Order_Line_Item__c ();
                orderLineItem.Order__c  = order.Id;
                orderLineItem.RecordTypeId=rt1.Id;
                orderLineItem.Products__c = proData.productId;   
                orderLineItem.Ordered_Quantity__c   = proData.quantity;
                 orderLineItem.Product_Price__c = proData.productOfferPrice;
                orderLineItemList.add(orderLineItem);
            }
            insert orderLineItemList;
            response.status ='Success';
            response.ordid =order.id;
            return response;
            
        } catch (Exception e) {
            System.debug(e.getMessage());
            System.debug(e.getLineNumber());
            
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Decimal> getTaxRates() {
        Map<String, Decimal> taxRates = new Map<String, Decimal>();
        Order_tax_value__c taxSetting = [SELECT Name , SGST__c, IGST__c, CGST__c FROM Order_tax_value__c WHERE Name = 'General GST Settings' LIMIT 1];
        if(taxSetting != null){
            taxRates.put('CGST', taxSetting.CGST__c);
            taxRates.put('SGST', taxSetting.SGST__c);
        }
        return taxRates;
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
        @AuraEnabled public Integer availableQuantity { get; set; }         //Holds available stock from Inventory__c
        @AuraEnabled public Decimal productOfferPrice{get;set;}
        @AuraEnabled public Decimal percentageValue {get;set;}
        @AuraEnabled public Boolean offerIsThere {get;set;}
        @AuraEnabled public String uom {get;set;}
        public ProductDataWrapper(){
            productImages = new List<String>();
            productQuantity = 0;
            availableQuantity = 0;
        }
    }
    
    public class ContactDataWrapper{
        //@AuraEnabled public String ConName{get;set;}
        @AuraEnabled public String ConBillingState{get;set;}
        @AuraEnabled public String ConBillingCity{get;set;}
        @AuraEnabled public String ConBillingPostalCode{get;set;}
        @AuraEnabled public String ConBillingCountry{get;set;}
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
        public decimal totalPrceBeforeDiscount; //0
        public decimal totalPriceExcludingTax; //0
        public Integer totalQuantity;   //0
        public Decimal totalSGST;
        public Decimal totalCGST;
        public Decimal totalIGST;
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
        public OrderSummaryWrapper parse(String json){
            return (OrderSummaryWrapper) System.JSON.deserialize(json, OrderSummaryWrapper.class);
        }
    }
}