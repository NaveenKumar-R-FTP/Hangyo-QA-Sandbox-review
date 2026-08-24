@isTest
private class MultiSchemeReimbursementServiceTest {

    // ─────────────────────────────────────────────────────────────────────────
    // @testSetup — ensures GenerateRetailerCreationCode's dependency exists
    // before any test in this class inserts a Retailer-type Account. Without
    // this, that trigger's own lookup to RetailerCodeSetting__c comes back
    // null and throws, unrelated to anything this test class is actually
    // trying to cover.
    // ─────────────────────────────────────────────────────────────────────────
    @testSetup
    static void setupRetailerCodeSetting() {
        List<RetailerCodeSetting__c> existing = [SELECT Id FROM RetailerCodeSetting__c WHERE Name = 'SF' LIMIT 1];
        if (existing.isEmpty()) {
            insert new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Shared test data setup
    // ─────────────────────────────────────────────────────────────────────────
    private static Account createRetailerAccount(String name) {
        Id retailerRTId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId();
        Account acc = new Account(
            Name          = name,
            RecordTypeId  = retailerRTId,
            Primary_State__c = 'Karnataka'
        );
        insert acc;
        return acc;
    }

    private static Account createDistributorAccount(String name) {
        Account acc = new Account(Name = name);
        insert acc;
        return acc;
    }

    private static Reimbursement_Scheme_Definition__c createSchemeDefinition(String name, Date startDate, Date endDate) {
        Reimbursement_Scheme_Definition__c def = new Reimbursement_Scheme_Definition__c(
            Name          = name,
            Start_Date__c = startDate,
            End_Date__c   = endDate
        );
        insert def;
        return def;
    }

    private static Retailer_Reimbursement_Scheme__c createAllocation(Id retailerId, Id schemeDefId, Decimal balance) {
        Retailer_Reimbursement_Scheme__c alloc = new Retailer_Reimbursement_Scheme__c(
            Account__c           = retailerId,
            Scheme_Definition__c = schemeDefId,
            Balance__c            = balance
        );
        insert alloc;
        return alloc;
    }

    private static Invoice__c createInvoice(Id distributorId, Id retailerId) {
        Id secondaryInvoiceRT = Schema.SObjectType.Invoice__c.getRecordTypeInfosByDeveloperName().get('Secondary_Invoice').getRecordTypeId();
        Invoice__c inv = new Invoice__c(
            Name                   = 'TEST-INV-' + Math.random(),
            Distributor_Account__c = distributorId,
            Retailer_Account__c    = retailerId,
            RecordTypeId           = secondaryInvoiceRT,
            Status__c              = 'Draft',
            Invoice_Date__c        = System.today()
        );
        insert inv;
        return inv;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getActiveSchemes
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testGetActiveSchemes_ReturnsOnlyCurrentlyValidOnes() {
        Account retailer = createRetailerAccount('Test Retailer 1');

        Reimbursement_Scheme_Definition__c validDef = createSchemeDefinition(
            'Valid Scheme', System.today().addDays(-5), System.today().addDays(5)
        );
        Reimbursement_Scheme_Definition__c expiredDef = createSchemeDefinition(
            'Expired Scheme', System.today().addDays(-30), System.today().addDays(-10)
        );

        createAllocation(retailer.Id, validDef.Id, 500);
        createAllocation(retailer.Id, expiredDef.Id, 1000);

        Test.startTest();
        List<MultiSchemeReimbursementService.ActiveSchemeWrapper> result =
            MultiSchemeReimbursementService.getActiveSchemes(retailer.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Only the currently valid scheme should be returned');
        System.assertEquals('Valid Scheme', result[0].schemeName);
        System.assertEquals(500, result[0].balance);
    }

    @isTest
    static void testGetActiveSchemes_NullRetailerReturnsEmptyList() {
        Test.startTest();
        List<MultiSchemeReimbursementService.ActiveSchemeWrapper> result =
            MultiSchemeReimbursementService.getActiveSchemes(null);
        Test.stopTest();

        System.assertEquals(0, result.size());
    }

    @isTest
    static void testGetActiveSchemes_RetailerWithNoAllocations() {
        Account retailer = createRetailerAccount('Test Retailer No Allocations');

        Test.startTest();
        List<MultiSchemeReimbursementService.ActiveSchemeWrapper> result =
            MultiSchemeReimbursementService.getActiveSchemes(retailer.Id);
        Test.stopTest();

        System.assertEquals(0, result.size());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // saveAppliedLines
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testSaveAppliedLines_InsertsLinesAndUpdatesInvoiceTotal() {
        Account retailer     = createRetailerAccount('Test Retailer 2');
        Account distributor  = createDistributorAccount('Test Distributor 1');
        Reimbursement_Scheme_Definition__c def = createSchemeDefinition(
            'Scheme A', System.today().addDays(-1), System.today().addDays(10)
        );
        Retailer_Reimbursement_Scheme__c alloc = createAllocation(retailer.Id, def.Id, 500);
        Invoice__c inv = createInvoice(distributor.Id, retailer.Id);

        List<Map<String, Object>> appliedLines = new List<Map<String, Object>>{
            new Map<String, Object>{ 'allocationId' => alloc.Id, 'amount' => 300 }
        };

        Test.startTest();
        MultiSchemeReimbursementService.saveAppliedLines(inv.Id, JSON.serialize(appliedLines));
        Test.stopTest();

        List<Invoice_Reimbursement_Line__c> lines = [
            SELECT Amount_Applied__c, Retailer_Reimbursement_Scheme__c
            FROM Invoice_Reimbursement_Line__c
            WHERE Invoice__c = :inv.Id
        ];
        System.assertEquals(1, lines.size());
        System.assertEquals(300, lines[0].Amount_Applied__c);

        Invoice__c updatedInv = [SELECT Total_Reimbursement_Applied__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assertEquals(300, updatedInv.Total_Reimbursement_Applied__c);
    }

    @isTest
    static void testSaveAppliedLines_ReplacesExistingLinesOnResave() {
        Account retailer     = createRetailerAccount('Test Retailer 3');
        Account distributor  = createDistributorAccount('Test Distributor 2');
        Reimbursement_Scheme_Definition__c def = createSchemeDefinition(
            'Scheme B', System.today().addDays(-1), System.today().addDays(10)
        );
        Retailer_Reimbursement_Scheme__c alloc = createAllocation(retailer.Id, def.Id, 1000);
        Invoice__c inv = createInvoice(distributor.Id, retailer.Id);

        // First save
        MultiSchemeReimbursementService.saveAppliedLines(
            inv.Id,
            JSON.serialize(new List<Map<String, Object>>{
                new Map<String, Object>{ 'allocationId' => alloc.Id, 'amount' => 400 }
            })
        );

        Test.startTest();
        // Re-save with a different amount — should replace, not add to, the old line
        MultiSchemeReimbursementService.saveAppliedLines(
            inv.Id,
            JSON.serialize(new List<Map<String, Object>>{
                new Map<String, Object>{ 'allocationId' => alloc.Id, 'amount' => 150 }
            })
        );
        Test.stopTest();

        List<Invoice_Reimbursement_Line__c> lines = [
            SELECT Amount_Applied__c FROM Invoice_Reimbursement_Line__c WHERE Invoice__c = :inv.Id
        ];
        System.assertEquals(1, lines.size(), 'Old line should have been replaced, not duplicated');
        System.assertEquals(150, lines[0].Amount_Applied__c);

        Invoice__c updatedInv = [SELECT Total_Reimbursement_Applied__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assertEquals(150, updatedInv.Total_Reimbursement_Applied__c);
    }

    @isTest
    static void testSaveAppliedLines_BlankJsonClearsLinesAndZeroesTotal() {
        Account retailer     = createRetailerAccount('Test Retailer 4');
        Account distributor  = createDistributorAccount('Test Distributor 3');
        Reimbursement_Scheme_Definition__c def = createSchemeDefinition(
            'Scheme C', System.today().addDays(-1), System.today().addDays(10)
        );
        Retailer_Reimbursement_Scheme__c alloc = createAllocation(retailer.Id, def.Id, 200);
        Invoice__c inv = createInvoice(distributor.Id, retailer.Id);

        MultiSchemeReimbursementService.saveAppliedLines(
            inv.Id,
            JSON.serialize(new List<Map<String, Object>>{
                new Map<String, Object>{ 'allocationId' => alloc.Id, 'amount' => 200 }
            })
        );

        Test.startTest();
        MultiSchemeReimbursementService.saveAppliedLines(inv.Id, null);
        Test.stopTest();

        List<Invoice_Reimbursement_Line__c> lines = [
            SELECT Id FROM Invoice_Reimbursement_Line__c WHERE Invoice__c = :inv.Id
        ];
        System.assertEquals(0, lines.size());

        Invoice__c updatedInv = [SELECT Total_Reimbursement_Applied__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assertEquals(0, updatedInv.Total_Reimbursement_Applied__c);
    }

    @isTest
    static void testSaveAppliedLines_NullInvoiceIdDoesNothing() {
        Test.startTest();
        MultiSchemeReimbursementService.saveAppliedLines(null, '[]');
        Test.stopTest();
        // No exception thrown = success; nothing to assert against
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getAppliedLinesForInvoice
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testGetAppliedLinesForInvoice_ReturnsCorrectMap() {
        Account retailer     = createRetailerAccount('Test Retailer 5');
        Account distributor  = createDistributorAccount('Test Distributor 4');
        Reimbursement_Scheme_Definition__c def = createSchemeDefinition(
            'Scheme D', System.today().addDays(-1), System.today().addDays(10)
        );
        Retailer_Reimbursement_Scheme__c alloc = createAllocation(retailer.Id, def.Id, 800);
        Invoice__c inv = createInvoice(distributor.Id, retailer.Id);

        MultiSchemeReimbursementService.saveAppliedLines(
            inv.Id,
            JSON.serialize(new List<Map<String, Object>>{
                new Map<String, Object>{ 'allocationId' => alloc.Id, 'amount' => 250 }
            })
        );

        Test.startTest();
        Map<Id, Decimal> result = MultiSchemeReimbursementService.getAppliedLinesForInvoice(inv.Id);
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals(250, result.get(alloc.Id));
    }

    @isTest
    static void testGetAppliedLinesForInvoice_NullInvoiceReturnsEmptyMap() {
        Test.startTest();
        Map<Id, Decimal> result = MultiSchemeReimbursementService.getAppliedLinesForInvoice(null);
        Test.stopTest();

        System.assertEquals(0, result.size());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // applyLinesOnConfirm
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testApplyLinesOnConfirm_DeductsBalanceCorrectly() {
        Account retailer     = createRetailerAccount('Test Retailer 6');
        Account distributor  = createDistributorAccount('Test Distributor 5');
        Reimbursement_Scheme_Definition__c def = createSchemeDefinition(
            'Scheme E', System.today().addDays(-1), System.today().addDays(10)
        );
        Retailer_Reimbursement_Scheme__c alloc = createAllocation(retailer.Id, def.Id, 1000);
        Invoice__c inv = createInvoice(distributor.Id, retailer.Id);

        MultiSchemeReimbursementService.saveAppliedLines(
            inv.Id,
            JSON.serialize(new List<Map<String, Object>>{
                new Map<String, Object>{ 'allocationId' => alloc.Id, 'amount' => 350 }
            })
        );

        Test.startTest();
        MultiSchemeReimbursementService.applyLinesOnConfirm(new Set<Id>{ inv.Id });
        Test.stopTest();

        Retailer_Reimbursement_Scheme__c updatedAlloc = [
            SELECT Balance__c FROM Retailer_Reimbursement_Scheme__c WHERE Id = :alloc.Id
        ];
        System.assertEquals(650, updatedAlloc.Balance__c, 'Balance should be reduced by exactly the applied amount');
    }

    @isTest
    static void testApplyLinesOnConfirm_NeverGoesNegative() {
        Account retailer     = createRetailerAccount('Test Retailer 7');
        Account distributor  = createDistributorAccount('Test Distributor 6');
        Reimbursement_Scheme_Definition__c def = createSchemeDefinition(
            'Scheme F', System.today().addDays(-1), System.today().addDays(10)
        );
        // Allocation balance is smaller than what gets "applied" — simulates
        // a stale/edge-case scenario; balance should floor at 0, not go negative.
        Retailer_Reimbursement_Scheme__c alloc = createAllocation(retailer.Id, def.Id, 100);
        Invoice__c inv = createInvoice(distributor.Id, retailer.Id);

        insert new Invoice_Reimbursement_Line__c(
            Invoice__c                       = inv.Id,
            Retailer_Reimbursement_Scheme__c = alloc.Id,
            Amount_Applied__c                = 300
        );

        Test.startTest();
        MultiSchemeReimbursementService.applyLinesOnConfirm(new Set<Id>{ inv.Id });
        Test.stopTest();

        Retailer_Reimbursement_Scheme__c updatedAlloc = [
            SELECT Balance__c FROM Retailer_Reimbursement_Scheme__c WHERE Id = :alloc.Id
        ];
        System.assertEquals(0, updatedAlloc.Balance__c);
    }

    @isTest
    static void testApplyLinesOnConfirm_EmptySetDoesNothing() {
        Test.startTest();
        MultiSchemeReimbursementService.applyLinesOnConfirm(new Set<Id>());
        MultiSchemeReimbursementService.applyLinesOnConfirm(null);
        Test.stopTest();
        // No exception thrown = success
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RetailerReimbursementSchemeTrigger — Initial_Balance__c capture + lock
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testTrigger_AutoPopulatesInitialBalanceOnInsert() {
        Account retailer = createRetailerAccount('Test Retailer 8');
        Reimbursement_Scheme_Definition__c def = createSchemeDefinition(
            'Scheme G', System.today().addDays(-1), System.today().addDays(10)
        );

        Test.startTest();
        Retailer_Reimbursement_Scheme__c alloc = new Retailer_Reimbursement_Scheme__c(
            Account__c           = retailer.Id,
            Scheme_Definition__c = def.Id,
            Balance__c            = 700
        );
        insert alloc;
        Test.stopTest();

        Retailer_Reimbursement_Scheme__c inserted = [
            SELECT Initial_Balance__c FROM Retailer_Reimbursement_Scheme__c WHERE Id = :alloc.Id
        ];
        System.assertEquals(700, inserted.Initial_Balance__c, 'Initial Balance should auto-capture the starting Balance');
    }

    @isTest
    static void testTrigger_BlocksInitialBalanceChangeOnUpdate() {
        Account retailer = createRetailerAccount('Test Retailer 9');
        Reimbursement_Scheme_Definition__c def = createSchemeDefinition(
            'Scheme H', System.today().addDays(-1), System.today().addDays(10)
        );
        Retailer_Reimbursement_Scheme__c alloc = createAllocation(retailer.Id, def.Id, 500);

        Test.startTest();
        Boolean errorThrown = false;
        try {
            alloc.Initial_Balance__c = 999;
            update alloc;
        } catch (DmlException e) {
            errorThrown = true;
            System.assert(e.getMessage().contains('Initial Balance cannot be changed'));
        }
        Test.stopTest();

        System.assert(errorThrown, 'Updating Initial Balance after creation should be blocked');
    }

    @isTest
    static void testTrigger_AllowsBalanceUpdateWithoutTouchingInitialBalance() {
        Account retailer = createRetailerAccount('Test Retailer 10');
        Reimbursement_Scheme_Definition__c def = createSchemeDefinition(
            'Scheme I', System.today().addDays(-1), System.today().addDays(10)
        );
        Retailer_Reimbursement_Scheme__c alloc = createAllocation(retailer.Id, def.Id, 500);

        Test.startTest();
        alloc.Balance__c = 200; // normal depletion — Initial_Balance__c untouched
        update alloc;
        Test.stopTest();

        Retailer_Reimbursement_Scheme__c updated = [
            SELECT Balance__c, Initial_Balance__c FROM Retailer_Reimbursement_Scheme__c WHERE Id = :alloc.Id
        ];
        System.assertEquals(200, updated.Balance__c);
        System.assertEquals(500, updated.Initial_Balance__c, 'Initial Balance should remain unchanged');
    }
}