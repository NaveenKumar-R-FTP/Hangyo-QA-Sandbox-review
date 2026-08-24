@IsTest
public with sharing class RetailerAccountControllerTest {

    @TestSetup
    static void setupTestData() {
        // Insert the custom setting
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        // Retrieve Retailer Record Type
        RecordType retailerRecordType = [SELECT Id FROM RecordType WHERE Name = 'Retailer' AND SObjectType = 'Account' LIMIT 1];
          RecordType DistributorRecordType = [SELECT Id FROM RecordType WHERE Name = 'Distributor' AND SObjectType = 'Account' LIMIT 1];
        
        // Create Distributor Account
        Account distributor = new Account(
            Name = 'Test Distributor',
            RecordTypeId = DistributorRecordType.Id
        );
        insert distributor;
        
        // Create retailer Account
        Account retailer = new Account(
            Name = 'Test retailer',
            RecordTypeId = retailerRecordType.Id,
            Retailer_Code__c = 'SF1001'
        );
        insert retailer;
        
          // Create Visit Task
        Visit__c visit = new Visit__c(
            Account__c = distributor.Id
        );
        insert visit;
        
        // Create Visit Task
        Visit_Task__c visitTask = new Visit_Task__c(
            Distributor__c = distributor.Id,Visit__c = visit.id
        );
        insert visitTask;
        
        // Create existing Retailer Account for duplicate test
        Account existingAccount = new Account(
            Name = 'Existing Retailer',
            RecordTypeId = retailerRecordType.Id,
            Owners_Number__c = '9876543210'
        );
        insert existingAccount;
    }

    @IsTest
    static void testUploadFile() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        Test.startTest();
        String contentVersionId = RetailerAccountController.uploadFile(
            acc.Id, 
            'test.txt', 
            EncodingUtil.base64Encode(Blob.valueOf('Test data')), 
            'text/plain'
        );
        Test.stopTest();
        
        ContentVersion cv = [SELECT Title, FirstPublishLocationId FROM ContentVersion WHERE Id = :contentVersionId];
        System.assertEquals('test.txt', cv.Title, 'File title should match');
        System.assertEquals(acc.Id, cv.FirstPublishLocationId, 'Parent account should be linked');
    }

    @IsTest
    static void testCreateContentDistribution() {
        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'test.txt',
            VersionData = Blob.valueOf('Test Data')
        );
        insert cv;
        cv = [SELECT Id FROM ContentVersion WHERE Id = :cv.Id];
        
        Test.startTest();
        String publicUrl = RetailerAccountController.createContentDistribution(cv.Id);
        Test.stopTest();
        
        ContentDistribution cd = [SELECT DistributionPublicUrl FROM ContentDistribution WHERE ContentVersionId = :cv.Id];
        System.assertEquals(cd.DistributionPublicUrl, publicUrl, 'Public URL should match');
    }

    @IsTest
    static void testUploadSelfie() {
        Account acc = new Account(Name = 'Selfie Test Account');
        insert acc;
        String base64Image = 'iVBORw0KGgoAAAANSUhEUgAAAAUAAAAFCAYAAACNbyblAAAAHElEQVQI12P4//8/w38GIAXDIBKE0DHxgljNBAAO9TXL0Y4OHwAAAABJRU5ErkJggg==';
        
        Test.startTest();
        RetailerAccountController.uploadSelfie(acc.Id, base64Image);
        Test.stopTest();
        
        Account updatedAcc = [SELECT Outlet_Image__c FROM Account WHERE Id = :acc.Id];
        System.assert(updatedAcc.Outlet_Image__c.contains('/sfc/servlet.shepherd/version/download/'), 'Outlet image URL should be set');
        
        List<ContentVersion> contentVersions = [SELECT Id FROM ContentVersion WHERE FirstPublishLocationId = :acc.Id];
        System.assertEquals(1, contentVersions.size(), 'Content Version should be created');
    }

    @IsTest
    static void testUploadSelfieInvalidData() {
        Boolean exceptionThrown = false;
        
        // Test null account ID
        try {
            RetailerAccountController.uploadSelfie(null, 'test');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        System.assert(exceptionThrown, 'Should throw exception for null account ID');
        
        // Test empty base64
        exceptionThrown = false;
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        try {
            RetailerAccountController.uploadSelfie(acc.Id, '');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        System.assert(exceptionThrown, 'Should throw exception for empty base64 data');
    }

    @IsTest
    static void testGetStatePicklistValues() {
        Test.startTest();
        List<String> states = RetailerAccountController.getStatePicklistValues();
        Test.stopTest();
        
        System.assert(!states.isEmpty(), 'Should return state values from label');
    }
    
    @IsTest
    static void testgetBeatsForCurrentUser() {
        Account distributorAcc = new Account(Name = 'Test Distributor',
            RecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Distributor' AND SObjectType = 'Account' LIMIT 1].Id,
            Phone = '123-456-7890',
            PAN_Number__c = '248001'
        );
        insert distributorAcc;
        
        Beat__c beat = new Beat__c(Name = 'Test Beat', Distributor_Name__c = distributorAcc.Id);
        insert beat;
        
        Test.startTest();
        RetailerAccountController.getBeatsForCurrentUser();
        Test.stopTest();
    }

    @IsTest
    static void testGetPicklistValues() {
        Test.startTest();
        List<Map<String, String>> options = RetailerAccountController.getPicklistValues();
        Test.stopTest();
        
        Schema.DescribeFieldResult fieldResult = Account.Outlets_Type__c.getDescribe();
        Integer activeCount = 0;
        for (Schema.PicklistEntry entry : fieldResult.getPicklistValues()) {
            if (entry.isActive()) activeCount++;
        }
        System.assertEquals(activeCount, options.size(), 'Should return all active picklist values');
    }

    @IsTest
    static void testGetRecordTypeId() {
        RecordType expected = [SELECT Id FROM RecordType WHERE Name = 'Retailer' AND SObjectType = 'Account' LIMIT 1];
        
        Test.startTest();
        Id recordTypeId = RetailerAccountController.getRecordTypeId();
        Test.stopTest();
        
        System.assertEquals(expected.Id, recordTypeId, 'Should return Retailer record type ID');
    }

    @IsTest
    static void testCheckDuplicateOwnerNumber() {
        Test.startTest();
        Boolean existingNumber = RetailerAccountController.checkDuplicateOwnerNumber('9876543210');
        Boolean newNumber = RetailerAccountController.checkDuplicateOwnerNumber('1234567890');
        Test.stopTest();
        
        System.assert(existingNumber, 'Should find duplicate owner number');
        System.assert(!newNumber, 'Should not find non-existent owner number');
    }

    @IsTest
    static void testCreateAccount() {
        RecordType rt = [SELECT Id FROM RecordType WHERE Name = 'Retailer' LIMIT 1];
        Account distributor = [SELECT Id FROM Account WHERE Name = 'Test Distributor' LIMIT 1];
        Account retailer = [SELECT Id , Retailer_Code__c FROM Account WHERE Name = 'Test retailer' LIMIT 1];
        
        
        Map<String, Object> accountData = new Map<String, Object>{
            'Name' => 'Test Retailer',
            'Owners_Name__c' => 'Test Owner',
            'Owners_Number__c' => '1122334455',
            'Outlets_Type__c' => 'Others',
            'GSTIN__c' => 'GSTIN123',
            'BillingStreet' => '123 Test St',
            'Latitude__c' => 12.3456,
            'Longitude__c' => 67.8901,
            'BillingCity' => 'Test City',
            'BillingCountry' => 'Test Country',
            'BillingPostalCode' => '12345',
            'BillingState' => 'Test State',
            'Primary_State__c' => 'Test State',
            'Primary_Address_1__c' => 'Address 1',
            'PAN_Number__c' => 'PAN123',
            'FSSAI__c' => 'FSSAI123',
            'RecordTypeId' => rt.Id,
            'Distributor__c' => distributor.Id
        };
        
        Test.startTest();
        Id accountId = RetailerAccountController.createAccount(accountData);
        Test.stopTest();
        
        Account createdAccount = [SELECT Name, BillingLatitude, BillingLongitude, Latitude__c, Longitude__c 
                                FROM Account WHERE Id = :accountId];
        System.assertEquals(12.3456, createdAccount.BillingLatitude, 'Billing latitude should match');
        System.assertEquals(67.8901, createdAccount.BillingLongitude, 'Billing longitude should match');
        System.assertEquals('12.3456', createdAccount.Latitude__c, 'Latitude string should match');
        System.assertEquals('67.8901', createdAccount.Longitude__c, 'Longitude string should match');
    }

    @IsTest
    static void testGetDistributorFromVisitTask() {
        Visit_Task__c vt = [SELECT Id, Distributor__c FROM Visit_Task__c LIMIT 1];
        
        Test.startTest();
        Id distributorId = RetailerAccountController.getDistributorFromVisitTask(vt.Id);
        Test.stopTest();
        
        System.assertEquals(vt.Distributor__c, distributorId, 'Should return correct distributor ID');
    }
}