global class ArchiveInvoiceLineItemsBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful, Schedulable {
   
    private Integer totalProcessed = 0;
    private Integer totalArchived = 0; 
    private Integer totalFailed = 0; 
    private List<String> errorMessages = new List<String>();
    
    global Database.QueryLocator start(Database.BatchableContext bc) {  
        Azure_Archive_Config__mdt confg = Azure_Archive_Config__mdt.getInstance('Invoice_Line_Item');
        
        Date cutoffDate = Date.today().addDays(-(Integer)confg.Retention_Days__c);
        
        Map<String, Schema.SObjectField> fieldMap = Invoice_Line_Item__c.SObjectType.getDescribe().fields.getMap();
        Set<String> excludedFields = new Set<String>{
            'LastActivityDate', 'LastReferencedDate', 'LastViewedDate', 'RecordVisibilityId', 'UserRecordAccessId'
        };  
     
        List<String> fieldNames = new List<String>();
    
        for (String fieldName : fieldMap.keySet()) {
            if(!excludedFields.contains(fieldName)){
                    fieldNames.add(fieldName);
            }
        }
                        
        String query = 'SELECT ' + String.join(fieldNames, ',') +
                        ' FROM Invoice_Line_Item__c ';
        if(!String.isBlank(confg.Closed_State_Values__c)){
            query += (String)confg.Closed_State_Values__c;
        }   
                             
        return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext bc,List<Invoice_Line_Item__c> scope) {
        DateTime archivedTimestamp = DateTime.now();
        Set<Id> invoiceIdSet = new Set<Id>();
        List<Invoice_Line_Item__c> invoiceItemsToUpdate = new List<Invoice_Line_Item__c>();
        List<Invoice_Line_Item__c> archivedItems = new List<Invoice_Line_Item__c>();
        List<Invoice__c> invoicesToUpdate = new List<Invoice__c>();
        totalProcessed += scope.size();
            
        ArchiveConnectorService.SendResult r = ArchiveConnectorService.send('Invoice_Line_Item__c', scope, bc.getJobId());
    
        if (r.success) {
            System.debug('success:-' + r.success);
            try {
                System.debug('scope:-' + scope);
                System.debug('archivedIds:-' + r.archivedIds);
                for (Invoice_Line_Item__c item : scope) {            
                    if(r.archivedIds.contains(item.id)){
                        invoiceIdSet.add(item.Invoice__c);
                        invoiceItemsToUpdate.add(new Invoice_Line_Item__c(
                            Id = item.Id,
                            Archived__c = true,
                            Archived_Date__c = archivedTimestamp
                        ));
                        archivedItems.add(item);                        
                    }
                }        
                totalArchived+= invoiceItemsToUpdate.size();
                TriggerBypass.bypassed.add('Invoice_Line_Item__c');   // bypass ON (line item triggers)
                TriggerBypass.bypassed.add('Invoice__c');             // bypass ON (invoice triggers)
                Database.update(invoiceItemsToUpdate, false);
        
                for(Invoice__c inv : [SELECT Id, Invoice_Amount_Before_Tax_del__c, Collected_Amount__c,
                                      Invoice_Line_Item_Total_Amount__c, Number_of_Invoice_Line_Items__c, Discount__c,
                                      Total_Discount__c, Total_Discount1__c, Total_Discount_2__c
                                      FROM Invoice__c WHERE Id IN : invoiceIdSet]){
                    inv.Snapshot_Invoice_Amount_Before_Tax__c = inv.Invoice_Amount_Before_Tax_del__c;
                    inv.Snapshot_Collected_Amount__c = inv.Collected_Amount__c;
                    inv.Snapshot_Invoice_Line_Item_Total_Amount__c = inv.Invoice_Line_Item_Total_Amount__c;
                    inv.Snapshot_Number_of_Invoice_Line_Items__c = inv.Number_of_Invoice_Line_Items__c;
                    inv.Snapshot_Discount__c = inv.Discount__c;
                    inv.Snapshot_Total_Discount__c = inv.Total_Discount__c;
                    inv.Snapshot_Total_Discount_1__c = inv.Total_Discount1__c;
                    inv.Snapshot_Total_Discount_2__c = inv.Total_Discount_2__c;
                    invoicesToUpdate.add(inv);
                }
                
                if(!invoicesToUpdate.isEmpty()){
                    update invoicesToUpdate;
                }
            } catch (DmlException e) {
                for (Integer i = 0; i < e.getNumDml(); i++) {
                    System.debug('DML Error ' + i + ': ' + e.getDmlMessage(i));
                    System.debug('Status Code: ' + e.getDmlStatusCode(i));
                    System.debug('Fields: ' + e.getDmlFieldNames(i));
                }
            }
        } else {
            System.debug('Error while Archiving: ' + r.errorMessage);
            totalFailed += scope.size();
            errorMessages.add(r.errorCode + '-' + r.errorMessage);            
        }
    }


    global void finish(Database.BatchableContext bc) {

        System.debug('Archival job completed.');
        Archival_Job_Log__c ajl = new Archival_Job_Log__c(
            Archive_Batch_Id__c   = bc.getJobId(),
            Archived_Object__c    = 'Invoice_Line_Item__c',
            Error_Message__c      = errorMessages.isEmpty() ? null : String.join(errorMessages, '; '),
            Total_Archived__c     = totalArchived,
            Total_Failed__c       = totalFailed,
            Total_Processed__c    = totalProcessed
        );
        insert ajl;
    }
    
     global void execute(SchedulableContext sc) {
        Database.executeBatch(new ArchiveInvoiceLineItemsBatch(), 200);
    }    
}