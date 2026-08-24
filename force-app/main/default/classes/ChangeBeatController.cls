/**
* Class Name  : ChangeBeatController
* Test Class  : ChangeBeatControllerTest
* author      : Shyam
* CreatedDate : 20-12-24
* Description : This is used to create the Beat Change (deletion of existing Visit & Adding the New Beat).
*                User can create a Visit & its task from this class.
* */
public with sharing class ChangeBeatController {
    
    @AuraEnabled(cacheable=true)
    public static List<Beat__c> getAllBeats(Map<String, String> filterParams) {  
        // Get all subordinate user IDs for the logged-in user
        Set<Id> userIds = GetSubOrinates.getSubOrinatesUserIds();
        //String query = 'SELECT Id, Name,Territory__c FROM Beat__c WHERE OwnerId IN :userIds';
        // Get today's date in the user's timezone (optional: can use Date.today() directly)
        Date today = Date.today();
    
        // SOQL to exclude Beats with a Visit for today
        String query = 'SELECT Id, Name, Territory__c FROM Beat__c ' +
                   'WHERE Employee_Name__c IN :userIds ' +
                   'AND Id NOT IN (SELECT Beat__c FROM Visit__c WHERE Visit_planned_date__c = :today)';
        
        List<Beat__c> beats = Database.query(query);
        return beats;
    }
    
    @AuraEnabled
    public static List<Account> getRetailersByBeat(Id beatId) {
        Set<Id> userIds = GetSubOrinates.getSubOrinatesUserIds();
        if (beatId == null) {
            throw new IllegalArgumentException('Beat Id must not be null.');
        }
        Id retailerRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId();
        
        List<Account> retailerAccounts = [
            SELECT Id, Name, Beats_Name__c, Owners_Number__c
            FROM Account
            WHERE RecordTypeId = :retailerRecordTypeId
            AND Beats_Name__c = :beatId
            AND OwnerId IN :userIds
            AND Is_Active__c = true
        ];
        
        return retailerAccounts;
    }
    
    
    @AuraEnabled
    public static void createVisits(List<Id> retailerIds, Date visitDate, Id beatId) {
        // Create new Visit__c record for the selected Beat and Visit Date
        Visit__c visit = new Visit__c(
            Visit_planned_date__c = visitDate,
            Visitor_Name__c = UserInfo.getUserId(),
            Beat__c = beatId,
            Status__c = 'Not Started',
            Visit_Type__c = 'Ad-Hoc'          
        );
        
        try {
            insert visit;  // Insert the new Visit
        } catch (DmlException e) {
            throw new AuraHandledException('Error creating new Visit: ' + e.getMessage());
        }
        
        // Create Visit_Task__c records for each selected retailer
        List<Visit_Task__c> tasksToInsert = new List<Visit_Task__c>();
        for (Id retailerId : retailerIds) {
            Visit_Task__c visitTask = new Visit_Task__c(
                Visit__c = visit.Id,
                Retailer__c = retailerId,
                Account__c = retailerId,
                Beat__c = beatId,
                Task_Planned_Date__c = visit.Visit_planned_date__c,
                Status__c = 'Not Started',
                Visit_Type__c = 'Ad-Hoc',
                Visitor_Name__c = visit.Visitor_Name__c
            );
            tasksToInsert.add(visitTask);
        }
        
        // Insert Visit_Task__c records
        try {
            insert tasksToInsert;
        } catch (DmlException e) {
            throw new AuraHandledException('Error creating Visit Tasks: ' + e.getMessage());
        }
    }
    
    
    
}