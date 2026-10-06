/**
 * HttpCalloutMock implementations for the archive read path.
 *
 * Shapes here mirror responses captured live from
 * GET https://hangyo-archival-apim.azure-api.net/retrieve/OrderLineItems
 * on 2026-09-17: a bare {"value":[...]} envelope with no row count, and
 * forward-only paging via x-ms-continuation-* response headers.
 */
@IsTest
public class ArchiveReadServiceMocks {

    /** Field names exactly as the archive returns them, for one synthetic row. */
    public static Map<String, Object> sampleRow(Integer i) {
        return new Map<String, Object>{
            'PartitionKey' => 'O-' + String.valueOf(1000 + i),
            'RowKey' => 'a0TGB00003oqsw' + String.valueOf(i).leftPad(4, '0'),
            'Timestamp' => '2026-09-11T12:14:41.4911442Z',
            'Id' => 'a0TGB00003oqsw' + String.valueOf(i).leftPad(4, '0'),
            'Name' => 'Order-Item-' + String.valueOf(i).leftPad(4, '0'),
            'Order__c' => 'a0UGB00002Q4pzw2AB',
            'Product_Code__c' => '53000' + String.valueOf(i).leftPad(2, '0'),
            'Ordered_Quantity__c' => 1 + Math.mod(i, 5),
            'Unit_of_Measure__c' => 'EA',
            'Product_Price__c' => 203.39,
            'Total_Amount__c' => 203.39,
            'Total_Amount_Incl_Tax__c' => 213.56,
            // Descending index, so a correct newest-first sort reverses the input.
            'CreatedDate' => '2025-04-' + String.valueOf(28 - Math.mod(i, 27)).leftPad(2, '0')
                + 'T11:35:05.000Z',
            // Descends with the index too, so newest-first is deterministic
            // whichever date basis the report is using.
            'Archived_Date__c' => '2026-08-' + String.valueOf(28 - Math.mod(i, 27)).leftPad(2, '0')
                + 'T12:04:47.679Z'
        };
    }

    public static String valueBody(Integer rowCount, Integer startIndex) {
        List<Object> rows = new List<Object>();
        for (Integer i = 0; i < rowCount; i++) {
            rows.add(sampleRow(startIndex + i));
        }
        return JSON.serialize(new Map<String, Object>{ 'value' => rows });
    }

    /** One page of archived records in the live {"value":[...]} shape. */
    public class SuccessMock implements HttpCalloutMock {
        private final Integer rowCount;
        public String lastEndpoint;
        public Integer callCount = 0;

        public SuccessMock(Integer rowCount) {
            this.rowCount = rowCount;
        }

        public HttpResponse respond(HttpRequest req) {
            lastEndpoint = req.getEndpoint();
            callCount++;

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(valueBody(rowCount, 0));
            return res;
        }
    }

    /**
     * Serves a fixed number of pages, each advertising a continuation, then a
     * final page without one - the shape the service must follow to completion.
     */
    public class ContinuationMock implements HttpCalloutMock {
        private final Integer rowsPerPage;
        private final Integer pages;
        public Integer callCount = 0;
        public List<String> endpoints = new List<String>();

        public ContinuationMock(Integer rowsPerPage, Integer pages) {
            this.rowsPerPage = rowsPerPage;
            this.pages = pages;
        }

        public HttpResponse respond(HttpRequest req) {
            endpoints.add(req.getEndpoint());
            callCount++;

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(valueBody(rowsPerPage, (callCount - 1) * rowsPerPage));

            if (callCount < pages) {
                res.setHeader('x-ms-continuation-NextPartitionKey', '1!8!Ty0wMDU5');
                res.setHeader('x-ms-continuation-NextRowKey', '1!24!YTBUR0Iw' + callCount);
            }
            return res;
        }
    }

    /**
     * One distinct archived day per page, each page advertising a cursor named
     * after itself.
     *
     * Built for the first-seen cursor logic, which is only meaningful across
     * pages: the day on page one is met before any cursor exists and must record
     * a null bound, while a day first met on page three must record the cursor
     * page two handed back - not page three's own, which points past it.
     */
    public class DayPagesMock implements HttpCalloutMock {
        private final Integer rowsPerPage;
        private final Integer pages;
        public Integer callCount = 0;
        public List<String> endpoints = new List<String>();

        public DayPagesMock(Integer rowsPerPage, Integer pages) {
            this.rowsPerPage = rowsPerPage;
            this.pages = pages;
        }

        public HttpResponse respond(HttpRequest req) {
            endpoints.add(req.getEndpoint());
            callCount++;

            List<Object> rows = new List<Object>();
            for (Integer i = 0; i < rowsPerPage; i++) {
                Map<String, Object> row = sampleRow(i);
                // Day 01, 02, 03... one per page, so a day maps to exactly the
                // page it arrived on.
                row.put('Archived_Date__c',
                    '2026-09-' + String.valueOf(callCount).leftPad(2, '0') + 'T19:01:42.373Z');
                rows.add(row);
            }

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(JSON.serialize(new Map<String, Object>{ 'value' => rows }));

            if (callCount < pages) {
                res.setHeader('x-ms-continuation-NextPartitionKey', 'PK-' + callCount);
                res.setHeader('x-ms-continuation-NextRowKey', 'RK-' + callCount);
            }
            return res;
        }
    }

    /**
     * Always advertises another page. Used to prove the row cap stops the loop
     * rather than running until the callout limit.
     */
    public class EndlessMock implements HttpCalloutMock {
        private final Integer rowsPerPage;
        public Integer callCount = 0;

        public EndlessMock(Integer rowsPerPage) {
            this.rowsPerPage = rowsPerPage;
        }

        public HttpResponse respond(HttpRequest req) {
            callCount++;
            // $top is honoured by the live gateway up to 1000 - verified
            // 2026-09-17 - so the mock honours it too. Returning rowsPerPage
            // regardless would let a page-sized read come back oversized here and
            // pass, while the real endpoint returned the page that was asked for.
            Integer rows = Math.min(rowsPerPage, requestedTop(req, rowsPerPage));
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(valueBody(rows, (callCount - 1) * rows));
            res.setHeader('x-ms-continuation-NextPartitionKey', '1!8!Ty0wMDU5');
            res.setHeader('x-ms-continuation-NextRowKey', '1!24!YTBUR0Iw' + callCount);
            return res;
        }
    }

    /** The $top the caller asked for, or fallbackValue when it is absent. */
    private static Integer requestedTop(HttpRequest req, Integer fallbackValue) {
        String endpoint = req == null ? null : req.getEndpoint();
        if (String.isBlank(endpoint)) {
            return fallbackValue;
        }
        Matcher m = Pattern.compile('[?&]\\$top=(\\d+)').matcher(endpoint);
        return m.find() ? Integer.valueOf(m.group(1)) : fallbackValue;
    }

    /**
     * A scan in progress: 200, zero rows, but a continuation saying "keep going".
     * Measured live on 2026-09-17 - a date filter is not a key lookup, so Table
     * Storage scans and returns empty pages roughly every five seconds. Nothing
     * bounds this except a hop budget.
     */
    public class ScanningMock implements HttpCalloutMock {
        public Integer callCount = 0;

        public HttpResponse respond(HttpRequest req) {
            callCount++;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"value":[]}');
            res.setHeader('x-ms-continuation-NextPartitionKey', '1!12!Ty0xMDk1MDE-');
            res.setHeader('x-ms-continuation-NextRowKey', '1!24!YTBUR0Iw' + callCount);
            return res;
        }
    }

    /** Empty result set: the gateway returns 200 with an empty array, not 404. */
    public class EmptyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"value":[]}');
            return res;
        }
    }

    /** Object with no published retrieval route - every object but OrderLineItems. */
    public class NotFoundMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            res.setBody('{ "statusCode": 404, "message": "Resource not found" }');
            return res;
        }
    }

    /**
     * What Table Storage returns if an Authorization header reaches it - the
     * failure mode of pointing the read path at the write credential.
     */
    public class AuthHeaderRejectedMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setBody(
                '<?xml version="1.0" encoding="utf-8" standalone="yes"?>'
                + '<error><code>InvalidAuthenticationInfo</code><message xml:lang="en-US">'
                + 'Authentication information is not given in the correct format.'
                + '</message></error>');
            return res;
        }
    }

    /** Server-side failure that must surface to the user, not degrade silently. */
    public class ServerErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setStatus('Internal Server Error');
            res.setBody('{"status":"error","errorCode":"UPSTREAM_FAILURE"}');
            return res;
        }
    }

    /** 200 with a body that is not JSON at all. */
    public class MalformedMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('not-json');
            return res;
        }
    }

    /**
     * The superseded TDD shape: 200 with records under "records" and a totalCount.
     * Reading this as an empty success is the silent-failure mode the service now
     * refuses - it must be an explicit error.
     */
    public class LegacyShapeMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(JSON.serialize(new Map<String, Object>{
                'totalCount' => 942,
                'returnedCount' => 1,
                'records' => new List<Object>{ sampleRow(1) }
            }));
            return res;
        }
    }

    public class ThrowingMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Read timed out');
        }
    }
}