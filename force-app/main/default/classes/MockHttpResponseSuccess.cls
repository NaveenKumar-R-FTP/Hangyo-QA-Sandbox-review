// Mock HTTP Success Response
@isTest
public class MockHttpResponseSuccess implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setBody('{"data": {"sap_reference": "SAP12345", "status": "Success", "message": "Order Created"}}');
        return res;
    }
}