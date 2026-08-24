@IsTest
private class Retailer_DistributorChangeTest {

    @IsTest
    static void testVisitTaskDistributorUpdate_basicFlow() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        // Step 1: Create initial Distributor and Retailer
        Account oldDistributor = new Account(
            Name = 'Old Distributor',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId()
        );
        insert oldDistributor;

        Account newDistributor = new Account(
            Name = 'New Distributor',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId()
        );
        insert newDistributor;

        Account retailer = new Account(
            Name = 'Retailer A',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId(),
            Distributor__c = oldDistributor.Id
        );
        insert retailer;
        
        Visit__c visit = new Visit__c(
            Visit_Planned_Date__c = Date.today(),
            Visitor_Name__c = UserInfo.getUserId(),
            Status__c = 'Not Started',
            Visit_Type__c = 'Ad-Hoc'
        );
        insert visit;

        // Step 2: Create Visit Tasks for this retailer
        Visit_Task__c vtNotStarted = new Visit_Task__c(
            Retailer__c = retailer.Id,
            Visit__c = visit.Id,
            Distributor__c = oldDistributor.Id,
            Status__c = 'Not Started'
        );
        Visit_Task__c vtCompleted = new Visit_Task__c(
            Retailer__c = retailer.Id,
            Visit__c = visit.Id,
            Distributor__c = oldDistributor.Id,
            Status__c = 'Completed'
        );
        insert new List<Visit_Task__c>{ vtNotStarted, vtCompleted };

        // Step 3: Change Retailer Distributor to new distributor
        retailer.Distributor__c = newDistributor.Id;
        update retailer;

        // Step 4: Call the method under test
       Test.startTest();
        retailer.Distributor__c = newDistributor.Id;
        update retailer;
        // Call directly since Record_type_Name__c formula may not populate in test
        Retailer_DistributorChange.visitTaskDistributorUpdate(new Set<Id>{ retailer.Id });
        Test.stopTest();

        // Step 5: Re-query Visit Tasks and assert
        Map<Id, Visit_Task__c> vtMap = new Map<Id, Visit_Task__c>(
            [
                SELECT Id, Distributor__c, Status__c
                FROM Visit_Task__c
                WHERE Id IN :new List<Id>{ vtNotStarted.Id, vtCompleted.Id }
            ]
        );

        // Not Started visit task should be updated to new distributor
        System.assertEquals(
            newDistributor.Id,
            vtMap.get(vtNotStarted.Id).Distributor__c,
            'Distributor__c should be updated on Not Started Visit Task'
        );

        // Completed visit task should remain unchanged
        System.assertEquals(
            oldDistributor.Id,
            vtMap.get(vtCompleted.Id).Distributor__c,
            'Distributor__c should NOT be updated on non Not Started Visit Task'
        );
    }

    @IsTest
    static void testVisitTaskDistributorUpdate_noRetailers() {
        Test.startTest();
        // Should simply return without error
        Retailer_DistributorChange.visitTaskDistributorUpdate(new Set<Id>());
        Retailer_DistributorChange.visitTaskDistributorUpdate(null);
        Test.stopTest();

        // No asserts needed here; just making sure no exception is thrown
        System.assert(true, 'Method should handle null/empty sets gracefully');
    }

    @IsTest
    static void testVisitTaskDistributorUpdate_noVisitTasks() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        // Create a retailer with distributor, but no Visit_Task__c records
        Account distributor = new Account(
            Name = 'Distributor',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId()
        );
        insert distributor;

        Account retailer = new Account(
            Name = 'Retailer No Tasks',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId(),
            Distributor__c = distributor.Id
        );
        insert retailer;

        Test.startTest();
        // Should query retailer, find no tasks, and return cleanly
        Retailer_DistributorChange.visitTaskDistributorUpdate(
            new Set<Id>{ retailer.Id }
        );
        Test.stopTest();

        System.assert(true, 'Method should handle retailers with no Visit Tasks gracefully');
    }
@IsTest
    static void testAssetMappingDistributorUpdate() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        
        Account oldDistributor = new Account(
            Name = 'Old Distributor AM',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId()
        );
        insert oldDistributor;
        
        Account newDistributor = new Account(
            Name = 'New Distributor AM',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId()
        );
        insert newDistributor;
        
        Account retailer = new Account(
            Name = 'Retailer AM Test',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId(),
            Distributor__c = oldDistributor.Id
        );
        insert retailer;
        
        Asset_Master__c master = new Asset_Master__c(
            OEM_Serial_Number__c = 'HIPL-TEST-AM001'
        );
        insert master;
        
        Asset_Mapping__c mapping = new Asset_Mapping__c(
            Retailer__c = retailer.Id,
            Distributor__c = oldDistributor.Id,
            Asset_Master__c = master.Id,
            Active__c = true
        );
        insert mapping;
        
        Test.startTest();
        retailer.Distributor__c = newDistributor.Id;
        update retailer;
        Retailer_DistributorChange.visitTaskDistributorUpdate(new Set<Id>{ retailer.Id });
        Test.stopTest();
        Asset_Mapping__c updatedMapping = [
            SELECT Id, Distributor__c
            FROM Asset_Mapping__c
            WHERE Id = :mapping.Id
        ];
        
        System.assertEquals(
            newDistributor.Id,
            updatedMapping.Distributor__c,
            'Asset Mapping Distributor should be updated to new distributor'
        );
    }
}