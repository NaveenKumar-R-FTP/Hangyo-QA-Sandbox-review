/**
* Class Name : MonthlyExpenseClaimSchedulerJob
* Test Class  : MonthlyExpenseClaimSchedulerTest
* author      : Pradvith
* CreatedDate : 05-12-24
* Description : Scheduler to cretae the monthly expense records.
* */
public with sharing class MonthlyExpenseClaimSchedulerJob implements Schedulable {
    public void execute(SchedulableContext sc) {
        MonthlyExpenseClaimScheduler.createMonthlyExpenseClaim();
   }
}
/*String cronExp = '0 0 0 1 * ?';
String jobName = 'MonthlyExpenseClaimSchedulerJob';
MonthlyExpenseClaimSchedulerJob scheduler = new MonthlyExpenseClaimSchedulerJob();
System.schedule(jobName, cronExp, scheduler);
*/