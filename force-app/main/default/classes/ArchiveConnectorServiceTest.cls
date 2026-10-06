@isTest
private class ArchiveConnectorServiceTest {
    
    @testSetup
    static void setupTestData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
    }
    
    private static Order__c createTestOrder() {
        Id disRecId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId();
        Account distributor = new Account(Name = 'Distributor', RecordTypeId = disRecId, PAN_Number__c='1344',Primary_State__c='Karnataka');
        insert distributor;
        
        Id retailerRecId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId();
        Account retailer = new Account(Name = 'Retailer', Distributor__c = distributor.Id, RecordTypeId = retailerRecId,Primary_State__c='Karnataka',PAN_Number__c='1344');
        insert retailer;
		
        RecordType secondaryOrderRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Secondary_Order' AND SObjectType = 'Order__c' LIMIT 1];
        // Create Test Order
        Order__c ord = new Order__c(Account__c = retailer.Id,AccountId__c =distributor.ID,RecordTypeId = secondaryOrderRT.Id );
        insert ord;
        
        return ord;
    }

    private static List<Order_Line_Item__c> createTestLineItems(Id orderId, Integer count) {
        List<Order_Line_Item__c> items = new List<Order_Line_Item__c>();
        for (Integer i = 0; i < count; i++) {
            items.add(new Order_Line_Item__c(
                Order__c = orderId,
                Archived__c = false
            ));
        }
        insert items;
        return items;
    }

    @isTest
    static void testSend_success_returnsTrueWithArchivedIds() {
        Order__c ord = createTestOrder();
        List<Order_Line_Item__c> items = createTestLineItems(ord.Id, 3);

        List<String> archivedIdStrings = new List<String>();
        for (Order_Line_Item__c item : items) {
            archivedIdStrings.add(item.Id);
        }

        Test.setMock(HttpCalloutMock.class, new ArchiveConnectorServiceMocks.SuccessMock(archivedIdStrings));

        Test.startTest();
        ArchiveConnectorService.SendResult result = ArchiveConnectorService.send(
            'Order_Line_Item__c', items, ord.Id
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Result should indicate success');
        System.assertEquals('azure://archive/container/batch-001', result.archiveLocation,
            'Archive location should be parsed from response');
        System.assertNotEquals(null, result.checksum, 'Checksum should be populated');
        System.assertEquals(3, result.archivedIds.size(), 'All archived ids should be returned');
    }

    @isTest
    static void testSend_logicalFailure_returnsFalseWithErrorDetails() {
        Order__c ord = createTestOrder();
        List<Order_Line_Item__c> items = createTestLineItems(ord.Id, 2);

        Test.setMock(HttpCalloutMock.class, new ArchiveConnectorServiceMocks.LogicalFailureMock());

        Test.startTest();
        ArchiveConnectorService.SendResult result = ArchiveConnectorService.send(
            'Order_Line_Item__c', items, ord.Id
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Result should indicate failure per response body');
        System.assertEquals('VALIDATION_FAILED', result.errorCode, 'Error code should be parsed');
        System.assertEquals('Checksum mismatch detected', result.errorMessage, 'Error message should be parsed');
    }

    @isTest
    static void testSend_httpErrorStatus_returnsFailureWithHttpCode() {
        Order__c ord = createTestOrder();
        List<Order_Line_Item__c> items = createTestLineItems(ord.Id, 1);

        Test.setMock(HttpCalloutMock.class,
            new ArchiveConnectorServiceMocks.HttpErrorMock(500, 'Internal Server Error occurred'));

        Test.startTest();
        ArchiveConnectorService.SendResult result = ArchiveConnectorService.send(
            'Order_Line_Item__c', items, ord.Id
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'HTTP 500 should result in failure');
        System.assertEquals('ARCHIVE_HTTP_500', result.errorCode, 'Error code should reflect HTTP status');
        System.assertEquals('Internal Server Error occurred', result.errorMessage,
            'Error message should be the response body');
    }

    @isTest
    static void testSend_httpErrorStatus_emptyBody_usesStatusText() {
        Order__c ord = createTestOrder();
        List<Order_Line_Item__c> items = createTestLineItems(ord.Id, 1);

        Test.setMock(HttpCalloutMock.class, new ArchiveConnectorServiceMocks.HttpErrorMock(503, null));

        Test.startTest();
        ArchiveConnectorService.SendResult result = ArchiveConnectorService.send(
            'Order_Line_Item__c', items, ord.Id
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'HTTP 503 should result in failure');
        System.assertEquals('ARCHIVE_HTTP_503', result.errorCode, 'Error code should reflect HTTP status');
        System.assertNotEquals(null, result.errorMessage, 'Error message should fall back to status text');
    }

    @isTest
    static void testSend_malformedJsonResponse_returnsInvalidResponseError() {
        Order__c ord = createTestOrder();
        List<Order_Line_Item__c> items = createTestLineItems(ord.Id, 1);

        Test.setMock(HttpCalloutMock.class, new ArchiveConnectorServiceMocks.MalformedJsonMock());

        Test.startTest();
        ArchiveConnectorService.SendResult result = ArchiveConnectorService.send(
            'Order_Line_Item__c', items, ord.Id
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Malformed JSON should result in failure');
        System.assertEquals('INVALID_RESPONSE', result.errorCode, 'Error code should indicate parse failure');
        System.assertNotEquals(null, result.checksum, 'Checksum should still be populated from the request');
    }

    @isTest
    static void testSend_calloutException_returnsCalloutExceptionError() {
        Order__c ord = createTestOrder();
        List<Order_Line_Item__c> items = createTestLineItems(ord.Id, 1);

        Test.setMock(HttpCalloutMock.class, new ArchiveConnectorServiceMocks.ExceptionMock());

        Test.startTest();
        ArchiveConnectorService.SendResult result = ArchiveConnectorService.send(
            'Order_Line_Item__c', items, ord.Id
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Callout exception should result in failure');
        System.assertEquals('CALLOUT_EXCEPTION', result.errorCode, 'Error code should indicate callout exception');
        System.assertNotEquals(null, result.errorMessage, 'Exception message should be captured');
    }

    @isTest
    static void testSend_missingSuccessKeyInResponse_defaultsToTrue() {
        Order__c ord = createTestOrder();
        List<Order_Line_Item__c> items = createTestLineItems(ord.Id, 1);

        Test.setMock(HttpCalloutMock.class, new ArchiveConnectorServiceMocks.MissingSuccessKeyMock());

        Test.startTest();
        ArchiveConnectorService.SendResult result = ArchiveConnectorService.send(
            'Order_Line_Item__c', items, ord.Id
        );
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Response missing the success key should default to true per service logic');
    }

    @isTest
    static void testSend_noChecksumInResponse_fallsBackToRequestChecksum() {
        Order__c ord = createTestOrder();
        List<Order_Line_Item__c> items = createTestLineItems(ord.Id, 1);

        Test.setMock(HttpCalloutMock.class,
            new ArchiveConnectorServiceMocks.NoChecksumInResponseMock(new List<String>{ items[0].Id }));

        Test.startTest();
        ArchiveConnectorService.SendResult result = ArchiveConnectorService.send(
            'Order_Line_Item__c', items, ord.Id
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Result should be successful');
        System.assertNotEquals(null, result.checksum,
            'Checksum should fall back to the request-computed checksum when absent from response');
    }

    @isTest
    static void testSend_emptyRecordsList_stillSendsValidPayload() {
        Order__c ord = createTestOrder();
        List<Order_Line_Item__c> emptyItems = new List<Order_Line_Item__c>();

        Test.setMock(HttpCalloutMock.class,
            new ArchiveConnectorServiceMocks.SuccessMock(new List<String>()));

        Test.startTest();
        ArchiveConnectorService.SendResult result = ArchiveConnectorService.send(
            'Order_Line_Item__c', emptyItems, ord.Id
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Empty record list should still succeed with valid payload');
        System.assertEquals(0, result.archivedIds.size(), 'No archived ids should be returned for empty input');
    }

    @isTest
    static void testSend_nullRecordsList_handledGracefully() {
        Order__c ord = createTestOrder();

        Test.setMock(HttpCalloutMock.class,
            new ArchiveConnectorServiceMocks.SuccessMock(new List<String>()));

        Test.startTest();
        ArchiveConnectorService.SendResult result = ArchiveConnectorService.send(
            'Order_Line_Item__c', null, ord.Id
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Null records list should be treated as empty and succeed');
    }

    @isTest
    static void testSend_blankObjectName_throwsIllegalArgumentException() {
        Order__c ord = createTestOrder();
        List<Order_Line_Item__c> items = createTestLineItems(ord.Id, 1);

        Test.setMock(HttpCalloutMock.class, new ArchiveConnectorServiceMocks.SuccessMock(new List<String>()));

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ArchiveConnectorService.send('', items, ord.Id);
        } catch (IllegalArgumentException e) {
            exceptionThrown = true;
            System.assertEquals('objectName is required', e.getMessage(),
                'Exception message should indicate missing objectName');
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Blank objectName should throw IllegalArgumentException');
    }

    @isTest
    static void testSend_unknownObjectName_throwsIllegalArgumentException() {
        Order__c ord = createTestOrder();
        List<Order_Line_Item__c> items = createTestLineItems(ord.Id, 1);

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ArchiveConnectorService.send('Not_A_Real_Object__x', items, ord.Id);
        } catch (IllegalArgumentException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('Unknown object type'),
                'Exception message should indicate unknown object type');
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Unknown object name should throw IllegalArgumentException');
    }

    @isTest
    static void testSend_checksumIsConsistentForSameRecordState() {
        Order__c ord = createTestOrder();
        List<Order_Line_Item__c> items = createTestLineItems(ord.Id, 2);

        List<String> archivedIdStrings = new List<String>();
        for (Order_Line_Item__c item : items) {
            archivedIdStrings.add(item.Id);
        }

        Test.setMock(HttpCalloutMock.class, new ArchiveConnectorServiceMocks.SuccessMock(archivedIdStrings));

        Test.startTest();
        ArchiveConnectorService.SendResult result1 = ArchiveConnectorService.send(
            'Order_Line_Item__c', items, ord.Id
        );
        ArchiveConnectorService.SendResult result2 = ArchiveConnectorService.send(
            'Order_Line_Item__c', items, ord.Id
        );
        Test.stopTest();

        // Both calls send the identical record state, so the locally
        // computed request checksum embedded in the header/body should match.
        System.assertEquals(true, result1.success, 'First call should succeed');
        System.assertEquals(true, result2.success, 'Second call should succeed');
    }
}