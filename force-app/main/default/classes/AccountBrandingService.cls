/**
* ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
* Class Name      : AccountBrandingService
* Description     : Single owner of Account.Is_Branded__c.
*
*                   An account is branded when it currently holds EITHER an active
*                   deep freezer (Asset_Mapping__c) OR active branding material
*                   (Branding_Asset__c). Remove both and the flag goes back to false,
*                   so this recalculates in both directions rather than only setting
*                   the flag on.
*
*                   Called from AssetMappingTrigger, BrandingAssetTrigger,
*                   CaseTriggerHandler and AccountBrandedBackfillBatch so the rule
*                   lives in exactly one place.
* ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
*/
public without sharing class AccountBrandingService {

    /**
     * Retained for compatibility only. It is deliberately NOT used to short-circuit
     * recalculate: AccountTrigger never calls back into this service, so the guard
     * protected nothing while being able to silently suppress a legitimate second
     * recalculation later in the same transaction - which left accounts holding
     * active branding assets flagged as not branded.
     */
    public static Boolean isRunning = false;

    public static void recalculate(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) return;

        // A user without access to Branding_Asset__c can't run the branding half of
        // this, and guessing from freezers alone would wrongly clear accounts that
        // are branded by signage. Skip entirely rather than write a wrong value -
        // and never let a permissions gap block the case or mapping save itself.
        if (!Schema.sObjectType.Branding_Asset__c.isAccessible()) {
            System.debug(LoggingLevel.ERROR,
                'AccountBrandingService skipped: running user cannot access Branding_Asset__c. ' +
                'Assign the Branding_Asset_Access permission set.');
            return;
        }

        isRunning = true;
        try {
            Set<Id> brandedIds = new Set<Id>();

            // Deep freezers - a mapping can hang off any of the three account roles.
            for (Asset_Mapping__c am : [
                SELECT Retailer__c, Distributor__c, Super_Stockist__c
                FROM Asset_Mapping__c
                WHERE Active__c = true
                AND (Retailer__c IN :accountIds
                     OR Distributor__c IN :accountIds
                     OR Super_Stockist__c IN :accountIds)
            ]) {
                if (accountIds.contains(am.Retailer__c))       brandedIds.add(am.Retailer__c);
                if (accountIds.contains(am.Distributor__c))    brandedIds.add(am.Distributor__c);
                if (accountIds.contains(am.Super_Stockist__c)) brandedIds.add(am.Super_Stockist__c);
            }

            // Branding / marketing material.
            for (Branding_Asset__c ba : [
                SELECT Account__c
                FROM Branding_Asset__c
                WHERE Active__c = true AND Account__c IN :accountIds
            ]) {
                brandedIds.add(ba.Account__c);
            }

            // Only write where the flag actually differs.
            List<Account> toUpdate = new List<Account>();
            for (Account acc : [
                SELECT Id, Is_Branded__c FROM Account WHERE Id IN :accountIds
            ]) {
                Boolean shouldBeBranded = brandedIds.contains(acc.Id);
                if (acc.Is_Branded__c != shouldBeBranded) {
                    toUpdate.add(new Account(Id = acc.Id, Is_Branded__c = shouldBeBranded));
                }
            }

            if (!toUpdate.isEmpty()) {
                // allOrNone = false so one blocked account can't stop the rest -
                // but log every failure, otherwise a branded flag silently stays wrong.
                List<Database.SaveResult> results =
                    Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) continue;
                    System.debug(LoggingLevel.ERROR,
                        'Is_Branded__c update failed for ' + toUpdate[i].Id + ': ' +
                        results[i].getErrors());
                }
            }
        } finally {
            isRunning = false;
        }
    }

    /**
     * Collects every account a set of mappings touches, old value included, so a
     * freezer moved away from an outlet clears that outlet's flag too.
     */
    public static Set<Id> accountIdsFromMappings(
        List<Asset_Mapping__c> newMappings,
        Map<Id, Asset_Mapping__c> oldMap
    ) {
        Set<Id> accountIds = new Set<Id>();
        if (newMappings != null) {
            for (Asset_Mapping__c am : newMappings) {
                addMappingAccounts(accountIds, am);
                if (oldMap != null && oldMap.containsKey(am.Id)) {
                    addMappingAccounts(accountIds, oldMap.get(am.Id));
                }
            }
        }
        accountIds.remove(null);
        return accountIds;
    }

    private static void addMappingAccounts(Set<Id> accountIds, Asset_Mapping__c am) {
        if (am == null) return;
        accountIds.add(am.Retailer__c);
        accountIds.add(am.Distributor__c);
        accountIds.add(am.Super_Stockist__c);
    }
}