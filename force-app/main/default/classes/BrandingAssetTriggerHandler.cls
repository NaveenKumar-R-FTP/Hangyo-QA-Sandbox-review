/**
* ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
* Class Name      : BrandingAssetTriggerHandler
* Description     : Keeps Account.Is_Branded__c in step with branding material.
*                   All the branded logic lives in AccountBrandingService — this
*                   only works out which accounts need recalculating.
* ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
*/
public without sharing class BrandingAssetTriggerHandler {

    public static void recalculateBranding(
        List<Branding_Asset__c> records,
        List<Branding_Asset__c> oldRecords
    ) {
        Set<Id> accountIds = new Set<Id>();
        if (records != null) {
            for (Branding_Asset__c ba : records) accountIds.add(ba.Account__c);
        }
        // On reparent the previous account may now have nothing left.
        if (oldRecords != null) {
            for (Branding_Asset__c ba : oldRecords) accountIds.add(ba.Account__c);
        }
        accountIds.remove(null);

        AccountBrandingService.recalculate(accountIds);
    }
}