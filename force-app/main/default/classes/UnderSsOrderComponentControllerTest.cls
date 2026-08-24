@IsTest(SeeAllData = true)
private class UnderSsOrderComponentControllerTest {

    private static final String UNDER_SS_DIST_TYPE = 'Under Super Stockist';

    private static Id ssAccountId;
    private static Id underSsAccountId;
    private static Id productId;
    private static List<Id> retailerIds;
    private static User ssRunAsUser;
    private static User underSsPortalUser;
    private static String alignedState;
    private static Boolean dataReady = false;

    private static void ensureTestData() {
        if (dataReady) {
            return;
        }

        configureTestBypass();
        insertTaxCustomSetting();

        if (!bootstrapAccountsAndUsersFromOrg()) {
            System.assert(
                false,
                'Test setup failed: QA org needs (1) Under SS account with active portal user and Super_Stockist_Name__c, ' +
                '(2) active portal user on that Super Stockist account.'
            );
        }

        retailerIds = new List<Id>{ underSsAccountId };
        ensureProductPricebookAndInventory();

        dataReady = true;
    }

    // ─── Tests ─────────────────────────────────────────────────────────────────

    @IsTest
    static void fetchProducts_returnsProducts_whenDataValid() {
        ensureTestData();
        System.runAs(ssRunAsUser) {
            Test.startTest();
            String jsonResult = UnderSsOrderComponentController.fetchProducts(
                null, null, retailerIds, null, null
            );
            Test.stopTest();

            List<Object> rows = (List<Object>) JSON.deserializeUntyped(jsonResult);
            System.assert(!rows.isEmpty(), 'Expected products for SS user + aligned pricebook');
        }
    }

    @IsTest
    static void fetchProducts_searchByCode_and_availableStock() {
        ensureTestData();
        System.runAs(ssRunAsUser) {
            Test.startTest();
            UnderSsOrderComponentController.fetchProducts(
                'CAT', null, retailerIds, null, 'Code'
            );
            UnderSsOrderComponentController.fetchProducts(
                null, 'Available Stock', retailerIds, 'Available Stock', 'Name'
            );
            Test.stopTest();
        }
    }

    @IsTest
    static void fetchProducts_emptyWhenNoDistributorAccount() {
        ensureTestData();
        User noAccUser = createStandardUserWithoutAccount();
        System.runAs(noAccUser) {
            String jsonResult = UnderSsOrderComponentController.fetchProducts(
                'x', null, retailerIds, null, 'Name'
            );
            System.assertEquals(
                0,
                ((List<Object>) JSON.deserializeUntyped(jsonResult)).size()
            );
        }
    }

    @IsTest
    static void fetchFocusedProducts_excludesIds() {
        ensureTestData();
        System.runAs(ssRunAsUser) {
            Test.startTest();
            String withoutExclude = UnderSsOrderComponentController.fetchFocusedProducts(
                null, null, new List<String>(), retailerIds, null, 'Name'
            );
            String withExclude = UnderSsOrderComponentController.fetchFocusedProducts(
                null,
                null,
                new List<String>{ String.valueOf(productId) },
                retailerIds,
                null,
                'Name'
            );
            Test.stopTest();
            List<Object> included = (List<Object>) JSON.deserializeUntyped(withoutExclude);
            List<Object> excluded = (List<Object>) JSON.deserializeUntyped(withExclude);
            System.assert(!included.isEmpty(), 'Need focused products in result set');
            Integer excludedMatchCount = 0;
            for (Object rowObj : excluded) {
                Map<String, Object> row = (Map<String, Object>) rowObj;
                if (String.valueOf(row.get('productId')) == String.valueOf(productId)) {
                    excludedMatchCount++;
                }
            }
            System.assertEquals(
                0,
                excludedMatchCount,
                'Excluded productId must not appear when passed in excludedProductIds'
            );
        }
    }

    @IsTest
    static void getTaxRates_sameState_returnsCgstSgst() {
        ensureTestData();
        Map<String, Decimal> rates =
            UnderSsOrderComponentController.getTaxRates(alignedState, alignedState);
        System.assert(rates.containsKey('CGST'));
        System.assert(rates.containsKey('SGST'));
    }

    @IsTest
    static void getTaxRates_differentState_returnsIgst() {
        ensureTestData();
        String otherState = getAlternateState(alignedState);
        Map<String, Decimal> rates =
            UnderSsOrderComponentController.getTaxRates(alignedState, otherState);
        System.assert(rates.containsKey('IGST'));
    }

    @IsTest
    static void generateProposal_createsBothOrders() {
        ensureTestData();
        System.runAs(ssRunAsUser) {
            Test.startTest();
            UnderSsOrderComponentController.OrderResponse resp =
                UnderSsOrderComponentController.generateProposal(
                    buildCartJson(productId, false),
                    retailerIds,
                    buildOrderSummaryJson(false),
                    'Test order comment'
                );
            Test.stopTest();
            System.assertEquals('Success', resp.status);
            System.assertNotEquals(null, resp.underSsOrdId);
            System.assertNotEquals(null, resp.ordid);
        }
    }
    
    @IsTest
    static void generateProposal_failsWhenUnderSsNotTaggedToSs() {
        ensureTestData();

        Account rogue = new Account(
            Name = 'Rogue Under SS ' + uniqueSuffix(),
            Primary_State__c = alignedState,
            Distributor_Type__c = UNDER_SS_DIST_TYPE,
            Phone = '9999999999',
            BillingStreet = 'Test Street',
            BillingCity = 'Test City',
            BillingState = alignedState,
            BillingPostalCode = '560001',
            BillingCountry = 'India'
        );
        insert rogue;

        System.runAs(ssRunAsUser) {
            Boolean threw = false;
            try {
                UnderSsOrderComponentController.generateProposal(
                    buildCartJson(productId, false),
                    new List<Id>{ rogue.Id },
                    buildOrderSummaryJson(false),
                    'x'
                );
            } catch (AuraHandledException e) {
                threw = true;
            }
            System.assert(threw);
        }
    }

    @IsTest
    static void createUnderSsOrder_and_createSsSecondaryOrder_direct() {
        ensureTestData();
        System.runAs(ssRunAsUser) {
            UnderSsOrderComponentController.UnderSsOrderResult first =
                UnderSsOrderComponentController.createUnderSsOrder(
                    buildCartJson(productId, true),
                    retailerIds,
                    buildOrderSummaryJson(false),
                    'direct path'
                );
            System.assertNotEquals(null, first.underSsOrderId);
            Id secId =
                UnderSsOrderComponentController.createSsSecondaryOrder(first);
            System.assertNotEquals(null, secId);
        }
    }

    // ─── Org bootstrap (NO user insert with Contact on Standard profile) ───────

    private static Boolean bootstrapAccountsAndUsersFromOrg() {
        List<User> underSsUsers = [
            SELECT
                Id,
                Contact.AccountId,
                Contact.Account.Primary_State__c,
                Contact.Account.Super_Stockist_Name__c,
                Contact.Account.Distributor_Type__c
            FROM User
            WHERE
                IsActive = TRUE
                AND ContactId != NULL
                AND UserType IN :portalUserTypes()
                AND Contact.Account.Distributor_Type__c = :UNDER_SS_DIST_TYPE
                AND Contact.Account.Super_Stockist_Name__c != NULL
            LIMIT 1
        ];
        if (underSsUsers.isEmpty()) {
            return false;
        }

        underSsPortalUser = underSsUsers[0];
        underSsAccountId = underSsUsers[0].Contact.AccountId;
        ssAccountId = underSsUsers[0].Contact.Account.Super_Stockist_Name__c;
        alignedState = underSsUsers[0].Contact.Account.Primary_State__c;

        if (underSsAccountId == null || ssAccountId == null) {
            return false;
        }

        ssRunAsUser = findPortalUserOnAccount(ssAccountId);
        if (ssRunAsUser == null) {
            ssRunAsUser = findInternalUserOnAccount(ssAccountId);
        }
        if (ssRunAsUser == null) {
            return false;
        }

        if (String.isBlank(alignedState)) {
            alignedState = resolveAlignedStateFromPricebook();
        }

        syncAccountStateForPricebook(underSsAccountId, alignedState);
        syncAccountStateForPricebook(ssAccountId, alignedState);

        return true;
    }

    private static User findPortalUserOnAccount(Id accountId) {
        List<User> users = [
            SELECT Id
            FROM User
            WHERE
                IsActive = TRUE
                AND ContactId != NULL
                AND Contact.AccountId = :accountId
                AND UserType IN :portalUserTypes()
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
    }

    private static User findInternalUserOnAccount(Id accountId) {
        List<User> users = [
            SELECT Id
            FROM User
            WHERE IsActive = TRUE AND AccountId = :accountId
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
    }

    private static List<String> portalUserTypes() {
        return new List<String>{
            'PowerPartner',
            'CSPLitePortal',
            'CustomerSuccess',
            'CspLitePortal'
        };
    }

    // ─── Product / pricebook / inventory only ──────────────────────────────────

    private static void ensureProductPricebookAndInventory() {
        Id pricebookId = findOrCreatePricebookForState(alignedState);

        Product__c prod = new Product__c(
            Name = 'Under SS Prod ' + uniqueSuffix(),
            IsActive__c = true,
            Under_SS__c = true,
            Focus_Product__c = true,
            Image_Long__c = 'https://example.com/img1.png',
            Product_Brand__c = 'BrandA',
            Category_Code__c = 'CAT001',
            MRP__c = 100,
            Unit_of_Measure__c = 'EA',
            Crate_Conversion__c = 12
        );
        Id prodRtId = getRtId('Product__c', 'Product');
        if (prodRtId != null) {
            prod.RecordTypeId = prodRtId;
        }
        insert prod;
        productId = prod.Id;

        insert new Price_Book_Entry__c(
            Price_Book__c = pricebookId,
            Product__c = prod.Id,
            isActive__c = true,
            Type__c = resolvePbeType(),
            PTD__c = 50.25
        );

        insert new Inventory__c(
            Distributor_Name__c = ssAccountId,
            Product__c = prod.Id,
            Quantity_in_Hand__c = 25
        );
    }

    private static Id findOrCreatePricebookForState(String state) {
        List<Price_Book__c> existing = [
            SELECT Id
            FROM Price_Book__c
            WHERE isActive__c = TRUE AND Region__r.Name = :state
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }

        List<Price_Book__c> panIndia = [
            SELECT Id
            FROM Price_Book__c
            WHERE isActive__c = TRUE AND Region__c = NULL
            LIMIT 1
        ];
        if (!panIndia.isEmpty()) {
            return panIndia[0].Id;
        }

        Price_Book__c pb = new Price_Book__c(isActive__c = true);
        SObject region = createRegionIfExists(state);
        if (region != null) {
            pb.put('Region__c', region.get('Id'));
        }
        insert pb;
        return pb.Id;
    }

    private static String resolveAlignedStateFromPricebook() {
        for (Price_Book__c pb : [
            SELECT Region__r.Name
            FROM Price_Book__c
            WHERE isActive__c = TRUE AND Region__r.Name != NULL
            LIMIT 1
        ]) {
            return pb.Region__r.Name;
        }
        return 'Karnataka';
    }

    private static void syncAccountStateForPricebook(Id accountId, String state) {
        if (accountId == null || String.isBlank(state)) {
            return;
        }
        update new Account(Id = accountId, Primary_State__c = state);
    }

    private static String resolvePbeType() {
        Set<String> active = getActivePicklistValues('Price_Book_Entry__c', 'Type__c');
        if (active.contains('Direct Distributor')) {
            return 'Direct Distributor';
        }
        return active.isEmpty() ? 'Direct Distributor' : new List<String>(active)[0];
    }

    private static String getAlternateState(String currentState) {
        for (Price_Book__c pb : [
            SELECT Region__r.Name
            FROM Price_Book__c
            WHERE isActive__c = TRUE AND Region__r.Name != NULL
            LIMIT 10
        ]) {
            if (pb.Region__r.Name != currentState) {
                return pb.Region__r.Name;
            }
        }
        return currentState == 'Karnataka' ? 'Maharashtra' : 'Karnataka';
    }

    // ─── Helpers ───────────────────────────────────────────────────────────────

    private static User createStandardUserWithoutAccount() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = buildBaseUser(p.Id, 'noacc');
        insert u;
        return u;
    }

    private static User buildBaseUser(Id profileId, String keyPrefix) {
        String uniq = uniqueSuffix();
        return new User(
            FirstName = 'T',
            LastName = keyPrefix + uniq,
            Email = keyPrefix + uniq + '@hangyo.in',
            Username = keyPrefix + uniq + '@example.com.test',
            Alias = ('a' + uniq).left(8),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileId
        );
    }

    private static String buildCartJson(Id prodId, Boolean promotional) {
        CartProductWrapper.ProductWrapper w = new CartProductWrapper.ProductWrapper();
        w.productId = prodId;
        w.quantity = 2;
        w.productOfferPrice = 50.25;
        w.productListPrice = 50.25;
        w.isPromotional = promotional;
        w.selectedSchemeId = null;
        w.parentProductId = null;
        w.discountPercentage = promotional ? 10 : 0;
        return JSON.serialize(new List<CartProductWrapper.ProductWrapper>{ w });
    }

    private static String buildOrderSummaryJson(Boolean withScheme) {
        UnderSsOrderComponentController.OrderSummaryWrapper s =
            new UnderSsOrderComponentController.OrderSummaryWrapper();
        s.totalItems = 1;
        s.totalPrice = 100.50;
        s.totalDiscount = withScheme ? 5 : 0;
        s.totalOrderValue = 100.50;
        s.subTotal = 90;
        s.totalQuantity = 2;
        s.totalCGST = 4.5;
        s.totalSGST = 4.5;
        s.totalIGST = 0;
        s.totalDiscountRupees = withScheme ? 5 : 0;
        s.valueSchemeDiscount = withScheme ? 5 : 0;
        s.valuseSchemeIdOnOrder = withScheme ? 'TEST-SCHEME' : null;
        s.orderDate = String.valueOf(Date.today());
        return JSON.serialize(s);
    }

    private static String uniqueSuffix() {
        return String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }

    private static void configureTestBypass() {
        tryBypassHierarchySetting('Trigger_Settings__c', 'Bypass_All_Triggers__c');
        tryBypassHierarchySetting('Trigger_Settings__c', 'Bypass_Account_Trigger__c');
        tryBypassHierarchySetting('Hangyo_Settings__c', 'Bypass_Triggers__c');
    }

    private static void tryBypassHierarchySetting(String objectApi, String fieldApi) {
        if (!Schema.getGlobalDescribe().containsKey(objectApi)) {
            return;
        }
        Schema.SObjectType t = Schema.getGlobalDescribe().get(objectApi);
        if (!t.getDescribe().fields.getMap().containsKey(fieldApi)) {
            return;
        }
        Id orgId = UserInfo.getOrganizationId();
        List<SObject> rows = Database.query(
            'SELECT Id, ' + fieldApi + ' FROM ' + objectApi + ' WHERE SetupOwnerId = :orgId LIMIT 1'
        );
        SObject row = rows.isEmpty() ? t.newSObject() : rows[0];
        if (rows.isEmpty()) {
            row.put('SetupOwnerId', orgId);
        }
        row.put(fieldApi, true);
        upsert row;
    }

    private static void insertTaxCustomSetting() {
        if (Order_tax_value__c.getValues('General GST Settings') == null) {
            insert new Order_tax_value__c(
                Name = 'General GST Settings',
                SetupOwnerId = UserInfo.getOrganizationId(),
                CGST__c = 9,
                SGST__c = 9,
                IGST__c = 18
            );
        }
    }

    private static Set<String> getActivePicklistValues(String objectApi, String fieldApi) {
        Set<String> values = new Set<String>();
        Schema.SObjectField f =
            Schema.getGlobalDescribe()
                .get(objectApi)
                .getDescribe()
                .fields.getMap()
                .get(fieldApi);
        if (f == null) {
            return values;
        }
        for (Schema.PicklistEntry pe : f.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                values.add(pe.getValue());
            }
        }
        return values;
    }

    private static Id getRtId(String sObjectType, String developerName) {
        Schema.DescribeSObjectResult d =
            Schema.getGlobalDescribe().get(sObjectType).getDescribe();
        if (d.getRecordTypeInfosByDeveloperName().containsKey(developerName)) {
            return d.getRecordTypeInfosByDeveloperName()
                .get(developerName)
                .getRecordTypeId();
        }
        return null;
    }

    private static SObject createRegionIfExists(String stateName) {
        if (!Schema.getGlobalDescribe().containsKey('Region__c')) {
            return null;
        }
        SObject region = Schema.getGlobalDescribe().get('Region__c').newSObject();
        region.put('Name', stateName);
        insert region;
        return region;
    }
}