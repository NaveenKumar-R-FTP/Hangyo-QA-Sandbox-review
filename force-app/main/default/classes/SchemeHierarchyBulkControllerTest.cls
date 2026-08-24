@IsTest
public class SchemeHierarchyBulkControllerTest {

    @TestSetup
    static void makeData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;

        RecordType distRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Distributor' LIMIT 1];
        Account dist = new Account(
            Name = 'Bulk Test Distributor',
            RecordTypeId = distRT.Id,
            Primary_State__c = 'Kerala',
            PAN_Number__c = 'BULKDIST001',
            Hub__c = 'Mumbai'
        );
        insert dist;

        RecordType retailerRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1];
        Account retailer = new Account(
            Name = 'Bulk Test Retailer',
            RecordTypeId = retailerRT.Id,
            Primary_State__c = 'Kerala',
            PAN_Number__c = 'BULKRET001'
        );
        insert retailer;

        Region__c region = new Region__c(Name = 'Bulk Test Region');
        insert region;

        Id valueRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Value_Scheme' AND SObjectType = 'Scheme__c' LIMIT 1].Id;
        Scheme__c scheme = new Scheme__c(
            Name = 'Bulk Hierarchy Test Scheme',
            RecordTypeId = valueRT,
            Scheme_Start_Date__c = Date.today(),
            Scheme_End_Date__c = Date.today().addDays(30),
            Discount_Percentage__c = 10,
            Cart_Amount__c = 100,
            Retailer_Scheme__c = true,
            Under_SS_Scheme__c = false
        );
        insert scheme;
    }

    @IsTest
    static void testSearchDistributorsReturnsMatches() {
        List<SchemeHierarchyBulkController.AccountOption> results =
            SchemeHierarchyBulkController.searchDistributors('Bulk Test Distributor');
        System.assertEquals(1, results.size(), 'Should find the test distributor');
        System.assertEquals('Mumbai', results[0].extra, 'Should surface the Hub value');
    }

    @IsTest
    static void testSearchRetailersReturnsMatches() {
        List<SchemeHierarchyBulkController.AccountOption> results =
            SchemeHierarchyBulkController.searchRetailers('Bulk Test Retailer');
        System.assertEquals(1, results.size(), 'Should find the test retailer');
    }

    @IsTest
    static void testSearchRegionsReturnsMatches() {
        List<SchemeHierarchyBulkController.RegionOption> results =
            SchemeHierarchyBulkController.searchRegions('Bulk Test Region');
        System.assertEquals(1, results.size(), 'Should find the test region');
    }

    @IsTest
    static void testSearchHubsReturnsMatches() {
        List<String> results = SchemeHierarchyBulkController.searchHubs('Mumbai');
        System.assert(results.contains('Mumbai'), 'Should include Mumbai in the filtered Hub list');
    }

    @IsTest
    static void testSearchHubsEmptyTermReturnsAll() {
        List<String> results = SchemeHierarchyBulkController.searchHubs('');
        System.assert(results.size() > 1, 'Empty search term should return the full Hub picklist');
    }

    @IsTest
    static void testCreateDistributorRowsBulkSuccess() {
        Account dist = [SELECT Id FROM Account WHERE Name = 'Bulk Test Distributor' LIMIT 1];
        Scheme__c scheme = [SELECT Id FROM Scheme__c WHERE Name = 'Bulk Hierarchy Test Scheme' LIMIT 1];

        String result = SchemeHierarchyBulkController.createDistributorRows(scheme.Id, new List<Id>{ dist.Id });
        System.assertEquals(null, result, 'Should return null on full success');

        List<Scheme_Hierarchy__c> rows = [
            SELECT Scheme_Holder_Type__c, Distributor__c FROM Scheme_Hierarchy__c WHERE Scheme__c = :scheme.Id
        ];
        System.assertEquals(1, rows.size(), 'One row should have been created');
        System.assertEquals('Distributor', rows[0].Scheme_Holder_Type__c);
        System.assertEquals(dist.Id, rows[0].Distributor__c);
    }

    @IsTest
    static void testCreateDistributorRowsNoIdsReturnsMessage() {
        Scheme__c scheme = [SELECT Id FROM Scheme__c WHERE Name = 'Bulk Hierarchy Test Scheme' LIMIT 1];
        String result = SchemeHierarchyBulkController.createDistributorRows(scheme.Id, new List<Id>());
        System.assertEquals('Select at least one distributor.', result);
    }

    @IsTest
    static void testCreateDistributorRowsDuplicateReported() {
        Account dist = [SELECT Id FROM Account WHERE Name = 'Bulk Test Distributor' LIMIT 1];
        Scheme__c scheme = [SELECT Id FROM Scheme__c WHERE Name = 'Bulk Hierarchy Test Scheme' LIMIT 1];

        String first = SchemeHierarchyBulkController.createDistributorRows(scheme.Id, new List<Id>{ dist.Id });
        System.assertEquals(null, first, 'First insert should succeed');

        String second = SchemeHierarchyBulkController.createDistributorRows(scheme.Id, new List<Id>{ dist.Id });
        System.assertNotEquals(null, second, 'Duplicate distributor for the same scheme should be reported');
        System.assert(second.contains('already listed'), 'Message should explain the duplicate');
    }

    @IsTest
    static void testCreateRegionRowsBulkSuccess() {
        Region__c region = [SELECT Id FROM Region__c WHERE Name = 'Bulk Test Region' LIMIT 1];
        Scheme__c scheme = [SELECT Id FROM Scheme__c WHERE Name = 'Bulk Hierarchy Test Scheme' LIMIT 1];

        String result = SchemeHierarchyBulkController.createRegionRows(scheme.Id, new List<Id>{ region.Id });
        System.assertEquals(null, result, 'Should return null on full success');

        List<Scheme_Hierarchy__c> rows = [
            SELECT Scheme_Holder_Type__c, Region__c FROM Scheme_Hierarchy__c WHERE Scheme__c = :scheme.Id
        ];
        System.assertEquals(1, rows.size());
        System.assertEquals('Region', rows[0].Scheme_Holder_Type__c);
    }

    @IsTest
    static void testCreateHubRowsBulkSuccess() {
        Scheme__c scheme = [SELECT Id FROM Scheme__c WHERE Name = 'Bulk Hierarchy Test Scheme' LIMIT 1];

        String result = SchemeHierarchyBulkController.createHubRows(scheme.Id, new List<String>{ 'Mumbai', 'Goa' });
        System.assertEquals(null, result, 'Should return null on full success');

        List<Scheme_Hierarchy__c> rows = [
            SELECT Scheme_Holder_Type__c, Hub__c FROM Scheme_Hierarchy__c WHERE Scheme__c = :scheme.Id
        ];
        System.assertEquals(2, rows.size(), 'Both hub rows should have been created');
    }

    @IsTest
    static void testCreateRetailerRowsBulkSuccess() {
        Account retailer = [SELECT Id FROM Account WHERE Name = 'Bulk Test Retailer' LIMIT 1];
        Scheme__c scheme = [SELECT Id FROM Scheme__c WHERE Name = 'Bulk Hierarchy Test Scheme' LIMIT 1];

        String result = SchemeHierarchyBulkController.createRetailerRows(scheme.Id, new List<Id>{ retailer.Id });
        System.assertEquals(null, result, 'Should return null on full success');

        List<Scheme_Hierarchy__c> rows = [
            SELECT Scheme_Holder_Type__c, Account__c FROM Scheme_Hierarchy__c WHERE Scheme__c = :scheme.Id
        ];
        System.assertEquals(1, rows.size());
        System.assertEquals('Retailer', rows[0].Scheme_Holder_Type__c);
    }

    @IsTest
    static void testCreateRegionRowsNoIdsReturnsMessage() {
        Scheme__c scheme = [SELECT Id FROM Scheme__c WHERE Name = 'Bulk Hierarchy Test Scheme' LIMIT 1];
        String result = SchemeHierarchyBulkController.createRegionRows(scheme.Id, new List<Id>());
        System.assertEquals('Select at least one region.', result);
    }

    @IsTest
    static void testCreateHubRowsNoValuesReturnsMessage() {
        Scheme__c scheme = [SELECT Id FROM Scheme__c WHERE Name = 'Bulk Hierarchy Test Scheme' LIMIT 1];
        String result = SchemeHierarchyBulkController.createHubRows(scheme.Id, new List<String>());
        System.assertEquals('Select at least one hub.', result);
    }

    @IsTest
    static void testCreateRetailerRowsNoIdsReturnsMessage() {
        Scheme__c scheme = [SELECT Id FROM Scheme__c WHERE Name = 'Bulk Hierarchy Test Scheme' LIMIT 1];
        String result = SchemeHierarchyBulkController.createRetailerRows(scheme.Id, new List<Id>());
        System.assertEquals('Select at least one retailer.', result);
    }
}