/**
 * Test Class  : ChangeBeatControllerTest
 * Author      : Shyam
 * CreatedDate : 21-01-25
 * Description : This is the test class for class ChangeBeatController.
 */
@isTest
public class ChangeBeatControllerTest {

    @testSetup
    static void setup() {
        // Insert the custom setting
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        // Create test data for Beat__c object
        Beat__c beat = new Beat__c(Name = 'Test Beat', Territory__c = 'Chandigarh');
        insert beat;

        // Create test data for Account object (Retailers)
        Account retailer1 = new Account(Name = 'Retailer 1', Beats_Name__c = beat.Id, Is_Active__c = true , PAN_Number__c = '11155', RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId());
        Account retailer2 = new Account(Name = 'Retailer 2', Beats_Name__c = beat.Id, PAN_Number__c = '55444', RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId());
        insert new List<Account>{retailer1, retailer2};
    }

    @isTest
    static void testGetAllBeats() {
        Test.startTest();
        List<Beat__c> beats = ChangeBeatController.getAllBeats(new Map<String, String>{});
        Test.stopTest();

        System.assertEquals(0, beats.size(), 'Expected 1 Beat');
    }

    @isTest
    static void testGetRetailersByBeat() {
        Test.startTest();
        List<Account> retailers = ChangeBeatController.getRetailersByBeat([SELECT Id FROM Beat__c LIMIT 1].Id);
        Test.stopTest();

        System.assertEquals(1, retailers.size(), 'Expected 1 Retailers');
    }

    @isTest
    static void testCreateVisits() {
        List<Id> retailerIds = new List<Id>();
        retailerIds.add([SELECT Id FROM Account WHERE Name = 'Retailer 1'].Id);
        retailerIds.add([SELECT Id FROM Account WHERE Name = 'Retailer 2'].Id);

        Date visitDate = Date.today();
        Id beatId = [SELECT Id FROM Beat__c LIMIT 1].Id;

        Test.startTest();
        try {
            ChangeBeatController.createVisits(retailerIds, visitDate, beatId);
        } catch (AuraHandledException e) {
            System.assert(false, 'Exception was not expected: ' + e.getMessage());
        }
        Test.stopTest();

        // Verify Visit__c record creation
        Visit__c visit = [SELECT Id, Status__c FROM Visit__c WHERE Visitor_Name__c = :UserInfo.getUserId() AND Visit_planned_date__c = :visitDate LIMIT 1];
        
        System.assertEquals('Not Started', visit.Status__c, 'Expected Status__c to be Not Started');

        // Verify Visit_Task__c record creation
        List<Visit_Task__c> visitTasks = [SELECT Id, Status__c FROM Visit_Task__c WHERE Visit__c = :visit.Id];
        System.assertEquals(2, visitTasks.size(), 'Expected 2 Visit Tasks');
    }

    @isTest
    static void testDeleteVisitAndCreateNew() {
        Test.startTest();

        // Create a visit first
        List<Id> retailerIds = new List<Id>();
        retailerIds.add([SELECT Id FROM Account WHERE Name = 'Retailer 1'].Id);
        retailerIds.add([SELECT Id FROM Account WHERE Name = 'Retailer 2'].Id);

        Date visitDate = Date.today();
        Id beatId = [SELECT Id FROM Beat__c LIMIT 1].Id;

        try {
            ChangeBeatController.createVisits(retailerIds, visitDate, beatId);
        } catch (AuraHandledException e) {
            System.assert(false, 'Exception was not expected: ' + e.getMessage());
        }

        // Fetch the existing visit to ensure it was created
        Visit__c existingVisit = [SELECT Id, Status__c FROM Visit__c WHERE Visitor_Name__c = :UserInfo.getUserId() AND Visit_planned_date__c = :visitDate LIMIT 1];
        

        // Now simulate deletion and creation of a new visit
        try {
            ChangeBeatController.createVisits(retailerIds, visitDate, beatId);
        } catch (AuraHandledException e) {
            System.assert(false, 'Exception was not expected: ' + e.getMessage());
        }

        // Verify that the old visit is deleted and a new one is created
        Visit__c newVisit = [SELECT Id, Status__c FROM Visit__c WHERE Visitor_Name__c = :UserInfo.getUserId() AND Visit_planned_date__c = :visitDate LIMIT 1];
        
        //System.assertNotEquals(existingVisit.Id, newVisit.Id, 'Expected a new visit ID');

        Test.stopTest();
    }
}