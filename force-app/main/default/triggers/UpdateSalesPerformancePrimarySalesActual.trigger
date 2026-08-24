trigger UpdateSalesPerformancePrimarySalesActual on Order__c (after insert, after update, after delete, after undelete, before insert) {
    
    if(TriggerExecutionController__c.getInstance('OrderTrigger') !=NULL && TriggerExecutionController__c.getInstance('OrderTrigger').Is_Active__c){
        
        Id primaryRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Order__c' AND DeveloperName = 'Primary_Order' LIMIT 1].Id;
        
        Id secondaryRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Order__c' AND DeveloperName = 'Secondary_Order' LIMIT 1].Id;
        
        // Id underSSRecordTypeId = Schema.SObjectType.Order__c.getRecordTypeInfosByDeveloperName().get('Under_SS_Order').getRecordTypeId();
        // Id underSSSecondaryOrderRecordTypeId = Schema.SObjectType.Order__c.getRecordTypeInfosByDeveloperName().get('Under_SS_Secondary_Order').getRecordTypeId();
        // 
        System.debug('UpdateSalesPerformancePrimarySalesActual Triggering');
        
        if (Trigger.isBefore && Trigger.isInsert) {
            Set<Id> accountIds = new Set<Id>();
            Set<Id> ownerIds = new Set<Id>();
            Map<String, List<Order__c>> keyToOrdersMap = new Map<String, List<Order__c>>();
            
            Date todayDate = Date.today();
            Integer monthVal = todayDate.month();
            Integer yearVal = todayDate.year();
            
            for (Order__c ord : Trigger.new) {
                if ((ord.RecordTypeId == primaryRecordTypeId) && ord.AccountId__c != null) {
                    accountIds.add(ord.AccountId__c);
                    
                } else if ((ord.RecordTypeId == secondaryRecordTypeId) && ord.Account__c != null && ord.Type__c == 'DMS') {
                    accountIds.add(ord.Account__c);
                }
            }
            
            Map<Id, Id> accountOwnerMap = new Map<Id, Id>();
            if (!accountIds.isEmpty()) {
                for (Account acc : [
                    SELECT Id, OwnerId FROM Account WHERE Id IN :accountIds
                ]) {
                    accountOwnerMap.put(acc.Id, acc.OwnerId);
                }
            }
            
            for (Order__c ord : Trigger.new) {
                Id ownerId;
                
                if ((ord.RecordTypeId == primaryRecordTypeId) && ord.AccountId__c != null) {
                    ownerId = accountOwnerMap.get(ord.AccountId__c);
                    
                } else if ((ord.RecordTypeId == secondaryRecordTypeId) && ord.Account__c != null && ord.Type__c == 'DMS') {
                    ownerId = accountOwnerMap.get(ord.Account__c);
                    
                } else if ((ord.RecordTypeId == secondaryRecordTypeId) && ord.Type__c == 'Field Order' && ord.Ordered_By__c != null) {
                    ownerId = ord.Ordered_By__c;
                }
                
                if (ownerId != null) {
                    String key = ownerId + '-' + monthVal + '-' + yearVal;
                    
                    if (!keyToOrdersMap.containsKey(key)) {
                        keyToOrdersMap.put(key, new List<Order__c>());
                    }
                    keyToOrdersMap.get(key).add(ord);
                    
                    ownerIds.add(ownerId);
                }
            }
            
            System.debug('Key to Orders Map = ' + keyToOrdersMap);
            System.debug('Owner IDs = ' + ownerIds);
            
            Map<String, Boolean> existingPerformanceMap = new Map<String, Boolean>();
            if (!ownerIds.isEmpty()) {
                List<Sales_Target__c> perfList = [
                    SELECT Id, Assigned_To__c, Number_of_Month__c, Year__c
                    FROM Sales_Target__c
                    WHERE Assigned_To__c IN :ownerIds
                    AND Number_of_Month__c = :monthVal
                    AND Year__c = :String.valueOf(yearVal)
                ];
                
                for (Sales_Target__c perf : perfList) {
                    String key = perf.Assigned_To__c + '-' + perf.Number_of_Month__c + '-' + perf.Year__c;
                    existingPerformanceMap.put(key, true);
                }
            }
            
            System.debug('Existing Performance Map = ' + existingPerformanceMap);
            
            for (String key : keyToOrdersMap.keySet()) {
                if (!existingPerformanceMap.containsKey(key)) {
                    for (Order__c ord : keyToOrdersMap.get(key)) {
                        ord.addError('Error saving order. The account owner does not have a Sales Performance record. If one exists, please contact your admin.');
                    }
                }
            }
        }
        
        
        
        
        if (Trigger.isAfter && Trigger.isInsert) { 
            //List<Order__c> primaryOrders = new List<Order__c>();
            List<Order__c> secondaryOrders = new List<Order__c>();
            
            for (Order__c ord : Trigger.new) {
                /*if (ord.RecordTypeId == primaryRecordTypeId || ord.RecordTypeId == underSSRecordTypeId) {
primaryOrders.add(ord);
} else */if (ord.RecordTypeId == secondaryRecordTypeId ) {//|| ord.RecordTypeId == underSSSecondaryOrderRecordTypeId
    secondaryOrders.add(ord);
}
            }
            
            /*  if (!primaryOrders.isEmpty()) {
UpdateSalesPerformancePSAHandler.updateSalesPerformance(primaryOrders);
}*/
            
            if (!secondaryOrders.isEmpty()) {
                UpdateSalesPerformanceProducCallsActual.updateSalesPerformance(secondaryOrders);
            }
        }
        
        if (Trigger.isAfter && Trigger.isUpdate) { 
            List<Order__c> UpdateprimaryOrders = new List<Order__c>();
            
            for (Order__c ord : Trigger.new) {
                if (ord.RecordTypeId == primaryRecordTypeId) {// || ord.RecordTypeId == underSSRecordTypeId
                    UpdateprimaryOrders.add(ord);
                } /*else if (ord.RecordTypeId == secondaryRecordTypeId || ord.RecordTypeId == underSSSecondaryOrderRecordTypeId) {
secondaryOrders.add(ord);
}*/
            }
            
            if (!UpdateprimaryOrders.isEmpty()) {
                UpdateSalesPerformancePSAHandler.updateSalesPerformance(UpdateprimaryOrders);
            }
            
            /*if (!secondaryOrders.isEmpty()) {
UpdateSalesPerformanceProducCallsActual.updateSalesPerformance(secondaryOrders);
}*/
        }
        
        
        if (Trigger.isAfter && Trigger.isDelete) {
            List<Order__c> deletedPrimaryOrders = new List<Order__c>();
            List<Order__c> deletedSecondaryOrders = new List<Order__c>();
            
            for (Order__c ord : Trigger.old) {
                if (ord.RecordTypeId == primaryRecordTypeId ) {//|| ord.RecordTypeId == underSSRecordTypeId
                    deletedPrimaryOrders.add(ord);
                } else if (ord.RecordTypeId == secondaryRecordTypeId ) {//|| ord.RecordTypeId == underSSSecondaryOrderRecordTypeId
                    deletedSecondaryOrders.add(ord);
                }
            }
            
            if (!deletedPrimaryOrders.isEmpty()) {
                UpdateSalesPerformancePSAHandler.updateSalesPerformance(deletedPrimaryOrders);
            }
            
            if (!deletedSecondaryOrders.isEmpty()) {
                UpdateSalesPerformanceProducCallsActual.updateSalesPerformance(deletedSecondaryOrders);
            }
        }
        
        if (Trigger.isAfter && Trigger.isUndelete) {
            List<Order__c> undeletedPrimaryOrders = new List<Order__c>();
            List<Order__c> undeletedSecondaryOrders = new List<Order__c>();
            
            for (Order__c ord : Trigger.new) {
                if (ord.RecordTypeId == primaryRecordTypeId ) {//|| ord.RecordTypeId == underSSRecordTypeId
                    undeletedPrimaryOrders.add(ord);
                } else if (ord.RecordTypeId == secondaryRecordTypeId ) {//|| ord.RecordTypeId == underSSSecondaryOrderRecordTypeId
                    undeletedSecondaryOrders.add(ord);
                }
            }
            
            if (!undeletedPrimaryOrders.isEmpty()) {
                UpdateSalesPerformancePSAHandler.updateSalesPerformance(undeletedPrimaryOrders);
            }
            
            if (!undeletedSecondaryOrders.isEmpty()) {
                UpdateSalesPerformanceProducCallsActual.updateSalesPerformance(undeletedSecondaryOrders);
            }
        }
    }
}