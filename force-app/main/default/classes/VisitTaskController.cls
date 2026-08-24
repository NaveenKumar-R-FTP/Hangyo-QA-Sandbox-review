/**
* Class Name  : VisitTaskController
* Test Class  : VisitTaskControllerTest
* author      : Shyam
* CreatedDate : 05-12-24
* Description : This is controller for My Visit Page, where I am getting the selected days Visit Tasks.
*                User can create a Visit & its task from this class.
* */

public with sharing class VisitTaskController {   
    
    @AuraEnabled(cacheable=true)
    public static List<Visit_Task__c> getVisitRecordsByDate(String selectedDate, Map<String, String> filters, List<String> checkboxfilter) {
        system.debug('getVisitRecordsByDate**');
        Id userId = UserInfo.getUserId();
        Date visitDate;
        
        if (String.isNotBlank(selectedDate)) {
            visitDate = Date.valueOf(selectedDate);
        }
        
        // Extract account filter from filters map
        String accountFilter = (filters != null && filters.containsKey('account')) ? filters.get('account') : null;
        String likeFilter = String.isNotBlank(accountFilter) ? '%' + accountFilter + '%' : null;
        
        // Build the base query dynamically using bind variables
        // added by fuzail - Include both Account__c and Distributor__c fields to support both Retailer and Distributor visit tasks
        String baseQuery = 'SELECT Id, Account__c, Distributor__c, Status__c, Visit_Type__c, Task_Planned_Date__c, ' +
            'Account__r.Name, Account__r.Phone, Account__r.Outlet_photo__c , Retailers_Address__c, Account__r.Last_order_date__c, Account__r.Last_Ordered_Date__c,Account__r.Last_Confirmed_Invoice_Date__c,Account__r.Invoice_Amount__c, ' +
            'Account__r.Average_Order_Value__c, Account__r.Average_order_value_6_months__c, Account__r.Order_Frequency__c, Account__r.Total_Order_Value__c,' +
            'Account__r.Retailer_classification__c, ' +
            'Distributor__r.Name, Distributor__r.Phone, Distributor__r.Outlet_photo__c, Distributor__r.Last_order_date__c, Distributor__r.Last_Ordered_Date__c, Distributor__r.Last_Confirmed_Invoice_Date__c, Distributor__r.Invoice_Amount__c, ' +
            'Distributor__r.Average_Order_Value__c, Distributor__r.Average_order_value_6_months__c, Distributor__r.Order_Frequency__c, Distributor__r.Total_Order_Value__c, ' +
            'Distributor__r.Retailer_classification__c, Beat_Name_Text__c ' +
            'FROM Visit_Task__c ' +
            'WHERE (Account__c != null OR Distributor__c != null) AND Visitor_Name__c = :userId AND Task_Planned_Date__c = :visitDate';
        
        // Add dynamic filters using bind variables
        // added by fuzail - SeaClass.CreateNewVisitTaskContollerTest.testCreateVisitAndTasksWithMixedAccounts: line 373, column 1rch in both Account__r.Name and Distributor__r.Name
        if (String.isNotBlank(accountFilter)) {
            baseQuery += ' AND (Account__r.Name LIKE :likeFilter OR Distributor__r.Name LIKE :likeFilter OR ' +
                'Status__c LIKE :likeFilter OR ' +
                'Beat_Name_Text__c LIKE :likeFilter)';
        }
        
        if (checkboxfilter != null && !checkboxfilter.isEmpty()) {
            baseQuery += ' AND Status__c IN :checkboxfilter';
        }
        
        // added by fuzail - Order by CreatedDate DESC so recently created visit tasks appear first
        baseQuery += ' ORDER BY CreatedDate DESC';
        
        // Use Database.query() with bind variables
        List<Visit_Task__c> allVisits = Database.query(baseQuery);
        
        // Filter by selected date
        List<Visit_Task__c> filteredVisits = new List<Visit_Task__c>();
        for (Visit_Task__c visit : allVisits) {
            if (visit.Task_Planned_Date__c != null && visit.Task_Planned_Date__c == visitDate) {
                filteredVisits.add(visit);
            }
        }
        system.debug('filteredVisits**'+filteredVisits);
        return filteredVisits;
    }
    
    @AuraEnabled
    public static List<Visit_Task__c> getVisitRecordsByDateTest(String selectedDate) {
        Id userId = UserInfo.getUserId();
        Date visitDate;
        
        if (String.isNotBlank(selectedDate)) {
            visitDate = Date.valueOf(selectedDate);
        }
        
        
        // Build the base query dynamically using bind variables
        // added by fuzail - Include both Account__c and Distributor__c fields to support both Retailer and Distributor visit tasks
        String baseQuery = 'SELECT Id, Account__c, Distributor__c, Status__c, Visit_Type__c, Task_Planned_Date__c, ' +
            'Account__r.Name, Account__r.Phone, Account__r.Outlet_photo__c , Retailers_Address__c, Account__r.Last_order_date__c, Account__r.Last_Ordered_Date__c,Account__r.Last_Confirmed_Invoice_Date__c,Account__r.Invoice_Amount__c, ' +
            'Account__r.Average_Order_Value__c, Account__r.Average_order_value_6_months__c, Account__r.Order_Frequency__c, Account__r.Total_Order_Value__c,' +
            'Account__r.Retailer_classification__c, ' +
            'Distributor__r.Name, Distributor__r.Phone, Distributor__r.Outlet_photo__c, Distributor__r.Last_order_date__c, Distributor__r.Last_Ordered_Date__c, Distributor__r.Last_Confirmed_Invoice_Date__c, Distributor__r.Invoice_Amount__c, ' +
            'Distributor__r.Average_Order_Value__c, Distributor__r.Average_order_value_6_months__c, Distributor__r.Order_Frequency__c, Distributor__r.Total_Order_Value__c, ' +
            'Distributor__r.Retailer_classification__c, Beat_Name_Text__c ' +
            'FROM Visit_Task__c ' +
            'WHERE (Account__c != null OR Distributor__c != null) AND Visitor_Name__c = :userId AND Task_Planned_Date__c = :visitDate';
        
        // added by fuzail - Order by CreatedDate DESC so recently created visit tasks appear first
        baseQuery += ' ORDER BY CreatedDate DESC';
        
        // Use Database.query() with bind variables
        List<Visit_Task__c> allVisits = Database.query(baseQuery);
        
        // Filter by selected date
        List<Visit_Task__c> filteredVisits = new List<Visit_Task__c>();
        for (Visit_Task__c visit : allVisits) {
            if (visit.Task_Planned_Date__c != null && visit.Task_Planned_Date__c == visitDate) {
                filteredVisits.add(visit);
            }
        }
        return filteredVisits;
    }
    
    
    @AuraEnabled(cacheable=true)
    public static List<Account> searchAccounts(String searchKey) {
        // Ensure the search key is not null or empty
        if (String.isBlank(searchKey)) {
            return new List<Account>();
        }
        
        // Use a SOQL query to search for accounts with a safe bind variable
        List<Account> accounts = [
            SELECT Id, Name 
            FROM Account 
            WHERE Name LIKE :('%' + searchKey + '%') 
            AND RecordType.Name != 'Customer'
            LIMIT 10
        ];
        
        return accounts;
    }
    
    
    @AuraEnabled(cacheable=true)
    public static boolean checkAnyVisitTaskInprogress(){
        
        List<Visit_Task__c> visitTasks = new List<Visit_Task__c>();
        Date todayDate = Date.TODAY();
        visitTasks=  [SELECT Id,Visitor_Name__c,Status__c , Task_Planned_Date__c FROM Visit_Task__c WHERE Visitor_Name__c = :UserInfo.getUserId() AND Task_Planned_Date__c =: todayDate];
        
        for (Visit_Task__c task : visitTasks) {
            if (task.Status__c == 'In-Progress') {
                return true;
            }
        }
        
        return false;
    }
    
    
    @AuraEnabled(cacheable=true)
    public static Boolean checkAnyVisitTaskStatus(Id currentVisitTaskId) {
        Visit_Task__c currentTask = [
            SELECT Id, Status__c
            FROM Visit_Task__c
            WHERE Id = :currentVisitTaskId
            LIMIT 1
        ];
        
        // Block if status is "Not Started" or "Cancelled"
        return (currentTask.Status__c == 'Not Started' || currentTask.Status__c == 'Cancelled');
    }
    
    @AuraEnabled
    public static DFCheckResponse checkUserChecking(Id currentVisitTaskId, String actionType) {
        DFCheckResponse response = new DFCheckResponse();
   
        List<Visit_Task__c> tasks = [
            SELECT Id, Status__c, Checked_In_Time__c, Checked_Out_Time__c, Unproductive_Reasons__c // added by Fuzail - Added Checked_Out_Time__c
            FROM Visit_Task__c
            WHERE Id = :currentVisitTaskId
            LIMIT 1
        ];
   
        if (tasks.isEmpty()) {
            response.isAllowed = false;
            response.errorMessage = 'Task not found.';
            return response;
        }
   
        Visit_Task__c task = tasks[0];
   
        if (task.Unproductive_Reasons__c == 'Shop closed') {
            response.isAllowed = false;
            response.errorMessage = actionType == 'NoOrder'
                ? 'No Order cannot be performed as shop is closed.'
                : 'DF actions cannot be performed as shop is closed.';
        } else if (actionType == 'DFAction') {
            // added by Fuzail - DF buttons should be blocked before check-in and after check-out
            if (task.Checked_In_Time__c == null) {
                response.isAllowed = false;
                response.errorMessage = 'Please Check-In to perform DF actions.';
            } else if (task.Checked_Out_Time__c != null) {
                response.isAllowed = false;
                response.errorMessage = 'DF actions cannot be performed after Check-Out.';
            } else {
                response.isAllowed = true;
                response.errorMessage = null;
            }
        } else if (task.Checked_In_Time__c == null) {
            // added by Fuzail - NoOrder only requires check-in (no check-out restriction)
            response.isAllowed = false;
            response.errorMessage = 'Please Check-In to perform No Order.';
        } else {
            response.isAllowed = true;
            response.errorMessage = null;
        }
        return response;
    }
    
    public class DFCheckResponse {
        @AuraEnabled public Boolean isAllowed;
        @AuraEnabled public String errorMessage;
    }
}