@isTest
public class UnderSsOrderDMSControllerTest {

    @isTest
    static void testGetAllUnderSs() {

        // Create Retailer Code Setting
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(
            Name = 'SF',
            Latest_Code__c = 100
        );
        insert setting;

        // Fetch Distributor Record Type
        Id distributorRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE DeveloperName = 'Distributor'
            AND SObjectType = 'Account'
            LIMIT 1
        ].Id;
        
        Id SsRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE DeveloperName = 'SuperStockist'
            AND SObjectType = 'Account'
            LIMIT 1
        ].Id;

        // Create Distributor Account (Super Stockist)
        Account distributorAccount = new Account(
            Name = 'Main Distributor',
            RecordTypeId = SsRecordTypeId,
            PAN_Number__c = '248001',
            Is_Active__c = true
        );
        insert distributorAccount;

        // Create Contact linked with Distributor Account
        Contact distributorContact = new Contact(
            LastName = 'Distributor Contact',
            AccountId = distributorAccount.Id
        );
        insert distributorContact;

        // Fetch Community Profile
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'DMS Partner Community Custom'
            LIMIT 1
        ];

        // Create Community User
        User testUser = new User(
            Alias = 'tuser',
            Email = 'testuser@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testuser' + System.currentTimeMillis() + '@testorg.com',
            ContactId = distributorContact.Id
        );
        insert testUser;

        // Create Under Super Stockist Account
        Account underSsAccount = new Account(
            Name = 'Under SS Distributor',
            RecordTypeId = distributorRecordTypeId,
            PAN_Number__c = '248002',
            Distributor_Type__c = 'Under Super Stockist',
            Super_Stockist_Name__c = distributorAccount.Id,
            Is_Active__c = true
        );
        insert underSsAccount;

        // Create another Account which should NOT come in result
        Account otherAccount = new Account(
            Name = 'Inactive Under SS',
            RecordTypeId = distributorRecordTypeId,
            PAN_Number__c = '248003',
            Distributor_Type__c = 'Under Super Stockist',
            Super_Stockist_Name__c = distributorAccount.Id,
            Is_Active__c = false
        );
        insert otherAccount;

        System.runAs(testUser) {

            Test.startTest();

            List<Account> result =
                UnderSsOrderDMSController.getAllUnderSs('Under');

            Test.stopTest();

            System.assertNotEquals(
                null,
                result,
                'Result should not be null'
            );

            System.assertEquals(
                1,
                result.size(),
                'Only active Under SS account should be returned'
            );

            System.assertEquals(
                'Under SS Distributor',
                result[0].Name,
                'Expected matching Under SS account'
            );
        }
    }
}