/**
 * Coverage for UserTrackingTestDataFactory helpers used by User Tracking dashboard tests.
 */
@IsTest
private class UserTrackingTestDataFactoryTest {
    @TestSetup
    static void setupDashboardScenario() {
        UserTrackingTestDataFactory.createDashboardScenario();
    }

    @IsTest
    static void testCreateDashboardScenario_populatesScenarioCache() {
        UserTrackingTestDataFactory.createDashboardScenario();
        UserTrackingTestDataFactory.ScenarioData data = UserTrackingTestDataFactory.getScenario();

        System.assertNotEquals(null, data, 'Scenario cache should be populated');
        System.assertNotEquals(null, data.userId);
        System.assertEquals(Date.today(), data.selectedDate);
        System.assertNotEquals(null, data.productiveVisitId);
        System.assertNotEquals(null, data.attendanceId);

        List<Attendance__c> atts = [
            SELECT Id, Status__c, EOD_Date_Time__c, EOD_Location__Latitude__s
            FROM Attendance__c
            WHERE Id = :data.attendanceId
        ];
        System.assertEquals(1, atts.size());
        System.assertEquals('Present', atts[0].Status__c);
        System.assertNotEquals(null, atts[0].EOD_Date_Time__c);
        System.assertNotEquals(null, atts[0].EOD_Location__Latitude__s);

        List<Order__c> orders = [
            SELECT Total_Order_Value__c
            FROM Order__c
            WHERE Visit_Task__c = :data.productiveVisitId
        ];
        System.assert(orders.size() >= 1, 'Productive visit should have an order');
    }

    @IsTest
    static void testGetScenario_resolvesFromSetupWhenCacheEmpty() {
        UserTrackingTestDataFactory.ScenarioData data = UserTrackingTestDataFactory.getScenario();

        System.assertNotEquals(null, data.userId, 'Setup user should resolve');
        System.assertEquals(Date.today(), data.selectedDate);
        System.assertNotEquals(null, data.productiveVisitId);
        System.assertNotEquals(null, data.attendanceId);
    }

    @IsTest
    static void testCreateStandardUser() {
        User u = UserTrackingTestDataFactory.createStandardUser('utd_factory');
        System.assertNotEquals(null, u.Id);
        System.assert(u.Username.contains('utd_factory'));
        System.assertEquals('TrackingTest', u.LastName);
    }

    @IsTest
    static void testEnsureRetailerCodeSetting_insertsAndRepairsNullCode() {
        if (!Schema.getGlobalDescribe().containsKey('RetailerCodeSetting__c')) {
            UserTrackingTestDataFactory.ensureRetailerCodeSetting();
            return;
        }

        UserTrackingTestDataFactory.ensureRetailerCodeSetting();

        List<RetailerCodeSetting__c> rows = [
            SELECT Id, Latest_Code__c
            FROM RetailerCodeSetting__c
            WHERE Name = 'SF'
            LIMIT 1
        ];
        System.assertEquals(1, rows.size(), 'SF retailer code setting expected');
        System.assertNotEquals(null, rows[0].Latest_Code__c);

        rows[0].Latest_Code__c = null;
        update rows[0];

        UserTrackingTestDataFactory.ensureRetailerCodeSetting();

        rows = [
            SELECT Latest_Code__c
            FROM RetailerCodeSetting__c
            WHERE Name = 'SF'
            LIMIT 1
        ];
        System.assertEquals(1, rows[0].Latest_Code__c, 'Null Latest_Code__c should be repaired');
    }

    @IsTest
    static void testCreateRetailerAccount() {
        Account acc = UserTrackingTestDataFactory.createRetailerAccount(
            'UTD Factory Retailer ' + String.valueOf(Crypto.getRandomInteger())
        );
        System.assertNotEquals(null, acc.Id);
        System.assertNotEquals(null, [SELECT Name FROM Account WHERE Id = :acc.Id].Name);
    }

    @IsTest
    static void testCreateRetailerAccountWithGeo() {
        User runUser = UserTrackingTestDataFactory.createStandardUser('utd_geo');
        Datetime createdAt = DateTime.newInstance(Date.today(), Time.newInstance(14, 30, 0, 0));

        System.runAs(runUser) {
            UserTrackingTestDataFactory.createRetailerAccountWithGeo(
                createdAt,
                'UTD Geo Outlet ' + String.valueOf(Crypto.getRandomInteger())
            );
        }

        List<Account> accounts = [
            SELECT BillingLatitude, BillingLongitude, CreatedDate
            FROM Account
            WHERE CreatedById = :runUser.Id
              AND Name LIKE 'UTD Geo Outlet%'
        ];
        System.assertEquals(1, accounts.size());
        System.assertEquals(13.050000, accounts[0].BillingLatitude);
        System.assertEquals(77.650000, accounts[0].BillingLongitude);
    }

    @IsTest
    static void testCreateAttendance_defaultsStatusAndOptionalEod() {
        User u = UserTrackingTestDataFactory.createStandardUser('utd_att');
        Date d = Date.today().addDays(-5);

        Attendance__c withoutEod = UserTrackingTestDataFactory.createAttendance(
            u.Id,
            d,
            null,
            'Check-in',
            12.971600,
            77.594600,
            false,
            null,
            null
        );
        withoutEod = [
            SELECT Status__c, Description__c, EOD_Date_Time__c
            FROM Attendance__c
            WHERE Id = :withoutEod.Id
        ];
        System.assertEquals('Present', withoutEod.Status__c);
        System.assertEquals('Check-in', withoutEod.Description__c);
        System.assertEquals(null, withoutEod.EOD_Date_Time__c);

        Attendance__c withEod = UserTrackingTestDataFactory.createAttendance(
            u.Id,
            d.addDays(1),
            'Present',
            null,
            12.980000,
            77.600000,
            true,
            12.970000,
            77.590000
        );
        withEod = [
            SELECT EOD_Date_Time__c, EOD_Location__Latitude__s, EOD_Location__Longitude__s
            FROM Attendance__c
            WHERE Id = :withEod.Id
        ];
        System.assertNotEquals(null, withEod.EOD_Date_Time__c);
        System.assertEquals(12.970000, withEod.EOD_Location__Latitude__s);
        System.assertEquals(77.590000, withEod.EOD_Location__Longitude__s);
    }

    @IsTest
    static void testCreateAttendanceOnly() {
        User u = UserTrackingTestDataFactory.createStandardUser('utd_attonly');
        Date d = Date.today().addDays(-4);

        Attendance__c att = UserTrackingTestDataFactory.createAttendanceOnly(
            u.Id,
            d,
            'Present',
            26.070460,
            83.179924,
            false
        );
        System.assertNotEquals(null, att.Id);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Attendance__c WHERE Id = :att.Id AND User__c = :u.Id]
        );
    }

    @IsTest
    static void testCreateVisitTask_andCreateVisitOnly() {
        User u = UserTrackingTestDataFactory.createStandardUser('utd_visit');
        Date d = Date.today().addDays(-3);
        Account outlet = UserTrackingTestDataFactory.createRetailerAccount('UTD Visit Task Outlet');

        Visit_Task__c vt = UserTrackingTestDataFactory.createVisitTask(
            u.Id,
            d,
            outlet.Id,
            true,
            DateTime.newInstance(d, Time.newInstance(10, 15, 0, 0)),
            13.100000,
            77.700000
        );
        System.assertNotEquals(null, vt.Id);
        System.assertEquals(true, [SELECT Order_Placed__c FROM Visit_Task__c WHERE Id = :vt.Id].Order_Placed__c);

        User u2 = UserTrackingTestDataFactory.createStandardUser('utd_visitonly');
        UserTrackingTestDataFactory.createVisitOnly(u2.Id, d.addDays(1), false);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Visit_Task__c
                WHERE Visitor_Name__c = :u2.Id AND Order_Placed__c = FALSE
            ]
        );
    }

    @IsTest
    static void testCreateOrder_andAddSecondOrderForVisit() {
        UserTrackingTestDataFactory.ScenarioData data = UserTrackingTestDataFactory.getScenario();

        Order__c first = [
            SELECT Id, Total_Order_Value__c
            FROM Order__c
            WHERE Visit_Task__c = :data.productiveVisitId
            LIMIT 1
        ];
        System.assertEquals(500, first.Total_Order_Value__c);

        UserTrackingTestDataFactory.addSecondOrderForVisit(
            data.productiveVisitId,
            data.userId,
            data.selectedDate,
            250
        );

        Decimal total = 0;
        for (Order__c o : [
            SELECT Total_Order_Value__c
            FROM Order__c
            WHERE Visit_Task__c = :data.productiveVisitId
        ]) {
            total += o.Total_Order_Value__c;
        }
        System.assertEquals(750, total);
    }

    @IsTest
    static void testCreateOrder_standalone() {
        User u = UserTrackingTestDataFactory.createStandardUser('utd_order');
        Date d = Date.today().addDays(-2);
        Account outlet = UserTrackingTestDataFactory.createRetailerAccount('UTD Order Outlet');
        Visit_Task__c vt = UserTrackingTestDataFactory.createVisitTask(
            u.Id,
            d,
            outlet.Id,
            true,
            DateTime.newInstance(d, Time.newInstance(11, 0, 0, 0)),
            13.02,
            77.62
        );

        Order__c ord = UserTrackingTestDataFactory.createOrder(vt.Id, u.Id, d, outlet.Id, 99);
        System.assertNotEquals(null, ord.Id);
        System.assertEquals(99, [SELECT Total_Order_Value__c FROM Order__c WHERE Id = :ord.Id].Total_Order_Value__c);
    }

    @IsTest
    static void testScenarioData_fieldsAssignable() {
        UserTrackingTestDataFactory.ScenarioData data = new UserTrackingTestDataFactory.ScenarioData();
        User u = UserTrackingTestDataFactory.createStandardUser('utd_scenario');
        data.userId = u.Id;
        data.selectedDate = Date.today();
        data.productiveVisitId = u.Id;
        data.attendanceId = u.Id;

        System.assertEquals(u.Id, data.userId);
        System.assertEquals(Date.today(), data.selectedDate);
        System.assertEquals(u.Id, data.productiveVisitId);
        System.assertEquals(u.Id, data.attendanceId);
    }
}