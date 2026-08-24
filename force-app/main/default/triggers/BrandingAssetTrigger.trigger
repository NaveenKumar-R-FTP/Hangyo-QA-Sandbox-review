trigger BrandingAssetTrigger on Branding_Asset__c (after insert, after update, after delete, after undelete) {
    BrandingAssetTriggerHandler.recalculateBranding(
        Trigger.isDelete ? Trigger.old : Trigger.new,
        Trigger.isUpdate ? Trigger.old : null
    );
}