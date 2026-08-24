public without sharing class MonthlyBeatSchedulerController {

    @AuraEnabled(cacheable=true)
    public static List<User> getActiveUsers() {
        return [
            SELECT Id, Name , Profile.Name
            FROM User
            WHERE IsActive = true AND Profile.Name IN ('SFA Profile','SFA Profile - Light')
            ORDER BY Name
        ];
    }

    /*@AuraEnabled(cacheable=true)
    public static List<Beat__c> getBeatsByUser(Id userId) {
        return [
            SELECT Id, Name
            FROM Beat__c
            WHERE Employee_Name__c = :userId
            ORDER BY Name
        ];
    }*/
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getBeatsByUser(Id userId, Integer month, Integer year) {
        Map<String, Object> result = new Map<String, Object>();
    
        // Active beats for user
        List<Beat__c> beats = [SELECT Id, Name FROM Beat__c WHERE Employee_Name__c = :userId ORDER BY Name];
    
        // Existing monthly plans for this user/month/year
        List<Monthly_Beat_Plan__c> plans = [
            SELECT Id, Name , Date__c, Beat_Name__c , Beat_Name__r.Name
            FROM Monthly_Beat_Plan__c
            WHERE User__c = :userId
              AND CALENDAR_MONTH(Date__c) = :month + 1
              AND CALENDAR_YEAR(Date__c) = :year
              AND IsActive__c = true
        ];
    
        Map<String, Id> existingPlans = new Map<String, Id>();
        for(Monthly_Beat_Plan__c plan : plans) {
            System.debug('Monthly Beat Name:- '  + plan.Name);
            System.debug('Beat Name:- '  + plan.Beat_Name__r.Name);
            System.debug('Date:- '  + plan.Date__c);
            if(plan.Beat_Name__c != null){
                existingPlans.put(String.valueOf(plan.Date__c), plan.Beat_Name__c);
            }
        }
        System.debug('existingPlans:- '  + existingPlans);
    
        result.put('beats', beats);
        result.put('existingPlans', existingPlans);
        return result;
    }
    
    /*@AuraEnabled
    public static void saveMonthlyBeatPlans(
        Id userId,
        Integer month,
        Integer year,
        Map<String, Id> beatSelections
    ) {

        if (userId == null || beatSelections == null || beatSelections.isEmpty()) {
            return;
        }

        // Fetch beat names
        Map<Id, Beat__c> beatMap = new Map<Id, Beat__c>([
            SELECT Id, Name
            FROM Beat__c
            WHERE Id IN :beatSelections.values()
        ]);

        List<Monthly_Beat_Plan__c> plans = new List<Monthly_Beat_Plan__c>();

        for (String dateStr : beatSelections.keySet()) {
            Id beatId = beatSelections.get(dateStr);
            if (!beatMap.containsKey(beatId)) continue;

            Date beatDate = Date.valueOf(dateStr);
            Beat__c beat = beatMap.get(beatId);

            Monthly_Beat_Plan__c plan = new Monthly_Beat_Plan__c();
            plan.Name = getMonthName(month) + ' - ' + beat.Name;
            plan.User__c = userId;
            plan.Beat_Name__c = beatId;
            plan.Date__c = beatDate;
            plan.Month__c = getMonthName(month);
            plan.Year__c = String.valueOf(year);
            plan.IsActive__c = true;
            plan.OwnerId = userId;

            plans.add(plan);
        }

        if (!plans.isEmpty()) {
            insert plans;
        }
    }*/
    
    @AuraEnabled
    public static void saveMonthlyBeatPlans(
        Id userId,
        Integer month,
        Integer year,
        Map<String, Id> beatSelections
    ) {
        if (userId == null) {
            return;
        }
    
        /* ---------------- Fetch existing plans ---------------- */
        Map<Date, Monthly_Beat_Plan__c> existingPlanByDate = new Map<Date, Monthly_Beat_Plan__c>();
    
        List<Monthly_Beat_Plan__c> existingPlans = [
            SELECT Id, Date__c, Beat_Name__c, IsActive__c
            FROM Monthly_Beat_Plan__c
            WHERE User__c = :userId
              AND CALENDAR_MONTH(Date__c) = :month + 1
              AND CALENDAR_YEAR(Date__c) = :year
              AND IsActive__c = true
        ];
    
        for (Monthly_Beat_Plan__c plan : existingPlans) {
            existingPlanByDate.put(plan.Date__c, plan);
        }
    
        /* ---------------- Fetch beats ---------------- */
        Set<Id> beatIds = new Set<Id>();
        if (beatSelections != null) {
            beatIds.addAll(beatSelections.values());
        }
    
        Map<Id, Beat__c> beatMap = beatIds.isEmpty()
            ? new Map<Id, Beat__c>()
            : new Map<Id, Beat__c>([
                SELECT Id, Name
                FROM Beat__c
                WHERE Id IN :beatIds
            ]);
    
        List<Monthly_Beat_Plan__c> recordsToUpdate = new List<Monthly_Beat_Plan__c>();
        List<Monthly_Beat_Plan__c> recordsToInsert = new List<Monthly_Beat_Plan__c>();
    
        /* ---------------- Handle inserts & updates ---------------- */
        if (beatSelections != null) {
            for (String dateStr : beatSelections.keySet()) {
                Date beatDate = Date.valueOf(dateStr);
                Id beatId = beatSelections.get(dateStr);
    
                if (!beatMap.containsKey(beatId)) continue;
    
                Beat__c beat = beatMap.get(beatId);
    
                // Existing record → update if changed
                if (existingPlanByDate.containsKey(beatDate)) {
                    Monthly_Beat_Plan__c plan = existingPlanByDate.get(beatDate);
    
                    if (plan.Beat_Name__c != beatId) {
                        plan.Beat_Name__c = beatId;
                        plan.Name = getMonthName(month) + ' - ' + beat.Name;
                        plan.IsActive__c = true;
                        recordsToUpdate.add(plan);
                    }
                }
                // New record → insert
                else {
                    Monthly_Beat_Plan__c plan = new Monthly_Beat_Plan__c();
                    plan.Name = getMonthName(month) + ' - ' + beat.Name;
                    plan.User__c = userId;
                    plan.Beat_Name__c = beatId;
                    plan.Date__c = beatDate;
                    plan.Month__c = getMonthName(month);
                    plan.Year__c = String.valueOf(year);
                    plan.IsActive__c = true;
                    plan.OwnerId = userId;
    
                    recordsToInsert.add(plan);
                }
            }
        }
    
        /* ---------------- Handle NONE selection (Deactivate removed dates) ---------------- */
        for (Date existingDate : existingPlanByDate.keySet()) {
    
            // If date NOT sent from UI → user selected "None"
            if (beatSelections == null || !beatSelections.containsKey(String.valueOf(existingDate))) {
                Monthly_Beat_Plan__c plan = existingPlanByDate.get(existingDate);
    
                plan.IsActive__c = false;
                plan.Beat_Name__c = null;
    
                recordsToUpdate.add(plan);
            }
        }
    
        /* ---------------- DML ---------------- */
        if (!recordsToInsert.isEmpty()) {
            insert recordsToInsert;
        }
    
        if (!recordsToUpdate.isEmpty()) {
            update recordsToUpdate;
        }
    }

    /* ---------------- Helpers ---------------- */
    private static String getMonthName(Integer month) {
        List<String> months = new List<String>{
            'January','February','March','April','May','June',
            'July','August','September','October','November','December'
        };
        return months[month];
    }
}