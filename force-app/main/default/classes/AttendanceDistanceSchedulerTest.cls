/**
 * @description Test coverage for AttendanceDistanceScheduler.
 */

@IsTest
private class AttendanceDistanceSchedulerTest {

    private static final String TEST_JOB_NAME = 'Attendance Distance Scheduler Test';

    private static List<CronTrigger> queryCronJobsByName(String jobName) {
        return [
            SELECT Id, CronExpression, State, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
        ];
    }

    private static void abortScheduledJobsByName(String jobName) {
        for (CronTrigger cronJob : queryCronJobsByName(jobName)) {
            System.abortJob(cronJob.Id);
        }
    }

    @IsTest
    static void testScheduleDaily_createsCronTrigger() {
        abortScheduledJobsByName(AttendanceDistanceScheduler.JOB_NAME);

        Test.startTest();
        Id jobId = AttendanceDistanceScheduler.scheduleDaily();
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Scheduled job Id should not be null.');

        List<CronTrigger> cronJobs = queryCronJobsByName(AttendanceDistanceScheduler.JOB_NAME);

        System.assertEquals(1, cronJobs.size(), 'Exactly one daily cron job should exist.');
        System.assertEquals(
            AttendanceDistanceScheduler.CRON_EXPRESSION,
            cronJobs[0].CronExpression,
            'Cron expression should be daily at 11:00 PM.'
        );
        System.assertEquals(
            AttendanceDistanceScheduler.JOB_NAME,
            cronJobs[0].CronJobDetail.Name,
            'Scheduled job name should match.'
        );
    }

    @IsTest
    static void testScheduleDaily_throwsWhenJobAlreadyScheduled() {
        abortScheduledJobsByName(AttendanceDistanceScheduler.JOB_NAME);
        AttendanceDistanceScheduler.scheduleDaily();

        Boolean exceptionThrown = false;
        try {
            AttendanceDistanceScheduler.scheduleDaily();
        } catch (Exception ex) {
            exceptionThrown = true;
            System.assert(
                ex.getMessage().contains('already scheduled'),
                'Duplicate schedule should throw an already-scheduled error.'
            );
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'scheduleDaily should throw when the job name is already scheduled.'
        );
    }

    @IsTest
    static void testScheduleViaSystemSchedule_createsCronTrigger() {
        Test.startTest();
        Id jobId = System.schedule(
            TEST_JOB_NAME,
            AttendanceDistanceScheduler.CRON_EXPRESSION,
            new AttendanceDistanceScheduler()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'System.schedule should return a job Id.');

        List<CronTrigger> cronJobs = [
            SELECT Id, CronExpression, CronJobDetail.Name
            FROM CronTrigger
            WHERE Id = :jobId
            LIMIT 1
        ];

        System.assertEquals(1, cronJobs.size(), 'CronTrigger should be created after System.schedule.');
        System.assertEquals(
            AttendanceDistanceScheduler.CRON_EXPRESSION,
            cronJobs[0].CronExpression,
            'Cron expression should match the daily 11:00 PM schedule.'
        );
        System.assertEquals(
            TEST_JOB_NAME,
            cronJobs[0].CronJobDetail.Name,
            'Cron job name should match the scheduled job name.'
        );
    }

    @IsTest
    static void testExecute_startsAttendanceDistanceBatch() {
        Test.startTest();
        new AttendanceDistanceScheduler().execute(null);
        Test.stopTest();

        List<AsyncApexJob> batchJobs = [
            SELECT Id, Status, JobType, ApexClass.Name
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
                AND ApexClass.Name = 'AttendanceDistanceBatch'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        System.assertEquals(1, batchJobs.size(), 'execute() should enqueue AttendanceDistanceBatch.');
        System.assertEquals(
            'AttendanceDistanceBatch',
            batchJobs[0].ApexClass.Name,
            'Enqueued job should be AttendanceDistanceBatch.'
        );
    }

    @IsTest
    static void testExecute_throwsWhenForcedFailure() {
        AttendanceDistanceScheduler.testForceExecuteFailure = true;

        Boolean exceptionThrown = false;
        try {
            new AttendanceDistanceScheduler().execute(null);
        } catch (Exception ex) {
            exceptionThrown = true;
            System.assert(
                ex.getMessage().contains('Forced execute failure'),
                'Forced failure message should propagate from execute catch block.'
            );
        } finally {
            AttendanceDistanceScheduler.testForceExecuteFailure = false;
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'execute catch block should run when batch enqueue is forced to fail.'
        );
    }

    @IsTest
    static void testScheduledJob_executeRunsOnStopTest() {
        Test.startTest();
        Id cronTriggerId = System.schedule(
            'Attendance Distance Scheduler StopTest',
            AttendanceDistanceScheduler.CRON_EXPRESSION,
            new AttendanceDistanceScheduler()
        );
        Test.stopTest();

        System.assertNotEquals(null, cronTriggerId, 'Scheduled cron trigger Id should not be null.');

        List<AsyncApexJob> batchJobs = [
            SELECT Id, ApexClass.Name
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
                AND ApexClass.Name = 'AttendanceDistanceBatch'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        System.assertEquals(
            1,
            batchJobs.size(),
            'Scheduled execute should enqueue AttendanceDistanceBatch on Test.stopTest().'
        );
    }
}