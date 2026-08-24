/*Added by Hari - 04/05/2026*/

@IsTest
private class MonthlyAttendanceApprovalBatchTest {
    @IsTest
    static void createsTwelveMonthsForFutureYearWhenUserPredatesYear() {
        Profile std = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = buildUser(std.Id);
        insert u;

        Integer futureYear = Date.today().year() + 10;
        Test.startTest();
        Database.executeBatch(
            new MonthlyAttendanceApprovalBatch(
                futureYear,
                new Set<String>{ 'Standard User' }
            ),
            50
        );
        Test.stopTest();

        String y = String.valueOf(futureYear);
        List<Monthly_Attendance_Approval__c> rows = [
            SELECT Month__c
            FROM Monthly_Attendance_Approval__c
            WHERE User__c = :u.Id AND Year__c = :y
        ];
        System.assertEquals(12, rows.size(), 'Full-year user should receive 12 rows');
    }

    @IsTest
    static void secondRunIsIdempotent() {
        Profile std = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = buildUser(std.Id);
        insert u;

        Integer futureYear = Date.today().year() + 11;
        MonthlyAttendanceApprovalBatch batch = new MonthlyAttendanceApprovalBatch(
            futureYear,
            new Set<String>{ 'Standard User' }
        );

        Test.startTest();
        Database.executeBatch(batch, 50);
        Database.executeBatch(batch, 50);
        Test.stopTest();

        String y = String.valueOf(futureYear);
        Integer count = [
            SELECT COUNT()
            FROM Monthly_Attendance_Approval__c
            WHERE User__c = :u.Id AND Year__c = :y
        ];
        System.assertEquals(12, count);
    }

    private static User buildUser(Id profileId) {
        Long suffix = Crypto.getRandomInteger();
        if (suffix < 0) {
            suffix *= -1;
        }
        String unique = String.valueOf(suffix);
        return new User(
            FirstName = 'Maa',
            LastName = 'BatchTest',
            Email = 'maa.batch.' + unique + '@hangyo.in',
            Username = 'maa.batch.' + unique + '@example.com.test',
            Alias = ('t' + unique).left(8),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileId
        );
    }
}