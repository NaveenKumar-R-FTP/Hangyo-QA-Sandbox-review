@isTest
private class ArchiveVisitTasksBatchTest {

    @testSetup
    static void setup() {
        Visit__c visit = new Visit__c();
        insert visit;

        List<Visit_Task__c> tasks = new List<Visit_Task__c>();
        for (Integer i = 0; i < 5; i++) {
            tasks.add(new Visit_Task__c(
                Visit__c = visit.Id
            ));
        }
        insert tasks;
    }

    @isTest
    static void testExecuteBatch_SuccessArchivesTasksAndSnapshotsVisit() {
        List<Visit_Task__c> allTasks = [SELECT Id, Visit__c FROM Visit_Task__c];
        Set<Id> allTaskIds = new Map<Id, Visit_Task__c>(allTasks).keySet();

        Visit__c beforeVisit = [
            SELECT Id, Count_of_Completed_No_Order_Task__c, Count_of_Cancelled_Task__c,
                   Count_of_Completed_Order_Task__c, Count_of_In_Progress_Task__c,
                   Count_of_Not_Started_Task__c, Total_Ad_Hoc_Visits__c,
                   Total_Check_In_and_Check_Out_Time__c, Total_Planned_Visit__c,
                   Total_Tasks_for_Visit__c
            FROM Visit__c
            LIMIT 1
        ];

        Test.setMock(HttpCalloutMock.class, new VisitArchiveConnectorCalloutMock(true, allTaskIds));

        Test.startTest();
        Database.executeBatch(new ArchiveVisitTasksBatch(), 200);
        Test.stopTest();

        List<Visit_Task__c> updatedTasks = [
            SELECT Id, Archived__c, Archived_Date__c
            FROM Visit_Task__c
        ];
        System.assertEquals(allTasks.size(), updatedTasks.size());

        Visit__c afterVisit = [
            SELECT Id, Snapshot_Count_Completed_No_Order_Task__c, Snapshot_Count_of_Cancelled_Task__c,
                   Snapshot_Count_of_Completed_Order_Task__c, Snapshot_Count_of_In_Progress_Task__c,
                   Snapshot_Count_of_Not_Started_Task__c, Snapshot_Total_Ad_Hoc_Visit__c,
                   Snapshot_Total_Check_In_Check_Out_Time__c, Snapshot_Total_Planned_Visit__c,
                   Snapshot_Total_Tasks_for_Visit__c
            FROM Visit__c
            WHERE Id = :beforeVisit.Id
        ];
        System.assertEquals(beforeVisit.Count_of_Completed_No_Order_Task__c, afterVisit.Snapshot_Count_Completed_No_Order_Task__c);
        System.assertEquals(beforeVisit.Count_of_Cancelled_Task__c, afterVisit.Snapshot_Count_of_Cancelled_Task__c);
        System.assertEquals(beforeVisit.Count_of_Completed_Order_Task__c, afterVisit.Snapshot_Count_of_Completed_Order_Task__c);
        System.assertEquals(beforeVisit.Count_of_In_Progress_Task__c, afterVisit.Snapshot_Count_of_In_Progress_Task__c);
        System.assertEquals(beforeVisit.Count_of_Not_Started_Task__c, afterVisit.Snapshot_Count_of_Not_Started_Task__c);
        System.assertEquals(beforeVisit.Total_Ad_Hoc_Visits__c, afterVisit.Snapshot_Total_Ad_Hoc_Visit__c);
        System.assertEquals(beforeVisit.Total_Check_In_and_Check_Out_Time__c, afterVisit.Snapshot_Total_Check_In_Check_Out_Time__c);
        System.assertEquals(beforeVisit.Total_Planned_Visit__c, afterVisit.Snapshot_Total_Planned_Visit__c);
        System.assertEquals(beforeVisit.Total_Tasks_for_Visit__c, afterVisit.Snapshot_Total_Tasks_for_Visit__c);

        Archival_Job_Log__c log = [
            SELECT Archived_Object__c, Total_Processed__c, Total_Archived__c, Total_Failed__c, Error_Message__c
            FROM Archival_Job_Log__c
            LIMIT 1
        ];
        System.assertEquals('Visit_Task__c', log.Archived_Object__c);
    }

    @isTest
    static void testExecuteBatch_FailureLogsErrorAndLeavesTasksAndVisitUntouched() {
        Visit__c beforeVisit = [
            SELECT Id, Snapshot_Total_Tasks_for_Visit__c
            FROM Visit__c
            LIMIT 1
        ];
        System.assertEquals(null, beforeVisit.Snapshot_Total_Tasks_for_Visit__c);

        Test.setMock(HttpCalloutMock.class, new VisitArchiveConnectorCalloutMock(false, new Set<Id>()));

        Test.startTest();
        Database.executeBatch(new ArchiveVisitTasksBatch(), 200);
        Test.stopTest();

        List<Visit_Task__c> untouchedTasks = [SELECT Id, Archived__c FROM Visit_Task__c];
        for (Visit_Task__c t : untouchedTasks) {
            System.assertEquals(false, t.Archived__c, 'Task should remain unarchived when the callout fails');
        }

        Visit__c afterVisit = [
            SELECT Id, Snapshot_Total_Tasks_for_Visit__c
            FROM Visit__c
            WHERE Id = :beforeVisit.Id
        ];
        System.assertEquals(null, afterVisit.Snapshot_Total_Tasks_for_Visit__c,
            'Visit should not be snapshotted when no tasks were archived');

        Archival_Job_Log__c log = [
            SELECT Total_Archived__c, Total_Failed__c, Error_Message__c
            FROM Archival_Job_Log__c
            LIMIT 1
        ];
        System.assertEquals(0, (Integer) log.Total_Archived__c);
        System.assert((Integer) log.Total_Failed__c > 0);
        System.assertNotEquals(null, log.Error_Message__c);
    }

    @isTest
    static void testExecuteBatch_PartialArchiveOnlySnapshotsAffectedVisit() {
        // Second visit with its own task, not returned as archived by the mock.
        Visit__c otherVisit = new Visit__c();
        insert otherVisit;
        Visit_Task__c otherTask = new Visit_Task__c(Visit__c = otherVisit.Id);
        insert otherTask;

        List<Visit_Task__c> originalTasks = [
            SELECT Id, Visit__c FROM Visit_Task__c WHERE Visit__c != :otherVisit.Id
        ];
        Set<Id> partialIds = new Set<Id>{ originalTasks[0].Id };

        Test.setMock(HttpCalloutMock.class, new VisitArchiveConnectorCalloutMock(true, partialIds));

        Test.startTest();
        Database.executeBatch(new ArchiveVisitTasksBatch(), 200);
        Test.stopTest();

        Map<Id, Visit_Task__c> tasksById = new Map<Id, Visit_Task__c>(
            [SELECT Id, Archived__c FROM Visit_Task__c]
        );
        System.assertEquals(true, tasksById.get(originalTasks[0].Id).Archived__c);
        for (Integer i = 1; i < originalTasks.size(); i++) {
            System.assertEquals(false, tasksById.get(originalTasks[i].Id).Archived__c);
        }
        System.assertEquals(false, tasksById.get(otherTask.Id).Archived__c,
            'Task belonging to the untouched visit should not be archived');

        Visit__c untouchedVisitAfter = [
            SELECT Id, Snapshot_Total_Tasks_for_Visit__c FROM Visit__c WHERE Id = :otherVisit.Id
        ];
        System.assertEquals(null, untouchedVisitAfter.Snapshot_Total_Tasks_for_Visit__c,
            'Visit with no archived tasks should not receive a snapshot update');

        Archival_Job_Log__c log = [SELECT Total_Archived__c FROM Archival_Job_Log__c LIMIT 1];
        System.assertEquals(1, (Integer) log.Total_Archived__c);
    }

    @isTest
    static void testSchedulableExecuteKicksOffBatch() {
        Test.setMock(HttpCalloutMock.class, new VisitArchiveConnectorCalloutMock(true, new Set<Id>()));

        Test.startTest();
        String cronExpr = '0 0 3 * * ?'; // daily at 3 AM
        System.schedule('Archive Visit Tasks Test', cronExpr, new ArchiveVisitTasksBatch());
        Test.stopTest();
    }

    private class VisitArchiveConnectorCalloutMock implements HttpCalloutMock {
        private Boolean success;
        private Set<Id> archivedIds;

        VisitArchiveConnectorCalloutMock(Boolean success, Set<Id> archivedIds) {
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