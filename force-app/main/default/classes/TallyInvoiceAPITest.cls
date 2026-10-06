/**
 * @description Unit tests for TallyInvoiceAPI REST endpoint.
 */
@isTest
private class TallyInvoiceAPITest {
    @testSetup
    static void setupData() {
        TallyInvoiceTestDataFactory.createInvoiceWithLineItem(
            TallyInvoiceTestDataFactory.ALLOWED_OWNER_ID,
            Date.today()
        );
    }

    /**
     * @description Sets a deterministic whitelist row tied to the CURRENT
     *              running user via Integration_User_Id__c, so tests never
     *              depend on live org CMDT data matching whoever runs them.
     */
    private static void setDeterministicAllowedUser() {
        Map<String, Tally_Allowed_User__mdt> testRecords =
            new Map<String, Tally_Allowed_User__mdt>();
        testRecords.put(
            'TestRunUser',
            new Tally_Allowed_User__mdt(
                Is_Active__c = 'True',
                User_Id__c = String.valueOf(TallyInvoiceTestDataFactory.ALLOWED_OWNER_ID),
                Integration_User_Id__c = String.valueOf(UserInfo.getUserId())
            )
        );
        TallyAllowedUserService.testMetadataOverride = testRecords;
    }

    private static void resetAllowedUser() {
        TallyAllowedUserService.testMetadataOverride = null;
    }

    @isTest
    static void getInvoices_returnsSuccessWithInvoices() {
        setDeterministicAllowedUser();
        setRestContext(null, null, null);

        Test.startTest();
        TallyInvoiceAPI.getInvoices();
        Test.stopTest();

        resetAllowedUser();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(
            'application/json',
            RestContext.response.headers.get('Content-Type')
        );

        TallyInvoiceResponseWrapper body = parseResponse();
        System.assertEquals(true, body.success);
        System.assertEquals('Invoices retrieved successfully.', body.message);
        System.assert(body.invoices.size() >= 1, 'Expected at least one invoice');
    }

    @isTest
    static void getInvoices_appliesDateFilters() {
        setDeterministicAllowedUser();
        setRestContext(String.valueOf(Date.today()), String.valueOf(Date.today()), null);

        Test.startTest();
        TallyInvoiceAPI.getInvoices();
        Test.stopTest();

        resetAllowedUser();

        System.assertEquals(200, RestContext.response.statusCode);
        TallyInvoiceResponseWrapper body = parseResponse();
        System.assertEquals(true, body.success);
        System.assert(body.invoices.size() >= 1, 'Date filter should include today invoice');
    }

    @isTest
    static void getInvoices_returns500OnInvalidDate() {
        setDeterministicAllowedUser();
        setRestContext('INVALID-DATE', null, null);

        Test.startTest();
        TallyInvoiceAPI.getInvoices();
        Test.stopTest();

        resetAllowedUser();

        System.assertEquals(500, RestContext.response.statusCode);
        TallyInvoiceResponseWrapper body = parseResponse();
        System.assertEquals(false, body.success);
        System.assertNotEquals(null, body.message);
        System.assertEquals(0, body.invoices.size());
    }

    @isTest
    static void getInvoices_handlesBlankDateParams() {
        setDeterministicAllowedUser();
        setRestContext('', '', null);

        Test.startTest();
        TallyInvoiceAPI.getInvoices();
        Test.stopTest();

        resetAllowedUser();

        System.assertEquals(200, RestContext.response.statusCode);
        TallyInvoiceResponseWrapper body = parseResponse();
        System.assertEquals(true, body.success);
    }

    @isTest
    static void getInvoices_returnsMessageWhenNoAllowedUsersConfigured() {
        TallyInvoiceAPI.testForceEmptyAllowedUsers = true;
        setRestContext(null, null, null);

        Test.startTest();
        TallyInvoiceAPI.getInvoices();
        Test.stopTest();

        TallyInvoiceAPI.testForceEmptyAllowedUsers = false;

        System.assertEquals(200, RestContext.response.statusCode);
        TallyInvoiceResponseWrapper body = parseResponse();
        System.assertEquals(true, body.success);
        System.assertEquals('No allowed users configured.', body.message);
        System.assertEquals(0, body.invoices.size());
    }

    @isTest
    static void getInvoices_returnsEmptyListWhenDateOutOfRange() {
        setDeterministicAllowedUser();
        setRestContext(
            String.valueOf(Date.today().addDays(-60)),
            String.valueOf(Date.today().addDays(-30)),
            null
        );

        Test.startTest();
        TallyInvoiceAPI.getInvoices();
        Test.stopTest();

        resetAllowedUser();

        System.assertEquals(200, RestContext.response.statusCode);
        TallyInvoiceResponseWrapper body = parseResponse();
        System.assertEquals(true, body.success);
        System.assertEquals('Invoices retrieved successfully.', body.message);
        System.assertEquals(0, body.invoices.size());
    }

    @isTest
    static void getInvoices_parsesTrimmedDateParams() {
        setDeterministicAllowedUser();
        setRestContext(' ' + String.valueOf(Date.today()) + ' ', null, null);

        Test.startTest();
        TallyInvoiceAPI.getInvoices();
        Test.stopTest();

        resetAllowedUser();

        System.assertEquals(200, RestContext.response.statusCode);
        TallyInvoiceResponseWrapper body = parseResponse();
        System.assertEquals(true, body.success);
        System.assert(body.invoices.size() >= 1, 'Trimmed date param should match today invoice');
    }

    @isTest
    static void getInvoices_usesCustomerApiKeyParamWhenPresent() {
        // Query-param-based path: made visible ONLY via a Customer_Api_Key__c
        // match, with no Integration_User_Id__c set at all. Confirms the new
        // path works independently of the original Run-As User check.
        // Uses a query param (not a header) — Apex REST's RestRequest.headers
        // does not reliably expose custom headers from external clients.
        Map<String, Tally_Allowed_User__mdt> testRecords =
            new Map<String, Tally_Allowed_User__mdt>();
        testRecords.put(
            'ParamCustomer',
            new Tally_Allowed_User__mdt(
                Is_Active__c = 'True',
                User_Id__c = String.valueOf(TallyInvoiceTestDataFactory.ALLOWED_OWNER_ID),
                Customer_Api_Key__c = 'test-secret-key-12345'
            )
        );
        TallyAllowedUserService.testMetadataOverride = testRecords;

        setRestContext(null, null, 'test-secret-key-12345');

        Test.startTest();
        TallyInvoiceAPI.getInvoices();
        Test.stopTest();

        resetAllowedUser();

        System.assertEquals(200, RestContext.response.statusCode);
        TallyInvoiceResponseWrapper body = parseResponse();
        System.assertEquals(true, body.success);
        System.assert(
            body.invoices.size() >= 1,
            'Expected invoices for the owner matched via Customer_Api_Key__c param'
        );
    }

    @isTest
    static void getInvoices_ignoresWrongCustomerApiKeyParam() {
        // A param value that matches no row must behave like no allowed users.
        Map<String, Tally_Allowed_User__mdt> testRecords =
            new Map<String, Tally_Allowed_User__mdt>();
        testRecords.put(
            'ParamCustomer',
            new Tally_Allowed_User__mdt(
                Is_Active__c = 'True',
                User_Id__c = String.valueOf(TallyInvoiceTestDataFactory.ALLOWED_OWNER_ID),
                Customer_Api_Key__c = 'the-real-key'
            )
        );
        TallyAllowedUserService.testMetadataOverride = testRecords;

        setRestContext(null, null, 'wrong-key-entirely');

        Test.startTest();
        TallyInvoiceAPI.getInvoices();
        Test.stopTest();

        resetAllowedUser();

        System.assertEquals(200, RestContext.response.statusCode);
        TallyInvoiceResponseWrapper body = parseResponse();
        System.assertEquals(true, body.success);
        System.assertEquals(
            'No allowed users configured.',
            body.message,
            'A non-matching customer key must return no invoices, not another customer\'s data'
        );
    }

    private static void setRestContext(String fromDate, String toDate, String customerKey) {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/TallyInvoiceData/';
        req.httpMethod = 'GET';

        if (fromDate != null) {
            req.addParameter('fromDate', fromDate);
        }
        if (toDate != null) {
            req.addParameter('toDate', toDate);
        }
        if (customerKey != null) {
            req.addParameter('customerKey', customerKey);
        }

        RestContext.request = req;
        RestContext.response = res;
    }

    private static TallyInvoiceResponseWrapper parseResponse() {
        return (TallyInvoiceResponseWrapper) JSON.deserialize(
            RestContext.response.responseBody.toString(),
            TallyInvoiceResponseWrapper.class
        );
    }
}