/*
Created By : Fuzail 
Description : Test Class for invoiceTransactionTypeBatch
Created Date : 04/12/2025
Last Modified Date: 04/11/2025
*/

@isTest
public class InvoiceTransactionTypeBatchTest {
 @testSetup
    static void setup() {

        // Get each record type individually
        Id rtPrimary = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Invoice__c' AND DeveloperName = 'Primary_Invoice'
        ].Id;

        Id rtSecondarySS = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Invoice__c' AND DeveloperName = 'Secondary_Invoice_Under_SS'
        ].Id;

        Id rtSecondary = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Invoice__c' AND DeveloperName = 'Secondary_Invoice'
        ].Id;

        // Create 3 invoice test records (auto-number name not needed)
        insert new Invoice__c(RecordTypeId = rtPrimary);
        insert new Invoice__c(RecordTypeId = rtSecondarySS);
        insert new Invoice__c(RecordTypeId = rtSecondary);
    }

    @isTest
    static void testBatchResult() {

        Test.startTest();
        Database.executeBatch(new InvoiceTransactionTypeBatch(), 200);
        Test.stopTest();

        // Fetch all invoices back
        List<Invoice__c> invList = [
            SELECT Id, RecordType.DeveloperName,
                   Transaction_Type_Purchase__c,
                   Transaction_Type_Sale__c
            FROM Invoice__c
        ];

        // Assertions (1 by 1, no map needed)
        for (Invoice__c inv : invList) {

            if (inv.RecordType.DeveloperName == 'Primary_Invoice') {
                System.assertEquals(
                    'Purchased from Hangyo',
                    inv.Transaction_Type_Purchase__c
                );
                System.assertEquals(null, inv.Transaction_Type_Sale__c);
            }

            if (inv.RecordType.DeveloperName == 'Secondary_Invoice_Under_SS') {
                System.assertEquals(
                    'Purchased from Super Stockist',
                    inv.Transaction_Type_Purchase__c
                );
                System.assertEquals(
                    'Sale to Under S',
                    inv.Transaction_Type_Sale__c
                );
            }

            if (inv.RecordType.DeveloperName == 'Secondary_Invoice') {
                System.assertEquals(null, inv.Transaction_Type_Purchase__c);
                System.assertEquals(
                    'Sale to Retailer',
                    inv.Transaction_Type_Sale__c
                );
            }
        }
    }
}