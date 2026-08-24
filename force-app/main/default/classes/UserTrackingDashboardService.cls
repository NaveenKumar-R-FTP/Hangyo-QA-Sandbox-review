/**
 * Aggregates Attendance__c, Visit_Task__c, Order__c, and Account into a unified
 * tracking timeline for the User Tracking Dashboard (no User_Location__c).
 */
public with sharing class UserTrackingDashboardService {
    private static final String ACT_ATTENDANCE = 'Attendance';
    private static final String ACT_EOD = 'EOD';
    private static final String ACT_PRODUCTIVE = 'Productive Outlet';
    private static final String ACT_NON_PRODUCTIVE = 'Non Productive Outlet';
    private static final String ACT_NEW_OUTLET = 'New Outlet';
    private static final String RETAILER_RECORD_TYPE_NAME = 'Retailer';

    // ----------------------------
    // DTOs
    // ----------------------------

    public class UserOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;

        public UserOption(Id id, String name) {
            this.id = id;
            this.name = name;
        }
    }

    public class DashboardSummary {
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;

        @AuraEnabled public Integer totalProductiveOutlets = 0;
        @AuraEnabled public Integer totalNonProductiveOutlets = 0;
        @AuraEnabled public Integer totalVisitedOutlets = 0;

        @AuraEnabled public Decimal totalOrderValue = 0;

        @AuraEnabled public Integer attendanceCount = 0;
        @AuraEnabled public Integer eodCount = 0;

        @AuraEnabled public Integer newOutletAdded = 0;

        /** Rows in the calendar day before attendance lifecycle filter (for UX). */
        @AuraEnabled public Integer rawRowCount = 0;
    }

    public class TrackingActivityDTO {
        @AuraEnabled public Decimal latitude;
        @AuraEnabled public Decimal longitude;
        @AuraEnabled public String activityType;
        @AuraEnabled public Datetime sortTime;
        @AuraEnabled public Id outletId;
        @AuraEnabled public String outletName;
        @AuraEnabled public Datetime checkInTime;
        @AuraEnabled public Datetime checkOutTime;
        @AuraEnabled public Decimal orderValue;
        @AuraEnabled public Datetime attendanceAppliedOn;
        /** Attendance marker info window: Status__c */
        @AuraEnabled public String attendanceStatus;
        /** Attendance marker info window: Description__c, or lat/lng if description blank (no "GPS:" label). */
        @AuraEnabled public String attendanceLocationDetail;
        /** EOD marker info window: EOD_Date_Time__c */
        @AuraEnabled public Datetime eodDateTime;
        /** EOD marker info window: coordinates from EOD_Location__ */
        @AuraEnabled public String eodLocationDetail;
        /** New outlet marker info window: Account.Onboard_Date__c */
        @AuraEnabled public Date onboardDate;
        /** New outlet marker info window: Account.Latitude__c, Longitude__c */
        @AuraEnabled public String newOutletLocationDetail;
        @AuraEnabled public String sourceType;
        @AuraEnabled public Id sourceId;
    }

    public class TrackingDashboardResponse {
        @AuraEnabled public DashboardSummary summary;
        @AuraEnabled public List<TrackingActivityDTO> activities;
    }

    // ----------------------------
    // Public API
    // ----------------------------

    @AuraEnabled(cacheable=true)
    public static List<UserOption> getUsers() {
        UserTrackingController.assertDashboardAccessAllowed(); 
        Map<Id, UserOption> byId = new Map<Id, UserOption>();

        for (AggregateResult ar : [
            SELECT User__c userId, MAX(User__r.Name) userName
            FROM Attendance__c
            WHERE User__c != NULL
            GROUP BY User__c
            ORDER BY MAX(User__r.Name)
        ]) {
            Id uid = (Id) ar.get('userId');
            byId.put(uid, new UserOption(uid, (String) ar.get('userName')));
        }

        for (AggregateResult ar : [
            SELECT Visitor_Name__c userId, MAX(Visitor_Name__r.Name) userName
            FROM Visit_Task__c
            WHERE Visitor_Name__c != NULL
            GROUP BY Visitor_Name__c
            ORDER BY MAX(Visitor_Name__r.Name)
        ]) {
            Id uid = (Id) ar.get('userId');
            if (!byId.containsKey(uid)) {
                byId.put(uid, new UserOption(uid, (String) ar.get('userName')));
            }
        }

        List<UserOption> sorted = new List<UserOption>(byId.values());
        sorted.sort(new UserOptionNameComparator());
        return sorted;
    }

    @AuraEnabled
    public static TrackingDashboardResponse getDashboardData(Id userId, Date selectedDate) {
        UserTrackingController.assertDashboardAccessAllowed();
        validateInputs(userId, selectedDate);

        DateTime dayStart = DateTime.newInstance(selectedDate, Time.newInstance(0, 0, 0, 0));
        DateTime dayEndExclusive = dayStart.addDays(1);

        List<TrackingActivityDTO> rawActivities = new List<TrackingActivityDTO>();
        rawActivities.addAll(buildAttendanceActivities(userId, selectedDate));
        rawActivities.addAll(buildVisitActivities(userId, selectedDate));
        rawActivities.addAll(buildNewOutletActivities(userId, dayStart, dayEndExclusive));

        Map<Id, Decimal> orderByVisitTask = loadOrderTotalsByVisitTask(userId, selectedDate, rawActivities);
        applyOrderValuesToVisits(rawActivities, orderByVisitTask);

        Integer newOutletCount = countNewOutletsForDay(userId, dayStart, dayEndExclusive);
        DashboardSummary summary = buildSummary(userId, rawActivities, newOutletCount);

        List<TrackingActivityDTO> lifecycleActivities = filterFromFirstAttendance(
            activitiesForMap(rawActivities)
        );
        summary.rawRowCount = rawActivities.size();

        TrackingDashboardResponse resp = new TrackingDashboardResponse();
        resp.summary = summary;
        resp.activities = lifecycleActivities;
        return resp;
    }

    // ----------------------------
    // Data loaders
    // ----------------------------

    private static List<TrackingActivityDTO> buildAttendanceActivities(Id userId, Date selectedDate) {
        List<TrackingActivityDTO> out = new List<TrackingActivityDTO>();

        List<Attendance__c> rows = [
            SELECT
                Id,
                Location__Latitude__s,
                Location__Longitude__s,
                Attendance_Applied_on__c,
                Date_of_attendance__c,
                CreatedDate,
                User__c,
                Status__c,
                Description__c,
                EOD_Date_Time__c,
                EOD_Location__Latitude__s,
                EOD_Location__Longitude__s
            FROM Attendance__c
            WHERE User__c = :userId
              AND Date_of_attendance__c = :selectedDate
            ORDER BY CreatedDate ASC
        ];

        for (Attendance__c a : rows) {
            TrackingActivityDTO dto = new TrackingActivityDTO();
            dto.sourceType = 'Attendance';
            dto.sourceId = a.Id;
            dto.activityType = ACT_ATTENDANCE;
            dto.attendanceStatus = a.Status__c;
            dto.attendanceLocationDetail = buildAttendanceLocationDetail(a);
            dto.attendanceAppliedOn = a.Attendance_Applied_on__c != null
                ? a.Attendance_Applied_on__c
                : DateTime.newInstance(a.Date_of_attendance__c, Time.newInstance(0, 0, 0, 0));
            dto.sortTime = resolveSortTime(
                a.Attendance_Applied_on__c != null ? a.Attendance_Applied_on__c : a.Date_of_attendance__c,
                a.CreatedDate
            );
            dto.latitude = a.Location__Latitude__s;
            dto.longitude = a.Location__Longitude__s;
            out.add(dto);
            appendEodActivityIfPresent(a, out);
        }
        return out;
    }

    private static void appendEodActivityIfPresent(Attendance__c a, List<TrackingActivityDTO> out) {
        if (a == null || out == null || a.EOD_Date_Time__c == null) {
            return;
        }
        if (a.EOD_Location__Latitude__s == null || a.EOD_Location__Longitude__s == null) {
            return;
        }
        TrackingActivityDTO eodDto = new TrackingActivityDTO();
        eodDto.sourceType = 'Attendance_EOD';
        eodDto.sourceId = a.Id;
        eodDto.activityType = ACT_EOD;
        eodDto.eodDateTime = a.EOD_Date_Time__c;
        eodDto.eodLocationDetail = buildEodLocationDetail(a);
        eodDto.sortTime = a.EOD_Date_Time__c;
        eodDto.latitude = a.EOD_Location__Latitude__s;
        eodDto.longitude = a.EOD_Location__Longitude__s;
        out.add(eodDto);
    }

    private static String buildEodLocationDetail(Attendance__c a) {
        if (a == null) {
            return null;
        }
        if (a.EOD_Location__Latitude__s != null && a.EOD_Location__Longitude__s != null) {
            return String.valueOf(a.EOD_Location__Latitude__s.setScale(6, System.RoundingMode.HALF_UP)) +
                ', ' +
                String.valueOf(a.EOD_Location__Longitude__s.setScale(6, System.RoundingMode.HALF_UP));
        }
        return null;
    }

    private static String buildNewOutletLocationDetail(Account acc) {
        if (acc == null) {
            return null;
        }
        return formatAccountLatLongForDisplay(acc.Latitude__c, acc.Longitude__c);
    }

    /** Account Latitude__c / Longitude__c are text in org — parse when numeric, else show as stored. */
    private static String formatAccountLatLongForDisplay(String latitude, String longitude) {
        if (String.isBlank(latitude) || String.isBlank(longitude)) {
            return null;
        }
        String latTrim = latitude.trim();
        String lngTrim = longitude.trim();
        try {
            Decimal latD = Decimal.valueOf(latTrim);
            Decimal lngD = Decimal.valueOf(lngTrim);
            return String.valueOf(latD.setScale(6, System.RoundingMode.HALF_UP)) +
                ', ' +
                String.valueOf(lngD.setScale(6, System.RoundingMode.HALF_UP));
        } catch (Exception e) {
            return latTrim + ', ' + lngTrim;
        }
    }

    /** New-outlet map pin: prefer Account Latitude__c / Longitude__c; fallback to billing geocode. */
    private static Boolean resolveNewOutletMapCoordinates(Account acc, TrackingActivityDTO dto) {
        if (acc == null || dto == null) {
            return false;
        }
        if (!String.isBlank(acc.Latitude__c) && !String.isBlank(acc.Longitude__c)) {
            try {
                dto.latitude = Decimal.valueOf(acc.Latitude__c.trim());
                dto.longitude = Decimal.valueOf(acc.Longitude__c.trim());
                return true;
            } catch (Exception e) {
                // fall through to billing geocode
            }
        }
        if (acc.BillingLatitude != null && acc.BillingLongitude != null) {
            dto.latitude = acc.BillingLatitude;
            dto.longitude = acc.BillingLongitude;
            return true;
        }
        return false;
    }

    private static String buildAttendanceLocationDetail(Attendance__c a) {
        if (a == null) {
            return null;
        }
        String locationDescription =
            (a.Description__c != null && String.isNotBlank(a.Description__c.trim()))
                ? a.Description__c.trim()
                : null;
        if (locationDescription != null) {
            return locationDescription;
        }
        if (a.Location__Latitude__s != null && a.Location__Longitude__s != null) {
            return String.valueOf(a.Location__Latitude__s.setScale(6, System.RoundingMode.HALF_UP)) +
                ', ' +
                String.valueOf(a.Location__Longitude__s.setScale(6, System.RoundingMode.HALF_UP));
        }
        return null;
    }

    private static List<TrackingActivityDTO> buildVisitActivities(Id userId, Date selectedDate) {
        List<TrackingActivityDTO> out = new List<TrackingActivityDTO>();

        List<Visit_Task__c> rows = [
            SELECT
                Id,
                Checked_In_Time__c,
                Checked_Out_Time__c,
                Checked_In_Location__Latitude__s,
                Checked_In_Location__Longitude__s,
                Start_Call_Time__c,
                Start_Call_Location__Latitude__s,
                Start_Call_Location__Longitude__s,
                Order_Placed__c,
                Account__c,
                Account__r.Name,
                Retailer__c,
                Retailer__r.Name
            FROM Visit_Task__c
            WHERE Visitor_Name__c = :userId
              AND Task_Planned_Date__c = :selectedDate
              AND (
                  Checked_In_Time__c != NULL
                  OR Start_Call_Time__c != NULL
              )
            ORDER BY Checked_In_Time__c ASC, Start_Call_Time__c ASC
        ];

        for (Visit_Task__c v : rows) {
            TrackingActivityDTO dto = new TrackingActivityDTO();
            dto.sourceType = 'Visit_Task';
            dto.sourceId = v.Id;
            dto.activityType = v.Order_Placed__c == true ? ACT_PRODUCTIVE : ACT_NON_PRODUCTIVE;
            dto.sortTime = v.Checked_In_Time__c != null
                ? v.Checked_In_Time__c
                : v.Start_Call_Time__c;
            dto.checkInTime = v.Checked_In_Time__c;
            dto.checkOutTime = v.Checked_Out_Time__c;
            if (v.Account__c != null) {
                dto.outletId = v.Account__c;
                dto.outletName = v.Account__r != null ? v.Account__r.Name : null;
            } else if (v.Retailer__c != null) {
                dto.outletId = v.Retailer__c;
                dto.outletName = v.Retailer__r != null ? v.Retailer__r.Name : null;
            }
            if (v.Checked_In_Location__Latitude__s != null && v.Checked_In_Location__Longitude__s != null) {
                dto.latitude = v.Checked_In_Location__Latitude__s;
                dto.longitude = v.Checked_In_Location__Longitude__s;
            } else if (
                v.Start_Call_Location__Latitude__s != null &&
                v.Start_Call_Location__Longitude__s != null
            ) {
                dto.latitude = v.Start_Call_Location__Latitude__s;
                dto.longitude = v.Start_Call_Location__Longitude__s;
            }
            out.add(dto);
        }
        return out;
    }

    private static List<TrackingActivityDTO> buildNewOutletActivities(
        Id userId,
        DateTime dayStart,
        DateTime dayEndExclusive
    ) {
        List<TrackingActivityDTO> out = new List<TrackingActivityDTO>();
        List<Account> rows = [
            SELECT
                Id,
                Name,
                CreatedDate,
                BillingLatitude,
                BillingLongitude,
                Onboard_Date__c,
                Latitude__c,
                Longitude__c
            FROM Account
            WHERE CreatedById = :userId
              AND CreatedDate >= :dayStart
              AND CreatedDate < :dayEndExclusive
              AND RecordType.Name = :RETAILER_RECORD_TYPE_NAME
            ORDER BY CreatedDate ASC
        ];

        for (Account acc : rows) {
            TrackingActivityDTO dto = new TrackingActivityDTO();
            dto.sourceType = 'Account';
            dto.sourceId = acc.Id;
            dto.activityType = ACT_NEW_OUTLET;
            dto.sortTime = acc.CreatedDate;
            dto.outletId = acc.Id;
            dto.outletName = acc.Name;
            dto.onboardDate = acc.Onboard_Date__c;
            dto.newOutletLocationDetail = buildNewOutletLocationDetail(acc);
            if (!resolveNewOutletMapCoordinates(acc, dto)) {
                continue;
            }
            out.add(dto);
        }
        return out;
    }

    /** Productive visits only: SUM(Order__c.Total_Order_Value__c) per Visit_Task__c. */
    private static Map<Id, Decimal> loadOrderTotalsByVisitTask(
        Id userId,
        Date selectedDate,
        List<TrackingActivityDTO> activities
    ) {
        Set<Id> visitTaskIds = new Set<Id>();
        if (activities != null) {
            for (TrackingActivityDTO dto : activities) {
                if (
                    dto == null ||
                    dto.activityType != ACT_PRODUCTIVE ||
                    dto.sourceType != 'Visit_Task' ||
                    dto.sourceId == null
                ) {
                    continue;
                }
                visitTaskIds.add(dto.sourceId);
            }
        }
        if (visitTaskIds.isEmpty()) {
            return new Map<Id, Decimal>();
        }

        Map<Id, Decimal> totals = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Visit_Task__c visitTaskId, SUM(Total_Order_Value__c) total
            FROM Order__c
            WHERE Visit_Task__c IN :visitTaskIds
              AND OwnerId = :userId
              AND EffectiveDate__c = :selectedDate
            GROUP BY Visit_Task__c
        ]) {
            Id visitTaskId = (Id) ar.get('visitTaskId');
            Decimal sumVal = (Decimal) ar.get('total');
            if (visitTaskId != null && sumVal != null) {
                totals.put(visitTaskId, sumVal);
            }
        }
        return totals;
    }

    private static void applyOrderValuesToVisits(
        List<TrackingActivityDTO> activities,
        Map<Id, Decimal> orderByVisitTask
    ) {
        if (orderByVisitTask == null || orderByVisitTask.isEmpty()) {
            return;
        }
        for (TrackingActivityDTO dto : activities) {
            if (dto == null || dto.activityType != ACT_PRODUCTIVE || dto.sourceId == null) {
                continue;
            }
            if (orderByVisitTask.containsKey(dto.sourceId)) {
                dto.orderValue = orderByVisitTask.get(dto.sourceId);
            }
        }
    }

    // ----------------------------
    // Summary
    // ----------------------------

    private static Integer countNewOutletsForDay(
        Id userId,
        DateTime dayStart,
        DateTime dayEndExclusive
    ) {
        return [
            SELECT COUNT()
            FROM Account
            WHERE CreatedById = :userId
              AND CreatedDate >= :dayStart
              AND CreatedDate < :dayEndExclusive
              AND RecordType.Name = :RETAILER_RECORD_TYPE_NAME
        ];
    }

    private static DashboardSummary buildSummary(
        Id userId,
        List<TrackingActivityDTO> rawActivities,
        Integer newOutletCount
    ) {
        DashboardSummary summary = new DashboardSummary();
        summary.userId = userId;

        List<User> users = [SELECT Name FROM User WHERE Id = :userId LIMIT 1];
        if (!users.isEmpty()) {
            summary.userName = users[0].Name;
        }

        Integer productiveVisitCount = 0;
        Integer nonProductiveVisitCount = 0;
        Integer visitedCheckInCount = 0;
        Decimal orderTotal = 0;

        for (TrackingActivityDTO dto : rawActivities) {
            if (dto == null) {
                continue;
            }
            if (dto.activityType == ACT_ATTENDANCE) {
                summary.attendanceCount++;
                continue;
            }
            if (dto.activityType == ACT_EOD) {
                summary.eodCount++;
                continue;
            }
            if (dto.activityType == ACT_NEW_OUTLET) {
                continue;
            }
            if (dto.activityType == ACT_PRODUCTIVE) {
                productiveVisitCount++;
                if (dto.checkInTime != null) {
                    visitedCheckInCount++;
                }
                if (dto.orderValue != null) {
                    orderTotal += dto.orderValue;
                }
            } else if (dto.activityType == ACT_NON_PRODUCTIVE) {
                nonProductiveVisitCount++;
                if (dto.checkInTime != null) {
                    visitedCheckInCount++;
                }
            }
        }

        summary.totalProductiveOutlets = productiveVisitCount;
        summary.totalNonProductiveOutlets = nonProductiveVisitCount;
        summary.newOutletAdded = newOutletCount != null ? newOutletCount : 0;
        summary.totalVisitedOutlets = visitedCheckInCount + summary.newOutletAdded;

        summary.totalOrderValue = orderTotal;

        return summary;
    }

    // ----------------------------
    // Timeline
    // ----------------------------

    /** Map pins and route: physical outlet visits only (check-in); start-call-only excluded. */
    private static List<TrackingActivityDTO> activitiesForMap(
        List<TrackingActivityDTO> activities
    ) {
        List<TrackingActivityDTO> out = new List<TrackingActivityDTO>();
        if (activities == null) {
            return out;
        }
        for (TrackingActivityDTO dto : activities) {
            if (dto == null) {
                continue;
            }
            if (dto.sourceType == 'Visit_Task' && dto.checkInTime == null) {
                continue;
            }
            out.add(dto);
        }
        return out;
    }

    private static List<TrackingActivityDTO> filterFromFirstAttendance(
        List<TrackingActivityDTO> activities
    ) {
        if (activities == null || activities.isEmpty()) {
            return new List<TrackingActivityDTO>();
        }

        activities.sort(new ActivitySortComparator());

        Datetime lifecycleStart = null;
        for (TrackingActivityDTO dto : activities) {
            if (dto != null && dto.activityType == ACT_ATTENDANCE && dto.sortTime != null) {
                lifecycleStart = dto.sortTime;
                break;
            }
        }
        if (lifecycleStart == null) {
            return new List<TrackingActivityDTO>();
        }

        List<TrackingActivityDTO> kept = new List<TrackingActivityDTO>();
        for (TrackingActivityDTO dto : activities) {
            if (dto == null) {
                continue;
            }
            /** Physical outlet check-ins always plot on map; summary uses the same visits. */
            if (dto.sourceType == 'Visit_Task' && dto.checkInTime != null) {
                kept.add(dto);
                continue;
            }
            if (dto.sortTime == null) {
                continue;
            }
            if (dto.sortTime >= lifecycleStart) {
                kept.add(dto);
            }
        }
        return kept;
    }

    // ----------------------------
    // Helpers
    // ----------------------------

    private static Datetime resolveSortTime(Object appliedOn, Datetime createdDate) {
        if (appliedOn instanceof Datetime) {
            return (Datetime) appliedOn;
        }
        if (appliedOn instanceof Date) {
            return DateTime.newInstance((Date) appliedOn, Time.newInstance(0, 0, 0, 0));
        }
        return createdDate;
    }

    private static void validateInputs(Id userId, Date selectedDate) {
        if (userId == null) {
            throw new AuraHandledException('User is required.');
        }
        if (selectedDate == null) {
            throw new AuraHandledException('Date is required.');
        }
    }

    private class UserOptionNameComparator implements System.Comparator<UserOption> {
        public Integer compare(UserOption a, UserOption b) {
            String na = a != null && a.name != null ? a.name : '';
            String nb = b != null && b.name != null ? b.name : '';
            return na.toLowerCase().compareTo(nb.toLowerCase());
        }
    }

    private class ActivitySortComparator implements System.Comparator<TrackingActivityDTO> {
        public Integer compare(TrackingActivityDTO a, TrackingActivityDTO b) {
            if (a == null && b == null) {
                return 0;
            }
            if (a == null) {
                return -1;
            }
            if (b == null) {
                return 1;
            }
            if (a.sortTime == null && b.sortTime == null) {
                return 0;
            }
            if (a.sortTime == null) {
                return -1;
            }
            if (b.sortTime == null) {
                return 1;
            }
            return a.sortTime < b.sortTime ? -1 : (a.sortTime > b.sortTime ? 1 : 0);
        }
    }
}