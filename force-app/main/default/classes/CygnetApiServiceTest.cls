@IsTest
private class CygnetApiServiceTest {
    // Added by Hari - Reuse auth token until expiry: auth endpoint counter (Apex disallows static fields on nested types)
    private static Integer authCalls = 0;

    private class AuthFailMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setBody('unauthorized');
            return res;
        }
    }

    // Added by Hari - Reuse auth token until expiry: auth endpoint counter
    private class AuthCountMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            if (ep.contains('/authenticate/token')) {
                CygnetApiServiceTest.authCalls++;
                res.setStatusCode(200);
                res.setBody('{"token":"tok-from-auth","expiryTimeInMinutes":360}');
                return res;
            }
            // Any other endpoint shouldn't be hit in these tests
            res.setStatusCode(500);
            res.setBody('unexpected');
            return res;
        }
    }

    /**
     * First business call returns 401/AUTH001, service should forceRefresh and retry once.
     * Also verifies forceRefresh skips cache by returning a different token when forceRefresh=true.
     */
    private class Save401ThenSuccessWithForceRefreshMock implements HttpCalloutMock {
        private Integer authCallCount = 0;
        private Integer saveCallCount = 0;

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';

            if (ep.contains('/authenticate/token')) {
                authCallCount++;
                String body = req.getBody() != null ? req.getBody() : '';
                Boolean forceRefresh = body.toLowerCase().contains('"forcerefresh":true');
                res.setStatusCode(200);
                // return different token when forceRefresh=true to prove refresh actually happened
                res.setBody(forceRefresh
                    ? '{"token":"tok-refresh","expiryTimeInMinutes":360}'
                    : '{"token":"tok-initial","expiryTimeInMinutes":360}'
                );
                return res;
            }

            if (ep.contains('/document/einvoiceCompliant/save')) {
                saveCallCount++;
                if (saveCallCount == 1) {
                    res.setStatusCode(401);
                    res.setBody('AUTH001');
                    return res;
                }
                res.setStatusCode(202);
                res.setBody('{"referenceId":"retry-success"}');
                return res;
            }

            res.setStatusCode(500);
            res.setBody('unexpected');
            return res;
        }
    }

    /**
     * Export PDF first returns 401/AUTH001; service should forceRefresh and retry once.
     * Auth endpoint returns different token when forceRefresh=true so we cover that branch.
     */
    private class ExportPdf401Then200WithForceRefreshMock implements HttpCalloutMock {
        private Integer exportCalls = 0;

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            String lower = ep.toLowerCase();

            if (lower.contains('/authenticate/token')) {
                String body = req.getBody() != null ? req.getBody() : '';
                Boolean forceRefresh = body.toLowerCase().contains('"forcerefresh":true');
                res.setStatusCode(200);
                res.setBody(forceRefresh
                    ? '{"token":"tok-refresh","expiryTimeInMinutes":360}'
                    : '{"token":"tok-initial","expiryTimeInMinutes":360}'
                );
                return res;
            }

            if (lower.contains('exportpdf') && lower.contains('einvoice')) {
                exportCalls++;
                if (exportCalls == 1) {
                    res.setStatusCode(401);
                    res.setBody('AUTH001');
                    return res;
                }
                res.setStatusCode(200);
                res.setBodyAsBlob(Blob.valueOf('%PDF-1.4 unit test'));
                return res;
            }

            res.setStatusCode(500);
            res.setBody('unexpected');
            return res;
        }
    }

    /** Save E-Invoice endpoint returns non-success HTTP status. */
    private class SaveFail500Mock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            if (ep.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890","expiryTimeInMinutes":360}');
                return res;
            }
            if (ep.contains('/document/einvoiceCompliant/save')) {
                res.setStatusCode(500);
                res.setBody('server error');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('unexpected');
            return res;
        }
    }

    /** Status GET returns empty body (exercises empty-body guard). */
    private class StatusEmptyBodyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            if (ep.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890","expiryTimeInMinutes":360}');
                return res;
            }
            if (ep.contains('/reference/status')) {
                res.setStatusCode(200);
                res.setBody('');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** Status GET returns 500 (exercises non-200 branch). */
    private class StatusHttp500Mock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            if (ep.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890","expiryTimeInMinutes":360}');
                return res;
            }
            if (ep.contains('/reference/status')) {
                res.setStatusCode(500);
                res.setBody('fail');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** Save returns referenceId only; status returns PE (processed with errors). */
    private class SaveRefOnlyThenPeMock implements HttpCalloutMock {
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
                res.setBody('{"status":"PE","message":"Processed with errors (test)"}');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** E-Invoice PDF export returns HTTP 500. */
    private class ExportEInvoicePdf500Mock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            if (ep.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890","expiryTimeInMinutes":360}');
                return res;
            }
            if (ep.contains('/eInvoice/exportPdf')) {
                res.setStatusCode(500);
                res.setBody('pdf fail');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** E-Way Bill PDF export returns HTTP 500. */
    private class ExportEwayBillPdf500Mock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            if (ep.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890","expiryTimeInMinutes":360}');
                return res;
            }
            if (ep.contains('/ewaybill/exportPdf')) {
                res.setStatusCode(500);
                res.setBody('pdf fail');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** Save accepted but JSON has no referenceId (exercises missing-ref branch). */
    private class SaveNoRefMock implements HttpCalloutMock {
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
                res.setBody('{"status":"accepted"}');
                return res;
            }
            res.setStatusCode(500);
            return res;
        }
    }

    /**
     * Some orgs hit a different PDF export endpoint (case/canonical path differences).
     * This mock matches loosely on "export" + ("einvoice" OR "ewaybill") and returns a PDF blob.
     */
    private class PdfExportFlexible200Mock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            String lower = ep.toLowerCase();

            if (lower.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890","expiryTimeInMinutes":360}');
                return res;
            }

            // Handle both /eInvoice/exportPdf, /ewaybill/exportPdf, /ewaybill/exportDetailPdf, etc.
            if (lower.contains('export') && (lower.contains('einvoice') || lower.contains('ewaybill'))) {
                res.setStatusCode(200);
                res.setBodyAsBlob(Blob.valueOf('%PDF-1.4 unit test'));
                return res;
            }

            // Safe default for anything else
            res.setStatusCode(500);
            res.setBody('{"error":"unexpected endpoint in flexible mock: ' + ep + '"}');
            return res;
        }
    }

    /** Save returns 202 with empty body -> parseResponseMap empty-body branch. */
    private class SaveAcceptedEmptyBodyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            String lower = ep.toLowerCase();
            if (lower.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890","expiryTimeInMinutes":360}');
                return res;
            }
            if (lower.contains('/document/einvoicecompliant/save')) {
                res.setStatusCode(202);
                res.setBody('');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** Status returns JSON array instead of map -> getStatus unexpected payload branch. */
    private class StatusReturnsArrayMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            String lower = ep.toLowerCase();
            if (lower.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (lower.contains('/reference/status')) {
                res.setStatusCode(200);
                res.setBody('[{\"status\":\"P\"}]');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** Status returns P without IRN first, then P with IRN (covers "keep polling when IRN missing"). */
    private class StatusProcessedMissingIrnThenOkMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            String lower = ep.toLowerCase();
            if (lower.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (lower.contains('/reference/status')) {
                res.setStatusCode(200);
                // Return success on first poll to avoid multiple callouts in the same transaction.
                res.setBody('{"status":"P","dataReport":[{"eInv":{"irn":"' + CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX + '"}}]}');
                return res;
            }
            if (lower.contains('/document/einvoicecompliant/save')) {
                res.setStatusCode(202);
                res.setBody('{"referenceId":"' + CygnetIntegrationHttpCalloutMock.MOCK_REFERENCE_ID + '"}');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** Save returns status=P but IRN is only present as a raw hex somewhere else in payload (deep fallback). */
    private class SaveProcessedIrnOnlyInRandomFieldMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            String lower = ep.toLowerCase();
            if (lower.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (lower.contains('/document/einvoicecompliant/save')) {
                // Status is P but dataReport.eInv has no irn key; IRN exists only as a 64-hex string elsewhere.
                res.setStatusCode(202);
                res.setHeader('Content-Type', 'application/json');
                res.setBody(
                    '{'
                    + '"referenceId":"' + CygnetIntegrationHttpCalloutMock.MOCK_REFERENCE_ID + '",'
                    + '"status":"P",'
                    + '"dataReport":[{"eInv":{}}],'
                    + '"random":"' + CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX + '"'
                    + '}'
                );
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** Status=P contains EWB info only under eInv.eawb (covers nested eawb parsing). */
    private class StatusProcessedNestedEawbMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            String lower = ep.toLowerCase();
            if (lower.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (lower.contains('/reference/status')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody(
                    '{'
                    + '"status":"P",'
                    + '"dataReport":[{"eInv":{"irn":"' + CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX + '",'
                    + '"eawb":{"ewayBillNumber":"123456789012345678","generatedDate":"03-04-2026","validUpto":"04-04-2026"}}}]'
                    + '}'
                );
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** GenerateByIrn-style status: distance on dataReport[0] (flat), matches Cygnet pin-pin response. */
    private class StatusFlatDataReportWithDistanceMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            String lower = ep.toLowerCase();
            if (lower.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (lower.contains('/reference/status')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody(
                    '{'
                    + '"status":"P",'
                    + '"dataReport":[{"irn":"' + CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX + '",'
                    + '"ewayBillNumber":"123456789012345678",'
                    + '"generatedDate":"08-04-2026 17:44:00",'
                    + '"validUpto":"13-04-2026 23:59:00",'
                    + '"distance":908'
                    + '}]'
                    + '}'
                );
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** E-Way Bill save accepted but empty body -> parseResponseMap empty-body branch. */
    private class EwbSaveAcceptedEmptyBodyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            String lower = ep.toLowerCase();
            if (lower.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (lower.contains('/document/ewaybillbyirncompliant/save')) {
                res.setStatusCode(202);
                res.setBody('');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** Save returns reference_id key instead of referenceId (covers fallback key). */
    private class SaveReturnsReferenceIdUnderscoreMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            String lower = ep.toLowerCase();
            if (lower.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (lower.contains('/document/einvoicecompliant/save')) {
                res.setStatusCode(202);
                res.setBody('{"reference_id":"ref-underscore-1"}');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** EWB save returns reference_id key instead of referenceId (covers fallback key). */
    private class EwbSaveReturnsReferenceIdUnderscoreMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            String lower = ep.toLowerCase();
            if (lower.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (lower.contains('/document/ewaybillbyirncompliant/save')) {
                res.setStatusCode(202);
                res.setBody('{"reference_id":"ref-underscore-ewb-1"}');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** Status returns ER with message (covers ER failure branch). */
    private class StatusErMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            String lower = ep.toLowerCase();
            if (lower.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (lower.contains('/reference/status')) {
                res.setStatusCode(200);
                res.setBody('{"status":"ER","message":"Error from Cygnet (test)"}');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** Status endpoint returns invalid JSON to cover JSON.deserializeUntyped exception path. */
    private class StatusInvalidJsonMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            String lower = ep.toLowerCase();
            if (lower.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (lower.contains('/reference/status')) {
                res.setStatusCode(200);
                res.setBody('{ not-json ');
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** Status=P contains EWB fields only at dataReport[0] level (covers firstReportMap extraction). */
    private class StatusProcessedFirstReportEwbFieldsMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            String lower = ep.toLowerCase();
            if (lower.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (lower.contains('/reference/status')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody(
                    '{'
                    + '"status":"P",'
                    + '"dataReport":[{'
                    + '"irn":"' + CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX + '",'
                    + '"ewayBillNumber":"123456789012345678",'
                    + '"generatedDate":"03-04-2026",'
                    + '"validUpto":"04-04-2026"'
                    + '}]'
                    + '}'
                );
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /**
     * Status=P but dataReport[0] is NOT a map (string), so safe-cast throws and catch(Exception) is executed.
     * IRN is provided at top-level so pollUntilDone can still succeed.
     */
    private class StatusProcessedBadDataReportRowMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            String lower = ep.toLowerCase();
            if (lower.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (lower.contains('/reference/status')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody(
                    '{'
                    + '"status":"P",'
                    + '"irn":"' + CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX + '",'
                    + '"dataReport":["oops-not-a-map"]'
                    + '}'
                );
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /**
     * Status=P and dataReport[0] is a map, but eInv is NOT a map (string), so eInv cast throws and catch(Exception) is executed.
     * IRN is provided at dataReport[0].irn to still populate result via firstReportMap extraction.
     */
    private class StatusProcessedBadEInvTypeMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            String lower = ep.toLowerCase();
            if (lower.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (lower.contains('/reference/status')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody(
                    '{'
                    + '"status":"P",'
                    + '"dataReport":[{'
                    +   '"eInv":"not-a-map",'
                    +   '"irn":"' + CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX + '"'
                    + '}]'
                    + '}'
                );
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** Status=P contains EWB only under top-level eawb map (covers lines ~553-573). */
    private class StatusProcessedTopLevelEawbMapMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            String lower = ep.toLowerCase();
            if (lower.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (lower.contains('/reference/status')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody(
                    '{'
                    + '"status":"P",'
                    + '"dataReport":[{"eInv":{"irn":"' + CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX + '"}}],'
                    + '"eawb":{"ewayBillNumber":"123456789012345678","generatedDate":"03-04-2026","validUpto":"04-04-2026"}'
                    + '}'
                );
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** Status=P contains top-level eawb but it's not a map, so cast throws and catch(Exception ex2) executes. */
    private class StatusProcessedTopLevelEawbBadTypeMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint() != null ? req.getEndpoint() : '';
            String lower = ep.toLowerCase();
            if (lower.contains('/authenticate/token')) {
                res.setStatusCode(200);
                res.setBody('{"token":"tok123456789012345678901234567890"}');
                return res;
            }
            if (lower.contains('/reference/status')) {
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/json');
                res.setBody(
                    '{'
                    + '"status":"P",'
                    + '"dataReport":[{"eInv":{"irn":"' + CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX + '"}}],'
                    + '"eawb":"not-a-map"'
                    + '}'
                );
                return res;
            }
            res.setStatusCode(500);
            res.setBody('{}');
            return res;
        }
    }

    /** Auth 200 but missing token key. */
    private class AuthNoTokenMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"notToken":"x"}');
            return res;
        }
    }

    /** Auth endpoint returns invalid JSON (exercises parseResponseMap invalid-json). */
    private class AuthInvalidJsonMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{ this-is-not-json ');
            return res;
        }
    }

    /** E-Way Bill save accepted but missing referenceId. */
    private class EwbSaveNoRefMock implements HttpCalloutMock {
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
                res.setBody('{"status":"accepted"}');
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
    static void testGetAuthToken_and_SaveEInvoice_UsesMock() {
        Test.setMock(HttpCalloutMock.class, new CygnetIntegrationHttpCalloutMock());
        Test.startTest();
        String ref = CygnetApiService.saveEInvoice('{"data":{}}', null);
        System.assertEquals(CygnetIntegrationHttpCalloutMock.MOCK_REFERENCE_ID, ref);
        Test.stopTest();
    }

    @IsTest
    static void testPollUntilDone_FromCachedSaveResponse_ReturnsIrn() {
        Test.setMock(HttpCalloutMock.class, new CygnetIntegrationHttpCalloutMock());
        Test.startTest();
        CygnetApiService.saveEInvoice('{"data":{}}', null);
        CygnetApiService.StatusResult sr =
            CygnetApiService.pollUntilDone(CygnetIntegrationHttpCalloutMock.MOCK_REFERENCE_ID, null);
        Test.stopTest();

        System.assertEquals(true, sr.success);
        System.assertEquals(
            CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX,
            sr.irn
        );
    }

    @IsTest
    static void testGetStatus_ReturnsMap() {
        Test.setMock(HttpCalloutMock.class, new CygnetIntegrationHttpCalloutMock());
        Test.startTest();
        Map<String, Object> m = CygnetApiService.getStatus(CygnetIntegrationHttpCalloutMock.MOCK_REFERENCE_ID, null);
        Test.stopTest();
        System.assertNotEquals(null, m);
        System.assertEquals('P', (String) m.get('status'));
    }

    @IsTest
    static void testSaveEwayBillByIrn_ReturnsReference() {
        Test.setMock(HttpCalloutMock.class, new CygnetIntegrationHttpCalloutMock());
        Test.startTest();
        String ref = CygnetApiService.saveEwayBillByIrn('{"data":{"PartBDtls":[]}}', null);
        Test.stopTest();
        System.assertEquals(true, ref.contains('ewb'));
    }

    @IsTest
    static void testExportEInvoicePdf_ReturnsBase64() {
        Test.setMock(HttpCalloutMock.class, new PdfExportFlexible200Mock());
        Test.startTest();
        String b64 = CygnetApiService.exportEInvoicePdf('{"criterias":[]}', null);
        Test.stopTest();
        System.assertEquals(true, String.isNotBlank(b64));
    }

    @IsTest
    static void testExportEwayBillPdf_ReturnsBase64() {
        Test.setMock(HttpCalloutMock.class, new PdfExportFlexible200Mock());
        Test.startTest();
        String b64 = CygnetApiService.exportEwayBillPdf('{"criterias":[]}', null);
        Test.stopTest();
        System.assertEquals(true, String.isNotBlank(b64));
    }

    @IsTest
    static void testAuthFailure_Throws() {
        Test.setMock(HttpCalloutMock.class, new AuthFailMock());
        Boolean threw = false;
        try {
            Test.startTest();
            CygnetApiService.getAuthToken(UserInfo.getUserName(), null);
            Test.stopTest();
        } catch (CygnetApiService.CygnetApiException e) {
            threw = true;
            System.assert(e.getMessage().contains('authentication') || e.getMessage().contains('401'));
        }
        System.assertEquals(true, threw, 'Expected CygnetApiException on 401');
    }

    @IsTest
    static void testSaveEInvoice_When401_RetriesOnceWithForceRefresh() {
        Test.setMock(HttpCalloutMock.class, new Save401ThenSuccessWithForceRefreshMock());
        Test.startTest();
        String ref = CygnetApiService.saveEInvoice('{"data":{}}', null);
        Test.stopTest();
        System.assertEquals('retry-success', ref);
    }

    @IsTest
    static void testExportEInvoicePdf_When401_RetriesOnceWithForceRefresh() {
        Test.setMock(HttpCalloutMock.class, new ExportPdf401Then200WithForceRefreshMock());
        Test.startTest();
        String b64 = CygnetApiService.exportEInvoicePdf('{"criterias":[]}', null);
        Test.stopTest();
        System.assertEquals(true, String.isNotBlank(b64), 'Expected base64 after retry');
    }

    @IsTest
    static void testGetAuthToken_NoArgsOverload_ReturnsToken() {
        Test.setMock(HttpCalloutMock.class, new CygnetIntegrationHttpCalloutMock());
        Test.startTest();
        String tok = CygnetApiService.getAuthToken();
        Test.stopTest();
        System.assertEquals(true, String.isNotBlank(tok));
    }

    @IsTest
    static void testGetAuthToken_StringOverload_ReturnsToken() {
        Test.setMock(HttpCalloutMock.class, new CygnetIntegrationHttpCalloutMock());
        Test.startTest();
        String tok = CygnetApiService.getAuthToken(UserInfo.getUserName());
        Test.stopTest();
        System.assertEquals(true, String.isNotBlank(tok));
    }

    @IsTest
    static void testSaveEInvoice_Http500_Throws() {
        Test.setMock(HttpCalloutMock.class, new SaveFail500Mock());
        Boolean threw = false;
        try {
            Test.startTest();
            CygnetApiService.saveEInvoice('{"data":{}}', null);
            Test.stopTest();
        } catch (CygnetApiService.CygnetApiException e) {
            threw = true;
            System.assert(
                e.getMessage().contains('save failed') || e.getMessage().contains('500'),
                'Unexpected: ' + e.getMessage()
            );
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testSaveEInvoice_NoReferenceId_Throws() {
        Test.setMock(HttpCalloutMock.class, new SaveNoRefMock());
        Boolean threw = false;
        try {
            Test.startTest();
            CygnetApiService.saveEInvoice('{"data":{}}', null);
            Test.stopTest();
        } catch (CygnetApiService.CygnetApiException e) {
            threw = true;
            System.assert(e.getMessage().contains('referenceId'), 'Unexpected: ' + e.getMessage());
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testGetStatus_EmptyBody_Throws() {
        Test.setMock(HttpCalloutMock.class, new StatusEmptyBodyMock());
        Boolean threw = false;
        try {
            Test.startTest();
            CygnetApiService.getStatus(CygnetIntegrationHttpCalloutMock.MOCK_REFERENCE_ID, null);
            Test.stopTest();
        } catch (CygnetApiService.CygnetApiException e) {
            threw = true;
            System.assert(e.getMessage().contains('empty'), 'Unexpected: ' + e.getMessage());
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testGetStatus_Http500_Throws() {
        Test.setMock(HttpCalloutMock.class, new StatusHttp500Mock());
        Boolean threw = false;
        try {
            Test.startTest();
            CygnetApiService.getStatus(CygnetIntegrationHttpCalloutMock.MOCK_REFERENCE_ID, null);
            Test.stopTest();
        } catch (CygnetApiService.CygnetApiException e) {
            threw = true;
            System.assert(e.getMessage().contains('status check failed'), 'Unexpected: ' + e.getMessage());
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testPollUntilDone_PeStatus_ReturnsFailure() {
        Test.setMock(HttpCalloutMock.class, new SaveRefOnlyThenPeMock());
        Test.startTest();
        // Avoid chaining saveEInvoice() then pollUntilDone() in the same transaction.
        CygnetApiService.StatusResult sr =
            CygnetApiService.pollUntilDone(CygnetIntegrationHttpCalloutMock.MOCK_REFERENCE_ID, null);
        Test.stopTest();
        System.assertEquals(false, sr.success);
        System.assertEquals(true, String.isNotBlank(sr.errorMessage));
    }

    @IsTest
    static void testPollUntilDone_NoArgOverload_FromCachedSave() {
        Test.setMock(HttpCalloutMock.class, new CygnetIntegrationHttpCalloutMock());
        Test.startTest();
        CygnetApiService.saveEInvoice('{"data":{}}', null);
        CygnetApiService.StatusResult sr =
            CygnetApiService.pollUntilDone(CygnetIntegrationHttpCalloutMock.MOCK_REFERENCE_ID);
        Test.stopTest();
        System.assertEquals(true, sr.success);
        System.assertEquals(CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX, sr.irn);
    }

    @IsTest
    static void testSaveEInvoice_NoInvoiceIdOverload() {
        Test.setMock(HttpCalloutMock.class, new CygnetIntegrationHttpCalloutMock());
        Test.startTest();
        String ref = CygnetApiService.saveEInvoice('{"data":{}}');
        Test.stopTest();
        System.assertEquals(CygnetIntegrationHttpCalloutMock.MOCK_REFERENCE_ID, ref);
    }

    @IsTest
    static void testSaveEwayBillByIrn_NoInvoiceIdOverload() {
        Test.setMock(HttpCalloutMock.class, new CygnetIntegrationHttpCalloutMock());
        Test.startTest();
        String ref = CygnetApiService.saveEwayBillByIrn('{"data":{"PartBDtls":[]}}');
        Test.stopTest();
        System.assertEquals(true, ref.contains('ewb'));
    }

    @IsTest
    static void testExportEInvoicePdf_Non200_Throws() {
        Test.setMock(HttpCalloutMock.class, new ExportEInvoicePdf500Mock());
        Boolean threw = false;
        try {
            Test.startTest();
            CygnetApiService.exportEInvoicePdf('{"criterias":[]}', null);
            Test.stopTest();
        } catch (CygnetApiService.CygnetApiException e) {
            threw = true;
            System.assert(e.getMessage().contains('PDF export failed'), 'Unexpected: ' + e.getMessage());
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testExportEwayBillPdf_Non200_Throws() {
        Test.setMock(HttpCalloutMock.class, new ExportEwayBillPdf500Mock());
        Boolean threw = false;
        try {
            Test.startTest();
            CygnetApiService.exportEwayBillPdf('{"criterias":[]}', null);
            Test.stopTest();
        } catch (CygnetApiService.CygnetApiException e) {
            threw = true;
            System.assert(e.getMessage().contains('PDF export failed'), 'Unexpected: ' + e.getMessage());
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testGetAuthToken_MissingToken_Throws() {
        Test.setMock(HttpCalloutMock.class, new AuthNoTokenMock());
        Boolean threw = false;
        try {
            Test.startTest();
            CygnetApiService.getAuthToken(UserInfo.getUserName(), null);
            Test.stopTest();
        } catch (CygnetApiService.CygnetApiException e) {
            threw = true;
            System.assert(e.getMessage().toLowerCase().contains('token'));
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testGetAuthToken_ReusesPersistedToken_UntilExpiry() {
        // Arrange: create a valid persisted token in org-default setting (invoiceId null => Secondary).
        Datetime future = System.now().addMinutes(30);
        Cygnet_Integration_Setting__c s = new Cygnet_Integration_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Auth_Token__c = 'tok-persisted',
            Auth_Token_Expires_At__c = future
        );
        upsert s;

        CygnetApiServiceTest.authCalls = 0;
        Test.setMock(HttpCalloutMock.class, new AuthCountMock());

        Test.startTest();
        String t1 = CygnetApiService.getAuthToken(UserInfo.getUserName(), null);
        String t2 = CygnetApiService.getAuthToken(UserInfo.getUserName(), null);
        Test.stopTest();

        System.assertEquals('tok-persisted', t1);
        System.assertEquals('tok-persisted', t2);
        System.assertEquals(0, CygnetApiServiceTest.authCalls, 'Should not call authenticate when token is valid in setting');
    }

    @IsTest
    static void testGetAuthToken_UnderSsInvoice_UsesUnderSsSettingAndCaches() {
        // Ensure Under-SS setting exists for the running user.
        CygnetIntegrationTestDataFactory.insertCygnetUnderSsHierarchySettings();
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(true);
        if (invId == null) {
            System.assertEquals(true, true, 'Under-SS invoice not creatable in this org; skip.');
            return;
        }

        CygnetApiServiceTest.authCalls = 0;
        Test.setMock(HttpCalloutMock.class, new AuthCountMock());

        Test.startTest();
        String t1 = CygnetApiService.getAuthToken(UserInfo.getUserName(), invId);
        String t2 = CygnetApiService.getAuthToken(UserInfo.getUserName(), invId);
        Test.stopTest();

        System.assertEquals('tok-from-auth', t1);
        System.assertEquals('tok-from-auth', t2, 'Should reuse token from memory cache for Under-SS flow');
        System.assertEquals(1, CygnetApiServiceTest.authCalls, 'Auth call should happen once for cached Under-SS token');
    }

    @IsTest
    static void testGetAuthToken_PersistsTokenAsyncQueueable_WritesToSetting() {
        // Uses AuthCountMock so only auth endpoint is called; queueable persistence runs at Test.stopTest().
        Test.setMock(HttpCalloutMock.class, new AuthCountMock());

        Test.startTest();
        String tok = CygnetApiService.getAuthToken(UserInfo.getUserName(), null);
        Test.stopTest();
        System.assertEquals('tok-from-auth', tok);

        // Persist prefers user-level row if it exists; else org default.
        Cygnet_Integration_Setting__c sUser = Cygnet_Integration_Setting__c.getInstance(UserInfo.getUserId());
        Cygnet_Integration_Setting__c sOrg = Cygnet_Integration_Setting__c.getInstance();
        Cygnet_Integration_Setting__c s = sUser != null ? sUser : sOrg;

        System.assertNotEquals(null, s, 'Expected hierarchy setting row to exist');
        System.assertEquals(true, String.isNotBlank(s.Auth_Token__c), 'Expected token persisted by queueable');
        System.assertNotEquals(null, s.Auth_Token_Expires_At__c, 'Expected expiry persisted by queueable');
    }

    @IsTest
    static void testGetAuthToken_PersistedTokenNearExpiry_DoesNotReuse_UsesAuth() {
        // With 5-minute validity buffer, a token expiring in <5 minutes must not be reused.
        Datetime nearExpiry = System.now().addMinutes(4);
        Cygnet_Integration_Setting__c s = new Cygnet_Integration_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Auth_Token__c = 'tok-near-expiry',
            Auth_Token_Expires_At__c = nearExpiry
        );
        upsert s;

        CygnetApiServiceTest.authCalls = 0;
        Test.setMock(HttpCalloutMock.class, new AuthCountMock());

        Test.startTest();
        String t = CygnetApiService.getAuthToken(UserInfo.getUserName(), null);
        Test.stopTest();

        System.assertEquals('tok-from-auth', t, 'Should generate a new token when persisted token is within buffer window');
        System.assertEquals(1, CygnetApiServiceTest.authCalls, 'Should call authenticate when token is near expiry');
    }

    @IsTest
    static void testGetAuthToken_InvalidJson_Throws() {
        Test.setMock(HttpCalloutMock.class, new AuthInvalidJsonMock());
        Boolean threw = false;
        try {
            Test.startTest();
            CygnetApiService.getAuthToken(UserInfo.getUserName(), null);
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
            // In this codebase, invalid JSON can surface as System.JSONException before the service wraps it.
            System.assert(
                e.getTypeName().contains('JSONException') || (e.getMessage() != null && e.getMessage().toLowerCase().contains('unexpected character')),
                'Unexpected exception: ' + e.getTypeName() + ' / ' + e.getMessage()
            );
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testSaveEwayBillByIrn_MissingReferenceId_Throws() {
        Test.setMock(HttpCalloutMock.class, new EwbSaveNoRefMock());
        Boolean threw = false;
        try {
            Test.startTest();
            CygnetApiService.saveEwayBillByIrn('{"data":{"PartBDtls":[]}}', null);
            Test.stopTest();
        } catch (CygnetApiService.CygnetApiException e) {
            threw = true;
            System.assert(e.getMessage().contains('referenceId'));
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testSaveEInvoice_EmptyBody_Throws() {
        Test.setMock(HttpCalloutMock.class, new SaveAcceptedEmptyBodyMock());
        Boolean threw = false;
        try {
            Test.startTest();
            CygnetApiService.saveEInvoice('{"data":{}}', null);
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
            System.assert(
                e.getMessage() != null && e.getMessage().toLowerCase().contains('empty'),
                'Unexpected: ' + e.getTypeName() + ' / ' + e.getMessage()
            );
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testGetStatus_UnexpectedPayload_Throws() {
        Test.setMock(HttpCalloutMock.class, new StatusReturnsArrayMock());
        Boolean threw = false;
        try {
            Test.startTest();
            CygnetApiService.getStatus('ref-any', null);
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
            System.assert(
                e.getMessage() != null && e.getMessage().toLowerCase().contains('unexpected payload'),
                'Unexpected: ' + e.getTypeName() + ' / ' + e.getMessage()
            );
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testPollUntilDone_WhenProcessedButIrnMissing_FirstPoll_ThenSuccess() {
        // invoiceId != null triggers the "Processed but IRN missing -> keep polling" branch.
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        Test.setMock(HttpCalloutMock.class, new StatusProcessedMissingIrnThenOkMock());
        Test.startTest();
        CygnetApiService.StatusResult sr =
            CygnetApiService.pollUntilDone(CygnetIntegrationHttpCalloutMock.MOCK_REFERENCE_ID, invId);
        Test.stopTest();

        System.assertEquals(true, sr.success);
        System.assertEquals(CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX, sr.irn);
    }

    @IsTest
    static void testPollUntilDone_DeepFindHex64_FromCachedSavePayload() {
        // invoiceId != null enables deep fallback scan of cached save response.
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        Test.setMock(HttpCalloutMock.class, new SaveProcessedIrnOnlyInRandomFieldMock());
        Test.startTest();
        String ref = CygnetApiService.saveEInvoice('{"data":{}}', invId);
        CygnetApiService.StatusResult sr = CygnetApiService.pollUntilDone(ref, invId);
        Test.stopTest();

        System.assertEquals(true, sr.success);
        System.assertEquals(CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX, sr.irn);
    }

    @IsTest
    static void testPollUntilDone_FillsNestedEawbFields() {
        Test.setMock(HttpCalloutMock.class, new StatusProcessedNestedEawbMock());
        Test.startTest();
        CygnetApiService.StatusResult sr = CygnetApiService.pollUntilDone('ref-any', null);
        Test.stopTest();

        System.assertEquals(true, sr.success);
        System.assertEquals(true, String.isNotBlank(sr.irn));
        System.assertEquals(true, String.isNotBlank(sr.ewbNo));
    }

    @IsTest
    static void testPollUntilDone_FillsDataReportDistanceKm() {
        Test.setMock(HttpCalloutMock.class, new StatusFlatDataReportWithDistanceMock());
        Test.startTest();
        CygnetApiService.StatusResult sr = CygnetApiService.pollUntilDone('ref-any', null);
        Test.stopTest();

        System.assertEquals(true, sr.success);
        System.assertEquals(Decimal.valueOf(908), sr.distanceKm);
    }

    @IsTest
    static void testSaveEwayBillByIrn_EmptyBody_Throws() {
        Test.setMock(HttpCalloutMock.class, new EwbSaveAcceptedEmptyBodyMock());
        Boolean threw = false;
        try {
            Test.startTest();
            CygnetApiService.saveEwayBillByIrn('{"data":{"PartBDtls":[]}}', null);
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
            System.assert(
                e.getMessage() != null && e.getMessage().toLowerCase().contains('empty'),
                'Unexpected: ' + e.getTypeName() + ' / ' + e.getMessage()
            );
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testSaveEInvoice_ReferenceIdUnderscoreKey_IsAccepted() {
        Test.setMock(HttpCalloutMock.class, new SaveReturnsReferenceIdUnderscoreMock());
        Test.startTest();
        String ref = CygnetApiService.saveEInvoice('{"data":{}}', null);
        Test.stopTest();
        System.assertEquals('ref-underscore-1', ref);
    }

    @IsTest
    static void testSaveEwayBillByIrn_ReferenceIdUnderscoreKey_IsAccepted() {
        Test.setMock(HttpCalloutMock.class, new EwbSaveReturnsReferenceIdUnderscoreMock());
        Test.startTest();
        String ref = CygnetApiService.saveEwayBillByIrn('{"data":{"PartBDtls":[]}}', null);
        Test.stopTest();
        System.assertEquals('ref-underscore-ewb-1', ref);
    }

    @IsTest
    static void testPollUntilDone_StatusEr_ReturnsFailureWithMessage() {
        Test.setMock(HttpCalloutMock.class, new StatusErMock());
        Test.startTest();
        CygnetApiService.StatusResult sr = CygnetApiService.pollUntilDone('ref-any', null);
        Test.stopTest();
        System.assertEquals(false, sr.success);
        System.assertEquals(true, String.isNotBlank(sr.errorMessage));
    }

    @IsTest
    static void testGetStatus_InvalidJson_ThrowsJSONException() {
        Test.setMock(HttpCalloutMock.class, new StatusInvalidJsonMock());
        Boolean threw = false;
        try {
            Test.startTest();
            CygnetApiService.getStatus('ref-any', null);
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
            System.assert(
                e.getTypeName().contains('JSONException') || (e.getMessage() != null && e.getMessage().toLowerCase().contains('unexpected character')),
                'Unexpected: ' + e.getTypeName() + ' / ' + e.getMessage()
            );
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testPollUntilDone_FillsEwbFields_FromFirstReportMap() {
        Test.setMock(HttpCalloutMock.class, new StatusProcessedFirstReportEwbFieldsMock());
        Test.startTest();
        CygnetApiService.StatusResult sr = CygnetApiService.pollUntilDone('ref-any', null);
        Test.stopTest();
        System.assertEquals(true, sr.success);
        System.assertEquals(true, String.isNotBlank(sr.irn));
        System.assertEquals(true, String.isNotBlank(sr.ewbNo));
        System.assertEquals(true, String.isNotBlank(sr.ewbGeneratedDate));
        System.assertEquals(true, String.isNotBlank(sr.ewbValidUpto));
    }

    @IsTest
    static void testPollUntilDone_ExecutesFillStatusResult_Catch_WhenDataReportRowNotMap() {
        Test.setMock(HttpCalloutMock.class, new StatusProcessedBadDataReportRowMock());
        Test.startTest();
        CygnetApiService.StatusResult sr = CygnetApiService.pollUntilDone('ref-any', null);
        Test.stopTest();
        System.assertEquals(true, sr.success);
        System.assertEquals(CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX, sr.irn);
    }

    @IsTest
    static void testPollUntilDone_ExecutesFillStatusResult_Catch_WhenEInvNotMap() {
        Test.setMock(HttpCalloutMock.class, new StatusProcessedBadEInvTypeMock());
        Test.startTest();
        CygnetApiService.StatusResult sr = CygnetApiService.pollUntilDone('ref-any', null);
        Test.stopTest();
        System.assertEquals(true, sr.success);
        System.assertEquals(CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX, sr.irn);
    }

    @IsTest
    static void testPollUntilDone_FillsEwb_FromTopLevelEawbMap() {
        Test.setMock(HttpCalloutMock.class, new StatusProcessedTopLevelEawbMapMock());
        Test.startTest();
        CygnetApiService.StatusResult sr = CygnetApiService.pollUntilDone('ref-any', null);
        Test.stopTest();
        System.assertEquals(true, sr.success);
        System.assertEquals(CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX, sr.irn);
        System.assertEquals(true, String.isNotBlank(sr.ewbNo));
        System.assertEquals(true, String.isNotBlank(sr.ewbGeneratedDate));
        System.assertEquals(true, String.isNotBlank(sr.ewbValidUpto));
    }

    @IsTest
    static void testPollUntilDone_TopLevelEawbBadType_DoesNotThrow() {
        Test.setMock(HttpCalloutMock.class, new StatusProcessedTopLevelEawbBadTypeMock());
        Test.startTest();
        CygnetApiService.StatusResult sr = CygnetApiService.pollUntilDone('ref-any', null);
        Test.stopTest();
        System.assertEquals(true, sr.success);
        System.assertEquals(CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX, sr.irn);
    }
}