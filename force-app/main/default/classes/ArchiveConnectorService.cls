public class ArchiveConnectorService {

    public class SendResult {
        public Boolean success;
        public String archiveLocation;
        public String checksum;
        public String errorCode;
        public String errorMessage;
    }

    public static SendResult send(String objectName,List<SObject> records,Id batchId ) {
        String payload = buildCanonicalPayload(objectName, records, batchId);

        String checksum = 'sha256:' + EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(payload)));

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Archive_Endpoint/archive/records');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-Batch-Id', String.valueOf(batchId));
        req.setHeader('X-Checksum', checksum);
        req.setBody(payload);
        req.setTimeout(60000);

        try {
            HttpResponse res = new Http().send(req);
            return parseResponse(res, checksum);
        } catch (Exception e) {
            SendResult r = new SendResult();
            r.success = false;
            r.errorCode = 'CALLOUT_EXCEPTION';
            r.errorMessage = e.getMessage();
            r.checksum = checksum;
            return r;
        }
    }

    /**
     * Builds the JSON payload sent to the archive service.
     *
     * Uses JSON.serialize rather than manually concatenating JSON,
     * which prevents malformed JSON when field values contain quotes,
     * newlines, etc.
     */
    private static String buildCanonicalPayload(String objectName,List<SObject> records,Id batchId) {
        if (String.isBlank(objectName)) {
            throw new IllegalArgumentException('objectName is required');
        }

        if (records == null) {
            records = new List<SObject>();
        }

        Map<String, Object> payload = new Map<String, Object>();

        payload.put('objectName', objectName);
        payload.put('batchId', String.valueOf(batchId));
        payload.put('recordCount', records.size());

        List<Object> serializedRecords = new List<Object>();

        for (SObject record : records) {
            serializedRecords.add(record);
        }

        payload.put('records', serializedRecords);

        return JSON.serialize(payload);
    }

    /**
     * Parses the archive service response.
     */
    private static SendResult parseResponse(
        HttpResponse res,
        String requestChecksum
    ) {
        SendResult result = new SendResult();

        if (res == null) {
            result.success = false;
            result.errorCode = 'NULL_RESPONSE';
            result.errorMessage = 'Archive service returned no response';
            result.checksum = requestChecksum;
            return result;
        }

        Integer statusCode = res.getStatusCode();
        String responseBody = res.getBody();

        if (statusCode >= 200 && statusCode < 300) {
            try {
                Map<String, Object> response =
                    (Map<String, Object>) JSON.deserializeUntyped(responseBody);

                result.success = response.containsKey('success')
                    ? (Boolean) response.get('success')
                    : true;

                if (response.containsKey('archiveLocation')) {
                    result.archiveLocation =
                        (String) response.get('archiveLocation');
                }

                if (response.containsKey('checksum')) {
                    result.checksum =
                        (String) response.get('checksum');
                } else {
                    result.checksum = requestChecksum;
                }

                if (response.containsKey('errorCode')) {
                    result.errorCode =
                        (String) response.get('errorCode');
                }

                if (response.containsKey('errorMessage')) {
                    result.errorMessage =
                        (String) response.get('errorMessage');
                }

            } catch (Exception e) {
                result.success = false;
                result.errorCode = 'INVALID_RESPONSE';
                result.errorMessage =
                    'Unable to parse archive response: ' + e.getMessage();
                result.checksum = requestChecksum;
            }

            return result;
        }

        // Non-2xx response
        result.success = false;
        result.checksum = requestChecksum;
        result.errorCode = 'ARCHIVE_HTTP_' + String.valueOf(statusCode);

        if (String.isNotBlank(responseBody)) {
            result.errorMessage = responseBody;
        } else {
            result.errorMessage = res.getStatus();
        }

        return result;
    }
}