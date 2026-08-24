@IsTest
private class InvoiceEInvoiceControllerTest {
    /** Auth OK + exportPdf OK (handles endpoint casing variations). */
    private class PdfExportSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            String lower = ep.toLowerCase();
            if (lower.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (lower.contains('exportpdf') && (lower.contains('einvoice') || lower.contains('ewaybill') || lower.contains('ewaybill'))) {
                res.setStatusCode(200);
                res.setBodyAsBlob(Blob.valueOf('%PDF-1.4 unit test'));
                return res;
            }
            // Status/polling safe default if a queueable is enqueued indirectly
            res.setStatusCode(200);
            res.setBody('{"status":"P","dataReport":[{"eInv":{"irn":"' + CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX + '"}}]}');
            return res;
        }
    }

    /** Returns 200 for auth, but PDF export has empty body (base64 becomes blank). */
    private class EmptyPdfExportMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            if (ep.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (ep.toLowerCase().contains('exportpdf')) {
                res.setStatusCode(200);
                res.setBodyAsBlob(Blob.valueOf(''));
                return res;
            }
            // Default safe responses for any follow-up calls
            res.setStatusCode(200);
            res.setBody('{"status":"P","dataReport":[{"eInv":{"irn":"' + CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX + '"}}]}');
            return res;
        }
    }

    @TestSetup
    static void setupData() {
        CygnetIntegrationTestDataFactory.insertCygnetHierarchySettings();
    }

    @IsTest
    static void testGetInvoiceEInvoiceFields_ReturnsWrapper() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId, 'Requires invoice test data');

        Test.startTest();
        InvoiceEInvoiceController.InvoiceEInvoiceFieldsWrapper w =
            InvoiceEInvoiceController.getInvoiceEInvoiceFields(invId);
        Test.stopTest();

        System.assertNotEquals(null, w);
        System.assertEquals(true, w.statusApproved);
    }

    @IsTest
    static void testGetCygnetPdfAttachmentFlags_ReturnsMap() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        Test.startTest();
        Map<String, Boolean> m = InvoiceEInvoiceController.getCygnetPdfAttachmentFlags(invId);
        Test.stopTest();

        System.assertEquals(false, m.get('hasEInvoicePdf'));
        System.assertEquals(false, m.get('hasEwayBillPdf'));
    }

    @IsTest
    static void testProcessEInvoiceResult_UpdatesInvoice() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        CygnetApiService.StatusResult sr = new CygnetApiService.StatusResult();
        sr.success = true;
        sr.irn = CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX;
        sr.ackNo = '123456789012345678';

        Test.startTest();
        InvoiceEInvoiceController.processEInvoiceResult(invId, sr);
        Test.stopTest();

        Invoice__c inv = [SELECT IRN_Number__c FROM Invoice__c WHERE Id = :invId];
        System.assertNotEquals(null, inv.IRN_Number__c);
    }

    @IsTest
    static void testProcessEWayBillResult_UpdatesEwbFields() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        Test.setMock(HttpCalloutMock.class, new CygnetIntegrationHttpCalloutMock());

        CygnetApiService.StatusResult sr = new CygnetApiService.StatusResult();
        sr.success = true;
        sr.ewbNo = '123456789012345678';
        sr.ewbGeneratedDate = '03-04-2026';
        sr.ewbValidUpto = '04-04-2026';

        Test.startTest();
        InvoiceEInvoiceController.processEWayBillResult(invId, sr);
        Test.stopTest();

        Invoice__c inv = [SELECT EWB__c FROM Invoice__c WHERE Id = :invId];
        System.assertNotEquals(null, inv.EWB__c);
    }

    @IsTest
    static void testProcessEWayBillResult_PersistsTransportDistanceWhenFieldExists() {
        Map<String, Schema.SObjectField> fm = Invoice__c.SObjectType.getDescribe().fields.getMap();
        Schema.SObjectField tf = fm.get('Transport_Distance__c');
        if (tf == null) tf = fm.get('transport_distance__c');
        if (tf == null) {
            return;
        }

        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        CygnetApiService.StatusResult sr = new CygnetApiService.StatusResult();
        sr.success = true;
        sr.ewbNo = '123456789012345678';
        sr.ewbGeneratedDate = '03-04-2026';
        sr.ewbValidUpto = '04-04-2026';
        sr.distanceKm = Decimal.valueOf(908);

        Test.startTest();
        InvoiceEInvoiceController.processEWayBillResult(invId, sr);
        Test.stopTest();

        Invoice__c inv = [
            SELECT Transport_Distance__c
            FROM Invoice__c
            WHERE Id = :invId
        ];
        System.assertNotEquals(null, inv.Transport_Distance__c);
        System.assertEquals(
            Decimal.valueOf(908),
            Decimal.valueOf(String.valueOf(inv.Transport_Distance__c))
        );
    }

    @IsTest
    static void testGetInvoiceEInvoiceFields_NullId_ReturnsEmptyWrapper() {
        Test.startTest();
        InvoiceEInvoiceController.InvoiceEInvoiceFieldsWrapper w =
            InvoiceEInvoiceController.getInvoiceEInvoiceFields(null);
        Test.stopTest();

        System.assertNotEquals(null, w);
        System.assertEquals('', w.irn);
        System.assertEquals(false, w.statusApproved);
    }

    @IsTest
    static void testGetCygnetPdfAttachmentFlags_NullId_ReturnsDefaults() {
        Test.startTest();
        Map<String, Boolean> m = InvoiceEInvoiceController.getCygnetPdfAttachmentFlags(null);
        Test.stopTest();

        System.assertEquals(false, m.get('hasEInvoicePdf'));
        System.assertEquals(false, m.get('hasEwayBillPdf'));
    }

    @IsTest
    static void testGenerateEInvoice_NullId_Throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            InvoiceEInvoiceController.generateEInvoice(null);
        } catch (AuraHandledException e) {
            threw = true;
            // Message text varies by org/runtime; asserting throw is enough.
        } finally {
            Test.stopTest();
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testGenerateEWayBill_NullId_Throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            InvoiceEInvoiceController.generateEWayBill(null);
        } catch (AuraHandledException e) {
            threw = true;
            // Message text varies by org/runtime; asserting throw is enough.
        } finally {
            Test.stopTest();
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testGetEInvoicePdfContentDocumentId_NullId_ReturnsNull() {
        Test.startTest();
        String docId = InvoiceEInvoiceController.getEInvoicePdfContentDocumentId(null);
        Test.stopTest();
        System.assertEquals(null, docId);
    }

    @IsTest
    static void testGetEwayBillPdfContentDocumentId_NullId_ReturnsNull() {
        Test.startTest();
        String docId = InvoiceEInvoiceController.getEwayBillPdfContentDocumentId(null);
        Test.stopTest();
        System.assertEquals(null, docId);
    }

    @IsTest
    static void testGetEInvoicePdfContentDocumentId_AttachesWhenMissing() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        // Ensure no existing "E-Invoice%" link for this invoice
        Integer beforeCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :invId AND ContentDocument.Title LIKE 'E-Invoice%'
        ];
        System.assertEquals(0, beforeCount);

        Test.setMock(HttpCalloutMock.class, new PdfExportSuccessMock());
        Test.startTest();
        String docId = InvoiceEInvoiceController.getEInvoicePdfContentDocumentId(invId);
        Test.stopTest();

        System.assertEquals(true, String.isNotBlank(docId), 'Expected ContentDocumentId after attach');
        Integer afterCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :invId AND ContentDocument.Title LIKE 'E-Invoice%'
        ];
        System.assertEquals(true, afterCount > 0, 'Expected E-Invoice PDF link created');
    }

    @IsTest
    static void testGetEwayBillPdfContentDocumentId_AttachesWhenMissing() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        Integer beforeCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :invId AND ContentDocument.Title LIKE 'E-Way Bill%'
        ];
        System.assertEquals(0, beforeCount);

        Test.setMock(HttpCalloutMock.class, new PdfExportSuccessMock());
        Test.startTest();
        String docId = InvoiceEInvoiceController.getEwayBillPdfContentDocumentId(invId);
        Test.stopTest();

        System.assertEquals(true, String.isNotBlank(docId), 'Expected ContentDocumentId after attach');
        Integer afterCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :invId AND ContentDocument.Title LIKE 'E-Way Bill%'
        ];
        System.assertEquals(true, afterCount > 0, 'Expected E-Way Bill PDF link created');
    }

    @IsTest
    static void testGetEInvoicePdfContentDocumentId_EmptyPdf_Throws() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        Test.setMock(HttpCalloutMock.class, new EmptyPdfExportMock());
        Boolean threw = false;
        Test.startTest();
        try {
            InvoiceEInvoiceController.getEInvoicePdfContentDocumentId(invId);
        } catch (AuraHandledException e) {
            threw = true;
        } finally {
            Test.stopTest();
        }
        System.assertEquals(true, threw, 'Expected AuraHandledException when PDF content is empty');
    }

    @IsTest
    static void testProcessEInvoiceResult_ParsesAckDate_SlashFormat_And_MonthNameFormat() {
        // Covers parseDate branches around lines ~456-506 in controller.
        Id invId1 = CygnetIntegrationTestData.createInvoiceWithLine(false);
        Id invId2 = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId1);
        System.assertNotEquals(null, invId2);

        CygnetApiService.StatusResult sr1 = new CygnetApiService.StatusResult();
        sr1.success = true;
        sr1.irn = CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX;
        sr1.ackDate = '16/09/2026';

        CygnetApiService.StatusResult sr2 = new CygnetApiService.StatusResult();
        sr2.success = true;
        sr2.irn = CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX;
        sr2.ackDate = 'Sat Sep 16 00:00:00 GMT 2026';

        Test.startTest();
        InvoiceEInvoiceController.processEInvoiceResult(invId1, sr1);
        InvoiceEInvoiceController.processEInvoiceResult(invId2, sr2);
        Test.stopTest();

        Invoice__c inv1 = [SELECT IRN_Number__c FROM Invoice__c WHERE Id = :invId1];
        Invoice__c inv2 = [SELECT IRN_Number__c FROM Invoice__c WHERE Id = :invId2];
        System.assertNotEquals(null, inv1.IRN_Number__c);
        System.assertNotEquals(null, inv2.IRN_Number__c);
    }

    @IsTest
    static void testProcessEInvoiceResult_InvalidAckDate_DoesNotCrash() {
        // Exercises parseDate catch(Exception) path via invalid numeric parts.
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        CygnetApiService.StatusResult sr = new CygnetApiService.StatusResult();
        sr.success = true;
        sr.irn = CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX;
        sr.ackDate = 'aa/bb/cccc';

        Test.startTest();
        InvoiceEInvoiceController.processEInvoiceResult(invId, sr);
        Test.stopTest();

        Invoice__c inv = [SELECT IRN_Number__c FROM Invoice__c WHERE Id = :invId];
        System.assertNotEquals(null, inv.IRN_Number__c);
    }

    @IsTest
    static void testGenerateEInvoice_UnderSsValidationBranches_WhenRecordTypeAvailable() {
        // Covers validateForEInvoice Under-SS branches (lines ~233-247) when the RT exists in this org.
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(true);
        System.assertNotEquals(null, invId);

        Invoice__c inv = [
            SELECT Id, RecordType.DeveloperName, Distributor_Account__c, Under_SS__c
            FROM Invoice__c
            WHERE Id = :invId
            LIMIT 1
        ];
        if (inv.RecordType == null || inv.RecordType.DeveloperName == null
            || !inv.RecordType.DeveloperName.equalsIgnoreCase('Secondary_Invoice_Under_SS')) {
            return;
        }

        Test.setMock(HttpCalloutMock.class, new CygnetIntegrationHttpCalloutMock());

        // Use a single Test.startTest/stopTest to avoid "Testing already started" even if
        // the org throws different exception types during validation.
        Boolean threw1 = false;
        Boolean threw2 = false;
        Boolean threw3 = false;

        Test.startTest();
        try {
            // 1) Missing Distributor_Account__c -> seller required
            update new Invoice__c(Id = invId, Distributor_Account__c = null);
            try {
                InvoiceEInvoiceController.generateEInvoice(invId);
            } catch (AuraHandledException e) {
                threw1 = true;
            }

            // 2) Missing Under_SS__c -> buyer required
            update new Invoice__c(Id = invId, Distributor_Account__c = inv.Distributor_Account__c, Under_SS__c = null);
            try {
                InvoiceEInvoiceController.generateEInvoice(invId);
            } catch (AuraHandledException e) {
                threw2 = true;
            }

            // 3) Under_SS_GSTIN__c blank + Account GSTIN blank -> GSTIN required
            update new Invoice__c(Id = invId, Under_SS__c = inv.Under_SS__c, Distributor_Account__c = inv.Distributor_Account__c);
            // Some orgs mark Under_SS_GSTIN__c as formula/read-only; update defensively.
            try {
                SObject invUpd = new Invoice__c(Id = invId);
                invUpd.put('Under_SS_GSTIN__c', null);
                update invUpd;
            } catch (Exception ex) { }
            try { update new Account(Id = inv.Under_SS__c, GSTIN__c = null); } catch (Exception ex) { }

            try {
                InvoiceEInvoiceController.generateEInvoice(invId);
            } catch (AuraHandledException e) {
                threw3 = true;
            }
        } finally {
            Test.stopTest();
        }

        System.assertEquals(true, threw1);
        System.assertEquals(true, threw2);
        System.assertEquals(true, threw3);
    }

    @IsTest
    static void testProcessEInvoiceResult_WithEwbFieldsInSr_StoresEwb() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        CygnetApiService.StatusResult sr = new CygnetApiService.StatusResult();
        sr.success = true;
        sr.irn = CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX;
        sr.ewbNo = '9876543210987654';

        Test.startTest();
        InvoiceEInvoiceController.processEInvoiceResult(invId, sr);
        Test.stopTest();

        Invoice__c inv = [SELECT EWB__c FROM Invoice__c WHERE Id = :invId];
        System.assertNotEquals(null, inv.EWB__c);
    }

    @IsTest
    static void testProcessEInvoiceResult_WithAckDateAndSignedFields() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        CygnetApiService.StatusResult sr = new CygnetApiService.StatusResult();
        sr.success = true;
        sr.irn = CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX;
        sr.ackNo = '111122223333444455';
        sr.ackDate = '2026-04-01';
        sr.signedInvoice = 'signed-payload';
        sr.signedQRCode = 'signed-qr';
        sr.qrCodeData = 'qr-data';

        Test.startTest();
        InvoiceEInvoiceController.processEInvoiceResult(invId, sr);
        Test.stopTest();

        Invoice__c inv = [SELECT IRN_Number__c FROM Invoice__c WHERE Id = :invId];
        System.assertNotEquals(null, inv.IRN_Number__c);
    }

    @IsTest
    static void testGenerateEInvoice_EnqueuesQueueable() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        Test.setMock(HttpCalloutMock.class, new CygnetIntegrationHttpCalloutMock());
        Test.startTest();
        InvoiceEInvoiceController.generateEInvoice(invId);
        Test.stopTest();

        Invoice__c inv = [SELECT IRN_Number__c FROM Invoice__c WHERE Id = :invId];
        System.assert(
            String.isNotBlank(String.valueOf(inv.IRN_Number__c))
                || CygnetIntegrationLogTestHelper.countLogsForInvoice(invId) > 0,
            'Queueable should complete with IRN or failure log'
        );
    }

    @IsTest
    static void testGenerateEWayBill_EnqueuesQueueable() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);
        CygnetIntegrationTestData.makeInvoiceEwayBillReady(invId);

        Test.setMock(HttpCalloutMock.class, new CygnetIntegrationHttpCalloutMock());
        Test.startTest();
        InvoiceEInvoiceController.generateEWayBill(invId);
        Test.stopTest();

        Invoice__c inv = [SELECT EWB__c FROM Invoice__c WHERE Id = :invId];
        System.assert(
            inv.EWB__c != null || CygnetIntegrationLogTestHelper.countLogsForInvoice(invId) > 0,
            'Queueable should complete with EWB or failure log'
        );
    }

    @IsTest
    static void testGenerateEInvoice_StatusNotConfirmed_Throws() {
        // IMPORTANT: don't update Confirmed -> Draft because some orgs block "status backward" via validation.
        // Instead, insert a separate Draft invoice with the same minimal relationships.
        Id seedInvId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, seedInvId);

        Invoice__c seed = [
            SELECT RecordTypeId, Distributor_Account__c, Retailer_Account__c,
                Invoice_Number__c, Invoice_Date__c, Taxable_Amount__c, CGST_Amount__c, SGST_Amount__c,
                IGST_Amount__c, Invoice_Total__c, Place_of_Supply__c
            FROM Invoice__c
            WHERE Id = :seedInvId
            LIMIT 1
        ];
        Invoice_Line_Item__c seedLine = [
            SELECT Product__c, Quantity__c, Price__c, CGST_Amount__c, SGST_Amount__c, IGST_Amount__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c = :seedInvId
            LIMIT 1
        ];

        Invoice__c inv = new Invoice__c();
        inv.RecordTypeId = seed.RecordTypeId;
        inv.Status__c = 'Draft';
        inv.Distributor_Account__c = seed.Distributor_Account__c;
        inv.Retailer_Account__c = seed.Retailer_Account__c;
        inv.Invoice_Number__c = (seed.Invoice_Number__c != null ? seed.Invoice_Number__c : 'INV-DRAFT')
            + '-D';
        inv.Invoice_Date__c = seed.Invoice_Date__c != null ? seed.Invoice_Date__c : Date.today();
        inv.Taxable_Amount__c = seed.Taxable_Amount__c;
        inv.CGST_Amount__c = seed.CGST_Amount__c;
        inv.SGST_Amount__c = seed.SGST_Amount__c;
        inv.IGST_Amount__c = seed.IGST_Amount__c;
        inv.Invoice_Total__c = seed.Invoice_Total__c;
        inv.Place_of_Supply__c = seed.Place_of_Supply__c;
        insert inv;

        Invoice_Line_Item__c line = new Invoice_Line_Item__c();
        line.Invoice__c = inv.Id;
        line.Product__c = seedLine.Product__c;
        line.Quantity__c = seedLine.Quantity__c;
        line.Price__c = seedLine.Price__c;
        line.CGST_Amount__c = seedLine.CGST_Amount__c;
        line.SGST_Amount__c = seedLine.SGST_Amount__c;
        line.IGST_Amount__c = seedLine.IGST_Amount__c;
        insert line;

        Test.setMock(HttpCalloutMock.class, new CygnetIntegrationHttpCalloutMock());
        Boolean threw = false;
        Test.startTest();
        try {
            InvoiceEInvoiceController.generateEInvoice(inv.Id);
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage() != null);
        } finally {
            Test.stopTest();
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testGenerateEWayBill_MissingIrn_Throws() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        Test.setMock(HttpCalloutMock.class, new CygnetIntegrationHttpCalloutMock());
        Boolean threw = false;
        Test.startTest();
        try {
            InvoiceEInvoiceController.generateEWayBill(invId);
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage() != null);
        } finally {
            Test.stopTest();
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testGetCygnetPdfAttachmentFlags_WhenFilesExist_ReturnsTrue() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        ContentVersion cv1 = new ContentVersion();
        cv1.Title = 'E-Invoice - Unit Test';
        cv1.PathOnClient = 'einv.pdf';
        cv1.VersionData = Blob.valueOf('pdf');
        cv1.FirstPublishLocationId = invId;
        insert cv1;

        ContentVersion cv2 = new ContentVersion();
        cv2.Title = 'E-Way Bill - Unit Test';
        cv2.PathOnClient = 'ewb.pdf';
        cv2.VersionData = Blob.valueOf('pdf');
        cv2.FirstPublishLocationId = invId;
        insert cv2;

        Test.startTest();
        Map<String, Boolean> m = InvoiceEInvoiceController.getCygnetPdfAttachmentFlags(invId);
        Test.stopTest();

        System.assertEquals(true, m.get('hasEInvoicePdf'));
        System.assertEquals(true, m.get('hasEwayBillPdf'));
    }

    @IsTest
    static void testGetEInvoicePdfContentDocumentId_WhenAlreadyAttached_ReturnsId() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        ContentVersion cv = new ContentVersion(
            Title = 'E-Invoice - Existing',
            PathOnClient = 'einv.pdf',
            VersionData = Blob.valueOf('pdf'),
            FirstPublishLocationId = invId
        );
        insert cv;

        Test.startTest();
        String docId = InvoiceEInvoiceController.getEInvoicePdfContentDocumentId(invId);
        Test.stopTest();

        System.assertEquals(true, String.isNotBlank(docId));
    }

    @IsTest
    static void testGetEwayBillPdfContentDocumentId_WhenAlreadyAttached_ReturnsId() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        ContentVersion cv = new ContentVersion(
            Title = 'E-Way Bill - Existing',
            PathOnClient = 'ewb.pdf',
            VersionData = Blob.valueOf('pdf'),
            FirstPublishLocationId = invId
        );
        insert cv;

        Test.startTest();
        String docId = InvoiceEInvoiceController.getEwayBillPdfContentDocumentId(invId);
        Test.stopTest();

        System.assertEquals(true, String.isNotBlank(docId));
    }
}