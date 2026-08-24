@IsTest
public class VisitTaskHandlerTest {

    @IsTest
    static void testPopulateFirstActivity_InsertThenUpdate() {

        /* --------- Setup --------- */
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(
            Name = 'SF',
            Latest_Code__c = 100
        );
        insert setting;

        Profile p = [SELECT Id FROM Profile WHERE Name = 'SFA Profile' LIMIT 1];

        User u = new User(
            Alias = 'tuser',
            Email = 'testuser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'User',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            UserName = 'testuser' + System.currentTimeMillis() + '@test.com'
        );
        insert u;

        Date today = Date.today();

        /* --------- Attendance --------- */
        Attendance__c att = new Attendance__c(
            User__c = u.Id,
            Date_of_attendance__c = today,
            Status__c = 'Present',
            First_Activity_Time__c = null
        );
        insert att;

        /* --------- Visit --------- */
        Visit__c visit = new Visit__c(
            OwnerId = u.Id
        );
        insert visit;

        /* --------- STEP 1: Insert Visit Tasks (No Check-In Time) --------- */
        Visit_Task__c vt1 = new Visit_Task__c(
            Visit__c = visit.Id,
            Visitor_Name__c = u.Id
            // Checked_In_Time__c = null
        );

        Visit_Task__c vt2 = new Visit_Task__c(
            Visit__c = visit.Id,
            Visitor_Name__c = u.Id
        );

        insert new List<Visit_Task__c>{ vt1, vt2 };

        /* --------- STEP 2: Update Visit Tasks with Check-In Time --------- */
        DateTime earlierCheckIn = DateTime.now().addHours(-3);
        DateTime laterCheckIn   = DateTime.now().addHours(-1);

        vt1.Checked_In_Time__c = laterCheckIn;
        vt2.Checked_In_Time__c = earlierCheckIn;

        update new List<Visit_Task__c>{ vt1, vt2 };

        /* --------- Execute Handler (Simulating After Update Trigger) --------- */
        Test.startTest();
        VisitTaskHandler.populateFirstActivity(
            new Set<Id>{ vt1.Id, vt2.Id }
        );
        Test.stopTest();

        /* --------- Assertions --------- */
        Attendance__c updatedAtt = [
            SELECT First_Activity_Time__c
            FROM Attendance__c
            WHERE Id = :att.Id
        ];

        System.assertNotEquals(
            null,
            updatedAtt.First_Activity_Time__c,
            'First Activity Time should be populated'
        );
    }
}