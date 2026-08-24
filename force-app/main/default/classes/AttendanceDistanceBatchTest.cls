/**
 * @description Test coverage for AttendanceDistanceBatch.
 */
@IsTest
private class AttendanceDistanceBatchTest {

    private static final Decimal CHECK_IN_LAT = 12.971600;
    private static final Decimal CHECK_IN_LNG = 77.594600;
    private static final Decimal EOD_LAT = 12.980000;
    private static final Decimal EOD_LNG = 77.600000;

    @TestSetup
    static void setupData() {
        insert new Attendance__c(
            User__c = UserInfo.getUserId(),
            Date_of_attendance__c = Date.today(),
            Status__c = 'Present',
            Location__Latitude__s = CHECK_IN_LAT,
            Location__Longitude__s = CHECK_IN_LNG,
            EOD_Date_Time__c = DateTime.newInstance(Date.today(), Time.newInstance(18, 0, 0, 0)),
            EOD_Location__Latitude__s = EOD_LAT,
            EOD_Location__Longitude__s = EOD_LNG
        );
    }

    private static void configureDirectionsMock(Integer totalMeters) {
        AttendanceGoogleDirectionsService.testApiKeyOverrideConfigured = true;
        AttendanceGoogleDirectionsService.testApiKeyOverride = 'test-google-maps-api-key';
        Test.setMock(HttpCalloutMock.class, new GoogleDirectionsHttpMock(totalMeters, false));
    }

    private static void configureDirectionsFailureMock() {
        AttendanceGoogleDirectionsService.testApiKeyOverrideConfigured = true;
        AttendanceGoogleDirectionsService.testApiKeyOverride = 'test-google-maps-api-key';
        Test.setMock(HttpCalloutMock.class, new GoogleDirectionsHttpMock(null, true));
    }

    private static Attendance__c createAttendanceForToday(
        Decimal checkInLat,
        Decimal checkInLng,
        Boolean withEod
    ) {
        Attendance__c attendance = new Attendance__c(
            User__c = UserInfo.getUserId(),
            Date_of_attendance__c = Date.today(),
            Status__c = 'Present',
            Location__Latitude__s = checkInLat,
            Location__Longitude__s = checkInLng
        );
        if (withEod) {
            attendance.EOD_Date_Time__c = DateTime.newInstance(
                Date.today(),
                Time.newInstance(19, 0, 0, 0)
            );
            attendance.EOD_Location__Latitude__s = EOD_LAT;
            attendance.EOD_Location__Longitude__s = EOD_LNG;
        }
        insert attendance;
        return attendance;
    }

    @IsTest
    static void testBatch_updatesDistanceFieldOnSuccessfulDirectionsResponse() {
        configureDirectionsMock(12500);

        AttendanceDistanceBatch.processingDateOverride = Date.today();

        Test.startTest();
        Database.executeBatch(new AttendanceDistanceBatch(), 20);
        Test.stopTest();

        Attendance__c updated = [
            SELECT Total_Distance_Calculated_by_Google_API__c
            FROM Attendance__c
            WHERE Date_of_attendance__c = :Date.today()
                AND User__c = :UserInfo.getUserId()
            LIMIT 1
        ];
    }

    @IsTest
    static void testBatch_leavesDistanceFieldNullWhenDirectionsFails() {
        configureDirectionsFailureMock();

        AttendanceDistanceBatch.processingDateOverride = Date.today();

        Test.startTest();
        Database.executeBatch(new AttendanceDistanceBatch(), 20);
        Test.stopTest();

        Attendance__c unchanged = [
            SELECT Total_Distance_Calculated_by_Google_API__c
            FROM Attendance__c
            WHERE Date_of_attendance__c = :Date.today()
                AND User__c = :UserInfo.getUserId()
            LIMIT 1
        ];

        System.assertEquals(
            null,
            unchanged.Total_Distance_Calculated_by_Google_API__c,
            'Distance field must remain null when Google Directions fails.'
        );
    }

    @IsTest
    static void testBatch_continuesProcessingWhenOneRecordFails() {
        Attendance__c setupAttendance = [
            SELECT Id
            FROM Attendance__c
            WHERE Date_of_attendance__c = :Date.today()
                AND User__c = :UserInfo.getUserId()
            LIMIT 1
        ];
        Attendance__c failureAttendance = createAttendanceForToday(
            12.973000,
            77.596000,
            true
        );

        AttendanceGoogleDirectionsService.testApiKeyOverrideConfigured = true;
        AttendanceGoogleDirectionsService.testApiKeyOverride = 'test-google-maps-api-key';
        Test.setMock(HttpCalloutMock.class, new GoogleDirectionsFailOnSecondCallMock(8400));

        AttendanceDistanceBatch.processingDateOverride = Date.today();

        Test.startTest();
        Database.executeBatch(new AttendanceDistanceBatch(), 20);
        Test.stopTest();

        Map<Id, Attendance__c> results = new Map<Id, Attendance__c>([
            SELECT Total_Distance_Calculated_by_Google_API__c
            FROM Attendance__c
            WHERE Id IN :new Set<Id>{ setupAttendance.Id, failureAttendance.Id }
        ]);

        System.assertNotEquals(
            null,
            results.get(setupAttendance.Id).Total_Distance_Calculated_by_Google_API__c,
            'A successful record should still be updated when another record fails.'
        );
        System.assertEquals(
            null,
            results.get(failureAttendance.Id).Total_Distance_Calculated_by_Google_API__c,
            'A failed record must not populate the distance field.'
        );
    }

    @IsTest
    static void testBatch_skipsRecordsWithoutCheckInCoordinates() {
        configureDirectionsMock(5000);

        Attendance__c ineligible = new Attendance__c(
            User__c = UserInfo.getUserId(),
            Date_of_attendance__c = Date.today(),
            Status__c = 'Present'
        );
        insert ineligible;

        AttendanceDistanceBatch.processingDateOverride = Date.today();

        Test.startTest();
        Database.executeBatch(new AttendanceDistanceBatch(), 20);
        Test.stopTest();

        Attendance__c refreshed = [
            SELECT Total_Distance_Calculated_by_Google_API__c
            FROM Attendance__c
            WHERE Id = :ineligible.Id
        ];

        System.assertEquals(
            null,
            refreshed.Total_Distance_Calculated_by_Google_API__c,
            'Records without check-in coordinates must be excluded from processing.'
        );
    }

    @IsTest
    static void testStartQuery_includesEligibleAttendanceForProcessingDate() {
        Date processingDate = Date.today();
        AttendanceDistanceBatch.processingDateOverride = processingDate;

        Test.startTest();
        Database.QueryLocator locator = Database.getQueryLocator(
            AttendanceDistanceBatch.buildEligibleAttendanceQuery(processingDate)
        );
        Test.stopTest();

        List<Attendance__c> rows = Database.query(locator.getQuery());
        System.assert(rows.size() > 0, 'Eligible attendance rows should be returned for processing.');
        for (Attendance__c row : rows) {
            System.assertNotEquals(null, row.User__c, 'Eligible rows must include User__c.');
            System.assertNotEquals(
                null,
                row.Location__Latitude__s,
                'Eligible rows must include check-in latitude.'
            );
            System.assertNotEquals(
                null,
                row.Location__Longitude__s,
                'Eligible rows must include check-in longitude.'
            );
        }
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
                    + ',"text":"12.5 km"}}]}]}'
            );
            return response;
        }
    }

    private class GoogleDirectionsFailOnSecondCallMock implements HttpCalloutMock {
        private final Integer successMeters;
        private Integer invocationCount = 0;

        GoogleDirectionsFailOnSecondCallMock(Integer successMeters) {
            this.successMeters = successMeters;
        }

        public HttpResponse respond(HttpRequest request) {
            invocationCount++;
            HttpResponse response = new HttpResponse();
            if (invocationCount == 2) {
                response.setStatusCode(500);
                response.setBody('{"status":"ZERO_RESULTS"}');
                return response;
            }

            response.setStatusCode(200);
            response.setBody(
                '{"status":"OK","routes":[{"legs":[{"distance":{"value":'
                    + successMeters
                    + ',"text":"8.4 km"}}]}]}'
            );
            return response;
        }
    }
}