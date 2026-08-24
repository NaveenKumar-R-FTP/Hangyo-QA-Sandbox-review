public with sharing class AdditionalScreenMockupController {
    
    // ---------- STATIC CACHES ----------
    private static Map<Id, Id> GLOBAL_userRoleMap;
    private static Map<Id, Set<Id>> GLOBAL_parentRoleToChildRoles;
    private static Map<Id, Set<Id>> GLOBAL_roleToUserIds;
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getKpiCounts(Id userId) {
        System.debug('=== getKpiCounts called with userId: ' + userId);
        
        Map<String, Integer> result = new Map<String, Integer>{
            /*'Distributor' => 0,
                'Beats' => 0,
                'Outlets' => 0,*/
                'Planned' => 0,
                /*'UPC' => 0,
                'UTC' => 0,*/
                'LPC' => 0,
                'NetPay' => 0,
                'QTY' => 0,
                'TLC' => 0
                };
                    
                    if (userId == null) {
                        System.debug('UserId is null. Returning empty result.');
                        return result;
                    }
        
        Set<Id> allUserIds = new Set<Id>();
        collectAllSubordinateIdsByRole(userId, allUserIds);
        allUserIds.add(userId);
        
        System.debug('All relevant user IDs (role-based, no same role): ' + allUserIds);
        
        //result.put('Distributor', [SELECT COUNT() FROM Account WHERE RecordType.DeveloperName = 'Distributor' AND OwnerId IN :allUserIds]);
        //result.put('Beats', [SELECT COUNT() FROM Beat__c WHERE OwnerId IN :allUserIds]);
        //result.put('Outlets', [SELECT COUNT() FROM Account WHERE RecordType.DeveloperName = 'Retailer' AND OwnerId IN :allUserIds]);
        
        Date today = Date.today();
        result.put('Planned', [SELECT COUNT() FROM Visit__c WHERE Visitor_Name__c IN :allUserIds AND Visit_Planned_Date__c = :today]);
        
        /*result.put('UPC', [SELECT COUNT() FROM Visit_Task__c WHERE Visitor_Name__c IN :allUserIds AND Visit__r.Visit_Planned_Date__c = :today 
                           AND Id IN (SELECT Visit_Task__c FROM Order__c)]);
        
        result.put('UTC', [SELECT COUNT() FROM Visit_Task__c WHERE Visitor_Name__c IN :allUserIds AND Visit__r.Visit_Planned_Date__c = :today]);*/
        
        AggregateResult arSum = [SELECT SUM(Total_Order_Value__c) totalorder FROM Order__c WHERE Visit_Task__r.Visitor_Name__c IN :allUserIds
                              AND Visit_Task__r.Task_Planned_Date__c = :today AND RecordType.DeveloperName = 'Secondary_Order' AND Visit_Task__r.Order_Placed__c = true];
        
     
        
        Decimal tov = (Decimal) arSum.get('totalorder');
        result.put('NetPay', tov != null ? tov.intValue() : 0);
                
        List<Order_Line_Item__c> oliList = [SELECT Id, Products__c, Order__c FROM Order_Line_Item__c
                                            WHERE Order__r.Visit__r.Visitor_Name__c IN :allUserIds AND Order__r.Visit__r.Visit_Planned_Date__c = :today];

        
        Map<Id, Set<String>> orderToUniqueProducts = new Map<Id, Set<String>>();
        
        for (Order_Line_Item__c oli : oliList) {
            if (!orderToUniqueProducts.containsKey(oli.Order__c)) {
                orderToUniqueProducts.put(oli.Order__c, new Set<String>());
            }
            orderToUniqueProducts.get(oli.Order__c).add(oli.Products__c);
        }
        
        Integer totalUniqueProducts = 0;
        for (Id orderId : orderToUniqueProducts.keySet()) {
            totalUniqueProducts += orderToUniqueProducts.get(orderId).size();
        }
        
        Integer plannedCount = result.get('Planned');
        
        System.debug('plannedCount = ' + plannedCount);
        
        
        if (plannedCount > 0) {
            result.put('LPC', totalUniqueProducts / plannedCount);
        } else {
            result.put('LPC', 0);
        }
        
        System.debug('totalUniqueProducts = ' + totalUniqueProducts);
        
        result.put('TLC', totalUniqueProducts);
        
        AggregateResult ar = [SELECT SUM(Sum_of_Ordered_Quantity__c) totalQty FROM Order__c WHERE Visit__r.Visitor_Name__c IN :allUserIds
                              AND Visit__r.Visit_Planned_Date__c = :today AND RecordType.DeveloperName = 'Secondary_Order'];
        
        Decimal qty = (Decimal) ar.get('totalQty');
        result.put('QTY', qty != null ? qty.intValue() : 0);
        
        System.debug('Final KPI map: ' + result);
        return result;
    }
    
    // ---------- ROLE-BASED SUBORDINATE COLLECTION ----------
    private static void collectAllSubordinateIdsByRole(Id userId, Set<Id> allUserIds) {
        if (userId == null) return;
        
        // ---------- LOAD STATIC CACHES ONCE ----------
        if (GLOBAL_userRoleMap == null) {
            GLOBAL_userRoleMap = new Map<Id, Id>();
            GLOBAL_roleToUserIds = new Map<Id, Set<Id>>();
            GLOBAL_parentRoleToChildRoles = new Map<Id, Set<Id>>();
            
            // Load all active standard users
            for (User u : [SELECT Id, UserRoleId FROM User WHERE IsActive = true AND UserType = 'Standard']) {
                if (u.UserRoleId != null) {
                    GLOBAL_userRoleMap.put(u.Id, u.UserRoleId);
                    
                    if (!GLOBAL_roleToUserIds.containsKey(u.UserRoleId)) {
                        GLOBAL_roleToUserIds.put(u.UserRoleId, new Set<Id>());
                    }
                    GLOBAL_roleToUserIds.get(u.UserRoleId).add(u.Id);
                }
            }
            
            // Load role hierarchy
            for (UserRole r : [SELECT Id, ParentRoleId FROM UserRole WHERE ParentRoleId != null]) {
                if (!GLOBAL_parentRoleToChildRoles.containsKey(r.ParentRoleId)) {
                    GLOBAL_parentRoleToChildRoles.put(r.ParentRoleId, new Set<Id>());
                }
                GLOBAL_parentRoleToChildRoles.get(r.ParentRoleId).add(r.Id);
            }
        }
        
        // ---------- START BFS ----------
        Id startingRoleId = GLOBAL_userRoleMap.get(userId);
        if (startingRoleId == null) return;
        
        Set<Id> visitedRoles = new Set<Id>();
        List<Id> queue = new List<Id>();
        
        // Enqueue direct child roles
        if (GLOBAL_parentRoleToChildRoles.containsKey(startingRoleId)) {
            queue.addAll(GLOBAL_parentRoleToChildRoles.get(startingRoleId));
        }
        
        while (!queue.isEmpty()) {
            Id roleId = queue.remove(0);
            if (visitedRoles.contains(roleId)) continue;
            visitedRoles.add(roleId);
            
            // Add all users in this child role
            if (GLOBAL_roleToUserIds.containsKey(roleId)) {
                allUserIds.addAll(GLOBAL_roleToUserIds.get(roleId));
            }
            
            // Enqueue deeper child roles
            if (GLOBAL_parentRoleToChildRoles.containsKey(roleId)) {
                queue.addAll(GLOBAL_parentRoleToChildRoles.get(roleId));
            }
        }
        
        System.debug('All subordinate IDs collected (role-based, excluding same role): ' + allUserIds);
    }
}