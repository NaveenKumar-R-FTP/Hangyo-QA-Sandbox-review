global class AttendanceAbsentScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {
        updateAttendanceStatus();
    }

    public static void updateAttendanceStatus() {
        List<Attendance__c> attendanceList = [
            SELECT Id, Status__c, EOD_Date_Time__c
            FROM Attendance__c
            WHERE EOD_Date_Time__c = NULL
            AND Status__c NOT IN ('Absent' , 'Leave')
            AND Date__c = :Date.today()
        ];

        if (!attendanceList.isEmpty()) {
            for (Attendance__c att : attendanceList) {
                att.Status__c = 'Absent';
            }
            update attendanceList;
            System.debug('Attendance marked as Absent: ' + attendanceList.size());
        } else {
            System.debug('No attendance records found for update.');
        }
    }
}