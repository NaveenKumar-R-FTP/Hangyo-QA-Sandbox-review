trigger Asset_Trigger on Asset__c (before update, after insert, after update, after delete, after undelete) {
    
    // added by fuzail – sync Salesman__c and OwnerId when Retailer_Account__c changes
    if (Trigger.isBefore && Trigger.isUpdate) {
        AssetRetailerOwnerController.syncSalesmanWithRetailerOwner(
            Trigger.new,
            Trigger.oldMap
        );
    }
    if(Trigger.isAfter) {
        if(Trigger.isInsert || Trigger.isUndelete) {
            AssetTriggerHandler.updateAccountAssetCount(Trigger.new, null);
        }
        else if(Trigger.isUpdate) {
            AssetTriggerHandler.updateAccountAssetCount(Trigger.new, Trigger.old);
        }
        else if(Trigger.isDelete) {
            AssetTriggerHandler.updateAccountAssetCount(null, Trigger.old);
        }
    }
}