@isTest
public class ClaimHeaderTriggerTest {
    
    @isTest
    static void testHelperHit_WithError() {
        
        Trigger_Setting__c setting = new Trigger_Setting__c(
            Name = 'ClaimHeaderTrigger',
            IsActive__c = true
        );
        insert setting;
        
        Claim_Header__c ch = new Claim_Header__c(
            Status__c = 'Draft'
        );
        insert ch;
        
        Test.startTest();
        
        ch.Status__c = 'Reject';
        
        Boolean isErrorThrown = false;
        
        try {
            update ch;
        } catch (DmlException e) {
            isErrorThrown = true;
            System.assert(
                e.getMessage().contains('Comments are mandatory'),
                'Expected validation error'
            );
        }
        
        Test.stopTest();
        System.assert(isErrorThrown, 'Error should be thrown');
    }


@isTest
static void testTriggerHandlerMethods() {

    ClaimHeaderTriggerHandler handler = new ClaimHeaderTriggerHandler();

    List<SObject> newList = new List<SObject>();
    List<SObject> oldList = new List<SObject>();

    Map<Id, SObject> newMap = new Map<Id, SObject>();
    Map<Id, SObject> oldMap = new Map<Id, SObject>();

    Test.startTest();

    handler.BeforeInsert(newList);
    handler.AfterInsert(newList, newMap);
    handler.AfterUpdate(newList, newMap, oldList, oldMap);
    handler.BeforeDelete(oldList, oldMap);
    handler.AfterDelete(oldList, oldMap);
    handler.AfterUnDelete(newList, newMap);

    Boolean result = handler.isDisabled();

    Test.stopTest();

    System.assertEquals(false, result);
}
    
    
}