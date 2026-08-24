@isTest
private class AttendanceAbsentSchedulerTest {

    // Common method to create test user
    private static User createTestUser() {

        Profile p = [SELECT Id FROM Profile WHERE Name = 'SFA Profile' LIMIT 1];

        User usr = new User(
            FirstName = 'Test',
            LastName = 'User',
            Alias = 'tuser',
            Email = 'testuser@hangyo.in',
            Username = 'testuser' + System.currentTimeMillis() + '@test.com',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        insert usr;
        return usr;
    }

    @isTest
    static void testUpdateAttendanceStatus() {

        User testUser = createTestUser();

        // Create test Attendance records
        Attendance__c att1 = new Attendance__c(
            User__c = testUser.Id,
            Status__c = 'Present',
            Date_of_attendance__c = Date.today()
        );

        Attendance__c att2 = new Attendance__c(
            User__c = testUser.Id,
            Status__c = 'Late',
            Date_of_attendance__c = Date.today()
        );

        Attendance__c att3 = new Attendance__c(
            User__c = testUser.Id,
            Status__c = 'Absent',
            Date_of_attendance__c = Date.today()
        );

        Attendance__c att4 = new Attendance__c(
            User__c = testUser.Id,
            Status__c = 'Present',
            Date_of_attendance__c = Date.today(),
            EOD_Date_Time__c = System.now()
        );

        insert new List<Attendance__c>{att1, att2, att3, att4};

        Test.startTest();

        // Execute scheduler method
        AttendanceAbsentScheduler.updateAttendanceStatus();

        Test.stopTest();

        // Fetch updated records
        List<Attendance__c> updatedList = [ SELECT Id, Status__c, EOD_Date_Time__c FROM Attendance__c  ORDER BY CreatedDate];

        System.assertEquals('Absent', updatedList[0].Status__c, 'att1 should be marked Absent');
        System.assertEquals('Absent', updatedList[1].Status__c, 'att2 should be marked Absent');
        System.assertEquals('Absent', updatedList[2].Status__c, 'att3 should remain Absent');
        System.assertEquals('Present', updatedList[3].Status__c, 'att4 should not be updated');
    }

    @isTest
    static void testSchedulerExecution() {

        User testUser = createTestUser();

        Attendance__c att = new Attendance__c(
            User__c = testUser.Id,
            Status__c = 'Present',
            Date_of_attendance__c = Date.today()
        );

        insert att;

        Test.startTest();

        String cronExp = '0 0 23 * * ?';
        System.schedule( 'Attendance Absent Scheduler Test', cronExp, new AttendanceAbsentScheduler());

        Test.stopTest();

        Attendance__c updatedAtt = [ SELECT Id, Status__c FROM Attendance__c WHERE Id = :att.Id];
        System.assertEquals('Absent', updatedAtt.Status__c);
    }
}