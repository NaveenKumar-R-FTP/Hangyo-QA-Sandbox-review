public class CreateAttendanceRecordBatch implements Database.Batchable<SObject> {

    public static final Date BACKFILL_START_DATE = Date.newInstance(2025, 8, 1);

    // TEST-ONLY: optional filter user Ids
    private Set<Id> testUserIds;

    // Default constructor for normal use
    public CreateAttendanceRecordBatch() {}

    // Test constructor to restrict to specific users
    public CreateAttendanceRecordBatch(Set<Id> testUserIds) {
        this.testUserIds = testUserIds;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        //String soql = 'SELECT Id, Name FROM User WHERE IsActive = TRUE AND Profile.Name = \'SFA Profile\'';
        String soql = 'SELECT Id, Name FROM User WHERE IsActive = TRUE AND Profile.Name IN (\'SFA Profile\', \'SFA Profile - Light\')';

        // If running from a test and specific users are provided, filter by them
        if (Test.isRunningTest() && testUserIds != null && !testUserIds.isEmpty()) {
            soql += ' AND Id IN :testUserIds';
            return Database.getQueryLocator(soql);
        }

        // Normal behavior in production / non-filtered tests
        return Database.getQueryLocator(soql);
    }

    public void execute(Database.BatchableContext bc, List<User> scope) {
        if (scope.isEmpty()) return;

        Date today = Date.today();
        Date startDate = BACKFILL_START_DATE;
        Date endDate   = today.addDays(-1); // backfill only up to yesterday

        if (startDate >= today) {
            return;
        }

        Set<Id> userIds = new Set<Id>();
        for (User u : scope) {
            userIds.add(u.Id);
        }

        Set<String> existingUserDateKeys = new Set<String>();

        for (Attendance__c att : [
            SELECT Id, User__c, Date__c
            FROM Attendance__c
            WHERE User__c IN :userIds
            AND Date__c >= :startDate
            AND Date__c <= :endDate
        ]) {
            String key = att.User__c + '|' + String.valueOf(att.Date__c);
            existingUserDateKeys.add(key);
        }

        List<Attendance__c> attendanceToInsert = new List<Attendance__c>();

        for (User u : scope) {
            Date d = startDate;
            while (d <= endDate) {
                String key = u.Id + '|' + String.valueOf(d);

                if (!existingUserDateKeys.contains(key)) {
                    Attendance__c att = new Attendance__c();
                    att.User__c = u.Id;
                    att.OwnerId = u.Id;

                    att.Leave_Date__c = d;
                    att.Date_of_attendance__c = d;
                    att.Status__c = 'Absent';
                    att.Description__c = 'Automatic backfilled Absent Attendance Record';
                    att.Automatic_Attendance_Record__c = true;

                    attendanceToInsert.add(att);
                }

                d = d.addDays(1);
            }
        }

        if (!attendanceToInsert.isEmpty()) {
            insert attendanceToInsert;
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Backfilled attendance records (Absent) for users who did not mark attendance from 1-Aug-2025 to yesterday.');
    }
}