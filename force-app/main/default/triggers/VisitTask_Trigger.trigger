trigger VisitTask_Trigger on Visit_Task__c (after update) {
    
    if(Trigger.isAfter && Trigger.isUpdate){
        Set<Id> visitTaskSet = new Set<Id>{};
        for(Visit_Task__c vt : Trigger.new){
            if(vt.Checked_In_Time__c != NULL && Trigger.oldMap.get(vt.Id).Checked_In_Time__c == NULL){
                visitTaskSet.add(vt.Id);
            }
        }
        
        if(visitTaskSet.size() > 0){
            VisitTaskHandler.populateFirstActivity(visitTaskSet);
        }
    }
}