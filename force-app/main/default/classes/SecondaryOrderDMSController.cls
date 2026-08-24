/**
* Class Name  : SecondaryOrderDMSController
* Test Class  : SecondaryOrderDMSControllerTest
* author      : Mirza
* CreatedDate : 04-03-25
* Description : Created for to fetching retailer for the dms user'
* */
public without sharing class SecondaryOrderDMSController {
    @AuraEnabled
    public static List<Account> getAllRetailer(String searchValue) {
        System.debug('searchValue ' + searchValue);
        String userId = UserInfo.getUserId();
        //Fetch the distributor for the current user
        Id distributorAccId;
        Id conId = [SELECT ContactId FROM User WHERE Id = :userId].ContactId;
        // Query the account via the contact associated with the user
        if (conId !=null){
            Contact contact = [
                SELECT AccountId 
                FROM Contact 
                WHERE Id = :conId
                LIMIT 1
            ];
            
            // Retrieve the account if the contact has one
            if (contact.AccountId != null) {
                distributorAccId=contact.AccountId;
            }
        }
        
        Id accountRecordTypeId = [
            SELECT Id FROM RecordType 
            WHERE Name = 'Retailer' AND SObjectType = 'Account' 
            LIMIT 1
        ].Id;
        String query = 'SELECT Id, Name,Phone , Distributor__r.Name , Beats_Name__r.Name , Primary_State__c , Owners_Number__c FROM Account WHERE RecordTypeId = :accountRecordTypeId AND Distributor__c =: distributorAccId AND Is_Active__c = true';      
        if (!String.isEmpty(searchValue)) {
            searchValue = '%' + searchValue + '%';
            query += ' AND Name LIKE :searchValue';
        }
        
        query += ' ORDER BY Name ASC';
        System.debug('query ' + query);
        List<Account> getRetailer = Database.query(query);
        
        return getRetailer;
    }
}