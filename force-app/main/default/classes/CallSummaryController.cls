public with sharing class CallSummaryController {



    @AuraEnabled(cacheable=true)
    public static CallSummaryWrapper getCallSummary(String filterType) {

        Date today = Date.today();
        Date startDate;
        Date endDate;

        Set<Id> userIds = GetSubOrinates.getSubOrinatesUserIds();

        if (userIds.isEmpty()) {
            return new CallSummaryWrapper();
        }

        if (filterType == 'MTD') {
            startDate = Date.newInstance(today.year(), today.month(), 1);
            endDate = today.addDays(1);
        } else {
            startDate = today;
            endDate = today.addDays(1);
        }

        CallSummaryWrapper wrap = new CallSummaryWrapper();
        List<Id> userIdList = new List<Id>(userIds);
        Integer chunkSize = 2000;

        try {
            for (Integer i = 0; i < userIdList.size(); i += chunkSize) {
                Integer endc = Math.min(i + chunkSize, userIdList.size());
                List<Id> chunk = new List<Id>();
                for (Integer j = i; j < endc; j++) {
                    chunk.add(userIdList[j]);
                }

                // --- SC : Scheduled Calls (aggregate) ---
                AggregateResult[] scRes = [
                    SELECT COUNT(Id) cnt
                    FROM Visit_Task__c
                    WHERE Task_Planned_Date__c >= :startDate
                    AND Task_Planned_Date__c < :endDate
                    AND Visitor_Name__c IN :chunk
                ];
                if (!scRes.isEmpty()) {
                    wrap.sc += (Integer) scRes[0].get('cnt');
                }

                // --- TC : Total Calls (fast estimation using sample ratio) ---
                // Step 1: Count total tasks with a check-in time
                Integer totalWithTime = [
                    SELECT COUNT()
                    FROM Visit_Task__c
                    WHERE Task_Planned_Date__c >= :startDate
                    AND Task_Planned_Date__c < :endDate
                    AND Visitor_Name__c IN :chunk
                    AND Checked_In_Time__c != NULL
                ];

                if (totalWithTime > 0) {
                    // Step 2: Sample up to 2000 records to estimate % with location
                    List<Visit_Task__c> sample = [
                        SELECT Checked_In_Location__c
                        FROM Visit_Task__c
                        WHERE Task_Planned_Date__c >= :startDate
                        AND Task_Planned_Date__c < :endDate
                        AND Visitor_Name__c IN :chunk
                        AND Checked_In_Time__c != NULL
                        LIMIT 2000
                    ];
                    Integer sampleWithLocation = 0;
                    for (Visit_Task__c vt : sample) {
                        if (vt.Checked_In_Location__c != null) sampleWithLocation++;
                    }
                    Double ratio = (sample.size() > 0) ? (sampleWithLocation / (Double) sample.size()) : 0.0;
                    Integer estimatedTC = (Integer) Math.round(totalWithTime * ratio);
                    wrap.tc += estimatedTC;
                }

                // --- PC : Productive Calls (aggregate) ---
                AggregateResult[] pcRes = [
                    SELECT COUNT(Id) cnt
                    FROM Visit_Task__c
                    WHERE Task_Planned_Date__c >= :startDate
                    AND Task_Planned_Date__c < :endDate
                    AND Visitor_Name__c IN :chunk
                    AND Order_Placed__c = true
                ];
                if (!pcRes.isEmpty()) {
                    wrap.pc += (Integer) pcRes[0].get('cnt');
                }

                // --- Net Value (aggregate) ---
                AggregateResult[] netRes = [
                    SELECT SUM(Total_Order_Value__c) total
                    FROM Order__c
                    WHERE RecordType.DeveloperName = 'Secondary_Order'
                    AND Visit_Task__r.Task_Planned_Date__c >= :startDate
                    AND Visit_Task__r.Task_Planned_Date__c < :endDate
                    AND Visit_Task__r.Visitor_Name__c IN :chunk
                    AND Visit_Task__r.Order_Placed__c = true
                ];
                if (!netRes.isEmpty() && netRes[0].get('total') != null) {
                    wrap.netValue += (Decimal) netRes[0].get('total');
                }
            }
        } catch (Exception e) {
            System.debug('Error in getCallSummary: ' + e.getMessage());
        }

        return wrap;
    }



    // Alternative: Use relationship query to avoid checking Checked_In_Location__c in Apex
    @AuraEnabled(cacheable=true)
    public static CallSummaryWrapper getCallSummaryOptimized(String filterType) {

        Date today = Date.today();
        Date startDate;
        Date endDate;

        Set<Id> userIds = GetSubOrinates.getSubOrinatesUserIds();
        
        // If no users, return empty wrapper
        if (userIds.isEmpty()) {
            return new CallSummaryWrapper();
        }

        if (filterType == 'MTD') {
            startDate = Date.newInstance(today.year(), today.month(), 1);
            endDate = today.addDays(1);
        } else {
            startDate = today;
            endDate = today.addDays(1);
        }

        CallSummaryWrapper wrap = new CallSummaryWrapper();
        
        try {
            // Process in chunks to avoid query limits
            List<Id> userIdList = new List<Id>(userIds);
            List<List<Id>> userChunks = new List<List<Id>>();
            List<Id> currentChunk = new List<Id>();
            
            for (Id userId : userIdList) {
                currentChunk.add(userId);
                if (currentChunk.size() == 2000) {
                    userChunks.add(currentChunk);
                    currentChunk = new List<Id>();
                }
            }
            if (!currentChunk.isEmpty()) {
                userChunks.add(currentChunk);
            }
            
            for (List<Id> chunk : userChunks) {
                // Get SC - Scheduled Calls (all visit tasks)
                wrap.sc += Database.countQuery(
                    'SELECT COUNT() FROM Visit_Task__c ' +
                    'WHERE Task_Planned_Date__c >= :startDate ' +
                    'AND Task_Planned_Date__c < :endDate ' +
                    'AND Visitor_Name__c IN :chunk'
                );
                
                // Get TC - Total Calls (with check-in time)
                // We'll use Checked_In_Time__c only since we can't filter on Checked_In_Location__c
                wrap.tc += Database.countQuery(
                    'SELECT COUNT() FROM Visit_Task__c ' +
                    'WHERE Task_Planned_Date__c >= :startDate ' +
                    'AND Task_Planned_Date__c < :endDate ' +
                    'AND Visitor_Name__c IN :chunk ' +
                    'AND Checked_In_Time__c != NULL'
                );
                
                // Get PC - Productive Calls (with orders)
                wrap.pc += Database.countQuery(
                    'SELECT COUNT() FROM Visit_Task__c ' +
                    'WHERE Task_Planned_Date__c >= :startDate ' +
                    'AND Task_Planned_Date__c < :endDate ' +
                    'AND Visitor_Name__c IN :chunk ' +
                    'AND Order_Placed__c = true'
                );
                
                // Get net value
                AggregateResult[] netValueResults = [
                    SELECT SUM(Total_Order_Value__c) netValue
                    FROM Order__c
                    WHERE Visit_Task__r.Task_Planned_Date__c >= :startDate 
                    AND Visit_Task__r.Task_Planned_Date__c < :endDate
                    AND Visit_Task__r.Visitor_Name__c IN :chunk
                    AND Visit_Task__r.Order_Placed__c = true
                    AND RecordType.DeveloperName = 'Secondary_Order'
                ];
                
                if (!netValueResults.isEmpty() && netValueResults[0].get('netValue') != null) {
                    wrap.netValue += (Decimal)netValueResults[0].get('netValue');
                }
            }

        } catch (Exception e) {
            System.debug('Error in getCallSummaryOptimized: ' + e.getMessage() + ' ' + e.getStackTraceString());
            // Return empty wrapper on error
        }

        return wrap;
    }

    // Simple version without checking Checked_In_Location__c (if business logic allows)
    @AuraEnabled(cacheable=true)
    public static CallSummaryWrapper getCallSummarySimple(String filterType) {

        Date today = Date.today();
        Date startDate;
        Date endDate;

        Set<Id> userIds = GetSubOrinates.getSubOrinatesUserIds();
        
        // If no users, return empty wrapper
        if (userIds.isEmpty()) {
            return new CallSummaryWrapper();
        }

        if (filterType == 'MTD') {
            startDate = Date.newInstance(today.year(), today.month(), 1);
            endDate = today.addDays(1);
        } else {
            startDate = today;
            endDate = today.addDays(1);
        }

        CallSummaryWrapper wrap = new CallSummaryWrapper();
        
        try {
            // Get all metrics in single queries (most efficient but may not be accurate for TC)
            
            // SC - Scheduled Calls
            wrap.sc = Database.countQuery(
                'SELECT COUNT() FROM Visit_Task__c ' +
                'WHERE Task_Planned_Date__c >= :startDate ' +
                'AND Task_Planned_Date__c < :endDate ' +
                'AND Visitor_Name__c IN :userIds'
            );
            
            // TC - Total Calls (using Checked_In_Time__c only - business decision)
            wrap.tc = Database.countQuery(
                'SELECT COUNT() FROM Visit_Task__c ' +
                'WHERE Task_Planned_Date__c >= :startDate ' +
                'AND Task_Planned_Date__c < :endDate ' +
                'AND Visitor_Name__c IN :userIds ' +
                'AND Checked_In_Time__c != NULL'
            );
            
            // PC - Productive Calls
            wrap.pc = Database.countQuery(
                'SELECT COUNT() FROM Visit_Task__c ' +
                'WHERE Task_Planned_Date__c >= :startDate ' +
                'AND Task_Planned_Date__c < :endDate ' +
                'AND Visitor_Name__c IN :userIds ' +
                'AND Order_Placed__c = true'
            );
            
            // Net Value
            AggregateResult[] netValueResults = [
                SELECT SUM(Total_Order_Value__c) netValue
                FROM Order__c
                WHERE Visit_Task__r.Task_Planned_Date__c >= :startDate 
                AND Visit_Task__r.Task_Planned_Date__c < :endDate
                AND Visit_Task__r.Visitor_Name__c IN :userIds
                AND Visit_Task__r.Order_Placed__c = true
            ];
            
            if (!netValueResults.isEmpty() && netValueResults[0].get('netValue') != null) {
                wrap.netValue = (Decimal)netValueResults[0].get('netValue');
            }

        } catch (Exception e) {
            System.debug('Error in getCallSummarySimple: ' + e.getMessage() + ' ' + e.getStackTraceString());
            // Return empty wrapper on error
        }

        return wrap;
    }

    public class CallSummaryWrapper {
        @AuraEnabled public Integer tc = 0;
        @AuraEnabled public Integer pc = 0;
        @AuraEnabled public Integer sc = 0;
        @AuraEnabled public Decimal netValue = 0;
    }
}