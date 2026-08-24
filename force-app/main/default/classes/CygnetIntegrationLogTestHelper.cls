/**
 * Test-only helper to assert Integration_Log__c rows (org must include Integration_Log__c).
 * Referenced from *Test classes only.
 */
public class CygnetIntegrationLogTestHelper {
    public static Integer countLogsForInvoice(Id invoiceId) {
        if (invoiceId == null || !Schema.getGlobalDescribe().containsKey('Integration_Log__c')) {
            return 0;
        }
        return [
            SELECT COUNT()
            FROM Integration_Log__c
            WHERE Record_Id__c = :String.valueOf(invoiceId)
        ];
    }
}