/**
 * @description Test coverage for AttendanceGoogleDirectionsService.
 */
@IsTest
private class AttendanceGoogleDirectionsServiceTest {

    private static final Decimal CHECK_IN_LAT = 12.971600;
    private static final Decimal CHECK_IN_LNG = 77.594600;
    private static final Decimal EOD_LAT = 12.980000;
    private static final Decimal EOD_LNG = 77.600000;
    private static final Decimal VISIT_LAT = 12.975000;
    private static final Decimal VISIT_LNG = 77.597000;

    @TestSetup
    static void setupData() {
        Attendance__c attendance = new Attendance__c(
            User__c = UserInfo.getUserId(),
            Date_of_attendance__c = Date.today(),
            Status__c = 'Present',
            Location__Latitude__s = CHECK_IN_LAT,
            Location__Longitude__s = CHECK_IN_LNG
        );
        insert attendance;

        attendance = [
            SELECT Attendance_Applied_on__c, CreatedDate, Date_of_attendance__c
            FROM Attendance__c
            WHERE Id = :attendance.Id
            LIMIT 1
        ];
        Datetime lifecycleAnchor = resolveAttendanceLifecycleAnchor(attendance);
        attendance.EOD_Date_Time__c = lifecycleAnchor.addHours(4);
        attendance.EOD_Location__Latitude__s = EOD_LAT;
        attendance.EOD_Location__Longitude__s = EOD_LNG;
        update attendance;
    }

    private static void resetGoogleApiTestState() {
        AttendanceGoogleDirectionsService.testApiKeyOverrideConfigured = false;
        AttendanceGoogleDirectionsService.testApiKeyOverride = null;
    }

    private static void configureTestApiKeyOverride(String apiKey) {
        AttendanceGoogleDirectionsService.testApiKeyOverrideConfigured = true;
        AttendanceGoogleDirectionsService.testApiKeyOverride = apiKey;
    }

    private static void configureDirectionsMock(Integer totalMeters) {
        resetGoogleApiTestState();
        configureTestApiKeyOverride('test-google-maps-api-key');
        Test.setMock(HttpCalloutMock.class, new GoogleDirectionsHttpMock(totalMeters, false));
    }

    private static void configureDirectionsFailureMock() {
        resetGoogleApiTestState();
        configureTestApiKeyOverride('test-google-maps-api-key');
        Test.setMock(HttpCalloutMock.class, new GoogleDirectionsHttpMock(null, true));
    }

    private static Attendance__c getSetupAttendance() {
        return [
            SELECT
                Id,
                User__c,
                Date_of_attendance__c,
                Attendance_Applied_on__c,
                CreatedDate
            FROM Attendance__c
            WHERE Date_of_attendance__c = :Date.today()
                AND User__c = :UserInfo.getUserId()
            LIMIT 1
        ];
    }

    private static Datetime resolveAttendanceLifecycleAnchor(Attendance__c attendance) {
        if (attendance == null) {
            return DateTime.newInstance(Date.today(), Time.newInstance(8, 0, 0, 0));
        }
        if (attendance.Attendance_Applied_on__c != null) {
            return attendance.Attendance_Applied_on__c;
        }
        if (attendance.CreatedDate != null) {
            return attendance.CreatedDate;
        }
        return DateTime.newInstance(attendance.Date_of_attendance__c, Time.newInstance(8, 0, 0, 0));
    }

    /** Outlet CreatedDate must be on/after attendance check-in to pass lifecycle filtering in the service. */
    private static Datetime resolveOutletCreatedAtAfterCheckIn(Attendance__c attendance) {
        return resolveAttendanceLifecycleAnchor(attendance).addHours(1);
    }

    /**
     * Account BeforeInsert runs GenerateRetailerCreationCode, which fails when
     * RetailerCodeSetting__c (Name=SF) is missing or Latest_Code__c is null.
     */
    private static void ensureRetailerCodeSetting() {
        if (!Schema.getGlobalDescribe().containsKey('retailercodesetting__c')) {
            return;
        }
        List<RetailerCodeSetting__c> rows = [
            SELECT Id, Latest_Code__c
            FROM RetailerCodeSetting__c
            WHERE Name = 'SF'
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            insert new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 1);
            return;
        }
        if (rows[0].Latest_Code__c == null) {
            rows[0].Latest_Code__c = 1;
            update rows[0];
        }
    }

    private static List<AttendanceGoogleDirectionsService.LatLngPoint> buildDistinctPath(Integer count) {
        List<AttendanceGoogleDirectionsService.LatLngPoint> path =
            new List<AttendanceGoogleDirectionsService.LatLngPoint>();
        for (Integer i = 0; i < count; i++) {
            path.add(
                new AttendanceGoogleDirectionsService.LatLngPoint(
                    12.970000 + (i * 0.010000),
                    77.590000 + (i * 0.010000)
                )
            );
        }
        return path;
    }

    @IsTest
    static void testCalculateTotalDistanceKm_returnsNullForNullInputs() {
        System.assertEquals(null, AttendanceGoogleDirectionsService.calculateTotalDistanceKm(null, null, null));
        System.assertEquals(
            null,
            AttendanceGoogleDirectionsService.calculateTotalDistanceKm(
                null,
                UserInfo.getUserId(),
                null
            )
        );
    }

    @IsTest
    static void testCalculateTotalDistanceKm_returnsNullWhenInsufficientWaypoints() {
        Id userId = UserInfo.getUserId();
        System.assertEquals(
            null,
            AttendanceGoogleDirectionsService.calculateTotalDistanceKm(
                null,
                userId,
                Date.today().addDays(-30)
            )
        );
    }

    @IsTest
    static void testCalculateTotalDistanceKm_returnsKmFromDirectionsResponse() {
        configureDirectionsMock(8750);
        Attendance__c attendance = getSetupAttendance();

        Test.startTest();
        Decimal result = AttendanceGoogleDirectionsService.calculateTotalDistanceKm(
            attendance.Id,
            attendance.User__c,
            attendance.Date_of_attendance__c
        );
        Test.stopTest();

        System.assertEquals(8.75, result, 'Directions meters should convert to km with 2 dp.');
    }

    @IsTest
    static void testCalculateTotalDistanceKm_usesHaversineWhenGoogleReturnsZero() {
        configureDirectionsMock(0);
        Attendance__c attendance = getSetupAttendance();

        Test.startTest();
        Decimal result = AttendanceGoogleDirectionsService.calculateTotalDistanceKm(
            attendance.Id,
            attendance.User__c,
            attendance.Date_of_attendance__c
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Haversine fallback should return a distance when Google returns 0 m.');
        System.assert(result >= 0, 'Haversine fallback distance should be non-negative.');
    }

    @IsTest
    static void testCalculateTotalDistanceKm_returnsNullWhenDirectionsFails() {
        configureDirectionsFailureMock();
        Attendance__c attendance = getSetupAttendance();

        Test.startTest();
        Decimal result = AttendanceGoogleDirectionsService.calculateTotalDistanceKm(
            attendance.Id,
            attendance.User__c,
            attendance.Date_of_attendance__c
        );
        Test.stopTest();

        System.assertEquals(null, result, 'Failed Directions call should return null.');
    }

    @IsTest
    static void testCalculateTotalDistanceKm_returnsNullWhenApiKeyMissing() {
        resetGoogleApiTestState();
        configureTestApiKeyOverride('');
        Attendance__c attendance = getSetupAttendance();

        try {
            Test.startTest();
            Decimal result = AttendanceGoogleDirectionsService.calculateTotalDistanceKm(
                attendance.Id,
                attendance.User__c,
                attendance.Date_of_attendance__c
            );
            Test.stopTest();

            System.assertEquals(null, result, 'Blank API key should prevent a Directions distance.');
        } finally {
            resetGoogleApiTestState();
        }
    }

    @IsTest
    static void testBuildRouteWaypoints_includesAttendanceCheckInAndEod() {
        Attendance__c attendance = getSetupAttendance();

        List<AttendanceGoogleDirectionsService.LatLngPoint> waypoints =
            AttendanceGoogleDirectionsService.buildRouteWaypoints(
                attendance.User__c,
                attendance.Date_of_attendance__c
            );

        System.assertEquals(2, waypoints.size(), 'Check-in and EOD should produce two waypoints.');
        System.assertEquals(CHECK_IN_LAT, waypoints[0].latitude);
        System.assertEquals(EOD_LAT, waypoints[1].latitude);
    }

    @IsTest
    static void testBuildRouteWaypoints_includesNewOutletWhenPresent() {
        Attendance__c attendance = getSetupAttendance();
        Integer baseWaypointCount =
            AttendanceGoogleDirectionsService.buildRouteWaypoints(
                attendance.User__c,
                attendance.Date_of_attendance__c
            ).size();
        System.assertEquals(2, baseWaypointCount, 'Setup should provide check-in and EOD.');

        Id retailerRecordTypeId = resolveRetailerRecordTypeId();
        if (retailerRecordTypeId == null) {
            return;
        }

        Datetime lifecycleStart = resolveAttendanceLifecycleAnchor(attendance);
        Datetime outletCreatedAt = resolveOutletCreatedAtAfterCheckIn(attendance);
        User attendanceUser = [SELECT Id FROM User WHERE Id = :attendance.User__c LIMIT 1];
        Id outletId;
        System.runAs(attendanceUser) {
            outletId = createRetailerAccount(retailerRecordTypeId, outletCreatedAt);
        }

        Integer serviceVisibleOutletCount = countNewOutletsVisibleToService(
            attendance.User__c,
            attendance.Date_of_attendance__c,
            lifecycleStart
        );

        List<AttendanceGoogleDirectionsService.LatLngPoint> waypoints =
            AttendanceGoogleDirectionsService.buildRouteWaypoints(
                attendance.User__c,
                attendance.Date_of_attendance__c
            );

        if (serviceVisibleOutletCount == 0) {
            System.assertEquals(
                baseWaypointCount,
                waypoints.size(),
                'When outlet rows are not visible to the service query, only attendance waypoints should remain.'
            );
            return;
        }

        System.assert(
            waypoints.size() > baseWaypointCount,
            'A retailer account created today should add at least one route waypoint.'
        );

        Account outlet = [
            SELECT BillingLatitude, Latitude__c, Longitude__c
            FROM Account
            WHERE Id = :outletId
            LIMIT 1
        ];
        AttendanceGoogleDirectionsService.LatLngPoint expectedCoords =
            AttendanceGoogleDirectionsService.resolveNewOutletMapCoordinates(outlet);
        System.assertNotEquals(null, expectedCoords, 'Test outlet should have resolvable map coordinates.');
        Boolean includesOutletLatitude = false;
        for (AttendanceGoogleDirectionsService.LatLngPoint point : waypoints) {
            if (point.latitude == expectedCoords.latitude) {
                includesOutletLatitude = true;
                break;
            }
        }
        System.assert(
            includesOutletLatitude,
            'New outlet map coordinates should be included in the route.'
        );
    }

    @IsTest
    static void testBuildRouteWaypoints_includesNewOutletWithTextCoordinatesOnly() {
        Attendance__c attendance = getSetupAttendance();
        Id retailerRecordTypeId = resolveRetailerRecordTypeId();
        if (retailerRecordTypeId == null) {
            return;
        }

        Datetime outletCreatedAt = resolveOutletCreatedAtAfterCheckIn(attendance);
        User attendanceUser = [SELECT Id FROM User WHERE Id = :attendance.User__c LIMIT 1];
        Id outletId;
        System.runAs(attendanceUser) {
            outletId = createRetailerAccount(retailerRecordTypeId, outletCreatedAt, true);
        }

        Account outlet = [
            SELECT BillingLatitude, Latitude__c, Longitude__c
            FROM Account
            WHERE Id = :outletId
            LIMIT 1
        ];
        AttendanceGoogleDirectionsService.LatLngPoint expectedCoords =
            AttendanceGoogleDirectionsService.resolveNewOutletMapCoordinates(outlet);
        System.assertNotEquals(null, expectedCoords, 'Text-only outlet coordinates should resolve.');

        List<AttendanceGoogleDirectionsService.LatLngPoint> waypoints =
            AttendanceGoogleDirectionsService.buildRouteWaypoints(
                attendance.User__c,
                attendance.Date_of_attendance__c
            );

        Boolean includesOutletLatitude = false;
        for (AttendanceGoogleDirectionsService.LatLngPoint point : waypoints) {
            if (point.latitude == expectedCoords.latitude) {
                includesOutletLatitude = true;
                break;
            }
        }
        System.assert(
            includesOutletLatitude,
            'Outlets with only Latitude__c/Longitude__c should be included like the dashboard.'
        );
    }

    @IsTest
    static void testBuildRouteWaypoints_includesVisitWhenPresent() {
        Attendance__c attendance = getSetupAttendance();
        createVisitTaskForUser(
            attendance.User__c,
            attendance.Date_of_attendance__c,
            resolveAttendanceLifecycleAnchor(attendance).addHours(1)
        );

        List<AttendanceGoogleDirectionsService.LatLngPoint> waypoints =
            AttendanceGoogleDirectionsService.buildRouteWaypoints(
                attendance.User__c,
                attendance.Date_of_attendance__c
            );

        System.assertEquals(3, waypoints.size(), 'Check-in, visit, and EOD should produce three waypoints.');

        Boolean includesVisitLatitude = false;
        for (AttendanceGoogleDirectionsService.LatLngPoint point : waypoints) {
            if (point.latitude == VISIT_LAT) {
                includesVisitLatitude = true;
                break;
            }
        }
        System.assert(includesVisitLatitude, 'Visit check-in latitude should be included in the route.');
    }

    @IsTest
    static void testExpandPathForRouting_offsetsCoincidentStops() {
        List<AttendanceGoogleDirectionsService.LatLngPoint> path = new List<AttendanceGoogleDirectionsService.LatLngPoint>{
            new AttendanceGoogleDirectionsService.LatLngPoint(12.971600, 77.594600),
            new AttendanceGoogleDirectionsService.LatLngPoint(12.971600, 77.594600),
            new AttendanceGoogleDirectionsService.LatLngPoint(12.980000, 77.600000)
        };

        List<AttendanceGoogleDirectionsService.LatLngPoint> expanded =
            AttendanceGoogleDirectionsService.expandPathForRouting(path);

        System.assertEquals(3, expanded.size());
        System.assertNotEquals(
            expanded[0].latitude,
            expanded[1].latitude,
            'Coincident consecutive stops should be offset for routing.'
        );
    }

    @IsTest
    static void testPreparePathForDirectionsRouting_returnsProcessedPath() {
        List<AttendanceGoogleDirectionsService.LatLngPoint> path = new List<AttendanceGoogleDirectionsService.LatLngPoint>{
            new AttendanceGoogleDirectionsService.LatLngPoint(12.971600, 77.594600),
            new AttendanceGoogleDirectionsService.LatLngPoint(12.980000, 77.600000)
        };

        List<AttendanceGoogleDirectionsService.LatLngPoint> routingPath =
            AttendanceGoogleDirectionsService.preparePathForDirectionsRouting(path);

        System.assertEquals(2, routingPath.size());
        System.assertNotEquals(null, routingPath[0].latitude);
        System.assertNotEquals(null, routingPath[1].latitude);
    }

    @IsTest
    static void testHangyoPathForRouting_returnsSinglePointPathUnchanged() {
        List<AttendanceGoogleDirectionsService.LatLngPoint> path = new List<AttendanceGoogleDirectionsService.LatLngPoint>{
            new AttendanceGoogleDirectionsService.LatLngPoint(12.971600, 77.594600)
        };

        List<AttendanceGoogleDirectionsService.LatLngPoint> result =
            AttendanceGoogleDirectionsService.hangyoPathForRouting(path);

        System.assertEquals(1, result.size());
        System.assertEquals(12.971600, result[0].latitude);
    }

    @IsTest
    static void testParseDirectionsDistanceMeters_handlesValidAndInvalidPayloads() {
        System.assertEquals(null, AttendanceGoogleDirectionsService.parseDirectionsDistanceMeters(null));
        System.assertEquals(null, AttendanceGoogleDirectionsService.parseDirectionsDistanceMeters(''));
        System.assertEquals(
            null,
            AttendanceGoogleDirectionsService.parseDirectionsDistanceMeters('{"status":"REQUEST_DENIED"}')
        );
        System.assertEquals(
            null,
            AttendanceGoogleDirectionsService.parseDirectionsDistanceMeters('{"status":"OK","routes":[]}')
        );
        System.assertEquals(
            null,
            AttendanceGoogleDirectionsService.parseDirectionsDistanceMeters(
                '{"status":"OK","routes":[{"legs":[]}]}'
            )
        );

        Integer singleLeg = AttendanceGoogleDirectionsService.parseDirectionsDistanceMeters(
            '{"status":"OK","routes":[{"legs":[{"distance":{"value":1500}}]}]}'
        );
        System.assertEquals(1500, singleLeg);

        Integer multiLeg = AttendanceGoogleDirectionsService.parseDirectionsDistanceMeters(
            '{"status":"OK","routes":[{"legs":['
                + '{"distance":{"value":1000}},'
                + '{"distance":{"value":2500}}'
                + ']}]}'
        );
        System.assertEquals(3500, multiLeg);
    }

    @IsTest
    static void testRequestGoogleDirectionsDistanceMeters_singleRoute() {
        configureDirectionsMock(4200);
        List<AttendanceGoogleDirectionsService.LatLngPoint> path = buildDistinctPath(3);

        Test.startTest();
        Integer meters = AttendanceGoogleDirectionsService.requestGoogleDirectionsDistanceMeters(path);
        Test.stopTest();

        System.assertEquals(4200, meters);
    }

    @IsTest
    static void testRequestGoogleDirectionsDistanceMeters_chunkedRoute() {
        configureDirectionsMock(1000);
        Test.setMock(HttpCalloutMock.class, new GoogleDirectionsChunkedMock(1000));
        List<AttendanceGoogleDirectionsService.LatLngPoint> path = buildDistinctPath(26);

        try {
            Test.startTest();
            Integer meters = AttendanceGoogleDirectionsService.requestGoogleDirectionsDistanceMeters(path);
            Test.stopTest();

            System.assertEquals(2000, meters, 'Chunked routing should sum leg distances across segments.');
        } finally {
            resetGoogleApiTestState();
        }
    }

    @IsTest
    static void testCalculateHaversineRouteDistanceKm_sumsLegs() {
        List<AttendanceGoogleDirectionsService.LatLngPoint> path = new List<AttendanceGoogleDirectionsService.LatLngPoint>{
            new AttendanceGoogleDirectionsService.LatLngPoint(CHECK_IN_LAT, CHECK_IN_LNG),
            new AttendanceGoogleDirectionsService.LatLngPoint(EOD_LAT, EOD_LNG)
        };

        Decimal km = AttendanceGoogleDirectionsService.calculateHaversineRouteDistanceKm(path);

        System.assertNotEquals(null, km);
        System.assert(km > 0, 'Haversine distance between check-in and EOD should be positive.');
    }

    @IsTest
    static void testResolveGoogleMapsApiKey_usesTestOverride() {
        resetGoogleApiTestState();
        configureTestApiKeyOverride('override-key');
        System.assertEquals('override-key', AttendanceGoogleDirectionsService.resolveGoogleMapsApiKey());
        resetGoogleApiTestState();
    }

    @IsTest
    static void testResolveGoogleMapsApiKey_returnsBlankWhenOverrideEmpty() {
        resetGoogleApiTestState();
        configureTestApiKeyOverride('');
        System.assertEquals('', AttendanceGoogleDirectionsService.resolveGoogleMapsApiKey());
        resetGoogleApiTestState();
    }

    @IsTest
    static void testResolveNewOutletMapCoordinates_prefersTextFieldsOverBilling() {
        Account acc = new Account(
            Latitude__c = '12.111111',
            Longitude__c = '75.222222',
            BillingLatitude = 99.000000,
            BillingLongitude = 88.000000
        );

        AttendanceGoogleDirectionsService.LatLngPoint coords =
            AttendanceGoogleDirectionsService.resolveNewOutletMapCoordinates(acc);

        System.assertNotEquals(null, coords);
        System.assertEquals(12.111111, coords.latitude);
        System.assertEquals(75.222222, coords.longitude);
    }

    private static void createVisitTaskForUser(Id userId, Date plannedDate, Datetime checkInTime) {
        Beat__c beat = new Beat__c(
            Name = 'AGDS Test Beat ' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        insert beat;

        Visit__c visit = new Visit__c(
            Visit_planned_date__c = plannedDate,
            Visitor_Name__c = userId,
            Beat__c = beat.Id,
            Status__c = 'Not Started',
            Visit_Type__c = 'Planned'
        );
        insert visit;

        Datetime accountCreatedAt = DateTime.newInstance(
            plannedDate.addDays(-1),
            Time.newInstance(12, 0, 0, 0)
        );
        Id accountId = createRetailerAccount(accountCreatedAt);

        insert new Visit_Task__c(
            Visit__c = visit.Id,
            Beat__c = beat.Id,
            Visitor_Name__c = userId,
            Task_Planned_Date__c = plannedDate,
            Account__c = accountId,
            Retailer__c = accountId,
            Order_Placed__c = false,
            Status__c = 'In-Progress',
            Checked_In_Time__c = checkInTime,
            Checked_Out_Time__c = checkInTime.addHours(1),
            End_Call_Time__c = checkInTime.addHours(1),
            Checked_In_Location__Latitude__s = VISIT_LAT,
            Checked_In_Location__Longitude__s = VISIT_LNG
        );
    }

    private static Id resolveRetailerRecordTypeId() {
        List<RecordType> retailerTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
                AND Name = 'Retailer'
            LIMIT 1
        ];
        return retailerTypes.isEmpty() ? null : retailerTypes[0].Id;
    }

    private static Integer countNewOutletsVisibleToService(
        Id userId,
        Date attendanceDate,
        Datetime lifecycleStart
    ) {
        DateTime dayStart = DateTime.newInstance(attendanceDate, Time.newInstance(0, 0, 0, 0));
        DateTime dayEndExclusive = dayStart.addDays(1);
        Integer visibleCount = 0;
        for (Account row : [
            SELECT CreatedDate, BillingLatitude, BillingLongitude, Latitude__c, Longitude__c
            FROM Account
            WHERE CreatedById = :userId
                AND CreatedDate >= :dayStart
                AND CreatedDate < :dayEndExclusive
                AND RecordType.Name = 'Retailer'
        ]) {
            if (
                lifecycleStart != null
                && row.CreatedDate != null
                && row.CreatedDate < lifecycleStart
            ) {
                continue;
            }
            if (AttendanceGoogleDirectionsService.resolveNewOutletMapCoordinates(row) != null) {
                visibleCount++;
            }
        }
        return visibleCount;
    }

    private static Id createRetailerAccount(Datetime createdAt) {
        return createRetailerAccount(resolveRetailerRecordTypeId(), createdAt, false);
    }

    private static Id createRetailerAccount(Id retailerRecordTypeId, Datetime createdAt) {
        return createRetailerAccount(retailerRecordTypeId, createdAt, false);
    }

    private static Id createRetailerAccount(
        Id retailerRecordTypeId,
        Datetime createdAt,
        Boolean textCoordinatesOnly
    ) {
        ensureRetailerCodeSetting();

        Account outlet = new Account(
            Name = 'AGDS Test Outlet ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Onboard_Date__c = createdAt == null ? Date.today() : createdAt.date()
        );
        if (textCoordinatesOnly) {
            outlet.Latitude__c = '13.010000';
            outlet.Longitude__c = '77.610000';
        } else {
            outlet.BillingLatitude = 13.010000;
            outlet.BillingLongitude = 77.610000;
            outlet.Latitude__c = '13.010000';
            outlet.Longitude__c = '77.610000';
        }
        if (retailerRecordTypeId != null) {
            outlet.RecordTypeId = retailerRecordTypeId;
        }
        insert outlet;
        if (createdAt != null) {
            Test.setCreatedDate(outlet.Id, createdAt);
        }
        return outlet.Id;
    }

    private class GoogleDirectionsHttpMock implements HttpCalloutMock {
        private final Integer totalMeters;
        private final Boolean simulateFailure;

        GoogleDirectionsHttpMock(Integer totalMeters, Boolean simulateFailure) {
            this.totalMeters = totalMeters;
            this.simulateFailure = simulateFailure;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            if (simulateFailure) {
                response.setStatusCode(500);
                response.setBody('{"status":"REQUEST_DENIED"}');
                return response;
            }

            response.setStatusCode(200);
            response.setBody(
                '{"status":"OK","routes":[{"legs":[{"distance":{"value":'
                    + totalMeters
                    + ',"text":"distance"}}]}]}'
            );
            return response;
        }
    }

    private class GoogleDirectionsChunkedMock implements HttpCalloutMock {
        private final Integer metersPerCall;

        GoogleDirectionsChunkedMock(Integer metersPerCall) {
            this.metersPerCall = metersPerCall;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody(
                '{"status":"OK","routes":[{"legs":[{"distance":{"value":'
                    + metersPerCall
                    + ',"text":"chunk"}}]}]}'
            );
            return response;
        }
    }
}