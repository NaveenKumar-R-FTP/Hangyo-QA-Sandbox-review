public class ScheduleBeatPlan {

    public static void createVisitTask(Set<Id> attendanceIdSet) {

        if (attendanceIdSet == null || attendanceIdSet.isEmpty()) {
            return;
        }

        Date todayDate = Date.today();

        /* ---------------- Fetch Present Users ---------------- */
        Set<Id> userIds = new Set<Id>();
        for (Attendance__c att : [
            SELECT User__c
            FROM Attendance__c
            WHERE Id IN :attendanceIdSet
            AND Status__c IN ('Present', 'Present Half Day')
        ]) {
            if (att.User__c != null) {
                userIds.add(att.User__c);
            }
        }

        if (userIds.isEmpty()) return;

        /* ---------------- Fetch Monthly Beat Plans ---------------- */
        List<Monthly_Beat_Plan__c> beatPlans = [
            SELECT User__c, Beat_Name__c
            FROM Monthly_Beat_Plan__c
            WHERE User__c IN :userIds
            AND Date__c = :todayDate
            AND IsActive__c = true
        ];

        if (beatPlans.isEmpty()) return;

        /* ---------------- Beat → User Mapping ---------------- */
        Map<Id, Id> beatToUserMap = new Map<Id, Id>();
        Set<Id> beatIds = new Set<Id>();

        for (Monthly_Beat_Plan__c mbp : beatPlans) {
            if (mbp.Beat_Name__c != null && !beatToUserMap.containsKey(mbp.Beat_Name__c)) {
                beatToUserMap.put(mbp.Beat_Name__c, mbp.User__c);
                beatIds.add(mbp.Beat_Name__c);
            }
        }

        if (beatIds.isEmpty()) return;

        /* ---------------- Fetch Existing Visits (Prevent Duplicates) ---------------- */
        Set<String> existingVisitKeys = new Set<String>();

        for (Visit__c v : [
            SELECT OwnerId, Beat__c
            FROM Visit__c
            WHERE OwnerId IN :userIds
            AND Beat__c IN :beatIds
            AND Visit_planned_date__c = :todayDate
            AND Visit_Type__c = 'Planned'
        ]) {
            existingVisitKeys.add(v.OwnerId + '-' + v.Beat__c);
        }

        /* ---------------- Create Missing Visits Only ---------------- */
        List<Visit__c> visitsToInsert = new List<Visit__c>();

        for (Id beatId : beatToUserMap.keySet()) {

            Id userId = beatToUserMap.get(beatId);
            String key = userId + '-' + beatId;

            if (existingVisitKeys.contains(key)) {
                continue; //Skip duplicate
            }

            visitsToInsert.add(new Visit__c(
                OwnerId = userId,
                Visitor_Name__c = userId,
                Beat__c = beatId,
                Visit_planned_date__c = todayDate,
                Status__c = 'Not Started',
                Visit_Type__c = 'Planned'
            ));
        }

        if (visitsToInsert.isEmpty()) return;

        insert visitsToInsert;

        /* ---------------- Beat → Visit Mapping ---------------- */
        Map<Id, Visit__c> beatToVisitMap = new Map<Id, Visit__c>();
        for (Visit__c v : visitsToInsert) {
            beatToVisitMap.put(v.Beat__c, v);
        }

        /* ---------------- Fetch Retailers ---------------- */
        List<Account> retailers = [
            SELECT Id, Beats_Name__c
            FROM Account
            WHERE Beats_Name__c IN :beatToVisitMap.keySet()
            AND RecordType.Name = 'Retailer'
        ];

        if (retailers.isEmpty()) return;

        /* ---------------- Create Visit Tasks ---------------- */
        List<Visit_Task__c> visitTasks = new List<Visit_Task__c>();

        for (Account ret : retailers) {

            Visit__c relatedVisit = beatToVisitMap.get(ret.Beats_Name__c);
            if (relatedVisit == null) continue;

            visitTasks.add(new Visit_Task__c(
                Visit__c = relatedVisit.Id,
                Retailer__c = ret.Id,
                Account__c = ret.Id,
                Beat__c = ret.Beats_Name__c,
                Visitor_Name__c = relatedVisit.OwnerId,
                Status__c = 'Not Started',
                Visit_Type__c = 'Planned',
                Task_Planned_Date__c = todayDate
            ));
        }

        if (!visitTasks.isEmpty()) {
            insert visitTasks;
        }
    }
}