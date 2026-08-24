/**
* Class Name : UpdateEmployeeLeaveAllowanceBatch
* Test Class  : UpdateEmployeeLeaveAllowanceBatchTest
* author      : Shyam
* CreatedDate : 23-01-25
* Description : This is to update all "Employee Leave LeaveAllowance" record on yearly basis (first of Jan for every Yeary).
* */

public class UpdateEmployeeLeaveAllowanceBatch implements Database.Batchable<SObject> {
    
    public String query;
    
    public UpdateEmployeeLeaveAllowanceBatch() {
        query = 'SELECT Id, User__c, User__r.FirstName, User__r.LastName FROM Employee_Leave_Allowance__c'; 
    }
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(query);
    }
    
    public void execute(Database.BatchableContext bc, List<Employee_Leave_Allowance__c> leaveAllowanceList) {
        // Retrieve Custom Settings values
        Casual_Leaves__c customCasualLeaves = [SELECT Total_Casual_Leave__c FROM Casual_Leaves__c WHERE Name = 'Casual Leave Value' LIMIT 1];
        Sick_Leave__c customSickLeaves = [SELECT Total_Sick_Leave__c FROM Sick_Leave__c WHERE Name = 'Sick Leave Value' LIMIT 1];
        Maternity_Leave__c customMaternityLeaves = [SELECT Total_Maternity_Leave__c FROM Maternity_Leave__c WHERE Name = 'Maternity Leave Value' LIMIT 1];

        List<Employee_Leave_Allowance__c> newLeaveAllowanceList = new List<Employee_Leave_Allowance__c>();

        for (Employee_Leave_Allowance__c allowance : leaveAllowanceList) {
            // Create a new Employee Leave Allowance record with the updated values
            Employee_Leave_Allowance__c newAllowance = new Employee_Leave_Allowance__c();
            newAllowance.User__c = allowance.User__c; // Maintain the same User
			newAllowance.OwnerId = allowance.User__c; // Maintain the same User
            newAllowance.Total_Casual_Leave__c = customCasualLeaves.Total_Casual_Leave__c;
            newAllowance.Total_Sick_Leave__c = customSickLeaves.Total_Sick_Leave__c;
            newAllowance.Total_Maternity_Leave__c = customMaternityLeaves.Total_Maternity_Leave__c;
            newAllowance.Used_Casual_Leave__c = 0;
            newAllowance.Used_Sick_Leave__c = 0;
            newAllowance.Used_Earned_Leave__c = 0;

            // Set the Name field for the new record
            if (allowance.User__c != null) {
                newAllowance.Name = String.valueOf(Date.today().year()) + ' ' + allowance.User__r.FirstName + ' ' + allowance.User__r.LastName + ' - Leave Allowance';
            }

            // Add to the list of new records
            newLeaveAllowanceList.add(newAllowance);
        }

        // Insert new leave allowance records
        if (!newLeaveAllowanceList.isEmpty()) {
            insert newLeaveAllowanceList;
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('Batch finished at ' + System.now());
    }
}