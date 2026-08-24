@isTest
public class UpdateRetailerBeatControllerTest {
    
    @isTest
    public static void setup() {
        // Create test data for Visit_Task__c
        Account distributorAcc = new Account(Name = 'Test Distributor',
            RecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Distributor' AND SObjectType = 'Account' LIMIT 1].Id,
            Phone = '123-456-7890',
            PAN_Number__c = '248001'
        );
        insert distributorAcc;
        
        Account retailerrAcc = new Account(Name = 'Test Retailer 1',
            RecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Retailer' AND SObjectType = 'Account' LIMIT 1].Id,
            Phone = '123-456-7890' ,
            PAN_Number__c = '246001'
        );
        insert retailerrAcc;
        
        Beat__c beat = new Beat__c(Name = 'Test Beat', Distributor_Name__c = distributorAcc.Id);
        insert beat;
        
        Account updateRetailerAcc = new Account();
        updateRetailerAcc.Id = retailerrAcc.Id;
        updateRetailerAcc.Beats_Name__c = beat.Id;
        update updateRetailerAcc;
        
        List<Beat__c> beatList = UpdateRetailerBeatController.getAllBeats('b');
        List<Account> accList = UpdateRetailerBeatController.getAllRetailer('t');
        List<Id> beatId = new List<Id>{beat.Id};
        List<Id> acctId = new List<Id>{retailerrAcc.Id};
        String result = UpdateRetailerBeatController.updateRetailerRecord(beatId, acctId);
    }
}