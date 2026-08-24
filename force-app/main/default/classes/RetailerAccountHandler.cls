public without sharing class RetailerAccountHandler {
    
    public static String accountFields  =   'Id, Name, Primary_Address_1__c,Distributor_Type__c, Primary_City__c, Primary_State__c, Primary_PINCode__c,BillingStreet,BillingCity,BillingState,BillingPostalCode,BillingCountry,ShippingStreet,ShippingCity,ShippingState,ShippingPostalCode,ShippingCountry,ShippingAddress,' + 
                                            'Ship_To_Address_1__c, Ship_to_District__c, ' +
                                            'GSTIN__c, PAN_Number__c, FSSAI__c, Phone, Phone_1__c, Phone_2__c,Owners_Number__c'; 

    public static Account getRetailerAccount(Id accountId) {
        Id recordTypeId                 =   Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Retailer').getRecordTypeId();
        String queryStr                 =   'SELECT ' + accountFields + ' FROM Account WHERE Id=:accountId AND RecordTypeId=:recordTypeId LIMIT 1';
        /*Map<String, Object> bindVarMap  =   new Map<String, Object> {'accountId' => accountId, 'recordTypeId' => recordTypeId};
        System.debug('getRetailerAccount queryStr*** ' + queryStr);
        List<Account> accountList       =   Utility.soqlQuery(queryStr,bindVarMap,AccessLevel.USER_MODE);
        System.debug('getRetailerAccount Account List*** ' + accountList.size() + ' ' + accountList);     
        return accountList.size() == 1 ? accountList[0] : null;*/
        List<Account> acc = [SELECT Id, Name, Primary_Address_1__c,Distributor_Type__c, Primary_City__c, Primary_State__c, 
                             Primary_PINCode__c,BillingStreet,BillingCity,BillingState,BillingPostalCode,BillingCountry,
                             ShippingStreet,ShippingCity,ShippingState,ShippingPostalCode,ShippingCountry,ShippingAddress, 
                             Ship_To_Address_1__c, Ship_to_District__c,GSTIN__c, PAN_Number__c, FSSAI__c, Phone, 
                             Phone_1__c, Phone_2__c,Owners_Number__c FROM Account WHERE Id=:accountId AND RecordTypeId=:recordTypeId LIMIT 1];
        return acc.size() == 1 ? acc[0] : null;
    }   //End of getRetailerAccount()
    
    
    public static Account getUnderSSAccount(Id accountId) {
        Id recordTypeId                 =   Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Distributor').getRecordTypeId();
        String queryStr                 =   'SELECT ' + accountFields + ' FROM Account WHERE Id=:accountId AND RecordTypeId=:recordTypeId LIMIT 1';
        //Map<String, Object> bindVarMap  =   new Map<String, Object> {'accountId' => accountId, 'recordTypeId' => recordTypeId};
        //System.debug('getUnderSSAccount queryStr*** ' + queryStr + 'AccessLevel.USER_MODE'+AccessLevel.USER_MODE);
        //List<Account> accountList       =   Utility.soqlQuery(queryStr,bindVarMap,AccessLevel.USER_MODE);
        List<Account> acc = [Select Id,Name, Primary_Address_1__c, Primary_City__c, Primary_State__c, Primary_PINCode__c,
                             BillingStreet,BillingCity,BillingState,BillingPostalCode,BillingCountry,
                             Ship_To_Address_1__c, Ship_to_District__c,
                             GSTIN__c, PAN_Number__c, FSSAI__c, Phone, Phone_1__c, Phone_2__c,Owners_Number__c,Distributor_Type__c
                             from Account where Id =: accountId AND RecordTypeId=:recordTypeId LIMIT 1];
        //System.debug('getUnderSSAccount Account List*** ' + accountList.size() + ' ' + accountList);     
        //return accountList.size() == 1 ? accountList[0] : null;
        return acc.size() == 1 ? acc[0] : null;
    }   //End of getRetailerAccount()
}