/**
* Class Name : CreateEmployeeLeaveAllowance
* Test Class  : CreateEmployeeLeaveAllowanceTest
* author      : Shyam
* CreatedDate : 15-01-24
* Description : This is to create "Employee Leave Allowance" record when user inserted.
*                
* */
trigger CreateEmployeeLeaveAllowance on User (before insert, after insert,before update) {   
    
    
    if (Trigger.isInsert || Trigger.isUpdate) {
        //handler class contains the logic for ensuring only one Primary_Distributor__c is true for a given PartnerAccountId
        UserHandler.enforceSinglePrimaryDistributor(Trigger.new);
    }
    
    
     // After Insert: Delegate Employee Leave Allowance creation to a future method
    if (Trigger.isAfter && Trigger.isInsert) {
        // Collect User IDs to process asynchronously
        Set<Id> userIds = new Set<Id>();
        for (User u : Trigger.new) {
            if(u.Employee_Role__c != Null){
                userIds.add(u.Id);
            }
        }

        // Call future method
        if(userIds.size()>0){
            CreateEmployeeLeaveAllowanceHandler.createEmployeeLeaveAllowancesAsync(userIds);
        }
    }

    //Code to Re-size the QR Code Image - Resolution is set to 160x160
    if(trigger.isBefore) {
        for(User oUser : Trigger.new) {
            if(String.isNotBlank(oUser.UPI_QR_CODE__c) && (Trigger.isInsert || (Trigger.isUpdate && oUser.UPI_QR_CODE__c != Trigger.oldMap.get(oUser.Id).UPI_QR_CODE__c))) {
                String qrImage = String.valueOf(oUser.UPI_QR_CODE__c);
                if(qrImage.contains('<img')) {
                    oUser.UPI_QR_CODE__c = qrImage.replace('<img', '<img width="160" height="160"');
                }
            }
        }
    }
    
}