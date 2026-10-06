@IsTest
private class DmsCartControllerTest {

    @IsTest
    static void saveThenLoadReturnsLatestState() {
        Test.startTest();
        System.assertEquals(null, DmsCartController.getCartState(), 'No cart before the first save');
        DmsCartController.saveCartState('{"primaryCart":"A"}');
        DmsCartController.saveCartState('{"primaryCart":"B"}');
        Test.stopTest();
        System.assertEquals('{"primaryCart":"B"}', DmsCartController.getCartState(), 'Latest state is returned');
        System.assertEquals(1, [SELECT COUNT() FROM DMS_Cart__c WHERE Cart_Key__c = :UserInfo.getUserId() WITH SYSTEM_MODE], 'One record per user');
    }

    @IsTest
    static void blankStateIsSavedAsEmptyObject() {
        DmsCartController.saveCartState(null);
        System.assertEquals('{}', DmsCartController.getCartState(), 'Blank state saved as {}');
    }

    @IsTest
    static void invalidStateIsRejected() {
        List<String> badStates = new List<String>{
            'not json',
            '[1,2]',
            '{"a":"' + 'x'.repeat(DmsCartController.MAX_STATE_LENGTH) + '"}'
        };
        for (String s : badStates) {
            Boolean thrown = false;
            try {
                DmsCartController.saveCartState(s);
            } catch (AuraHandledException e) {
                thrown = true;
            }
            System.assert(thrown, 'Expected rejection for: ' + s.left(20));
        }
        System.assertEquals(null, DmsCartController.getCartState(), 'Nothing saved for invalid input');
    }

    @IsTest
    static void changesAreMergedIntoSavedCart() {
        DmsCartController.saveCartState('{"a":"1","b":"2"}');
        Test.startTest();
        DmsCartController.saveCartChanges('{"set":{"b":"3","c":"4"},"remove":["a"]}');
        Test.stopTest();
        Map<String, Object> state = (Map<String, Object>) JSON.deserializeUntyped(DmsCartController.getCartState());
        System.assert(!state.containsKey('a'), 'Removed value is gone');
        System.assertEquals('3', state.get('b'), 'Changed value is updated');
        System.assertEquals('4', state.get('c'), 'New value is added');
    }

    @IsTest
    static void changesCreateCartWhenNoneSaved() {
        DmsCartController.saveCartChanges('{"set":{"x":"1"}}');
        Map<String, Object> state = (Map<String, Object>) JSON.deserializeUntyped(DmsCartController.getCartState());
        System.assertEquals('1', state.get('x'), 'Cart created from changes');
    }

    @IsTest
    static void invalidChangesAreRejected() {
        for (String s : new List<String>{ 'not json', '[1,2]' }) {
            Boolean thrown = false;
            try {
                DmsCartController.saveCartChanges(s);
            } catch (AuraHandledException e) {
                thrown = true;
            }
            System.assert(thrown, 'Expected rejection for: ' + s);
        }
        System.assertEquals(null, DmsCartController.getCartState(), 'Nothing saved for invalid input');
    }
}