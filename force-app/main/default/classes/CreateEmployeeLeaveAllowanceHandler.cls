/**
* Class Name  : CreateEmployeeLeaveAllowanceHandler
* Test Class  : CreateEmployeeLeaveAllowanceHandlerTest
* author      : Shyam
* CreatedDate : 21-01-25
* Description : This is to create "Employee Leave Allowance" record when user inserted future method is added to avoid mixed DML Error.
                
* */
public with sharing class CreateEmployeeLeaveAllowanceHandler {

    // Future method to create Employee Leave Allowance records
    @future
    public static void createEmployeeLeaveAllowancesAsync(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()){
            return;
        }

        List<Employee_Leave_Allowance__c> leaveAllowances = new List<Employee_Leave_Allowance__c>();
        if(userIds.size()>0){
            for (User u : [SELECT Id, Name, UserRoleId,Employee_Role__c, UserRole.Name FROM User WHERE Id IN :userIds]) {
                if (u.Employee_Role__c != Null) {
                    leaveAllowances.add(new Employee_Leave_Allowance__c(
                        Name = String.valueOf(Date.today().year()) + ' ' + u.Name + '-' + u.UserRole.Name,
                        User__c = u.Id,
                        OwnerId = u.Id,
                        Total_Casual_Leave__c = 12
                    ));
                }
            }
        }

        // Insert leave allowances
        if (!leaveAllowances.isEmpty()) {
            insert leaveAllowances;
        }
    }
}