/**
* Class Name  : UpdateRetailerBeatController
* Test Class  : UpdateRetailerBeatControllerTest
* author      : Mirza
* CreatedDate : 19-2-25
* Description : This is used to update the beat in retailer record
* */
public with sharing class UpdateRetailerBeatController {
    
    @AuraEnabled
    public static List<Beat__c> getAllBeats(String searchValue) {
        String userId = UserInfo.getUserId();
        User currentUser = [
            SELECT Id, UserRoleId 
            FROM User 
            WHERE Id = :userId
            LIMIT 1
        ];
        // Get all subordinate user Ids
        Set<Id> userIds = new Set<Id>{userId}; // Include the logged-in user
        // Fetch subordinate roles and their users
        List<UserRole> subRoles = [
            SELECT Id 
            FROM UserRole 
            WHERE ParentRoleId = :currentUser.UserRoleId
        ];
        if (!subRoles.isEmpty()) {
            List<User> subUsers = [
                SELECT Id 
                FROM User 
                WHERE UserRoleId IN :subRoles
            ];
            for (User u : subUsers) {
                userIds.add(u.Id);
            }
        }
        
        String query = 'SELECT Id, Name,Territory__c , Distributor_Name__r.Name FROM Beat__c WHERE Employee_Name__c IN :userIds';      
        if (!String.isEmpty(searchValue)) {
            searchValue = '%' + searchValue + '%';
            query += ' AND Name LIKE :searchValue';
        }
        List<Beat__c> beats = Database.query(query);
        
        return beats;
    }
    
    @AuraEnabled
    public static List<Account> getAllRetailer(String searchValue) {
        String userId = UserInfo.getUserId();
        // Fetch the logged-in user's role
        User currentUser = [
            SELECT Id, UserRoleId 
            FROM User 
            WHERE Id = :userId
            LIMIT 1
        ];
        // Get all subordinate user Ids
        Set<Id> userIds = new Set<Id>{userId}; // Include the logged-in user
        // Fetch subordinate roles and their users
        List<UserRole> subRoles = [
            SELECT Id 
            FROM UserRole 
            WHERE ParentRoleId = :currentUser.UserRoleId
        ];
        if (!subRoles.isEmpty()) {
            List<User> subUsers = [
                SELECT Id 
                FROM User 
                WHERE UserRoleId IN :subRoles
            ];
            for (User u : subUsers) {
                userIds.add(u.Id);
            }
        }
        
        Id accountRecordTypeId = [
            SELECT Id FROM RecordType 
            WHERE Name = 'Retailer' AND SObjectType = 'Account' 
            LIMIT 1
        ].Id;
        String query = 'SELECT Id, Name,Owners_Number__c , Distributor__r.Name FROM Account WHERE OwnerId IN :userIds AND RecordTypeId = :accountRecordTypeId';      
        if (!String.isEmpty(searchValue)) {
            searchValue = '%' + searchValue + '%';
            query += ' AND Name LIKE :searchValue';
        }
        List<Account> getRetailer = Database.query(query);
        
        return getRetailer;
    }
    
    @AuraEnabled
    public static String updateRetailerRecord(List<Id> beatId , List<Id> retailerId) {
        System.debug('beatId: '+beatId);
        System.debug('retailerId: '+retailerId);
        List<Account> updateAAccountList = new List<Account>();
        if (!String.isEmpty(beatId[0]) && retailerId.size()>0){
            Account acc;
            for(Account accRecord : [SELECT Id, Name,Beats_Name__c FROM Account WHERE Id IN: retailerId]){
                acc = new Account();
                acc.Id = accRecord.Id;
                acc.Beats_Name__c = beatId[0];
                updateAAccountList.add(acc);
            }
        }
        try {
            update updateAAccountList;
            return 'Success';
        } catch (DmlException e) {
            throw new AuraHandledException('Error creating Visit Tasks: ' + e.getMessage());
        }
    }
}