/**
 * @description Batch orchestrator for persisting daily travelled distance on Attendance__c.
 *              Delegates route calculation and Google Directions callouts to
 *              AttendanceGoogleDirectionsService. Contains no route or API logic.
 */
public without sharing class AttendanceDistanceBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {

    @TestVisible
    private static Date processingDateOverride;

    /**
     * @description Resolves the attendance date to process. Always Date.today() in production;
     *              processingDateOverride for unit tests only.
     */
    @TestVisible
    private Date resolveProcessingDate() {
        if (Test.isRunningTest() && processingDateOverride != null) {
            return processingDateOverride;
        }
        return Date.today();
    }

    /**
     * @description Builds the SOQL used to fetch eligible Attendance__c rows.
     *              Kept in one place so filters can be extended without changing execute logic.
     */
    @TestVisible
    private static String buildEligibleAttendanceQuery(Date processingDate) {
        return 'SELECT Id,'
            + ' User__c,'
            + ' Date_of_attendance__c,'
            + ' Location__Latitude__s,'
            + ' Location__Longitude__s,'
            + ' EOD_Location__Latitude__s,'
            + ' EOD_Location__Longitude__s,'
            + ' EOD_Date_Time__c,'
            + ' Total_Distance_Calculated_by_Google_API__c'
            + ' FROM Attendance__c'
            + ' WHERE Date_of_attendance__c = '
            + quoteDateLiteral(processingDate)
            + ' AND User__c != NULL'
            + ' AND Location__Latitude__s != NULL'
            + ' AND Location__Longitude__s != NULL'
            + ' ORDER BY CreatedDate ASC';
    }

    @TestVisible
    private static String quoteDateLiteral(Date value) {
        return value == null ? 'NULL' : String.valueOf(value);
    }

    /**
     * @description Determines whether a record has the minimum data required for route calculation.
     */
    @TestVisible
    private static Boolean isEligibleForRouteCalculation(Attendance__c attendance) {
        return attendance != null
            && attendance.User__c != null
            && attendance.Date_of_attendance__c != null
            && attendance.Location__Latitude__s != null
            && attendance.Location__Longitude__s != null;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date processingDate = resolveProcessingDate();
        System.debug(
            LoggingLevel.INFO,
            'AttendanceDistanceBatch.start | processingDate=' + processingDate
                + ' | batchJobId='
                + (bc != null ? bc.getJobId() : 'null')
        );
        return Database.getQueryLocator(buildEligibleAttendanceQuery(processingDate));
    }

    public void execute(Database.BatchableContext bc, List<Attendance__c> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        List<Attendance__c> recordsToUpdate = new List<Attendance__c>();

        for (Attendance__c attendance : scope) {
            try {
                if (!isEligibleForRouteCalculation(attendance)) {
                    continue;
                }

                Decimal totalDistanceKm = AttendanceGoogleDirectionsService.calculateTotalDistanceKm(
                    attendance.Id,
                    attendance.User__c,
                    attendance.Date_of_attendance__c
                );

                if (totalDistanceKm == null) {
                    continue;
                }

                recordsToUpdate.add(
                    new Attendance__c(
                        Id = attendance.Id,
                        Total_Distance_Calculated_by_Google_API__c = totalDistanceKm.setScale(
                            2,
                            RoundingMode.HALF_UP
                        )
                    )
                );
            } catch (Exception ex) {
                System.debug(
                    LoggingLevel.ERROR,
                    'AttendanceDistanceBatch.execute | attendanceId='
                        + (attendance != null ? attendance.Id : null)
                        + ' | error='
                        + ex.getMessage()
                        + ' | stack='
                        + ex.getStackTraceString()
                );
            }
        }

        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(
            LoggingLevel.INFO,
            'AttendanceDistanceBatch.finish | batchJobId='
                + (bc != null ? bc.getJobId() : 'null')
        );
    }
}