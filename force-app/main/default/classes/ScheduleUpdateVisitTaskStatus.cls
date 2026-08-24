/**
* Class Name  : ScheduleUpdateVisitTaskStatus
* Test Class  : ScheduleUpdateVisitTaskStatusTest
* author      : Shyam
* CreatedDate : 15-01-25
* Description : This is to scheduled "UpdateVisitTaskStatusBatch"class.
                
* */
public with sharing class ScheduleUpdateVisitTaskStatus implements Schedulable {
    public void execute(SchedulableContext sc) {
        // Instantiate the batch class
        UpdateVisitTaskStatusBatch batch = new UpdateVisitTaskStatusBatch();
        Database.executeBatch(batch, 200);
    }
}
// Schedule the batch to run every day at 12 AM
/*String cronExp = '0 0 0 * * ?'; // Cron expression for 12 AM every day
String jobName = 'UpdateVisitTaskStatusJob'; // Name of the job
ScheduleUpdateVisitTaskStatus scheduler = new ScheduleUpdateVisitTaskStatus();
System.schedule(jobName, cronExp, scheduler);*/