@isTest
public class AttendanceDistanceBatchHaversineTest {
    // Test data setup method
    @TestSetup
    static void setup() {
        // Create test users with the required profile
        Profile sfaProfile = [SELECT Id FROM Profile WHERE Name = 'SFA Profile' LIMIT 1];
        List<User> testUsers = new List<User>();
        for (Integer i = 0; i < 3; i++) {
            testUsers.add(new User(
                FirstName = 'Test',
                LastName = 'User ' + i,
                Email = 'testuser' + i + '@hangyo.in',
                Username = 'testuser' + i + '@lkjdsexample.com',
                Alias = 'tuser' + i,
                TimeZoneSidKey = 'America/New_York',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = sfaProfile.Id,
                IsActive = true
            ));
        }
        insert testUsers;

        // Create Attendance records for today with 'Present' status
        List<Attendance__c> attendances = new List<Attendance__c>();
        for (User u : testUsers) {
            attendances.add(new Attendance__c(
                User__c = u.Id,
                Date_of_attendance__c = Date.today(),
                Status__c = 'Present'
            ));
        }
        insert attendances;
Visit__c visit = new Visit__c( Status__c ='Completed');
        insert visit;
        // Create Visit_Task__c records with geolocation data for today
        List<Visit_Task__c> visitTasks = new List<Visit_Task__c>();
        for (User u : testUsers) {
            // First check-in location (latitude, longitude)
            visitTasks.add(new Visit_Task__c(
                Visitor_Name__c = u.Id,
                Visit__c=visit.id,
                Checked_In_Time__c = DateTime.newInstance(Date.today(), Time.newInstance(9, 0, 0, 0)),
                Checked_In_Location__Latitude__s = 37.7749,
                Checked_In_Location__Longitude__s = -122.4194
            ));
            // Second check-in location (1 km away)
            visitTasks.add(new Visit_Task__c(
                Visitor_Name__c = u.Id,
                 Visit__c=visit.id,
                Checked_In_Time__c = DateTime.newInstance(Date.today(), Time.newInstance(10, 0, 0, 0)),
                Checked_In_Location__Latitude__s = 37.7849, // ~1 km North
                Checked_In_Location__Longitude__s = -122.4194
            ));
        }
        insert visitTasks;
    }

    // Test the DistanceUtils class
    @isTest
    static void testDistanceUtils() {
        // Test with valid coordinates (San Francisco to ~1 km North)
        Double distance = DistanceUtils.calculateDistanceInMeters(37.7749, -122.4194, 37.7849, -122.4194);
        system.debug(distance);
        System.assert(distance > 900 && distance < 1112, 'Distance should be approximately 1000 meters'); // Allowing 12% tolerance

        // Test with null values
        Double nullDistance = DistanceUtils.calculateDistanceInMeters(null, null, null, null);
        System.assertEquals(0.0, nullDistance, 'Should return 0 for null inputs');
    }

    // Test the batch class
    @isTest
    static void testAttendanceDistanceBatch() {
        Test.startTest();
        AttendanceDistanceBatchHaversine batch = new AttendanceDistanceBatchHaversine();
        Database.executeBatch(batch, 200);
        Test.stopTest();

    }

    // Test the scheduler class
    @isTest
    static void testAttendanceScheduler() {
        Test.startTest();
        AttendanceScheduler scheduler = new AttendanceScheduler();
        scheduler.execute(null); // Pass null since we don't use the SchedulableContext
        Test.stopTest();

        // Verify the batch was executed (check if Attendances were updated)
        Integer updatedCount = [SELECT COUNT() FROM Attendance__c WHERE Total_Distance__c != null];
        System.assert(updatedCount > 0, 'Batch should have been executed by scheduler');
    }

    // Test edge case: No Visit_Task__c records
    @isTest
    static void testNoVisitTasks() {
        // Delete all Visit_Task__c records
        delete [SELECT Id FROM Visit_Task__c];

        Test.startTest();
        Database.executeBatch(new AttendanceDistanceBatchHaversine(), 200);
        Test.stopTest();

        // Attendances should not have distance calculated
        List<Attendance__c> atts = [SELECT Total_Distance__c FROM Attendance__c];
        for (Attendance__c att : atts) {
            System.assertEquals(null, att.Total_Distance__c, 'Distance should remain null');
        }
    }
}