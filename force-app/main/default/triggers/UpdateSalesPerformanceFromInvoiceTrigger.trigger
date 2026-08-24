trigger UpdateSalesPerformanceFromInvoiceTrigger on Invoice__c (after update, after delete, after undelete,before insert) {
    
    if(TriggerExecutionController__c.getInstance('InvoiceTrigger') !=NULL && TriggerExecutionController__c.getInstance('InvoiceTrigger').Is_Active__c){
        
        List<Invoice__c> updatedInvoices = new List<Invoice__c>();
        Id secondaryRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Invoice__c' AND DeveloperName = 'Secondary_Invoice' LIMIT 1].Id;
       // Id secondarySSRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Invoice__c' AND DeveloperName = 'Secondary_Invoice_Under_SS' LIMIT 1].Id;
        
        
        if (Trigger.isBefore && Trigger.isInsert) {
            Set<Id> accountIds = new Set<Id>();
            
            for (Invoice__c inv : Trigger.new) {
                if (inv.Retailer_Account__c != null) {
                    accountIds.add(inv.Retailer_Account__c);
                }
            }
            
            if (!accountIds.isEmpty()) {
                Map<Id, Id> accountOwnerMap = new Map<Id, Id>();
                for (Account acc : [
                    SELECT Id, OwnerId FROM Account WHERE Id IN :accountIds
                ]) {
                    accountOwnerMap.put(acc.Id, acc.OwnerId);
                }
                
                Map<String, Invoice__c> keyToInvoiceMap = new Map<String, Invoice__c>();
                Set<Integer> monthSet = new Set<Integer>();
                Set<String> yearSet = new Set<String>();
                Set<Id> ownerIds = new Set<Id>();
                
                Date todayDate = Date.today();
                Integer monthVal = todayDate.month();
                Integer yearVal = todayDate.year();
                
                for (Invoice__c inv : Trigger.new) {
                    if (inv.Retailer_Account__c != null) {
                        Id ownerId = accountOwnerMap.get(inv.Retailer_Account__c);
                        if (ownerId != null) {
                            String key = ownerId + '-' + monthVal + '-' + yearVal;
                            keyToInvoiceMap.put(key, inv);
                            
                            monthSet.add(monthVal);
                            yearSet.add(String.valueOf(yearVal));
                            ownerIds.add(ownerId);
                        }
                    }
                }
                Map<String, Boolean> existingPerformanceMap = new Map<String, Boolean>();
                if (!ownerIds.isEmpty()) {
                    List<Sales_Target__c> perfList = [SELECT Id, Assigned_To__c, Number_of_Month__c, Year__c FROM Sales_Target__c WHERE Assigned_To__c IN :ownerIds 
                                                      AND Number_of_Month__c IN :monthSet 
                                                      AND Year__c IN :yearSet];
                    
                    for (Sales_Target__c perf : perfList) {
                        String key = perf.Assigned_To__c + '-' + perf.Number_of_Month__c + '-' + perf.Year__c;
                        existingPerformanceMap.put(key, true);
                    }
                }
                
                // Validate if Sales Performance exists
                for (String key : keyToInvoiceMap.keySet()) {
                    if (!existingPerformanceMap.containsKey(key)) {
                        Invoice__c inv = keyToInvoiceMap.get(key);
                        inv.addError(
                            'Error saving invoice. The account owner does not have a sales performance record. Please contact admin to create it.'
                        );
                    }
                }
            }
        }
        
        
        if (Trigger.isAfter && Trigger.isUpdate) {
            for (Invoice__c inv : Trigger.new) {
                Invoice__c oldInvoice = Trigger.oldMap.get(inv.Id);
                if ((inv.Status__c == 'Confirmed' || inv.Status__c == 'Delivered') && inv.Status__c != oldInvoice.Status__c && 
                    (inv.RecordTypeId == secondaryRecordTypeId )) {//|| inv.RecordTypeId == secondarySSRecordTypeId
                        
                        updatedInvoices.add(inv);
                    }
            }
        }
        
        if (Trigger.isAfter && Trigger.isDelete) {
            for (Invoice__c inv : Trigger.old) {
                if ((inv.Status__c == 'Confirmed' || inv.Status__c == 'Delivered') &&
                    (inv.RecordTypeId == secondaryRecordTypeId )) {//|| inv.RecordTypeId == secondarySSRecordTypeId
                        
                        updatedInvoices.add(inv);
                    }
            }
        }
        
        if (Trigger.isAfter && Trigger.isUndelete) {
            for (Invoice__c inv : Trigger.new) {
                if ((inv.Status__c == 'Confirmed' || inv.Status__c == 'Delivered') &&
                    (inv.RecordTypeId == secondaryRecordTypeId )) {//|| inv.RecordTypeId == secondarySSRecordTypeId
                        
                        updatedInvoices.add(inv);
                    }
            }
        }
        
        if (!updatedInvoices.isEmpty()) {
            UpdateSalesPerformanceLPSCandTDFBHandler.updateSalesPerformance(updatedInvoices);
            //UpdateSalesPerformanceTDFThroughHandler.updateSalesPerformance(updatedInvoices);
        }
    }
}