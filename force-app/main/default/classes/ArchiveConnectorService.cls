public class ArchiveConnectorService {

    public class SendResult {
        public Boolean success;
        public String archiveLocation;
        public String checksum;
        public String errorCode;
        public String errorMessage;
        public List<String> archivedIds;
    }

    public static SendResult send(String objectName, List<SObject> records, Id batchId) {
        Map<String, Object> payloadMap = buildCanonicalPayloadMap(objectName, records, batchId);

        List<Map<String, Object>> rawRecords = (List<Map<String, Object>>) payloadMap.get('__rawRecords');
        String checksum = ArchivalChecksumBuilder.buildChecksum(rawRecords);
        System.debug('checksum: ' + checksum);

        // Embed checksum into payload for the outgoing request body (unchanged shape)
        payloadMap.remove('__rawRecords');
        payloadMap.put('checksum', checksum);
        SortedKeyMap sortedPayload = sortMapKeys(payloadMap);
        String payload = writeSortedJson(sortedPayload);       
        System.debug('OUTGOING_PAYLOAD: ' + payload);
        
        String endpointUrl = resolveEndpoint(objectName);

        HttpRequest req = new HttpRequest();
        //req.setEndpoint('callout:AzureDataArchive_NC/archive/OrderLineItems');
        req.setEndpoint(endpointUrl);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-Batch-Id', String.valueOf(batchId));
        req.setHeader('checksum', checksum);
        req.setBody(payload);
        req.setTimeout(120000);

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
    
    private static String resolveEndpoint(String objectName) {
        if (String.isBlank(objectName)) {
            throw new IllegalArgumentException('objectName is required');
        }
    
        String namedCredential = 'AzureDataArchive_NC';
        String path;
    
        if (objectName == 'Order_Line_Item__c') {
            path = 'archive/OrderLineItems';
        } else if (objectName == 'Invoice_Line_Item__c') {
            path = 'archive/InvoiceLineItems';
        } else if (objectName == 'Visit_Task__c') {
            path = 'archive/VisitTasks';
        } else if (objectName == 'Inventory_Adjustment__c') {
            path = 'archive/InventoryAdjustments';
        } else if (objectName == 'Attendance__c') {
            path = 'archive/Attendance';
        } else {
            System.debug('No archive endpoint configured for object: ' + objectName);
            throw new IllegalArgumentException('No archive endpoint configured for object: ' + objectName);
        }
    
        return 'callout:' + namedCredential + '/' + path;
    }

    private static Map<String, Object> buildCanonicalPayloadMap(String objectName, List<SObject> records, Id batchId) {
        if (String.isBlank(objectName)) {
            throw new IllegalArgumentException('objectName is required');
        }

        if (records == null) {
            records = new List<SObject>();
        }

        Set<String> allFieldNames = getAllFieldNames(objectName);
        Set<String> excludeFields = new Set<String>{
            'LastActivityDate', 'LastReferencedDate', 'LastViewedDate', 'RecordVisibilityId', 'UserRecordAccessId'
        };
        allFieldNames.removeAll(excludeFields);
        
        Boolean lowercaseKeys = (objectName != 'Order_Line_Item__c');

        List<Map<String, Object>> rawRecords = new List<Map<String, Object>>();
        List<SortedKeyMap> sortedRecords = new List<SortedKeyMap>();
        for (SObject record : records) {
            //Map<String, Object> fieldsMap = getAllFieldsAsMap(record, allFieldNames);
            Map<String, Object> fieldsMap = getAllFieldsAsMap(record, allFieldNames, lowercaseKeys);
            rawRecords.add(fieldsMap);
            sortedRecords.add(sortMapKeys(fieldsMap));
        }

        Map<String, Object> payload = new Map<String, Object>();
        payload.put('objectName', objectName);
        payload.put('batchId', String.valueOf(batchId));
        payload.put('recordCount', records.size());
        payload.put('records', sortedRecords);
        payload.put('__rawRecords', rawRecords);

        return payload;
    }

    private static Set<String> getAllFieldNames(String objectName) {
        Set<String> fieldNames = new Set<String>();

        Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectName);
        if (sObjType == null) {
            throw new IllegalArgumentException('Unknown object type: ' + objectName);
        }

        Map<String, Schema.SObjectField> fieldMap = sObjType.getDescribe().fields.getMap();
        for (Schema.SObjectField sObjField : fieldMap.values()) {
            fieldNames.add(sObjField.getDescribe().getName());
        }

        return fieldNames;
    }
    
    private static Map<String, Object> getAllFieldsAsMap(SObject record, Set<String> allFieldNames, Boolean lowercaseKeys) {
        Map<String, Object> result = new Map<String, Object>();
    
        for (String fieldName : allFieldNames) {
            String outputKey = lowercaseKeys ? fieldName.toLowerCase() : fieldName;
            try {
                result.put(outputKey, record.get(fieldName));
            } catch (Exception e) {
                result.put(outputKey, null);
            }
        }
    
        return result;
    }

    /*private static Map<String, Object> getAllFieldsAsMap(SObject record, Set<String> allFieldNames) {
        Map<String, Object> result = new Map<String, Object>();

        for (String fieldName : allFieldNames) {
            try {
                result.put(fieldName, record.get(fieldName));
            } catch (Exception e) {
                result.put(fieldName, null);
            }
        }

        return result;
    }*/

    private class SortedKeyMap {
        Map<String, Object> data;
        List<String> orderedKeys;

        SortedKeyMap(Map<String, Object> data, List<String> orderedKeys) {
            this.data = data;
            this.orderedKeys = orderedKeys;
        }

        Object get(String key) {
            return data.get(key);
        }
    }

    private static SortedKeyMap sortMapKeys(Map<String, Object> input) {
        if (input == null) {
            return null;
        }
        List<String> sortedKeys = new List<String>(input.keySet());
        sortedKeys.sort();

        Map<String, Object> result = new Map<String, Object>();
        for (String key : sortedKeys) {
            Object val = input.get(key);
            if (val instanceof Map<String, Object>) {
                result.put(key, sortMapKeys((Map<String, Object>) val));
            } else {
                result.put(key, val);
            }
        }

        return new SortedKeyMap(result, sortedKeys);
    }

    private static String writeSortedJson(Object value) {
        JSONGenerator gen = JSON.createGenerator(false);
        writeValue(gen, value);
        return gen.getAsString();
    }

    private static void writeValue(JSONGenerator gen, Object value) {
        if (value == null) {
            gen.writeNull();
        } else if (value instanceof SortedKeyMap) {
            SortedKeyMap m = (SortedKeyMap) value;
            gen.writeStartObject();
            for (String key : m.orderedKeys) {
                gen.writeFieldName(key);
                writeValue(gen, m.get(key));
            }
            gen.writeEndObject();
        } else if (value instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) value;
            List<String> keys = new List<String>(m.keySet());
            keys.sort();
            gen.writeStartObject();
            for (String key : keys) {
                gen.writeFieldName(key);
                writeValue(gen, m.get(key));
            }
            gen.writeEndObject();
        } else if (value instanceof List<Object>) {
            gen.writeStartArray();
            for (Object item : (List<Object>) value) {
                writeValue(gen, item);
            }
            gen.writeEndArray();
        } else if (value instanceof Integer) {
            gen.writeNumber((Integer) value);
        } else if (value instanceof Long) {
            gen.writeNumber((Long) value);
        } else if (value instanceof Decimal) {
            gen.writeNumber((Decimal) value);
        } else if (value instanceof Double) {
            gen.writeNumber((Double) value);
        } else if (value instanceof Boolean) {
            gen.writeBoolean((Boolean) value);
        } else if (value instanceof Date) {
            gen.writeString(String.valueOf((Date) value));
        } else if (value instanceof Datetime) {
            gen.writeString(((Datetime) value).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''));
        } else {
            gen.writeString(String.valueOf(value));
        }
    }

    private static SendResult parseResponse(HttpResponse res, String requestChecksum) {
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
                Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(responseBody);

                result.success = response.containsKey('success')?(Boolean) response.get('success'):true;

                if (response.containsKey('archiveLocation')) {
                    result.archiveLocation = (String) response.get('archiveLocation');
                }

                if (response.containsKey('checksum')) {
                    result.checksum = (String) response.get('checksum');
                } else {
                    result.checksum = requestChecksum;
                }

                if (response.containsKey('errorCode')) {
                    result.errorCode = (String) response.get('errorCode');
                }

                if (response.containsKey('errorMessage')) {
                    result.errorMessage = (String) response.get('errorMessage');
                }
                if (response.containsKey('archivedIds')) {
                    //result.archivedIds = (list<String>)response.get('archivedIds'); 
                    List<Object> rawArchivedIds = (List<Object>) response.get('archivedIds');
                    List<String> archivedIds = new List<String>();
                    if (rawArchivedIds != null) {
                        for (Object idVal : rawArchivedIds) {
                            if (idVal != null) {
                                archivedIds.add(String.valueOf(idVal));
                            }
                        }
                    }
                    result.archivedIds = archivedIds;                   
                }

            } catch (Exception e) {
                result.success = false;
                result.errorCode = 'INVALID_RESPONSE';
                result.errorMessage = 'Unable to parse archive response: ' + e.getMessage();
                result.checksum = requestChecksum;
            }
            return result;
        }
        
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