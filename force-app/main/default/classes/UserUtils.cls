public with sharing class UserUtils {
    
    // Static method to get all subordinate user Ids for the logged-in user
    public static Set<Id> getSubordinateUserIds() {
        // Fetch the logged-in user's ID
        String userId = UserInfo.getUserId();
        
        // Fetch the logged-in user's role
        User currentUser = [
            SELECT Id, UserRoleId 
            FROM User 
            WHERE Id = :userId
            LIMIT 1
        ];
        
        // Initialize the set with the logged-in user ID
        Set<Id> userIds = new Set<Id>{userId}; 
        
        // Fetch subordinate roles
        List<UserRole> subRoles = [
            SELECT Id 
            FROM UserRole 
            WHERE ParentRoleId = :currentUser.UserRoleId
        ];
        
        // If there are subordinate roles, fetch the users in those roles
        if (!subRoles.isEmpty()) {
            List<User> subUsers = [
                SELECT Id 
                FROM User 
                WHERE UserRoleId IN :subRoles
            ];
            
            // Add the subordinate user IDs to the set
            for (User u : subUsers) {
                userIds.add(u.Id);
            }
        }
        
        return userIds; // Return the set of all subordinate user IDs
    }
}