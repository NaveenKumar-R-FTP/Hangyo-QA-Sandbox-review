@IsTest
private class UpdateCollectionRemainingBalanceTest {

    @IsTest
    static void testBatchUpdatesRemainingBalance() {
        // 1. Test data setup
        Invoice__c inv = new Invoice__c();
        inv.Invoice_Amount__c = 5000;
        //inv.Collected_Amount__c = 3000; // just to satisfy the WHERE filter in start()
        insert inv;

        // Create 3 collection records for this invoice
        // Total_Amount__c values: 1000, 1000, 1000 → Remaining should be 4000, 3000, 2000
        List<Collection__c> colList = new List<Collection__c>();

        colList.add(new Collection__c(
            Invoice__c = inv.Id,
            Amount_Collected__c = 1000
        ));
        colList.add(new Collection__c(
            Invoice__c = inv.Id,
            Amount_Collected__c = 1000
        ));
        colList.add(new Collection__c(
            Invoice__c = inv.Id,
            Amount_Collected__c = 1000
        ));

        insert colList;

        // 2. Run the batch
        Test.startTest();
        UpdateCollectionRemainingBalance batchJob = new UpdateCollectionRemainingBalance();
        Database.executeBatch(batchJob, 50);
        Test.stopTest();

        // 3. Reload collections ordered as in the batch and assert results
        List<Collection__c> updatedCols = [
            SELECT Id, Total_Amount__c, Remaining_Balance__c, CreatedDate
            FROM Collection__c
            WHERE Invoice__c = :inv.Id
            ORDER BY CreatedDate ASC, Id ASC
        ];

        System.assertEquals(3, updatedCols.size(), 'There should be 3 collection records');

        // Remaining logic:
        // Invoice_Amount__c = 5000
        // After 1st (1000): remaining = 4000
        // After 2nd (1000): remaining = 3000
        // After 3rd (1000): remaining = 2000

        System.assertEquals(4000, updatedCols[0].Remaining_Balance__c,
            'First collection remaining balance should be 4000');
        System.assertEquals(3000, updatedCols[1].Remaining_Balance__c,
            'Second collection remaining balance should be 3000');
        System.assertEquals(2000, updatedCols[2].Remaining_Balance__c,
            'Third collection remaining balance should be 2000');
    }

    @IsTest
    static void testBatchWithNoCollections() {
        // Invoice with no collections but matching WHERE Collected_Amount__c > 0
        Invoice__c inv = new Invoice__c();
        inv.Invoice_Amount__c = 1000;
        //inv.Collected_Amount__c = 500;
        insert inv;

        Test.startTest();
        UpdateCollectionRemainingBalance batchJob = new UpdateCollectionRemainingBalance();
        Database.executeBatch(batchJob, 50);
        Test.stopTest();

        // No exception should occur; nothing to assert on collections here,
        // test just ensures batch handles invoices with no child records gracefully.
        System.assertEquals(0,
            [SELECT COUNT() FROM Collection__c WHERE Invoice__c = :inv.Id],
            'There should still be no collections for this invoice');
    }
}