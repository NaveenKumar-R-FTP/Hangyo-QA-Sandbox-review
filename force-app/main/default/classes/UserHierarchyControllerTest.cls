@isTest
public class UserHierarchyControllerTest {

    @isTest
    static void testControllerMethods() {

        User adminUser = [SELECT Id, UserRoleId FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];

        Id roleIdToUse = adminUser.UserRoleId;

        Date today = Date.today();

        insert new Attendance__c(
            User__c = adminUser.Id,
            Status__c = 'Present',
            Work__c = 'Official Meeting',
            Date_of_attendance__c = today,
            Leave_Date__c = today
        );

        insert new Attendance__c(
            User__c = adminUser.Id,
            Status__c = 'Leave',
            Work__c = '',
            Date_of_attendance__c = today,
            Leave_Date__c = today
        );

        insert new Attendance__c(
            User__c = adminUser.Id,
            Status__c = 'Present',
            Work__c = 'Beat',
            Date_of_attendance__c = today,
            Leave_Date__c = today
        );

        Visit__c v = new Visit__c(
            Visitor_Name__c = adminUser.Id,
            Beat__c = null,
            Visit_Planned_Date__c = today
        );
        insert v;

        Visit_Task__c vt = new Visit_Task__c(
            Visit__c = v.Id,
            Status__c = 'In-Progress'
        );
        insert vt;

        Test.startTest();

        List<Id> userIds = new List<Id>{ adminUser.Id };

        Map<String, Integer> summary = UserHierarchyController.getAttendanceSummary(userIds, today);

        List<Attendance__c> leave1 = UserHierarchyController.getLeaveUsersfirst(userIds);

        List<Map<String,String>> leave2 = UserHierarchyController.getLeaveUsers(userIds);
      
        List<Visit__c> visits = UserHierarchyController.getRetailingDetails(userIds);

        Test.stopTest();
    }
}