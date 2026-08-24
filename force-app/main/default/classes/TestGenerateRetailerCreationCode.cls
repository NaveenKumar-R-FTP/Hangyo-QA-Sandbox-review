@isTest
private class TestGenerateRetailerCreationCode {

    static Id retailerRecordTypeId;

    @testSetup
    static void setupTestData() {
        // Query the Retailer Record Type explicitly from the database
        RecordType retailerRT = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account' AND Name = 'Retailer'
            LIMIT 1
        ];
        
        // Store it in a custom setting for test class use
        // Or use a static variable (shown below)
        retailerRecordTypeId = retailerRT.Id;
    
        // Insert the custom setting
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
    }
    
    private static Id getRetailerRecordTypeId() {
        return [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1].Id;
    }

    @isTest
    static void testRetailerCreationCodeTrigger_WithExistingSetting() {
        // Insert new Retailer Accounts (this simulates the trigger running)
        Id retailerRecordTypeId = getRetailerRecordTypeId();
        
        List<Account> newRetailers = new List<Account>{
            new Account(Name = 'Retailer A', RecordTypeId = retailerRecordTypeId),
            new Account(Name = 'Retailer B', RecordTypeId = retailerRecordTypeId)
        };

        Test.startTest();
        insert newRetailers;
        Test.stopTest();

        // Query updated accounts
        List<Account> inserted = [SELECT Name, Retailer_Code__c FROM Account WHERE Name IN ('Retailer A', 'Retailer B')];

        System.assertEquals(2, inserted.size(), 'Two accounts should be inserted');

        System.assertEquals('SF101', inserted[0].Retailer_Code__c, 'First Retailer should have SF101');
        System.assertEquals('SF102', inserted[1].Retailer_Code__c, 'Second Retailer should have SF102');

        // Confirm that the setting was updated to 102
        RetailerCodeSetting__c updatedSetting = [SELECT Latest_Code__c FROM RetailerCodeSetting__c WHERE Name = 'SF' LIMIT 1];
        System.assertEquals(102, updatedSetting.Latest_Code__c, 'Setting should increment to 102');
    }
    
    @isTest
    static void testRetailerCreationCodeTrigger_WithoutSetting() {       
        Id retailerRecordTypeId = getRetailerRecordTypeId();

        // Insert a Retailer account with existing code SF200 to simulate max existing code
        insert new Account(Name = 'Existing Retailer', RecordTypeId = retailerRecordTypeId, Retailer_Code__c = 'SF200');
        
        // Delete the existing custom setting to trigger fallback logic
        delete [SELECT Id FROM RetailerCodeSetting__c WHERE Name = 'SF'];
        
        // Insert new Retailer accounts to trigger code generation
        List<Account> newRetailers = new List<Account>{
            new Account(Name = 'Retailer C', RecordTypeId = retailerRecordTypeId),
            new Account(Name = 'Retailer D', RecordTypeId = retailerRecordTypeId)
        };

        Test.startTest();
        //insert newRetailers;
        GenerateRetailerCreationCode.retailerCreationCode(newRetailers);
        Test.stopTest();
    }

    @isTest
    static void testTriggerSkipsNonRetailerAccounts() {
        // Get default record type (non-retailer)
        Id recordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId();
        Id retailerRecordTypeId = getRetailerRecordTypeId();
        
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Retailer E', RecordTypeId = retailerRecordTypeId),
            new Account(Name = 'Non-Retailer F', RecordTypeId = recordTypeId)
        };

        Test.startTest();
        insert accounts;
        Test.stopTest();

        List<Account> inserted = [SELECT Name, Retailer_Code__c FROM Account WHERE Name IN ('Retailer E', 'Non-Retailer F')];

        for (Account acc : inserted) {
            if (acc.Name == 'Retailer E') {
                System.assertNotEquals(null, acc.Retailer_Code__c, 'Retailer E should have code assigned');
            } else if (acc.Name == 'Non-Retailer F') {
                System.assertEquals(null, acc.Retailer_Code__c, 'Non-Retailer F should NOT have a code');
            }
        }
    }
}