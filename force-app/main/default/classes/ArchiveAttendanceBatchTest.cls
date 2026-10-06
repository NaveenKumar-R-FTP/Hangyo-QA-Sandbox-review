@isTest
private class ArchiveAttendanceBatchTest {

    @testSetup
    static void setup() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'SFA Profile' LIMIT 1];

        User u = new User(
            Alias = 'tuser',
            Email = 'testuser@sales.hangyo.in',
            EmailEncodingKey = 'UTF-8',
            LastName = 'User',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            UserName = 'testuser' + System.currentTimeMillis() + '@test.com'
        );
        insert u;

        Date today = Date.today();

        List<Attendance__c> records = new List<Attendance__c>();
        for (Integer i = 0; i < 5; i++) {
            records.add(new Attendance__c(
                User__c = u.Id,
                Date_of_attendance__c = today,
                Status__c = 'Present',
                First_Activity_Time__c = null
            ));
        }
        insert records;
    }

    @isTest
    static void testExecuteBatch_SuccessArchivesRecords() {
        List<Attendance__c> allRecords = [SELECT Id FROM Attendance__c];
        Set<Id> allIds = new Map<Id, Attendance__c>(allRecords).keySet();

        Test.setMock(HttpCalloutMock.class, new AttendanceArchiveConnectorCalloutMock(true, allIds));

        Test.startTest();
        Database.executeBatch(new ArchiveAttendanceBatch(), 200);
        Test.stopTest();

        List<Attendance__c> updated = [
            SELECT Id, Archived__c, Archived_Date__c
            FROM Attendance__c
        ];
        System.assertEquals(allRecords.size(), updated.size(), 'Expected all seeded records to be returned');
        for (Attendance__c rec : updated) {
            System.assertEquals(true, rec.Archived__c, 'Record should be marked archived');
            System.assertNotEquals(null, rec.Archived_Date__c, 'Archived_Date__c should be populated');
        }

        List<Archival_Job_Log__c> logs = [
            SELECT Archived_Object__c, Total_Processed__c, Total_Archived__c, Total_Failed__c, Error_Message__c
            FROM Archival_Job_Log__c
        ];
        System.assertEquals(1, logs.size(), 'Expected exactly one job log to be inserted in finish()');
        Archival_Job_Log__c log = logs[0];
        System.assertEquals('Attendance__c', log.Archived_Object__c);
        System.assertEquals(allRecords.size(), (Integer) log.Total_Processed__c);
        System.assertEquals(allRecords.size(), (Integer) log.Total_Archived__c);
        System.assertEquals(0, (Integer) log.Total_Failed__c);
        System.assertEquals(null, log.Error_Message__c, 'No errors expected on the success path');
    }

    @isTest
    static void testExecuteBatch_FailureLogsErrorAndLeavesRecordsUntouched() {
        Test.setMock(HttpCalloutMock.class, new AttendanceArchiveConnectorCalloutMock(false, new Set<Id>()));

        Test.startTest();
        Database.executeBatch(new ArchiveAttendanceBatch(), 200);
        Test.stopTest();

        List<Attendance__c> untouched = [
            SELECT Id, Archived__c, Archived_Date__c
            FROM Attendance__c
        ];
        for (Attendance__c rec : untouched) {
            System.assertEquals(false, rec.Archived__c, 'Record should remain unarchived when the callout fails');
            System.assertEquals(null, rec.Archived_Date__c);
        }

        Archival_Job_Log__c log = [
            SELECT Total_Processed__c, Total_Archived__c, Total_Failed__c, Error_Message__c
            FROM Archival_Job_Log__c
            LIMIT 1
        ];
        System.assertEquals(0, (Integer) log.Total_Archived__c);
        System.assert((Integer) log.Total_Failed__c > 0, 'Expected failed count to reflect the failed callout');
        System.assertNotEquals(null, log.Error_Message__c, 'Expected error message(s) to be captured');
    }

    @isTest
    static void testExecuteBatch_PartialArchiveOnlyUpdatesReturnedIds() {
        List<Attendance__c> allRecords = [SELECT Id FROM Attendance__c];
        // Only "archive" the first record returned by the mock service.
        Set<Id> partialIds = new Set<Id>{ allRecords[0].Id };

        Test.setMock(HttpCalloutMock.class, new AttendanceArchiveConnectorCalloutMock(true, partialIds));

        Test.startTest();
        Database.executeBatch(new ArchiveAttendanceBatch(), 200);
        Test.stopTest();

        Map<Id, Attendance__c> updatedById = new Map<Id, Attendance__c>(
            [SELECT Id, Archived__c FROM Attendance__c]
        );

        System.assertEquals(true, updatedById.get(allRecords[0].Id).Archived__c);
        for (Integer i = 1; i < allRecords.size(); i++) {
            System.assertEquals(false, updatedById.get(allRecords[i].Id).Archived__c,
                'Only ids returned as archived by the service should be updated');
        }

        Archival_Job_Log__c log = [SELECT Total_Archived__c FROM Archival_Job_Log__c LIMIT 1];
        System.assertEquals(1, (Integer) log.Total_Archived__c);
    }

    @isTest
    static void testSchedulableExecuteKicksOffBatch() {
        Test.setMock(HttpCalloutMock.class, new AttendanceArchiveConnectorCalloutMock(true, new Set<Id>()));

        Test.startTest();
        String cronExpr = '0 0 4 * * ?'; // daily at 4 AM
        System.schedule('Archive Attendance Test', cronExpr, new ArchiveAttendanceBatch());
        Test.stopTest();
    }

    /**
     * Mock HTTP callout used to simulate ArchiveConnectorService's response.
     * Adjust the JSON shape / status code to match what ArchiveConnectorService
     * actually expects from the Azure endpoint if this doesn't line up.
     */
    private class AttendanceArchiveConnectorCalloutMock implements HttpCalloutMock {
        private Boolean success;
        private Set<Id> archivedIds;

        AttendanceArchiveConnectorCalloutMock(Boolean success, Set<Id> archivedIds) {
            this.success = success;
            this.archivedIds = archivedIds;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            if (success) {
                List<String> idStrings = new List<String>();
                for (Id recId : archivedIds) {
                    idStrings.add('"' + recId + '"');
                }
                res.setStatusCode(200);
                res.setBody('{"success":true,"archivedIds":[' + String.join(idStrings, ',') + ']}');
            } else {
                res.setStatusCode(500);
                res.setBody('{"success":false,"errorCode":"AZ500","errorMessage":"Simulated archive failure"}');
            }
            return res;
        }
    }
}