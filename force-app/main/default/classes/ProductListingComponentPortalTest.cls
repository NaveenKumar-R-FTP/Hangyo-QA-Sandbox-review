@isTest
public class ProductListingComponentPortalTest {
    // Helper method to create test data
    private static void createTestData() {
        // Create RecordTypes
        
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        RecordType primaryOrderRt = [SELECT Id FROM RecordType WHERE DeveloperName = 'Primary_Order' LIMIT 1];
        RecordType primaryOliRt = [SELECT Id FROM RecordType WHERE DeveloperName = 'Primary_Order_Line_Item' LIMIT 1];
                RecordType underssOrderRt = [SELECT Id FROM RecordType WHERE DeveloperName = 'Under_SS_Order' LIMIT 1];
        RecordType underssOliRt = [SELECT Id FROM RecordType WHERE DeveloperName = 'UnderSS_Order_Line_Item' LIMIT 1];
         RecordType ssrec = [SELECT Id FROM RecordType WHERE DeveloperName = 'SuperStockist' LIMIT 1];

        // Create test Account
        Account testAccount = new Account(
            Name = 'Test Account', 
            Primary_State__c = 'Andhra Pradesh',
            PAN_Number__c = '123TEST',
            RecordTypeId = [SELECT Id FROM RecordType WHERE DeveloperName = 'SuperStockist' LIMIT 1].Id
            
        );
        insert testAccount;
         Account testAccount2 = new Account(
            Name = 'Test Account', 
            Primary_State__c = 'Andhra Pradesh',
            PAN_Number__c = '123TEST',
            RecordTypeId = [SELECT Id FROM RecordType WHERE DeveloperName = 'Distributor' LIMIT 1].Id,
            Super_Stockist_Name__c = testAccount.id,
             Distributor_Type__c = 'Under Super Stockist'
        );
        insert testAccount2;
        
        

        // Create test Contact
        Contact testContact = new Contact(
            LastName = 'Test Contact', 
            AccountId = testAccount.Id
        );
        insert testContact;
        
        
        // Create test Contact
        Contact testContact2 = new Contact(
            LastName = 'Test Contact2', 
            AccountId = testAccount2.Id
        );
        insert testContact2;

        // Create test User
        Profile p = [SELECT Id FROM Profile WHERE Name = 'DMS Partner Community Custom'];
        User testUser = new User(
            Alias = 'testUser',
            Email = 'testuser@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'Hangyotestuser@testhorg2.com',
            ContactId = testContact.Id,
            Primary_Distributor__c = true
        );
        insert testUser;
        
        User testUser1 = new User(
            Alias = 'testUser',
            Email = 'testuser@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'Hangyotestuser@testhorg.com',
            ContactId = testContact2.Id
        );
        insert testUser1;

        // Create test Product
        Id productRecordType = [SELECT Id FROM RecordType 
                              WHERE DeveloperName = 'Product' 
                              AND SObjectType = 'Product__c' LIMIT 1].Id;
        Product__c testProduct = new Product__c(
            Name = 'Test Product',
            IsActive__c = true,
            Image_Long__c = 'http://example.com/image1.jpg,http://example.com/image2.jpg',
            Unit_of_Measure__c = 'kg',
            Product_Brand__c = 'Test Brand',
            RecordTypeId = productRecordType,
            Primary_Product__c = true,
            Under_SS__c = true
        );
        insert testProduct;
Region__c region = new Region__c(
            Name = 'Andhra Pradesh'
        );
        insert region;
        // Create test Price Book (link to region for getPriceBookContext query)
        Price_Book__c testPriceBook = new Price_Book__c(
            Name = 'Pan India',
            isActive__c = true,
            Region__c = region.Id
        );
        insert testPriceBook;

        // Order_tax_value__c required by createBaseOrder / createBaseOrderUnderSSSecOrd
        Order_tax_value__c generalGst = new Order_tax_value__c(
            Name = 'General GST Settings',
            CGST__c = 9.0,
            SGST__c = 9.0,
            IGST__c = 18.0
        );
        insert generalGst;

        // Create Price Book Entry (PTD for Direct Distributor; PTSS for Super Stockist)
        Price_Book_Entry__c testPriceBookEntry = new Price_Book_Entry__c(
            Product__c = testProduct.Id,
            Price_Book__c = testPriceBook.Id,
            PTD__c = 100.00,
            PTSS__c = 95.00,
            Type__c = 'Direct Distributor',
            isActive__c = true
        );
        insert testPriceBookEntry;
    }

    // Test method for fetchProducts
    @isTest
    static void testFetchProducts() {
        createTestData();
        User testUser = [SELECT Id FROM User WHERE UserName = 'Hangyotestuser@testhorg.com'];

        System.runAs(testUser) {
            Test.startTest();
            String result = ProductListingComponentControllerPortal.fetchProducts('Test', 'Test Brand', 'Name');
            Test.stopTest();

            List<ProductListingComponentControllerPortal.ProductDataWrapper> wrappers = 
                (List<ProductListingComponentControllerPortal.ProductDataWrapper>)JSON.deserialize(
                    result, 
                    List<ProductListingComponentControllerPortal.ProductDataWrapper>.class
                );
            
            System.assertEquals(1, wrappers.size(), 'Should return 1 product');
            System.assertEquals('Test Product', wrappers[0].productShortDescription);
        }
    }

    @isTest
    static void testGenerateProposal() {
        createTestData();
        User testUser = [SELECT Id,Name FROM User WHERE UserName = 'Hangyotestuser@testhorg.com'];
        system.debug(testUser.name);
        Product__c testProduct = [SELECT Id FROM Product__c LIMIT 1];

        System.runAs(testUser) {
            // Build productsFromCart JSON (CartProductWrapper.ProductWrapper structure)
            String productsFromCart = JSON.serialize(new List<Map<String, Object>>{
                new Map<String, Object>{
                    'productId' => testProduct.Id,
                    'quantity' => 1,
                    'productOfferPrice' => 100,
                    'productListPrice' => 100,
                    'productName' => 'Test Product',
                    'productBrand' => 'Test Brand',
                    'isPromotional' => false,
                    'selectedSchemeId' => null,
                    'parentProductId' => null,
                    'discountPercentage' => null
                },
                new Map<String, Object>{
                    'productId' => testProduct.Id,
                    'quantity' => 2,
                    'productOfferPrice' => 100,
                    'productListPrice' => 100,
                    'productName' => 'Test Product',
                    'productBrand' => 'Test Brand',
                    'isPromotional' => false,
                    'selectedSchemeId' => null,
                    'parentProductId' => null,
                    'discountPercentage' => null
                }
            });

            // Build order summary (include all fields used by createBaseOrder)
            ProductListingComponentControllerPortal.OrderSummaryWrapper summary = 
                new ProductListingComponentControllerPortal.OrderSummaryWrapper();
            summary.totalItems = 2;
            summary.totalPrice = 300;
            summary.totalDiscount = 0;
            summary.totalOrderValue = 300;
            summary.totalQuantity = 3;
            summary.totalSGST = 25.20;
            summary.totalCGST = 25.20;
            summary.totalIGST = 0.00;
            summary.totalCrates = '0';
            summary.valuseSchemeIdOnOrder = null;
            summary.valueSchemeDiscount = 0;

            Test.startTest();
            ProductListingComponentControllerPortal.OrderResponse response = 
                ProductListingComponentControllerPortal.generateProposal(
                    productsFromCart,
                    JSON.serialize(summary),
                    'Test Comment'
                );
            
    
            Test.stopTest(); // Queueable will execute here

            // Verify order creation
            Order__c order = [SELECT Id, Total_order_value__c, Description__c 
                             FROM Order__c 
                             WHERE Id = :response.ordid];
            System.assertEquals(300, order.Total_order_value__c, 'Total value mismatch');
            
            // Verify line items through queueable execution
            List<Order_Line_Item__c> items = [SELECT Id, Ordered_Quantity__c 
                                            FROM Order_Line_Item__c 
                                            WHERE Order__c = :response.ordid];
            System.assertEquals(2, items.size(), 'Should create 2 line items');
        }
    }

    @isTest
    static void testOrderProcessingQueueable() {
        createTestData();
        User testUser = [SELECT Id, AccountId FROM User WHERE UserName = 'Hangyotestuser@testhorg.com'];
        Product__c testProduct = [SELECT Id FROM Product__c LIMIT 1];
        Id primaryOrderRtId = [SELECT Id FROM RecordType WHERE DeveloperName = 'Primary_Order' LIMIT 1].Id;
        System.runAs(testUser) {
            Order__c testOrder = new Order__c(
                AccountId__c = testUser.AccountId,
                RecordTypeId = primaryOrderRtId
            );
            insert testOrder;

            String productsFromCart = JSON.serialize(new List<Map<String, Object>>{
                new Map<String, Object>{
                    'productId' => testProduct.Id,
                    'quantity' => 3,
                    'productOfferPrice' => 100,
                    'productListPrice' => 100,
                    'isPromotional' => false,
                    'selectedSchemeId' => null,
                    'parentProductId' => null,
                    'discountPercentage' => null
                }
            });

        Test.startTest();
        ProductListingComponentControllerPortal.OrderProcessingQueueable queueable = 
            new ProductListingComponentControllerPortal.OrderProcessingQueueable(
                productsFromCart,
                '{}',
                'Test Comment',
                testOrder.Id,
                testUser.Id
            );
        queueable.execute(null);
        Test.stopTest();

        List<Order_Line_Item__c> items = [SELECT Id FROM Order_Line_Item__c WHERE Order__c = :testOrder.Id];
            System.assertEquals(1, items.size(), 'Queueable should create 1 line item');
        }
    }
    
      @isTest
    static void testGetTaxRates_Karnataka() {
        // Insert a test record for Karnataka
        Order_tax_value__c karnatakaTax = new Order_tax_value__c(
            Name = 'Karnataka',
            CGST__c = 9.0,
            SGST__c = 9.0,
            IGST__c = 18.0
        );
        insert karnatakaTax;

        // Call the method
        Test.startTest();
        Map<String, Decimal> taxRates = ProductListingComponentControllerPortal.getTaxRates('Karnataka');
        Test.stopTest();

        // Assert Karnataka tax values
        System.assertEquals(9.0, taxRates.get('CGST'), 'CGST should be 9.0 for Karnataka');
        System.assertEquals(9.0, taxRates.get('SGST'), 'SGST should be 9.0 for Karnataka');
        System.assert(!taxRates.containsKey('IGST'), 'IGST should not be returned for Karnataka');
    }

    @isTest
    static void testGetTaxRates_Others() {
        // Insert a test record for Others
        Order_tax_value__c otherTax = new Order_tax_value__c(
            Name = 'Others',
            CGST__c = 0.0,
            SGST__c = 0.0,
            IGST__c = 18.0
        );
        insert otherTax;

        // Call the method
        Test.startTest();
        Map<String, Decimal> taxRates = ProductListingComponentControllerPortal.getTaxRates('Delhi');
    
        
    
        Test.stopTest();

        // Assert Others tax value
        System.assertEquals(18.0, taxRates.get('IGST'), 'IGST should be 18.0 for Others');
        System.assert(!taxRates.containsKey('CGST'), 'CGST should not be returned for Others');
        System.assert(!taxRates.containsKey('SGST'), 'SGST should not be returned for Others');
    }

    @isTest
    static void testFetchProducts_SearchByCode() {
        createTestData();
        User testUser = [SELECT Id FROM User WHERE UserName = 'Hangyotestuser@testhorg.com'];
        Product__c testProduct = [SELECT Id, Product_Code__c FROM Product__c LIMIT 1];
        if (testProduct.Product_Code__c == null) {
            testProduct.Product_Code__c = 'TEST001';
            update testProduct;
        }
        System.runAs(testUser) {
            Test.startTest();
            String result = ProductListingComponentControllerPortal.fetchProducts('TEST', null, 'Code');
            Test.stopTest();
            List<ProductListingComponentControllerPortal.ProductDataWrapper> wrappers =
                (List<ProductListingComponentControllerPortal.ProductDataWrapper>)JSON.deserialize(
                    result, List<ProductListingComponentControllerPortal.ProductDataWrapper>.class);
            System.assert(wrappers != null, 'Should return list');
        }
    }

    @isTest
    static void testIsUnderSSUser() {
        createTestData();
        User underSSUser = [SELECT Id FROM User WHERE UserName = 'Hangyotestuser@testhorg.com'];
        System.runAs(underSSUser) {
            Test.startTest();
            Boolean isUnderSS = ProductListingComponentControllerPortal.isUnderSSUser();
            Test.stopTest();
            System.assert(isUnderSS != null, 'isUnderSSUser should return a value');
        }
    }

    @isTest
    static void testGetqualityScheme_NullProductId() {
        Boolean threwExpectedException = false;
        try {
            ProductListingComponentControllerPortal.getqualityScheme(null);
        } catch (AuraHandledException e) {
            threwExpectedException = true;
        }
        System.assert(threwExpectedException, 'Expected AuraHandledException when productId is null');
    }

    @isTest
    static void testGetqualityScheme_ValidProductId() {
        createTestData();
        User testUser = [SELECT Id FROM User WHERE UserName = 'Hangyotestuser@testhorg.com'];
        Product__c testProduct = [SELECT Id FROM Product__c LIMIT 1];
        System.runAs(testUser) {
            Test.startTest();
            List<ProductListingComponentControllerPortal.QuantitySchemeModalWrapper> result =
                ProductListingComponentControllerPortal.getqualityScheme(testProduct.Id);
            Test.stopTest();
            System.assert(result != null, 'Should return list');
        }
    }

    // Covers buildWrapper(Scheme__c s) and QuantitySchemeModalWrapper population (lines 1043-1055)
    @isTest
    static void testGetqualityScheme_ReturnsSchemeBuildWrapper() {
        createTestData();
        User underSSUser = [SELECT Id FROM User WHERE UserName = 'Hangyotestuser@testhorg.com'];
        Product__c testProduct = [SELECT Id FROM Product__c LIMIT 1];
        Id qtySchemeRtId = [SELECT Id FROM RecordType WHERE DeveloperName = 'Quantity_scheme' AND SObjectType = 'Scheme__c' LIMIT 1].Id;
        Scheme__c qtyScheme = new Scheme__c(
            Name = 'Buy 5 Get 1',
            RecordTypeId = qtySchemeRtId,
            Product__c = testProduct.Id,
            Minimum_Purchase_Quantity__c = 5,
            Promotion_Quantity__c = 1,
            Discount_Percentage__c = 20,
            Under_SS_Scheme__c = true,
            Scheme_Start_Date__c = Date.today().addDays(-1),
            Scheme_End_Date__c = Date.today().addMonths(1)
        );
        insert qtyScheme;
        System.runAs(underSSUser) {
            Test.startTest();
            List<ProductListingComponentControllerPortal.QuantitySchemeModalWrapper> result =
                ProductListingComponentControllerPortal.getqualityScheme(testProduct.Id);
            Test.stopTest();
            System.assert(result != null, 'Should return list');
            if (result.size() > 0) {
                ProductListingComponentControllerPortal.QuantitySchemeModalWrapper w = result[0];
                System.assertEquals(qtyScheme.Id, w.schemeId, 'buildWrapper: schemeId');
                System.assertEquals(qtyScheme.Name, w.schemeName, 'buildWrapper: schemeName');
                System.assertEquals(5, w.minQty, 'buildWrapper: minQty');
                System.assertEquals(1, w.promoQty, 'buildWrapper: promoQty');
                System.assertEquals(20, w.discountPercentage, 'buildWrapper: discountPercentage');
            }
        }
    }

    @isTest
    static void testGetProductsWithSchemes() {
        createTestData();
        Test.startTest();
        Map<Id, List<Map<String, Object>>> result =
            ProductListingComponentControllerPortal.getProductsWithSchemes();
        Test.stopTest();
        System.assert(result != null, 'Should return map');
    }

    @isTest
    static void testGetAppliedValueScheme() {
        createTestData();
        Id valueSchemeRtId = [SELECT Id FROM RecordType WHERE DeveloperName = 'Value_Scheme' AND SObjectType = 'Scheme__c' LIMIT 1].Id;
        // Validation: only one of Discount_Amount__c or Discount_Percentage__c allowed
        Scheme__c valueScheme = new Scheme__c(
            Name = 'Test Value Scheme',
            RecordTypeId = valueSchemeRtId,
            Discount_Amount__c = 10,
            Cart_Amount__c = 100,
            Scheme_Start_Date__c = Date.today(),
            Scheme_End_Date__c = Date.today().addMonths(1)
        );
        insert valueScheme;
        Test.startTest();
        ProductListingComponentControllerPortal.AppliedValueSchemeWrapper w =
            ProductListingComponentControllerPortal.getAppliedValueScheme(valueScheme.Id);
        Test.stopTest();
        System.assert(w != null, 'Should return wrapper');
        System.assertEquals(10, w.discountAmount, 'Discount amount should match');
    }

    @isTest
    static void testGetProductForValueScheme() {
        createTestData();
        Product__c testProduct = [SELECT Id FROM Product__c LIMIT 1];
        Test.startTest();
        CartProductWrapper.ProductWrapper w =
            ProductListingComponentControllerPortal.getProductForValueScheme(testProduct.Id);
        Test.stopTest();
        System.assert(w != null, 'Should return wrapper');
        System.assertEquals(testProduct.Id, w.productId, 'Product id should match');
    }

    @isTest
    static void testGetAppliedValueSchemeName() {
        createTestData();
        Id valueSchemeRtId = [SELECT Id FROM RecordType WHERE DeveloperName = 'Value_Scheme' AND SObjectType = 'Scheme__c' LIMIT 1].Id;
        Scheme__c valueScheme = new Scheme__c(
            Name = 'My Value Scheme',
            RecordTypeId = valueSchemeRtId,
            Cart_Amount__c = 100,
            Scheme_Start_Date__c = Date.today(),
            Scheme_End_Date__c = Date.today().addMonths(1)
        );
        insert valueScheme;
        Test.startTest();
        String name = ProductListingComponentControllerPortal.getAppliedValueSchemeName(valueScheme.Id);
        Test.stopTest();
        System.assertEquals('My Value Scheme', name, 'Scheme name should match');
    }

    @isTest
    static void testGetvalueScheme() {
        createTestData();
        User testUser = [SELECT Id FROM User WHERE UserName = 'Hangyotestuser@testhorg.com'];
        System.runAs(testUser) {
            Test.startTest();
            List<ProductListingComponentControllerPortal.SchemeDetailsWrapper> result =
                ProductListingComponentControllerPortal.getvalueScheme(500);
            Test.stopTest();
            System.assert(result != null, 'Should return list');
        }
    }

    // Covers getvalueScheme hierarchy path (schemeIds, hierarchyMap, Scheme_Hierarchy__c query)
    // and SchemeDetailsWrapper constructor/properties when schemes exist with hierarchy
    @isTest
    static void testGetvalueScheme_WithValueSchemesAndHierarchy() {
        createTestData();
        Account underSSAccount = [SELECT Id, Primary_State__c FROM Account WHERE Distributor_Type__c = 'Under Super Stockist' LIMIT 1];
        Region__c region = [SELECT Id, Name FROM Region__c LIMIT 1];
        if (region.Name != underSSAccount.Primary_State__c) {
            region.Name = underSSAccount.Primary_State__c;
            update region;
        }
        Id valueSchemeRtId = [SELECT Id FROM RecordType WHERE DeveloperName = 'Value_Scheme' AND SObjectType = 'Scheme__c' LIMIT 1].Id;
        Scheme__c valueScheme = new Scheme__c(
            Name = 'Value Scheme With Hierarchy',
            RecordTypeId = valueSchemeRtId,
            Under_SS_Scheme__c = true,
            Cart_Amount__c = 100,
            Scheme_Start_Date__c = Date.today().addDays(-1),
            Scheme_End_Date__c = Date.today().addMonths(1)
        );
        insert valueScheme;
        insert new Scheme_Hierarchy__c(
            Scheme__c = valueScheme.Id,
            Account__c = underSSAccount.Id,
            Region__c = region.Id,
            IsActive__c = true
        );
        User underSSUser = [SELECT Id FROM User WHERE UserName = 'Hangyotestuser@testhorg.com'];
        System.runAs(underSSUser) {
            Test.startTest();
            List<ProductListingComponentControllerPortal.SchemeDetailsWrapper> result =
                ProductListingComponentControllerPortal.getvalueScheme(500);
            Test.stopTest();
            System.assert(result != null, 'Should return list');
            System.assert(result.size() > 0, 'Should return at least one scheme when eligible');
            System.assertEquals(valueScheme.Id, result[0].id, 'Wrapper id should match scheme');
            System.assertEquals(valueScheme.Name, result[0].name, 'Wrapper name should match');
            System.assertEquals(true, result[0].isMatchExist, 'Cart meets Cart_Amount__c');
        }
    }

    @isTest
    static void testGetTaxRates_BlankState() {
        Order_tax_value__c othersTax = new Order_tax_value__c(
            Name = 'Others',
            CGST__c = 0.0,
            SGST__c = 0.0,
            IGST__c = 18.0
        );
        insert othersTax;
        Test.startTest();
        Map<String, Decimal> taxRates = ProductListingComponentControllerPortal.getTaxRates('');
        Test.stopTest();
        System.assert(taxRates != null, 'Should return map for blank state');
    }

    // Covers applyQuantityScheme FREE PRODUCT path (promo.productOfferPrice = 0, promo.unittotalPrice = 0)
    @isTest
    static void testApplyQuantityScheme_FreeProduct() {
        createTestData();
        User underSSUser = [SELECT Id FROM User WHERE UserName = 'Hangyotestuser@testhorg.com'];
        Product__c testProduct = [SELECT Id FROM Product__c LIMIT 1];
        Id qtySchemeRtId = [SELECT Id FROM RecordType WHERE DeveloperName = 'Quantity_scheme' AND SObjectType = 'Scheme__c' LIMIT 1].Id;
        Scheme__c freeScheme = new Scheme__c(
            Name = 'Free Product Scheme',
            RecordTypeId = qtySchemeRtId,
            Product__c = testProduct.Id,
            Minimum_Purchase_Quantity__c = 5,
            Promotion_Quantity__c = 1,
            Discount_Percentage__c = 100,
            Under_SS_Scheme__c = true,
            Scheme_Start_Date__c = Date.today().addDays(-1),
            Scheme_End_Date__c = Date.today().addMonths(1)
        );
        insert freeScheme;
        CartProductWrapper.ProductWrapper baseItem = new CartProductWrapper.ProductWrapper();
        baseItem.productId = testProduct.Id;
        baseItem.quantity = 10;
        baseItem.productOfferPrice = 100;
        baseItem.productName = 'Test Product';
        baseItem.productBrand = 'Test Brand';
        baseItem.prodmeasure = 'kg';
        baseItem.isPromotional = false;
        List<CartProductWrapper.ProductWrapper> cartItems = new List<CartProductWrapper.ProductWrapper>{ baseItem };
        System.runAs(underSSUser) {
            Test.startTest();
            List<CartProductWrapper.ProductWrapper> promos =
                ProductListingComponentControllerPortal.applyQuantityScheme(cartItems, freeScheme.Id);
            Test.stopTest();
            System.assert(promos != null, 'Should return list');
            System.assert(promos.size() > 0, 'Should return promo for free product');
            System.assertEquals(0, promos[0].productOfferPrice, 'FREE PRODUCT: offer price should be 0');
            System.assertEquals(0, promos[0].unittotalPrice, 'FREE PRODUCT: unit total should be 0');
        }
    }

    // Covers applyQuantityScheme DISCOUNTED path (promo.productOfferPrice calc, promo.unittotalPrice, promos.add)
    @isTest
    static void testApplyQuantityScheme_DiscountedProduct() {
        createTestData();
        User underSSUser = [SELECT Id FROM User WHERE UserName = 'Hangyotestuser@testhorg.com'];
        Product__c testProduct = [SELECT Id FROM Product__c LIMIT 1];
        Id qtySchemeRtId = [SELECT Id FROM RecordType WHERE DeveloperName = 'Quantity_scheme' AND SObjectType = 'Scheme__c' LIMIT 1].Id;
        Scheme__c discountScheme = new Scheme__c(
            Name = 'Discounted Product Scheme',
            RecordTypeId = qtySchemeRtId,
            Product__c = testProduct.Id,
            Minimum_Purchase_Quantity__c = 5,
            Promotion_Quantity__c = 2,
            Discount_Percentage__c = 50,
            Under_SS_Scheme__c = true,
            Scheme_Start_Date__c = Date.today().addDays(-1),
            Scheme_End_Date__c = Date.today().addMonths(1)
        );
        insert discountScheme;
        CartProductWrapper.ProductWrapper baseItem = new CartProductWrapper.ProductWrapper();
        baseItem.productId = testProduct.Id;
        baseItem.quantity = 10;
        baseItem.productOfferPrice = 100;
        baseItem.productName = 'Test Product';
        baseItem.productBrand = 'Test Brand';
        baseItem.prodmeasure = 'kg';
        baseItem.isPromotional = false;
        List<CartProductWrapper.ProductWrapper> cartItems = new List<CartProductWrapper.ProductWrapper>{ baseItem };
        System.runAs(underSSUser) {
            Test.startTest();
            List<CartProductWrapper.ProductWrapper> promos =
                ProductListingComponentControllerPortal.applyQuantityScheme(cartItems, discountScheme.Id);
            Test.stopTest();
            System.assert(promos != null, 'Should return list');
            System.assert(promos.size() > 0, 'Should return promo for discounted product');
            System.assertEquals(50, promos[0].productOfferPrice, 'DISCOUNTED: 50% of 100 = 50');
            System.assertEquals(200, promos[0].unittotalPrice, 'DISCOUNTED: 50 * 4 promo qty (2 slabs x 2) = 200');
        }
    }

}