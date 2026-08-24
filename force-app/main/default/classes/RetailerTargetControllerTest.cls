@isTest
public class RetailerTargetControllerTest {

    static String base64Data;
    static String base64DataFalse;

    @testSetup
    static void setupTestData() {
        // Step 1: Create Retailer RecordType
        RecordType retailerRecordType = [SELECT Id FROM RecordType WHERE DeveloperName = 'Retailer' LIMIT 1];

        // Step 2: Create Retailer Accounts
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            accounts.add(new Account(
                Name = 'Test Retailer ' + i,
                PAN_Number__c = 'AKSQ225'+ i,
                RecordTypeId = retailerRecordType.Id
            ));
        }
        insert accounts;

        // Step 3: Create Retailer_Target__c records linked to Accounts
        List<Retailer_Target__c> targets = new List<Retailer_Target__c>();
        for (Account acc : accounts) {
            targets.add(new Retailer_Target__c(
                Retailer__c = acc.Id,
                Amount__c = '900'
            ));
        }
        insert targets;

        // Step 4: Dynamically Build the String
        base64Data = 'Account Id,Retailer Name,Retailer Address,Retailer Location,Target Amount,Source\\r\\n';
        for (Account acc : accounts) {
            base64Data += acc.Id + ',' + acc.Name + ',Test1,address,11.33,66\\r\\n';
        }
        
        base64DataFalse = 'Account Id,Retailer Name,Retailer Address,Retailer Location,Target Amount,Source\\r\\n';
        for (Account acc : accounts) {
            base64DataFalse += acc.Id + ',' + acc.Name + ',Test1,address,11.33,77\\r\\n';
        }
    }

    @isTest
    static void testGetRetailerTargets() {
        // Create a Retailer Account and associated Retailer_Target__c record
        Account retailerAccount = new Account(
            Name = 'Test Retailer',
            PAN_Number__c = 'AKSI725',
            RecordTypeId = [SELECT Id FROM RecordType WHERE DeveloperName = 'Retailer' LIMIT 1].Id
        );
        insert retailerAccount;

        Retailer_Target__c target = new Retailer_Target__c(
            Retailer__c = retailerAccount.Id,
            Target_Amount__c = 1000,
            Amount__c = '900'
        );
        insert target;

        // Test method for retrieving retailer targets
        Test.startTest();
        List<Account> retailerAccounts = RetailerTargetController.getRetailerTargets();
        Test.stopTest();

        System.assertNotEquals(0, retailerAccounts.size(), 'Retailer accounts should be returned');
        System.assertEquals(1, retailerAccounts[0].Retailer_Targets__r.size(), 'One retailer target should be returned');
    }

    @isTest
    static void testSaveFileExistingTarget() {
        // Setup retailer and target data
        Account retailerAccount = new Account(
            Name = 'Test Retailer',
            PAN_Number__c = 'AKSS225',
            RecordTypeId = [SELECT Id FROM RecordType WHERE DeveloperName = 'Retailer' LIMIT 1].Id
        );
        insert retailerAccount;

        Retailer_Target__c target = new Retailer_Target__c(
            Retailer__c = retailerAccount.Id,
            Target_Amount__c = 1000,
            Amount__c = '900'
        );
        insert target;

        String base64Data = '\"Account Id,Retailer Name,Retailer Address,Retailer Location,Target Amount,Source\\r\\n' + 
            retailerAccount.Id + ',Test Retailer,address,11.33,66\\r\\n\"';

        String base64DataFalse = '\"Account Id,Retailer Name,Retailer Address,Retailer Location,Target Amount,Source\\r\\n' + 
            retailerAccount.Id + ',Test Retailer,address,11.33,100\\r\\n\"';

        // Testing valid and invalid data
        Test.startTest();
        List<Retailer_Target__c> savedTargets = RetailerTargetController.saveFile(base64Data);
        List<Retailer_Target__c> savedTargetsFalse = RetailerTargetController.saveFile(base64DataFalse);
        Test.stopTest();

        System.assertEquals(1, savedTargets.size(), 'Only one target should be updated');
        System.assertEquals(1, savedTargetsFalse.size(), 'Only one target should be updated');
    }

    @isTest
    static void testProcessTargetRowAndPerformUpsert() {
        // Create Retailer Account
        Account retailer = new Account(Name = 'Test Retailer', PAN_Number__c = 'AKSQ295', RecordTypeId = [SELECT Id FROM RecordType WHERE DeveloperName = 'Retailer' LIMIT 1].Id);
        insert retailer;

        // Create an existing Retailer_Target__c record
        Retailer_Target__c existingTarget = new Retailer_Target__c(Retailer__c = retailer.Id, Amount__c = '5000');
        insert existingTarget;

        // Test processTargetRow
        String jsonString = '{"retailerId":"' + retailer.Id + '", "newTargetAmount": 6000}';
        RetailerTargetController.TargetRowData targetData = (RetailerTargetController.TargetRowData) JSON.deserialize(jsonString, RetailerTargetController.TargetRowData.class);
        Map<String, Retailer_Target__c> existingTargetsMap = new Map<String, Retailer_Target__c>{retailer.Id => existingTarget};
        List<Retailer_Target__c> targetsToUpsert = new List<Retailer_Target__c>();

        Test.startTest();
        RetailerTargetController.processTargetRow(targetData, existingTargetsMap, targetsToUpsert);
        

        System.assertEquals(1, targetsToUpsert.size(), 'One record should be queued for upsert.');
        System.assertEquals('6000', targetsToUpsert[0].Amount__c, 'Target amount should be updated.');

        // Perform Upsert
        
        RetailerTargetController.performUpsert(targetsToUpsert);
        Test.stopTest();

        // Verify records were upserted
        List<Retailer_Target__c> updatedTargets = [SELECT Id, Amount__c FROM Retailer_Target__c WHERE Retailer__c = :retailer.Id];
        System.assertEquals(1, updatedTargets.size(), 'Only one target should exist for the retailer.');
        System.assertEquals('6000', updatedTargets[0].Amount__c, 'Target amount should be updated.');
    }

    @isTest
    static void testGetCurrentMonthYear() {
        String currentMonthYear = RetailerTargetController.getCurrentMonthYear();
        System.assertNotEquals(null, currentMonthYear, 'Current month-year should be returned.');
    }

    @isTest
    static void testSplitCSVLine() {
        String line = '12345,Test Retailer,Test Address,Test Location,1000';
        List<String> result = RetailerTargetController.splitCSVLine(line);
        System.assertEquals(5, result.size(), 'Should split into 5 columns.');
    }
    @isTest
    static void testUpdateRetailerMonthlyTarget() {
        // Step 1: Create a Retailer Account
        Account retailerAccount = new Account(
            Name = 'Test Retailer',
            PAN_Number__c = 'AKSQ355',
            RecordTypeId = [SELECT Id FROM RecordType WHERE DeveloperName = 'Retailer' LIMIT 1].Id
        );
        insert retailerAccount;

        // Step 2: Create Retailer_Target__c records linked to the Account
        List<Retailer_Target__c> targets = new List<Retailer_Target__c>();
        for (Integer i = 0; i < 3; i++) {
            targets.add(new Retailer_Target__c(
                Retailer__c = retailerAccount.Id,
                Amount__c = '1000'
            ));
        }
        insert targets;

        // Step 3: Update the target amounts to simulate the scenario where the retailer's targets are modified
        List<Retailer_Target__c> updatedTargets = [SELECT Id, Amount__c, Retailer_Target__c.Retailer__c FROM Retailer_Target__c WHERE Retailer__c = :retailerAccount.Id];
        for (Retailer_Target__c target : updatedTargets) {
            target.Amount__c = '1200';
        }
        update updatedTargets;

        // Step 4: Call the updateRetailerMonthlyTarget method
        Test.startTest();
        RetailerTargetController.updateRetailerMonthlyTarget(updatedTargets);
        Test.stopTest();

        // Step 5: Verify the results - check if the Monthly_Target__c field is updated correctly
        Account updatedRetailerAccount = [SELECT Id, Monthly_Target__c FROM Account WHERE Id = :retailerAccount.Id];
        
        Decimal expectedTotalTarget = 1200 * updatedTargets.size();
        System.assertEquals(expectedTotalTarget, updatedRetailerAccount.Monthly_Target__c, 'The Monthly_Target__c field should be updated correctly.');
    }
}