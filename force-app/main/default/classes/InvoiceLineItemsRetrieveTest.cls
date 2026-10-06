/**
 * Tests for InvoiceLineItemsRetrieve: reading archived Invoice Line Items back
 * from Azure for a set of Invoice Ids.
 *
 * The class's contract is that it never throws and always returns a list, so
 * most of these tests feed it a bad response and check it comes back empty (or
 * with only the good rows) rather than failing. Archived rows are shaped as the
 * live endpoint returns them: lower-case field names plus Table Storage's
 * PartitionKey / RowKey / Timestamp.
 */
@IsTest
private class InvoiceLineItemsRetrieveTest {

    /** Returns a fixed status and body, and records what it was asked. */
    private class ArchiveMock implements HttpCalloutMock {
        private final Integer status;
        private final String body;
        private Integer callCount = 0;
        private HttpRequest lastRequest;

        private ArchiveMock(Integer status, String body) {
            this.status = status;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            callCount++;
            lastRequest = req;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setHeader('Content-Type', 'application/json');
            if (body != null) {
                res.setBody(body);
            }
            return res;
        }
    }

    private class ThrowingMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Simulated timeout');
        }
    }

    /** An Invoice Id in the right format; nothing is queried, so it need not exist. */
    private static Id invoiceId(Integer n) {
        return Id.valueOf(Invoice__c.SObjectType.getDescribe().getKeyPrefix()
            + String.valueOf(n).leftPad(12, '0'));
    }

    /** One archived line item exactly as Azure stores it. */
    private static Map<String, Object> archivedRow(Id invoice, String name, Decimal quantity) {
        return new Map<String, Object>{
            'PartitionKey' => 'INV-0001',
            'RowKey' => name,
            'Timestamp' => '2026-09-23T06:00:00.000Z',
            'name' => name,
            'invoice__c' => String.valueOf(invoice),
            'quantity__c' => quantity,
            'price__c' => 1200.0,
            'total_amount__c' => quantity * 1200,
            'product_code__c' => '5300133',
            'archived_date__c' => '2026-09-18T10:30:00.538Z'
        };
    }

    private static String valueBody(List<Object> rows) {
        return JSON.serialize(new Map<String, Object>{ 'value' => rows });
    }

    private static List<Invoice_Line_Item__c> retrieve(HttpCalloutMock mock, Set<Id> ids) {
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        List<Invoice_Line_Item__c> items = InvoiceLineItemsRetrieve.retriveInvoiceLineItems(ids);
        Test.stopTest();
        return items;
    }

    // ------------------------------------------------------------ happy path

    @IsTest
    static void archivedLineItemsAreReadBack() {
        Id invoice = invoiceId(1);
        ArchiveMock mock = new ArchiveMock(200, valueBody(new List<Object>{
            archivedRow(invoice, 'Invoice-Item-0001', 4),
            archivedRow(invoice, 'Invoice-Item-0002', 2)
        }));

        List<Invoice_Line_Item__c> items = retrieve(mock, new Set<Id>{ invoice });

        System.assertEquals(2, items.size(), 'Every archived line item comes back');
        System.assertEquals('Invoice-Item-0001', items[0].Name, 'Lower-case archive names map onto fields');
        System.assertEquals(invoice, items[0].Invoice__c);
        System.assertEquals(4, items[0].Quantity__c);
        System.assertEquals(4800, items[0].Total_Amount__c);
        System.assertEquals(1, mock.callCount, 'One callout for the whole set');
    }

    @IsTest
    static void theRequestFiltersOnEveryInvoiceThroughTheNamedCredential() {
        ArchiveMock mock = new ArchiveMock(200, valueBody(new List<Object>()));
        Id first = invoiceId(1);
        Id second = invoiceId(2);

        retrieve(mock, new Set<Id>{ first, second });

        String endpoint = mock.lastRequest.getEndpoint();
        String decoded = EncodingUtil.urlDecode(endpoint, 'UTF-8');
        System.assert(endpoint.startsWith('callout:AzureArchiveRetrieval_NC/InvoiceLineItems?$filter='),
            'The existing read credential and route are used: ' + endpoint);
        System.assert(decoded.contains('invoice__c eq \'' + first + '\''), decoded);
        System.assert(decoded.contains('invoice__c eq \'' + second + '\''), decoded);
        System.assert(decoded.contains(' or '), 'Invoices are OR-ed into one filter: ' + decoded);
        System.assertEquals('GET', mock.lastRequest.getMethod());
        System.assertEquals('application/json', mock.lastRequest.getHeader('Accept'));
    }

    @IsTest
    static void azureKeysAndAnUnusableIdAreStripped() {
        Id invoice = invoiceId(1);
        Map<String, Object> row = archivedRow(invoice, 'Invoice-Item-0001', 1);
        // Neither is a field on Invoice_Line_Item__c, and an Id that is not a
        // Salesforce Id would make deserialising the row fail.
        row.put('Id', 'not-a-salesforce-id');
        row.put('attributes', new Map<String, Object>{ 'type' => 'Invoice_Line_Item__c' });

        List<Invoice_Line_Item__c> items = retrieve(
            new ArchiveMock(200, valueBody(new List<Object>{ row })), new Set<Id>{ invoice });

        System.assertEquals(1, items.size(), 'The row survives once the extra keys are removed');
        System.assertEquals(null, items[0].Id, 'The archived Id is not carried onto the record');
    }

    // ------------------------------------------------------------ nothing to ask for

    @IsTest
    static void nullOrEmptyIdsMakeNoCallout() {
        ArchiveMock mock = new ArchiveMock(200, valueBody(new List<Object>()));
        Test.setMock(HttpCalloutMock.class, mock);

        List<Invoice_Line_Item__c> fromNull = InvoiceLineItemsRetrieve.retriveInvoiceLineItems(null);
        List<Invoice_Line_Item__c> fromEmpty =
            InvoiceLineItemsRetrieve.retriveInvoiceLineItems(new Set<Id>());

        System.assertNotEquals(null, fromNull, 'Always a list, never null');
        System.assert(fromNull.isEmpty());
        System.assert(fromEmpty.isEmpty());
        System.assertEquals(0, mock.callCount, 'No callout when there is nothing to ask for');
    }

    // ------------------------------------------------------------ bad rows

    @IsTest
    static void aMalformedRowIsSkippedAndTheRestKept() {
        Id invoice = invoiceId(1);
        Map<String, Object> bad = archivedRow(invoice, 'Invoice-Item-BAD', 1);
        bad.put('quantity__c', 'not a number');

        List<Invoice_Line_Item__c> items = retrieve(new ArchiveMock(200, valueBody(new List<Object>{
            bad, archivedRow(invoice, 'Invoice-Item-GOOD', 3)
        })), new Set<Id>{ invoice });

        System.assertEquals(1, items.size(), 'One bad row does not cost the others');
        System.assertEquals('Invoice-Item-GOOD', items[0].Name);
    }

    @IsTest
    static void entriesThatAreNotRecordsAreIgnored() {
        Id invoice = invoiceId(1);

        List<Invoice_Line_Item__c> items = retrieve(new ArchiveMock(200, valueBody(new List<Object>{
            42, 'text', null, archivedRow(invoice, 'Invoice-Item-0001', 1)
        })), new Set<Id>{ invoice });

        System.assertEquals(1, items.size(), 'Only JSON objects become line items');
    }

    // ------------------------------------------------------------ bad responses

    @IsTest
    static void aFailedStatusReturnsNothing() {
        System.assert(retrieve(new ArchiveMock(500, '{"error":"upstream"}'),
            new Set<Id>{ invoiceId(1) }).isEmpty(), 'A 500 is handled, not thrown');
    }

    @IsTest
    static void aMissingRouteReturnsNothing() {
        System.assert(retrieve(new ArchiveMock(404, '{"message":"Resource not found"}'),
            new Set<Id>{ invoiceId(1) }).isEmpty());
    }

    @IsTest
    static void anEmptyBodyReturnsNothing() {
        System.assert(retrieve(new ArchiveMock(200, null), new Set<Id>{ invoiceId(1) }).isEmpty());
    }

    @IsTest
    static void unparsableJsonReturnsNothing() {
        System.assert(retrieve(new ArchiveMock(200, '{not valid json'),
            new Set<Id>{ invoiceId(1) }).isEmpty());
    }

    @IsTest
    static void aBodyThatIsNotAnObjectReturnsNothing() {
        System.assert(retrieve(new ArchiveMock(200, '[{"name":"x"}]'),
            new Set<Id>{ invoiceId(1) }).isEmpty());
    }

    @IsTest
    static void aBodyWithoutAValueArrayReturnsNothing() {
        System.assert(retrieve(new ArchiveMock(200, '{"records":[{"name":"x"}]}'),
            new Set<Id>{ invoiceId(1) }).isEmpty(), 'No "value" key');
        // Separate transaction-free check: "value" present but not a list.
        Test.setMock(HttpCalloutMock.class, new ArchiveMock(200, '{"value":{"name":"x"}}'));
        System.assert(InvoiceLineItemsRetrieve.retriveInvoiceLineItems(
            new Set<Id>{ invoiceId(1) }).isEmpty(), '"value" that is not an array');
    }

    @IsTest
    static void aCalloutFailureReturnsNothing() {
        System.assert(retrieve(new ThrowingMock(), new Set<Id>{ invoiceId(1) }).isEmpty(),
            'A timeout is caught so the PDF can still be generated');
    }
}