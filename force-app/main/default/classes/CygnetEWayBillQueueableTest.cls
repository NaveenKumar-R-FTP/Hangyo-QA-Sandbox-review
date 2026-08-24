@IsTest
private class CygnetEWayBillQueueableTest {
    /** E-Way Bill save succeeds; status poll returns PE (failure branch on queueable). */
    private class EwbSaveOkStatusPeMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            if (ep.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (ep.contains('/document/ewaybillByIrnCompliant/save')) {
                res.setStatusCode(202);
                res.setBody('{"referenceId":"ref-mock-ewb-pe"}');
                return res;
            }
            if (ep.contains('/reference/status')) {
                res.setStatusCode(200);
                res.setBody('{"status":"PE","message":"E-Way Bill poll PE (test)"}');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** Save endpoint fails (exercises outer catch(Exception) in queueable). */
    private class EwbSaveHttp500Mock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            if (ep.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890","expiryTimeInMinutes":360}');
                return res;
            }
            if (ep.contains('/document/ewaybillByIrnCompliant/save')) {
                res.setStatusCode(500);
                res.setBody('save fail');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** Save succeeds; status returns ER with no message (covers error branch + fallback). */
    private class EwbSaveOkStatusErNoMessageMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            if (ep.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890","expiryTimeInMinutes":360}');
                return res;
            }
            if (ep.contains('/document/ewaybillByIrnCompliant/save')) {
                res.setStatusCode(202);
                res.setBody('{"referenceId":"ref-mock-ewb-er"}');
                return res;
            }
            if (ep.contains('/reference/status')) {
                res.setStatusCode(200);
                res.setBody('{"status":"ER"}');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    @TestSetup
    static void setupData() {
        CygnetIntegrationTestDataFactory.insertCygnetHierarchySettings();
    }

    @IsTest
    static void testQueueable_ProcessesEWayBillWithMockHttp() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId, 'Requires Invoice__c + Product__c + Invoice_Line_Item__c');

        CygnetIntegrationTestData.makeInvoiceEwayBillReady(invId);

        Test.setMock(HttpCalloutMock.class, new CygnetIntegrationHttpCalloutMock());
        Test.startTest();
        System.enqueueJob(new CygnetEWayBillQueueable(invId));
        Test.stopTest();

        Invoice__c inv = [SELECT EWB__c FROM Invoice__c WHERE Id = :invId];
        System.assert(inv.EWB__c != null, 'Expected EWB number or successful path');
    }

    @IsTest
    static void testQueueable_SetsIntegrationError_WhenPollReturnsPe() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId, 'Requires Invoice__c + Product__c + Invoice_Line_Item__c');

        CygnetIntegrationTestData.makeInvoiceEwayBillReady(invId);

        Test.setMock(HttpCalloutMock.class, new EwbSaveOkStatusPeMock());
        Test.startTest();
        System.enqueueJob(new CygnetEWayBillQueueable(invId));
        Test.stopTest();

        System.assert(
            CygnetIntegrationLogTestHelper.countLogsForInvoice(invId) > 0,
            'Expected Integration_Log__c when status is PE'
        );
    }

    @IsTest
    static void testQueueable_CatchesMapperException_WhenIrnMissing() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        // Ensure IRN is blank so mapper throws before any callouts.
        SObject invUpd = new Invoice__c(Id = invId);
        invUpd.put('IRN_Number__c', null);
        update invUpd;

        Test.startTest();
        System.enqueueJob(new CygnetEWayBillQueueable(invId));
        Test.stopTest();

        System.assert(
            CygnetIntegrationLogTestHelper.countLogsForInvoice(invId) > 0,
            'Expected Integration_Log__c from mapper exception'
        );
    }

    @IsTest
    static void testQueueable_ClearsReferenceId_OnSuccess() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);
        CygnetIntegrationTestData.makeInvoiceEwayBillReady(invId);

        update new Invoice__c(Id = invId, Cygnet_Reference_Id__c = 'ref-to-clear');

        Test.setMock(HttpCalloutMock.class, new CygnetIntegrationHttpCalloutMock());
        Test.startTest();
        System.enqueueJob(new CygnetEWayBillQueueable(invId));
        Test.stopTest();

        Invoice__c inv = [
            SELECT Cygnet_Reference_Id__c
            FROM Invoice__c
            WHERE Id = :invId
        ];
        System.assertEquals(null, inv.Cygnet_Reference_Id__c, 'Expected reference id cleared on success');
    }

    @IsTest
    static void testQueueable_LogsAndClearsReference_WhenSaveThrows() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);
        CygnetIntegrationTestData.makeInvoiceEwayBillReady(invId);

        update new Invoice__c(Id = invId, Cygnet_Reference_Id__c = 'ref-to-clear');

        Test.setMock(HttpCalloutMock.class, new EwbSaveHttp500Mock());
        Test.startTest();
        System.enqueueJob(new CygnetEWayBillQueueable(invId));
        Test.stopTest();

        System.assert(
            CygnetIntegrationLogTestHelper.countLogsForInvoice(invId) > 0,
            'Expected Integration_Log__c on exception'
        );
        Invoice__c inv = [SELECT Cygnet_Reference_Id__c FROM Invoice__c WHERE Id = :invId];
        System.assertEquals(null, inv.Cygnet_Reference_Id__c, 'Reference should be cleared on fatal exception');
    }

    @IsTest
    static void testQueueable_SetsIntegrationError_WhenStatusIsEr_NoMessage() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);
        CygnetIntegrationTestData.makeInvoiceEwayBillReady(invId);

        Test.setMock(HttpCalloutMock.class, new EwbSaveOkStatusErNoMessageMock());
        Test.startTest();
        System.enqueueJob(new CygnetEWayBillQueueable(invId));
        Test.stopTest();

        System.assert(
            CygnetIntegrationLogTestHelper.countLogsForInvoice(invId) > 0,
            'Expected Integration_Log__c when status is ER'
        );
        Invoice__c inv = [SELECT Cygnet_Reference_Id__c FROM Invoice__c WHERE Id = :invId];
        System.assertEquals('ref-mock-ewb-er', inv.Cygnet_Reference_Id__c, 'Expected reference id retained on non-success');
    }
}