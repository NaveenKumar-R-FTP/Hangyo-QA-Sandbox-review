@isTest
public class ScheduleBeatPlanTest {

    @testSetup
    static void setupData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;

        /* -------- Create User -------- */
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@test.com',
            Username = 'testuser' + System.currentTimeMillis() + '@test.com',
            Alias = 'tuser',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert testUser;

        /* -------- Create Beat -------- */
        Beat__c beat = new Beat__c(
            Name = 'Test Beat'
        );
        insert beat;

        /* -------- Create Attendance (Present) -------- */
        Attendance__c attendance = new Attendance__c(
            User__c = testUser.Id,
            Status__c = 'Present'
        );
        insert attendance;

        /* -------- Create Monthly Beat Plan -------- */
        Monthly_Beat_Plan__c mbp = new Monthly_Beat_Plan__c(
            User__c = testUser.Id,
            Beat_Name__c = beat.Id,
            Date__c = Date.today(),
            IsActive__c = true
        );
        insert mbp;

        /* -------- Create Retailer Account -------- */
        RecordType retailerRT = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account'
            AND Name = 'Retailer'
            LIMIT 1
        ];

        Account retailer = new Account(
            Name = 'Test Retailer',
            RecordTypeId = retailerRT.Id,
            Beats_Name__c = beat.Id
        );
        insert retailer;
    }

    @isTest
    static void testCreateVisitTask() {

        /* -------- Fetch Attendance -------- */
        Attendance__c attendance = [
            SELECT Id FROM Attendance__c LIMIT 1
        ];

        Set<Id> attendanceIds = new Set<Id>{ attendance.Id };

        Test.startTest();
        ScheduleBeatPlan.createVisitTask(attendanceIds);
        Test.stopTest();

        /* -------- Verify Visit Created -------- */
        List<Visit__c> visits = [
            SELECT Id, OwnerId, Beat__c
            FROM Visit__c
        ];
        System.assertEquals(1, visits.size(), 'Visit should be created');

        /* -------- Verify Visit Task Created -------- */
        List<Visit_Task__c> tasks = [
            SELECT Id, Visit__c, Retailer__c
            FROM Visit_Task__c
        ];
        System.assertEquals(1, tasks.size(), 'Visit Task should be created');
    }
    
    @isTest
    static void testCreateVisitTaskOnAttendanceChange() {
        User testUser = [SELECT Id FROM User WHERE isActive = true AND Profile.Name = 'SFA Profile' LIMIT 1];

        /* -------- Fetch Attendance -------- */
        Attendance__c attendance = new Attendance__c(
            User__c = testUser.Id,
            Status__c = 'Leave'
        );
        insert attendance;
        
        Attendance__c attendanceUpdate = new Attendance__c(
            Id = attendance.Id,
            User__c = testUser.Id,
            Status__c = 'Leave'
        );
        Update attendanceUpdate;

        Set<Id> attendanceIds = new Set<Id>{ attendanceUpdate.Id };

        Test.startTest();
        ScheduleBeatPlan.createVisitTask(attendanceIds);
        Test.stopTest();
    }

    @isTest
    static void testDuplicatePrevention() {

        Attendance__c attendance = [
            SELECT Id FROM Attendance__c LIMIT 1
        ];

        Set<Id> attendanceIds = new Set<Id>{ attendance.Id };

        Test.startTest();
        // First execution
        ScheduleBeatPlan.createVisitTask(attendanceIds);

        // Second execution (should not create duplicates)
        ScheduleBeatPlan.createVisitTask(attendanceIds);
        Test.stopTest();

        List<Visit__c> visits = [
            SELECT Id FROM Visit__c
        ];

        System.assertEquals(1, visits.size(),
            'Duplicate Visit should not be created');
    }
}