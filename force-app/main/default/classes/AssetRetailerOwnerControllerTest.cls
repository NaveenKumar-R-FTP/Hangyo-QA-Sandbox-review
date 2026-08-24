@IsTest
public class AssetRetailerOwnerControllerTest {
    @testSetup
    static void setupData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(
        Name = 'SF',
        Latest_Code__c = 100
    );
    insert setting;
        // Create two users (owners)
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'SFA Profile'
            LIMIT 1
        ];
        User user1 = new User(
            Alias = 'uone',
            Email = 'user1@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'UserOne',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'user1_' + System.currentTimeMillis() + '@test.com'
        );
        User user2 = new User(
            Alias = 'utwo',
            Email = 'user2@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'UserTwo',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'user2_' + System.currentTimeMillis() + '@test.com'
        );

        insert new List<User>{ user1, user2 };
            
         // 3. Retailer Record Type
    Id retailerRtId = Schema.SObjectType.Account
        .getRecordTypeInfosByName()
        .get('Retailer')
        .getRecordTypeId();   

        // Create two retailer accounts with different owners
        Account retailer1 = new Account(
            Name = 'Retailer A',
            OwnerId = user1.Id,
            RecordTypeId = retailerRtId
        );

        Account retailer2 = new Account(
            Name = 'Retailer B',
            OwnerId = user2.Id,
            RecordTypeId = retailerRtId
        );

        insert new List<Account>{ retailer1, retailer2 };

        // Create Asset linked to first retailer
        Asset__c asset = new Asset__c(
            Retailer_Account__c = retailer1.Id
        );

        insert asset;
    }

    @IsTest
    static void testRetailerChangeUpdatesOwnerAndSalesman() {

        // Fetch test data
        Account retailer2 = [
            SELECT Id, OwnerId
            FROM Account
            WHERE Name = 'Retailer B'
            LIMIT 1
        ];

        Asset__c asset = [
            SELECT Id, Retailer_Account__c, Salesman__c, OwnerId
            FROM Asset__c
            LIMIT 1
        ];

        // Change retailer
        asset.Retailer_Account__c = retailer2.Id;

        Test.startTest();
        update asset;
        Test.stopTest();

        // Re-fetch asset after update
        Asset__c updatedAsset = [
            SELECT Salesman__c, OwnerId
            FROM Asset__c
            WHERE Id = :asset.Id
        ];

        // Assertions
        System.assertEquals(
            retailer2.OwnerId,
            updatedAsset.Salesman__c,
            'Salesman__c should match new Retailer owner'
        );

        System.assertEquals(
            retailer2.OwnerId,
            updatedAsset.OwnerId,
            'Asset OwnerId should match new Retailer owner'
        );
    }
}