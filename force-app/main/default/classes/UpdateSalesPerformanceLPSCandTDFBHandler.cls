public class UpdateSalesPerformanceLPSCandTDFBHandler {
    
    public static void updateSalesPerformance(List<Invoice__c> invoices) {
        if (invoices == null || invoices.isEmpty()) return;
        
        // Collect Retailer Accounts & Date Ranges
        Set<Id> retailerAccountIds = new Set<Id>();
        Set<Integer> months = new Set<Integer>();
        Set<Integer> years = new Set<Integer>();
        
        for (Invoice__c inv : invoices) {
            if (inv.Retailer_Account__c != null) {
                retailerAccountIds.add(inv.Retailer_Account__c);
                months.add(inv.CreatedDate.month());
                years.add(inv.CreatedDate.year());
            }
        }
        
        // Fetch Retailer Accounts with Owner
        Map<Id, Id> retailerAccountToOwner = new Map<Id, Id>();
        Set<Id> invoiceOwnerIds = new Set<Id>();
        
        for (Account acc : [
            SELECT Id, OwnerId FROM Account WHERE Id IN :retailerAccountIds
        ]) {
            retailerAccountToOwner.put(acc.Id, acc.OwnerId);
            invoiceOwnerIds.add(acc.OwnerId);
        }
        
        // Fetch Owner Users with their Role
        Map<Id, User> ownerUsers = new Map<Id, User>(
            [SELECT Id, UserRoleId FROM User WHERE Id IN :invoiceOwnerIds AND IsActive = TRUE]
        );
        
        // Fetch all Roles
        Map<Id, UserRole> allRoles = new Map<Id, UserRole>(
            [SELECT Id, ParentRoleId FROM UserRole]
        );
        
        // Build Role -> SubRoles map (non-recursive using queue)
        Map<Id, Set<Id>> roleToSubRoles = new Map<Id, Set<Id>>();
        for (Id roleId : allRoles.keySet()) roleToSubRoles.put(roleId, new Set<Id>());
        
        for (UserRole role : allRoles.values()) {
            if (role.ParentRoleId != null && roleToSubRoles.containsKey(role.ParentRoleId)) {
                roleToSubRoles.get(role.ParentRoleId).add(role.Id);
            }
        }
        
        // Collect Owner → Roles (self + subordinates)
        Map<Id, Set<Id>> ownerToAllRoles = new Map<Id, Set<Id>>();
        for (User u : ownerUsers.values()) {
            if (u.UserRoleId == null) continue;
            Set<Id> roles = new Set<Id>{u.UserRoleId};
                List<Id> queue = new List<Id>{u.UserRoleId};
                    while (!queue.isEmpty()) {
                        Id current = queue.remove(0);
                        if (roleToSubRoles.containsKey(current)) {
                            for (Id subRoleId : roleToSubRoles.get(current)) {
                                if (!roles.contains(subRoleId)) {
                                    roles.add(subRoleId);
                                    queue.add(subRoleId);
                                }
                            }
                        }
                    }
            ownerToAllRoles.put(u.Id, roles);
        }
        
        // Collect all roles for one SOQL
        Set<Id> allRolesNeeded = new Set<Id>();
        for (Set<Id> rSet : ownerToAllRoles.values()) allRolesNeeded.addAll(rSet);
        
        // Fetch Users for these roles (subordinates + owner only)
        Map<Id, Set<Id>> roleToUsers = new Map<Id, Set<Id>>();
        for (User u : [
            SELECT Id, UserRoleId FROM User WHERE UserRoleId IN :allRolesNeeded AND IsActive = TRUE
        ]) {
            if (!roleToUsers.containsKey(u.UserRoleId)) {
                roleToUsers.put(u.UserRoleId, new Set<Id>());
            }
            roleToUsers.get(u.UserRoleId).add(u.Id);
        }
        
        // Build Owner → All Users (self + subordinates, exclude peers)
        Map<Id, Set<Id>> ownerToUsers = new Map<Id, Set<Id>>();
        for (Id ownerId : ownerToAllRoles.keySet()) {
            Set<Id> userSet = new Set<Id>{ownerId}; // include self
                Id ownerRoleId = ownerUsers.get(ownerId).UserRoleId;
            for (Id roleId : ownerToAllRoles.get(ownerId)) {
                // Exclude the owner's own role (so peers are NOT added)
                if (roleId != ownerRoleId && roleToUsers.containsKey(roleId)) {
                    userSet.addAll(roleToUsers.get(roleId));
                }
            }
            ownerToUsers.put(ownerId, userSet);
        }
        
        // Collect all relevant User IDs
        Set<Id> allUserIds = new Set<Id>();
        for (Set<Id> s : ownerToUsers.values()) allUserIds.addAll(s);
        
        // Fetch Retailer Accounts owned by these users
        List<Account> relevantAccounts = [
            SELECT Id, OwnerId FROM Account
            WHERE RecordType.DeveloperName = 'Retailer'
            AND OwnerId IN :allUserIds
        ];
        
        // Map Owner → Accounts and Account → Top Owner
        Map<Id, Set<Id>> ownerToAccounts = new Map<Id, Set<Id>>();
        Map<Id, Id> accountToTopOwner = new Map<Id, Id>();
        for (Account acc : relevantAccounts) {
            for (Id ownerId : ownerToUsers.keySet()) {
                if (ownerToUsers.get(ownerId).contains(acc.OwnerId)) {
                    if (!ownerToAccounts.containsKey(ownerId)) {
                        ownerToAccounts.put(ownerId, new Set<Id>());
                    }
                    ownerToAccounts.get(ownerId).add(acc.Id);
                    accountToTopOwner.put(acc.Id, ownerId);
                    break;
                }
            }
        }
        
        // Fetch Secondary Invoices
        List<Invoice__c> secondaryInvoices = [
            SELECT Id, Retailer_Account__c, Invoice_Amount__c, Invoice_Line_Item_Total_Amount__c, 
            Number_of_Invoice_Line_Items__c, CreatedDate
            FROM Invoice__c
            WHERE RecordType.DeveloperName = 'Secondary_Invoice'
            AND Status__c IN ('Confirmed', 'Delivered')
            AND Retailer_Account__c IN :accountToTopOwner.keySet()
            AND CALENDAR_MONTH(CreatedDate) IN :months
            AND CALENDAR_YEAR(CreatedDate) IN :years
        ];
        
        Decimal threshold = 3000; // Or System.Label
        
        // Group invoices by Owner-Month-Year
        Map<String, List<Invoice__c>> allInvoicesMap = new Map<String, List<Invoice__c>>();
        Map<String, List<Invoice__c>> invoicesAboveThreshold = new Map<String, List<Invoice__c>>();
        
        for (Invoice__c inv : secondaryInvoices) {
            Id topOwner = accountToTopOwner.get(inv.Retailer_Account__c);
            String key = topOwner + '_' + inv.CreatedDate.month() + '_' + inv.CreatedDate.year();
            
            if (!allInvoicesMap.containsKey(key)) allInvoicesMap.put(key, new List<Invoice__c>());
            allInvoicesMap.get(key).add(inv);
            
            if (inv.Invoice_Amount__c != null && inv.Invoice_Amount__c > threshold) {
                if (!invoicesAboveThreshold.containsKey(key)) invoicesAboveThreshold.put(key, new List<Invoice__c>());
                invoicesAboveThreshold.get(key).add(inv);
            }
        }
        
        // Fetch retailers with assets for denominator
        Map<Id, Set<Id>> ownerToAssetRetailers = new Map<Id, Set<Id>>();
        for (Account acc : [
            SELECT Id FROM Account
            WHERE Id IN (SELECT Retailer_Account__c FROM Asset__c)
            AND Id IN :accountToTopOwner.keySet()
        ]) {
            Id topOwner = accountToTopOwner.get(acc.Id);
            if (!ownerToAssetRetailers.containsKey(topOwner)) ownerToAssetRetailers.put(topOwner, new Set<Id>());
            ownerToAssetRetailers.get(topOwner).add(acc.Id);
        }
        
        // Fetch Sales Targets
        Map<String, Sales_Target__c> salesTargetMap = new Map<String, Sales_Target__c>();
        for (Sales_Target__c st : [
            SELECT Id, Assigned_To__c, Number_of_Month__c, Year__c
            FROM Sales_Target__c
            WHERE RecordType.DeveloperName = 'Sales_Target_Month'
            AND Assigned_To__c IN :ownerToUsers.keySet()
            AND Number_of_Month__c IN :months
            AND Year__c IN :convertYearsToString(years)
        ]) {
            String key = st.Assigned_To__c + '_' + st.Number_of_Month__c + '_' + st.Year__c;
            salesTargetMap.put(key, st);
        }
        
        // Calculate KPIs
        List<Sales_Target__c> updates = new List<Sales_Target__c>();
        for (String key : allInvoicesMap.keySet()) {
            List<Invoice__c> invList = allInvoicesMap.get(key);
            List<Invoice__c> invAbove = invoicesAboveThreshold.get(key);
            
            Id ownerId = (Id) key.split('_')[0];
            Integer accCount = ownerToAssetRetailers.containsKey(ownerId) ? ownerToAssetRetailers.get(ownerId).size() : 0;
            
            Decimal totalAmt = 0, totalItems = 0, totalLineAmt = 0;
            for (Invoice__c inv : invList) {
                totalAmt += inv.Invoice_Amount__c != null ? inv.Invoice_Amount__c : 0;
                totalItems += inv.Number_of_Invoice_Line_Items__c != null ? inv.Number_of_Invoice_Line_Items__c : 0;
                totalLineAmt += inv.Invoice_Line_Item_Total_Amount__c != null ? inv.Invoice_Line_Item_Total_Amount__c : 0;
            }
            
            Decimal avgItems = invList.size() > 0 ? totalItems / invList.size() : 0;
            Decimal mrpSales = totalAmt > 0 ? (totalLineAmt / totalAmt) * 100 : 0;
            Decimal throughput = (totalAmt > 0 && accCount > 0) ? (totalAmt / accCount) * 100 : 0;
            Decimal billed = (invAbove != null && accCount > 0) ? (Decimal.valueOf(invAbove.size()) / accCount) * 100 : 0;
            
            Sales_Target__c st = salesTargetMap.get(key);
            if (st != null) {
                st.Total_DF_Billed_Actual__c = billed;
                st.LPSC_total_orders_of_bills_Actual__c = avgItems;
                st.X20Rs_N_MRP_Sales_Actual__c = mrpSales;
                st.Secondary_Sales_Actual__c = totalAmt;
                st.Total_DF_Throughput_Actual__c = throughput;
                updates.add(st);
            }
        }
        
        if (!updates.isEmpty()) {
            update updates;
        }
        
        // Enqueue upper role job
        if (!ownerToUsers.isEmpty()) {
            System.enqueueJob(new UpdateSalesPerformanceForUpperRoles(ownerToUsers.keySet(), months, years));
        }
    }
    
    private static List<String> convertYearsToString(Set<Integer> years) {
        List<String> res = new List<String>();
        for (Integer y : years) res.add(String.valueOf(y));
        return res;
    }
}