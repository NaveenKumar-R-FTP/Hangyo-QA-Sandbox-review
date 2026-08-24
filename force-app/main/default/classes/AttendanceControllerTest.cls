@IsTest
public class AttendanceControllerTest {

    @TestSetup
    static void setupData() {
        // Get the current test user (the running user in test context)
        User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        // Create today's Attendance__c record for the current user with Status__c = 'Present'
        Attendance__c att = new Attendance__c();
        att.User__c  = currentUser.Id;
        att.Date_of_attendance__c  = Date.today();
        att.Status__c = 'Present'; // or 'Present Half Day' – both should return true
        insert att;
    }

    @IsTest
    static void testCheckTodayAttendancePresent_ReturnsTrue() {
        Test.startTest();
        Boolean result = AttendanceController.checkTodayAttendancePresent();
        Test.stopTest();

        System.assertEquals(true, result, 'Method should return true when Present attendance exists for today.');
    }

    @IsTest
    static void testCheckTodayAttendancePresent_ReturnsFalse() {
        // Delete attendance so there is no record for today
        delete [SELECT Id FROM Attendance__c WHERE Date__c = :Date.today() AND User__c = :UserInfo.getUserId()];

        Test.startTest();
        Boolean result = AttendanceController.checkTodayAttendancePresent();
        Test.stopTest();

        System.assertEquals(false, result, 'Method should return false when no Present attendance exists for today.');
    }
}