public class InvoiceLineItemsRetrieve implements Database.AllowsCallouts {

    // Kept identical to the previous implementation.
    private static final Integer CALLOUT_TIMEOUT_MS = 120000;

    /**
     * Retrieves archived Invoice Line Items from Azure for the given Invoice Ids.
     *
     * Behavior contract (used as a fallback by SecondaryInvoiceDownloaderCtl when
     * no Invoice_Line_Item__c records exist in Salesforce for an invoice):
     *   - Uses the existing Named Credential ("AzureArchiveRetrieval_NC") exactly
     *     as before - no endpoints/credentials are hardcoded here or added.
     *   - NEVER throws. Any callout failure, non-200 response, empty/missing
     *     "value" array, malformed JSON, or unparsable individual record is
     *     handled internally and simply results in fewer (possibly zero)
     *     records being returned, so PDF generation can continue gracefully.
     *   - Always returns a non-null list.
     */
    public static List<Invoice_Line_Item__c> retriveInvoiceLineItems(Set<Id> invoiceIds) {

        List<Invoice_Line_Item__c> lineItems = new List<Invoice_Line_Item__c>();

        // Avoid an unnecessary callout entirely if there is nothing to ask for.
        if (invoiceIds == null || invoiceIds.isEmpty()) {
            return lineItems;
        }

        List<String> filters = new List<String>();
        for (Id invoiceId : invoiceIds) {
            filters.add('invoice__c eq \'' + invoiceId + '\'');
        }
        String filter = String.join(filters, ' or ');

        HttpResponse res;
        try {
            String endpoint = 'callout:AzureArchiveRetrieval_NC/InvoiceLineItems?$filter=' + EncodingUtil.urlEncode(filter, 'UTF-8');

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(CALLOUT_TIMEOUT_MS);

            res = new Http().send(req);
        } catch (Exception calloutEx) {
            // Covers System.CalloutException (timeout, DNS failure, Named
            // Credential misconfiguration, connection refused, etc.) and any
            // other unexpected error while making the callout itself.
            System.debug(LoggingLevel.ERROR,
                'InvoiceLineItemsRetrieve: Azure callout failed for filter [' + filter + '] - ' + calloutEx.getMessage());
            return lineItems;
        }

        if (res == null || res.getStatusCode() != 200 || String.isBlank(res.getBody())) {
            System.debug(LoggingLevel.ERROR,
                'InvoiceLineItemsRetrieve: Unexpected Azure response. Status: '
                + (res != null ? String.valueOf(res.getStatusCode()) : 'null')
                + ' Body: ' + (res != null ? res.getBody() : 'null'));
            return lineItems;
        }

        try {
            Object parsed = JSON.deserializeUntyped(res.getBody());
            if (!(parsed instanceof Map<String, Object>)) {
                System.debug(LoggingLevel.ERROR, 'InvoiceLineItemsRetrieve: Unexpected Azure response shape (not a JSON object).');
                return lineItems;
            }

            Map<String, Object> root = (Map<String, Object>) parsed;
            Object valueObj = root.get('value');
            if (!(valueObj instanceof List<Object>)) {
                System.debug(LoggingLevel.WARN, 'InvoiceLineItemsRetrieve: Azure response contained no "value" array.');
                return lineItems;
            }

            List<Object> jsonList = (List<Object>) valueObj;

            for (Object obj : jsonList) {
                if (!(obj instanceof Map<String, Object>)) {
                    continue;
                }
                try {
                    Map<String, Object> itemMap = (Map<String, Object>) obj;

                    // Dynamically remove Azure/table-storage specific fields
                    // that don't map onto Invoice_Line_Item__c.
                    itemMap.remove('PartitionKey');
                    itemMap.remove('RowKey');
                    itemMap.remove('Timestamp');
                    itemMap.remove('attributes');
                    // These archived rows are used purely in-memory for PDF
                    // rendering and are never inserted/updated, so any "Id"
                    // echoed back by Azure (which will not be a valid
                    // Salesforce Id) must be stripped before deserializing
                    // onto the sObject, otherwise JSON.deserialize throws.
                    itemMap.remove('Id');

                    String cleanedJsonStr = JSON.serialize(itemMap);
                    Invoice_Line_Item__c lineItem = (Invoice_Line_Item__c) JSON.deserialize(cleanedJsonStr, Invoice_Line_Item__c.class);
                    lineItems.add(lineItem);
                } catch (Exception itemEx) {
                    // Skip a single malformed archived record rather than
                    // failing the whole batch/PDF.
                    System.debug(LoggingLevel.ERROR, 'InvoiceLineItemsRetrieve: Skipping unparsable line item - ' + itemEx.getMessage());
                }
            }
        } catch (Exception parseEx) {
            System.debug(LoggingLevel.ERROR, 'InvoiceLineItemsRetrieve: Failed to parse Azure response - ' + parseEx.getMessage());
            return new List<Invoice_Line_Item__c>();
        }

        return lineItems;
    }
}