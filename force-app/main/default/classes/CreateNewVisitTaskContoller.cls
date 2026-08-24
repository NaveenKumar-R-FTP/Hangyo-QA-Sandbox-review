/**
* Class Name  : CreateNewVisitTaskContoller
* Test Class  : CreateNewVisitTaskContollerTest
* author      : Shyam
* CreatedDate : 22-12-24
* Description : To create the Visit & Visit Task for my visit page as a Ad hoc visit type.
*                User can create a Visit & its task from this class.
* */
 
public with sharing class CreateNewVisitTaskContoller {

    @AuraEnabled(cacheable=true)
    // added by fuzail - Added recordTypeName parameter to support both Retailer and Distributor
    public static List<Account> getRetailers(String searchKey, String recordTypeName) {
        Set<Id> userIds = GetSubOrinates.getSubOrinatesUserIds();
        
        // added by fuzail - Fetch record type based on the parameter (Retailer or Distributor)
        String recordTypeToQuery = (recordTypeName == 'Distributor') ? 'Distributor' : 'Retailer';
        RecordType accountRecordType = [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = 'Account' 
            AND Name = :recordTypeToQuery 
            LIMIT 1
        ];
        
        List<String> retailerId = new List<String>();
        for(Visit_Task__c visitTask : [SELECT Id , Retailer__c FROM Visit_Task__c WHERE Status__c = 'In-Progress' AND Retailer__c != NULL AND Task_Planned_Date__c =: Date.TODAY() AND Visitor_Name__c =:userIds]){
            retailerId.add(visitTask.Retailer__c);
        }
        System.debug('retailerId:- '+retailerId);
        Id recordTypeId = accountRecordType.Id;
        
        // Construct query to fetch accounts owned by the logged-in user or their subordinates
        String query = 'SELECT Id,Is_Active__c, Name, Beats_Name__c, Beats_Name__r.Name, RecordType.Name FROM Account WHERE RecordTypeId = :recordTypeId AND OwnerId IN :userIds AND Id NOT IN :retailerId AND Is_Active__c = true';
        
        if (String.isNotEmpty(searchKey)) {
            String searchFilter = '%' + searchKey + '%';
            // added by fuzail - Different search logic for Distributor vs Retailer
            if (recordTypeName == 'Distributor') {
                // For Distributor, only search by Name (no Beat Name)
                query += ' AND Name LIKE :searchFilter';
            } else {
                // For Retailer, search by Name or Beat Name
                query += ' AND (Name LIKE :searchFilter OR Beats_Name__r.Name LIKE :searchFilter)';
            }
        }
        
        List<Account> accountList = Database.query(query);
        return accountList;
    }

    @AuraEnabled
    public static Visit__c getLatestVisit() {
        List<Visit__c> visits = [SELECT Id, Name, Account__r.Name, Beat__r.Name, Visit_planned_date__c, Visitor_Name__c
                                 FROM Visit__c
                                 WHERE Visit_planned_date__c = :Date.today()
                                 AND Visitor_Name__c = :UserInfo.getUserId()
                                 ORDER BY CreatedDate DESC
                                 LIMIT 1];
        return visits.isEmpty() ? null : visits[0];
    }
 
    @AuraEnabled
    public static void createVisit(Id beatId, List<Id> retailerIds) {
        Visit__c newVisit = new Visit__c(
            Beat__c = beatId,
            Visit_Planned_Date__c = Date.today(),
            Visitor_Name__c = UserInfo.getUserId(),
            Status__c = 'Not Started',
            Visit_Type__c = 'Ad-Hoc'
        );
        insert newVisit;
 
        // Prepare Visit_Task__c records for insertion
        List<Visit_Task__c> tasksToInsert = new List<Visit_Task__c>();
        for (Id retailerId : retailerIds) {
            Visit_Task__c newTask = new Visit_Task__c(
                Visit__c = newVisit.Id,
                Retailer__c = retailerId,
                Account__c = retailerId,
                Beat__c = beatId,
                Visitor_Name__c = UserInfo.getUserId(),
                Status__c = 'Not Started',
                Visit_Type__c = 'Ad-Hoc',
                Task_Planned_Date__c = Date.today()
                //Type__c = 'Retailer Type'
            );
            tasksToInsert.add(newTask);
        }
 
        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
    }
 
   
    @AuraEnabled
    public static void createVisitAndTasks(List<Id> retailerIds) {
        if (retailerIds == null || retailerIds.isEmpty()) {
            throw new AuraHandledException('No retailers selected.');
        }
 
        Visit__c visit;
        try {
            List<Visit__c> visitList = [SELECT Id, Beat__c, Visit_planned_date__c, Visitor_Name__c
                                        FROM Visit__c 
                                        WHERE Visit_planned_date__c = :Date.today() 
                                        AND Visitor_Name__c = :UserInfo.getUserId()
                                        ORDER BY CreatedDate DESC 
                                        LIMIT 1];
 
            if (!visitList.isEmpty()) {
                visit = visitList[0]; // Use the existing visit
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving existing visit: ' + e.getMessage());
        }
 
        if (visit == null) {
            visit = new Visit__c(
                Visit_Planned_Date__c = Date.today(),
                Visitor_Name__c = UserInfo.getUserId(),
                Status__c = 'Not Started',
                Visit_Type__c = 'Ad-Hoc'
            );
            insert visit;
        }
 
        // Query all necessary account data in bulk including RecordType
        // added by fuzail - Added RecordType.Name to query to identify Retailer vs Distributor
        Map<Id, Account> accountMap = new Map<Id, Account>([
            SELECT Id, Beats_Name__c, RecordType.Name
            FROM Account
            WHERE Id IN :retailerIds
        ]);

        List<Visit_Task__c> tasksToInsert = new List<Visit_Task__c>();
        for (Id accountId : retailerIds) {
            Account account = accountMap.get(accountId);
            if (account != null) {
                Visit_Task__c visitTask = new Visit_Task__c(
                    Visit__c = visit.Id,
                    Beat__c = account.Beats_Name__c,
                    Visitor_Name__c = visit.Visitor_Name__c,
                    Status__c = 'Not Started',
                    Visit_Type__c = 'Ad-Hoc',
                    Task_Planned_Date__c = visit.Visit_planned_date__c
                );
                
                // added by fuzail - Set Retailer__c for Retailers, Distributor__c for Distributors
                // Leave Retailer__c blank for Distributors to avoid lookup filter validation error
                if (account.RecordType.Name == 'Retailer') {
                    visitTask.Retailer__c = accountId;
                    visitTask.Account__c = accountId;
                    //visitTask.Type__c = 'Retailer Type';
                } else if (account.RecordType.Name == 'Distributor') {
                    visitTask.Distributor__c = accountId;
                   // visitTask.Type__c = 'Distributor Type';
                    // Retailer__c remains blank for Distributors
                }
                
                tasksToInsert.add(visitTask);
            }
        }
 
        if (!tasksToInsert.isEmpty()) {
            try {
                insert tasksToInsert;
            } catch (DmlException e) {
                throw new AuraHandledException('Error creating Visit Tasks: ' + e.getMessage());
            }
        }
    }
 
    public class VisitRecord {
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public Date plannedStartTime { get; set; }
        @AuraEnabled public String visitType { get; set; } // Retailer or Distributor
    }
}