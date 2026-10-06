/**
 * @description Unit tests for TallyInvoiceQueryService.
 */
@isTest
private class TallyInvoiceQueryServiceTest {
    private static final Date TEST_DATE = Date.today();

    @testSetup
    static void setupData() {
        Id ownerId = TallyInvoiceTestDataFactory.resolveAllowedOwnerId();
        TallyInvoiceTestDataFactory.createInvoiceWithLineItem(ownerId, TEST_DATE);
    }

    @isTest
    static void getInvoices_returnsEmptyWhenAllowedUsersEmpty() {
        Test.startTest();
        List<Invoice__c> results = TallyInvoiceQueryService.getInvoices(
            new Set<Id>(),
            null,
            null
        );
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Empty allowed-user set must return no rows');
    }

    @isTest
    static void getInvoices_returnsEmptyWhenAllowedUsersNull() {
        Test.startTest();
        List<Invoice__c> results = TallyInvoiceQueryService.getInvoices(null, null, null);
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Null allowed-user set must return no rows');
    }

    @isTest
    static void getInvoices_returnsInvoicesForAllowedOwner() {
        Id ownerId = TallyInvoiceTestDataFactory.resolveAllowedOwnerId();
        Set<Id> allowedUsers = new Set<Id>{ ownerId };

        Test.startTest();
        List<Invoice__c> results = TallyInvoiceQueryService.getInvoices(allowedUsers, null, null);
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one invoice');
        System.assertEquals(1, results[0].Invoice_Line_Items__r.size(), 'Expected one line item');
        System.assertNotEquals(null, results[0].Invoice_Line_Items__r[0].Product__r);
    }

    @isTest
    static void getInvoices_filtersByDateRange() {
        Id ownerId = TallyInvoiceTestDataFactory.resolveAllowedOwnerId();
        Set<Id> allowedUsers = new Set<Id>{ ownerId };

        Test.startTest();
        List<Invoice__c> inRange = TallyInvoiceQueryService.getInvoices(
            allowedUsers,
            TEST_DATE,
            TEST_DATE
        );
        List<Invoice__c> outOfRange = TallyInvoiceQueryService.getInvoices(
            allowedUsers,
            TEST_DATE.addDays(-30),
            TEST_DATE.addDays(-1)
        );
        Test.stopTest();

        System.assertEquals(1, inRange.size(), 'Invoice date should match inclusive range');
        System.assertEquals(0, outOfRange.size(), 'Out-of-range dates should return no rows');
    }

    @isTest
    static void getInvoices_filtersByFromDateOnly() {
        Id ownerId = TallyInvoiceTestDataFactory.resolveAllowedOwnerId();
        Set<Id> allowedUsers = new Set<Id>{ ownerId };

        Test.startTest();
        List<Invoice__c> results = TallyInvoiceQueryService.getInvoices(
            allowedUsers,
            TEST_DATE.addDays(-1),
            null
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'From-date-only filter should include today invoice');
    }

    @isTest
    static void getInvoices_filtersByToDateOnly() {
        Id ownerId = TallyInvoiceTestDataFactory.resolveAllowedOwnerId();
        Set<Id> allowedUsers = new Set<Id>{ ownerId };

        Test.startTest();
        List<Invoice__c> results = TallyInvoiceQueryService.getInvoices(
            allowedUsers,
            null,
            TEST_DATE.addDays(1)
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'To-date-only filter should include today invoice');
    }
}