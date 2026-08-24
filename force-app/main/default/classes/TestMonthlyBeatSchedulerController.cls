/**
* Test Class : TestMonthlyBeatSchedulerController
* Class Name : MonthlyBeatSchedulerController
* Author     : Hariprasad
* CreatedDate: 03-02-26
* Description: Test class for "MonthlyBeatSchedulerController"
*/

@isTest
public class TestMonthlyBeatSchedulerController {

    /*-----------------------Return Coverage---------------------------*/
    @isTest
    static void testEmptyCoverage() {

        Test.startTest();
        MonthlyBeatSchedulerController.saveMonthlyBeatPlans(null, 0, 2026, null);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Monthly_Beat_Plan__c],
            'No Monthly Beat Plan should be created when input is null'
        );
    }

    /* --------------------------Step 1: Get Active User-----------------------*/
    @isTest
    static void testGetActiveUser() {

        Profile p = [
            SELECT Id FROM Profile
            WHERE Name = 'SFA Profile'
            LIMIT 1
        ];

        User u = new User(
            Alias = 'sfa',
            Email = 'sfa@test.com',
            Username = 'sfa' + System.currentTimeMillis() + '@test.com',
            FirstName = 'SFA',
            LastName = 'User',
            LanguageLocaleKey = 'en_US',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            IsActive = true
        );
        insert u;

        Test.startTest();
        List<User> users = MonthlyBeatSchedulerController.getActiveUsers();
        Test.stopTest();

        System.assert(users.size() > 0);
        System.assertEquals('SFA Profile', users[0].Profile.Name);
    }

    /* ----------------------------Step 2: Get Beats By User -----------------------------*/
    @isTest
    static void testGetBeatsByUser() {

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'usr',
            Email = 'user@test.com',
            Username = 'user' + System.currentTimeMillis() + '@test.com',
            FirstName = 'Test',
            LastName = 'User',
            LanguageLocaleKey = 'en_US',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            IsActive = true
        );
        insert u;

        Beat__c beat = new Beat__c(
            Name = 'Test Beat',
            Employee_Name__c = u.Id
        );
        insert beat;

        insert new Monthly_Beat_Plan__c(
            User__c = u.Id,
            Beat_Name__c = beat.Id,
            Date__c = Date.today(),
            IsActive__c = true
        );

        Test.startTest();
        Map<String, Object> result =
            MonthlyBeatSchedulerController.getBeatsByUser(
                u.Id,
                Date.today().month() - 1,
                Date.today().year()
            );
        Test.stopTest();

        System.assert(result.containsKey('beats'));
        System.assert(result.containsKey('existingPlans'));

        Map<String, Id> existingPlans =
            (Map<String, Id>) result.get('existingPlans');

        System.assertEquals(1, existingPlans.size());
    }

    /*---------------------Step 2A: Inactive Plans are Ignored-------------------------------*/
    @isTest
    static void testGetBeatsByUser_InactivePlanIgnored() {

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'usr2',
            Email = 'user2@test.com',
            Username = 'user2' + System.currentTimeMillis() + '@test.com',
            FirstName = 'Test',
            LastName = 'User',
            LanguageLocaleKey = 'en_US',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            IsActive = true
        );
        insert u;

        Beat__c beat = new Beat__c(
            Name = 'Beat A',
            Employee_Name__c = u.Id
        );
        insert beat;

        insert new Monthly_Beat_Plan__c(
            User__c = u.Id,
            Beat_Name__c = beat.Id,
            Date__c = Date.today(),
            IsActive__c = false
        );

        Test.startTest();
        Map<String, Object> result =
            MonthlyBeatSchedulerController.getBeatsByUser(
                u.Id,
                Date.today().month() - 1,
                Date.today().year()
            );
        Test.stopTest();

        Map<String, Id> existingPlans =
            (Map<String, Id>) result.get('existingPlans');

        System.assertEquals(0, existingPlans.size());
    }

    /*------------------------Step 3: Save Monthly Plan ------------------------*/
    @isTest
    static void testSaveMonthlyBeatPlans() {

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'pln',
            Email = 'planner@test.com',
            Username = 'planner' + System.currentTimeMillis() + '@test.com',
            FirstName = 'Planner',
            LastName = 'User',
            LanguageLocaleKey = 'en_US',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            IsActive = true
        );
        insert u;

        Beat__c beat = new Beat__c(
            Name = 'Monthly Beat',
            Employee_Name__c = u.Id
        );
        insert beat;

        Map<String, Id> beatSelections = new Map<String, Id>();
        beatSelections.put(String.valueOf(Date.today()), beat.Id);

        Test.startTest();
        MonthlyBeatSchedulerController.saveMonthlyBeatPlans(
            u.Id,
            Date.today().month() - 1,
            Date.today().year(),
            beatSelections
        );
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Monthly_Beat_Plan__c WHERE User__c = :u.Id]
        );
    }

    /*-----------------------Step 3A: Invalid Beat Coverage(CONTINUE)------------------*/
    @isTest
    static void testSaveMonthlyBeatPlans_InvalidBeatIgnored() {

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'bad',
            Email = 'bad@test.com',
            Username = 'bad' + System.currentTimeMillis() + '@test.com',
            FirstName = 'Bad',
            LastName = 'Beat',
            LanguageLocaleKey = 'en_US',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            IsActive = true
        );
        insert u;

        Map<String, Id> beatSelections = new Map<String, Id>();
        beatSelections.put(String.valueOf(Date.today()), UserInfo.getUserId()); // invalid beat

        Test.startTest();
        MonthlyBeatSchedulerController.saveMonthlyBeatPlans(
            u.Id,
            Date.today().month() - 1,
            Date.today().year(),
            beatSelections
        );
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Monthly_Beat_Plan__c]);
    }
}