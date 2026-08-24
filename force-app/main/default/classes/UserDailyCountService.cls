public without sharing class UserDailyCountService {

    public class UserDailySummary {

        @AuraEnabled public String userId;

        @AuraEnabled public Integer retailCount;

        @AuraEnabled public Integer officialCount;

        @AuraEnabled public Integer leaveCount;

        @AuraEnabled public Decimal orderValue;

        @AuraEnabled public String beatName;

        @AuraEnabled public String retailerAddress;

        @AuraEnabled public Integer totalUsers;

    }

  @AuraEnabled(cacheable=true)

public static List<UserDailySummary> getUserCounts(List<String> userIds) {

    System.debug('=== getUserCounts CALLED WITH userIds === ' + userIds);

    if (userIds == null || userIds.isEmpty()) {

        System.debug('userIds is NULL or EMPTY. Returning empty list.');

        return new List<UserDailySummary>();

    }

    // Convert incoming IDs

    Set<Id> requested = new Set<Id>();

    for (String s : userIds) {

        try {

            requested.add((Id)s);

        } catch (Exception e) {

            System.debug('INVALID USER ID SKIPPED: ' + s);

        }

    }

    if (requested.isEmpty()) {

        System.debug('No valid IDs found. Returning empty list.');

        return new List<UserDailySummary>();

    }

    Date today = Date.today();

    System.debug('Today: ' + today);

    // ===== STEP 1: Gather ALL relevant user IDs (requested + all subordinates) =====

    Map<Id, Id> userRoleMap = new Map<Id, Id>();

    List<User> requestedUsers = [

        SELECT Id, UserRoleId 

        FROM User 

        WHERE Id IN :requested 

        AND UserType = 'Standard'

    ];

    for (User u : requestedUsers) {

        userRoleMap.put(u.Id, u.UserRoleId);

    }

    // Build parent → children role map (for entire org)

    Map<Id, List<Id>> parentToChildren = new Map<Id, List<Id>>();

    for (UserRole r : [SELECT Id, ParentRoleId FROM UserRole]) {

        Id p = r.ParentRoleId;

        if (!parentToChildren.containsKey(p)) parentToChildren.put(p, new List<Id>());

        parentToChildren.get(p).add(r.Id);

    }

    // Collect all subordinate users for each requested parent

    Set<Id> allRelevantUserIds = new Set<Id>();

    allRelevantUserIds.addAll(requested);

    // Map: parentId → Set<Id> of all subordinate user IDs (excluding parent)

    Map<Id, Set<Id>> parentToSubordinates = new Map<Id, Set<Id>>();

    // Get all active standard users once (to avoid repeated queries)

    Map<Id, User> allUsersMap = new Map<Id, User>(

        [SELECT Id, UserRoleId FROM User WHERE IsActive = true AND UserType = 'Standard']

    );

    for (Id parentId : requested) {

        Id parentRole = userRoleMap.get(parentId);

        Set<Id> childRoles = new Set<Id>();

        if (parentRole != null) {

            childRoles.addAll(collectChildRoles(parentRole, parentToChildren));

        }

        Set<Id> subs = new Set<Id>();

        for (User u : allUsersMap.values()) {

            if (u.UserRoleId != null && childRoles.contains(u.UserRoleId)) {

                subs.add(u.Id);

            }

        }

        subs.remove(parentId);  // exclude self

        parentToSubordinates.put(parentId, subs);

        allRelevantUserIds.addAll(subs);

    }

    System.debug('All relevant user IDs count: ' + allRelevantUserIds.size());

    // ===== STEP 2: Initialize summary map for ALL relevant users =====

    Map<Id, UserDailySummary> summaryMap = new Map<Id, UserDailySummary>();

    for (Id uId : allRelevantUserIds) {

        UserDailySummary s = new UserDailySummary();

        s.userId = uId;

        s.retailCount = 0;

        s.officialCount = 0;

        s.leaveCount = 0;

        s.orderValue = 0;

        s.totalUsers = 0;

        s.beatName = null;

        s.retailerAddress = null;

        summaryMap.put(uId, s);

    }

    // ===== STEP 3: Query Visit counts and beat =====

    for (AggregateResult ar : [

        SELECT Visitor_Name__r.Id uid, COUNT(Id) cnt, MIN(Beat__r.Name) beat

        FROM Visit__c

        WHERE Visitor_Name__r.Id IN :allRelevantUserIds

        AND Visit_planned_date__c = :today

        GROUP BY Visitor_Name__r.Id

    ]) {

        Id uid = (Id) ar.get('uid');

        Integer cnt = ((Long) ar.get('cnt')).intValue();

        String beat = (String) ar.get('beat');

        if (summaryMap.containsKey(uid)) {

            summaryMap.get(uid).retailCount = cnt;

            summaryMap.get(uid).beatName = beat;

        }

    }

    // ===== STEP 4: Query Order Value =====

    for (AggregateResult ar : [

        SELECT Visit_Task__r.Visitor_Name__c uid, SUM(Total_Order_Value__c) val

        FROM Order__c

        WHERE Visit_Task__r.Visitor_Name__c IN :allRelevantUserIds

        AND Visit_Task__r.Task_Planned_Date__c = :today 

        AND RecordType.DeveloperName = 'Secondary_Order'

        AND Visit_Task__r.Order_Placed__c = true

        GROUP BY Visit_Task__r.Visitor_Name__c

    ]) {

        Id uid = (Id) ar.get('uid');

        Decimal val = (Decimal) ar.get('val');

        if (summaryMap.containsKey(uid)) {

            summaryMap.get(uid).orderValue = val != null ? val : 0;

        }

    }

    // ===== STEP 5: Query Attendance (Leave / Official) =====

    for (AggregateResult ar : [

        SELECT User__r.Id uid, Status__c status, Work__c work, COUNT(Id) cnt

        FROM Attendance__c

        WHERE User__r.Id IN :allRelevantUserIds

        AND Date__c = :today

        GROUP BY User__r.Id, Status__c, Work__c

    ]) {

        Id uid = (Id) ar.get('uid');

        Integer cnt = ((Long) ar.get('cnt')).intValue();

        String status = (String) ar.get('status');

        String work = (String) ar.get('work');

        if (!summaryMap.containsKey(uid)) continue;

        if ('Leave'.equalsIgnoreCase(status)) summaryMap.get(uid).leaveCount = cnt;

        if ('Official Meeting'.equalsIgnoreCase(work)) summaryMap.get(uid).officialCount = cnt;

    }

    // ===== STEP 6: Retailer Address (In-Progress Visit Tasks) =====

    for (Visit__c v : [

        SELECT Id, Visitor_Name__r.Id,

            (SELECT Retailer_Address_New__c FROM Visit_Tasks__r WHERE Status__c='In-Progress' LIMIT 1)

        FROM Visit__c

        WHERE Visitor_Name__r.Id IN :allRelevantUserIds

        AND Visit_Planned_Date__c = :today

    ]) {

        if (v.Visit_Tasks__r != null && !v.Visit_Tasks__r.isEmpty()) {

            String addr = v.Visit_Tasks__r[0].Retailer_Address_New__c;

            if (!String.isBlank(addr) && summaryMap.containsKey(v.Visitor_Name__r.Id)) {

                summaryMap.get(v.Visitor_Name__r.Id).retailerAddress = addr;

            }

        }

    }

    // ===== STEP 7: Aggregate subordinate counts for each requested parent =====

    for (Id parentId : requested) {

        Set<Id> subIds = parentToSubordinates.get(parentId);

        if (subIds == null || subIds.isEmpty()) continue;

        Integer totalRetail = 0;

        Integer totalOfficial = 0;

        Integer totalLeave = 0;

        Decimal totalOrder = 0;

        for (Id subId : subIds) {

            UserDailySummary subSum = summaryMap.get(subId);

            if (subSum != null) {

                totalRetail   += subSum.retailCount;

                totalOfficial += subSum.officialCount;

                totalLeave    += subSum.leaveCount;

                totalOrder    += subSum.orderValue;

            }

        }

        UserDailySummary parentSum = summaryMap.get(parentId);

        if (parentSum != null) {

            parentSum.totalUsers     = subIds.size();

            parentSum.retailCount   += totalRetail;

            parentSum.officialCount += totalOfficial;

            parentSum.leaveCount    += totalLeave;

            parentSum.orderValue    += totalOrder;

        }

    }

    // ===== STEP 8: Build result (only for originally requested IDs) =====

    List<UserDailySummary> result = new List<UserDailySummary>();

    for (Id reqId : requested) {

        UserDailySummary s = summaryMap.get(reqId);

        if (s != null) result.add(s);

    }

    System.debug('RETURNING ' + result.size() + ' UserDailySummary rows');

    return result;

}  

    // Helper: collect child roles recursively

    private static Set<Id> collectChildRoles(Id parentRoleId, Map<Id, List<Id>> parentToChildren) {

        Set<Id> result = new Set<Id>();

        if (parentRoleId == null) return result;

        List<Id> direct = parentToChildren.get(parentRoleId);

        if (direct == null) return result;

        for (Id child : direct) {

            if (!result.contains(child)) {

                result.add(child);

                result.addAll(collectChildRoles(child, parentToChildren));

            }

        }

        return result;

    }


    // Timeline code remains exactly the same

    @AuraEnabled

    public static TimelineWrapper getTodayTimeline(String userId) {

        TimelineWrapper tw = new TimelineWrapper();

        tw.timeline = new List<Checkpoint>();

        tw.beatName = 'No Beat Assigned';

        System.debug('getTodayTimeline START userId=' + userId);

        if (String.isBlank(userId)) {

            tw.timeline.add(new Checkpoint('Day Start', 'N/A', null, new List<String>()));

            System.debug('getTodayTimeline END -> no userId');

            return tw;

        }

        Date today = Date.today();

        try {

            List<Visit__c> visits = [

                SELECT Id, Name, Checked_In_Time__c, Checked_Out_Time__c, Beat__c,Visitor_Name__c,Beat__r.Name,

                (SELECT Id, Name, Checked_In_Time__c, Checked_Out_Time__c, Retailer__c, Retailer__r.Name

                 FROM Visit_Tasks__r WHERE Checked_In_Time__c != null

                 ORDER BY Checked_In_Time__c ASC NULLS LAST)

                FROM Visit__c

                WHERE Visitor_Name__c = :userId

                AND Visit_planned_date__c = :today

                ORDER BY Checked_In_Time__c ASC NULLS LAST

            ];

            Datetime earliestTaskDT = null;

            Id earliestVisitId;

            String debugTasks = '';

            for (Visit__c v : visits) {

                if (v.Visit_Tasks__r != null) {

                    for (SObject sObj : v.Visit_Tasks__r) {

                        Visit_Task__c vt = (Visit_Task__c) sObj;

                        if (vt.Checked_In_Time__c != null) {

                            if (earliestTaskDT == null || vt.Checked_In_Time__c < earliestTaskDT) {

                                earliestTaskDT = vt.Checked_In_Time__c;

                                earliestVisitId = v.Id;

                            }

                            debugTasks += 'T(' + vt.Id + ':' + vt.Checked_In_Time__c + '),';

                        }

                    }

                }

            }

            String dayStartTime;

            /*if (earliestTaskDT != null) {

                dayStartTime = formatTimeToHHmm(earliestTaskDT);

            } else {

                List<Attendance__c> atts = [

                    SELECT CreatedDate

                    FROM Attendance__c

                    WHERE User__c = :userId

                    AND Date__c = :today

                    ORDER BY CreatedDate ASC

                    LIMIT 1

                ];

                dayStartTime = !atts.isEmpty() ? formatTimeToHHmm(atts[0].CreatedDate) : 'N/A';

            }*/
 
            List<Attendance__c> atts = [

                    SELECT CreatedDate

                    FROM Attendance__c

                    WHERE User__c = :userId

                    AND Date__c = :today

                    ORDER BY CreatedDate ASC

                    LIMIT 1

                ];

                if (!atts.isEmpty()) {

    dayStartTime = formatTimeToHHmm(atts[0].CreatedDate);

}

               else if(earliestTaskDT != null){

                 dayStartTime = formatTimeToHHmm(earliestTaskDT);

               }

            tw.timeline.add(new Checkpoint('Day Start', dayStartTime, null, new List<String>()));

            if (!visits.isEmpty()) {

                tw.beatName = (visits[0].Beat__r != null && visits[0].Beat__r.Name != null) 

                    ? visits[0].Beat__r.Name 

                    : 'No Beat Assigned';

            }

            for (Visit__c v : visits) {

                if (v.Visit_Tasks__r == null || v.Visit_Tasks__r.isEmpty()) continue;

                for (Visit_Task__c vt : v.Visit_Tasks__r) {

                    String retailerName = (vt.Retailer__r != null && vt.Retailer__r.Name != null) 

                        ? vt.Retailer__r.Name 

                        : 'Unknown Retailer';

                    String checkInStr = vt.Checked_In_Time__c != null 

                        ? formatTimeToHHmm(vt.Checked_In_Time__c) 

                        : v.Checked_In_Time__c != null 

                            ? formatTimeToHHmm(v.Checked_In_Time__c) 

                            : 'N/A';

                    String checkOutStr = vt.Checked_Out_Time__c != null 

                        ? formatTimeToHHmm(vt.Checked_Out_Time__c) 

                        : 'N/A';

                    String stepTime = 'Check-In: ' + checkInStr + ' , Check-Out: ' + checkOutStr;

                    List<String> tks = vt.Name != null ? new List<String>{vt.Name} : new List<String>();

                    tw.timeline.add(new Checkpoint('Visit Task', stepTime, retailerName, tks));

                }

            }

            return tw;

        } catch (Exception ex) {

            tw.timeline.add(new Checkpoint('Day Start', 'N/A', null, new List<String>()));

            return tw;

        }

    }

    public class TimelineWrapper {

        @AuraEnabled public String beatName;

        @AuraEnabled public List<Checkpoint> timeline;

    }

    public class Checkpoint {

        @AuraEnabled public String stepName;

        @AuraEnabled public String stepTime;

        @AuraEnabled public String visitName;

        @AuraEnabled public List<String> tasks;

        public Checkpoint(String s, String t, String vName, List<String> tks) {

            stepName = s;

            stepTime = t;

            visitName = vName;

            tasks = (tks != null) ? tks : new List<String>();

        }

    }

    public static String formatTimeToHHmm(Datetime dt) {

        if (dt == null) return 'N/A';

        try {

            return dt.format('HH:mm');

        } catch (Exception e) {

            String s = String.valueOf(dt);

            if (s.contains('T')) {

                Integer spaceIdx = s.indexOf(' ');

                if (spaceIdx > 0 && s.length() >= spaceIdx + 6) {

                    return s.substring(spaceIdx+1, spaceIdx+6);

                }

            }

            return s;

        }

    }

    @AuraEnabled(cacheable=false)

    public static Map<String, Object> getMTDCounts(Id userId) {

        Date today = Date.today();

        Date monthStart = today.toStartOfMonth();

        Date yesterday = today.addDays(-1); 

        Integer retailCount = 0;

        Integer officialCount = 0;

        Integer leaveCount = 0;

        Decimal totalRetailMinutes = 0;

        Decimal totalVisitTotalMinutes = 0;

        Map<String, Object> result = new Map<String, Object>();

        try {

            retailCount = [SELECT count() FROM Visit__c WHERE Visitor_Name__c = :userId AND Visit_Planned_Date__c >= :monthStart AND Visit_Planned_Date__c <= :today];

        } catch (Exception ex) {

            System.debug('getMTDCounts - Visit query error: ' + ex);

        }

        try {

            leaveCount = [SELECT count() FROM Attendance__c WHERE User__c = :userId AND Status__c = 'Leave' AND Date__c >= :monthStart AND Date__c <= :today];

        } catch (Exception ex) {

            System.debug('getMTDCounts - Leave query error: ' + ex);

        }

        try {

            officialCount = [SELECT count() FROM Attendance__c WHERE User__c = :userId AND Work__c = 'Official Meeting' AND Date__c >= :monthStart AND Date__c <= :today];

        } catch (Exception ex) {

            System.debug('getMTDCounts - Official query error: ' + ex);

        }

        List<Visit__c> visits = [SELECT Id, Total_Check_In_and_Check_Out_Time__c FROM Visit__c WHERE Visitor_Name__c = :userId AND Visit_Planned_Date__c >= :monthStart 

                                 AND Visit_Planned_Date__c <= :today ORDER BY Visit_Planned_Date__c DESC];


        for (Visit__c v : visits) {

            if (v.Total_Check_In_and_Check_Out_Time__c != null) {

                totalRetailMinutes += v.Total_Check_In_and_Check_Out_Time__c;

            }

        }

        Decimal avgRetailMinutes = retailCount > 0 ? totalRetailMinutes / retailCount : 0;

        Decimal avgRetailHours = convertMinutesToHoursDecimal(avgRetailMinutes);

        List<AggregateResult> taskAgg = [SELECT Visit__c visitId, MIN(Checked_In_Time__c) earliestCheckIn, MAX(Checked_out_Time__c) latestCheckOut

                                         FROM Visit_Task__c WHERE Visit__c IN :visits GROUP BY Visit__c];

        Integer totalMinutes = 0;

        Integer validVisitCount = 0;

        for (AggregateResult ar : taskAgg) {

            Datetime firstCheckin = (Datetime) ar.get('earliestCheckIn');

            Datetime lastCheckout = (Datetime) ar.get('latestCheckOut');

            if (firstCheckin != null && lastCheckout != null) {

                Integer diff = Integer.valueOf((lastCheckout.getTime() - firstCheckin.getTime()) / (1000 * 60));

                totalMinutes += diff;

                validVisitCount++;

            }

        }

        //Decimal avgTotalMinutes = validVisitCount > 0 ? totalMinutes / validVisitCount : 0;

        //Decimal avgTotalHours = convertMinutesToHoursDecimal(avgTotalMinutes);

        Decimal avgTotalMinutes = validVisitCount > 0 ? 

            (Decimal.valueOf(totalMinutes) / Decimal.valueOf(validVisitCount)) 

            : 0;

        Decimal avgTotalHours = convertMinutesToHoursDecimal(avgTotalMinutes);

        System.debug('totalMinutes = ' + totalMinutes);

        System.debug('avgTotalMinutes = ' + avgTotalMinutes);

        System.debug('avgTotalHours = ' + avgTotalHours);

        // First, get the MTD visits

        List<Visit__c> mtdvisits = [

            SELECT Id, Beat__c, Beat__r.Name, Visit_Planned_Date__c,

            (SELECT Id, Retailer_Address_New__c, Status__c, Checked_In_Time__c, Checked_Out_Time__c

             FROM Visit_Tasks__r WHERE Checked_In_Time__c != null AND Checked_Out_Time__c != null

             ORDER BY Checked_In_Time__c ASC)

            FROM Visit__c

            WHERE Visitor_Name__c = :userId

            AND Visit_Planned_Date__c >= :monthStart 

            AND Visit_Planned_Date__c <= :today

            ORDER BY Visit_Planned_Date__c DESC

        ];

        List<Map<String, Object>> finalVisitList = new List<Map<String, Object>>();

        for (Visit__c v : mtdvisits) {

            Integer displayHours = 0;

            Integer displayMinutes = 0;

            String totalHoursStr = '0.00';

            Map<String, Object> row = new Map<String, Object>();

            if (v.Visit_Tasks__r != null && !v.Visit_Tasks__r.isEmpty()) {

                Visit_Task__c firstTask = v.Visit_Tasks__r[0];

                Visit_Task__c lastTask  = v.Visit_Tasks__r[v.Visit_Tasks__r.size() - 1];

                Datetime checkIn  = firstTask.Checked_In_Time__c;

                Datetime checkOut = lastTask.Checked_Out_Time__c;

                if (checkIn != null && checkOut != null && checkOut > checkIn) {

                    Long diffMs = checkOut.getTime() - checkIn.getTime();

                    Integer diffMinutes = (Integer)(diffMs / (1000 * 60));

                    displayHours = diffMinutes / 60;

                    displayMinutes = diffMinutes - (displayHours * 60);

                    // Format as H.MM

                    totalHoursStr = displayHours + '.' + 

                        (displayMinutes < 10 ? '0' + String.valueOf(displayMinutes) : String.valueOf(displayMinutes));
 
                }

            }

            Datetime dt = Datetime.newInstance(v.Visit_Planned_Date__c, Time.newInstance(0,0,0,0));

            String formattedDate = dt.format('EEEE, dd-MMM-yyyy');

            String label = (v.Visit_Planned_Date__c == yesterday) ? 'Yesterday' : '';

            String retailerAddress = '';

            if (v.Visit_Tasks__r != null && !v.Visit_Tasks__r.isEmpty()) {

                retailerAddress = v.Visit_Tasks__r[0].Retailer_Address_New__c;

            }

            row.put('Id', v.Id);

            row.put('VisitDate', formattedDate);

            row.put('totalHours', totalHoursStr + ' HOURS');

            row.put('yesterdayLabel', label);

            row.put('BeatName', v.Beat__r != null ? v.Beat__r.Name : '');

            row.put('retailerAddress', retailerAddress);

            finalVisitList.add(row);

        }


        System.debug('finalVisitList = ' + JSON.serialize(finalVisitList));

        // Map<String, Integer> result = new Map<String, Integer>();

        result.put('retailingCount', retailCount);

        result.put('officialCount', officialCount);

        result.put('leaveCount', leaveCount);

        result.put('avgRetailingHours', avgRetailHours);

        result.put('avgTotalHours', avgTotalHours);

        result.put('mtdVisits', JSON.serialize(finalVisitList)); 

        return result;

    }

    public static Decimal convertMinutesToHoursDecimal(Decimal minutes) {

        if (minutes == null) return 0;

        // Round minutes to integer

        Integer totalMins = Integer.valueOf(Math.round(minutes));

        // Calculate hours and leftover minutes

        Integer hrs = totalMins / 60;

        Integer mins = totalMins - (hrs * 60);

        // Convert to decimal format HH.MM

        Decimal hhmm = Decimal.valueOf(hrs) + (Decimal.valueOf(mins) / 100);

        return hhmm;

    }

    @AuraEnabled(cacheable=true)

    public static List<String> getEmployeeRoles() {

        List<String> roles = new List<String>();

        Schema.DescribeFieldResult fieldResult = User.Employee_Role__c.getDescribe();

        System.debug('Field picklist values: ' + fieldResult.getPicklistValues());

        for (Schema.PicklistEntry entry : fieldResult.getPicklistValues()) {

            roles.add(entry.getValue());

        }

        return roles;

    }


}