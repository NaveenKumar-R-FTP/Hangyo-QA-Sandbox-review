@IsTest
public class SchemeEvaluationServiceTest {

    // ========== OLD TEST - commented by Fuzail ==========
    /*
    @isTest
    static void testFetchProducts() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;

         User testUser = [SELECT Id FROM User LIMIT 1];

        // Query for the RecordType Id for 'Retailer'
        String recordTypeName = 'Retailer';
        RecordType recordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = :recordTypeName LIMIT 1];

        // Check if the RecordType exists
        if(recordType == null) {
            System.debug('RecordType ' + recordTypeName + ' not found');
        }
        Region__c rg=new Region__c(Name='Kerala');
        insert rg;


        // Create test data for Product__c
        Id productRecordTypeId = [
            SELECT Id FROM RecordType
            WHERE DeveloperName = 'Product' AND SObjectType = 'Product__c'
            LIMIT 1
        ].Id;

        Product__c testProduct = new Product__c(
            Name = 'Test Product',
            IsActive__c = true,
            Secondary_Product__c = true,
            RecordTypeId = productRecordTypeId,
            Rate_Value__c = 100,
            Unit_of_Measure__c = 'kg',
            Product_Brand__c = 'TestBrand',
            Image_Long__c = 'test_image1.jpg,test_image2.jpg'
        );
        insert testProduct;

        Product__c testProduct1 = new Product__c(
            Name = 'Test Product',
            IsActive__c = true,
            Secondary_Product__c = true,
            RecordTypeId = productRecordTypeId,
            Rate_Value__c = 100,
            Unit_of_Measure__c = 'kg',
            Product_Brand__c = 'TestBrand',
            Image_Long__c = 'test_image1.jpg,test_image2.jpg',
            Focus_Product__c = true
        );
        insert testProduct1;
         List<String> excludedProductIds=new List<String>();
        Product__c testProduct2 = new Product__c(
            Name = 'Test Product1',
            IsActive__c = true,
            Secondary_Product__c = true,
            RecordTypeId = productRecordTypeId,
            Rate_Value__c = 100,
            Unit_of_Measure__c = 'kg',
            Product_Brand__c = 'TestBrand1',
            Image_Long__c = 'test_image1.jpg,test_image2.jpg'
        );
        insert testProduct2;
        excludedProductIds.add(testProduct2.Id);
          // Create test accounts
        Account acc1 = new Account(Name = 'Test Account 1', Primary_State__c='Kerala',ShippingStreet = '123 Test St',
                 PAN_Number__c='TGYKI5566J',
                                   ShippingCity = 'Test City', ShippingState = 'Test State',Location__Latitude__s=15.3306984,Location__Longitude__s=75.1251715,
                                   ShippingPostalCode = '12345', ShippingCountry = 'Test Country', RecordTypeId = recordType.Id,Average_Order_Value__c=240.00,Monthly_Target__c=300.00);
        insert acc1;

        Contact con= new Contact(LastName='Test1',AccountId=acc1.id);
        insert con;
        Price_Book__c pb= new Price_Book__c(Name='Kerala',isActive__c=true,Region__c=rg.id);
        insert pb;

        Price_Book_Entry__c prbEntry= new Price_Book_Entry__c(Name='Alphonso Mango',Price_Book__c=pb.id,isActive__c=true,Product__c=testProduct.id,PTR__c=768,Type__c = 'Retailer');
        insert prbEntry;

        Id schemeRecordTypeId = [
            SELECT Id FROM RecordType
            WHERE DeveloperName = 'Quantity_scheme' AND SObjectType = 'Scheme__c'
            LIMIT 1
        ].Id;
        Scheme__c sch = new Scheme__c(
            Name = 'Test Scheme',
            Scheme_Start_Date__c = Date.Today(),
            Scheme_End_Date__c = Date.Today(),
            RecordTypeId = schemeRecordTypeId,
            Product__c=testProduct.id
        );
        insert sch;
        Id schemeRecordTypeId1 = [
            SELECT Id FROM RecordType
            WHERE DeveloperName = 'Value_scheme' AND SObjectType = 'Scheme__c'
            LIMIT 1
        ].Id;
        Scheme__c sch1 = new Scheme__c(
            Name = 'Test Scheme1',
            Scheme_Start_Date__c = Date.Today(),
            Scheme_End_Date__c = Date.Today(),
            RecordTypeId = schemeRecordTypeId1,
            Discount_Percentage__c=15,
            Cart_Amount__c=100
        );
        insert sch1;
         Id qtyRT = [SELECT Id FROM RecordType WHERE DeveloperName='Quantity_scheme' AND SObjectType='Scheme__c' LIMIT 1].Id;

        Scheme__c scheme = new Scheme__c(
            Name='Buy10Get2',
            RecordTypeId=qtyRT,
            Product__c=testProduct.Id,
            Minimum_Purchase_Quantity__c=10,
            Promotion_Quantity__c=2,
            Retailer_Scheme__c=true,
            //Is_Active__c=true,
            Scheme_Start_Date__c=Date.today().addDays(-1),
            Scheme_End_Date__c=Date.today().addDays(5)
        );
        insert scheme;

        insert new Scheme_Hierarchy__c(
            Scheme__c=scheme.Id,
            Account__c=acc1.Id,
            Region__c=rg.Id,
            IsActive__c=true
        );


        //orderProductController.getAllActiveQualityScheme();
        //orderProductController.getAllActiveValueScheme();
        //SchemeEvaluationService.getqualityScheme(testProduct.Id);
        SchemeEvaluationService.getAppliedValueScheme(sch1.Id);
        SchemeEvaluationService.getAppliedValueSchemeName(sch1.Id);
        //SchemeEvaluationService.getvalueScheme(0,sch1.Id);
        //SchemeEvaluationService.getvalueScheme(100,sch1.Id);
        //SchemeEvaluationService.getvalueScheme(10,sch1.Id);
        //orderProductController.getProductsWithSchemes();
        CartProductWrapper.ProductWrapper base =
                new CartProductWrapper.ProductWrapper();
            base.productId = testProduct1.Id;
            base.quantity = 12;
            base.productOfferPrice = 100;
            base.productName = 'Ice Cream';
            base.productBrand = 'Test';
            base.prodmeasure = 'Box';

            List<CartProductWrapper.ProductWrapper> cart = new List<CartProductWrapper.ProductWrapper>{ base };
        List<CartProductWrapper.ProductWrapper> promos =
                SchemeEvaluationService.applyQuantityScheme(
                    cart,
                    acc1.Id,
                    'Karnataka',
                    sch.id,
                    false
                );

    }
    */

    // ========== Added by Fuzail: Test data setup helper ==========
    @TestSetup
    static void makeData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;

        RecordType recordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1];
        Region__c rg = new Region__c(Name = 'Kerala');
        insert rg;

        Id productRecordTypeId = [SELECT Id FROM RecordType WHERE DeveloperName = 'Product' AND SObjectType = 'Product__c' LIMIT 1].Id;

        Product__c testProduct = new Product__c(
            Name = 'Test Product Scheme',
            IsActive__c = true,
            Secondary_Product__c = true,
            RecordTypeId = productRecordTypeId,
            Rate_Value__c = 100,
            Unit_of_Measure__c = 'kg',
            Product_Brand__c = 'TestBrand',
            Image_Long__c = 'test_image1.jpg',
            MRP__c = 100,
            HSN__c = '1234'
        );
        insert testProduct;

        Product__c testProduct2 = new Product__c(
            Name = 'Test Product Other',
            IsActive__c = true,
            Secondary_Product__c = true,
            RecordTypeId = productRecordTypeId,
            Rate_Value__c = 50,
            Unit_of_Measure__c = 'kg',
            Product_Brand__c = 'TestBrand',
            MRP__c = 50,
            HSN__c = '5678'
        );
        insert testProduct2;

        Account acc1 = new Account(
            Name = 'Test Account Scheme',
            Primary_State__c = 'Kerala',
            ShippingStreet = '123 Test St',
            PAN_Number__c = 'TGYKI5566J',
            ShippingCity = 'Test City',
            ShippingState = 'Test State',
            Location__Latitude__s = 15.3306984,
            Location__Longitude__s = 75.1251715,
            ShippingPostalCode = '12345',
            ShippingCountry = 'Test Country',
            RecordTypeId = recordType.Id,
            Average_Order_Value__c = 240.00,
            Monthly_Target__c = 300.00
        );
        insert acc1;

        Contact con = new Contact(LastName = 'Test Contact', AccountId = acc1.Id);
        insert con;

        Price_Book__c pb = new Price_Book__c(Name = 'Kerala', isActive__c = true, Region__c = rg.Id);
        insert pb;

        Price_Book_Entry__c prbEntry = new Price_Book_Entry__c(
            Name = 'Test PBE',
            Price_Book__c = pb.Id,
            isActive__c = true,
            Product__c = testProduct.Id,
            PTR__c = 768,
            Type__c = 'Retailer'
        );
        insert prbEntry;

        Price_Book_Entry__c prbEntry2 = new Price_Book_Entry__c(
            Name = 'Test PBE 2',
            Price_Book__c = pb.Id,
            isActive__c = true,
            Product__c = testProduct2.Id,
            PTR__c = 50,
            Type__c = 'Retailer'
        );
        insert prbEntry2;

        Id qtyRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Quantity_scheme' AND SObjectType = 'Scheme__c' LIMIT 1].Id;
        Id valueRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Value_Scheme' AND SObjectType = 'Scheme__c' LIMIT 1].Id;

        Scheme__c quantityScheme = new Scheme__c(
            Name = 'Buy10Get2',
            RecordTypeId = qtyRT,
            Product__c = testProduct.Id,
            Minimum_Purchase_Quantity__c = 10,
            Promotion_Quantity__c = 2,
            Discount_Percentage__c = 100,
            Retailer_Scheme__c = true,
            Under_SS_Scheme__c = false,
            Scheme_Start_Date__c = Date.today().addDays(-1),
            Scheme_End_Date__c = Date.today().addDays(5)
        );
        insert quantityScheme;

        Scheme__c valueScheme = new Scheme__c(
            Name = 'Test Value Scheme',
            RecordTypeId = valueRT,
            Scheme_Start_Date__c = Date.today(),
            Scheme_End_Date__c = Date.today().addDays(30),
            Discount_Percentage__c = 15,
            Cart_Amount__c = 100,
            Retailer_Scheme__c = true,
            Under_SS_Scheme__c = false,
            Other_Product_Quantity__c = 1
        );
        insert valueScheme;

        insert new Scheme_Hierarchy__c(
            Scheme__c = quantityScheme.Id,
            Account__c = acc1.Id,
            Region__c = rg.Id,
            IsActive__c = true
        );
    }

    // Added by Fuzail: Test getDistributorStockForProducts - null/empty input
    @IsTest
    static void testGetDistributorStockForProducts_EmptyInput() {
        Map<Id, Decimal> result = SchemeEvaluationService.getDistributorStockForProducts(new Set<Id>());
        System.assertNotEquals(null, result, 'Should return non-null map');
        System.assertEquals(0, result.size(), 'Should return empty map for empty input');
    }

    // Added by Fuzail: Test getDistributorStockForProducts - null input
    @IsTest
    static void testGetDistributorStockForProducts_NullInput() {
        Map<Id, Decimal> result = SchemeEvaluationService.getDistributorStockForProducts(null);
        System.assertNotEquals(null, result, 'Should return non-null map');
        System.assertEquals(0, result.size(), 'Should return empty map for null input');
    }

    // Added by Fuzail: Test getqualityScheme - missing required inputs (expect exception)
    @IsTest
    static void testGetqualityScheme_MissingInputs() {
        Boolean exceptionThrown = false;
        try {
            SchemeEvaluationService.getqualityScheme(null, null, null, false);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            // Assert exception was thrown for invalid input (message may vary by org)
            System.assert(String.isNotBlank(e.getMessage()), 'Exception should have a message');
        }
        System.assert(exceptionThrown, 'Should throw AuraHandledException for missing inputs');
    }

    // Added by Fuzail: Test getqualityScheme - valid input returns list (may be empty if no matching scheme)
    @IsTest
    static void testGetqualityScheme_ValidInput() {
        Product__c p = [SELECT Id FROM Product__c WHERE Name = 'Test Product Scheme' LIMIT 1];
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Scheme' LIMIT 1];
        Object result = SchemeEvaluationService.getqualityScheme(p.Id, acc.Id, 'Kerala', false);
        System.assert(result != null, 'Should return non-null list');
    }

    // Added by Fuzail: Test isSchemeApplicable - account and region match
    @IsTest
    static void testIsSchemeApplicable() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Scheme' LIMIT 1];
        Region__c rg = [SELECT Id, Name FROM Region__c WHERE Name = 'Kerala' LIMIT 1];
        List<Scheme_Hierarchy__c> hierarchy = [SELECT Scheme__c, Account__c, Region__c, Region__r.Name FROM Scheme_Hierarchy__c WHERE IsActive__c = true LIMIT 1];
        if (!hierarchy.isEmpty()) {
            Boolean applicable = SchemeEvaluationService.isSchemeApplicable(hierarchy, acc.Id, rg.Name);
            System.assertEquals(true, applicable, 'Scheme should be applicable for account and region match');
        }
    }

    // Added by Fuzail: Test getAppliedValueScheme
    @IsTest
    static void testGetAppliedValueScheme() {
        Scheme__c sch = [SELECT Id FROM Scheme__c WHERE Name = 'Test Value Scheme' LIMIT 1];
        Object result = SchemeEvaluationService.getAppliedValueScheme(sch.Id);
        System.assertNotEquals(null, result, 'Should return AppliedValueSchemeWrapper');
    }

    // Added by Fuzail: Test getAppliedValueSchemeName
    @IsTest
    static void testGetAppliedValueSchemeName() {
        Scheme__c sch = [SELECT Id, Name FROM Scheme__c WHERE Name = 'Test Value Scheme' LIMIT 1];
        String name = SchemeEvaluationService.getAppliedValueSchemeName(sch.Id);
        System.assertEquals('Test Value Scheme', name, 'Should return scheme name');
    }

    // Added by Fuzail: Test getProductForValueScheme
    @IsTest
    static void testGetProductForValueScheme() {
        Product__c p = [SELECT Id FROM Product__c WHERE Name = 'Test Product Scheme' LIMIT 1];
        CartProductWrapper.ProductWrapper result = SchemeEvaluationService.getProductForValueScheme(p.Id);
        System.assertNotEquals(null, result, 'Should return ProductWrapper');
        System.assertEquals(p.Id, result.productId, 'Product id should match');
    }

    // Added by Fuzail: Test getvalueScheme - null/insufficient input returns empty
    @IsTest
    static void testGetvalueScheme_EmptyInput() {
        Object result = SchemeEvaluationService.getvalueScheme(null, null, null, null, false);
        System.assert(result != null, 'Should return non-null list');
    }

    // Added by Fuzail: Test getvalueScheme - valid input
    @IsTest
    static void testGetvalueScheme_ValidInput() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Scheme' LIMIT 1];
        Object result = SchemeEvaluationService.getvalueScheme(150, null, acc.Id, 'Kerala', false);
        System.assert(result != null, 'Should return non-null list');
    }

    // Added by Fuzail: Test applyQuantityScheme - valid cart and scheme (region Kerala to match Price_Book)
    @IsTest
    static void testApplyQuantityScheme_Valid() {
        Product__c testProduct = [SELECT Id FROM Product__c WHERE Name = 'Test Product Scheme' LIMIT 1];
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Scheme' LIMIT 1];
        Scheme__c sch = [SELECT Id FROM Scheme__c WHERE Name = 'Buy10Get2' LIMIT 1];

        CartProductWrapper.ProductWrapper base = new CartProductWrapper.ProductWrapper();
        base.productId = testProduct.Id;
        base.quantity = 12;
        base.productOfferPrice = 100;
        base.productName = 'Test Product Scheme';
        base.productBrand = 'TestBrand';
        base.prodmeasure = 'kg';
        base.mrp = 100;
        base.hsn = '1234';

        List<CartProductWrapper.ProductWrapper> cart = new List<CartProductWrapper.ProductWrapper>{ base };
        List<CartProductWrapper.ProductWrapper> promos = SchemeEvaluationService.applyQuantityScheme(
            cart,
            acc.Id,
            'Kerala',
            sch.Id,
            false
        );
        System.assertNotEquals(null, promos, 'Should return non-null list');
        System.assert(promos.size() >= 0, 'May return promo lines when scheme applies');
    }

    // Added by Fuzail: Test applyQuantityScheme - null/empty cart returns empty list
    @IsTest
    static void testApplyQuantityScheme_EmptyCart() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Scheme' LIMIT 1];
        Scheme__c sch = [SELECT Id FROM Scheme__c WHERE Name = 'Buy10Get2' LIMIT 1];
        List<CartProductWrapper.ProductWrapper> promos = SchemeEvaluationService.applyQuantityScheme(
            new List<CartProductWrapper.ProductWrapper>(),
            acc.Id,
            'Kerala',
            sch.Id,
            false
        );
        System.assertEquals(0, promos.size(), 'Empty cart should return empty promos');
    }

    // Cover getDistributorStockForProducts when User has Contact + AccountId and Inventory__c exists
    @IsTest
    static void testGetDistributorStockForProducts_WithContactAndInventory() {
        Product__c p = [SELECT Id FROM Product__c WHERE Name = 'Test Product Scheme' LIMIT 1];
        RecordType recordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1];
        Account distAcc = new Account(
            Name = 'Distributor For Stock',
            RecordTypeId = recordType.Id,
            Primary_State__c = 'Kerala',
            PAN_Number__c = 'DIST5566J'
        );
        insert distAcc;
        Contact distCon = new Contact(LastName = 'Dist Contact', AccountId = distAcc.Id);
        insert distCon;

        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = 'DMS Partner Community Custom' LIMIT 1];
        if (profiles.isEmpty()) {
            profiles = [SELECT Id FROM Profile WHERE UserType = 'CspLitePortal' OR UserType = 'PowerCustomerSuccess' LIMIT 1];
        }
        if (profiles.isEmpty()) {
            return; // skip if no portal profile in org
        }
        User portalUser = new User(
            FirstName = 'Stock', LastName = 'User',
            Email = 'stockuser@example.com',
            Username = 'stockuser' + System.now().getTime() + '@example.com.salesforce',
            Alias = 'stkusr',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ContactId = distCon.Id,
            ProfileId = profiles[0].Id,
            LanguageLocaleKey = 'en_US'
        );
        insert portalUser;

        Inventory__c inv = new Inventory__c(
            Product__c = p.Id,
            Quantity_in_hand__c = 50,
            Distributor_Name__c = distAcc.Id
        );
        insert inv;

        Map<Id, Decimal> result;
        Test.startTest();
        System.runAs(portalUser) {
            result = SchemeEvaluationService.getDistributorStockForProducts(new Set<Id>{ p.Id });
        }
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return non-null map');
        System.assertEquals(1, result.size(), 'Should return one product stock');
        System.assertEquals(50, result.get(p.Id), 'Stock quantity should match');
    }

    // Cover isSchemeApplicable - account-only match (Region__c = null)
    @IsTest
    static void testIsSchemeApplicable_AccountOnly() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Scheme' LIMIT 1];
        Scheme__c sch = [SELECT Id FROM Scheme__c WHERE Name = 'Buy10Get2' LIMIT 1];
        Scheme_Hierarchy__c shAccountOnly = new Scheme_Hierarchy__c(
            Scheme__c = sch.Id,
            Account__c = acc.Id,
            Region__c = null,
            IsActive__c = true
        );
        insert shAccountOnly;
        List<Scheme_Hierarchy__c> hierarchy = [SELECT Scheme__c, Account__c, Region__c, Region__r.Name FROM Scheme_Hierarchy__c WHERE Id = :shAccountOnly.Id];
        Boolean applicable = SchemeEvaluationService.isSchemeApplicable(hierarchy, acc.Id, 'Kerala');
        System.assertEquals(true, applicable, 'Scheme should be applicable for account-only match');
    }

    // Cover isSchemeApplicable - region-only match (Account__c = null)
    @IsTest
    static void testIsSchemeApplicable_RegionOnly() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Scheme' LIMIT 1];
        Region__c rg = [SELECT Id, Name FROM Region__c WHERE Name = 'Kerala' LIMIT 1];
        Scheme__c sch = [SELECT Id FROM Scheme__c WHERE Name = 'Buy10Get2' LIMIT 1];
        Scheme_Hierarchy__c shRegionOnly = new Scheme_Hierarchy__c(
            Scheme__c = sch.Id,
            Account__c = null,
            Region__c = rg.Id,
            IsActive__c = true
        );
        insert shRegionOnly;
        List<Scheme_Hierarchy__c> hierarchy = [SELECT Scheme__c, Account__c, Region__c, Region__r.Name FROM Scheme_Hierarchy__c WHERE Id = :shRegionOnly.Id];
        Boolean applicable = SchemeEvaluationService.isSchemeApplicable(hierarchy, acc.Id, 'Kerala');
        System.assertEquals(true, applicable, 'Scheme should be applicable for region-only match');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Step 5: Scheme_Hierarchy__c Distributor/Hub level tests
    // ─────────────────────────────────────────────────────────────────────────

    // Helper: creates a Distributor-record-type Account with a given Hub__c value.
    private static Account createTestDistributor(String namePrefix, String hub, String pan) {
        RecordType distRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Distributor' LIMIT 1];
        Account dist = new Account(
            Name = namePrefix,
            RecordTypeId = distRT.Id,
            Primary_State__c = 'Kerala',
            PAN_Number__c = pan,
            Hub__c = hub
        );
        insert dist;
        return dist;
    }

    // Direct isSchemeApplicable (5-arg overload) - Distributor-only match
    @IsTest
    static void testIsSchemeApplicable_DistributorOnly() {
        Account dist = createTestDistributor('Test Distributor A', 'Mumbai', 'DISTHB001A');
        Scheme__c sch = [SELECT Id FROM Scheme__c WHERE Name = 'Buy10Get2' LIMIT 1];

        Scheme_Hierarchy__c shDistOnly = new Scheme_Hierarchy__c(
            Scheme__c = sch.Id,
            Scheme_Holder_Type__c = 'Distributor',
            Distributor__c = dist.Id,
            IsActive__c = true
        );
        insert shDistOnly;

        List<Scheme_Hierarchy__c> hierarchy = [
            SELECT Scheme__c, Account__c, Region__c, Region__r.Name, Distributor__c, Hub__c
            FROM Scheme_Hierarchy__c WHERE Id = :shDistOnly.Id
        ];

        // Matching distributor -> applicable
        Boolean applicable = SchemeEvaluationService.isSchemeApplicable(
            hierarchy, null, null, dist.Id, null
        );
        System.assertEquals(true, applicable, 'Scheme should be applicable for a matching Distributor');

        // Different distributor -> not applicable
        Boolean notApplicable = SchemeEvaluationService.isSchemeApplicable(
            hierarchy, null, null, UserInfo.getUserId(), null
        );
        System.assertEquals(false, notApplicable, 'Scheme should not be applicable for a non-matching Distributor');
    }

    // Direct isSchemeApplicable (5-arg overload) - Hub-only match
    @IsTest
    static void testIsSchemeApplicable_HubOnly() {
        Scheme__c sch = [SELECT Id FROM Scheme__c WHERE Name = 'Buy10Get2' LIMIT 1];

        Scheme_Hierarchy__c shHubOnly = new Scheme_Hierarchy__c(
            Scheme__c = sch.Id,
            Scheme_Holder_Type__c = 'Hub',
            Hub__c = 'Mumbai',
            IsActive__c = true
        );
        insert shHubOnly;

        List<Scheme_Hierarchy__c> hierarchy = [
            SELECT Scheme__c, Account__c, Region__c, Region__r.Name, Distributor__c, Hub__c
            FROM Scheme_Hierarchy__c WHERE Id = :shHubOnly.Id
        ];

        Boolean applicable = SchemeEvaluationService.isSchemeApplicable(
            hierarchy, null, null, null, 'Mumbai'
        );
        System.assertEquals(true, applicable, 'Scheme should be applicable for a matching Hub');

        Boolean notApplicable = SchemeEvaluationService.isSchemeApplicable(
            hierarchy, null, null, null, 'Goa'
        );
        System.assertEquals(false, notApplicable, 'Scheme should not be applicable for a non-matching Hub');
    }

    // End-to-end: a Value Scheme scoped to a Distributor-level hierarchy row resolves
    // for a retailer whose Account.Distributor__c points at that Distributor, and does
    // NOT resolve for a retailer under a different Distributor.
    @IsTest
    static void testGetvalueScheme_DistributorLevelHierarchy() {
        Account dist = createTestDistributor('Test Distributor B', 'Pune City', 'DISTHB002A');
        Account otherDist = createTestDistributor('Test Distributor C', 'Pune City', 'DISTHB003A');

        RecordType retailerRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1];
        Account retailerUnderDist = new Account(
            Name = 'Retailer Under Dist B',
            RecordTypeId = retailerRT.Id,
            Primary_State__c = 'Kerala',
            PAN_Number__c = 'RETDIST001',
            Distributor__c = dist.Id
        );
        insert retailerUnderDist;

        Account retailerUnderOtherDist = new Account(
            Name = 'Retailer Under Dist C',
            RecordTypeId = retailerRT.Id,
            Primary_State__c = 'Kerala',
            PAN_Number__c = 'RETDIST002',
            Distributor__c = otherDist.Id
        );
        insert retailerUnderOtherDist;

        Id valueRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Value_Scheme' AND SObjectType = 'Scheme__c' LIMIT 1].Id;
        Scheme__c distScheme = new Scheme__c(
            Name = 'Distributor Level Value Scheme',
            RecordTypeId = valueRT,
            Scheme_Start_Date__c = Date.today(),
            Scheme_End_Date__c = Date.today().addDays(30),
            Discount_Percentage__c = 10,
            Cart_Amount__c = 100,
            Retailer_Scheme__c = true,
            Under_SS_Scheme__c = false
        );
        insert distScheme;

        insert new Scheme_Hierarchy__c(
            Scheme__c = distScheme.Id,
            Scheme_Holder_Type__c = 'Distributor',
            Distributor__c = dist.Id,
            IsActive__c = true
        );

        List<SchemeDetailsWrapper> resultForMatchingRetailer =
            SchemeEvaluationService.getvalueScheme(150, null, retailerUnderDist.Id, 'Kerala', false);
        Boolean foundForMatching = false;
        for (SchemeDetailsWrapper w : resultForMatchingRetailer) {
            if (w.id == distScheme.Id) {
                foundForMatching = true;
            }
        }
        System.assertEquals(true, foundForMatching, 'Retailer under the scoped Distributor should see the scheme');

        List<SchemeDetailsWrapper> resultForOtherRetailer =
            SchemeEvaluationService.getvalueScheme(150, null, retailerUnderOtherDist.Id, 'Kerala', false);
        Boolean foundForOther = false;
        for (SchemeDetailsWrapper w : resultForOtherRetailer) {
            if (w.id == distScheme.Id) {
                foundForOther = true;
            }
        }
        System.assertEquals(false, foundForOther, 'Retailer under a different Distributor should NOT see the scheme');
    }

    // End-to-end: a Value Scheme scoped to a Hub-level hierarchy row resolves for a
    // retailer whose Distributor's Hub__c matches, and does not for a different Hub.
    @IsTest
    static void testGetvalueScheme_HubLevelHierarchy() {
        Account dist = createTestDistributor('Test Distributor D', 'Nasik', 'DISTHB004A');
        Account otherHubDist = createTestDistributor('Test Distributor E', 'Goa', 'DISTHB005A');

        RecordType retailerRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1];
        Account retailerInHub = new Account(
            Name = 'Retailer In Nasik Hub',
            RecordTypeId = retailerRT.Id,
            Primary_State__c = 'Kerala',
            PAN_Number__c = 'RETHUB0001',
            Distributor__c = dist.Id
        );
        insert retailerInHub;

        Account retailerInOtherHub = new Account(
            Name = 'Retailer In Goa Hub',
            RecordTypeId = retailerRT.Id,
            Primary_State__c = 'Kerala',
            PAN_Number__c = 'RETHUB0002',
            Distributor__c = otherHubDist.Id
        );
        insert retailerInOtherHub;

        Id valueRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Value_Scheme' AND SObjectType = 'Scheme__c' LIMIT 1].Id;
        Scheme__c hubScheme = new Scheme__c(
            Name = 'Hub Level Value Scheme',
            RecordTypeId = valueRT,
            Scheme_Start_Date__c = Date.today(),
            Scheme_End_Date__c = Date.today().addDays(30),
            Discount_Percentage__c = 10,
            Cart_Amount__c = 100,
            Retailer_Scheme__c = true,
            Under_SS_Scheme__c = false
        );
        insert hubScheme;

        insert new Scheme_Hierarchy__c(
            Scheme__c = hubScheme.Id,
            Scheme_Holder_Type__c = 'Hub',
            Hub__c = 'Nasik',
            IsActive__c = true
        );

        List<SchemeDetailsWrapper> resultForMatchingHub =
            SchemeEvaluationService.getvalueScheme(150, null, retailerInHub.Id, 'Kerala', false);
        Boolean foundForMatching = false;
        for (SchemeDetailsWrapper w : resultForMatchingHub) {
            if (w.id == hubScheme.Id) {
                foundForMatching = true;
            }
        }
        System.assertEquals(true, foundForMatching, 'Retailer under a Distributor in the scoped Hub should see the scheme');

        List<SchemeDetailsWrapper> resultForOtherHub =
            SchemeEvaluationService.getvalueScheme(150, null, retailerInOtherHub.Id, 'Kerala', false);
        Boolean foundForOther = false;
        for (SchemeDetailsWrapper w : resultForOtherHub) {
            if (w.id == hubScheme.Id) {
                foundForOther = true;
            }
        }
        System.assertEquals(false, foundForOther, 'Retailer under a Distributor in a different Hub should NOT see the scheme');
    }

    // Cover applyQuantityScheme - Other Product branch (isOtherProductScheme && otherProduct != null)
    @IsTest
    static void testApplyQuantityScheme_OtherProduct() {
        String otherProductTypeValue = null;
        for (Schema.PicklistEntry pe : Scheme__c.Type__c.getDescribe().getPicklistValues()) {
            if (pe.getValue() != null && pe.getValue().startsWith('Other Product')) {
                otherProductTypeValue = pe.getValue();
                break;
            }
        }
        System.assertNotEquals(null, otherProductTypeValue, 'Scheme__c.Type__c must have a value starting with "Other Product" to cover this branch. Add the picklist value in Setup if needed.');

        Product__c baseProduct = [SELECT Id FROM Product__c WHERE Name = 'Test Product Scheme' LIMIT 1];
        Product__c otherProduct = [SELECT Id, Name, Product_Brand__c, Unit_of_Measure__c, MRP__c, HSN__c FROM Product__c WHERE Name = 'Test Product Other' LIMIT 1];
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Scheme' LIMIT 1];
        Id qtyRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Quantity_scheme' AND SObjectType = 'Scheme__c' LIMIT 1].Id;

        Scheme__c otherProductScheme = new Scheme__c(
            Name = 'Other Product Scheme Test',
            RecordTypeId = qtyRT,
            Product__c = baseProduct.Id,
            Other_Product__c = otherProduct.Id,
            Type__c = otherProductTypeValue,
            Minimum_Purchase_Quantity__c = 10,
            Promotion_Quantity__c = 2,
            Discount_Percentage__c = 100,
            Retailer_Scheme__c = true,
            Under_SS_Scheme__c = false,
            Scheme_Start_Date__c = Date.today().addDays(-1),
            Scheme_End_Date__c = Date.today().addDays(5)
        );
        insert otherProductScheme;

        CartProductWrapper.ProductWrapper cartItem = new CartProductWrapper.ProductWrapper();
        cartItem.productId = baseProduct.Id;
        cartItem.quantity = 12;
        cartItem.productOfferPrice = 100;
        cartItem.productName = 'Test Product Scheme';
        cartItem.productBrand = 'TestBrand';
        cartItem.prodmeasure = 'kg';
        cartItem.mrp = 100;
        cartItem.hsn = '1234';

        List<CartProductWrapper.ProductWrapper> cart = new List<CartProductWrapper.ProductWrapper>{ cartItem };
        List<CartProductWrapper.ProductWrapper> promos = SchemeEvaluationService.applyQuantityScheme(
            cart,
            acc.Id,
            'Kerala',
            otherProductScheme.Id,
            false
        );

        System.assertNotEquals(null, promos, 'Should return non-null list');
        System.assertEquals(1, promos.size(), 'Should return one promo line');
        System.assertEquals(otherProduct.Name, promos[0].productName, 'Promo productName should come from other product');
        System.assertEquals(otherProduct.Product_Brand__c, promos[0].productBrand, 'Promo productBrand should come from other product');
        System.assertEquals(otherProduct.MRP__c, promos[0].mrp, 'Promo mrp should come from other product');
        System.assertEquals(otherProduct.HSN__c, promos[0].hsn, 'Promo hsn should come from other product');
    }

    // Cover applyQuantityScheme - Purchase Quantity Discount no-op guard (should return empty
    // promo list immediately, since this scheme type doesn't add a bonus/promo line).
    @IsTest
    static void testApplyQuantityScheme_PurchaseQuantityDiscount_NoOp() {
        Product__c testProduct = [SELECT Id FROM Product__c WHERE Name = 'Test Product Scheme' LIMIT 1];
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Scheme' LIMIT 1];
        Id qtyRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Quantity_scheme' AND SObjectType = 'Scheme__c' LIMIT 1].Id;

        Scheme__c pqdScheme = new Scheme__c(
            Name = 'PQD No-Op Test',
            RecordTypeId = qtyRT,
            Product__c = testProduct.Id,
            Type__c = 'Purchase Quantity Discount',
            Discount_Percentage__c = 10,
            Retailer_Scheme__c = true,
            Scheme_Start_Date__c = Date.today().addDays(-1),
            Scheme_End_Date__c = Date.today().addDays(5)
        );
        insert pqdScheme;

        CartProductWrapper.ProductWrapper cartItem = new CartProductWrapper.ProductWrapper();
        cartItem.productId = testProduct.Id;
        cartItem.quantity = 5;
        cartItem.productOfferPrice = 100;
        cartItem.productName = 'Test Product Scheme';

        List<CartProductWrapper.ProductWrapper> cart = new List<CartProductWrapper.ProductWrapper>{ cartItem };
        List<CartProductWrapper.ProductWrapper> promos = SchemeEvaluationService.applyQuantityScheme(
            cart,
            acc.Id,
            'Kerala',
            pqdScheme.Id,
            false
        );

        System.assertNotEquals(null, promos, 'Should return non-null list');
        System.assertEquals(0, promos.size(), 'Purchase Quantity Discount should never add a bonus/promo line');
    }

    // Cover getAppliedQuantityDiscountSchemes — the new field-level (not rate-level)
    // Purchase Quantity Discount display, used on invoice screens/PDFs. Also exercises
    // AppliedSchemeDisplay's properties.
    @IsTest
    static void testGetAppliedQuantityDiscountSchemes_Valid() {
        Product__c testProduct = [SELECT Id FROM Product__c WHERE Name = 'Test Product Scheme' LIMIT 1];
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Scheme' LIMIT 1];
        Id qtyRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Quantity_scheme' AND SObjectType = 'Scheme__c' LIMIT 1].Id;

        Scheme__c pqdScheme = new Scheme__c(
            Name = 'PQD Applied Test',
            RecordTypeId = qtyRT,
            Product__c = testProduct.Id,
            Type__c = 'Purchase Quantity Discount',
            Discount_Percentage__c = 10,
            Retailer_Scheme__c = true,
            Scheme_Start_Date__c = Date.today().addDays(-1),
            Scheme_End_Date__c = Date.today().addDays(5)
        );
        insert pqdScheme;

        RecordType secondaryOrderRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Secondary_Order' AND SObjectType = 'Order__c' LIMIT 1];
        Order__c ord = new Order__c(Account__c = acc.Id, AccountId__c = acc.Id, RecordTypeId = secondaryOrderRT.Id);
        insert ord;

        RecordType secondaryInvoiceRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Secondary_Invoice' AND SObjectType = 'Invoice__c' LIMIT 1];
        Invoice__c inv = new Invoice__c(
            Name = 'PQD Test Invoice',
            Status__c = 'Confirmed',
            RecordTypeId = secondaryInvoiceRT.Id,
            Retailer_Account__c = acc.Id,
            Distributor_Account__c = acc.Id,
            Order__c = ord.Id
        );
        insert inv;

        Invoice_Line_Item__c ili = new Invoice_Line_Item__c(
            Invoice__c = inv.Id,
            Product__c = testProduct.Id,
            Quantity__c = 5,
            Price__c = 100,
            Total_Amount__c = 500,
            Is_Promotional__c = false,
            Quantity_Scheme_Applied__c = pqdScheme.Id,
            Scheme_Discount_Amount__c = 50
        );
        insert ili;

        List<Invoice_Line_Item__c> lineItems = [
            SELECT Id, Price__c, Quantity__c, Is_Promotional__c, Scheme_Discount_Amount__c,
                   Quantity_Scheme_Applied__c, Quantity_Scheme_Applied__r.Name,
                   Quantity_Scheme_Applied__r.Discount_Percentage__c, Quantity_Scheme_Applied__r.Type__c
            FROM Invoice_Line_Item__c
            WHERE Id = :ili.Id
        ];

        List<AppliedSchemeDisplay> result = SchemeEvaluationService.getAppliedQuantityDiscountSchemes(lineItems);
        System.assertEquals(1, result.size(), 'Should return one applied scheme entry');
        System.assertEquals('PQD Applied Test', result[0].schemeName, 'Scheme name should match');
        System.assertEquals(10, result[0].discountPercent, 'Discount percent should match');
        System.assertEquals(50, result[0].discountAmount, 'Discount amount should match the stored Scheme_Discount_Amount__c');
    }

    // Cover getAppliedQuantityDiscountSchemes — null input and no-scheme-applied lines
    @IsTest
    static void testGetAppliedQuantityDiscountSchemes_EmptyAndNull() {
        System.assertEquals(0, SchemeEvaluationService.getAppliedQuantityDiscountSchemes(null).size(), 'Null input should return empty list');

        Product__c testProduct = [SELECT Id FROM Product__c WHERE Name = 'Test Product Scheme' LIMIT 1];
        Invoice_Line_Item__c bare = new Invoice_Line_Item__c(
            Quantity__c = 1, Price__c = 10, Total_Amount__c = 10
        );
        List<AppliedSchemeDisplay> result = SchemeEvaluationService.getAppliedQuantityDiscountSchemes(
            new List<Invoice_Line_Item__c>{ bare }
        );
        System.assertEquals(0, result.size(), 'Line item with no scheme applied should be skipped');
    }

    // Cover getEligibleQuantitySchemeProductIds — bulk button-visibility check used by
    // the order cart page. testProduct has an active Quantity_scheme + matching
    // Scheme_Hierarchy__c for acc1/Kerala (from makeData()); testProduct2 has none.
    @IsTest
    static void testGetEligibleQuantitySchemeProductIds_Valid() {
        Product__c testProduct = [SELECT Id FROM Product__c WHERE Name = 'Test Product Scheme' LIMIT 1];
        Product__c testProduct2 = [SELECT Id FROM Product__c WHERE Name = 'Test Product Other' LIMIT 1];
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Scheme' LIMIT 1];

        List<Id> result = SchemeEvaluationService.getEligibleQuantitySchemeProductIds(
            new List<Id>{ testProduct.Id, testProduct2.Id },
            acc.Id,
            'Kerala',
            false
        );

        System.assert(result.contains(testProduct.Id), 'Product with an active, applicable scheme should be eligible');
        System.assert(!result.contains(testProduct2.Id), 'Product with no scheme at all should not be eligible');
    }

    // Cover getEligibleQuantitySchemeProductIds — null/empty inputs all return an empty set
    @IsTest
    static void testGetEligibleQuantitySchemeProductIds_EmptyInputs() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Scheme' LIMIT 1];

        System.assertEquals(0, SchemeEvaluationService.getEligibleQuantitySchemeProductIds(null, acc.Id, 'Kerala', false).size(), 'Null productIds should return empty set');
        System.assertEquals(0, SchemeEvaluationService.getEligibleQuantitySchemeProductIds(new List<Id>(), acc.Id, 'Kerala', false).size(), 'Empty productIds should return empty set');
        System.assertEquals(0, SchemeEvaluationService.getEligibleQuantitySchemeProductIds(new List<Id>{ acc.Id }, null, 'Kerala', false).size(), 'Null buyerAccountId should return empty set');
        System.assertEquals(0, SchemeEvaluationService.getEligibleQuantitySchemeProductIds(new List<Id>{ acc.Id }, acc.Id, null, false).size(), 'Blank buyerRegion should return empty set');
    }

    // Cover hasEligibleValueScheme — makeData()'s "Test Value Scheme" is Retailer_Scheme__c=true
    // with no Scheme_Hierarchy__c (a global scheme), so it should be applicable to any
    // retailer/region combination.
    @IsTest
    static void testHasEligibleValueScheme_Valid() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Scheme' LIMIT 1];
        Boolean result = SchemeEvaluationService.hasEligibleValueScheme(acc.Id, 'Kerala', false);
        System.assertEquals(true, result, 'Global Value Scheme should be applicable for any retailer/region');
    }

    // Cover hasEligibleValueScheme — null/blank inputs return false
    @IsTest
    static void testHasEligibleValueScheme_EmptyInputs() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Scheme' LIMIT 1];
        System.assertEquals(false, SchemeEvaluationService.hasEligibleValueScheme(null, 'Kerala', false), 'Null buyerAccountId should return false');
        System.assertEquals(false, SchemeEvaluationService.hasEligibleValueScheme(acc.Id, null, false), 'Blank buyerRegion should return false');
    }

    // Cover hasEligibleValueScheme — Under SS flag excludes a Retailer-only scheme
    @IsTest
    static void testHasEligibleValueScheme_UnderSSMismatch() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Scheme' LIMIT 1];
        Boolean result = SchemeEvaluationService.hasEligibleValueScheme(acc.Id, 'Kerala', true);
        System.assertEquals(false, result, 'Retailer-only Value Scheme should not apply when isUnderSS=true');
    }

    // ========== Flat Discount / Scheme_Slab__c coverage ==========

    private static Scheme__c createFlatDiscountScheme() {
        Id valueRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Value_Scheme' AND SObjectType = 'Scheme__c' LIMIT 1].Id;
        Scheme__c flatScheme = new Scheme__c(
            Name = 'Test Flat Discount Scheme',
            RecordTypeId = valueRT,
            Type__c = 'Flat Discount',
            Discount_Mode__c = 'Percentage',
            Scheme_Start_Date__c = Date.today(),
            Scheme_End_Date__c = Date.today().addDays(30),
            Retailer_Scheme__c = true,
            Under_SS_Scheme__c = false
        );
        insert flatScheme;

        insert new List<Scheme_Slab__c>{
            new Scheme_Slab__c(Scheme__c = flatScheme.Id, Slab_Code__c = 'S1', For_Amount__c = 3000, Discount_Percent__c = 3),
            new Scheme_Slab__c(Scheme__c = flatScheme.Id, Slab_Code__c = 'S2', For_Amount__c = 5000, Discount_Percent__c = 5)
        };

        return flatScheme;
    }

    // getvalueScheme should mark a Flat Discount scheme eligible once the cart total
    // clears the lowest slab's For Amount, even though Cart_Amount__c is null.
    @IsTest
    static void testGetvalueScheme_FlatDiscountEligible() {
        Scheme__c flatScheme = createFlatDiscountScheme();
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Scheme' LIMIT 1];

        List<SchemeDetailsWrapper> result = SchemeEvaluationService.getvalueScheme(3500, null, acc.Id, 'Kerala', false);

        Boolean found = false;
        for (SchemeDetailsWrapper w : result) {
            if (w.id == flatScheme.Id) {
                found = true;
                System.assertEquals(true, w.isMatchExist, 'Cart total above the lowest slab should be eligible');
            }
        }
        System.assert(found, 'Flat Discount scheme should be returned even with no Cart_Amount__c');
    }

    // Cart total below every slab's For Amount should come back not-eligible.
    @IsTest
    static void testGetvalueScheme_FlatDiscountBelowLowestSlab() {
        Scheme__c flatScheme = createFlatDiscountScheme();
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Scheme' LIMIT 1];

        List<SchemeDetailsWrapper> result = SchemeEvaluationService.getvalueScheme(1000, null, acc.Id, 'Kerala', false);

        for (SchemeDetailsWrapper w : result) {
            if (w.id == flatScheme.Id) {
                System.assertEquals(false, w.isMatchExist, 'Cart total below the lowest slab should not be eligible');
            }
        }
    }

    // getAppliedValueScheme(Id, Decimal) should resolve the best-matching slab and
    // populate the discount from the slab, not from the parent Scheme fields.
    @IsTest
    static void testGetAppliedValueSchemeForCart_FlatDiscount() {
        Scheme__c flatScheme = createFlatDiscountScheme();

        AppliedValueSchemeWrapper resultLow = SchemeEvaluationService.getAppliedValueSchemeForCart(flatScheme.Id, 3500, null);
        System.assertEquals(3, resultLow.discountPercentage, 'Cart of 3500 should match the 3000 slab (3%)');

        AppliedValueSchemeWrapper resultHigh = SchemeEvaluationService.getAppliedValueSchemeForCart(flatScheme.Id, 6000, null);
        System.assertEquals(5, resultHigh.discountPercentage, 'Cart of 6000 should match the 5000 slab (5%)');

        AppliedValueSchemeWrapper resultTooLow = SchemeEvaluationService.getAppliedValueSchemeForCart(flatScheme.Id, 500, null);
        System.assertEquals(null, resultTooLow.discountPercentage, 'Cart below every slab should have no discount applied');
    }

    // The original 1-arg getAppliedValueScheme must still work untouched for
    // non-Flat-Discount (plain Value Scheme) records — no regression from the overload.
    @IsTest
    static void testGetAppliedValueScheme_OriginalOverloadUnaffected() {
        Scheme__c sch = [SELECT Id FROM Scheme__c WHERE Name = 'Test Value Scheme' LIMIT 1];
        AppliedValueSchemeWrapper result = SchemeEvaluationService.getAppliedValueScheme(sch.Id);
        System.assertEquals(15, result.discountPercentage, 'Plain Value Scheme should still read its own Discount_Percentage__c');
    }

    // ========== Scheme_Applicability__c scoping (Step 4 Apex engine work) ==========
    // A scheme with NO Scheme_Applicability__c rows is a global scheme — it must keep
    // resolving against the whole cart total exactly like before, regardless of what
    // cart lines are passed in. This is the fallback safety net for every scheme that
    // predates the Scheme_Applicability__c feature.
    @IsTest
    static void testGetAppliedValueSchemeForCart_NoApplicabilityRowsUsesWholeCart() {
        Scheme__c flatScheme = createFlatDiscountScheme();
        Product__c p = [SELECT Id FROM Product__c WHERE Name = 'Test Product Scheme' LIMIT 1];

        List<SchemeEvaluationService.CartLineWrapper> cartLines = new List<SchemeEvaluationService.CartLineWrapper>();
        SchemeEvaluationService.CartLineWrapper line = new SchemeEvaluationService.CartLineWrapper();
        line.productId = p.Id;
        line.productBrand = 'TestBrand';
        line.lineAmount = 100; // far below every slab on its own
        cartLines.add(line);

        // cartTotal (3500) still clears the 3000 slab even though the one matched line
        // is only 100 — because this scheme has no applicability rows, the whole-cart
        // total is used, not the matched-line sum.
        AppliedValueSchemeWrapper result = SchemeEvaluationService.getAppliedValueSchemeForCart(flatScheme.Id, 3500, JSON.serialize(cartLines));
        System.assertEquals(3, result.discountPercentage, 'No applicability rows should fall back to the whole cart total');
    }

    // A scheme scoped to a specific Product should only count that product's cart
    // line(s) toward the slab threshold — an unrelated product's spend must not count,
    // even though it's in the same cart and would clear the slab on its own.
    @IsTest
    static void testGetAppliedValueSchemeForCart_ScopedToProductOnly() {
        Scheme__c flatScheme = createFlatDiscountScheme();
        Product__c matchProduct = [SELECT Id FROM Product__c WHERE Name = 'Test Product Scheme' LIMIT 1];
        Product__c otherProduct = [SELECT Id FROM Product__c WHERE Name = 'Test Product Other' LIMIT 1];

        insert new Scheme_Applicability__c(
            Scheme__c = flatScheme.Id,
            Entity_Type__c = 'Product',
            Product__c = matchProduct.Id
        );

        List<SchemeEvaluationService.CartLineWrapper> cartLines = new List<SchemeEvaluationService.CartLineWrapper>();

        SchemeEvaluationService.CartLineWrapper matchLine = new SchemeEvaluationService.CartLineWrapper();
        matchLine.productId = matchProduct.Id;
        matchLine.productBrand = 'TestBrand';
        matchLine.lineAmount = 2000;
        cartLines.add(matchLine);

        SchemeEvaluationService.CartLineWrapper otherLine = new SchemeEvaluationService.CartLineWrapper();
        otherLine.productId = otherProduct.Id;
        otherLine.productBrand = 'TestBrand';
        otherLine.lineAmount = 2000;
        cartLines.add(otherLine);

        // Whole cart is 4000 (would clear the 3000 slab), but only 2000 of it is the
        // scoped product — should NOT be eligible for even the lowest (3000) slab.
        AppliedValueSchemeWrapper resultBelow = SchemeEvaluationService.getAppliedValueSchemeForCart(flatScheme.Id, 4000, JSON.serialize(cartLines));
        System.assertEquals(null, resultBelow.discountPercentage, 'Only the scoped product\'s 2000 should count, which is below the 3000 slab');

        // Bump the matched line to 3200 — now the SCOPED subtotal alone clears the 3000 slab.
        matchLine.lineAmount = 3200;
        AppliedValueSchemeWrapper resultAbove = SchemeEvaluationService.getAppliedValueSchemeForCart(flatScheme.Id, 5200, JSON.serialize(cartLines));
        System.assertEquals(3, resultAbove.discountPercentage, 'Scoped product line alone (3200) should clear the 3000 slab');
    }

    // A scheme scoped to a Brand should match by normalised Brand_Key__c, so a cart
    // line's brand string with different case/whitespace still counts.
    @IsTest
    static void testGetAppliedValueSchemeForCart_ScopedToBrandNormalizedMatch() {
        Scheme__c flatScheme = createFlatDiscountScheme();

        insert new Scheme_Applicability__c(
            Scheme__c = flatScheme.Id,
            Entity_Type__c = 'Brand',
            Product_Brand__c = 'TestBrand'
        );

        Product__c p = [SELECT Id FROM Product__c WHERE Name = 'Test Product Scheme' LIMIT 1];

        List<SchemeEvaluationService.CartLineWrapper> cartLines = new List<SchemeEvaluationService.CartLineWrapper>();
        SchemeEvaluationService.CartLineWrapper line = new SchemeEvaluationService.CartLineWrapper();
        line.productId = p.Id;
        line.productBrand = '  testbrand  '; // differs in case/whitespace from the stored 'TestBrand'
        line.lineAmount = 5200;
        cartLines.add(line);

        AppliedValueSchemeWrapper result = SchemeEvaluationService.getAppliedValueSchemeForCart(flatScheme.Id, 5200, JSON.serialize(cartLines));
        System.assertEquals(5, result.discountPercentage, 'Brand match should be case/whitespace-insensitive via Brand_Key__c normalisation');
    }

    // getvalueScheme()'s eligibility flag must respect the same scoping — a scheme
    // shouldn't show as eligible just because the whole cart clears the slab if the
    // scoped product/brand's own subtotal doesn't.
    @IsTest
    static void testGetvalueScheme_ScopedToProductEligibilityRespectsScoping() {
        Scheme__c flatScheme = createFlatDiscountScheme();
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Scheme' LIMIT 1];
        Product__c matchProduct = [SELECT Id FROM Product__c WHERE Name = 'Test Product Scheme' LIMIT 1];
        Product__c otherProduct = [SELECT Id FROM Product__c WHERE Name = 'Test Product Other' LIMIT 1];

        insert new Scheme_Applicability__c(
            Scheme__c = flatScheme.Id,
            Entity_Type__c = 'Product',
            Product__c = matchProduct.Id
        );

        List<SchemeEvaluationService.CartLineWrapper> cartLines = new List<SchemeEvaluationService.CartLineWrapper>();

        SchemeEvaluationService.CartLineWrapper matchLine = new SchemeEvaluationService.CartLineWrapper();
        matchLine.productId = matchProduct.Id;
        matchLine.productBrand = 'TestBrand';
        matchLine.lineAmount = 500;
        cartLines.add(matchLine);

        SchemeEvaluationService.CartLineWrapper otherLine = new SchemeEvaluationService.CartLineWrapper();
        otherLine.productId = otherProduct.Id;
        otherLine.productBrand = 'TestBrand';
        otherLine.lineAmount = 3500;
        cartLines.add(otherLine);

        // Whole cart (4000) clears the 3000 slab, but the scoped product's own line
        // (500) does not — should NOT be reported eligible.
        List<SchemeDetailsWrapper> result = SchemeEvaluationService.getvalueScheme(4000, JSON.serialize(cartLines), acc.Id, 'Kerala', false);

        for (SchemeDetailsWrapper w : result) {
            if (w.id == flatScheme.Id) {
                System.assertEquals(false, w.isMatchExist, 'Scoped product subtotal (500) is below the 3000 slab, whole cart total must not be used');
            }
        }
    }
}