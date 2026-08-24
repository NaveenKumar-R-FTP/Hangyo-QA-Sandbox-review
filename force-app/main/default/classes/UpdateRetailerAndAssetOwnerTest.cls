@isTest
public class UpdateRetailerAndAssetOwnerTest {
    
    @testSetup
    static void setupData() {
        // Create RetailerCodeSetting custom setting (Hierarchy or List)
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(
            Name = 'SF',
            Latest_Code__c = 100
        );
        insert setting;

        // Create test users
        TestUtility testUser = new TestUtility();
        User ownerUser = testUser.createUser('OwnerUser');
        User employeeUser = testUser.createUser('EmployeeUser');
        User distributorOwner = testUser.createUser('DistributorOwner');
        
        Id distributorRecordType = [ 
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Distributor' AND SObjectType = 'Account' 
            LIMIT 1 
        ].Id;
        
        // Insert Distributor (Account)
        Account distributor = new Account(
            Name = 'Test Distributor',
            OwnerId = distributorOwner.Id,
            RecordTypeId = distributorRecordType
        );
        insert distributor;

        // Insert Beat
        Beat__c beat = new Beat__c(
            Name = 'Test Beat',
            OwnerId = ownerUser.Id,
            Employee_Name__c = ownerUser.Id,
            Distributor_Name__c = distributor.Id
        );
        insert beat;
        
        Id accountRecordType = [ 
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Retailer' AND SObjectType = 'Account' 
            LIMIT 1 
        ].Id;

        // Create a Retailer linked to the Beat, with Distributor__c populated
        Account retailer = new Account(
            Name = 'Retailer A',
            RecordTypeId = accountRecordType,
            Beats_Name__c = beat.Id,
            OwnerId = ownerUser.Id,
            Distributor__c = distributor.Id
        );
        insert retailer;

        // Create Asset linked to the Retailer
        Asset__c asset = new Asset__c(
            Retailer_Account__c = retailer.Id,
            OwnerId = ownerUser.Id,
            Distributor_Name__c = distributor.Id
        );
        insert asset;
    }

    @isTest
    static void testSyncOwnerAndEmployee_OwnerChangedOnly() {
        // Query the Beat
        Beat__c beat = [SELECT Id, OwnerId, Employee_Name__c FROM Beat__c LIMIT 1];

        // Simulate changing owner only
        TestUtility testUser = new TestUtility();
        User newUser = testUser.createUser('NewOwner');
        Beat__c beatClone = beat.clone(false, false, false, false);
        beatClone.OwnerId = newUser.Id;           // ownerChanged = true

        Test.startTest();
        UpdateRetailerAndAssetOwner.syncOwnerAndEmployee(
            new List<Beat__c>{ beatClone },
            new Map<Id, Beat__c>{ beatClone.Id => beat }
        );
        Test.stopTest();

        System.assertEquals(
            beatClone.OwnerId,
            beatClone.Employee_Name__c,
            'When owner changes and employee does not, employee should be updated to match owner.'
        );
    }

    @isTest
    static void testSyncOwnerAndEmployee_EmployeeChangedOnly() {
        Beat__c beat = [SELECT Id, OwnerId, Employee_Name__c FROM Beat__c LIMIT 1];

        // Simulate changing employee only
        TestUtility testUser = new TestUtility();
        User empUser = testUser.createUser('EmpUser');
        Beat__c beatClone = beat.clone(false, false, false, false);
        beatClone.Employee_Name__c = empUser.Id;  // employeeChanged = true

        Test.startTest();
        UpdateRetailerAndAssetOwner.syncOwnerAndEmployee(
            new List<Beat__c>{ beatClone },
            new Map<Id, Beat__c>{ beatClone.Id => beat }
        );
        Test.stopTest();

        System.assertEquals(
            beatClone.Employee_Name__c,
            beatClone.OwnerId,
            'When employee changes and owner does not, owner should be updated to match employee.'
        );
    }

    @isTest
    static void testRetailerAndAssetOwnerUpdate_OwnerAndDistributorChange() {
        Beat__c beat = [SELECT Id, OwnerId, Distributor_Name__c FROM Beat__c LIMIT 1];
        Account oldRetailer = [
            SELECT Id, OwnerId, Distributor__c, Beats_Name__c, Record_type_Name__c 
            FROM Account 
            WHERE Beats_Name__c = :beat.Id AND Record_type_Name__c = 'Retailer'
            LIMIT 1
        ];
        Asset__c oldAsset = [
            SELECT Id, OwnerId, Retailer_Account__c, Distributor_Name__c 
            FROM Asset__c 
            WHERE Retailer_Account__c = :oldRetailer.Id 
            LIMIT 1
        ];

        // Change Beat owner so retailer and asset should follow
        TestUtility testUser = new TestUtility();
        User newOwner = testUser.createUser('AnotherOwner');
        
        Id disRecordType = [ 
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Distributor' AND SObjectType = 'Account' 
            LIMIT 1 
        ].Id;

        // Also change Distributor on Beat to trigger distributorChanged = true
        Account anotherDistributor = new Account(
            Name = 'Another Distributor',
            OwnerId = newOwner.Id,
            RecordTypeId = disRecordType
        );
        insert anotherDistributor;

        beat.OwnerId = newOwner.Id;
        beat.Distributor_Name__c = anotherDistributor.Id;
        update beat;

        Test.startTest();
        UpdateRetailerAndAssetOwner.retailerAndAssetOwnerUpdate(new Set<Id>{ beat.Id });
        Test.stopTest();

        // Validate retailer and asset owners and distributor values
        Account updatedRetailer = [
            SELECT Id, OwnerId, Distributor__c 
            FROM Account 
            WHERE Id = :oldRetailer.Id
        ];
        Asset__c updatedAsset = [
            SELECT Id, OwnerId, Retailer_Account__c, Distributor_Name__c, Salesman__c 
            FROM Asset__c 
            WHERE Id = :oldAsset.Id
        ];

        System.assertEquals(
            newOwner.Id, 
            updatedRetailer.OwnerId, 
            'Retailer owner should be updated to Beat owner'
        );
        System.assertEquals(
            anotherDistributor.Id, 
            updatedRetailer.Distributor__c, 
            'Retailer distributor should be updated to Beat distributor'
        );
        System.assertEquals(
            newOwner.Id, 
            updatedAsset.OwnerId, 
            'Asset owner should be updated to new retailer owner'
        );
        System.assertEquals(
            newOwner.Id,
            updatedAsset.Salesman__c,
            'Asset salesman should be updated to new owner as per logic'
        );
        System.assertEquals(
            anotherDistributor.Id,
            updatedAsset.Distributor_Name__c,
            'Asset distributor should be updated to new retailer distributor'
        );
    }

    @isTest
    static void testRetailerAndAssetOwnerUpdate_DistributorOnlyChange() {
        // Here we keep Beat.OwnerId same but change Beat.Distributor_Name__c
        Beat__c beat = [SELECT Id, OwnerId, Distributor_Name__c FROM Beat__c LIMIT 1];
        Id originalOwner = beat.OwnerId;

        Account retail = [
            SELECT Id, OwnerId, Distributor__c, Beats_Name__c, Record_type_Name__c 
            FROM Account 
            WHERE Beats_Name__c = :beat.Id AND Record_type_Name__c = 'Retailer'
            LIMIT 1
        ];

        // Ensure retailer owner currently matches beat owner, so ownerChanged = false
        retail.OwnerId = originalOwner;
        update retail;

        // Create another distributor so only distributor changes
        TestUtility testUser = new TestUtility();
        User distOwner = testUser.createUser('DistOwner2');
        
        Id distributorAccRecordType = [ 
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Distributor' AND SObjectType = 'Account' 
            LIMIT 1 
        ].Id;
        
        Account thirdDistributor = new Account(
            Name = 'Third Distributor',
            OwnerId = distOwner.Id,
            RecordTypeId = distributorAccRecordType
        );
        insert thirdDistributor;

        beat.Distributor_Name__c = thirdDistributor.Id;
        update beat;

        Test.startTest();
        UpdateRetailerAndAssetOwner.retailerAndAssetOwnerUpdate(new Set<Id>{ beat.Id });
        Test.stopTest();

        Account updatedRetail = [
            SELECT Id, OwnerId, Distributor__c 
            FROM Account 
            WHERE Id = :retail.Id
        ];
        Asset__c updatedAsset = [
            SELECT Id, OwnerId, Distributor_Name__c, Retailer_Account__c 
            FROM Asset__c 
            WHERE Retailer_Account__c = :retail.Id
            LIMIT 1
        ];

        // Owner should remain same, only distributor should change
        System.assertEquals(
            originalOwner,
            updatedRetail.OwnerId,
            'Retailer owner should not change when only distributor changes'
        );
        System.assertEquals(
            thirdDistributor.Id,
            updatedRetail.Distributor__c,
            'Retailer distributor should be updated'
        );
        System.assertEquals(
            thirdDistributor.Id,
            updatedAsset.Distributor_Name__c,
            'Asset distributor should follow retailer distributor change'
        );
    }

    @isTest
    static void testUpdateDistributorOwnerFromBeat() {
        Beat__c beat = [
            SELECT Id, OwnerId, Distributor_Name__c 
            FROM Beat__c 
            WHERE Distributor_Name__c != null 
            LIMIT 1
        ];

        // New user to drive distributor owner update
        TestUtility testUser = new TestUtility();
        User newBeatOwner = testUser.createUser('NewBeatOwner');
        beat.OwnerId = newBeatOwner.Id;
        update beat;

        Account distributorBefore = [
            SELECT Id, OwnerId 
            FROM Account 
            WHERE Id = :beat.Distributor_Name__c
            LIMIT 1
        ];
        Id oldDistOwner = distributorBefore.OwnerId;

        Test.startTest();
        UpdateRetailerAndAssetOwner.updateDistributorOwnerFromBeat(new Set<Id>{ beat.Id });
        Test.stopTest();

        Account distributorAfter = [
            SELECT Id, OwnerId 
            FROM Account 
            WHERE Id = :beat.Distributor_Name__c
            LIMIT 1
        ];

        System.assertEquals(
            newBeatOwner.Id,
            distributorAfter.OwnerId,
            'Distributor owner should be updated to Beat owner'
        );
    }

    // Utility class to create test users
    public class TestUtility {
        private User createUser(String alias) {
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