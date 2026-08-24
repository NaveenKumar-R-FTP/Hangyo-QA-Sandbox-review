@isTest
private class SchemeSlabTriggerHandlerTest {

    private static Scheme__c createScheme(String mode) {
        Scheme__c s = new Scheme__c(
            Name = 'Test Flat Discount',
            Type__c = 'Flat Discount',
            Discount_Mode__c = mode,
            Scheme_Start_Date__c = Date.today(),
            Scheme_End_Date__c = Date.today().addMonths(1),
            Retailer_Scheme__c = true
        );
        insert s;
        return s;
    }

    @isTest
    static void testValidSlabsSucceed() {
        Scheme__c scheme = createScheme('Percentage');

        List<Scheme_Slab__c> slabs = new List<Scheme_Slab__c>{
            new Scheme_Slab__c(Scheme__c = scheme.Id, Slab_Code__c = 'S1', For_Amount__c = 3000, Discount_Percent__c = 3),
            new Scheme_Slab__c(Scheme__c = scheme.Id, Slab_Code__c = 'S2', For_Amount__c = 5000, Discount_Percent__c = 5)
        };

        Test.startTest();
        insert slabs;
        Test.stopTest();

        List<Scheme_Slab__c> result = [SELECT Id FROM Scheme_Slab__c WHERE Scheme__c = :scheme.Id];
        System.assertEquals(2, result.size());
    }

    @isTest
    static void testDuplicateForAmountBlocked() {
        Scheme__c scheme = createScheme('Percentage');
        insert new Scheme_Slab__c(Scheme__c = scheme.Id, Slab_Code__c = 'S1', For_Amount__c = 3000, Discount_Percent__c = 3);

        Test.startTest();
        Boolean errorThrown = false;
        try {
            insert new Scheme_Slab__c(Scheme__c = scheme.Id, Slab_Code__c = 'S2', For_Amount__c = 3000, Discount_Percent__c = 4);
        } catch (DmlException e) {
            errorThrown = true;
            System.assert(e.getMessage().contains('For Amount'));
        }
        Test.stopTest();

        System.assert(errorThrown, 'Expected duplicate For Amount to be blocked');
    }

    @isTest
    static void testDescendingDiscountBlocked() {
        Scheme__c scheme = createScheme('Percentage');
        insert new Scheme_Slab__c(Scheme__c = scheme.Id, Slab_Code__c = 'S1', For_Amount__c = 3000, Discount_Percent__c = 5);

        Test.startTest();
        Boolean errorThrown = false;
        try {
            insert new Scheme_Slab__c(Scheme__c = scheme.Id, Slab_Code__c = 'S2', For_Amount__c = 5000, Discount_Percent__c = 3);
        } catch (DmlException e) {
            errorThrown = true;
        }
        Test.stopTest();

        System.assert(errorThrown, 'Expected lower discount on higher slab to be blocked');
    }

    @isTest
    static void testModeMismatchBlocked() {
        Scheme__c scheme = createScheme('Percentage');

        Test.startTest();
        Boolean errorThrown = false;
        try {
            insert new Scheme_Slab__c(Scheme__c = scheme.Id, Slab_Code__c = 'S1', For_Amount__c = 3000, Cash_Discount__c = 100);
        } catch (DmlException e) {
            errorThrown = true;
        }
        Test.stopTest();

        System.assert(errorThrown, 'Expected Cash Discount on a Percentage-mode scheme to be blocked');
    }
}