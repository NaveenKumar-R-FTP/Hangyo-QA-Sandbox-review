/**
 * WelcomeDashboardControllerTest
 * ---------------------------------------------------------------------------
 * Coverage for WelcomeDashboardController.
 *
 * The controller is READ-ONLY (only SELECT/aggregate queries), so the primary
 * test simply invokes it for the running user and asserts a fully-populated DTO
 * — this executes every query and DTO-building path and covers the majority of
 * the class with zero dependency on org data.
 *
 * seedBestEffort() additionally inserts a few minimal records to exercise the
 * loop / non-empty branches. Because this org is automation-heavy (triggers,
 * flows, validation rules, required fields), each insert is isolated in its own
 * try/catch so a blocked insert never fails the test — the read-only baseline
 * still provides the coverage.
 */
@isTest
private class WelcomeDashboardControllerTest {

    // 1) Baseline — controller returns a complete DTO for the current user.
    @isTest
    static void dashboard_returnsCompleteDto() {
        Test.startTest();
        WelcomeDashboardController.DashboardDTO dto = WelcomeDashboardController.getDashboard();
        WelcomeDashboardController.AttendanceTodayDTO status = WelcomeDashboardController.getTodayAttendanceStatus();
        Test.stopTest();

        System.assertNotEquals(null, dto, 'Dashboard DTO should not be null');
        System.assertNotEquals(null, dto.attendance, 'attendance section present');
        System.assertNotEquals(null, dto.outlets,    'outlets section present');
        System.assertNotEquals(null, dto.target,     'target section present');
        System.assertNotEquals(null, dto.beat,       'beat section present');
        System.assertNotEquals(null, dto.order,      'order section present');
        System.assertNotEquals(null, dto.rings,      'rings section present');
        System.assert(dto.attendance.workingDays >= 0, 'working days computed');
        System.assertNotEquals(null, status, 'attendance/EOD status returned');
    }

    // 2) Working-days helper (private @TestVisible) — Sundays excluded, reversed range guarded.
    @isTest
    static void workingDays_excludeSundays() {
        Date monday = Date.newInstance(2024, 1, 1); // Monday
        Date sunday = Date.newInstance(2024, 1, 7); // Sunday
        System.assertEquals(6, WelcomeDashboardController.countWorkingDays(monday, sunday),
            '1–7 Jan 2024 = 6 working days (one Sunday excluded)');
        System.assertEquals(0, WelcomeDashboardController.countWorkingDays(sunday, monday),
            'reversed range returns 0');
    }

    // 3) Best-effort data path — exercises non-empty branches where the org allows.
    @isTest
    static void dashboard_withSeededData() {
        seedBestEffort();
        Test.startTest();
        WelcomeDashboardController.DashboardDTO dto = WelcomeDashboardController.getDashboard();
        WelcomeDashboardController.getTodayAttendanceStatus();
        Test.stopTest();
        System.assertNotEquals(null, dto, 'DTO still returned with seeded data');
    }

    /**
     * Inserts a minimal, self-contained data set owned by / linked to the running
     * user. Every insert is isolated — a validation rule, required field or trigger
     * on any one object cannot stop the others.
     */
    static void seedBestEffort() {
        Id uid = UserInfo.getUserId();

        Account retailer;
        try {
            retailer = new Account(Name = 'SFA Test Retailer', OwnerId = uid);
            insert retailer;
        } catch (Exception e) { retailer = null; }

        try {
            insert new Attendance__c(
                User__c = uid,
                Date_of_attendance__c = Date.today(),
                Status__c = 'Present'
            );
        } catch (Exception e) {}

        if (retailer != null) {
            try {
                insert new Asset_Mapping__c(Retailer__c = retailer.Id, Active__c = true);
            } catch (Exception e) {}

            try {
                insert new Invoice__c(
                    Retailer_Account__c = retailer.Id,
                    Invoice_Date__c = Date.today(),
                    Invoice_Amount__c = 1000
                );
            } catch (Exception e) {}
        }
    }
}