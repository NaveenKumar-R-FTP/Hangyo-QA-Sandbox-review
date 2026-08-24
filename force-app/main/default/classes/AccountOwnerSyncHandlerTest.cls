@IsTest
public class AccountOwnerSyncHandlerTest {

    @testSetup
    static void setupData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(
            Name = 'SF',
            Latest_Code__c = 100
        );
        insert setting;
    }

    private static User createUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'SFA Profile' LIMIT 1];
        User u = new User(
            FirstName = alias,
            LastName = 'Test',
            Email = alias + '@test.com',
            Username = alias + '.' + System.currentTimeMillis() + '@test.com',
            Alias = alias.substring(0, Math.min(8, alias.length())),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert u;
        return u;
    }

    @isTest
    static void testAssetOwnerUpdatedWhenAccountOwnerChanges() {

        User oldOwner = createUser('OldOwner');
        User newOwner = createUser('NewOwner');

        // Retailer Account (Generate code will run here)
        Account retailer = new Account(
            Name = 'Retailer Test',
            OwnerId = oldOwner.Id
        );
        insert retailer;

        // Asset linked via Retailer_Account__c
        Asset__c asset = new Asset__c(
            Retailer_Account__c = retailer.Id,
            OwnerId = oldOwner.Id
        );
        insert asset;

        // Simulate oldMap
        Account oldRetailer = retailer.clone(false, false, false, false);
        Map<Id, Account> oldMap = new Map<Id, Account>{
            retailer.Id => oldRetailer
        };

        // Change owner
        retailer.OwnerId = newOwner.Id;

        Test.startTest();
        AccountOwnerSyncHandler.syncRetailerAssetOwners(
            new List<Account>{ retailer },
            oldMap
        );
        Test.stopTest();

        Asset__c updatedAsset = [
            SELECT OwnerId
            FROM Asset__c
            WHERE Id = :asset.Id
        ];

        System.assertEquals(
            newOwner.Id,
            updatedAsset.OwnerId,
            'Asset owner should follow Account owner change'
        );
    }

    @isTest
    static void testNullSafety() {
        Test.startTest();
        AccountOwnerSyncHandler.syncRetailerAssetOwners(null, null);
        Test.stopTest();
        System.assert(true);
    }
}