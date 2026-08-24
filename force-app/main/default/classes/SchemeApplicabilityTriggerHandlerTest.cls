@isTest
private class SchemeApplicabilityTriggerHandlerTest {

    private static Scheme__c createScheme() {
        Id valueRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Value_Scheme' AND SObjectType = 'Scheme__c' LIMIT 1].Id;
        Scheme__c s = new Scheme__c(
            Name = 'Test Applicability Scheme',
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
    static void testValidProductRowSucceeds() {
        Scheme__c scheme = createScheme();
        Product__c product = createProduct('Test Product A', 'Amul');

        insert new Scheme_Applicability__c(
            Scheme__c = scheme.Id,
            Entity_Type__c = 'Product',
            Product__c = product.Id
        );

        List<Scheme_Applicability__c> result = [SELECT Id FROM Scheme_Applicability__c WHERE Scheme__c = :scheme.Id];
        System.assertEquals(1, result.size());
    }

    @isTest
    static void testValidBrandRowSucceedsAndNormalizesKey() {
        Scheme__c scheme = createScheme();

        Scheme_Applicability__c row = new Scheme_Applicability__c(
            Scheme__c = scheme.Id,
            Entity_Type__c = 'Brand',
            Product_Brand__c = '  Amul  '
        );
        insert row;

        Scheme_Applicability__c result = [SELECT Brand_Key__c FROM Scheme_Applicability__c WHERE Id = :row.Id];
        System.assertEquals('AMUL', result.Brand_Key__c, 'Brand_Key__c should be trimmed and upper-cased');
    }

    @isTest
    static void testProductRowWithoutProductBlocked() {
        Scheme__c scheme = createScheme();

        Boolean errorThrown = false;
        try {
            insert new Scheme_Applicability__c(
                Scheme__c = scheme.Id,
                Entity_Type__c = 'Product'
            );
        } catch (DmlException e) {
            errorThrown = true;
        }
        System.assert(errorThrown, 'Entity Type Product with no Product should be blocked');
    }

    @isTest
    static void testBrandRowWithoutBrandBlocked() {
        Scheme__c scheme = createScheme();

        Boolean errorThrown = false;
        try {
            insert new Scheme_Applicability__c(
                Scheme__c = scheme.Id,
                Entity_Type__c = 'Brand'
            );
        } catch (DmlException e) {
            errorThrown = true;
        }
        System.assert(errorThrown, 'Entity Type Brand with no Product Brand should be blocked');
    }

    @isTest
    static void testProductRowWithBothProductAndBrandBlocked() {
        Scheme__c scheme = createScheme();
        Product__c product = createProduct('Test Product B', 'Amul');

        Boolean errorThrown = false;
        try {
            insert new Scheme_Applicability__c(
                Scheme__c = scheme.Id,
                Entity_Type__c = 'Product',
                Product__c = product.Id,
                Product_Brand__c = 'Amul'
            );
        } catch (DmlException e) {
            errorThrown = true;
        }
        System.assert(errorThrown, 'Entity Type Product should not also allow Product Brand to be set');
    }

    @isTest
    static void testDuplicateProductBlocked() {
        Scheme__c scheme = createScheme();
        Product__c product = createProduct('Test Product C', 'Amul');

        insert new Scheme_Applicability__c(
            Scheme__c = scheme.Id,
            Entity_Type__c = 'Product',
            Product__c = product.Id
        );

        Boolean errorThrown = false;
        try {
            insert new Scheme_Applicability__c(
                Scheme__c = scheme.Id,
                Entity_Type__c = 'Product',
                Product__c = product.Id
            );
        } catch (DmlException e) {
            errorThrown = true;
            System.assert(e.getMessage().contains('already listed'));
        }
        System.assert(errorThrown, 'Duplicate Product on the same scheme should be blocked');
    }

    @isTest
    static void testDuplicateBrandBlockedCaseAndWhitespaceInsensitive() {
        Scheme__c scheme = createScheme();

        insert new Scheme_Applicability__c(
            Scheme__c = scheme.Id,
            Entity_Type__c = 'Brand',
            Product_Brand__c = 'AMUL'
        );

        Boolean errorThrown = false;
        try {
            insert new Scheme_Applicability__c(
                Scheme__c = scheme.Id,
                Entity_Type__c = 'Brand',
                Product_Brand__c = '  amul '
            );
        } catch (DmlException e) {
            errorThrown = true;
            System.assert(e.getMessage().contains('already listed'));
        }
        System.assert(errorThrown, 'Duplicate brand (differing only in case/whitespace) should be blocked');
    }
}