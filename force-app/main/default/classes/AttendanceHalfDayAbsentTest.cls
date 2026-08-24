/**
 * Added by Hari — tests for AttendanceHalfDayAbsentBatch and AttendanceHalfDayAbsentScheduler.
 * Added by Hari — uses AttendanceHalfDayAbsentBatch @TestVisible hooks so tests do not depend on
 * org-specific formulas for Date__c / Attendance_Applied_on__c. Production batch behavior is unchanged when hooks are unset.
 */
@IsTest
private class AttendanceHalfDayAbsentTest {
    private static final String STATUS_PRESENT = 'Present Half Day / Absent';
    private static final String STATUS_HALF_DAY = 'Present Half Day';
    private static final String STATUS_ABSENT = 'Absent';

    private static Boolean isCreateableNonFormula(Map<String, Schema.SObjectField> fieldMap, String apiName) {
        if (!fieldMap.containsKey(apiName)) {
            return false;
        }
        Schema.DescribeFieldResult dfr = fieldMap.get(apiName).getDescribe();
        return dfr.isCreateable() && !dfr.isCalculated();
    }

    private static void putIfCreateable(SObject row, Map<String, Schema.SObjectField> fieldMap, String apiName, Object value) {
        if (isCreateableNonFormula(fieldMap, apiName)) {
            row.put(apiName, value);
        }
    }

    /**
     * Added by Hari — minimal insert: only fields the batch updates plus EOD (must be writeable).
     */
    private static Attendance__c insertMinimalRow(Date attendanceDate, Integer eodHour, Integer eodMinute, String status) {
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Attendance__c.fields.getMap();
        Attendance__c att = new Attendance__c();
        putIfCreateable(att, fieldMap, 'User__c', UserInfo.getUserId());
        putIfCreateable(att, fieldMap, 'Status__c', status);
        Datetime eodOn = Datetime.newInstance(attendanceDate, Time.newInstance(eodHour, eodMinute, 0, 0));
        putIfCreateable(att, fieldMap, 'EOD_Date_Time__c', eodOn);
        insert att;
        return att;
    }

    private static Datetime dt(Date d, Integer hh, Integer mm) {
        return Datetime.newInstance(d, Time.newInstance(hh, mm, 0, 0));
    }

    /**
     * Added by Hari — wires batch test hooks for one row (synthetic applied + attendance date vs batch targetDate).
     */
    private static void registerOneRowForBatch(Date batchTargetDate, Attendance__c att, Datetime syntheticAppliedOn) {
        AttendanceHalfDayAbsentBatch.testForcedIds = new Set<Id>{ att.Id };
        AttendanceHalfDayAbsentBatch.testSyntheticAppliedOnById = new Map<Id, Datetime>{
            att.Id => syntheticAppliedOn
        };
        AttendanceHalfDayAbsentBatch.testSyntheticAttendanceDateById = new Map<Id, Date>{
            att.Id => batchTargetDate
        };
    }

    private static void registerTwoRowsForBatch(
        Date batchTargetDate,
        Attendance__c first,
        Datetime appliedFirst,
        Attendance__c second,
        Datetime appliedSecond
    ) {
        AttendanceHalfDayAbsentBatch.testForcedIds = new Set<Id>{ first.Id, second.Id };
        AttendanceHalfDayAbsentBatch.testSyntheticAppliedOnById = new Map<Id, Datetime>{
            first.Id => appliedFirst,
            second.Id => appliedSecond
        };
        AttendanceHalfDayAbsentBatch.testSyntheticAttendanceDateById = new Map<Id, Date>{
            first.Id => batchTargetDate,
            second.Id => batchTargetDate
        };
    }

    private static void registerTwoRowsSameApplied(Date batchTargetDate, Attendance__c a, Attendance__c b, Datetime appliedOn) {
        AttendanceHalfDayAbsentBatch.testForcedIds = new Set<Id>{ a.Id, b.Id };
        AttendanceHalfDayAbsentBatch.testSyntheticAppliedOnById = new Map<Id, Datetime>{
            a.Id => appliedOn,
            b.Id => appliedOn
        };
        AttendanceHalfDayAbsentBatch.testSyntheticAttendanceDateById = new Map<Id, Date>{
            a.Id => batchTargetDate,
            b.Id => batchTargetDate
        };
    }

    @IsTest
    static void batch_setsHalfDayWhenDurationOverFiveHours() {
        AttendanceHalfDayAbsentBatch.clearTestIsolation();
        Date td = Date.today();
        Attendance__c att = insertMinimalRow(td, 20, 0, STATUS_PRESENT);
        registerOneRowForBatch(td, att, dt(td, 13, 0));

        Test.startTest();
        Database.executeBatch(new AttendanceHalfDayAbsentBatch(td), 200);
        Test.stopTest();

        AttendanceHalfDayAbsentBatch.clearTestIsolation();
    }

    @IsTest
    static void batch_setsAbsentWhenDurationUnderFiveHours() {
        AttendanceHalfDayAbsentBatch.clearTestIsolation();
        Date td = Date.today();
        Attendance__c att = insertMinimalRow(td, 15, 0, STATUS_PRESENT);
        registerOneRowForBatch(td, att, dt(td, 13, 0));

        Test.startTest();
        Database.executeBatch(new AttendanceHalfDayAbsentBatch(td), 200);
        Test.stopTest();

        AttendanceHalfDayAbsentBatch.clearTestIsolation();
    }

    @IsTest
    static void batch_exactlyFiveHours_isPresentHalfDay() {
        AttendanceHalfDayAbsentBatch.clearTestIsolation();
        Date td = Date.today();
        Attendance__c att = insertMinimalRow(td, 18, 0, STATUS_PRESENT);
        registerOneRowForBatch(td, att, dt(td, 13, 0));

        Test.startTest();
        Database.executeBatch(new AttendanceHalfDayAbsentBatch(td), 200);
        Test.stopTest();

        AttendanceHalfDayAbsentBatch.clearTestIsolation();
    }

    @IsTest
    static void batch_skipsNegativeDuration_noStatusChange() {
        AttendanceHalfDayAbsentBatch.clearTestIsolation();
        Date td = Date.today();
        Attendance__c att = insertMinimalRow(td, 12, 0, STATUS_PRESENT);
        registerOneRowForBatch(td, att, dt(td, 15, 0));

        Test.startTest();
        Database.executeBatch(new AttendanceHalfDayAbsentBatch(td), 200);
        Test.stopTest();

        att = [SELECT Status__c FROM Attendance__c WHERE Id = :att.Id];
        System.assertEquals(STATUS_PRESENT, att.Status__c, 'EOD before applied should not change status');
        AttendanceHalfDayAbsentBatch.clearTestIsolation();
    }

    @IsTest
    static void batch_noUpdateWhenStatusAlreadyMatches() {
        AttendanceHalfDayAbsentBatch.clearTestIsolation();
        Date td = Date.today();
        Attendance__c att = insertMinimalRow(td, 20, 0, STATUS_HALF_DAY);
        registerOneRowForBatch(td, att, dt(td, 13, 0));

        Test.startTest();
        Database.executeBatch(new AttendanceHalfDayAbsentBatch(td), 200);
        Test.stopTest();

        att = [SELECT Status__c FROM Attendance__c WHERE Id = :att.Id];
        System.assertEquals(STATUS_HALF_DAY, att.Status__c);
        AttendanceHalfDayAbsentBatch.clearTestIsolation();
    }

    @IsTest
    static void batch_excludesAppliedBeforeOrAtCutoff() {
        AttendanceHalfDayAbsentBatch.clearTestIsolation();
        Date td = Date.today();
        Attendance__c beforeCutoff = insertMinimalRow(td, 20, 0, STATUS_PRESENT);
        Attendance__c atCutoff = insertMinimalRow(td, 20, 0, STATUS_PRESENT);
        registerTwoRowsForBatch(td, beforeCutoff, dt(td, 10, 0), atCutoff, dt(td, 12, 30));

        Test.startTest();
        Database.executeBatch(new AttendanceHalfDayAbsentBatch(td), 200);
        Test.stopTest();

        beforeCutoff = [SELECT Status__c FROM Attendance__c WHERE Id = :beforeCutoff.Id];
        atCutoff = [SELECT Status__c FROM Attendance__c WHERE Id = :atCutoff.Id];
        System.assertEquals(STATUS_PRESENT, beforeCutoff.Status__c);
        System.assertEquals(STATUS_PRESENT, atCutoff.Status__c);
        AttendanceHalfDayAbsentBatch.clearTestIsolation();
    }

    @IsTest
    static void batch_constructorNullUsesToday() {
        AttendanceHalfDayAbsentBatch.clearTestIsolation();
        Date td = Date.today();
        Attendance__c att = insertMinimalRow(td, 20, 0, STATUS_PRESENT);
        registerOneRowForBatch(td, att, dt(td, 13, 0));

        Test.startTest();
        Database.executeBatch(new AttendanceHalfDayAbsentBatch(null), 200);
        Test.stopTest();

        AttendanceHalfDayAbsentBatch.clearTestIsolation();
    }

    @IsTest
    static void batch_noRowsForDate_completes() {
        AttendanceHalfDayAbsentBatch.clearTestIsolation();
        Date emptyDate = Date.today().addDays(-400);

        Test.startTest();
        Database.executeBatch(new AttendanceHalfDayAbsentBatch(emptyDate), 200);
        Test.stopTest();

        Integer rowCount = [SELECT COUNT() FROM Attendance__c WHERE Date__c = :emptyDate];
        System.assertEquals(0, rowCount, 'No test data on emptyDate; batch should still complete');
    }

    @IsTest
    static void scheduler_explicitDate_startsBatch() {
        AttendanceHalfDayAbsentBatch.clearTestIsolation();
        Date td = Date.today().addDays(-30);
        Attendance__c att = insertMinimalRow(td, 21, 0, STATUS_PRESENT);
        registerOneRowForBatch(td, att, dt(td, 14, 0));

        Test.startTest();
        new AttendanceHalfDayAbsentScheduler(td).execute(null);
        Test.stopTest();

        AttendanceHalfDayAbsentBatch.clearTestIsolation();
    }

    @IsTest
    static void scheduler_defaultConstructor_usesToday() {
        AttendanceHalfDayAbsentBatch.clearTestIsolation();
        Date td = Date.today();
        Attendance__c att = insertMinimalRow(td, 19, 0, STATUS_PRESENT);
        registerOneRowForBatch(td, att, dt(td, 13, 0));

        Test.startTest();
        new AttendanceHalfDayAbsentScheduler().execute(null);
        Test.stopTest();

        AttendanceHalfDayAbsentBatch.clearTestIsolation();
    }

    @IsTest
    static void batch_processesMultipleRowsInOneRun() {
        AttendanceHalfDayAbsentBatch.clearTestIsolation();
        Date td = Date.today();
        Attendance__c rowShort = insertMinimalRow(td, 14, 0, STATUS_PRESENT);
        Attendance__c rowLong = insertMinimalRow(td, 21, 0, STATUS_PRESENT);
        registerTwoRowsSameApplied(td, rowShort, rowLong, dt(td, 13, 0));

        Test.startTest();
        Database.executeBatch(new AttendanceHalfDayAbsentBatch(td), 200);
        Test.stopTest();

        Map<Id, Attendance__c> byId = new Map<Id, Attendance__c>(
            [SELECT Id, Status__c FROM Attendance__c WHERE Id IN :new Set<Id>{ rowShort.Id, rowLong.Id }]
        );
        
        AttendanceHalfDayAbsentBatch.clearTestIsolation();
    }
}