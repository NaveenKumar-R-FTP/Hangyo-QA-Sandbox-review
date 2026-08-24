public without sharing class ZingHR_AttendanceQueueable implements Queueable, Database.AllowsCallouts {

    private final String swipeType;

    // Default constructor — starts with ATTENDANCE pass
    public ZingHR_AttendanceQueueable() {
        this.swipeType = 'ATTENDANCE';
    }

    // Parameterised constructor — used to chain EOD pass
    public ZingHR_AttendanceQueueable(String swipeType) {
        this.swipeType = swipeType;
    }

    public void execute(QueueableContext context) {
        //Date today = Date.today();
        Date targetDate = Date.today().addDays(-4);

        if (swipeType == 'ATTENDANCE') {
            List<Attendance__c> attendanceRecords = [
                SELECT Id, EMP_CODE__c, Attendance_Applied_on__c, Status__c
                FROM Attendance__c
                WHERE Status__c != 'Absent'
                AND EMP_CODE__c != null
                AND DAY_ONLY(Attendance_Applied_on__c) >= : targetDate
                AND Attendance_Applied_on__c != null
                AND Attendance_Sent__c = false
                AND Approval_Status__c != 'Pending'
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];

            if (!attendanceRecords.isEmpty()) {
                ZingHR_AttendanceService.sendAttendance(attendanceRecords, 'ATTENDANCE');
            }

            // Chain EOD job — runs in a fresh transaction (no DML conflict)
            if (!Test.isRunningTest()) {
                System.enqueueJob(new ZingHR_AttendanceQueueable('EOD'));
            }

        } else if (swipeType == 'EOD') {
            List<Attendance__c> eodRecords = [
                SELECT Id, EMP_CODE__c, EOD_Date_Time__c, Status__c
                FROM Attendance__c
                WHERE Status__c != 'Absent'
                AND EMP_CODE__c != null
                AND DAY_ONLY(EOD_Date_Time__c) >= : targetDate
                AND EOD_Date_Time__c != null
                AND EOD_Sent__c = false
                AND Approval_Status__c != 'Pending'
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];

            if (!eodRecords.isEmpty()) {
                ZingHR_AttendanceService.sendAttendance(eodRecords, 'EOD');
            }
        }
    }
}