/**
 * Tests for ArchiveInvoiceLineItemsBatch: sending Invoice Line Items to the Azure
 * archive, marking the ones Azure confirms as archived, snapshotting their
 * invoices' totals, and logging the run.
 *
 * Which records the batch picks up comes from Azure_Archive_Config__mdt
 * 'Invoice_Line_Item' (Closed_State_Values__c / Retention_Days__c). In the
 * sandbox that is every line item not yet archived, so the tests rely only on
 * Archived__c - not on record age - to decide what is eligible.
 */
@IsTest
private class ArchiveInvoiceLineItemsBatchTest {

    private static Invoice__c createInvoice(String name) {
        Invoice__c invoice = new Invoice__c(
            Name = name, Status__c = 'Draft', Invoice_Date__c = Date.today());
        insert invoice;
        return invoice;
    }

    private static List<Invoice_Line_Item__c> createLineItems(Id invoiceId, Integer count) {
        return createLineItems(invoiceId, count, false);
    }

    private static List<Invoice_Line_Item__c> createLineItems(Id invoiceId, Integer count, Boolean archived) {
        List<Invoice_Line_Item__c> items = new List<Invoice_Line_Item__c>();
        for (Integer i = 0; i < count; i++) {
            items.add(new Invoice_Line_Item__c(
                Invoice__c = invoiceId,
                Quantity__c = 2 + i,
                Price__c = 100,
                Total_Amount__c = (2 + i) * 100,
                Archived__c = archived
            ));
        }
        insert items;
        return items;
    }

    private static List<String> idStrings(List<Invoice_Line_Item__c> items) {
        List<String> ids = new List<String>();
        for (Invoice_Line_Item__c item : items) {
            ids.add(item.Id);
        }
        return ids;
    }

    private static void runBatch(HttpCalloutMock mock) {
        if (mock != null) {
            Test.setMock(HttpCalloutMock.class, mock);
        }
        Test.startTest();
        Database.executeBatch(new ArchiveInvoiceLineItemsBatch(), 200);
        Test.stopTest();
    }

    private static Map<Id, Invoice_Line_Item__c> reload(List<Invoice_Line_Item__c> items) {
        return new Map<Id, Invoice_Line_Item__c>([
            SELECT Id, Archived__c, Archived_Date__c
            FROM Invoice_Line_Item__c
            WHERE Id IN :new Map<Id, Invoice_Line_Item__c>(items).keySet()
        ]);
    }

    private static Archival_Job_Log__c jobLog() {
        List<Archival_Job_Log__c> logs = [
            SELECT Archived_Object__c, Total_Archived__c, Total_Failed__c, Total_Processed__c,
                   Error_Message__c, Archive_Batch_Id__c
            FROM Archival_Job_Log__c
        ];
        System.assertEquals(1, logs.size(), 'finish() writes exactly one job log');
        return logs[0];
    }

    // ------------------------------------------------------------ archiving

    @IsTest
    static void confirmedLineItemsAreArchivedAndLogged() {
        Invoice__c invoice = createInvoice('INV-ARCH-001');
        List<Invoice_Line_Item__c> items = createLineItems(invoice.Id, 3);

        runBatch(new ArchiveConnectorServiceMocks.SuccessMock(idStrings(items)));

        for (Invoice_Line_Item__c item : reload(items).values()) {
            System.assertEquals(true, item.Archived__c, 'Confirmed by Azure, so marked archived');
            System.assertNotEquals(null, item.Archived_Date__c, 'And stamped with when');
        }
        Archival_Job_Log__c log = jobLog();
        System.assertEquals('Invoice_Line_Item__c', log.Archived_Object__c);
        System.assertEquals(3, log.Total_Processed__c);
        System.assertEquals(3, log.Total_Archived__c);
        System.assertEquals(0, log.Total_Failed__c);
        System.assertEquals(null, log.Error_Message__c);
        System.assertNotEquals(null, log.Archive_Batch_Id__c, 'The log names the batch job');
    }

    @IsTest
    static void theInvoiceTotalsAreSnapshotted() {
        Invoice__c invoice = createInvoice('INV-ARCH-002');
        List<Invoice_Line_Item__c> items = createLineItems(invoice.Id, 2);

        runBatch(new ArchiveConnectorServiceMocks.SuccessMock(idStrings(items)));

        Invoice__c after = [
            SELECT Number_of_Invoice_Line_Items__c, Snapshot_Number_of_Invoice_Line_Items__c,
                   Invoice_Line_Item_Total_Amount__c, Snapshot_Invoice_Line_Item_Total_Amount__c,
                   Invoice_Amount_Before_Tax_del__c, Snapshot_Invoice_Amount_Before_Tax__c,
                   Collected_Amount__c, Snapshot_Collected_Amount__c,
                   Discount__c, Snapshot_Discount__c,
                   Total_Discount__c, Snapshot_Total_Discount__c,
                   Total_Discount1__c, Snapshot_Total_Discount_1__c,
                   Total_Discount_2__c, Snapshot_Total_Discount_2__c
            FROM Invoice__c WHERE Id = :invoice.Id
        ];
        // Each snapshot holds the invoice's own value at the moment of archiving,
        // so the invoice keeps its totals once the line items leave the org.
        System.assertEquals(after.Number_of_Invoice_Line_Items__c, after.Snapshot_Number_of_Invoice_Line_Items__c);
        System.assertEquals(after.Invoice_Line_Item_Total_Amount__c, after.Snapshot_Invoice_Line_Item_Total_Amount__c);
        System.assertEquals(after.Invoice_Amount_Before_Tax_del__c, after.Snapshot_Invoice_Amount_Before_Tax__c);
        System.assertEquals(after.Collected_Amount__c, after.Snapshot_Collected_Amount__c);
        System.assertEquals(after.Discount__c, after.Snapshot_Discount__c);
        System.assertEquals(after.Total_Discount__c, after.Snapshot_Total_Discount__c);
        System.assertEquals(after.Total_Discount1__c, after.Snapshot_Total_Discount_1__c);
        System.assertEquals(after.Total_Discount_2__c, after.Snapshot_Total_Discount_2__c);
    }

    @IsTest
    static void onlyLineItemsAzureConfirmsAreArchived() {
        Invoice__c confirmedInvoice = createInvoice('INV-ARCH-003');
        Invoice__c otherInvoice = createInvoice('INV-ARCH-004');
        List<Invoice_Line_Item__c> confirmed = createLineItems(confirmedInvoice.Id, 1);
        List<Invoice_Line_Item__c> notConfirmed = createLineItems(otherInvoice.Id, 2);

        runBatch(new ArchiveConnectorServiceMocks.SuccessMock(idStrings(confirmed)));

        System.assertEquals(true, reload(confirmed).values()[0].Archived__c);
        for (Invoice_Line_Item__c item : reload(notConfirmed).values()) {
            System.assertEquals(false, item.Archived__c, 'Not confirmed, so left in place');
        }
        System.assertNotEquals(null, [
            SELECT Snapshot_Number_of_Invoice_Line_Items__c FROM Invoice__c WHERE Id = :confirmedInvoice.Id
        ].Snapshot_Number_of_Invoice_Line_Items__c, 'The confirmed invoice is snapshotted');
        System.assertEquals(null, [
            SELECT Snapshot_Number_of_Invoice_Line_Items__c FROM Invoice__c WHERE Id = :otherInvoice.Id
        ].Snapshot_Number_of_Invoice_Line_Items__c, 'An invoice with nothing archived is not');

        Archival_Job_Log__c log = jobLog();
        System.assertEquals(3, log.Total_Processed__c);
        System.assertEquals(1, log.Total_Archived__c);
    }

    @IsTest
    static void alreadyArchivedLineItemsAreNotSentAgain() {
        Invoice__c invoice = createInvoice('INV-ARCH-005');
        List<Invoice_Line_Item__c> items = createLineItems(invoice.Id, 2, true);

        runBatch(new ArchiveConnectorServiceMocks.SuccessMock(idStrings(items)));

        Archival_Job_Log__c log = jobLog();
        System.assertEquals(0, log.Total_Processed__c, 'Nothing eligible, nothing sent');
        System.assertEquals(0, log.Total_Archived__c);
    }

    // ------------------------------------------------------------ failures

    @IsTest
    static void aRejectedSendArchivesNothingAndLogsWhy() {
        Invoice__c invoice = createInvoice('INV-ARCH-006');
        List<Invoice_Line_Item__c> items = createLineItems(invoice.Id, 2);

        runBatch(new ArchiveConnectorServiceMocks.LogicalFailureMock());

        for (Invoice_Line_Item__c item : reload(items).values()) {
            System.assertEquals(false, item.Archived__c, 'Azure did not accept them');
        }
        Archival_Job_Log__c log = jobLog();
        System.assertEquals(2, log.Total_Failed__c);
        System.assertEquals(0, log.Total_Archived__c);
        System.assert(log.Error_Message__c.contains('VALIDATION_FAILED'),
            'The error code is logged: ' + log.Error_Message__c);
    }

    @IsTest
    static void aServerErrorArchivesNothing() {
        Invoice__c invoice = createInvoice('INV-ARCH-007');
        List<Invoice_Line_Item__c> items = createLineItems(invoice.Id, 2);

        runBatch(new ArchiveConnectorServiceMocks.HttpErrorMock(500, '{"error":"upstream"}'));

        for (Invoice_Line_Item__c item : reload(items).values()) {
            System.assertEquals(false, item.Archived__c);
        }
        Archival_Job_Log__c log = jobLog();
        System.assertEquals(2, log.Total_Failed__c);
        System.assertNotEquals(null, log.Error_Message__c);
    }

    @IsTest
    static void aCalloutFailureArchivesNothing() {
        Invoice__c invoice = createInvoice('INV-ARCH-008');
        List<Invoice_Line_Item__c> items = createLineItems(invoice.Id, 2);

        runBatch(new ArchiveConnectorServiceMocks.ExceptionMock());

        for (Invoice_Line_Item__c item : reload(items).values()) {
            System.assertEquals(false, item.Archived__c, 'A timeout leaves the records in place');
        }
        System.assertEquals(2, jobLog().Total_Failed__c);
    }

    // ------------------------------------------------------------ entry points

    @IsTest
    static void startBuildsTheQueryFromTheArchiveConfig() {
        Database.QueryLocator locator = new ArchiveInvoiceLineItemsBatch().start(null);

        String query = locator.getQuery();
        System.assert(query.containsIgnoreCase('FROM Invoice_Line_Item__c'), query);
        System.assert(query.containsIgnoreCase('archived__c'), 'Every field is sent to the archive: ' + query);
        String configured = Azure_Archive_Config__mdt.getInstance('Invoice_Line_Item').Closed_State_Values__c;
        if (String.isNotBlank(configured)) {
            System.assert(query.endsWith(configured),
                'The config\'s clause decides what is eligible: ' + query);
        }
    }

    @IsTest
    static void theSchedulerStartsTheBatch() {
        Test.startTest();
        Id jobId = System.schedule(
            'ArchiveInvoiceLineItemsBatchTest', '0 0 2 * * ?', new ArchiveInvoiceLineItemsBatch());
        Test.stopTest();

        CronTrigger scheduled = [SELECT CronExpression, State FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals('0 0 2 * * ?', scheduled.CronExpression);
    }
}