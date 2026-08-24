/**
 * Added by Hari on 04/05/2026
 * Updates Attendance__c.Status__c from EOD vs Attendance_Applied_on__c for rows on the
 * target attendance date where applied time is after 12:30 PM that day and EOD is populated.
 */
public class AttendanceHalfDayAbsentBatch implements Database.Batchable<SObject> {
    private static final Decimal HALF_DAY_THRESHOLD_HOURS = 5;
    private static final String STATUS_HALF_DAY = 'Present Half Day';
    private static final String STATUS_ABSENT = 'Absent';

    /**
     * Added by Hari — @TestVisible hooks so unit tests can drive rows when Date__c / Attendance_Applied_on__c
     * are formula-only in the org. Never set these outside @IsTest; production path is unchanged when null.
     */
    @TestVisible
    static Set<Id> testForcedIds;
    @TestVisible
    static Map<Id, Datetime> testSyntheticAppliedOnById;
    @TestVisible
    static Map<Id, Date> testSyntheticAttendanceDateById;

    @TestVisible
    static void clearTestIsolation() {
        testForcedIds = null;
        testSyntheticAppliedOnById = null;
        testSyntheticAttendanceDateById = null;
    }

    private Date targetDate;

    public AttendanceHalfDayAbsentBatch(Date targetDate) {
        //Added by Hari — explicit null handling instead of ternary
        if (targetDate == null) {
            this.targetDate = Date.today();
        } else {
            this.targetDate = targetDate;
        }
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (Test.isRunningTest() && testForcedIds != null && !testForcedIds.isEmpty()) {
            return Database.getQueryLocator(
                [
                    SELECT Id, Date__c, Attendance_Applied_on__c, EOD_Date_Time__c, Status__c
                    FROM Attendance__c
                    WHERE Id IN :testForcedIds AND EOD_Date_Time__c != NULL AND Status__c = 'Present Half Day / Absent'
                ]
            );
        }

        //Added by Hari — 12:30 PM cutoff on the attendance date; only matching rows are processed
        Datetime appliedAfterCutoff = Datetime.newInstance(this.targetDate, Time.newInstance(12, 30, 0, 0));

        return Database.getQueryLocator(
            [
                SELECT Id, Date__c, Attendance_Applied_on__c, EOD_Date_Time__c, Status__c
                FROM Attendance__c
                WHERE
                    Date__c = :targetDate
                    AND Attendance_Applied_on__c > :appliedAfterCutoff
                    AND EOD_Date_Time__c != NULL AND Status__c = 'Present Half Day / Absent'
            ]
        );
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Attendance__c> toUpdate = new List<Attendance__c>();

        Datetime appliedAfterCutoff = Datetime.newInstance(this.targetDate, Time.newInstance(12, 30, 0, 0));

        for (SObject row : scope) {
            Attendance__c att = (Attendance__c) row;

            Datetime appliedOn = att.Attendance_Applied_on__c;
            Date attendanceDateForFilter = att.Date__c;

            Boolean useSynthetic =
                Test.isRunningTest() &&
                testForcedIds != null &&
                !testForcedIds.isEmpty() &&
                testForcedIds.contains(att.Id);

            if (useSynthetic) {
                if (testSyntheticAppliedOnById != null && testSyntheticAppliedOnById.containsKey(att.Id)) {
                    appliedOn = testSyntheticAppliedOnById.get(att.Id);
                }
                if (testSyntheticAttendanceDateById != null && testSyntheticAttendanceDateById.containsKey(att.Id)) {
                    attendanceDateForFilter = testSyntheticAttendanceDateById.get(att.Id);
                }
                if (attendanceDateForFilter != this.targetDate) {
                    continue;
                }
                if (!(appliedOn > appliedAfterCutoff)) {
                    continue;
                }
            }

            if (appliedOn == null || att.EOD_Date_Time__c == null) {
                continue;
            }

            Long diffMs = att.EOD_Date_Time__c.getTime() - appliedOn.getTime();
            if (diffMs < 0) {
                continue;
            }

            Decimal hours = (Decimal) diffMs / (1000 * 60 * 60);

            //Added by Hari — plain if/else instead of ternary for readability
            String newStatus;
            if (hours >= HALF_DAY_THRESHOLD_HOURS) {
                newStatus = STATUS_HALF_DAY;
            } else {
                newStatus = STATUS_ABSENT;
            }

            if (att.Status__c != newStatus) {
                att.Status__c = newStatus;
                toUpdate.add(att);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    public void finish(Database.BatchableContext bc) {
    }
}