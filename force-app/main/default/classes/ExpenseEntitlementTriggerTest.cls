/**
* Test Class Name : ExpenseEntitlementTriggerTest
* Trigger Name    : ExpenseEntitlementTrigger
* author          : Shyam
* CreatedDate     : 23-01-25
* Description     : Test class for "ExpenseEntitlementTrigger".
* */
@isTest
public class ExpenseEntitlementTriggerTest {

    @isTest
    static void testDuplicateRoleAndRecordType() {
        // Step 1: Query an existing Record Type
        RecordType expenseRecordType = [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = 'Expense_Entitlement__c' 
            AND DeveloperName = 'Daily_Allowance' 
            LIMIT 1
        ];

        // Step 2: Create a valid Expense_Entitlement__c record
        Expense_Entitlement__c entitlement1 = new Expense_Entitlement__c(
            Role__c = 'SSO',
            RecordTypeId = expenseRecordType.Id
        );
        insert entitlement1;

        // Step 3: Try to insert a duplicate record with the same Role__c and RecordTypeId
        Expense_Entitlement__c entitlement2 = new Expense_Entitlement__c(
            Role__c = 'SSO',  // Same Role__c
            RecordTypeId = expenseRecordType.Id  // Same RecordTypeId
        );

        // Step 4: Assert that the insert fails with the proper error message
        Test.startTest();
        try {
            insert entitlement2;
            System.assert(false, 'Expected a DML exception due to duplicate role and record type.');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('A record with this role already exists for the selected record type.'),
                'Error message does not match expected output.'
            );
        }
        Test.stopTest();
    }

    @isTest
    static void testValidInsertion() {
        // Step 1: Query an existing Record Type
        RecordType expenseRecordType = [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = 'Expense_Entitlement__c' 
            AND DeveloperName = 'Daily_Allowance' 
            LIMIT 1
        ];

        // Step 2: Create two valid Expense_Entitlement__c records with different Role__c values
        Expense_Entitlement__c entitlement1 = new Expense_Entitlement__c(
            Role__c = 'SSO',
            RecordTypeId = expenseRecordType.Id
        );
        Expense_Entitlement__c entitlement2 = new Expense_Entitlement__c(
            Role__c = 'SO',
            RecordTypeId = expenseRecordType.Id
        );

        // Step 3: Insert both records
        Test.startTest();
        insert new List<Expense_Entitlement__c>{entitlement1, entitlement2};
        Test.stopTest();

        // Step 4: Assert that both records were inserted successfully
        System.assertNotEquals(null, entitlement1.Id, 'Entitlement 1 was not inserted.');
        System.assertNotEquals(null, entitlement2.Id, 'Entitlement 2 was not inserted.');
    }

    @isTest
    static void testMultipleRolesSameRecordType() {
        // Step 1: Query an existing Record Type
        RecordType expenseRecordType = [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = 'Expense_Entitlement__c' 
            AND DeveloperName = 'Daily_Allowance' 
            LIMIT 1
        ];

        // Step 2: Create valid Expense_Entitlement__c records with different Role__c values and the same RecordTypeId
        Expense_Entitlement__c entitlement1 = new Expense_Entitlement__c(
            Role__c = 'ASM',
            RecordTypeId = expenseRecordType.Id
        );
        Expense_Entitlement__c entitlement2 = new Expense_Entitlement__c(
            Role__c = 'RSM',
            RecordTypeId = expenseRecordType.Id
        );

        // Step 3: Insert both records
        Test.startTest();
        insert new List<Expense_Entitlement__c>{entitlement1, entitlement2};
        Test.stopTest();

        // Step 4: Assert that both records were inserted successfully
        System.assertNotEquals(null, entitlement1.Id, 'Entitlement 1 was not inserted.');
        System.assertNotEquals(null, entitlement2.Id, 'Entitlement 2 was not inserted.');
    }
}