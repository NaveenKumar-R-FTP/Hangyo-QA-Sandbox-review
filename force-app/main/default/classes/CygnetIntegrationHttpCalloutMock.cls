/**
 * HttpCalloutMock for CygnetApiService tests. Does not change production integration behavior.
 */
public class CygnetIntegrationHttpCalloutMock implements HttpCalloutMock {
    public static final String MOCK_IRN_HEX =
        'bee02120ceceb2a04932fcbbf14425ed4861b12a051342d093ef06362ae82e8d';
    public static final String MOCK_REFERENCE_ID = 'ref-mock-001';

    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        String ep = req.getEndpoint() != null ? req.getEndpoint() : '';

        if (ep.contains('/authenticate/token')) {
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"token":"tok123456789012345678901234567890"}');
            return res;
        }
        if (ep.contains('/document/einvoiceCompliant/save')) {
            res.setStatusCode(202);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{"referenceId":"'
                    + MOCK_REFERENCE_ID
                    + '","status":"P","dataReport":[{"eInv":{"irn":"'
                    + MOCK_IRN_HEX
                    + '","ackNumber":"123456789012345678","signedInvoice":"sig","signedQRCode":"qr","qrCodeData":"qd"}}]}'
            );
            return res;
        }
        if (ep.contains('/document/ewaybillByIrnCompliant/save')) {
            res.setStatusCode(202);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"referenceId":"' + MOCK_REFERENCE_ID + '-ewb"}');
            return res;
        }
        if (ep.contains('/reference/status')) {
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{"status":"P","dataReport":[{"irn":"'
                    + MOCK_IRN_HEX
                    + '","ewayBillNumber":"123456789012345678","eInv":{"irn":"'
                    + MOCK_IRN_HEX
                    + '","ewayBillNo":"123456789012345678"},"generatedDate":"03-04-2026","validUpto":"04-04-2026"}]}'
            );
            return res;
        }
        if (ep.contains('/eInvoice/exportPdf')) {
            res.setStatusCode(200);
            res.setBodyAsBlob(Blob.valueOf('%PDF-1.4 mock'));
            return res;
        }
        if (ep.contains('/ewaybill/exportPdf')) {
            res.setStatusCode(200);
            res.setBodyAsBlob(Blob.valueOf('%PDF-1.4 mock'));
            return res;
        }

        res.setStatusCode(500);
        res.setBody('{"error":"unexpected endpoint in mock: ' + ep + '"}');
        return res;
    }
}