global class AttendanceDistanceBatchHaversine implements Database.Batchable<SObject>, Database.Stateful {

    global Database.QueryLocator start(Database.BatchableContext bc) {
        // Query directly instead of fetching profile separately
        return Database.getQueryLocator([
            SELECT Id, Name, User__c,Total_Distance__c,Date_of_attendance__c
            FROM Attendance__c
            WHERE Date_of_attendance__c = TODAY
            AND Status__c NOT IN ('Leave' , 'Absent')
            AND User__r.IsActive = true
            //AND User__r.Profile.Name = 'SFA Profile'
            AND User__r.Profile.Name IN ('SFA Profile','SFA Profile - Light')
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Attendance__c> scope) {
        System.debug('scope:- ' + scope);
        if (scope.isEmpty()) return;

        Set<Id> userIds = new Set<Id>();
        for (Attendance__c att : scope) {
            if (att.User__c != null) {
                userIds.add(att.User__c);
            }
        }
        System.debug('userIds:- ' + userIds);

        if (userIds.isEmpty()) return;

        // Fetch Visit Tasks for today's date based on Checked_In_Time__c
        List<Visit_Task__c> visitTasks = [
            SELECT Id, Visitor_Name__c, 
                   Checked_In_Location__Latitude__s, Checked_In_Location__Longitude__s, 
                   Checked_In_Time__c
            FROM Visit_Task__c
            WHERE Visitor_Name__c IN :userIds
            AND DAY_ONLY(Checked_In_Time__c) = TODAY
            ORDER BY Visitor_Name__c, Checked_In_Time__c ASC
        ];

        // Group tasks by user
        Map<Id, List<Visit_Task__c>> userTasks = new Map<Id, List<Visit_Task__c>>();
        for (Visit_Task__c vt : visitTasks) {
            if (vt.Visitor_Name__c == null 
                || vt.Checked_In_Location__Latitude__s == null 
                || vt.Checked_In_Location__Longitude__s == null) {
                continue; // skip invalid entries
            }
            if (!userTasks.containsKey(vt.Visitor_Name__c)) {
                userTasks.put(vt.Visitor_Name__c, new List<Visit_Task__c>());
            }
            userTasks.get(vt.Visitor_Name__c).add(vt);
        }

        // Calculate distances and update attendance
        List<Attendance__c> updated = new List<Attendance__c>();
        for (Attendance__c att : scope) {
            if (userTasks.containsKey(att.User__c)) {
                List<Visit_Task__c> tList = userTasks.get(att.User__c);
                Double totalDistanceMeters = 0.0;

                for (Integer i = 0; i < tList.size() - 1; i++) {
                    totalDistanceMeters += DistanceUtils.calculateDistanceInMeters(
                        tList[i].Checked_In_Location__Latitude__s,
                        tList[i].Checked_In_Location__Longitude__s,
                        tList[i+1].Checked_In_Location__Latitude__s,
                        tList[i+1].Checked_In_Location__Longitude__s
                    );
                }

                // Store in KM
                att.Total_Distance__c = (totalDistanceMeters / 1000);
                updated.add(att);
            }
        }

        if (!updated.isEmpty()) {
            Database.update(updated, false);
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('Finished Attendance Distance Calculation - Updated Records');
    }
}