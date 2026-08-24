/**
 * ClassName : GetSubOrinates.cls
 * Description : This class is used to fetch the user IDs under the current user based on the role hierarchy.
 * Author : Gleveta 
 * Created On : July 25, 2025
 * Last Modified By :
 * Last Modified On : July 25, 2025
 **/
public with sharing class GetSubOrinates {
    public static Set<Id> getSubOrinatesUserIds() {
       Id currentUserId = UserInfo.getUserId();
        User currentUser = [SELECT Id, UserRoleId FROM User WHERE Id = :currentUserId LIMIT 1];
       
        Set<Id> userIds = new Set<Id>();
        userIds.add(currentUserId);
       
        if (currentUser.UserRoleId != null) {
            List<UserRole> allRoles = [SELECT Id, ParentRoleId FROM UserRole];
           
            Map<Id, List<Id>> roleHierarchyMap = new Map<Id, List<Id>>();
            for (UserRole role : allRoles) {
                if (!roleHierarchyMap.containsKey(role.ParentRoleId)) {
                    roleHierarchyMap.put(role.ParentRoleId, new List<Id>());
                }
                roleHierarchyMap.get(role.ParentRoleId).add(role.Id);
            }
           
            Set<Id> childRoleIds = new Set<Id>();
            collectChildRoles(roleHierarchyMap, currentUser.UserRoleId, childRoleIds);
           
            for (User u : [SELECT Id FROM User WHERE UserRoleId IN :childRoleIds AND IsActive = true]) {
                userIds.add(u.Id);
            }
        }
        
        return userIds;
    }

     private static void collectChildRoles(Map<Id, List<Id>> roleMap, Id parentId, Set<Id> collector) {
        if (!roleMap.containsKey(parentId)) return;
        
        for (Id childId : roleMap.get(parentId)) {
            collector.add(childId);
            collectChildRoles(roleMap, childId, collector); // Recurse
        }
    }

}