@IsTest
private class ZingHR_Attendance_Test {

    /*
     * ---------------------------------------------------------
     * HTTP MOCK CLASS
     * ---------------------------------------------------------
     */
    private class ZingHRHttpMock implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {

            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            // Token API
            if (req.getEndpoint().contains('GenerateJWTToken')) {
                res.setStatusCode(200);
                res.setBody('{"data":"TEST_TOKEN"}');
            }

            // Attendance API
            else if (req.getEndpoint().contains('SynSwipes')) {
                res.setStatusCode(200);
                res.setBody('{"status":"success"}');
            }

            else {
                res.setStatusCode(400);
                res.setBody('{"error":"Unknown Endpoint"}');
            }

            return res;
        }
    }

    /*
     * ---------------------------------------------------------
     * TEST DATA CREATION
     * ---------------------------------------------------------
     */
    private static User createTestUser() {

        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        User u = new User(
            FirstName = 'Test',
            LastName = 'User',
            Alias = 'tuser',
            Email = 'testuser@hangyo.in',
            Username = 'testuser' + System.currentTimeMillis() + '@test.com',
            CommunityNickname = 'testnick' + System.currentTimeMillis(),
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id,
            EmployeeNumber = 'EMP001'
        );

        insert u;
        return u;
    }

    private static Attendance__c createAttendance(
        User u,
        Boolean attendanceSent,
        Boolean eodSent
    ) {

        Datetime targetDateTime = Datetime.now().addDays(-4);

        Attendance__c att = new Attendance__c(
            User__c = u.Id,
            Status__c = 'Present',
            EOD_Date_Time__c = targetDateTime,
            Attendance_Sent__c = attendanceSent,
            EOD_Sent__c = eodSent
        );

        insert att;
        return att;
    }

    /*
     * ---------------------------------------------------------
     * TEST getAccessToken()
     * ---------------------------------------------------------
     */
    @IsTest
    static void testGetAccessToken() {

        Test.setMock(HttpCalloutMock.class, new ZingHRHttpMock());

        Test.startTest();
        String token = ZingHR_AttendanceService.getAccessToken();
        Test.stopTest();

        System.assertEquals('TEST_TOKEN', token);
    }

    /*
     * ---------------------------------------------------------
     * TEST sendAttendance() - ATTENDANCE
     * ---------------------------------------------------------
     */
    @IsTest
    static void testSendAttendance_Attendance() {

        User u = createTestUser();
        Attendance__c att = createAttendance(u, false, false);

        List<Attendance__c> records = [
            SELECT Id,
                   EMP_CODE__c,
                   Attendance_Applied_on__c
            FROM Attendance__c
            WHERE Id = :att.Id
        ];

        Test.setMock(HttpCalloutMock.class, new ZingHRHttpMock());

        Test.startTest();
        ZingHR_AttendanceService.sendAttendance(records, 'ATTENDANCE');
        Test.stopTest();

        Attendance__c updatedRec = [
            SELECT Attendance_Sent__c
            FROM Attendance__c
            WHERE Id = :att.Id
        ];

        System.assertEquals(true, updatedRec.Attendance_Sent__c);
    }

    @IsTest
    static void testSendAttendance_EOD() {

        User u = createTestUser();
        Attendance__c att = createAttendance(u, false, false);

        List<Attendance__c> records = [
            SELECT Id,
                   EMP_CODE__c,
                   EOD_Date_Time__c
            FROM Attendance__c
            WHERE Id = :att.Id
        ];

        Test.setMock(HttpCalloutMock.class, new ZingHRHttpMock());

        Test.startTest();
        ZingHR_AttendanceService.sendAttendance(records, 'EOD');
        Test.stopTest();

        Attendance__c updatedRec = [
            SELECT EOD_Sent__c
            FROM Attendance__c
            WHERE Id = :att.Id
        ];

        System.assertEquals(true, updatedRec.EOD_Sent__c);
    }

    @IsTest
    static void testQueueable_Attendance() {

        User u = createTestUser();
        Attendance__c att = createAttendance(u, false, false);

        Test.setMock(HttpCalloutMock.class, new ZingHRHttpMock());

        Test.startTest();
        System.enqueueJob(new ZingHR_AttendanceQueueable());
        Test.stopTest();

        Attendance__c rec = [
            SELECT Attendance_Sent__c
            FROM Attendance__c
            WHERE Id = :att.Id
        ];
    }

    @IsTest
    static void testQueueable_EOD() {

        User u = createTestUser();
        Attendance__c att = createAttendance(u, false, false);

        Test.setMock(HttpCalloutMock.class, new ZingHRHttpMock());

        Test.startTest();
        System.enqueueJob(new ZingHR_AttendanceQueueable('EOD'));
        Test.stopTest();

        Attendance__c rec = [
            SELECT EOD_Sent__c
            FROM Attendance__c
            WHERE Id = :att.Id
        ];

        System.assertEquals(
            true,
            rec.EOD_Sent__c,
            'EOD should be marked as sent'
        );
    }

    @IsTest
    static void testScheduler() {

        User u = createTestUser();
        Attendance__c att = createAttendance(u, false, false);

        Test.setMock(HttpCalloutMock.class, new ZingHRHttpMock());

        Test.startTest();

        System.schedule(
            'ZingHR Scheduler Test',
            '0 0 10 * * ?',
            new ZingHR_AttendanceScheduler()
        );

        Test.stopTest();

        Attendance__c rec = [
            SELECT Attendance_Sent__c,
                   EOD_Sent__c
            FROM Attendance__c
            WHERE Id = :att.Id
        ];
    }
}