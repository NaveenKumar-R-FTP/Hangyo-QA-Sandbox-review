/**
 * Unit tests for ArchiveReadService against the retrieval contract Azure
 * published on 2026-09-17 and that was verified live the same day.
 */
@IsTest
private class ArchiveReadServiceTest {

    private static final String OLI = 'Order_Line_Item__c';

    private static ArchiveReadService.ArchiveQuery query() {
        ArchiveReadService.ArchiveQuery q = new ArchiveReadService.ArchiveQuery();
        q.objectApiName = OLI;
        return q;
    }

    // ------------------------------------------------------------ happy path

    @IsTest
    static void readsRowsFromTheValueEnvelope() {
        ArchiveReadServiceMocks.SuccessMock mock = new ArchiveReadServiceMocks.SuccessMock(3);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ArchiveReadService.PageResult result = ArchiveReadService.fetch(query());
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, 'A 200 with a value array is a success');
        System.assertEquals(3, result.records.size(), 'Every element of value becomes a row');
        System.assertEquals(3, result.totalCount, 'Totals are counted, never read from the body');
        System.assertEquals(3, result.returnedCount, 'returnedCount matches what was retrieved');
        System.assertEquals(false, result.isCapped, 'No continuation means the result is complete');
        System.assertEquals(1, result.calloutCount, 'One page needs exactly one callout');
        System.assertEquals(
            'Order-Item-0000', result.records[0].get('Name'),
            'Field names pass through exactly as the archive returns them');
    }

    @IsTest
    static void emptyResultIsSuccessNotAnError() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.EmptyMock());

        Test.startTest();
        ArchiveReadService.PageResult result = ArchiveReadService.fetch(query());
        Test.stopTest();

        System.assertEquals(true, result.isSuccess, '{"value":[]} is an empty result, not a failure');
        System.assertEquals(0, result.records.size(), 'No rows');
        System.assertEquals(false, result.endpointUnavailable, 'An empty archive is not a missing route');
    }

    // ------------------------------------------------------------ the request

    @IsTest
    static void endpointCarriesPathTopSelectAndFilter() {
        ArchiveReadServiceMocks.SuccessMock mock = new ArchiveReadServiceMocks.SuccessMock(1);
        Test.setMock(HttpCalloutMock.class, mock);

        ArchiveReadService.ArchiveQuery q = query();
        q.fromDate = Date.newInstance(2025, 4, 1);
        q.toDate = Date.newInstance(2025, 4, 30);
        q.selectFields = new List<String>{ 'Name', 'Total_Amount__c' };

        Test.startTest();
        ArchiveReadService.fetch(q);
        Test.stopTest();

        String endpoint = mock.lastEndpoint;
        System.assert(
            endpoint.startsWith('callout:AzureArchiveRetrieval_NC/OrderLineItems?'),
            'The object is a path segment on the retrieval credential: ' + endpoint);
        System.assert(endpoint.contains('$top='), 'A row limit is always sent: ' + endpoint);
        System.assert(endpoint.contains('$select='), '$select trims the payload: ' + endpoint);
        System.assert(endpoint.contains('$filter='), 'The date range becomes a $filter: ' + endpoint);
        System.assert(
            !endpoint.contains('$skip'),
            '$skip returns 501 on this gateway and must never be sent: ' + endpoint);
        System.assert(
            !endpoint.contains('+'),
            'Spaces must be %20, not +, inside a quoted OData filter: ' + endpoint);
    }

    @IsTest
    static void dateRangeFilterIsInclusiveOfTheWholeToDay() {
        ArchiveReadService.ArchiveQuery q = query();
        q.fromDate = Date.newInstance(2025, 4, 1);
        q.toDate = Date.newInstance(2025, 4, 30);

        String filter = ArchiveReadService.buildFilter(q);

        System.assertEquals(
            'CreatedDate ge \'2025-04-01T00:00:00.000Z\' and CreatedDate lt \'2025-05-01T00:00:00.000Z\'',
            filter,
            'To date is inclusive, so the upper bound is lt the following midnight');
    }

    @IsTest
    static void filterIsOmittedWhenNoRangeIsGiven() {
        System.assertEquals(null, ArchiveReadService.buildFilter(query()),
            'No dates means no $filter clause at all');
    }

    @IsTest
    static void selectAlwaysCarriesIdAndTheSortField() {
        ArchiveReadService.ArchiveQuery q = query();
        q.selectFields = new List<String>{ 'Name' };

        String selectClause = ArchiveReadService.buildSelect(q);

        System.assert(selectClause.contains('Id'), 'Id keys the datatable rows: ' + selectClause);
        System.assert(selectClause.contains('CreatedDate'), 'The sort field must be fetched: ' + selectClause);
        System.assert(selectClause.contains('Name'), 'Requested columns survive: ' + selectClause);
    }

    @IsTest
    static void noSelectFieldsRequestsEveryField() {
        System.assertEquals(null, ArchiveReadService.buildSelect(query()),
            'An empty select list means "all fields", not "no fields"');
    }

    @IsTest
    static void namedCredentialOverrideToleratesTheCalloutPrefix() {
        ArchiveReadServiceMocks.SuccessMock mock = new ArchiveReadServiceMocks.SuccessMock(1);
        Test.setMock(HttpCalloutMock.class, mock);

        ArchiveReadService.ArchiveQuery q = query();
        q.namedCredential = 'callout:SomeOtherCredential';
        q.readPath = 'CustomRoute';

        Test.startTest();
        ArchiveReadService.fetch(q);
        Test.stopTest();

        System.assert(
            mock.lastEndpoint.startsWith('callout:SomeOtherCredential/CustomRoute?'),
            'Config may be entered with or without the prefix, and a path without a slash: '
            + mock.lastEndpoint);
    }

    // ------------------------------------------------------------ paging

    @IsTest
    static void followsContinuationTokensToCompletion() {
        ArchiveReadServiceMocks.ContinuationMock mock =
            new ArchiveReadServiceMocks.ContinuationMock(10, 3);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ArchiveReadService.PageResult result = ArchiveReadService.fetch(query());
        Test.stopTest();

        System.assertEquals(3, result.calloutCount, 'Three advertised pages, three callouts');
        System.assertEquals(30, result.records.size(), 'Every page is accumulated');
        System.assertEquals(false, result.isCapped, 'Reaching the end is not a cap');
        System.assert(
            mock.endpoints[1].contains('NextPartitionKey='),
            'The continuation is replayed as a query parameter: ' + mock.endpoints[1]);
        System.assert(
            mock.endpoints[1].contains('NextRowKey='),
            'Both continuation parts are required: ' + mock.endpoints[1]);
        System.assert(
            !mock.endpoints[0].contains('NextPartitionKey='),
            'The first request carries no continuation: ' + mock.endpoints[0]);
    }

    @IsTest
    static void rowCapStopsAnUnboundedResult() {
        ArchiveReadServiceMocks.EndlessMock mock = new ArchiveReadServiceMocks.EndlessMock(1000);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ArchiveReadService.PageResult result = ArchiveReadService.fetch(query());
        Test.stopTest();

        System.assertEquals(
            ArchiveReadService.MAX_ROWS, result.records.size(),
            'The service never holds more than MAX_ROWS rows in one transaction');
        System.assertEquals(true, result.isCapped, 'A surviving continuation means more rows exist');
        System.assertEquals(true, result.isSuccess, 'A capped read is still a successful read');
        System.assertEquals(2, result.calloutCount, 'Two 1000-row pages reach the 2000-row cap');
    }

    @IsTest
    static void endlessEmptyScanIsStoppedByTheHopBudget() {
        // The real failure this guards: a date filter scans the whole table and
        // returns empty pages with continuations, roughly one per five seconds.
        // Without a hop budget this runs until the 100-callout limit throws.
        ArchiveReadServiceMocks.ScanningMock mock = new ArchiveReadServiceMocks.ScanningMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ArchiveReadService.PageResult result = ArchiveReadService.fetch(query());
        Test.stopTest();

        System.assertEquals(ArchiveReadService.MAX_PAGES, result.calloutCount,
            'The hop budget, not the row cap, has to stop a scan that returns nothing');
        System.assertEquals(true, result.scanIncomplete,
            'The caller must know the search never reached the end of the table');
        System.assertEquals(true, result.isSuccess,
            'An unfinished scan is not an error - the rows found so far are real');
        System.assertEquals(0, result.records.size(), 'This scan matched nothing yet');
    }

    @IsTest
    static void completeResultIsNotMarkedIncomplete() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.EmptyMock());

        Test.startTest();
        ArchiveReadService.PageResult result = ArchiveReadService.fetch(query());
        Test.stopTest();

        System.assertEquals(false, result.scanIncomplete,
            'An empty result with no continuation is a finished search: genuinely no rows');
        System.assertEquals(false, result.isCapped);
    }

    @IsTest
    static void denseResultNeverReachesTheHopBudget() {
        ArchiveReadServiceMocks.EndlessMock mock = new ArchiveReadServiceMocks.EndlessMock(1000);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ArchiveReadService.PageResult result = ArchiveReadService.fetch(query());
        Test.stopTest();

        System.assertEquals(false, result.scanIncomplete,
            'Hitting the row cap is a full page of answers, not an unfinished search');
        System.assertEquals(true, result.isCapped, 'But there is more beyond it');
    }

    @IsTest
    static void maxRowsIsClampedToTheServiceCeiling() {
        ArchiveReadServiceMocks.EndlessMock mock = new ArchiveReadServiceMocks.EndlessMock(1000);
        Test.setMock(HttpCalloutMock.class, mock);

        ArchiveReadService.ArchiveQuery q = query();
        q.maxRows = 999999;

        Test.startTest();
        ArchiveReadService.PageResult result = ArchiveReadService.fetch(q);
        Test.stopTest();

        System.assertEquals(
            ArchiveReadService.MAX_ROWS, result.records.size(),
            'A caller cannot raise the heap ceiling by asking for more');
    }

    // ------------------------------------------------------------ failures

    @IsTest
    static void blankObjectIsRejectedWithoutACallout() {
        ArchiveReadService.ArchiveQuery q = new ArchiveReadService.ArchiveQuery();

        Test.startTest();
        ArchiveReadService.PageResult result = ArchiveReadService.fetch(q);
        Test.stopTest();

        System.assertEquals('INVALID_REQUEST', result.errorCode, 'Guarded before any HTTP work');
        System.assertEquals(0, result.calloutCount, 'No callout is spent on an invalid request');
    }

    @IsTest
    static void objectWithNoKnownRouteIsUnavailableWithoutACallout() {
        ArchiveReadService.ArchiveQuery q = new ArchiveReadService.ArchiveQuery();
        // Every archived object has a default route now; Account has none.
        q.objectApiName = 'Account';

        Test.startTest();
        ArchiveReadService.PageResult result = ArchiveReadService.fetch(q);
        Test.stopTest();

        System.assertEquals(true, result.endpointUnavailable,
            'An object with no route degrades without a callout');
        System.assertEquals('READ_ENDPOINT_NOT_CONFIGURED', result.errorCode);
        System.assertEquals(0, result.calloutCount,
            'A known-missing route should not cost a callout');
    }

    @IsTest
    static void notFoundMarksTheEndpointUnavailable() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.NotFoundMock());

        Test.startTest();
        ArchiveReadService.PageResult result = ArchiveReadService.fetch(query());
        Test.stopTest();

        System.assertEquals(true, result.endpointUnavailable, '404 means no route for this object');
        System.assertEquals('READ_ENDPOINT_NOT_FOUND', result.errorCode);
        System.assertEquals(false, result.isSuccess, 'A missing route is not a success');
    }

    @IsTest
    static void serverErrorSurfacesRatherThanDegrading() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.ServerErrorMock());

        Test.startTest();
        ArchiveReadService.PageResult result = ArchiveReadService.fetch(query());
        Test.stopTest();

        System.assertEquals('ARCHIVE_HTTP_500', result.errorCode,
            'A broken archive must not look like a missing one');
        System.assertEquals(false, result.endpointUnavailable,
            '500 must not trigger the silent fallback path');
    }

    @IsTest
    static void authHeaderRejectionSurfacesAsAnError() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.AuthHeaderRejectedMock());

        Test.startTest();
        ArchiveReadService.PageResult result = ArchiveReadService.fetch(query());
        Test.stopTest();

        System.assertEquals('ARCHIVE_HTTP_400', result.errorCode,
            'Pointing the read path at the write credential must fail loudly');
        System.assert(
            result.errorMessage.contains('InvalidAuthenticationInfo'),
            'The cause is kept in the message so the misconfiguration is diagnosable: '
            + result.errorMessage);
    }

    @IsTest
    static void unparseableBodyIsAnError() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.MalformedMock());

        Test.startTest();
        ArchiveReadService.PageResult result = ArchiveReadService.fetch(query());
        Test.stopTest();

        System.assertEquals('INVALID_RESPONSE', result.errorCode);
        System.assertEquals(false, result.isSuccess);
    }

    @IsTest
    static void calloutExceptionIsCaught() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.ThrowingMock());

        Test.startTest();
        ArchiveReadService.PageResult result = ArchiveReadService.fetch(query());
        Test.stopTest();

        System.assertEquals('CALLOUT_EXCEPTION', result.errorCode, 'Never throws out of fetch');
        System.assertEquals(false, result.isSuccess);
    }
    // --------------------------------------------------------------- counting

    /** The ordinary case: count everything the archive offers, exactly. */
    @IsTest
    static void countMatchingTalliesEveryRow() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.SuccessMock(123));

        Test.startTest();
        ArchiveReadService.CountResult counted = ArchiveReadService.countMatching(query());
        Test.stopTest();

        System.assertEquals(true, counted.isSuccess);
        System.assertEquals(true, counted.isExact, 'The archive ran out before the budget');
        System.assertEquals(123, counted.total);
    }

    /**
     * Out of budget: a floor, plus the cursor to carry on from. Without the
     * cursor the next job in the chain would recount from the beginning, and the
     * total would grow without ever converging.
     */
    @IsTest
    static void countMatchingHandsBackItsCursorWhenBudgetRunsOut() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.EndlessMock(1000));

        Test.startTest();
        ArchiveReadService.CountResult counted = ArchiveReadService.countMatching(query(), 3);
        Test.stopTest();

        System.assertEquals(true, counted.isSuccess);
        System.assertEquals(false, counted.isExact, 'An endless archive cannot be counted exactly');
        System.assertEquals(3000, counted.total, 'Three pages of a thousand');
        System.assertNotEquals(null, counted.nextPartitionKey, 'The chain needs somewhere to resume');
    }

    /**
     * A body in the old "records" shape must fail the count outright.
     *
     * Counting zero out of a 200 response is the worst available outcome: it
     * looks like a confident, precise answer and is entirely wrong. This is the
     * count-side twin of the guard ArchiveReadContractTest puts on reads.
     */
    @IsTest
    static void countMatchingRejectsAResponseWithNoValueArray() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.LegacyShapeMock());

        Test.startTest();
        ArchiveReadService.CountResult counted = ArchiveReadService.countMatching(query());
        Test.stopTest();

        System.assertEquals(false, counted.isSuccess, 'An unrecognised shape is not a zero count');
        System.assertEquals('UNEXPECTED_RESPONSE_SHAPE', counted.errorCode);
        System.assertEquals(0, counted.total);
    }

    /** An empty archive is a legitimate zero, not a contract violation. */
    @IsTest
    static void countMatchingCountsAnEmptyArchiveAsZero() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.EmptyMock());

        Test.startTest();
        ArchiveReadService.CountResult counted = ArchiveReadService.countMatching(query());
        Test.stopTest();

        System.assertEquals(true, counted.isSuccess);
        System.assertEquals(true, counted.isExact);
        System.assertEquals(0, counted.total);
    }

    /** A 404 on the count path degrades the same way a read does. */
    @IsTest
    static void countMatchingReportsAMissingRoute() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.NotFoundMock());

        Test.startTest();
        ArchiveReadService.CountResult counted = ArchiveReadService.countMatching(query());
        Test.stopTest();

        System.assertEquals(false, counted.isSuccess);
        System.assertEquals(true, counted.endpointUnavailable);
    }

    /** The row tally itself, away from HTTP. */
    @IsTest
    static void tallyRowsInPageReadsTheEnvelope() {
        Map<String, Integer> tally = new Map<String, Integer>();
        System.assertEquals(0,
            ArchiveReadService.tallyRowsInPage('{"value":[]}', 'D__c', tally),
            'An empty array is zero rows');
        System.assertEquals(2,
            ArchiveReadService.tallyRowsInPage('{"value":[{"a":1},{"a":2}]}', 'D__c', tally));
        System.assertEquals(-1,
            ArchiveReadService.tallyRowsInPage('{"records":[{"a":1}]}', 'D__c', tally),
            'The old shape must be rejected, not counted as zero');
        System.assertEquals(-1,
            ArchiveReadService.tallyRowsInPage('{"value":"nope"}', 'D__c', tally),
            'A value that is not an array is a broken contract');
        System.assertEquals(-1,
            ArchiveReadService.tallyRowsInPage('', 'D__c', tally), 'A blank body is broken');
    }

    /**
     * Nested objects inside a record must not each count as a row. The live
     * payload is flat today, but a future column could nest.
     */
    @IsTest
    static void tallyRowsInPageIgnoresNestedObjects() {
        Map<String, Integer> tally = new Map<String, Integer>();
        String body = '{"value":[{"a":1,"child":{"b":2}},{"a":3,"child":{"b":4}}]}';
        System.assertEquals(2, ArchiveReadService.tallyRowsInPage(body, 'D__c', tally));
    }

    /**
     * The tally is what the whole rollup rests on: rows have to land on the right
     * day, and a row with no usable date must still be counted somewhere rather
     * than quietly dropped out of the total.
     */
    @IsTest
    static void tallyRowsInPageGroupsByDay() {
        Map<String, Integer> tally = new Map<String, Integer>();
        String body =
            '{"value":['
            + '{"Archived_Date__c":"2026-08-30T12:04:47.679Z"},'
            + '{"Archived_Date__c":"2026-08-30T18:22:01.000Z"},'
            + '{"Archived_Date__c":"2026-09-01T00:00:00.000Z"},'
            + '{"Other__c":"no date here"}'
            + ']}';

        System.assertEquals(4,
            ArchiveReadService.tallyRowsInPage(body, 'Archived_Date__c', tally));
        System.assertEquals(2, tally.get('2026-08-30'), 'Two rows share a day');
        System.assertEquals(1, tally.get('2026-09-01'));
        System.assertEquals(1, tally.get('UNDATED'), 'A dateless row is counted, not dropped');
    }

    /** Tallies accumulate across pages, as they must across a chained walk. */
    @IsTest
    static void tallyRowsInPageAccumulatesAcrossCalls() {
        Map<String, Integer> tally = new Map<String, Integer>();
        String page = '{"value":[{"Archived_Date__c":"2026-08-30T01:00:00.000Z"}]}';

        ArchiveReadService.tallyRowsInPage(page, 'Archived_Date__c', tally);
        ArchiveReadService.tallyRowsInPage(page, 'Archived_Date__c', tally);
        ArchiveReadService.tallyRowsInPage(page, 'Archived_Date__c', tally);

        System.assertEquals(3, tally.get('2026-08-30'), 'Each page adds to the same day');
    }

    /**
     * The cursor recorded for a day is the one that OPENED the page it was first
     * met on, which for the first page of a walk is no cursor at all.
     *
     * This is the difference between a lower bound and a wrong answer: page
     * three's own cursor points past page three, so a day first met there would
     * be resumed from after some of its own rows.
     */
    @IsTest
    static void countRecordsTheCursorEachDayWasFirstMetAt() {
        ArchiveReadServiceMocks.DayPagesMock mock =
            new ArchiveReadServiceMocks.DayPagesMock(2, 3);
        Test.setMock(HttpCalloutMock.class, mock);

        ArchiveReadService.ArchiveQuery q = new ArchiveReadService.ArchiveQuery();
        q.objectApiName = 'Order_Line_Item__c';
        q.dateField = 'Archived_Date__c';

        Test.startTest();
        ArchiveReadService.CountResult result = ArchiveReadService.countMatching(q, 10);
        Test.stopTest();

        System.assert(result.isSuccess, 'Walk should succeed');
        System.assert(result.isExact, 'Three pages then no continuation is a finished walk');
        System.assertEquals(6, result.total, 'Two rows on each of three pages');

        System.assertEquals(3, result.dayFirstSeen.size(), 'One cursor per day met');
        System.assertEquals(null, result.dayFirstSeen.get('2026-09-01').partitionKey,
            'The first day opens the table, so it has no cursor to skip to');
        System.assertEquals('PK-1', result.dayFirstSeen.get('2026-09-02').partitionKey,
            'Day two is resumed from what page one handed back, not page two');
        System.assertEquals('RK-1', result.dayFirstSeen.get('2026-09-02').rowKey);
        System.assertEquals('PK-2', result.dayFirstSeen.get('2026-09-03').partitionKey);
    }

    /**
     * A day spanning several pages keeps its earliest cursor. Overwriting it with
     * a later sighting would point past rows that day owns.
     */
    @IsTest
    static void firstSightingOfADayWins() {
        ArchiveReadService.CountResult result = new ArchiveReadService.CountResult();

        ArchiveReadService.absorbDayTally(
            result, new Map<String, Integer>{ '2026-09-20' => 5 }, 'PK-early', 'RK-early');
        ArchiveReadService.absorbDayTally(
            result, new Map<String, Integer>{ '2026-09-20' => 7 }, 'PK-later', 'RK-later');

        System.assertEquals(12, result.byDay.get('2026-09-20'),
            'Counts accumulate across pages');
        System.assertEquals('PK-early', result.dayFirstSeen.get('2026-09-20').partitionKey,
            'Cursors do not - the earliest is the only one that bounds the day');
    }

    // ------------------------------------------------------------ count failures

    @IsTest
    static void countMatchingRejectsABlankObject() {
        ArchiveReadService.CountResult counted =
            ArchiveReadService.countMatching(new ArchiveReadService.ArchiveQuery(), 1);

        System.assertEquals(false, counted.isSuccess);
        System.assertEquals('INVALID_REQUEST', counted.errorCode);
        System.assertEquals(0, counted.calloutCount, 'Rejected before any callout');
    }

    @IsTest
    static void countMatchingWithNoRouteMakesNoCallout() {
        ArchiveReadService.ArchiveQuery q = new ArchiveReadService.ArchiveQuery();
        q.objectApiName = 'Account';

        ArchiveReadService.CountResult counted = ArchiveReadService.countMatching(q, 1);

        System.assertEquals(true, counted.endpointUnavailable);
        System.assertEquals('READ_ENDPOINT_NOT_CONFIGURED', counted.errorCode);
        System.assertEquals(0, counted.calloutCount);
    }

    @IsTest
    static void countMatchingSurfacesAServerError() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.ServerErrorMock());

        Test.startTest();
        ArchiveReadService.CountResult counted = ArchiveReadService.countMatching(query(), 1);
        Test.stopTest();

        System.assertEquals(false, counted.isSuccess);
        System.assertEquals('ARCHIVE_HTTP_500', counted.errorCode);
        System.assertEquals(false, counted.endpointUnavailable, 'A 500 is not a missing route');
    }

    @IsTest
    static void countMatchingCatchesACalloutException() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.ThrowingMock());

        Test.startTest();
        ArchiveReadService.CountResult counted = ArchiveReadService.countMatching(query(), 1);
        Test.stopTest();

        System.assertEquals('CALLOUT_EXCEPTION', counted.errorCode);
    }

    // ------------------------------------------------------------ tally edge cases

    @IsTest
    static void tallyRowsInPageSkipsNestedValuesAndReadsTheDay() {
        Map<String, Integer> tally = new Map<String, Integer>();
        String body = '{"value":[{"tags":["a","b"],"meta":{"x":1},'
            + '"D__c":"2026-09-01T10:00:00.000Z"}]}';

        System.assertEquals(1, ArchiveReadService.tallyRowsInPage(body, 'D__c', tally));
        System.assertEquals(1, tally.get('2026-09-01'), 'Nested values do not hide the date');
    }

    @IsTest
    static void tallyRowsInPageRejectsATruncatedBody() {
        // Apex's JSONParser throws on early end-of-input before the -1 path is
        // reached. Either outcome is a rejection; a partial count is not.
        for (String body : new List<String>{
            '{"value":[{"D__c":"2026-09-01"}', '{"value":[{"D__c":'
        }) {
            Map<String, Integer> tally = new Map<String, Integer>();
            try {
                System.assertEquals(-1, ArchiveReadService.tallyRowsInPage(body, 'D__c', tally),
                    'A truncated body is broken, not a partial count: ' + body);
            } catch (JSONException e) {
                System.assert(true, 'Rejected by the parser');
            }
        }
    }

    // ------------------------------------------------------------ query building

    @IsTest
    static void partitionBoundsAreFilteredAndQuotesEscaped() {
        ArchiveReadService.ArchiveQuery q = query();
        q.partitionKeyFrom = 'O\'1';
        q.partitionKeyBefore = 'O-2';

        String filter = ArchiveReadService.buildFilter(q);

        System.assert(filter.contains('PartitionKey ge \'O\'\'1\''),
            'A quote in a key is doubled for OData: ' + filter);
        System.assert(filter.contains('PartitionKey lt \'O-2\''), filter);
    }

    @IsTest
    static void configuredPathGainsALeadingSlash() {
        ArchiveReadService.ArchiveQuery q = query();
        q.readPath = 'OrderLineItems';

        System.assertEquals('/OrderLineItems', ArchiveReadService.resolvePath(q));
    }

    @IsTest
    static void aMissingResponseIsAnError() {
        ArchiveReadService.PageResult result = new ArchiveReadService.PageResult();

        System.assertEquals(false, ArchiveReadService.absorbPage(null, result));
        System.assertEquals('NULL_RESPONSE', result.errorCode);
    }
}