/**
 * Conformance suite for the archive READ contract.
 *
 * Azure published the retrieval operation on 2026-09-17:
 *
 *   GET /retrieve/OrderLineItems  ->  200 {"value":[ {flat record}, ... ]}
 *
 * verified live the same day. This suite pins that contract from the Salesforce
 * side, so that if the gateway's response shape drifts, a test fails here instead
 * of the report quietly rendering something wrong.
 *
 * Each test states whether the variation is a BLOCKER (report is wrong, empty or
 * misleading), DEGRADED (report is right but loses something) or TOLERATED. The
 * point is to hand Azure a short list of things that genuinely must not change.
 *
 * The superseded TDD section 4.2.2 shape - records nested under "fields", keyed
 * on "records", with a totalCount - is covered below precisely because the report
 * used to accept it silently.
 */
@IsTest
private class ArchiveReadContractTest {

    private static final String ILI = 'Invoice_Line_Item__c';

    private static final String OLI = 'Order_Line_Item__c';

    /** Emits an arbitrary status + body, so any wire shape can be simulated. */
    private class ShapeMock implements HttpCalloutMock {
        private final Integer status;
        private final String body;
        ShapeMock(Integer status, String body) {
            this.status = status;
            this.body = body;
        }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(body);
            return res;
        }
    }

    private static ArchivedRecordsController.ReportPage run(Integer status, String body) {
        return runFor(OLI, status, body);
    }

    private static ArchivedRecordsController.ReportPage runFor(
        String objectApiName, Integer status, String body
    ) {
        Test.setMock(HttpCalloutMock.class, new ShapeMock(status, body));
        return ArchivedRecordsController.getArchivedRecords(
            new List<String>{ objectApiName }, null, null, 10, 1, null);
    }

    /**
     * True when the response raised to the user rather than being absorbed.
     *
     * Only the fact of the raise is asserted here: Apex replaces an
     * AuraHandledException's message with 'Script-thrown exception' inside a test
     * context, so the wording is unassertable at this layer. The error codes and
     * messages themselves are pinned in ArchiveReadServiceTest, which inspects
     * PageResult directly.
     */
    private static Boolean raisesToTheUser(Integer status, String body) {
        try {
            run(status, body);
            return false;
        } catch (AuraHandledException e) {
            return true;
        }
    }

    private static Object firstRowValue(ArchivedRecordsController.ReportPage p, String fieldName) {
        return p.rows.isEmpty() ? null : p.rows[0].get(fieldName);
    }

    private static String valueBody(List<Object> rows) {
        return JSON.serialize(new Map<String, Object>{ 'value' => rows });
    }

    // ------------------------------------------------------------ the baseline

    @IsTest
    static void liveShapePopulatesTheReport() {
        String body = valueBody(new List<Object>{
            new Map<String, Object>{
                'PartitionKey' => 'O-0057',
                'RowKey' => 'a0TGB00003oqswE2AQ',
                'Timestamp' => '2026-09-11T12:14:41.4911442Z',
                'Id' => 'a0TGB00003oqswE2AQ',
                'Order_Name__c' => 'Order-Item-0184',
                'Total_Amount__c' => 203.39,
                'CreatedDate' => '2025-04-01T11:35:05.000Z',
                'Archived_Date__c' => '2026-08-30T12:04:47.679Z'
            }
        });

        Test.startTest();
        ArchivedRecordsController.ReportPage p = run(200, body);
        Test.stopTest();

        System.assertEquals(false, p.degraded, 'A healthy 200 must not degrade to the log index');
        System.assertEquals(1, p.totalCount, 'Totals are counted from the rows retrieved');
        System.assertEquals(1, p.rows.size(), 'The row should be rendered');
        System.assertEquals('Order-Item-0184', firstRowValue(p, 'Order_Name__c'),
            'Flat field names map straight through to columns');
        System.assertEquals(203.39, firstRowValue(p, 'Total_Amount__c'),
            'Numeric fields survive as numbers');
    }

    @IsTest
    static void rowsAreOrderedNewestFirst() {
        String body = valueBody(new List<Object>{
            new Map<String, Object>{ 'Id' => 'a1', 'Order_Name__c' => 'oldest',
                                     'Archived_Date__c' => '2025-01-01T00:00:00.000Z' },
            new Map<String, Object>{ 'Id' => 'a2', 'Order_Name__c' => 'newest',
                                     'Archived_Date__c' => '2026-01-01T00:00:00.000Z' },
            new Map<String, Object>{ 'Id' => 'a3', 'Order_Name__c' => 'middle',
                                     'Archived_Date__c' => '2025-06-01T00:00:00.000Z' }
        });

        Test.startTest();
        ArchivedRecordsController.ReportPage p = run(200, body);
        Test.stopTest();

        System.assertEquals(3, p.rows.size(), 'All three rows render');
        System.assertEquals('newest', p.rows[0].get('Order_Name__c'),
            'The archive returns storage order; the report must impose date order');
        System.assertEquals('middle', p.rows[1].get('Order_Name__c'));
        System.assertEquals('oldest', p.rows[2].get('Order_Name__c'));
    }

    @IsTest
    static void emptyArchiveIsAnEmptyReportNotAFallback() {
        Test.startTest();
        ArchivedRecordsController.ReportPage p = run(200, '{"value":[]}');
        Test.stopTest();

        System.assertEquals(false, p.degraded,
            'An empty result set is a real answer from a working endpoint');
        System.assertEquals(0, p.totalCount, 'Nothing matched');
        System.assertEquals(0, p.rows.size());
    }

    // ------------------------------------------------------------ BLOCKER 1
    // The envelope key changing away from "value".

    @IsTest
    static void recordsKeyInsteadOfValueIsRejectedLoudly() {
        // The superseded TDD shape. Previously this produced a confident, entirely
        // empty report: 200 OK, zero rows, no error, no fallback banner.
        String body = JSON.serialize(new Map<String, Object>{
            'totalCount' => 942,
            'returnedCount' => 1,
            'records' => new List<Object>{
                new Map<String, Object>{ 'Id' => 'a1', 'Order_Name__c' => 'OLI-1',
                                         'CreatedDate' => '2026-08-30T06:49:13.000Z' }
            }
        });

        Test.startTest();
        Boolean raised = raisesToTheUser(200, body);
        Test.stopTest();

        System.assertEquals(true, raised,
            'BLOCKER: a 200 with no "value" array must raise, not report zero rows. '
            + 'This shape previously produced a confident, entirely empty report.');
    }

    @IsTest
    static void valueThatIsNotAnArrayIsRejected() {
        Test.startTest();
        Boolean raised = raisesToTheUser(200, '{"value":{"Name":"OLI-1"}}');
        Test.stopTest();

        System.assertEquals(true, raised,
            'BLOCKER: a single object under "value" must not be read as an empty page');
    }

    // ------------------------------------------------------------ BLOCKER 2
    // Records nested one level down instead of flat.

    @IsTest
    static void nestedFieldsRenderBlankColumns() {
        String body = valueBody(new List<Object>{
            new Map<String, Object>{
                'Id' => 'a1',
                'fields' => new Map<String, Object>{
                    'Order_Name__c' => 'OLI-1', 'Total_Amount__c' => 203.39
                }
            }
        });

        Test.startTest();
        ArchivedRecordsController.ReportPage p = run(200, body);
        Test.stopTest();

        System.assertEquals(1, p.rows.size(), 'The row count still looks right...');
        System.assertEquals(null, firstRowValue(p, 'Order_Name__c'),
            'BLOCKER: nesting under "fields" silently blanks every data column. '
            + 'The archive must keep returning flat records.');
    }

    // ------------------------------------------------------------ BLOCKER 3
    // Field-name casing, which differs per object.
    //
    // Order Line Items are archived with exact Salesforce casing; Invoice Line
    // Items entirely in lower case. Both verified live on 2026-09-21 - the two
    // Azure Functions were written independently. So casing is not a single
    // global rule to enforce, it is a per-object fact the report has to know,
    // and the blocker is a MISMATCH against whichever convention an object uses.

    @IsTest
    static void orderLineItemsInTheWrongCaseRenderBlankColumns() {
        String body = valueBody(new List<Object>{
            new Map<String, Object>{
                'id' => 'a1', 'order_name__c' => 'OLI-1', 'total_amount__c' => 203.39,
                'createddate' => '2025-04-01T11:35:05.000Z'
            }
        });

        Test.startTest();
        ArchivedRecordsController.ReportPage p = run(200, body);
        Test.stopTest();

        System.assertEquals(1, p.rows.size(), 'The row count still looks right...');
        System.assertEquals(null, firstRowValue(p, 'Order_Name__c'),
            'BLOCKER: Order Line Items are stored with Salesforce casing, so a '
            + 'lower-cased payload maps to nothing. Column mapping is case-sensitive; '
            + 'if this endpoint ever switches to lower case, ARCHIVE_NAMING must be '
            + 'updated to match or every column goes blank with no error.');
    }

    /**
     * The Invoice Line Item contract, which is the mirror image: lower case is
     * correct here, and it must render. If this fails, ARCHIVE_NAMING has drifted
     * from what the endpoint actually stores.
     */
    @IsTest
    static void invoiceLineItemsInLowerCaseRender() {
        String body = valueBody(new List<Object>{
            new Map<String, Object>{
                'id' => 'a0T1', 'name' => 'Invoice-Item-8044100',
                'invoice_number__c' => 'INV-001', 'product_code__c' => '5300133',
                'quantity__c' => 12, 'total_amount__c' => 4800.0,
                'createddate' => '2026-07-21T09:06:01.000Z',
                'archived_date__c' => '2026-09-18T10:30:00.538Z'
            }
        });

        Test.startTest();
        ArchivedRecordsController.ReportPage p = runFor(ILI, 200, body);
        Test.stopTest();

        System.assertEquals(false, p.degraded,
            'Invoice Line Items has a published read route and must not fall back');
        System.assertEquals(1, p.rows.size());
        System.assertEquals('INV-001', firstRowValue(p, 'invoice_number__c'),
            'Lower-case field names are correct for this object and must map');
        System.assertEquals(4800.0, firstRowValue(p, 'total_amount__c'));
        System.assertEquals('a0T1', firstRowValue(p, '_rowKey'),
            'The lower-case id column keys the datatable row');
    }

    /**
     * Columns must be declared in the case the archive uses, not the case
     * Salesforce describe reports. Describe matches names case-insensitively and
     * hands back its own casing, so taking that would silently break every
     * lower-case object.
     */
    @IsTest
    static void invoiceLineItemColumnsKeepTheArchiveCasing() {
        String body = valueBody(new List<Object>{
            new Map<String, Object>{ 'id' => 'a0T1', 'name' => 'Invoice-Item-1' }
        });

        Test.startTest();
        ArchivedRecordsController.ReportPage p = runFor(ILI, 200, body);
        Test.stopTest();

        Set<String> columnNames = new Set<String>();
        for (ArchivedRecordsController.ReportColumn col : p.columns) {
            columnNames.add(col.fieldName);
        }
        System.assert(columnNames.contains('total_amount__c'),
            'Columns must carry the archive name: ' + columnNames);
        System.assert(!columnNames.contains('Total_Amount__c'),
            'Salesforce casing here would match nothing in the rows: ' + columnNames);
    }

    // ------------------------------------------------------------ DEGRADED
    // Things that cost the report something without making it wrong.

    @IsTest
    static void missingIdFallsBackToASyntheticRowKey() {
        String body = valueBody(new List<Object>{
            new Map<String, Object>{ 'Order_Name__c' => 'OLI-1',
                                     'CreatedDate' => '2025-04-01T11:35:05.000Z' }
        });

        Test.startTest();
        ArchivedRecordsController.ReportPage p = run(200, body);
        Test.stopTest();

        System.assertEquals('OLI-1', firstRowValue(p, 'Order_Name__c'), 'The row still renders');
        System.assertNotEquals(null, firstRowValue(p, '_rowKey'),
            'DEGRADED: without Id the datatable key is positional, so row identity is '
            + 'not stable across pages - but nothing is displayed incorrectly.');
    }

    @IsTest
    static void missingDateSortsLastWithoutBreakingTheReport() {
        String body = valueBody(new List<Object>{
            new Map<String, Object>{ 'Id' => 'a1', 'Order_Name__c' => 'undated' },
            new Map<String, Object>{ 'Id' => 'a2', 'Order_Name__c' => 'dated',
                                     'Archived_Date__c' => '2025-06-01T00:00:00.000Z' }
        });

        Test.startTest();
        ArchivedRecordsController.ReportPage p = run(200, body);
        Test.stopTest();

        System.assertEquals(2, p.rows.size(), 'Both rows render');
        System.assertEquals('dated', p.rows[0].get('Order_Name__c'),
            'DEGRADED: undated rows sort last rather than corrupting the ordering');
    }

    // ------------------------------------------------------------ TOLERATED

    @IsTest
    static void extraUnknownKeysAreIgnored() {
        String body = valueBody(new List<Object>{
            new Map<String, Object>{
                'Id' => 'a1', 'Order_Name__c' => 'OLI-1',
                'CreatedDate' => '2025-04-01T11:35:05.000Z',
                'PartitionKey' => 'O-0057', 'RowKey' => 'a1', 'Timestamp' => 'x',
                'odata.etag' => 'W/"datetime\'2026\'"', 'somethingNew' => 42
            }
        });

        Test.startTest();
        ArchivedRecordsController.ReportPage p = run(200, body);
        Test.stopTest();

        System.assertEquals('OLI-1', firstRowValue(p, 'Order_Name__c'),
            'TOLERATED: Table Storage metadata and future keys are simply not columns');
    }

    @IsTest
    static void quotedNumbersStillRender() {
        String body = valueBody(new List<Object>{
            new Map<String, Object>{
                'Id' => 'a1', 'Order_Name__c' => 'OLI-1', 'Total_Amount__c' => '203.39',
                'CreatedDate' => '2025-04-01T11:35:05.000Z'
            }
        });

        Test.startTest();
        ArchivedRecordsController.ReportPage p = run(200, body);
        Test.stopTest();

        System.assertEquals('203.39', firstRowValue(p, 'Total_Amount__c'),
            'TOLERATED: a stringified number reaches the datatable, which formats it');
    }

    // ------------------------------------------------------------ transport

    @IsTest
    static void notFoundDegradesToTheLogIndex() {
        Test.startTest();
        ArchivedRecordsController.ReportPage p = run(404, '{"statusCode":404,"message":"Resource not found"}');
        Test.stopTest();

        System.assertEquals(true, p.degraded,
            'A 404 means this object has no published route, so the log index stands in');
        System.assertNotEquals(null, p.degradedReason, 'And the user is told why');
    }

    @IsTest
    static void serverErrorIsRaisedNotDegraded() {
        Test.startTest();
        Boolean raised = raisesToTheUser(500, '{"errorCode":"UPSTREAM_FAILURE"}');
        Test.stopTest();

        System.assertEquals(true, raised,
            'A broken archive must not masquerade as an unpublished one by degrading');
    }

    @IsTest
    static void authRejectionIsRaisedNotDegraded() {
        String body =
            '<?xml version="1.0" encoding="utf-8" standalone="yes"?>'
            + '<error><code>InvalidAuthenticationInfo</code></error>';

        Test.startTest();
        Boolean raised = raisesToTheUser(400, body);
        Test.stopTest();

        System.assertEquals(true, raised,
            'Sending an Authorization header to Table Storage 400s; that is a '
            + 'misconfiguration and must be visible, not silently degraded');
    }
}