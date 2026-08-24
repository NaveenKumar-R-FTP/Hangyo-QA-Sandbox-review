/**
 * @description Apex REST entry point for the Tally pull-based Invoice API.
 *              Orchestrates allowed-user lookup, invoice query, and mapping.
 */
@RestResource(urlMapping='/TallyInvoiceData/*')
global with sharing class TallyInvoiceAPI {
    private static final String CONTENT_TYPE_JSON = 'application/json';
    private static final String PARAM_FROM_DATE = 'fromDate';
    private static final String PARAM_TO_DATE = 'toDate';

    /**
     * @description GET /services/apexrest/TallyInvoiceData/
     *              Returns invoices for configured allowed users.
     */
    @HttpGet
    global static void getInvoices() {
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', CONTENT_TYPE_JSON);

        try {
            RestRequest req = RestContext.request;
            Date fromDate = parseDateParam(req.params.get(PARAM_FROM_DATE));
            Date toDate = parseDateParam(req.params.get(PARAM_TO_DATE));

            Set<Id> allowedUserIds = TallyAllowedUserService.getAllowedUserIds();

            TallyInvoiceResponseWrapper response = new TallyInvoiceResponseWrapper();
            response.invoices = new List<TallyInvoiceResponseWrapper.InvoiceWrapper>();

            if (allowedUserIds.isEmpty()) {
                response.success = true;
                response.message = 'No allowed users configured.';
                writeResponse(res, 200, response);
                return;
            }

            List<Invoice__c> invoices = TallyInvoiceQueryService.getInvoices(
                allowedUserIds,
                fromDate,
                toDate
            );

            response.success = true;
            response.message = 'Invoices retrieved successfully.';
            response.invoices = TallyInvoiceMapper.mapInvoices(invoices);
            writeResponse(res, 200, response);
        } catch (Exception e) {
            TallyInvoiceResponseWrapper errorResponse = new TallyInvoiceResponseWrapper();
            errorResponse.success = false;
            errorResponse.message = e.getMessage();
            errorResponse.invoices = new List<TallyInvoiceResponseWrapper.InvoiceWrapper>();
            writeResponse(res, 500, errorResponse);
        }
    }

    /**
     * @description Parses an optional YYYY-MM-DD query parameter.
     * @param dateValue Raw query string value
     * @return Parsed Date, or null when blank
     */
    private static Date parseDateParam(String dateValue) {
        if (String.isBlank(dateValue)) {
            return null;
        }
        return Date.valueOf(dateValue.trim());
    }

    /**
     * @description Writes the serialized wrapper to the REST response.
     */
    private static void writeResponse(
        RestResponse res,
        Integer statusCode,
        TallyInvoiceResponseWrapper response
    ) {
        res.statusCode = statusCode;
        res.responseBody = Blob.valueOf(JSON.serialize(response));
    }
}