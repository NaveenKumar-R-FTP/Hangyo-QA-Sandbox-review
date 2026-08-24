public class UpdateSalesPerformanceProducCallsActual {
    
    public static void updateSalesPerformance(List<Order__c> orders) {
        if (orders == null || orders.isEmpty()) return;
        
        // Step 1: Collect retailer accounts and month/year from incoming orders
        Set<Id> retailerAccountIds = new Set<Id>();
        Set<Integer> months = new Set<Integer>();
        Set<Integer> years = new Set<Integer>();
        
        for (Order__c order : orders) {
            if (order.Account__c != null) {
                retailerAccountIds.add(order.Account__c);
                months.add(order.CreatedDate.month());
                years.add(order.CreatedDate.year());
            }
        }
        
        // Step 2: Map retailer account -> OwnerId
        Map<Id, Id> retailerAccountToOwnerMap = new Map<Id, Id>();
        for (Account acc : [SELECT Id, OwnerId FROM Account WHERE Id IN :retailerAccountIds]) {
            retailerAccountToOwnerMap.put(acc.Id, acc.OwnerId);
        }
        
        Set<Id> ownerIds = new Set<Id>(retailerAccountToOwnerMap.values());
        if (ownerIds.isEmpty()) return;
        
        // Step 3: Fetch user roles for owners
        Map<Id, User> userIdToUserMap = new Map<Id, User>(
            [SELECT Id, UserRoleId FROM User WHERE Id IN :ownerIds AND IsActive = TRUE]
        );
        
        Map<Id, UserRole> allRoles = new Map<Id, UserRole>(
            [SELECT Id, ParentRoleId FROM UserRole]
        );
        
        // Step 4: Build map of roleId -> Users
        Map<Id, List<User>> roleIdToUsersMap = new Map<Id, List<User>>();
        for (User u : [SELECT Id, UserRoleId FROM User WHERE UserRoleId != null AND IsActive = TRUE]) {
            if (!roleIdToUsersMap.containsKey(u.UserRoleId)) {
                roleIdToUsersMap.put(u.UserRoleId, new List<User>());
            }
            roleIdToUsersMap.get(u.UserRoleId).add(u);
        }
        
        Map<Id, Id> subordinateToTopOwnerMap = new Map<Id, Id>();
        for (Id ownerId : ownerIds) {
            subordinateToTopOwnerMap.put(ownerId, ownerId); // self mapping
        }
        
        // Step 5: Gather all relevant userIds (owners + subordinates)
        //Set<Id> allRelevantUserIds = new Set<Id>();
        /*for (Id ownerId : ownerIds) {
if (!userIdToUserMap.containsKey(ownerId)) continue;
allRelevantUserIds.add(ownerId);

User ownerUser = userIdToUserMap.get(ownerId);
Set<Id> subordinateRoleIds = getOnlySubordinateRoleIds(ownerUser.UserRoleId, allRoles);

for (Id roleId : subordinateRoleIds) {
if (roleIdToUsersMap.containsKey(roleId)) {
for (User u : roleIdToUsersMap.get(roleId)) {
allRelevantUserIds.add(u.Id);
}
}
}
}*/
        
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
        
        // Step 7: Collect all relevant userIds (owners + subordinates)
        Set<Id> allRelevantUserIds = new Set<Id>(subordinateToTopOwnerMap.keySet());
        
        // Step 6: Fetch all related accounts for relevant users
        List<Account> relevantAccounts = [
            SELECT Id, OwnerId, CreatedDate 
            FROM Account 
            WHERE RecordType.DeveloperName = 'Retailer' 
            AND OwnerId IN :allRelevantUserIds
        ];
        
        // Step 7: Fetch secondary orders for these accounts
        Decimal threshold = Decimal.valueOf(System.Label.OrderValue300);
        List<Order__c> allRelatedOrders = [
            SELECT Id, Account__c, CreatedDate, Account__r.OwnerId 
            FROM Order__c 
            WHERE RecordType.DeveloperName = 'Secondary_Order'
            AND Total_Order_Value__c > :threshold
            AND Account__r.OwnerId IN :allRelevantUserIds
            AND CALENDAR_MONTH(CreatedDate) IN :months
            AND CALENDAR_YEAR(CreatedDate) IN :years
        ];//(RecordType.DeveloperName IN ('Secondary_Order', 'Under_SS_Secondary_Order'))
        
        // Step 8: Aggregate productive calls and new outlets by owner-month-year
        Map<String, Decimal> productiveCallMap = new Map<String, Decimal>();
        Map<String, Decimal> newOutletMap = new Map<String, Decimal>();
        
        // Productive Calls aggregation
        for (Order__c secOrder : allRelatedOrders) {
            //Id ownerId = secOrder.Account__r.OwnerId;
            Id topOwnerId = subordinateToTopOwnerMap.get(secOrder.Account__r.OwnerId);
            Integer month = secOrder.CreatedDate.month();
            Integer year = secOrder.CreatedDate.year();
            String key = topOwnerId + '-' + month + '-' + year;
            
            productiveCallMap.put(key, (productiveCallMap.containsKey(key) ? productiveCallMap.get(key) : 0) + 1);
        }
        
        // New Outlet aggregation
        List<Account> newOutletAccounts = [
            SELECT Id, OwnerId, CreatedDate
            FROM Account
            WHERE RecordType.DeveloperName = 'Retailer'
            AND OwnerId IN :allRelevantUserIds
            AND CALENDAR_MONTH(CreatedDate) IN :months
            AND CALENDAR_YEAR(CreatedDate) IN :years
        ];
        
        // New Outlet aggregation
        for (Account acc : newOutletAccounts) {
            Id topOwnerId = subordinateToTopOwnerMap.get(acc.OwnerId);
            Integer month = acc.CreatedDate.month();
            Integer year = acc.CreatedDate.year();
            String key = topOwnerId + '-' + month + '-' + year;
            
            newOutletMap.put(key, (newOutletMap.containsKey(key) ? newOutletMap.get(key) : 0) + 1);
        }
        
        // Step 9: Fetch targets and update
        List<Sales_Target__c> allSalesTargets = [
            SELECT Id, Assigned_To__c, Number_of_Month__c, Year__c,
            Productive_Calls_Actual__c, New_Outlet_Opened_Actual__c
            FROM Sales_Target__c
            WHERE RecordType.DeveloperName = 'Sales_Target_Month' AND Assigned_To__c IN :ownerIds
            AND Number_of_Month__c IN :months
            AND Year__c IN :convertYearsToString(years)
        ];
        
        Map<Id, Sales_Target__c> targetsToUpdate = new Map<Id, Sales_Target__c>();
        
        for (Sales_Target__c target : allSalesTargets) {
            String key = target.Assigned_To__c + '-' + target.Number_of_Month__c + '-' + target.Year__c;
            Boolean updated = false;
            
            if (productiveCallMap.containsKey(key)) {
                target.Productive_Calls_Actual__c = productiveCallMap.get(key);
                updated = true;
            }
            if (newOutletMap.containsKey(key)) {
                target.New_Outlet_Opened_Actual__c = newOutletMap.get(key);
                updated = true;
            }
            
            if (updated) {
                targetsToUpdate.put(target.Id, target);
            }
        }
        
        if (!targetsToUpdate.isEmpty()) {
            update targetsToUpdate.values();
        }
        
        // Enqueue job for further processing if needed
        // if (!ownerIds.isEmpty()) {
        //    System.enqueueJob(new UpdateSalesPeSecondaryOrderForUpperRoles(ownerIds));
        // }
        
        if (!ownerIds.isEmpty()) {
            System.enqueueJob(new UpdateSalesPeSecondaryOrderForUpperRoles(ownerIds, months, years));
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