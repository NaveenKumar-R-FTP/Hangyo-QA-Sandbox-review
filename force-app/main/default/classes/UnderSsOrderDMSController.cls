public without sharing class UnderSsOrderDMSController {

    @AuraEnabled(cacheable=false)
    public static List<Account> getAllUnderSs(String searchValue) {
        System.debug('searchValue ' + searchValue);

        String userId = UserInfo.getUserId();
        Id distributorAccId;

        // FIX: Wrap in try-catch to avoid hard failures if user has no contact
        try {
            Id conId = [SELECT ContactId FROM User WHERE Id = :userId LIMIT 1].ContactId;
            if (conId != null) {
                List<Contact> contacts = [
                    SELECT AccountId FROM Contact WHERE Id = :conId LIMIT 1
                ];
                if (!contacts.isEmpty() && contacts[0].AccountId != null) {
                    distributorAccId = contacts[0].AccountId;
                }
            }
        } catch (Exception e) {
            System.debug('Error fetching contact/account: ' + e.getMessage());
        }

        System.debug('distributorAccId=> ' + distributorAccId);

        // FIX: Guard — if no distributor found, return empty list instead of crashing
        if (distributorAccId == null) {
            return new List<Account>();
        }

        List<RecordType> rtList = [
            SELECT Id FROM RecordType
            WHERE Name = 'Distributor' AND SObjectType = 'Account'
            LIMIT 1
        ];

        if (rtList.isEmpty()) {
            return new List<Account>();
        }

        Id accountRecordTypeId = rtList[0].Id;
        System.debug('accountRecordTypeId=> ' + accountRecordTypeId);

        // FIX: Added Super_Stockist_Name__c != null as an explicit filter per requirement
        String query = 'SELECT Id, Name, Phone, Super_Stockist_Name__c, Primary_State__c, Owners_Number__c ' +
                       'FROM Account ' +
                       'WHERE RecordTypeId = :accountRecordTypeId ' +
                       'AND Super_Stockist_Name__c = :distributorAccId ' +
                       'AND Super_Stockist_Name__c != null ' +
                       'AND Distributor_Type__c = \'Under Super Stockist\' ' +
                       'AND Is_Active__c = true';

        if (!String.isEmpty(searchValue)) {
            searchValue = '%' + searchValue + '%';
            query += ' AND Name LIKE :searchValue';
        }

        query += ' ORDER BY Name ASC';

        System.debug('query ' + query);
        List<Account> getUnderSs = Database.query(query);
        System.debug('getUnderSs==> ' + getUnderSs);
        return getUnderSs;
    }
}