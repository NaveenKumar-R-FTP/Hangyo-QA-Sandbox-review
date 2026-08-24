/**
 * Added by Hari - 04/05/2026
 * Ensures each eligible user has one Monthly_Attendance_Approval__c per applicable
 * calendar month for a given year (Attendance links via Monthly_Attendance_Approval__c).
 *
 * Profile filter defaults to SFA Profile and SFA Profile - Light (Profile.Name).
 * Start-of-employment uses User.CreatedDate; switch the query/shape if you store join date elsewhere.
 *
 * Month__c picklist values must match MONTH_ORDER (API values). Adjust if your picklist differs.
 */

public without sharing class MonthlyAttendanceApprovalBatch implements Database.Batchable<sObject> {
    private final Integer targetYear;
    private final Set<String> profileNames;

    /** Picklist API values for Month__c, index 0 = January. */
    private static final List<String> MONTH_ORDER = new List<String>{
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
    };

    private static Set<String> defaultProfileNames() {
        return new Set<String>{ 'SFA Profile', 'SFA Profile - Light' };
    }

    public MonthlyAttendanceApprovalBatch() {
        this(Date.today().year(), defaultProfileNames());
    }

    public MonthlyAttendanceApprovalBatch(Integer year) {
        this(year, defaultProfileNames());
    }

    public MonthlyAttendanceApprovalBatch(Integer year, Set<String> profileNames) {
        if (year == null) {
            throw new IllegalArgumentException('year is required');
        }
        if (profileNames == null || profileNames.isEmpty()) {
            throw new IllegalArgumentException('profileNames is required');
        }
        this.targetYear = year;
        this.profileNames = new Set<String>(profileNames);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            [
                SELECT Id, Name, CreatedDate
                FROM User
                WHERE
                    IsActive = TRUE
                    AND Profile.Name IN :profileNames
            ]
        );
    }

    public void execute(Database.BatchableContext bc, List<sObject> scope) {
        List<User> users = (List<User>) scope;
        if (users.isEmpty()) {
            return;
        }

        Set<Id> userIds = new Map<Id, User>(users).keySet();
        String yearText = String.valueOf(targetYear);

        Map<String, Monthly_Attendance_Approval__c> existingByKey = new Map<String, Monthly_Attendance_Approval__c>();
        for (Monthly_Attendance_Approval__c row : [
            SELECT Id, User__c, Month__c, Year__c
            FROM Monthly_Attendance_Approval__c
            WHERE User__c IN :userIds AND Year__c = :yearText
        ]) {
            existingByKey.put(compositeKey(row.User__c, row.Month__c), row);
        }

        List<Monthly_Attendance_Approval__c> toInsert = new List<Monthly_Attendance_Approval__c>();

        for (User u : users) {
            Date joinDate = u.CreatedDate.date();
            Integer startMonth = resolveStartMonth(joinDate, targetYear);
            if (startMonth == null) {
                continue;
            }

            for (Integer m = startMonth; m <= 12; m++) {
                String monthVal = MONTH_ORDER[m - 1];
                String key = compositeKey(u.Id, monthVal);
                if (existingByKey.containsKey(key)) {
                    continue;
                }

                Monthly_Attendance_Approval__c rec = new Monthly_Attendance_Approval__c(
                    User__c = u.Id,
                    OwnerId = u.Id,
                    Month__c = monthVal,
                    Year__c = yearText,
                    Number_Of_Approvals__c = 0,
                    Name = buildRecordName(u, monthVal, yearText)
                );
                toInsert.add(rec);
                existingByKey.put(key, rec);
            }
        }

        if (!toInsert.isEmpty()) {
            for (Database.SaveResult sr : Database.insert(toInsert, false)) {
                if (!sr.isSuccess()) {
                    for (Database.Error err : sr.getErrors()) {
                        System.debug(
                            LoggingLevel.ERROR,
                            'MonthlyAttendanceApprovalBatch insert failed: ' + err.getMessage()
                        );
                    }
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
    }

    /**
     * First month in targetYear for which a row should exist.
     * null if the user should have no rows for that year (joined after target year).
     */
    private static Integer resolveStartMonth(Date joinDate, Integer year) {
        if (joinDate.year() > year) {
            return null;
        }
        if (joinDate.year() < year) {
            return 1;
        }
        return joinDate.month();
    }

    private static String compositeKey(Id userId, String monthVal) {
        return String.valueOf(userId) + '|' + monthVal;
    }

    private static String buildRecordName(User u, String monthLabel, String yearStr) {
        String base =
            (String.isBlank(u.Name) ? 'User' : u.Name) + ' - ' + monthLabel + ' ' + yearStr;
        return base.length() > 80 ? base.substring(0, 80) : base;
    }
}