/*******************************************************************************************************************************************************************
 * Class Name: DmsUserProfile 
 * Description: This apex class is used to retrieve,update DMS User Object record.
 * CHANGE LOG: 
 * -----------------------------------------------------------------------------------------------------------------------------------------------------------------
 * Date             By                  Description
 * -----------------------------------------------------------------------------------------------------------------------------------------------------------------
 * 27-Dec-2024      Pooja P Bhat        Initial Version
********************************************************************************************************************************************************************/

public without sharing class DmsUserProfile {

    
    public static String userFields =  'Id, Name, CompanyName, Phone, MobilePhone, Email, FullPhotoUrl, SmallPhotoUrl, MediumPhotoUrl,' +
                                        'GSTIN__c, PAN_Number__c, Invoice_Number_Prefix__c, Invoice_Start_Number__c, State, Notes__c, ' +
                                        'Bank_Name__c, Bank_Account_Number__c, IFSC_Code__c, UPI_ID__c, UPI_QR_CODE__c, ' +
        								'Contact.Account.BillingStreet,Contact.Account.BillingCity,Contact.Account.BillingState,Contact.Account.BillingPostalCode,Contact.Account.BillingCountry,'+
                                        'Terms_and_Conditions__c, Contact.AccountId,Contact.Account.Name,AccountId,Primary_Distributor__c , Contact.Account.Phone_1__c, Contact.Account.Primary_State__c';

  
  
    
    public static User fetchDMSUser() {
        Id userId                       =   UserInfo.getUserId();
        User loggedInUser = [SELECT Id, AccountId FROM User WHERE Id = :UserInfo.getUserId()];
    
        // Check if logged-in user has an AccountId
        if (loggedInUser.AccountId == null) {
            System.debug('No AccountId found for the logged-in user.');
            return null; // Exit if there's no AccountId
        }
        String queryStr                 =   'SELECT ' + userFields + ' FROM User WHERE AccountId=:loggedInUser.AccountId AND Primary_Distributor__c = true LIMIT 1';
        Map<String, Object> bindVarMap  =   new Map<String, Object> {'AccountId' => loggedInUser.AccountId};
        List<User> dmsUserList          =   Utility.soqlQuery(queryStr,bindVarMap,AccessLevel.USER_MODE);
        return dmsUserList.size() == 1 ? dmsUserList[0] : null;
    }   //End of class fetchDMSUser
 

   public static User fetchDMSUser(String userId) {
        User loggedInUser = [SELECT Id, AccountId FROM User WHERE Id =: userId];
    
        // Check if logged-in user has an AccountId
        if (loggedInUser.AccountId == null) {
            System.debug('No AccountId found for the logged-in user.');
            return null; // Exit if there's no AccountId
        }
        String queryStr                 =   'SELECT ' + userFields + ' FROM User WHERE AccountId=:loggedInUser.AccountId AND Primary_Distributor__c = true LIMIT 1';
        Map<String, Object> bindVarMap  =   new Map<String, Object> {'AccountId' => loggedInUser.AccountId};
        List<User> dmsUserList          =   Utility.soqlQuery(queryStr,bindVarMap,AccessLevel.USER_MODE);
        return dmsUserList.size() == 1 ? dmsUserList[0] : null;
    }   //End of class fetchDMSUser

}   //End of class DmsUserProfile