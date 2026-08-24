/**
 * @description Schedulable entry point for the daily attendance distance batch job.
 *              Contains no business logic; only initiates AttendanceDistanceBatch.
 *              Intended schedule: daily at 11:00 PM (cron: 0 0 23 * * ?).
 */
public with sharing class AttendanceDistanceScheduler implements Schedulable {

    public static final String JOB_NAME = 'Attendance Distance Calculation - Daily 11 PM';
    public static final String CRON_EXPRESSION = '0 0 23 * * ?';

    @TestVisible
    private static Boolean testForceExecuteFailure = false;

    /**
     * @description Schedules this job to run daily at 11:00 PM.
     * @return Id of the created CronTrigger.
     */
    public static Id scheduleDaily() {
        try {
            Id jobId = System.schedule(JOB_NAME, CRON_EXPRESSION, new AttendanceDistanceScheduler());
            System.debug(
                LoggingLevel.INFO,
                'AttendanceDistanceScheduler.scheduleDaily | Scheduled job Id: ' + jobId
            );
            return jobId;
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.ERROR,
                'AttendanceDistanceScheduler.scheduleDaily | Error: ' + ex.getMessage()
                    + ' | StackTrace: ' + ex.getStackTraceString()
            );
            throw ex;
        }
    }

    /**
     * @description Schedulable execute method. Initiates the distance calculation batch only.
     * @param sc SchedulableContext provided by the platform when the job runs.
     */
    public void execute(SchedulableContext sc) {
        String triggerId = sc != null ? String.valueOf(sc.getTriggerId()) : 'null';

        try {
            if (Test.isRunningTest() && testForceExecuteFailure == true) {
                throw new SchedulerTestException('Forced execute failure for test coverage.');
            }

            Id batchJobId = Database.executeBatch(
                new AttendanceDistanceBatch(),
                20
            );
            System.debug(
                LoggingLevel.INFO,
                'AttendanceDistanceScheduler.execute | CronTrigger Id: ' + triggerId
                    + ' | AttendanceDistanceBatch Job Id: ' + batchJobId
            );
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.ERROR,
                'AttendanceDistanceScheduler.execute | CronTrigger Id: ' + triggerId
                    + ' | Error: ' + ex.getMessage()
                    + ' | StackTrace: ' + ex.getStackTraceString()
            );
            throw ex;
        }
    }

    private class SchedulerTestException extends Exception {
    }
}