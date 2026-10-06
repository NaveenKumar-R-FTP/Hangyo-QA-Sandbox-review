/**
 * Counts the archived rows matching one set of filters, across as many
 * transactions as it takes.
 *
 * This exists because the Azure archive publishes no row count. $count=true is
 * silently ignored, the {"value":[...]} envelope carries no total, and there is
 * no aggregate operation - verified live 2026-09-17 - so the only way to a total
 * is to read every matching row and add them up, a thousand per callout.
 *
 * One Apex transaction allows 100 callouts, so a synchronous count tops out at
 * 100,000 rows no matter how it is written. The archive holds 1M+ order line
 * items, all archived on the same day, so any useful filter matches far more than
 * that. Hence a chain: each job spends CALLOUT_BUDGET callouts, writes its running
 * total and its continuation cursor to Archive_Row_Count__c, and enqueues its
 * successor. The report polls that record and shows the number when Status flips
 * to Complete.
 *
 * Cost, measured against this archive: a dense filter returns 1000 rows in about
 * a quarter of a second, so roughly 1M rows is ~1000 callouts and about four
 * minutes of wall clock across ~12 jobs. The result is cached, so that price is
 * paid once per distinct question rather than once per page view.
 *
 * Rows are counted and discarded - only a running Integer survives a page - so
 * heap stays flat regardless of how large the result set turns out to be.
 */
public with sharing class ArchiveCountQueueable implements Queueable, Database.AllowsCallouts {

    /**
     * Callouts one job will spend before handing over to its successor.
     *
     * Ten below the governor limit of 100. The margin is not decoration: a retry
     * inside ArchiveReadService, or any future callout added to this path, would
     * otherwise turn a slow count into an uncatchable LimitException that loses
     * the running total along with the transaction. (The one small casing read
     * ArchivedRecordsController.countDateField may make comes out of this margin.)
     */
    @TestVisible
    private static final Integer CALLOUT_BUDGET = 90;

    /**
     * Jobs one count may chain through before giving up.
     *
     * At CALLOUT_BUDGET x 1000 rows a job this bounds a count at roughly 22M rows.
     * It was 60 - about 5.4M - on the assumption, taken from the project notes,
     * that the archive held "1M+" Order Line Items. Counting it properly on
     * 2026-09-21 passed 4.7M and was still going, so that figure was a floor
     * somebody had inferred rather than a measurement, and the ceiling derived
     * from it would have failed a legitimate count 600,000 rows from the end.
     *
     * The bound is still worth having - it is what stops a count that can never
     * converge from enqueueing itself for the rest of the day - but it should sit
     * far enough above the real data that only a genuine fault reaches it.
     */
    @TestVisible
    private static final Integer MAX_CHAIN_DEPTH = 250;

    private final Id countId;

    public ArchiveCountQueueable(Id countId) {
        this.countId = countId;
    }

    public void execute(QueueableContext context) {
        List<Archive_Row_Count__c> found = [
            SELECT Id, Cache_Key__c, Object_API_Name__c, Date_Basis__c,
                   From_Date__c, To_Date__c, Running_Total__c, Callouts_Used__c,
                   Chain_Depth__c, Next_Partition_Key__c, Next_Row_Key__c,
                   Status__c, Partial_Tally__c, Partial_Day_Cursors__c
            FROM Archive_Row_Count__c
            WHERE Id = :countId
            LIMIT 1
        ];
        if (found.isEmpty()) {
            return;
        }

        Archive_Row_Count__c state = found[0];
        if (state.Status__c != 'Running') {
            // Completed, failed, or superseded by a forced recount. Either way
            // this job is stale and must not resume a finished walk.
            return;
        }

        try {
            step(state);
        } catch (Exception e) {
            state.Status__c = 'Failed';
            state.Error_Message__c = truncate(e.getMessage(), 255);
            state.Completed_At__c = Datetime.now();
            update state;
        }
    }

    /** One job's worth of walking, then either finish or hand over. */
    private void step(Archive_Row_Count__c state) {
        ArchiveReadService.CountResult counted = ArchiveReadService.countMatching(
            buildQuery(state), CALLOUT_BUDGET);

        if (!counted.isSuccess) {
            state.Status__c = 'Failed';
            state.Error_Message__c = truncate(
                counted.errorCode + ': ' + counted.errorMessage, 255);
            state.Completed_At__c = Datetime.now();
            update state;
            return;
        }

        state.Running_Total__c = nvl(state.Running_Total__c) + counted.total;
        state.Callouts_Used__c = nvl(state.Callouts_Used__c) + counted.calloutCount;
        state.Chain_Depth__c = nvl(state.Chain_Depth__c) + 1;

        // Fold this job's per-day tally into the one carried on the record. The
        // walk spans many transactions, so the tally has to survive between them
        // and only becomes Archive Day Count rows once the walk is finished -
        // publishing partial days would let the report sum a half-counted day.
        Map<String, Integer> tally = mergeTally(state.Partial_Tally__c, counted.byDay);
        state.Partial_Tally__c = JSON.serialize(tally);

        // The cursor each day was first met at rides along with the tally, for the
        // same reason and with the same lifetime: a day first seen in job 5 has to
        // still be publishable when job 108 finishes the walk.
        Map<String, ArchiveReadService.DayCursor> cursors =
            mergeCursors(state.Partial_Day_Cursors__c, counted.dayFirstSeen);
        state.Partial_Day_Cursors__c = JSON.serialize(cursors);

        if (counted.isExact) {
            // The archive ran out before the budget did: every entity has now been
            // seen, so the tally is complete and can be published.
            state.Status__c = 'Complete';
            state.Next_Partition_Key__c = null;
            state.Next_Row_Key__c = null;
            state.Completed_At__c = Datetime.now();
            update state;
            publishDayCounts(state, tally, cursors);
            return;
        }

        state.Next_Partition_Key__c = truncate(counted.nextPartitionKey, 255);
        state.Next_Row_Key__c = truncate(counted.nextRowKey, 255);

        if (state.Chain_Depth__c >= MAX_CHAIN_DEPTH) {
            state.Status__c = 'Failed';
            state.Error_Message__c =
                'Count did not finish within ' + MAX_CHAIN_DEPTH + ' chained jobs ('
                + state.Callouts_Used__c + ' callouts, ' + state.Running_Total__c
                + ' rows counted). The filter matches more rows than this design '
                + 'counts; ask Azure to enable $count on the gateway.';
            state.Completed_At__c = Datetime.now();
            update state;
            return;
        }

        update state;

        // Chaining is disabled in tests - a queueable may not enqueue another -
        // so the test asserts on one step's outcome rather than the whole walk.
        if (!Test.isRunningTest()) {
            System.enqueueJob(new ArchiveCountQueueable(state.Id));
        }
    }

    /**
     * Adds a job's tally to the one accumulated so far.
     *
     * Days are merged rather than replaced: the same day appears in every job
     * that touches it, and for this archive one day holds all 9.65M rows, so
     * every one of the hundred-odd jobs contributes to the same key.
     */
    @TestVisible
    private static Map<String, Integer> mergeTally(String carried, Map<String, Integer> latest) {
        Map<String, Integer> merged = new Map<String, Integer>();

        if (String.isNotBlank(carried)) {
            try {
                Map<String, Object> raw =
                    (Map<String, Object>) JSON.deserializeUntyped(carried);
                for (String day : raw.keySet()) {
                    merged.put(day, Integer.valueOf(raw.get(day)));
                }
            } catch (Exception e) {
                // An unreadable tally is a bug, not user data. Quietly starting
                // the day map over would undercount by however much had already
                // been walked, and the result would still look like a total.
                throw new IllegalArgumentException(
                    'Partial tally could not be read: ' + e.getMessage());
            }
        }

        if (latest != null) {
            for (String day : latest.keySet()) {
                Integer seen = merged.get(day);
                merged.put(day, (seen == null ? 0 : seen) + latest.get(day));
            }
        }
        return merged;
    }

    /**
     * Adds a job's first-seen cursors to those accumulated so far, first sighting
     * winning.
     *
     * Opposite rule to mergeTally, and deliberately so: counts accumulate because
     * every job that touches a day contributes rows to it, while cursors do not,
     * because only the earliest sighting bounds the day. Jobs walk the table in
     * order, so whatever is already carried was seen further back than anything
     * this job found and must not be overwritten by it.
     *
     * A carried entry whose keys are null is still an entry: it records a day that
     * begins at the top of the table, which is a bound, not a missing one.
     */
    @TestVisible
    private static Map<String, ArchiveReadService.DayCursor> mergeCursors(
        String carried,
        Map<String, ArchiveReadService.DayCursor> latest
    ) {
        Map<String, ArchiveReadService.DayCursor> merged =
            new Map<String, ArchiveReadService.DayCursor>();

        if (String.isNotBlank(carried)) {
            try {
                Map<String, Object> raw =
                    (Map<String, Object>) JSON.deserializeUntyped(carried);
                for (String day : raw.keySet()) {
                    Map<String, Object> pair = (Map<String, Object>) raw.get(day);
                    merged.put(day, new ArchiveReadService.DayCursor(
                        pair == null ? null : (String) pair.get('partitionKey'),
                        pair == null ? null : (String) pair.get('rowKey')));
                }
            } catch (Exception e) {
                // Same reasoning as mergeTally: silently starting over would lose
                // the bounds for every day already walked, and the result would
                // still look complete.
                throw new IllegalArgumentException(
                    'Partial day cursors could not be read: ' + e.getMessage());
            }
        }

        if (latest != null) {
            for (String day : latest.keySet()) {
                if (!merged.containsKey(day)) {
                    merged.put(day, latest.get(day));
                }
            }
        }
        return merged;
    }

    /**
     * Writes the finished tally out as the rows the report actually queries.
     *
     * Upserted on the external id so a re-walk replaces its own figures rather
     * than doubling them, and so a day that still exists keeps one row.
     */
    private static void publishDayCounts(
        Archive_Row_Count__c state,
        Map<String, Integer> tally,
        Map<String, ArchiveReadService.DayCursor> cursors
    ) {
        List<Archive_Day_Count__c> rows = new List<Archive_Day_Count__c>();
        Datetime countedAt = Datetime.now();

        for (String day : tally.keySet()) {
            // UNDATED records have no usable date and so belong to no range.
            // They are counted on the run record's total but cannot be summed
            // into a date-filtered question, so they are not published as a day.
            if (day == 'UNDATED') {
                continue;
            }
            ArchiveReadService.DayCursor cursor =
                cursors == null ? null : cursors.get(day);

            rows.add(new Archive_Day_Count__c(
                Cache_Key__c            = state.Object_API_Name__c + '|' + state.Date_Basis__c + '|' + day,
                Object_API_Name__c      = state.Object_API_Name__c,
                Date_Basis__c           = state.Date_Basis__c,
                Day__c                  = Date.valueOf(day),
                Row_Count__c            = tally.get(day),
                Counted_At__c           = countedAt,
                // Blank when the day opens at the top of the table, and blank is
                // read downstream as "nothing to skip" rather than "unknown" -
                // the two mean the same thing to a reader.
                First_Partition_Key__c  = cursor == null ? null : truncate(cursor.partitionKey, 255),
                First_Row_Key__c        = cursor == null ? null : truncate(cursor.rowKey, 255)
            ));
        }

        if (!rows.isEmpty()) {
            upsert rows Cache_Key__c;
        }
    }

    private static ArchiveReadService.ArchiveQuery buildQuery(Archive_Row_Count__c state) {
        Azure_Archive_Config__mdt cfg = ArchivedRecordsController.configFor(
            state.Object_API_Name__c);

        ArchiveReadService.ArchiveQuery q = new ArchiveReadService.ArchiveQuery();
        q.objectApiName = state.Object_API_Name__c;
        q.fromDate = state.From_Date__c;
        q.toDate = state.To_Date__c;
        // Per object, not hardcoded: Invoice Line Items archive their dates as
        // archived_date__c / createddate. Tallying on the wrong name would put
        // every single row under UNDATED and publish an empty rollup - which is
        // what happened to objects whose casing the report detects at read time.
        // countDateField runs the same detection here, before any DML in this job.
        q.dateField = ArchivedRecordsController.countDateField(
            state.Object_API_Name__c, state.Date_Basis__c);
        q.readPath = cfg == null ? null : cfg.Read_Path__c;
        q.namedCredential = cfg == null ? null : cfg.Read_Named_Credential__c;
        q.startPartitionKey = state.Next_Partition_Key__c;
        q.startRowKey = state.Next_Row_Key__c;
        return q;
    }

    private static Decimal nvl(Decimal value) {
        return value == null ? 0 : value;
    }

    private static String truncate(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return value;
        }
        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }
}