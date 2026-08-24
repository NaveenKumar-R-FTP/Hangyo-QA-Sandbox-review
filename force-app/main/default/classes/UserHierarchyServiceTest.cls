@IsTest
private class UserHierarchyServiceTest {
    
    @TestSetup
    static void setupData() {
        
        UserRole parentRole = new UserRole(
            Name = 'Parent Role'
        );
        insert parentRole;
        
        UserRole childRole = new UserRole(
            Name = 'Child Role',
            ParentRoleId = parentRole.Id
        );
        insert childRole;
        
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User parentUser = new User(
            FirstName = 'Parent',
            LastName = 'User',
            Alias = 'puser',
            Email = 'parent@test.com',
            Username = 'parentusectdbr@test.com',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id,
            UserRoleId = parentRole.Id
        );
        insert parentUser;
        
        User childUser = new User(
            FirstName = 'Child',
            LastName = 'User',
            Alias = 'cuser',
            Email = 'child@test.com',
            Username = 'childusectdbr@test.com',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id,
            UserRoleId = childRole.Id
        );
        insert childUser;
        
        UserRole otherRole = new UserRole(Name = 'Other Role');
        insert otherRole;
        
    }
    
    @IsTest
    static void testGetSubordinatesIncludeSelf() {
        
        User parentUser = [SELECT Id FROM User WHERE FirstName = 'Parent' LIMIT 1];
        
        Test.startTest();
        UserHierarchyService.UserHierarchyResult result =
            UserHierarchyService.getSubordinatesincludeself(parentUser.Id);
        Test.stopTest();
        
        System.assertEquals(2, result.totalUsers, 'Parent + Child expected');
    }
    
    @IsTest
    static void testGetSubordinates() {
        User parentUser = [SELECT Id FROM User WHERE FirstName = 'Parent' LIMIT 1];
        
        Test.startTest();
        UserHierarchyService.UserHierarchyResult result =
            UserHierarchyService.getSubordinates(parentUser.Id);
        Test.stopTest();
        
        System.assertEquals(1, result.totalUsers, 'Only child expected');
    }
    
    
    @IsTest
    static void testGetSubordinatesNoSameRoleUsers() {
        User parentUser = [SELECT Id FROM User WHERE FirstName = 'Parent' LIMIT 1];
        
        Test.startTest();
        UserHierarchyService.UserHierarchyResult result =
            UserHierarchyService.getSubordinatesnosameroleusers(parentUser.Id);
        Test.stopTest();
        
        System.assertEquals(2, result.totalUsers, 'Parent + Child expected');
    }
    
    @IsTest
    static void testGetDirectSubordinates() {
        User parentUser = [SELECT Id FROM User WHERE FirstName = 'Parent' LIMIT 1];
        
        Test.startTest();
        UserHierarchyService.UserHierarchyResult result =
            UserHierarchyService.getDirectSubordinates(parentUser.Id);
        Test.stopTest();
        
        System.assertEquals(2, result.totalUsers, 'Parent + DIRECT child expected');
    }
    
    @IsTest
    static void testGetAllSubordinateUsers() {
        User parentUser = [SELECT Id, UserRoleId FROM User WHERE FirstName = 'Parent' LIMIT 1];
        
        Test.startTest();
        Set<Id> result = UserHierarchyService.getAllSubordinateUsers(new Set<Id>{ parentUser.Id });
        Test.stopTest();
        
        System.assertEquals(2, result.size(), 'Parent + Child user IDs expected');
    }
    
    @IsTest
    static void testGetTotalSubordinates() {
        User parentUser = [SELECT Id FROM User WHERE FirstName = 'Parent' LIMIT 1];
        
        Test.startTest();
        Map<Id, Integer> res = UserHierarchyService.getTotalSubordinates(
            new List<Id>{ parentUser.Id }
        );
        Test.stopTest();
        
        System.assertEquals(1, res.size());
        System.assertEquals(2, res.get(parentUser.Id), 'Parent + Child expected');
    }
    
    @IsTest
    static void testGetAllSubordinateIds() {
        User parentUser = [SELECT Id FROM User WHERE FirstName = 'Parent' LIMIT 1];
        User childUser = [SELECT Id, ManagerId FROM User WHERE FirstName = 'Child' LIMIT 1];
        
        childUser.ManagerId = parentUser.Id;
        update childUser;
        
        Test.startTest();
        Set<Id> ids = UserHierarchyService.getAllSubordinateIds(parentUser.Id);
        Test.stopTest();
        
        System.assertEquals(2, ids.size(), 'Parent + Child expected');
    }
}