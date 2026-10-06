@isTest
private class ArchiveInventoryAdjustmentsBatchTest {

    private static final String CONFIG_DEV_NAME = 'Inventory_Adjustment';

    @testSetup
    static void setup() {
        List<Inventory_Adjustment__c> records = new List<Inventory_Adjustment__c>();
        for (Integer i = 0; i < 5; i++) {
            records.add(new Inventory_Adjustment__c(
                Quantity__c = 5,
                Type__c = 'Increment'
            ));
        }
        insert records;
    }

    @isTest
    static void testExecuteBatch_SuccessArchivesRecords() {
        List<Inventory_Adjustment__c> allRecords = [SELECT Id FROM Inventory_Adjustment__c];
        Set<Id> allIds = new Map<Id, Inventory_Adjustment__c>(allRecords).keySet();

        Test.setMock(HttpCalloutMock.class, new ArchiveConnectorCalloutMock(true, allIds));

        Test.startTest();
        Database.executeBatch(new ArchiveInventoryAdjustmentsBatch(), 200);
        Test.stopTest();

        List<Inventory_Adjustment__c> updated = [
            SELECT Id, Archived__c, Archived_Date__c
            FROM Inventory_Adjustment__c
        ];
        System.assertEquals(allRecords.size(), updated.size(), 'Expected all seeded records to be returned');
        for (Inventory_Adjustment__c rec : updated) {
            System.assertEquals(true, rec.Archived__c, 'Record should be marked archived');
            System.assertNotEquals(null, rec.Archived_Date__c, 'Archived_Date__c should be populated');
        }

        List<Archival_Job_Log__c> logs = [
            SELECT Archived_Object__c, Total_Processed__c, Total_Archived__c, Total_Failed__c, Error_Message__c
            FROM Archival_Job_Log__c
        ];
        System.assertEquals(1, logs.size(), 'Expected exactly one job log to be inserted in finish()');
        Archival_Job_Log__c log = logs[0];
        System.assertEquals('Inventory_Adjustment__c', log.Archived_Object__c);
        System.assertEquals(allRecords.size(), (Integer) log.Total_Processed__c);
        System.assertEquals(allRecords.size(), (Integer) log.Total_Archived__c);
        System.assertEquals(0, (Integer) log.Total_Failed__c);
        System.assertEquals(null, log.Error_Message__c, 'No errors expected on the success path');
    }

    @isTest
    static void testExecuteBatch_FailureLogsErrorAndLeavesRecordsUntouched() {
        Test.setMock(HttpCalloutMock.class, new ArchiveConnectorCalloutMock(false, new Set<Id>()));

        Test.startTest();
        Database.executeBatch(new ArchiveInventoryAdjustmentsBatch(), 200);
        Test.stopTest();

        List<Inventory_Adjustment__c> untouched = [
            SELECT Id, Archived__c, Archived_Date__c
            FROM Inventory_Adjustment__c
        ];
        for (Inventory_Adjustment__c rec : untouched) {
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
        List<Inventory_Adjustment__c> allRecords = [SELECT Id FROM Inventory_Adjustment__c ORDER BY Name];
        // Only "archive" the first record returned by the mock service.
        Set<Id> partialIds = new Set<Id>{ allRecords[0].Id };

        Test.setMock(HttpCalloutMock.class, new ArchiveConnectorCalloutMock(true, partialIds));

        Test.startTest();
        Database.executeBatch(new ArchiveInventoryAdjustmentsBatch(), 200);
        Test.stopTest();

        Map<Id, Inventory_Adjustment__c> updatedById = new Map<Id, Inventory_Adjustment__c>(
            [SELECT Id, Archived__c FROM Inventory_Adjustment__c]
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
        Test.setMock(HttpCalloutMock.class, new ArchiveConnectorCalloutMock(true, new Set<Id>()));

        Test.startTest();
        String cronExpr = '0 0 2 * * ?'; // daily at 2 AM
        System.schedule('Archive Inventory Adjustments Test', cronExpr, new ArchiveInventoryAdjustmentsBatch());
        Test.stopTest();
    }

    private class ArchiveConnectorCalloutMock implements HttpCalloutMock {
        private Boolean success;
        private Set<Id> archivedIds;

        ArchiveConnectorCalloutMock(Boolean success, Set<Id> archivedIds) {
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