@isTest
public class UserUtilsTest {

    @isTest
    static void testGetSubordinateUserIds_WithSubordinates() {
        // Create a test user role
        UserRole parentRole = new UserRole(Name = 'Parent Role');
        insert parentRole;

        // Create a subordinate role under the parent role
        UserRole childRole = new UserRole(Name = 'Child Role', ParentRoleId = parentRole.Id);
        insert childRole;

        // Create test users with different roles
        User parentUser = new User(
            Username = 'parentUser@test.com.qa', 
            LastName = 'Parent', 
            FirstName = 'User', 
            Alias = 'pUser1', // Alias should be 5 characters
            Email = 'parentUser@test.com',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            UserRoleId = parentRole.Id, 
            TimeZoneSidKey = 'America/New_York', 
            LocaleSidKey = 'en_US', 
            LanguageLocaleKey = 'en_US', 
            EmailEncodingKey = 'UTF-8', 
            Country = 'US'
        );
        insert parentUser;

        User childUser = new User(
            Username = 'childUser@test.com.qa', 
            LastName = 'Child', 
            FirstName = 'User', 
            Alias = 'cUser1', // Alias should be 5 characters
            Email = 'childUser@test.com',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            UserRoleId = childRole.Id, 
            TimeZoneSidKey = 'America/New_York', 
            LocaleSidKey = 'en_US', 
            LanguageLocaleKey = 'en_US', 
            EmailEncodingKey = 'UTF-8', 
            Country = 'US'
        );
        insert childUser;

        // Log in as the parent user
        System.runAs(parentUser) {
            // Get the subordinate user IDs using the method
            Set<Id> subordinateUserIds = UserUtils.getSubordinateUserIds();

            // Assert that the child user's ID is included
            System.assert(subordinateUserIds.contains(childUser.Id), 'Child user should be in the subordinate list');
            System.assert(subordinateUserIds.contains(parentUser.Id), 'Parent user should be in the subordinate list');
        }
    }

    @isTest
    static void testGetSubordinateUserIds_NoSubordinates() {
        // Create a user with no subordinates (no child roles)
        UserRole parentRole = new UserRole(Name = 'Parent Role');
        insert parentRole;

        User parentUser = new User(
            Username = 'parent2User2@test.com.qa', 
            LastName = 'Parent2', 
            FirstName = 'User2', 
            Alias = 'pUser2', // Alias should be 5 characters
            Email = 'parentUser2@test.com',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            UserRoleId = parentRole.Id, 
            TimeZoneSidKey = 'America/New_York', 
            LocaleSidKey = 'en_US', 
            LanguageLocaleKey = 'en_US', 
            EmailEncodingKey = 'UTF-8', 
            Country = 'US'
        );
        insert parentUser;

        // Log in as the parent user
        System.runAs(parentUser) {
            // Get the subordinate user IDs using the method
            Set<Id> subordinateUserIds = UserUtils.getSubordinateUserIds();

            // Assert that only the parent user is in the set
            System.assert(subordinateUserIds.size() == 1, 'Only the parent user should be in the subordinate list');
        }
    }

    @isTest
    static void testGetSubordinateUserIds_EmptySubordinates() {
        // Create a user with a subordinate role but no users in that role
        UserRole parentRole = new UserRole(Name = 'Parent Role');
        insert parentRole;

        UserRole childRole = new UserRole(Name = 'Child Role', ParentRoleId = parentRole.Id);
        insert childRole;

        User parentUser = new User(
            Username = 'parent3User3@test.com.qa', 
            LastName = 'Parent3', 
            FirstName = 'User3', 
            Alias = 'pUser3', // Alias should be 5 characters
            Email = 'parentUser3@test.com',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            UserRoleId = parentRole.Id, 
            TimeZoneSidKey = 'America/New_York', 
            LocaleSidKey = 'en_US', 
            LanguageLocaleKey = 'en_US', 
            EmailEncodingKey = 'UTF-8', 
            Country = 'US'
        );
        insert parentUser;

        // Log in as the parent user (but no users in the child role)
        System.runAs(parentUser) {
            Set<Id> subordinateUserIds = UserUtils.getSubordinateUserIds();
            // Assert that only the parent user is in the set since there are no subordinates
            System.assert(subordinateUserIds.size() == 1, 'Only the parent user should be in the subordinate list');
        }
    }
}