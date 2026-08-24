/*
Created By : Fuzail 
Description :     Batch Apex class used to update Transaction_Type_Purchase__c and 
                  Transaction_Type_Sale__c picklist values on Invoice__c records 
                  based on their Record Type.
Created Date : 04/12/2025
Last Modified Date: 04/11/2025
*/

global class InvoiceTransactionTypeBatch implements Database.Batchable<SObject> {

    global Database.QueryLocator start(Database.BatchableContext bc) {

        // Filter invoices created from 1st October to today
        String startDate = '2025-10-01T00:00:00.000Z';

        return Database.getQueryLocator(
            'SELECT Id, RecordType.DeveloperName, ' +
            'Transaction_Type_Purchase__c, Transaction_Type_Sale__c ' +
            'FROM Invoice__c ' +
            'WHERE CreatedDate >= ' + startDate
        );
    }

    global void execute(Database.BatchableContext bc, List<Invoice__c> invList) {

        for (Invoice__c inv : invList) {

            // Reset fields before assigning
            inv.Transaction_Type_Purchase__c = null;
            inv.Transaction_Type_Sale__c = null;

            // Apply mapping rules based on record type
            if (inv.RecordType.DeveloperName == 'Primary_Invoice') {

                inv.Transaction_Type_Purchase__c = 'Purchased from Hangyo';

            } else if (inv.RecordType.DeveloperName == 'Secondary_Invoice_Under_SS') {

                inv.Transaction_Type_Purchase__c = 'Purchased from Super Stockist';
                inv.Transaction_Type_Sale__c = 'Sale to Under S';

            } else if (inv.RecordType.DeveloperName == 'Secondary_Invoice') {

                inv.Transaction_Type_Sale__c = 'Sale to Retailer';
            }
        }

        update invList;
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('✔ Batch Completed — Invoice types updated for records from Oct 1 onwards.');
    }
}