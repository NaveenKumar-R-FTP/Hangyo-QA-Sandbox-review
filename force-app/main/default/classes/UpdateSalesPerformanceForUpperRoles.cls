public class UpdateSalesPerformanceForUpperRoles implements Queueable, Database.AllowsCallouts {

    private Set<Id> startingOwnerIds;
    private Set<Integer> months;
    private Set<Integer> years;

    public UpdateSalesPerformanceForUpperRoles(Set<Id> ownerIds, Set<Integer> months, Set<Integer> years) {
        this.startingOwnerIds = ownerIds;
        this.months = months;
        this.years = years;
    }

    public void execute(QueueableContext context) {
        System.debug('=== STARTING Queueable: UpdateSalesPerformanceForUpperRoles ===');

        if (startingOwnerIds == null || startingOwnerIds.isEmpty()) return;

        // 1. Fetch starting users with roles
        Map<Id, User> startingUsers = new Map<Id, User>(
            [SELECT Id, UserRoleId, Employee_Role__c 
             FROM User 
             WHERE Id IN :startingOwnerIds AND UserRoleId != null AND IsActive = TRUE]
        );
        if (startingUsers.isEmpty()) return;

        // Fetch all roles once
        Map<Id, UserRole> allRoles = new Map<Id, UserRole>(
            [SELECT Id, ParentRoleId FROM UserRole]
        );

        // Build Role → Employee_Role__c map
        Map<Id, String> roleIdToEmpRole = new Map<Id, String>();
        for (User u : [SELECT Id, UserRoleId, Employee_Role__c FROM User WHERE UserRoleId != null AND IsActive = TRUE]) {
            roleIdToEmpRole.put(u.UserRoleId, u.Employee_Role__c);
        }

        // 2. Collect all parent roles recursively but stop if parent role = ASM
        Set<Id> parentRoleIds = new Set<Id>();
        Set<Id> visited = new Set<Id>();
        for (User u : startingUsers.values()) {
            collectParentRoles(u.UserRoleId, allRoles, roleIdToEmpRole, parentRoleIds, visited);
        }

        if (parentRoleIds.isEmpty()) return;

        // 3. Fetch upper-level users
        List<User> upperUsers = [
            SELECT Id, UserRoleId FROM User WHERE UserRoleId IN :parentRoleIds AND IsActive = TRUE
        ];
        if (upperUsers.isEmpty()) return;

        Set<Id> upperUserIds = new Set<Id>();
        for (User u : upperUsers) upperUserIds.add(u.Id);

        // 4. Build user hierarchy for each upper user (self + subordinates)
        Map<Id, Set<Id>> upperUserToSubUsers = new Map<Id, Set<Id>>();
        Set<Id> allSubUserIds = new Set<Id>();

        for (User upperUser : upperUsers) {
            Set<Id> userIds = new Set<Id>();
            userIds.add(upperUser.Id); // include self
            Set<Id> subRoleIds = getChildRoles(upperUser.UserRoleId, allRoles);
            if (!subRoleIds.isEmpty()) {
                for (User u : [SELECT Id, UserRoleId FROM User WHERE UserRoleId IN :subRoleIds AND IsActive = TRUE]) {
                    userIds.add(u.Id);
                }
            }
            upperUserToSubUsers.put(upperUser.Id, userIds);
            allSubUserIds.addAll(userIds);
        }

        if (allSubUserIds.isEmpty()) return;

        // 5. Fetch Retailer Accounts owned by these users
        List<Account> retailerAccounts = [
            SELECT Id, OwnerId FROM Account
            WHERE OwnerId IN :allSubUserIds
            AND RecordType.DeveloperName = 'Retailer'
        ];

        Map<Id, Set<Id>> userToRetailerAccs = new Map<Id, Set<Id>>();
        Set<Id> allRetailerAccIds = new Set<Id>();
        for (Account acc : retailerAccounts) {
            if (!userToRetailerAccs.containsKey(acc.OwnerId)) {
                userToRetailerAccs.put(acc.OwnerId, new Set<Id>());
            }
            userToRetailerAccs.get(acc.OwnerId).add(acc.Id);
            allRetailerAccIds.add(acc.Id);
        }

        if (allRetailerAccIds.isEmpty()) return;

        // 6. Fetch Retailers with Assets
        Set<Id> retailerWithAssets = new Set<Id>();
        for (Asset__c asset : [
            SELECT Retailer_Account__c FROM Asset__c WHERE Retailer_Account__c IN :allRetailerAccIds
        ]) {
            retailerWithAssets.add(asset.Retailer_Account__c);
        }

        // 7. Fetch Invoices for given months and years
        List<Invoice__c> allInvoices = [
            SELECT Id, Retailer_Account__c, Invoice_Amount__c, 
                   Invoice_Line_Item_Total_Amount__c, Number_of_Invoice_Line_Items__c
            FROM Invoice__c
            WHERE RecordType.DeveloperName = 'Secondary_Invoice'
            AND Retailer_Account__c IN :allRetailerAccIds
            AND Status__c IN ('Confirmed', 'Delivered')
            AND CALENDAR_MONTH(CreatedDate) IN :months
            AND CALENDAR_YEAR(CreatedDate) IN :years
        ];

        Map<Id, List<Invoice__c>> accountToInvoices = new Map<Id, List<Invoice__c>>();
        for (Invoice__c inv : allInvoices) {
            if (!accountToInvoices.containsKey(inv.Retailer_Account__c)) {
                accountToInvoices.put(inv.Retailer_Account__c, new List<Invoice__c>());
            }
            accountToInvoices.get(inv.Retailer_Account__c).add(inv);
        }

        // 8. Fetch Sales Targets for upper users
        Map<Id, Sales_Target__c> userToTarget = new Map<Id, Sales_Target__c>();
        for (Sales_Target__c t : [
            SELECT Id, Assigned_To__c FROM Sales_Target__c
            WHERE RecordType.DeveloperName = 'Sales_Target_Month'
            AND Assigned_To__c IN :upperUserIds
            AND Year__c IN :convertYearsToString(years)
            AND Number_of_Month__c IN :months
        ]) {
            userToTarget.put(t.Assigned_To__c, t);
        }

        // 9. Compute KPIs and update
        List<Sales_Target__c> targetsToUpdate = new List<Sales_Target__c>();

        for (User upperUser : upperUsers) {
            Set<Id> accIds = new Set<Id>();
            if (upperUserToSubUsers.containsKey(upperUser.Id)) {
                for (Id subUserId : upperUserToSubUsers.get(upperUser.Id)) {
                    if (userToRetailerAccs.containsKey(subUserId)) {
                        accIds.addAll(userToRetailerAccs.get(subUserId));
                    }
                }
            }

            if (accIds.isEmpty()) continue;

            Integer activeAssetRetailerCount = 0;
            Decimal totalLineItems = 0, totalLineAmount = 0, totalInvoiceAmount = 0;
            Integer relevantInvoiceCount = 0, invoiceAbove3000Count = 0;

            for (Id accId : accIds) {
                if (retailerWithAssets.contains(accId)) {
                    activeAssetRetailerCount++;
                }
                if (accountToInvoices.containsKey(accId)) {
                    for (Invoice__c inv : accountToInvoices.get(accId)) {
                        relevantInvoiceCount++;
                        totalLineItems += (inv.Number_of_Invoice_Line_Items__c != null) ? inv.Number_of_Invoice_Line_Items__c : 0;
                        totalLineAmount += (inv.Invoice_Line_Item_Total_Amount__c != null) ? inv.Invoice_Line_Item_Total_Amount__c : 0;
                        totalInvoiceAmount += (inv.Invoice_Amount__c != null) ? inv.Invoice_Amount__c : 0;
                        if (inv.Invoice_Amount__c != null && inv.Invoice_Amount__c > 3000) {
                            invoiceAbove3000Count++;
                        }
                    }
                }
            }

            Decimal totalDFBilled = (invoiceAbove3000Count > 0 && activeAssetRetailerCount > 0)
                ? ((Decimal)invoiceAbove3000Count / activeAssetRetailerCount) * 100 : 0;

            Decimal averageLineItems = (relevantInvoiceCount > 0)
                ? totalLineItems / relevantInvoiceCount : 0;

            Decimal mrpSalesActual20Rs = (totalInvoiceAmount > 0)
                ? (totalLineAmount / totalInvoiceAmount) * 100 : 0;

            Decimal totalDFThroughput = (totalInvoiceAmount != null && activeAssetRetailerCount > 0)
                ? (totalInvoiceAmount / activeAssetRetailerCount) * 100 : 0;

            if (userToTarget.containsKey(upperUser.Id)) {
                Sales_Target__c target = userToTarget.get(upperUser.Id);
                target.Total_DF_Billed_Actual__c = totalDFBilled;
                target.LPSC_total_orders_of_bills_Actual__c = averageLineItems;
                target.X20Rs_N_MRP_Sales_Actual__c = mrpSalesActual20Rs;
                target.Secondary_Sales_Actual__c = totalInvoiceAmount;
                target.Total_DF_Throughput_Actual__c = totalDFThroughput;
                targetsToUpdate.add(target);
            }
        }

        if (!targetsToUpdate.isEmpty()) {
            update targetsToUpdate;
        }

        System.debug('=== END Queueable: UpdateSalesPerformanceForUpperRoles ===');
    }

    // Stops recursion at ASM
    private static void collectParentRoles(Id roleId, Map<Id, UserRole> allRoles, 
                                           Map<Id, String> roleIdToEmpRole, 
                                           Set<Id> result, Set<Id> visited) {
        if (roleId == null || visited.contains(roleId)) return;
        visited.add(roleId);

        UserRole role = allRoles.get(roleId);
        if (role != null && role.ParentRoleId != null) {
            String empRole = roleIdToEmpRole.get(role.ParentRoleId);
            if (empRole != null && empRole.equalsIgnoreCase('ASM')) {
                result.add(role.ParentRoleId);
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