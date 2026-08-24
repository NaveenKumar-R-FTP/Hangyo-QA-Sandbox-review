/**
* Trigger Name : EmployeeLeaveApplicationTrigger
* Test Class  : 
* author      : Shyam
* CreatedDate : 20-01-25
* Description : This is to update the "Employee Leave Allowance" record for a user whoose Leave application got "Rejecetd" by its Manager.
* */
trigger EmployeeLeaveApplicationTrigger on Employee_Leave_Application__c (after update) {
    
    
    //Submitter will get notified when leave is approved or rejected
    List<Messaging.CustomNotification> notifications = new List<Messaging.CustomNotification>();

    // Loop through updated records
    for (Employee_Leave_Application__c leaveApp : Trigger.new) {
        Employee_Leave_Application__c oldLeaveApp = Trigger.oldMap.get(leaveApp.Id);

        // Check if Approval_Status__c is changed to Approved or Rejected
        if (leaveApp.Approval_Status__c != oldLeaveApp.Approval_Status__c &&
            (leaveApp.Approval_Status__c == 'Approved' || leaveApp.Approval_Status__c == 'Rejected')) {
            
            // Create a Custom Notification
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            CustomNotificationType type = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'Approval_Outcome_Notification'];
            notification.setNotificationTypeId(type.id);          
            notification.setTitle('Leave Approval Update');
            notification.setBody('Your leave application ' +leaveApp.Name+ ' has been ' + leaveApp.Approval_Status__c + '.');
            notification.setSenderId(UserInfo.getUserId()); // Sender is the current user
            notification.setTargetId(leaveApp.Id); // Links the notification to the record
            //notification.setRecipientIds(new List<Id>{leaveApp.CreatedById}); // Send to submitter
            notification.send(new Set<String> { leaveApp.CreatedById });
            //notifications.add(notification);
        }
    }

    
    // Maps to store the updated leave applications for each user
    Map<Id, Map<String, Decimal>> userLeaveDaysToUpdate = new Map<Id, Map<String, Decimal>>();

    // Collect all the leave applications where Approval Status is updated to 'Rejected'
    for (Employee_Leave_Application__c record : Trigger.new) {
        if (record.Approval_Status__c == 'Rejected' &&
            record.Approval_Status__c != Trigger.oldMap.get(record.Id).Approval_Status__c) {
            
            // Initialize the map for this user if it's not already initialized
            if (!userLeaveDaysToUpdate.containsKey(record.User__c)) {
                userLeaveDaysToUpdate.put(record.User__c, new Map<String, Decimal>());
            }

            // Get the leave type and number of days
            String leaveType = record.Leave_Type__c;
            Decimal numberOfDays = record.Number_of_Days__c;

            // Add the number of days to the leave type map for this user
            if (userLeaveDaysToUpdate.get(record.User__c).containsKey(leaveType)) {
                userLeaveDaysToUpdate.get(record.User__c).put(leaveType, 
                    userLeaveDaysToUpdate.get(record.User__c).get(leaveType) + numberOfDays);
            } else {
                userLeaveDaysToUpdate.get(record.User__c).put(leaveType, numberOfDays);
            }
        }
    }

    // If we have any leave applications to update, proceed
    if (!userLeaveDaysToUpdate.isEmpty()) {

        // Query the related Employee_Leave_Allowance__c records for these users
        List<Employee_Leave_Allowance__c> allowancesToUpdate = [
            SELECT Id, User__c, Available_Sick_Leave__c, Available_Earned_Leave__c, Available_Casual_Leave__c, Available_Maternity_Leave__c,
                   Used_Sick_Leave__c, Used_Earned_Leave__c, Used_Casual_Leave__c, Used_Maternity_Leave__c
            FROM Employee_Leave_Allowance__c
            WHERE User__c IN :userLeaveDaysToUpdate.keySet()
        ];

        // Iterate over the allowances and update them based on the leave type
        for (Employee_Leave_Allowance__c allowance : allowancesToUpdate) {
            Map<String, Decimal> leaveDays = userLeaveDaysToUpdate.get(allowance.User__c);
            
            // Update the Used leave days based on the Leave Type
            if (leaveDays.containsKey('Sick Leave')) {
                allowance.Used_Sick_Leave__c -= leaveDays.get('Sick Leave');
            }
            if (leaveDays.containsKey('Earned Leave')) {
                allowance.Used_Earned_Leave__c -= leaveDays.get('Earned Leave');
            }
            if (leaveDays.containsKey('Casual Leave')) {
                allowance.Used_Casual_Leave__c -= leaveDays.get('Casual Leave');
            }
            if (leaveDays.containsKey('Maternity Leave')) {
                allowance.Used_Maternity_Leave__c -= leaveDays.get('Maternity Leave');
            }
        }

        // Perform the DML update to adjust the leave allowances
        if (!allowancesToUpdate.isEmpty()) {
            update allowancesToUpdate;
        }
    }
}