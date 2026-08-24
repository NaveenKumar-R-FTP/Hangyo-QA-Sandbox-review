public class UpdateSalesPeSecondaryOrderForUpperRoles implements Queueable, Database.AllowsCallouts {
    
    private Set<Id> startingOwnerIds;
    private Set<Integer> months;
    private Set<Integer> years;
    
    public UpdateSalesPeSecondaryOrderForUpperRoles(Set<Id> ownerIds, Set<Integer> months, Set<Integer> years) {
        this.startingOwnerIds = ownerIds;
        this.months = months;
        this.years = years;
    }
    
    public void execute(QueueableContext context) {
        if (startingOwnerIds == null || startingOwnerIds.isEmpty()) return;
        
        // 1. Fetch all roles
        Map<Id, UserRole> allRoles = new Map<Id, UserRole>(
            [SELECT Id, ParentRoleId FROM UserRole]
        );
        
        // 2. Build Role → Employee_Role__c map
        Map<Id, String> roleIdToEmpRole = new Map<Id, String>();
        for (User u : [
            SELECT Id, UserRoleId, Employee_Role__c 
            FROM User 
            WHERE UserRoleId != null AND IsActive = TRUE
        ]) {
            roleIdToEmpRole.put(u.UserRoleId, u.Employee_Role__c);
        }
        
        // 3. Collect parent roles (stop at ASM)
        Set<Id> parentRoleIds = new Set<Id>();
        Set<Id> visited = new Set<Id>();
        Map<Id, Id> userIdToRoleIdMap = new Map<Id, Id>();
        
        for (User u : [
            SELECT Id, UserRoleId 
            FROM User 
            WHERE Id IN :startingOwnerIds AND IsActive = TRUE
        ]) {
            if (u.UserRoleId != null) {
                userIdToRoleIdMap.put(u.Id, u.UserRoleId);
                collectParentRoles(u.UserRoleId, allRoles, roleIdToEmpRole, parentRoleIds, visited);
            }
        }
        
        if (parentRoleIds.isEmpty()) return;
        
        // 4. Fetch upper users (ASM and above)
        List<User> upperUsers = [
            SELECT Id, UserRoleId 
            FROM User 
            WHERE UserRoleId IN :parentRoleIds AND IsActive = TRUE
        ];
        
        if (upperUsers.isEmpty()) return;
        
        Set<Id> upperUserIds = new Set<Id>();
        Map<Id, Id> upperUserIdToRoleId = new Map<Id, Id>();
        for (User u : upperUsers) {
            upperUserIds.add(u.Id);
            upperUserIdToRoleId.put(u.Id, u.UserRoleId);
        }
        
        // 5. For each upper user, collect subordinate roles and users
        Map<Id, Set<Id>> upperUserToSubUsers = new Map<Id, Set<Id>>();
        Set<Id> allSubUserIds = new Set<Id>();
        
        for (Id upperUserId : upperUserIds) {
            Id roleId = upperUserIdToRoleId.get(upperUserId);
            Set<Id> subRoles = getChildRoles(roleId, allRoles);
            subRoles.add(roleId); // include self role
            
            Set<Id> subUsers = new Set<Id>{ upperUserId };
            if (!subRoles.isEmpty()) {
                for (User u : [
                    SELECT Id, UserRoleId FROM User WHERE UserRoleId IN :subRoles AND IsActive = TRUE
                ]) {
                    subUsers.add(u.Id);
                }
            }
            upperUserToSubUsers.put(upperUserId, subUsers);
            allSubUserIds.addAll(subUsers);
        }
        
        if (allSubUserIds.isEmpty()) return;
        
        // 6. Fetch Retailer Accounts for sub users
        List<Account> retailerAccounts = [
            SELECT Id, OwnerId 
            FROM Account 
            WHERE OwnerId IN :allSubUserIds 
            AND RecordType.DeveloperName = 'Retailer'
        ];
        
        Map<Id, List<Account>> upperUserToRetailers = new Map<Id, List<Account>>();
        for (Account acc : retailerAccounts) {
            for (Id upperUserId : upperUserToSubUsers.keySet()) {
                if (upperUserToSubUsers.get(upperUserId).contains(acc.OwnerId)) {
                    if (!upperUserToRetailers.containsKey(upperUserId)) {
                        upperUserToRetailers.put(upperUserId, new List<Account>());
                    }
                    upperUserToRetailers.get(upperUserId).add(acc);
                }
            }
        }
        
        Set<Id> allRetailerIds = new Set<Id>();
        for (Account acc : retailerAccounts) allRetailerIds.add(acc.Id);
        
        // 7. Fetch new outlets created in given months & years
        List<Account> newOutlets = [
            SELECT Id, OwnerId 
            FROM Account
            WHERE OwnerId IN :allSubUserIds
            AND RecordType.DeveloperName = 'Retailer'
            AND CALENDAR_MONTH(CreatedDate) IN :months
            AND CALENDAR_YEAR(CreatedDate) IN :years
        ];
        
        Map<Id, Integer> upperUserToNewOutlets = new Map<Id, Integer>();
        for (Account acc : newOutlets) {
            for (Id upperUserId : upperUserToSubUsers.keySet()) {
                if (upperUserToSubUsers.get(upperUserId).contains(acc.OwnerId)) {
                    Integer count = upperUserToNewOutlets.containsKey(upperUserId) ? upperUserToNewOutlets.get(upperUserId) : 0;
                    upperUserToNewOutlets.put(upperUserId, count + 1);
                }
            }
        }
        
        // 8. Fetch Orders for these retailer accounts
        Decimal orderThreshold = Decimal.valueOf(System.Label.OrderValue300);
        List<Order__c> allOrders = [
            SELECT Id, Account__c 
            FROM Order__c
            WHERE RecordType.DeveloperName = 'Secondary_Order'
            AND Total_Order_Value__c > :orderThreshold
            AND Account__c IN :allRetailerIds
            AND CALENDAR_MONTH(CreatedDate) IN :months 
            AND CALENDAR_YEAR(CreatedDate) IN :years
        ];
        
        Map<Id, Integer> accountToOrderCount = new Map<Id, Integer>();
        for (Order__c o : allOrders) {
            Integer count = accountToOrderCount.containsKey(o.Account__c) ? accountToOrderCount.get(o.Account__c) : 0;
            accountToOrderCount.put(o.Account__c, count + 1);
        }
        
        // 9. Fetch Sales Targets
        List<Sales_Target__c> salesTargets = [
            SELECT Id, Assigned_To__c 
            FROM Sales_Target__c 
            WHERE RecordType.DeveloperName = 'Sales_Target_Month'
            AND Assigned_To__c IN :upperUserIds
            AND Year__c IN :convertYearsToString(years)
            AND Number_of_Month__c IN :months
        ];
        
        Map<Id, Sales_Target__c> userToTargetMap = new Map<Id, Sales_Target__c>();
        for (Sales_Target__c st : salesTargets) {
            userToTargetMap.put(st.Assigned_To__c, st);
        }
        
        // 10. Compute metrics and update targets
        List<Sales_Target__c> targetsToUpdate = new List<Sales_Target__c>();
        for (Id upperUserId : upperUserIds) {
            List<Account> accounts = upperUserToRetailers.get(upperUserId);
            if (accounts == null || accounts.isEmpty()) continue;
            
            Integer productiveCalls = 0;
            for (Account acc : accounts) {
                productiveCalls += accountToOrderCount.containsKey(acc.Id) ? accountToOrderCount.get(acc.Id) : 0;
            }
            
            Integer newOutletCount = upperUserToNewOutlets.containsKey(upperUserId) ? upperUserToNewOutlets.get(upperUserId) : 0;
            
            if (userToTargetMap.containsKey(upperUserId)) {
                Sales_Target__c target = userToTargetMap.get(upperUserId);
                target.Productive_Calls_Actual__c = productiveCalls;
                target.New_Outlet_Opened_Actual__c = newOutletCount;
                targetsToUpdate.add(target);
            }
        }
        
        if (!targetsToUpdate.isEmpty()) {
            update targetsToUpdate;
        }
    }
    
    // Collect parent roles until ASM
    private static void collectParentRoles(Id roleId, Map<Id, UserRole> allRoles, 
                                           Map<Id, String> roleIdToEmpRole, 
                                           Set<Id> result, Set<Id> visited) {
        if (roleId == null || visited.contains(roleId)) return;
        visited.add(roleId);
        
        UserRole role = allRoles.get(roleId);
        if (role != null && role.ParentRoleId != null) {
            String empRole = roleIdToEmpRole.get(role.ParentRoleId);
            if (empRole != null && empRole.equalsIgnoreCase('ASM')) {
                result.add(role.ParentRoleId); // stop at ASM
                return;
            }
            result.add(role.ParentRoleId);
            collectParentRoles(role.ParentRoleId, allRoles, roleIdToEmpRole, result, visited);
        }
    }
    
    private static Set<Id> getChildRoles(Id parentRoleId, Map<Id, UserRole> allRoles) {
        Set<Id> childRoles = new Set<Id>();
        for (UserRole role : allRoles.values()) {
            if (role.ParentRoleId == parentRoleId) {
                childRoles.add(role.Id);
                childRoles.addAll(getChildRoles(role.Id, allRoles));
            }
        }
        return childRoles;
    }
    
    private static List<String> convertYearsToString(Set<Integer> years) {
        List<String> result = new List<String>();
        for (Integer y : years) {
            result.add(String.valueOf(y));
        }
        return result;
    }
}