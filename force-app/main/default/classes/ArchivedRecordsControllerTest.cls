@IsTest
private class ArchivedRecordsControllerTest {

    private static final String OLI = 'Order_Line_Item__c';
    private static final String VISIT_TASK = 'Visit_Task__c';

    private static List<String> only(String objectApiName) {
        return new List<String>{ objectApiName };
    }

    /** yyyy-MM-dd, the shape lightning-input type="date" sends the controller. */
    private static String isoDate(Date value) {
        return DateTime.newInstance(value, Time.newInstance(0, 0, 0, 0)).format('yyyy-MM-dd');
    }

    @TestSetup
    static void setup() {
        // Committed in its own transaction so the degraded-path tests can still
        // make a callout without tripping "uncommitted work pending".
        List<Archival_Log__c> logs = new List<Archival_Log__c>();
        for (Integer i = 0; i < 12; i++) {
            logs.add(new Archival_Log__c(
                Archived_Record_Id__c   = 'a0B00000000' + String.valueOf(i).leftPad(4, '0') + 'AA',
                Archived_Object__c      = OLI,
                Parent_Record_Id__c     = '80100000000' + String.valueOf(i).leftPad(4, '0'),
                Parent_Record_Name__c   = 'PO-2025-' + i,
                Parent_Object__c        = 'Order__c',
                Original_CreatedDate__c = Datetime.newInstance(2025, 2, 10 + i, 9, 0, 0),
                Archive_Batch_Id__c     = '707000000000ABC',
                Archived_Location__c    = 'hangyo-archive/orderlineitem/2025/02/batch.parquet',
                CheckSum__c             = 'sha256:abc',
                Soft_Archived_Date__c   = Datetime.newInstance(2026, 8, 30, 6, 57, 30),
                Status__c               = 'Soft-Archived'
            ));
        }
        // Outside the date window used by the range test.
        logs.add(new Archival_Log__c(
            Archived_Record_Id__c   = 'a0B0000000099999AA',
            Archived_Object__c      = OLI,
            Parent_Record_Id__c     = '801000000009999',
            Parent_Record_Name__c   = 'PO-2024-OLD',
            Parent_Object__c        = 'Order__c',
            Original_CreatedDate__c = Datetime.newInstance(2024, 1, 1, 9, 0, 0),
            Archive_Batch_Id__c     = '707000000000XYZ',
            Archived_Location__c    = 'hangyo-archive/orderlineitem/2024/01/batch.parquet',
            CheckSum__c             = 'sha256:def',
            Soft_Archived_Date__c   = Datetime.newInstance(2026, 8, 30, 6, 57, 30),
            Status__c               = 'Hard-Deleted'
        ));
        // A second object, so the multi-object fallback has something to merge.
        for (Integer i = 0; i < 4; i++) {
            logs.add(new Archival_Log__c(
                Archived_Record_Id__c   = 'a0X00000000' + String.valueOf(i).leftPad(4, '0') + 'AA',
                Archived_Object__c      = VISIT_TASK,
                Parent_Record_Id__c     = 'a0V00000000' + String.valueOf(i).leftPad(4, '0'),
                Parent_Record_Name__c   = 'VISIT-' + i,
                Parent_Object__c        = 'Visit__c',
                Original_CreatedDate__c = Datetime.newInstance(2025, 2, 20 + i, 9, 0, 0),
                Archive_Batch_Id__c     = '707000000000VST',
                Archived_Location__c    = 'hangyo-archive/visittask/2025/02/batch.parquet',
                CheckSum__c             = 'sha256:ghi',
                Soft_Archived_Date__c   = Datetime.newInstance(2026, 8, 30, 6, 57, 30),
                Status__c               = 'Soft-Archived'
            ));
        }

        insert logs;
    }

    @IsTest
    static void objectOptionsFollowConfiguration() {
        Test.startTest();
        List<ArchivedRecordsController.ObjectOption> options =
            ArchivedRecordsController.getObjectOptions();
        Test.stopTest();

        System.assert(!options.isEmpty(), 'Expected at least one in-scope object');

        Set<String> apiNames = new Set<String>();
        for (ArchivedRecordsController.ObjectOption opt : options) {
            apiNames.add(opt.value);
            System.assert(String.isNotBlank(opt.label), 'Every option needs a label');
        }
        System.assert(
            apiNames.contains(OLI),
            'Order_Line_Item__c is configured and should appear: ' + apiNames
        );
    }

    @IsTest
    static void returnsArchiveRowsWhenEndpointIsLive() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.SuccessMock(5));

        Test.startTest();
        ArchivedRecordsController.ReportPage page =
            ArchivedRecordsController.getArchivedRecords(only(OLI), '2025-01-01', '2025-03-31', 50, 1, null);
        Test.stopTest();

        System.assertEquals(false, page.degraded, 'A live endpoint must not degrade');
        System.assertEquals(5, page.totalCount,
            'The archive reports no count, so the total is what was actually retrieved');
        System.assertEquals(5, page.rows.size());
        // A token-paged read has no total to divide into pages, so totalPages is
        // 0 by design and the client shows a page number rather than "of N".
        System.assertEquals(true, page.tokenPaged, 'A single routable object pages by token');
        System.assertEquals(0, page.totalPages, 'No count means no page span');
        System.assertEquals(false, page.hasMore, 'The mock offered no continuation');
        System.assertEquals(false, page.isCapped, 'A complete result is not capped');
        System.assert(page.unavailableObjects.isEmpty(), 'Order Line Item has a published route');
        System.assert(!page.columns.isEmpty(), 'Columns should be described from the object');

        // Name is no longer an Order Line Item column, so the row is identified by
        // its key - the archived Id of mock row 0, which carries the newest date.
        Map<String, Object> firstRow = page.rows[0];
        System.assertEquals('a0TGB00003oqsw0000', (String) firstRow.get('_rowKey'),
            'Rows are newest-first, and the mock dates descend with the index');
    }

    @IsTest
    static void fallsBackToArchivalLogWhenEndpointMissing() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.NotFoundMock());

        Test.startTest();
        ArchivedRecordsController.ReportPage page =
            ArchivedRecordsController.getArchivedRecords(only(OLI), null, null, 50, 1, null);
        Test.stopTest();

        System.assertEquals(true, page.degraded, 'A 404 read should degrade to the log index');
        System.assert(String.isNotBlank(page.degradedReason), 'The user must be told why');
        System.assertEquals(13, page.totalCount, 'Only the selected object should be counted');
        System.assertEquals(13, page.rows.size());
    }

    @IsTest
    static void fallbackAppliesDateRange() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.NotFoundMock());

        Test.startTest();
        ArchivedRecordsController.ReportPage page =
            ArchivedRecordsController.getArchivedRecords(only(OLI), '2025-02-01', '2025-02-28', 50, 1, 'CREATED');
        Test.stopTest();

        System.assertEquals(true, page.degraded);
        System.assertEquals(12, page.totalCount, 'The 2024 row is outside the window');
    }

    @IsTest
    static void defaultDateBasisIsArchivedNotCreated() {
        // These records were created in Feb 2025 and archived on 2026-08-30. A
        // window over the archive run must find them by default; the same window
        // on created date must not. Getting this backwards is what made the
        // report return nothing for every recent range.
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.NotFoundMock());

        Test.startTest();
        ArchivedRecordsController.ReportPage byArchived =
            ArchivedRecordsController.getArchivedRecords(
                only(OLI), '2026-08-01', '2026-08-31', 50, 1, null);
        ArchivedRecordsController.ReportPage byCreated =
            ArchivedRecordsController.getArchivedRecords(
                only(OLI), '2026-08-01', '2026-08-31', 50, 1, 'CREATED');
        Test.stopTest();

        System.assertEquals('ARCHIVED', byArchived.dateBasis, 'Archived date is the default');
        System.assertEquals(13, byArchived.totalCount,
            'Every Order Line Item row was archived inside this window');
        System.assertEquals(0, byCreated.totalCount,
            'None of them were created inside it - the two dates are a year apart');
    }

    @IsTest
    static void fallbackPaginates() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.NotFoundMock());

        Test.startTest();
        ArchivedRecordsController.ReportPage pageOne =
            ArchivedRecordsController.getArchivedRecords(only(OLI), null, null, 5, 1, null);
        Test.stopTest();

        System.assertEquals(5, pageOne.rows.size());
        System.assertEquals(3, pageOne.totalPages, '13 rows at 5 per page is 3 pages');
        System.assertEquals(1, pageOne.pageNumber);
    }

    @IsTest
    static void serverErrorSurfacesToTheUser() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.ServerErrorMock());

        Test.startTest();
        try {
            ArchivedRecordsController.getArchivedRecords(only(OLI), null, null, 50, 1, null);
            System.assert(false, 'A 500 should not be swallowed');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void rejectsInvertedDateRange() {
        Test.startTest();
        try {
            ArchivedRecordsController.getArchivedRecords(only(OLI), '2025-06-01', '2025-01-01', 50, 1, null);
            System.assert(false, 'From after To should be rejected');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException');
        }
        Test.stopTest();
    }

    /**
     * The day cap is the server-side backstop for the UI's date-range picker. Both
     * halves matter: a range wider than the cap must be refused, and a range
     * sitting exactly on it must not be - the picker's own "Last 90 days" preset
     * spans precisely MAX_RANGE_DAYS, so an off-by-one here would reject the
     * report's default filter.
     */
    @IsTest
    static void rejectsDateRangeWiderThanTheDayCap() {
        Test.startTest();
        try {
            ArchivedRecordsController.getArchivedRecords(
                only(OLI), '2026-01-01', '2026-12-31', 50, 1, null);
            System.assert(false, 'A 364-day range should be rejected');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void acceptsDateRangeExactlyOnTheDayCap() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.NotFoundMock());

        // 90 days apart to the day, matching what the Last 90 days preset emits.
        Date rangeEnd = Date.today();
        Date rangeStart = rangeEnd.addDays(-ArchivedRecordsController.MAX_RANGE_DAYS);
        System.assertEquals(
            ArchivedRecordsController.MAX_RANGE_DAYS,
            rangeStart.daysBetween(rangeEnd),
            'Fixture must sit exactly on the cap for this test to mean anything'
        );

        Test.startTest();
        ArchivedRecordsController.ReportPage page = ArchivedRecordsController.getArchivedRecords(
            only(OLI), isoDate(rangeStart), isoDate(rangeEnd), 50, 1, null);
        Test.stopTest();

        System.assertNotEquals(null, page, 'A range on the cap must be served, not refused');
    }

    /**
     * An open-ended range is bounded by the row cap rather than the day cap, and
     * several callers rely on that - so widening the guard to cover nulls would be
     * a behaviour change, not a tightening.
     */
    @IsTest
    static void openEndedRangeIsNotSubjectToTheDayCap() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.NotFoundMock());

        Test.startTest();
        ArchivedRecordsController.ReportPage page =
            ArchivedRecordsController.getArchivedRecords(only(OLI), null, null, 50, 1, null);
        Test.stopTest();

        System.assertNotEquals(null, page, 'No bounds means no span to cap');
    }

    @IsTest
    static void rejectsUnknownObject() {
        Test.startTest();
        try {
            ArchivedRecordsController.getArchivedRecords(only('Not_A_Real_Object__c'), null, null, 50, 1, null);
            System.assert(false, 'Unknown objects should be rejected');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void rejectsBlankObject() {
        Test.startTest();
        try {
            ArchivedRecordsController.getArchivedRecords(new List<String>{ '' }, null, null, 50, 1, null);
            System.assert(false, 'A blank object should be rejected');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void pageSizeIsClamped() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.SuccessMock(2));

        Test.startTest();
        ArchivedRecordsController.ReportPage page =
            ArchivedRecordsController.getArchivedRecords(only(OLI), null, null, 5000, 0, null);
        Test.stopTest();

        System.assertEquals(200, page.pageSize, 'Page size should be capped at 200');
        System.assertEquals(1, page.pageNumber, 'Page number below 1 should normalise to 1');
    }

    @IsTest
    static void buildsColumnsForEveryConfiguredObject() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.SuccessMock(0));

        List<ArchivedRecordsController.ObjectOption> options =
            ArchivedRecordsController.getObjectOptions();

        Test.startTest();
        for (ArchivedRecordsController.ObjectOption opt : options) {
            ArchivedRecordsController.ReportPage page =
                ArchivedRecordsController.getArchivedRecords(only(opt.value), null, null, 50, 1, null);
            System.assert(
                !page.columns.isEmpty(),
                'Every configured object needs at least one readable column: ' + opt.value
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void multiObjectFallbackMergesAndLabelsRows() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.NotFoundMock());

        Test.startTest();
        ArchivedRecordsController.ReportPage page = ArchivedRecordsController.getArchivedRecords(
            new List<String>{ OLI, VISIT_TASK }, null, null, 50, 1, null);
        Test.stopTest();

        System.assertEquals(true, page.degraded);
        System.assertEquals(17, page.totalCount, '13 order line item rows plus 4 visit task rows');
        System.assertEquals(17, page.rows.size());

        Set<String> labels = new Set<String>();
        for (Map<String, Object> row : page.rows) {
            labels.add(String.valueOf(row.get('_objectLabel')));
        }
        System.assertEquals(2, labels.size(), 'Both objects should be represented: ' + labels);
    }

    @IsTest
    static void objectColumnIsAlwaysFirst() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.NotFoundMock());

        Test.startTest();
        ArchivedRecordsController.ReportPage page = ArchivedRecordsController.getArchivedRecords(
            new List<String>{ OLI, VISIT_TASK }, null, null, 50, 1, null);
        Test.stopTest();

        System.assertEquals('_objectLabel', page.columns[0].fieldName, 'Object column leads the table');
        System.assertEquals('Object', page.columns[0].label);
    }

    @IsTest
    static void everyRoutableObjectContributesToAMixedRead() {
        // Order Line Item and Visit Task both have retrieval routes now, so a mixed
        // selection reads both archives and merges them into one windowed result -
        // neither object is dropped from the total.
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.SuccessMock(7));

        Test.startTest();
        ArchivedRecordsController.ReportPage page = ArchivedRecordsController.getArchivedRecords(
            new List<String>{ OLI, VISIT_TASK }, null, null, 10, 1, null);
        Test.stopTest();

        System.assertEquals(false, page.degraded, 'Readable objects stay on the archive');
        System.assertEquals(14, page.totalCount, 'Both objects contribute their rows');
        System.assertEquals(false, page.tokenPaged, 'Two objects cannot share one token');
        System.assertEquals(10, page.rows.size(), 'One page of the merged rows');
        System.assert(page.unavailableObjects.isEmpty(),
            'Both objects have a route: ' + page.unavailableObjects);
    }

    @IsTest
    static void objectsWithNoArchiveRouteAreNamedNotSilentlyDropped() {
        // Account has no archive route at all. Mixed with Order Line Item, the
        // Order Line Item rows are reported and Account is named as contributing
        // none, rather than a total that silently covers fewer objects.
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.SuccessMock(7));

        Test.startTest();
        ArchivedRecordsController.ReportPage page = ArchivedRecordsController.getArchivedRecords(
            new List<String>{ OLI, 'Account' }, null, null, 10, 1, null);
        Test.stopTest();

        System.assertEquals(false, page.degraded,
            'One readable object is enough to stay on the archive rather than the log');
        System.assertEquals(7, page.totalCount, 'Only the readable object contributes rows');
        System.assertEquals(1, page.unavailableObjects.size(),
            'Account has no route and must be named: ' + page.unavailableObjects);
    }

    @IsTest
    static void cappedArchiveResultIsFlaggedToTheUser() {
        // A surviving continuation token means the archive has more to give. On a
        // token-paged read that is ordinary - it is simply "there is a next page",
        // reported as hasMore with the token to reach it. It must NOT come back as
        // isCapped: that flag drives a "partial result, narrow your range" banner,
        // and raising it on every page of a normal read would be nonsense.
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.EndlessMock(1000));

        Test.startTest();
        ArchivedRecordsController.ReportPage page =
            ArchivedRecordsController.getArchivedRecords(only(OLI), null, null, 50, 1, null);
        Test.stopTest();

        System.assertEquals(true, page.tokenPaged, 'Order Line Item pages by token');
        System.assertEquals(true, page.hasMore, 'A surviving continuation means a next page');
        System.assertNotEquals(null, page.nextContinuation, 'The next page needs its token');
        System.assertEquals(false, page.isCapped,
            'Ordinary paging must not raise the partial-result warning');
        System.assertEquals(50, page.rows.size(), 'The page holds exactly one page of rows');
    }

    /**
     * The token round trip. Page two must be fetched with the token page one
     * handed back - there is no $skip to fall back on, so if the token is not
     * carried through, page two silently repeats page one.
     */
    @IsTest
    static void continuationTokenCarriesToTheNextPage() {
        ArchiveReadServiceMocks.EndlessMock mock = new ArchiveReadServiceMocks.EndlessMock(1000);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ArchivedRecordsController.ReportPage first =
            ArchivedRecordsController.getArchivedRecordsPage(
                only(OLI), null, null, 50, 1, null, null);
        ArchivedRecordsController.ReportPage second =
            ArchivedRecordsController.getArchivedRecordsPage(
                only(OLI), null, null, 50, 2, null, first.nextContinuation);
        Test.stopTest();

        System.assertNotEquals(null, first.nextContinuation, 'Page one must yield a token');
        System.assertEquals(50, second.rows.size(), 'Page two is a full page');
        System.assertEquals(2, second.pageNumber);
        System.assertNotEquals(
            first.nextContinuation,
            second.nextContinuation,
            'Page two must advance the cursor, not hand back page one\'s token'
        );
    }

    /** An unreadable token falls back to the first page rather than throwing. */
    @IsTest
    static void malformedContinuationIsTreatedAsTheFirstPage() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.SuccessMock(5));

        Test.startTest();
        ArchivedRecordsController.ReportPage page =
            ArchivedRecordsController.getArchivedRecordsPage(
                only(OLI), null, null, 50, 1, null, 'not json at all');
        Test.stopTest();

        System.assertEquals(5, page.rows.size(), 'A bad token must not break the read');
    }

    // ------------------------------------------------------------------- count

    /**
     * The first call enqueues the chain and reports nothing yet.
     *
     * This is the shape the whole count design forces. The archive publishes no
     * row count, so a total means reading every matching row at a thousand a
     * callout, and one transaction allows a hundred - so the answer cannot come
     * back in the request that asks for it. What comes back is "started".
     */
    @IsTest
    static void countStartsAChainAndReportsIncomplete() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.SuccessMock(37));

        Test.startTest();
        ArchivedRecordsController.ArchiveCount counted =
            ArchivedRecordsController.getArchivedRecordCount(only(OLI), null, null, null, false);
        Integer queued = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(false, counted.isComplete, 'Nothing is counted synchronously');
        System.assertEquals(1, queued, 'One counting job should have been enqueued');

        List<Archive_Row_Count__c> state = [
            SELECT Status__c, Running_Total__c, Object_API_Name__c
            FROM Archive_Row_Count__c
        ];
        System.assertEquals(1, state.size(), 'One cache row per object counted');
        System.assertEquals(OLI, state[0].Object_API_Name__c);
        // stopTest ran the queued job, and the mock's archive ends after one page.
        System.assertEquals('Complete', state[0].Status__c, 'One page means one job finishes it');
        System.assertEquals(37, state[0].Running_Total__c, 'Every matching row counted');
    }

    /** Builds a finished rollup: the walk is done and its days are published. */
    private static void seedRollup(String basis, Map<Date, Integer> byDay) {
        insert new Archive_Row_Count__c(
            Cache_Key__c       = ArchivedRecordsController.countCacheKey(OLI, null, null, basis),
            Object_API_Name__c = OLI,
            Date_Basis__c      = basis,
            Running_Total__c   = 0,
            Callouts_Used__c   = 9653,
            Status__c          = 'Complete',
            Started_At__c      = Datetime.now().addMinutes(-40),
            Completed_At__c    = Datetime.now().addMinutes(-1)
        );

        List<Archive_Day_Count__c> days = new List<Archive_Day_Count__c>();
        for (Date day : byDay.keySet()) {
            days.add(new Archive_Day_Count__c(
                Cache_Key__c       = OLI + '|' + basis + '|' + String.valueOf(day),
                Object_API_Name__c = OLI,
                Date_Basis__c      = basis,
                Day__c             = day,
                Row_Count__c       = byDay.get(day),
                Counted_At__c      = Datetime.now()
            ));
        }
        insert days;
    }

    /**
     * The point of the whole rollup: once built, a total is one SOQL aggregate
     * and costs no callouts at all.
     */
    @IsTest
    static void totalComesFromTheRollupWithoutCallouts() {
        seedRollup('ARCHIVED', new Map<Date, Integer>{
            Date.newInstance(2026, 8, 30) => 9652401
        });

        Test.startTest();
        ArchivedRecordsController.ArchiveCount counted =
            ArchivedRecordsController.getArchivedRecordCount(
                only(OLI), '2026-06-23', '2026-09-21', null, false);
        Integer callouts = Limits.getCallouts();
        Integer queued = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(true, counted.isComplete);
        System.assertEquals(9652401, counted.total, 'Summed straight out of the rollup');
        System.assertEquals(0, callouts, 'A built rollup must never touch the archive');
        System.assertEquals(0, queued, 'Nor start a walk');
    }

    /**
     * The rollup is stored per day precisely so that an arbitrary range can be
     * answered from it. A range must include only the days it covers.
     */
    @IsTest
    static void totalSumsOnlyTheDaysInRange() {
        seedRollup('ARCHIVED', new Map<Date, Integer>{
            Date.newInstance(2026, 7, 1)  => 100,
            Date.newInstance(2026, 8, 30) => 9652401,
            Date.newInstance(2026, 9, 15) => 25
        });

        Test.startTest();
        ArchivedRecordsController.ArchiveCount august =
            ArchivedRecordsController.getArchivedRecordCount(
                only(OLI), '2026-08-01', '2026-08-31', null, false);
        ArchivedRecordsController.ArchiveCount everything =
            ArchivedRecordsController.getArchivedRecordCount(
                only(OLI), null, null, null, false);
        ArchivedRecordsController.ArchiveCount empty =
            ArchivedRecordsController.getArchivedRecordCount(
                only(OLI), '2026-09-20', '2026-09-21', null, false);
        Test.stopTest();

        System.assertEquals(9652401, august.total, 'Only the August day');
        System.assertEquals(9652526, everything.total, 'Unbounded sums every day');
        System.assertEquals(0, empty.total, 'A range with no archive run is genuinely zero');
        System.assertEquals(true, empty.isComplete, 'And that zero is a real answer, not a gap');
    }

    /**
     * Archived date and created date are rolled up separately, because the report
     * lets the user pick and for this data they are a year apart. A created-date
     * question must not be answered out of the archived-date rollup.
     */
    @IsTest
    static void rollupsAreSeparatePerDateBasis() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.SuccessMock(3));
        seedRollup('ARCHIVED', new Map<Date, Integer>{
            Date.newInstance(2026, 8, 30) => 9652401
        });

        Test.startTest();
        ArchivedRecordsController.ArchiveCount created =
            ArchivedRecordsController.getArchivedRecordCount(
                only(OLI), null, null, 'CREATED', false);
        Test.stopTest();

        System.assertEquals(false, created.isComplete,
            'No created-date rollup exists yet, so it must be built rather than borrowed');
        System.assertEquals(true, created.isBuilding);
    }

    /** Refresh discards the cached total and counts again. */
    @IsTest
    static void forceRecountDiscardsTheCachedTotal() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.SuccessMock(5));
        insert new Archive_Row_Count__c(
            Cache_Key__c       = ArchivedRecordsController.countCacheKey(OLI, null, null, 'ARCHIVED'),
            Object_API_Name__c = OLI,
            Date_Basis__c      = 'ARCHIVED',
            Running_Total__c   = 999,
            Status__c          = 'Complete',
            Started_At__c      = Datetime.now().addMinutes(-5),
            Completed_At__c    = Datetime.now().addMinutes(-1)
        );

        Test.startTest();
        ArchivedRecordsController.getArchivedRecordCount(only(OLI), null, null, null, true);
        Integer queued = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(1, queued, 'Forcing must start a new walk');
        Archive_Row_Count__c after = [
            SELECT Running_Total__c, Status__c FROM Archive_Row_Count__c LIMIT 1
        ];
        System.assertEquals(5, after.Running_Total__c, 'The stale 999 must be replaced, not added to');
    }

    /**
     * A long count must NOT be mistaken for a dead one.
     *
     * Counting the archive takes about thirty-five minutes, and stall detection
     * originally measured from the moment the count started - so a healthy chain
     * was declared dead partway through and restarted from zero, which meant a
     * watched count could never finish. Progress is what proves life: this row
     * was started long ago but written to just now.
     */
    @IsTest
    static void aLongRunningCountIsNotRestarted() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.SuccessMock(8));
        insert new Archive_Row_Count__c(
            Cache_Key__c       = ArchivedRecordsController.countCacheKey(OLI, null, null, 'ARCHIVED'),
            Object_API_Name__c = OLI,
            Date_Basis__c      = 'ARCHIVED',
            Running_Total__c   = 5400000,
            Status__c          = 'Running',
            // Hours old, but LastModifiedDate is now - the chain is mid-walk.
            Started_At__c      = Datetime.now().addHours(-3)
        );

        Test.startTest();
        ArchivedRecordsController.ArchiveCount counted =
            ArchivedRecordsController.getArchivedRecordCount(only(OLI), null, null, null, false);
        Integer queued = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(0, queued, 'A count still making progress must be left alone');
        System.assertEquals(false, counted.isComplete, 'Still counting');
        System.assertEquals(5400000, counted.total, 'Its progress so far is reported as a floor');
    }

    /** No archive route anywhere: count the in-org index instead, and say so. */
    @IsTest
    static void countDegradesToTheArchivalLog() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.NotFoundMock());

        Test.startTest();
        ArchivedRecordsController.ArchiveCount counted =
            // Every archived object has a route now; Account has none.
            ArchivedRecordsController.getArchivedRecordCount(
                only('Account'), '2026-08-01', '2026-08-31', null, false);
        Test.stopTest();

        System.assertEquals(true, counted.degraded, 'No route means the log index is counted');
        System.assertEquals(true, counted.isComplete, 'A SOQL count of the log is immediate');
    }

    /**
     * A chain that cannot reach the end fails visibly rather than running for
     * ever. The endless mock never stops offering more, which is exactly the
     * shape of a filter matching more rows than the design counts.
     */
    @IsTest
    static void countChainGivesUpRatherThanLooping() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.EndlessMock(1000));

        Archive_Row_Count__c state = new Archive_Row_Count__c(
            Cache_Key__c       = ArchivedRecordsController.countCacheKey(OLI, null, null, 'ARCHIVED'),
            Object_API_Name__c = OLI,
            Date_Basis__c      = 'ARCHIVED',
            Running_Total__c   = 0,
            Callouts_Used__c   = 0,
            // One short of the ceiling, so this job is the one that must give up.
            Chain_Depth__c     = ArchiveCountQueueable.MAX_CHAIN_DEPTH - 1,
            Status__c          = 'Running',
            Started_At__c      = Datetime.now()
        );
        insert state;

        Test.startTest();
        System.enqueueJob(new ArchiveCountQueueable(state.Id));
        Test.stopTest();

        Archive_Row_Count__c after = [
            SELECT Status__c, Error_Message__c, Running_Total__c
            FROM Archive_Row_Count__c WHERE Id = :state.Id
        ];
        System.assertEquals('Failed', after.Status__c, 'An unbounded count must stop');
        System.assert(
            after.Error_Message__c.contains('chained jobs'),
            'The failure must say why: ' + after.Error_Message__c
        );
        System.assert(after.Running_Total__c > 0, 'What it did count is still recorded');
    }

    /** A partway job records its cursor so the next one resumes, not restarts. */
    @IsTest
    static void countJobHandsItsCursorOn() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.EndlessMock(1000));

        Archive_Row_Count__c state = new Archive_Row_Count__c(
            Cache_Key__c       = ArchivedRecordsController.countCacheKey(OLI, null, null, 'ARCHIVED'),
            Object_API_Name__c = OLI,
            Date_Basis__c      = 'ARCHIVED',
            Running_Total__c   = 0,
            Callouts_Used__c   = 0,
            Chain_Depth__c     = 0,
            Status__c          = 'Running',
            Started_At__c      = Datetime.now()
        );
        insert state;

        Test.startTest();
        System.enqueueJob(new ArchiveCountQueueable(state.Id));
        Test.stopTest();

        Archive_Row_Count__c after = [
            SELECT Status__c, Running_Total__c, Next_Partition_Key__c, Chain_Depth__c
            FROM Archive_Row_Count__c WHERE Id = :state.Id
        ];
        System.assertEquals('Running', after.Status__c, 'Still more archive to walk');
        System.assertNotEquals(null, after.Next_Partition_Key__c,
            'Without a cursor the next job would recount from the beginning');
        System.assertEquals(1, after.Chain_Depth__c);
        System.assert(after.Running_Total__c > 0, 'This job counted something');
    }

    /** A job whose record is no longer Running must not resume a finished walk. */
    @IsTest
    static void countJobIgnoresASupersededRecord() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.EndlessMock(1000));

        Archive_Row_Count__c state = new Archive_Row_Count__c(
            Cache_Key__c       = ArchivedRecordsController.countCacheKey(OLI, null, null, 'ARCHIVED'),
            Object_API_Name__c = OLI,
            Date_Basis__c      = 'ARCHIVED',
            Running_Total__c   = 42,
            Status__c          = 'Complete',
            Started_At__c      = Datetime.now(),
            Completed_At__c    = Datetime.now()
        );
        insert state;

        Test.startTest();
        System.enqueueJob(new ArchiveCountQueueable(state.Id));
        Test.stopTest();

        Archive_Row_Count__c after = [
            SELECT Running_Total__c FROM Archive_Row_Count__c WHERE Id = :state.Id
        ];
        System.assertEquals(42, after.Running_Total__c, 'A stale job must change nothing');
    }

    @IsTest
    static void rejectsEmptyObjectList() {
        Test.startTest();
        try {
            ArchivedRecordsController.getArchivedRecords(new List<String>(), null, null, 50, 1, null);
            System.assert(false, 'An empty selection should be rejected');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void rejectsNullObjectList() {
        Test.startTest();
        try {
            ArchivedRecordsController.getArchivedRecords(null, null, null, 50, 1, null);
            System.assert(false, 'A null selection should be rejected');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException');
        }
        Test.stopTest();
    }

    /** Seeds a rollup whose days carry recorded start cursors. */
    private static void seedRollupWithCursors(
        String basis,
        Map<Date, String> cursorByDay
    ) {
        List<Archive_Day_Count__c> days = new List<Archive_Day_Count__c>();
        for (Date day : cursorByDay.keySet()) {
            days.add(new Archive_Day_Count__c(
                Cache_Key__c           = OLI + '|' + basis + '|' + String.valueOf(day),
                Object_API_Name__c     = OLI,
                Date_Basis__c          = basis,
                Day__c                 = day,
                Row_Count__c           = 100,
                Counted_At__c          = Datetime.now(),
                First_Partition_Key__c = cursorByDay.get(day),
                First_Row_Key__c       = cursorByDay.get(day) == null
                    ? null : 'RK-' + cursorByDay.get(day)
            ));
        }
        insert days;
    }

    /**
     * The bound taken for a range is the smallest across every day in it, not the
     * from date's own.
     *
     * Archived date does not advance with key order - measured live, O-600000 is
     * 2026-09-04 where O-620000 is 2026-09-01 - so a later day can begin earlier
     * in the table. Taking the from date's cursor would skip past rows that match.
     */
    @IsTest
    static void rangeCursorTakesTheSmallestAcrossTheRange() {
        seedRollupWithCursors('ARCHIVED', new Map<Date, String>{
            Date.newInstance(2026, 9, 18) => 'PK-790000',
            Date.newInstance(2026, 9, 19) => 'PK-780000',
            Date.newInstance(2026, 9, 20) => 'PK-792000'
        });

        Test.startTest();
        ArchiveReadService.DayCursor startAt = ArchivedRecordsController.rangeStartCursor(
            OLI, 'ARCHIVED',
            Date.newInstance(2026, 9, 18), Date.newInstance(2026, 9, 20));
        Test.stopTest();

        System.assertNotEquals(null, startAt, 'Every day in range has a cursor');
        System.assertEquals('PK-780000', startAt.partitionKey,
            'The lowest bound in the range is the only safe one for all of it');
        System.assertEquals('RK-PK-780000', startAt.rowKey, 'The pair travels together');
    }

    /**
     * One day in range without a cursor withholds the hint entirely.
     *
     * That day may begin anywhere, including above the others, so there is no
     * bound that is safe for the range. Reading from the top is slower and right;
     * reading from a bound that does not cover every day is fast and wrong.
     */
    @IsTest
    static void rangeCursorWithheldWhenAnyDayHasNoBound() {
        seedRollupWithCursors('ARCHIVED', new Map<Date, String>{
            Date.newInstance(2026, 9, 19) => 'PK-780000',
            Date.newInstance(2026, 9, 20) => null
        });

        Test.startTest();
        ArchiveReadService.DayCursor startAt = ArchivedRecordsController.rangeStartCursor(
            OLI, 'ARCHIVED',
            Date.newInstance(2026, 9, 19), Date.newInstance(2026, 9, 20));
        Test.stopTest();

        System.assertEquals(null, startAt,
            'An unbounded day in range means the read must start at the beginning');
    }

    /** A rollup that has never run leaves the read exactly as it was. */
    @IsTest
    static void rangeCursorNullWhenRollupHasNoDays() {
        Test.startTest();
        ArchiveReadService.DayCursor startAt = ArchivedRecordsController.rangeStartCursor(
            OLI, 'ARCHIVED',
            Date.newInstance(2026, 9, 20), Date.newInstance(2026, 9, 20));
        Test.stopTest();

        System.assertEquals(null, startAt, 'No recorded days, nothing to skip to');
    }

    /** An open-ended range below has to start at the beginning regardless. */
    @IsTest
    static void rangeCursorNullWithoutAFromDate() {
        seedRollupWithCursors('ARCHIVED', new Map<Date, String>{
            Date.newInstance(2026, 9, 20) => 'PK-792000'
        });

        Test.startTest();
        ArchiveReadService.DayCursor startAt = ArchivedRecordsController.rangeStartCursor(
            OLI, 'ARCHIVED', null, Date.newInstance(2026, 9, 20));
        Test.stopTest();

        System.assertEquals(null, startAt, 'Unbounded below means no skipping');
    }

    /**
     * Cursors carried between chained jobs keep the earliest sighting.
     *
     * Jobs walk the table in order, so anything already carried was seen further
     * back than anything the current job found.
     */
    @IsTest
    static void carriedCursorsAreNotOverwrittenByLaterJobs() {
        String carried = JSON.serialize(new Map<String, ArchiveReadService.DayCursor>{
            '2026-09-20' => new ArchiveReadService.DayCursor('PK-early', 'RK-early')
        });

        Map<String, ArchiveReadService.DayCursor> merged = ArchiveCountQueueable.mergeCursors(
            carried,
            new Map<String, ArchiveReadService.DayCursor>{
                '2026-09-20' => new ArchiveReadService.DayCursor('PK-later', 'RK-later'),
                '2026-09-21' => new ArchiveReadService.DayCursor('PK-new', 'RK-new')
            });

        System.assertEquals(2, merged.size(), 'A newly met day is added');
        System.assertEquals('PK-early', merged.get('2026-09-20').partitionKey,
            'An earlier job\'s sighting survives a later one');
        System.assertEquals('PK-new', merged.get('2026-09-21').partitionKey);
    }

    /** An unreadable cursor blob fails loudly rather than silently losing bounds. */
    @IsTest
    static void unreadableCarriedCursorsThrow() {
        try {
            ArchiveCountQueueable.mergeCursors('not json at all', null);
            System.assert(false, 'Corrupt carried cursors should not be swallowed');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('Partial day cursors'),
                'Error should name what could not be read: ' + e.getMessage());
        }
    }

    // ------------------------------------------------------------ inventory name

    private static ArchivedRecordsController.ReportPage inventoryPage(List<Object> inventoryIds) {
        ArchivedRecordsController.ReportPage page = new ArchivedRecordsController.ReportPage();
        ArchivedRecordsController.ReportColumn col = new ArchivedRecordsController.ReportColumn();
        col.fieldName = 'Inventory_Name__c';
        col.label = 'Inventory Name';
        page.columns.add(col);
        for (Object inventoryId : inventoryIds) {
            page.rows.add(new Map<String, Object>{
                'Inventory_Name__c' => null,
                '_inventoryId' => inventoryId
            });
        }
        return page;
    }

    @IsTest
    static void inventoryNameIsLookedUpFromTheArchivedInventoryId() {
        Inventory__c inventory = new Inventory__c();
        insert inventory;
        inventory = [SELECT Id, Name FROM Inventory__c WHERE Id = :inventory.Id];

        ArchivedRecordsController.ReportPage page = inventoryPage(new List<Object>{
            String.valueOf(inventory.Id), null, 'not-an-id'
        });

        Test.startTest();
        ArchivedRecordsController.mapInventoryAdjustmentNames('Inventory_Adjustment__c', page);
        Test.stopTest();

        System.assertEquals(inventory.Name, page.rows[0].get('Inventory_Name__c'),
            'The name comes from the Inventory record the archived Id points at');
        System.assertEquals(null, page.rows[1].get('Inventory_Name__c'),
            'A row with no archived Inventory stays blank');
        System.assertEquals(null, page.rows[2].get('Inventory_Name__c'),
            'An unreadable Id stays blank rather than failing the page');
        for (Map<String, Object> row : page.rows) {
            System.assert(!row.containsKey('_inventoryId'),
                'The hidden Id is not sent to the LWC');
        }
    }

    @IsTest
    static void inventoryIdIsShownWhenNoNameCanBeFound() {
        // An Inventory that exists only in the org the archive was written from.
        Id elsewhere = Id.valueOf(
            Inventory__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        ArchivedRecordsController.ReportPage page = inventoryPage(new List<Object>{
            String.valueOf(elsewhere)
        });

        Test.startTest();
        ArchivedRecordsController.mapInventoryAdjustmentNames('Inventory_Adjustment__c', page);
        Test.stopTest();

        System.assertEquals(String.valueOf(elsewhere), page.rows[0].get('Inventory_Name__c'),
            'With no name to be found, the column shows which Inventory it is');
    }

    @IsTest
    static void archivedInventoryNameIsShownAsStored() {
        ArchivedRecordsController.ReportPage page = inventoryPage(new List<Object>{ null });
        page.rows[0].put('_inventoryName', 'IN - 0042');

        Test.startTest();
        ArchivedRecordsController.mapInventoryAdjustmentNames('Inventory_Adjustment__c', page);
        Test.stopTest();

        System.assertEquals('IN - 0042', page.rows[0].get('Inventory_Name__c'),
            'An archived Inventory_Name__c is used without any lookup');
        System.assert(!page.rows[0].containsKey('_inventoryName'), 'The hidden value is cleared');
    }

    @IsTest
    static void inventoryNameComesFromTheAdjustmentStillInTheOrg() {
        Inventory__c inventory = new Inventory__c(Quantity_in_hand__c = 10);
        insert inventory;
        Inventory_Adjustment__c adjustment = new Inventory_Adjustment__c(
            Inventory__c = inventory.Id, Quantity__c = 5, Type__c = 'Increment');
        insert adjustment;
        adjustment = [SELECT Id, Inventory_Name__c FROM Inventory_Adjustment__c WHERE Id = :adjustment.Id];

        // Archived with no Inventory Id, but the adjustment itself is still in the
        // org (soft-archived, not yet deleted), so its own formula names it.
        ArchivedRecordsController.ReportPage page = inventoryPage(new List<Object>{ null });
        page.rows[0].put('_adjustmentId', String.valueOf(adjustment.Id));

        Test.startTest();
        ArchivedRecordsController.mapInventoryAdjustmentNames('Inventory_Adjustment__c', page);
        Test.stopTest();

        System.assertNotEquals(null, adjustment.Inventory_Name__c, 'Setup: the formula has a value');
        System.assertEquals(adjustment.Inventory_Name__c, page.rows[0].get('Inventory_Name__c'),
            'The live record\'s Inventory_Name__c fills the column');
        System.assert(!page.rows[0].containsKey('_adjustmentId'), 'The hidden Id is cleared');
    }

    // ------------------------------------------------------------ primary invoice

    /** One row with a Primary Invoice Transaction column, as the read builds it. */
    private static ArchivedRecordsController.ReportPage invoicePage(Object invoiceId) {
        ArchivedRecordsController.ReportPage page = new ArchivedRecordsController.ReportPage();
        ArchivedRecordsController.ReportColumn col = new ArchivedRecordsController.ReportColumn();
        col.fieldName = 'primary_invoice_transaction__c';
        col.label = 'Primary Invoice transaction';
        page.columns.add(col);
        page.rows.add(new Map<String, Object>{
            'primary_invoice_transaction__c' => invoiceId,
            '_primaryInvoiceId' => invoiceId
        });
        return page;
    }

    /** An Invoice Id in the right format; no Invoice__c is inserted. */
    private static Id invoiceId(Integer n) {
        return Id.valueOf(Invoice__c.SObjectType.getDescribe().getKeyPrefix()
            + String.valueOf(n).leftPad(12, '0'));
    }

    // These tests name invoices through ArchivedRecordsController.invoiceNamesOverride
    // rather than by inserting Invoice__c, so they do not depend on Invoice
    // triggers compiling - see the note on that seam.

    @IsTest
    static void primaryInvoiceIsShownByName() {
        Id invoice = invoiceId(1);
        ArchivedRecordsController.invoiceNamesOverride = new Map<Id, String>{ invoice => 'GSR-TEST-001' };
        ArchivedRecordsController.ReportPage page = invoicePage(String.valueOf(invoice));

        Test.startTest();
        ArchivedRecordsController.mapInventoryAdjustmentNames('Inventory_Adjustment__c', page);
        Test.stopTest();

        System.assertEquals('GSR-TEST-001', page.rows[0].get('primary_invoice_transaction__c'),
            'The archived Invoice Id is shown as the Invoice name');
        System.assert(!page.rows[0].containsKey('_primaryInvoiceId'), 'The hidden Id is cleared');
    }

    @IsTest
    static void primaryInvoiceIdIsShownWhenNoNameCanBeFound() {
        // An Invoice that exists only in the org the archive was written from.
        Id elsewhere = Id.valueOf(
            Invoice__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        ArchivedRecordsController.ReportPage page = invoicePage(String.valueOf(elsewhere));

        Test.startTest();
        ArchivedRecordsController.mapInventoryAdjustmentNames('Inventory_Adjustment__c', page);
        Test.stopTest();

        System.assertEquals(String.valueOf(elsewhere), page.rows[0].get('primary_invoice_transaction__c'),
            'With no name to be found, the column keeps the Invoice Id');
    }

    @IsTest
    static void bothInvoiceLookupsShowTheInvoiceNameField() {
        // Primary Invoice Transaction is named by the wrapper from Invoice__c.Name;
        // Secondary Invoice Transaction goes through the generic lookup resolver,
        // which must not be redirected to Invoice_Number__c.
        Map<String, String> displayFields =
            ArchivedRecordsController.LOOKUP_DISPLAY_FIELDS.get('Inventory_Adjustment__c');
        System.assert(displayFields == null || !displayFields.containsKey('secondary invoice transaction'),
            'Secondary Invoice Transaction has no display-field override');
        System.assertEquals('Name',
            ArchivedRecordsController.displayFieldFor(Invoice__c.SObjectType, null),
            'With no override, an Invoice is shown by its standard Name field');
    }

    @IsTest
    static void inventoryNameMappingLeavesOtherObjectsAlone() {
        ArchivedRecordsController.ReportPage page = inventoryPage(new List<Object>{ 'x' });

        ArchivedRecordsController.mapInventoryAdjustmentNames(OLI, page);

        System.assertEquals(null, page.rows[0].get('Inventory_Name__c'),
            'Only Inventory Adjustment rows are mapped');
    }
}