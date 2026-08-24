/**
* Class Name  : OrderProductController
* Test Class  : OrderProductControllerTest
* author      : Ashwini
* CreatedDate : 25-12-24
* Description : Created to update Average order value on account
* */
public without sharing class OrderTriggerHandler {
    //This method is to collect orders related to account
    public static void updateAverageOrderValue(List<Order__c> orderList) {
        Set<Id> accountIds = collectAccountIds(orderList);
        
        if (accountIds.isEmpty()) {
            return;
        }
        
        Map<Id, Account> retailerAccounts = getRetailerAccounts(accountIds);
        
        if (retailerAccounts.isEmpty()) {
            return;
        }
        
        List<Order__c> ordList = getOrdersForRetailerAccounts(retailerAccounts.keySet());
        
        Map<Id, Decimal> accountTotalValueMap = new Map<Id, Decimal>();
        Map<Id, Integer> accountOrderCountMap = new Map<Id, Integer>();
        
        calculateOrderStats(ordList, accountTotalValueMap, accountOrderCountMap);
        
        List<Account> accountsToUpdate = prepareAccountsForUpdate(accountTotalValueMap, accountOrderCountMap);
        
        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
    }
    
    // Helper method to collect AccountIds
    private static Set<Id> collectAccountIds(List<Order__c> orderList) {
        Set<Id> accountIds = new Set<Id>();
        for (Order__c ord : orderList) {
            if (ord.Account__c != null) {
                accountIds.add(ord.Account__c);
            }
        }
        return accountIds;
    }
    
    // Helper method to get Retailer Accounts
    private static Map<Id, Account> getRetailerAccounts(Set<Id> accountIds) {
        return new Map<Id, Account>(
            [SELECT Id, RecordType.Name 
             FROM Account 
             WHERE Id IN :accountIds AND RecordType.Name = 'Retailer']
        );
    }
    
    // Helper method to get Orders for Retailer Accounts
    private static List<Order__c> getOrdersForRetailerAccounts(Set<Id> retailerAccountIds) {
        return [SELECT Id, Account__c, Total_Order_Value__c, RecordType.Name
                FROM Order__c 
                WHERE Account__c IN :retailerAccountIds
                AND RecordType.Name = 'Secondary Order'];
    }
    
    // Helper method to calculate total order value and order count for each account
    private static void calculateOrderStats(List<Order__c> ordList, Map<Id, Decimal> accountTotalValueMap, Map<Id, Integer> accountOrderCountMap) {
        for (Order__c ord : ordList) {
            Decimal orderValue = ord.Total_Order_Value__c != null ? ord.Total_Order_Value__c : 0;
            
            // Add to the total order value for the account
            if (!accountTotalValueMap.containsKey(ord.Account__c)) {
                accountTotalValueMap.put(ord.Account__c, 0);
            }
            accountTotalValueMap.put(ord.Account__c, accountTotalValueMap.get(ord.Account__c) + orderValue);
            
            // Count the orders for the account
            if (!accountOrderCountMap.containsKey(ord.Account__c)) {
                accountOrderCountMap.put(ord.Account__c, 0);
            }
            accountOrderCountMap.put(ord.Account__c, accountOrderCountMap.get(ord.Account__c) + 1);
        }
    }
    
    // Helper method to prepare accounts for update with average order value
    private static List<Account> prepareAccountsForUpdate(Map<Id, Decimal> accountTotalValueMap, Map<Id, Integer> accountOrderCountMap) {
        List<Account> accountsToUpdate = new List<Account>();
        
        for (Id accountId : accountTotalValueMap.keySet()) {
            Decimal totalOrderValue = accountTotalValueMap.get(accountId);
            Integer orderCount = accountOrderCountMap.containsKey(accountId) ? accountOrderCountMap.get(accountId) : 0;
            
            // Calculate average order value
            Decimal averageOrderValue = (orderCount > 0) ? totalOrderValue / orderCount : 0;
            
            // Prepare Account for update
            accountsToUpdate.add(new Account(
                Id = accountId,
                Average_Order_Value__c = averageOrderValue
            ));
        }
        
        return accountsToUpdate;
    }
    
    //Update Order Frequency & Last Order Date
    /*public static void updateRetailerOrderData(List<Order__c> orders) {
        Id secondaryOrderRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Order__c' AND DeveloperName = 'Secondary_Order' LIMIT 1].Id;
        
        List<Order__c> secondaryOrders = new List<Order__c>();
        for (Order__c order : orders) {
            if (order.RecordTypeId == secondaryOrderRecordTypeId) {
                secondaryOrders.add(order);
            }
        }
        
        if (secondaryOrders.isEmpty()) {
            return; 
        }
        
        Set<Id> retailerIds = new Set<Id>();
        for (Order__c order : secondaryOrders) {
            if (order.Account__c != null) {
                retailerIds.add(order.Account__c);
            }
        }
        
        if (retailerIds.isEmpty()) {
            return; 
        }
        
        // Get the retailers
        List<Account> retailers = [SELECT Id, Name, Last_Order_Date__c, Order_Frequency__c
                                   FROM Account
                                   WHERE Id IN :retailerIds];
        
        Map<Id, Account> retailerMap = new Map<Id, Account>();
        for (Account retailer : retailers) {
            retailerMap.put(retailer.Id, retailer);
        }
        
        // Map to store the number of orders placed by each retailer in the current year
        Map<Id, Integer> retailerOrderCountMap = new Map<Id, Integer>();
        
        // Get the current year
        Integer currentYear = Date.today().year();
        
        // Loop through the orders to count the ones for the current year
        for (Order__c order : secondaryOrders) {
            if (order.Account__c != null) {
                Date orderDate = order.CreatedDate.date();
                
                // Only count orders from the current year
                if (orderDate.year() == currentYear) {
                    if (!retailerOrderCountMap.containsKey(order.Account__c)) {
                        retailerOrderCountMap.put(order.Account__c, 0);
                    }
                    // Increment the order count for this retailer in the current year
                    retailerOrderCountMap.put(order.Account__c, retailerOrderCountMap.get(order.Account__c) + 1);
                }
                
                // Update the Last Order Date if necessary
                Account retailer = retailerMap.get(order.Account__c);
                if (retailer != null) {
                    if (retailer.Last_Order_Date__c == null || order.CreatedDate.date() > retailer.Last_Order_Date__c) {
                        retailer.Last_Order_Date__c = order.CreatedDate.date();
                    }
                }
            }
        }
        
        // Fetch all orders for the retailer in the current year (including new ones)
        List<Order__c> allCurrentYearOrders = [SELECT Account__c, CreatedDate 
                                               FROM Order__c 
                                               WHERE Account__c IN :retailerIds 
                                               AND CreatedDate >= :Date.newInstance(currentYear, 1, 1)];
        
        // Add counts from all current year orders (including the current ones)
        for (Order__c order : allCurrentYearOrders) {
            if (!retailerOrderCountMap.containsKey(order.Account__c)) {
                retailerOrderCountMap.put(order.Account__c, 0);
            }
            retailerOrderCountMap.put(order.Account__c, retailerOrderCountMap.get(order.Account__c) + 1);
        }
        
        // Debugging: Check the retailer order counts
        System.debug('Retailer Order Counts (including new orders): ' + retailerOrderCountMap);
        
        // Update the order frequency based on total orders in the current year / 12
        for (Account retailer : retailers) {
            Integer totalOrdersThisYear = retailerOrderCountMap.get(retailer.Id)-1;
            
            if (totalOrdersThisYear != null) {
                // Calculate the frequency and round to 2 decimal places
                Decimal frequency = (Decimal)totalOrdersThisYear / 12;
                retailer.Order_Frequency__c = frequency.setScale(2, RoundingMode.HALF_UP); // Round to 2 decimal places
            } else {
                retailer.Order_Frequency__c = 0; // If no orders in the current year, set frequency to 0
            }
            
            // Debugging: Check the updated order frequency
            System.debug('Retailer ' + retailer.Id + ' Order Frequency: ' + retailer.Order_Frequency__c);
        }
        
        // Update the retailers with the calculated data
        update retailers;
    }*/
    public static void updateRetailerOrderData(List<Order__c> orders) {
        // Get RecordType ID for Secondary Orders
        Id secondaryOrderRecordTypeId = [
            SELECT Id FROM RecordType 
            WHERE SObjectType = 'Order__c' 
            AND DeveloperName = 'Secondary_Order' 
            LIMIT 1
        ].Id;
        
        // Filter only Secondary Orders
        List<Order__c> secondaryOrders = new List<Order__c>();
        for (Order__c order : orders) {
            if (order.RecordTypeId == secondaryOrderRecordTypeId) {
                secondaryOrders.add(order);
            }
        }
        if (secondaryOrders.isEmpty()) return;
    
        // Collect unique Retailer IDs
        Set<Id> retailerIds = new Set<Id>();
        for (Order__c order : secondaryOrders) {
            if (order.Account__c != null) {
                retailerIds.add(order.Account__c);
            }
        }
        if (retailerIds.isEmpty()) return;
    
        // Fetch Retailers
        List<Account> retailers = [
            SELECT Id, Name, Last_Order_Date__c, Order_Frequency__c
            FROM Account
            WHERE Id IN :retailerIds
        ];
        Map<Id, Account> retailerMap = new Map<Id, Account>(retailers);
    
        // Map to store count of orders per retailer
        Map<Id, Integer> retailerOrderCountMap = new Map<Id, Integer>();
    
        // Current year
        Integer currentYear = Date.today().year();
    
        // Update Last Order Date for each retailer based on the latest incoming orders
        for (Order__c order : secondaryOrders) {
            if (order.Account__c == null) continue;
    
            Account retailer = retailerMap.get(order.Account__c);
            if (retailer != null) {
                Date orderDate = order.CreatedDate.date();
                if (retailer.Last_Order_Date__c == null || orderDate > retailer.Last_Order_Date__c) {
                    retailer.Last_Order_Date__c = orderDate;
                }
            }
        }
    
        // ✅ Aggregated query instead of fetching all orders — prevents 50k row error
        AggregateResult[] orderCounts = [
            SELECT Account__c accId, COUNT(Id) totalOrders
            FROM Order__c
            WHERE Account__c IN :retailerIds
            AND CreatedDate >= :Date.newInstance(currentYear, 1, 1)
            GROUP BY Account__c
        ];
    
        for (AggregateResult ar : orderCounts) {
            retailerOrderCountMap.put((Id) ar.get('accId'), (Integer) ar.get('totalOrders'));
        }
    
        System.debug('Retailer Order Counts (Aggregated): ' + retailerOrderCountMap);
    
        // Calculate frequency and update retailer records
        for (Account retailer : retailers) {
            Integer totalOrdersThisYear = retailerOrderCountMap.get(retailer.Id);
    
            if (totalOrdersThisYear != null && totalOrdersThisYear > 0) {
                Decimal frequency = (Decimal) totalOrdersThisYear / 12;
                retailer.Order_Frequency__c = frequency.setScale(2, RoundingMode.HALF_UP);
            } else {
                retailer.Order_Frequency__c = 0;
            }
    
            System.debug('Retailer ' + retailer.Id + 
                         ' Order Frequency: ' + retailer.Order_Frequency__c +
                         ', Last Order Date: ' + retailer.Last_Order_Date__c);
        }
    
        // Update the retailers
        if (!retailers.isEmpty()) {
            update retailers;
        }
    }
    
    //Written by ashwini-14/04/2025 to update the status of order where if we update order status of secondary order then corresponding underss order status need to get update
    
    public static void updateUnderssOrderStatus(List<Order__c> orderList) {
        Set<Id> childOrderIds = new Set<Id>();
        
        // Step 1: Collect valid child order IDs
        for (Order__c ord : orderList) {
            if (ord.Record_Type_Name__c == 'Under SS Secondary Order' && ord.Under_SS_Order__c != null) {
                childOrderIds.add(ord.Id);
            }
        }
        
        if (childOrderIds.isEmpty()) {
            return;
        }
        
        // Step 2: Get child orders with their parent and status
        List<Order__c> childOrders = [
            SELECT Id, Status__c, Under_SS_Order__c
            FROM Order__c
            WHERE Id IN :childOrderIds
        ];
        
        // Step 3: Build a map of ParentId => Status from child
        Map<Id, String> parentIdToStatusMap = new Map<Id, String>();
        for (Order__c child : childOrders) {
            if (child.Under_SS_Order__c != null) {
                parentIdToStatusMap.put(child.Under_SS_Order__c, child.Status__c);
            }
        }
        
        if (parentIdToStatusMap.isEmpty()) {
            return;
        }
        
        // Step 4: Fetch parent orders that need status updates
        List<Order__c> parentOrdersToUpdate = new List<Order__c>();
        List<Order__c> parentOrders = [
            SELECT Id, Status__c
            FROM Order__c
            WHERE Id IN :parentIdToStatusMap.keySet()
        ];
        
        for (Order__c parent : parentOrders) {
            String newStatus = parentIdToStatusMap.get(parent.Id);
            if (newStatus != null && parent.Status__c != newStatus) {
                parent.Status__c = newStatus;
                parentOrdersToUpdate.add(parent);
            }
        }
        
        // Step 5: Update parent orders with new status
        if (!parentOrdersToUpdate.isEmpty()) {
            update parentOrdersToUpdate;
        }
    }
    
}