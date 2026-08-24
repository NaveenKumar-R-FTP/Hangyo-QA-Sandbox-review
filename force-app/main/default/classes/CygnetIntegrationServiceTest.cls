@isTest
public class CygnetIntegrationServiceTest {

    @testSetup
    static void setupTestData() {
        // Insert required integration settings
        CygnetIntegrationTestDataFactory.insertCygnetHierarchySettings();
        CygnetIntegrationTestDataFactory.insertCygnetUnderSsHierarchySettings();
    }

    @isTest
    static void testInvoiceCreationAndProcessing() {
        // Create Invoice with line item
        Id invoiceId = CygnetIntegrationTestDataFactory.createInvoiceWithLineForMapper(false);
        System.assertNotEquals(null, invoiceId, 'Invoice should be created');

        Test.startTest();

        // 👉 Replace below with your actual method call
        // Example:
        // CygnetIntegrationService.processInvoice(invoiceId);

        Test.stopTest();

        // Validate results (update based on your logic)
        Invoice__c inv = [SELECT Id, Status__c FROM Invoice__c WHERE Id = :invoiceId];
        System.assertNotEquals(null, inv, 'Invoice should exist');
    }

    @isTest
    static void testEWayBillQueueableFlow() {
        Id invoiceId = CygnetIntegrationTestDataFactory.createInvoiceWithLineForMapper(false);
        invoiceId = CygnetIntegrationTestDataFactory.createInvoiceForEWayBillQueueable(invoiceId);

        Test.startTest();

        // 👉 Replace with your Queueable / Future call
        // Example:
        // System.enqueueJob(new EWayBillQueueable(invoiceId));

        Test.stopTest();

        // Add assertions based on expected updates
        Invoice__c inv = [SELECT Id FROM Invoice__c WHERE Id = :invoiceId];
        System.assertNotEquals(null, inv);
    }

    @isTest
    static void testUnderSSScenario() {
        Id invoiceId = CygnetIntegrationTestDataFactory.createInvoiceWithLineForMapper(true);
        System.assertNotEquals(null, invoiceId, 'Under SS invoice should be created');

        Test.startTest();

        // 👉 Call your method handling Under SS logic

        Test.stopTest();
    }
}