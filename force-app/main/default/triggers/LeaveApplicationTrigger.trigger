/**
* Trigger Name: LeaveApplicationTrigger
* Class Name  : LeaveApplicationsTriggerHandler
* Test Class  : LeaveApplicationsTriggerTest
* author      : Shyam
* CreatedDate : 15-12-24
* Description : This is to Create & Update Attendance record for a user whoose Leave application got approved by its Manager
* */
trigger LeaveApplicationTrigger on Leave_Application__c (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        System.debug('Enter trigger');
        List<Leave_Application__c> approvedLeaves = new List<Leave_Application__c>();
        
        for (Leave_Application__c leaveApplication : Trigger.new) {
            Leave_Application__c oldLeave = Trigger.oldMap.get(leaveApplication.Id);
            System.debug('leaveApplication.Approval_Status__c:- '+leaveApplication.Approval_Status__c);
            System.debug('oldLeave.Approval_Status__c:- '+oldLeave.Approval_Status__c);
            if (leaveApplication.Approval_Status__c == 'Approved' &&
                leaveApplication.Approval_Status__c != oldLeave.Approval_Status__c) {
                approvedLeaves.add(leaveApplication);
            }
        }
        
        if (!approvedLeaves.isEmpty()) {
            System.debug('Enter if statement');
            LeaveApplicationsTriggerHandler.createAttendanceForApprovedLeave(approvedLeaves);
        }
        //LeaveApplicationsTriggerHandler.createAttendanceForApprovedLeave(Trigger.new);
    }
}