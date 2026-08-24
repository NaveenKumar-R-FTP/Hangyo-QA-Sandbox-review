@isTest
public class TestRetailer_BeatChange {
    
    @testSetup
    static void setupData() {
        // Create test users
        TestUtility testUser = new TestUtility();
        User ownerUser = testUser.createUser('OwnerUser');
        User employeeUser = testUser.createUser('EmployeeUser');
        
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        // Fetch Record Types
        Id distributorRecordType = [ 
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Distributor' AND SObjectType = 'Account' 
            LIMIT 1 
        ].Id;

        Id retailerRecordType = [ 
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Retailer' AND SObjectType = 'Account' 
            LIMIT 1 
        ].Id;

        // Create Distributors
        Account distributor1 = new Account(
            Name = 'Distributor 1',
            RecordTypeId = distributorRecordType,
            OwnerId = ownerUser.Id
        );
        
        Account distributor2 = new Account(
            Name = 'Distributor 2',
            RecordTypeId = distributorRecordType,
            OwnerId = employeeUser.Id
        );

        insert new List<Account>{distributor1, distributor2};

        // Create Beats
        Beat__c beat1 = new Beat__c(
            Name = 'Beat One',
            OwnerId = ownerUser.Id,
            Distributor_Name__c = distributor1.Id,
            Employee_Name__c = ownerUser.Id
        );
        
        Beat__c beat2 = new Beat__c(
            Name = 'Beat Two',
            OwnerId = employeeUser.Id,
            Distributor_Name__c = distributor2.Id,
            Employee_Name__c = employeeUser.Id
        );

        insert new List<Beat__c>{beat1, beat2};

        // Create Retailers
        Account retailerWithBeat = new Account(
            Name = 'Retailer With Beat',
            RecordTypeId = retailerRecordType,
            Beats_Name__c = beat2.Id,
            OwnerId = ownerUser.Id // This will change to employeeUser.Id after update
        );

        Account retailerWithoutBeat = new Account(
            Name = 'Retailer Without Beat',
            RecordTypeId = retailerRecordType,
            OwnerId = ownerUser.Id // Should remain unchanged
        );

        insert new List<Account>{retailerWithBeat, retailerWithoutBeat};

        // Create Assets for retailers
        Asset__c asset1 = new Asset__c(
            Retailer_Account__c = retailerWithBeat.Id,
            OwnerId = ownerUser.Id
        );

        Asset__c asset2 = new Asset__c(
            Retailer_Account__c = retailerWithoutBeat.Id,
            OwnerId = ownerUser.Id
        );

        insert new List<Asset__c>{asset1, asset2};
    }
    
    @isTest
    static void testRetailerOwnerUpdate() {
        // Get test data
        List<Account> retailers = [
            SELECT Id, OwnerId, Beats_Name__c, Distributor__c 
            FROM Account 
            WHERE RecordType.DeveloperName = 'Retailer'
        ];

        Set<Id> accountIds = new Set<Id>();
        for (Account acc : retailers) {
            accountIds.add(acc.Id);
        }

        Test.startTest();
        Retailer_BeatChange.retailerOwnerUpdate(accountIds);
        Test.stopTest();

        // Fetch updated records
        List<Account> updatedRetailers = [
            SELECT Id, Beats_Name__c, OwnerId, Distributor__c 
            FROM Account 
            WHERE Id IN :accountIds
        ];

        List<Asset__c> updatedAssets = [
            SELECT Id, Retailer_Account__c, OwnerId, Distributor_Name__c 
            FROM Asset__c 
            WHERE Retailer_Account__c IN :accountIds
        ];

        // Assertions to verify behavior
        for (Account acc : updatedRetailers) {
            if (acc.Beats_Name__c != null) {
                System.assertNotEquals(null, acc.Distributor__c, 'Distributor should be updated.');
            } else {
                System.assertEquals(null, acc.Distributor__c, 'Distributor should not be set if beat is null.');
            }
        }

        for (Asset__c ast : updatedAssets) {
            Account relatedAcc = [SELECT OwnerId, Distributor__c FROM Account WHERE Id = :ast.Retailer_Account__c];
            System.assertEquals(relatedAcc.OwnerId, ast.OwnerId, 'Asset owner should match updated retailer owner.');
            System.assertEquals(relatedAcc.Distributor__c, ast.Distributor_Name__c, 'Asset distributor should match updated retailer distributor.');
        }
    }

    // Utility class to create test users
    public class TestUtility {
        public User createUser(String alias) {
            Profile p = [SELECT Id FROM Profile WHERE Name = 'SFA Profile' LIMIT 1];
            User u = new User(
                FirstName = alias,
                LastName = 'Test',
                Email = alias + '@test.com',
                Username = alias + '.' + System.currentTimeMillis() + '@test.com',
                Alias = alias.replaceAll('\\s','').substring(0, Math.min(8, alias.length())),
                TimeZoneSidKey = 'America/New_York',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = p.Id,
                Employee_Role__c = 'ASM'
            );
            insert u;
            return u;
        }
    }
}