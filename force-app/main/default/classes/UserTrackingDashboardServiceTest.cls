@IsTest
private class UserTrackingDashboardServiceTest {
    private static void clearCustomSettingTestOverrides() {
        UserTrackingController.testDashboardAccessOverride = null;
        UserTrackingController.testGoogleApiUserTrackingConfigUnavailable = null;
        UserTrackingController.testDashboardAccessRolesOverride = null;
    }

    private static void assertDashboardAccessDeniedException(Exception e) {
        System.assertNotEquals(null, e, 'Expected an exception when access is denied');
        String msg = e.getMessage() != null ? e.getMessage() : '';
        Boolean denied =
            UserTrackingController.DASHBOARD_ACCESS_DENIED_MESSAGE.equals(msg)
            || 'Script-thrown exception'.equals(msg)
            || msg.contains('do not have access')
            || msg.contains('User Tracking Dashboard');
        System.assert(
            denied,
            'Expected dashboard access denial. type=' + e.getTypeName() + ' msg=' + msg
        );
    }

    private static final String TEST_USER_EMAIL_DOMAIN = 'sales.hangyo.in';

    private static User createStandardUserForTest(String aliasPrefix) {
        return createStandardUserForTest(aliasPrefix, null);
    }

    /** Org requires User.Email in sales.hangyo.in / hangyo.in / hangyo.com — not @example.com. */
    private static User createStandardUserForTest(String aliasPrefix, String employeeRole) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String token = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        String localPart = aliasPrefix + token;
        User u = new User(
            Alias = (aliasPrefix + token).left(8),
            Email = localPart + '@' + TEST_USER_EMAIL_DOMAIN,
            EmailEncodingKey = 'UTF-8',
            LastName = 'TrackingTest',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = localPart + '@' + TEST_USER_EMAIL_DOMAIN + '.qa'
        );
        if (
            String.isNotBlank(employeeRole) &&
            Schema.SObjectType.User.fields.getMap().containsKey('Employee_Role__c')
        ) {
            u.put('Employee_Role__c', employeeRole.trim());
        }
        insert u;
        return u;
    }

    private static Datetime resolveAttendanceLifecycleAnchorForTest(Attendance__c att, Date onDate) {
        if (att == null) {
            return DateTime.newInstance(onDate, Time.newInstance(8, 0, 0, 0));
        }
        if (att.Attendance_Applied_on__c != null) {
            return att.Attendance_Applied_on__c;
        }
        if (att.CreatedDate != null) {
            return att.CreatedDate;
        }
        return DateTime.newInstance(onDate, Time.newInstance(8, 0, 0, 0));
    }

    private static void setupDashboardScenarioForTest() {
        UserTrackingTestDataFactory.ensureRetailerCodeSetting();
        User runUser = createStandardUserForTest('utd_main');
        Date selectedDate = Date.today();

        Account outlet = UserTrackingTestDataFactory.createRetailerAccount(
            'UTD Outlet ' + String.valueOf(Crypto.getRandomInteger())
        );
        Attendance__c att = UserTrackingTestDataFactory.createAttendance(
            runUser.Id,
            selectedDate,
            'Present',
            'HQ check-in notes',
            12.989024,
            77.592635,
            false,
            null,
            null
        );

        att = [
            SELECT Attendance_Applied_on__c, Date_of_attendance__c, CreatedDate
            FROM Attendance__c
            WHERE Id = :att.Id
            LIMIT 1
        ];
        Datetime lifecycleAnchor = resolveAttendanceLifecycleAnchorForTest(att, selectedDate);

        att.EOD_Date_Time__c = lifecycleAnchor.addHours(4);
        att.EOD_Location__Latitude__s = 12.988000;
        att.EOD_Location__Longitude__s = 77.590000;
        update att;

        Visit_Task__c productive = UserTrackingTestDataFactory.createVisitTask(
            runUser.Id,
            selectedDate,
            outlet.Id,
            true,
            lifecycleAnchor.addHours(1),
            13.001,
            77.601
        );
        UserTrackingTestDataFactory.createVisitTask(
            runUser.Id,
            selectedDate,
            outlet.Id,
            false,
            lifecycleAnchor.addHours(2),
            13.002,
            77.602
        );

        UserTrackingTestDataFactory.createOrder(
            productive.Id,
            runUser.Id,
            selectedDate,
            outlet.Id,
            500
        );
        System.runAs(runUser) {
            UserTrackingTestDataFactory.createRetailerAccountWithGeo(
                lifecycleAnchor.addHours(3),
                'UTD New Outlet'
            );
        }
    }

    private static UserTrackingTestDataFactory.ScenarioData getTestScenario() {
        User u = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'utd_main%@sales.hangyo.in%'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        Date d = Date.today();
        List<Visit_Task__c> visits = [
            SELECT Id
            FROM Visit_Task__c
            WHERE Visitor_Name__c = :u.Id
              AND Task_Planned_Date__c = :d
            ORDER BY Checked_In_Time__c ASC
            LIMIT 1
        ];
        UserTrackingTestDataFactory.ScenarioData data = new UserTrackingTestDataFactory.ScenarioData();
        data.userId = u.Id;
        data.selectedDate = d;
        data.productiveVisitId = visits.isEmpty() ? null : visits[0].Id;
        List<Attendance__c> atts = [
            SELECT Id
            FROM Attendance__c
            WHERE User__c = :u.Id AND Date_of_attendance__c = :d
            LIMIT 1
        ];
        data.attendanceId = atts.isEmpty() ? null : atts[0].Id;
        return data;
    }

    @TestSetup
    static void setupData() {
        UserTrackingController.ensureGoogleApiUserTrackingOrgDefaultsForTest();
        setupDashboardScenarioForTest();
    }

    @IsTest
    static void testGetUsers_returnsDistinctUsersSorted() {
        UserTrackingController.testDashboardAccessOverride = true;
        Test.startTest();
        List<UserTrackingDashboardService.UserOption> users =
            UserTrackingDashboardService.getUsers();
        Test.stopTest();
        UserTrackingController.testDashboardAccessOverride = null;

        System.assertNotEquals(null, users, 'User list should not be null');
        for (Integer i = 1; i < users.size(); i++) {
            String prev = users[i - 1].name != null ? users[i - 1].name.toLowerCase() : '';
            String cur = users[i].name != null ? users[i].name.toLowerCase() : '';
            System.assert(prev.compareTo(cur) <= 0, 'Users should be sorted by name');
        }
    }

    @IsTest
    static void testGetDashboardData_fullDayScenario() {
        UserTrackingTestDataFactory.ScenarioData data = getTestScenario();
        System.assertNotEquals(null, data, 'Test data should be created in setup');

        UserTrackingController.testDashboardAccessOverride = true;
        Test.startTest();
        UserTrackingDashboardService.TrackingDashboardResponse resp =
            UserTrackingDashboardService.getDashboardData(data.userId, data.selectedDate);
        Test.stopTest();
        UserTrackingController.testDashboardAccessOverride = null;

        System.assertNotEquals(null, resp);
        System.assertNotEquals(null, resp.summary);
        System.assertNotEquals(null, resp.activities);

        UserTrackingDashboardService.DashboardSummary s = resp.summary;
        System.assertEquals(data.userId, s.userId);
        System.assertEquals(1, s.attendanceCount, 'One attendance row');
        System.assertEquals(1, s.eodCount, 'One EOD activity when EOD location is set');
        System.assertEquals(1, s.totalProductiveOutlets);
        System.assertEquals(1, s.totalNonProductiveOutlets);
        System.assertEquals(1, s.newOutletAdded);
        System.assertEquals(500, s.totalOrderValue, 'Order value summed per visit task');
        System.assertEquals(3, s.totalVisitedOutlets);

        Boolean sawAttendance = false;
        Boolean sawEod = false;
        Boolean sawProductive = false;
        Boolean sawNonProductive = false;
        Boolean sawNewOutlet = false;

        for (UserTrackingDashboardService.TrackingActivityDTO dto : resp.activities) {
            System.assert(dto.sortTime != null, 'Lifecycle activities need sortTime');
            if (dto.activityType == 'Attendance') {
                sawAttendance = true;
                System.assertEquals('Present', dto.attendanceStatus);
                System.assertEquals('HQ check-in notes', dto.attendanceLocationDetail);
            } else if (dto.activityType == 'EOD') {
                sawEod = true;
                System.assertNotEquals(null, dto.eodDateTime);
                System.assert(dto.eodLocationDetail != null && dto.eodLocationDetail.contains(','));
            } else if (dto.activityType == 'Productive Outlet') {
                sawProductive = true;
                System.assertEquals(500, dto.orderValue);
                System.assertEquals(data.productiveVisitId, dto.sourceId);
            } else if (dto.activityType == 'Non Productive Outlet') {
                sawNonProductive = true;
                System.assertEquals(null, dto.orderValue);
            } else if (dto.activityType == 'New Outlet') {
                sawNewOutlet = true;
                System.assertNotEquals(null, dto.onboardDate);
                System.assertEquals(13.050000, dto.latitude);
                System.assertEquals(77.650000, dto.longitude);
                System.assert(
                    dto.newOutletLocationDetail != null &&
                        dto.newOutletLocationDetail.contains(','),
                    'New outlet location from Latitude__c / Longitude__c'
                );
            }
        }

        System.assert(sawAttendance, 'Attendance marker expected');
        System.assert(sawEod, 'EOD marker expected');
        System.assert(sawProductive, 'Productive visit expected');
        System.assert(sawNonProductive, 'Non-productive visit expected');
        System.assert(sawNewOutlet, 'New outlet expected');
        System.assert(resp.summary.rawRowCount >= resp.activities.size(), 'Raw count includes pre-filter rows');
    }

    @IsTest
    static void testGetDashboardData_validateInputs() {
        UserTrackingTestDataFactory.ScenarioData data = getTestScenario();
        Boolean userError = false;
        Boolean dateError = false;

        try {
            UserTrackingDashboardService.getDashboardData(null, data.selectedDate);
        } catch (Exception e) {
            userError = true;
        }
        try {
            UserTrackingDashboardService.getDashboardData(data.userId, null);
        } catch (Exception e) {
            dateError = true;
        }

        System.assert(userError, 'Null user should throw');
        System.assert(dateError, 'Null date should throw');
    }

    @IsTest
    static void testGetDashboardData_noAttendance_lifecycleEmpty() {
        User u = createStandardUserForTest('utd_natt');
        Date d = Date.today().addDays(-30);
        UserTrackingTestDataFactory.createVisitOnly(u.Id, d, false);

        Test.startTest();
        UserTrackingDashboardService.TrackingDashboardResponse resp =
            UserTrackingDashboardService.getDashboardData(u.Id, d);
        Test.stopTest();

        System.assertEquals(0, resp.activities.size(), 'No attendance means lifecycle filter returns empty');
    }

    @IsTest
    static void testGetDashboardData_attendanceCoordsOnly_locationDetail() {
        User u = createStandardUserForTest('utd_coords');
        Date d = Date.today().addDays(-29);
        UserTrackingTestDataFactory.createAttendanceOnly(
            u.Id,
            d,
            'Present',
            26.070460,
            83.179924,
            false
        );

        Test.startTest();
        UserTrackingDashboardService.TrackingDashboardResponse resp =
            UserTrackingDashboardService.getDashboardData(u.Id, d);
        Test.stopTest();

        System.assertEquals(1, resp.activities.size());
        System.assertEquals('Attendance', resp.activities[0].activityType);
        System.assert(
            resp.activities[0].attendanceLocationDetail != null &&
                resp.activities[0].attendanceLocationDetail.contains('26.07046'),
            'Location detail should fall back to lat/lng'
        );
    }

    @IsTest
    static void testGetDashboardData_eodTimeWithoutEodLocation_skipsEodActivity() {
        User u = createStandardUserForTest('utd_noeodloc');
        Date d = Date.today().addDays(-28);
        Attendance__c att = UserTrackingTestDataFactory.createAttendanceOnly(
            u.Id,
            d,
            'Present',
            12.99,
            77.59,
            false
        );
        att.EOD_Date_Time__c = DateTime.newInstance(d, Time.newInstance(18, 0, 0, 0));
        update att;

        Test.startTest();
        UserTrackingDashboardService.TrackingDashboardResponse resp =
            UserTrackingDashboardService.getDashboardData(u.Id, d);
        Test.stopTest();

        System.assertEquals(0, resp.summary.eodCount);
        for (UserTrackingDashboardService.TrackingActivityDTO dto : resp.activities) {
            System.assertNotEquals('EOD', dto.activityType);
        }
    }

    @IsTest
    static void testGetDashboardData_multipleOrdersSummedPerVisit() {
        UserTrackingTestDataFactory.ScenarioData data = getTestScenario();
        UserTrackingTestDataFactory.addSecondOrderForVisit(
            data.productiveVisitId,
            data.userId,
            data.selectedDate,
            150
        );

        Test.startTest();
        UserTrackingDashboardService.TrackingDashboardResponse resp =
            UserTrackingDashboardService.getDashboardData(data.userId, data.selectedDate);
        Test.stopTest();

        System.assertEquals(650, resp.summary.totalOrderValue);
        for (UserTrackingDashboardService.TrackingActivityDTO dto : resp.activities) {
            if (dto.activityType == 'Productive Outlet') {
                System.assertEquals(650, dto.orderValue);
            }
        }
    }

    @IsTest
    static void testGetUsers_directCall_deniedForUnauthorizedRole() {
        User runUser = createStandardUserForTest('utd_svcdeny', 'Sales Executive');
        clearCustomSettingTestOverrides();
        System.runAs(runUser) {
            Exception caught = null;
            Test.startTest();
            try {
                UserTrackingDashboardService.getUsers();
            } catch (Exception e) {
                caught = e;
            }
            Test.stopTest();
            assertDashboardAccessDeniedException(caught);
        }
    }

    @IsTest
    static void testGetDashboardData_directCall_deniedForUnauthorizedRole() {
        User runUser = createStandardUserForTest('utd_svcdeny2', 'Sales Executive');
        UserTrackingTestDataFactory.ScenarioData data = getTestScenario();
        clearCustomSettingTestOverrides();
        System.runAs(runUser) {
            Exception caught = null;
            Test.startTest();
            try {
                UserTrackingDashboardService.getDashboardData(data.userId, data.selectedDate);
            } catch (Exception e) {
                caught = e;
            }
            Test.stopTest();
            assertDashboardAccessDeniedException(caught);
        }
    }

    @IsTest
    static void testGetDashboardData_directCall_deniedForBlankEmployeeRole() {
        User runUser = createStandardUserForTest('utd_svcblank', null);
        UserTrackingTestDataFactory.ScenarioData data = getTestScenario();
        clearCustomSettingTestOverrides();
        System.runAs(runUser) {
            Exception caught = null;
            Test.startTest();
            try {
                UserTrackingDashboardService.getDashboardData(data.userId, data.selectedDate);
            } catch (Exception e) {
                caught = e;
            }
            Test.stopTest();
            assertDashboardAccessDeniedException(caught);
        }
    }

    @IsTest
    static void testGetUsers_directCall_deniedForBlankEmployeeRole() {
        User runUser = createStandardUserForTest('utd_svcusrblank', null);
        clearCustomSettingTestOverrides();
        System.runAs(runUser) {
            Exception caught = null;
            Test.startTest();
            try {
                UserTrackingDashboardService.getUsers();
            } catch (Exception e) {
                caught = e;
            }
            Test.stopTest();
            assertDashboardAccessDeniedException(caught);
        }
    }

    @IsTest
    static void testServiceDirectCall_authorizedRolesCanLoadDashboardData() {
        UserTrackingTestDataFactory.ScenarioData data = getTestScenario();
        List<String> allowedRoles = new List<String>{
            'ADMIN',
            'ZSM',
            'RSM',
            'ASM',
            'SSO'
        };
        for (String roleCode : allowedRoles) {
            User runUser = createStandardUserForTest(
                'utd_svc' + roleCode.toLowerCase(),
                roleCode
            );
            System.runAs(runUser) {
                UserTrackingDashboardService.TrackingDashboardResponse resp =
                    UserTrackingDashboardService.getDashboardData(data.userId, data.selectedDate);
                System.assertNotEquals(null, resp, 'Authorized role should load data: ' + roleCode);
                System.assertNotEquals(null, resp.summary);
            }
        }
    }

    @IsTest
    static void testGetUsers_directCall_authorizedRolesCanLoadUserList() {
        UserTrackingController.testDashboardAccessOverride = null;
        List<String> allowedRoles = new List<String>{ 'ADMIN', 'ZSM', 'RSM', 'ASM', 'SSO' };
        for (String roleCode : allowedRoles) {
            User runUser = createStandardUserForTest(
                'utd_svcusr' + roleCode.toLowerCase(),
                roleCode
            );
            System.runAs(runUser) {
                List<UserTrackingDashboardService.UserOption> users =
                    UserTrackingDashboardService.getUsers();
                System.assertNotEquals(null, users, 'Authorized role should load users: ' + roleCode);
            }
        }
    }

    @IsTest
    static void testGetUsers_directCall_authorizedAsmUser() {
        User runUser = createStandardUserForTest('utd_svcusr', 'ASM');
        clearCustomSettingTestOverrides();
        System.runAs(runUser) {
            Test.startTest();
            List<UserTrackingDashboardService.UserOption> users =
                UserTrackingDashboardService.getUsers();
            Test.stopTest();
            System.assertNotEquals(null, users);
        }
    }

    @IsTest
    static void testServiceDirectCall_deniedForReviewExactRoles() {
        UserTrackingTestDataFactory.ScenarioData data = getTestScenario();
        List<String> deniedRoles = new List<String>{ 'NON-ADMIN', 'SSO-NORTH', 'RSM-EAST' };
        clearCustomSettingTestOverrides();
        for (String roleCode : deniedRoles) {
            User runUser = createStandardUserForTest(
                'utd_den' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                roleCode
            );
            System.runAs(runUser) {
                Exception caught = null;
                try {
                    UserTrackingDashboardService.getDashboardData(data.userId, data.selectedDate);
                } catch (Exception e) {
                    caught = e;
                }
                assertDashboardAccessDeniedException(caught);
            }
        }
    }
}