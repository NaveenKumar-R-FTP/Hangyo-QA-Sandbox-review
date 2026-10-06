/**
 * Server-side storage for the DMS order-screen cart (used by LWC dmsCartStore).
 * One DMS_Cart__c record per user, keyed by the user's Id in Cart_Key__c.
 * Every method reads or writes only the calling user's own record.
 */
public with sharing class DmsCartController {

    @TestVisible
    private static final Integer MAX_STATE_LENGTH = 131072;

    @AuraEnabled
    public static String getCartState() {
        List<DMS_Cart__c> carts = [
            SELECT Cart_State__c
            FROM DMS_Cart__c
            WHERE Cart_Key__c = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return carts.isEmpty() ? null : carts[0].Cart_State__c;
    }

    @AuraEnabled
    public static void saveCartState(String stateJson) {
        String state = String.isBlank(stateJson) ? '{}' : stateJson;
        if (state.length() > MAX_STATE_LENGTH) {
            throw new AuraHandledException('The cart is too large to save.');
        }
        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(state);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid cart data.');
        }
        if (!(parsed instanceof Map<String, Object>)) {
            throw new AuraHandledException('Invalid cart data.');
        }
        DMS_Cart__c cart = new DMS_Cart__c(
            Cart_Key__c = UserInfo.getUserId(),
            Cart_State__c = state
        );
        Database.upsert(cart, DMS_Cart__c.Cart_Key__c, true, AccessLevel.SYSTEM_MODE);
    }

    // Saves only the values that changed, merged into this user's saved cart, so one
    // browser or device can never overwrite another's newer cart with an older copy.
    // changesJson = {"set": {key: value, ...}, "remove": [key, ...]}
    @AuraEnabled
    public static void saveCartChanges(String changesJson) {
        Map<String, Object> changes;
        try {
            changes = (Map<String, Object>) JSON.deserializeUntyped(String.isBlank(changesJson) ? '{}' : changesJson);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid cart data.');
        }
        List<DMS_Cart__c> carts = [
            SELECT Cart_State__c
            FROM DMS_Cart__c
            WHERE Cart_Key__c = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
            FOR UPDATE
        ];
        Map<String, Object> state = new Map<String, Object>();
        if (!carts.isEmpty() && String.isNotBlank(carts[0].Cart_State__c)) {
            try {
                state = (Map<String, Object>) JSON.deserializeUntyped(carts[0].Cart_State__c);
            } catch (Exception e) {
                state = new Map<String, Object>();
            }
        }
        Object toSet = changes.get('set');
        if (toSet instanceof Map<String, Object>) {
            state.putAll((Map<String, Object>) toSet);
        }
        Object toRemove = changes.get('remove');
        if (toRemove instanceof List<Object>) {
            for (Object key : (List<Object>) toRemove) {
                state.remove(String.valueOf(key));
            }
        }
        saveCartState(JSON.serialize(state));
    }
}