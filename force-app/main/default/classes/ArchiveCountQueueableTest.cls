/**
 * Tests for ArchiveCountQueueable: one job's step of the rollup walk - finishing
 * and publishing day counts, handing over a cursor, accumulating across jobs,
 * giving up at the chain ceiling - plus the stale/missing record guards, failure
 * handling and the two merge helpers.
 *
 * Chaining is disabled in tests (a queueable may not enqueue another), so each
 * test runs exactly one job and asserts on what it wrote.
 */
@IsTest
private class ArchiveCountQueueableTest {

    private static final String OLI = 'Order_Line_Item__c';
    private static final String ILI = 'Invoice_Line_Item__c';
    private static final String BASIS = 'ARCHIVED';

    /**
     * Returns the given rows on every call, with a continuation on every
     * response when endless is true. Records the decoded endpoints it was called
     * with, so a test can see where a job started reading.
     */
    private class CountMock implements HttpCalloutMock {
        private final List<Map<String, Object>> rows;
        private final Boolean endless;
        private String continuationKey = 'PK-next';
        private Integer callCount = 0;
        private final List<String> endpoints = new List<String>();

        private CountMock(List<Map<String, Object>> rows, Boolean endless) {
            this.rows = rows;
            this.endless = endless;
        }

        public HttpResponse respond(HttpRequest req) {
            callCount++;
            endpoints.add(EncodingUtil.urlDecode(req.getEndpoint(), 'UTF-8'));
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(JSON.serialize(new Map<String, Object>{ 'value' => rows }));
            if (endless) {
                res.setHeader('x-ms-continuation-NextPartitionKey', continuationKey);
                res.setHeader('x-ms-continuation-NextRowKey', 'RK-' + callCount);
            }
            return res;
        }
    }

    private static Map<String, Object> row(String dateField, String archivedDay) {
        Map<String, Object> r = new Map<String, Object>{ 'Id' => 'a0T000000000001' };
        if (archivedDay != null) {
            r.put(dateField, archivedDay + 'T10:00:00.000Z');
        }
        return r;
    }

    private static Archive_Row_Count__c runningCount(String objectApiName) {
        return new Archive_Row_Count__c(
            Cache_Key__c       = ArchivedRecordsController.countCacheKey(objectApiName, null, null, BASIS),
            Object_API_Name__c = objectApiName,
            Date_Basis__c      = BASIS,
            Running_Total__c   = 0,
            Callouts_Used__c   = 0,
            Chain_Depth__c     = 0,
            Status__c          = 'Running',
            Started_At__c      = Datetime.now()
        );
    }

    private static void runJob(Id countId) {
        Test.startTest();
        System.enqueueJob(new ArchiveCountQueueable(countId));
        Test.stopTest();
    }

    private static Archive_Row_Count__c reload(Id countId) {
        return [
            SELECT Status__c, Error_Message__c, Running_Total__c, Callouts_Used__c,
                   Chain_Depth__c, Next_Partition_Key__c, Next_Row_Key__c,
                   Completed_At__c, Partial_Tally__c, Partial_Day_Cursors__c
            FROM Archive_Row_Count__c
            WHERE Id = :countId
        ];
    }

    private static Map<Date, Archive_Day_Count__c> dayCounts(String objectApiName) {
        Map<Date, Archive_Day_Count__c> byDay = new Map<Date, Archive_Day_Count__c>();
        for (Archive_Day_Count__c day : [
            SELECT Day__c, Row_Count__c, First_Partition_Key__c, First_Row_Key__c, Cache_Key__c
            FROM Archive_Day_Count__c
            WHERE Object_API_Name__c = :objectApiName
        ]) {
            byDay.put(day.Day__c, day);
        }
        return byDay;
    }

    // ------------------------------------------------------------ finishing a walk

    @IsTest
    static void aWalkThatReachesTheEndPublishesItsDays() {
        Test.setMock(HttpCalloutMock.class, new CountMock(new List<Map<String, Object>>{
            row('Archived_Date__c', '2026-09-01'),
            row('Archived_Date__c', '2026-09-01'),
            row('Archived_Date__c', '2026-09-02'),
            row('Archived_Date__c', null)
        }, false));
        Archive_Row_Count__c state = runningCount(OLI);
        insert state;

        runJob(state.Id);

        Archive_Row_Count__c after = reload(state.Id);
        System.assertEquals('Complete', after.Status__c, 'The archive ran out, so the count is done');
        System.assertEquals(4, after.Running_Total__c, 'Every row is counted, dated or not');
        System.assertEquals(1, after.Chain_Depth__c);
        System.assertEquals(1, after.Callouts_Used__c);
        System.assertEquals(null, after.Next_Partition_Key__c, 'A finished walk keeps no cursor');
        System.assertNotEquals(null, after.Completed_At__c);

        Map<Date, Archive_Day_Count__c> days = dayCounts(OLI);
        System.assertEquals(2, days.size(), 'UNDATED rows are not published as a day: ' + days.keySet());
        System.assertEquals(2, days.get(Date.newInstance(2026, 9, 1)).Row_Count__c);
        System.assertEquals(1, days.get(Date.newInstance(2026, 9, 2)).Row_Count__c);
        System.assertEquals(OLI + '|' + BASIS + '|2026-09-01',
            days.get(Date.newInstance(2026, 9, 1)).Cache_Key__c);
    }

    @IsTest
    static void aRecountReplacesThePublishedDayRatherThanDoublingIt() {
        insert new Archive_Day_Count__c(
            Cache_Key__c       = OLI + '|' + BASIS + '|2026-09-01',
            Object_API_Name__c = OLI,
            Date_Basis__c      = BASIS,
            Day__c             = Date.newInstance(2026, 9, 1),
            Row_Count__c       = 99,
            Counted_At__c      = Datetime.now().addDays(-2)
        );
        Test.setMock(HttpCalloutMock.class, new CountMock(new List<Map<String, Object>>{
            row('Archived_Date__c', '2026-09-01')
        }, false));
        Archive_Row_Count__c state = runningCount(OLI);
        insert state;

        runJob(state.Id);

        Map<Date, Archive_Day_Count__c> days = dayCounts(OLI);
        System.assertEquals(1, days.size(), 'Still one row for the day');
        System.assertEquals(1, days.get(Date.newInstance(2026, 9, 1)).Row_Count__c,
            'The new figure replaces the old one');
    }

    @IsTest
    static void carriedTallyAndCursorsAreFoldedIn() {
        Test.setMock(HttpCalloutMock.class, new CountMock(new List<Map<String, Object>>{
            row('Archived_Date__c', '2026-09-01'),
            row('Archived_Date__c', '2026-09-03')
        }, false));
        Archive_Row_Count__c state = runningCount(OLI);
        state.Running_Total__c = 1000;
        state.Callouts_Used__c = 5;
        state.Chain_Depth__c = 3;
        state.Next_Partition_Key__c = 'PK-resume';
        state.Next_Row_Key__c = 'RK-resume';
        state.Partial_Tally__c = '{"2026-09-01":1000}';
        state.Partial_Day_Cursors__c =
            '{"2026-09-01":{"partitionKey":"PK-first","rowKey":"RK-first"}}';
        insert state;

        runJob(state.Id);

        Archive_Row_Count__c after = reload(state.Id);
        System.assertEquals('Complete', after.Status__c);
        System.assertEquals(1002, after.Running_Total__c, 'This job adds to the running total');
        System.assertEquals(6, after.Callouts_Used__c);
        System.assertEquals(4, after.Chain_Depth__c);

        Map<Date, Archive_Day_Count__c> days = dayCounts(OLI);
        Archive_Day_Count__c first = days.get(Date.newInstance(2026, 9, 1));
        System.assertEquals(1001, first.Row_Count__c, 'Counts for a day accumulate across jobs');
        System.assertEquals('PK-first', first.First_Partition_Key__c,
            'The earliest sighting of a day wins over this job\'s');
        System.assertEquals('RK-first', first.First_Row_Key__c);
        System.assertEquals('PK-resume', days.get(Date.newInstance(2026, 9, 3)).First_Partition_Key__c,
            'A day first met in this job is bounded by where this job started');
    }

    @IsTest
    static void lowerCaseArchivesAreTalliedOnTheirOwnDateField() {
        // Invoice Line Items are archived in lower case; tallying on
        // Archived_Date__c would put every row under UNDATED.
        Test.setMock(HttpCalloutMock.class, new CountMock(new List<Map<String, Object>>{
            row('archived_date__c', '2026-09-05'),
            row('archived_date__c', '2026-09-05')
        }, false));
        Archive_Row_Count__c state = runningCount(ILI);
        insert state;

        runJob(state.Id);

        Map<Date, Archive_Day_Count__c> days = dayCounts(ILI);
        System.assertEquals(1, days.size(), 'The rows are dated, not UNDATED');
        System.assertEquals(2, days.get(Date.newInstance(2026, 9, 5)).Row_Count__c);
    }

    // ------------------------------------------------------------ handing over

    @IsTest
    static void aJobThatRunsOutOfBudgetHandsOverItsCursor() {
        CountMock mock = new CountMock(new List<Map<String, Object>>{
            row('Archived_Date__c', '2026-09-01')
        }, true);
        Test.setMock(HttpCalloutMock.class, mock);
        Archive_Row_Count__c state = runningCount(OLI);
        state.Next_Partition_Key__c = 'PK-start';
        state.Next_Row_Key__c = 'RK-start';
        insert state;

        runJob(state.Id);

        Archive_Row_Count__c after = reload(state.Id);
        System.assertEquals('Running', after.Status__c, 'Not finished, so still running');
        System.assertEquals(ArchiveCountQueueable.CALLOUT_BUDGET, after.Callouts_Used__c,
            'One job spends exactly its budget');
        System.assertEquals(ArchiveCountQueueable.CALLOUT_BUDGET, after.Running_Total__c);
        System.assertEquals('PK-next', after.Next_Partition_Key__c, 'The successor resumes here');
        System.assertNotEquals(null, after.Next_Row_Key__c);
        System.assertEquals(null, after.Completed_At__c);
        System.assert(String.isNotBlank(after.Partial_Tally__c), 'The tally rides along');
        System.assert(mock.endpoints[0].contains('NextPartitionKey=PK-start'),
            'The job starts where the last one stopped: ' + mock.endpoints[0]);
        System.assert(dayCounts(OLI).isEmpty(), 'Nothing is published until the walk ends');
    }

    @IsTest
    static void anOverlongCursorIsTruncatedToFit() {
        CountMock mock = new CountMock(new List<Map<String, Object>>{
            row('Archived_Date__c', '2026-09-01')
        }, true);
        mock.continuationKey = 'K'.repeat(300);
        Test.setMock(HttpCalloutMock.class, mock);
        Archive_Row_Count__c state = runningCount(OLI);
        insert state;

        runJob(state.Id);

        System.assertEquals(255, reload(state.Id).Next_Partition_Key__c.length(),
            'The cursor is cut to the field length rather than failing the save');
    }

    @IsTest
    static void aChainThatCannotFinishGivesUp() {
        Test.setMock(HttpCalloutMock.class, new CountMock(new List<Map<String, Object>>{
            row('Archived_Date__c', '2026-09-01')
        }, true));
        Archive_Row_Count__c state = runningCount(OLI);
        state.Chain_Depth__c = ArchiveCountQueueable.MAX_CHAIN_DEPTH - 1;
        insert state;

        runJob(state.Id);

        Archive_Row_Count__c after = reload(state.Id);
        System.assertEquals('Failed', after.Status__c, 'An unbounded count must stop');
        System.assert(after.Error_Message__c.contains('chained jobs'), after.Error_Message__c);
        System.assert(after.Running_Total__c > 0, 'What it did count is still recorded');
        System.assertNotEquals(null, after.Completed_At__c);
    }

    // ------------------------------------------------------------ guards and failures

    @IsTest
    static void aFailedReadFailsTheCount() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.ServerErrorMock());
        Archive_Row_Count__c state = runningCount(OLI);
        insert state;

        runJob(state.Id);

        Archive_Row_Count__c after = reload(state.Id);
        System.assertEquals('Failed', after.Status__c);
        System.assert(after.Error_Message__c.startsWith('ARCHIVE_HTTP_500'), after.Error_Message__c);
        System.assertNotEquals(null, after.Completed_At__c);
    }

    @IsTest
    static void aFinishedCountIsNotResumed() {
        CountMock mock = new CountMock(new List<Map<String, Object>>(), false);
        Test.setMock(HttpCalloutMock.class, mock);
        Archive_Row_Count__c state = runningCount(OLI);
        state.Status__c = 'Complete';
        state.Running_Total__c = 42;
        insert state;

        runJob(state.Id);

        System.assertEquals(0, mock.callCount, 'A stale job makes no callout');
        Archive_Row_Count__c after = reload(state.Id);
        System.assertEquals('Complete', after.Status__c);
        System.assertEquals(42, after.Running_Total__c, 'The finished total is untouched');
    }

    @IsTest
    static void aDeletedCountIsIgnored() {
        Archive_Row_Count__c state = runningCount(OLI);
        insert state;
        Id goneId = state.Id;
        delete state;

        runJob(goneId);

        System.assertEquals(0, [SELECT COUNT() FROM Archive_Row_Count__c], 'Nothing is recreated');
    }

    @IsTest
    static void anUnreadableCarriedTallyFailsVisibly() {
        Test.setMock(HttpCalloutMock.class, new CountMock(new List<Map<String, Object>>{
            row('Archived_Date__c', '2026-09-01')
        }, false));
        Archive_Row_Count__c state = runningCount(OLI);
        state.Partial_Tally__c = 'not json';
        insert state;

        runJob(state.Id);

        Archive_Row_Count__c after = reload(state.Id);
        System.assertEquals('Failed', after.Status__c, 'Undercounting silently would be worse');
        System.assert(after.Error_Message__c.contains('Partial tally'), after.Error_Message__c);
    }

    @IsTest
    static void unreadableCarriedCursorsFailVisibly() {
        Test.setMock(HttpCalloutMock.class, new CountMock(new List<Map<String, Object>>{
            row('Archived_Date__c', '2026-09-01')
        }, false));
        Archive_Row_Count__c state = runningCount(OLI);
        state.Partial_Day_Cursors__c = '["not", "a", "map"]';
        insert state;

        runJob(state.Id);

        Archive_Row_Count__c after = reload(state.Id);
        System.assertEquals('Failed', after.Status__c);
        System.assert(after.Error_Message__c.contains('Partial day cursors'), after.Error_Message__c);
    }

    // ------------------------------------------------------------ merge helpers

    @IsTest
    static void mergeTallyHandlesNothingCarriedAndNothingNew() {
        System.assert(ArchiveCountQueueable.mergeTally(null, null).isEmpty());

        Map<String, Integer> fresh = ArchiveCountQueueable.mergeTally(
            '', new Map<String, Integer>{ '2026-09-01' => 3 });
        System.assertEquals(3, fresh.get('2026-09-01'));

        Map<String, Integer> carriedOnly = ArchiveCountQueueable.mergeTally('{"2026-09-01":4}', null);
        System.assertEquals(4, carriedOnly.get('2026-09-01'));
    }

    @IsTest
    static void mergeCursorsKeepsTheFirstSightingAndNullBounds() {
        Map<String, ArchiveReadService.DayCursor> merged = ArchiveCountQueueable.mergeCursors(
            '{"2026-09-01":{"partitionKey":null,"rowKey":null},"2026-09-02":null}',
            new Map<String, ArchiveReadService.DayCursor>{
                '2026-09-01' => new ArchiveReadService.DayCursor('PK-late', 'RK-late'),
                '2026-09-03' => new ArchiveReadService.DayCursor('PK-3', 'RK-3')
            });

        System.assertEquals(3, merged.size());
        System.assertEquals(null, merged.get('2026-09-01').partitionKey,
            'A day that opens at the top of the table keeps that bound');
        System.assertEquals(null, merged.get('2026-09-02').partitionKey, 'A null entry is still an entry');
        System.assertEquals('PK-3', merged.get('2026-09-03').partitionKey, 'A new day is added');
        System.assert(ArchiveCountQueueable.mergeCursors(null, null).isEmpty());
    }
}