/**
* Class Name  : DailyExpenseSchedulerJob
* Test Class  : DailyExpenseRecordSchedulerTest
* author      : Pradvith
* CreatedDate : 15-12-24
* Description : Test class for "MonthlyExpenseClaimSchedulerTest".
* */
public class DailyExpenseSchedulerJob implements Schedulable {
    public void execute(SchedulableContext sc) {	
        DailyExpenseRecordScheduler.createDailyExpenses();
    }
}
/*
String cronExp = '0 01 0 * * ?';
String jobName = 'DailyExpenseSchedulerJob';
DailyExpenseSchedulerJob scheduler = new DailyExpenseSchedulerJob();
System.schedule(jobName, cronExp, scheduler);
*/