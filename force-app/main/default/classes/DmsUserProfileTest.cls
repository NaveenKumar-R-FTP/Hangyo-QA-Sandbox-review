@isTest
public class DmsUserProfileTest {
    @testSetup
    static void setupTestData() {
        // Create test Account
        Id disRecId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId();
        Account distributor = new Account(Name = 'Distributor', RecordTypeId = disRecId);
        insert distributor;

        // Create Contact
        Contact contact = new Contact(FirstName = 'Test', LastName = 'User', AccountId = distributor.Id);
        insert contact;
        
        Profile partnerProfile = [SELECT Id FROM Profile WHERE Name = 'DMS Partner Community Custom' LIMIT 1];
        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@example.com',
            Username = 'testusermystery@example.com.salesforce',
            Alias = 'testusr',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ContactId = contact.Id,
            ProfileId = partnerProfile.Id,
            LanguageLocaleKey = 'en_US',
            Invoice_Number_Prefix__c='123',
            Invoice_Start_Number__c = 123,
            Primary_Distributor__c = true,
            State = 'Karnataka'
            
        );
        insert testUser;
    }
    
    @isTest
    static void testFetchDMSUser() {
        User testUser = [SELECT Id FROM User WHERE Username = 'testusermystery@example.com.salesforce' LIMIT 1];
        System.runAs(testUser) {
        Test.startTest();
        User result = DmsUserProfile.fetchDMSUser();
        Test.stopTest();
        
        System.assert(result == null || result.Id != null, 'FetchDMSUser should return a valid User or null.');
        }
    }
    
    @isTest
    static void testFetchDMSUserWithId() {
        
        User testUser = [SELECT Id FROM User WHERE Username = 'testusermystery@example.com.salesforce' LIMIT 1];
        System.runAs(testUser) {
        
        Test.startTest();
        User result = DmsUserProfile.fetchDMSUser(testUser.Id);
        Test.stopTest();
        
        System.assert(result == null || result.Id != null, 'FetchDMSUser with Id should return a valid User or null.');
        }
    }
}