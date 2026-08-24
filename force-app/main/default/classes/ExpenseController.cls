/**
* Class Name  : ExpenseController
* Test Class  : ExpenseControllerTest
* author      : Pradvith
* CreatedDate : 15-12-24
* Description : This is controller to create the expense records
* */
public with sharing class ExpenseController {
    public class ExpenseResponse {
        @AuraEnabled public Id expenseId;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Boolean blockSave; // true if saving must be blocked
    }
    
    public class UserEntitlementWrapper {
        @AuraEnabled public String userRole;
        @AuraEnabled public String userManager;
        @AuraEnabled public Boolean flightAllowance;
        @AuraEnabled public Decimal bikeAllowanceAmount;
        @AuraEnabled public Decimal carAllowanceAmount;
        @AuraEnabled public Decimal trainAllowanceAmount;
        @AuraEnabled public Decimal busAllowanceAmount;
        @AuraEnabled public Decimal classACitiesAmount;
        @AuraEnabled public Decimal otherCitiesAmount;
    }
    
    
    /* @AuraEnabled(cacheable=true)
public static String getUserRole() {
User currentUser = [SELECT Employee_Role__c,UserRole.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
return currentUser.Employee_Role__c != null ? currentUser.Employee_Role__c : 'No Role Assigned';
}*/
    
    @AuraEnabled(cacheable=true)
    public static UserEntitlementWrapper getUserRoleAndEntitlements() {
        User currentUser = [
            SELECT Employee_Role__c,L1_Approver__c 
            FROM User 
            WHERE Id = :UserInfo.getUserId() 
            LIMIT 1
        ];
        
        String role = currentUser.Employee_Role__c;
        String manager = currentUser.L1_Approver__c;
        
        // Query the entitlement
        List<Expense_Entitlement__c> entitlements = [
            SELECT Flight_Allowance_Amount__c, Car_Allowance_Amount_per_km__c, Bike_Allowance_Amount_per_Km__c,
            Train_Allowance_Amount__c, Bus_Allowance_Amount__c,Class_A_Cities_Amount__c,Other_Cities_Amount__c,Flight_allowance__c
            FROM Expense_Entitlement__c 
            WHERE Role__c = :role AND Active__c = true
            LIMIT 1
        ];
        
        if (entitlements.isEmpty()) {
            // Throw a user-friendly error if no record found
            throw new AuraHandledException('No entitlement assigned for your role. Please contact the administrator.');
        }
         if (String.isBlank(manager)) {
            // Throw a user-friendly error if no record found
            throw new AuraHandledException('No approver assigned for your role. Please contact the administrator.');
        }
        
        Expense_Entitlement__c entitlement = entitlements[0];
        
        UserEntitlementWrapper wrapper = new UserEntitlementWrapper();
        wrapper.userRole = role;
        wrapper.userManager = manager;
        wrapper.flightAllowance = entitlement.Flight_allowance__c;
        wrapper.carAllowanceAmount = entitlement.Car_Allowance_Amount_per_km__c;
        wrapper.bikeAllowanceAmount = entitlement.Bike_Allowance_Amount_per_Km__c;
        wrapper.trainAllowanceAmount = entitlement.Train_Allowance_Amount__c;
        wrapper.busAllowanceAmount = entitlement.Bus_Allowance_Amount__c;
        wrapper.classACitiesAmount = entitlement.Class_A_Cities_Amount__c;
        wrapper.otherCitiesAmount = entitlement.Other_Cities_Amount__c;
        
        return wrapper;
    }
    
    
    
    
    
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getClassACities() {
        List<Map<String, String>> cityOptions = new List<Map<String, String>>();
        
        // Fetch picklist values for Class_A_Cities__c field on the Expense__c object
        Schema.DescribeFieldResult fieldResult = Expense__c.Class_A_Cities__c.getDescribe();
        List<Schema.PicklistEntry> picklistValues = fieldResult.getPicklistValues();
        
        for (Schema.PicklistEntry entry : picklistValues) {
            Map<String, String> option = new Map<String, String>();
            option.put('label', entry.getLabel());
            option.put('value', entry.getValue());
            cityOptions.add(option);
        }
        
        return cityOptions;
    }
    
    
    @AuraEnabled
    public static ExpenseResponse validateExpense(
        String userRole,
        String expenseType,
        String transportType,
        String accommodationType,
        Decimal amount,
        Decimal bikeRun
    ) {
        ExpenseResponse response = new ExpenseResponse();
        String currentUserRole;
        
        // Get current user’s role
        User currentUser = [SELECT Employee_Role__c, UserRole.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        currentUserRole = currentUser.Employee_Role__c;
        
        // Query entitlement safely
        List<Expense_Entitlement__c> entitlementList = [
            SELECT Role__c, Bus_Allowance_Amount__c, Train_Allowance_Amount__c, Flight_Allowance_Amount__c,
            Class_A_Cities_Amount__c, Other_Cities_Amount__c
            FROM Expense_Entitlement__c
            WHERE Role__c = :currentUserRole AND Active__c = true
            LIMIT 1
        ];
        
        // If no entitlement found, block save and return
        if (entitlementList.isEmpty()) {
            response.errorMessage = 'No entitlement configuration found for your role (' + currentUserRole + '). Please contact administrator.';
            response.blockSave = true;
            return response;
        }
        
        Expense_Entitlement__c entitlement = entitlementList[0];
        String errorMessage;
        
        // Handle travel expenses
        if (expenseType == 'Travel_Expense_Request') {
            if (transportType == 'Bus') {
                if (entitlement.Bus_Allowance_Amount__c == null || entitlement.Bus_Allowance_Amount__c == 0) {
                    errorMessage = 'There is no entitlement for Bus travel for you. Please contact administrator.';
                    response.blockSave = true;
                } else if (amount > entitlement.Bus_Allowance_Amount__c) {
                    errorMessage = 'Maximum ' + entitlement.Bus_Allowance_Amount__c +
                        ' rupees allowed for Bus travel. Do you still wish to proceed for approval?';
                }
            } else if (transportType == 'Train') {
                if (entitlement.Train_Allowance_Amount__c == null || entitlement.Train_Allowance_Amount__c == 0) {
                    errorMessage = 'There is no entitlement for Train travel for you. Please contact administrator.';
                    response.blockSave = true;
                } else if (amount > entitlement.Train_Allowance_Amount__c) {
                    errorMessage = 'Maximum ' + entitlement.Train_Allowance_Amount__c +
                        ' rupees allowed for Train travel. Do you still wish to proceed for approval?';
                }
            } /*else if (transportType == 'Flight') {
if (entitlement.Flight_Allowance_Amount__c == null || entitlement.Flight_Allowance_Amount__c == 0) {
errorMessage = 'There is no entitlement for Flight travel for you. Please contact administrator.';
response.blockSave = true;
} else if (amount > entitlement.Flight_Allowance_Amount__c) {
errorMessage = 'Maximum ' + entitlement.Flight_Allowance_Amount__c +
' rupees allowed for Flight travel. Do you still wish to proceed for approval?';
}
}*/
        }
        
        // Handle accommodation expenses
        if (expenseType == 'Accommodation Request') {
            if (accommodationType == 'Class A cities') {
                if (entitlement.Class_A_Cities_Amount__c == null || entitlement.Class_A_Cities_Amount__c == 0) {
                    errorMessage = 'There is no entitlement for ' + accommodationType + ' for you.';
                    response.blockSave = true;
                } else if (amount > entitlement.Class_A_Cities_Amount__c) {
                    errorMessage = 'Maximum ' + entitlement.Class_A_Cities_Amount__c +
                        ' rupees allowed for Accommodation in ' + accommodationType + '. Do you still wish to proceed for approval?';
                }
            } else if (accommodationType == 'Other Cities') {
                if (entitlement.Other_Cities_Amount__c == null || entitlement.Other_Cities_Amount__c == 0) {
                    errorMessage = 'There is no entitlement for ' + accommodationType + ' for you.';
                    response.blockSave = true;
                } else if (amount > entitlement.Other_Cities_Amount__c) {
                    errorMessage = 'Maximum ' + entitlement.Other_Cities_Amount__c +
                        ' rupees allowed for Accommodation in ' + accommodationType + '. Do you still wish to proceed for approval?';
                }
            }
        }
        
        response.errorMessage = errorMessage;
        return response;
    }
    
    @AuraEnabled
    public static ExpenseResponse saveExpense(
        String userRole,
        String expenseType,
        String transportType,
        String accommodationType,
        String classACity,
        String otherCity,
        Decimal amount,
        Decimal bikeRun,
        Date expenseDate,
        List<String> uploadedFileIds,
        Id recordId,
        string miscExpenseDetails
        
    ) {
        ExpenseResponse response = new ExpenseResponse();
        
        //Get logged in user's Role
        String currentUserRole;
        User currentUser = [SELECT Employee_Role__c,UserRole.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        currentUserRole = currentUser.Employee_Role__c;
        
        
        
        // Get the RecordTypeId the Expense__c object
        String miscellaneousRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Expense__c' AND Name = 'Manual Expense' LIMIT 1].Id;
        
        // Retrieve Custom Settings values
        /*Bike_Allowance__c bikeAllowance = [SELECT Cost_Km__c FROM Bike_Allowance__c WHERE Name = 'Bike Cost' LIMIT 1];
Car_Allowance__c carAllowance = [SELECT Cost_Km__c FROM Car_Allowance__c WHERE Name = 'Car Cost' LIMIT 1];*/
        
        // Query entitlement safely
        Expense_Entitlement__c ent = [
            SELECT Role__c, Bus_Allowance_Amount__c, Train_Allowance_Amount__c, Flight_Allowance_Amount__c,
            Class_A_Cities_Amount__c, Other_Cities_Amount__c, Car_Allowance_Amount_per_km__c, Bike_Allowance_Amount_per_Km__c
            FROM Expense_Entitlement__c 
            WHERE Role__c = :currentUserRole AND Active__c = true
            LIMIT 1
        ];
        
        // Query the Expense_Claim__c for the logged-in user, with start date in the current month
        /*      Date startOfMonth = Date.today().toStartOfMonth();  // First day of current month
Date lastDayOfMonth = startOfMonth.addMonths(1).addDays(-1);   // Last day of month
Expense_Claim__c userExpenseClaim = [
SELECT Id
FROM Expense_Claim__c
WHERE User__c = :UserInfo.getUserId()
AND Start_Date__c >= :startOfMonth
AND Start_Date__c <= :lastDayOfMonth
LIMIT 1
];*/
        // Query the Expense_Claim__c for the logged-in user, for the month of the submitted expense date
        Date startOfMonth = expenseDate.toStartOfMonth();
        Date lastDayOfMonth = startOfMonth.addMonths(1).addDays(-1);
        List<Expense_Claim__c> expenseClaims = [
            SELECT Id
            FROM Expense_Claim__c
            WHERE User__c = :UserInfo.getUserId()
            AND Start_Date__c >= :startOfMonth
            AND Start_Date__c <= :lastDayOfMonth
            LIMIT 1
        ];
        if (expenseClaims.isEmpty()) {
            
            DateTime dt = DateTime.newInstance(expenseDate, Time.newInstance(0, 0, 0, 0));
            String monthYear = dt.format('MMMM yyyy');
            throw new AuraHandledException('No Expense Claim exists for the month of ' +
                                           monthYear + '. Please contact your admin.');
        
        }
        Expense_Claim__c userExpenseClaim = expenseClaims[0];
        
        system.debug(userExpenseClaim);
        
        
        
        // Create the new Expense record
        Expense__c newExpense = new Expense__c();
        newExpense.User_Role__c = userRole;
        newExpense.Expense_Type__c = expenseType;
        newExpense.Transport_Type__c = transportType;
        newExpense.Accomodation_Type__c = accommodationType;
        newExpense.Class_A_Cities__c = classACity;
        newExpense.Other_City__c = otherCity;       
        newExpense.Expense_date__c = expenseDate;
        newExpense.RecordTypeId = miscellaneousRecordTypeId;
        newExpense.Misc_Expense_Details__c = miscExpenseDetails;  
        newExpense.Visitor_Name__c = UserInfo.getUserId(); 
        // newExpense.Expense_Claim__c = recordId;
        newExpense.Expense_Claim__c = userExpenseClaim.Id; // Set the Expense Claim lookup
        
        // Check Transport Type and calculate the Amount
        if (newExpense.Transport_Type__c == 'Car' && ent.Car_Allowance_Amount_per_km__c != null) {
            newExpense.Car_Run_Km__c = bikeRun; 
            newExpense.Amount__c = bikeRun * ent.Car_Allowance_Amount_per_km__c;  
            // newExpense.Amount__c = bikeRun * carAllowance.Cost_Km__c;  
        } else if (newExpense.Transport_Type__c == 'Bike' && ent.Bike_Allowance_Amount_per_Km__c != null) {
            newExpense.Bike_Run_Km__c = bikeRun; 
            newExpense.Amount__c = bikeRun * ent.Bike_Allowance_Amount_per_Km__c;
            //  newExpense.Amount__c = bikeRun * bikeAllowance.Cost_Km__c;  
        } else {
            newExpense.Amount__c = amount; 
        }
        // Query entitlement for the user's role
        Expense_Entitlement__c entitlement = [
            SELECT Role__c, Bus_Allowance_Amount__c, Train_Allowance_Amount__c, Flight_Allowance_Amount__c,Class_A_Cities_Amount__c,Other_Cities_Amount__c
            FROM Expense_Entitlement__c
            WHERE Role__c = :currentUserRole AND Active__c = true
            LIMIT 1
        ];
        
        String errorMessage;
        
        // Handle transport-based dynamic entitlement check
        if (expenseType == 'Travel_Expense_Request') {
            if (transportType == 'Bus') {
                if (entitlement.Bus_Allowance_Amount__c == null || entitlement.Bus_Allowance_Amount__c == 0) {
                    errorMessage = 'There is no entitlement for Bus travel for you.';
                } else if (amount > entitlement.Bus_Allowance_Amount__c) {
                    errorMessage = 'Maximum ' + entitlement.Bus_Allowance_Amount__c + ' rupees allowed for Bus travel.';
                }
            } else if (transportType == 'Train') {
                if (entitlement.Train_Allowance_Amount__c == null || entitlement.Train_Allowance_Amount__c == 0) {
                    errorMessage = 'There is no entitlement for Train travel for you.';
                } else if (amount > entitlement.Train_Allowance_Amount__c) {
                    errorMessage = 'Maximum ' + entitlement.Train_Allowance_Amount__c + ' rupees allowed for Train travel.';
                }
            } /*else if (transportType == 'Flight') {
if (entitlement.Flight_Allowance_Amount__c == null || entitlement.Flight_Allowance_Amount__c == 0) {
errorMessage = 'There is no entitlement for Flight travel for you.';
} else if (amount > entitlement.Flight_Allowance_Amount__c) {
errorMessage = 'Maximum ' + entitlement.Flight_Allowance_Amount__c + ' rupees allowed for Flight travel.';
}
}*/
        }
        
        // Dynamic accommodation amount checks based on entitlement
        if (expenseType == 'Accommodation Request') {
            if (accommodationType == 'Class A cities') {
                if (entitlement.Class_A_Cities_Amount__c == null || entitlement.Class_A_Cities_Amount__c == 0) {
                    errorMessage = 'There is no entitlement for ' + accommodationType + ' for you.';
                } else if (amount > entitlement.Class_A_Cities_Amount__c) {
                    errorMessage = 'Maximum ' + entitlement.Class_A_Cities_Amount__c +
                        ' rupees allowed for Accommodation in ' + accommodationType + '.';
                }
            } else if (accommodationType == 'Other Cities') {
                if (entitlement.Other_Cities_Amount__c == null || entitlement.Other_Cities_Amount__c == 0) {
                    errorMessage = 'There is no entitlement for ' + accommodationType + ' for you.';
                } else if (amount > entitlement.Other_Cities_Amount__c) {
                    errorMessage = 'Maximum ' + entitlement.Other_Cities_Amount__c +
                        ' rupees allowed for Accommodation in ' + accommodationType + '.';
                }
            }
        }
        if (errorMessage != null ||  newExpense.Expense_Type__c == 'Miscellaneous Request' || transportType == 'Flight') {
            newExpense.Status__c = 'Submitte_for_Approval';
            newExpense.Approval_Status__c = 'Submitted';
        } else {
            newExpense.Status__c = 'Approved';
            newExpense.Approval_Status__c = 'Approved';
        }
        
        try {
            insert newExpense;
            
            if (uploadedFileIds != null && !uploadedFileIds.isEmpty()) {
                List<ContentDocumentLink> documentLinks = new List<ContentDocumentLink>();
                for (String fileId : uploadedFileIds) {
                    documentLinks.add(new ContentDocumentLink(
                        ContentDocumentId = fileId,
                        LinkedEntityId = newExpense.Id,
                        ShareType = 'V'
                    ));
                }
                insert documentLinks;
            }
            
            response.expenseId = newExpense.Id;
            response.errorMessage = errorMessage; // may be null
            return response;
        } catch (DmlException e) {
            throw new AuraHandledException('Error saving expense: ' + e.getMessage());
        }
    }
}