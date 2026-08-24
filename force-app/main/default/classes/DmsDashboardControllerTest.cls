@isTest
private class DmsDashboardControllerTest {
    
    @testSetup
    static void setupTestData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
    }

    private static RecordType getRecordType(String sObjectType, String developerName) {
        return [
            SELECT Id FROM RecordType
            WHERE SObjectType = :sObjectType
            AND   DeveloperName = :developerName
            LIMIT 1
        ];
    }

    private static Map<String, SObject> createRegularDistributorData() {
        RecordType distRT     = getRecordType('Account', 'Distributor');
        RecordType retailerRT = getRecordType('Account', 'Retailer');

        Account distributor = new Account(
            Name             = 'Test Distributor',
            RecordTypeId     = distRT.Id,
            BillingCity      = 'Mumbai',
            BillingState     = 'Maharashtra',
            Is_Active__c     = true
        );
        insert distributor;

        Account retailer = new Account(
            Name             = 'Test Retailer',
            RecordTypeId     = retailerRT.Id,
            Distributor__c   = distributor.Id,
            Is_Active__c     = true
        );
        insert retailer;

        Product__c product = new Product__c(
            Name             = 'Test Product',
            IsActive__c         = true,
            Product_Brand__c = 'Brand A'
        );
        insert product;

        RecordType secInvRT = getRecordType('Invoice__c', 'Secondary_Invoice');
        RecordType priInvRT = getRecordType('Invoice__c', 'Primary_Invoice');

        Date today     = Date.today();
        Date currStart = today.addDays(-20);
        Date prevStart = today.addDays(-50);

        Invoice__c currSecInv = new Invoice__c(
            RecordTypeId            = secInvRT.Id,
            Distributor_Account__c  = distributor.Id,
            Retailer_Account__c     = retailer.Id,
            Invoice_Date__c         = currStart,
            Invoice_Amount__c       = 10000
        );
        insert currSecInv;

        Invoice__c currPriInv = new Invoice__c(
            RecordTypeId            = priInvRT.Id,
            Distributor_Account__c  = distributor.Id,
            Invoice_Date__c         = currStart,
            Invoice_Amount__c       = 20000
        );
        insert currPriInv;

        Invoice__c prevSecInv = new Invoice__c(
            RecordTypeId            = secInvRT.Id,
            Distributor_Account__c  = distributor.Id,
            Retailer_Account__c     = retailer.Id,
            Invoice_Date__c         = prevStart,
            Invoice_Amount__c       = 8000
        );
        insert prevSecInv;

        Invoice_Line_Item__c currLineItem = new Invoice_Line_Item__c(
            Invoice__c      = currSecInv.Id,
            Product__c      = product.Id,
            Total_Amount__c = 10000
        );
        insert currLineItem;

        Invoice_Line_Item__c prevLineItem = new Invoice_Line_Item__c(
            Invoice__c      = prevSecInv.Id,
            Product__c      = product.Id,
            Total_Amount__c = 8000
        );
        insert prevLineItem;

        Returns__c ret = new Returns__c(
            Invoice__c = currSecInv.Id,
            Return_Amount__c = 500
        );
        insert ret;

        return new Map<String, SObject>{
            'distributor'  => distributor,
            'retailer'     => retailer,
            'product'      => product,
            'currSecInv'   => currSecInv,
            'currPriInv'   => currPriInv
        };
    }

    private static Map<String, SObject> createSuperStockistData() {
        RecordType ssRT   = getRecordType('Account', 'SuperStockist');
        RecordType distRT = getRecordType('Account', 'Distributor');

        Account ss = new Account(
            Name         = 'Test Super Stockist',
            RecordTypeId = ssRT.Id,
            BillingCity  = 'Delhi',
            BillingState = 'Delhi',
            Is_Active__c = true
        );
        insert ss;

        Account underSSDist = new Account(
            Name                      = 'Under SS Distributor',
            RecordTypeId              = distRT.Id,
            Super_Stockist_Name__c    = ss.Id,
            Distributor_Type__c       = 'Under Super Stockist',
            Is_Active__c              = true
        );
        insert underSSDist;

        Product__c product = new Product__c(
            Name             = 'SS Product',
            IsActive__c      = true,
            Product_Brand__c = 'Brand SS'
        );
        insert product;

        RecordType secUnderSSRT = getRecordType('Invoice__c', 'Secondary_Invoice_Under_SS');
        RecordType priInvRT     = getRecordType('Invoice__c', 'Primary_Invoice');

        Date today     = Date.today();
        Date currStart = today.addDays(-15);
        Date prevStart = today.addDays(-45);

        Invoice__c currSecInv = new Invoice__c(
            RecordTypeId            = secUnderSSRT.Id,
            Distributor_Account__c  = ss.Id,
            Under_SS__c             = underSSDist.Id,
            Invoice_Date__c         = currStart,
            Invoice_Amount__c       = 50000
        );
        insert currSecInv;

        Invoice__c currPriInv = new Invoice__c(
            RecordTypeId            = priInvRT.Id,
            Distributor_Account__c  = ss.Id,
            Invoice_Date__c         = currStart,
            Invoice_Amount__c       = 70000
        );
        insert currPriInv;

        Invoice__c prevSecInv = new Invoice__c(
            RecordTypeId            = secUnderSSRT.Id,
            Distributor_Account__c  = ss.Id,
            Under_SS__c             = underSSDist.Id,
            Invoice_Date__c         = prevStart,
            Invoice_Amount__c       = 40000
        );
        insert prevSecInv;

        Invoice_Line_Item__c currLine = new Invoice_Line_Item__c(
            Invoice__c      = currSecInv.Id,
            Product__c      = product.Id,
            Total_Amount__c = 50000
        );
        insert currLine;

        Invoice_Line_Item__c prevLine = new Invoice_Line_Item__c(
            Invoice__c      = prevSecInv.Id,
            Product__c      = product.Id,
            Total_Amount__c = 40000
        );
        insert prevLine;

        Returns__c ret = new Returns__c(
            Invoice__c               = currSecInv.Id,
            Return_Amount__c  = 1000
        );
        insert ret;

        return new Map<String, SObject>{
            'ss'           => ss,
            'underSSDist'  => underSSDist,
            'product'      => product
        };
    }

    private static Map<String, SObject> createUnderSSDistributorData() {
        RecordType ssRT   = getRecordType('Account', 'SuperStockist');
        RecordType distRT = getRecordType('Account', 'Distributor');
        RecordType retailerRT = getRecordType('Account', 'Retailer');

        Account ss = new Account(
            Name         = 'Parent SS',
            RecordTypeId = ssRT.Id,
            Is_Active__c = true
        );
        insert ss;

        Account underSSDist = new Account(
            Name                      = 'Under SS Dist',
            RecordTypeId              = distRT.Id,
            Super_Stockist_Name__c    = ss.Id,
            Distributor_Type__c       = 'Under Super Stockist',
            Is_Active__c              = true
        );
        insert underSSDist;

        Account retailer = new Account(
            Name             = 'Under SS Retailer',
            RecordTypeId     = retailerRT.Id,
            Distributor__c   = underSSDist.Id,
            Is_Active__c     = true
        );
        insert retailer;

        Product__c product = new Product__c(
            Name             = 'Under SS Product',
            IsActive__c         = true,
            Product_Brand__c = 'Brand Under SS'
        );
        insert product;

        RecordType secInvRT     = getRecordType('Invoice__c', 'Secondary_Invoice');
        RecordType secUnderSSRT = getRecordType('Invoice__c', 'Secondary_Invoice_Under_SS');

        Date today     = Date.today();
        Date currStart = today.addDays(-10);
        Date prevStart = today.addDays(-45);

        // Secondary_Invoice (distributor sells to retailer)
        Invoice__c currSecInv = new Invoice__c(
            RecordTypeId            = secInvRT.Id,
            Distributor_Account__c  = underSSDist.Id,
            Retailer_Account__c     = retailer.Id,
            Invoice_Date__c         = currStart,
            Invoice_Amount__c       = 15000
        );
        insert currSecInv;

        Invoice__c prevSecInv = new Invoice__c(
            RecordTypeId            = secInvRT.Id,
            Distributor_Account__c  = underSSDist.Id,
            Retailer_Account__c     = retailer.Id,
            Invoice_Date__c         = prevStart,
            Invoice_Amount__c       = 12000
        );
        insert prevSecInv;

        // Secondary_Invoice_Under_SS (SS sells to this distributor — purchase side)
        Invoice__c purchaseInv = new Invoice__c(
            RecordTypeId            = secUnderSSRT.Id,
            Distributor_Account__c  = ss.Id,
            Under_SS__c             = underSSDist.Id,
            Invoice_Date__c         = currStart,
            Invoice_Amount__c       = 25000
        );
        insert purchaseInv;

        Invoice_Line_Item__c lineItem = new Invoice_Line_Item__c(
            Invoice__c      = currSecInv.Id,
            Product__c      = product.Id,
            Total_Amount__c = 15000
        );
        insert lineItem;

        Invoice_Line_Item__c prevLineItem = new Invoice_Line_Item__c(
            Invoice__c      = prevSecInv.Id,
            Product__c      = product.Id,
            Total_Amount__c = 12000
        );
        insert prevLineItem;

        Returns__c ret = new Returns__c(
            Invoice__c               = currSecInv.Id,
            Return_Amount__c  = 300
        );
        insert ret;

        return new Map<String, SObject>{
            'ss'          => ss,
            'distributor' => underSSDist,
            'retailer'    => retailer,
            'product'     => product
        };
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test Methods
    // ─────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetDashboardData_RegularDistributor() {
        Map<String, SObject> data = createRegularDistributorData();
        Account dist = (Account) data.get('distributor');

        Test.startTest();
        DmsDashboardController.DashboardPayload payload =
            DmsDashboardController.getDashboardData(dist.Id);
        Test.stopTest();

        // Payload not null
        System.assertNotEquals(null, payload, 'Payload should not be null');

        // Window labels populated
        System.assertNotEquals(null, payload.currentWindowLabel, 'Current window label should be set');
        System.assertNotEquals(null, payload.prevWindowLabel,    'Prev window label should be set');

        // Distributor info
        System.assertEquals(dist.Id, payload.distributorInfo.accountId);
        System.assertEquals('Test Distributor', payload.distributorInfo.name);
        System.assertEquals(false, payload.distributorInfo.isSuperStockist);
        System.assert(payload.distributorInfo.location.contains('Mumbai'));

        // KPI
        System.assertNotEquals(null, payload.kpi);
        System.assert(payload.kpi.salesCurrent >= 0);
        System.assert(payload.kpi.purchaseCurrent >= 0);
        System.assert(payload.kpi.returnsCurrent >= 0);
        System.assert(payload.kpi.activeRetailersCurrent >= 0);

        // Weekly trend list not null
        System.assertNotEquals(null, payload.weeklyTrend);

        // Category data not null
        System.assertNotEquals(null, payload.categoryData);
        System.assert(payload.categoryData.size() > 0, 'Should have at least 1 category row');

        // Top retailers not null
        System.assertNotEquals(null, payload.topRetailers);
        System.assert(payload.topRetailers.size() > 0, 'Should have at least 1 top retailer');

        // Top products not null
        System.assertNotEquals(null, payload.topProducts);
        System.assert(payload.topProducts.size() > 0, 'Should have at least 1 top product');
    }

    @isTest
    static void testGetDashboardData_SuperStockist() {
        Map<String, SObject> data = createSuperStockistData();
        Account ss = (Account) data.get('ss');

        Test.startTest();
        DmsDashboardController.DashboardPayload payload =
            DmsDashboardController.getDashboardData(ss.Id);
        Test.stopTest();

        System.assertNotEquals(null, payload);
        System.assertEquals(true, payload.distributorInfo.isSuperStockist);
        System.assertEquals('Test Super Stockist', payload.distributorInfo.name);

        // SS KPIs should reflect Secondary_Invoice_Under_SS and Primary_Invoice
        System.assert(payload.kpi.salesCurrent >= 0);
        System.assert(payload.kpi.purchaseCurrent >= 0);

        // Active retailers for SS = count of under-SS distributors
        System.assert(payload.kpi.activeRetailersCurrent >= 1);

        // Top retailers = under-SS distributors
        System.assertNotEquals(null, payload.topRetailers);

        // Category data from SS secondary
        System.assertNotEquals(null, payload.categoryData);

        // Weekly trend
        System.assertNotEquals(null, payload.weeklyTrend);
    }

    @isTest
    static void testGetDashboardData_UnderSSDistributor() {
        Map<String, SObject> data = createUnderSSDistributorData();
        Account dist = (Account) data.get('distributor');

        Test.startTest();
        DmsDashboardController.DashboardPayload payload =
            DmsDashboardController.getDashboardData(dist.Id);
        Test.stopTest();

        System.assertNotEquals(null, payload);
        System.assertEquals(false, payload.distributorInfo.isSuperStockist);

        // Under-SS purchase = sumUnderSSPurchase
        System.assert(payload.kpi.purchaseCurrent >= 0);
        System.assert(payload.kpi.salesCurrent >= 0);
        System.assert(payload.kpi.returnsCurrent >= 0);
        System.assert(payload.kpi.activeRetailersCurrent >= 1);

        System.assertNotEquals(null, payload.topRetailers);
        System.assertNotEquals(null, payload.topProducts);
        System.assertNotEquals(null, payload.categoryData);
    }

    /*@isTest
    static void testGetDashboardData_NullAccountId() {
        Test.startTest();

            DmsDashboardController.getDashboardData(null);
        Test.stopTest();

        System.assertNotEquals(null, payload, 'Payload should still be returned for null Id');
        System.assertEquals(null, payload.distributorInfo.accountId);
        System.assertEquals(false, payload.distributorInfo.isSuperStockist);
    }*/

    @isTest
    static void testKpiValues_RegularDistributor() {
        Map<String, SObject> data = createRegularDistributorData();
        Account dist = (Account) data.get('distributor');

        Test.startTest();
        DmsDashboardController.DashboardPayload payload =
            DmsDashboardController.getDashboardData(dist.Id);
        Test.stopTest();

        // Current secondary sales should be 10000
        System.assertEquals(10000, payload.kpi.salesCurrent,
            'Current sales should match inserted invoice amount');

        // Current primary purchase should be 20000
        System.assertEquals(20000, payload.kpi.purchaseCurrent,
            'Current purchase should match inserted invoice amount');

        // Returns should be 500
        System.assertEquals(500, payload.kpi.returnsCurrent,
            'Returns should match inserted return amount');
    }

    @isTest
    static void testKpiValues_SuperStockist() {
        Map<String, SObject> data = createSuperStockistData();
        Account ss = (Account) data.get('ss');

        Test.startTest();
        DmsDashboardController.DashboardPayload payload =
            DmsDashboardController.getDashboardData(ss.Id);
        Test.stopTest();

        System.assertEquals(50000, payload.kpi.salesCurrent,
            'SS secondary sales should be 50000');
        System.assertEquals(70000, payload.kpi.purchaseCurrent,
            'SS primary purchase should be 70000');
        System.assertEquals(1000, payload.kpi.returnsCurrent,
            'SS returns should be 1000');
    }

    @isTest
    static void testWeeklyTrend_PopulatedForRegularDist() {
        Map<String, SObject> data = createRegularDistributorData();
        Account dist = (Account) data.get('distributor');

        Test.startTest();
        DmsDashboardController.DashboardPayload payload =
            DmsDashboardController.getDashboardData(dist.Id);
        Test.stopTest();

        System.assertNotEquals(null, payload.weeklyTrend);
        // At least one bucket should be populated from the inserted invoices
        System.assert(payload.weeklyTrend.size() >= 1, 'Weekly trend should have at least 1 bucket');

        DmsDashboardController.WeeklyBucket bucket = payload.weeklyTrend[0];
        System.assertNotEquals(null, bucket.weekLabel);
        System.assert(bucket.secondarySales >= 0);
        System.assert(bucket.primaryPurchase >= 0);
    }

    @isTest
    static void testCategoryData_RegularDist() {
        Map<String, SObject> data = createRegularDistributorData();
        Account dist = (Account) data.get('distributor');

        Test.startTest();
        DmsDashboardController.DashboardPayload payload =
            DmsDashboardController.getDashboardData(dist.Id);
        Test.stopTest();

        System.assert(payload.categoryData.size() >= 1);
        DmsDashboardController.CategoryRow row = payload.categoryData[0];
        System.assertNotEquals(null, row.category);
        System.assert(row.currentAmount > 0);
    }

    @isTest
    static void testTopRetailers_RegularDist() {
        Map<String, SObject> data = createRegularDistributorData();
        Account dist = (Account) data.get('distributor');

        Test.startTest();
        DmsDashboardController.DashboardPayload payload =
            DmsDashboardController.getDashboardData(dist.Id);
        Test.stopTest();

        System.assert(payload.topRetailers.size() >= 1);
        DmsDashboardController.TopRetailerRow row = payload.topRetailers[0];
        System.assertNotEquals(null, row.retailerName);
        System.assert(row.currentAmount > 0);
    }

    @isTest
    static void testTopProducts_RegularDist() {
        Map<String, SObject> data = createRegularDistributorData();
        Account dist = (Account) data.get('distributor');

        Test.startTest();
        DmsDashboardController.DashboardPayload payload =
            DmsDashboardController.getDashboardData(dist.Id);
        Test.stopTest();

        System.assert(payload.topProducts.size() >= 1);
        DmsDashboardController.TopProductRow row = payload.topProducts[0];
        System.assertNotEquals(null, row.productName);
        System.assert(row.currentAmount > 0);
    }

    @isTest
    static void testTopRetailers_SuperStockist() {
        Map<String, SObject> data = createSuperStockistData();
        Account ss = (Account) data.get('ss');

        Test.startTest();
        DmsDashboardController.DashboardPayload payload =
            DmsDashboardController.getDashboardData(ss.Id);
        Test.stopTest();

        System.assertNotEquals(null, payload.topRetailers);
        // Should show under-SS distributors
        if (payload.topRetailers.size() > 0) {
            DmsDashboardController.TopRetailerRow row = payload.topRetailers[0];
            System.assertNotEquals(null, row.retailerName);
            System.assert(row.currentAmount > 0);
        }
    }

    @isTest
    static void testAnnouncements() {
        // Announcements come from Custom Metadata — just verify list is returned (may be empty in test org)
        Map<String, SObject> data = createRegularDistributorData();
        Account dist = (Account) data.get('distributor');

        Test.startTest();
        DmsDashboardController.DashboardPayload payload =
            DmsDashboardController.getDashboardData(dist.Id);
        Test.stopTest();

        System.assertNotEquals(null, payload.announcements,
            'Announcements list should not be null even if empty');
    }

    @isTest
    static void testLocationBuilding_CityOnly() {
        RecordType distRT = getRecordType('Account', 'Distributor');
        Account dist = new Account(
            Name         = 'City Only Dist',
            RecordTypeId = distRT.Id,
            BillingCity  = 'Pune',
            Is_Active__c = true
        );
        insert dist;

        Test.startTest();
        DmsDashboardController.DashboardPayload payload =
            DmsDashboardController.getDashboardData(dist.Id);
        Test.stopTest();

        System.assertEquals('Pune', payload.distributorInfo.location);
    }

    @isTest
    static void testLocationBuilding_StateOnly() {
        RecordType distRT = getRecordType('Account', 'Distributor');
        Account dist = new Account(
            Name          = 'State Only Dist',
            RecordTypeId  = distRT.Id,
            BillingState  = 'Gujarat',
            Is_Active__c  = true
        );
        insert dist;

        Test.startTest();
        DmsDashboardController.DashboardPayload payload =
            DmsDashboardController.getDashboardData(dist.Id);
        Test.stopTest();

        System.assertEquals('Gujarat', payload.distributorInfo.location);
    }

    @isTest
    static void testLocationBuilding_NoCityNoState() {
        RecordType distRT = getRecordType('Account', 'Distributor');
        Account dist = new Account(
            Name         = 'No Location Dist',
            RecordTypeId = distRT.Id,
            Is_Active__c = true
        );
        insert dist;

        Test.startTest();
        DmsDashboardController.DashboardPayload payload =
            DmsDashboardController.getDashboardData(dist.Id);
        Test.stopTest();

        System.assertEquals('', payload.distributorInfo.location);
    }

    @isTest
    static void testNoInvoices_EmptyLists() {
        // Distributor with no invoices at all — all aggregates should return 0 gracefully
        RecordType distRT = getRecordType('Account', 'Distributor');
        Account dist = new Account(
            Name         = 'Empty Dist',
            RecordTypeId = distRT.Id,
            Is_Active__c = true
        );
        insert dist;

        Test.startTest();
        DmsDashboardController.DashboardPayload payload =
            DmsDashboardController.getDashboardData(dist.Id);
        Test.stopTest();

        System.assertEquals(0, payload.kpi.salesCurrent);
        System.assertEquals(0, payload.kpi.purchaseCurrent);
        System.assertEquals(0, payload.kpi.returnsCurrent);
        System.assertEquals(0, payload.topRetailers.size());
        System.assertEquals(0, payload.topProducts.size());
        System.assertEquals(0, payload.categoryData.size());
    }

    @isTest
    static void testPreviousWindowValues_RegularDist() {
        Map<String, SObject> data = createRegularDistributorData();
        Account dist = (Account) data.get('distributor');

        Test.startTest();
        DmsDashboardController.DashboardPayload payload =
            DmsDashboardController.getDashboardData(dist.Id);
        Test.stopTest();

        // Previous period secondary invoice = 8000
        System.assertEquals(8000, payload.kpi.salesPrev,
            'Previous sales should match prev-period invoice');
    }

    @isTest
    static void testWrapperClasses_FieldsAccessible() {
        // Directly instantiate wrappers to confirm @AuraEnabled fields compile and are accessible
        DmsDashboardController.DashboardPayload dp  = new DmsDashboardController.DashboardPayload();
        DmsDashboardController.DistributorInfo  di  = new DmsDashboardController.DistributorInfo();
        DmsDashboardController.KpiBlock         kpi = new DmsDashboardController.KpiBlock();
        DmsDashboardController.WeeklyBucket     wb  = new DmsDashboardController.WeeklyBucket();
        DmsDashboardController.CategoryRow      cr  = new DmsDashboardController.CategoryRow();
        DmsDashboardController.TopRetailerRow   tr  = new DmsDashboardController.TopRetailerRow();
        DmsDashboardController.TopProductRow    tp  = new DmsDashboardController.TopProductRow();
        DmsDashboardController.AnnouncementItem ai  = new DmsDashboardController.AnnouncementItem();

        dp.currentWindowLabel = 'Test';
        di.isSuperStockist    = false;
        kpi.salesCurrent      = 100;
        wb.secondarySales     = 200;
        wb.primaryPurchase    = 300;
        cr.currentAmount      = 400;
        tr.currentAmount      = 500;
        tp.currentAmount      = 600;
        ai.label              = 'Test Label';
        ai.message            = 'Test Message';

        System.assertEquals('Test', dp.currentWindowLabel);
        System.assertEquals(100, kpi.salesCurrent);
        System.assertEquals(200, wb.secondarySales);
    }
}