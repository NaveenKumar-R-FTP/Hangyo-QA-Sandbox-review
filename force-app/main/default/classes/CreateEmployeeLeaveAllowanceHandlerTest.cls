/**
* 
* Test Class  : CreateEmployeeLeaveAllowanceHandlerTest
* author      : Shyam
* CreatedDate : 21-01-25
* Description : Test class for class CreateEmployeeLeaveAllowanceHandler.
*                
* */
@isTest
public class CreateEmployeeLeaveAllowanceHandlerTest {

    @isTest
    static void testCreateEmployeeLeaveAllowancesAsync() {
        // Step 1: Create test data

        // Create a UserRole
        UserRole testRole = new UserRole(
            Name = 'Test Role',
            DeveloperName = 'TestRole'
        );
        insert testRole;
        
      

        // Create Users
        User user1 = new User(
            Alias = 'Sam',
            Email = 'Samsahaw1@hangyo.com',
            ProfileId = UserInfo.getProfileId(),
            Username = 'Samsahaw1@hangyo.com',
            FirstName = 'John',
            LastName = 'Doe',
            LanguageLocaleKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            Employee_Role__c = 'SSO',
            IsActive = true
        );

        User user2 = new User(
            Alias = 'JaneSmt',
            Email = 'janesmith1@hangyo.com',
            ProfileId = UserInfo.getProfileId(),
            Username = 'janesmith1@hangyo.com',
            FirstName = 'Jane',
            LastName = 'Smith',
            LanguageLocaleKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            Employee_Role__c = 'SSO',
            IsActive = true
        );
        
        insert new List<User> { user1, user2 };

        // Step 2: Call the future method
        Test.startTest();
        CreateEmployeeLeaveAllowanceHandler.createEmployeeLeaveAllowancesAsync(
            new Set<Id> { user1.Id, user2.Id }
        );
        Test.stopTest();

        // Step 3: Verify the results
        List<Employee_Leave_Allowance__c> allowances = [
            SELECT Name, User__c, Total_Casual_Leave__c
            FROM Employee_Leave_Allowance__c
            WHERE User__c IN :new Set<Id> { user1.Id, user2.Id }
        ];

        System.assertEquals(12, allowances[0].Total_Casual_Leave__c);
        System.assertEquals(12, allowances[1].Total_Casual_Leave__c);
    }

    @isTest
    static void testNoUsersProvided() {
        // Step 1: Call the future method with an empty set
        Test.startTest();
        CreateEmployeeLeaveAllowanceHandler.createEmployeeLeaveAllowancesAsync(new Set<Id>());
        Test.stopTest();

        // Step 2: Verify no records are created
        List<Employee_Leave_Allowance__c> allowances = [
            SELECT Id FROM Employee_Leave_Allowance__c
        ];
        System.assertEquals(0, allowances.size(), 'No leave allowance records should be created.');
    }

    @isTest
    static void testNullInput() {
        // Step 1: Call the future method with null
        Test.startTest();
        CreateEmployeeLeaveAllowanceHandler.createEmployeeLeaveAllowancesAsync(null);
        Test.stopTest();

        // Step 2: Verify no records are created
        List<Employee_Leave_Allowance__c> allowances = [
            SELECT Id FROM Employee_Leave_Allowance__c
        ];
        System.assertEquals(0, allowances.size(), 'No leave allowance records should be created.');
    }
}