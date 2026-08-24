@IsTest
private class CreateAttendanceRecordBatchTest {

    @testSetup
    static void setupData() {
        Profile sfaProfile = [
            SELECT Id 
            FROM Profile 
            WHERE Name = 'SFA Profile'
            LIMIT 1
        ];

        User u = new User(
            FirstName = 'Test',
            LastName = 'SFAUser',
            Alias = 'tsfa',
            Email = 'test.sfauser@example.com',
            Username = 'test.sfauser' + DateTime.now().getTime() + '@example.com',
            CommunityNickname = 'tsfa' + DateTime.now().getTime(),
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = sfaProfile.Id
        );
        insert u;
    }

    @IsTest
    static void testBackfillCreatesRecordsWithinLimits() {
        User u = [SELECT Id FROM User WHERE LastName = 'SFAUser' LIMIT 1];

        Date startDate = CreateAttendanceRecordBatch.BACKFILL_START_DATE;
        Date today     = Date.today();
        Date endDate   = today.addDays(-1);

        if (endDate < startDate) {
            return; // nothing to do if before Aug 1 2025
        }

        // Pre-create one manual attendance to verify it is not overridden
        Date manualDate = startDate;
        insert new Attendance__c(
            User__c = u.Id,
            OwnerId = u.Id,
            Date_of_attendance__c = manualDate,
            Leave_Date__c = manualDate,
            Status__c = 'Present',
            Description__c = 'Manual present record',
            Automatic_Attendance_Record__c = false
        );

        Test.startTest();
        // Use test constructor to restrict to ONLY our test user
        Set<Id> testUsers = new Set<Id>{ u.Id };
        CreateAttendanceRecordBatch batch = new CreateAttendanceRecordBatch(testUsers);
        Database.executeBatch(batch, 200); // single execute is fine, but size 200 is okay
        Test.stopTest();

        List<Attendance__c> atts = [
            SELECT Id,
                   User__c,
                   Date_of_attendance__c,
                   Status__c,
                   Automatic_Attendance_Record__c
            FROM Attendance__c
            WHERE User__c = :u.Id
            AND Date_of_attendance__c >= :startDate
            AND Date_of_attendance__c <= :endDate
            ORDER BY Date_of_attendance__c
        ];

        Integer totalDays = startDate.daysBetween(endDate) + 1;
        System.assertEquals(
            totalDays,
            atts.size(),
            'There should be one attendance per day for the test user in the backfill range.'
        );

        // Manual day still present & not automatic
        Attendance__c manualAtt;
        for (Attendance__c a : atts) {
            if (a.Date_of_attendance__c == manualDate) {
                manualAtt = a;
                break;
            }
        }
        System.assertNotEquals(null, manualAtt, 'Manual attendance day must exist.');
        System.assertEquals('Present', manualAtt.Status__c);
        System.assertEquals(false, manualAtt.Automatic_Attendance_Record__c);

        // Other days are automatic Absent
        for (Attendance__c a : atts) {
            if (a.Date_of_attendance__c == manualDate) continue;
            System.assertEquals(true, a.Automatic_Attendance_Record__c);
            System.assertEquals('Absent', a.Status__c);
        }
    }
}