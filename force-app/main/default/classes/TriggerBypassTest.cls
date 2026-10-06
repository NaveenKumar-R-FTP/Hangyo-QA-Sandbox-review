@isTest
private class TriggerBypassTest {

    @isTest
    static void testIsBypassed_ReturnsFalseWhenNotBypassed() {
        System.assertEquals(false, TriggerBypass.isBypassed('Account'),
            'Should return false for a name that was never added to bypassed');
    }

    @isTest
    static void testIsBypassed_ReturnsTrueAfterAddingToBypassed() {
        TriggerBypass.bypassed.add('Account');

        System.assertEquals(true, TriggerBypass.isBypassed('Account'),
            'Should return true once the name has been added to bypassed');
        System.assertEquals(false, TriggerBypass.isBypassed('Contact'),
            'Should return false for a name that was not added');
    }

    @isTest
    static void testBypassed_SupportsMultipleEntriesAndRemoval() {
        TriggerBypass.bypassed.add('Visit__c');
        TriggerBypass.bypassed.add('Visit_Task__c');

        System.assertEquals(true, TriggerBypass.isBypassed('Visit__c'));
        System.assertEquals(true, TriggerBypass.isBypassed('Visit_Task__c'));
        System.assertEquals(2, TriggerBypass.bypassed.size());

        TriggerBypass.bypassed.remove('Visit__c');

        System.assertEquals(false, TriggerBypass.isBypassed('Visit__c'),
            'Should return false after the name is removed from bypassed');
        System.assertEquals(true, TriggerBypass.isBypassed('Visit_Task__c'),
            'Remaining entries should be unaffected by removal of another entry');
    }

    @isTest
    static void testIsBypassed_IsCaseSensitive() {
        TriggerBypass.bypassed.add('Inventory_Adjustment__c');

        System.assertEquals(true, TriggerBypass.isBypassed('Inventory_Adjustment__c'));
        System.assertEquals(false, TriggerBypass.isBypassed('inventory_adjustment__c'),
            'Set<String> containment is case-sensitive by default in Apex');
    }
}