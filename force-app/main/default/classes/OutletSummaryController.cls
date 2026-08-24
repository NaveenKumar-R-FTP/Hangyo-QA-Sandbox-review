public with sharing class OutletSummaryController {

    // ========================================================================
    // GLOBAL STATIC CACHE (Loaded once per transaction)
    // ========================================================================
    private static Map<Id, Id> GLOBAL_userRoleMap;                     // UserId → RoleId
    private static Map<Id, Set<Id>> GLOBAL_roleToUserIds;              // RoleId → UserIds
    private static Map<Id, Set<Id>> GLOBAL_parentRoleToChildRoles;     // ParentRole → ChildRoles
    
    // RecordType cache
    private static Map<String, Id> RECORD_TYPE_CACHE;

    // ========================================================================
    // SUMMARY METRICS CLASS
    // ========================================================================
    public class SummaryMetrics {
        @AuraEnabled public Integer distributors = 0;
        @AuraEnabled public Integer beats = 0;
        @AuraEnabled public Integer outlets = 0;
        @AuraEnabled public Integer outletPlanned = 0;
        @AuraEnabled public Integer upc = 0;
        @AuraEnabled public Integer utc = 0;
        @AuraEnabled public Integer totalTC = 0;
        @AuraEnabled public Integer productiveCalls = 0;
        @AuraEnabled public Integer zeroOrderCount = 0;
        @AuraEnabled public Decimal coveragePct = 0;
        @AuraEnabled public Decimal productivity = 0;
        @AuraEnabled public Decimal netValue = 0;
    }

    // ========================================================================
    // HELPER CLASS FOR HIERARCHY DATA
    // ========================================================================
    public class HierarchyData {
        @AuraEnabled public Map<String, Object> currentUser;
        @AuraEnabled public List<Map<String, Object>> directReports;
    }

    // ========================================================================
    // DATE RANGE HELPERS
    // ========================================================================
    private static Date getStartDate(String periodType) {
        Date endDate = Date.today();
        if (periodType == 'MTD') {
            return Date.newInstance(endDate.year(), endDate.month(), 1);
        } else {
            return endDate; // FTD
        }
    }

    private static Date getEndDate() {
        return Date.today();
    }

    private static Datetime toStartOfDayDT(Date d) {
        return Datetime.newInstance(d.year(), d.month(), d.day(), 0, 0, 0);
    }

    private static Datetime toEndOfDayDT(Date d) {
        return Datetime.newInstance(d.year(), d.month(), d.day(), 23, 59, 59);
    }

    // ========================================================================
    // INITIALIZE CACHE METHODS
    // ========================================================================
    private static void initGlobalCaches() {
        if (GLOBAL_userRoleMap == null) {
            GLOBAL_userRoleMap = new Map<Id, Id>();
            GLOBAL_roleToUserIds = new Map<Id, Set<Id>>();
            GLOBAL_parentRoleToChildRoles = new Map<Id, Set<Id>>();

            // Load all active users with roles (ONE QUERY)
            for (User u : [
                SELECT Id, UserRoleId
                FROM User
                WHERE IsActive = true
                AND UserType = 'Standard'
                LIMIT 10000
            ]) {
                if (u.UserRoleId != null) {
                    GLOBAL_userRoleMap.put(u.Id, u.UserRoleId);

                    if (!GLOBAL_roleToUserIds.containsKey(u.UserRoleId)) {
                        GLOBAL_roleToUserIds.put(u.UserRoleId, new Set<Id>());
                    }
                    GLOBAL_roleToUserIds.get(u.UserRoleId).add(u.Id);
                }
            }

            // Load entire role hierarchy (ONE QUERY)
            for (UserRole r : [
                SELECT Id, ParentRoleId
                FROM UserRole
                WHERE ParentRoleId != null
                LIMIT 10000
            ]) {
                if (!GLOBAL_parentRoleToChildRoles.containsKey(r.ParentRoleId)) {
                    GLOBAL_parentRoleToChildRoles.put(r.ParentRoleId, new Set<Id>());
                }
                GLOBAL_parentRoleToChildRoles.get(r.ParentRoleId).add(r.Id);
            }
        }
        
        // Initialize RecordType cache
        if (RECORD_TYPE_CACHE == null) {
            RECORD_TYPE_CACHE = new Map<String, Id>();
            for (RecordType r : [
                SELECT Id, DeveloperName, SObjectType 
                FROM RecordType 
                WHERE SObjectType = 'Account'
                LIMIT 50
            ]) {
                RECORD_TYPE_CACHE.put(r.DeveloperName, r.Id);
            }
        }
    }

    // ========================================================================
    // BULK ROLE-HIERARCHY SUBORDINATES
    // ========================================================================
    private static void collectAllSubordinateIdsBulk(Id userId, Set<Id> allUserIds) {
        if (userId == null) return;

        // Initialize caches
        initGlobalCaches();

        // Get User Role
        Id parentRoleId = GLOBAL_userRoleMap.get(userId);
        if (parentRoleId == null) return;

        // BFS Through Child Roles
        Set<Id> visited = new Set<Id>();
        List<Id> queue = new List<Id>();

        if (GLOBAL_parentRoleToChildRoles.containsKey(parentRoleId)) {
            queue.addAll(GLOBAL_parentRoleToChildRoles.get(parentRoleId));
        }

        while (!queue.isEmpty()) {
            Id roleId = queue.remove(0);
            if (visited.contains(roleId)) continue;

            visited.add(roleId);

            // Add users in this role
            if (GLOBAL_roleToUserIds.containsKey(roleId)) {
                allUserIds.addAll(GLOBAL_roleToUserIds.get(roleId));
            }

            // Add deeper roles
            if (GLOBAL_parentRoleToChildRoles.containsKey(roleId)) {
                queue.addAll(GLOBAL_parentRoleToChildRoles.get(roleId));
            }
        }
    }

    // ========================================================================
    // OUTLET SUMMARY (FTD / MTD) - SINGLE USER - OPTIMIZED
    // ========================================================================
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getOutletSummary(Id userId, String periodType) {
        if (userId == null) userId = UserInfo.getUserId();

        Date startDate = getStartDate(periodType);
        Date endDate = getEndDate();
        Datetime startDT = toStartOfDayDT(startDate);
        Datetime endDT = toEndOfDayDT(endDate);

        // Get all users in role hierarchy
        Set<Id> users = new Set<Id>();
        users.add(userId);
        collectAllSubordinateIdsBulk(userId, users);

        // Get Total TC - Fixed: Use Checked_In_Time__c instead of Checked_In_Location__c
        Integer totalTC = 0;
        for (AggregateResult ar : [
            SELECT COUNT(Id) tcCount
            FROM Visit_Task__c
            WHERE Visitor_Name__c IN :users
            AND Checked_In_Time__c != NULL
            AND Checked_In_Time__c >= :startDT
            AND Checked_In_Time__c <= :endDT
            GROUP BY Visitor_Name__c
        ]) {
            totalTC += (Integer)ar.get('tcCount');
        }

        // Get Productive Calls (UPC)
        Integer upc = 0;
        for (AggregateResult ar : [
            SELECT COUNT(Id) upcCount
            FROM Visit_Task__c
            WHERE Visitor_Name__c IN :users
            AND Task_Planned_Date__c >= :startDate
            AND Task_Planned_Date__c <= :endDate
            AND Id IN (
                SELECT Visit_Task__c 
                FROM Order__c 
                WHERE EffectiveDate__c >= :startDate 
                AND EffectiveDate__c <= :endDate
            )
            GROUP BY Visitor_Name__c
        ]) {
            upc += (Integer)ar.get('upcCount');
        }

        // Get Productive Calls (with check-in time)
        Integer productiveCalls = 0;
        for (AggregateResult ar : [
            SELECT COUNT(Id) productiveCount
            FROM Visit_Task__c
            WHERE Visitor_Name__c IN :users
            AND Checked_In_Time__c != NULL
            AND Checked_In_Time__c >= :startDT
            AND Checked_In_Time__c <= :endDT
            AND Id IN (
                SELECT Visit_Task__c 
                FROM Order__c 
                WHERE EffectiveDate__c >= :startDate 
                AND EffectiveDate__c <= :endDate
            )
            GROUP BY Visitor_Name__c
        ]) {
            productiveCalls += (Integer)ar.get('productiveCount');
        }

        // UTC (Unvisited planned tasks)
        Integer utcNoOrder = 0;
        for (AggregateResult ar : [
            SELECT COUNT(Id) utcCount
            FROM Visit_Task__c
            WHERE Visitor_Name__c IN :users
            AND Checked_In_Time__c = NULL
            AND Task_Planned_Date__c >= :startDate
            AND Task_Planned_Date__c <= :endDate
            GROUP BY Visitor_Name__c
        ]) {
            utcNoOrder += (Integer)ar.get('utcCount');
        }

        // Zero Order Outlets
        Integer zeroOrderCount = 0;
        for (AggregateResult ar : [
            SELECT COUNT_DISTINCT(Retailer__c) zc
            FROM Visit_Task__c
            WHERE Visitor_Name__c IN :users
            AND Checked_In_Time__c >= :startDT
            AND Checked_In_Time__c <= :endDT
            AND Id NOT IN (
                SELECT Visit_Task__c
                FROM Order__c
                WHERE EffectiveDate__c >= :startDate
                AND EffectiveDate__c <= :endDate
            )
            GROUP BY Visitor_Name__c
        ]) {
            zeroOrderCount += (Integer)ar.get('zc');
        }

        // TOTAL ORDER VALUE - Fixed: Remove LIMIT
        Decimal totalNetValue = 0;
        AggregateResult[] netValues = [
            SELECT SUM(Total_Order_Value__c) nv
            FROM Order__c
            WHERE Visit_Task__c IN (
                SELECT Id
                FROM Visit_Task__c
                WHERE Visitor_Name__c IN :users
                AND Checked_In_Time__c >= :startDT
                AND Checked_In_Time__c <= :endDT
            )
            AND EffectiveDate__c >= :startDate
            AND EffectiveDate__c <= :endDate
        ];

        if (!netValues.isEmpty() && netValues[0].get('nv') != null) {
            totalNetValue = (Decimal) netValues[0].get('nv');
        }

        // Calculate percentages
        Decimal coveragePct = 0;
        Decimal productivity = 0;
        
        Decimal denom = totalTC + utcNoOrder;
        if (denom > 0) {
            coveragePct = ((Decimal)totalTC / denom) * 100;
        }
        
        if (totalTC > 0) {
            productivity = ((Decimal)upc / totalTC) * 100;
        }

        return new Map<String, Object>{
            'totalTC' => totalTC,
            'productiveCalls' => productiveCalls,
            'upc' => upc,
            'utcNoOrder' => utcNoOrder,
            'zeroOrderCount' => zeroOrderCount,
            'coveragePct' => coveragePct,
            'productivity' => productivity,
            'netValue' => totalNetValue
        };
    }

    // ========================================================================
    // BULK OUTLET SUMMARY FOR MULTIPLE USERS - OPTIMIZED
    // ========================================================================
    @AuraEnabled(cacheable=true)
    public static Map<String, SummaryMetrics> getBulkOutletSummary(List<Id> userIds, String periodType) {
        Map<String, SummaryMetrics> resultMap = new Map<String, SummaryMetrics>();
        if (userIds == null || userIds.isEmpty()) return resultMap;

        Date startDate = getStartDate(periodType);
        Date endDate = getEndDate();
        Datetime startDT = toStartOfDayDT(startDate);
        Datetime endDT = toEndOfDayDT(endDate);

        // 1️⃣ Build subordinate map for all users
        Map<Id, Set<Id>> userToHierarchy = new Map<Id, Set<Id>>();
        Set<Id> allUserIds = new Set<Id>();

        for (Id uid : userIds) {
            Set<Id> subs = new Set<Id>();
            subs.add(uid);
            collectAllSubordinateIdsBulk(uid, subs);
            userToHierarchy.put(uid, subs);
            allUserIds.addAll(subs);
        }

        // Initialize result map
        for (Id userId : userIds) {
            resultMap.put(String.valueOf(userId), new SummaryMetrics());
        }

        // 2️⃣ Get record type ids from cache
        initGlobalCaches();
        Set<Id> distRTs = new Set<Id>();
        if (RECORD_TYPE_CACHE.containsKey('Distributor')) distRTs.add(RECORD_TYPE_CACHE.get('Distributor'));
        if (RECORD_TYPE_CACHE.containsKey('Super_Stockist')) distRTs.add(RECORD_TYPE_CACHE.get('Super_Stockist'));
        if (RECORD_TYPE_CACHE.containsKey('Under_SS')) distRTs.add(RECORD_TYPE_CACHE.get('Under_SS'));
        
        Id retailerRT = RECORD_TYPE_CACHE.get('Retailer');

        // 3️⃣ BULK QUERIES WITH BATCHING FOR LARGE DATASETS
        // Maps to store aggregated data
        Map<Id, Integer> tcMap = new Map<Id, Integer>();
        Map<Id, Integer> upcMap = new Map<Id, Integer>();
        Map<Id, Integer> productiveMap = new Map<Id, Integer>();
        Map<Id, Integer> utcMap = new Map<Id, Integer>();
        Map<Id, Integer> zeroOrderMap = new Map<Id, Integer>();
        Map<Id, Decimal> netValueMap = new Map<Id, Decimal>();
        Map<Id, Integer> distributorMap = new Map<Id, Integer>();
        Map<Id, Integer> outletMap = new Map<Id, Integer>();
        Map<Id, Integer> beatMap = new Map<Id, Integer>();

        // Query 1: Total TC - Fixed: Use Checked_In_Time__c
        for (AggregateResult ar : [
            SELECT Visitor_Name__c vid, COUNT(Id) tcCount
            FROM Visit_Task__c
            WHERE Visitor_Name__c IN :allUserIds
            AND Checked_In_Time__c != NULL
            AND Checked_In_Time__c >= :startDT
            AND Checked_In_Time__c <= :endDT
            GROUP BY Visitor_Name__c
            LIMIT 10000
        ]) {
            Id uid = (Id)ar.get('vid');
            tcMap.put(uid, (Integer)ar.get('tcCount'));
        }

        // Query 2: Productive Calls
        for (AggregateResult ar : [
            SELECT Visitor_Name__c vid, COUNT(Id) productiveCount
            FROM Visit_Task__c
            WHERE Visitor_Name__c IN :allUserIds
            AND Checked_In_Time__c != NULL
            AND Checked_In_Time__c >= :startDT
            AND Checked_In_Time__c <= :endDT
            AND Id IN (
                SELECT Visit_Task__c 
                FROM Order__c 
                WHERE EffectiveDate__c >= :startDate
                AND EffectiveDate__c <= :endDate
            )
            GROUP BY Visitor_Name__c
            LIMIT 10000
        ]) {
            Id uid = (Id)ar.get('vid');
            productiveMap.put(uid, (Integer)ar.get('productiveCount'));
        }

        // Query 3: UPC
        for (AggregateResult ar : [
            SELECT Visitor_Name__c vid, COUNT(Id) upcCount
            FROM Visit_Task__c
            WHERE Visitor_Name__c IN :allUserIds
            AND Task_Planned_Date__c >= :startDate
            AND Task_Planned_Date__c <= :endDate
            AND Id IN (
                SELECT Visit_Task__c 
                FROM Order__c 
                WHERE EffectiveDate__c >= :startDate
                AND EffectiveDate__c <= :endDate
            )
            GROUP BY Visitor_Name__c
            LIMIT 10000
        ]) {
            Id uid = (Id)ar.get('vid');
            upcMap.put(uid, (Integer)ar.get('upcCount'));
        }

        // Query 4: UTC (Unvisited)
        for (AggregateResult ar : [
            SELECT Visitor_Name__c vid, COUNT(Id) c
            FROM Visit_Task__c
            WHERE Visitor_Name__c IN :allUserIds
            AND Checked_In_Time__c = null
            AND Task_Planned_Date__c >= :startDate
            AND Task_Planned_Date__c <= :endDate
            GROUP BY Visitor_Name__c
            LIMIT 10000
        ]) {
            utcMap.put((Id)ar.get('vid'), (Integer)ar.get('c'));
        }

        // Query 5: Zero Order Outlets
        for (AggregateResult ar : [
            SELECT Visitor_Name__c vid, COUNT_DISTINCT(Retailer__c) z
            FROM Visit_Task__c
            WHERE Visitor_Name__c IN :allUserIds
            AND Checked_In_Time__c >= :startDT
            AND Checked_In_Time__c <= :endDT
            AND Id NOT IN (
                SELECT Visit_Task__c FROM Order__c
                WHERE EffectiveDate__c >= :startDate
                AND EffectiveDate__c <= :endDate
            )
            GROUP BY Visitor_Name__c
            LIMIT 10000
        ]) {
            zeroOrderMap.put((Id)ar.get('vid'), (Integer)ar.get('z'));
        }

        // Query 6: Net Value
        for (AggregateResult ar : [
            SELECT Visit_Task__r.Visitor_Name__c vid, SUM(Total_Order_Value__c) nv
            FROM Order__c
            WHERE Visit_Task__r.Visitor_Name__c IN :allUserIds
            AND Visit_Task__r.Checked_In_Time__c >= :startDT
            AND Visit_Task__r.Checked_In_Time__c <= :endDT
            AND EffectiveDate__c >= :startDate
            AND EffectiveDate__c <= :endDate
            GROUP BY Visit_Task__r.Visitor_Name__c
            LIMIT 10000
        ]) {
            netValueMap.put((Id)ar.get('vid'), (Decimal)ar.get('nv'));
        }

        // Query 7: Distributor accounts
        for (AggregateResult ar : [
            SELECT OwnerId oid, COUNT(Id) c
            FROM Account
            WHERE OwnerId IN :allUserIds
            AND RecordTypeId IN :distRTs
            GROUP BY OwnerId
            LIMIT 10000
        ]) {
            distributorMap.put((Id)ar.get('oid'), (Integer)ar.get('c'));
        }

        // Query 8: Retailer accounts
        for (AggregateResult ar : [
            SELECT OwnerId oid, COUNT(Id) c
            FROM Account
            WHERE OwnerId IN :allUserIds
            AND RecordTypeId = :retailerRT
            GROUP BY OwnerId
            LIMIT 10000
        ]) {
            outletMap.put((Id)ar.get('oid'), (Integer)ar.get('c'));
        }

        // Query 9: Beats
        for (AggregateResult ar : [
            SELECT OwnerId oid, COUNT(Id) c
            FROM Beat__c
            WHERE OwnerId IN :allUserIds
            GROUP BY OwnerId
            LIMIT 10000
        ]) {
            beatMap.put((Id)ar.get('oid'), (Integer)ar.get('c'));
        }

        // 4️⃣ Populate final result for each user
        for (Id userId : userIds) {
            SummaryMetrics m = resultMap.get(String.valueOf(userId));
            Set<Id> hierarchy = userToHierarchy.get(userId);

            Integer upc = 0, utc = 0, tc = 0, zero = 0, productive = 0;
            Decimal netv = 0;
            Integer dist = 0, outlets = 0, beats = 0;

            for (Id uid : hierarchy) {
                upc += upcMap.containsKey(uid) ? upcMap.get(uid) : 0;
                utc += utcMap.containsKey(uid) ? utcMap.get(uid) : 0;
                tc += tcMap.containsKey(uid) ? tcMap.get(uid) : 0;
                zero += zeroOrderMap.containsKey(uid) ? zeroOrderMap.get(uid) : 0;
                productive += productiveMap.containsKey(uid) ? productiveMap.get(uid) : 0;
                netv += netValueMap.containsKey(uid) ? netValueMap.get(uid) : 0;
                dist += distributorMap.containsKey(uid) ? distributorMap.get(uid) : 0;
                outlets += outletMap.containsKey(uid) ? outletMap.get(uid) : 0;
                beats += beatMap.containsKey(uid) ? beatMap.get(uid) : 0;
            }

            m.upc = upc;
            m.utc = utc;
            m.totalTC = tc;
            m.zeroOrderCount = zero;
            m.productiveCalls = productive;
            m.netValue = netv;
            m.distributors = dist;
            m.outlets = outlets;
            m.beats = beats;

            // coverage calculation
            if (upc + utc > 0) {
                m.coveragePct = ((Decimal)upc / (upc + utc)) * 100;
            }

            // productivity calculation
            if (tc > 0) {
                m.productivity = ((Decimal)upc / tc) * 100;
            }
        }

        return resultMap;
    }

    // ========================================================================
    // GET DIRECT SUBORDINATES HIERARCHY
    // ========================================================================
    @AuraEnabled(cacheable=true)
    public static HierarchyData getSubordinateHierarchy(Id userId, Integer monthNum, Integer yearNum) {
        HierarchyData result = new HierarchyData();

        if (userId == null) {
            userId = UserInfo.getUserId();
        }

        // Get current user info
        List<User> currentUser = [
            SELECT Id, Name, UserRole.Name 
            FROM User 
            WHERE Id = :userId
            LIMIT 1
        ];

        if (!currentUser.isEmpty()) {
            result.currentUser = new Map<String, Object>{
                'userId' => currentUser[0].Id,
                'userName' => currentUser[0].Name,
                'userRole' => currentUser[0].UserRole?.Name
            };
        }

        // Get direct reports (users with same manager or in role hierarchy)
        List<User> directReports = new List<User>();

        // Get user's role
        User currentUserRecord = [SELECT UserRoleId FROM User WHERE Id = :userId];

        if (currentUserRecord.UserRoleId != null) {
            // Find users in roles directly under this role
            List<UserRole> childRoles = [
                SELECT Id 
                FROM UserRole 
                WHERE ParentRoleId = :currentUserRecord.UserRoleId
            ];

            if (!childRoles.isEmpty()) {
                Set<Id> childRoleIds = new Set<Id>();
                for (UserRole role : childRoles) {
                    childRoleIds.add(role.Id);
                }

                directReports = [
                    SELECT Id, Name, UserRole.Name 
                    FROM User 
                    WHERE UserRoleId IN :childRoleIds
                    AND IsActive = true
                    AND Id != :userId
                    AND UserType = 'Standard'
                    ORDER BY Name
                ];
            }
        }

        List<Map<String, Object>> reportsList = new List<Map<String, Object>>();
        for (User u : directReports) {
            reportsList.add(new Map<String, Object>{
                'userId' => u.Id,
                'userName' => u.Name,
                'userRole' => u.UserRole?.Name
            });
        }

        result.directReports = reportsList;
        return result;
    }

    // ========================================================================
    // GET ALL SUBORDINATES (INCLUDING SELF)
    // ========================================================================
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getSubordinatesincludeself(Id parentUserId) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();

        if (parentUserId == null) {
            parentUserId = UserInfo.getUserId();
        }

        // Get all subordinates including self
        Set<Id> allUserIds = new Set<Id>();
        allUserIds.add(parentUserId);
        collectAllSubordinateIdsBulk(parentUserId, allUserIds);

        // Get user details
        List<User> allUsers = [
            SELECT Id, Name, UserRole.Name, Employee_Role__c
            FROM User 
            WHERE Id IN :allUserIds 
            AND IsActive = true
            AND UserType = 'Standard'
            ORDER BY Name
        ];

        for (User u : allUsers) {
            result.add(new Map<String, Object>{
                'Id' => u.Id,
                'Name' => u.Name,
                'Role' => u.UserRole?.Name,
                'Employee_Role__c' => u.Employee_Role__c
            });
        }

        return result;
    }

    // ========================================================================
    // GET USER OWN METRICS ONLY
    // ========================================================================
    @AuraEnabled(cacheable=true)
    public static Map<String, SummaryMetrics> getUserOwnMetricsOnly(List<Id> userIds, String periodType) {
        Map<String, SummaryMetrics> resultMap = new Map<String, SummaryMetrics>();

        if (userIds == null || userIds.isEmpty()) {
            return resultMap;
        }

        Date startDate = getStartDate(periodType);
        Date endDate = getEndDate();
        Datetime startDT = toStartOfDayDT(startDate);
        Datetime endDT = toEndOfDayDT(endDate);

        // Initialize result map
        for (Id userId : userIds) {
            resultMap.put(String.valueOf(userId), new SummaryMetrics());
        }

        try {
            // Get record type IDs
            initGlobalCaches();
            Set<Id> distRTs = new Set<Id>();
            if (RECORD_TYPE_CACHE.containsKey('Distributor')) distRTs.add(RECORD_TYPE_CACHE.get('Distributor'));
            if (RECORD_TYPE_CACHE.containsKey('Super_Stockist')) distRTs.add(RECORD_TYPE_CACHE.get('Super_Stockist'));
            if (RECORD_TYPE_CACHE.containsKey('Under_SS')) distRTs.add(RECORD_TYPE_CACHE.get('Under_SS'));
            
            Id retailerRT = RECORD_TYPE_CACHE.get('Retailer');

            // Maps to store aggregated data
            Map<Id, Integer> upcMap = new Map<Id, Integer>();
            Map<Id, Integer> utcMap = new Map<Id, Integer>();
            Map<Id, Integer> tcMap = new Map<Id, Integer>();
            Map<Id, Integer> zeroOrderMap = new Map<Id, Integer>();
            Map<Id, Decimal> netValueMap = new Map<Id, Decimal>();
            Map<Id, Integer> distributorMap = new Map<Id, Integer>();
            Map<Id, Integer> outletMap = new Map<Id, Integer>();
            Map<Id, Integer> beatMap = new Map<Id, Integer>();

            // UPC Map - User's own UPC
            for (AggregateResult ar : [
                SELECT Visitor_Name__c vid, COUNT(Id) c
                FROM Visit_Task__c
                WHERE Visitor_Name__c IN :userIds
                AND Task_Planned_Date__c >= :startDate
                AND Task_Planned_Date__c <= :endDate
                AND Id IN (
                    SELECT Visit_Task__c 
                    FROM Order__c 
                    WHERE EffectiveDate__c >= :startDate
                    AND EffectiveDate__c <= :endDate
                )
                GROUP BY Visitor_Name__c
                LIMIT 10000
            ]) {
                upcMap.put((Id) ar.get('vid'), (Integer) ar.get('c'));
            }

            // UTC Map - User's own UTC
            for (AggregateResult ar : [
                SELECT Visitor_Name__c vid, COUNT(Id) c
                FROM Visit_Task__c
                WHERE Visitor_Name__c IN :userIds
                AND Checked_In_Time__c = null
                AND Task_Planned_Date__c >= :startDate
                AND Task_Planned_Date__c <= :endDate
                GROUP BY Visitor_Name__c
                LIMIT 10000
            ]) {
                utcMap.put((Id) ar.get('vid'), (Integer) ar.get('c'));
            }

            // Total TC Map - User's own TC - Fixed: Use Checked_In_Time__c
            for (AggregateResult ar : [
                SELECT Visitor_Name__c vid, COUNT(Id) c
                FROM Visit_Task__c
                WHERE Visitor_Name__c IN :userIds
                AND Checked_In_Time__c != NULL
                AND Checked_In_Time__c >= :startDT
                AND Checked_In_Time__c <= :endDT
                GROUP BY Visitor_Name__c
                LIMIT 10000
            ]) {
                tcMap.put((Id) ar.get('vid'), (Integer) ar.get('c'));
            }

            // Zero Order Map - User's own zero orders
            for (AggregateResult ar : [
                SELECT Visitor_Name__c vid, COUNT_DISTINCT(Retailer__c) z
                FROM Visit_Task__c
                WHERE Visitor_Name__c IN :userIds
                AND Checked_In_Time__c >= :startDT
                AND Checked_In_Time__c <= :endDT
                AND Id NOT IN (
                    SELECT Visit_Task__c FROM Order__c
                    WHERE EffectiveDate__c >= :startDate
                    AND EffectiveDate__c <= :endDate
                )
                GROUP BY Visitor_Name__c
                LIMIT 10000
            ]) {
                zeroOrderMap.put((Id) ar.get('vid'), (Integer) ar.get('z'));
            }

            // Net Value Map - User's own net value
            for (AggregateResult ar : [
                SELECT Visit_Task__r.Visitor_Name__c vid, SUM(Total_Order_Value__c) nv
                FROM Order__c
                WHERE Visit_Task__r.Visitor_Name__c IN :userIds
                AND Visit_Task__r.Checked_In_Time__c >= :startDT
                AND Visit_Task__r.Checked_In_Time__c <= :endDT
                AND EffectiveDate__c >= :startDate
                AND EffectiveDate__c <= :endDate
                GROUP BY Visit_Task__r.Visitor_Name__c
                LIMIT 10000
            ]) {
                netValueMap.put((Id) ar.get('vid'), (Decimal) ar.get('nv'));
            }

            // Distributor accounts - User's own distributors
            for (AggregateResult ar : [
                SELECT OwnerId oid, COUNT(Id) c
                FROM Account
                WHERE OwnerId IN :userIds
                AND RecordTypeId IN :distRTs
                GROUP BY OwnerId
                LIMIT 10000
            ]) {
                distributorMap.put((Id) ar.get('oid'), (Integer) ar.get('c'));
            }

            // Retailer accounts - User's own outlets
            for (AggregateResult ar : [
                SELECT OwnerId oid, COUNT(Id) c
                FROM Account
                WHERE OwnerId IN :userIds
                AND RecordTypeId = :retailerRT
                GROUP BY OwnerId
                LIMIT 10000
            ]) {
                outletMap.put((Id) ar.get('oid'), (Integer) ar.get('c'));
            }

            // Beats - User's own beats
            for (AggregateResult ar : [
                SELECT OwnerId oid, COUNT(Id) c
                FROM Beat__c
                WHERE OwnerId IN :userIds
                GROUP BY OwnerId
                LIMIT 10000
            ]) {
                beatMap.put((Id) ar.get('oid'), (Integer) ar.get('c'));
            }

            // Build results for each user
            for (Id userId : userIds) {
                SummaryMetrics m = resultMap.get(String.valueOf(userId));

                // Get user's own metrics
                m.upc = upcMap.containsKey(userId) ? upcMap.get(userId) : 0;
                m.utc = utcMap.containsKey(userId) ? utcMap.get(userId) : 0;
                m.totalTC = tcMap.containsKey(userId) ? tcMap.get(userId) : 0;
                m.zeroOrderCount = zeroOrderMap.containsKey(userId) ? zeroOrderMap.get(userId) : 0;
                m.netValue = netValueMap.containsKey(userId) ? netValueMap.get(userId) : 0;
                m.distributors = distributorMap.containsKey(userId) ? distributorMap.get(userId) : 0;
                m.outlets = outletMap.containsKey(userId) ? outletMap.get(userId) : 0;
                m.beats = beatMap.containsKey(userId) ? beatMap.get(userId) : 0;
                m.productiveCalls = m.upc; // Productive calls = UPC for user-only

                // Coverage percentage (user's own coverage)
                if (m.upc + m.utc > 0) {
                    m.coveragePct = ((Decimal)m.upc / (m.upc + m.utc)) * 100;
                }

                // Productivity (user's own productivity)
                if (m.totalTC > 0) {
                    m.productivity = ((Decimal)m.upc / m.totalTC) * 100;
                }
            }

        } catch (Exception e) {
            // Log the error but still return empty results
            System.debug('Error in getUserOwnMetricsOnly: ' + e.getMessage() + ' ' + e.getStackTraceString());
        }

        return resultMap;
    }
}