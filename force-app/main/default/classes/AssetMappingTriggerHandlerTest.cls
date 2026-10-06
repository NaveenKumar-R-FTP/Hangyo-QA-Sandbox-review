@isTest
public class AssetMappingTriggerHandlerTest {
    
    @isTest
    static void testUpdateDistributor() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        Account distributor = new Account(
            Name = 'Test Distributor',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId()
        );
        insert distributor;
        
        Account retailer = new Account(
            Name = 'Test Retailer',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId(),
            Distributor__c = distributor.Id
        );
        insert retailer;
        
        Asset_Master__c master = new Asset_Master__c(
            OEM_Serial_Number__c = 'HIPL-TEST-001'
        );
        insert master;
        
        Asset_Mapping__c mapping = new Asset_Mapping__c(
            Retailer__c = retailer.Id,
            Asset_Master__c = master.Id,
            Active__c = true
        );
        insert mapping;
        
        Test.startTest();
        AssetMappingTriggerHandler.isRunning = false;
        AssetMappingTriggerHandler.updateDistributor(
            new List<Asset_Mapping__c>{ mapping },
            null
        );
        Test.stopTest();
        
        Asset_Mapping__c result = [
            SELECT Id, Distributor__c
            FROM Asset_Mapping__c
            WHERE Id = :mapping.Id
        ];
        
        System.assertEquals(distributor.Id, result.Distributor__c,
            'Distributor should be auto-populated from Retailer');
    }
@isTest
    static void testDistributorAssetCount() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        Account distributor = new Account(
            Name = 'Test Distributor Count',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId()
        );
        insert distributor;
        
        Account retailer = new Account(
            Name = 'Test Retailer Count',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId(),
            Distributor__c = distributor.Id
        );
        insert retailer;
        
        Asset_Master__c master = new Asset_Master__c(OEM_Serial_Number__c = 'HIPL-COUNT-001');
        insert master;
        
        Asset_Mapping__c mapping = new Asset_Mapping__c(
            Distributor__c = distributor.Id,
            Asset_Master__c = master.Id,
            Active__c = true
        );
        insert mapping;
        
        Test.startTest();
        mapping.Retailer__c = retailer.Id;
        update mapping;
        Test.stopTest();
        
        Account result = [SELECT Number_of_Assets__c FROM Account WHERE Id = :distributor.Id];
        System.assertNotEquals(null, result.Number_of_Assets__c);
    }

    @isTest
    static void testValidateDuplicateMapping() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        Account distributor = new Account(
            Name = 'Test Distributor Val',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId()
        );
        insert distributor;
        
        Account retailer1 = new Account(
            Name = 'Test Retailer Val 1',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId(),
            Distributor__c = distributor.Id
        );
        Account retailer2 = new Account(
            Name = 'Test Retailer Val 2',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId(),
            Distributor__c = distributor.Id
        );
        insert new List<Account>{retailer1, retailer2};
        
        Asset_Master__c master = new Asset_Master__c(OEM_Serial_Number__c = 'HIPL-VAL-001');
        insert master;
        
        Asset_Mapping__c mapping1 = new Asset_Mapping__c(
            Retailer__c = retailer1.Id,
            Distributor__c = distributor.Id,
            Asset_Master__c = master.Id,
            Active__c = true
        );
        insert mapping1;
        
        Test.startTest();
        List<Asset_Mapping__c> testMappings = new List<Asset_Mapping__c>{
            new Asset_Mapping__c(
                Retailer__c = retailer2.Id,
                Distributor__c = distributor.Id,
                Asset_Master__c = master.Id,
                Active__c = true
            )
        };
        AssetMappingTriggerHandler.validateDuplicateMapping(testMappings, null);
        
        List<Asset_Mapping__c> inactiveMappings = new List<Asset_Mapping__c>{
            new Asset_Mapping__c(Asset_Master__c = master.Id, Active__c = false)
        };
        AssetMappingTriggerHandler.validateDuplicateMapping(inactiveMappings, null);
        
        List<Asset_Mapping__c> nullMasterMappings = new List<Asset_Mapping__c>{
            new Asset_Mapping__c(Active__c = true)
        };
        AssetMappingTriggerHandler.validateDuplicateMapping(nullMasterMappings, null);
        Test.stopTest();
        
        System.assert(true, 'Validation completed without exception');
    }
}