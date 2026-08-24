@isTest
public class AssetTriggerHandlerTest {
    
    @testSetup
    static void setupData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        // Create two Accounts (Retailer record type is assumed, but you can adjust if needed)
        Account acc1 = new Account(Name = 'Retailer A');
        Account acc2 = new Account(Name = 'Retailer B');
        insert new List<Account>{ acc1, acc2 };
    }
    
    @isTest
    static void testInsertAssets() {
        Account acc1 = [SELECT Id, Number_of_Assets__c FROM Account WHERE Name = 'Retailer A' LIMIT 1];
        
        // Insert two assets for acc1
        List<Asset__c> assets = new List<Asset__c>{
            new Asset__c(Retailer_Account__c = acc1.Id),
            new Asset__c(Retailer_Account__c = acc1.Id)
        };
        insert assets;
        
        acc1 = [SELECT Id, Number_of_Assets__c FROM Account WHERE Id = :acc1.Id];
        System.assertEquals(2, acc1.Number_of_Assets__c, 'Account should have 2 assets');
    }
    
    @isTest
    static void testReparentAssets() {
        Account acc1 = [SELECT Id FROM Account WHERE Name = 'Retailer A' LIMIT 1];
        Account acc2 = [SELECT Id FROM Account WHERE Name = 'Retailer B' LIMIT 1];
        
        // Insert one asset under acc1
        Asset__c asset = new Asset__c( Retailer_Account__c = acc1.Id);
        insert asset;
        
        // Reparent the asset to acc2
        asset.Retailer_Account__c = acc2.Id;
        update asset;
        
        acc1 = [SELECT Number_of_Assets__c FROM Account WHERE Id = :acc1.Id];
        acc2 = [SELECT Number_of_Assets__c FROM Account WHERE Id = :acc2.Id];
        
        System.assertEquals(0, acc1.Number_of_Assets__c, 'Old account should now have 0 assets');
        System.assertEquals(1, acc2.Number_of_Assets__c, 'New account should now have 1 asset');
    }
    
    @isTest
    static void testDeleteAssets() {
        Account acc1 = [SELECT Id FROM Account WHERE Name = 'Retailer A' LIMIT 1];
        
        // Insert asset
        Asset__c asset = new Asset__c(Retailer_Account__c = acc1.Id);
        insert asset;
        
        // Verify count = 1
        acc1 = [SELECT Number_of_Assets__c FROM Account WHERE Id = :acc1.Id];
        System.assertEquals(1, acc1.Number_of_Assets__c);
        
        // Delete asset
        delete asset;
        
        acc1 = [SELECT Number_of_Assets__c FROM Account WHERE Id = :acc1.Id];
        System.assertEquals(0, acc1.Number_of_Assets__c, 'Account should now have 0 assets after delete');
    }
   

}