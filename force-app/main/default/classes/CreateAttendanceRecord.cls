public class CreateAttendanceRecord implements Database.Batchable<SObject> , Schedulable {
    
    public Database.QueryLocator start(Database.BatchableContext bc){
        return Database.getQueryLocator([
            SELECT Id, Name FROM User
            WHERE Id NOT IN (SELECT User__c FROM Attendance__c WHERE Date__c =: Date.TODAY())
            //AND IsActive = TRUE AND Profile.Name = 'SFA Profile'
            AND IsActive = TRUE AND Profile.Name IN ('SFA Profile','SFA Profile - Light')
        ]);
    }
    
    public void execute(Database.BatchableContext bc, List<User> scope) {
        List<Attendance__c> attendanceList = new List<Attendance__c>();

        for (User u : scope) {
            Attendance__c att = new Attendance__c();
            att.User__c = u.Id;
            att.OwnerId = u.Id;
            att.Leave_Date__c = Date.today();
            att.Date_of_attendance__c = Date.today();
            att.Status__c = 'Absent';
            att.Description__c = 'Automatic Attendance Record Created';
            att.Automatic_Attendance_Record__c = true;
            attendanceList.add(att);
        }

        if (!attendanceList.isEmpty()) {
            insert attendanceList;
        }
    }

    public void finish(Database.BatchableContext bc) {
        // Optional: Send email, log info, etc.
        System.debug('Attendance records created successfully for users without today\'s attendance.');
    }
    
    // Schedulable execute – this method runs when scheduled
    public void execute(SchedulableContext sc) {
        CreateAttendanceRecord batchJob = new CreateAttendanceRecord();
        Database.executeBatch(batchJob, 500); // you can adjust batch size
    }
}