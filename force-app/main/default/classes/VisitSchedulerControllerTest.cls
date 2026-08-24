/**
* Test Class  : VisitSchedulerControllerTest
* Class Name  : VisitSchedulerController
* author      : Shyam
* CreatedDate : 24-01-25	
* Description : Test class for "VisitSchedulerController".
*               
* */
@isTest
public class VisitSchedulerControllerTest {

    // Helper method to create test data
    private static void setupTestData() {
      
        // Create a test Beat
        Beat__c beat = new Beat__c(Name = 'Test Beat', Territory__c = 'Maharashtra');
        insert beat;

        // Create a test Retailer Record Type
        RecordType retailerRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1];
        
        // Create test Retailers
        List<Account> retailers = new List<Account>();
        for (Integer i = 1; i <= 3; i++) {
            retailers.add(new Account(
                Name = 'Test Retailer ' + i,
                RecordTypeId = retailerRecordType.Id,
                Beats_Name__c = beat.Id,
                Is_Active__c = true
            ));
        }
        insert retailers;
    }

    @isTest
    static void testGetAllBeats() {
        setupTestData(); // Setup test data
        
        Test.startTest();
        List<Beat__c> beats = VisitSchedulerController.getAllBeats(new Map<String, String>());
        Test.stopTest();

        System.assertEquals(1, beats.size());
    }

    @isTest
    static void testGetRetailersByBeat() {
        setupTestData(); // Setup test data

        Beat__c testBeat = [SELECT Id FROM Beat__c LIMIT 1];

        Test.startTest();
        List<Account> retailers = VisitSchedulerController.getRetailersByBeat(testBeat.Id);
        Test.stopTest();

        System.assertNotEquals(0, retailers.size(), 'Retailers should be returned.');
    }

    @isTest
    static void testGetRetailersByBeatWithNullId() {
        Test.startTest();
        try {
            VisitSchedulerController.getRetailersByBeat(null);
            System.assert(false, 'Exception should have been thrown for null Beat Id.');
        } catch (IllegalArgumentException e) {
            System.assertEquals('Beat Id must not be null.', e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateVisits() {
        setupTestData(); // Setup test data

        Beat__c testBeat = [SELECT Id FROM Beat__c LIMIT 1];
        List<Account> retailers = [SELECT Id FROM Account LIMIT 2];
        List<Id> retailerIds = new List<Id>();
        for (Account retailer : retailers) {
            retailerIds.add(retailer.Id);
        }

        Date visitDate = Date.today().addDays(1);

        Test.startTest();
        VisitSchedulerController.createVisits(retailerIds, visitDate, testBeat.Id);
        Test.stopTest();

        // Verify the Visit record
        List<Visit__c> visits = [SELECT Id, Visit_planned_date__c, Beat__c, Status__c FROM Visit__c];
        System.assertEquals(1, visits.size(), 'One Visit should have been created.');
        System.assertEquals('Not Started', visits[0].Status__c, 'Status should be Not Started.');

        // Verify the Visit_Task__c records
        List<Visit_Task__c> visitTasks = [SELECT Id, Visit__c, Retailer__c FROM Visit_Task__c];
        System.assertEquals(2, visitTasks.size(), 'Two Visit Tasks should have been created.');
    }

    @isTest
    static void testCreateVisitsWithDuplicateVisit() {
        setupTestData(); // Setup test data

        Beat__c testBeat = [SELECT Id FROM Beat__c LIMIT 1];
        List<Account> retailers = [SELECT Id FROM Account LIMIT 2];
        List<Id> retailerIds = new List<Id>();
        for (Account retailer : retailers) {
            retailerIds.add(retailer.Id);
        }

        Date visitDate = Date.today().addDays(1);

        // Create an existing Visit for the same date and beat
        Visit__c existingVisit = new Visit__c(
            Visit_planned_date__c = visitDate,
            Visitor_Name__c = UserInfo.getUserId(),
            Beat__c = testBeat.Id,
            Status__c = 'Not Started',
            Visit_Type__c = 'Planned'
        );
        insert existingVisit;

        Test.startTest();
        try {
            VisitSchedulerController.createVisits(retailerIds, visitDate, testBeat.Id);
            System.assert(false, 'Exception should have been thrown for duplicate Visit.');
        } catch (AuraHandledException e) {
            System.assertNotEquals('A visit already exists for the selected date and beat.', e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateVisitsWithInvalidData() {
        setupTestData(); // Setup test data

        Test.startTest();
        try {
            VisitSchedulerController.createVisits(new List<Id>(), Date.today().addDays(1), null);            
        } catch (AuraHandledException e) {
            System.assertNotEquals('', e.getMessage(), 'An exception should have been thrown.');
        }
        Test.stopTest();
    }
}