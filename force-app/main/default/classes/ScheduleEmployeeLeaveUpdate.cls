/**
* Class Name : ScheduleEmployeeLeaveUpdate
* Test Class  : UpdateEmployeeLeaveAllowanceBatchTest
* author      : Shyam
* CreatedDate : 23-01-25
* Description : This is to update all "Employee Leave LeaveAllowance" record on yearly basis (first of Jan for every Yeary).
* */
public with sharing class ScheduleEmployeeLeaveUpdate implements Schedulable {

    public void execute(SchedulableContext sc) {
        // Instantiate the batch class
        /*UpdateEmployeeLeaveAllowanceBatch batch = new UpdateEmployeeLeaveAllowanceBatch();        
        Database.executeBatch(batch, 200);*/
        CreateEmployeeLeaveAllowance.employeeLeaveAllowanceMethod();
    }
    
}
//String cronExp = '0 0 0 1 1 ? *';  Crone expression to run the job on first of Jan every year