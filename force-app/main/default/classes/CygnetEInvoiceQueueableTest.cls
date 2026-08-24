@IsTest
private class CygnetEInvoiceQueueableTest {
    /** Async save returns reference only; poll returns PE so queueable writes Integration_Log__c. */
    private class EinSaveRefThenPeMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            if (ep.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (ep.contains('/document/einvoiceCompliant/save')) {
                res.setStatusCode(202);
                res.setBody('{"referenceId":"' + CygnetIntegrationHttpCalloutMock.MOCK_REFERENCE_ID + '"}');
                return res;
            }
            if (ep.contains('/reference/status')) {
                res.setStatusCode(200);
                res.setBody('{"status":"PE","message":"E-Invoice poll PE (test)"}');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** Save endpoint fails (exercises outer catch(Exception) in queueable). */
    private class EinSaveHttp500Mock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            if (ep.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (ep.contains('/document/einvoiceCompliant/save')) {
                res.setStatusCode(500);
                res.setBody('save fail');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** Save returns referenceId, but status payload is malformed (exercises queueable catch(Exception)). */
    private class EinStatusMalformedJsonMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            if (ep.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (ep.contains('/document/einvoiceCompliant/save')) {
                res.setStatusCode(202);
                res.setBody('{"referenceId":"' + CygnetIntegrationHttpCalloutMock.MOCK_REFERENCE_ID + '"}');
                return res;
            }
            if (ep.contains('/reference/status')) {
                res.setStatusCode(200);
                res.setBody('{ this-is-not-json ');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** Happy path: save returns referenceId; status returns P with IRN so queueable clears referenceId. */
    private class EinSaveRefThenOkMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            if (ep.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890","expiryTimeInMinutes":360}');
                return res;
            }
            if (ep.contains('/document/einvoiceCompliant/save')) {
                res.setStatusCode(202);
                res.setBody('{"referenceId":"' + CygnetIntegrationHttpCalloutMock.MOCK_REFERENCE_ID + '"}');
                return res;
            }
            if (ep.contains('/reference/status')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"status":"P","dataReport":[{"eInv":{"irn":"'
                    + CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX
                    + '"}}]}'
                );
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
    static void testQueueable_ProcessesEInvoiceWithMockHttp() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId, 'Requires Invoice__c + Product__c + Invoice_Line_Item__c');

        Test.setMock(HttpCalloutMock.class, new CygnetIntegrationHttpCalloutMock());
        Test.startTest();
        System.enqueueJob(new CygnetEInvoiceQueueable(invId));
        Test.stopTest();

        Invoice__c inv = [
            SELECT IRN_Number__c, Cygnet_Reference_Id__c
            FROM Invoice__c
            WHERE Id = :invId
        ];
        System.assertEquals(
            true,
            String.isNotBlank(String.valueOf(inv.IRN_Number__c)),
            'Expected IRN on invoice'
        );
    }

    @IsTest
    static void testQueueable_ClearsReferenceId_OnSuccess() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId, 'Requires Invoice__c + Product__c + Invoice_Line_Item__c');

        update new Invoice__c(Id = invId, Cygnet_Reference_Id__c = 'ref-to-clear');

        Test.setMock(HttpCalloutMock.class, new EinSaveRefThenOkMock());
        Test.startTest();
        System.enqueueJob(new CygnetEInvoiceQueueable(invId));
        Test.stopTest();

        Invoice__c inv = [SELECT Cygnet_Reference_Id__c, IRN_Number__c FROM Invoice__c WHERE Id = :invId];
        System.assertEquals(null, inv.Cygnet_Reference_Id__c, 'Expected reference id cleared on success');
        System.assertEquals(true, String.isNotBlank(String.valueOf(inv.IRN_Number__c)), 'Expected IRN set on success');
    }

    @IsTest
    static void testQueueable_SetsIntegrationError_WhenPollReturnsPe() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId, 'Requires Invoice__c + Product__c + Invoice_Line_Item__c');

        Test.setMock(HttpCalloutMock.class, new EinSaveRefThenPeMock());
        Test.startTest();
        System.enqueueJob(new CygnetEInvoiceQueueable(invId));
        Test.stopTest();

        System.assert(
            CygnetIntegrationLogTestHelper.countLogsForInvoice(invId) > 0,
            'Expected Integration_Log__c when status is PE'
        );
    }

    @IsTest
    static void testQueueable_SetsIntegrationError_WhenSaveThrows() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId, 'Requires Invoice__c + Product__c + Invoice_Line_Item__c');

        Test.setMock(HttpCalloutMock.class, new EinSaveHttp500Mock());
        Test.startTest();
        System.enqueueJob(new CygnetEInvoiceQueueable(invId));
        Test.stopTest();

        Invoice__c inv = [SELECT Cygnet_Reference_Id__c FROM Invoice__c WHERE Id = :invId];
        System.assert(
            CygnetIntegrationLogTestHelper.countLogsForInvoice(invId) > 0,
            'Expected Integration_Log__c on exception'
        );
        System.assertEquals(null, inv.Cygnet_Reference_Id__c, 'Reference should be cleared on fatal exception');
    }

    @IsTest
    static void testQueueable_SetsIntegrationError_WhenStatusIsMalformed() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId, 'Requires Invoice__c + Product__c + Invoice_Line_Item__c');

        Test.setMock(HttpCalloutMock.class, new EinStatusMalformedJsonMock());
        Test.startTest();
        System.enqueueJob(new CygnetEInvoiceQueueable(invId));
        Test.stopTest();

        System.assert(
            CygnetIntegrationLogTestHelper.countLogsForInvoice(invId) > 0,
            'Expected Integration_Log__c on malformed status payload'
        );
    }

    @IsTest
    static void testQueueable_CatchesMapperException_WhenNoLineItems() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        // Delete line items so mapper/path validation fails before callouts.
        List<Invoice_Line_Item__c> lines = [
            SELECT Id
            FROM Invoice_Line_Item__c
            WHERE Invoice__c = :invId
        ];
        if (!lines.isEmpty()) {
            delete lines;
        }

        Test.startTest();
        System.enqueueJob(new CygnetEInvoiceQueueable(invId));
        Test.stopTest();

        System.assert(
            CygnetIntegrationLogTestHelper.countLogsForInvoice(invId) > 0,
            'Expected Integration_Log__c from mapper exception'
        );
    }
}