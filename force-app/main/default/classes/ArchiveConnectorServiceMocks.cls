@isTest
public class ArchiveConnectorServiceMocks {

    // Successful response including archivedIds matching the records sent.
    public class SuccessMock implements HttpCalloutMock {
        private List<String> archivedIds;
        private String archiveLocation;
        private String checksum;

        public SuccessMock(List<String> archivedIds) {
            this.archivedIds = archivedIds;
            this.archiveLocation = 'azure://archive/container/batch-001';
            this.checksum = 'sha256:mockChecksumValue';
        }

        public HttpResponse respond(HttpRequest req) {
            Map<String, Object> body = new Map<String, Object>{
                'success' => true,
                'archiveLocation' => archiveLocation,
                'checksum' => checksum,
                'archivedIds' => archivedIds
            };
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');
            res.setHeader('Content-Type', 'application/json');
            res.setBody(JSON.serialize(body));
            return res;
        }
    }

    // Success=false in body but HTTP 200.
    public class LogicalFailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            Map<String, Object> body = new Map<String, Object>{
                'success' => false,
                'errorCode' => 'VALIDATION_FAILED',
                'errorMessage' => 'Checksum mismatch detected'
            };
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');
            res.setHeader('Content-Type', 'application/json');
            res.setBody(JSON.serialize(body));
            return res;
        }
    }

    // HTTP-level error status code (e.g. 500).
    public class HttpErrorMock implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;

        public HttpErrorMock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setStatus('Internal Server Error');
            if (String.isNotBlank(responseBody)) {
                res.setBody(responseBody);
            }
            return res;
        }
    }

    // Malformed JSON body with a 200 status - triggers INVALID_RESPONSE path.
    public class MalformedJsonMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');
            res.setBody('{not valid json');
            return res;
        }
    }

    // Simulates a callout exception (e.g. timeout / unreachable endpoint).
    public class ExceptionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Simulated callout failure: connection timed out');
        }
    }

    // Success response missing the optional 'success' key entirely (defaults true per service logic).
    public class MissingSuccessKeyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            Map<String, Object> body = new Map<String, Object>{
                'archiveLocation' => 'azure://archive/default',
                'archivedIds' => new List<String>()
            };
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');
            res.setBody(JSON.serialize(body));
            return res;
        }
    }

    // Response with no checksum key - service should fall back to requestChecksum.
    public class NoChecksumInResponseMock implements HttpCalloutMock {
        private List<String> archivedIds;

        public NoChecksumInResponseMock(List<String> archivedIds) {
            this.archivedIds = archivedIds;
        }

        public HttpResponse respond(HttpRequest req) {
            Map<String, Object> body = new Map<String, Object>{
                'success' => true,
                'archiveLocation' => 'azure://archive/no-checksum',
                'archivedIds' => archivedIds
            };
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');
            res.setBody(JSON.serialize(body));
            return res;
        }
    }
}