trigger Beat_Trigger on Beat__c (before update, after update) {
    
    if (Trigger.isBefore && Trigger.isUpdate) {

        // Fetch current user's role and profile
        String userProfileName = [
            SELECT Profile.Name 
            FROM User 
            WHERE Id = :UserInfo.getUserId()
        ].Profile.Name;

        User currentUser = [
            SELECT UserRole.Name, Employee_Role__c 
            FROM User 
            WHERE Id = :UserInfo.getUserId()
        ];

        String userRoleName = currentUser.Employee_Role__c;

        Boolean isAuthorized = userProfileName == 'System Administrator' || userRoleName == 'ASM';

        Boolean shouldSync = false;

        for (Beat__c beat : Trigger.new) {
            Beat__c oldBeat = Trigger.oldMap.get(beat.Id);
    
            Boolean ownerChanged       = beat.OwnerId != oldBeat.OwnerId;
            Boolean employeeChanged    = beat.Employee_Name__c != oldBeat.Employee_Name__c;
            Boolean distributorChanged = beat.Distributor_Name__c != oldBeat.Distributor_Name__c;
    
            // Restrict changes to Owner, Employee, and Distributor for unauthorized users
            if ((ownerChanged || employeeChanged || distributorChanged) && !isAuthorized) {
                beat.addError('Only ASM and System Administrators are allowed to change the Owner, Employee Name, or Distributor of a Beat.');
            }
    
            // Only flag for sync if owner or employee changed
            if (ownerChanged || employeeChanged) {
                shouldSync = true;
            }
        }
    
        // Only call sync logic if owner or employee name changed
        if (isAuthorized && shouldSync) {
            UpdateRetailerAndAssetOwner.syncOwnerAndEmployee(Trigger.new, Trigger.oldMap);
        }
    }
    
    if (Trigger.isAfter && Trigger.isUpdate) {

        Set<Id> beatIdsForRetailerAsset = new Set<Id>();
        Set<Id> beatIdsForDistributor   = new Set<Id>();

        for (Beat__c beatRecord : Trigger.new) {
            Beat__c oldBeat = Trigger.oldMap.get(beatRecord.Id);

            Boolean ownerChanged       = beatRecord.OwnerId != oldBeat.OwnerId;
            Boolean employeeChanged    = beatRecord.Employee_Name__c != oldBeat.Employee_Name__c;
            Boolean distributorChanged = beatRecord.Distributor_Name__c != oldBeat.Distributor_Name__c;

            // Retailer/Asset updates should run when:
            //  - Owner changed OR Employee changed OR Distributor changed (your previous logic)
            if (ownerChanged || employeeChanged || distributorChanged) {
                beatIdsForRetailerAsset.add(beatRecord.Id);
            }

            // Distributor owner updates should run when:
            //  - Owner or Employee changed (per your new requirement)
            if (ownerChanged || employeeChanged) {
                beatIdsForDistributor.add(beatRecord.Id);
            }
        }

        // Retailer + Asset owner/distributor sync
        if (!beatIdsForRetailerAsset.isEmpty()) {
            UpdateRetailerAndAssetOwner.retailerAndAssetOwnerUpdate(beatIdsForRetailerAsset);
        }

        // Distributor owner sync from Beat
        if (!beatIdsForDistributor.isEmpty()) {
            UpdateRetailerAndAssetOwner.updateDistributorOwnerFromBeat(beatIdsForDistributor);
        }
    }
}