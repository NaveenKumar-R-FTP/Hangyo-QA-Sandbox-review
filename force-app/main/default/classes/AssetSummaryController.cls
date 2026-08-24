public without sharing class AssetSummaryController {
    
    public class AssetSummaryResult {
        @AuraEnabled public String userId;
        @AuraEnabled public String name;
        @AuraEnabled public String role;
        @AuraEnabled public Integer totalDF;
        @AuraEnabled public Integer billedDF;
        @AuraEnabled public Integer zeroBillingDF;
        @AuraEnabled public Decimal throughput;
        @AuraEnabled public List<AssetSummaryResult> subordinates;
        
        public AssetSummaryResult() {
            this.subordinates = new List<AssetSummaryResult>();
            this.totalDF = 0;
            this.billedDF = 0;
            this.zeroBillingDF = 0;
            this.throughput = 0;
        }
    }
    
    // Configuration constants
    private static final String RETAILER_RECORD_TYPE = 'Retailer';
    private static final String SECONDARY_ORDER_RECORD_TYPE = 'Secondary Order';
    
    // Cache for user hierarchy to avoid repeated queries
    private static Map<Id, Set<Id>> roleHierarchyCache = new Map<Id, Set<Id>>();
    
    @AuraEnabled(cacheable=true)
    public static AssetSummaryResult getSummaryForUser(Id userId) {
        try {
            if (userId == null) {
                userId = UserInfo.getUserId();
            }
            User currentUser = getUserWithRole(userId);
            Date mtdStart = Date.today().toStartOfMonth();
            Date mtdEnd = Date.today();
            Map<String, Object> individualMetrics = calculateSingleUserMetrics(userId, mtdStart, mtdEnd);
            AssetSummaryResult result = buildResultFromMetrics(currentUser, individualMetrics);
            result.subordinates = getDirectSubordinatesWithRolledUp(userId, mtdStart, mtdEnd);
            return result;
        } catch (Exception e) {
            System.debug('Error in getSummaryForUser: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            return createErrorResult(userId, e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static AssetSummaryResult getAssetMetricsForUsers(List<Id> userIds) {
        try {
            if (userIds == null || userIds.isEmpty()) {
                return new AssetSummaryResult();
            }
            Set<Id> uniqueUserIds = new Set<Id>(userIds);
            Set<Id> allRoleIds = new Set<Id>();
            for (User u : [SELECT Id, UserRoleId FROM User WHERE Id IN :uniqueUserIds AND IsActive = true AND UserType = 'Standard']) {
                if (u.UserRoleId != null) allRoleIds.add(u.UserRoleId);
            }
            Set<Id> allSubordinateRoleIds = getAllSubordinateRoleIds(allRoleIds);
            Set<Id> allUserIdsForRollup = new Set<Id>();
            for (User usr : [SELECT Id FROM User WHERE UserRoleId IN :allSubordinateRoleIds AND IsActive = true AND UserType = 'Standard']) {
                allUserIdsForRollup.add(usr.Id);
            }
            Date mtdStart = Date.today().toStartOfMonth();
            Date mtdEnd = Date.today();
            Map<String, Object> metrics = calculateMetricsForUsers(allUserIdsForRollup, mtdStart, mtdEnd);
            AssetSummaryResult result = new AssetSummaryResult();
            result.totalDF = (Integer)metrics.get('totalDF');
            result.billedDF = (Integer)metrics.get('billedDF');
            result.zeroBillingDF = (Integer)metrics.get('zeroBillingDF');
            result.throughput = (Decimal)metrics.get('throughput');
            return result;
        } catch (Exception e) {
            System.debug('Error in getAssetMetricsForUsers: ' + e.getMessage());
            return createDefaultResult();
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getAllFieldSubordinates(Id userId) {
        List<Map<String, Object>> allUsers = new List<Map<String, Object>>();
        try {
            if (userId == null) userId = UserInfo.getUserId();
            User currentUser = [SELECT UserRoleId FROM User WHERE Id = :userId AND UserType = 'Standard' LIMIT 1];
            if (currentUser.UserRoleId == null) return allUsers;
            Set<Id> subordinateRoleIds = getAllSubordinateRoleIds(new Set<Id>{currentUser.UserRoleId});
            List<User> subordinateUsers = [
                SELECT Id, Name, UserRole.Name, Phone
                FROM User 
                WHERE UserRoleId IN :subordinateRoleIds 
                AND IsActive = true AND UserType = 'Standard'
                ORDER BY Name
            ];
            if (subordinateUsers.isEmpty()) return allUsers;
            Set<Id> allUserIds = new Set<Id>();
            Map<Id, Map<String, String>> userInfoMap = new Map<Id, Map<String, String>>();
            for (User usr : subordinateUsers) {
                allUserIds.add(usr.Id);
                Map<String, String> userMap = new Map<String, String>();
                userMap.put('Id', usr.Id);
                userMap.put('Name', usr.Name);
                userMap.put('Role', usr.UserRole != null ? usr.UserRole.Name : 'N/A');
                userMap.put('Phone', usr.Phone != null ? usr.Phone : '');
                userInfoMap.put(usr.Id, userMap);
            }
            Date mtdStart = Date.today().toStartOfMonth();
            Date mtdEnd = Date.today();
            Map<Id, Map<String, Object>> userMetricsMap = calculateIndividualUserMetrics(allUserIds, mtdStart, mtdEnd);
            for (Id usrId : allUserIds) {
                Map<String, String> userInfo = userInfoMap.get(usrId);
                Map<String, Object> metrics = userMetricsMap.get(usrId);
                if (userInfo != null && metrics != null) {
                    Map<String, Object> userWithMetrics = new Map<String, Object>{
                        'userId' => usrId,
                        'name' => userInfo.get('Name'),
                        'role' => userInfo.get('Role'),
                        'phone' => userInfo.get('Phone'),
                        'totalDF' => (Integer)metrics.get('totalDF'),
                        'billedDF' => (Integer)metrics.get('billedDF'),
                        'zeroBillingDF' => (Integer)metrics.get('zeroBillingDF'),
                        'throughput' => ((Decimal)metrics.get('throughput')).setScale(2)
                    };
                    allUsers.add(userWithMetrics);
                }
            }
        } catch (Exception e) {
            System.debug('Error in getAllFieldSubordinates: ' + e.getMessage());
        }
        return allUsers;
    }
    
    @AuraEnabled(cacheable=true)
    public static AssetSummaryResult getUserOwnAssetMetrics(Id userId) {
        try {
            if (userId == null) userId = UserInfo.getUserId();
            Date mtdStart = Date.today().toStartOfMonth();
            Date mtdEnd = Date.today();
            User currentUser = getUserWithRole(userId);
            Map<String, Object> metrics = calculateSingleUserMetrics(userId, mtdStart, mtdEnd);
            AssetSummaryResult result = buildResultFromMetrics(currentUser, metrics);
            return result;
        } catch (Exception e) {
            System.debug('Error in getUserOwnAssetMetrics: ' + e.getMessage());
            return createErrorResult(userId, e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static AssetSummaryResult getUserRolledUpMetrics(Id userId) {
        try {
            if (userId == null) userId = UserInfo.getUserId();
            User currentUser = getUserWithRole(userId);
            Set<Id> allUserIds = getHierarchyUserIdsByRole(currentUser.UserRoleId);
            allUserIds.add(userId);
            Date mtdStart = Date.today().toStartOfMonth();
            Date mtdEnd = Date.today();
            Map<String, Object> rolledUpMetrics = calculateMetricsForUsers(allUserIds, mtdStart, mtdEnd);
            AssetSummaryResult result = buildResultFromMetrics(currentUser, rolledUpMetrics);
            return result;
        } catch (Exception e) {
            System.debug('Error in getUserRolledUpMetrics: ' + e.getMessage());
            return createErrorResult(userId, e.getMessage());
        }
    }
    
    // ============ OPTIMIZED METRICS CALCULATION METHODS ============
    
    private static Map<String, Object> calculateMetricsForUsers(Set<Id> userIds, Date startDate, Date endDate) {
        Map<String, Object> metrics = new Map<String, Object>{
            'totalDF' => 0,
            'billedDF' => 0,
            'zeroBillingDF' => 0,
            'throughput' => 0
        };
        
        if (userIds == null || userIds.isEmpty()) return metrics;
        
        try {
            List<AggregateResult> retailerCountResults = [
                SELECT COUNT(Id) retailerCount
                FROM Account 
                WHERE OwnerId IN :userIds 
                AND RecordType.Name = :RETAILER_RECORD_TYPE
            ];
            
            if (retailerCountResults.isEmpty() || (Integer)retailerCountResults[0].get('retailerCount') == 0) {
                return metrics;
            }
            
            // ================= CHANGED: Use Asset_Mapping__c instead of Asset__c =================
            List<AggregateResult> totalAssetResults = [
                SELECT COUNT(Id) assetCount
                FROM Asset_Mapping__c 
                WHERE Retailer__c IN (
                    SELECT Id 
                    FROM Account 
                    WHERE OwnerId IN :userIds 
                    AND RecordType.Name = :RETAILER_RECORD_TYPE
                )
                AND Active__c = true
            ];
            
            if (totalAssetResults.isEmpty() || (Integer)totalAssetResults[0].get('assetCount') == 0) {
                metrics.put('totalDF', 0);
                return metrics;
            }
            
            Integer totalDF = (Integer)totalAssetResults[0].get('assetCount');
            
            List<AggregateResult> orderResults = [
                SELECT Account__c retailerId, SUM(Total_Order_Value__c) totalValue
                FROM Order__c
                WHERE Account__c IN (
                    SELECT Id 
                    FROM Account 
                    WHERE OwnerId IN :userIds 
                    AND RecordType.Name = :RETAILER_RECORD_TYPE
                )
                AND RecordType.Name = :SECONDARY_ORDER_RECORD_TYPE
                AND Visit_Task__r.Task_Planned_Date__c >= :startDate 
                AND Visit_Task__r.Task_Planned_Date__c <= :endDate
                AND Visit_Task__r.Order_Placed__c = true
                GROUP BY Account__c
            ];
            
            Set<Id> retailersWithOrders = new Set<Id>();
            Decimal totalOrderValue = 0;
            for (AggregateResult ar : orderResults) {
                Id retailerId = (Id)ar.get('retailerId');
                Decimal orderValue = (Decimal)ar.get('totalValue');
                if (retailerId != null) {
                    retailersWithOrders.add(retailerId);
                    totalOrderValue += orderValue != null ? orderValue : 0;
                }
            }
            
            Integer billedDF = 0;
            if (!retailersWithOrders.isEmpty()) {
                // ================= CHANGED: Use Asset_Mapping__c instead of Asset__c =================
                List<AggregateResult> billedAssetResults = [
                    SELECT COUNT(Id) assetCount
                    FROM Asset_Mapping__c 
                    WHERE Retailer__c IN :retailersWithOrders
                    AND Active__c = true
                ];
                if (!billedAssetResults.isEmpty()) {
                    billedDF = (Integer)billedAssetResults[0].get('assetCount');
                }
            }
            
            Integer zeroBillingDF = totalDF - billedDF;
            Decimal throughput = (totalDF > 0 && totalOrderValue > 0) ? (totalOrderValue / totalDF) : 0;
            
            metrics.put('totalDF', totalDF);
            metrics.put('billedDF', billedDF);
            metrics.put('zeroBillingDF', zeroBillingDF);
            metrics.put('throughput', throughput.setScale(2));
            
        } catch (Exception e) {
            System.debug('Error in calculateMetricsForUsers: ' + e.getMessage() + ' - ' + e.getStackTraceString());
        }
        
        return metrics;
    }
    
    private static Map<String, Object> calculateSingleUserMetrics(Id userId, Date startDate, Date endDate) {
        Map<String, Object> metrics = new Map<String, Object>{
            'totalDF' => 0,
            'billedDF' => 0,
            'zeroBillingDF' => 0,
            'throughput' => 0
        };
        
        try {
            List<AggregateResult> retailerCountResults = [
                SELECT COUNT(Id) retailerCount
                FROM Account 
                WHERE OwnerId = :userId 
                AND RecordType.Name = :RETAILER_RECORD_TYPE
            ];
            
            if (retailerCountResults.isEmpty() || (Integer)retailerCountResults[0].get('retailerCount') == 0) {
                return metrics;
            }
            
            // ================= CHANGED: Use Asset_Mapping__c instead of Asset__c =================
            List<AggregateResult> assetResults = [
                SELECT COUNT(Id) assetCount
                FROM Asset_Mapping__c 
                WHERE Retailer__c IN (
                    SELECT Id 
                    FROM Account 
                    WHERE OwnerId = :userId 
                    AND RecordType.Name = :RETAILER_RECORD_TYPE
                )
                AND Active__c = true
            ];
            
            if (assetResults.isEmpty()) return metrics;
            
            Integer totalDF = (Integer)assetResults[0].get('assetCount');
            
            List<AggregateResult> orderResults = [
                SELECT Account__c retailerId, SUM(Total_Order_Value__c) totalValue
                FROM Order__c
                WHERE Account__c IN (
                    SELECT Id 
                    FROM Account 
                    WHERE OwnerId = :userId 
                    AND RecordType.Name = :RETAILER_RECORD_TYPE
                )
                AND RecordType.Name = :SECONDARY_ORDER_RECORD_TYPE
                AND Visit_Task__r.Task_Planned_Date__c >= :startDate 
                AND Visit_Task__r.Task_Planned_Date__c <= :endDate
                AND Visit_Task__r.Order_Placed__c = true
                GROUP BY Account__c
            ];
            
            Set<Id> retailersWithOrders = new Set<Id>();
            Decimal totalOrderValue = 0;
            for (AggregateResult ar : orderResults) {
                Id retailerId = (Id)ar.get('retailerId');
                Decimal orderValue = (Decimal)ar.get('totalValue');
                if (retailerId != null) {
                    retailersWithOrders.add(retailerId);
                    totalOrderValue += orderValue != null ? orderValue : 0;
                }
            }
            
            Integer billedDF = 0;
            if (!retailersWithOrders.isEmpty()) {
                // ================= CHANGED: Use Asset_Mapping__c instead of Asset__c =================
                List<AggregateResult> billedAssetResults = [
                    SELECT COUNT(Id) assetCount
                    FROM Asset_Mapping__c 
                    WHERE Retailer__c IN :retailersWithOrders
                    AND Active__c = true
                ];
                if (!billedAssetResults.isEmpty()) {
                    billedDF = (Integer)billedAssetResults[0].get('assetCount');
                }
            }
            
            Integer zeroBillingDF = totalDF - billedDF;
            Decimal throughput = (totalDF > 0 && totalOrderValue > 0) ? (totalOrderValue / totalDF) : 0;
            
            metrics.put('totalDF', totalDF);
            metrics.put('billedDF', billedDF);
            metrics.put('zeroBillingDF', zeroBillingDF);
            metrics.put('throughput', throughput.setScale(2));
            
        } catch (Exception e) {
            System.debug('Error in calculateSingleUserMetrics: ' + e.getMessage());
        }
        
        return metrics;
    }
    
    private static Map<Id, Map<String, Object>> calculateIndividualUserMetrics(Set<Id> userIds, Date startDate, Date endDate) {
        Map<Id, Map<String, Object>> metricsByUser = new Map<Id, Map<String, Object>>();
        
        if (userIds.isEmpty()) return metricsByUser;
        
        try {
            for (Id userId : userIds) {
                metricsByUser.put(userId, new Map<String, Object>{
                    'totalDF' => 0,
                    'billedDF' => 0,
                    'zeroBillingDF' => 0,
                    'throughput' => 0
                });
            }
            
            List<Id> userIdList = new List<Id>(userIds);
            Integer batchSize = 100;
            
            for (Integer i = 0; i < userIdList.size(); i += batchSize) {
                Integer endIdx = Math.min(i + batchSize, userIdList.size());
                Set<Id> batchUserIds = new Set<Id>();
                for (Integer j = i; j < endIdx; j++) {
                    batchUserIds.add(userIdList[j]);
                }
                
                List<AggregateResult> retailerResults = [
                    SELECT OwnerId, COUNT(Id) retailerCount
                    FROM Account 
                    WHERE OwnerId IN :batchUserIds 
                    AND RecordType.Name = :RETAILER_RECORD_TYPE
                    GROUP BY OwnerId
                ];
                
                if (retailerResults.isEmpty()) continue;
                
                Map<Id, Integer> retailerCountByUser = new Map<Id, Integer>();
                for (AggregateResult ar : retailerResults) {
                    Id ownerId = (Id)ar.get('OwnerId');
                    Integer count = (Integer)ar.get('retailerCount');
                    retailerCountByUser.put(ownerId, count);
                }
                
                // ================= CHANGED: Use Asset_Mapping__c instead of Asset__c =================
                List<AggregateResult> assetResults = [
                    SELECT a.Retailer__r.OwnerId ownerId, COUNT(Id) assetCount
                    FROM Asset_Mapping__c a
                    WHERE a.Retailer__r.OwnerId IN :batchUserIds
                    AND a.Retailer__r.RecordType.Name = :RETAILER_RECORD_TYPE
                    AND a.Active__c = true
                    GROUP BY a.Retailer__r.OwnerId
                ];
                
                Map<Id, Integer> assetCountByUser = new Map<Id, Integer>();
                for (AggregateResult ar : assetResults) {
                    Id ownerId = (Id)ar.get('ownerId');
                    Integer assetCount = (Integer)ar.get('assetCount');
                    assetCountByUser.put(ownerId, assetCount);
                }
                
                List<AggregateResult> orderResults = [
                    SELECT o.Account__r.OwnerId ownerId, SUM(o.Total_Order_Value__c) totalValue
                    FROM Order__c o
                    WHERE o.Account__r.OwnerId IN :batchUserIds
                    AND o.RecordType.Name = :SECONDARY_ORDER_RECORD_TYPE
                    AND o.Account__r.RecordType.Name = :RETAILER_RECORD_TYPE
                    AND o.Visit_Task__r.Task_Planned_Date__c >= :startDate 
                    AND o.Visit_Task__r.Task_Planned_Date__c <= :endDate
                    AND o.Visit_Task__r.Order_Placed__c = true
                    GROUP BY o.Account__r.OwnerId
                ];
                
                Map<Id, Decimal> orderValueByUser = new Map<Id, Decimal>();
                for (AggregateResult ar : orderResults) {
                    Id ownerId = (Id)ar.get('ownerId');
                    Decimal totalValue = (Decimal)ar.get('totalValue');
                    if (ownerId != null) {
                        orderValueByUser.put(ownerId, totalValue != null ? totalValue : 0);
                    }
                }
                
                for (Id userId : batchUserIds) {
                    Map<String, Object> userMetrics = metricsByUser.get(userId);
                    Integer totalDF = assetCountByUser.get(userId) != null ? assetCountByUser.get(userId) : 0;
                    Decimal totalOrderValue = orderValueByUser.get(userId) != null ? orderValueByUser.get(userId) : 0;
                    Integer billedDF = (totalOrderValue > 0 && totalDF > 0) ? totalDF : 0;
                    Integer zeroBillingDF = totalDF - billedDF;
                    Decimal throughput = (totalDF > 0 && totalOrderValue > 0) ? (totalOrderValue / totalDF) : 0;
                    userMetrics.put('totalDF', totalDF);
                    userMetrics.put('billedDF', billedDF);
                    userMetrics.put('zeroBillingDF', zeroBillingDF);
                    userMetrics.put('throughput', throughput);
                }
            }
            
        } catch (Exception e) {
            System.debug('Error in calculateIndividualUserMetrics: ' + e.getMessage() + ' - ' + e.getStackTraceString());
        }
        
        return metricsByUser;
    }
    
    private static List<AssetSummaryResult> getDirectSubordinatesWithRolledUp(Id parentUserId, Date mtdStart, Date mtdEnd) {
        List<AssetSummaryResult> subordinates = new List<AssetSummaryResult>();
        try {
            User parentUser = [SELECT Id, UserRoleId FROM User WHERE Id = :parentUserId AND UserType = 'Standard' LIMIT 1];
            if (parentUser.UserRoleId == null) return subordinates;
            List<UserRole> childRoles = [
                SELECT Id, Name FROM UserRole WHERE ParentRoleId = :parentUser.UserRoleId ORDER BY Name
            ];
            if (childRoles.isEmpty()) return subordinates;
            Set<Id> childRoleIds = new Set<Id>();
            for (UserRole role : childRoles) childRoleIds.add(role.Id);
            List<User> directSubs = [
                SELECT Id, Name, UserRoleId, UserRole.Name
                FROM User
                WHERE UserRoleId IN :childRoleIds
                AND IsActive = true AND UserType = 'Standard'
                ORDER BY Name
            ];
            if (directSubs.isEmpty()) return subordinates;
            for (User sub : directSubs) {
                AssetSummaryResult subResult = new AssetSummaryResult();
                subResult.userId = sub.Id;
                subResult.name = sub.Name;
                subResult.role = sub.UserRole != null ? sub.UserRole.Name : 'N/A';
                Set<Id> allSubordinateIds = getHierarchyUserIdsByRole(sub.UserRoleId);
                allSubordinateIds.add(sub.Id);
                Map<String, Object> subMetrics = calculateMetricsForUsers(allSubordinateIds, mtdStart, mtdEnd);
                subResult.totalDF = (Integer)subMetrics.get('totalDF');
                subResult.billedDF = (Integer)subMetrics.get('billedDF');
                subResult.zeroBillingDF = (Integer)subMetrics.get('zeroBillingDF');
                subResult.throughput = ((Decimal)subMetrics.get('throughput')).setScale(2);
                subordinates.add(subResult);
            }
        } catch (Exception e) {
            System.debug('Error in getDirectSubordinatesWithRolledUp: ' + e.getMessage());
        }
        return subordinates;
    }
    
    private static Set<Id> getAllSubordinateRoleIds(Set<Id> roleIds) {
        Set<Id> subordinateRoleIds = new Set<Id>();
        if (roleIds == null || roleIds.isEmpty()) return subordinateRoleIds;
        try {
            List<UserRole> allRoles = [SELECT Id, ParentRoleId FROM UserRole];
            Map<Id, List<Id>> roleChildren = new Map<Id, List<Id>>();
            for (UserRole role : allRoles) {
                if (role.ParentRoleId != null) {
                    if (!roleChildren.containsKey(role.ParentRoleId)) {
                        roleChildren.put(role.ParentRoleId, new List<Id>());
                    }
                    roleChildren.get(role.ParentRoleId).add(role.Id);
                }
            }
            for (Id roleId : roleIds) {
                List<Id> queue = new List<Id>{roleId};
                Set<Id> visited = new Set<Id>{roleId};
                while (!queue.isEmpty()) {
                    Id currentRoleId = queue.remove(0);
                    if (roleChildren.containsKey(currentRoleId)) {
                        for (Id childRoleId : roleChildren.get(currentRoleId)) {
                            if (!visited.contains(childRoleId)) {
                                visited.add(childRoleId);
                                subordinateRoleIds.add(childRoleId);
                                queue.add(childRoleId);
                            }
                        }
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error in getAllSubordinateRoleIds: ' + e.getMessage());
        }
        return subordinateRoleIds;
    }
    
    private static Set<Id> getHierarchyUserIdsByRole(Id roleId) {
        Set<Id> userIds = new Set<Id>();
        try {
            if (roleId != null) {
                Set<Id> subordinateRoleIds = getAllSubordinateRoleIds(new Set<Id>{roleId});
                if (!subordinateRoleIds.isEmpty()) {
                    for (User usr : [
                        SELECT Id FROM User 
                        WHERE UserRoleId IN :subordinateRoleIds 
                        AND IsActive = true AND UserType = 'Standard'
                    ]) {
                        userIds.add(usr.Id);
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error in getHierarchyUserIdsByRole: ' + e.getMessage());
        }
        return userIds;
    }
    
    private static User getUserWithRole(Id userId) {
        return [SELECT Id, Name, UserRoleId, UserRole.Name FROM User WHERE Id = :userId AND UserType = 'Standard' LIMIT 1];
    }
    
    private static AssetSummaryResult buildResultFromMetrics(User user, Map<String, Object> metrics) {
        AssetSummaryResult result = new AssetSummaryResult();
        result.userId = user.Id;
        result.name = user.Name != null ? user.Name : 'N/A';
        result.role = user.UserRole != null ? user.UserRole.Name : 'N/A';
        result.totalDF = (Integer)metrics.get('totalDF');
        result.billedDF = (Integer)metrics.get('billedDF');
        result.zeroBillingDF = (Integer)metrics.get('zeroBillingDF');
        result.throughput = ((Decimal)metrics.get('throughput')).setScale(2);
        return result;
    }
    
    private static AssetSummaryResult createErrorResult(Id userId, String errorMessage) {
        System.debug('Creating error result: ' + errorMessage);
        AssetSummaryResult errorResult = new AssetSummaryResult();
        errorResult.userId = userId != null ? String.valueOf(userId) : '';
        errorResult.name = 'Error';
        errorResult.role = 'N/A';
        return errorResult;
    }
    
    private static AssetSummaryResult createDefaultResult() {
        return new AssetSummaryResult();
    }
}