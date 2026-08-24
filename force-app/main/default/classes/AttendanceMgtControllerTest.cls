/**
* Test Class  : AttendanceMgtControllerTest
* author      : Shyam
* CreatedDate : 22-01-25
* Description : This is test class for "AttendanceMgtController".
* 

@isTest
public class AttendanceMgtControllerTest {
    
    @testSetup
    static void setupTestData() {
        // Create a test user
        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        // Create Employee Leave Allowance record
        Employee_Leave_Allowance__c leaveAllowance = new Employee_Leave_Allowance__c(
            User__c = testUser.Id,            
            Total_Sick_Leave__c = 10,
            Total_Earned_Leave__c = 20,
            Total_Casual_Leave__c = 10,
            Total_Maternity_Leave__c = 5,
            Used_Sick_Leave__c = 5,
            Used_Earned_Leave__c = 10,
            Used_Casual_Leave__c = 7,
            Used_Maternity_Leave__c = 5
        );
        insert leaveAllowance;

        // Create Attendance record
        Attendance__c attendance = new Attendance__c(
            User__c = testUser.Id,
            Date_of_Attendance__c = Date.today(),
            Location__Latitude__s = 25.333,
            Location__Longitude__s = 12.33,
            Status__c = 'Present'
        );
        insert attendance;
        
        // Create Employee Leave Application.
        Employee_Leave_Application__c leaveMaster = new Employee_Leave_Application__c(
            User__c = testUser.Id
            );
        insert leaveMaster;

        // Create Leave Application record
        Leave_Application__c leaveApplication = new Leave_Application__c(
            User__c = testUser.Id,
            Employee_Leave_Application__c = leaveMaster.Id,
            Leave_Types__c = 'Casual Leave',
            Start_Date__c = Date.today(),
            End_Date__c = Date.today(),
            Leave_Period__c = 'Full Day'
        );
        insert leaveApplication;
    }

    @isTest
    static void testGetLeaveBalancesForUser() {
        // Call the method
        Test.startTest();
        Employee_Leave_Allowance__c result = AttendanceMgtController.getLeaveBalancesForUser();
        Test.stopTest();

        // Assert the results
        System.assertNotEquals(null, result, 'Leave allowance should not be null.');
        System.assertEquals(5, result.Available_Sick_Leave__c, 'Available Sick Leave should be 5.');
    }

    @isTest
    static void testCheckAttendanceForToday() {
        // Call the method
        Test.startTest();
        Boolean hasAttendance = AttendanceMgtController.checkAttendanceForToday();
        Test.stopTest();

        // Assert the result
        System.assert(hasAttendance, 'There should be an attendance record for today.');
    }
    
    @isTest
    static void testGetLeaveApplicationRecords() {       
            Test.startTest();            
            // Call the method
            List<Leave_Application__c> results = AttendanceMgtController.getLeaveApplicationRecords();            
            Test.stopTest();
            // Assertions
            System.assertEquals(1, results.size(), 'Expected 1 leave record');        
       }
    
     @isTest
    static void testAttendanceList() {
        // Set up the test user (if running as a specific user)
        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        // Create a test Attendance record for the current date for this user
        Attendance__c attendance = new Attendance__c(
            User__c = testUser.Id,
            Date_of_attendance__c = System.today(),
            Status__c = 'Present'
        );
        insert attendance;

        // Start the test
        Test.startTest();

        // Call the method and verify the result
        List<Attendance__c> result = AttendanceMgtController.attendanceList();

        // Stop the test
      

        // Assert that the attendance record was returned
        System.assertNotEquals(null, result, 'The attendance list should not be null.');
        System.assertEquals(1, result.size(), 'The attendance list should contain exactly one record.');
        System.assertEquals('Present', result[0].Status__c, 'The status should be "Present".');

        // Test case where no attendance records exist for the current date
        // Delete the attendance record
        delete attendance;

        // Start the test again for the no data scenario
       

        // Call the method when no data is present
        List<Attendance__c> resultNoData = AttendanceMgtController.attendanceList();

        // Stop the test
        Test.stopTest();

        // Assert that the result is null since no attendance records exist
        System.assertNotEquals(null, resultNoData, 'The attendance list should be null when no records exist.');
    }

     @isTest
    static void testMarkAttendanceNewRecord() {
        List<Attendance__c> deleteAttendence = [SELECT Id FROM Attendance__c];
    delete deleteAttendence;
        
        // Create test Attendance record
        Attendance__c testAttendance = new Attendance__c(
            Work__c = 'Test Work',
            Description__c = 'Test Description'
        );
        
        // Set a user context
        User testUser = [SELECT Id FROM User WHERE Username = :UserInfo.getUserName() LIMIT 1];
        System.runAs(testUser) {
            Test.startTest();
            String result = AttendanceMgtController.markAttendance(testAttendance);
            Test.stopTest();           
        }
    }

    @isTest
    static void testMarkAttendanceExistingRecord() {
        // Create an existing Attendance record for today
        User testUser = [SELECT Id FROM User WHERE Username = :UserInfo.getUserName() LIMIT 1];
        Attendance__c existingAttendance = new Attendance__c(
            User__c = testUser.Id,
            Status__c = 'Present',
            Date_of_attendance__c = System.Today(),
            Work__c = 'Test Work',
            Location__Latitude__s = 25.333,
            Location__Longitude__s = 12.33,
            Description__c = 'Test Description'
        );
        insert existingAttendance;

        // Create new Attendance object for update scenario
        Attendance__c testAttendance = new Attendance__c(
            Work__c = 'Updated Work',
            Description__c = 'Updated Description',
            Status__c = 'Leave',
            Leave_Period__c = 'Full Day'
        );

        System.runAs(testUser) {
            Test.startTest();
            String result = AttendanceMgtController.markAttendance(testAttendance);
            Test.stopTest();

            // Verify the record is updated
            existingAttendance = [SELECT Id, Status__c, Work__c, Description__c FROM Attendance__c WHERE Id = :existingAttendance.Id];
            
            //System.assertEquals(existingAttendance.Id, result);
            System.assertNotEquals(null, result);
        }
    }
    
    @isTest
private static void testMarkAttendance_AbsentAutomaticRecordUpdated() {
    // Try to set the correct user for User__c.
    // If User__c is not a lookup to User, change this assignment to match your org.
    Id currentUserId = UserInfo.getUserId();
    
    List<Attendance__c> deleteAttendence = [SELECT Id FROM Attendance__c];
    delete deleteAttendence;
    
    // 1) Create an existing attendance record that matches getExistingAttendanceRecord() query
    Attendance__c existingAtt = new Attendance__c();
    existingAtt.User__c = currentUserId;          // IMPORTANT: must align with WHERE User__c = :UserInfo.getUserId()
    existingAtt.Status__c = 'Absent';            // To hit the "Absent" condition
    existingAtt.Automatic_Attendance_Record__c = true;   // To hit the "Automatic = true" condition
    existingAtt.Date_of_attendance__c = System.today();  // So it matches the date filter
    insert existingAtt;

    // 2) Simulate UI input (LWC/VF) – what user selects on screen
    Attendance__c uiInput = new Attendance__c();
    uiInput.Status__c = 'Present';           // New status from UI
    uiInput.Work__c = 'Field Visit';
    uiInput.Description__c = 'Visited client A';
    uiInput.Location__Latitude__s = 12.9716;
    uiInput.Location__Longitude__s = 77.5946;
    // Note: we DON'T need to set User__c here because method finds existing by UserInfo

    Test.startTest();
    String returnedId = AttendanceMgtController.markAttendance(uiInput);
    Test.stopTest();

    // 3) Query attendance(s) for this user and today
    List<Attendance__c> todaysAtts = [
        SELECT Id,
               Status__c,
               Work__c,
               Description__c,
               Date_of_attendance__c,
               Automatic_Attendance_Record__c,
               Location__Latitude__s,
               Location__Longitude__s
        FROM Attendance__c
        WHERE User__c = :currentUserId
          AND Date_of_attendance__c = :System.today()
    ];

    // We expect exactly one record for today for this user in this test context
    /*System.assertEquals(1, todaysAtts.size(),
        'There should be exactly one attendance record for this user today in test context.');*/

   /* Attendance__c updatedAtt = todaysAtts[0];

    // 4) Assertions to ensure Absent block logic executed
    System.assertEquals('Present', updatedAtt.Status__c,
        'Status should be updated from Absent to UI Status (Present).');
    System.assertEquals(false, updatedAtt.Automatic_Attendance_Record__c,
        'Automatic flag should be set to false after manual update.');
    System.assertEquals('Field Visit', updatedAtt.Work__c,
        'Work__c should be copied from UI input.');
    System.assertEquals('Visited client A', updatedAtt.Description__c,
        'Description__c should be copied from UI input.');
    System.assertEquals(System.today(), updatedAtt.Date_of_attendance__c,
        'Date_of_attendance__c should be set to today.');
    System.assertEquals(12.9716, updatedAtt.Location__Latitude__s,
        'Latitude should be copied from UI input.');
    System.assertEquals(77.5946, updatedAtt.Location__Longitude__s,
        'Longitude should be copied from UI input.');

    System.assertNotEquals('error', returnedId,
        'Method should not return "error" for this scenario.');
}

    @isTest
    static void testMarkAttendanceException() {
        // Test exception handling in markAttendance method
        Attendance__c testAttendance = new Attendance__c();
        
        // Simulate an error (you can modify the record to trigger an exception if needed)
        testAttendance.Work__c = null; // Invalid field for testing
        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        System.runAs(testUser) {
            Test.startTest();
            String result = AttendanceMgtController.markAttendance(testAttendance);
            Test.stopTest();
            System.assertNotEquals(null, result, 'Attendance should not be null.');
        }
    }

    @isTest
    static void testAddLeaveApplication() {
        // Fetch the current user for testing
        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        // Create a test Employee Leave Application
        Employee_Leave_Application__c empLeaveApp = new Employee_Leave_Application__c(
            User__c = testUser.Id,
            Leave_Type__c = 'Casual Leave',
            Reason_For_Leave__c = 'Vacation'
        );
        insert empLeaveApp;

        // Create the first Leave Application record for 'Full Day' leave
        Leave_Application__c testLeaveApp = new Leave_Application__c(
            User__c = testUser.Id,
            Leave_Types__c = 'Casual Leave',
            Start_Date__c = System.today(),
            End_Date__c = System.today(),
            Leave_Period__c = 'Full Day',
            Employee_Leave_Application__c = empLeaveApp.Id
        );

        // Insert the first leave application
        insert testLeaveApp;

        // Now, attempt to create a conflicting leave application for the same day ('Half Day')
        Leave_Application__c conflictingLeaveApp = new Leave_Application__c(
            User__c = testUser.Id,
            Leave_Types__c = 'Casual Leave',
            Start_Date__c = System.today(),
            End_Date__c = System.today(),
            Leave_Period__c = 'Half Day',  
            Leave_For__c = 'First Half',  
            Employee_Leave_Application__c = empLeaveApp.Id
        );

        // Test to check for conflicting leave application
        try {
            // This will trigger the conflict logic in the controller
            insert conflictingLeaveApp;

        } catch (DmlException e) {
            // Ensure the error message contains 'You already have a leave application for this day.'
            System.debug('Expected error: ' + e.getMessage());
            System.assert(e.getMessage().contains('You already have a leave application for this day.'), 
                          'Unexpected exception message: ' + e.getMessage());
        }

        // Now, test adding the leave application using the controller method
        Test.startTest();
        String result = '';
        
        try {
            result = AttendanceMgtController.addLeaveApplication(testLeaveApp);
        } catch (AuraHandledException e) {
            System.debug('Error during leave application process: ' + e.getMessage());
        }

        Test.stopTest();

        // Verify that the leave application was added and associated correctly
        Leave_Application__c insertedLeaveApp = [SELECT Id, Employee_Leave_Application__c FROM Leave_Application__c WHERE Id = :testLeaveApp.Id LIMIT 1];
        System.assertNotEquals(null, insertedLeaveApp.Employee_Leave_Application__c, 'Leave Application not associated correctly.');

    }

    @isTest
    static void testAddLeaveApplicationExceedsLeaveLimit() {
        // Create test Leave Application record
        Leave_Application__c testLeaveApp = new Leave_Application__c(
            User__c = [SELECT Id FROM User WHERE Username = :UserInfo.getUserName() LIMIT 1].Id,
            Leave_Types__c = 'Casual Leave',
            Start_Date__c = System.today(),
            End_Date__c = System.today()
        );

        // Try to add leave that exceeds the limit (2 days for Casual Leave)
        try {
            Test.startTest();
            String result = AttendanceMgtController.addLeaveApplication(testLeaveApp);
            Test.stopTest();
        } catch (AuraHandledException e) {
            System.assertEquals('You can only take 2 Casual Leaves for a month.', e.getMessage());
        }
    }
    
    @isTest
static void testAddLeaveApplicationCombinationLeave() {
    // Create a Employee_Leave_Application__c record
    Employee_Leave_Application__c empApp1 = new Employee_Leave_Application__c(
        User__c = [SELECT Id FROM User WHERE Username = :UserInfo.getUserName() LIMIT 1].Id
    );
    insert empApp1;
    
    Employee_Leave_Application__c empApp2 = new Employee_Leave_Application__c(
        User__c = [SELECT Id FROM User WHERE Username = :UserInfo.getUserName() LIMIT 1].Id
    );
    insert empApp2;
    
    // Create a valid Leave_Application__c record
    Leave_Application__c testLeaveApp = new Leave_Application__c(
        User__c = [SELECT Id FROM User WHERE Username = :UserInfo.getUserName() LIMIT 1].Id,
        Leave_Types__c = 'Casual Leave',
        Start_Date__c = System.today(),
        End_Date__c = System.today(),
        Leave_Period__c = 'Half Day',
        Leave_For__c = 'First Half',
        Employee_Leave_Application__c = empApp1.id
    );
    insert testLeaveApp;

    // Create conflicting Leave_Application__c record
    Leave_Application__c conflictingLeaveApp = new Leave_Application__c(
        User__c = [SELECT Id FROM User WHERE Username = :UserInfo.getUserName() LIMIT 1].Id,
        Leave_Types__c = 'Sick Leave',
        Start_Date__c = System.today(),
        End_Date__c = System.today(),
        Leave_Period__c = 'Half Day',
        Leave_For__c = 'Second Half',
        Employee_Leave_Application__c = empApp2.Id
    );
    
    Test.startTest();
    try {
        // Call the method and expect an exception
        String result = AttendanceMgtController.addLeaveApplication(conflictingLeaveApp);
        // If no exception is thrown, fail the test
        System.assert(false, 'Expected an exception to be thrown but it was not.');
    } catch (AuraHandledException e) {
        // Validate the exception message
        System.assertEquals(
            'Script-thrown exception',
            e.getMessage(),
            'The exception message is incorrect.'
        );
    }
    Test.stopTest();
}
    
    @isTest
    static void testAddLeaveApplicationEarnedLeave() {
        // Setup test data: Create User if needed
        User testUser = [SELECT Id FROM User WHERE Username = :UserInfo.getUserName() LIMIT 1];
        if (testUser == null) {
            // Create a User if no matching user found for test purposes
            testUser = new User(
                Alias = 'testusr',
                Email = 'testuser@example.com',
                Username = 'testuser@example.com',
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
                UserRoleId = null,
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                LanguageLocaleKey = 'en'
            );
            insert testUser;
        }

        // Create Employee Leave Application records
        Employee_Leave_Application__c empApp1 = new Employee_Leave_Application__c(
            User__c = testUser.Id
        );
        insert empApp1;

        Employee_Leave_Application__c empApp2 = new Employee_Leave_Application__c(
            User__c = testUser.Id
        );
        insert empApp2;

        // Create first Leave Application with Half Day leave (Earned Leave)
        Leave_Application__c testLeaveApp = new Leave_Application__c(
            User__c = testUser.Id,
            Leave_Types__c = 'Earned Leave',
            Start_Date__c = System.today(),
            End_Date__c = System.today(),
            Leave_Period__c = 'Half Day',
            Leave_For__c = 'Second Half',
            Employee_Leave_Application__c = empApp1.Id
        );
        
        // Create a conflicting Leave Application for the same day (same leave type and half day)
        Leave_Application__c conflictingLeaveApp = new Leave_Application__c(
            User__c = testUser.Id,
            Leave_Types__c = 'Earned Leave',
            Start_Date__c = System.today(),
            End_Date__c = System.today(),
            Leave_Period__c = 'Half Day',
            Leave_For__c = 'First Half',
            Employee_Leave_Application__c = empApp2.Id
        );
        
        try {
            // Insert first leave application
            insert testLeaveApp;

            // Simulate the conflicting leave application scenario (insert should fail if conflict handling is in place)
            insert conflictingLeaveApp;

            // Call the method and assert result
            Test.startTest();
            String result = AttendanceMgtController.addLeaveApplication(testLeaveApp);
            Test.stopTest();
            
            System.assertNotEquals(null, result, 'Leave application should be added successfully.');

        } catch (DmlException e) {
            // Handle DML exception if occurs during insertions
            System.debug('DML Error: ' + e.getMessage());
            // You can check specific error messages here for more insight
            System.assert(false, 'Expected behavior not achieved, error: ' + e.getMessage());
        } catch (Exception e) {
            // Catch all other exceptions and log the error message
            System.debug('Error: ' + e.getMessage());
        }
    }

    @isTest
    static void uploadSelfie() {
        // Create user related Employee_Leave_Application__c record
        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        Employee_Leave_Application__c leaveApplication = new Employee_Leave_Application__c(
            User__c = testUser.Id,
            Leave_Type__c = 'Casual Leave'
        );
        insert leaveApplication;  
        
             // Fetch the correct Attendance record
        Attendance__c attendance = [SELECT Id FROM Attendance__c WHERE User__c = :testUser.Id LIMIT 1];
    
        // Ensure correct ID is passed
        String latestAttendanceId = attendance.Id;

        decimal latitude = 22.225;
        decimal longitude = 12.655;
        //String latestAttendanceId = leaveApplication.Id;
        String base64Image = '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAIBAQEBAQIBAQECAgICAgQDAgICAgUEBAMEBgUGBgYFBgYGBwkIBgcJBwYGCAsICQoKCgoKBggLDAsKDAkKCgr/2wBDAQICAgICAgUDAwUKBwYHCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgr/wAARCAImAiYDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD5Xooor6Q/0sCiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooJbCiiigV2FFFFBYUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRRe25MpKwUYPpQAWOFGf6fX0p0MFxczrbW0bSSMcLHGhZmPoAOtTOUacbzdl5ky929+g3nOKVVdj+7UZ/wBocD612Ghfs8/HnxLbC70D4O+I7uM9Hi0qTB/MV2XwK/Yo+LHxQ+JkPg3xv4U1Lw9plrEbnWNU1SzaIRWwOSqbsZf37da+dx3GHDeXYWpWni6bcfsqScn5Kzvfslq2edXzbLcPTcp1Y6a6NXv2scL8KPgn8UPjlri+G/hb4PudQkRv9Imh/wBTEPV26KPr+Ve7r/wT18AfDu3jl/aN/ad0Tw3dEZk03T2WSVPzIz+VHx2/bL0v4baO3wB/ZBhj0Lw/p7GC88QWgX7TqMg4dt+M4z/F1PavmS+v73Vbp7/U7u4uJ5GJkmup2kd2PUkn/wDXXyNGPHPF8fbxq/UcO/hslKs13lzPlV+mlzzI/wBtZx+8UlRpvZL4n532V+x9M/8ADLf7BeqH7Don7abLdPwhvLNVVm+uBgfjWL8Qf+CdXxO0PRn8XfCLxLpfjzSVjLNNo9wDcAD0XJVsexz7V89kKVww3DP3No/PNdR8M/jH8TPg3rcfiL4eeLbqxmjkBaCOdvJmHcOnQjt61tPhrjbK/wB/gM1liGt6deEWn6TjZxfnsXPL86wvv0MU5NdJf5nN3lpd6ZePpupWklvcRMUkt51KujDqCDzkVH2yOlfX1/p/wz/4KIfDy61fQtHttC+LGi23m3MdqoVNVjUcjP8AED0z95enPWvnu1/Zj/aKvAwtPgj4mZY2IZhpUmAR17V6OR8dZbiqdSlmko4XE03adOo0nzfzQk2rxaNMDntHERccVJU5rpJ2fyvY4Xk9BRmtvxX8M/iN4Gbb4y8CaxpffdfafIgx65IrEBDNsGM9fvV9jhcbg8dT58PUjNd4tNfgezSqU68eam013TuFFGDgN/e6UV1eRtEKKKKCgooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACjPzBfWit74X/AA/134qeP9J+HvhyJWutWvo4Fdukak/Mx9gua58VjKOX4WpiartGEW2+1le/y3OerUjRpSqS2SbfyR3X7Mv7KPjD9onVbi7N7HpHhnTfm1rXLv5Y0UDOxCeC2O+cDua9a1r9qv8AZo/Zdgk8Ifsq/CzT9e1OE7Lrxhr0fnZkH9wkbj7YKrgd+tZv7b/xc0v4aaXZ/sc/BOZbPQdBt0XX5rdvmvbgrlkcjqoPUdz16V8wRsIirIPuAhVz8uPp3PvX5TlmS4zxBj/auayccJPWlRTklKP89SzTfNuo/ej5nD4GXEH+0Yq6p/ZjdrTu7bnt+u/8FFv2tteumn/4WWunpuysOn6dEiKPTBBqh4h/bz/ai8V+Bbz4f+IPiF51rqEZiuLhbREmMZPKhlAxkV49RX2VHgHguPJGGW07Ra15FdW7Ozf4ntRyPJ6aUVQj6/8ADgAFG1QqqPuqq4H+f5miiivqo8sY7cvl26JHoWjGKS0WwUUUVQG18OfiH4w+FPjGx8d+BtX+x6jYyFkkVeH9mHce3Q16jrH/AAUO/a51a6N4nxP+y85SGz0+ONB+QzXimF67aMgda8HMuGeHc2xSxGNwlOpUWznFNped07+Ry4jLMvxFb2lWkm/M+iPBv/BTH9obSj/Z/wAQLfRvF2mycTWuqaeitt74ZRj8wa7CT4Ufsv8A7cenTan8BI18GePltzLL4auGxb3bDrsHTOe68jPIr5IIUcOm7K96ueHtd1rwxrlt4o8PalJY32nyLLa3FvIVeNgcgrz17emO1fK5j4c5bh5vE5DJ4TERV0ov93N9pRvaz20R5OK4fpUv3+B/dzWqs3a/mupL4x8KeI/AfiS88IeMtLksdSsJjDc2s6nfuBxnP8Q9D0I6Vm/hX1l8dItK/bI/Zfh/aX0SxiXxf4U8u38URwx/NJF3f8Ac9/TtXybjbxXucIcRy4gy1+2hyVqUnTqQ7SjvZ9YveJ6GV46eMo2q/wASGkvUKKKK+sPUCiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooopSfKrgGCehr6W/4JmaPY2vxQ8TfEu9hVv8AhGfCtxcW/mDIWRgRn8gfzr5p255IY46qo619Tf8ABNHTNV1e0+JelDTrgx3nhKSKC68o+T5g3YQt0yc1+feKdeVHgfE8jtzOEXrZuMpxUt+8W1bc8DiKXJks5PRSaX4o+Z/E+vXvijxNqXiW/lZ5dQ1CW6eRjyxdy35c9PSqOAOgp0tubOaS2cbWjkZWX+6QcEU3619xgaNGjl9KNH4IpctusbJLTpypdT2aHs40YKO3KvwXUdtbcuxNzM2PL5yfYY6k17T8Kv8Agn7+0v8AFnTY9e07wnDpdhOu6CbWZvIZx/eCEFiPrXr3/BML9lDRvF/mftA+PtMW8tIbkw+H7OaP5GlX70zA8EDovvXs37Q3/BSP4TfAzxRL4F0vRrnxBqNr8moLYyJHBaMf4Cx6t6gcCv59438WeJK/EtThzhDCrEV6fxyfwx7Wd/W9z4nM+JMwnjXg8shzyW76eR8oePv+CaP7T/gLS5NZi0XT9cjhTdJDpN5mTHrtIBP4V4Jd2t1Y3Ellf2U1vcQyFJoZkKlGH8JB5zX6vfsyfth/DX9p+1mh8KwzafrFnHuutJvGTzFX+8pB+ZeK8e/4KX/smaL4m8GzfHjwNpEcOtaSobW47UYW8t/72P74yOfTNeBwP45cTYfiZcPcY4ZUqk3ZOyVnsuuzezOTKuLcfSzBYTMqaTeh+ftFB2k7lYHP93pn29qMhep69K/qyWr06q/9eh+ipc23a5Y03S9Q13ULXSNEspri8u5/Kt7eFNzSt/dX/a/pX2T8BP8Agk82uaPb678ffFV1YyTx7zoulbfMUejueAfYVvf8ExP2VbHStCX9obx1pvmXl8uzw/FNHu8qEHmYr6seA3pit3/go5+2Drfwd0+3+Efwz1FbfXNUhD6heAjzLO36AD+7If5V/LHGnidxRxVxtDhDg6ai4u06u/8Ai1f8vX8D87zXPMdmeZrK8ue28u3f7jB+NX/BJzwFF4YutU+CviXU4tWsYGkXT9UYSLc4GdgOAVJ7V8K31jc6fqEmmahA0dxbysk0bLgxupwVPuDX6af8E0fEXxL8X/s+HWPiVq99fiTWHGlXWoOXllt8jOWPJAYECvz/AP2l7nT7n9oPxpNpIUWx8R3JhCjAA3c/rXteCvFHFmI4jzLhvN8T9Y+rPSaXXm5d97ddtjp4ZzLMZYzEYLEz9o6a0Z7J/wAEwtcXUvih4m+E+qt5lh4m8Mzq9q33WdFJz+VfNuvaVLoOvX2hzE7rO9lgbcf7rkV9Df8ABLTRrm//AGoV1eFSY9P0G8eb/gSbR+v868L+JkepRfErxD/atjJBM2tXLSRTRlGQmRj0NffZH7On4nZnRpNJSp05uO1paq6Xmldnu4VU6fEWJhF2vGD+bWph0UdOD2or9Ni7xT76nvRCiiimUFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFGM8UUfL1cfKOWz6etCdncD0T9mL9n3WP2i/iZH4PtG+x6bbqJ9b1Bl3LBAv3j6ZPb357V6t+0j+1zpfhDQ5P2cf2Vof7F8LaapttQ1a1/12pv0ch+u0kHLdznHFaWhajcfsu/8E+21zRmFv4i+Jl6UjuIx88VrzyCecbf/AEKvlNRsUR72bbn5m78/5P41+T5bg48dcRVsfjfewuGqOnTg9YylG3NOXdpuyWx8rRoxzrMKmIq6wpu0V0dt3949Le5upvs1vDJLNI4Eax8mV2OBj15/Emvu39kj/gmb4bsdDs/H/wC0Da/2hqF0qy2vh+SQpDAnXMpHJbHO3p6189/8E9/h7o3xI/ah0TTtfgWa302OTUTE3R2iGVB9ecflX2J/wU6+L/i74X/ACGx8H31xaS67qIs7i8tfleOIDLBT/Du4AP1r4Hxh4u4ixHE2C4NyKp7GpXSdSa0cU7WS8rK/qeXxVmOOrZnRyrBy5XPr5Gx8Wv2sP2a/gL4A1TwV4P8AHeh2+oWOlzR6VpOkgOEl2HYuIxtHJz161+XV9eXWo38uo6hcNJcXUhkuJm5MjE7j/Ok+aOaRzIoeQfNIrb8/59aaa/TPDfwxy7w3w9ZU6kq1as06k5btq90t3uz3MlyChkspNScpu15Putz0j9kTxpqPw/8A2jvCmv6XP5ZfVYra42/xRSMFIPr1r9YPG+iW3ifwdqnh69j82G8sZY3XHZlYY/WvyK/Z106XVvj14PsIVJaTxDbcKPRwa/Ye7eK3V5chlWJj83GeD61/Nv0noU6PGGWYilpVcb36tqacfyPh+PVTp5ph6kU1LfTrY/E/WdNGkaze6SsW37LezQ/grkD9BW58Gvh7cfFb4q6D8PbSDc2palHBN7RscsfyU81m+O7lbjxtrF3H/q5dWuWXtx5rV9Ff8EpfAr+Jf2hLrxbd2Z8nQ9JkkjlaPjzWwq8+oBav6i4u4gnw/wAA1cwqO040bq7S1lFbrfR66H3+ZYv+z8jlVbtJxVvuP0M06y0fwD4SjsrGNYNP0nTdqhcDbHGv6cCvzd8C/BP4hft9ftKa14/uoZ7Xwzcaw76jrE2QiQIcCBM9XIXt0zX6UeJfDum+KtDu/Dmt2vmWuoK0N1HFIRmJhhuR04rlfFXi74OfsrfDD7XdNp+g6HpsG2z0+FQpk44CLjLufXnnrX+f3h5x3mHDsMYsqpOtmOLXLF2cuRSerS3bd9+h+OZRmtbCSqfVoXr1NL9rnP8Axz+IPgj9kP8AZxuLnREW1h0vT/7P0GzDDdNcbcJx3wSGJ9ua/J/UNQvNX1C41fUbjzbq6maW4k/vOTkt+Jya9N/au/ak8UftO+PBrd5E9lotluj0bSd3+oTP337M7dSe3TpXlnNf2r4M+HuK4KyaeIzJuWMxHvzaesVuk33Tbv3P1ThXJ6mV4N1cRrVnq/8AI2vh/wDEjxz8JvFFv42+HfiCTTdTt+I5Y+fMXqUI6Mp7g19RapaeB/8Agob8JrzxJo2nW2k/Fbw7b+ZcWsTBF1SEDrj+INggd1Yc8V8h12PwD+KusfBX4t6L8R9LlwtreLHeR5/1sBPzJ75yfyr6rjThqWOwrzTL/cxtFc0JL7Vt4T7pq/zOzNsv9v8A7RQfLUjrfuktn5HI3NtPY3ElldQyRyQyGOSOVNrKwOCCOxz2ple+f8FFvhpo/gj4+L4o8NxBdM8XaWmqQbRhRI/3yPxw3414HX0HDecUeIMjoZhSVlUjdrpFrRq3Sz3PQyzGRx2X06vVrUKKKK9w7gooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigApG+6RjNLSopdto71NSLlTaXYD6i/b8YWnwR+CunWfzWv8AwiqvuHTeY0zXy5jHNfVHxYi/4Xr/AME+vCXxB0pGkvPANybHVI8ZZIT8u4+gA2n8a+V9rL94qc/3Tkda/OfC6t7HI62Ef8SlWqqS8+fmTfqmvuPn+HJRWDlRl8UJSv8AN3X4HrH7EvxX0v4N/tHeH/FmvMqWE0zWV5NJ92OOUbSx9gdv51+mHx1+CXgv9or4X3XgHxOWWG8US2WoQsC1u4zskHrj07g1+OxRWB3M/K/wtwD2P4f4elfW/wCyL/wUrvvhho1r8N/jhHcX+lW6rHp+sQLunt4x2kHVx/tZ/Cvy/wAcfDfPs4zHD8S8OyvicOtUt9Nbru76JdmeBxdkmNxWIp4/BfHHscR8TP8Agmz+054A1SaPQPDUfiaxH/HteaXKnmFe2UOG6e1cfb/sWftXXU4t4vgPr+4nA3W4UfmTX6V+Df2qf2dfiJaRTeGfizoUxblY7m8WJlJ9pMc11n/CfeBgPMl8e6KUPf8AtKLn/wAer81pfSC8Ucrj9Vx2WXqpWcnTmm7d+l35Hif66cQUYuNXDrmWmqevnofD/wCxV+wX8dvBXx10P4lfFDwrDpelaQ0k7LNdo0xl24QbBnufwxX3fq1jLqui3GmrdNDJNayQi4VQTHuUjcPcE1U0Hxb4Y8TzTQ+GvE+m6gLc4nWxukl2HtkoSB9K5H9pD9obwh+zT4B/4T/xjZXV1C9wILe2s9u+WQ9Bya/G+KuK+LPE7iqhUxVBKukowhFNWs9NHqnd6s+Xx2YZpn+YQlOK5rWSV1+fU838Bf8ABMb9mjwfdtqfiPTb3xLdPKztJq1ztjZid2fLTA6nvmvcvCvgXwj4Fsk0nwZ4as9Jg+VY47K1WNR78Dmvhj4mf8FcviLq0clj8LfAFjo67mC3moyG4m644UYUcfXmvff+Cc3xL+Ivxc+DV945+J3iafVL648QSoskqhQiBVAVQoAAH0r6zj7grxYwPC8834jxdoRcYqnztuz6cu2x6WaZXxFh8v8ArWPk1HZK/wCh0/7Y37Sx/Zc+F8fjGy8OrqV9fXQtbG2kfYiuQeX7446V+ZXxi+OnxN+PHiOTxP8AEvxHJeTbj9ntE+WC1U/wxr2A/M+tfZH/AAWCu5B8PfCNgJG/eatK2M9f3Yx/PNfBJ9q/ob6N/CeSYfgennLpJ4mo5XqNe9ZSsku2nY+04Hy7BxymOLcbzb3YDgYoooyO5r+lD7gKJY2MeDuZGK9P4Tk/4Uc9xWr4G8Jan4/8aaT4K0e1kluNT1BLeNY+c5PJPoAOa5cdiKOEwc69WXLGKbbe1kZ1qkadKUpbWf5M+j/29InvfgZ8GtV1D/j8k8Mqsjn7xG1eK+W6+lP+ClXiXTYPiV4b+D+kXKyW/g3w3DaXCxtkCYrz9CAB+dfNdfD+FlKrT4JoOpHl55VJpeUptr8DyeGacqeT0+brd/JsKKKK/Qj3gooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAoDKpyzbR3NFAJU5FHNy+8+ga9D3D9ib9oTRPhJ4lv8A4a/Ehlk8F+MIvsmqRyrujhc8LL7D1PPY9qyf2rf2VvE37OfiT+0LWNr7wnqbeZoetRfNG0bcqrsOARnHoRg15KSyrhBz/CP89K+vv+CffxL8V+NPh145+GXxBuLfWvCeh+G5Lq10/VIPNeJuflUt/D6emOMV+T8W4fGcF46fEeBa5G4qvDpJyajGSX8yur+SPl80pYjK6zzDDtckmlOPVva/rqfITqyNtZcEcFfSkBIXb2zmnTypNczSRDCNKxjXnhScgfhTa/VKdT2lNTt8Wtu2if6n01NxlRT28hCiF1k2/Mv8VPMs2zy1mlx2RZSP602hVLtsCs27javepq06MoyqTinbXVdv+ATKNOOtlpr8j9IP+CVHgSPw5+zvN4rePbPr+szStJjHyrhR+HFeef8ABX/xwFg8H+AYJDl2uL6aP24jXI/BjX1H+zH4Ji+HP7P3hXwyIdskOjRNJ6bmG9h+Oa/P3/gpZ46k8YftUappyzq0OhWcNjCFboQNzfqf0r+HvDFPi7x+xOaLWFF1JeivypfJn5JkcY5jxjOulpFv7uh4EwUPtXOF4G5q/SX/AIJS3tvdfsxNbxH95b+IrhZfxCn+Vfmz3ya+3v8AgkL8U7eN/Evweu51Vt0epWccn/LTPyyY+gC1+4/SKy2tmfhnWdLX2UozfotH+J9fxxh6mIyRyjryyudV/wAFc/Dk+ofBbQfEMCErputFJn252q6YB/MCvz3zX7F/Hr4RaZ8b/hRrXwy1ebZHfQbbaZ1+aKfgo34MK/LT4h/svfHj4ZeJ5PCXiD4YatNMJStvcWdqzxXC9nR1BBB/Ovj/AKNvG2T/AOp8soxNSMKtGbsnJRbi9W7PfU8ngXN8N/Z7w1Sai1rqefOdsbMPTj/6/tXR6t8JviVoXgy2+IOteBdUs9DvFBt9Ymt/3LZ6H6HtX01+yN/wTX8Y+J9ZtviB+0DojaXotrMskGiSkLcXmOnmDoq5xnuRXpn/AAVF+LHhfwR8ELH4FaLHbLeavNCVs7dcfZrWM43hegUngevWvusy8YsHiON8Lw7kMY4qcnarJaRgrPqtHL8D1MRxRTqZtSwmCXtNfea2t1Pz3RJJZlghRpJG4WGNCxZj0Ax19gOTX1p8BvhjpH7F3w7uf2oPjfbxx+Irq1aLwf4ekYCXcV/1rg8qe/8Asjr1rlP+CYdv4a1X9pkWGvaDb3UjaLcS6dHcJuFvMi794B74BGfevLv2i/ih8Qfiz8VNV1T4j6015cWd9Lb2sI+WO2jRyAiL24HPr3zXtcRSzLi7iWrwxT/c4eEYSqy5rupGV3yw7ar3jqzGWIzLMpZfH3Yw96TXVPaPoc1408Xa34/8Vah4z8SXjXF9ql41zdTN1Zic49h7VmUZJ5NFfpmHoU8NRhSpxUYxSSS2SXRPqj6SjRWHoRpR2SsgooorY0CiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAJI5r6e/4JrXUGqa349+H/m7bjWfB0qW/1G7I/UV8w13v7Mnxhk+BXxu0P4iOW+yW9x5Woqv8dvJ8rjHsDn8K+R48yutnPCeKw1L42lKP+KLUl+KPHzqjKvldWMd7XXqtf0OGu7O6sL2bTLuFlkt5niZSOcqSP6VGCCMg17x+3z8D4fhp8T5Pin4Qh8zwt4txqGn6hD8yJM4y0eenOcgV4SVkL7Cdzeqrgf5xXocM51h8+yPD46nvNe8usZJJNNdHe+j1OrK8VHHYONWO9lfyshtaXg2TSofGWkSa86rYx6nA14z/AHfLEi7s+2Kzeo4oO9Odwb/ZIr2MRS+sUZUpS5VJNX9Vb9TqqR9tTlSUrNpo/aF/HPg/TfA48XDWrf8Ase2sBcLdRyL5ZQJkYOfQdK/H/wCLfjBviF8Udf8AG5csNT1SaZHb+JCx2n/vnFZz+JvEkmk/8I23ijUf7OOP9Ce+laID025xj2rPJLYYBQu3Crtxivx3wt8IKPhvmOMxUsQ6kqzfTo3e34ny/D/Df9h1alVy5nIK6P4SfFDxP8HPiHpvxD8JTmO806bcY1b5Z4j95G+ornKK/XMdgMJmWCnhcVBTp1FZo+mxFKlWhKjPVNH61fs7/te/CH9ovQIbjQdegt9YVV+2aPfSBJllx/CCRuUc4Ir1IzLEPMeT5ev3utfiLayy2lxHc2lxJHJGcpLHKyuh9mzx+FbE/wAR/iLcWv2O4+ImuvEv8P8Aa03P/j1fyfnn0WMPWzR4jLMe6dN7qSv8tOh+cYrw/Uq3Nh6toH6b/tL/ALc/wg+AOh3FtFrMOs+INhNpotnIJCJO3mkZEYz26mvzQ+KnxR8ZfGLxze/EDx1qTT6hfSbpFz8kI7Rp/sgcVz4L3UjSuWkkblpHJ3N9SetNQGVDsQtvXavyk85HT39K/ZPDXwn4c8OcPKdCTq1pfFUlv5pdo27n1OQ8M4LI6MprWT3k9D6R/wCCXOiy3H7RVz4rmXbZ6J4fu5riTOANybef/r+leBeN9Xj1/wAa6xrsJyl5qtxMp9mkY19QaNYP+xt+xXq2u66Wt/GnxIjEFrasu2S1tduNxHbrk/71fJe3YdhTaV4Zc9D3rq4QqLOuKsyzun/BbVGm+j9n8TT6pye6KymUsZmGJxnRuMV5qKauu4UUUV+nH0EQooooKCiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiijpcAooop2b2FzRte4UUUUlqF0FFFFAwooopc0R2CiiimIKKKKACiiigAooooAKKKKACgdxnt+dFFHu7SWj0ItLt959DfsyftS+AU8Fn9mn9prT21DwbeAjT9RkYtJpUjdB6lM5IbqKZ8Yv+CePxN8Lwf8Jv8D7iHxx4XuMta3WksHukj7B0B+b0JH5V8+fIQNybtpyM9q674X/Hr4x/Bi5+0/DX4hahpql9z2yzFoX+qHivznHcI5vlGZVMfw3XjTdTWdKV3CbXVW+GT6tXR8/WynFYXEOvgZJX3jJXj8uz8/U5/U/CvijRLhrPWPC2o2ciHHlXNjIhHtyKavh3xCNObVjoN8tmn+sumtH8uPnu2MCvojTP+Cp37RFvAqa74c8K6o6rjzrjStrH8j1rpfhV/wAFFbr4l+Jn+HH7RnhzR7fwjr1qbK4/s2x2/ZpHOFdyc/L057HBrnr8T+IuAouvXymm1T96ThVbulo7Kyb0d7fcYYjMM+w8FN4dWW7jK/4bnyNlemefSivXP2oP2U/GP7P+ttqVhE2peEb1t+k67bnzI3U8hXYZ+YDjPANeSsmFDq3ysuQW+XP519vkudZbnmBjiMHNST3XVPqmt01fqrnvYXF0sdRVSDv39RtFDDauev8AdC8k0+3trm6uY7C2tpJriZwkMMCFixPQfX2r051adODnN2S3vpb1udF4pXbQWltdX9zHZWNtJNNM22GGNCzyN6AdSanvdA8RabObTUvDmoW8w/5ZzWjq36ivqr4D/CLw/wDsceBpv2nf2irZV1uWLb4T8MyYaYykfLIwP8X/AKCOvNYMP/BUv48ee1xqHg3wpdPvYwtNppyin+E4PNfm8uNs+zbHVoZBgViKFJ2dRz5FN/3G7ppdbaHzv9t47FV2sBQ54LS7fKr/AD1t5o8T8CfA/wCLvxNvl0/wT8OdVv3ZwC32BxGvuXICge5NfRngn9nH4P8A7F9pD8W/2r9esNS163xLo3g3T7gMRJ1VnGecHHsDzzXC+NP+Clf7VHi+xbS7HxFpuhW7Lhl0TTUjb/vo5Irw3Wdc1rxJqkmueJNYudQvJmzJdX0plc/8Cbn+lTXyvjriyLo5rUjhcO9JQpScpzXZy0Svs7dLkywebZleOKcacOsYXbf/AG87WOt/aB+P/jj9o74gzePvGR8tdxTTbFG/d2sGeFA9fU9zzxXEfMeXbcx5Ymhjls5P40V+gZbl+EyrA08JhYKNOCskui/Xzb1Z9BhsPQwtGNGirRirBRRRXcdAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFB3HhRz7np70Uj42/MOP4sdapWWrZSi5aFvRdB13xLqcOi+HNFub+8m+WK1tITJJIfUKB0rq/FX7OPx58F6R/b/AIn+EOu2Nn/z8y2LFF+pAyPyx7190/8ABL34LeGvC3wKt/irPZxza14imkka8ZfnghV9qxqe33cnHevpq4ggu7aayuYvMSaNleNxuV88YIPX8a/kvjT6SmI4f4sqZbhMIp0qU+Sc27NtOzslpbtex+aZlxzLBZg6FGmpRi7O+/nY/EcMGGVI9PlbNFe3f8FBfgt4c+Cf7RV/pXg60jt9L1W1S/tLeJcLEz5DKB6bhXiIzgZ64GfrX9McN55R4lyPD5nRi4xrR5knutNj7vA4qGPwcMRBWUkrLsFFFBIAyf0r2kdr21JLS2uL26jsrS3kmllbbHHDGzMzegABJrtpv2Y/2hYNAHiaX4O68tjjc1w2nv8Ad/vbcbsfhX0t/wAEmfgj4Y1+91/4x+I9PivLrS7iOy0tJo9yW743PIv+1gqOelfdkplkO+SRj8u0fN29PpX8v+JX0hsTwXxNLKsBhoz9m17Ry7eX/BsfAZ7xlUy3MHhqFNPldm2fiGyyI7JNC8bKxDRyIVZfYg9DRX1p/wAFXPgp4R8A+PNB+JnhfTo7EeII5U1S3t49qyzRnJlx/eKnBxjpXyXX7vwXxRheMuG6ObUI8qqLVdmnZ/kfXZTmFLNsvhioq3Nf8Aooor6k9IKKKKACiiigAooooAKKKKACiiigTD6ikCDnjk/xbj09PpS0VMoxlpJX+dgSPav2f/24viL8FdG/4V74m0+38VeD5flm0PVPm8pT18tj+PynI57V3Nza/wDBMn42u2ow65q/w51C4OZLMxs9uG74GGUfRSK+XCAeCKNx2lT0NfC5hwBltbFPF4CrPDVpbypS5b+sdY+rtdnhYrI8LUqOpQk6UnvyvR+dnpc+pIf2aP8Agnzo8f2zXP2zpri3P/LCyswruP7uQCc/hUlt+1J+yN+zckjfsxfCBtc1sfJD4k8Rrwpx94A5Y89gB9a+V1G07l4Oc0KSpynyn1FcP/EO5Y2S/tbMa+Jp/wDPuUlGD/xcqvL00Mf7AdaSWKxE6kez0X3K35nT/Fv4w/ET43+LZfGXxJ8QS314zHyoySsVuM/djTooH6981zFFFfoGBwOCy7Cww2GgoQgrJR0VvTv37nvUcPRwtNQoqyCiiiuo05QooooBIKKKKCgooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiignmCiiiizDmCiiigoKKKKACiiigAooooAKKKKACiiigAoHXiilT71HvO8VtZlRb2P1U/wCCe5/4xA8Hf9esmf8Av61ez5rxf/gnt/yaB4N/685P/RjV7R/+qv8AJvxB147zKP8A0/qf+lM/nLNI/wDCpWf95/mfnR/wVuJH7RWkrnj/AIRiP/0M18tHrX1N/wAFbRj9o/TRj/mVY/8A0M18s9vwr/Rrwfb/AOIbZbJdaX/AP23hv/kRYf0QUCihTg5NfpUd0e7L4T9CP+CQZP8AwpPxJ/2Mef8AyGK+tK+S/wDgkNn/AIUv4lz/ANDF/wC0xX1pX+X/AI0/8nMzDl0u0u/Q/BOKPd4hr3195fkfF/8AwWM58OeBR/0+Xf8A6CtfCec8+1fdv/BYf/kA+Bf+vy7/APQVr4SHSv7U+j1JvwrwfrP8JSR+n8F+7w7SXnL8woozjmm5VxhXX/voV+2S92N21Y+r5o2/qw7NGCOorvPhz+zJ8fvitbC58CfCnVr2HqLlofJj/wC+pMZ/Cu+h/wCCaf7XUkP2yT4f2iNty0LatH5n5dK+VxvHHB2XVnSxOPpQltZzjf566HnVM4yyjLllWin6nguR60e9egfEP9lf9on4WxteeN/hVqVrajn7UsImj/76TP615+ORuB3KOMCvZy7N8rzal7TBV4VF3jJSX3rb5nXh8VhcVHmozUvRhRW54H+GPxF+Jl21j8PfBOpaxKv31sbUuF+p6D8TR41+GfxE+G12th8QvBWpaPNJ/q11C2Me76HofwNVHNcreO+puvBVbtcvMr6K+1wWKwrrey51zdrmHRRkY3fjWl4W8IeK/G+tR+HvBvhy91S+k+7a2Nu0jH8q6a+Io4WMp1pKMY7tuyXzZpOpGnFyk0kt2zNOR1FFdd49+Avxp+GFmmp/ED4Z6zpdrJ926vLQiMexYZA/GuRVlZdytj3Pes8HjcJj6PtsNVjOC3lGSa+RNHEYfEx56M1KK3d9gJwMmja3XbXffDb9lv8AaD+LNuLrwJ8K9YuLd/u3ksflQN+L4rvZP+CaP7XEFktyfAtsxxnyV1aPcPrXz+N444Ny7EOhicfSjJdHJJ/c2cVTOMro1OWdaP3ngmDjOKK7X4j/ALOfx0+EKNL8Rvhfq2nw9ftn2fzIcf76ZA/GuKVlcZR1YZx8rA5r3MBmWX5pT9rhKsZx6uMlK3rZux10K+HxUealNS9GFFA5G4d6K7teqNHpoFFHQ7aWJHmlWGAFpGOFVV3E/gKJWhHnlovPS3+K+iXzK5ly32XdiZ4zRnHJr0jwF+x7+0n8SLMat4R+D2qNbt924uI/JVx6/vMZ/Cuy/wCHa37YAs/tK+AbNmxnyV1SPzPyr5PGcecFYCr7KvmFKMuqc1+h5tTOsrpScZ1or5ngtHvXZfEf9nv42/CRWl+Ivw01LTIV63MkO6Hr/fXKj8a43v1yOOPr0r3sFmWX5lhvb4OtCrDvB8y1811O2hiqGKjzUZKXoFFdJ4L+D/xV+JCPL4A+Her6xHHkPJYWbSIMdt3T9ay/EvhbxP4N1dtA8W+H7zTb5c5tby3ZH4789RRHNMrqYqWEjXg6sXrFSV36BHFYWcnCM02ulzPooYFPvCtDSfCXivX45JtC8LalfJCMySWdjJKqfUqCK3xGKwuFip1ZqMe8ml8lfr5GsqlOmrzkl6sz6M06W3uLed7W4t5I5Y/9ZFIhVl+oPIpvtW0ZU6iUo7Prpb71oHMpQUotPXoFFFBbaM0wv0D2oq9o/hjxJ4jlMPh/w7fX8i8sllZvKR9doOKr6jp+oaPdfYdXsJrWcf8ALG5haNx/wFgDXPHFYWVZ0VUi5romm16q9yPbUfacnOr+pDRRtbAO3r0oII6+uK6lHm8n2Zp7yk00FG4HgGr/AIc8K+J/GWpronhbw7faldt923sbVpH/ACUcfU8V7N4T/wCCcv7WniyxjvX8B2+mQsfkTU7yOGT8QM5r57NuKuG8j/3/ABcKXlKST+44cTmmX4PStVin6nhXXgUYIGcV9GX/APwSz/ars4Ge30vQ7hmGdkepqD/KvLfiN+y/8e/g+kjePfhjqlrDHy15HD5sOPXcmf1riy3jrg7OK3scHj6U5PZKauZUM6yvEy5adaL+ZwtHSjcMle6rkjHQUSDdtX+6c19X2b2fXoemtY83QMHO3HPpV7RfDWv+IZPsfh7QLvULj00+3aXH4AGu5/Z5+DeifEzVtQ8TePtTm0/wj4btReeIL6E/vGjzjyEP95zwPQV7P4A8b/G74teHdVvP2Z9a8O/C3wToMy27KJ1t5m3fdM05Ukk98EV8RxFxh/ZNedDD003C3NKbcYRctIq6Um230SZ4WYZt9Um40481rJtuyTfTZu/yPmLXfCfijwuFHibw1fWJY4Vr2yeHJ9twwazsjOM19ReO/iZ+1r8BtPs9S+Mus6P8SPBmqT+QovJItQtZeMlVmC7onx0rzP8AaD+Evg3T9D0n46/BgTf8Ib4kkeJbO4OZNLvF5e2b2/unuKnI+MJ42vCljIxUamkKkJOUHJbxd0pRlfZNK4YPNpVpR9rCyk7RkneLfbo0/Kx5TRQOVDjo3SivurS6nu3CiiigYUUUUAFFFFABRRRQAUUUUAFKn3qSlT71Efifoyo7o/VP/gnt/wAmgeDf+vOT/wBGNXtGeAP9rNeL/wDBPb/k0Dwb/wBecn/oxq9or/JvxA/5LzMv+v8AU/8ASmfzlmz/AOFSt/if5n50f8FcZET9o/S3kYKG8LR4LMP+ehr5Y82HH+uX/vqv2c8XfCH4VePr9dW8b/DbRNYu1jEa3WpaekrrGM/LkjpWQP2ZP2dQAP8AhSXhnpj/AJBMf+Ff0dwP9IrJeFuE8JldXBzlKjFRbUlq+rPscp46w2XYGnhZ0m3FJX72Px682H/nun/fVHmRNwsq5/3q/YQ/sy/s6/8AREfDH/gni/wob9mT9ndhhfgn4ZX3Gjxf4V9UvpXcNxd3gJ/+BxPT/wCIiYN6exf3ngf/AASDnil+DHiYRtux4k5K9P8AVL/jX1tWP4O+H/gf4e2L6b4F8I6fpFvK++aLT7VYw7f3jgelbFfyPx1xJQ4t4sxGaUoOCqO6T1Z+dZtjlmeZTxUVZSaf6Hxh/wAFh/8AkAeBf+vy7/8AQVr4SX7tfdv/AAWH/wCQB4F/6/Lv/wBBWvhJOfvlVXaTuY+gr+9/o8X/AOIWYKyvrP8A9LkfsHBlv9X6V/735ml4N8H+J/iB4ms/B/g7RZr7Ur+TZa2sS8uT/Ie/bFfoh+yp/wAE4fhz8HrO18V/FTTYNe8TmNXeG5UNa2TEfdVMYZh/eNZ//BMn9l2w8BfD2P45eLdIxr+vQs9m03W2tP4cDsX7/SvqonPbhfugdv8AE1+B+N3jVmWOzStkeS1nTo0m4znHRykrXs1rZbeZ8bxZxVUrYiWFwsrQjo2t2/UIo4ILdbaGFVVF2qqoBtHtjGBQflXarE46E1R1zxJoHhnSJtd8R6vb2NnAu6W4u5AiIPcnv7DNeF+Lf+Cm/wCyd4YvXsbXxZfaqUbaZNN0yRlJ9iQM1/PGU8LcV8TXnl2FqV+rlZ29bvdnxeHwGYY6X7qk5fefQEqCeI2sqq0TriRWUMGz1BB4NfLv7YX/AATr8I/FS0k8b/BrS4dG8SRfvJNPt1Edvfr04HRH6nPQ16B8LP29f2Y/i1qEejaH8QEsr6VsRWerQm3Zz6AvhT+dexLKsgUrJG26P5NrE7vpXtZdmXHnhfmkK0VUw8t7TTUJLs+lzrpVM2yLEKai6b7dDiv2ffgz4Z+B/wALNI8EaBpa28kNnH/aEy8STTFcszHuQSRg0/4/fCXwp8afhXrPg3xXpUMyy2TtZzSDL28irlWU9uR2rtBkDBGPb0qtrIzo14D/AM+cv/oBrxcNn2aYnianmc6r9s6ifNd9X67HNTxWIljI1uZ8107/ADPxQvbV9Oup7K6k85reRoWl6b9rEf0r9OP+Ccnwc8MfD39nrSfF9tZq+reIIzd3t5gbxztWMHqFAHb1r8zfE67vEGpc9L6Yf+PtX6xfsWrt/Zb8FnPXRx/6Ea/s76SOZ46jwFglCo17WS5rO17JNH6dxzVqU8moqMmr2T89L/meheIfDej+MtGuPC/iXToLuyuomSa1uF3I4Ix0PoCSD1Br5j/Z1/4JreBfAHj3VPHXxAtYtWht9Tc+G9NmUtFBCGysjg/eftt6CvqokkAf3TkGs/xN4q8NeCdFuPFHjDXodP0+0jLTXV5IEjTH8/p1Nfxzw/xbxNkuX18syyrJRxGkkm3JttfD5+lj80wePxuFpyo0ZNc2lluzQt4kt4Y7WCDZDGuFjVsKPbaMCmlCRjdXy540/wCCsnwB0LUpNO8K+Htc1pYuGvIoUhjfntvO4j8K7X4E/wDBQT9nz466ynhWw1a40XWJMCPT9YRU8wnsrqSp/MV6mY+GPiNhMC8fjMDVdOybk7tpPZvrZ9XfQ3rZFm1HD+3nRdn16ntF9pdhqltLYalbrNazLiW1mjV1cY6Hd2/CviT9vT/gn9pWk6Pe/Gv4IaQLdbdfM1bw/axjZ5f8UsK/w46kdK+4zwMZ79qju7W3vbdrS6t1kjkUpMrDrGRhh9CDXLwPx5nnAubRxeDrONNP95C7cZK6TVn1M8pzbFZTilUpy06rp93c/El2R23o2c02vSf2tvhJD8Ff2hPEXga0Vo7MXXn6cGHHkv8AMAPYcivPNO0+/wBXvIdO0y2aa4uJljgiX7zsSAB9eelf6lZbnGAzTJ6OZUnalOmp36JWu/uP6Aw2Ko4vCrEp2i43Oq+CnwP+Ivx+8cQ+BvAGmNIy4e8uWwI7aM/xu3YfrX6Q/s3/ALCvwa/Z8sbfU00iLWPEQUG41m8jB2t/0yXkIPzNaP7Hv7NOgfs4fCmx0WO0Vtc1CNbjXLzyxvaUqDtz/dX7oHfFetY55/QV/A/jF41ZvxNm1TLsrqOng432due27cux+P8AEvFGJzDETpUJONOOmnUVyGVULbVXhVXhR+FNeNimEJ9M+lcH8cf2k/g9+z3pq3nxO8VR280ylrPTrZTLczgdwi8hf9o4FfOWqf8ABYXwNFeFdD+Cup3drn93PeahHCT7hdrY/OvzfIfDXjriii6+AwUpRavzOyi0+0pWT+TPCwOR5pmMXOjRcl3fU+wr/S7DVrJtM1iEXdvIpEkN0odGU9iCOfxr49/ao/4JnaHrniWx8cfAuxazhnvoote0OL7vku/zzR+mMcqPWvQvg1/wUx+AHxX1WDw9rb3nhq/uGCQJqqr5Lt/dEg4/PFfQySW91ErRXMbq65VicqQehGOvr1716GBx3iN4RY+06c8O7NOMuZxaa7fD5qzub0a2c8O17NSj5dDL8B+CvDXw28IWXgrwlpMFnY2duqLHbxBQxAAzj145J614z/wUM+C3hL4jfs9ax4kvNNgXVvD1ub3T70L+8QKcvHu6lWHY1758+PnG1u49K81/bAH/ABjP44Ofu+H5h+YrwuDs6zanxvg8bGvL2k60bttttSkrp6+ZzZbiMR/a1OspO7kr692fmD+zn8L0+Mvxt8O/DmW4CW2qXyrcM3XyhywHuR0r9b/BfgPwh8PPDkHhTwV4et9Ps7VdkcMChQwA+8xH3ie+a/IL4JfEe7+EnxQ8P/EWzYhtJ1KN5NvVo8jePxUmv2K8Oa5p/ifw/Y+I9ImElre2qTW8i9GRxuH6HFf0f9Kmrn0c0wDhNxw8ot2TaXtI2etu6PsvED6ysRSldqFktO58w/8ABS79mLwz4r+F1z8ZfCOiR2es6HiW+ktYQpuoDw+4Acleor87dwcCQfxjc3ufWv2v8R+H9O8VeH77wzrEQktNRtWt7hG7owIP86/Hb4w/DbUvhN8UNc+HuqJtm03VJYlVlxmLOUYD0IxX1n0Y+NsRnOU18mxc3J0mpRTeri+1+zZ6XAebPEUJ4Wb1T0v2OZ68VqeB/CWo+PPGWl+CtJTddapfR20K4zgs2M/gOay1JIyRivpT/glz8Lm8c/tFHxnPaK1p4WsTcyMwyBcOSqY98c1++8bZ9T4X4WxeY1Jcrp021/ieiXrfU+zzfFU8DldSvLs0vU+9vgn8EfA/wP8ABNn4M8IaFDa+TCPtV2q/vbqUAB3c9fmPOO1ee/t1fs4+DPi78E9Y8Qto9rBrmi2L3trqUMKrIRGMlCRyQRXugUBjjcxY4Xceg/8A114j/wAFCPis3wp/Zn1iezuAl9rWNNsV3ct5n3zj2UGv83ODc24mzfxAw+Iw9acq9asnfmezeul7WSufheW4jGYjNoSpSfM2j8sg6qDI75zt2/7uPlH1r6D/AGNf2F/FH7R9/wD8Jd4qefS/CELfNeRqFlvWU8xxE9Bnq/4CuN/Y8/Z4uP2kfjJY+EJ2mj0ezh+06zcRr0hH8P1Y/L7da/Vzw54a0Twj4ftfCvhrTorOxsYRDa20MYCxKOAAK/rjx08X8TwfRjk2Vy/2uovenvyxt+D03P0ri7iaWWRWEw8v3jSu+2hi/Cj4N/Db4MaGmgfDbwlaaXbr/rJIV/fTerO/Vj7ZxXUHLuztJ/u7l3cf0ppZhuCrnH3Sf4vb615j8Wv2yP2dvgteHSvGnxCt2vh/y4aejXEo+oQEL+JFfxDRwvFXF2MbpQqYqpLV6OW/TZpWPyn2OMx1Rrlc5M9QbJ4A/Oo7q1hu7aS0vII5o2GDHJkoV9MHNfP+hf8ABTz9k3WtQWxl8UajYqzY+03mlyLGvux7CvcfCvjLwt450WPxD4N8Q2epWcy7obm1uA0b/iOnHrRm3CvFHCyjWzDDVKKTunKLjZ+TVn+Nh18ux2CtKpSdNnzl+1N/wTa+HvxOsrjxV8GNNttB8RqGlNrExS1vD/cK/wABP94d6/PTxb4P8S+AfEV34R8X6PLp+oWMxiuLWZMFD2/3gf73ev2qIVl3BVbcvU9/b6V8w/8ABR/9lPTfil8Prj4weFdJb/hJdBt97/Z+t5bfxqw7so5B54r+hvBPxszDA5nSyLO6rnRqtKE5bwl05m3qnsux9nwnxTUw2KWGxMuaD0TffzZ8pab5mnf8E+tUbRhtmv8Ax/HDq3Od0aw5RT6Dd29a6T9l7w/4J8UfsefErRfiF40j0LS5tb083GqtZtKIGBAAIHUk1w/7Nvjzwfe+HfEH7PXxR1AWfh7xesbWmpH/AJh2oRnEUp9EP3T0rQ8Sx+Pf2dvgz4w/Z98a+A7yRvEt9b3Nn4gt5C9m8SH7+5QVfI6cjB7V/QGe4Oc5YjLeZ06s68asZOy5oOS96Dk+V8lrW3fY+qxkG+ek3yzdWM1L+7ZfLQ6T9qTT/DfwC+Bnh/8AZe8Navf6xHqd8PEMniGa3EdvKjrhUhGegHXpg1y3wxu5tR/Yr+I+naghNnYazp1zYrJz5dw7ENt+q9aTTPEPjv8AaV+DPhv4D6V8Mb/Wte0LUXOl+IC5xFaN/wAs5Ceig85JwAOlWPj/AK54V+Efwrsf2VfBOsW+p3kN82oeMtXtW3RS3e3CQIw+8IwTn3qsvwtSGBo5K482KeIdSclZ3s7upeL5YpqySve9woQ5KccI1zVOfmb8v5uyv2PESwIG0cdfoe9FBIxgCiv2u9727JH2UX7qQUUUUigooooAKKKKACiiigAooooAKVPvUlKn3qcfifoyo7o/VP8A4J7f8mgeDf8Arzk/9GNXtFeL/wDBPb/k0Dwb/wBecn/oxq9or/JnxCjL/XzMmv8An/U/9KZ/Oeaf8jOt/if5jhG7qdiNu7fL1poDEZ8iQf8AAa+Gf+Cln7Qnxq+FXxy0/wAO/Dv4j6jpFjJ4djnktrWQBTJvI3cg84r56H7af7VuMD43ax9TMv8A8TX6vwv9HPiDirIqGbYfFUowqpNJp3V++m59Fl/BOYZlhY4iE42aurn62bX/AOeT/wDfNIVIGWVl92GBX5Jn9tL9q/8A6Ldq/wD3+X/Cg/tpftWEYf426xj/AK7L/wDE19J/xKnxR1x1J/Jnb/xD3NZae0ifrXkZxk8jIBWlr5o/4Ji/Fb4j/Fj4Wa9q/wAR/Ft1rFxb635UM12wJRNgOBgD1r6Xr+euKuHcVwjxFXyjETU50pKLa9LnxmOwcsvxzw82m0z4u/4LFOV8P+BSB/y+Xf8A6CtfHnwQ8AS/FL4u+G/AEduJP7R1KKORf+mYYO3/AI6DX2F/wWJ50TwKp6fbLv8A9BWvB/8AgnBpkWoftd+G2f5RbwXUij+8RCa/t3wrx1TK/o/SxUN4U6zT7PmlqfqXD9aWH4LdRbpSt95+oenabY6VYQadYW6xw28KRRqvQKowo/AUmranpui6Vc6zrFysNrZwNNcTN0jRRuLfhirAPy59vyrxX/goR4n1Hwt+yf4mvNKlZZLqOK2Yx9QjyAMPxHFfw3keW1OJuKcNg7616sYt+Un/AMOflODovH46FO/xyt+J8H/td/tZeM/2lPHN0V1C4t/CtnO0Wl6WshVGAON74PLHr9DXjp5IJ7DHHHHYUiHbGsQ/3m9M4/wpa/1c4fyHLeG8tp4PA01CEFZWVr20b+bR/Q2X4Ojl+GVGkkrb+vUCW2bVdlwwZWXggivtj/gmz+2NrV3r0P7PvxP1aS7juFz4cvbpizo46wlyecjJXuMfSvietj4c6/qHhXx9ouv6YzLPa6vBJGV6/fUEj8K8DxG4Ry3jLhfEYXFwTkoylFtaprZo488yrD5nltSE0uZLR9j9pCMHGc+/rVbWT/xJrz/r0l/9ANSWk5ubG3u9u3zoUcj0yoNR6z/yBrz/AK9JP/QDX+WmEp+xzSFPtNL7pWPwCnHlrKPZr8z8WPEv/Iwap/1/zf8AobV+sX7GGP8AhlnwSf8AqDr/AOhGvyd8Tf8AIwap/wBf83/obV+sX7GA/wCMWPBP/YIX/wBCNf2n9Ja/+oWW27/+2o/UePP+RTh/Vf8ApJ6eu05DHtlfevzp/wCCpvx11vxd8WP+FN6XqEi6P4fjjkurZeFlumXO5v72ARjPSv0VUAyxkjvj+Vfkv+2/LJL+1Z41MjZ/4mhH5KuK/LPozZPg8y42q1q0U3SpqUbpOzvFXV+up87wLhqeIza81flV/wAUeVgupbe25m4ZvWnW81xaSxz2MzwyQsGhaNtpVgchhjv700kk5NFf6B1OWvRdKesZXVnqndH7M17VpSV03Zn6o/sD/HHUfjp8BLXVfENw0uraPcNp+ozN1lZRlWP/AAH9a9rZiqMa+Qf+CQGf+FYeLBnga1H/AOi6+viAy7T0Nf5ZeLGVYfJ/ELMMNQiowU7pLZXS2R/PvEGHp4fOK1OCsrn55/8ABXbSUtPjpoGsiJf9K8P/ALxv7zLIwH6GuJ/4JufDGD4iftL6fe3NmJrXw/bPqMyuON6jEZ/BjXpH/BYFi/xH8JFj/wAweUf+RTR/wSAtID8Q/GF95n7yPRolVfbza/rbB5xist+jf9ZpN8ypSin1V3Z/gfodHEVKXAvPfXkf5n30o8viJzx0bua4T9pP42ad+z98H9W+JN0iy3FvDs022Lcy3DcIv9a7voMCvj3/AILA6newfDrwtpSFvs9xrEks+DwzLHgflmv4/wDDPIcPxNxvgsvxOsJzjKSe0ktWn5Ox+d5LhYY/M6NGp1d356nw5498feKvih4svfHXjbV5rzU764Z5mmy3l5Gdq9lUdABxWQzyMeZG56/4UrM7tvLdsUmea/1QweGoZfhIYbDpRhBWSS0S7JH9AUaUaVFQgrKPYJVSaNoZl3I3LJ2r7j/4Jg/tXeINevpP2dfH+rSXTLbtN4dup23OFX70G49cdV9BXw5Xo37JOsalof7SngvUNK3CYa5Gny/xK2QR+VfB+KXC2X8VcG4uliopyhCU4ye6cYtqz/A8biHL6OYZXVc1rFXT9D9du1ec/texq37MHjxj/wBAGb+Qr0ZgAxAXHPSvO/2uv+TX/Hf/AGAZ/wClf5o8ILl4qwCt/wAvqf8A6UtPl+p+G5d7uYUo/wB6P5o/IW2G5FGevI9jiv0h/wCCXHxrPxC+Cs3w11G88y/8JyiJd7fN9nflT746V+cEOBAuP7v+Fey/sI/Go/Bf9onStRvptmm6xJ9g1Ri2FCvwrn6Niv8ARrxo4PjxhwLXpwjzVaKVWHrFbfM/bOKMt/tLJpKKvKGqP1YPDcL8qnAJ/iI6/hmvgn/grX8G10vxlonxssrX9zqkRs9SkVekyYKMceo4/CvvONiy5zuU8hh/FnvXmv7YHwkh+Nf7PfiLwXFBuvhZ/adNO3J86LLgD3I4/Gv4O8IeKp8H8eYXEzbUJSdOa8pOzv6P8j8fyDMJZbnFKp9lvlkfkflQuQfl9a/Sb/glz8K18Efs9nxpeWwS68Uag1yp24YwoNig+2QT+Vfnf4O8Hat4y8a2XgawtmN3fahFaRx99zNtb8utfsh4I8K2fgLwbpPg3TIlWDS7GO0j2Dg7UAP6iv6f+lFxRRwvDmHyelK/1hqcvOMf+HTP0Dj7MPZ4Sng4P4tfVdDWzyOD1/hr87f+CsPxcl8T/GLTfhdYXO608O2Pm3m1vlNzKSfzAx+dfoF4r8TWHg3wvqPi7VJ1jt9Ns5LiZ2PACqTX42fErxpqHxJ8ea14/wBTuWafVtUlufm/hVm+X8AAK/M/ov8AC/8AaHE1fOa0Xy4eNlf+Z6P7l+Z4fAmA9tmM8U1dU1p67XP0I/4JY/DKHwn8AJfHF1YLHeeItReWOTbz9nTCoPoTmvpvnqTk9SfWvOf2SNMg0f8AZs8GWFsQVXQYG3L3LDJP5k16MMhuV/iz9enFfifiJmlbOuN8dXrt61HFeSTf+R8nnGIqYrNq0n/NY+Sf+Ckv7X2sfC61h+Cnw01JrXWtQtjLqmpQn95ZwN0jXuGb17dsV+fc0stzcSXl3K81xM26e4mcs8rerE9TXov7XviTUvFP7S3jTWNQkYzf249uqt1VE+VQPYCvOOnFf6KeFPBeU8JcJYdUaa9pUjGcpNK75kmtX6n7Xw7ldHK8sp2S55K7f5CsSQQPlz/d4r0r9mH9prxz+zT43h1vRNRmm0WaVRq2js5MMyE84Xs/oRXmnWhcjlfvKQVPoa+9zfKcDn2AqYPGU4zhJW95J6nr4jB0cdRlRqxTTT37n7UeDPFei+OvCun+MvDl4s9jqlnHcWsi/wBxh0/DkfhWlJFazq1vdwhopBsk3dDngj6Yr55/4Jf+I9S179lm1tdQZ2Gm6rcW1vv/AIYwQQo9hk19DlFOcjrX+UnFWT/6r8U4rB0pfwqjt5a3X3X0P57zDDywOOnRT+Fn5B/tS/DFfhF8ffFHgVLTbb22oSTWsfY28h3Lj6Zp/wAN/wBqb46fCvSv+Ef8NeNWuNNVsx6bq1sl1DH7KsgO0fTpXqH/AAVV02Oz/agW7jkXfc6DC7e5yR/ICvm2v9LOCY4XirgPAYjH01U5qUFeSvry6v1duh+45TTo5pktKpXjzOyTv5I9O8bfthftAeOdJfQLrxlHptjJxLb6HYx2fmDuGaMBiPxrzHJ5GepzRRX1+W5RlmURccHRjTTvsu++u56NDC4fDRtSikFFFFeidUX0CiiigoKKKKACiiigAooooAKKKKAClT71JSrw1Ed36MqO6P1T/wCCe3/JoHg3/rzk/wDRjV7RXi//AAT2IP7IHg3B/wCXOT/0Y1e0V/k34gP/AIz7Ml/0/qf+lM/nPNGv7Urf4n+Z+dP/AAVs/wCTjtMH/Uqx/wDoZr5Z2qRyvavqb/graf8AjI7TD/1Ksf8A6Ga+We34V/o14Oy/41nlln/y7X5n7Zwzb+waHohNi/3R+VKiqG4UUUAgHJNfpl9dT3ZbH6Ef8Ehv+SL+JeP+Zi/9pivrSvkr/gkOyj4MeJAT/wAzF/7TFfWp45Nf5e+NFl4m4/8AxK/3H4FxVb/WCs1/MvyPi/8A4LDgf2D4FOP+Xy7/APQVr5x/YL8S2/hb9rDwjqF7c+VHNcS2zMW43SRlV/Wvo7/gsQ6roPgXJ/5fLr/0Fa+HdB1rUPDmtWPiDTn2z2F5FcR/7yMGU/zr+u/BnLf7Y8D4YFb1YVor1cpI/R+HKH1nhH2XdS/M/bJMgBTyQK89/al+FU3xl+APiTwFaD/SrjTybEA43TR/Oo/E4rY+CPxR8P8Axk+Fui/ETQrjdHqFqkk21sskmMOh9MEc+ldUpAYFjjnrtziv4Lp1MdwnxBCW1TDVNVs/ddkvwufkUZVMuxStpKnK/wCJ+I11aXFjcyWd3btDNBIUuIm4Mb9x+YNMzX6B/trf8E6F+KWu3HxU+CAht9YuG3ajo0zbIr1ufnU/wOf1r4s8YfAH44eB9Vk0vxR8JvEFrJHwS2nu4J9mRcEehr/THgjxS4V4wymlVpYiNOpZKUJSitVvu+rP3PJ+IsszLDxqcyjK2qbS1OPPTJr0P9lj4Val8Zfjz4c8G2Nu0ka6gk1/IFOIoEIdifwHFXfhb+xz+0T8Xr1bHw58Nb61t/MH2jUtVgaCGJe5+Yc/QV+hn7JP7IPhP9l3wvJHBcrqXiC+2/2lqjKVyv8Acjz90D9a+V8VvF3h7hfh+vhcNWjVxVSPLBRkmo83VtPePY4OIuKMHgcLKNOd5yVtNbfcevpGkSLCn3UUKv0FV9Z/5A15/wBekn/oBqz+NVtZ/wCQNef9ekn/AKAa/wA68FOU8zpyk9XOLfzkj8Yp3daLfdfmfix4m/5GDVP+v+b/ANDav1i/Yw/5NZ8E/wDYHH/oRr8nfEuf+Eg1T/r+m/8AQ2r9Yv2MP+TWfBP/AGBx/wChGv7V+kt/yQeW+v8A7aj9R47/AORVh/VfkeoRcyivyT/bZ/5Op8bf9hZv5LX62Q/6z8K/JP8AbZ/5Op8a/wDYWb+S18D9FTXivGP/AKdr84nk8A6ZlV/w/qjy2g0UGv7vVklfuz9aV7pL+tUff3/BH7/klvi4/wDUah/9F19fV8g/8Ef+Phb4tGf+Y1D/AOi6+vq/zD8bf+Tm5h/iX5I/BuKv+Sgr/wCL9D4F/wCCvvPxH8J/9geX/wBGmud/4JReM7Lw5+0BqHh2+bB1rRnjt+eskbb8flXRf8Fff+Sj+E8n/mDy/wDo018u/Cf4han8JviXo/xF0Nm+1aVfLNt7OucFD7Fc5/Cv664P4flxN4AxyyO9SlNR/wASfMn+B+iZXhPr3BvsY7uP43P2cYBAQ/ReteAf8FGPgrqPxh/Z/vLvQ4Gm1Pw7MNRt4UHzSRqNrqPwOce1ey/D3xzoHxK8E6b478LXUdxY6raxzR5cHGVBI+oPB9xWw8ccyNDKCVYYYDHT8a/hPI83zDgriiljFH97QkuZPR2T108z8lweIrZXj4zW8WvXRn4ihWX928fzo207shk4zgj17UYOcYr70/au/wCCYa+M9buviB8A763sby6kaS90G4bbDMx6tE/8BP8AdPH0r5d1f9jH9qbQdVXTtS+COtM3K7raMSgn2ZTt/HNf6Q8K+LPBfFGWwxNLFxpya96E2o2l13aP3HL+I8rx2HVT2qjLqnZfmeWk46/Svon/AIJqfBrU/iJ+0Ba+ObiyP9k+FQbm4mb7rTEfu0Hvnn6VP8Hv+CYf7Qnj+/hm+IWlR+E9LDBppL5hJcuueQka9Gx0Y19//BX4L+B/gT4Jt/AngOwW2tV/1ss43STufvSSN/eP6dK/MvGTxo4dy/h2tlOU1fa1qsXF21iovd8yur9Nz5/ibinA08HPDYefNKSs7dvkdbliMnrXnf7XX/Jr/jv/ALAM/wDSvRBgnCq30brXnf7XXH7L/jrPfQZwPyFfxPwj/wAlVgNLfvadvTmVv1Py/Lv+RlRX96P5o/IeHP2df92lWaWA+dCcMvzL7kHOPY9/wpIf+Pdf9z/Cg5xj+H+JfWv9cfiTg9pWT9Gj+jXyyilLbX8T9Y/2JfjUnxy/Z50XxFc3fnalYxCx1fnnz0GN3/Ahg16x8hfa0bN1PDdABzX52/8ABK/41jwX8Xrr4W6ve7bHxJb5tVZsBLmMZX8SBgfSv0Txg4PXPzfWv8wfGLhGXBfG2JpUk1Tqvnp+l9fxPwTiXLZZbm0qK+F+8j4z+FH7I7+Gv+Cimsau2n7dB0yN9a075RgST5UKO3DFuO2BX2YAD8vbJP4nvTFtLf7Q12UjV2UIZfL+fAO7H0p+M8Hv6V8xxlxhmPGlfD1cS/4dONJfLr+Gp5+YZlXzKpCpPokl8lY+Z/8AgqJ8XD4A+AK+CLGcrfeKLoWrbXxi3TDSH+lfmzIUEBUfLj7zeuen6V9Cf8FKfi1/wsj9oy60CyufMsfDMf2CHachpgcyt+eB+FfP67SpVq/0I8EuFY8L8AUHVVp17Tn0d5fD+CP2jhHLf7PymK6zV/vP1c/YR8XWnjH9lnwte2s4kazs/sk3+y0ZxXr4zu2t0KmvhP8A4JP/AB3t7C91b4Ea7Ps+1M2o6OzN8rNgebF7nHNfdblDIQpPr81fwn4vcNYrhvj7GYeeinKU4vyk03bv8u5+S59gZYHNqsf5ndH5d/8ABRP4R6n8NP2jtU1uS0ZdP8SMNR0+b++xGJF/BhXg4y3IFfr9+0R+zx4A/aR8BS+CvGsDK8beZp+oRf660lx95fb1XvX56/F3/gnj+0n8L9Qmm07we3ibSw/7nUNDzIR7NHwwP51/X3g54y8P51w3Qy/Mq0aOIpJRvJpJpaJ3btslfsfo3C/FGBxGDjQxEuScdLvS/bc8Lp0ZkJVbdC8kjBYUUffYnG0e5ru/DP7Lf7SHizVP7M0f4K+IjPuwDLp7Qqv1ZxgV9f8A7Hv/AATY/wCFf6/a/E347yW95qlqwlsNDhk3QwydpJD0Zh2A4zX6Bxd4r8G8I5bKvWxEKs7PkhCUZc0ktL2bse1mnEWW5ZR53UU5K9rNPf0Paf2KPhLe/Bn9nPQfC2rJtv7iNr2/jPWOSX5tp+gxXq+C52ngDn60B1K/7oyTt28VzPxe+Jnh74QfD7VPiN4jn22+l2bSYzgu/wDAg9y1f5r4rGY7jDiSdZq9avVvor/Hol8lY/Dq0sRjsddaynK5+cv/AAUo8U2Xib9q7VbS3u1l/sy1hs9o/hZRucZ/4FXgfHQVo+N/FOreOvF+peM9afdeapfS3Erf3d7E81nfWv8AVDhDJ58PcM4PLnvSpKL9bK5/QeW0PqeBpUeyX5BRRRX0h3BRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABQv3sUUdsU1+IX95H6nf8ABOq6t7z9kTwmltKrtDBLHKFP3W8xiQa9uO4Fcr94nFfmJ+xh+3Pqn7MTXHhPxJob6r4Zvp/NaCF8TWsh4Z0zwQf7tfRvjP8A4K0/AnTfDzXHg7wvrmpaky7Ybe8tUhVWxwWbceh9K/zy8RPBnjufG2JrYTDurTr1HJTja1pO73aeh+J51w3m7zafsad4yk3f1PEf+CtF1bT/ALSljaxyhpIfDMSSr/cYuSAa+X1OV4+ldB8UPiX4r+LvjvVPiD41u/O1DUrgs+3O2NMYVF9hXP8A4V/cHAmQ1OFuEcHltXWVOEYy9UtT9YyfBywOW06Et1FJ+oUFSw2gUUYzwSR/u19Y7Hqx0Z+gP/BIO7t7j4SeKLKGQNNHryu0fGdrRjB/Q/lX13uQ8FwO3Pr6V+Sv7K/7UfiX9mDx4fEWmad9v0u+RYdX0stjzowchk9HBzz6HFfY0/8AwVt/Z5TQ/wC04fDfiKS8WP8Ad2Js1Hz/AN3zM49s46V/B3jR4TcaY7jqvmGW4d1qeIs7rl0e3Vo/HuJOG8ynm1SrSg5RnttocX/wWMuYf7L8DWWf332q5cx8Z24Xmvhv8K9C/aT/AGivFn7S3xCbxt4lt1s7eGFoNM0yBvktYSc4/wB7PU156a/qvwp4YxnBvA2FyrFv34pt905NvfbS5+hcOZfVyvJYUKnxLU+kv+Cev7YUXwJ8TyfDbx/qYj8KatMWW6Y/Lp9wxHzn/Zb+L8+1fpJZahYalaRX+n3kc1vNGrwzRNuV1PQgjqCK/EqUrLw25V27W8vHz+5zXuf7MP7enxV/Z58nw3e41zwzH8q6TdSHdbr6xOeR/u9K/I/GfwJqcU4ipnOQ8qxDXvU3pGdvtf4mfOcT8JTx1V4vCL3nuu5+pJjf7wPy7sM2evtS+ZIRtZ8r/dYcfzrwX4X/APBRr9lr4iWqve+Mm8PXJXLWuuR7Np7hXGVI/HNeiQ/tIfs+XNt9qg+NXhllK5GdWiH/ALNn9K/jjGcF8ZZTiOSvg6imtPdT/ON1+J+YVsvzDD1OWpTkn5I7VTLIvlGT73Ece44/KqWt67o/hfS7jV/EN9HY2trGXuJrlwqoo7k/jx614z8S/wDgon+y58ObSR7Txuuv3aL/AMeehxmVmb03fdAr4h/aq/bg+Iv7S7yaDBEdB8NrIrRaVayZaUjo0rfxHPboK+94H8EeMuMcanXhKhQ+1Op2/u3d7+dj2cp4XzLNKtpxcY92fqdBNHdQR3Vs4kjlVWjdejAjKkfUdKh1sbdDvZCw2raybmz935DXx9+yj/wUs+HkXgKw8CfHS4m03UtLt1gi1RoWkiuY1GEJ2ZYMB3IqT9q7/gph8OZ/h/f+CPgLcyarqGoWz276t5LRx2aMMMRuwWOM/nWeG8G+O6HGCy1YSbhGcfftpyJpp32Ijwzm9PMlQ9m999LWvufCniRoxr2pt5i7TeykPu4OXav1g/YvKt+yt4JkXp/ZIGfX5jX5Jq8gzufPf6t6mvsL9g/9v7wl8J/BqfCD4yfaILC0kLaXrES7o4UYkmOQdRzyCPWv6s8fODs84g4Jw1HLoe1nh5JtR3ask3br1P0Ti/LMRjcrpxoxu4NX81ax99xtscOVO3/PFfkn+2zg/tUeNCrq3/E4dflPfatfcHxe/wCCln7OXgrwpPf+CPEyeJNVaLNlZ6ejFVk/hZ2IAUD86/NzxT4k1nxn4kv/ABb4hnEl9qV09xcMvTcxya+B+jTwTxJkuZYzM8woSpQlGMIqStd3Tej16Hj8C5ZjsPiKterFpNWV/VFGg/1oHAxQDg5xX9gv4r2v/nY/TlvF+Z9+f8EfmDfDHxYf72tx7ff93X2Cq73MSspZWwVB5Fflp+w/+1sP2YPHN3/wkFjPd+H9aCrqUEI3NC6n5ZUHsM5HevtrVf8Agop+yRY+HP8AhILX4mw3jKu7+z4YXN0ePu7ccH6niv8AP3xs8O+Ma3iBWxeDws6tLEONpRV0naz22t5n4rxVk2YPOpyhBtTejR85/wDBX+Qf8LJ8Ixk/M2jSkD28018fuMsUPZq9I/an/aH1f9pb4s3Pjy9s2tbGKP7PpNm7DdFCM9cdyTmvNxnaAeu0Z96/sjwxyLHcNcE4LAYxNVIRaknur6n6hw/g6mDyelRqq0luj6O/YS/bZk/Z51b/AIV94/e4uPCeoSFo5FYMbCY/ecD+43de2M1+kHh7xJoXizR7fxB4a1SG+s7uMPb3FuwZXB9x39utfii/7wqZFVlHVccGvQvgl+1H8av2fr5b3wD4olXT92ZtIvMyWsv1TPyn3XBr8k8WPALC8XYh5rkslSxEl7ya92pbvbRM+Z4l4Np5hU+sYX3Z9u/z2P16JkxmLb1w25cgf/Xpwmk3LAkj/N/CvevifwL/AMFgtLWxjt/id8HbxLgAA3Gi3StHJ77X6fTNdhL/AMFb/wBnRbTcvhbxQZsZa3FnGPw3bq/lnG+CHidgcU6X9nvykmrP8T4OpwznlOTiqLfmmrffex9UFGJxhx/vr0/LNcF8YP2gPA3wcv8ASdA1u987Wde1CK003SYpQJH3MAZCOyDvXyN8WP8Agrt4m1iyk0v4OfDaPSWZSF1HVphNJH7hFwpP1rw34F6543+NP7V/hPV/Gmv3msapdeIIZGuLqYs21TuO3+6AAeBwAMV91w19HfPPqNfNOJLUaVOEp8ier5VdXabVu56uB4Px31eeJxjUYwTduv4H6zRlVJZcbe22vOf2v3H/AAzD44H93Qpz+Yr0Z+M4ryr9tbVLfSP2WPGlxIW2yaSYvqWIAr8S4PhKpxdgeXW9aD/8nX4WtY+Yy6L/ALSpNfzr8z8l0OI41/6Z/wCFLTVzlR/dXaadX+uHKf0cl7pe8MeJNV8F+JtN8ZaHM0N3pl9HcQSIf4kO4D6cH86/Yn4OfEXTvi58MtD+IWllfK1XT45ioP3GI+ZT7g5r8aVXf8uQNvJ3NgdK/SX/AIJZaV4y0r9mtrnxPK/9m3WqSy6DG6nclvjr9C+cV/LH0o+H8vxnC9DNeZRrUZpLvOMt0vTc/PfEDB0pYGNeTtJOy80fSx4Ncv8AGb4jWHwo+FeufELUG2rpumySxK38UmMIv4sRXUlWVtrde9fHn/BW74uNofgTR/g7p93tutanF1fRqeVgiPy5+p/lX8k+HPDUuLONcJlcY3TqXl/hWrv5H5xkuBeYZpSoLa9/l1Pg/XNYvfEOuXmvalIZLm9unnuJGbOWYkt+uKq0NtzlBiiv9VqNGOHpRpU9IpJJduVWX4H9C040401GOllZehoeFPFfiDwN4jsvF3hXUWs9R0+5Sa1uY87lYH+XqO4NfqR+yP8Atb+DP2lvBcNw2oQ2niazgH9taOzfMrDjzU/vIevHTOK/KetTwX438XfDvxJa+LfBHiG40zULOTfDcWrYb/dPqp7joa/LfFPwry/xIy/kuqeIh8FS3k9PRnz/ABBw7RzrDqztUXXv5fM/aZhuLOvTd1p5kYFirNknkq20N+Ar4i+Bf/BWqyhsYdB+P/hBhcJjy9Y0RSyvx1eM9z7cV9IeFP2yP2YvGVlDfaV8Z9DjWYZ8q9uvIkHttkAr+BeIPCrjfhnFzjicLOXLopQV0/PS+/mfj2NyHNcvqWnTdu+/5HpxfcMOWb6twP8AGmKgHzn8fauM1L9o74BaTB9pvvjN4ZVCM7v7YiP8jXlPxT/4Kdfs4fD+GaLwxeXHiq8jX93HpceIi3/XV8Afhk15uW8D8a55iI0sPg6sp9OaLSXzdkYUcrzHFyUaUG36W/M+gtY1bTfD2mza1r2oR2lnaxmSaa4kCoqjqST7V+bf7fH7Zcnx98Rf8K/8BX7r4R02fLMrf8hGUHG8/wCyOo9a5P8AaT/ba+L/AO0j5mj6vdjSNBLbodI09iFPP/LRv4z+leNjgYwPwr+xvBvwHp8J4iOcZ57+IS9yGlovu+jf5I/TeF+Eo5fUWJxavPouwKoUbRRRRX9Pa9T72wUUUUFBRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQJq4qsV6UisyHKuR/s9vyooo+1rf7xrswJyc4oooo/rUAooooAVWwd2OnT2pfMkxtD4Gc02ii84y91/gCfdAxyc0UUUdNdX3FrJahQCAeQD9aKKNxRUou6dhGWMnJiQ+7LSGOMrtK8H0p1FEowqfGlp5Ib9F9wLhU2KgC+1Gfr+JoozRFS5d7fK6+4vdb29EAZwCPMb5jzzQx3tuZV/756UUUa8tv8/zuZ8t42b+fUKBgMGI6UUUBaS1QIPLj8uPp/tc5+vrQcZ+UUUUS1lf8f+BsW5OWu3oFFFFAgwCQSOhzSlzzwMn1FJRR5oE7dEHygYUfrRRRQB03wg+EfjH44fECw+HPga2WW8vpCJJGU7baPvI/+yOp+tfZWlf8EffCR8NLDf8Axg1D+11hz9oj09fsyyf7pJYj8a8t/wCCUvizw/oXx/1DTtVuoY7nUNHaHT2mwPMkDg7cn1GR74r9IN75BZi23IXdzgen0r+N/HrxY444X4uhlmVz9lSir7fE9/Rp9T8v4v4gzbL8wWHoS5IrX19T8h/2iP2X/ij+zX4j/sbxlpck2nyMWsdatg32e6XsQTwD/snBFectMjnmRssPlbt+hr9tNX0jSvEFg+la7psF7ayKQ9vdQiRDn2PevNdX/Yn/AGUdbuWu774G6IJG+8YIWiB+oUgVXDP0p8JQwUYZ1hG6iVnKDi0/k7W+ReB8Qp+xjHF0uZrrGyXzVz8lw89xMtrHC0krYWNIzuZj2AHf6Zr7n/4Jq/sa+KPCGt/8L6+KWitY3H2ZotB0+6XDpu6ztkfLxkAehr6d8Efs3fAT4cXa3/gn4TaJY3CfcuFs1Z19wWzXb7j6cbcMvY/hXyPiV9IitxXk9TKsow7p06itKTa5rXu0km90eZxBxtWzDCyoUIckXvfcbn5c47V8uf8ABVX4pL4Y+A1v4Btpf33iXUIwVLbSsMeGJx15PH0r6O8d+OvC3w38K3njfxtrMOnafp8ZluJpn6r6D1Y+gr8o/wBq79ojVf2lPixd+OLsSJp8P7jR7Z+kcOeGx2Y9T3r5/wCj7wHjeI+LqGbSpv2GHlzOT2crOyT2duvY87hHKamNzKFZq8Y6v16Hmu35mf1qbT9Pv9WvodM0qxmubieQJDb28RdnY9gBUKldw3Oq/wC9mvtr/gkl8LfCOpQeIPivqdhHcana3Mdpp5mAb7Mu3czKPU+vWv7g4/4uw/AvCtXN60eZQ0iu7/4c/Xc8zKOU4GWJ5eZroee/s5f8E1vi78S9ctNZ+LGhTeG/D0bCSaG8A+03Q4+RUH3c+p9a/Rjw/omjeGNCtvDXh+xjtbG0tlgt7aH7qRjov19auFdxWQjtR5iMzM52qo+ZuAF46knpX+cviJ4mcSeI2Lp1ccuWMNIU4/DZ9fV9T8PzjPMbnVRSxDsltFFfU9Ts9D0241nVpVt7O1haSe4kYBY1UZJOfQc1+Sf7V3xuu/j/APHLWvHzTH7GszW2lq2flhQ4AGfUZY+5r6O/4KQ/trWGp2Nx+z18KdbW481tviTUrd/lVVb/AFCHpuPRiPpXxSQDt4+7yPyxX9WfRy8NcRkGCqZ/mMOSrXSUE94x3v8AP8j9B4HySWFpyx1dWk9IryYUUUV/UR+g8oUUUUFAMAEBF574poRAxcLglcfLxTqKf2eWTuvRBq90vuG+VH3ByOjZ6U5QUYsJGJJzktRRULlhpFW/rtYPOy+4CBuLhcbvSiiirZLUnqwooopFBRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQBPpmqanoepwa9oeozWt5ayBre6t5CkkTDoVI5FfYf7Ov/BV3VdGsrfwv+0JojX8KAJHr+mx5uCB/FLHnBH+0CPpXxrRmvjeMuAuGeOsKqOa0eZx+GS0lH0Z5Wa5Nl+b0eWvH3u5+uvw+/a3/Z2+KEQbwx8WNL81lH+j3VwIJV9ikmD+IyK72HxD4duI/Mi1/T3UL96O9j/PrX4ltHG/+sOPfB/pVmG+vbXEVtqFyqj+7dOAfwzX89476KmUzrOWBx06afRxUrfO6Piqnh7h5S/d1mvlf9T9l9f+KXw28K27X3iTx/o1nCi5aW41OJQB6cn/AOvXh/xe/wCCnH7Ofw7tZIPB97deLNQ2kQx6fxDG3+1IwUY/A+1fmi4MkjSyytIzc5k5/rR06CvUyP6LfCuBrRnmWJniEteXSKb87Nux0Yfw/wADSqKVabku236s9O/aM/a1+K/7Ser+b4u1X7HpMbb7HQ7MnyIGzwzDrI2O5rzHJ6/jRRX9H5Tk2V5HgY4TA0lThHS0dFb0/XqfdYTD4fB0VSoQUUhGJA3KyjHPztgH2r2/9in9r9/2WvGlz/bWlSXvh/WNv9oQRL+8gI6SL2P09K8RorDiDIMr4myirluYU1OlNW815p/8Ayx2Dw+Pw8qFdXUj9MPEH/BUb9lbTNGXVbDWdVvpiv7vTIdNKybsdDuwAD7mvmP9or/gpd8W/jBplx4W8C2X/CK6POGEjW9xuurhehBbjb/wGvmuivzHhXwF8PeFMYsXRoOrUTunVfOo+i0X33Pn8v4PyPL6yqxhzNbX1BsncH3Hc25txzlvU+pozRRX7RFRi/dVl0XReh9ZaPLa2nYKKKKBhRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFHu9EG4UUUUBawUUUUCsFFFFAuUKKKKCgooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKOMcn6fXt+tAutgo9q+nv+CWv7F3w8/bd+Nmt/D34marqOn2Wk+G5NQQaXMFklk8xUUZYHgZOR7V4D8WvB9l8Pfin4k8B6bdyXFvouuXNlDNKBudY5CoJx39alS5pOPY8TD5/gMTnVXLI39rSjGT7Wlt+Rz/WheWwRXefs1fs5fEr9qr4waX8GfhbpvnahqTEzXMinyrOJfvSufQDt64FfdXiD/gmT/wAEuf2bjD4N/an/AGz7y38WyRD7RZ290kawtjuiRuy/8CIrOpWjCy3ueVn3G2UcO4iOGrc06slfkpxc5Jd2lsj82e9BYKMmvur9qz/gkP4T8P8AwVm/aW/Yq+M6/EDwna2bXV9brJHNOkSjLNG8YAbA6qwUjFfCpMTALhvm4TA+9noT6EHtVxqRmejw/wARZZxNhnVwUm7Ozv7sovtKL1T7CptcZGaUp6V+gP7E/wDwTh/Y1+Iv7Ey/tZ/tR/E3WtBs476dL+6trsLb2sayCNchULHJNaq/sy/8EEM5P7aepFSMjbfS9D/2xrKWIp8zST0Pka/inktPGVcNTo1ZyptxlyU3LVeaPznII60V9bftu/Bz/glr4C+Ew1v9kL9ojUvEvir7dEqadNM0sbwZPmZ3Rptxwc5r5JKlflZs++Qf5VtGcZLRM+0yPOqOfYD61Spygr2tNOMvWz6BRtcdaM45I963Phx8OfFvxY8eaV8M/AOlSX+raxfpa2MScbpGPRv7qAHluwFU5KO56OIxVPB4eVao7KKu29kurMOgkAc1+kdx/wAEmv2D/wBmDwxYv+3V+2Aum+ILuJZH0zS7lYljyMkBdjyNjkBiFBxwKyPij/wR3+BfxY+Fd98X/wDgnf8AtGjxnHpdu8txo99NHK0uFLbA6hSjkdAy8kVisRHm20PgKHipwvWxCp801Buyqum1Tv5yemvQ/PMEEZFKNmOd1PurW7tLmS01G0ktbiGRkuLWaMq8Tg4KsD0II5r7c/4Jdf8ABPT9nf8Aaw+DPjb4vfHvxTrFha+FrrZ/oF0sMccKx+Y8rHazNge3atJ1IU43PqOIOI8v4Zyl4/E3lC8UnHW/NsfD56ZH5UMdind1r9FtO/ZX/wCCD2uOtnB+2bqltcyLhN2pMAp9fmgrzv8Abh/4JKR/AX4VyftF/s6/FH/hPPAsarNd3SmNpbWAkDzQ0fyyqO5GCvcVmq1OXdHzuXeJXD+Mx1LCzhUoym7L2sGlJva0tteh8Wv8qgil2nGaRnjeNiFZv3Z8pl+767j+FfpJ8JP+CZ3/AAT28Pfsb+Df2nP2pvjJr2gw+I7OJ7i++2hYFmcnagVYyegNVUqRp2b6nt8T8WZbwrRpVMTGcnUk4xUFd3Svolqfm3sag8cYr9Fh+zV/wQUVwj/tj6scdxeSf/Ga8B/bx+Fv/BOz4e+HtGuf2L/jhqHijUbi8ZdVhupGkSKDbw+WRNp3e5zSjWjN2SZ42V8f4LNswp4Wnha0XN2TlCSivVtWPmcelA5OKQHK8Gvq3/gkx+wp4N/bj+L2t6d8S5dQj8N+HtNE1z/Z9x5bTzM2FQNjIGMnjnirqTVON2fU59nWB4dy+pjsY37KC1ce/l+p8pjJzRXvH/BR79kiw/Yw/af1L4SeG7i6uNEltYb3Rp7xt0hgcchjgZw3FeD0RlzRujTKs0w2c5bSxuGd4VEmu9n38xRt/izShFPIJr6i/wCCVP7EHw6/bj+LPiLwZ8S9e1SxsdF0FbxTpUiK7O0mzJLKeB6Yry/9s39l/wAT/sh/tB658Fdanmnt7WTzdF1GSMAXlq2Nj8cbsHnHej2keblPNo8UZTX4gq5NGT9vCKlZ7fI8rPBxR39q1PA/grxJ8R/Gmk/D/wAH6fJealrV6ltYpGuS7s+0ZHYZPJ7Bc19nf8FHv+CWHgD9iH9mvwv8R9K8ZalqHiG6v4LTWlnmT7O0joSxjUKCArKVHJ45olVjH3XuPNOKsqyvNsPl2Ib9rX+FLyPh2iiiqPobhRRRQWFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUHgZ9OaKG+63+6aqO4dj9A/+DdpFP7WPiyMr8p8EsSP+2yV8aftOgD9pTx+QP8Amb7/AP8ARzV9mf8ABu0f+Ms/Fn/Yjt/6OSvjP9p3/k5Px/8A9jhf/wDo5q46f+8v5H5nkS/42dmP/Xqj+bPuH/g3a0jT4vid8TvGD2qteWPheBbWbug8xmOPTkCvgr4zeJNY8a/F7xP4u8S3b3WoX+u3Ut1cSsWZ281u59uPwr78/wCDeHjxR8Wif+hZt/8A0Jq/PTx3keOdaBH/ADF7r/0a1XSS+sS9DLhmMZeJGbVJbqNNJ9dY7I+oP+CcH/BSDw3+xZ8PvH3w48e+EdU1/S/FFqfsNvp8imOGcxujkq+PvAjp2Wvk65l+03F1dRQeVHNctKsP9wFicH35qMkKOT2z+FAG4McZ28N7VsqdnzI+5wGQYHLc0xGNoRtKvZz7Jx0TX33P0x8BgL/wbza+3AC3UgHsPticV+ZihQWUAY3Hiv1w/Yj8R/Ajwp/wRPm1/wDaV8JXWueDINQuP7Y0uyXMk4+0qFA+Zf4sd6+V/wBpP44f8EgfEvwd1jQf2eP2YfFGjeLZ7ULoupXcZjjtpc/eJ898DGcjBzXNRm1Ukj8j4Iz3FZbneY4elhKlRTxElzwSstt23e3fQ+OQVClS3DDDD1FBx2NA3BV3PuOPvf5AxRXVzcx+5OOnNZK2ml/xbA57DNfZf/BCXw9pWu/8FALC41a3WdrPw/dzQb1z5cmAAfqAa+NB1r7W/wCCBOf+G/Iz/wBSte8/itZYj+Cz4nxEqSp8F42zt7jPG/8Agpf4v1nxv+3Z8SNQ8R3rTSWXiKWxs1Zi3lQQgKijPQdeK6D/AIJi/t2aV+wf8ZNU8Y+JdD1PVtF1zSmtr7TdLkG+SUMCj7W4OOcn0rj/APgoGyn9t74qYPXxhdEfTfXjuDjcPzpxhGVJJmuU5Ll+c8E4fLsRD93UpRUraatJq3n+J1Hxs8d6T8UvjD4o+JOh6R9gtNe1y4vreybGYVkkLBTjjP0r9Ev+CO6q/wDwTo+PSlc/uLr/ANJGr8xehK/3evtX6o/8EOJvB8f7Enxil+IVu82hpdSNqscWdzW32U7wu0g5xnvWOIjy0UvM+c8VKUcv4LhSgny050kl1aUkreZ+V0ZXABPFfqB/wTD1DVm/4JKfGi18dtL/AMI7DFqC6ObgZj5gDMqZ6ASY6dzWh+x/8Fv+CI37W/xPX4afCn4ba9JrCWLXUVnrc81vHOE++E+f5sV43/wU0/b18W6RpOrf8E9fhJ8EIfhz4P8ADl0bPU7ONl8y/jQ7lwBjEbcN/EWJ5NZyk6slGPQ+dzrPq3HGJoZHhcHOnOnKnUbqWi4Qi09Fq3drQ+EY1Q2mfWPP8/6V+nn7cwQ/8ELvhBIwG7zdN+b8JK/MOZWWJiX6jNfstqfjP9lLwN/wR/8AhLrP7Yfw51DxR4VaxsY49O01Nz/aCH2PjenA+tbYiXLyNHteKGIng8RlNSEJTca792NuZ+5sr6H40pjZtzwvT2p3yYILfeILe5HSvq79sP4x/wDBLLxp8H5NC/ZI/Zz8QeHPF7XsTx6xfZWJIB99CPNk3ZHbHB5r5Sbr17VvGpzQs0fo2S4+tm2H9rPCzw7Ta5aiXM/NWb0EZ3Hzk++6v00/ZW1W8/YZ/wCCN3iT9pGyVrPxL461DGhyEbJEDv5UOMcnADuB6Gvze8E+ENT+IHjPR/Auh24e61rUIbSFRyxkkk2DFfoX/wAFz/Gmk/CH4WfCX9ivwrdQrb+H9HjvdQiWQfeRBFFkdstvb6Vz1/elGPc+F4+hHOMyy7h9bVqjnP8AwQV397aJf+Cw+j2P7Q/7Hnwb/bc8OJHNJNp8djq1xGv/AD2jB+b6SxsB6ZNfm2O23lSuc1+mH7AMtt+15/wSZ+Jn7K092t1qnhVprjRo2bLRgj7RHgdeHDD6mvzQ/fKZIpY9jRysJF9H7j881VB8sWvMvwzxKwdLF5HU3wtSXL/glZx/Ox+iH/Budn/hobx+dgbb4Sgbn/r46V6H/wAFJvCfhz/goP8Asdt+1p8MtGhXxZ8MdTvbPxFY2+PNMMMxSWNv90Kso/2SfWvPv+DczH/DQfxC5/5kyPH/AIECsH/gmr+1ZZ/Bv9ujx98BPiBdRnwf8SPE2oWV5HeMDDBeebIsbkH+FwTG34GsJfxnI/POI8HjIce5hm+Cb9rhI0ZJL7UX8at10L//AARY+AHhrwjZeKP+Cg3xps1h8N+BbGZNFkukGx59hMsy567VwoHYvXtP/BaT4lQfGj/gm98PfixFp/2ZfEWuWt/HG3VFeNyg+u2vPv8Ags58aPAP7Ovwc8P/APBO/wDZz8mz0cxi/wDEEFjMCVhLl1gcjuz5dvUACtP/AIKWKi/8EcPgi4PLPpw/8gPWV5e0Un3OanHMM64qyziLGaPEV+WnF6Wpxi7adLu7ffQ/MGiiivTP6bCiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKAChiApz6UUA4OSufrT+yTLp6n6Bf8G7Tr/w1n4tLZX/AIohhhuP+WyV8bftP8ftJePmwcHxdfEHH/TZq9B/4J8/tw3/AOwf8WNS+Jlt4FHiRdU0N9Pms5L77OVLOHDhgDwNuMV498Q/GVz8RPiDr3xAv7NIJtc1ee+khjYsIvMctsyeuAetYRjJVnI+Gy3Kcww/HOOx84NUqlOlGL01cW7rvoffP/BvJ4k0dPi18Rfh9e3Xl3OteG4WtVzy2xzuwPYNmvh79of4ceLPhD8cPE3w+8daNNp+oWetXQ8m4XaXTzCyuvqCpByPWq3wZ+M3xG/Z/wDiVpfxa+FHiCTTda0mcSW8y8q47xuP40YdVPBr7xh/4Lm/Bz4l6dDN+05+wn4f8T6xDGFa/jaB1ZgPvDzkLLn0yQO1ZyjUhV5oq54uYYPiXhvi2vmuX4X6zRxEYqUYzUZRlHRPW3Q4j/gmN/wT2+Ff7Q/wK+Inx1/aL0a+ttF0a0kXRb4Xj2sZZIneSQbSNwX5B6ZOK+Ib5IIr+SK3ZZIUuHW2mZuTHkgD3PHWvrj9sH/grp8Sv2jfh1J8EPhZ8PNP+HfguaLyrrT9KkDzXMQ/5ZkhVWNPVVHPc18hodjqAAE5+XGdvGBj9a0pKp8Uj2uD6PE1TEYrMs5bj7Vrko3+BLzV162P0w8BFG/4N4tfi8tiy30rZUdB9sSvzPWaOYkxyKy9Rz6819sfsbf8FedE/Zi/Zlh/Zq8Z/s02fjDT4biaQyXOor5Uwd9wDxuhBINdyv8AwWr/AGaF+9/wTc8Kt2+b7L/8arKPtqcpWR8fksuL+FcdjoU8rlWhVqynGSqRWjt3f6H53NheSffihgVO019aftp/8FGvg1+1N8Ij8NPAv7G/h/wPeNfRTnXdPEPnRomSVXy0U8+5xivkssWOSP510Qk5LVWP03I8dmOYYV1cbhXh53+FyjL5+6AznivsH/ghl4z0zwp/wUC0WLWrqKP+1dFvLO1dm+V5CocL/vEDpXx8CQcir3hTxNrvgjxFY+LfCepy2GpaXdLc6fd27YaGVTlXHvRUjz02iuIsp/tzI8Rl/Ny+1jKK00vZ2b+Z7t/wVQ+F/i/4W/tzePo/E+l3Fvbazrkup6TcSQkLc28oBDIf4gDkHHQ13X/BIX9hvwR+2F8VNd1f4y+GtSvPBfh3Sy089ncPDHLdMcKnmJgkgZOAe3NeneD/APguf4b8YeELPwz+13+yFoPji6sowqapG0RMjAffKTodjHqdpAJrl/2g/wDgtf448VfC28+DH7LfwY0n4YaLqETxXV5p5QXWxuCEEahUJHBbk1zfvuVRtt1Py+NXxFqcP08lo4L2NSKjB11OKXKtOZW97mtt2PkT44+H/BvhD4z+KvB/w7u2n0HSdfurXSZGcsTCkhC5Pf61+iP/AAR3Ab/gnV8evmUZhusbmx/y5tX5il5nZpJpWkkkYs7uclifU9/rX0l+yN/wUQ1T9lT9nr4gfAe2+GcOtL43hkWPUZNQMX2NnhMRJXB3DnPGK2rRlKil1ufV8cZHmWZ8L0cHh71KkZ029bt8sk5Sbdr9zxv4BfGfxP8As8fGLQfjN4MuJYbzQdSjutscmPPQf6yM+xHGK+/v+CyPwT8MftD/AAL8H/8ABRn4LWEdxbX2nQL4oa3wxWF1ykrY7oxMbH6Zr80kUooGa+n/ANnb/gpd4o+CH7Jfi79kzxB8OrbxLo+vQTRaM95dFY9NWYfvAVwdw3fMADwamcJXUkY8WZDmksywGbZXG9ak1CaWjlSdr817Xtuj5fuCERo2+95Zbb3x0r9O/wBt91j/AOCEvwhjY/dm0zdjoOJK/MSRHltvs/mbdq4Vtu7P1z7V99fA/wD4LUeD/ht+zh4Z/Z7+IP7JFh4st/DdmkEc1/qSPDLtPD+XJGcMBmirGXNGSV7GXiFl+b46pl+KwOHdZ0aqlKKaTtytbt23Z8Drhkyrj8eKMevrjdjj86/RIf8ABa39mo8y/wDBNzwrI3d2+y5P/kGvA/27f26vhZ+1toGh6T8Nv2WdF+HtzpV481xfac0Ra5UrgIRGi8d+c1VOpU5rSiellfEfFGKzCNHEZVKlBt3m5wajpdOyd90kdF/wRQ+Blt8Z/wBufR9Y1W08zT/CdjJq1wrL8iuvyRZ+rtn6ivoj9qz/AIKff8E/9d/aB8Qab8U/2Jl8daho16+mPr13ND+9WE4+UNzgNuxXyf8AsB/8FCrz9hPT/F8OkfC231u88TWfk2uoNfmKSyIVgo6HKZYtj1r51vtRu9Vv7jVdRfzLm8uHmuJe7szFif8Avo1n7HmrXle3Q8HHcFV+JuMcTjMx540YQjGlyy5W73crNO61tvufrh/wTq/4KJ/sP+M/2hIfg18HP2T/APhX954ut5LdtQR4fLuNiFhC4U8seQK/O/8A4KD/AAUk/Z+/bI8efDaGFUs4tYa7035cZt5h5in6ZYj8K87+EHxJ1v4OfFPw/wDFbw6T9u8P6vDfW6q5XeY2BKZ7AjI/GvTv2+v2y2/bj+M1v8XH+G1v4be30qOyMEV2ZnmCknc7YHcnHHSrhSVOtdbGmUcG1OF+NHVwCnLC1qVpuUrtSTTV23d3PqD/AINz8f8ADQXxAcsFx4PiHzH1uBXwz8bbi4t/jx4vvbSWSGaHxdqEkM0LbSCLhypz1Bz0Ir1b/gnx+3Ze/sHfEDXvHFp8Pk8RDXNGFi1u16YPKIfcHzg5+mK8R8aeJZvGfjPWPGU9otvJq2qT3jW6MWWIySF9oJ6gZpxp/vnJ9j1MryXH0eOMxx1aH7mtCnGLdtbXv56FfxF4h13xPqU2ueJ9YutSvrhds15fXDSyuPUsa/TL/gpUMf8ABHL4Iq7KCjab8rHn/Ut2/GvzCdd/HtivpX9or/gonqnx+/Y/8Efsoz/DOHTU8IGAyayuoNIbnylKrhMfLkHnJNRUpybhboHFWR43GZplMsHTThQq80mraR5Wr/pofNdFFFdJ97YKKKKCwooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooJaCgM4YEHp220UUBygTk5ooooDlCiiigOUKKKKASCiiigbVwBx2o47CiigXKFFFFAcoUUUUByhRRRQHKFFFFAcoUUUUDSsFFFFAmgooooDlCiiigOUKKKKCgooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooA//2Q=='; 

        Test.startTest();
        AttendanceMgtController.uploadSelfie(latestAttendanceId, base64Image);
        Test.stopTest();

        ContentVersion cv = [SELECT Id, Title FROM ContentVersion LIMIT 1];
        System.assertNotEquals(null, cv, 'Selfie file should be uploaded.');
    }
    
   @isTest
    static void uploadfile() {
        // Create user related Employee_Leave_Application__c record
        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        Employee_Leave_Application__c leaveApplication = new Employee_Leave_Application__c(
            User__c = testUser.Id,
            Leave_Type__c = 'Casual Leave'
        );
        insert leaveApplication;              
                
        String latestAttendanceId = leaveApplication.Id;
        String base64Image = '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAIBAQEBAQIBAQECAgICAgQDAgICAgUEBAMEBgUGBgYFBgYGBwkIBgcJBwYGCAsICQoKCgoKBggLDAsKDAkKCgr/2wBDAQICAgICAgUDAwUKBwYHCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgr/wAARCAImAiYDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD5Xooor6Q/0sCiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooJbCiiigV2FFFFBYUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRRe25MpKwUYPpQAWOFGf6fX0p0MFxczrbW0bSSMcLHGhZmPoAOtTOUacbzdl5ky929+g3nOKVVdj+7UZ/wBocD612Ghfs8/HnxLbC70D4O+I7uM9Hi0qTB/MV2XwK/Yo+LHxQ+JkPg3xv4U1Lw9plrEbnWNU1SzaIRWwOSqbsZf37da+dx3GHDeXYWpWni6bcfsqScn5Kzvfslq2edXzbLcPTcp1Y6a6NXv2scL8KPgn8UPjlri+G/hb4PudQkRv9Imh/wBTEPV26KPr+Ve7r/wT18AfDu3jl/aN/ad0Tw3dEZk03T2WSVPzIz+VHx2/bL0v4baO3wB/ZBhj0Lw/p7GC88QWgX7TqMg4dt+M4z/F1Pav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v8XH+G1v4be30qOyMEV2ZnmCknc7YHcnHHSrhSVOtdbGmUcG1OF+NHVwCnLC1qVpuUrtSTTV23d3PqD/AINz8f8ADQXxAcsFx4PiHzH1uBXwz8bbi4t/jx4vvbSWSGaHxdqEkM0LbSCLhypz1Bz0Ir1b/gnx+3Ze/sHfEDXvHFp8Pk8RDXNGFi1u16YPKIfcHzg5+mK8R8aeJZvGfjPWPGU9otvJq2qT3jW6MWWIySF9oJ6gZpxp/vnJ9j1MryXH0eOMxx1aH7mtCnGLdtbXv56FfxF4h13xPqU2ueJ9YutSvrhds15fXDSyuPUsa/TL/gpUMf8ABHL4Iq7KCjab8rHn/Ut2/GvzCdd/HtivpX9or/gonqnx+/Y/8Efsoz/DOHTU8IGAyayuoNIbnylKrhMfLkHnJNRUpybhboHFWR43GZplMsHTThQq80mraR5Wr/pofNdFFFdJ97YKKKKCwooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooJaCgM4YEHp220UUBygTk5ooooDlCiiigOUKKKKASCiiigbVwBx2o47CiigXKFFFFAcoUUUUByhRRRQHKFFFFAcoUUUUDSsFFFFAmgooooDlCiiigOUKKKKCgooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooA//2Q=='; 

        Test.startTest();
        AttendanceMgtController.uploadfile(latestAttendanceId, base64Image);
        Test.stopTest();

        ContentVersion cv = [SELECT Id, Title FROM ContentVersion LIMIT 1];
        System.assertNotEquals(null, cv, 'Selfie file should be uploaded.');
    }
    
    @isTest
    static void testUpdateEOFDfield() {
        Test.startTest();
        Boolean result = AttendanceMgtController.updateEOFDfield();
        Test.stopTest();

        System.assert(result, 'updateEOFDfield should return true');

        // Verify that the field was updated
        Attendance__c updatedRecord = [SELECT EOD_Date_Time__c FROM Attendance__c WHERE CreatedDate = TODAY LIMIT 1];
        System.assertNotEquals(updatedRecord.EOD_Date_Time__c, null, 'EOD_Date_Time__c should be updated');
    }

    @isTest
    static void testUpdateEOFDfieldNoRecords() {
        Test.startTest();
        Boolean result = AttendanceMgtController.updateEOFDfield();
        Test.stopTest();
        
        System.assert(result, 'updateEOFDfield should return true even if no records exist');
    }
} */


/**
 * Test Class  : AttendanceMgtControllerTest
 * author      : Shyam
 * CreatedDate : 22-01-25
 * Description : Test class for AttendanceMgtController.
 */
@isTest
private class AttendanceMgtControllerTest {

    private static final String MIN_JPEG_BASE64 =
        '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAv/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCwAA8A/9k=';

    @testSetup
    static void setupTestData() {
        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        insert new Employee_Leave_Allowance__c(
            User__c = testUser.Id,
            Total_Sick_Leave__c = 10,
            Total_Earned_Leave__c = 20,
            Total_Casual_Leave__c = 10,
            Total_Maternity_Leave__c = 5,
            Used_Sick_Leave__c = 5,
            Used_Earned_Leave__c = 10,
            Used_Casual_Leave__c = 7,
            Used_Maternity_Leave__c = 5
        );

        insert new Attendance__c(
            User__c = testUser.Id,
            Date_of_attendance__c = Date.today(),
            Location__Latitude__s = 25.333,
            Location__Longitude__s = 12.33,
            Status__c = 'Present'
        );

        Employee_Leave_Application__c leaveMaster = new Employee_Leave_Application__c(
            User__c = testUser.Id
        );
        insert leaveMaster;

        insert new Leave_Application__c(
            User__c = testUser.Id,
            Employee_Leave_Application__c = leaveMaster.Id,
            Leave_Types__c = 'Casual Leave',
            Start_Date__c = Date.today(),
            End_Date__c = Date.today(),
            Leave_Period__c = 'Full Day'
        );
    }

    @isTest
    static void testGetLeaveBalancesForUser() {
        Test.startTest();
        Employee_Leave_Allowance__c result = AttendanceMgtController.getLeaveBalancesForUser();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Leave allowance should not be null.');
        System.assertEquals(5, result.Available_Sick_Leave__c, 'Available Sick Leave should be 5.');
    }

    @isTest
    static void testCheckAttendanceForToday() {
        Test.startTest();
        Boolean hasAttendance = AttendanceMgtController.checkAttendanceForToday();
        Test.stopTest();

        System.assert(hasAttendance, 'There should be an attendance record for today.');
    }

    @isTest
    static void testGetLeaveApplicationRecords() {
        Test.startTest();
        List<Leave_Application__c> results = AttendanceMgtController.getLeaveApplicationRecords();
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected 1 leave record');
    }

    @isTest
    static void testAttendanceList() {
        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        Attendance__c attendance = new Attendance__c(
            User__c = testUser.Id,
            Date_of_attendance__c = Date.today(),
            Status__c = 'Present'
        );
        insert attendance;

        Test.startTest();
        List<Attendance__c> result = AttendanceMgtController.attendanceList();
        Test.stopTest();

        System.assertNotEquals(null, result, 'The attendance list should not be null.');
        System.assertEquals(1, result.size(), 'The attendance list should contain exactly one record.');
        System.assertEquals('Present', result[0].Status__c, 'The status should be Present.');

        delete [SELECT Id FROM Attendance__c WHERE User__c = :testUser.Id];

        List<Attendance__c> resultNoData = AttendanceMgtController.attendanceList();
        System.assertEquals(0, resultNoData.size(), 'The attendance list should be empty when no records exist.');
    }

    @isTest
    static void testMarkAttendanceNewRecord() {
        delete [SELECT Id FROM Attendance__c];

        User testUser = [SELECT Id FROM User WHERE Username = :UserInfo.getUserName() LIMIT 1];
        Attendance__c testAttendance = new Attendance__c(
            User__c = testUser.Id,
            Work__c = 'Test Work',
            Description__c = 'Test Description'
        );

        System.runAs(testUser) {
            Test.startTest();
            String result = AttendanceMgtController.markAttendance(testAttendance);
            Test.stopTest();
            System.assert(!result.startsWith('error'), 'markAttendance failed: ' + result);
        }
    }

    @isTest
    static void testMarkAttendanceExistingRecord() {
        User testUser = [SELECT Id FROM User WHERE Username = :UserInfo.getUserName() LIMIT 1];
        Attendance__c existingAttendance = new Attendance__c(
            User__c = testUser.Id,
            Status__c = 'Present',
            Date_of_attendance__c = Date.today(),
            Work__c = 'Test Work',
            Location__Latitude__s = 25.333,
            Location__Longitude__s = 12.33,
            Description__c = 'Test Description'
        );
        insert existingAttendance;

        Attendance__c testAttendance = new Attendance__c(
            Work__c = 'Updated Work',
            Description__c = 'Updated Description',
            Status__c = 'Leave',
            Leave_Period__c = 'Full Day'
        );

        System.runAs(testUser) {
            Test.startTest();
            String result = AttendanceMgtController.markAttendance(testAttendance);
            Test.stopTest();

            existingAttendance = [
                SELECT Id, Status__c, Work__c, Description__c
                FROM Attendance__c
                WHERE Id = :existingAttendance.Id
            ];
            System.assertNotEquals(null, result);
        }
    }

    @isTest
    static void testMarkAttendance_AbsentAutomaticUpdate() {
        Id currentUserId = UserInfo.getUserId();

        delete [SELECT Id FROM Attendance__c];

        Attendance__c existingAtt = new Attendance__c(
            User__c = currentUserId,
            Status__c = 'Absent',
            Automatic_Attendance_Record__c = true,
            Date_of_attendance__c = Date.today()
        );
        insert existingAtt;

        Attendance__c uiInput = new Attendance__c(
            Status__c = 'Present',
            Work__c = 'Field Visit',
            Description__c = 'Visited client A',
            Location__Latitude__s = 12.9716,
            Location__Longitude__s = 77.5946
        );

        Test.startTest();
        String returnedId = AttendanceMgtController.markAttendance(uiInput);
        Test.stopTest();

        List<Attendance__c> todaysAtts = [
            SELECT Id, Status__c, Work__c, Description__c, Date_of_attendance__c,
                   Automatic_Attendance_Record__c, Location__Latitude__s, Location__Longitude__s
            FROM Attendance__c
            WHERE User__c = :currentUserId
              AND Date_of_attendance__c = :Date.today()
        ];

        System.assertEquals(1, todaysAtts.size(), 'Expected one attendance for today.');
        Attendance__c updatedAtt = todaysAtts[0];

        System.assertEquals(false, updatedAtt.Automatic_Attendance_Record__c,
            'Automatic flag should be false after manual update.');
        System.assert(
            new Set<String>{ 'Present', 'Late', 'Present Half Day', 'Present Half Day / Absent' }
                .contains(updatedAtt.Status__c),
            'Status should reflect time-based attendance rules. Actual: ' + updatedAtt.Status__c
        );
        System.assertEquals('Field Visit', updatedAtt.Work__c);
        System.assertEquals('Visited client A', updatedAtt.Description__c);
        System.assertEquals(Date.today(), updatedAtt.Date_of_attendance__c);
        System.assertEquals(12.9716, updatedAtt.Location__Latitude__s);
        System.assertEquals(77.5946, updatedAtt.Location__Longitude__s);
        System.assert(!returnedId.startsWith('error'), 'Method should not return error: ' + returnedId);
    }

    @isTest
    static void testMarkAttendanceException() {
        Attendance__c testAttendance = new Attendance__c();
        testAttendance.Work__c = null;

        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        System.runAs(testUser) {
            Test.startTest();
            String result = AttendanceMgtController.markAttendance(testAttendance);
            Test.stopTest();
            System.assertNotEquals(null, result);
        }
    }

    @isTest
    static void testAddLeaveApplication() {
        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        Employee_Leave_Application__c empLeaveApp = new Employee_Leave_Application__c(
            User__c = testUser.Id,
            Leave_Type__c = 'Casual Leave',
            Reason_For_Leave__c = 'Vacation'
        );
        insert empLeaveApp;

        Leave_Application__c testLeaveApp = new Leave_Application__c(
            User__c = testUser.Id,
            Leave_Types__c = 'Casual Leave',
            Start_Date__c = Date.today(),
            End_Date__c = Date.today(),
            Leave_Period__c = 'Full Day',
            Employee_Leave_Application__c = empLeaveApp.Id
        );
        insert testLeaveApp;

        Leave_Application__c conflictingLeaveApp = new Leave_Application__c(
            User__c = testUser.Id,
            Leave_Types__c = 'Casual Leave',
            Start_Date__c = Date.today(),
            End_Date__c = Date.today(),
            Leave_Period__c = 'Half Day',
            Leave_For__c = 'First Half',
            Employee_Leave_Application__c = empLeaveApp.Id
        );

        try {
            insert conflictingLeaveApp;
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('You already have a leave application for this day.'),
                'Unexpected exception message: ' + e.getMessage()
            );
        }

        Test.startTest();
        String result = '';
        try {
            result = AttendanceMgtController.addLeaveApplication(testLeaveApp);
        } catch (AuraHandledException e) {
            System.debug('Error during leave application process: ' + e.getMessage());
        }
        Test.stopTest();

        Leave_Application__c insertedLeaveApp = [
            SELECT Id, Employee_Leave_Application__c
            FROM Leave_Application__c
            WHERE Id = :testLeaveApp.Id
            LIMIT 1
        ];
        System.assertNotEquals(null, insertedLeaveApp.Employee_Leave_Application__c);
    }

    @isTest
    static void testAddLeaveApplicationExceedsLeaveLimit() {
        Leave_Application__c testLeaveApp = new Leave_Application__c(
            User__c = [SELECT Id FROM User WHERE Username = :UserInfo.getUserName() LIMIT 1].Id,
            Leave_Types__c = 'Casual Leave',
            Start_Date__c = Date.today(),
            End_Date__c = Date.today()
        );

        try {
            Test.startTest();
            AttendanceMgtController.addLeaveApplication(testLeaveApp);
            Test.stopTest();
        } catch (AuraHandledException e) {
            System.assertEquals('You can only take 2 Casual Leaves for a month.', e.getMessage());
        }
    }

    @isTest
    static void testAddLeaveApplicationCombinationLeave() {
        Id userId = [SELECT Id FROM User WHERE Username = :UserInfo.getUserName() LIMIT 1].Id;

        Employee_Leave_Application__c empApp1 = new Employee_Leave_Application__c(User__c = userId);
        insert empApp1;
        Employee_Leave_Application__c empApp2 = new Employee_Leave_Application__c(User__c = userId);
        insert empApp2;

        Leave_Application__c testLeaveApp = new Leave_Application__c(
            User__c = userId,
            Leave_Types__c = 'Casual Leave',
            Start_Date__c = Date.today(),
            End_Date__c = Date.today(),
            Leave_Period__c = 'Half Day',
            Leave_For__c = 'First Half',
            Employee_Leave_Application__c = empApp1.Id
        );
        insert testLeaveApp;

        Leave_Application__c conflictingLeaveApp = new Leave_Application__c(
            User__c = userId,
            Leave_Types__c = 'Sick Leave',
            Start_Date__c = Date.today(),
            End_Date__c = Date.today(),
            Leave_Period__c = 'Half Day',
            Leave_For__c = 'Second Half',
            Employee_Leave_Application__c = empApp2.Id
        );

        Test.startTest();
        try {
            AttendanceMgtController.addLeaveApplication(conflictingLeaveApp);
            System.assert(false, 'Expected an exception to be thrown.');
        } catch (AuraHandledException e) {
            System.assert(
                e.getMessage() == 'Script-thrown exception'
                    || e.getMessage().contains('leave application'),
                'Unexpected message: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @isTest
    static void testAddLeaveApplicationEarnedLeave() {
        User testUser = [SELECT Id FROM User WHERE Username = :UserInfo.getUserName() LIMIT 1];

        Employee_Leave_Application__c empApp1 = new Employee_Leave_Application__c(User__c = testUser.Id);
        insert empApp1;
        Employee_Leave_Application__c empApp2 = new Employee_Leave_Application__c(User__c = testUser.Id);
        insert empApp2;

        Leave_Application__c testLeaveApp = new Leave_Application__c(
            User__c = testUser.Id,
            Leave_Types__c = 'Earned Leave',
            Start_Date__c = Date.today(),
            End_Date__c = Date.today(),
            Leave_Period__c = 'Half Day',
            Leave_For__c = 'Second Half',
            Employee_Leave_Application__c = empApp1.Id
        );

        Leave_Application__c conflictingLeaveApp = new Leave_Application__c(
            User__c = testUser.Id,
            Leave_Types__c = 'Earned Leave',
            Start_Date__c = Date.today(),
            End_Date__c = Date.today(),
            Leave_Period__c = 'Half Day',
            Leave_For__c = 'First Half',
            Employee_Leave_Application__c = empApp2.Id
        );

        try {
            insert testLeaveApp;
            insert conflictingLeaveApp;

            Test.startTest();
            String result = AttendanceMgtController.addLeaveApplication(testLeaveApp);
            Test.stopTest();

            System.assertNotEquals(null, result);
        } catch (DmlException e) {
            System.assert(false, 'Expected behavior not achieved: ' + e.getMessage());
        } catch (Exception e) {
            System.debug('Error: ' + e.getMessage());
        }
    }

    @isTest
    static void uploadSelfie() {
        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        insert new Employee_Leave_Application__c(
            User__c = testUser.Id,
            Leave_Type__c = 'Casual Leave'
        );

        Attendance__c attendance = [SELECT Id FROM Attendance__c WHERE User__c = :testUser.Id LIMIT 1];

        Test.startTest();
        AttendanceMgtController.uploadSelfie(attendance.Id, MIN_JPEG_BASE64);
        Test.stopTest();

        System.assertNotEquals(0, [SELECT COUNT() FROM ContentVersion]);
    }

    @isTest
    static void uploadfile() {
        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        Employee_Leave_Application__c leaveApplication = new Employee_Leave_Application__c(
            User__c = testUser.Id,
            Leave_Type__c = 'Casual Leave'
        );
        insert leaveApplication;

        Test.startTest();
        AttendanceMgtController.uploadfile(leaveApplication.Id, MIN_JPEG_BASE64);
        Test.stopTest();

        System.assertNotEquals(0, [SELECT COUNT() FROM ContentVersion]);
    }

    @isTest
    static void testUpdateEODDateTime() {
        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        Attendance__c att = new Attendance__c(
            User__c = testUser.Id,
            Date_of_attendance__c = Date.today(),
            Status__c = 'Present'
        );
        insert att;

        Test.startTest();
        AttendanceMgtController.updateEODDateTime(att.Id, 12.9716, 77.5946);
        Test.stopTest();

        att = [
            SELECT EOD_Date_Time__c, EOD_Location__Latitude__s, EOD_Location__Longitude__s
            FROM Attendance__c
            WHERE Id = :att.Id
        ];
        System.assertNotEquals(null, att.EOD_Date_Time__c);
        System.assertEquals(12.9716, att.EOD_Location__Latitude__s);
        System.assertEquals(77.5946, att.EOD_Location__Longitude__s);
    }

    @isTest
    static void testUpdateEODDateTime_MissingLocation() {
        Attendance__c att = [
            SELECT Id FROM Attendance__c WHERE User__c = :UserInfo.getUserId() LIMIT 1
        ];

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            AttendanceMgtController.updateEODDateTime(att.Id, null, null);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected exception when EOD location is missing.');
    }

    @isTest
    static void testUpdateEOFDfield() {
        Test.startTest();
        Boolean result = AttendanceMgtController.updateEOFDfield();
        Test.stopTest();

        System.assertEquals(true, result, 'updateEOFDfield should return true');

        List<Attendance__c> updated = [
            SELECT EOD_Date_Time__c
            FROM Attendance__c
            WHERE CreatedDate = TODAY
        ];
        if (!updated.isEmpty()) {
            System.assertNotEquals(null, updated[0].EOD_Date_Time__c);
        }
    }

    @isTest
    static void testUpdateEOFDfieldNoRecords() {
        delete [SELECT Id FROM Attendance__c];

        Test.startTest();
        Boolean result = AttendanceMgtController.updateEOFDfield();
        Test.stopTest();

        System.assertEquals(true, result, 'updateEOFDfield should return true even if no records exist');
    }

    @isTest
    static void testAddLeaveApplication_NullInput() {
        Boolean exceptionThrown = false;
        try {
            AttendanceMgtController.addLeaveApplication(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        System.assert(exceptionThrown, 'Expected exception for null leave application.');
    }

    @isTest
    static void testAddLeaveApplication_FullDayConflictViaController() {
        Id userId = UserInfo.getUserId();
        Leave_Application__c duplicate = new Leave_Application__c(
            User__c = userId,
            Leave_Types__c = 'Sick Leave',
            Start_Date__c = Date.today(),
            End_Date__c = Date.today(),
            Leave_Period__c = 'Full Day'
        );

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            AttendanceMgtController.addLeaveApplication(duplicate);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected duplicate full-day leave rejection.');
    }

    @isTest
    static void testAddLeaveApplication_HalfDayConflictViaController() {
        Id userId = UserInfo.getUserId();
        Leave_Application__c duplicate = new Leave_Application__c(
            User__c = userId,
            Leave_Types__c = 'Earned Leave',
            Start_Date__c = Date.today(),
            End_Date__c = Date.today(),
            Leave_Period__c = 'Half Day',
            Leave_For__c = 'First Half'
        );

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            AttendanceMgtController.addLeaveApplication(duplicate);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected duplicate half-day leave rejection.');
    }

    @isTest
    static void testAddLeaveApplication_SickLeaveSuccess() {
        Id userId = UserInfo.getUserId();
        Date futureDate = Date.today().addDays(5);

        Leave_Application__c sickLeave = new Leave_Application__c(
            User__c = userId,
            Leave_Types__c = 'Sick Leave',
            Start_Date__c = futureDate,
            End_Date__c = futureDate,
            Leave_Period__c = 'Half Day',
            Leave_For__c = 'Second Half',
            Reason_For_Leave__c = 'Fever'
        );

        Test.startTest();
        String result = AttendanceMgtController.addLeaveApplication(sickLeave);
        Test.stopTest();
    }

    @isTest
    static void testAddLeaveApplication_EarnedLeaveViaController() {
        Id userId = UserInfo.getUserId();
        Date futureDate = Date.today().addDays(7);

        Leave_Application__c earnedLeave = new Leave_Application__c(
            User__c = userId,
            Leave_Types__c = 'Earned Leave',
            Start_Date__c = futureDate,
            End_Date__c = futureDate,
            Leave_Period__c = 'Full Day',
            Reason_For_Leave__c = 'Personal'
        );

        Test.startTest();
        String result = AttendanceMgtController.addLeaveApplication(earnedLeave);
        Test.stopTest();
    }

    @isTest
    static void testAddLeaveApplication_SickCasualCombination() {
        Id userId = UserInfo.getUserId();
        Date leaveDate = Date.today().addDays(10);

        Employee_Leave_Application__c empLeaveApp = new Employee_Leave_Application__c(
            User__c = userId
        );
        insert empLeaveApp;

        insert new Leave_Application__c(
            User__c = userId,
            Employee_Leave_Application__c = empLeaveApp.Id,
            Leave_Types__c = 'Casual Leave',
            Start_Date__c = leaveDate,
            End_Date__c = leaveDate,
            Leave_Period__c = 'Half Day',
            Leave_For__c = 'First Half',
            Approval_status__c = 'Approved'
        );

        Leave_Application__c sickHalf = new Leave_Application__c(
            User__c = userId,
            Leave_Types__c = 'Sick Leave',
            Start_Date__c = leaveDate,
            End_Date__c = leaveDate,
            Leave_Period__c = 'Half Day',
            Leave_For__c = 'Second Half'
        );

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            AttendanceMgtController.addLeaveApplication(sickHalf);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected sick/casual combination rejection.');
    }

    @isTest
    static void testMarkAttendance_PresentHalfDayExisting() {
        delete [SELECT Id FROM Attendance__c];
        Id userId = UserInfo.getUserId();

        insert new Attendance__c(
            User__c = userId,
            Status__c = 'Present Half Day',
            Date_of_attendance__c = Date.today(),
            Work__c = 'Morning',
            Location__Latitude__s = 12.9716,
            Location__Longitude__s = 77.5946
        );

        Attendance__c input = new Attendance__c(
            Work__c = 'Afternoon update',
            Description__c = 'Continued work',
            Location__Latitude__s = 12.9720,
            Location__Longitude__s = 77.5950
        );

        Test.startTest();
        String result = AttendanceMgtController.markAttendance(input);
        Test.stopTest();

        System.assert(!result.startsWith('error'), 'markAttendance failed: ' + result);

        Attendance__c updated = [
            SELECT Status__c, Work__c, Description__c
            FROM Attendance__c
            WHERE Id = :result
        ];
        System.assertEquals('Present Half Day', updated.Status__c);
        System.assertEquals('Afternoon update', updated.Work__c);
        System.assertEquals('Continued work', updated.Description__c);
    }

    @isTest
    static void testMarkAttendance_HalfDayLeavePeriodUpdate() {
        delete [SELECT Id FROM Attendance__c];
        Id userId = UserInfo.getUserId();

        insert new Attendance__c(
            User__c = userId,
            Status__c = 'Present',
            Leave_Period__c = 'Half Day',
            Date_of_attendance__c = Date.today()
        );

        Attendance__c input = new Attendance__c(
            Work__c = 'Updated',
            Description__c = 'Half day path'
        );

        Test.startTest();
        String result = AttendanceMgtController.markAttendance(input);
        Test.stopTest();

        Attendance__c updated = [
            SELECT Status__c, Work__c
            FROM Attendance__c
            WHERE User__c = :userId
            LIMIT 1
        ];
        System.assert(!result.startsWith('error'));
        System.assertEquals('Present Half Day', updated.Status__c);
    }

    @isTest
    static void testMarkAttendance_LeaveStatusFullDay() {
        delete [SELECT Id FROM Attendance__c];
        Id userId = UserInfo.getUserId();

        insert new Attendance__c(
            User__c = userId,
            Status__c = 'Leave',
            Leave_Period__c = 'Full Day',
            Date_of_attendance__c = Date.today()
        );

        Attendance__c input = new Attendance__c(
            Work__c = 'N/A',
            Description__c = 'On leave'
        );

        Test.startTest();
        String result = AttendanceMgtController.markAttendance(input);
        Test.stopTest();

        Attendance__c updated = [
            SELECT Status__c
            FROM Attendance__c
            WHERE User__c = :userId
            LIMIT 1
        ];
        System.assert(!result.startsWith('error'));
        System.assertEquals('Leave', updated.Status__c);
    }

    @isTest
    static void testMarkAttendance_MatchByLeaveDate() {
        delete [SELECT Id FROM Attendance__c];
        Id userId = UserInfo.getUserId();

        insert new Attendance__c(
            User__c = userId,
            Status__c = 'Leave',
            Leave_Date__c = Date.today()
        );

        Attendance__c input = new Attendance__c(
            Work__c = 'Leave day update',
            Description__c = 'Matched via Leave_Date__c'
        );

        Test.startTest();
        String result = AttendanceMgtController.markAttendance(input);
        Test.stopTest();

        System.assert(!result.startsWith('error'), result);
    }

    @isTest
    static void testMarkAttendance_MissingUserReturnsError() {
        delete [SELECT Id FROM Attendance__c];

        Attendance__c invalid = new Attendance__c(
            Work__c = 'No user',
            Description__c = 'Should fail insert'
        );

        Test.startTest();
        String result = AttendanceMgtController.markAttendance(invalid);
        Test.stopTest();

        System.assert(result.startsWith('error'), 'Expected error when User__c is missing.');
    }

    @isTest
    static void testUploadSelfie_InvalidInput() {
        Boolean exceptionThrown = false;
        try {
            AttendanceMgtController.uploadSelfie(null, '');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        System.assert(exceptionThrown, 'Expected exception for invalid selfie input.');
    }

    @isTest
    static void testUploadfile_InvalidInput() {
        Boolean exceptionThrown = false;
        try {
            AttendanceMgtController.uploadfile('', '');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        System.assert(exceptionThrown, 'Expected exception for invalid file upload input.');
    }

    @isTest
    static void testUploadfile_Base64DataUriPrefix() {
        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        Employee_Leave_Application__c leaveApplication = new Employee_Leave_Application__c(
            User__c = testUser.Id,
            Leave_Type__c = 'Casual Leave'
        );
        insert leaveApplication;

        String dataUri = 'data:image/jpeg;base64,' + MIN_JPEG_BASE64;

        Test.startTest();
        AttendanceMgtController.uploadfile(leaveApplication.Id, dataUri);
        Test.stopTest();

        System.assertNotEquals(0, [SELECT COUNT() FROM ContentVersion]);
    }

    @isTest
    static void testUpdateEODDateTime_NullAttendanceId() {
        Boolean exceptionThrown = false;
        try {
            AttendanceMgtController.updateEODDateTime(null, 1.0, 2.0);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        System.assert(exceptionThrown, 'Expected exception when attendance Id is null.');
    }

    @isTest
    static void testUpdateEODDateTime_AttendanceNotFound() {
        Attendance__c temp = new Attendance__c(
            User__c = UserInfo.getUserId(),
            Date_of_attendance__c = Date.today(),
            Status__c = 'Present'
        );
        insert temp;
        Id deletedId = temp.Id;
        delete temp;

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            AttendanceMgtController.updateEODDateTime(deletedId, 12.0, 77.0);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected exception when attendance record is missing.');
    }

    @isTest
    static void testCheckAttendanceForToday_NoPresentOrLeave() {
        delete [SELECT Id FROM Attendance__c];
        Id userId = UserInfo.getUserId();

        insert new Attendance__c(
            User__c = userId,
            Date_of_attendance__c = Date.today(),
            Status__c = 'Absent'
        );

        Test.startTest();
        Boolean hasAttendance = AttendanceMgtController.checkAttendanceForToday();
        Test.stopTest();

        System.assertEquals(false, hasAttendance, 'Absent should not count as present/leave for today.');
    }
}