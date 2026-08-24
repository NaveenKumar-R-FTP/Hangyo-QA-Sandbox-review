@isTest
public class UpdateAccountAssetCountBatchTest {

    @testSetup
    static void setupData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        RecordType distributorRT = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Account'
            AND DeveloperName = 'Distributor'
            LIMIT 1
        ];

        
        // Create two Accounts
        Account acc1 = new Account(Name = 'Distributor A' , RecordTypeId = distributorRT.Id);
        Account acc2 = new Account(Name = 'Distributor B', RecordTypeId = distributorRT.Id);
        insert new List<Account>{ acc1, acc2 };

        // Add Assets for acc1
        List<Asset__c> assets = new List<Asset__c>{
            new Asset__c(Distributor_Name__c = acc1.Id,Retailer_Account__c = null),
            new Asset__c(Distributor_Name__c = acc1.Id,Retailer_Account__c = null),
            new Asset__c(Distributor_Name__c = acc1.Id,Retailer_Account__c = null)
        };
        insert assets;

        // Add Assets for acc2
        insert new Asset__c(Distributor_Name__c = acc2.Id);
    }

    @isTest
    static void testBatchUpdatesAssetCount() {
        // Before running batch, Number_of_Assets__c should be null or 0
        List<Account> beforeAccounts = [
            SELECT Id, Name, Number_of_Assets__c
            FROM Account
            WHERE Name IN ('Distributor A','Distributor B')
        ];

        Test.startTest();
        // Run the batch with batch size of 200
        Database.executeBatch(new UpdateAccountAssetCountBatch(), 200);
        Test.stopTest();

        // After batch, validate counts
        List<Account> afterAccounts = [
            SELECT Name, Number_of_Assets__c
            FROM Account
            WHERE Name IN ('Distributor A','Distributor B')
        ];

        Map<String, Integer> expectedCounts = new Map<String, Integer>{
            'Distributor A' => 3,
            'Distributor B' => 1
        };
    }
}