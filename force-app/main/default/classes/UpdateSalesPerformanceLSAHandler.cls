public class UpdateSalesPerformanceLSAHandler {
    public static void updateSalesPerformance(List<Order__c> newOrders) {
        
        System.debug('newOrders: ' + newOrders);
        
        Map<Id, Id> accountOwnerMap = new Map<Id, Id>();

        // Populate Account to Owner mapping
        for (Order__c order : newOrders) {
            if (order.AccountId__c != null) {
                accountOwnerMap.put(order.AccountId__c, null);
            }
        }
        
        if (!accountOwnerMap.isEmpty()) {
            List<Account> accounts = [SELECT Id, OwnerId FROM Account WHERE Id IN :accountOwnerMap.keySet()];
            
            for (Account acc : accounts) {
                accountOwnerMap.put(acc.Id, acc.OwnerId);
            }
        }
        
        List<Sales_Target__c> salesTargetsToUpdate = new List<Sales_Target__c>();

        for (Order__c order : newOrders) {
            System.debug('Processing order: ' + order.Id + ' for Retailer: ' + order.AccountId__c);
            
            Id accountOwnerId = accountOwnerMap.get(order.AccountId__c);
            if (accountOwnerId == null) {
                System.debug('No OwnerId found for Account ' + order.AccountId__c + ' on Order ' + order.Id);
                continue;
            }

            // Retrieve all Account IDs for the current Owner
            List<Id> accountIdsForOwner = new List<Id>();
            List<Account> ownerAccounts = [SELECT Id FROM Account WHERE OwnerId = :accountOwnerId];
            for (Account acc : ownerAccounts) {
                accountIdsForOwner.add(acc.Id);
            }

            // Aggregate result for all orders under accounts owned by the same owner
            AggregateResult aggregatedResult = [
                SELECT SUM(Line_Item_Volume__c) totalLineItems
                FROM Order__c
                WHERE RecordType.Name = 'Primary Order'
                AND AccountId__c IN :accountIdsForOwner
                AND CALENDAR_MONTH(CreatedDate) = :order.CreatedDate.month() 
                AND CALENDAR_YEAR(CreatedDate) = :order.CreatedDate.year()
            ];

            Decimal totalLineItems = (Decimal) aggregatedResult.get('totalLineItems');
            System.debug('Total Line Items for Owner ' + accountOwnerId + ': ' + totalLineItems);

            // Query Sales Target record
            List<Sales_Target__c> salesPerformanceRecords = [SELECT Id, Assigned_To__c, Number_of_Month__c, Year__c, Litre_Sold_Actual__c 
                                                             FROM Sales_Target__c 
                                                             WHERE Assigned_To__c = :accountOwnerId 
                                                             AND Year__c = :String.valueOf(order.CreatedDate.year()) 
                                                             AND Number_of_Month__c = :order.CreatedDate.month() 
                                                             LIMIT 1];

            System.debug('Sales Performance Records for Owner ' + accountOwnerId + ': ' + salesPerformanceRecords.size());

            if (!salesPerformanceRecords.isEmpty()) {
                Sales_Target__c salesTarget = salesPerformanceRecords[0];
                salesTarget.Litre_Sold_Actual__c = totalLineItems;
                
                System.debug('Updating Sales Target ' + salesTarget.Id + ' with Productive Calls Actual: ' + totalLineItems);

                salesTargetsToUpdate.add(salesTarget);
            } else {
                System.debug('No Sales Performance Records found for order ' + order.Id);
            }
        }
        
        // Update all Sales Target records in a single DML operation
        if (!salesTargetsToUpdate.isEmpty()) {
            update salesTargetsToUpdate;
        }
    }
}