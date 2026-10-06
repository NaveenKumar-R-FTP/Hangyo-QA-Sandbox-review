/**
 * PerformanceDashboardControllerTest
 * ---------------------------------------------------------------------------
 * Coverage for PerformanceDashboardController, PerformanceDataService and PerformanceDashboardDTO.
 * New class - Performance Dashboard project.
 *
 * - Pure logic (date windows, growth, percentages, HUB key) is asserted deterministically.
 * - Test users (ZSM -> RSM -> SO) are created inside the test only; all data is rolled back.
 * - Business records are seeded best-effort: this org is automation-heavy, so each insert is
 *   isolated in try/catch and a blocked insert never fails the test (same approach as the
 *   existing Welcome Dashboard tests). No existing record is read-modified or deleted.
 */
@isTest
private class PerformanceDashboardControllerTest {

    static final String HUB = 'Goa';

    @testSetup
    static void setup() {
        Profile p = pickProfile();
        User zsm; User rsm; User so; User other;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            zsm = newUser(p, 'pdzsm', 'ZSM', null);
            insert zsm;
            rsm = newUser(p, 'pdrsm', 'RSM', zsm.Id);
            insert rsm;
            so = newUser(p, 'pdso', 'SO', rsm.Id);
            insert so;
            other = newUser(p, 'pdoth', 'SO', null);
            insert other;
        }
        seedBestEffort(zsm, rsm, so);
    }

    // ------------------------------------------------------------ pure logic
    @isTest
    static void windows_mtdAndYtd() {
        Date d = Date.newInstance(2026, 9, 29);
        PerformanceDataService.Window m = PerformanceDataService.window('mtd', d);
        System.assertEquals('MTD', m.mode);
        System.assertEquals(Date.newInstance(2026, 9, 1), m.startDate);
        System.assertEquals(Date.newInstance(2025, 9, 1), m.lyStart);
        System.assertEquals(Date.newInstance(2025, 9, 29), m.lyEnd);
        System.assertEquals(2, m.remainingDays, '29 and 30 Sep');

        PerformanceDataService.Window y = PerformanceDataService.window('YTD', d);
        System.assertEquals(Date.newInstance(2026, 4, 1), y.startDate);
        System.assertEquals(Date.newInstance(2027, 3, 31), y.periodEnd);
        System.assertEquals(184, y.remainingDays);

        PerformanceDataService.Window jan = PerformanceDataService.window('YTD', Date.newInstance(2027, 1, 10));
        System.assertEquals(Date.newInstance(2026, 4, 1), jan.startDate, 'before April -> FY started last year');
        System.assertEquals('MTD', PerformanceDataService.normaliseMode(null));
    }

    @isTest
    static void helpers_growthPctHubKey() {
        System.assertEquals(Date.newInstance(2027, 2, 28),
            PerformanceDataService.sameDateLastYear(Date.newInstance(2028, 2, 29)), '29 Feb -> 28 Feb');
        System.assertEquals(null, PerformanceDataService.growthPercent(100, 0), 'LY = 0 -> dash');
        System.assert(PerformanceDataService.growthPercent(125, 100) == 25);
        System.assert(PerformanceDataService.pct(1, 2) == 50);
        System.assert(PerformanceDataService.pct(1, 0) == 0);
        System.assertEquals('PUNE CITY', PerformanceDataService.hubKey(' Pune city '));
        System.assertEquals(null, PerformanceDataService.hubKey(''));
        Map<String, Decimal> m = new Map<String, Decimal>{ 'a' => 1, 'b' => 2 };
        System.assert(PerformanceDataService.sumValues(m) == 3);
    }

    // ------------------------------------------------------------ access
    @isTest
    static void access_deniedForUnmappedRole() {
        User other = [SELECT Id FROM User WHERE Username LIKE 'pdoth%' LIMIT 1];
        System.runAs(other) {
            Test.startTest();
            System.assertEquals(true, PerformanceDashboardController.getSummary('MTD').accessDenied);
            System.assertEquals(true, PerformanceDashboardController.getFreezer('MTD').accessDenied);
            System.assertEquals(true, PerformanceDashboardController.getRegion('MTD').accessDenied);
            Test.stopTest();
        }
    }

    // ------------------------------------------------------------ full paths as a ZSM
    @isTest
    static void summary_mtdAndYtd_asZsm() {
        User zsm = [SELECT Id FROM User WHERE Username LIKE 'pdzsm%' LIMIT 1];
        System.runAs(zsm) {
            Test.startTest();
            PerformanceDashboardDTO.Summary mtd = PerformanceDashboardController.getSummary('MTD');
            PerformanceDashboardDTO.Summary ytd = PerformanceDashboardController.getSummary('YTD');
            Test.stopTest();
            System.assertEquals(false, mtd.accessDenied, 'ZSM has access');
            System.assertEquals('ZSM', mtd.header.designation);
            System.assertEquals(1, mtd.header.directReports, 'one direct report (RSM)');
            System.assertNotEquals(null, mtd.target);
            System.assertNotEquals(null, mtd.growth);
            System.assertNotEquals(null, mtd.calls);
            System.assertNotEquals(null, mtd.primary);
            System.assertNotEquals(null, mtd.attendance, 'Card 6 in MTD');
            System.assertNotEquals(null, mtd.today, 'Card 9 in MTD');
            System.assert(mtd.attendance.total >= 0 && mtd.attendance.total <= 2, 'viewer excluded; RSM + SO when on the SFA profile');
            System.assertEquals(null, ytd.attendance, 'Card 6 hidden in YTD');
            System.assertEquals(null, ytd.today, 'Card 9 hidden in YTD');
        }
    }

    @isTest
    static void freezerAndRegion_asZsm() {
        User zsm = [SELECT Id FROM User WHERE Username LIKE 'pdzsm%' LIMIT 1];
        System.runAs(zsm) {
            Test.startTest();
            PerformanceDashboardDTO.FreezerDTO f = PerformanceDashboardController.getFreezer('YTD');
            PerformanceDashboardDTO.RegionDTO r = PerformanceDashboardController.getRegion('MTD');
            PerformanceDashboardDTO.RegionDTO ry = PerformanceDashboardController.getRegion('YTD');
            Test.stopTest();
            System.assertEquals(false, f.accessDenied);
            System.assertEquals(false, r.accessDenied);
            System.assertEquals(1, r.hubs.size(), 'one HUB (Goa)');
            System.assertEquals('Goa', r.hubs[0].hub);
            System.assertNotEquals(null, r.hubs[0].headName);
            System.assertNotEquals(null, ry);
        }
    }

    @isTest
    static void team_multiHubHeadIsExpanded() {
        User zsm = [SELECT Id FROM User WHERE Username LIKE 'pdzsm%' LIMIT 1];
        User so = [SELECT Id FROM User WHERE Username LIKE 'pdso%' LIMIT 1];
        Set<Id> team = PerformanceDataService.selfAndReports(zsm.Id);
        System.assertEquals(3, team.size(), 'ZSM + RSM + SO');
        PerformanceDataService.Team t = new PerformanceDataService.Team(team, new Map<Id, Decimal>{ so.Id => 500 });
        System.assert(t.subtreeSales(zsm.Id) == 500, 'SO sales roll up to ZSM');
        System.assertEquals(1, t.subtreeDivisions(zsm.Id).size());
        System.assertEquals(zsm.Id, t.labelFor(so.Id).Id, 'first ZSM up the chain');
    }

    // ------------------------------------------------------------ data helpers
    static Profile pickProfile() {
        List<Profile> ps = [SELECT Id, Name FROM Profile WHERE Name IN ('SFA Profile', 'Standard User', 'System Administrator')];
        for (Profile p : ps) if (p.Name == 'SFA Profile') return p;
        return ps[0];
    }

    static User newUser(Profile p, String alias, String role, Id managerId) {
        String u = alias + System.currentTimeMillis() + '@pdtest.example.com';
        // Org restricts User.Email to company domains; test users are rolled back and never emailed.
        String email = alias + '.pdtest@hangyo.in';
        return new User(
            Username = u, Email = email, LastName = 'PD ' + role, Alias = alias,
            ProfileId = p.Id, TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            Employee_Role__c = role, Division = HUB, ManagerId = managerId
        );
    }

    /** Minimal records for the team; each insert isolated so org automation can't fail the test. */
    static void seedBestEffort(User zsm, User rsm, User so) {
        Date today = Date.today();
        try {
            Id monthRt = Schema.SObjectType.Sales_Target__c.getRecordTypeInfosByDeveloperName()
                            .get('Sales_Target_Month').getRecordTypeId();
            insert new Sales_Target__c(
                Target_Key__c = 'PDTEST-' + zsm.Id, Assigned_To__c = zsm.Id, RecordTypeId = monthRt,
                Number_of_Month__c = today.month(), From_Date__c = today.toStartOfMonth(),
                To_Date__c = today.toStartOfMonth().addMonths(1).addDays(-1), Secondary_Sales_Target__c = 100000);
        } catch (Exception e) {}

        Account retailer;
        try {
            retailer = new Account(Name = 'PD Test Retailer', OwnerId = so.Id, Is_Active__c = true);
            insert retailer;
        } catch (Exception e) { retailer = null; }

        Account dist;
        try {
            dist = new Account(Name = 'PD Test Distributor', Distributor_Type__c = 'Super Stockist', Hub__c = HUB);
            insert dist;
        } catch (Exception e) { dist = null; }

        try { insert new Attendance__c(User__c = so.Id, Date_of_attendance__c = today, Status__c = 'Present'); } catch (Exception e) {}
        try { insert new Attendance__c(User__c = rsm.Id, Date_of_attendance__c = today, Status__c = 'Leave'); } catch (Exception e) {}

        if (retailer != null) {
            try { insert new Asset_Mapping__c(Retailer__c = retailer.Id, Active__c = true); } catch (Exception e) {}
            try {
                insert new Invoice__c(
                    RecordTypeId = rtId('Invoice__c', 'Secondary_Invoice'), Retailer_Account__c = retailer.Id,
                    Invoice_Date__c = today, Invoice_Amount__c = 1000, Status__c = 'Confirmed');
            } catch (Exception e) {}
            try {
                insert new Visit_Task__c(
                    Visitor_Name__c = so.Id, Retailer__c = retailer.Id, Task_Planned_Date__c = today,
                    Checked_In_Time__c = System.now(), Order_Placed__c = true);
            } catch (Exception e) {}
            try {
                insert new Order__c(
                    RecordTypeId = rtId('Order__c', 'Secondary_Order'), OwnerId = so.Id,
                    Account__c = retailer.Id, Status__c = 'Order Placed');
            } catch (Exception e) {}
        }
        if (dist != null) {
            try {
                insert new Invoice__c(
                    RecordTypeId = rtId('Invoice__c', 'Primary_Invoice'), Distributor_Account__c = dist.Id,
                    Invoice_Date__c = today, Invoice_Amount__c = 5000);
            } catch (Exception e) {}
        }
    }

    static Id rtId(String obj, String devName) {
        Schema.RecordTypeInfo i = Schema.getGlobalDescribe().get(obj).getDescribe()
                                    .getRecordTypeInfosByDeveloperName().get(devName);
        return i == null ? null : i.getRecordTypeId();
    }
}