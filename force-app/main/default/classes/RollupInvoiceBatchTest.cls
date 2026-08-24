@isTest
public class RollupInvoiceBatchTest {

    @testSetup
    static void setupData() {

        // Get Primary Invoice record type
        RecordType rt = [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = 'Invoice__c' 
            AND DeveloperName = 'Primary_Invoice'
            LIMIT 1
        ];

        // Create two invoices with Primary record type
        List<Invoice__c> invoices = new List<Invoice__c>{
            new Invoice__c(Name = 'INV-001', RecordTypeId = rt.Id),
            new Invoice__c(Name = 'INV-002', RecordTypeId = rt.Id)
        };
        insert invoices;

        // Create Line Items
        List<Invoice_Line_Item__c> items = new List<Invoice_Line_Item__c>();

        // Line items for Invoice 1
        items.add(new Invoice_Line_Item__c(
            Invoice__c = invoices[0].Id,
            CGST_Amount__c = 10,
            SGST_Amount__c = 5,
            IGST_Amount__c = 8,
            Quantity__c = 2
        ));
        items.add(new Invoice_Line_Item__c(
            Invoice__c = invoices[0].Id,
            CGST_Amount__c = 15,
            SGST_Amount__c = 7,
            IGST_Amount__c = 6,
            Quantity__c = 3
        ));

        // Line items for Invoice 2
        items.add(new Invoice_Line_Item__c(
            Invoice__c = invoices[1].Id,
            CGST_Amount__c = 12,
            SGST_Amount__c = 4,
            IGST_Amount__c = 10,
            Quantity__c = 5
        ));

        insert items;
    }

    @isTest
    static void testBatchExecution() {

        Test.startTest();
        Database.executeBatch(new RollupInvoiceBatch(), 200);
        Test.stopTest();

        // Fetch updated invoices
        List<Invoice__c> invList = [
            SELECT CGST_Amount__c, SGST_Amount__c, IGST_Amount__c, Total_Quantity__c, Name
            FROM Invoice__c
            ORDER BY Name
        ];

        Invoice__c inv1 = invList[0]; // INV-001
        Invoice__c inv2 = invList[1]; // INV-002

        // Validate Invoice 1 rollups
        System.assertEquals(25, inv1.CGST_Amount__c, 'CGST total incorrect for INV-001');  // 10 + 15
        System.assertEquals(12, inv1.SGST_Amount__c, 'SGST total incorrect for INV-001');  // 5 + 7
        System.assertEquals(14, inv1.IGST_Amount__c, 'IGST total incorrect for INV-001');  // 8 + 6
        System.assertEquals(5,  inv1.Total_Quantity__c, 'Quantity total incorrect for INV-001');  // 2 + 3

        // Validate Invoice 2 rollups
        System.assertEquals(12, inv2.CGST_Amount__c, 'CGST total incorrect for INV-002');
        System.assertEquals(4,  inv2.SGST_Amount__c, 'SGST total incorrect for INV-002');
        System.assertEquals(10, inv2.IGST_Amount__c, 'IGST total incorrect for INV-002');
        System.assertEquals(5,  inv2.Total_Quantity__c, 'Quantity total incorrect for INV-002');
    }
}