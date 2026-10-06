/**
 * Tests for the report's live entry point, searchArchivedRecords, and the read
 * paths behind it that ArchivedRecordsControllerTest does not reach: reading by
 * day from the rollup, parent search by partition and by scan, lookup Ids shown
 * as names, Time values as clock times, the Inventory Name wrapper, the
 * diagnostics, and the count job's failure handling.
 */
@IsTest
private class ArchivedRecordsSearchTest {

    private static final String OLI = 'Order_Line_Item__c';
    private static final String INVENTORY_ADJUSTMENT = 'Inventory_Adjustment__c';
    private static final String ATTENDANCE = 'Attendance__c';

    /**
     * Returns the same rows for every request, with a continuation on the first
     * pagesWithMore responses. Responds with no rows when the decoded endpoint
     * contains emptyWhen, so a filtered read can be made to find nothing.
     */
    private class RowsMock implements HttpCalloutMock {
        private final List<Map<String, Object>> rows;
        private final Integer pagesWithMore;
        private String emptyWhen;
        private Integer callCount = 0;
        private final List<String> endpoints = new List<String>();

        private RowsMock(List<Map<String, Object>> rows, Integer pagesWithMore) {
            this.rows = rows;
            this.pagesWithMore = pagesWithMore;
        }

        public HttpResponse respond(HttpRequest req) {
            callCount++;
            String endpoint = EncodingUtil.urlDecode(req.getEndpoint(), 'UTF-8');
            endpoints.add(endpoint);

            List<Map<String, Object>> body = rows;
            if (emptyWhen != null && endpoint.contains(emptyWhen)) {
                body = new List<Map<String, Object>>();
            }

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(JSON.serialize(new Map<String, Object>{ 'value' => body }));
            if (callCount <= pagesWithMore) {
                res.setHeader('x-ms-continuation-NextPartitionKey', 'PK-' + callCount);
                res.setHeader('x-ms-continuation-NextRowKey', 'RK-' + callCount);
            }
            return res;
        }

        private Boolean calledWith(String fragment) {
            for (String endpoint : endpoints) {
                if (endpoint.contains(fragment)) {
                    return true;
                }
            }
            return false;
        }
    }

    /**
     * The Inventory Adjustment archive as partitioned live: rows with an
     * Inventory under their Inventory Id, rows without one under NO_INVENTORY.
     * Answers each PartitionKey range the report asks for with the rows that sit
     * in it, and an unbounded read (the casing probe) with everything.
     */
    private class InventoryPartitionMock implements HttpCalloutMock {
        private final List<Map<String, Object>> withInventory;
        private final List<Map<String, Object>> withoutInventory;
        private final List<String> endpoints = new List<String>();

        private InventoryPartitionMock(
            List<Map<String, Object>> withInventory,
            List<Map<String, Object>> withoutInventory
        ) {
            this.withInventory = withInventory;
            this.withoutInventory = withoutInventory;
        }

        public HttpResponse respond(HttpRequest req) {
            String endpoint = EncodingUtil.urlDecode(req.getEndpoint(), 'UTF-8');
            endpoints.add(endpoint);

            List<Map<String, Object>> body = new List<Map<String, Object>>();
            if (endpoint.contains('PartitionKey ge \'NO_INVENTORY \'')) {
                body.addAll(withInventory);
            } else if (endpoint.contains('PartitionKey lt \'NO_INVENTORY\'')) {
                // Nothing sorts before NO_INVENTORY in this archive.
            } else if (endpoint.contains('PartitionKey ge \'NO_INVENTORY\'')) {
                body.addAll(withoutInventory);
            } else {
                body.addAll(withoutInventory);
                body.addAll(withInventory);
            }

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(JSON.serialize(new Map<String, Object>{ 'value' => body }));
            return res;
        }
    }

    /**
     * An Inventory Adjustment as archived and as the report receives it: lower
     * case, partitioned by Inventory, and - because the report selects some fields
     * in both casings - with the casing the archive lacks present as an explicit
     * null, exactly as Table Storage returns it (verified live 2026-10-05).
     */
    private static Map<String, Object> adjustmentRow(Integer i, String inventoryId, String archivedDay) {
        return new Map<String, Object>{
            'Inventory__c' => null,
            'Inventory_Name__c' => null,
            'inventory_name__c' => null,
            'Primary_Invoice_transaction__c' => null,
            'PartitionKey' => String.isBlank(inventoryId) ? 'NO_INVENTORY' : inventoryId,
            'RowKey' => 'a0PGB00001WK' + String.valueOf(i).leftPad(3, '0'),
            'id' => 'a0PGB00001WK' + String.valueOf(i).leftPad(3, '0'),
            'name' => 'Invadj - ' + i,
            'inventory__c' => inventoryId == null ? '' : inventoryId,
            'ownerid' => UserInfo.getUserId(),
            'quantity__c' => 5,
            'type__c' => 'Inward',
            'archived_date__c' => archivedDay + 'T09:52:33.415Z',
            'createddate' => '2026-01-01T00:00:00.000Z'
        };
    }

    private static String iso(Date value) {
        return String.valueOf(value);
    }

    private static String fakeId(Schema.SObjectType sobjType, Integer n) {
        return sobjType.getDescribe().getKeyPrefix() + String.valueOf(n).leftPad(12, '0');
    }

    /** An Order Line Item as the archive stores it - exact Salesforce casing. */
    private static Map<String, Object> oliRow(Integer i, String orderName, String archivedDay) {
        return new Map<String, Object>{
            'PartitionKey' => orderName,
            'RowKey' => 'a0TGB00003oq' + String.valueOf(i).leftPad(6, '0'),
            'Id' => 'a0TGB00003oq' + String.valueOf(i).leftPad(6, '0'),
            'Order_Name__c' => orderName,
            'Total_Amount__c' => 100 + i,
            'Archived_Date__c' => archivedDay + 'T10:00:0' + Math.mod(i, 10) + '.000Z',
            'CreatedDate' => '2025-04-01T11:35:05.000Z'
        };
    }

    private static Boolean rowsContainValue(ArchivedRecordsController.ReportPage page, Object value) {
        for (Map<String, Object> row : page.rows) {
            if (row.values().contains(value)) {
                return true;
            }
        }
        return false;
    }

    // ------------------------------------------------------------ search entry point

    @IsTest
    static void searchReadsOneObjectByArchivedDate() {
        String day = iso(Date.today().addDays(-3));
        RowsMock mock = new RowsMock(new List<Map<String, Object>>{
            oliRow(1, 'O-1001', day), oliRow(2, 'O-1002', day), oliRow(3, 'O-1003', day)
        }, 0);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ArchivedRecordsController.ReportPage page = ArchivedRecordsController.searchArchivedRecords(
            OLI, iso(Date.today().addDays(-10)), iso(Date.today()), 50, 1, null, null);
        Test.stopTest();

        System.assertEquals(3, page.rows.size(), 'Every archived row in range is shown');
        System.assertEquals(true, page.tokenPaged, 'One object pages by continuation token');
        System.assertEquals(false, page.hasMore, 'The mock offered no continuation');
        System.assertEquals('ARCHIVED', page.dateBasis, 'The report filters on archived date');
        System.assert(rowsContainValue(page, 'O-1002'), 'Order Name is a column');
    }

    @IsTest
    static void searchRequiresAnObject() {
        try {
            ArchivedRecordsController.searchArchivedRecords(' ', null, null, 50, 1, null, null);
            System.assert(false, 'A blank object must be rejected');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void searchPagesAcrossTheWholeRangeWithoutARollup() {
        String day = iso(Date.today().addDays(-2));
        RowsMock mock = new RowsMock(new List<Map<String, Object>>{
            oliRow(1, 'O-1001', day), oliRow(2, 'O-1002', day)
        }, 1);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ArchivedRecordsController.ReportPage first = ArchivedRecordsController.searchArchivedRecords(
            OLI, iso(Date.today().addDays(-5)), iso(Date.today()), 2, 1, null, null);
        ArchivedRecordsController.ReportPage second = ArchivedRecordsController.searchArchivedRecords(
            OLI, iso(Date.today().addDays(-5)), iso(Date.today()), 2, 2, first.nextContinuation, null);
        Test.stopTest();

        System.assertEquals(true, first.hasMore, 'A continuation means a next page');
        System.assertNotEquals(null, first.nextContinuation, 'The token is handed back');
        System.assert(mock.calledWith('PK-1'), 'Page two resumes from the token');
        System.assertEquals(false, second.hasMore, 'The archive had nothing further');
    }

    // ------------------------------------------------------------ read by day

    private static void publishRollupDay(Date day, Integer rowCount) {
        insert new Archive_Day_Count__c(
            Cache_Key__c           = OLI + '|ARCHIVED|' + String.valueOf(day),
            Object_API_Name__c     = OLI,
            Date_Basis__c          = 'ARCHIVED',
            Day__c                 = day,
            Row_Count__c           = rowCount,
            Counted_At__c          = Datetime.now(),
            First_Partition_Key__c = 'O-' + String.valueOf(day.day()),
            First_Row_Key__c       = 'RK-' + String.valueOf(day.day())
        );
    }

    @IsTest
    static void searchReadsDayByDayOnceTheRollupHasPublished() {
        Date counted = Date.today().addDays(-10);
        publishRollupDay(counted, 2);
        String day = iso(counted);
        RowsMock mock = new RowsMock(new List<Map<String, Object>>{
            oliRow(1, 'O-1001', day), oliRow(2, 'O-1002', day)
        }, 0);
        Test.setMock(HttpCalloutMock.class, mock);

        String fromDate = iso(Date.today().addDays(-12));
        String toDate = iso(Date.today());

        Test.startTest();
        // A page of two fills on the counted day, so the read stops there and
        // hands back a by-day continuation for the days still to visit.
        ArchivedRecordsController.ReportPage first = ArchivedRecordsController.searchArchivedRecords(
            OLI, fromDate, toDate, 2, 1, null, null);
        ArchivedRecordsController.ReportPage second = ArchivedRecordsController.searchArchivedRecords(
            OLI, fromDate, toDate, 50, 2, first.nextContinuation, null);
        Test.stopTest();

        System.assertEquals(2, first.rows.size(), 'The counted day fills the page');
        System.assertEquals(true, first.hasMore, 'Recent, uncounted days are still to read');
        System.assert(first.nextContinuation.contains('"day"'),
            'The continuation names the day to resume: ' + first.nextContinuation);
        System.assert(mock.calledWith('PartitionKey'),
            'The counted day starts from its recorded position');
        System.assertEquals(false, second.hasMore, 'Every planned day has been read');
    }

    @IsTest
    static void aRangeTheRollupProvesEmptyAnswersWithoutReading() {
        // Published, with nothing in the range asked about.
        publishRollupDay(Date.today().addDays(-60), 5);
        RowsMock mock = new RowsMock(new List<Map<String, Object>>(), 0);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ArchivedRecordsController.ReportPage page = ArchivedRecordsController.searchArchivedRecords(
            OLI, iso(Date.today().addDays(-40)), iso(Date.today().addDays(-30)), 50, 1, null, null);
        Test.stopTest();

        System.assert(page.rows.isEmpty(), 'Nothing was archived in that range');
        System.assertEquals(false, page.hasMore, 'A proven-empty range is complete');
        System.assertEquals(0, mock.callCount, 'No archive read is needed to say so');
    }

    // ------------------------------------------------------------ parent search

    @IsTest
    static void orderSearchSeeksStraightToThePartition() {
        String day = iso(Date.today().addDays(-3));
        RowsMock mock = new RowsMock(new List<Map<String, Object>>{
            oliRow(1, 'O-1001', day), oliRow(2, 'O-1001', day)
        }, 0);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ArchivedRecordsController.ReportPage page = ArchivedRecordsController.searchArchivedRecords(
            OLI, null, null, 50, 1, null, 'O-1001');
        Test.stopTest();

        System.assertEquals(2, page.rows.size(), 'Both lines of the Order are found');
        System.assert(mock.calledWith('PartitionKey ge \'O-1001\''),
            'The archive is partitioned by Order, so the read seeks: ' + mock.endpoints);
    }

    @IsTest
    static void orderSearchRetriesInUpperCase() {
        String day = iso(Date.today().addDays(-3));
        RowsMock mock = new RowsMock(new List<Map<String, Object>>{
            oliRow(1, 'O-1001', day)
        }, 0);
        // Keys are stored in upper case, so the term as typed finds nothing.
        mock.emptyWhen = 'ge \'o-1001\'';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ArchivedRecordsController.ReportPage page = ArchivedRecordsController.searchArchivedRecords(
            OLI, null, null, 50, 1, null, 'o-1001');
        Test.stopTest();

        System.assertEquals(1, page.rows.size(), 'The upper-case retry finds the Order');
        System.assert(mock.calledWith('ge \'O-1001\''), 'The retry is upper-cased');
    }

    @IsTest
    static void datedOrderSearchKeepsOnlyMatchingRows() {
        String day = iso(Date.today().addDays(-3));
        RowsMock mock = new RowsMock(new List<Map<String, Object>>{
            oliRow(1, 'O-1001', day), oliRow(2, 'O-2002', day), oliRow(3, 'O-1001', day)
        }, 0);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ArchivedRecordsController.ReportPage page = ArchivedRecordsController.searchArchivedRecords(
            OLI, iso(Date.today().addDays(-10)), iso(Date.today()), 50, 1, null, 'o-1001');
        Test.stopTest();

        System.assertEquals(2, page.rows.size(), 'Only the lines of the searched Order');
        System.assert(!rowsContainValue(page, 'O-2002'), 'Other Orders are filtered out');
    }

    @IsTest
    static void orderSearchByRecordIdMatchesTheLookup() {
        String orderId = fakeId(Order__c.SObjectType, 1);
        String day = iso(Date.today().addDays(-3));
        Map<String, Object> match = oliRow(1, 'O-1001', day);
        match.put('Order__c', orderId);
        Map<String, Object> other = oliRow(2, 'O-2002', day);
        other.put('Order__c', fakeId(Order__c.SObjectType, 2));
        Test.setMock(HttpCalloutMock.class, new RowsMock(
            new List<Map<String, Object>>{ match, other }, 0));

        Test.startTest();
        ArchivedRecordsController.ReportPage page = ArchivedRecordsController.searchArchivedRecords(
            OLI, iso(Date.today().addDays(-10)), iso(Date.today()), 50, 1, null, orderId);
        Test.stopTest();

        System.assertEquals(1, page.rows.size(), 'Only the line under that Order Id');
    }

    @IsTest
    static void parentSearchRejectsWhatItCannotSearch() {
        Integer rejected = 0;
        List<List<String>> cases = new List<List<String>>{
            // Inventory Adjustment has no parent search.
            new List<String>{ INVENTORY_ADJUSTMENT, 'IN-1' },
            new List<String>{ OLI, 'O' },
            new List<String>{ OLI, 'O'.repeat(256) }
        };
        for (List<String> c : cases) {
            try {
                ArchivedRecordsController.searchArchivedRecords(c[0], null, null, 50, 1, null, c[1]);
            } catch (AuraHandledException e) {
                rejected++;
            }
        }
        System.assertEquals(3, rejected, 'Unsupported object, too short and too long all refused');
    }

    @IsTest
    static void parentSearchWithoutARouteSaysSo() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.NotFoundMock());
        try {
            ArchivedRecordsController.searchArchivedRecords(
                OLI, iso(Date.today().addDays(-5)), iso(Date.today()), 50, 1, null, 'O-1001');
            System.assert(false, 'A search the log index cannot answer must not degrade');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    // ------------------------------------------------------------ display

    @IsTest
    static void inventoryAdjustmentsShowInventoryAndOwnerNames() {
        Inventory__c inventory = new Inventory__c();
        insert inventory;
        inventory = [SELECT Id, Name FROM Inventory__c WHERE Id = :inventory.Id];

        String day = iso(Date.today().addDays(-2));
        // Named through the controller's test seam rather than by inserting an
        // Invoice__c, so the test does not depend on Invoice triggers compiling.
        // That both invoice lookups use Invoice__c.Name is pinned separately, in
        // ArchivedRecordsControllerTest.bothInvoiceLookupsShowTheInvoiceNameField.
        Id invoiceId = Id.valueOf(fakeId(Invoice__c.SObjectType, 1));
        ArchivedRecordsController.invoiceNamesOverride = new Map<Id, String>{ invoiceId => 'GSR-SEARCH-001' };

        Map<String, Object> named = adjustmentRow(0, String.valueOf(inventory.Id), day);
        named.put('product__c', fakeId(Product__c.SObjectType, 0));
        named.put('primary_invoice_transaction__c', String.valueOf(invoiceId));
        Test.setMock(HttpCalloutMock.class, new InventoryPartitionMock(
            new List<Map<String, Object>>{ named },
            new List<Map<String, Object>>{ adjustmentRow(1, null, day) }));

        Test.startTest();
        ArchivedRecordsController.ReportPage page = ArchivedRecordsController.searchArchivedRecords(
            INVENTORY_ADJUSTMENT, iso(Date.today().addDays(-5)), iso(Date.today()), 50, 1, null, null);
        Test.stopTest();

        System.assertEquals(2, page.rows.size());
        System.assert(rowsContainValue(page, inventory.Name),
            'The archived Inventory Id is shown as the Inventory name: ' + page.rows);
        System.assert(rowsContainValue(page, UserInfo.getName()),
            'Owner Ids are shown as the user name');
        System.assert(rowsContainValue(page, 'GSR-SEARCH-001'),
            'The archived Primary Invoice Id is shown as the Invoice name: ' + page.rows);
        for (Map<String, Object> row : page.rows) {
            System.assert(!row.containsKey('_inventoryId'), 'The working Id is not sent to the UI');
            System.assert(!row.containsKey('_primaryInvoiceId'), 'Nor is the invoice one');
        }
    }

    @IsTest
    static void inventoryAdjustmentsWithAnInventoryAreShownFirst() {
        Inventory__c inventory = new Inventory__c();
        insert inventory;
        String inventoryId = String.valueOf(inventory.Id);
        String day = iso(Date.today().addDays(-2));

        InventoryPartitionMock mock = new InventoryPartitionMock(
            new List<Map<String, Object>>{
                adjustmentRow(1, inventoryId, day), adjustmentRow(2, inventoryId, day)
            },
            new List<Map<String, Object>>{
                adjustmentRow(3, null, day), adjustmentRow(4, null, day), adjustmentRow(5, null, day)
            });
        Test.setMock(HttpCalloutMock.class, mock);

        String fromDate = iso(Date.today().addDays(-5));
        String toDate = iso(Date.today());

        Test.startTest();
        ArchivedRecordsController.ReportPage first = ArchivedRecordsController.searchArchivedRecords(
            INVENTORY_ADJUSTMENT, fromDate, toDate, 2, 1, null, null);
        ArchivedRecordsController.ReportPage second = ArchivedRecordsController.searchArchivedRecords(
            INVENTORY_ADJUSTMENT, fromDate, toDate, 2, 2, first.nextContinuation, null);
        Test.stopTest();

        System.assertEquals(2, first.rows.size());
        for (Map<String, Object> row : first.rows) {
            System.assertNotEquals(null, row.get('Inventory_Name__c'),
                'Page one holds the rows with an Inventory: ' + first.rows);
        }
        System.assertEquals(true, first.hasMore, 'The rows without an Inventory are still to come');
        System.assert(first.nextContinuation.contains('"seg"'),
            'The token says which part of the archive comes next: ' + first.nextContinuation);

        System.assertEquals(3, second.rows.size(), 'Page two moves on to the rest');
        for (Map<String, Object> row : second.rows) {
            System.assertEquals(null, row.get('Inventory_Name__c'),
                'Rows without an Inventory come last');
        }
        System.assertEquals(false, second.hasMore, 'Every part of the archive has been read');
    }

    @IsTest
    static void anInventoryOnlyInAnotherOrgShowsItsId() {
        // As in the sandbox: the archive was written from another org, so the
        // Inventory it names does not exist here.
        String elsewhere = String.valueOf(Id.valueOf(fakeId(Inventory__c.SObjectType, 7)));
        String day = iso(Date.today().addDays(-2));
        Test.setMock(HttpCalloutMock.class, new InventoryPartitionMock(
            new List<Map<String, Object>>{ adjustmentRow(1, elsewhere, day) },
            new List<Map<String, Object>>()));

        Test.startTest();
        ArchivedRecordsController.ReportPage page = ArchivedRecordsController.searchArchivedRecords(
            INVENTORY_ADJUSTMENT, iso(Date.today().addDays(-5)), iso(Date.today()), 50, 1, null, null);
        Test.stopTest();

        System.assertEquals(1, page.rows.size());
        System.assertEquals(elsewhere, page.rows[0].get('Inventory_Name__c'),
            'The archived Inventory Id is read past the null projection and shown');
    }

    @IsTest
    static void attendanceTimesShowAsClockTimes() {
        String day = iso(Date.today().addDays(-2));
        Test.setMock(HttpCalloutMock.class, new RowsMock(new List<Map<String, Object>>{
            new Map<String, Object>{
                'Id' => 'a0AGB0000000001',
                'Name' => 'ATT-0001',
                'First_Activity_Time__c' => '13:05:00.000Z',
                'User__c' => UserInfo.getUserId(),
                'Archived_Date__c' => day + 'T09:00:00.000Z',
                'CreatedDate' => '2026-01-01T00:00:00.000Z'
            }
        }, 0));

        Test.startTest();
        ArchivedRecordsController.ReportPage page = ArchivedRecordsController.searchArchivedRecords(
            ATTENDANCE, iso(Date.today().addDays(-5)), iso(Date.today()), 50, 1, null, null);
        Test.stopTest();

        System.assertEquals(1, page.rows.size());
        System.assert(rowsContainValue(page, '1:05 PM'),
            'A Time field reads as a 12-hour clock time: ' + page.rows);
        System.assert(rowsContainValue(page, UserInfo.getName()), 'User Ids read as names');
    }

    @IsTest
    static void formatTime12hLeavesAnythingUnreadableAlone() {
        System.assertEquals('12:15 AM', ArchivedRecordsController.formatTime12h('00:15:00.000Z'));
        System.assertEquals('12:00 PM', ArchivedRecordsController.formatTime12h('12:00:00.000Z'));
        System.assertEquals('9:28 AM', ArchivedRecordsController.formatTime12h('09:28:04.000Z'));
        System.assertEquals(null, ArchivedRecordsController.formatTime12h(null));
        System.assertEquals('later', ArchivedRecordsController.formatTime12h('later'));
        System.assertEquals('25:61', ArchivedRecordsController.formatTime12h('25:61'));
    }

    // ------------------------------------------------------------ diagnostics

    @IsTest
    static void diagnoseDisplayReportsIdsThatCouldNotBeNamed() {
        String day = iso(Date.today().addDays(-2));
        Map<String, Object> row = oliRow(1, 'O-1001', day);
        // A Product that does not exist in this org stays an Id.
        row.put('Products__c', fakeId(Product__c.SObjectType, 9));
        Test.setMock(HttpCalloutMock.class, new RowsMock(new List<Map<String, Object>>{ row }, 0));

        Test.startTest();
        String report = ArchivedRecordsController.diagnoseDisplay(
            OLI, iso(Date.today().addDays(-5)), iso(Date.today()));
        Test.stopTest();

        System.assert(report.contains('Object: ' + OLI), report);
        System.assert(report.contains('Rows on page 1: 1'), report);
        System.assert(report.contains('STILL IDS'), 'The unnamed Product Id is called out: ' + report);
    }

    @IsTest
    static void sampleArchiveRowsReturnsTheRawRows() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.SuccessMock(3));

        Test.startTest();
        List<Map<String, Object>> rows = ArchivedRecordsController.sampleArchiveRows(OLI, 3);
        Test.stopTest();

        System.assertEquals(3, rows.size());
        System.assert(rows[0].containsKey('PartitionKey'), 'Rows are unprojected');
    }

    @IsTest
    static void sampleArchiveRowsRaisesAFailedRead() {
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.ServerErrorMock());
        try {
            ArchivedRecordsController.sampleArchiveRows(OLI, null);
            System.assert(false, 'A failed read must raise');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void readPathForFollowsConfiguration() {
        Azure_Archive_Config__mdt cfg = ArchivedRecordsController.configFor(OLI);
        String expected = (cfg != null && String.isNotBlank(cfg.Read_Path__c)) ? cfg.Read_Path__c : null;
        System.assertEquals(expected, ArchivedRecordsController.readPathFor(OLI));
    }

    // ------------------------------------------------------------ count

    private static Archive_Row_Count__c rollupState(String status, Datetime completedAt) {
        return new Archive_Row_Count__c(
            Cache_Key__c       = ArchivedRecordsController.countCacheKey(OLI, null, null, 'ARCHIVED'),
            Object_API_Name__c = OLI,
            Date_Basis__c      = 'ARCHIVED',
            Running_Total__c   = 50000,
            Callouts_Used__c   = 50,
            Chain_Depth__c     = 0,
            Status__c          = status,
            Started_At__c      = Datetime.now().addDays(-3),
            Completed_At__c    = completedAt
        );
    }

    @IsTest
    static void aFailedCountIsStartedAgain() {
        insert rollupState('Failed', Datetime.now().addHours(-1));
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.SuccessMock(3));

        ArchivedRecordsController.ArchiveCount counted = ArchivedRecordsController.getArchivedRecordCount(
            new List<String>{ OLI }, null, null, 'ARCHIVED', false);

        System.assertEquals(true, counted.isBuilding, 'A failed count is recounted');
        System.assertEquals(false, counted.isFailed, 'The old failure is not reported again');
    }

    @IsTest
    static void aStaleCountIsStartedAgain() {
        insert rollupState('Complete', Datetime.now().addDays(-2));
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.SuccessMock(3));

        ArchivedRecordsController.ArchiveCount counted = ArchivedRecordsController.getArchivedRecordCount(
            new List<String>{ OLI }, null, null, 'ARCHIVED', false);

        System.assertEquals(true, counted.isBuilding, 'A count older than a day is recounted');
    }

    @IsTest
    static void aCountWithNoCompletionTimeIsStartedAgain() {
        insert rollupState('Complete', null);
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.SuccessMock(3));

        ArchivedRecordsController.ArchiveCount counted = ArchivedRecordsController.getArchivedRecordCount(
            new List<String>{ OLI }, null, null, 'ARCHIVED', false);

        System.assertEquals(true, counted.isBuilding, 'A count with no finish time cannot be trusted');
    }

    @IsTest
    static void countRejectsAnInvertedRange() {
        try {
            ArchivedRecordsController.getArchivedRecordCount(
                new List<String>{ OLI }, '2026-09-30', '2026-09-01', null, false);
            System.assert(false, 'From after To must be refused');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    // ------------------------------------------------------------ count job

    @IsTest
    static void countJobIgnoresARecordThatNoLongerExists() {
        Archive_Row_Count__c state = rollupState('Running', null);
        insert state;
        Id goneId = state.Id;
        delete state;

        Test.startTest();
        System.enqueueJob(new ArchiveCountQueueable(goneId));
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Archive_Row_Count__c],
            'Nothing is recreated for a deleted count');
    }

    @IsTest
    static void countJobFailsVisiblyOnAnUnreadableTally() {
        Archive_Row_Count__c state = rollupState('Running', null);
        state.Partial_Tally__c = 'not json';
        insert state;
        Test.setMock(HttpCalloutMock.class, new ArchiveReadServiceMocks.SuccessMock(3));

        Test.startTest();
        System.enqueueJob(new ArchiveCountQueueable(state.Id));
        Test.stopTest();

        Archive_Row_Count__c after = [
            SELECT Status__c, Error_Message__c FROM Archive_Row_Count__c WHERE Id = :state.Id
        ];
        System.assertEquals('Failed', after.Status__c, 'A broken tally fails the count');
        System.assert(after.Error_Message__c.contains('Partial tally'),
            'The failure says why: ' + after.Error_Message__c);
    }

    @IsTest
    static void mergeTallyAddsToWhatWasCarried() {
        Map<String, Integer> merged = ArchiveCountQueueable.mergeTally(
            '{"2026-09-01":5}',
            new Map<String, Integer>{ '2026-09-01' => 2, '2026-09-02' => 1 });

        System.assertEquals(7, merged.get('2026-09-01'), 'Counts for the same day accumulate');
        System.assertEquals(1, merged.get('2026-09-02'), 'A new day is added');
    }
}