/**
* 
* Test Class  : CreateEmployeeLeaveAllowanceTest
* author      : Shyam
* CreatedDate : 21-01-24
* Description : Test class for class CreateEmployeeLeaveAllowanceHandler.
*                
* */
@isTest
public class CreateEmployeeLeaveAllowanceTest {

    @isTest
    static void testCreateEmployeeLeaveAllowanceTrigger() {
        // Step 1: Create required data

        // Create a UserRole for testing
        UserRole testRole = new UserRole(
            Name = 'Test Role',
            DeveloperName = 'TestRole'
        );
        insert testRole;

        // Create a User with a UPI_QR_CODE__c value
        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Alias = 'tuser',
            Email = 'testuser@Hangyo.com',
            Username = 'testuser' + System.currentTimeMillis() + '@Hangyo.com',
            CommunityNickname = 'testuser',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            UserRoleId = testRole.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            UPI_QR_CODE__c = '<img src="sampleQRCode.jpg">'
        );

        // Step 2: Insert the user
        Test.startTest();
        insert testUser;
        Test.stopTest();

        // Step 3: Validate the "after insert" trigger functionality
        List<Employee_Leave_Allowance__c> leaveAllowances = [
            SELECT Name, User__c, Total_Casual_Leave__c
            FROM Employee_Leave_Allowance__c
            WHERE User__c = :testUser.Id
        ];

        System.assertEquals(1, leaveAllowances.size(), 'One leave allowance record should be created.'); 
        //System.assertEquals(testUser.Id, leaveAllowances[0].User__c, 'The leave allowance should be linked to the user.');
        //System.assertEquals(12, leaveAllowances[0].Total_Casual_Leave__c, 'The total casual leave should be set to 12.');

        // Step 4: Validate the "before insert" trigger functionality
        User insertedUser = [SELECT UPI_QR_CODE__c FROM User WHERE Id = :testUser.Id];
        //System.assert(insertedUser.UPI_QR_CODE__c.contains('width="160" height="160"'), 'The UPI_QR_CODE__c field should have resized dimensions.');
    }

    @isTest
    static void testBeforeUpdateTrigger() {
        // Step 1: Create a UserRole and a User
        UserRole testRole = new UserRole(
            Name = 'Test Role',
            DeveloperName = 'TestRole'
        );
        insert testRole;

        User testUser = new User(
            FirstName = 'John',
            LastName = 'Doe',
            Alias = 'jdoe',
            Email = 'johndoe@Hangyo.com',
            Username = 'johndoe' + System.currentTimeMillis() + '@Hangyo.com',
            CommunityNickname = 'johndoe',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            UserRoleId = testRole.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            UPI_QR_CODE__c = '<img src="originalQRCode.jpg">'
        );
        insert testUser;

        // Step 2: Update the user's UPI_QR_CODE__c field
        testUser.UPI_QR_CODE__c = '<img src="updatedQRCode.jpg">';
        Test.startTest();
        update testUser;
        Test.stopTest();

        // Step 3: Validate the "before update" trigger functionality
        User updatedUser = [SELECT UPI_QR_CODE__c FROM User WHERE Id = :testUser.Id];
        System.assert(updatedUser.UPI_QR_CODE__c.contains('width="160" height="160"'), 'The UPI_QR_CODE__c field should have resized dimensions.');
    }

    @isTest
    static void testTriggerWithEmptyQRCode() {
        // Step 1: Create a UserRole and a User without a UPI_QR_CODE__c value
        UserRole testRole = new UserRole(
            Name = 'Test Role',
            DeveloperName = 'TestRole'
        );
        insert testRole;

        User testUser = new User(
            FirstName = 'Jane',
            LastName = 'Smith',
            Alias = 'jsmith',
            Email = 'janesmith@Hangyo.com',
            Username = 'janesmith' + System.currentTimeMillis() + '@Hangyo.com',
            CommunityNickname = 'janesmith',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            UserRoleId = testRole.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        // Step 2: Insert the user
        Test.startTest();
        insert testUser;
        Test.stopTest();

        // Step 3: Validate the user was inserted without changes to the QR code
        User insertedUser = [SELECT UPI_QR_CODE__c FROM User WHERE Id = :testUser.Id];
        System.assert(String.isBlank(insertedUser.UPI_QR_CODE__c), 'The UPI_QR_CODE__c field should remain blank.');
    }
}