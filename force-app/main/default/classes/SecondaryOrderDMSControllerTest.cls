@isTest
public class SecondaryOrderDMSControllerTest {
    @isTest
    public static void test(){
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        // Create a test Account
        Id distributorRecordType = [ 
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Distributor' AND SObjectType = 'Account' 
            LIMIT 1 
        ].Id;
        Account distributorAccount = new Account(Name = 'Distributor Account', RecordTypeId=distributorRecordType , PAN_Number__c = '248001');
        insert distributorAccount;

        // Create a test Contact associated with the Account
        Contact testContact = new Contact(LastName = 'Test Contact', AccountId = distributorAccount.Id);
        insert testContact;
        
        Id retailerRecordType = [ 
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Retailer' AND SObjectType = 'Account' 
            LIMIT 1 
        ].Id;
        Account testAccount = new Account(Name = 'Counter Sales Customer', RecordTypeId=retailerRecordType , Distributor__c = distributorAccount.Id , PAN_Number__c = '248001' , Is_Active__c = true);
        insert testAccount;

        // Create a test User associated with the Contact
        Profile p = [SELECT Id FROM Profile WHERE Name = 'DMS Partner Community Custom'];
        User testUser = new User(
            Alias = 'testUser',
            Email = 'testuser1@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testuser1@hangyoWierd.com',
            ContactId = testContact.Id
        );
        insert testUser;
        
        System.runAs(testUser) {
            Test.startTest();
            List<Account> result = SecondaryOrderDMSController.getAllRetailer('Counter');
            System.assert(result[0].Name.contains('Counter'), 'Expected retailer name to contain "Counter"');
            Test.stopTest();
        }
    }
}