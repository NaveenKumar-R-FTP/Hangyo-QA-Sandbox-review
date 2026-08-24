@IsTest
public class SchemeHierarchyTriggerHandlerTest {

    @TestSetup
    static void makeData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;

        RecordType distRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Distributor' LIMIT 1];
        Account dist = new Account(
            Name = 'Trigger Test Distributor',
            RecordTypeId = distRT.Id,
            Primary_State__c = 'Kerala',
            PAN_Number__c = 'TRIGDIST001',
            Hub__c = 'Mumbai'
        );
        insert dist;

        RecordType retailerRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1];
        Account retailer = new Account(
            Name = 'Trigger Test Retailer',
            RecordTypeId = retailerRT.Id,
            Primary_State__c = 'Kerala',
            PAN_Number__c = 'TRIGRET001'
        );
        insert retailer;

        Id valueRT = [SELECT Id FROM RecordType WHERE DeveloperName = 'Value_Scheme' AND SObjectType = 'Scheme__c' LIMIT 1].Id;
        Scheme__c scheme = new Scheme__c(
            Name = 'Trigger Hierarchy Test Scheme',
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
    static void testDuplicateHubRejected() {
        Scheme__c scheme = [SELECT Id FROM Scheme__c WHERE Name = 'Trigger Hierarchy Test Scheme' LIMIT 1];

        insert new Scheme_Hierarchy__c(
            Name = 'Hub: Goa',
            Scheme__c = scheme.Id,
            Scheme_Holder_Type__c = 'Hub',
            Hub__c = 'Goa',
            IsActive__c = true
        );

        Boolean exceptionThrown = false;
        try {
            insert new Scheme_Hierarchy__c(
                Name = 'Hub: Goa (dup)',
                Scheme__c = scheme.Id,
                Scheme_Holder_Type__c = 'Hub',
                Hub__c = 'Goa',
                IsActive__c = true
            );
        } catch (DmlException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('already listed'), 'Should surface the duplicate-Hub message');
        }
        System.assertEquals(true, exceptionThrown, 'Duplicate Hub row for the same scheme should be blocked');
    }

    @IsTest
    static void testDifferentHolderTypesSameSchemeAllowed() {
        Scheme__c scheme = [SELECT Id FROM Scheme__c WHERE Name = 'Trigger Hierarchy Test Scheme' LIMIT 1];
        Account dist = [SELECT Id FROM Account WHERE Name = 'Trigger Test Distributor' LIMIT 1];

        insert new Scheme_Hierarchy__c(
            Name = 'Hub: Goa',
            Scheme__c = scheme.Id,
            Scheme_Holder_Type__c = 'Hub',
            Hub__c = 'Goa',
            IsActive__c = true
        );

        // Different holder type (Distributor), same scheme — should NOT be treated as a
        // duplicate even though both rows belong to the same scheme.
        insert new Scheme_Hierarchy__c(
            Name = 'Distributor: Test',
            Scheme__c = scheme.Id,
            Scheme_Holder_Type__c = 'Distributor',
            Distributor__c = dist.Id,
            IsActive__c = true
        );

        List<Scheme_Hierarchy__c> rows = [SELECT Id FROM Scheme_Hierarchy__c WHERE Scheme__c = :scheme.Id];
        System.assertEquals(2, rows.size(), 'Both rows should have saved successfully');
    }

    @IsTest
    static void testLegacyAccountRegionRowsUnaffected() {
        // Rows without Scheme_Holder_Type__c set (the original Account__c/Region__c
        // pattern, predating this field) must not be touched by the new duplicate guard —
        // inserting the same Account__c/Region__c combo twice should still succeed exactly
        // as it did before Step 5.
        Scheme__c scheme = [SELECT Id FROM Scheme__c WHERE Name = 'Trigger Hierarchy Test Scheme' LIMIT 1];
        Account retailer = [SELECT Id FROM Account WHERE Name = 'Trigger Test Retailer' LIMIT 1];

        insert new Scheme_Hierarchy__c(
            Scheme__c = scheme.Id,
            Account__c = retailer.Id,
            IsActive__c = true
        );

        insert new Scheme_Hierarchy__c(
            Scheme__c = scheme.Id,
            Account__c = retailer.Id,
            IsActive__c = true
        );

        List<Scheme_Hierarchy__c> rows = [SELECT Id FROM Scheme_Hierarchy__c WHERE Scheme__c = :scheme.Id];
        System.assertEquals(2, rows.size(), 'Legacy-style rows are not deduplicated by the new trigger');
    }
}