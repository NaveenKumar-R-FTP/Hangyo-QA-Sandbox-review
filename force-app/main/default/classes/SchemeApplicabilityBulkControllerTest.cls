@isTest
private class SchemeApplicabilityBulkControllerTest {

    private static Scheme__c createScheme() {
        Id valueRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Value_Scheme' AND SObjectType = 'Scheme__c' LIMIT 1].Id;
        Scheme__c s = new Scheme__c(
            Name = 'Test Bulk Applicability Scheme',
            RecordTypeId = valueRT,
            Type__c = 'Flat Discount',
            Discount_Mode__c = 'Percentage',
            Scheme_Start_Date__c = Date.today(),
            Scheme_End_Date__c = Date.today().addMonths(1),
            Retailer_Scheme__c = true
        );
        insert s;
        return s;
    }

    private static Product__c createProduct(String name, String brand) {
        Id productRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Product' AND SObjectType = 'Product__c' LIMIT 1].Id;
        Product__c p = new Product__c(
            Name = name,
            IsActive__c = true,
            Secondary_Product__c = true,
            RecordTypeId = productRT,
            Rate_Value__c = 100,
            Unit_of_Measure__c = 'kg',
            Product_Brand__c = brand,
            MRP__c = 100,
            HSN__c = '1234'
        );
        insert p;
        return p;
    }

    @isTest
    static void testSearchProductsReturnsMatches() {
        createProduct('Amul Butter 500g', 'Amul');
        createProduct('Amul Milk 1L', 'Amul');
        createProduct('Britannia Bread', 'Britannia');

        Test.startTest();
        List<SchemeApplicabilityBulkController.ProductOption> results = SchemeApplicabilityBulkController.searchProducts('Amul');
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Should only match products with Amul in the name');
    }

    @isTest
    static void testSearchBrandsReturnsDistinctMatches() {
        createProduct('Amul Butter 500g', 'Amul');
        createProduct('Amul Milk 1L', 'Amul');
        createProduct('Amul Cheese', 'Amul');
        createProduct('Britannia Bread', 'Britannia');

        Test.startTest();
        List<String> results = SchemeApplicabilityBulkController.searchBrands('Amul');
        Test.stopTest();

        System.assertEquals(1, results.size(), 'GROUP BY should collapse 3 Amul products into 1 distinct brand');
        System.assertEquals('Amul', results[0]);
    }

    @isTest
    static void testCreateProductRowsBulkSuccess() {
        Scheme__c scheme = createScheme();
        Product__c p1 = createProduct('Test Product X', 'Amul');
        Product__c p2 = createProduct('Test Product Y', 'Amul');

        Test.startTest();
        String result = SchemeApplicabilityBulkController.createProductRows(scheme.Id, new List<Id>{ p1.Id, p2.Id });
        Test.stopTest();

        System.assertEquals(null, result, 'No errors expected on a clean bulk insert');
        List<Scheme_Applicability__c> rows = [SELECT Id, Product__c FROM Scheme_Applicability__c WHERE Scheme__c = :scheme.Id];
        System.assertEquals(2, rows.size());
    }

    @isTest
    static void testCreateProductRowsPartialFailureReported() {
        Scheme__c scheme = createScheme();
        Product__c p1 = createProduct('Test Product Z', 'Amul');

        insert new Scheme_Applicability__c(
            Scheme__c = scheme.Id,
            Entity_Type__c = 'Product',
            Product__c = p1.Id
        );

        Test.startTest();
        // p1 is already linked to this scheme, so this attempt should be reported
        // as a failure by the trigger's duplicate check, not silently dropped or thrown.
        String result = SchemeApplicabilityBulkController.createProductRows(scheme.Id, new List<Id>{ p1.Id });
        Test.stopTest();

        System.assert(result != null, 'A duplicate row should be reported as an error');
        System.assert(result.contains('already listed'));
    }

    @isTest
    static void testCreateProductRowsNoIdsReturnsMessage() {
        Scheme__c scheme = createScheme();

        Test.startTest();
        String result = SchemeApplicabilityBulkController.createProductRows(scheme.Id, new List<Id>());
        Test.stopTest();

        System.assertEquals('Select at least one product.', result);
    }

    @isTest
    static void testCreateBrandRowsBulkSuccess() {
        Scheme__c scheme = createScheme();

        Test.startTest();
        String result = SchemeApplicabilityBulkController.createBrandRows(scheme.Id, new List<String>{ 'Nestle', 'Britannia' });
        Test.stopTest();

        System.assertEquals(null, result);
        List<Scheme_Applicability__c> rows = [SELECT Id, Brand_Key__c FROM Scheme_Applicability__c WHERE Scheme__c = :scheme.Id ORDER BY Brand_Key__c ASC];
        System.assertEquals(2, rows.size());
        System.assertEquals('BRITANNIA', rows[0].Brand_Key__c);
        System.assertEquals('NESTLE', rows[1].Brand_Key__c);
    }

    @isTest
    static void testCreateBrandRowsPartialFailureReported() {
        Scheme__c scheme = createScheme();

        insert new Scheme_Applicability__c(
            Scheme__c = scheme.Id,
            Entity_Type__c = 'Brand',
            Product_Brand__c = 'Nestle'
        );

        Test.startTest();
        // 'Nestle' duplicates the existing row (case-insensitive via Brand_Key__c),
        // 'Dabur' is new — expect a partial success with the duplicate reported.
        String result = SchemeApplicabilityBulkController.createBrandRows(scheme.Id, new List<String>{ 'nestle', 'Dabur' });
        Test.stopTest();

        System.assert(result != null, 'The duplicate brand should be reported as an error');
        System.assert(result.contains('already listed'));
        List<Scheme_Applicability__c> rows = [SELECT Id FROM Scheme_Applicability__c WHERE Scheme__c = :scheme.Id];
        System.assertEquals(2, rows.size(), 'Original Nestle row plus the new Dabur row should exist; the duplicate nestle attempt should not');
    }

    @isTest
    static void testCreateBrandRowsNoBrandsReturnsMessage() {
        Scheme__c scheme = createScheme();

        Test.startTest();
        String result = SchemeApplicabilityBulkController.createBrandRows(scheme.Id, new List<String>());
        Test.stopTest();

        System.assertEquals('Select at least one brand.', result);
    }
}