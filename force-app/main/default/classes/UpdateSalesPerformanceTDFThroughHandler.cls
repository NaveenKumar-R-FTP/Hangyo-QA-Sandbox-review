public class UpdateSalesPerformanceTDFThroughHandler {
    public static void updateSalesPerformance(List<Invoice__c> invoices) {
        
        System.debug('invoices: ' + invoices);
        
        Map<Id, Id> accountOwnerMap = new Map<Id, Id>();
        
        for (Invoice__c invoice : invoices) {
            if (invoice.Retailer_Account__c != null) {
                accountOwnerMap.put(invoice.Retailer_Account__c, null);
            }
        }
        
        if (!accountOwnerMap.isEmpty()) {
            List<Account> accounts = [SELECT Id, OwnerId FROM Account WHERE Id IN :accountOwnerMap.keySet()];
            
            for (Account acc : accounts) {
                accountOwnerMap.put(acc.Id, acc.OwnerId);
            }
        }
        
        List<Sales_Target__c> salesTargetsToUpdate = new List<Sales_Target__c>();
        
        for (Invoice__c invoice : invoices) {
            System.debug('Processing invoice: ' + invoice.Id + ' for Retailer: ' + invoice.Retailer_Account__c);
            
            Id accountOwnerId = accountOwnerMap.get(invoice.Retailer_Account__c);
            if (accountOwnerId == null) {
                System.debug('No OwnerId found for Account ' + invoice.Retailer_Account__c + ' on invoice ' + invoice.Id);
                continue;
            }
            
            // Fetch subordinates of the account owner based on role hierarchy
            Set<Id> subordinateUserIds = new Set<Id>();
            
            //List<User> subordinates = [SELECT Id FROM User WHERE UserRoleId IN (SELECT Id FROM UserRole WHERE ParentRoleId = (SELECT UserRoleId FROM User WHERE Id = :accountOwnerId))];
            
           /* // Step 1: Retrieve the UserRoleId of the account owner
            User accountOwner = [SELECT UserRoleId FROM User WHERE Id = :accountOwnerId LIMIT 1];
            system.debug('accountOwner = ' + accountOwner);
            
            // Step 2: Retrieve the IDs of subordinate roles
            List<Id> subordinateRoleIds = new List<Id>();
            for (UserRole ur : [SELECT Id FROM UserRole WHERE ParentRoleId = :accountOwner.UserRoleId]) {
                subordinateRoleIds.add(ur.Id);
            }
            system.debug('subordinateRoleIds = ' + subordinateRoleIds);
            //List<Id> subordinateRoleIds = [SELECT Id FROM UserRole WHERE ParentRoleId = :accountOwner.UserRoleId];
            
            // Step 3: Retrieve the users in those subordinate roles
            List<User> subordinates = [SELECT Id FROM User WHERE UserRoleId IN :subordinateRoleIds];
            system.debug('subordinates = ' + subordinates);
            
            for (User subordinate : subordinates) {
                subordinateUserIds.add(subordinate.Id);
            }
            
            // Include the current owner in the list of UserIds
            subordinateUserIds.add(accountOwnerId);*/
           
            User accountOwner = [SELECT Id FROM User WHERE Id = :accountOwnerId LIMIT 1];
            system.debug('accountOwner = ' + accountOwner);
            
            List<User> subordinates = [SELECT Id FROM User WHERE ManagerId =: accountOwner.Id];
            system.debug('subordinates = ' + subordinates);
            
            for (User subordinate : subordinates) {
                subordinateUserIds.add(subordinate.Id);
            }
            
            // Include the current owner in the list of UserIds
            subordinateUserIds.add(accountOwnerId);
            
            // Fetch accounts owned by the owner and their subordinates
            Set<Id> relatedAccountIds = new Set<Id>();
            List<Account> relatedAccounts = [SELECT Id FROM Account WHERE OwnerId IN :subordinateUserIds];
            for (Account account : relatedAccounts) {
                relatedAccountIds.add(account.Id);
            }
            
            // Query for related invoices
            List<Invoice__c> invoiceCounts = [SELECT Id, Number_of_Invoice_Line_Items__c, Retailer_Account__c, CreatedDate,Invoice_Line_Item_Total_Amount__c,Invoice_Amount__c 
                                              FROM Invoice__c 
                                              WHERE RecordType.Name = 'Secondary Invoice' 
                                              AND Retailer_Account__c IN :relatedAccountIds
                                              AND CALENDAR_MONTH(CreatedDate) = :invoice.CreatedDate.month() 
                                              AND CALENDAR_YEAR(CreatedDate) = :invoice.CreatedDate.year()
                                              AND (Status__c = 'Confirmed' OR Status__c = 'Delivered')];
            
            List<Asset__c> assets = [Select Id FROM Asset__c Where Retailer_Account__c IN :relatedAccountIds];
            
            System.debug('Invoice counts for Invoice ' + invoice.Id + ': ' + invoiceCounts.size());
            
            System.debug('assets.size() = ' + assets.size());
            
            // Calculate the total number of invoice line items
            Decimal totalInvoiceAmount = 0;
            for (Invoice__c relatedInvoice : invoiceCounts) {
                totalInvoiceAmount += relatedInvoice.Invoice_Amount__c != null ? relatedInvoice.Invoice_Amount__c : 0;
            }
            
            Decimal totalDFThroughput = 0;
            if (totalInvoiceAmount != null && assets.size() > 0) {
                totalDFThroughput = (totalInvoiceAmount/assets.size()) * 100;
            }
            
            System.debug('totalDFThroughput = ' + totalDFThroughput);
            
            List<Sales_Target__c> salesPerformanceRecords = [SELECT Id, Assigned_To__c, Number_of_Month__c, Year__c, Total_DF_Throughput_Actual__c 
                                                             FROM Sales_Target__c  
                                                             WHERE Assigned_To__c = :accountOwnerId 
                                                             AND Year__c = :String.valueOf(invoice.CreatedDate.year())
                                                             AND Number_of_Month__c = :invoice.CreatedDate.month() 
                                                             LIMIT 1];
            
            System.debug('Sales Performance Records for Retailer ' + invoice.Retailer_Account__c + ': ' + salesPerformanceRecords.size());
            
            if (!salesPerformanceRecords.isEmpty() && !invoiceCounts.isEmpty()) {
                Sales_Target__c salesTarget = salesPerformanceRecords[0];
                salesTarget.Total_DF_Throughput_Actual__c = totalDFThroughput;
                
                System.debug('Updating Sales Target ' + salesTarget.Id + ' with LPSC_total_orders_of_bills_Actual: ' + totalDFThroughput);
                
                salesTargetsToUpdate.add(salesTarget);
            } else {
                System.debug('No Sales Performance Records or invoice Counts found for invoice ' + invoice.Id);
            }
        }
        
        // Update the sales targets in Salesforce
        if (!salesTargetsToUpdate.isEmpty()) {
            update salesTargetsToUpdate;
            System.debug('Updated Sales Targets: ' + salesTargetsToUpdate);
        }
        
    }
}