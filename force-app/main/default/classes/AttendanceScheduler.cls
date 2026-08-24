global class AttendanceScheduler implements Schedulable{
    
    global void execute(SchedulableContext sc){
        
        AttendanceDistanceBatchHaversine batch = new AttendanceDistanceBatchHaversine();
        
        Database.executeBatch(batch,200);
    }

}