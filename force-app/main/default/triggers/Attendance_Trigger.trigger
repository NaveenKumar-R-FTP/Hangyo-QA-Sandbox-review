trigger Attendance_Trigger on Attendance__c (after insert, after update) {

    if (Trigger.isAfter) {
        Set<Id> attendanceIdSet = new Set<Id>();
        if (Trigger.isInsert) {
            for (Attendance__c att : Trigger.new) {
                if (att.Status__c == 'Present' || att.Status__c == 'Present Half Day') {
                    attendanceIdSet.add(att.Id);
                }
            }
        }

        if (Trigger.isUpdate) {
            for (Attendance__c att : Trigger.new) {
                Attendance__c oldAtt = Trigger.oldMap.get(att.Id);
                if (
                    (att.Status__c == 'Present' || att.Status__c == 'Present Half Day') &&
                    att.Status__c != oldAtt.Status__c
                ) {
                    attendanceIdSet.add(att.Id);
                }
            }
        }

        if (!attendanceIdSet.isEmpty()) {
            ScheduleBeatPlan.createVisitTask(attendanceIdSet);
        }
    }
}