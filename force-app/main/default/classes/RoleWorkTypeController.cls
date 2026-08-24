public with sharing class RoleWorkTypeController {

    @AuraEnabled(cacheable=true)
    public static List<String> getAllowedWorkTypesForCurrentUser() {
        try {
            // Step 1: Get current user's Employee Role field
            User currentUser = [
                SELECT Id, Employee_Role__c 
                FROM User 
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];

            String employeeRole = currentUser.Employee_Role__c;

            if (String.isBlank(employeeRole)) {
                return new List<String>(); // No role assigned
            }

            // Step 2: Fetch matching Custom Setting record by role name
            Role_Work_Type_Mapping__c roleMapping = Role_Work_Type_Mapping__c.getInstance(employeeRole);

            if (roleMapping == null || String.isBlank(roleMapping.Allowed_Work_Types__c)) {
                return new List<String>(); // No mapping found
            }

            // Step 3: Split and return allowed work types
            List<String> allowedTypes = new List<String>();
            for (String val : roleMapping.Allowed_Work_Types__c.split(',')) {
                allowedTypes.add(val.trim());
            }

            return allowedTypes;

        } catch (Exception e) {
            throw new AuraHandledException('Error fetching work types: ' + e.getMessage());
        }
    }
}