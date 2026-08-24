/**
* Test Class  : createNewVisitTaskContollerTest
* author      : Shyam
* CreatedDate : 28-12-24
* Description : This is test class for createNewVisitTaskContollerTest.
* */
@isTest
private class CreateNewVisitTaskContollerTest {

    // Create custom setting once for all tests
    @testSetup
    static void setupTestData() {
        // Create the RetailerCodeSetting__c custom setting needed for Account trigger
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(
            Name = 'SF', 
            Latest_Code__c = 100
        );
        insert setting;
    }

    @isTest
    private static void testGetRetailers() {
        Beat__c beat = new Beat__c(Name = 'Nagpur');
        insert beat;
        Id retailerRtId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId();
        Account retailer1 = new Account(Name = 'Retailer 1', Beats_Name__c = beat.Id, PAN_Number__c = 'ASA445', RecordTypeId = retailerRtId, Is_Active__c = true, OwnerId = UserInfo.getUserId());
        Account retailer2 = new Account(Name = 'Retailer 2', Beats_Name__c = beat.Id, PAN_Number__c = 'ASB445', RecordTypeId = retailerRtId, Is_Active__c = true, OwnerId = UserInfo.getUserId());
        insert retailer1;
        insert retailer2;

        Test.startTest();
        List<Account> result = createNewVisitTaskContoller.getRetailers('Retailer', 'Retailer');
        Test.stopTest();

        System.assertNotEquals(null, result);

        delete retailer1;
        delete retailer2;
    }

    @isTest
    private static void testGetLatestVisit() {
        Visit__c visit = new Visit__c(
            Visit_planned_date__c = Date.today(),
            Visitor_Name__c = UserInfo.getUserId(),
            Status__c = 'Not Started',
            Visit_Type__c = 'Ad-Hoc'
        );
        insert visit;

        Visit__c result = createNewVisitTaskContoller.getLatestVisit();

        System.assertNotEquals(null, result);
        System.assertEquals(visit.Id, result.Id);

        delete visit;
    }

    @isTest
    private static void testCreateVisit() {
        Beat__c beat = new Beat__c(Name = 'Nagpur');
        insert beat;
        
        Id beatId = [SELECT Id FROM Beat__c LIMIT 1].Id;
        Account retailer1 = new Account(Name = 'Retailer 1', Beats_Name__c = beat.Id, PAN_Number__c = 'ASM245', RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId(), OwnerId = UserInfo.getUserId());
        Account retailer2 = new Account(Name = 'Retailer 2', Beats_Name__c = beat.Id, PAN_Number__c = 'ASU545', RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId(), OwnerId = UserInfo.getUserId());
        insert retailer1;
        insert retailer2;

        List<Id> retailerIds = new List<Id>{retailer1.Id, retailer2.Id};

        Test.startTest();
        createNewVisitTaskContoller.createVisit(beatId, retailerIds);
        Test.stopTest();

        Visit__c createdVisit = [SELECT Id FROM Visit__c WHERE Visitor_Name__c = :UserInfo.getUserId() AND Visit_Planned_Date__c = :Date.today() LIMIT 1];
        System.assertNotEquals(null, createdVisit);

        List<Visit_Task__c> createdTasks = [SELECT Id FROM Visit_Task__c WHERE Visit__c = :createdVisit.Id];
        System.assertEquals(2, createdTasks.size());

        delete createdVisit;
        delete retailer2;
    }

    @isTest
    private static void testCreateVisitAndTasks() {
        Beat__c beat = new Beat__c(Name = 'Nagpur');
        insert beat;
        
        Id beatId = [SELECT Id FROM Beat__c LIMIT 1].Id;
        Account retailer1 = new Account(Name = 'Retailer 1', Beats_Name__c = beat.Id, PAN_Number__c = 'ASB555', RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId(), OwnerId = UserInfo.getUserId());
        Account retailer2 = new Account(Name = 'Retailer 2', Beats_Name__c = beat.Id, PAN_Number__c = 'ASB455', RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId(), OwnerId = UserInfo.getUserId());
        insert retailer1;
        insert retailer2;

        List<Id> retailerIds = new List<Id>{retailer1.Id, retailer2.Id};

        Test.startTest();
        createNewVisitTaskContoller.createVisitAndTasks(retailerIds);
        Test.stopTest();

        Visit__c createdVisit = [SELECT Id FROM Visit__c WHERE Visitor_Name__c = :UserInfo.getUserId() AND Visit_Planned_Date__c = :Date.today() LIMIT 1];
        System.assertNotEquals(null, createdVisit);

        List<Visit_Task__c> createdTasks = [SELECT Id FROM Visit_Task__c WHERE Visit__c = :createdVisit.Id];
        System.assertEquals(2, createdTasks.size());

        delete createdVisit;
        delete retailer2;
    }
    
    // added by Fuzail - Note: createVisit method only supports Retailer accounts (always sets Retailer__c field)
    // Distributors should use createVisitAndTasks method instead, which is tested in testCreateVisitAndTasksForDistributor
    
    // added by Fuzail - Test createVisitAndTasks for Distributor accounts
    @isTest
    private static void testCreateVisitAndTasksForDistributor() {
        Beat__c beat = new Beat__c(Name = 'Nagpur');
        insert beat;
        
        RecordType distributorRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Distributor' LIMIT 1];
        
        Account distributor1 = new Account(
            Name = 'Distributor 1', 
            Beats_Name__c = beat.Id, 
            PAN_Number__c = 'DIST003',
            RecordTypeId = distributorRecordType.Id,
            OwnerId = UserInfo.getUserId()
        );
        Account distributor2 = new Account(
            Name = 'Distributor 2', 
            Beats_Name__c = beat.Id, 
            PAN_Number__c = 'DIST004',
            RecordTypeId = distributorRecordType.Id,
            OwnerId = UserInfo.getUserId()
        );
        insert distributor1;
        insert distributor2;

        List<Id> distributorIds = new List<Id>{distributor1.Id, distributor2.Id};

        Test.startTest();
        createNewVisitTaskContoller.createVisitAndTasks(distributorIds);
        Test.stopTest();

        Visit__c createdVisit = [SELECT Id FROM Visit__c WHERE Visitor_Name__c = :UserInfo.getUserId() AND Visit_Planned_Date__c = :Date.today() LIMIT 1];
        System.assertNotEquals(null, createdVisit);

        List<Visit_Task__c> createdTasks = [
            SELECT Id, Distributor__c, Account__c, Retailer__c 
            FROM Visit_Task__c 
            WHERE Visit__c = :createdVisit.Id
        ];
        System.assertEquals(2, createdTasks.size(), 'Two Visit Tasks should be created');
        
        for (Visit_Task__c task : createdTasks) {
            System.assertNotEquals(null, task.Distributor__c, 'Distributor__c should be populated');
            System.assertEquals(null, task.Account__c, 'Account__c should be null for Distributor');
            System.assertEquals(null, task.Retailer__c, 'Retailer__c should be null for Distributor');
        }

        delete createdVisit;
    }
    
    // added by Fuzail - Test getRetailers with empty searchKey
    @isTest
    private static void testGetRetailersWithEmptySearchKey() {
        Beat__c beat = new Beat__c(Name = 'Nagpur');
        insert beat;
        
        Id retailerRtId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId();
        Account retailer1 = new Account(Name = 'Retailer 1', Beats_Name__c = beat.Id, PAN_Number__c = 'ASA445', RecordTypeId = retailerRtId, Is_Active__c = true, OwnerId = UserInfo.getUserId());
        insert retailer1;

        Test.startTest();
        List<Account> result = createNewVisitTaskContoller.getRetailers('', 'Retailer');
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        delete retailer1;
    }
    
    // added by Fuzail - Test getRetailers with null searchKey
    @isTest
    private static void testGetRetailersWithNullSearchKey() {
        Beat__c beat = new Beat__c(Name = 'Nagpur');
        insert beat;
        
        Id retailerRtId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId();
        Account retailer1 = new Account(Name = 'Retailer 1', Beats_Name__c = beat.Id, PAN_Number__c = 'ASA446', RecordTypeId = retailerRtId, Is_Active__c = true, OwnerId = UserInfo.getUserId());
        insert retailer1;

        Test.startTest();
        List<Account> result = createNewVisitTaskContoller.getRetailers(null, 'Retailer');
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        delete retailer1;
    }
    
    // added by Fuzail - Test getRetailers for Distributor with searchKey
    @isTest
    private static void testGetRetailersForDistributorWithSearch() {
        Id distributorRtId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId();
        Account distributor1 = new Account(Name = 'Distributor Test 1', PAN_Number__c = 'DIST005', RecordTypeId = distributorRtId, Is_Active__c = true, OwnerId = UserInfo.getUserId());
        insert distributor1;

        Test.startTest();
        List<Account> result = createNewVisitTaskContoller.getRetailers('Distributor Test', 'Distributor');
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        delete distributor1;
    }
    
    // added by Fuzail - Test getRetailers for Retailer with Beat Name search
    @isTest
    private static void testGetRetailersForRetailerWithBeatNameSearch() {
        Beat__c beat = new Beat__c(Name = 'Test Beat');
        insert beat;
        
        Id retailerRtId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId();
        Account retailer1 = new Account(Name = 'Retailer 1', Beats_Name__c = beat.Id, PAN_Number__c = 'ASA447', RecordTypeId = retailerRtId, Is_Active__c = true, OwnerId = UserInfo.getUserId());
        insert retailer1;

        Test.startTest();
        List<Account> result = createNewVisitTaskContoller.getRetailers('Test Beat', 'Retailer');
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        delete retailer1;
    }
    
    // added by Fuzail - Test getLatestVisit when no visit exists
    @isTest
    private static void testGetLatestVisitWhenNoVisitExists() {
        List<Visit__c> existingVisits = [SELECT Id FROM Visit__c WHERE Visit_planned_date__c = :Date.today() AND Visitor_Name__c = :UserInfo.getUserId()];
        delete existingVisits;

        Visit__c result = createNewVisitTaskContoller.getLatestVisit();

        System.assertEquals(null, result, 'Should return null when no visit exists');
    }
    
       
    // added by Fuzail - Test createVisitAndTasks reusing existing visit
    @isTest
    private static void testCreateVisitAndTasksReuseExistingVisit() {
        Beat__c beat = new Beat__c(Name = 'Nagpur');
        insert beat;
        
        Id retailerRtId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId();
        Account retailer1 = new Account(Name = 'Retailer 1', Beats_Name__c = beat.Id, PAN_Number__c = 'ASB556', RecordTypeId = retailerRtId, OwnerId = UserInfo.getUserId());
        Account retailer2 = new Account(Name = 'Retailer 2', Beats_Name__c = beat.Id, PAN_Number__c = 'ASB456', RecordTypeId = retailerRtId, OwnerId = UserInfo.getUserId());
        insert retailer1;
        insert retailer2;

        Visit__c existingVisit = new Visit__c(
            Visit_Planned_Date__c = Date.today(),
            Visitor_Name__c = UserInfo.getUserId(),
            Status__c = 'Not Started',
            Visit_Type__c = 'Ad-Hoc'
        );
        insert existingVisit;

        List<Id> retailerIds = new List<Id>{retailer1.Id, retailer2.Id};

        Test.startTest();
        createNewVisitTaskContoller.createVisitAndTasks(retailerIds);
        Test.stopTest();

        List<Visit__c> visits = [SELECT Id FROM Visit__c WHERE Visitor_Name__c = :UserInfo.getUserId() AND Visit_Planned_Date__c = :Date.today()];
        System.assertEquals(1, visits.size(), 'Should reuse existing visit');

        List<Visit_Task__c> createdTasks = [SELECT Id FROM Visit_Task__c WHERE Visit__c = :existingVisit.Id];
        System.assertEquals(2, createdTasks.size(), 'Should create 2 tasks');

        delete existingVisit;
    }
    
    // added by Fuzail - Test createVisitAndTasks with mixed Retailer and Distributor accounts
    @isTest
    private static void testCreateVisitAndTasksWithMixedAccounts() {
        Beat__c beat = new Beat__c(Name = 'Nagpur');
        insert beat;
        
        Id retailerRtId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId();
        Id distributorRtId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId();
        
        Account retailer1 = new Account(Name = 'Retailer 1', Beats_Name__c = beat.Id, PAN_Number__c = 'ASB557', RecordTypeId = retailerRtId, OwnerId = UserInfo.getUserId());
        Account distributor1 = new Account(Name = 'Distributor 1', Beats_Name__c = beat.Id, PAN_Number__c = 'DIST006', RecordTypeId = distributorRtId, OwnerId = UserInfo.getUserId());
        insert retailer1;
        insert distributor1;

        List<Id> accountIds = new List<Id>{retailer1.Id, distributor1.Id};

        Test.startTest();
        createNewVisitTaskContoller.createVisitAndTasks(accountIds);
        Test.stopTest();

        Visit__c createdVisit = [SELECT Id FROM Visit__c WHERE Visitor_Name__c = :UserInfo.getUserId() AND Visit_Planned_Date__c = :Date.today() LIMIT 1];
        System.assertNotEquals(null, createdVisit);

        List<Visit_Task__c> createdTasks = [
            SELECT Id, Retailer__c, Distributor__c, Account__c 
            FROM Visit_Task__c 
            WHERE Visit__c = :createdVisit.Id
        ];
        System.assertEquals(2, createdTasks.size());
        
        Visit_Task__c retailerTask = createdTasks[0].Retailer__c == retailer1.Id ? createdTasks[0] : createdTasks[1];
        System.assertEquals(retailer1.Id, retailerTask.Retailer__c);
        System.assertEquals(retailer1.Id, retailerTask.Account__c);
        
        Visit_Task__c distributorTask = createdTasks[0].Distributor__c == distributor1.Id ? createdTasks[0] : createdTasks[1];
        System.assertEquals(distributor1.Id, distributorTask.Distributor__c);
        System.assertEquals(null, distributorTask.Retailer__c);
        System.assertEquals(null, distributorTask.Account__c);

        delete createdVisit;
    }
    
}