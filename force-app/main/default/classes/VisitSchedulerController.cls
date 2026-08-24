/**
* Class Name  : VisitSchedulerController
* Test Class  : VisitSchedulerControllerTest
* author      : Shyam
* CreatedDate : 15-01-25	
* Description : This is controller for creating Visit & Visit Task on future (Selected Date).
                
* */
public with sharing class VisitSchedulerController {
    
    @AuraEnabled(cacheable=true)
    public static List<Beat__c> getAllBeats(Map<String, String> filterParams) {
        Set<Id> userIds = GetSubOrinates.getSubOrinatesUserIds();
        String query = 'SELECT Id, Name,Territory__c, Employee_Name__c FROM Beat__c WHERE OwnerId In :userIds';
        /*String userId = UserInfo.getUserId();
        String query = 'SELECT Id, Name,Territory__c, Employee_Name__c FROM Beat__c WHERE Employee_Name__c = :userId';*/     
        
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
            SELECT Id, Name, Beats_Name__c, Phone, Owners_Number__c
            FROM Account
            WHERE RecordTypeId = :retailerRecordTypeId
            AND Beats_Name__c = :beatId
            AND OwnerId IN :userIds AND Is_Active__c = true
        ];

        return retailerAccounts;
    }
    
    @AuraEnabled
    public static void createVisits(List<Id> retailerIds, Date visitDate, Id beatId) {
        /*if (retailerIds == null || retailerIds.isEmpty()) {
            throw new AuraHandledException('No retailers selected.');
        }
        if (visitDate == null) {
            throw new AuraHandledException('Visit date is not provided.');
        }
        if (beatId == null) {
            throw new AuraHandledException('No Beat selected.');
        }*/
        
         // Check if a visit already exists for the selected date and beat for the logged-in user
    List<Visit__c> existingVisits = [
        SELECT Id
        FROM Visit__c
        WHERE Visit_planned_date__c = :visitDate
        AND Visitor_Name__c = :UserInfo.getUserId()
        //AND Beat__c = :beatId
    ];
    
    if (!existingVisits.isEmpty()) {
        throw new AuraHandledException('A visit already exists for the selected date and beat.');
    }
       
            Visit__c visit = new Visit__c(
                Visit_planned_date__c = visitDate,
                Visitor_Name__c = UserInfo.getUserId(),
                Beat__c = beatId,
                Status__c = 'Not Started',
                Visit_Type__c = 'Planned'

            );
            try {
                insert visit;
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
                Visit_Type__c = 'Planned',
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