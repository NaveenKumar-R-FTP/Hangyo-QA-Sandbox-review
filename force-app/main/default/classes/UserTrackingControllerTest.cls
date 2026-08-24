@IsTest
private class UserTrackingControllerTest {
    private static void clearCustomSettingTestOverrides() {
        UserTrackingController.testDashboardAccessOverride = null;
        UserTrackingController.testGoogleApiUserTrackingConfigUnavailable = null;
        UserTrackingController.testDashboardAccessRolesOverride = null;
        UserTrackingController.testDirectionApiAccessRolesOverride = null;
        UserTrackingController.testHaversineAccessRolesOverride = null;
    }

    private static void restoreGoogleApiUserTrackingOrgDefaults() {
        UserTrackingController.ensureGoogleApiUserTrackingOrgDefaultsForTest();
        clearCustomSettingTestOverrides();
    }

    private static Boolean customSettingObjectAvailable() {
        return Schema.getGlobalDescribe().containsKey('google_api_user_tracking__c');
    }

    private static Google_API_User_Tracking__c orgGoogleApiUserTrackingRow() {
        Google_API_User_Tracking__c row = Google_API_User_Tracking__c.getOrgDefaults();
        if (row == null || row.Id == null) {
            row = new Google_API_User_Tracking__c();
            row.SetupOwnerId = UserInfo.getOrganizationId();
        }
        return row;
    }

    /**
     * AuraHandledException.getMessage() in Apex tests often returns "Script-thrown exception"
     * instead of the LWC-facing denial text — accept both as valid access denial.
     */
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
    static void testGetDashboardAccess_runningUserAllowedInTestContext() {
        UserTrackingController.testDashboardAccessOverride = true;
        Test.startTest();
        UserTrackingController.DashboardAccessResult access =
            UserTrackingController.getDashboardAccess();
        Test.stopTest();
        UserTrackingController.testDashboardAccessOverride = null;

        System.assertEquals(true, access.allowed);
    }

    @IsTest
    static void testGetDashboardAccess_deniedWhenOverrideFalse() {
        UserTrackingController.testDashboardAccessOverride = false;
        Test.startTest();
        UserTrackingController.DashboardAccessResult access =
            UserTrackingController.getDashboardAccess();
        Test.stopTest();
        UserTrackingController.testDashboardAccessOverride = null;

        System.assertEquals(false, access.allowed);
    }

    @IsTest
    static void testRoleNameMatchesAllowedCode_exactMatchOnly() {
        System.assert(
            UserTrackingController.roleNameMatchesAllowedCode('ASM'),
            'Exact ASM should match dashboard list'
        );
        System.assert(
            UserTrackingController.roleNameMatchesAllowedCode('zsm'),
            'Case-insensitive exact ZSM should match'
        );
        System.assertEquals(
            false,
            UserTrackingController.roleNameMatchesAllowedCode('ASM-RSM-VP KHP'),
            'Compound role must not match ASM via substring'
        );
        System.assertEquals(
            false,
            UserTrackingController.roleNameMatchesAllowedCode('NON-ADMIN'),
            'NON-ADMIN must not match ADMIN via substring'
        );
    }

    @IsTest
    static void testRoleNameMatchesAllowedCode_unrelatedRole() {
        System.assertEquals(
            false,
            UserTrackingController.roleNameMatchesAllowedCode('Sales Executive')
        );
    }

    @IsTest
    static void testRoleNameMatchesAllowedCode_blankAndPartialRolesDenied() {
        System.assertEquals(false, UserTrackingController.roleNameMatchesAllowedCode(null));
        System.assertEquals(false, UserTrackingController.roleNameMatchesAllowedCode(''));
        System.assertEquals(
            false,
            UserTrackingController.roleNameMatchesAllowedCode('ZSM Karnataka')
        );
        System.assertEquals(false, UserTrackingController.roleNameMatchesAllowedCode('RSM-West'));
        System.assertEquals(false, UserTrackingController.roleNameMatchesAllowedCode('SSO Team'));
        System.assertEquals(false, UserTrackingController.roleNameMatchesAllowedCode('ADMIN Ops'));
        System.assertEquals(
            false,
            UserTrackingController.roleNameMatchesAllowedCode('Territory ASM ASM-2')
        );
        System.assertEquals(
            false,
            UserTrackingController.roleNameMatchesAllowedCode('BASMGR')
        );
    }

    @IsTest
    static void testIsDashboardAccessAllowed_nullUser() {
        UserTrackingController.testDashboardAccessOverride = null;
        System.assertEquals(false, UserTrackingController.isDashboardAccessAllowed(null));
    }

    @IsTest
    static void testGetDashboardAccess_withoutOverride_usesRunningUser() {
        UserTrackingController.testDashboardAccessOverride = null;
        Test.startTest();
        UserTrackingController.DashboardAccessResult access =
            UserTrackingController.getDashboardAccess();
        Test.stopTest();
        System.assertNotEquals(null, access);
        System.assertNotEquals(null, access.profileName);
    }

    @IsTest
    static void testIsDashboardAccessAllowed_employeeRoleAllowed() {
        User runUser = createStandardUserForTest('utd_roleaccess', 'ASM');

        UserTrackingController.testDashboardAccessOverride = null;
        System.runAs(runUser) {
            Test.startTest();
            UserTrackingController.DashboardAccessResult access =
                UserTrackingController.getDashboardAccess();
            Test.stopTest();
            System.assertEquals(true, access.allowed, 'Employee Role ASM should be allowed');
            System.assertEquals('ASM', access.userRoleName);
        }
    }

    /**
     * Replaces legacy UserRole-based org scan: access uses User.Employee_Role__c only.
     */
    @IsTest
    static void testIsDashboardAccessAllowed_compoundRoleDeniedUnlessExactInCsv() {
        User runUser = createStandardUserForTest(
            'utd_roleorg',
            'ASM-RSM-VP KHP'
        );

        UserTrackingController.testDashboardAccessOverride = null;
        System.runAs(runUser) {
            Test.startTest();
            UserTrackingController.DashboardAccessResult access =
                UserTrackingController.getDashboardAccess();
            Test.stopTest();
            System.assertEquals(
                false,
                access.allowed,
                'Compound Employee Role must match CSV entry exactly'
            );
            System.assertEquals('ASM-RSM-VP KHP', access.userRoleName);
        }
    }
    
    @IsTest
    static void testIsDashboardAccessAllowed_employeeRoleDenied() {
        User runUser = createStandardUserForTest(
            'utd_empdeny',
            'Sales Executive'
        );

        UserTrackingController.testDashboardAccessOverride = null;
        System.runAs(runUser) {
            Test.startTest();
            UserTrackingController.DashboardAccessResult access =
                UserTrackingController.getDashboardAccess();
            Test.stopTest();
            System.assertEquals(false, access.allowed, 'Unlisted Employee Role should be denied');
        }
    }

    @IsTest
    static void testGetDashboardAccess_routingModeZsmGetsDirections() {
        User runUser = createStandardUserForTest('utd_rtzsm', 'ZSM');
        UserTrackingController.testDashboardAccessOverride = null;
        System.runAs(runUser) {
            Test.startTest();
            UserTrackingController.DashboardAccessResult access =
                UserTrackingController.getDashboardAccess();
            Test.stopTest();
            System.assertEquals(true, access.allowed);
            System.assertEquals('directions', access.routingMode);
        }
    }

    @IsTest
    static void testGetDashboardAccess_routingModeAsmGetsHaversine() {
        User runUser = createStandardUserForTest('utd_rtasm', 'ASM');
        UserTrackingController.testDashboardAccessOverride = null;
        System.runAs(runUser) {
            Test.startTest();
            UserTrackingController.DashboardAccessResult access =
                UserTrackingController.getDashboardAccess();
            Test.stopTest();
            System.assertEquals(true, access.allowed);
            System.assertEquals('haversine', access.routingMode);
        }
    }

    @IsTest
    static void testRoleCodesFromCustomSetting_defaultsMatchOrgConfig() {
        Set<String> dashboard = UserTrackingController.dashboardAllowedRoleCodes();
        Set<String> directions = UserTrackingController.directionApiAccessRoleCodes();
        Set<String> haversine = UserTrackingController.haversineAccessRoleCodes();

        System.assert(dashboard.contains('ZSM'), 'Dashboard set must include ZSM');
        System.assert(dashboard.contains('ASM'), 'Dashboard set must include ASM');
        System.assert(directions.contains('ZSM'), 'Directions set must include ZSM');
        System.assert(haversine.contains('ASM'), 'Haversine set must include ASM');
        System.assert(!haversine.contains('ZSM'), 'Haversine set should not include ZSM');
    }

    @IsTest
    static void testParseCommaSeparatedRoleCodeSet_whitespaceAndCase() {
        Set<String> parsed = UserTrackingController.parseCommaSeparatedRoleCodeSet(
            ' ADMIN , zsm , ASM ',
            null
        );
        System.assertEquals(3, parsed.size());
        System.assert(parsed.contains('ADMIN'));
        System.assert(parsed.contains('ZSM'));
        System.assert(parsed.contains('ASM'));
    }

    @IsTest
    static void testParseCommaSeparatedRoleCodeSet_blankCsvUsesFallback() {
        Set<String> parsed = UserTrackingController.parseCommaSeparatedRoleCodeSet(
            '',
            'RSM,SSO'
        );
        System.assertEquals(2, parsed.size());
        System.assert(parsed.contains('RSM'));
        System.assert(parsed.contains('SSO'));
    }

    @IsTest
    static void testParseCommaSeparatedRoleCodeSet_nullCsvAndNullFallbackEmpty() {
        Set<String> parsed = UserTrackingController.parseCommaSeparatedRoleCodeSet(null, null);
        System.assertEquals(0, parsed.size());
    }

    @IsTest
    static void testParseCommaSeparatedRoleCodeSet_duplicatesAndBlankSegments() {
        Set<String> parsed = UserTrackingController.parseCommaSeparatedRoleCodeSet(
            'ADMIN,ADMIN, ZSM ,, ,RSM',
            null
        );
        System.assertEquals(3, parsed.size());
        System.assert(parsed.contains('ADMIN'));
        System.assert(parsed.contains('ZSM'));
        System.assert(parsed.contains('RSM'));
    }

    @IsTest
    static void testParseCommaSeparatedRoleCodeSet_mixedCaseRoles() {
        Set<String> parsed = UserTrackingController.parseCommaSeparatedRoleCodeSet(
            'admin, Zsm , rSm',
            null
        );
        System.assertEquals(3, parsed.size());
        System.assert(parsed.contains('ADMIN'));
        System.assert(parsed.contains('ZSM'));
        System.assert(parsed.contains('RSM'));
    }

    @IsTest
    static void testParseCommaSeparatedRoleCodeSet_unknownTokensParsedWithoutGrantingAccess() {
        Set<String> parsed = UserTrackingController.parseCommaSeparatedRoleCodeSet(
            'ADMIN,RMS,XYZ,ZSM',
            null
        );
        System.assertEquals(4, parsed.size());
        System.assert(parsed.contains('RMS'));
        System.assert(parsed.contains('XYZ'));
        System.assert(UserTrackingController.roleNameMatchesAllowedCode('RMS', parsed));
        System.assert(UserTrackingController.roleNameMatchesAllowedCode('ZSM', parsed));
        System.assertEquals(false, UserTrackingController.roleNameMatchesAllowedCode('ASM', parsed));
        System.assertEquals(false, UserTrackingController.roleNameMatchesAllowedCode('RSM', parsed));
    }

    @IsTest
    static void testResolveConfiguredRoleCodes_blankFieldUsesFallback() {
        Set<String> codes = UserTrackingController.resolveConfiguredRoleCodes(
            '',
            'ADMIN,ZSM,RSM',
            'Dashboard_Access_Roles__c'
        );
        System.assertEquals(3, codes.size());
        System.assert(codes.contains('ZSM'));
    }

    @IsTest
    static void testResolveConfiguredRoleCodes_nullFieldUsesFallback() {
        Set<String> codes = UserTrackingController.resolveConfiguredRoleCodes(
            null,
            'ASM,SSO',
            'Haversine_Access_Roles__c'
        );
        System.assertEquals(2, codes.size());
        System.assert(codes.contains('ASM'));
    }

    @IsTest
    static void testResolveConfiguredRoleCodes_emptyResultDeniesAccess() {
        Set<String> codes = UserTrackingController.resolveConfiguredRoleCodes(
            '',
            '',
            'Dashboard_Access_Roles__c'
        );
        System.assertEquals(0, codes.size());
        System.assertEquals(
            false,
            UserTrackingController.roleNameMatchesAllowedCode('ASM', codes)
        );
    }

    @IsTest
    static void testDashboardAccess_missingCustomSettingUsesFallbackWithoutNpe() {
        UserTrackingController.testGoogleApiUserTrackingConfigUnavailable = true;
        UserTrackingController.testDashboardAccessRolesOverride = null;
        User runUser = createStandardUserForTest('utd_cs_miss', 'ASM');
        UserTrackingController.testDashboardAccessOverride = null;
        System.runAs(runUser) {
            Test.startTest();
            Set<String> codes = UserTrackingController.dashboardAllowedRoleCodes();
            UserTrackingController.DashboardAccessResult access =
                UserTrackingController.getDashboardAccess();
            Test.stopTest();
            System.assert(codes.contains('ASM'), 'Missing CS should fall back to default dashboard roles');
            System.assertEquals(true, access.allowed);
        }
        UserTrackingController.testGoogleApiUserTrackingConfigUnavailable = null;
    }

    @IsTest
    static void testDashboardAccess_blankCustomSettingUsesFallback() {
        UserTrackingController.testDashboardAccessRolesOverride = '';
        User runUser = createStandardUserForTest('utd_cs_blank', 'ZSM');
        UserTrackingController.testDashboardAccessOverride = null;
        System.runAs(runUser) {
            Test.startTest();
            UserTrackingController.DashboardAccessResult access =
                UserTrackingController.getDashboardAccess();
            Test.stopTest();
            System.assertEquals(true, access.allowed);
            System.assertEquals('directions', access.routingMode);
        }
        UserTrackingController.testDashboardAccessRolesOverride = null;
    }

    @IsTest
    static void testDashboardAccess_restrictedCsvDeniesUnauthorizedRole() {
        UserTrackingController.testDashboardAccessRolesOverride = 'ADMIN,ZSM';
        User runUser = createStandardUserForTest('utd_cs_deny', 'ASM');
        UserTrackingController.testDashboardAccessOverride = null;
        System.runAs(runUser) {
            Test.startTest();
            UserTrackingController.DashboardAccessResult access =
                UserTrackingController.getDashboardAccess();
            Test.stopTest();
            System.assertEquals(false, access.allowed);
        }
        UserTrackingController.testDashboardAccessRolesOverride = null;
    }

    @IsTest
    static void testReadCustomSettingRoleCsv_nullConfigReturnsNullSafely() {
        String raw = UserTrackingController.readCustomSettingRoleCsv(
            null,
            null,
            'Dashboard_Access_Roles__c'
        );
        System.assertEquals(null, raw);
        Set<String> codes = UserTrackingController.resolveConfiguredRoleCodes(
            raw,
            'ADMIN',
            'Dashboard_Access_Roles__c'
        );
        System.assert(codes.contains('ADMIN'));
    }

    @IsTest
    static void testUsesGoogleDirectionsRouting_asmRsmVpKhpIsHaversine() {
        User runUser = createStandardUserForTest(
            'utd_rthav',
            'ASM-RSM-VP KHP'
        );
        System.runAs(runUser) {
            System.assertEquals(
                false,
                UserTrackingController.usesGoogleDirectionsRouting(runUser)
            );
        }
    }

    @IsTest
    static void testInnerClassConstructors() {
        UserTrackingController.testDashboardAccessOverride = true;
        Id uid = UserInfo.getUserId();
        UserTrackingController.UserOption opt = new UserTrackingController.UserOption(uid, 'Test User');
        System.assertEquals(uid, opt.id);
        System.assertEquals('Test User', opt.name);

        UserTrackingController.DashboardSummary summary = new UserTrackingController.DashboardSummary();
        summary.userId = uid;
        summary.userName = 'Test User';
        summary.totalProductiveOutlets = 1;
        System.assertEquals(1, summary.totalProductiveOutlets);

        UserTrackingController.DashboardAccessResult accessResult =
            new UserTrackingController.DashboardAccessResult(
                true,
                'ASM-RSM',
                'SFA Profile',
                'haversine'
            );
        System.assertEquals(true, accessResult.allowed);
        UserTrackingController.testDashboardAccessOverride = null;
    }

    @IsTest
    static void testGetDashboardData_throwsWhenAccessDenied() {
        User runUser = createStandardUserForTest('utd_ctldeny', 'Sales Executive');
        UserTrackingTestDataFactory.ScenarioData data = getTestScenario();
        clearCustomSettingTestOverrides();
        System.runAs(runUser) {
            Exception caught = null;
            Test.startTest();
            try {
                UserTrackingController.getDashboardData(data.userId, data.selectedDate);
            } catch (Exception e) {
                caught = e;
            }
            Test.stopTest();
            assertDashboardAccessDeniedException(caught);
        }
    }

    @IsTest
    static void testGetUsers_throwsWhenAccessDenied() {
        User runUser = createStandardUserForTest('utd_ctlusr', 'Sales Executive');
        clearCustomSettingTestOverrides();
        System.runAs(runUser) {
            Exception caught = null;
            Test.startTest();
            try {
                UserTrackingController.getUsers();
            } catch (Exception e) {
                caught = e;
            }
            Test.stopTest();
            assertDashboardAccessDeniedException(caught);
        }
    }

    @IsTest
    static void testGetUsers_delegatesToService() {
        UserTrackingController.testDashboardAccessOverride = true;
        Test.startTest();
        List<UserTrackingController.UserOption> users = UserTrackingController.getUsers();
        Test.stopTest();
        UserTrackingController.testDashboardAccessOverride = null;

        System.assertNotEquals(null, users);
        if (!users.isEmpty()) {
            System.assertNotEquals(null, users[0].id);
        }
    }

    @IsTest
    static void testGetDashboardData_delegatesToService() {
        UserTrackingController.testDashboardAccessOverride = true;
        UserTrackingTestDataFactory.ScenarioData data = getTestScenario();

        Test.startTest();
        UserTrackingDashboardService.TrackingDashboardResponse resp =
            UserTrackingController.getDashboardData(data.userId, data.selectedDate);
        Test.stopTest();

        System.assertNotEquals(null, resp);
        System.assertNotEquals(null, resp.summary);
        System.assertNotEquals(null, resp.activities);
        System.assert(resp.activities.size() > 0);
        UserTrackingController.testDashboardAccessOverride = null;
    }

    @IsTest
    static void testGetUserTrackingMapEmbedUrl_containsPageAndVersion() {
        UserTrackingController.testDashboardAccessOverride = true;
        UserTrackingController.testMapAuthorityHostOverride = null;
        Test.startTest();
        String url = UserTrackingController.getUserTrackingMapEmbedUrl();
        String pagePath = Page.UserTrackingMapEmbed.getUrl();
        Test.stopTest();

        System.assertNotEquals(null, url);
        System.assert(url.startsWith('https://'), 'Should be absolute URL');
        System.assert(url.contains('hmv=iwHangyo26'), 'Should include asset version param');
        System.assert(
            !url.contains('hpo=%2A') && !url.contains('hpo=*'),
            'Embed URL must not pass wildcard postMessage origin'
        );
        System.assert(
            url.toLowerCase().contains('usertrackingmapembed') ||
                (!String.isBlank(pagePath) && url.contains(pagePath)),
            'Should reference VF page. url=' + url + ' pagePath=' + pagePath
        );
        UserTrackingController.testDashboardAccessOverride = null;
    }

    @IsTest
    static void testGetUserTrackingMapIframePostMessageOrigin_returnsString() {
        UserTrackingController.testDashboardAccessOverride = true;
        Test.startTest();
        String origin = UserTrackingController.getUserTrackingMapIframePostMessageOrigin();
        Test.stopTest();

        System.assertNotEquals(null, origin);
        UserTrackingController.testDashboardAccessOverride = null;
    }

    @IsTest
    static void testGetGoogleMapsJavaScriptApiKey_returnsTrimmedLabel() {
        UserTrackingController.testDashboardAccessOverride = true;
        Test.startTest();
        String key = UserTrackingController.getGoogleMapsJavaScriptApiKey();
        Test.stopTest();

        System.assertNotEquals(null, key);
        UserTrackingController.testDashboardAccessOverride = null;
    }

    @IsTest
    static void testMapUrlHelpers_sandboxLightningHost() {
        UserTrackingController.testDashboardAccessOverride = true;
        UserTrackingController.testMapAuthorityHostOverride = 'acme.sandbox.lightning.force.com';
        Test.startTest();
        String url = UserTrackingController.getUserTrackingMapEmbedUrl();
        Test.stopTest();
        System.assert(url.contains('sandbox.my.salesforce.com'), 'LEX host should map to my.salesforce sandbox');
        System.assert(
            url.contains('hpo=') && url.contains('sandbox.lightning.force.com'),
            'Embed URL should include trusted LEX parent origin'
        );
        UserTrackingController.testMapAuthorityHostOverride = null;
        UserTrackingController.testDashboardAccessOverride = null;
    }

    @IsTest
    static void testMapUrlHelpers_productionLightningHost() {
        UserTrackingController.testDashboardAccessOverride = true;
        UserTrackingController.testMapAuthorityHostOverride = 'acme.lightning.force.com';
        Test.startTest();
        String url = UserTrackingController.getUserTrackingMapEmbedUrl();
        Test.stopTest();
        System.assert(url.contains('acme.my.salesforce.com'), 'LEX host should map to my.salesforce');
        System.assert(url.contains('hpo=') && url.contains('acme.lightning.force.com'));
        UserTrackingController.testMapAuthorityHostOverride = null;
        UserTrackingController.testDashboardAccessOverride = null;
    }

    @IsTest
    static void testMapUrlHelpers_sandboxMySalesforceVfOrigin() {
        UserTrackingController.testDashboardAccessOverride = true;
        UserTrackingController.testMapAuthorityHostOverride = 'acme.sandbox.my.salesforce.com';
        Test.startTest();
        String origin = UserTrackingController.getUserTrackingMapIframePostMessageOrigin();
        Test.stopTest();
        System.assertEquals('https://acme--c.sandbox.vf.force.com', origin);
        UserTrackingController.testMapAuthorityHostOverride = null;
        UserTrackingController.testDashboardAccessOverride = null;
    }

    @IsTest
    static void testMapUrlHelpers_productionMySalesforceVfOrigin() {
        UserTrackingController.testDashboardAccessOverride = true;
        UserTrackingController.testMapAuthorityHostOverride = 'acme.my.salesforce.com';
        Test.startTest();
        String origin = UserTrackingController.getUserTrackingMapIframePostMessageOrigin();
        Test.stopTest();
        System.assertEquals('https://acme--c.vf.force.com', origin);
        UserTrackingController.testMapAuthorityHostOverride = null;
        UserTrackingController.testDashboardAccessOverride = null;
    }

    @IsTest
    static void testMapUrlHelpers_unrecognizedHostReturnsEmptyOrigin() {
        UserTrackingController.testDashboardAccessOverride = true;
        /* Empty override is ignored (isBlank); use a host that does not map to VF origin. */
        UserTrackingController.testMapAuthorityHostOverride = 'unknown.example.com';
        Test.startTest();
        String origin = UserTrackingController.getUserTrackingMapIframePostMessageOrigin();
        Test.stopTest();
        System.assertEquals('', origin);
        UserTrackingController.testMapAuthorityHostOverride = null;
        UserTrackingController.testDashboardAccessOverride = null;
    }

    @IsTest
    static void testMapUrlHelpers_trailingSlashesAndEmbedUrl() {
        UserTrackingController.testDashboardAccessOverride = true;
        UserTrackingController.testMapAuthorityHostOverride = 'acme.my.salesforce.com///';
        Test.startTest();
        String url = UserTrackingController.getUserTrackingMapEmbedUrl();
        String origin = UserTrackingController.getUserTrackingMapIframePostMessageOrigin();
        Test.stopTest();
        System.assert(url.contains('hmv=iwHangyo26'));
        System.assert(url.contains('acme.my.salesforce.com'));
        System.assertEquals('https://acme--c.vf.force.com', origin);
        UserTrackingController.testMapAuthorityHostOverride = null;
        UserTrackingController.testDashboardAccessOverride = null;
    }

    @IsTest
    static void testMapUrlHelpers_blankHostUsesBaseUrl() {
        UserTrackingController.testDashboardAccessOverride = true;
        UserTrackingController.testMapAuthorityHostOverride = '///';
        Test.startTest();
        String url = UserTrackingController.getUserTrackingMapEmbedUrl();
        Test.stopTest();
        System.assertNotEquals(null, url);
        System.assert(url.contains('UserTrackingMapEmbed') || url.contains('usertrackingmapembed'));
        UserTrackingController.testMapAuthorityHostOverride = null;
        UserTrackingController.testDashboardAccessOverride = null;
    }

    @IsTest
    static void testMapUrlHelpers_sandboxMyDomainNotConfusedWithProductionVf() {
        UserTrackingController.testDashboardAccessOverride = true;
        UserTrackingController.testMapAuthorityHostOverride = 'tenant.sandbox.my.salesforce.com';
        Test.startTest();
        String origin = UserTrackingController.getUserTrackingMapIframePostMessageOrigin();
        Test.stopTest();
        System.assertEquals('https://tenant--c.sandbox.vf.force.com', origin);
        UserTrackingController.testMapAuthorityHostOverride = null;
        UserTrackingController.testDashboardAccessOverride = null;
    }

    @IsTest
    static void testGetUserTrackingMapParentPostMessageOrigin_sandboxMySalesforce() {
        UserTrackingController.testDashboardAccessOverride = true;
        UserTrackingController.testMapAuthorityHostOverride = 'acme.sandbox.my.salesforce.com';
        Test.startTest();
        String origin = UserTrackingController.getUserTrackingMapParentPostMessageOrigin();
        Test.stopTest();
        System.assertEquals('https://acme.sandbox.lightning.force.com', origin);
        UserTrackingController.testMapAuthorityHostOverride = null;
        UserTrackingController.testDashboardAccessOverride = null;
    }

    @IsTest
    static void testGetUserTrackingMapParentPostMessageOrigin_productionMySalesforce() {
        UserTrackingController.testDashboardAccessOverride = true;
        UserTrackingController.testMapAuthorityHostOverride = 'acme.my.salesforce.com';
        Test.startTest();
        String origin = UserTrackingController.getUserTrackingMapParentPostMessageOrigin();
        Test.stopTest();
        System.assertEquals('https://acme.lightning.force.com', origin);
        UserTrackingController.testMapAuthorityHostOverride = null;
        UserTrackingController.testDashboardAccessOverride = null;
    }

    @IsTest
    static void testGetUserTrackingMapParentPostMessageOrigin_unrecognizedHostEmpty() {
        UserTrackingController.testDashboardAccessOverride = true;
        UserTrackingController.testMapAuthorityHostOverride = 'unknown.example.com';
        Test.startTest();
        String origin = UserTrackingController.getUserTrackingMapParentPostMessageOrigin();
        Test.stopTest();
        System.assertEquals('', origin);
        UserTrackingController.testMapAuthorityHostOverride = null;
        UserTrackingController.testDashboardAccessOverride = null;
    }

    @IsTest
    static void testIsTrustedSalesforceOrigin_validHosts() {
        System.assert(
            UserTrackingController.isTrustedSalesforceOrigin(
                'https://acme--c.sandbox.vf.force.com'
            )
        );
        System.assert(
            UserTrackingController.isTrustedSalesforceOrigin('https://acme--c.vf.force.com')
        );
        System.assert(
            UserTrackingController.isTrustedSalesforceOrigin(
                'https://acme.sandbox.lightning.force.com'
            )
        );
        System.assert(
            UserTrackingController.isTrustedSalesforceOrigin('https://acme.lightning.force.com')
        );
        System.assert(
            UserTrackingController.isTrustedSalesforceOrigin('https://acme.my.salesforce.com')
        );
        System.assert(
            UserTrackingController.isTrustedSalesforceOrigin(
                'https://acme.sandbox.my.salesforce.com'
            )
        );
    }

    @IsTest
    static void testIsTrustedSalesforceOrigin_rejectsSpoofedAndInvalid() {
        System.assertEquals(false, UserTrackingController.isTrustedSalesforceOrigin(null));
        System.assertEquals(false, UserTrackingController.isTrustedSalesforceOrigin(''));
        System.assertEquals(
            false,
            UserTrackingController.isTrustedSalesforceOrigin('https://fake-force.com')
        );
        System.assertEquals(
            false,
            UserTrackingController.isTrustedSalesforceOrigin('https://malicious-force.com')
        );
        System.assertEquals(
            false,
            UserTrackingController.isTrustedSalesforceOrigin(
                'https://test.salesforce.com.attacker.com'
            )
        );
        System.assertEquals(
            false,
            UserTrackingController.isTrustedSalesforceOrigin('http://acme.lightning.force.com')
        );
        System.assertEquals(
            false,
            UserTrackingController.isTrustedSalesforceOrigin('not-a-valid-url')
        );
    }

    @IsTest
    static void testIsTrustedSalesforceHostname_rejectsGenericForceSuffix() {
        System.assertEquals(false, UserTrackingController.isTrustedSalesforceHostname('evil.force.com'));
        System.assertEquals(
            false,
            UserTrackingController.isTrustedSalesforceHostname('fake-force.com')
        );
    }

    @IsTest
    static void testGetGoogleMapsJavaScriptApiKey_throwsWhenAccessDenied() {
        User runUser = createStandardUserForTest('utd_ctlkey', 'Sales Executive');
        clearCustomSettingTestOverrides();
        System.runAs(runUser) {
            Exception caught = null;
            Test.startTest();
            try {
                UserTrackingController.getGoogleMapsJavaScriptApiKey();
            } catch (Exception e) {
                caught = e;
            }
            Test.stopTest();
            assertDashboardAccessDeniedException(caught);
        }
    }

    @IsTest
    static void testGetUserTrackingMapEmbedUrl_throwsWhenAccessDenied() {
        User runUser = createStandardUserForTest('utd_ctlemb', 'Sales Executive');
        clearCustomSettingTestOverrides();
        System.runAs(runUser) {
            Exception caught = null;
            Test.startTest();
            try {
                UserTrackingController.getUserTrackingMapEmbedUrl();
            } catch (Exception e) {
                caught = e;
            }
            Test.stopTest();
            assertDashboardAccessDeniedException(caught);
        }
    }

    @IsTest
    static void testServiceGetUsers_throwsWhenAccessDenied() {
        User runUser = createStandardUserForTest('utd_svcgusr', 'Sales Executive');
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
    static void testServiceGetDashboardData_throwsWhenAccessDenied() {
        User runUser = createStandardUserForTest('utd_svcdeny3', 'Sales Executive');
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
    static void testExactRoleMatching_reviewDeniedRoles() {
        List<String> denied = new List<String>{ 'NON-ADMIN', 'SSO-NORTH', 'RSM-EAST' };
        for (String roleCode : denied) {
            System.assertEquals(
                false,
                UserTrackingController.roleNameMatchesAllowedCode(roleCode),
                'Role must not match via substring: ' + roleCode
            );
        }
    }

    @IsTest
    static void testExactRoleMatching_reviewAllowedRoles() {
        List<String> allowed = new List<String>{ 'ADMIN', 'ZSM', 'RSM', 'ASM', 'SSO' };
        for (String roleCode : allowed) {
            System.assert(
                UserTrackingController.roleNameMatchesAllowedCode(roleCode),
                'Exact role should match dashboard list: ' + roleCode
            );
        }
    }

    @IsTest
    static void testGetDashboardAccess_allAuthorizedEmployeeRolesAllowed() {
        List<String> allowedRoles = new List<String>{ 'ADMIN', 'ZSM', 'RSM', 'ASM', 'SSO' };
        clearCustomSettingTestOverrides();
        for (String roleCode : allowedRoles) {
            User runUser = createStandardUserForTest(
                'utd_all' + roleCode.toLowerCase(),
                roleCode
            );
            System.runAs(runUser) {
                UserTrackingController.DashboardAccessResult access =
                    UserTrackingController.getDashboardAccess();
                System.assertEquals(true, access.allowed, 'Role should be allowed: ' + roleCode);
                System.assertEquals(roleCode, access.userRoleName);
            }
        }
    }

    @IsTest
    static void testGetDashboardAccess_unauthorizedRoleDeniedWithoutOverride() {
        User runUser = createStandardUserForTest('utd_unauth', 'Sales Executive');
        clearCustomSettingTestOverrides();
        System.runAs(runUser) {
            UserTrackingController.DashboardAccessResult access =
                UserTrackingController.getDashboardAccess();
            System.assertEquals(false, access.allowed);
            System.assertEquals('Sales Executive', access.userRoleName);
        }
    }

    @IsTest
    static void testRestrictedCustomSetting_runAsDeniedUserThrowsOnControllerMethods() {
        UserTrackingController.testDashboardAccessRolesOverride = 'ADMIN,ZSM';
        User runUser = createStandardUserForTest('utd_csrest', 'ASM');
        UserTrackingTestDataFactory.ScenarioData data = getTestScenario();
        System.runAs(runUser) {
            UserTrackingController.DashboardAccessResult access =
                UserTrackingController.getDashboardAccess();
            System.assertEquals(false, access.allowed);

            Exception usersEx = null;
            try {
                UserTrackingController.getUsers();
            } catch (Exception e) {
                usersEx = e;
            }
            assertDashboardAccessDeniedException(usersEx);

            Exception dataEx = null;
            try {
                UserTrackingController.getDashboardData(data.userId, data.selectedDate);
            } catch (Exception e) {
                dataEx = e;
            }
            assertDashboardAccessDeniedException(dataEx);
        }
        UserTrackingController.testDashboardAccessRolesOverride = null;
    }

    @IsTest
    static void testCustomSettingRecord_whitespaceMixedCaseAndDuplicates() {
        if (!customSettingObjectAvailable()) {
            return;
        }
        clearCustomSettingTestOverrides();
        Google_API_User_Tracking__c row = orgGoogleApiUserTrackingRow();
        row.Dashboard_Access_Roles__c = ' ADMIN , zsm , ASM ,ADMIN, ,ZSM';
        row.Direction_API_Access_Roles__c = ' zSm ';
        row.Haversine_Access_Roles__c = ' admin , RSM ,SSO,SSO';
        upsert row;

        Set<String> dashboard = UserTrackingController.dashboardAllowedRoleCodes();
        Set<String> directions = UserTrackingController.directionApiAccessRoleCodes();
        Set<String> haversine = UserTrackingController.haversineAccessRoleCodes();

        System.assertEquals(3, dashboard.size());
        System.assert(dashboard.contains('ADMIN'));
        System.assert(dashboard.contains('ZSM'));
        System.assert(dashboard.contains('ASM'));
        System.assertEquals(1, directions.size());
        System.assert(directions.contains('ZSM'));
        System.assertEquals(3, haversine.size());
        System.assert(haversine.contains('ADMIN'));
        System.assert(haversine.contains('RSM'));
        System.assert(haversine.contains('SSO'));

        restoreGoogleApiUserTrackingOrgDefaults();
    }

    @IsTest
    static void testCustomSettingRecord_blankFieldsUseFallbackWithoutNpe() {
        if (!customSettingObjectAvailable()) {
            return;
        }
        clearCustomSettingTestOverrides();
        Google_API_User_Tracking__c row = orgGoogleApiUserTrackingRow();
        row.Dashboard_Access_Roles__c = '';
        row.Direction_API_Access_Roles__c = '';
        row.Haversine_Access_Roles__c = '';
        upsert row;

        Set<String> dashboard = UserTrackingController.dashboardAllowedRoleCodes();
        System.assert(dashboard.contains('ASM'), 'Blank dashboard CSV should use org default fallback');
        System.assert(dashboard.contains('ZSM'));
        System.assert(UserTrackingController.roleNameMatchesAllowedCode('ASM', dashboard));

        restoreGoogleApiUserTrackingOrgDefaults();
    }

    @IsTest
    static void testCustomSettingRecord_nullFieldValuesUseFallbackWithoutNpe() {
        if (!customSettingObjectAvailable()) {
            return;
        }
        clearCustomSettingTestOverrides();
        Google_API_User_Tracking__c row = orgGoogleApiUserTrackingRow();
        row.Dashboard_Access_Roles__c = null;
        row.Direction_API_Access_Roles__c = null;
        row.Haversine_Access_Roles__c = null;
        upsert row;

        Set<String> dashboard = UserTrackingController.dashboardAllowedRoleCodes();
        System.assert(!dashboard.isEmpty(), 'Null CSV should fall back without NPE');
        System.assert(dashboard.contains('SSO'));

        restoreGoogleApiUserTrackingOrgDefaults();
    }

    @IsTest
    static void testCustomSettingRecord_missingHierarchyRowUsesFallbackWithoutNpe() {
        UserTrackingController.testGoogleApiUserTrackingConfigUnavailable = true;
        UserTrackingController.testDashboardAccessRolesOverride = null;
        Set<String> dashboard = UserTrackingController.dashboardAllowedRoleCodes();
        System.assert(dashboard.contains('ADMIN'));
        System.assert(dashboard.contains('ASM'));
        UserTrackingController.testGoogleApiUserTrackingConfigUnavailable = null;
    }
}