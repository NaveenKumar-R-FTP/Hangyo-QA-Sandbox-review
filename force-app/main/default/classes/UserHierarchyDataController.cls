public with sharing class UserHierarchyDataController {
    
    private static Map<Id, Id> userToRoleMap;
    private static Map<Id, Set<Id>> parentRoleToChildRoles;
    private static Map<Id, Set<Id>> roleToUserIds;

    public class MetricsDTO {
        @AuraEnabled public Integer plannedCount = 0;
        @AuraEnabled public Integer tlcCount = 0; 
        @AuraEnabled public Decimal netPay = 0;
        @AuraEnabled public Decimal qty = 0;
    }
    
    public class UserNode {
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String roleName;
        @AuraEnabled public MetricsDTO metrics;
        @AuraEnabled public List<UserNode> directSubordinates;

        public UserNode() {
            this.metrics = new MetricsDTO();
            this.directSubordinates = new List<UserNode>();
        }
    }
    
    public class HierarchyResponse {
        @AuraEnabled public UserNode parentUser;
    }
    
    @AuraEnabled(cacheable=true)
    public static HierarchyResponse getHierarchyWithMetrics(Id rootUserId) {
        if (rootUserId == null) rootUserId = UserInfo.getUserId();
        
        initializeCaches();
        Set<Id> allRelevantUserIds = new Set<Id>();
        collectAllSubordinateIds(rootUserId, allRelevantUserIds);
        allRelevantUserIds.add(rootUserId);
        
        // Match filter from mockup: Active Standard Users
        Map<Id, User> userMap = new Map<Id, User>([SELECT Id, Name, UserRoleId, UserRole.Name 
                                                   FROM User WHERE Id IN :allRelevantUserIds 
                                                   AND IsActive = true AND UserType = 'Standard']);
        
        Map<Id, MetricsDTO> metricsMap = computeMetricsForUserSet(allRelevantUserIds);
        
        HierarchyResponse resp = new HierarchyResponse();
        resp.parentUser = buildNodeWithRollup(rootUserId, userMap, metricsMap, new Set<Id>());
        return resp;
    }
    
    private static UserNode buildNodeWithRollup(Id uId, Map<Id, User> userMap, Map<Id, MetricsDTO> mMap, Set<Id> visited) {
        if (visited.contains(uId)) return null;
        visited.add(uId);
        
        User u = userMap.get(uId);
        UserNode node = new UserNode();
        node.userId = uId;
        node.userName = (u != null) ? u.Name : 'Unknown';
        node.roleName = (u != null && u.UserRole != null) ? u.UserRole.Name : '';
        
        if (mMap.containsKey(uId)) {
            MetricsDTO own = mMap.get(uId);
            node.metrics.plannedCount = own.plannedCount;
            node.metrics.tlcCount = own.tlcCount;
            node.metrics.netPay = own.netPay;
            node.metrics.qty = own.qty;
        }
        
        if (u != null && u.UserRoleId != null) {
            for (Id subId : findDirectSubUsers(u.UserRoleId, userMap)) {
                UserNode child = buildNodeWithRollup(subId, userMap, mMap, visited);
                if (child != null) {
                    node.directSubordinates.add(child);
                    // Rollup values to Parent
                    node.metrics.plannedCount += child.metrics.plannedCount;
                    node.metrics.tlcCount     += child.metrics.tlcCount;
                    node.metrics.netPay       += child.metrics.netPay;
                    node.metrics.qty          += child.metrics.qty;
                }
            }
        }
        return node;
    }

  private static Map<Id, MetricsDTO> computeMetricsForUserSet(Set<Id> userIds) {
    Map<Id, MetricsDTO> resultMap = new Map<Id, MetricsDTO>();
    for (Id u : userIds) resultMap.put(u, new MetricsDTO());
    Date today = Date.today();
    
    // 1. PLANNED & 3. NET PAY & 4. QTY 
    // (These are safe because they group by User, and you likely have < 2000 users)
    for (AggregateResult ar : [SELECT Visitor_Name__c uId, COUNT(Id) c FROM Visit__c 
                               WHERE Visitor_Name__c IN :userIds AND Visit_Planned_Date__c = :today 
                               GROUP BY Visitor_Name__c]) {
        resultMap.get((Id)ar.get('uId')).plannedCount = (Integer)ar.get('c');
    }

    for (AggregateResult ar : [SELECT Visit_Task__r.Visitor_Name__c uId, SUM(Total_Order_Value__c) v FROM Order__c 
                               WHERE Visit_Task__r.Visitor_Name__c IN :userIds AND Visit_Task__r.Task_Planned_Date__c = :today 
                               AND RecordType.DeveloperName = 'Secondary_Order' AND Visit_Task__r.Order_Placed__c = true 
                               GROUP BY Visit_Task__r.Visitor_Name__c]) {
        resultMap.get((Id)ar.get('uId')).netPay = (Decimal)ar.get('v');
    }

    for (AggregateResult ar : [SELECT Visit__r.Visitor_Name__c uId, SUM(Sum_of_Ordered_Quantity__c) q FROM Order__c 
                               WHERE Visit__r.Visitor_Name__c IN :userIds AND Visit__r.Visit_Planned_Date__c = :today 
                               AND RecordType.DeveloperName = 'Secondary_Order' GROUP BY Visit__r.Visitor_Name__c]) {
        resultMap.get((Id)ar.get('uId')).qty = (Decimal)ar.get('q');
    }

    // 2. FIXED TOTAL LINES CUT (TLC)
    // We use a standard SOQL loop to avoid the 2,000 row "queryMore" limit.
    // This allows us to handle 50,000+ records safely.
    Map<Id, Set<String>> orderToProducts = new Map<Id, Set<String>>();
    Map<Id, Id> orderToUser = new Map<Id, Id>();

    for (Order_Line_Item__c oli : [SELECT Order__c, Products__c, Order__r.Visit__r.Visitor_Name__c 
                                   FROM Order_Line_Item__c 
                                   WHERE Order__r.Visit__r.Visitor_Name__c IN :userIds 
                                   AND Order__r.Visit__r.Visit_Planned_Date__c = :today]) {
        
        // Track which user owns this order
        orderToUser.put(oli.Order__c, oli.Order__r.Visit__r.Visitor_Name__c);
        
        // Group unique products by Order ID
        if (!orderToProducts.containsKey(oli.Order__c)) {
            orderToProducts.put(oli.Order__c, new Set<String>());
        }
        orderToProducts.get(oli.Order__c).add(oli.Products__c);
    }

    // Now aggregate the unique counts per order back to the user
    for (Id orderId : orderToProducts.keySet()) {
        Id userId = orderToUser.get(orderId);
        Integer uniqueProductsInThisOrder = orderToProducts.get(orderId).size();
        
        if (resultMap.containsKey(userId)) {
            resultMap.get(userId).tlcCount += uniqueProductsInThisOrder;
        }
    }
        
    return resultMap;
}

    private static void initializeCaches() {
        if (userToRoleMap != null) return;
        userToRoleMap = new Map<Id, Id>();
        roleToUserIds = new Map<Id, Set<Id>>();
        parentRoleToChildRoles = new Map<Id, Set<Id>>();
        for (User u : [SELECT Id, UserRoleId FROM User WHERE IsActive = true AND UserType = 'Standard']) {
            if (u.UserRoleId != null) {
                userToRoleMap.put(u.Id, u.UserRoleId);
                if (!roleToUserIds.containsKey(u.UserRoleId)) roleToUserIds.put(u.UserRoleId, new Set<Id>());
                roleToUserIds.get(u.UserRoleId).add(u.Id);
            }
        }
        for (UserRole r : [SELECT Id, ParentRoleId FROM UserRole WHERE ParentRoleId != null]) {
            if (!parentRoleToChildRoles.containsKey(r.ParentRoleId)) parentRoleToChildRoles.put(r.ParentRoleId, new Set<Id>());
            parentRoleToChildRoles.get(r.ParentRoleId).add(r.Id);
        }
    }

    private static void collectAllSubordinateIds(Id userId, Set<Id> allUserIds) {
        Id roleId = userToRoleMap.get(userId);
        if (roleId == null) return;
        List<Id> queue = new List<Id>{roleId};
        while(!queue.isEmpty()){
            Id current = queue.remove(0);
            if(parentRoleToChildRoles.containsKey(current)){
                for(Id child : parentRoleToChildRoles.get(current)){
                    queue.add(child);
                    if(roleToUserIds.containsKey(child)) allUserIds.addAll(roleToUserIds.get(child));
                }
            }
        }
    }

    private static List<Id> findDirectSubUsers(Id roleId, Map<Id, User> userMap) {
        List<Id> ids = new List<Id>();
        if (!parentRoleToChildRoles.containsKey(roleId)) return ids;
        for (Id childRole : parentRoleToChildRoles.get(roleId)) {
            if (roleToUserIds.containsKey(childRole)) {
                for(Id uId : roleToUserIds.get(childRole)) if(userMap.containsKey(uId)) ids.add(uId);
            } else {
                ids.addAll(findDirectSubUsers(childRole, userMap)); 
            }
        }
        return ids;
    }
}