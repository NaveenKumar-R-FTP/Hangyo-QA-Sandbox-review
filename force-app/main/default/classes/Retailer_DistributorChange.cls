public with sharing class Retailer_DistributorChange {

 public static void visitTaskDistributorUpdate(Set<Id> retailerIds) {
        if (retailerIds == null || retailerIds.isEmpty()) {
            return;
        }
        Map<Id, Account> retailerMap = new Map<Id, Account>(
            [SELECT Id, Distributor__c FROM Account WHERE Id IN :retailerIds]
        );
        if (retailerMap.isEmpty()) {
            return;
        }
        // Update Visit Tasks
        List<Visit_Task__c> visitTasksToUpdate = [
            SELECT Id, Retailer__c, Distributor__c, Status__c
            FROM Visit_Task__c
            WHERE Retailer__c IN :retailerMap.keySet()
            AND Status__c = 'Not Started'
        ];
        for (Visit_Task__c vt : visitTasksToUpdate) {
            Account relatedRetailer = retailerMap.get(vt.Retailer__c);
            if (relatedRetailer != null) {
                vt.Distributor__c = relatedRetailer.Distributor__c;
            }
        }
        if (!visitTasksToUpdate.isEmpty()) {
            update visitTasksToUpdate;
        }
        // Update Asset Mappings
        List<Asset_Mapping__c> mappingsToUpdate = [
            SELECT Id, Retailer__c, Distributor__c
            FROM Asset_Mapping__c
            WHERE Retailer__c IN :retailerMap.keySet()
            AND Active__c = true
        ];
        for (Asset_Mapping__c mapping : mappingsToUpdate) {
            Account relatedRetailer = retailerMap.get(mapping.Retailer__c);
            if (relatedRetailer != null) {
                mapping.Distributor__c = relatedRetailer.Distributor__c;
            }
        }
        if (!mappingsToUpdate.isEmpty()) {
            update mappingsToUpdate;
        }
    }
}