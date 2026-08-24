/**
* Trigger Name : FreezerRequestTrigger
* Test Class  : 
* author      : Supriya
* CreatedDate : 04-03-25
* Description : This is to send custom notification to approval request submitter on approve or reject status
* */
trigger FreezerRequestTrigger on Freezer_Request__c (after update) {
	 //Submitter will get notified when leave is approved or rejected
    List<Messaging.CustomNotification> notifications = new List<Messaging.CustomNotification>();

    // Loop through updated records
    for (Freezer_Request__c freeApp : Trigger.new) {
        Freezer_Request__c oldfreeApp = Trigger.oldMap.get(freeApp.Id);

        // Check if Approval_Status__c is changed to Approved or Rejected
       	if (freeApp.Approval_Request_Status__c != oldfreeApp.Approval_Request_Status__c &&
            (freeApp.Approval_Request_Status__c == 'Request approved' || freeApp.Approval_Request_Status__c == 'Request rejected')) {
            
            // Create a Custom Notification
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            CustomNotificationType type = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'Approval_Outcome_Notification'];
			notification.setNotificationTypeId(type.id);          
            notification.setTitle('Freezer Request Approval Update');
            notification.setBody('Your freezer request application ' +freeApp.Name+ ' has been ' + freeApp.Approval_Request_Status__c + '.');
            notification.setSenderId(UserInfo.getUserId()); // Sender is the current user
            notification.setTargetId(freeApp.Id); // Links the notification to the record
            //notification.setRecipientIds(new List<Id>{leaveApp.CreatedById}); // Send to submitter
			notification.send(new Set<String> { freeApp.CreatedById });
            //notifications.add(notification);
        }
    }
}