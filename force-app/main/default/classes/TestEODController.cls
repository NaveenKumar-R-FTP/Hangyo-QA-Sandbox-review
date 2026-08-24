/**
 * Class : TestEODController Class
 * Author : Hariprasad
 * LastModifiedDate : 16/02/2026
 * Descriprtion : Test class for the EODController class 
 **/

@isTest
private class TestEODController {

    @TestSetup
    static void setup() {
        Id retailerRTId;
        try {
            retailerRTId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Retailer').getRecordTypeId();
        } catch (Exception e) {
            retailerRTId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = 'Retailer' LIMIT 1].Id;
        }
        
        RetailerCodeSetting__c rcs = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 1);
        insert rcs;

        Account acc = new Account(Name = 'EOD Test Retailer', RecordTypeId = retailerRTId);
        insert acc;

        Beat__c beat = new Beat__c(Name = 'EOD Test Beat');
        insert beat;

        Visit__c visit = new Visit__c(
            Visit_planned_date__c = Date.today(),
            Visitor_Name__c = UserInfo.getUserId(),
            Beat__c = beat.Id,
            Status__c = 'Not Started',
            Visit_Type__c = 'Planned'
        );
        insert visit;

        Visit_Task__c vt = new Visit_Task__c(
            Visit__c = visit.Id,
            Account__c = acc.Id,
            Retailer__c = acc.Id,
            Beat__c = beat.Id,
            Visitor_Name__c = UserInfo.getUserId(),
            Task_Planned_Date__c = Date.today(),
            Status__c = 'In-Progress',
            Order_Placed__c = false,
            Checked_In_Time__c = DateTime.now().addHours(-4),
            End_Call_Time__c = DateTime.now()
        );
        insert vt;

        Order__c ord = new Order__c(
            OwnerId = UserInfo.getUserId(),
            EffectiveDate__c = Date.today(),
            Total_Order_Value__c = 500,
            Account__c = acc.Id
        );
        insert ord;

        Freezer_Request__c fr = new Freezer_Request__c(Freezer_Make__c = 'EOD Test');
        insert fr;
    }

    @isTest
    static void testGetDailyPerformance() {
        Test.startTest();
        EODController.EODWrapper result = EODController.getDailyPerformance();
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assert(result.totalOrderValue >= 0);
    }

    @isTest
    static void testGetDailyPerformanceForUser_Null() {
        Test.startTest();
        EODController.EODWrapper result = EODController.getDailyPerformanceForUser(null);
        Test.stopTest();
        System.assertNotEquals(null, result);
    }

    @isTest
    static void testGetDailyPerformanceForUser_WithUserId() {
        Id userId = UserInfo.getUserId();
        Test.startTest();
        EODController.EODWrapper result = EODController.getDailyPerformanceForUser(userId);
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assert(result.totalOrderValue >= 0);
    }

    @isTest
    static void testGetDailyPerformanceForUserAndDate_Valid() {
        Id userId = UserInfo.getUserId();
        String dateStr = String.valueOf(Date.today());
        Test.startTest();
        EODController.EODWrapper result = EODController.getDailyPerformanceForUserAndDate(userId, dateStr);
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assert(result.totalOrderValue >= 0);
    }

    @isTest
    static void testGetDailyPerformanceForUserAndDate_InvalidDate() {
        Id userId = UserInfo.getUserId();
        Test.startTest();
        EODController.EODWrapper result = EODController.getDailyPerformanceForUserAndDate(userId, 'invalid-date');
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assert(String.isNotBlank(result.message));
    }

    @isTest
    static void testGetDailyPerformanceForUserAndDate_BlankDate() {
        Test.startTest();
        EODController.EODWrapper result = EODController.getDailyPerformanceForUserAndDate(UserInfo.getUserId(), '');
        Test.stopTest();
        System.assertNotEquals(null, result);
    }

    @isTest
    static void testGetDailyPerformanceForUserAndDate_NullUserId() {
        Test.startTest();
        EODController.EODWrapper result = EODController.getDailyPerformanceForUserAndDate(null, String.valueOf(Date.today()));
        Test.stopTest();
        System.assertNotEquals(null, result);
    }
}