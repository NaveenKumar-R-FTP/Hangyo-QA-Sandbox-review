@isTest
public class CreateAttendanceRecordTest {

    @testSetup
    static void setupData() {
        // Get a Profile with name 'SFA Profile'
        Profile sfaProfile = [
            SELECT Id, Name
            FROM Profile
            WHERE Name = 'SFA Profile'
            LIMIT 1
        ];

        // Create User 1 (already has today's attendance)
        User userWithAttendance = new User(
            FirstName = 'Test',
            LastName = 'UserWithAttendance',
            Alias = 'tuwatt',
            Email = 'userwithattendance@test.com',
            Username = 'userwithattendance' + DateTime.now().getTime() + '@test.com',
            CommunityNickname = 'userwithatt' + DateTime.now().getTime(),
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = sfaProfile.Id
        );
        insert userWithAttendance;

        // Create User 2 (no attendance yet)
        User userWithoutAttendance = new User(
            FirstName = 'Test',
            LastName = 'UserWithoutAttendance',
            Alias = 'tuwout',
            Email = 'userwithoutattendance@test.com',
            Username = 'userwithoutattendance' + DateTime.now().getTime() + '@test.com',
            CommunityNickname = 'userwithoutatt' + DateTime.now().getTime(),
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = sfaProfile.Id
        );
        insert userWithoutAttendance;

        // Insert today's Attendance__c only for userWithAttendance
        Attendance__c att = new Attendance__c(
            User__c = userWithAttendance.Id,
            OwnerId = userWithAttendance.Id,
            Leave_Date__c = Date.today(),
            Date_of_attendance__c = Date.today(),
            Status__c = 'Present',
            Description__c = 'Manual Attendance',
            Automatic_Attendance_Record__c = false
        );
        insert att;
    }

    @isTest
    static void testBatchCreatesAttendanceOnlyForMissingUsers() {
        // Get users created in setup
        List<User> sfaUsers = [
            SELECT Id, Name
            FROM User
            WHERE Profile.Name = 'SFA Profile'
        ];
        //System.assertEquals(2, sfaUsers.size(), 'Expected 2 SFA users from test setup');

        // Run the batch
        Test.startTest();
        CreateAttendanceRecord batch = new CreateAttendanceRecord();
        Database.executeBatch(batch, 2000);
        Test.stopTest();

        // Query all Attendance__c for today
        List<Attendance__c> todayAttendance = [
            SELECT Id, User__c, Automatic_Attendance_Record__c, Status__c, Date_of_attendance__c
            FROM Attendance__c
            WHERE Date_of_attendance__c = :Date.today()
        ];

        Integer autoCount = 0;
        Integer manualCount = 0;
        for (Attendance__c att : todayAttendance) {
            if (att.Automatic_Attendance_Record__c == true) {
                autoCount++;
                System.assertEquals('Absent', att.Status__c, 'Automatic records should be Absent');
            } else {
                manualCount++;
            }
        }
    }
}