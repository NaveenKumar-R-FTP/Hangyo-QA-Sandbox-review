@isTest
private class ProductRestrictionServiceTest {

    @testSetup
    static void setupData() {
        // Pre-seed so GenerateRetailerCreationCode's trigger logic never hits its
        // null-latestCode edge case on the bare Account inserts below (none of these
        // accounts use the Retailer record type on purpose, but a fresh org default
        // can still route them there).
        if (RetailerCodeSetting__c.getInstance('SF') == null) {
            insert new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 1000);
        }
    }

    @isTest
    static void testNoRestrictionsReturnsEmptySet() {
        Account distributor = new Account(Name = 'Test Distributor No Restrictions', Hub__c = 'Bangalore');
        insert distributor;

        Set<Id> denied = ProductRestrictionService.getDeniedProductIds(distributor.Id);
        System.assert(denied.isEmpty(), 'A Hub with no Product_Restriction__c records should have no denied products.');
        System.assertEquals(new Set<Id>(), ProductRestrictionService.getDeniedProductIds(null));
    }

    @isTest
    static void testAccountWithNoHubReturnsEmptySet() {
        Account distributor = new Account(Name = 'Test Distributor No Hub');
        insert distributor;

        Set<Id> denied = ProductRestrictionService.getDeniedProductIds(distributor.Id);
        System.assert(denied.isEmpty(), 'An Account with no Hub__c value should never be restricted.');
    }

    @isTest
    static void testRestrictedProductIsDeniedForEveryDistributorInThatHubOnly() {
        Id productRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Product__c' AND DeveloperName = 'Product' LIMIT 1].Id;

        // Two distributors sharing the same Hub ("Bangalore") — both should be denied.
        Account restrictedDistributor1 = new Account(Name = 'Test Distributor Bangalore 1', Hub__c = 'Bangalore');
        Account restrictedDistributor2 = new Account(Name = 'Test Distributor Bangalore 2', Hub__c = 'Bangalore');
        // A distributor in a different Hub — should NOT be affected.
        Account openDistributor = new Account(Name = 'Test Distributor Goa', Hub__c = 'Goa');
        insert new List<Account>{ restrictedDistributor1, restrictedDistributor2, openDistributor };

        Product__c restrictedProduct = new Product__c(
            Name = 'Test Restricted Product',
            RecordTypeId = productRT,
            IsActive__c = true,
            Secondary_Product__c = true,
            MRP__c = 100,
            Image_Long__c = 'https://example.com/img.png',
            Unit_of_Measure__c = 'EA',
            Product_Brand__c = 'Test Brand',
            Category_Code__c = 'RESTRICTED',
            Category_Name__c = 'Test Category',
            Product_Code__c = 'RESTRICTED-1'
        );
        Product__c openProduct = new Product__c(
            Name = 'Test Open Product',
            RecordTypeId = productRT,
            IsActive__c = true,
            Secondary_Product__c = true,
            MRP__c = 50,
            Image_Long__c = 'https://example.com/img.png',
            Unit_of_Measure__c = 'EA',
            Product_Brand__c = 'Test Brand',
            Category_Code__c = 'OPEN',
            Category_Name__c = 'Test Category',
            Product_Code__c = 'OPEN-1'
        );
        insert new List<Product__c>{ restrictedProduct, openProduct };

        insert new Product_Restriction__c(
            Hub__c = 'Bangalore',
            Product__c = restrictedProduct.Id
        );

        Set<Id> deniedForDistributor1 = ProductRestrictionService.getDeniedProductIds(restrictedDistributor1.Id);
        System.assertEquals(1, deniedForDistributor1.size());
        System.assert(deniedForDistributor1.contains(restrictedProduct.Id));

        Set<Id> deniedForDistributor2 = ProductRestrictionService.getDeniedProductIds(restrictedDistributor2.Id);
        System.assertEquals(1, deniedForDistributor2.size());
        System.assert(deniedForDistributor2.contains(restrictedProduct.Id), 'Both distributors sharing the same Hub should be denied, not just the one directly referenced.');

        Set<Id> deniedForOpen = ProductRestrictionService.getDeniedProductIds(openDistributor.Id);
        System.assert(deniedForOpen.isEmpty(), 'A distributor in a different Hub should not be affected.');

        List<Product__c> filtered = ProductRestrictionService.filterOutDeniedProducts(
            new List<Product__c>{ restrictedProduct, openProduct },
            restrictedDistributor1.Id
        );
        System.assertEquals(1, filtered.size());
        System.assertEquals(openProduct.Id, filtered[0].Id);
    }
}