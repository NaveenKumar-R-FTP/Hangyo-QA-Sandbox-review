/**
 * Added by Hari on 04/05/2026
 * Schedulable entry point. Run on a schedule (for example daily after 12:30 PM) to process
 * Attendance__c rows for a given attendance date where Attendance_Applied_on__c is after
 * 12:30 PM that day; status is set from EOD vs applied duration in the batch class.
 */
public class AttendanceHalfDayAbsentScheduler implements Schedulable {
    private Date targetDate;

    /**
     * @param targetDate Attendance date (Date__c) to evaluate; when null, today is used.
     */
    public AttendanceHalfDayAbsentScheduler(Date targetDate) {
        this.targetDate = targetDate;
    }

    public AttendanceHalfDayAbsentScheduler() {
        this.targetDate = null;
    }

    public void execute(SchedulableContext sc) {
        //Added by Hari — record-wise scope only; no user-level aggregate
        Date runDate;
        if (this.targetDate == null) {
            runDate = Date.today();
        } else {
            runDate = this.targetDate;
        }

        Database.executeBatch(new AttendanceHalfDayAbsentBatch(runDate), 200);
    }
}