public with sharing class ArchiveReadService {

    @TestVisible
    private static final String DEFAULT_NAMED_CREDENTIAL = 'AzureArchiveRetrieval_NC';

    @TestVisible
    private static final Integer AZURE_PAGE_SIZE = 1000;

    public static final Integer MAX_ROWS = 2000;

    private static final Integer CALLOUT_TIMEOUT_MS = 120000;

    @TestVisible
    private static final Integer MAX_PAGES = 6;

    /**
     * Archive path per object, RELATIVE TO the named credential's base URL, which
     * is already the gateway's /retrieve root. So the published operation
     * GET /retrieve/VisitTasks is '/VisitTasks' here - '/retrieve/VisitTasks'
     * would request /retrieve/retrieve/VisitTasks and 404.
     *
     * Every read, every count (ArchiveCountQueueable) and hasRoute resolve through
     * this map, so a new route belongs here and nowhere else. Override per object
     * with Azure_Archive_Config__mdt.Read_Path__c.
     */
    private static final Map<String, String> DEFAULT_PATHS = new Map<String, String>{
        'Order_Line_Item__c'      => '/OrderLineItems',
        'Invoice_Line_Item__c'    => '/InvoiceLineItems',
        'Attendance__c'           => '/Attendance',
        'Inventory_Adjustment__c' => '/InventoryAdjustments',
        'Visit_Task__c'           => '/VisitTasks'
    };

    @TestVisible
    private static final Integer MAX_COUNT_PAGES = 20;

    public class ArchiveQuery {
        public String objectApiName;
        public Date fromDate;
        public Date toDate;
        public String dateField = 'CreatedDate';
        public List<String> selectFields;
        public Integer maxRows = MAX_ROWS;
        public String readPath;
        public String namedCredential;
        public String idField = 'Id';
        public String startPartitionKey;
        public String startRowKey;
        /**
         * Optional PartitionKey bounds: inclusive lower, exclusive upper; null is
         * unbounded. PartitionKey is the archive's only indexed column, so a read
         * bounded here goes straight to those partitions instead of scanning -
         * which is how a parent search with no date range finds its rows. Both
         * null (the default) leaves every existing read and count unchanged.
         */
        public String partitionKeyFrom;
        public String partitionKeyBefore;
    }

    public class PageResult {
        public Boolean isSuccess = false;
        public Integer totalCount = 0;
        public Integer returnedCount = 0;
        public List<Map<String, Object>> records = new List<Map<String, Object>>();
        public Boolean endpointUnavailable = false;
        public Boolean isCapped = false;
        public Boolean scanIncomplete = false;
        public Integer calloutCount = 0;
        public String errorCode;
        public String errorMessage;
        /**
         * Resume point for the page after this one, or null when the archive had
         * nothing further to give. Feed straight back into the next
         * ArchiveQuery.startPartitionKey / startRowKey.
         */
        public String nextPartitionKey;
        public String nextRowKey;
        /** True when nextPartitionKey is set, i.e. a further page exists. */
        public Boolean hasMore = false;
    }

    /** Outcome of one bounded count. Rows are counted and discarded, never kept. */
    public class CountResult {
        public Boolean isSuccess = false;
        /** Rows counted. Exact when isExact; otherwise a floor. */
        public Integer total = 0;
        /** False when the hop budget ran out before the archive did. */
        public Boolean isExact = false;
        public Boolean endpointUnavailable = false;
        public Integer calloutCount = 0;
        public String errorCode;
        public String errorMessage;
        /**
         * Where counting stopped, when isExact is false. Feed these back in as
         * startPartitionKey / startRowKey to resume in a later transaction -
         * which is how ArchiveCountQueueable counts past the 100-callout limit.
         */
        public String nextPartitionKey;
        public String nextRowKey;
        /**
         * Rows seen per day, keyed yyyy-MM-dd on the query's date field. Rows
         * whose date field is absent or unreadable are keyed UNDATED, so they
         * are still counted somewhere rather than lost from the total.
         */
        public Map<String, Integer> byDay = new Map<String, Integer>();
        /**
         * Where each day was first met, keyed the same way as byDay.
         *
         * This is what lets a later read of one day start near its rows instead
         * of at the top of the table. PartitionKey is the archive's only indexed
         * column, so a date filter alone is a full scan: measured on 2026-09-21,
         * reading 2026-09-20 unhinted spent six seconds and returned nothing
         * while still scanning, and the same filter resumed from that day's
         * cursor returned a full page in under a second.
         *
         * An entry whose partitionKey is null means the day was first met on the
         * very first page of the table - a real answer, and the reason absence
         * and "starts at the beginning" are kept distinguishable.
         */
        public Map<String, DayCursor> dayFirstSeen = new Map<String, DayCursor>();
    }

    /**
     * A continuation pair. Table Storage resumes on both halves together, so they
     * travel together and are never stored or replayed apart.
     */
    public class DayCursor {
        public String partitionKey;
        public String rowKey;

        public DayCursor(String partitionKey, String rowKey) {
            this.partitionKey = partitionKey;
            this.rowKey = rowKey;
        }
    }

    /**
     * Objects with a built-in retrieval route, so callers can offer them without
     * keeping a second copy of the route table.
     */
    public static Set<String> publishedObjects() {
        return new Set<String>(DEFAULT_PATHS.keySet());
    }

    /**
     * Retrieves up to q.maxRows matching rows, following continuation tokens.
     *
     * Rows come back in the archive's own PartitionKey/RowKey order, which is
     * stable but unrelated to date. That only matters when the result is capped -
     * the caller orders a complete window itself.
     */
    public static PageResult fetch(ArchiveQuery q) {
        PageResult result = new PageResult();

        if (q == null || String.isBlank(q.objectApiName)) {
            result.errorCode = 'INVALID_REQUEST';
            result.errorMessage = 'objectApiName is required';
            return result;
        }

        String path = resolvePath(q);
        if (String.isBlank(path)) {
            // No route configured or known for this object: same outcome as a 404.
            result.endpointUnavailable = true;
            result.errorCode = 'READ_ENDPOINT_NOT_CONFIGURED';
            result.errorMessage =
                'No archive read path is configured for ' + q.objectApiName
                + '. Set Azure_Archive_Config__mdt.Read_Path__c once Azure publishes '
                + 'a retrieval operation for this object.';
            return result;
        }

        Integer ceiling = (q.maxRows == null || q.maxRows < 1)
            ? MAX_ROWS
            : Math.min(q.maxRows, MAX_ROWS);
        String filter = buildFilter(q);
        String selectClause = buildSelect(q);

        // Resume where the caller left off. Null on the first page.
        String nextPartitionKey = q.startPartitionKey;
        String nextRowKey = q.startRowKey;
        Integer pages = 0;

        do {
            Integer wanted = Math.min(AZURE_PAGE_SIZE, ceiling - result.records.size());
            String endpoint = buildEndpoint(
                q, path, filter, selectClause, wanted, nextPartitionKey, nextRowKey);

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(CALLOUT_TIMEOUT_MS);

            HttpResponse res;
            try {
                res = new Http().send(req);
                result.calloutCount++;
            } catch (Exception e) {
                result.errorCode = 'CALLOUT_EXCEPTION';
                result.errorMessage = e.getMessage();
                return result;
            }

            if (!absorbPage(res, result)) {
                return result;
            }
            pages++;

            nextPartitionKey = res.getHeader('x-ms-continuation-NextPartitionKey');
            nextRowKey = res.getHeader('x-ms-continuation-NextRowKey');

            if (String.isNotBlank(nextPartitionKey)) {
                if (result.records.size() >= ceiling) {
                    // More rows exist than this transaction is willing to hold.
                    result.isCapped = true;
                    break;
                }
                if (pages >= MAX_PAGES) {
                    // Still scanning, and out of hops. Rows found so far are real,
                    // but the search did not reach the end of the table.
                    result.isCapped = true;
                    result.scanIncomplete = true;
                    break;
                }
            }
        } while (String.isNotBlank(nextPartitionKey) && result.records.size() < ceiling);

        // Whatever token the last response carried is where the next page starts.
        // Blank means the archive reached the end of the matching rows.
        result.nextPartitionKey = String.isNotBlank(nextPartitionKey) ? nextPartitionKey : null;
        result.nextRowKey = String.isNotBlank(nextRowKey) ? nextRowKey : null;
        result.hasMore = result.nextPartitionKey != null;

        result.totalCount = result.records.size();
        result.returnedCount = result.records.size();
        result.isSuccess = true;
        return result;
    }

    /**
     * Counts matching rows without retaining them.
     *
     * This exists because the archive reports no row count of its own: $count=true
     * is silently ignored and the {"value":[...]} envelope carries no total, so the
     * only way to a number is to walk the matching rows and add them up. Rows are
     * discarded as they are counted, which is what lets this go far wider than
     * fetch() - heap never grows - but it is still bounded by MAX_COUNT_PAGES.
     *
     * The result is therefore exact only for result sets that fit inside the
     * budget; above it, total is a floor and isExact is false. Callers must render
     * that distinction rather than presenting a floor as a total.
     */
    public static CountResult countMatching(ArchiveQuery q) {
        return countMatching(q, MAX_COUNT_PAGES);
    }

    /**
     * Counts with an explicit callout budget, resuming from q.startPartitionKey.
     *
     * The budget is the caller's because the two callers can afford very
     * different things. A synchronous page read shares its transaction with the
     * user's patience and takes the small default; ArchiveCountQueueable owns a
     * whole transaction, takes ninety, and chains for as many transactions as the
     * archive needs - which is the only way past the 100-callout ceiling and
     * therefore the only way to an exact total on a table this size.
     */
    public static CountResult countMatching(ArchiveQuery q, Integer budget) {
        CountResult result = new CountResult();
        Integer hopBudget = (budget == null || budget < 1) ? MAX_COUNT_PAGES : budget;

        if (q == null || String.isBlank(q.objectApiName)) {
            result.errorCode = 'INVALID_REQUEST';
            result.errorMessage = 'objectApiName is required';
            return result;
        }

        String path = resolvePath(q);
        if (String.isBlank(path)) {
            result.endpointUnavailable = true;
            result.errorCode = 'READ_ENDPOINT_NOT_CONFIGURED';
            result.errorMessage = 'No archive read path is configured for ' + q.objectApiName + '.';
            return result;
        }

        String filter = buildFilter(q);
        // One narrow column. The rows are thrown away, so this only has to be
        // something every record carries; asking for all 41 fields would move
        // roughly fifteen times the bytes to reach the same number.
        String selectClause = String.isBlank(q.dateField) ? 'Id' : q.dateField.trim();

        String nextPartitionKey = q.startPartitionKey;
        String nextRowKey = q.startRowKey;
        Integer pages = 0;

        do {
            // The cursor that opens this page, held before the response below
            // overwrites it. Any day first met on this page can be resumed from
            // here, which is the whole point of the walk recording cursors.
            String pageStartPartitionKey = nextPartitionKey;
            String pageStartRowKey = nextRowKey;

            String endpoint = buildEndpoint(
                q, path, filter, selectClause, AZURE_PAGE_SIZE, nextPartitionKey, nextRowKey);

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(CALLOUT_TIMEOUT_MS);

            HttpResponse res;
            try {
                res = new Http().send(req);
                result.calloutCount++;
            } catch (Exception e) {
                result.errorCode = 'CALLOUT_EXCEPTION';
                result.errorMessage = e.getMessage();
                return result;
            }

            if (!checkResponse(res, result)) {
                return result;
            }

            // Tallied per page rather than straight into the result, so that
            // "this day is new" can still be asked once the page is read.
            Map<String, Integer> pageTally = new Map<String, Integer>();
            Integer rows = tallyRowsInPage(res.getBody(), selectClause, pageTally);
            if (rows < 0) {
                result.errorCode = 'UNEXPECTED_RESPONSE_SHAPE';
                result.errorMessage =
                    'Archive response has no "value" array - the retrieval contract has '
                    + 'changed. Refusing to report a count taken from a shape we do not '
                    + 'recognise.';
                return result;
            }

            absorbDayTally(result, pageTally, pageStartPartitionKey, pageStartRowKey);
            result.total += rows;
            pages++;

            nextPartitionKey = res.getHeader('x-ms-continuation-NextPartitionKey');
            nextRowKey = res.getHeader('x-ms-continuation-NextRowKey');

            // CPU, not callouts, is what actually stops a long count. Even
            // streamed, tokenising a thousand records a page adds up, and the
            // limit is enforced by killing the transaction - which rolls back the
            // progress record along with it, so a count that hits the wall makes
            // no progress at all and simply hits it again on the next attempt.
            // Standing down early and handing on the cursor is what turns that
            // into a chain that finishes.
            if (String.isNotBlank(nextPartitionKey) && Limits.getCpuTime() > cpuCeiling()) {
                result.isSuccess = true;
                result.isExact = false;
                result.nextPartitionKey = nextPartitionKey;
                result.nextRowKey = nextRowKey;
                return result;
            }

            if (String.isNotBlank(nextPartitionKey) && pages >= hopBudget) {
                // Out of budget with the archive still offering more. Hand back
                // the cursor so a later transaction can pick the walk up here.
                result.isSuccess = true;
                result.isExact = false;
                result.nextPartitionKey = nextPartitionKey;
                result.nextRowKey = nextRowKey;
                return result;
            }
        } while (String.isNotBlank(nextPartitionKey));

        // The archive ran out before the budget did, so every matching row was seen.
        result.isSuccess = true;
        result.isExact = true;
        return result;
    }

    /**
     * Whether this object has an archive read path at all, without calling out.
     *
     * A configured path is not proof the gateway answers it, so a true here still
     * has to survive the read. It is enough to decide which objects are worth
     * asking about.
     */
    public static Boolean hasRoute(String objectApiName, String configuredPath) {
        ArchiveQuery q = new ArchiveQuery();
        q.objectApiName = objectApiName;
        q.readPath = configuredPath;
        return String.isNotBlank(resolvePath(q));
    }

    /**
     * Two thirds of whatever CPU this context is allowed.
     *
     * Derived rather than hard-coded because the two callers run under limits an
     * order of magnitude apart - 10 seconds synchronous, 60 in a queueable - and
     * a constant tuned for one would either strangle the other or fail to protect
     * it. The remaining third covers the page in flight plus the update that
     * records where the walk got to.
     */
    private static Integer cpuCeiling() {
        return (Limits.getLimitCpuTime() * 2) / 3;
    }

    /**
     * Folds one page's tally into the running result, noting where any day not
     * seen before began.
     *
     * The cursor recorded is the one that OPENED the page, never the one the
     * page returned. Pages are walked in storage order, so a day appearing here
     * for the first time has no rows in any earlier page, which makes the start
     * of this page a position at or before that day's first row. Recording the
     * returned cursor instead would point just past the page and could sit after
     * rows that matched - the difference between a lower bound and a wrong answer.
     *
     * Because it is only ever a lower bound, replaying it can skip rows that were
     * never going to match but can never skip rows that would have. A read that
     * uses it returns the same rows as one that does not, sooner.
     */
    @TestVisible
    private static void absorbDayTally(
        CountResult result,
        Map<String, Integer> pageTally,
        String pageStartPartitionKey,
        String pageStartRowKey
    ) {
        for (String day : pageTally.keySet()) {
            Integer seen = result.byDay.get(day);
            result.byDay.put(day, (seen == null ? 0 : seen) + pageTally.get(day));

            // First sighting wins. A day spans many pages and the walk only moves
            // forward, so the earliest cursor is the only one that bounds it.
            if (!result.dayFirstSeen.containsKey(day)) {
                result.dayFirstSeen.put(
                    day, new DayCursor(pageStartPartitionKey, pageStartRowKey));
            }
        }
    }

    @TestVisible
    private static Integer tallyRowsInPage(String body,String dateField,Map<String, Integer> tally){
        if (String.isBlank(body)) {
            return -1;
        }

        JSONParser parser = JSON.createParser(body);
        while (parser.nextToken() != null) {
            if (parser.getCurrentToken() != JSONToken.FIELD_NAME
                || !'value'.equals(parser.getText())) {
                continue;
            }
            if (parser.nextToken() != JSONToken.START_ARRAY) {
                return -1;
            }

            Integer rows = 0;
            while (true) {
                JSONToken token = parser.nextToken();
                // A truncated body ends the stream mid-array. Treat it as a
                // broken response rather than trusting a partial tally.
                if (token == null) {
                    return -1;
                }
                if (token == JSONToken.END_ARRAY) {
                    return rows;
                }
                if (token != JSONToken.START_OBJECT) {
                    continue;
                }

                String day = readDay(parser, dateField);
                if (day == null) {
                    return -1;
                }
                rows++;
                Integer seen = tally.get(day);
                tally.put(day, (seen == null ? 0 : seen) + 1);
            }
        }
        return -1;
    }

    private static String readDay(JSONParser parser, String dateField) {
        String day = null;
        while (true) {
            JSONToken token = parser.nextToken();
            if (token == null) {
                return null;
            }
            if (token == JSONToken.END_OBJECT) {
                return day == null ? 'UNDATED' : day;
            }
            if (token != JSONToken.FIELD_NAME) {
                continue;
            }

            Boolean wanted = String.isNotBlank(dateField) && dateField.equals(parser.getText());
            JSONToken valueToken = parser.nextToken();
            if (valueToken == null) {
                return null;
            }
            if (valueToken == JSONToken.START_OBJECT || valueToken == JSONToken.START_ARRAY) {
                parser.skipChildren();
                continue;
            }
            if (wanted && valueToken == JSONToken.VALUE_STRING) {
                String raw = parser.getText();
                // Dates are stored as ISO-8601 strings; the first ten characters
                // are the calendar day in UTC, which is how they were written.
                if (String.isNotBlank(raw) && raw.length() >= 10) {
                    day = raw.substring(0, 10);
                }
            }
        }
        // Unreachable - the loop only exits by returning - but Apex requires it.
        return day;
    }

    /**
     * The status-code half of absorbPage, without the body handling - so the
     * count path rejects a 404 or a 500 in exactly the same terms as a read.
     */
    private static Boolean checkResponse(HttpResponse res, CountResult result) {
        if (res == null) {
            result.errorCode = 'NULL_RESPONSE';
            result.errorMessage = 'Archive service returned no response';
            return false;
        }

        Integer status = res.getStatusCode();
        if (status == 404) {
            result.endpointUnavailable = true;
            result.errorCode = 'READ_ENDPOINT_NOT_FOUND';
            result.errorMessage =
                'The archive gateway has no read operation for this object.';
            return false;
        }
        if (status < 200 || status >= 300) {
            result.errorCode = 'ARCHIVE_HTTP_' + String.valueOf(status);
            String body = res.getBody();
            result.errorMessage = String.isNotBlank(body) ? body : res.getStatus();
            return false;
        }
        return true;
    }

    /** Config path wins; otherwise the built-in per-object default. */
    @TestVisible
    private static String resolvePath(ArchiveQuery q) {
        String path = String.isNotBlank(q.readPath)
            ? q.readPath.trim()
            : DEFAULT_PATHS.get(q.objectApiName);

        if (String.isBlank(path)) {
            return null;
        }
        return path.startsWith('/') ? path : '/' + path;
    }

    /**
     * OData $filter for the date range, or null for no range.
     *
     * Dates are stored as ISO-8601 strings, so these are string comparisons -
     * verified against the live endpoint. The To date is inclusive of its whole
     * day, hence lt (toDate + 1) rather than le.
     */
    @TestVisible
    private static String buildFilter(ArchiveQuery q) {
        String field = String.isBlank(q.dateField) ? 'CreatedDate' : q.dateField.trim();
        List<String> clauses = new List<String>();

        // Key bounds first: an indexed range, so the archive seeks rather than scans.
        if (String.isNotBlank(q.partitionKeyFrom)) {
            clauses.add('PartitionKey ge \'' + odataString(q.partitionKeyFrom) + '\'');
        }
        if (String.isNotBlank(q.partitionKeyBefore)) {
            clauses.add('PartitionKey lt \'' + odataString(q.partitionKeyBefore) + '\'');
        }
        if (q.fromDate != null) {
            clauses.add(field + ' ge \'' + isoStart(q.fromDate) + '\'');
        }
        if (q.toDate != null) {
            clauses.add(field + ' lt \'' + isoStart(q.toDate.addDays(1)) + '\'');
        }
        return clauses.isEmpty() ? null : String.join(clauses, ' and ');
    }

    /** An OData string literal body: a single quote is escaped by doubling it. */
    private static String odataString(String value) {
        return value.replace('\'', '\'\'');
    }

    private static String isoStart(Date value) {
        return String.valueOf(value) + 'T00:00:00.000Z';
    }

    /**
     * $select list. Id and the date field are always included - the first keys the
     * datatable rows, the second orders them - even when not displayed as columns.
     */
    @TestVisible
    private static String buildSelect(ArchiveQuery q) {
        if (q.selectFields == null || q.selectFields.isEmpty()) {
            return null;
        }

        Set<String> fields = new Set<String>{
            String.isBlank(q.idField) ? 'Id' : q.idField.trim()
        };
        if (String.isNotBlank(q.dateField)) {
            fields.add(q.dateField.trim());
        }
        for (String field : q.selectFields) {
            if (String.isNotBlank(field)) {
                fields.add(field.trim());
            }
        }
        return String.join(new List<String>(fields), ',');
    }

    @TestVisible
    private static String buildEndpoint(
        ArchiveQuery q,
        String path,
        String filter,
        String selectClause,
        Integer wanted,
        String nextPartitionKey,
        String nextRowKey
    ) {
        String credential = String.isBlank(q.namedCredential)
            ? DEFAULT_NAMED_CREDENTIAL
            : q.namedCredential.trim();
        // Tolerate a config value entered either as 'Name' or 'callout:Name'.
        if (credential.startsWith('callout:')) {
            credential = credential.substring('callout:'.length());
        }

        List<String> params = new List<String>();
        params.add('$top=' + String.valueOf(wanted));
        if (String.isNotBlank(selectClause)) {
            params.add('$select=' + encode(selectClause));
        }
        if (String.isNotBlank(filter)) {
            params.add('$filter=' + encode(filter));
        }
        if (String.isNotBlank(nextPartitionKey)) {
            params.add('NextPartitionKey=' + encode(nextPartitionKey));
        }
        if (String.isNotBlank(nextRowKey)) {
            params.add('NextRowKey=' + encode(nextRowKey));
        }

        return 'callout:' + credential + path + '?' + String.join(params, '&');
    }

    /**
     * urlEncode emits '+' for a space, which Table Storage reads literally inside
     * a quoted $filter value. %20 is unambiguous in both readings.
     */
    private static String encode(String value) {
        return EncodingUtil.urlEncode(value, 'UTF-8').replace('+', '%20');
    }

    /**
     * Folds one HTTP response into the accumulating result.
     *
     * Returns false when the caller should stop and surface result.errorCode.
     *
     * A body that parses but carries no "value" key is treated as a hard error,
     * not an empty page. The previous contract used "records", and silently
     * reading zero rows out of a 200 response produced a plausible-looking but
     * entirely empty report - the exact failure ArchiveReadContractTest exists to
     * prevent. An empty archive legitimately returns {"value":[]}, which parses
     * to a present-but-empty list and is not an error.
     */
    @TestVisible
    private static Boolean absorbPage(HttpResponse res, PageResult result) {
        if (res == null) {
            result.errorCode = 'NULL_RESPONSE';
            result.errorMessage = 'Archive service returned no response';
            return false;
        }

        Integer status = res.getStatusCode();
        String body = res.getBody();

        if (status == 404) {
            result.endpointUnavailable = true;
            result.errorCode = 'READ_ENDPOINT_NOT_FOUND';
            result.errorMessage =
                'The archive gateway has no read operation for this object. Set '
                + 'Azure_Archive_Config__mdt.Read_Named_Credential__c / Read_Path__c '
                + 'once Azure publishes its retrieval operation.';
            return false;
        }

        if (status < 200 || status >= 300) {
            result.errorCode = 'ARCHIVE_HTTP_' + String.valueOf(status);
            result.errorMessage = String.isNotBlank(body) ? body : res.getStatus();
            return false;
        }

        Map<String, Object> parsed;
        try {
            parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        } catch (Exception e) {
            result.errorCode = 'INVALID_RESPONSE';
            result.errorMessage = 'Unable to parse archive response: ' + e.getMessage();
            return false;
        }

        if (!parsed.containsKey('value')) {
            result.errorCode = 'UNEXPECTED_RESPONSE_SHAPE';
            result.errorMessage =
                'Archive response has no "value" array - the retrieval contract has '
                + 'changed. Refusing to report an empty result set as success.';
            return false;
        }

        Object rawValue = parsed.get('value');
        if (!(rawValue instanceof List<Object>)) {
            result.errorCode = 'UNEXPECTED_RESPONSE_SHAPE';
            result.errorMessage = 'Archive response "value" is not an array.';
            return false;
        }

        for (Object row : (List<Object>) rawValue) {
            if (row instanceof Map<String, Object>) {
                result.records.add((Map<String, Object>) row);
            }
        }
        return true;
    }
}