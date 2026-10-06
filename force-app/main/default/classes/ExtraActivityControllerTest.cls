/**
* Class Name  : ExtraActivityControllerTest
* Tests       : ExtraActivityController
* author      : IT Support
* CreatedDate : 06-10-26
* Description : Coverage for the Extra Activity capture flow. BRD v6.0, item D2.
* */
@IsTest
private class ExtraActivityControllerTest {

    // Starts an activity and returns its Id. Used by most tests as a starting point.
    private static Id startMeeting() {
        ExtraActivityController.ActivityResponse r =
            ExtraActivityController.startActivity('Meeting', 13.340590, 74.742150, 'Manipal');
        System.assertEquals(true, r.isAllowed, 'Start should be allowed: ' + r.errorMessage);
        return r.activity.Id;
    }

    @IsTest
    static void startCreatesRecordImmediately() {
        Test.startTest();
        ExtraActivityController.ActivityResponse r =
            ExtraActivityController.startActivity('Meeting', 13.340590, 74.742150, 'Manipal');
        Test.stopTest();

        System.assertEquals(true, r.isAllowed, 'Start should succeed');
        System.assertNotEquals(null, r.activity.Id, 'A record should exist straight away');

        Extra_Activity__c saved = [
            SELECT Status__c, Activity_Date__c, User__c, Start_Time__c,
                   Start_Latitude__c, End_Time__c
            FROM Extra_Activity__c WHERE Id = :r.activity.Id
        ];

        System.assertEquals('In Progress', saved.Status__c);
        System.assertEquals(Date.today(), saved.Activity_Date__c);
        System.assertEquals(UserInfo.getUserId(), saved.User__c);
        System.assertNotEquals(null, saved.Start_Time__c);
        System.assertEquals(null, saved.End_Time__c, 'Not ended yet');
    }

    @IsTest
    static void startRejectsUnknownType() {
        Test.startTest();
        ExtraActivityController.ActivityResponse r =
            ExtraActivityController.startActivity('Superstockist Visit', 13.3, 74.7, null);
        Test.stopTest();

        System.assertEquals(false, r.isAllowed);
        System.assertEquals(0, [SELECT COUNT() FROM Extra_Activity__c], 'Nothing should be created');
    }

    @IsTest
    static void startRejectsBlankType() {
        ExtraActivityController.ActivityResponse r =
            ExtraActivityController.startActivity('', 13.3, 74.7, null);
        System.assertEquals(false, r.isAllowed);
    }

    @IsTest
    static void onlyOneActivityOpenAtATime() {
        startMeeting();

        Test.startTest();
        ExtraActivityController.ActivityResponse second =
            ExtraActivityController.startActivity('Event', 13.3, 74.7, 'Udupi');
        Test.stopTest();

        System.assertEquals(false, second.isAllowed);
        System.assertEquals(1, [SELECT COUNT() FROM Extra_Activity__c], 'Still only one');
    }

    @IsTest
    static void resumeFindsTheOpenActivity() {
        Id activityId = startMeeting();

        Test.startTest();
        Extra_Activity__c open = ExtraActivityController.getInProgressActivity();
        Test.stopTest();

        System.assertNotEquals(null, open, 'Resume bar needs this');
        System.assertEquals(activityId, open.Id);
    }

    @IsTest
    static void noOpenActivityReturnsNull() {
        Test.startTest();
        Extra_Activity__c open = ExtraActivityController.getInProgressActivity();
        Test.stopTest();

        System.assertEquals(null, open, 'Nothing started, so nothing to resume');
    }

    @IsTest
    static void endStampsTimeAndDuration() {
        Id activityId = startMeeting();

        Test.startTest();
        ExtraActivityController.ActivityResponse r = ExtraActivityController.endActivity(activityId);
        Test.stopTest();

        System.assertEquals(true, r.isAllowed, 'error: ' + r.errorMessage);

        Extra_Activity__c ended = [
            SELECT End_Time__c, Duration_Minutes__c, Status__c
            FROM Extra_Activity__c WHERE Id = :activityId
        ];

        System.assertNotEquals(null, ended.End_Time__c);
        System.assertNotEquals(null, ended.Duration_Minutes__c);
        System.assertEquals('In Progress', ended.Status__c, 'Ending does not complete it');
    }

    @IsTest
    static void endRejectsMissingRecord() {
        ExtraActivityController.ActivityResponse r = ExtraActivityController.endActivity(null);
        System.assertEquals(false, r.isAllowed);
    }

    @IsTest
    static void saveWithoutEndingIsRefused() {
        Id activityId = startMeeting();

        Test.startTest();
        ExtraActivityController.ActivityResponse r = ExtraActivityController.saveActivity(
            activityId, null, null, null, 'Office', 'Meeting at Office', null, null, null);
        Test.stopTest();

        System.assertEquals(false, r.isAllowed, 'End must come first');
    }

    @IsTest
    static void saveMeetingWritesMeetingFieldsOnly() {
        Id activityId = startMeeting();
        ExtraActivityController.endActivity(activityId);

        Test.startTest();
        ExtraActivityController.ActivityResponse r = ExtraActivityController.saveActivity(
            activityId, 'ignored outlet', 'ignored event', 'ignored city',
            'ABC Distributors Office', 'Meeting with Distributor',
            9999, 'went well', 'ignored comment');
        Test.stopTest();

        System.assertEquals(true, r.isAllowed, 'error: ' + r.errorMessage);

        Extra_Activity__c done = [
            SELECT Status__c, Meeting_Location__c, Meeting_Type__c, Remarks__c,
                   Outlet_Name__c, Event_Name__c, City_Area__c, Comment__c, Expected_Sale__c
            FROM Extra_Activity__c WHERE Id = :activityId
        ];

        System.assertEquals('Completed', done.Status__c);
        System.assertEquals('ABC Distributors Office', done.Meeting_Location__c);
        System.assertEquals('Meeting with Distributor', done.Meeting_Type__c);
        System.assertEquals('went well', done.Remarks__c);
        System.assertEquals(null, done.Outlet_Name__c, 'Not a Meeting field');
        System.assertEquals(null, done.Event_Name__c, 'Not a Meeting field');
        System.assertEquals(null, done.Comment__c, 'Not a Meeting field');
        System.assertEquals(null, done.Expected_Sale__c, 'Meeting has no expected sale');
    }

    @IsTest
    static void saveNewOutletApproach() {
        ExtraActivityController.ActivityResponse s =
            ExtraActivityController.startActivity('New Outlet Approach', 13.3, 74.7, null);
        ExtraActivityController.endActivity(s.activity.Id);

        Test.startTest();
        ExtraActivityController.ActivityResponse r = ExtraActivityController.saveActivity(
            s.activity.Id, 'Vadiraj Cool Point', null, null, null, null, 15000, 'keen', null);
        Test.stopTest();

        System.assertEquals(true, r.isAllowed, 'error: ' + r.errorMessage);

        Extra_Activity__c done = [
            SELECT Outlet_Name__c, Expected_Sale__c, Status__c
            FROM Extra_Activity__c WHERE Id = :s.activity.Id
        ];
        System.assertEquals('Vadiraj Cool Point', done.Outlet_Name__c);
        System.assertEquals(15000, done.Expected_Sale__c);
        System.assertEquals('Completed', done.Status__c);
    }

    @IsTest
    static void saveEvent() {
        ExtraActivityController.ActivityResponse s =
            ExtraActivityController.startActivity('Event', 13.3, 74.7, null);
        ExtraActivityController.endActivity(s.activity.Id);

        Test.startTest();
        ExtraActivityController.ActivityResponse r = ExtraActivityController.saveActivity(
            s.activity.Id, null, 'Manipal Food Fest', 'Udupi', null, null, 40000, null, null);
        Test.stopTest();

        System.assertEquals(true, r.isAllowed, 'error: ' + r.errorMessage);

        Extra_Activity__c done = [
            SELECT Event_Name__c, City_Area__c FROM Extra_Activity__c WHERE Id = :s.activity.Id
        ];
        System.assertEquals('Manipal Food Fest', done.Event_Name__c);
        System.assertEquals('Udupi', done.City_Area__c);
    }

    @IsTest
    static void saveOthers() {
        ExtraActivityController.ActivityResponse s =
            ExtraActivityController.startActivity('Others', 13.3, 74.7, null);
        ExtraActivityController.endActivity(s.activity.Id);

        Test.startTest();
        ExtraActivityController.ActivityResponse r = ExtraActivityController.saveActivity(
            s.activity.Id, null, null, null, null, null, null, null, 'Freezer breakdown at Kadiyali');
        Test.stopTest();

        System.assertEquals(true, r.isAllowed, 'error: ' + r.errorMessage);

        Extra_Activity__c done = [
            SELECT Comment__c, Remarks__c FROM Extra_Activity__c WHERE Id = :s.activity.Id
        ];
        System.assertEquals('Freezer breakdown at Kadiyali', done.Comment__c);
        System.assertEquals(null, done.Remarks__c, 'Others carries no remarks');
    }

    @IsTest
    static void completedActivityCannotBeChanged() {
        Id activityId = startMeeting();
        ExtraActivityController.endActivity(activityId);
        ExtraActivityController.saveActivity(
            activityId, null, null, null, 'Office', 'Meeting at Office', null, null, null);

        Test.startTest();
        ExtraActivityController.ActivityResponse again = ExtraActivityController.endActivity(activityId);
        Test.stopTest();

        System.assertEquals(false, again.isAllowed, 'Already saved');
    }

    @IsTest
    static void anotherUserCannotTouchIt() {
        Id activityId = startMeeting();

        User other = new User(
            FirstName         = 'Other',
            LastName          = 'Rep',
            Email             = 'ea.other@hangyo.in',
            Username          = 'ea.other.' + DateTime.now().getTime() + '@hangyo.in.invalid',
            Alias             = 'eaoth',
            TimeZoneSidKey    = 'Asia/Kolkata',
            LocaleSidKey      = 'en_IN',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = UserInfo.getProfileId()
        );
        insert other;

        Test.startTest();
        ExtraActivityController.ActivityResponse r;
        System.runAs(other) {
            r = ExtraActivityController.endActivity(activityId);
        }
        Test.stopTest();

        System.assertEquals(false, r.isAllowed, 'Someone else must not be able to end it');
    }
}