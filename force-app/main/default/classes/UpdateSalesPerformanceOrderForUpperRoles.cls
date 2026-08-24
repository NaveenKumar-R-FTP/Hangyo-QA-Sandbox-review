public class UpdateSalesPerformanceOrderForUpperRoles implements Queueable, Database.AllowsCallouts {
    
    private Set<Id> startingOwnerIds;
    private Set<Integer> months;
    private Set<Integer> years;
    
    public UpdateSalesPerformanceOrderForUpperRoles(Set<Id> ownerIds, Set<Integer> months, Set<Integer> years) {
        this.startingOwnerIds = ownerIds;
        this.months = months;
        this.years = years;
    }
    
    public void execute(QueueableContext context) {
        if (startingOwnerIds == null || startingOwnerIds.isEmpty()) return;
        
        // Fetch roles and users
        Map<Id, UserRole> allRoles = new Map<Id, UserRole>([SELECT Id, ParentRoleId FROM UserRole]);
        List<User> allUsers = [SELECT Id, UserRoleId, Employee_Role__c FROM User WHERE UserRoleId != null AND IsActive = TRUE];
        
        Map<Id, User> userMap = new Map<Id, User>(allUsers);
        Map<Id, List<User>> roleIdToUsersMap = new Map<Id, List<User>>();
        
        // Build Role → Users map
        for (User u : allUsers) {
            if (u.UserRoleId == null) continue;
            if (!roleIdToUsersMap.containsKey(u.UserRoleId)) {
                roleIdToUsersMap.put(u.UserRoleId, new List<User>());
            }
            roleIdToUsersMap.get(u.UserRoleId).add(u);
        }
        
        // Build RoleId → Employee_Role__c map
        Map<Id, String> roleIdToEmpRole = new Map<Id, String>();
        for (User u : allUsers) {
            if (u.UserRoleId != null && u.Employee_Role__c != null) {
                roleIdToEmpRole.put(u.UserRoleId, u.Employee_Role__c);
            }
        }
        
        // Collect parent roles up to ASM
        Set<Id> parentRoleIds = new Set<Id>();
        Set<Id> visited = new Set<Id>();
        for (Id ownerId : startingOwnerIds) {
            User u = userMap.get(ownerId);
            if (u != null && u.UserRoleId != null) {
                collectParentRoles(u.UserRoleId, allRoles, roleIdToEmpRole, parentRoleIds, visited);
            }
        }
        if (parentRoleIds.isEmpty()) return;
        
        // Fetch upper users (ASM or higher)
        List<User> upperUsers = new List<User>();
        Map<Id, Id> upperUserToRoleMap = new Map<Id, Id>();
        Set<Id> upperUserIds = new Set<Id>();
        
        for (User u : allUsers) {
            if (u.UserRoleId != null && parentRoleIds.contains(u.UserRoleId)) {
                upperUsers.add(u);
                upperUserIds.add(u.Id);
                upperUserToRoleMap.put(u.Id, u.UserRoleId);
            }
        }
        if (upperUserIds.isEmpty()) return;
        
        // Build hierarchy: Upper User → Subordinate Users (self + subordinates, excluding same role others)
        Map<Id, Set<Id>> upperUserToSubordinateUsers = new Map<Id, Set<Id>>();
        
        for (Id upperUserId : upperUserIds) {
            Set<Id> subordinateUsers = new Set<Id>();
            Id currentRoleId = upperUserToRoleMap.get(upperUserId);
            
            // Get all child roles
            Set<Id> subRoles = getOnlySubordinateRoleIds(currentRoleId, allRoles);
            
            // Add users from child roles
            for (Id roleId : subRoles) {
                if (roleIdToUsersMap.containsKey(roleId)) {
                    for (User u : roleIdToUsersMap.get(roleId)) {
                        subordinateUsers.add(u.Id);
                    }
                }
            }
            
            // Add self explicitly
            subordinateUsers.add(upperUserId);
            
            upperUserToSubordinateUsers.put(upperUserId, subordinateUsers);
        }
        
        // Fetch Distributor Accounts
        List<Account> distributorAccounts = [
            SELECT Id, OwnerId, CreatedDate FROM Account
            WHERE RecordType.DeveloperName = 'Distributor'
            AND OwnerId IN :allSubordinateUsers(upperUserToSubordinateUsers)
        ];
        
        // Fetch Retailer Accounts created in selected months/years
        List<Account> newOutletsAccounts = [
            SELECT Id, OwnerId, CreatedDate FROM Account
            WHERE OwnerId IN :allSubordinateUsers(upperUserToSubordinateUsers)
            AND RecordType.DeveloperName = 'Retailer'
            AND CALENDAR_MONTH(CreatedDate) IN :months
            AND CALENDAR_YEAR(CreatedDate) IN :years
        ];
        
        // Map Accounts by Owner
        Map<Id, List<Account>> ownerToAccounts = new Map<Id, List<Account>>();
        Map<Id, List<Account>> ownerToNewAccounts = new Map<Id, List<Account>>();
        Set<Id> accountIds = new Set<Id>();
        
        for (Account acc : distributorAccounts) {
            accountIds.add(acc.Id);
            
            if (!ownerToAccounts.containsKey(acc.OwnerId)) {
                ownerToAccounts.put(acc.OwnerId, new List<Account>());
            }
            ownerToAccounts.get(acc.OwnerId).add(acc);
            
            if (months.contains(acc.CreatedDate.month()) && years.contains(acc.CreatedDate.year())) {
                if (!ownerToNewAccounts.containsKey(acc.OwnerId)) {
                    ownerToNewAccounts.put(acc.OwnerId, new List<Account>());
                }
                ownerToNewAccounts.get(acc.OwnerId).add(acc);
            }
        }
        if (accountIds.isEmpty()) return;
        
        // Fetch Primary Orders
        List<Order__c> allOrders = [
            SELECT Id, AccountId__c, Total_Order_Value__c, Line_Item_Volume__c 
            FROM Order__c 
            WHERE RecordType.DeveloperName = 'Primary_Order'
            AND AccountId__c IN :accountIds
            AND CALENDAR_MONTH(CreatedDate) IN :months
            AND CALENDAR_YEAR(CreatedDate) IN :years
        ];
        
        // Map Orders by Account
        Map<Id, List<Order__c>> accountToOrdersMap = new Map<Id, List<Order__c>>();
        for (Order__c ord : allOrders) {
            if (ord.AccountId__c == null) continue;
            if (!accountToOrdersMap.containsKey(ord.AccountId__c)) {
                accountToOrdersMap.put(ord.AccountId__c, new List<Order__c>());
            }
            accountToOrdersMap.get(ord.AccountId__c).add(ord);
        }
        
        // Fetch Sales Targets for upper users
        List<Sales_Target__c> salesTargets = [
            SELECT Id, Assigned_To__c, Number_of_Month__c, Year__c,
            Primary_Sales_Actual__c, Litre_Sold_Actual__c, New_Outlet_Opened_Actual__c
            FROM Sales_Target__c
            WHERE RecordType.DeveloperName = 'Sales_Target_Month' AND Assigned_To__c IN :upperUserIds
            AND Year__c IN :convertYearsToString(years) 
            AND Number_of_Month__c IN :months
        ];
        
        Map<Id, Sales_Target__c> userToTargetMap = new Map<Id, Sales_Target__c>();
        for (Sales_Target__c st : salesTargets) {
            userToTargetMap.put(st.Assigned_To__c, st);
        }
        
        // Build upper user → accounts map
        Map<Id, Set<Id>> upperUserToAccounts = new Map<Id, Set<Id>>();
        for (Id upperUserId : upperUserIds) {
            Set<Id> accIds = new Set<Id>();
            for (Id subUserId : upperUserToSubordinateUsers.get(upperUserId)) {
                if (ownerToAccounts.containsKey(subUserId)) {
                    for (Account acc : ownerToAccounts.get(subUserId)) {
                        accIds.add(acc.Id);
                    }
                }
            }
            upperUserToAccounts.put(upperUserId, accIds);
        }
        
        // Calculate order totals per account
        Map<Id, Map<String, Decimal>> accountToOrderTotals = new Map<Id, Map<String, Decimal>>();
        for (Id accId : accountToOrdersMap.keySet()) {
            Decimal totalSales = 0;
            Decimal totalLitres = 0;
            for (Order__c ord : accountToOrdersMap.get(accId)) {
                totalSales += (ord.Total_Order_Value__c != null ? ord.Total_Order_Value__c : 0);
                totalLitres += (ord.Line_Item_Volume__c != null ? ord.Line_Item_Volume__c : 0);
            }
            accountToOrderTotals.put(accId, new Map<String, Decimal>{
                'sales' => totalSales,
                'litres' => totalLitres
            });
        }
        
        // Update Sales Targets
        List<Sales_Target__c> targetsToUpdate = new List<Sales_Target__c>();
        for (Id upperUserId : upperUserIds) {
            Decimal primarySalesActual = 0;
            Decimal litreSoldActual = 0;
            Integer newOutlets = 0;
            
            if (upperUserToAccounts.containsKey(upperUserId)) {
                for (Id accId : upperUserToAccounts.get(upperUserId)) {
                    if (accountToOrderTotals.containsKey(accId)) {
                        Map<String, Decimal> totals = accountToOrderTotals.get(accId);
                        primarySalesActual += totals.get('sales');
                        litreSoldActual += totals.get('litres');
                    }
                }
            }
            
            for (Account acc : newOutletsAccounts) {
                if (upperUserToSubordinateUsers.get(upperUserId).contains(acc.OwnerId)) {
                    newOutlets++;
                }
            }
            
            if (userToTargetMap.containsKey(upperUserId)) {
                Sales_Target__c target = userToTargetMap.get(upperUserId);
                target.Primary_Sales_Actual__c = primarySalesActual;
                target.Litre_Sold_Actual__c = litreSoldActual;
                target.New_Outlet_Opened_Actual__c = newOutlets;
                targetsToUpdate.add(target);
            }
        }
        
        if (!targetsToUpdate.isEmpty()) {
            update targetsToUpdate;
        }
    }
    
    // Stop recursion at ASM
    private static void collectParentRoles(Id roleId, Map<Id, UserRole> allRoles, Map<Id, String> roleIdToEmpRole, Set<Id> result, Set<Id> visited) {
        if (roleId == null || visited.contains(roleId)) return;
        visited.add(roleId);
        
        UserRole role = allRoles.get(roleId);
        if (role != null && role.ParentRoleId != null) {
            String empRole = roleIdToEmpRole.get(role.ParentRoleId);
            if (empRole != null && empRole.equalsIgnoreCase('ASM')) {
                result.add(role.ParentRoleId);
                return; // stop here
            }
            result.add(role.ParentRoleId);
            collectParentRoles(role.ParentRoleId, allRoles, roleIdToEmpRole, result, visited);
        }
    }
    
    private static Set<Id> getOnlySubordinateRoleIds(Id parentRoleId, Map<Id, UserRole> allRoles) {
        Set<Id> childRoleIds = new Set<Id>();
        if (parentRoleId == null) return childRoleIds;
        collectSubRoles(parentRoleId, allRoles, childRoleIds);
        return childRoleIds;
    }
    
    private static void collectSubRoles(Id parentId, Map<Id, UserRole> allRoles, Set<Id> result) {
        for (UserRole role : allRoles.values()) {
            if (role.ParentRoleId == parentId) {
                result.add(role.Id);
                collectSubRoles(role.Id, allRoles, result);
            }
        }
    }
    
    private static Set<Id> allSubordinateUsers(Map<Id, Set<Id>> mapData) {
        Set<Id> allUsers = new Set<Id>();
        for (Set<Id> users : mapData.values()) {
            allUsers.addAll(users);
        }
        return allUsers;
    }
    
    private static List<String> convertYearsToString(Set<Integer> years) {
        List<String> result = new List<String>();
        for (Integer y : years) {
            result.add(String.valueOf(y));
        }
        return result;
    }
}