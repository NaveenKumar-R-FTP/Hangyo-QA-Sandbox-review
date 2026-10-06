@isTest
private class ArchiveOrderLineItemsBatchTest {

    @testSetup
    static void setupTestData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
    }

    private static Order__c createTestOrder() {
        Id disRecId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId();
        Account distributor = new Account(Name = 'Distributor', RecordTypeId = disRecId, PAN_Number__c = '1344', Primary_State__c = 'Karnataka');
        insert distributor;

        Id retailerRecId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId();
        Account retailer = new Account(Name = 'Retailer', Distributor__c = distributor.Id, RecordTypeId = retailerRecId, Primary_State__c = 'Karnataka', PAN_Number__c = '1344');
        insert retailer;

        RecordType secondaryOrderRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Secondary_Order' AND SObjectType = 'Order__c' LIMIT 1];
        Order__c ord = new Order__c(Account__c = retailer.Id, AccountId__c = distributor.Id, RecordTypeId = secondaryOrderRT.Id);
        insert ord;

        return ord;
    }

    private static List<Order_Line_Item__c> createBackdatedLineItems(Id orderId, Integer count, Integer daysAgo) {
        List<Order_Line_Item__c> items = new List<Order_Line_Item__c>();
        for (Integer i = 0; i < count; i++) {
            items.add(new Order_Line_Item__c(
                Order__c = orderId,
                Archived__c = false
            ));
        }
        insert items;

        DateTime backdated = DateTime.now().addDays(-daysAgo);
        for (Order_Line_Item__c item : items) {
            Test.setCreatedDate(item.Id, backdated);
        }

        return items;
    }

    private static Set<String> extractIdStrings(List<Order_Line_Item__c> items) {
        Set<String> idStrings = new Set<String>();
        for (Order_Line_Item__c item : items) {
            idStrings.add(item.Id);
        }
        return idStrings;
    }

    private static Set<Id> extractIds(List<Order_Line_Item__c> items) {
        Set<Id> ids = new Set<Id>();
        for (Order_Line_Item__c item : items) {
            ids.add(item.Id);
        }
        return ids;
    }

    @isTest
    static void testBatch_archivesEligibleRecords_success() {
        Order__c ord = createTestOrder();
        List<Order_Line_Item__c> items = createBackdatedLineItems(ord.Id, 3, 100);

        List<String> archivedIdStrings = new List<String>();
        for (Order_Line_Item__c item : items) {
            archivedIdStrings.add(item.Id);
        }

        Test.setMock(HttpCalloutMock.class, new ArchiveConnectorServiceMocks.SuccessMock(archivedIdStrings));

        Test.startTest();
        ArchiveOrderLineItemsBatch batch = new ArchiveOrderLineItemsBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        Set<Id> itemIds = extractIds(items);

        List<Order_Line_Item__c> updatedItems = [
            SELECT Id, Archived__c, Archived_Date__c
            FROM Order_Line_Item__c
            WHERE Id IN :itemIds
        ];
        for (Order_Line_Item__c item : updatedItems) {
            System.assertEquals(true, item.Archived__c, 'Line item should be marked archived');
            System.assertNotEquals(null, item.Archived_Date__c, 'Archived date should be populated');
        }

        List<Archival_Job_Log__c> jobLogs = [
            SELECT Id, Total_Archived__c, Total_Processed__c, Total_Failed__c
            FROM Archival_Job_Log__c
        ];
        System.assertEquals(1, jobLogs.size(), 'A job log should be created on finish');
        System.assertEquals(3, jobLogs[0].Total_Archived__c);
        System.assertEquals(3, jobLogs[0].Total_Processed__c);
        System.assertEquals(0, jobLogs[0].Total_Failed__c);
    }

    @isTest
    static void testBatch_noEligibleRecords_completesWithoutError() {
        Order__c ord = createTestOrder();
        List<Order_Line_Item__c> items = new List<Order_Line_Item__c>{
            new Order_Line_Item__c(Order__c = ord.Id, Archived__c = false)
        };
        insert items;

        Test.startTest();
        ArchiveOrderLineItemsBatch batch = new ArchiveOrderLineItemsBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        Order_Line_Item__c unchanged = [
            SELECT Id, Archived__c FROM Order_Line_Item__c WHERE Id = :items[0].Id
        ];
        System.assertEquals(false, unchanged.Archived__c,
            'Recently created records should not be archived since they are not past retention cutoff');
    }

    @isTest
    static void testBatch_partialArchiveSuccess_onlyArchivedIdsUpdated() {
        Order__c ord = createTestOrder();
        List<Order_Line_Item__c> items = createBackdatedLineItems(ord.Id, 3, 100);

        List<String> partialArchivedIds = new List<String>{ items[0].Id };

        Test.setMock(HttpCalloutMock.class, new ArchiveConnectorServiceMocks.SuccessMock(partialArchivedIds));

        Test.startTest();
        Database.executeBatch(new ArchiveOrderLineItemsBatch(), 200);
        Test.stopTest();

        Set<Id> itemIds = extractIds(items);

        List<Order_Line_Item__c> refreshed = [
            SELECT Id, Archived__c FROM Order_Line_Item__c WHERE Id IN :itemIds ORDER BY Id
        ];

        Integer archivedCount = 0;
        for (Order_Line_Item__c item : refreshed) {
            if (item.Archived__c) {
                archivedCount++;
            }
        }
        System.assertEquals(1, archivedCount,
            'Only the item confirmed archived by the external service should be marked Archived__c');
    }

    @isTest
    static void testBatch_serviceFailure_noRecordsUpdated() {
        Order__c ord = createTestOrder();
        List<Order_Line_Item__c> items = createBackdatedLineItems(ord.Id, 2, 100);

        Test.setMock(HttpCalloutMock.class, new ArchiveConnectorServiceMocks.LogicalFailureMock());

        Test.startTest();
        Database.executeBatch(new ArchiveOrderLineItemsBatch(), 200);
        Test.stopTest();

        Set<Id> itemIds = extractIds(items);

        List<Order_Line_Item__c> refreshed = [
            SELECT Id, Archived__c FROM Order_Line_Item__c WHERE Id IN :itemIds
        ];
        for (Order_Line_Item__c item : refreshed) {
            System.assertEquals(false, item.Archived__c,
                'Records should remain unarchived when the external service reports failure');
        }

        List<Archival_Job_Log__c> jobLogs = [
            SELECT Id, Error_Message__c, Total_Failed__c FROM Archival_Job_Log__c
        ];
        System.assertEquals(1, jobLogs.size());
        System.assertNotEquals(null, jobLogs[0].Error_Message__c,
            'Error message should be populated when the service reports failure');
        System.assertEquals(2, jobLogs[0].Total_Failed__c);
    }

    @isTest
    static void testBatch_calloutException_handledGracefully() {
        Order__c ord = createTestOrder();
        createBackdatedLineItems(ord.Id, 2, 100);

        Test.setMock(HttpCalloutMock.class, new ArchiveConnectorServiceMocks.ExceptionMock());

        Test.startTest();
        Database.executeBatch(new ArchiveOrderLineItemsBatch(), 200);
        Test.stopTest();

        List<Order_Line_Item__c> refreshed = [SELECT Id, Archived__c FROM Order_Line_Item__c];
        for (Order_Line_Item__c item : refreshed) {
            System.assertEquals(false, item.Archived__c,
                'Records should remain unarchived when the callout throws an exception');
        }
    }

    /*@isTest
    static void testBatch_finishMethod_doesNotThrow() {
        ArchiveOrderLineItemsBatch batch = new ArchiveOrderLineItemsBatch();
        Test.startTest();
        batch.finish(null);
        Test.stopTest();

        List<Archival_Job_Log__c> jobLogs = [SELECT Id FROM Archival_Job_Log__c];
        System.assertEquals(1, jobLogs.size(), 'finish() should insert a job log even with zero counts');
    }*/

    @isTest
    static void testBatch_multipleOrders_groupedCorrectly() {
        Order__c ord1 = createTestOrder();
        Order__c ord2 = createTestOrder();

        List<Order_Line_Item__c> items1 = createBackdatedLineItems(ord1.Id, 2, 100);
        List<Order_Line_Item__c> items2 = createBackdatedLineItems(ord2.Id, 2, 100);

        List<String> allArchivedIds = new List<String>();
        for (Order_Line_Item__c item : items1) {
            allArchivedIds.add(item.Id);
        }
        for (Order_Line_Item__c item : items2) {
            allArchivedIds.add(item.Id);
        }

        Test.setMock(HttpCalloutMock.class, new ArchiveConnectorServiceMocks.SuccessMock(allArchivedIds));

        Test.startTest();
        Database.executeBatch(new ArchiveOrderLineItemsBatch(), 200);
        Test.stopTest();

        Set<Id> allIds = new Set<Id>();
        allIds.addAll(extractIds(items1));
        allIds.addAll(extractIds(items2));

        List<Order_Line_Item__c> refreshed = [
            SELECT Id, Archived__c FROM Order_Line_Item__c WHERE Id IN :allIds
        ];
        for (Order_Line_Item__c item : refreshed) {
            System.assertEquals(true, item.Archived__c);
        }
    }

    @isTest
    static void testBatch_start_returnsQueryLocator() {
        // Directly exercises start() to ensure the dynamic SOQL / metadata
        // config path executes without error outside of executeBatch context.
        ArchiveOrderLineItemsBatch batch = new ArchiveOrderLineItemsBatch();
        Test.startTest();
        Database.QueryLocator ql = batch.start(null);
        Test.stopTest();
        System.assertNotEquals(null, ql, 'start() should return a valid query locator');
    }
}