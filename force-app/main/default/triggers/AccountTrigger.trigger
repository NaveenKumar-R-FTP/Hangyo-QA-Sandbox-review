trigger AccountTrigger on Account (before insert , after insert, after update , after delete , after undelete) {
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        AccountTriggerHandler.handleSuperStockistSharing(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
    }
    
    if(Trigger.isBefore && Trigger.isInsert){
        GenerateRetailerCreationCode.retailerCreationCode(Trigger.new);
    }
    
    if(Trigger.isAfter && Trigger.isUpdate){
        Set<Id> setofAccountId = new Set<Id>();
        Set<Id> setofRetailer = new Set<Id>();
        Set<Id> accountOwnerChangedIds = new Set<Id>();
		
        for(Account acc : Trigger.new){
            
            Account oldAcc = Trigger.oldMap.get(acc.Id);
			// added by Fuzail – sync Asset owner when Account owner changes
            if (acc.OwnerId != oldAcc.OwnerId) {
               accountOwnerChangedIds.add(acc.Id);
            }
            
            if((acc.Beats_Name__c != Trigger.oldMap.get(acc.Id).Beats_Name__c) && acc.Record_type_Name__c == 'Retailer'){
                setofAccountId.add(acc.Id);
            }
            if((acc.Distributor__c != Trigger.oldMap.get(acc.Id).Distributor__c) && acc.Record_type_Name__c == 'Retailer'){
                setofRetailer.add(acc.Id);
            }
        }
        if (!accountOwnerChangedIds.isEmpty()) {
        AccountOwnerSyncHandler.syncRetailerAssetOwners(Trigger.new,Trigger.oldMap);
        }
        
        if(setofAccountId.size()>0){
            Retailer_BeatChange.retailerOwnerUpdate(setofAccountId);
        }
        if(setofRetailer.size()>0){
            Retailer_DistributorChange.visitTaskDistributorUpdate(setofRetailer);
        }
    }

	// added by Fuzail – update Beat retailer count only when relevant
   if (Trigger.isAfter) {

    List<Account> newRelevant = new List<Account>();
    List<Account> oldRelevant = new List<Account>();

    // INSERT & UNDELETE
    if (Trigger.isInsert || Trigger.isUndelete) {
        for (Account acc : Trigger.new) {
            if (acc.Record_type_Name__c == 'Retailer') {
                newRelevant.add(acc);
            }
        }
    }

    // UPDATE (Beat or Active flag change)
    if (Trigger.isUpdate) {
        for (Account acc : Trigger.new) {
            Account oldAcc = Trigger.oldMap.get(acc.Id);

            if (
                acc.Record_type_Name__c == 'Retailer' &&
                (
                    acc.Beats_Name__c != oldAcc.Beats_Name__c ||
                    acc.Is_Active__c != oldAcc.Is_Active__c
                )
            ) {
                newRelevant.add(acc);
                oldRelevant.add(oldAcc);
            }
        }
    }

    // DELETE
    if (Trigger.isDelete) {
        for (Account acc : Trigger.old) {
            if (acc.Record_type_Name__c == 'Retailer') {
                oldRelevant.add(acc);
            }
        }
    }

    if (!newRelevant.isEmpty() || !oldRelevant.isEmpty()) {
        BeatTriggerHandler.updateRetailerCount(
            newRelevant.isEmpty() ? null : newRelevant,
            oldRelevant.isEmpty() ? null : oldRelevant
        );
    }
}
}