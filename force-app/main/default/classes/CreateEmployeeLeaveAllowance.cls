/**
* Class Name  : CreateEmployeeLeaveAllowance
* Test Class  : TestCreateEmployeeLeaveAllowance
* author      : Mirza
* CreatedDate : 23-01-25
* Description : This is to create all "Employee Leave Allowance" record on yearly basis (first of Jan for every Year).
* */
public class CreateEmployeeLeaveAllowance {
    
    public static void employeeLeaveAllowanceMethod() {
        // Retrieve Custom Settings values
        List<User> userList = [SELECT Name, Id,Employee_Role__c FROM User WHERE IsActive = true AND (Employee_Role__c IN ('SO', 'SSO', 'ASM' , 'RSM' , 'ZSM' , 'PSR'))];
        
        Casual_Leaves__c customCasualLeaves = [SELECT Total_Casual_Leave__c FROM Casual_Leaves__c WHERE Name = 'Casual Leave Value' LIMIT 1];
        Sick_Leave__c customSickLeaves = [SELECT Total_Sick_Leave__c FROM Sick_Leave__c WHERE Name = 'Sick Leave Value' LIMIT 1];
        Maternity_Leave__c customMaternityLeaves = [SELECT Total_Maternity_Leave__c FROM Maternity_Leave__c WHERE Name = 'Maternity Leave Value' LIMIT 1];
        Map <Id,User> userMap = new Map <Id, User>([SELECT Name, Email FROM User]);
        Set<Id> userIds = new Set<Id>();
        if(userList.size()>0){
            for (User userId : userList) {
                userIds.add(userId.Id);
            }
        }
        System.debug('Set of user Id: '+ userIds);
        
        String currentYear = String.ValueOf(System.today().year());
        Map<Id, Employee_Leave_Allowance__c> existingAllowances = new Map<Id, Employee_Leave_Allowance__c>();
        for (Employee_Leave_Allowance__c allowance : 
             [SELECT Id, User__c FROM Employee_Leave_Allowance__c WHERE User__c IN :userIds AND Year__c = :currentYear]) {
             existingAllowances.put(allowance.User__c, allowance);
        }
        System.debug('Employee leave allowance which already exists: '+ existingAllowances);
        
        List<Employee_Leave_Allowance__c> newLeaveRecords = new List<Employee_Leave_Allowance__c>();
        Employee_Leave_Allowance__c newAllowance;
        for (Id userRecord : userIds) {
            if (existingAllowances.containsKey(userRecord)) { 
                continue;
            }
            newAllowance = new Employee_Leave_Allowance__c();
            newAllowance.User__c = userRecord; // Maintain the same User
            newAllowance.OwnerId = userRecord; // Maintain the same User
            newAllowance.Total_Casual_Leave__c = customCasualLeaves.Total_Casual_Leave__c;
            newAllowance.Total_Sick_Leave__c = customSickLeaves.Total_Sick_Leave__c;
            newAllowance.Total_Maternity_Leave__c = customMaternityLeaves.Total_Maternity_Leave__c;
            newAllowance.Used_Casual_Leave__c = 0;
            newAllowance.Used_Sick_Leave__c = 0;
            newAllowance.Used_Earned_Leave__c = 0;
            newAllowance.Name = String.valueOf(Date.today().year()) + ' ' + userMap.get(userRecord).Name + ' - Leave Allowance';
            
            newLeaveRecords.add(newAllowance);
        }
        
        System.debug('newLeaveRecords: '+ newLeaveRecords);
        if (!newLeaveRecords.isEmpty()) {
            insert newLeaveRecords;
        }
    }
}