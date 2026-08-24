public without sharing class UserHierarchyService {
    
    public class UserHierarchyResult {
        @AuraEnabled public Integer totalUsers;
        @AuraEnabled public List<Map<String, String>> users; // changed
        public UserHierarchyResult(Integer totalUsers, List<Map<String,String>> users) {
            this.totalUsers = totalUsers;
            this.users = users;
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static UserHierarchyResult getSubordinatesincludeself(Id parentUserId) {
        
		User parentUser = [SELECT Id, UserRoleId, Name, UserRole.Name, Employee_Role__c FROM User WHERE Id = :parentUserId LIMIT 1];
        System.debug('query1 parentUser----> ' + parentUser);
        
        if (parentUser.UserRoleId == null) return new UserHierarchyResult(0, new List<Map<String,String>>());
        
        Set<Id> childRoles = getChildRolesRecursive(new Set<Id>{ parentUser.UserRoleId });
        
        List<User> users = [SELECT Id, Name, UserRole.Name, MobilePhone, Employee_Role__c FROM User WHERE UserRoleId IN :childRoles AND IsActive = true AND UserType = 'Standard'];
        System.debug('query2 users----> ' + users);
        
        // Map to plain JS-friendly objects
        List<Map<String,String>> userList = new List<Map<String,String>>();
        
		
        for(User u : users){
            Map<String,String> m = new Map<String,String>();
            m.put('Id', u.Id);
            m.put('Name', u.Name);
            m.put('Phone', u.MobilePhone);
            m.put('Employee_Role__c', u.Employee_Role__c);
            m.put('Role', u.UserRole != null ? u.UserRole.Name : 'N/A');
            userList.add(m);
        }
        
        return new UserHierarchyResult(userList.size(), userList);
    }
    
    @AuraEnabled(cacheable=true)
    public static UserHierarchyResult getSubordinates(Id parentUserId) {
        User parentUser = [SELECT Id, UserRoleId, Name, UserRole.Name, Employee_Role__c FROM User WHERE Id = :parentUserId LIMIT 1];
        
		System.debug('query3 parentUser----> ' + parentUser);
        
        if (parentUser.UserRoleId == null) return new UserHierarchyResult(0, new List<Map<String,String>>());
        
        Set<Id> childRoles = getChildRolesRecursive(new Set<Id>{ parentUser.UserRoleId });
        childRoles.remove(parentUser.UserRoleId);
        
        List<User> users = [SELECT Id, Name, UserRole.Name, MobilePhone, Employee_Role__c FROM User WHERE UserRoleId IN :childRoles AND IsActive = true AND UserType = 'Standard'];
        
		System.debug('query4 users----> ' + users);
        
        List<Map<String,String>> userList = new List<Map<String,String>>();
        for(User u : users){
            Map<String,String> m = new Map<String,String>();
            m.put('Id', u.Id);
            m.put('Name', u.Name);
            m.put('Phone', u.MobilePhone);
            m.put('Employee_Role__c', u.Employee_Role__c);
            userList.add(m);
        }
        
        return new UserHierarchyResult(userList.size(), userList);
    }
    
    @AuraEnabled(cacheable=true)
    public static UserHierarchyResult getSubordinatesnosameroleusers(Id parentUserId) {
        // 1️⃣ Fetch parent user
        User parentUser = [
            SELECT Id, UserRoleId, Name, UserRole.Name, UserType, Employee_Role__c 
            FROM User 
            WHERE Id = :parentUserId 
            LIMIT 1
        ];
        
        System.debug('query5 parentUser----> ' + parentUser);
        
        // 2️⃣ If no role, return only parent (if not partner user)
        if (parentUser.UserRoleId == null || isPartnerUser(parentUser)) {
            List<Map<String,String>> onlyParent = new List<Map<String,String>>();
            if (!isPartnerUser(parentUser)) {
                onlyParent.add(new Map<String,String>{
                    'Id' => parentUser.Id, 
                    'Name' => parentUser.Name, 
                    'Employee_Role__c' => parentUser.Employee_Role__c,
                    'Role' => parentUser.UserRole != null ? parentUser.UserRole.Name : 'N/A'
                });
            }
            return new UserHierarchyResult(onlyParent.size(), onlyParent);
        }
        
        // 3️⃣ Get all child roles recursively
        Set<Id> childRoles = getChildRolesRecursive(new Set<Id>{ parentUser.UserRoleId });
        
        // 4️⃣ Remove parent role (exclude same-role users)
        childRoles.remove(parentUser.UserRoleId);
        
        // 5️⃣ Query parent + all subordinates in child roles (exclude Partner users)
        List<User> users = [
            SELECT Id, Name, UserRole.Name, UserType , MobilePhone, Employee_Role__c
            FROM User 
            WHERE (Id = :parentUserId OR UserRoleId IN :childRoles)
            AND IsActive = true
            AND  UserType = 'Standard'
        ];
        
        System.debug('query6 users----> ' + users);
        
        // 6️⃣ Map to JS-friendly objects without duplicates
        List<Map<String,String>> userList = new List<Map<String,String>>();
        Set<Id> addedIds = new Set<Id>();
        for (User u : users) {
            if (!addedIds.contains(u.Id)) {
                Map<String,String> m = new Map<String,String>();
                m.put('Id', u.Id);
                m.put('Name', u.Name);
                m.put('Phone', u.MobilePhone);
                m.put('Employee_Role__c', u.Employee_Role__c);
                m.put('Role', u.UserRole != null ? u.UserRole.Name : 'N/A');
                userList.add(m);
                addedIds.add(u.Id);
            }
        }
        
        return new UserHierarchyResult(userList.size(), userList);
    }
    
    @AuraEnabled(cacheable=true)
    public static UserHierarchyResult getDirectSubordinates(Id parentUserId) {
        
        system.debug('==== getDirectSubordinates called for parentUserId: ' + parentUserId + ' ====');
        
        // 1️⃣ Fetch parent user
        User parentUser = [SELECT Id, UserRoleId, Name, UserRole.Name, UserType, Employee_Role__c FROM User WHERE Id = :parentUserId LIMIT 1];
        
         system.debug('Parent User fetched: ' + parentUser.Name + ', RoleId: ' + parentUser.UserRoleId);
        
        // 2️⃣ If user has no role or is partner, return parent only
        if (parentUser.UserRoleId == null || isPartnerUser(parentUser)) {
            List<Map<String,String>> onlyParent = new List<Map<String,String>>();
            onlyParent.add(new Map<String,String>{
                'Id' => parentUser.Id,
                    'Name' => parentUser.Name,
                    'Role' => parentUser.UserRole != null ? parentUser.UserRole.Name : 'N/A'
                        });
            system.debug('Parent has no role or is a partner user. Returning empty list.');
            return new UserHierarchyResult(onlyParent.size(), onlyParent);
        }
        
        // ⭐️ 3️⃣ Fetch ONLY DIRECT CHILD ROLES (NO recursion)
        Set<Id> directChildRoles = new Set<Id>();
        
        for (UserRole ur : [SELECT Id FROM UserRole WHERE ParentRoleId = :parentUser.UserRoleId
        ]) {
            directChildRoles.add(ur.Id);
        }
        
        system.debug('Direct child roles count: ' + directChildRoles.size());
        
        // 4️⃣ Query parent + users in only DIRECT child role
        List<User> users = [
            SELECT Id, Name, UserRole.Name, UserType, MobilePhone, Employee_Role__c FROM User WHERE (Id = :parentUserId OR UserRoleId IN :directChildRoles)
            AND IsActive = true
            AND  UserType = 'Standard'
        ];
        
         system.debug('Users fetched in direct child roles: ' + users.size());
        
        // 5️⃣ Prepare clean result
        List<Map<String,String>> userList = new List<Map<String,String>>();
        Set<Id> added = new Set<Id>();
        
        for (User u : users) {
            if (!added.contains(u.Id)) {
                Map<String,String> m = new Map<String,String>{
                    'Id' => u.Id,
                        'Name' => u.Name,
                        'Phone' => u.MobilePhone,
                        'Role' => u.UserRole != null ? u.UserRole.Name : 'N/A',
                        'Employee_Role__c' => u.Employee_Role__c
                            };
                                userList.add(m);
                added.add(u.Id);
            }
        }
        
        return new UserHierarchyResult(userList.size(), userList);
    }
    
    public static Set<Id> getAllSubordinateUsers(Set<Id> userIds) {
        Set<Id> allUsersRecursive = new Set<Id>();
        allUsersRecursive.addAll(userIds);
        
        // 1️⃣ Get roles of passed users
        Map<Id, Id> userRoleMap = new Map<Id, Id>();
        for (User u : [
            SELECT Id, UserRoleId , Employee_Role__c
            FROM User 
            WHERE Id IN :userIds AND UserType = 'Standard'
        ]) {
            userRoleMap.put(u.Id, u.UserRoleId);
        }
        
        // 2️⃣ Query ALL roles once (NO SOQL IN RECURSION NOW)
        Map<Id, List<Id>> parentToChildren = new Map<Id, List<Id>>();
        for (UserRole r : [
            SELECT Id, ParentRoleId 
            FROM UserRole
        ]) {
            if (!parentToChildren.containsKey(r.ParentRoleId)) {
                parentToChildren.put(r.ParentRoleId, new List<Id>());
            }
            parentToChildren.get(r.ParentRoleId).add(r.Id);
        }
        
        // 3️⃣ Recursively gather children roles in memory
        Set<Id> allRolesRecursive = new Set<Id>();
        for (Id roleId : userRoleMap.values()) {
            if (roleId != null) {
                allRolesRecursive.addAll(
                    collectChildRoles(roleId, parentToChildren)
                );
            }
        }
        
        // 4️⃣ Query users under these roles
        for (User u : [
            SELECT Id, Employee_Role__c
            FROM User
            WHERE UserRoleId IN :allRolesRecursive AND UserType = 'Standard'
        ]) {
            allUsersRecursive.add(u.Id);
        }
        
        return allUsersRecursive;
    }
    private static Set<Id> collectChildRoles(Id parentRoleId, Map<Id, List<Id>> parentToChildren) {
        Set<Id> result = new Set<Id>();
        if (parentToChildren.containsKey(parentRoleId)) {
            for (Id childRoleId : parentToChildren.get(parentRoleId)) {
                if (!result.contains(childRoleId)) {
                    result.add(childRoleId);
                    result.addAll(collectChildRoles(childRoleId, parentToChildren)); // recursion in memory
                }
            }
        }
        return result;
    }
    



    
    // 🔁 Recursive method to get all child roles
    public static Set<Id> getChildRolesRecursive(Set<Id> roleIds) {
        Set<Id> allRoles = new Set<Id>(roleIds);
        List<UserRole> children = [
            SELECT Id 
            FROM UserRole 
            WHERE ParentRoleId IN :roleIds
        ];
        
        System.debug('query7 children----> ' + children);
        
        Set<Id> childRoleIds = new Set<Id>();
        for (UserRole r : children) {
            if (!allRoles.contains(r.Id)) {
                allRoles.add(r.Id);
                childRoleIds.add(r.Id);
            }
        }
        if (!childRoleIds.isEmpty()) {
            allRoles.addAll(getChildRolesRecursive(childRoleIds));
        }
        return allRoles;
    }

    // 🧩 Helper to check Partner/External users
    private static Boolean isPartnerUser(User u) {
        return (u.UserType == 'PowerPartner' ||
                u.UserType == 'Partner' ||
                u.UserType == 'CustomerPortal' ||
                u.UserType == 'CsnOnly');
    }

    // 📊 For summary use
    @AuraEnabled(cacheable=true)
    public static Map<Id, Integer> getTotalSubordinates(List<Id> userIds) {
        Map<Id, Integer> totals = new Map<Id, Integer>();
        for (Id uid : userIds) {
            UserHierarchyResult res = getSubordinatesnosameroleusers(uid);
            totals.put(uid, res.totalUsers);
        }
        return totals;
    }
    
    public static Set<Id> getAllSubordinateIds(Id userId) {
        Set<Id> userIds = new Set<Id>();
        userIds.add(userId);

        // Map to hold manager ID and their direct reports
        Set<Id> managersToQuery = new Set<Id>{userId};
        Set<Id> processedManagers = new Set<Id>();

        // Recursive query to build the hierarchy map
        while (!managersToQuery.isEmpty()) {
            Set<Id> nextLevelManagers = new Set<Id>();
            
            // Query only users whose ManagerId is in the current level, and who haven't been added yet
            for (User u : [SELECT Id FROM User WHERE ManagerId IN :managersToQuery AND Id NOT IN :userIds AND UserType = 'Standard']) {
                userIds.add(u.Id);
                nextLevelManagers.add(u.Id);
            }
            processedManagers.addAll(managersToQuery);
            managersToQuery = nextLevelManagers;
            managersToQuery.removeAll(processedManagers); // Ensure we don't requery old managers
        }

        return userIds;
    }
    
}