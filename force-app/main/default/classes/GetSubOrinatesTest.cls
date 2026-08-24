/**
* Test Class  : GetSubOrinatesTest
* Class Name  : GetSubOrinates
* Author      : Gleveta
* CreatedDate : July 18, 2025	
* Description : Test class for   GetSubOrinates Class.
*               
* */
@isTest
private class GetSubOrinatesTest {

    @testSetup
    static void setupData() {
        // Create User Roles
        UserRole topRole = new UserRole(Name = 'Top Role');
        insert topRole;

        UserRole subRole1 = new UserRole(Name = 'Sub Role 1', ParentRoleId = topRole.Id);
        UserRole subRole2 = new UserRole(Name = 'Sub Role 2', ParentRoleId = topRole.Id);
        insert new List<UserRole>{ subRole1, subRole2 };

        // Fetch Standard Profile
        Profile userProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        // Create Top User (simulating logged-in user)
        User topUser = new User(
            FirstName = 'Top',
            LastName = 'User',
            Alias = 'tuser',
            Email = 'topuser@example.com',
            Username = 'topuser@example.com.test',
            ProfileId = userProfile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            UserRoleId = topRole.Id
        );
        insert topUser;

        // Create subordinate users
        User subUser1 = new User(
            FirstName = 'Sub1',
            LastName = 'User',
            Alias = 'suser1',
            Email = 'subuser1@example.com',
            Username = 'subuser1@example.com.test',
            ProfileId = userProfile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            UserRoleId = subRole1.Id
        );

        User subUser2 = new User(
            FirstName = 'Sub2',
            LastName = 'User',
            Alias = 'suser2',
            Email = 'subuser2@example.com',
            Username = 'subuser2@example.com.test',
            ProfileId = userProfile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            UserRoleId = subRole2.Id
        );

        insert new List<User>{ subUser1, subUser2 };
    }

    @isTest
    static void testGetSubOrinatesUserIds() {
        // Get the top user created in setup
        User topUser = [SELECT Id FROM User WHERE Username = 'topuser@example.com.test' LIMIT 1];

        System.runAs(topUser) {
            Test.startTest();
            Set<Id> resultUserIds = GetSubOrinates.getSubOrinatesUserIds();
            Test.stopTest();

            System.debug('Returned User Ids: ' + resultUserIds);

            // Assert that 3 users are returned: topUser + 2 subordinates
            System.assertEquals(3, resultUserIds.size(), 'Should return top user and two subordinates');
        }
    }
}