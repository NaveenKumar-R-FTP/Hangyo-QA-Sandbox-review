public without sharing class AssetTransferQueueable implements Queueable {
    
    private Set<Id> caseIds;
    
    public AssetTransferQueueable(Set<Id> caseIds) {
        this.caseIds = caseIds;
    }
    
    public void execute(QueueableContext context) {
        try {
            List<Case__c> cases = [
                SELECT Id, Status__c, Case_Type__c, Case_Type__r.Name, OEM_serial_number__c,
                       Request_type__c, Retailer_Transfer_To__c,
                       Distributor_Transfer_To__c, Scrap__c,
                       Retailer_Transfer_From__c, Distributor_Transfer_From__c,
                       Sync__c, New_Asset_Code__c, Old_Asset_Code__c,
                       Serial_Number__c, Make__c, Model__c, Capacity__c,
                       Retailer__c, Distributor__c
                FROM Case__c
                WHERE Id IN :caseIds
                AND Sync__c = true
            ];
            
            if (!cases.isEmpty()) {
                CaseTriggerHandler.handleAfterUpdate(cases, new Map<Id, Case__c>());
                List<Case__c> casesToReset = new List<Case__c>();
                for (Case__c c : cases) {
                    casesToReset.add(new Case__c(Id = c.Id, Sync__c = false));
                }
                Database.update(casesToReset, AccessLevel.SYSTEM_MODE);
            }
        } catch (Exception e) {
            System.debug('AssetTransferQueueable error: ' + e.getMessage());
        }
    }
}