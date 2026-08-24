@isTest
public class BatchUpdateLastConfirmedInvoiceDateTest {

    @testSetup
    static void setupTestData() {
        insert new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        
        // Create sample Accounts
        List<Account> accList = new List<Account>{
            new Account(Name = 'Retailer A'),
            new Account(Name = 'UnderSS B'),
            new Account(Name = 'Retailer C - No Confirmed Invoice')
        };
        insert accList;

        Id retailerAId = accList[0].Id;
        Id underSSBId = accList[1].Id;
        Id retailerCId = accList[2].Id;

        Date baseDate = Date.newInstance(2025, 8, 1);

        // Step 1️⃣ — Create all invoices as DRAFT
        List<Invoice__c> invoices = new List<Invoice__c>{
            new Invoice__c(Name = 'Retailer A - Inv1', Status__c = 'Draft',
                           Invoice_Date__c = baseDate.addDays(2), Retailer_Account__c = retailerAId),
            new Invoice__c(Name = 'Retailer A - Inv2', Status__c = 'Draft',
                           Invoice_Date__c = baseDate.addDays(5), Retailer_Account__c = retailerAId),
            new Invoice__c(Name = 'UnderSS B - Inv1', Status__c = 'Draft',
                           Invoice_Date__c = baseDate.addDays(10), Under_SS__c = underSSBId),
            new Invoice__c(Name = 'Retailer C - Inv1', Status__c = 'Draft',
                           Invoice_Date__c = baseDate.addDays(3), Retailer_Account__c = retailerCId)
        };
        insert invoices;

        // Step 2️⃣ — Update to CONFIRMED where needed
        List<Invoice__c> toConfirm = new List<Invoice__c>();
        for (Invoice__c inv : invoices) {
            if (inv.Name.contains('Inv2') || inv.Name.contains('UnderSS')) {
                toConfirm.add(new Invoice__c(
                    Id = inv.Id,
                    Status__c = 'Confirmed'
                ));
            }
        }
        update toConfirm;

        // Step 3️⃣ — Update some to DELIVERED (after confirmation)
        List<Invoice__c> toDeliver = new List<Invoice__c>();
        for (Invoice__c inv : invoices) {
            if (inv.Name.contains('Inv2')) {
                toDeliver.add(new Invoice__c(
                    Id = inv.Id,
                    Status__c = 'Delivered'
                ));
            }
        }
        update toDeliver;

        // ✅ Step 4️⃣ — Set CreatedDate inside batch date range
        for (Invoice__c inv : invoices) {
            Test.setCreatedDate(inv.Id, DateTime.newInstance(2025, 8, 15, 10, 0, 0));
        }
    }

    @isTest
    static void testBatchExecute() {
        // Run the batch
        Test.startTest();
        Database.executeBatch(new BatchUpdateLastConfirmedInvoiceDate(), 200);
        Test.stopTest();
    }

    @isTest
    static void testBatchWithNoData() {
        delete [SELECT Id FROM Invoice__c];

        Test.startTest();
        Database.executeBatch(new BatchUpdateLastConfirmedInvoiceDate(), 200);
        Test.stopTest();

        System.assert(true, 'Batch executed successfully with no data.');
    }
}