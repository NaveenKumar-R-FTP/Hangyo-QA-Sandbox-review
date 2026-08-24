public class UpdateSalesPerformancePSAHandler {
    
    public static void updateSalesPerformance(List<Order__c> orders) {
        if (orders == null || orders.isEmpty()) return;
        
        // 1. Collect Distributor Accounts and Date Parts
        Set<Id> distributorAccountIds = new Set<Id>();
        Set<Integer> months = new Set<Integer>();
        Set<Integer> years = new Set<Integer>();
        
        for (Order__c order : orders) {
            if (order.AccountId__c != null) distributorAccountIds.add(order.AccountId__c);
            months.add(order.CreatedDate.month());
            years.add(order.CreatedDate.year());
        }
        
        // 2. Distributor Account -> Owner Map
        Map<Id, Id> distributorAccountToOwnerMap = new Map<Id, Id>();
        for (Account acc : [
            SELECT Id, OwnerId FROM Account WHERE Id IN :distributorAccountIds
        ]) {
            distributorAccountToOwnerMap.put(acc.Id, acc.OwnerId);
        }
        
        // 3. Initial ownerIds
        Set<Id> ownerIds = new Set<Id>(distributorAccountToOwnerMap.values());
        if (ownerIds.isEmpty()) return;
        
        // 4. Build Role Hierarchy & Subordinate Map
        Map<Id, User> userIdToUserMap = new Map<Id, User>(
            [SELECT Id, UserRoleId FROM User WHERE Id IN :ownerIds AND IsActive = TRUE]
        );
        
        Map<Id, UserRole> allRoles = new Map<Id, UserRole>(
            [SELECT Id, ParentRoleId FROM UserRole]
        );
        
        Map<Id, List<User>> roleIdToUsersMap = new Map<Id, List<User>>();
        for (User u : [SELECT Id, UserRoleId FROM User WHERE UserRoleId != null AND IsActive = TRUE]) {
            if (!roleIdToUsersMap.containsKey(u.UserRoleId)) {
                roleIdToUsersMap.put(u.UserRoleId, new List<User>());
            }
            roleIdToUsersMap.get(u.UserRoleId).add(u);
        }
        
        // Map subordinate user -> top owner
        Map<Id, Id> subordinateToTopOwnerMap = new Map<Id, Id>();
        for (Id ownerId : ownerIds) {
            subordinateToTopOwnerMap.put(ownerId, ownerId); // self mapping
        }
        
        for (Id ownerId : ownerIds) {
            User ownerUser = userIdToUserMap.get(ownerId);
            if (ownerUser == null || ownerUser.UserRoleId == null) continue;
            
            Set<Id> subordinateRoleIds = getOnlySubordinateRoleIds(ownerUser.UserRoleId, allRoles);
            for (Id roleId : subordinateRoleIds) {
                if (roleIdToUsersMap.containsKey(roleId)) {
                    for (User u : roleIdToUsersMap.get(roleId)) {
                        subordinateToTopOwnerMap.put(u.Id, ownerId);
                    }
                }
            }
        }
        
        Set<Id> allRelevantUserIds = new Set<Id>(subordinateToTopOwnerMap.keySet());
        
        // 5. Fetch All Distributor Accounts (Filtered)
        Map<Id, Account> allAccounts = new Map<Id, Account>(
            [SELECT Id, OwnerId FROM Account 
             WHERE RecordType.DeveloperName = 'Distributor' 
             AND OwnerId IN :allRelevantUserIds]
        );
        
        // 6. Fetch Primary Orders grouped by Account
        Map<Id, List<Order__c>> accountIdToOrdersMap = new Map<Id, List<Order__c>>();
        for (Order__c o : [
            SELECT Id, AccountId__c, CreatedDate, Total_Order_Value__c, Line_Item_Volume__c 
            FROM Order__c 
            WHERE RecordType.DeveloperName = 'Primary_Order'
            AND CALENDAR_MONTH(CreatedDate) IN :months
            AND CALENDAR_YEAR(CreatedDate) IN :years
            AND AccountId__r.OwnerId IN :allRelevantUserIds
        ]) {
            if (o.AccountId__c == null) continue;
            if (!accountIdToOrdersMap.containsKey(o.AccountId__c)) {
                accountIdToOrdersMap.put(o.AccountId__c, new List<Order__c>());
            }
            accountIdToOrdersMap.get(o.AccountId__c).add(o);
        }
        
        // 7. Fetch Retailer Accounts for New Outlets
        Map<String, Decimal> newOutletMap = new Map<String, Decimal>();
        for (Account a : [
            SELECT Id, CreatedDate, OwnerId FROM Account 
            WHERE RecordType.DeveloperName = 'Retailer' 
            AND OwnerId IN :allRelevantUserIds 
            AND CALENDAR_MONTH(CreatedDate) IN :months 
            AND CALENDAR_YEAR(CreatedDate) IN :years
        ]) {
            Id topOwnerId = subordinateToTopOwnerMap.get(a.OwnerId);
            if (topOwnerId == null) continue;
            
            String key = topOwnerId + ':' + a.CreatedDate.month() + ':' + a.CreatedDate.year();
            newOutletMap.put(key, (newOutletMap.containsKey(key) ? newOutletMap.get(key) : 0) + 1);
        }
        
        // 8. Aggregate Primary Sales & Litre Sold for all accounts in one pass
        Map<String, Decimal> primarySalesMap = new Map<String, Decimal>();
        Map<String, Decimal> litreSoldMap = new Map<String, Decimal>();
        
        for (Id accId : accountIdToOrdersMap.keySet()) {
            Account acc = allAccounts.get(accId);
            if (acc == null) continue;
            
            Id topOwnerId = subordinateToTopOwnerMap.get(acc.OwnerId);
            if (topOwnerId == null) continue;
            
            for (Order__c relOrder : accountIdToOrdersMap.get(accId)) {
                Integer month = relOrder.CreatedDate.month();
                Integer year = relOrder.CreatedDate.year();
                String key = topOwnerId + ':' + month + ':' + year;
                
                Decimal totalVal = (relOrder.Total_Order_Value__c != null ? relOrder.Total_Order_Value__c : 0);
                Decimal litreVal = (relOrder.Line_Item_Volume__c != null ? relOrder.Line_Item_Volume__c : 0);
                
                primarySalesMap.put(key, (primarySalesMap.containsKey(key) ? primarySalesMap.get(key) : 0) + totalVal);
                litreSoldMap.put(key, (litreSoldMap.containsKey(key) ? litreSoldMap.get(key) : 0) + litreVal);
            }
        }
        
        // 9. Fetch Sales Targets and Update
        Map<String, Sales_Target__c> salesTargetMap = new Map<String, Sales_Target__c>();
        for (Sales_Target__c st : [
            SELECT Id, Assigned_To__c, Number_of_Month__c, Year__c,
            Primary_Sales_Actual__c, Litre_Sold_Actual__c, New_Outlet_Opened_Actual__c
            FROM Sales_Target__c
            WHERE RecordType.DeveloperName = 'Sales_Target_Month' 
            AND Assigned_To__c IN :ownerIds
            AND Number_of_Month__c IN :months
            AND Year__c IN :convertYearsToString(years)
        ]) {
            String key = st.Assigned_To__c + ':' + st.Number_of_Month__c + ':' + st.Year__c;
            salesTargetMap.put(key, st);
        }
        
        Map<Id, Sales_Target__c> salesTargetsToUpdateMap = new Map<Id, Sales_Target__c>();
        
        for (String stKey : salesTargetMap.keySet()) {
            Sales_Target__c st = salesTargetMap.get(stKey);
            String key = st.Assigned_To__c + ':' + st.Number_of_Month__c + ':' + st.Year__c;
            
            Boolean updated = false;
            
            if (primarySalesMap.containsKey(key)) {
                st.Primary_Sales_Actual__c = primarySalesMap.get(key);
                updated = true;
            }
            if (litreSoldMap.containsKey(key)) {
                st.Litre_Sold_Actual__c = litreSoldMap.get(key);
                updated = true;
            }
            if (newOutletMap.containsKey(key)) {
                st.New_Outlet_Opened_Actual__c = newOutletMap.get(key);
                updated = true;
            }
            
            if (updated) {
                salesTargetsToUpdateMap.put(st.Id, st);
            }
        }
        
        if (!salesTargetsToUpdateMap.isEmpty()) {
            update salesTargetsToUpdateMap.values();
        }
        
        if (!ownerIds.isEmpty()) {
            System.enqueueJob(new UpdateSalesPerformanceOrderForUpperRoles(ownerIds, months, years));
        }
    }
    
    private static List<String> convertYearsToString(Set<Integer> yearSet) {
        List<String> yearStrings = new List<String>();
        for (Integer yr : yearSet) {
            yearStrings.add(String.valueOf(yr));
        }
        return yearStrings;
    }
    
    public static Set<Id> getOnlySubordinateRoleIds(Id parentRoleId, Map<Id, UserRole> allRoles) {
        Set<Id> childRoleIds = new Set<Id>();
        if (parentRoleId == null) return childRoleIds;
        collectSubRoles(parentRoleId, allRoles, childRoleIds);
        return childRoleIds;
    }
    
    private static void collectSubRoles(Id parentId, Map<Id, UserRole> allRoles, Set<Id> result) {
        for (UserRole role : allRoles.values()) {
            if (role.ParentRoleId == parentId && !result.contains(role.Id)) {
                result.add(role.Id);
                collectSubRoles(role.Id, allRoles, result);
            }
        }
    }
}