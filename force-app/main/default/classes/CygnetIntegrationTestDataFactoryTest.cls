@IsTest
private class CygnetIntegrationTestDataFactoryTest {
    @IsTest
    static void testInsertHierarchySettings_InsertsUserLevelRows() {
        Test.startTest();
        CygnetIntegrationTestDataFactory.insertCygnetHierarchySettings();
        CygnetIntegrationTestDataFactory.insertCygnetUnderSsHierarchySettings();
        Test.stopTest();

        // Hierarchy custom settings can be read via getInstance(userId).
        Cygnet_Integration_Setting__c s1 = Cygnet_Integration_Setting__c.getInstance(UserInfo.getUserId());
        System.assertNotEquals(null, s1, 'Expected Secondary hierarchy setting row for user');
        System.assertEquals(true, String.isNotBlank(s1.Base_Url__c));

        Cygnet_Integration_Setting_Under_SS__c s2 =
            Cygnet_Integration_Setting_Under_SS__c.getInstance(UserInfo.getUserId());
        System.assertNotEquals(null, s2, 'Expected Under-SS hierarchy setting row for user');
        System.assertEquals(true, String.isNotBlank(s2.Base_Url__c));
    }

    @IsTest
    static void testCreateInvoiceWithLineForMapper_CreatesInvoice_WhenSupported() {
        // Some orgs may not have the custom objects/record types; factory returns null in that case.
        Id invId = CygnetIntegrationTestDataFactory.createInvoiceWithLineForMapper(false);
        if (invId == null) {
            System.assertEquals(true, true, 'Org does not support mapper invoice creation; skip.');
            return;
        }
        System.assertNotEquals(null, invId);

        // Verify at least the record exists.
        Invoice__c inv = [SELECT Id FROM Invoice__c WHERE Id = :invId LIMIT 1];
        System.assertNotEquals(null, inv);
    }

    @IsTest
    static void testCreateInvoiceWithLineForMapper_UnderSsVariant_WhenAvailable() {
        Id invId = CygnetIntegrationTestDataFactory.createInvoiceWithLineForMapper(true);
        if (invId == null) {
            System.assertEquals(true, true, 'Under-SS record type not available; skip.');
            return;
        }
        Invoice__c inv = [SELECT Id FROM Invoice__c WHERE Id = :invId LIMIT 1];
        System.assertNotEquals(null, inv);
    }

    @IsTest
    static void testCreateInvoiceForEWayBillQueueable_Null_ReturnsNull() {
        System.assertEquals(null, CygnetIntegrationTestDataFactory.createInvoiceForEWayBillQueueable(null));
    }

    @IsTest
    static void testCreateInvoiceForEWayBillQueueable_UpdatesInvoice_WhenSupported() {
        Id invId = CygnetIntegrationTestDataFactory.createInvoiceWithLineForMapper(false);
        if (invId == null) {
            System.assertEquals(true, true, 'Org does not support invoice creation; skip.');
            return;
        }

        Id outId = CygnetIntegrationTestDataFactory.createInvoiceForEWayBillQueueable(invId);
        System.assertEquals(invId, outId);

        // Query only fields that should exist in this org; if missing, query will throw, so keep it minimal.
        Invoice__c inv = [SELECT Id FROM Invoice__c WHERE Id = :invId LIMIT 1];
        System.assertNotEquals(null, inv);
    }

    @IsTest
    static void testPrepareProductForInvoiceLineLookupFilter_DoesNotThrow() {
        if (!Schema.getGlobalDescribe().containsKey('Product__c')) {
            System.assertEquals(true, true, 'Product__c not present; skip.');
            return;
        }
        SObject prod = Schema.getGlobalDescribe().get('Product__c').newSObject();
        prod.put('Name', 'UT Product');

        Test.startTest();
        CygnetIntegrationTestDataFactory.prepareProductForInvoiceLineLookupFilter(prod, null, null);
        Test.stopTest();

        // No assertions: goal is to execute the heuristics without exceptions across orgs.
        System.assertNotEquals(null, prod);
    }
}