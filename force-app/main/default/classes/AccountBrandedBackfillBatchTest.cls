@isTest
public class AccountBrandedBackfillBatchTest {

    private static Id retailerRecordTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Retailer').getRecordTypeId();
    }

    @testSetup
    static void setupData() {
        insert new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
    }

    /**
     * The batch walks every Account, so this checks it handles a mixed population
     * in one pass: freezer-backed, material-backed, and nothing at all.
     * Direction-by-direction rules are covered in AccountBrandingServiceTest.
     */
    @isTest
    static void testBatchEvaluatesMixedPopulation() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            accounts.add(new Account(
                Name = 'Backfill Retailer ' + i,
                BillingCity = 'Mumbai', BillingState = 'Maharashtra',
                RecordTypeId = retailerRecordTypeId(),
                Retailer_Code__c = 'SF93000' + i
            ));
        }
        insert accounts;

        // accounts[0] holds a freezer.
        Asset_Master__c master = new Asset_Master__c(OEM_Serial_Number__c = 'HIPLBK001');
        insert master;
        insert new Asset_Mapping__c(
            Asset_Master__c = master.Id, Retailer__c = accounts[0].Id,
            External_ID__c = 'BK-EXT-001', Active__c = true, Allocation_Start_Date__c = Date.today()
        );

        // accounts[1] holds branding material.
        insert new Branding_Asset__c(
            Account__c = accounts[1].Id, Asset_Name__c = 'Banner',
            Quantity__c = 3, Installed_Date__c = Date.today(), Active__c = true
        );

        // accounts[2] holds nothing but is wrongly flagged.
        update new Account(Id = accounts[2].Id, Is_Branded__c = true);

        Test.startTest();
        Database.executeBatch(new AccountBrandedBackfillBatch(), 200);
        Test.stopTest();

        Map<Id, Account> result = new Map<Id, Account>([
            SELECT Id, Is_Branded__c FROM Account WHERE Id IN :accounts
        ]);

        System.assertEquals(true, result.get(accounts[0].Id).Is_Branded__c,
            'Freezer-backed account should be branded');
        System.assertEquals(true, result.get(accounts[1].Id).Is_Branded__c,
            'Material-backed account should be branded');
        System.assertEquals(false, result.get(accounts[2].Id).Is_Branded__c,
            'Account with nothing installed should be cleared');
    }

    @isTest
    static void testBatchIsIdempotent() {
        Account retailer = new Account(
            Name = 'Idempotent Retailer',
            BillingCity = 'Mumbai', BillingState = 'Maharashtra',
            RecordTypeId = retailerRecordTypeId(), Retailer_Code__c = 'SF930099'
        );
        insert retailer;

        insert new Branding_Asset__c(
            Account__c = retailer.Id, Asset_Name__c = 'Poster',
            Quantity__c = 1, Installed_Date__c = Date.today(), Active__c = true
        );

        Test.startTest();
        Database.executeBatch(new AccountBrandedBackfillBatch(), 200);
        Test.stopTest();

        Boolean afterFirstRun = [SELECT Is_Branded__c FROM Account WHERE Id = :retailer.Id].Is_Branded__c;
        System.assertEquals(true, afterFirstRun);

        Database.executeBatch(new AccountBrandedBackfillBatch(), 200);

        System.assertEquals(afterFirstRun,
            [SELECT Is_Branded__c FROM Account WHERE Id = :retailer.Id].Is_Branded__c,
            'A second run should not change anything');
    }
}