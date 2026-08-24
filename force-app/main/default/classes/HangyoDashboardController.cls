public with sharing class HangyoDashboardController {
    
    /* ======================================================
    DTO CLASSES
    ====================================================== */
    
    private static Map<Id, Id> GLOBAL_userRoleMap;
    private static Map<Id, Set<Id>> GLOBAL_parentRoleToChildRoles;
    private static Map<Id, Set<Id>> GLOBAL_roleToUserIds;
    
    public class UserHierarchyDTO {
        @AuraEnabled public TeamMemberDTO currentUser;
        @AuraEnabled public List<TeamMemberDTO> directReports;
    }
    
    public class PositionOrderDTO implements Comparable {
        @AuraEnabled public String positionName;
        @AuraEnabled public Decimal actualAmount;
        @AuraEnabled public Decimal targetAmount;
        @AuraEnabled public Integer rank;
        @AuraEnabled public Id ownerId;
        
        // Sort by actualAmount DESC
        public Integer compareTo(Object otherObj) {
            PositionOrderDTO o = (PositionOrderDTO) otherObj;
            if (this.actualAmount == o.actualAmount) return 0;
            return this.actualAmount > o.actualAmount ? -1 : 1;
        }
    }
    
    public class TeamMemberDTO implements Comparable {
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String userRole;
        @AuraEnabled public Decimal actualAmount;
        @AuraEnabled public Decimal targetAmount;
        @AuraEnabled public Decimal secondaryTarget;
        
        // Sort by actualAmount DESC
        public Integer compareTo(Object otherObj) {
            TeamMemberDTO o = (TeamMemberDTO) otherObj;
            if (this.actualAmount == o.actualAmount) return 0;
            return this.actualAmount > o.actualAmount ? -1 : 1;
        }
    }
    
    /* ======================================================
    MONTH NAME HELPER
    ====================================================== */
    private static String getMonthName(Integer monthNum) {
        final List<String> names = new List<String>{
            'January','February','March','April','May','June',
            'July','August','September','October','November','December'
        };
        if (monthNum != null && monthNum >= 1 && monthNum <= 12)
            return names[monthNum - 1];
        return null;
    }
    
    /* ======================================================
    OPTIMIZATION: CACHE MANAGEMENT
    ====================================================== */
    private static void initializeGlobalCaches() {
        if (GLOBAL_userRoleMap != null) return;
        
        GLOBAL_userRoleMap = new Map<Id, Id>();
        GLOBAL_roleToUserIds = new Map<Id, Set<Id>>();
        GLOBAL_parentRoleToChildRoles = new Map<Id, Set<Id>>();
        
        // Load ALL users only once
        List<User> allUsers = [SELECT Id, UserRoleId FROM User WHERE IsActive = true AND UserType = 'Standard' LIMIT 10000];
        for (User u : allUsers) {
            if (u.UserRoleId != null) {
                GLOBAL_userRoleMap.put(u.Id, u.UserRoleId);
                
                if (!GLOBAL_roleToUserIds.containsKey(u.UserRoleId)) {
                    GLOBAL_roleToUserIds.put(u.UserRoleId, new Set<Id>());
                }
                GLOBAL_roleToUserIds.get(u.UserRoleId).add(u.Id);
            }
        }
        
        // Load ALL user roles only once
        List<UserRole> allRoles = [SELECT Id, ParentRoleId FROM UserRole WHERE ParentRoleId != null LIMIT 10000];
        for (UserRole r : allRoles) {
            if (!GLOBAL_parentRoleToChildRoles.containsKey(r.ParentRoleId)) {
                GLOBAL_parentRoleToChildRoles.put(r.ParentRoleId, new Set<Id>());
            }
            GLOBAL_parentRoleToChildRoles.get(r.ParentRoleId).add(r.Id);
        }
    }
    
    /* ======================================================
    OPTIMIZATION: BATCH DATA FETCHING
    ====================================================== */
    private static Map<Id, Decimal> getActualAmountsForUsers(Set<Id> userIds, Date startDate, Date endDate) {
        Map<Id, Decimal> actualMap = new Map<Id, Decimal>();
        
        if (userIds.isEmpty()) return actualMap;
        
        // Initialize with 0 for all users
        for (Id userId : userIds) {
            actualMap.put(userId, 0);
        }
        
        // Process in chunks to avoid governor limits
        List<Id> userIdList = new List<Id>(userIds);
        Integer maxUsersPerQuery = 5000; // Conservative limit to avoid issues
        
        for (Integer i = 0; i < userIdList.size(); i += maxUsersPerQuery) {
            Integer endIdx = Math.min(i + maxUsersPerQuery, userIdList.size());
            List<Id> chunk = new List<Id>();
            for (Integer j = i; j < endIdx; j++) {
                chunk.add(userIdList[j]);
            }
            
            for (AggregateResult ar : [
                SELECT Visit_Task__r.Visitor_Name__c oid, SUM(Total_Order_Value__c) total 
                FROM Order__c 
                WHERE Visit_Task__r.Visitor_Name__c IN :chunk 
                AND RecordType.DeveloperName = 'Secondary_Order'
                AND Visit_Task__r.Task_Planned_Date__c >= :startDate 
                AND Visit_Task__r.Task_Planned_Date__c <= :endDate 
                GROUP BY Visit_Task__r.Visitor_Name__c
            ]) {
                Id userId = (Id)ar.get('oid');
                Decimal total = (Decimal)ar.get('total');
                if (total != null) {
                    actualMap.put(userId, total);
                }
            }
        }
        
        return actualMap;
    }
    
    private static Map<Id, Decimal> getTargetAmountsForUsers(Set<Id> userIds, String monthName, String yearStr) {
        Map<Id, Decimal> targetMap = new Map<Id, Decimal>();
        
        if (userIds.isEmpty() || monthName == null) return targetMap;
        
        // Initialize with 0 for all users
        for (Id userId : userIds) {
            targetMap.put(userId, 0);
        }
        
        // Process in chunks
        List<Id> userIdList = new List<Id>(userIds);
        Integer maxUsersPerQuery = 5000;
        
        for (Integer i = 0; i < userIdList.size(); i += maxUsersPerQuery) {
            Integer endIdx = Math.min(i + maxUsersPerQuery, userIdList.size());
            List<Id> chunk = new List<Id>();
            for (Integer j = i; j < endIdx; j++) {
                chunk.add(userIdList[j]);
            }
            
            for (Sales_Target__c t : [
                SELECT Assigned_To__c, Secondary_Sales_Target__c 
                FROM Sales_Target__c 
                WHERE Assigned_To__c IN :chunk 
                AND Month__c = :monthName 
                AND Year__c = :yearStr 
                AND RecordType.DeveloperName = 'Sales_Target_Month'
            ]) {
                if (t.Assigned_To__c != null) {
                    Decimal currentValue = targetMap.get(t.Assigned_To__c);
                    if (currentValue == null) currentValue = 0;
                    currentValue += (t.Secondary_Sales_Target__c != null ? t.Secondary_Sales_Target__c : 0);
                    targetMap.put(t.Assigned_To__c, currentValue);
                }
            }
        }
        
        return targetMap;
    }
    
    /* ======================================================
    OPTIMIZED: GET ALL SUBORDINATE IDS WITH CACHING
    ====================================================== */
    private static Set<Id> getAllSubordinateIdsBulk(Id userId) {
        Set<Id> allUserIds = new Set<Id>();
        if (userId == null) return allUserIds;
        
        initializeGlobalCaches();
        
        Id parentRoleId = GLOBAL_userRoleMap.get(userId);
        if (parentRoleId == null) return allUserIds;
        
        // BFS traversal through role hierarchy
        Set<Id> visitedRoles = new Set<Id>();
        List<Id> roleQueue = new List<Id>();
        
        if (GLOBAL_parentRoleToChildRoles.containsKey(parentRoleId)) {
            roleQueue.addAll(GLOBAL_parentRoleToChildRoles.get(parentRoleId));
        }
        
        while (!roleQueue.isEmpty()) {
            Id roleId = roleQueue.remove(0);
            if (visitedRoles.contains(roleId)) continue;
            
            visitedRoles.add(roleId);
            
            // Add users for this role
            if (GLOBAL_roleToUserIds.containsKey(roleId)) {
                allUserIds.addAll(GLOBAL_roleToUserIds.get(roleId));
            }
            
            // Add deeper roles
            if (GLOBAL_parentRoleToChildRoles.containsKey(roleId)) {
                roleQueue.addAll(GLOBAL_parentRoleToChildRoles.get(roleId));
            }
        }
        
        return allUserIds;
    }
    
    /* ======================================================
    1 ► GET USER KPI + DRILLDOWN HIERARCHY (OPTIMIZED)
    ====================================================== */
    @AuraEnabled(cacheable=true)
    public static UserHierarchyDTO getSubordinateHierarchy(Id userId, Integer monthNum, Integer yearNum) {
        UserHierarchyDTO result = new UserHierarchyDTO();
        
        if (userId == null || monthNum == null || yearNum == null) {
            result.currentUser = new TeamMemberDTO();
            result.directReports = new List<TeamMemberDTO>();
            return result;
        }
        
        Date startDate = Date.newInstance(yearNum, monthNum, 1);
        Date endDate = startDate.addMonths(1);
        String monthName = getMonthName(monthNum);
        String yearStr = String.valueOf(yearNum);
        
        // Get current user info
        User currentUser = [SELECT Id, Name, UserRoleId, UserRole.Name FROM User WHERE Id = :userId LIMIT 1];
        
        // Get direct reports
        List<User> directReports = getDirectReportsByRole(userId);
        
        // Get current user KPI
        result.currentUser = createUserKPIDTO(currentUser, startDate, endDate, monthName, yearStr, true);
        
        if (directReports.isEmpty()) {
            result.directReports = new List<TeamMemberDTO>();
            return result;
        }
        
        // Collect all IDs for batch query
        Set<Id> allUserIds = new Set<Id>();
        Map<Id, User> userMap = new Map<Id, User>();
        
        for (User dr : directReports) {
            allUserIds.add(dr.Id);
            userMap.put(dr.Id, dr);
        }
        
        // Get ALL subordinate IDs for each direct report
        for (User dr : directReports) {
            Set<Id> subordinateIds = getAllSubordinateIdsBulk(dr.Id);
            allUserIds.addAll(subordinateIds);
        }
        
        // Add current user's subordinates for their totals
        Set<Id> currentUserSubordinates = getAllSubordinateIdsBulk(userId);
        allUserIds.addAll(currentUserSubordinates);
        
        // Batch fetch actual amounts
        Map<Id, Decimal> actualMap = getActualAmountsForUsers(allUserIds, startDate, endDate);
        
        // Batch fetch target amounts
        Map<Id, Decimal> targetMap = getTargetAmountsForUsers(allUserIds, monthName, yearStr);
        
        // Build direct report DTOs
        result.directReports = new List<TeamMemberDTO>();
        for (User dr : directReports) {
            TeamMemberDTO dto = new TeamMemberDTO();
            dto.userId = dr.Id;
            dto.userName = dr.Name;
            dto.userRole = dr.UserRole?.Name;
            
            // Calculate actual amount including subordinates
            Set<Id> drSubordinateIds = getAllSubordinateIdsBulk(dr.Id);
            drSubordinateIds.add(dr.Id);
            
            Decimal drTotalActual = 0;
            for (Id subId : drSubordinateIds) {
                drTotalActual += actualMap.get(subId) != null ? actualMap.get(subId) : 0;
            }
            
            dto.actualAmount = drTotalActual;
            dto.targetAmount = targetMap.get(dr.Id) != null ? targetMap.get(dr.Id) : 0;
            dto.secondaryTarget = dto.targetAmount;
            
            result.directReports.add(dto);
        }
        
        result.directReports.sort();
        return result;
    }
    
    /* ======================================================
    2 ► POSITION WISE ORDER SUMMARY (OPTIMIZED)
    ====================================================== */
    @AuraEnabled(cacheable=true)
    public static List<PositionOrderDTO> getPositionWiseOrders(Integer monthNum, Integer yearNum) {
        List<PositionOrderDTO> result = new List<PositionOrderDTO>();
        if (monthNum == null || yearNum == null) return result;
        
        Date startDate = Date.newInstance(yearNum, monthNum, 1);
        Date endDate = startDate.addMonths(1);
        String monthName = getMonthName(monthNum);
        String yearStr = String.valueOf(yearNum);
        
        // Get all users with orders in this period
        List<AggregateResult> aggResults = [
            SELECT Visit_Task__r.Visitor_Name__c ownerId, 
                   Visit_Task__r.Visitor_Name__r.Name ownerName, 
                   SUM(Total_Order_Value__c) totalActual
            FROM Order__c
            WHERE Visit_Task__r.Task_Planned_Date__c >= :startDate 
            AND Visit_Task__r.Task_Planned_Date__c < :endDate
            AND RecordType.DeveloperName = 'Secondary_Order'
            AND Visit_Task__r.Visitor_Name__c != null
            GROUP BY Visit_Task__r.Visitor_Name__c, Visit_Task__r.Visitor_Name__r.Name
            HAVING SUM(Total_Order_Value__c) > 0
            ORDER BY SUM(Total_Order_Value__c) DESC
            LIMIT 1000
        ];
        
        if (aggResults.isEmpty()) return result;
        
        // Collect user IDs for batch processing
        Set<Id> userIds = new Set<Id>();
        Map<Id, String> userNameMap = new Map<Id, String>();
        
        for (AggregateResult ar : aggResults) {
            Id ownerId = (Id)ar.get('ownerId');
            userIds.add(ownerId);
            userNameMap.put(ownerId, (String)ar.get('ownerName'));
        }
        
        // Get targets in batch
        Map<Id, Decimal> targetMap = getTargetAmountsForUsers(userIds, monthName, yearStr);
        
        // Get actual amounts in batch for all users
        Map<Id, Decimal> actualMap = getActualAmountsForUsers(userIds, startDate, endDate);
        
        Integer rank = 1;
        
        // Create DTOs
        for (AggregateResult ar : aggResults) {
            Id ownerId = (Id)ar.get('ownerId');
            Decimal userActual = (Decimal)ar.get('totalActual');
            
            // Calculate total including subordinates
            Set<Id> subordinateIds = getAllSubordinateIdsBulk(ownerId);
            subordinateIds.add(ownerId);
            
            Decimal totalActual = userActual;
            for (Id subId : subordinateIds) {
                if (subId != ownerId) {
                    totalActual += actualMap.get(subId) != null ? actualMap.get(subId) : 0;
                }
            }
            
            PositionOrderDTO dto = new PositionOrderDTO();
            dto.ownerId = ownerId;
            dto.positionName = userNameMap.get(ownerId);
            dto.actualAmount = totalActual;
            dto.targetAmount = targetMap.get(ownerId) != null ? targetMap.get(ownerId) : 0;
            dto.rank = rank;
            result.add(dto);
            rank++;
        }
        
        // Sort by actual amount
        result.sort();
        
        // Update ranks after sorting
        for (Integer i = 0; i < result.size(); i++) {
            result[i].rank = i + 1;
        }
        
        return result;
    }
    
    /* ======================================================
    3 ► USER KPI (STRIP SUMMARY) - OPTIMIZED
    ====================================================== */
    @AuraEnabled(cacheable=true)
    public static Map<String,Object> getUserKPIAndSubordinates(Integer monthNum, Integer yearNum) {
        Map<String,Object> out = new Map<String,Object>{
            'userActual' => 0,
            'userTarget' => 0,
            'userSecondary' => 0,
            'subordinatesActual' => 0
        };
        
        if (monthNum == null || yearNum == null) return out;
        
        Id userId = UserInfo.getUserId();
        Date startDate = Date.newInstance(yearNum, monthNum, 1);
        Date endDate = startDate.addMonths(1);
        String monthName = getMonthName(monthNum);
        String yearStr = String.valueOf(yearNum);
        
        // Get all subordinate IDs
        Set<Id> allSubordinateIds = getAllSubordinateIdsBulk(userId);
        allSubordinateIds.add(userId);
        
        // Batch fetch actual amounts
        Map<Id, Decimal> actualMap = getActualAmountsForUsers(allSubordinateIds, startDate, endDate);
        
        // Calculate totals
        Decimal userOwnTotal = actualMap.get(userId) != null ? actualMap.get(userId) : 0;
        Decimal subsTotal = 0;
        
        for (Id subId : allSubordinateIds) {
            if (subId != userId) {
                subsTotal += actualMap.get(subId) != null ? actualMap.get(subId) : 0;
            }
        }
        
        // Get user target
        Map<Id, Decimal> targetMap = getTargetAmountsForUsers(new Set<Id>{userId}, monthName, yearStr);
        Decimal userTarget = targetMap.get(userId) != null ? targetMap.get(userId) : 0;
        
        out.put('userActual', userOwnTotal + subsTotal);
        out.put('userTarget', userTarget);
        out.put('userSecondary', userTarget);
        out.put('subordinatesActual', subsTotal);
        
        return out;
    }
    
    /* ======================================================
    4 ► SUBORDINATE DRILLDOWN (ALL LEVELS) - OPTIMIZED
    ====================================================== */
    @AuraEnabled(cacheable=true)
    public static List<TeamMemberDTO> getSubordinatesCoverage(Integer monthNum, Integer yearNum) {
        List<TeamMemberDTO> result = new List<TeamMemberDTO>();
        if (monthNum == null || yearNum == null) return result;
        
        Id userId = UserInfo.getUserId();
        Set<Id> subordinateIds = getAllSubordinateIdsBulk(userId);
        
        if (subordinateIds.isEmpty()) return result;
        
        Date startDate = Date.newInstance(yearNum, monthNum, 1);
        Date endDate = startDate.addMonths(1);
        String monthName = getMonthName(monthNum);
        String yearStr = String.valueOf(yearNum);
        
        // Get user details
        Map<Id, User> userMap = new Map<Id, User>([
            SELECT Id, Name, UserRoleId, UserRole.Name 
            FROM User 
            WHERE Id IN :subordinateIds
            AND IsActive = true
            ORDER BY Name
            LIMIT 1000
        ]);
        
        // Batch fetch actual amounts
        Map<Id, Decimal> actualMap = getActualAmountsForUsers(subordinateIds, startDate, endDate);
        
        // Batch fetch target amounts
        Map<Id, Decimal> targetMap = getTargetAmountsForUsers(subordinateIds, monthName, yearStr);
        
        // Build DTOs
        for (User u : userMap.values()) {
            TeamMemberDTO dto = new TeamMemberDTO();
            dto.userId = u.Id;
            dto.userName = u.Name;
            dto.userRole = u.UserRole?.Name;
            dto.actualAmount = actualMap.get(u.Id) != null ? actualMap.get(u.Id) : 0;
            dto.targetAmount = targetMap.get(u.Id) != null ? targetMap.get(u.Id) : 0;
            dto.secondaryTarget = dto.targetAmount;
            result.add(dto);
        }
        
        result.sort();
        return result;
    }
    
    /* ======================================================
    5 ► TEAM COVERAGE (DIRECT REPORTS ONLY) - OPTIMIZED
    ====================================================== */
    @AuraEnabled(cacheable=true)
    public static List<TeamMemberDTO> getTeamCoverage(Id ownerId, Integer monthNum, Integer yearNum) {
        List<TeamMemberDTO> result = new List<TeamMemberDTO>();
        if (ownerId == null || monthNum == null || yearNum == null) return result;
        
        Date startDate = Date.newInstance(yearNum, monthNum, 1);
        Date endDate = startDate.addMonths(1);
        String monthName = getMonthName(monthNum);
        String yearStr = String.valueOf(yearNum);
        
        // Get direct reports
        List<User> directReports = getDirectReportsByRole(ownerId);
        if (directReports.isEmpty()) return result;
        
        // Collect user IDs
        Set<Id> userIds = new Set<Id>();
        for (User u : directReports) {
            userIds.add(u.Id);
        }
        
        // Batch fetch actual amounts
        Map<Id, Decimal> actualMap = getActualAmountsForUsers(userIds, startDate, endDate);
        
        // Batch fetch target amounts
        Map<Id, Decimal> targetMap = getTargetAmountsForUsers(userIds, monthName, yearStr);
        
        // Build DTOs
        for (User u : directReports) {
            TeamMemberDTO dto = new TeamMemberDTO();
            dto.userId = u.Id;
            dto.userName = u.Name;
            dto.actualAmount = actualMap.get(u.Id) != null ? actualMap.get(u.Id) : 0;
            dto.targetAmount = targetMap.get(u.Id) != null ? targetMap.get(u.Id) : 0;
            dto.secondaryTarget = dto.targetAmount;
            result.add(dto);
        }
        
        result.sort();
        return result;
    }
    
    /* ======================================================
    UTILITY METHODS
    ====================================================== */
    
    private static List<User> getDirectReportsByRole(Id userId) {
        if (userId == null) return new List<User>();
        
        User parent = [SELECT UserRoleId FROM User WHERE Id = :userId LIMIT 1];
        if (parent == null || parent.UserRoleId == null) return new List<User>();
        
        Set<Id> childRoleIds = new Set<Id>();
        for (UserRole ur : [SELECT Id FROM UserRole WHERE ParentRoleId = :parent.UserRoleId LIMIT 100]) {
            childRoleIds.add(ur.Id);
        }
        
        if (childRoleIds.isEmpty()) return new List<User>();
        
        return [
            SELECT Id, Name, UserRoleId, UserRole.Name 
            FROM User 
            WHERE UserRoleId IN :childRoleIds 
            AND IsActive = true 
            AND UserType = 'Standard'
            ORDER BY Name
            LIMIT 1000
        ];
    }
    
    private static TeamMemberDTO createUserKPIDTO(User u, Date startDate, Date endDate, String monthName, String yearStr, Boolean includeSubordinates) {
        TeamMemberDTO dto = new TeamMemberDTO();
        dto.userId = u.Id;
        dto.userName = u.Name;
        dto.userRole = u.UserRole?.Name;
        
        Set<Id> userIds = new Set<Id>{u.Id};
        
        if (includeSubordinates) {
            Set<Id> subordinateIds = getAllSubordinateIdsBulk(u.Id);
            userIds.addAll(subordinateIds);
        }
        
        // Get actual amount
        Map<Id, Decimal> actualMap = getActualAmountsForUsers(userIds, startDate, endDate);
        
        Decimal totalActual = 0;
        for (Id userId : userIds) {
            totalActual += actualMap.get(userId) != null ? actualMap.get(userId) : 0;
        }
        dto.actualAmount = totalActual;
        
        // Get target
        Map<Id, Decimal> targetMap = getTargetAmountsForUsers(new Set<Id>{u.Id}, monthName, yearStr);
        dto.targetAmount = targetMap.get(u.Id) != null ? targetMap.get(u.Id) : 0;
        dto.secondaryTarget = dto.targetAmount;
        
        return dto;
    }
    
    /* ======================================================
    FOR ALL FIELDS USER (OPTIMIZED)
    ====================================================== */
    
    @AuraEnabled(cacheable=true)
    public static UserHierarchyResult getSubordinatesnosameroleusers(Id parentUserId) {
        if (parentUserId == null) return new UserHierarchyResult(0, new List<Map<String,String>>());
        
        Date today = Date.today();
        Date monthStart = today.toStartOfMonth();
        String yearStr = String.valueOf(today.year());
        DateTime dt = DateTime.newInstance(today.year(), today.month(), today.day()); 
        String monthName = dt.format('MMMM');
        
        // Get parent user
        User parentUser = [
            SELECT Id, UserRoleId, Name, UserRole.Name, UserType, Employee_Role__c, MobilePhone 
            FROM User 
            WHERE Id = :parentUserId 
            LIMIT 1
        ];
        
        // Handle partner users
        if (isPartnerUser(parentUser)) {
            return new UserHierarchyResult(0, new List<Map<String,String>>());
        }
        
        if (parentUser.UserRoleId == null) {
            List<Map<String,String>> onlyParent = new List<Map<String,String>>();
            onlyParent.add(createUserMap(parentUser, 0, 0));
            return new UserHierarchyResult(onlyParent.size(), onlyParent);
        }
        
        // Get all subordinate IDs
        Set<Id> allUserIds = getAllSubordinateIdsBulk(parentUserId);
        allUserIds.add(parentUserId);
        
        if (allUserIds.isEmpty()) {
            List<Map<String,String>> onlyParent = new List<Map<String,String>>();
            onlyParent.add(createUserMap(parentUser, 0, 0));
            return new UserHierarchyResult(onlyParent.size(), onlyParent);
        }
        
        // Convert to list and chunk if too large
        List<Id> allUserIdsList = new List<Id>(allUserIds);
        List<User> users = new List<User>();
        Integer chunkSize = 5000;
        
        for (Integer i = 0; i < allUserIdsList.size(); i += chunkSize) {
            Integer endIdx = Math.min(i + chunkSize, allUserIdsList.size());
            List<Id> chunk = new List<Id>();
            for (Integer j = i; j < endIdx; j++) {
                chunk.add(allUserIdsList[j]);
            }
            
            users.addAll([
                SELECT Id, Name, UserRoleId, UserRole.Name, UserType, Employee_Role__c, MobilePhone 
                FROM User 
                WHERE Id IN :chunk
                AND IsActive = true 
                AND UserType = 'Standard'
                ORDER BY Name
            ]);
        }
        
        // Batch fetch order totals
        Map<Id, Decimal> orderTotals = getActualAmountsForUsers(allUserIds, monthStart, today);
        
        // Batch fetch targets
        Map<Id, Decimal> targetMap = getTargetAmountsForUsers(allUserIds, monthName, yearStr);
        
        // Build result
        List<Map<String,String>> userList = new List<Map<String,String>>();
        for (User u : users) {
            Decimal totalActual = orderTotals.get(u.Id) != null ? orderTotals.get(u.Id) : 0;
            Decimal targetVal = targetMap.get(u.Id) != null ? targetMap.get(u.Id) : 0;
            userList.add(createUserMap(u, totalActual, targetVal));
        }
        
        return new UserHierarchyResult(userList.size(), userList);
    }
    
    @AuraEnabled(cacheable=true)
    public static Decimal getMySelfOnlyMTD(Integer monthNum, Integer yearNum) {
        if (monthNum == null || yearNum == null) return 0;
        
        Id userId = UserInfo.getUserId();
        Date startDate = Date.newInstance(yearNum, monthNum, 1);
        Date endDate = startDate.addMonths(1);
        
        Map<Id, Decimal> actualMap = getActualAmountsForUsers(new Set<Id>{userId}, startDate, endDate);
        return actualMap.get(userId) != null ? actualMap.get(userId) : 0;
    }
    
    /* ======================================================
    HELPER METHODS
    ====================================================== */
    
    private static Map<String, String> createUserMap(User u, Decimal totalActual, Decimal targetVal) {
        return new Map<String,String>{
            'Id' => u.Id,
            'Name' => u.Name,
            'Phone' => u.MobilePhone,
            'Employee_Role__c' => u.Employee_Role__c,
            'Role' => u.UserRole != null ? u.UserRole.Name : 'N/A',
            'TotalOrderValue' => String.valueOf(totalActual),
            'SecondaryTarget' => String.valueOf(targetVal)
        };
    }
    
    private static Boolean isPartnerUser(User u) {
        return (u.UserType == 'PowerPartner' ||
                u.UserType == 'Partner' ||
                u.UserType == 'CustomerPortal' ||
                u.UserType == 'CsnOnly');
    }
    
    public class UserHierarchyResult {
        @AuraEnabled public Integer totalUsers;
        @AuraEnabled public List<Map<String, String>> users;
        
        public UserHierarchyResult(Integer totalUsers, List<Map<String,String>> users) {
            this.totalUsers = totalUsers;
            this.users = users;
        }
    }
}