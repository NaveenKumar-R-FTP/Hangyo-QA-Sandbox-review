@isTest
public class UserDailyCountServiceTest {

    @isTest
    static void testUserCountsAndTimeline() {

        User adminUser = [SELECT Id, UserRoleId FROM User WHERE Profile.Name='System Administrator' LIMIT 1];
        Id userId = adminUser.Id;
        Date today = Date.today();

        Attendance__c att1 = new Attendance__c(
            User__c = userId,
            Status__c = 'Present',
            Work__c = 'Official Meeting',
            Date_of_attendance__c = today,
            Leave_Date__c = today
        );
        Attendance__c att2 = new Attendance__c(
            User__c = userId,
            Status__c = 'Leave',
            Work__c = '',
            Date_of_attendance__c = today,
            Leave_Date__c = today
        );
        insert new List<Attendance__c>{ att1, att2 };

        Visit__c v = new Visit__c(
            Visitor_Name__c = userId,
            Beat__c = null,
            Visit_Planned_Date__c = today
        );
        insert v;

        Visit_Task__c vt = new Visit_Task__c(
            Visit__c = v.Id,
            Status__c = 'In-Progress',
            Checked_In_Time__c = Datetime.now().addHours(-2),
            Checked_Out_Time__c = Datetime.now()
        );
        insert vt;

        Order__c ord = new Order__c(
            Visit__c = v.Id,
            Total_Order_Value__c = 500
        );
        insert ord;

        Test.startTest();

        List<String> userIds = new List<String>{ userId };
        List<UserDailyCountService.UserDailySummary> summaries = UserDailyCountService.getUserCounts(userIds);
        System.assertNotEquals(0, summaries.size(), 'Should return at least one summary');
        System.assertEquals(userId, summaries[0].userId, 'UserId should match');
        System.assertEquals(1, summaries[0].officialCount, 'Official count should be 1');
        System.assertEquals(1, summaries[0].leaveCount, 'Leave count should be 1');
        System.assertEquals(1, summaries[0].retailCount, 'Retail count should be 1');

        UserDailyCountService.TimelineWrapper tw = UserDailyCountService.getTodayTimeline(userId);
        System.assertNotEquals(null, tw);
        System.assertNotEquals(0, tw.timeline.size(), 'Timeline should not be empty');

        Map<String, Object> mtd = UserDailyCountService.getMTDCounts(userId);
        System.assertEquals(1, (Integer)mtd.get('retailingCount'), 'MTD retailing count should be 1');
        System.assertEquals(1, (Integer)mtd.get('officialCount'), 'MTD official count should be 1');
        System.assertEquals(1, (Integer)mtd.get('leaveCount'), 'MTD leave count should be 1');

        Test.stopTest();
    }
}