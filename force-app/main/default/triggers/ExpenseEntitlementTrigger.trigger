/**
* Trigger Name    : ExpenseEntitlementTrigger
* Test Class Name : ExpenseEntitlementTriggerTest
* author          : Shyam
* CreatedDate     : 22-01-25
* Description     : This is to validate there should only one record per role.
* */
trigger ExpenseEntitlementTrigger on Expense_Entitlement__c (before insert) {
    // Collect all the roles and record types from the new records being inserted
    Set<String> roleKeys = new Set<String>();
    for (Expense_Entitlement__c entitlement : Trigger.new) {
        if (entitlement.Role__c != null && entitlement.RecordTypeId != null) {
            // Create a unique key using RecordTypeId and Role
            String key = entitlement.RecordTypeId + '-' + entitlement.Role__c.trim().toLowerCase();
            roleKeys.add(key);
        }
    }

    // Query to check if records with the same role and record type already exist
    Map<String, Expense_Entitlement__c> existingRecords = new Map<String, Expense_Entitlement__c>();
    for (Expense_Entitlement__c existing : [
        SELECT Id, Role__c, RecordTypeId 
        FROM Expense_Entitlement__c
        WHERE Role__c != null AND RecordTypeId != null
    ]) {
        String key = existing.RecordTypeId + '-' + existing.Role__c.trim().toLowerCase();
        existingRecords.put(key, existing);
    }

    // Loop through the new records and check for duplicate roles within the same record type
    for (Expense_Entitlement__c entitlement : Trigger.new) {
        if (entitlement.Role__c != null && entitlement.RecordTypeId != null) {
            String key = entitlement.RecordTypeId + '-' + entitlement.Role__c.trim().toLowerCase();
            if (existingRecords.containsKey(key)) {
                entitlement.addError('A record with this role already exists for the selected record type. Only one record per role per record type is allowed.');
            }
        }
    }
}