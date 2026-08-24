/**
 * Test Class  : RoleWorkTypeControllerTest
 * Description : Tests for RoleWorkTypeController.getAllowedWorkTypesForCurrentUser
 */
@IsTest
private class RoleWorkTypeControllerTest {

    private static final String ROLE_ASM = 'ASM-RSM-VP KHP';
    private static final String ROLE_BLANK_MAPPING = 'Role With Blank Types';

    @TestSetup
    static void setupTestData() {
        // Mapping with comma-separated work types (including extra spaces to verify trim)
        insert new Role_Work_Type_Mapping__c(
            Name = ROLE_ASM,
            Allowed_Work_Types__c = 'Visit, Meeting , Follow-up'
        );

        // Mapping exists but Allowed_Work_Types__c is blank
        insert new Role_Work_Type_Mapping__c(
            Name = ROLE_BLANK_MAPPING,
            Allowed_Work_Types__c = ''
        );
    }

    @IsTest
    static void testGetAllowedWorkTypes_withValidRole() {
        User testUser = createStandardUser('rwt', ROLE_ASM);

        System.runAs(testUser) {
            Test.startTest();
            List<String> result = RoleWorkTypeController.getAllowedWorkTypesForCurrentUser();
            Test.stopTest();

            System.assertEquals(3, result.size(), 'Should return 3 work types');
            System.assertEquals('Visit', result[0]);
            System.assertEquals('Meeting', result[1]);
            System.assertEquals('Follow-up', result[2]);
        }
    }

    @IsTest
    static void testGetAllowedWorkTypes_blankEmployeeRole() {
        User testUser = createStandardUser('rwtblank', null);

        System.runAs(testUser) {
            Test.startTest();
            List<String> result = RoleWorkTypeController.getAllowedWorkTypesForCurrentUser();
            Test.stopTest();

            System.assertNotEquals(null, result);
            System.assertEquals(0, result.size(), 'Blank role should return empty list');
        }
    }

    @IsTest
    static void testGetAllowedWorkTypes_noMappingFound() {
        User testUser = createStandardUser('rwtno', 'Unknown Role');

        System.runAs(testUser) {
            Test.startTest();
            List<String> result = RoleWorkTypeController.getAllowedWorkTypesForCurrentUser();
            Test.stopTest();

            System.assertNotEquals(null, result);
            System.assertEquals(0, result.size(), 'Missing mapping should return empty list');
        }
    }
    
    public static User createStandardUser(String aliasPrefix, String employeeRole) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'SFA Profile' LIMIT 1];
        String token = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User u = new User(
            Alias = (aliasPrefix + token).left(8),
            Email = aliasPrefix + token + '@hangyo.in',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TrackingTest',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = aliasPrefix + token + '@example.com'
        );
        if (
            String.isNotBlank(employeeRole) &&
            Schema.SObjectType.User.fields.getMap().containsKey('Employee_Role__c')
        ) {
            u.put('Employee_Role__c', employeeRole.trim());
        }
        insert u;
        return u;
    }

    @IsTest
    static void testGetAllowedWorkTypes_blankAllowedWorkTypes() {
        User testUser = createStandardUser('rwtempty', ROLE_BLANK_MAPPING);

        System.runAs(testUser) {
            Test.startTest();
            List<String> result = RoleWorkTypeController.getAllowedWorkTypesForCurrentUser();
            Test.stopTest();

            System.assertNotEquals(null, result);
            System.assertEquals(0, result.size(), 'Blank Allowed_Work_Types__c should return empty list');
        }
    }

    @IsTest
    static void testGetAllowedWorkTypes_runningUserWithRole() {
        // Covers path using UserInfo.getUserId() when role is set on running user
        User runningUser = [
            SELECT Id, Employee_Role__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        if (Schema.SObjectType.User.fields.getMap().containsKey('Employee_Role__c')) {
            runningUser.put('Employee_Role__c', ROLE_ASM);
            update runningUser;
        }

        Test.startTest();
        List<String> result = RoleWorkTypeController.getAllowedWorkTypesForCurrentUser();
        Test.stopTest();

        System.assertEquals(3, result.size());
    }
}