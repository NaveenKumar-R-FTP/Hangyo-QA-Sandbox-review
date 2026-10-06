/**
 * Tells the DMS invoice screens whether the logged-in distributor's invoices are shown as
 * "Duplicate Invoice" (Account.Show_Duplicate_Invoice__c) - the same flag the invoice PDF uses.
 */
public with sharing class DmsInvoiceDisplayController {
    @AuraEnabled(cacheable=true)
    public static Boolean isDuplicateInvoice() {
        List<User> users = [
            SELECT Contact.Account.Show_Duplicate_Invoice__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return !users.isEmpty() && users[0].Contact?.Account?.Show_Duplicate_Invoice__c == true;
    }
}