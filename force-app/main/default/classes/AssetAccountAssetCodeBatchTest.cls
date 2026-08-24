@isTest
public class AssetAccountAssetCodeBatchTest {
    @testSetup
    static void setupData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        // Create Retailer account
        Account retailerAcc = new Account(
            Name = 'Test Retailer Account',
            RecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'Retailer' LIMIT 1].Id
        );
        insert retailerAcc;

        // Create Asset Master records
        List<Asset_Master__c> masters = new List<Asset_Master__c>();
        masters.add(new Asset_Master__c(OEM_Serial_Number__c = 'HIPL-TEST-001'));
        masters.add(new Asset_Master__c(OEM_Serial_Number__c = 'HIPL-TEST-002'));
        insert masters;

        // Create Asset Mapping records
        List<Asset_Mapping__c> mappings = new List<Asset_Mapping__c>();
        mappings.add(new Asset_Mapping__c(
            Retailer__c = retailerAcc.Id,
            Asset_Master__c = masters[0].Id,
            Active__c = true
        ));
        mappings.add(new Asset_Mapping__c(
            Retailer__c = retailerAcc.Id,
            Asset_Master__c = masters[1].Id,
            Active__c = true
        ));
        insert mappings;
    }

    @isTest
    static void testBatchUpdatesAssetCounts() {
        Test.startTest();
        Database.executeBatch(new AssetAccountAssetCodeBatch(), 100);
        Test.stopTest();

        Account updatedRetailer = [
            SELECT Id, Number_of_Assets__c, Asset_Code__c
            FROM Account
            WHERE Name = 'Test Retailer Account'
            LIMIT 1
        ];

        System.assertEquals(2, updatedRetailer.Number_of_Assets__c,
            'Number_of_Assets__c should be 2 after batch execution.');
        System.assertNotEquals(null, updatedRetailer.Asset_Code__c,
            'Asset_Code__c should be populated after batch execution.');
    }
}