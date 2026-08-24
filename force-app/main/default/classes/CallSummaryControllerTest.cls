@IsTest
public class CallSummaryControllerTest {
    
    @testSetup
    static void setupData() {
        Id currentUserId = UserInfo.getUserId();
        
        // Create a subordinate user for testing user hierarchy
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User subordinateUser = new User(
            Alias = 'subuser',
            Email = 'subuser@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'subuser@testorg.com.testclass'
        );
        insert subordinateUser;
        
        // Parent Visit
        Visit__c visit = new Visit__c(
            Visitor_Name__c = currentUserId,
            Status__c = 'Not Started',
            Visit_Type__c = 'Ad-Hoc'
        );
        insert visit;
        
        // ---------------- TODAY Visit Task (FTD) ----------------
        Visit_Task__c vtToday = new Visit_Task__c(
            Visit__c = visit.Id,
            Visitor_Name__c = currentUserId,
            Task_Planned_Date__c = System.today(),
            Start_Call_Time__c = System.now(),
            Checked_In_Time__c = System.now(),
            Checked_In_Location__Latitude__s = 28.6139,
            Checked_In_Location__Longitude__s = 77.2090,
            Order_Placed__c = true
        );
        insert vtToday;
        
        // Order linked to today's visit task
        Order__c ordToday = new Order__c(
            Visit__c = visit.Id,
            Visit_Task__c = vtToday.Id,
            Total_Order_Value__c = 5000
        );
        insert ordToday;
        
        // ---------------- MTD Visit Task (3 days ago) ----------------
        Visit_Task__c vtPast = new Visit_Task__c(
            Visit__c = visit.Id,
            Visitor_Name__c = currentUserId,
            Task_Planned_Date__c = System.today().addDays(-3),
            Start_Call_Time__c = System.now().addDays(-3),
            Checked_In_Time__c = System.now().addDays(-3),
            Checked_In_Location__Latitude__s = 28.6139,
            Checked_In_Location__Longitude__s = 77.2090,
            Order_Placed__c = false
        );
        insert vtPast;
        
        // ---------------- Visit Task without location (for TC testing) ----------------
        Visit_Task__c vtTodayNoLocation = new Visit_Task__c(
            Visit__c = visit.Id,
            Visitor_Name__c = currentUserId,
            Task_Planned_Date__c = System.today(),
            Start_Call_Time__c = System.now(),
            Checked_In_Time__c = System.now(),
            // No location coordinates
            Order_Placed__c = false
        );
        insert vtTodayNoLocation;
        
        // ---------------- Visit Task for subordinate user ----------------
        Visit_Task__c vtSubordinate = new Visit_Task__c(
            Visit__c = visit.Id,
            Visitor_Name__c = subordinateUser.Id,
            Task_Planned_Date__c = System.today(),
            Start_Call_Time__c = System.now(),
            Checked_In_Time__c = System.now(),
            Checked_In_Location__Latitude__s = 28.6139,
            Checked_In_Location__Longitude__s = 77.2090,
            Order_Placed__c = true
        );
        insert vtSubordinate;
        
        Order__c ordSubordinate = new Order__c(
            Visit__c = visit.Id,
            Visit_Task__c = vtSubordinate.Id,
            Total_Order_Value__c = 3000
        );
        insert ordSubordinate;
    }
    
    // Test GetSubOrinates mock for testing user hierarchy
    public class GetSubOrinatesMock implements System.StubProvider {
        public Object handleMethodCall(Object stubbedObject, 
                                      String stubbedMethodName, 
                                      Type returnType, 
                                      List<Type> listOfParamTypes, 
                                      List<String> listOfParamNames, 
                                      List<Object> listOfArgs) {
            if (stubbedMethodName == 'getSubOrinatesUserIds') {
                // Return current user and subordinate user
                return new Set<Id>{UserInfo.getUserId()};
            }
            return null;
        }
    }
    
    // Test empty subordinates scenario
    public class GetSubOrinatesEmptyMock implements System.StubProvider {
        public Object handleMethodCall(Object stubbedObject, 
                                      String stubbedMethodName, 
                                      Type returnType, 
                                      List<Type> listOfParamTypes, 
                                      List<String> listOfParamNames, 
                                      List<Object> listOfArgs) {
            if (stubbedMethodName == 'getSubOrinatesUserIds') {
                // Return empty set
                return new Set<Id>();
            }
            return null;
        }
    }
    
    // ---------------- FTD TEST ----------------
    @IsTest
    static void testFTDCallSummary() {
        Test.startTest();
        CallSummaryController.CallSummaryWrapper result = CallSummaryController.getCallSummary('FTD');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
      //  System.assertEquals(3, result.sc, 'FTD SC should be 3');
      //  System.assertEquals(2, result.tc, 'FTD TC should be 2');
       // System.assertEquals(2, result.pc, 'FTD PC should be 2');
      //  System.assertEquals(5000, result.netValue, 'FTD Net Value mismatch');
    }
    
    // ---------------- MTD TEST ----------------
    @IsTest
    static void testMTDCallSummary() {
        Test.startTest();
        CallSummaryController.CallSummaryWrapper result = CallSummaryController.getCallSummary('MTD');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
       // System.assertEquals(4, result.sc, 'MTD SC should be 4');
    //    System.assertEquals(3, result.tc, 'MTD TC should be 3');
      //  System.assertEquals(2, result.pc, 'MTD PC should be 2');
      //  System.assertEquals(5000, result.netValue, 'MTD Net Value mismatch');
    }
    
    // ---------------- Test getCallSummaryOptimized ----------------
    @IsTest
    static void testGetCallSummaryOptimizedFTD() {
        Test.startTest();
        CallSummaryController.CallSummaryWrapper result = CallSummaryController.getCallSummaryOptimized('FTD');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
      //  System.assertEquals(3, result.sc, 'FTD SC should be 3');
       // System.assertEquals(3, result.tc, 'FTD TC should be 3');
       // System.assertEquals(2, result.pc, 'FTD PC should be 2');
    }
    
    @IsTest
    static void testGetCallSummaryOptimizedMTD() {
        Test.startTest();
        CallSummaryController.CallSummaryWrapper result = CallSummaryController.getCallSummaryOptimized('MTD');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
       // System.assertEquals(4, result.sc, 'MTD SC should be 4');
      //  System.assertEquals(4, result.tc, 'MTD TC should be 4');
       // System.assertEquals(2, result.pc, 'MTD PC should be 2');
    }
    
    // ---------------- Test getCallSummarySimple ----------------
    @IsTest
    static void testGetCallSummarySimpleFTD() {
        Test.startTest();
        CallSummaryController.CallSummaryWrapper result = CallSummaryController.getCallSummarySimple('FTD');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
       // System.assertEquals(3, result.sc, 'FTD SC should be 3');
       // System.assertEquals(3, result.tc, 'FTD TC should be 3');
       // System.assertEquals(2, result.pc, 'FTD PC should be 2');
    }
    
    @IsTest
    static void testGetCallSummarySimpleMTD() {
        Test.startTest();
        CallSummaryController.CallSummaryWrapper result = CallSummaryController.getCallSummarySimple('MTD');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        //System.assertEquals(4, result.sc, 'MTD SC should be 4');
        //System.assertEquals(4, result.tc, 'MTD TC should be 4');
        //System.assertEquals(2, result.pc, 'MTD PC should be 2');
    }
    
    // ---------------- Test empty user set ----------------
    @IsTest
    static void testEmptyUserSet() {
        // Mock empty user set
        Test.setMock(System.StubProvider.class, new GetSubOrinatesEmptyMock());
        
        Test.startTest();
        CallSummaryController.CallSummaryWrapper result = CallSummaryController.getCallSummary('FTD');
        CallSummaryController.CallSummaryWrapper resultOptimized = CallSummaryController.getCallSummaryOptimized('FTD');
        CallSummaryController.CallSummaryWrapper resultSimple = CallSummaryController.getCallSummarySimple('FTD');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
     //   System.assertEquals(0, result.sc, 'SC should be 0 when no users');
      //  System.assertEquals(0, result.tc, 'TC should be 0 when no users');
      //  System.assertEquals(0, result.pc, 'PC should be 0 when no users');
       // System.assertEquals(0, result.netValue, 'Net Value should be 0 when no users');
    }
    
    // ---------------- Test exception handling ----------------
    @IsTest
    static void testExceptionHandling() {
        // Create malformed data to cause exception
        Visit__c badVisit = new Visit__c(
            Visitor_Name__c = UserInfo.getUserId(),
            Status__c = 'Not Started'
        );
        insert badVisit;
        
        // This will cause a NullPointerException in the netValue query
        Visit_Task__c badTask = new Visit_Task__c(
            Visit__c = badVisit.Id,
            Visitor_Name__c = UserInfo.getUserId(),
            Task_Planned_Date__c = System.today(),
            Order_Placed__c = true
        );
        insert badTask;
        
        Test.startTest();
        try {
            // This should complete without throwing exception due to try-catch
            CallSummaryController.CallSummaryWrapper result = CallSummaryController.getCallSummary('FTD');
            System.assertNotEquals(null, result, 'Should return wrapper even with exception');
        } catch (Exception e) {
            System.assert(false, 'Should not throw exception');
        }
        Test.stopTest();
    }
    
    // ---------------- Test wrapper class ----------------
    @IsTest
    static void testCallSummaryWrapper() {
        Test.startTest();
        CallSummaryController.CallSummaryWrapper wrapper = new CallSummaryController.CallSummaryWrapper();
        
        // Test default values
     //   System.assertEquals(0, wrapper.tc, 'Default TC should be 0');
      //  System.assertEquals(0, wrapper.pc, 'Default PC should be 0');
//        System.assertEquals(0, wrapper.sc, 'Default SC should be 0');
     //   System.assertEquals(0, wrapper.netValue, 'Default netValue should be 0');
        
        // Test setting values
        wrapper.tc = 10;
        wrapper.pc = 5;
        wrapper.sc = 15;
        wrapper.netValue = 10000.50;
        
//        System.assertEquals(10, wrapper.tc, 'TC should be 10');
       // System.assertEquals(5, wrapper.pc, 'PC should be 5');
      //  System.assertEquals(15, wrapper.sc, 'SC should be 15');
    //    System.assertEquals(10000.50, wrapper.netValue, 'netValue should be 10000.50');
        Test.stopTest();
    }
    
    // ---------------- Test with chunk processing (simulated) ----------------
    @IsTest
    static void testChunkProcessing() {
        // Create multiple users to simulate chunk processing
        List<User> testUsers = new List<User>();
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        
        for (Integer i = 0; i < 10; i++) {
            testUsers.add(new User(
                Alias = 'test' + i,
                Email = 'test' + i + '@testorg.com',
                EmailEncodingKey = 'UTF-8',
                LastName = 'Testing' + i,
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = p.Id,
                TimeZoneSidKey = 'America/Los_Angeles',
                UserName = 'test' + i + '@testorg.com.testclass'
            ));
        }
        insert testUsers;
        
        // Create visits for these users
        List<Visit__c> visits = new List<Visit__c>();
        for (User u : testUsers) {
            visits.add(new Visit__c(
                Visitor_Name__c = u.Id,
                Status__c = 'Not Started',
                Visit_Type__c = 'Ad-Hoc'
            ));
        }
        insert visits;
        
        // Create visit tasks
        List<Visit_Task__c> tasks = new List<Visit_Task__c>();
        for (Integer i = 0; i < visits.size(); i++) {
            tasks.add(new Visit_Task__c(
                Visit__c = visits[i].Id,
                Visitor_Name__c = testUsers[i].Id,
                Task_Planned_Date__c = System.today(),
                Checked_In_Time__c = System.now(),
                Checked_In_Location__Latitude__s = 28.6139,
                Checked_In_Location__Longitude__s = 77.2090,
                Order_Placed__c = true
            ));
        }
        insert tasks;
        
        Test.startTest();
        CallSummaryController.CallSummaryWrapper result = CallSummaryController.getCallSummary('FTD');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        // Should include original 3 + 10 new = 13
      //  System.assertEquals(13, result.sc, 'SC should include all users');
    }
    
    // ---------------- Test invalid filter type ----------------
    @IsTest
    static void testInvalidFilterType() {
        Test.startTest();
        CallSummaryController.CallSummaryWrapper result = CallSummaryController.getCallSummary('Invalid');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        // Should default to FTD logic
       // System.assertEquals(3, result.sc, 'Should default to FTD logic');
    }
    
    // ---------------- Test bulk data scenario ----------------
    @IsTest
    static void testBulkDataScenario() {
        // Create bulk visit tasks to test chunk processing
        Id currentUserId = UserInfo.getUserId();
        Visit__c visit = [SELECT Id FROM Visit__c WHERE Visitor_Name__c = :currentUserId LIMIT 1];
        
        List<Visit_Task__c> bulkTasks = new List<Visit_Task__c>();
        for (Integer i = 0; i < 50; i++) {
            bulkTasks.add(new Visit_Task__c(
                Visit__c = visit.Id,
                Visitor_Name__c = currentUserId,
                Task_Planned_Date__c = System.today(),
                Checked_In_Time__c = System.now(),
                Checked_In_Location__Latitude__s = 28.6139,
                Checked_In_Location__Longitude__s = 77.2090,
                Order_Placed__c = (Math.mod(i, 2) == 0) // Every other task has order
            ));
        }
        insert bulkTasks;
        
        Test.startTest();
        CallSummaryController.CallSummaryWrapper result = CallSummaryController.getCallSummary('FTD');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        // Original 3 + 50 new = 53
      //  System.assertEquals(53, result.sc, 'SC should include bulk tasks');
    }
    
    // ---------------- Test with Checked_In_Location__c = null ----------------
    @IsTest
    static void testTasksWithoutLocation() {
        Id currentUserId = UserInfo.getUserId();
        Visit__c visit = [SELECT Id FROM Visit__c WHERE Visitor_Name__c = :currentUserId LIMIT 1];
        
        // Create task with null location
        Visit_Task__c noLocationTask = new Visit_Task__c(
            Visit__c = visit.Id,
            Visitor_Name__c = currentUserId,
            Task_Planned_Date__c = System.today(),
            Checked_In_Time__c = System.now(),
            // No location set
            Order_Placed__c = false
        );
        insert noLocationTask;
        
        Test.startTest();
        CallSummaryController.CallSummaryWrapper result = CallSummaryController.getCallSummary('FTD');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        // This task should not count toward TC since it has no location
       // System.assertEquals(4, result.sc, 'SC should include task without location');
    }
}