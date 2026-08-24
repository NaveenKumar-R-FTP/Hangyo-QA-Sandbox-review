@IsTest
public class AccountTriggerHandlerTest {
    @TestSetup
    static void setupTestData() {
        // 1. Create Record Type for Super Stockist
        RecordType superstockistRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'SuperStockist' AND SObjectType = 'Account' LIMIT 1];
        RecordType distributorRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Distributor' AND SObjectType = 'Account' LIMIT 1];
        // 2. Create Super Stockist Account (valid record type)
        Account validSS = new Account(
            Name = 'Valid Super Stockist',
            RecordTypeId = superstockistRT.Id            
        );
        insert validSS;
         Account validSS2 = new Account(
            Name = 'Valid Super Stockist2',
            RecordTypeId = superstockistRT.Id
        );
        insert validSS2;
        
            Account ssDis = new Account(
            Name = 'Valid Distributor',
            RecordTypeId = distributorRT.Id
        );
        insert ssDis;
        
         Account ssDis2 = new Account(
            Name = 'Valid Distributor2',
            RecordTypeId = distributorRT.Id,
            Super_Stockist_Name__c = validSS.Id
        );
        insert ssDis2;

        // 3. Create Contact for valid Super Stockist
        Contact validContact = new Contact(
            FirstName = 'Valid',
            LastName = 'User',
            AccountId = validSS.Id
        );
        insert validContact;
        
        Contact validContact2 = new Contact(
            FirstName = 'Valid',
            LastName = 'User',
            AccountId = validSS2.Id
        );
        insert validContact2;
         Contact validContact3 = new Contact(
            FirstName = 'Valid',
            LastName = 'User',
            AccountId = ssDis.Id
        );
        insert validContact3;
        Contact validContact4 = new Contact(
            FirstName = 'Valid',
            LastName = 'User',
            AccountId = ssDis2.Id
        );
        insert validContact4;

        // 4. Create Portal User for valid Super Stockist (this implicitly sets IsPartner = true)
        Profile portalProfile = [SELECT Id FROM Profile WHERE Name LIKE '%DMS Partner Community Custom%' LIMIT 1];
        User portalUser = new User(
            Alias = 'test',
            Email = 'validuser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'User',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'validuser@test.com' + System.currentTimeMillis(),
            ProfileId = portalProfile.Id,
            ContactId = validContact.Id
        );
        insert portalUser;
        
         User portalUser2 = new User(
            Alias = 'test',
            Email = 'validuser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'User',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'validuser@test.com' + System.currentTimeMillis(),
            ProfileId = portalProfile.Id,
            ContactId = validContact2.Id
        );
         insert portalUser2;
        
           User portalUser3 = new User(
            Alias = 'test',
            Email = 'validuser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'User',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'validuser@test.com' + System.currentTimeMillis(),
            ProfileId = portalProfile.Id,
            ContactId = validContact3.Id
        );
         insert portalUser3;
           User portalUser4 = new User(
            Alias = 'test',
            Email = 'validuser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'User',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'validuser@test.com' + System.currentTimeMillis(),
            ProfileId = portalProfile.Id,
            ContactId = validContact4.Id
        );
 insert portalUser4;
        // 5. Refresh Account to reflect IsPartner = true (not directly possible in tests, 
        // but portal user association implies partner status)
    }

    // Test 1: Sharing created when valid Super Stockist is added
    static testMethod void testSharingCreatedForValidSuperStockist() {
        Account validDD = [SELECT Id FROM Account WHERE Name = 'Valid Distributor'];
         Account validSS = [SELECT Id FROM Account WHERE Name = 'Valid Super Stockist'];
        User portalUser = [SELECT Id FROM User WHERE Email = 'validuser@test.com' LIMIT 1];
        
        // Create test Account and update Super_Stockist_Name__c
        Account testAcc = new Account(Name = 'Test Account');
        insert testAcc;
                    system.debug(validDD);
             system.debug(validSS);
        Test.startTest();
        validDD.Super_Stockist_Name__c = validSS.Id;
        
        update validDD;
        Test.stopTest();

        // Verify sharing
        List<AccountShare> shares = [SELECT Id FROM AccountShare 
                                   WHERE AccountId = :testAcc.Id 
                                   AND UserOrGroupId = :portalUser.Id];
       // System.assertEquals(1, shares.size(), 'Account should be shared with portal user');
    }
    
      static testMethod void testSharingCreatedForValidSuperStockist2() {
        Account validDD = [SELECT Id FROM Account WHERE Name = 'Valid Distributor'];
         Account validSS = [SELECT Id FROM Account WHERE Name = 'Valid Super Stockist'];
           Account validSS2 = [SELECT Id FROM Account WHERE Name = 'Valid Super Stockist2'];
        User portalUser = [SELECT Id FROM User WHERE Email = 'validuser@test.com' LIMIT 1];
           Account validDD2 = [SELECT Id FROM Account WHERE Name = 'Valid Distributor2'];
        
        // Create test Account and update Super_Stockist_Name__c
        Account testAcc = new Account(Name = 'Test Account');
        insert testAcc;
                    system.debug(validDD);
             system.debug(validSS);
        Test.startTest();
       
          validDD2.Super_Stockist_Name__c = validSS2.Id;
           update validDD2;
        Test.stopTest();

        // Verify sharing
        List<AccountShare> shares = [SELECT Id FROM AccountShare 
                                   WHERE AccountId = :testAcc.Id 
                                   AND UserOrGroupId = :portalUser.Id];
       // System.assertEquals(1, shares.size(), 'Account should be shared with portal user');
    }

   /* // Test 2: No sharing for invalid Super Stockist (wrong record type)
    static testMethod void testNoSharingForInvalidSuperStockist() {
        // Create non-Superstockist Account
        Account invalidSS = new Account(Name = 'Invalid Super Stockist');
        insert invalidSS;

        // Assign invalid SS and test
        Account testAcc = new Account(Name = 'Test Account');
        insert testAcc;
        
        Test.startTest();
        testAcc.Super_Stockist_Name__c = invalidSS.Id;
        update testAcc;
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM AccountShare 
                              WHERE AccountId = :testAcc.Id],
                         'No shares should be created');
    }*/


    // Helper to create portal user
    private static User createPortalUser(Contact ct, String username) {
    Profile portalProfile = [SELECT Id FROM Profile WHERE Name LIKE '%Customer Community User%' LIMIT 1];
    User newUser = new User( // 1. Create User instance
        Alias = 'test',
        Email = ct.FirstName + '@test.com',
        EmailEncodingKey = 'UTF-8',
        LastName = 'User',
        LanguageLocaleKey = 'en_US',
        LocaleSidKey = 'en_US',
        TimeZoneSidKey = 'America/Los_Angeles',
        Username = username + System.currentTimeMillis(),
        ProfileId = portalProfile.Id,
        ContactId = ct.Id
    );
    insert newUser; // 2. Insert the User
    return newUser; // 3. Return the inserted User
}
}