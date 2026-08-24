public class ZingHR_AttendanceScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        System.enqueueJob(new ZingHR_AttendanceQueueable());
    }
}