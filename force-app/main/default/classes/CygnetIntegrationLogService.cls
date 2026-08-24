/**
 * Failure-only integration logging to Integration_Log__c.
 * Swallows all exceptions so Cygnet callout/DML flows behave exactly as before.
 */
public with sharing class CygnetIntegrationLogService {
    private static final Integer MAX_LONG = 131072;
    private static final Integer MAX_NAME = 80;

    /**
     * @param invoiceId Related Invoice (Record_Id__c)
     * @param errorMessage Human-readable error (Error_Message__c)
     * @param requestBody Outbound payload if available (Request__c)
     * @param responseBody API/status payload if available (Response__c)
     * @param source Short label for Name (e.g. E-Invoice Queueable)
     */
    public static void logFailure(
        Id invoiceId,
        String errorMessage,
        String requestBody,
        String responseBody,
        String source
    ) {
        try {
            if (!Schema.getGlobalDescribe().containsKey('Integration_Log__c')) {
                return;
            }
            Schema.SObjectType logType = Schema.getGlobalDescribe().get('Integration_Log__c');
            SObject row = logType.newSObject();

            String name = 'Cygnet ' + (String.isNotBlank(source) ? source : 'Integration');
            if (invoiceId != null) {
                String idStr = String.valueOf(invoiceId);
                name += ' ' + (idStr.length() > 5 ? idStr.substring(0, 5) : idStr);
            }
            name += ' ' + String.valueOf(Datetime.now());
            putIfCreateable(row, 'Name', truncate(name, MAX_NAME));

            if (invoiceId != null) {
                putIfCreateable(row, 'Record_Id__c', String.valueOf(invoiceId));
            }
            putIfCreateable(row, 'Error_Message__c', truncate(errorMessage, MAX_LONG));
            putIfCreateable(row, 'Request__c', truncate(requestBody, MAX_LONG));
            putIfCreateable(row, 'Response__c', truncate(responseBody, MAX_LONG));
            putErrorStatusIfPossible(row, logType);

            insert row;
        } catch (Exception ignore) {
            // Never break integration flow
        }
    }

    private static void putIfCreateable(SObject row, String fieldApi, String val) {
        if (row == null || String.isBlank(fieldApi)) {
            return;
        }
        Map<String, Schema.SObjectField> fm = row.getSObjectType().getDescribe().fields.getMap();
        if (!fm.containsKey(fieldApi.toLowerCase())) {
            return;
        }
        Schema.DescribeFieldResult d = fm.get(fieldApi.toLowerCase()).getDescribe();
        if (!d.isCreateable() || d.isCalculated()) {
            return;
        }
        row.put(fieldApi, val);
    }

    private static void putErrorStatusIfPossible(SObject row, Schema.SObjectType logType) {
        Map<String, Schema.SObjectField> fm = logType.getDescribe().fields.getMap();
        if (!fm.containsKey('status__c')) {
            return;
        }
        Schema.DescribeFieldResult d = fm.get('status__c').getDescribe();
        if (!d.isCreateable() || d.getType() != Schema.DisplayType.Picklist) {
            return;
        }
        for (Schema.PicklistEntry pe : d.getPicklistValues()) {
            if (pe == null || !pe.isActive()) {
                continue;
            }
            String v = pe.getValue();
            String lab = pe.getLabel();
            if ((v != null && v.toLowerCase().contains('error'))
                || (lab != null && lab.toLowerCase().contains('error'))
                || (v != null && v.toLowerCase().contains('fail'))) {
                row.put('Status__c', v);
                return;
            }
        }
        for (Schema.PicklistEntry pe : d.getPicklistValues()) {
            if (pe != null && pe.isActive()) {
                row.put('Status__c', pe.getValue());
                return;
            }
        }
    }

    private static String truncate(String s, Integer maxLen) {
        if (s == null) {
            return null;
        }
        if (maxLen == null || maxLen <= 0) {
            return s;
        }
        return s.length() > maxLen ? s.substring(0, maxLen) : s;
    }
}