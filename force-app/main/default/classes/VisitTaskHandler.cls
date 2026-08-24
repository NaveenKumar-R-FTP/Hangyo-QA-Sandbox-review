public class VisitTaskHandler {
    
    public static void populateFirstActivity(Set<Id> visitTaskSet){
        if(visitTaskSet.isEmpty()){
            return;
        }else{
            Set<Id> userIds = new Set<Id>();
            Map<Id, Time> userCheckInMap = new Map<Id, Time>();
            for(Visit_Task__c vt : [SELECT Id , Checked_In_Time__c , Visitor_Name__c FROM Visit_Task__c WHERE Id IN: visitTaskSet]){
                if(vt.Checked_In_Time__c != null){
                    userIds.add(vt.Visitor_Name__c);
                    Time currentCheckInTime = vt.Checked_In_Time__c.time();
                    if (userCheckInMap.containsKey(vt.Visitor_Name__c)) {       
                        Time existingTime = userCheckInMap.get(vt.Visitor_Name__c);
                        if (currentCheckInTime < existingTime) {
                            userCheckInMap.put(vt.Visitor_Name__c, currentCheckInTime);
                        }
                    } else {
                        userCheckInMap.put(vt.Visitor_Name__c, currentCheckInTime);
                    }
                }               
            }
            
            if(userIds.size() > 0){
                Date today = Date.today();
                List<Attendance__c> attendanceList = [
                    SELECT Id, User__c, First_Activity_Time__c FROM Attendance__c
                    WHERE User__c IN :userIds AND Date__c = :today AND First_Activity_Time__c = NULL
                ];
                
                List<Attendance__c> updateList = new List<Attendance__c>();

                for (Attendance__c att : attendanceList) {
                    if (userCheckInMap.containsKey(att.User__c)) {
                        att.First_Activity_Time__c = userCheckInMap.get(att.User__c);
                        updateList.add(att);
                    }
                }
        
                if (!updateList.isEmpty()) {
                    update updateList;
                }
            }
        }
    }
}