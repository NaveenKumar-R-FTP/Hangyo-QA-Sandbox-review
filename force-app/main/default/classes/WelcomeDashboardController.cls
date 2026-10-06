/**
 * WelcomeDashboardController
 * ---------------------------------------------------------------------------
 * Backing controller for the SFA Lite field-rep "Welcome" home dashboard LWC.
 * Returns every metric the dashboard renders in a single DTO so the LWC makes
 * one round trip.
 *
 * Field API names below are mapped to the Hangyo QA org schema (verified via
 * FieldDefinition describe). All seven sections are implemented against real
 * fields. A few data-correctness choices are flagged "CONFIRM" — they compile
 * and run, but change WHICH rows/values are counted, so confirm they match how
 * your team reports:
 *   - Attendance Status__c picklist values (Present / Leave / Absent)
 *   - Secondary Order record-type DeveloperName
 *   - Invoice sale field (Invoice_Amount__c vs Invoice_Amount__c)
 *
 * SCOPE OF DATES
 *   - "As of yesterday": date range [1st of current month .. yesterday].
 *   - Sundays are excluded ONLY in the Attendance working-day count. Every
 *     other metric is plain MTD-as-of-yesterday with no Sunday exclusion.
 */
public without sharing class WelcomeDashboardController {

    // Attendance Status__c picklist buckets:
    //   Present   <- 'Present', 'Late'                 (1 each)
    //   Half Day  <- 'Present Half Day'                (0.5 each)
    //   Leave     <- 'Leave'                           (1 each)
    //   Absent    <- 'Absent'                          (1 each)
    //             +  'Present Half Day / Absent'       (0.5 each)
    private static final String STATUS_PRESENT      = 'Present';
    private static final String STATUS_LATE         = 'Late';
    private static final String STATUS_LEAVE        = 'Leave';
    private static final String STATUS_ABSENT       = 'Absent';
    private static final String STATUS_HALF_DAY     = 'Present Half Day';
    private static final String STATUS_HALF_ABSENT  = 'Present Half Day / Absent';

    // CONFIRM: DeveloperName of the Secondary Order record type on Order__c.
    private static final String SECONDARY_ORDER_RT = 'Secondary_Order';

    // =========================================================================
    // Public entry point
    // =========================================================================
    @AuraEnabled
    public static DashboardDTO getDashboard() {
        Id userId = UserInfo.getUserId();

        Date today      = Date.today();
        Date monthStart = today.toStartOfMonth();
        // Fully live: all MTD metrics count through TODAY (includes today's invoices/visits).
        Date asOf = today;

        // Team scope = self + everyone below in the Manager hierarchy. For a field rep
        // with no reports this is just {self}, so their dashboard is unchanged. For a
        // manager, the outlet metrics, target-vs-achievement and fill/delivery rings roll
        // up the whole team. Attendance, Today's Beat and Order Details stay individual.
        Set<Id> teamIds = getSelfAndReports(userId);

        DashboardDTO dto = new DashboardDTO();
        dto.attendance = buildAttendance(userId, monthStart, asOf, today);   // individual
        dto.outlets    = buildOutlets(teamIds, monthStart, asOf);            // team
        dto.target     = buildTarget(userId, teamIds, monthStart, asOf, today); // target=own, achievement=team
        dto.beat       = buildBeat(userId, today);                          // individual
        dto.order      = buildOrder(userId, today);                         // individual
        dto.rings      = buildRings(teamIds, monthStart, asOf);             // team
        dto.ytd        = buildYtd(userId, teamIds, asOf);                    // FY Apr->now
        return dto;
    }

    /** Today's attendance + EOD status. Non-cacheable so the dashboard reflects a
     *  just-submitted EOD without an app restart. */
    @AuraEnabled
    public static AttendanceTodayDTO getTodayAttendanceStatus() {
        AttendanceTodayDTO t = new AttendanceTodayDTO();
        Id userId = UserInfo.getUserId();
        List<Attendance__c> todays = [
            SELECT Status__c, CreatedDate, EOD_Date_Time__c
            FROM Attendance__c
            WHERE User__c = :userId
              AND Date_of_attendance__c = :Date.today()
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!todays.isEmpty()) {
            t.marked     = true;
            t.status     = todays[0].Status__c;
            t.markedTime = todays[0].CreatedDate;
            if (todays[0].EOD_Date_Time__c != null) {
                t.eodMarked = true;
                t.eodTime   = todays[0].EOD_Date_Time__c;
            }
        }
        return t;
    }

    // =========================================================================
    // 2. Attendance ring
    // =========================================================================
    private static AttendanceDTO buildAttendance(Id userId, Date monthStart, Date asOf, Date today) {
        AttendanceDTO a = new AttendanceDTO();
        a.workingDays = countWorkingDays(monthStart, today);

        // Count attendance by status, EXCLUDING Sundays. Sundays are non-working days
        // (they're excluded from workingDays), so a Sunday auto-marked "Absent" must not
        // inflate the Absent count. Ring includes today so a rep sees what they just marked.
        for (Attendance__c att : [
            SELECT Date_of_attendance__c, Status__c
            FROM Attendance__c
            WHERE User__c = :userId
              AND Date_of_attendance__c >= :monthStart
              AND Date_of_attendance__c <= :today
        ]) {
            if (att.Date_of_attendance__c == null || isSunday(att.Date_of_attendance__c)) continue;
            String status = att.Status__c;
            if (status == STATUS_PRESENT || status == STATUS_LATE) a.present   += 1;
            else if (status == STATUS_LEAVE)       a.leaveCount += 1;
            else if (status == STATUS_HALF_DAY)    a.halfDay    += 0.5;
            else if (status == STATUS_ABSENT)      a.absent     += 1;
            else if (status == STATUS_HALF_ABSENT) a.absent     += 0.5;
        }
        return a;
    }

    /** True if the given date falls on a Sunday. */
    private static Boolean isSunday(Date d) {
        Date knownSunday = Date.newInstance(2024, 1, 7); // a Sunday
        return Math.mod(knownSunday.daysBetween(d), 7) == 0;
    }

    // =========================================================================
    // 3. Outlet metrics
    // =========================================================================
    private static OutletsDTO buildOutlets(Set<Id> userIds, Date monthStart, Date asOf) {
        OutletsDTO o = new OutletsDTO();

        // Retailer outlets owned across the team (exclude Distributors etc.).
        // Only ACTIVE outlets count (Is_Active__c = true) — deactivated/closed retailers
        // are excluded from the base. COUNT(Id) (aggregate) returns one row and does NOT
        // consume a query row per matched account, unlike bare COUNT() — important for
        // large manager zones.
        AggregateResult outletsAgg = [
            SELECT COUNT(Id) c
            FROM Account
            WHERE OwnerId IN :userIds
              AND RecordType.Name = 'Retailer'
              AND Is_Active__c = true
        ];
        o.totalOutlets = (Integer) outletsAgg.get('c');

        // Unique outlets visited (a call = check-in OR start-call) as of yesterday.
        // Aggregate (COUNT_DISTINCT) so it scales to a full manager zone without loading rows.
        AggregateResult visAr = [
            SELECT COUNT_DISTINCT(Retailer__c) c
            FROM Visit_Task__c
            WHERE Visitor_Name__c IN :userIds
              AND (Checked_In_Time__c != null OR Start_Call_Time__c != null)
              AND Task_Planned_Date__c >= :monthStart
              AND Task_Planned_Date__c <= :asOf
              AND Retailer__c != null
        ];
        o.uniqueOutletsVisited = (Integer) visAr.get('c');

        // Unique billed outlets + overall sale amount as of yesterday (aggregate — scales to any team size).
        AggregateResult billAr = [
            SELECT COUNT_DISTINCT(Retailer_Account__c) c, SUM(Invoice_Amount__c) s
            FROM Invoice__c
            WHERE Retailer_Account__r.OwnerId IN :userIds
              AND Invoice_Date__c >= :monthStart
              AND Invoice_Date__c <= :asOf
              AND RecordType.DeveloperName = 'Secondary_Invoice'
              AND Status__c NOT IN ('Draft', 'Cancelled')
        ];
        o.uniqueOutletsBilled = (Integer) billAr.get('c');
        Decimal saleAmount = (billAr.get('s') == null) ? 0 : (Decimal) billAr.get('s');
        o.throughPut = (o.uniqueOutletsBilled == 0) ? 0
                       : (saleAmount / o.uniqueOutletsBilled).setScale(2);
        return o;
    }

    // =========================================================================
    // 4. Target vs Achievement
    // =========================================================================
    private static TargetDTO buildTarget(Id userId, Set<Id> teamUserIds, Date monthStart, Date asOf, Date today) {
        TargetDTO t = new TargetDTO();

        // Monthly target comes ONLY from Secondary Target Management (Sales_Target__c,
        // "Sales Performance - Month" record type) for the period covering today.
        // No legacy fallback: if no target is uploaded for the month, it shows 0.
        Decimal target = 0;
        List<Sales_Target__c> stg = [
            SELECT Secondary_Sales_Target__c
            FROM Sales_Target__c
            WHERE Assigned_To__c = :userId
              AND RecordType.DeveloperName = 'Sales_Target_Month'
              AND From_Date__c <= :today
              AND To_Date__c   >= :today
            ORDER BY From_Date__c DESC
            LIMIT 1
        ];
        if (!stg.isEmpty() && stg[0].Secondary_Sales_Target__c != null) {
            target = stg[0].Secondary_Sales_Target__c;
        }
        t.monthlyTarget = target;

        // Achievement = REAL-TIME team actual: own + everyone below the viewer in the
        // Manager (User.ManagerId) hierarchy (teamUserIds), summed live from invoices.
        // A field rep with no reports resolves to just their own secondary sales.
        // (The stored Team_Secondary_Sales_Actual__c + nightly job remain for Admin reports.)
        AggregateResult ar = [
            SELECT SUM(Invoice_Amount__c) total
            FROM Invoice__c
            WHERE Retailer_Account__r.OwnerId IN :teamUserIds
              AND Invoice_Date__c >= :monthStart
              AND Invoice_Date__c <= :asOf
              AND RecordType.DeveloperName = 'Secondary_Invoice'
              AND Status__c NOT IN ('Draft', 'Cancelled')
        ];
        t.achievement = (ar.get('total') == null) ? 0 : (Decimal) ar.get('total');
        t.percent = (t.monthlyTarget == 0) ? 0
                    : (t.achievement / t.monthlyTarget * 100).setScale(0);

        Integer lastDay = Date.daysInMonth(today.year(), today.month());
        t.daysLeft = lastDay - today.day();
        return t;
    }

    /** Self + all users below `rootId` in the Manager (User.ManagerId) hierarchy, all levels. */
    private static Set<Id> getSelfAndReports(Id rootId) {
        Map<Id, List<Id>> children = new Map<Id, List<Id>>();
        for (User u : [SELECT Id, ManagerId FROM User WHERE IsActive = true AND ManagerId != null]) {
            if (!children.containsKey(u.ManagerId)) children.put(u.ManagerId, new List<Id>());
            children.get(u.ManagerId).add(u.Id);
        }
        Set<Id> result = new Set<Id>{ rootId };
        List<Id> queue = new List<Id>{ rootId };
        while (!queue.isEmpty()) {
            Id current = queue.remove(0);
            if (children.containsKey(current)) {
                for (Id child : children.get(current)) {
                    if (!result.contains(child)) { result.add(child); queue.add(child); }
                }
            }
        }
        return result;
    }

    // =========================================================================
    // 4b. YTD (fiscal year Apr 1 -> today) Target vs Achievement
    // =========================================================================
    private static YtdDTO buildYtd(Id userId, Set<Id> teamIds, Date asOf) {
        YtdDTO y = new YtdDTO();

        // Fiscal year starts 1 April. Before April, FY started last calendar year.
        Integer fyStartYear = (asOf.month() >= 4) ? asOf.year() : asOf.year() - 1;
        Date fyStart = Date.newInstance(fyStartYear, 4, 1);
        y.fyStartYear = fyStartYear;

        // YTD target = sum of THIS user's monthly targets from FY start to now
        // (targets are added month on month; this grows as they're loaded).
        AggregateResult tAr = [
            SELECT SUM(Secondary_Sales_Target__c) total
            FROM Sales_Target__c
            WHERE Assigned_To__c = :userId
              AND RecordType.DeveloperName = 'Sales_Target_Month'
              AND From_Date__c >= :fyStart
              AND From_Date__c <= :asOf
        ];
        y.target = (tAr.get('total') == null) ? 0 : (Decimal) tAr.get('total');

        // YTD achievement = sum of the STORED monthly team actuals (Team_Secondary_Sales_Actual__c),
        // FY start -> now. The rollup already computes each month's team actual on this user's
        // monthly row, so this is ~a handful of rows. Summing the zone's 6-month invoice set live
        // (tens of thousands of rows) exceeds the SOQL query-row governor limit for large zones
        // (ZSM+), which is why YTD reads the rollup instead. Freshness = the 30-min rollup.
        AggregateResult aAr = [
            SELECT SUM(Team_Secondary_Sales_Actual__c) total
            FROM Sales_Target__c
            WHERE Assigned_To__c = :userId
              AND RecordType.DeveloperName = 'Sales_Target_Month'
              AND From_Date__c >= :fyStart
              AND From_Date__c <= :asOf
        ];
        y.achievement = (aAr.get('total') == null) ? 0 : (Decimal) aAr.get('total');
        y.percent = (y.target == 0) ? 0 : (y.achievement / y.target * 100).setScale(0);
        return y;
    }

    // =========================================================================
    // 5. Today's Beat  (TC/PC + DF-outlet-vs-PC)
    // =========================================================================
    private static BeatDTO buildBeat(Id userId, Date today) {
        BeatDTO b = new BeatDTO();

        List<Visit_Task__c> todays = [
            SELECT Beat__c, Beat__r.Name
            FROM Visit_Task__c
            WHERE Visitor_Name__c = :userId
              AND Task_Planned_Date__c = :today
              AND Beat__c != null
            LIMIT 1
        ];
        if (!todays.isEmpty()) {
            b.beatName = todays[0].Beat__r.Name;
        }

        // Today's plan = every outlet the rep will cover today: the assigned beat PLUS
        // any outlets added from other beats. Reps can now add outlets from other beats,
        // so we count ALL of today's Visit_Task outlets for this rep (any beat), not just
        // the assigned beat. This is the header "(N)" count shown next to the beat name.
        Set<Id> planOutletIds = new Set<Id>();
        for (Visit_Task__c vt : [
            SELECT Retailer__c
            FROM Visit_Task__c
            WHERE Visitor_Name__c = :userId
              AND Task_Planned_Date__c = :today
              AND Retailer__c != null
        ]) {
            planOutletIds.add(vt.Retailer__c);
        }
        b.beatOutletCount = planOutletIds.size();

        // Total Calls = today's visits at a real outlet where the rep checked in
        // OR started the call (null-retailer check-ins are not outlet calls).
        Integer totalCalls = 0, productive = 0;
        for (Visit_Task__c vt : [
            SELECT Order_Placed__c
            FROM Visit_Task__c
            WHERE Visitor_Name__c = :userId
              AND Task_Planned_Date__c = :today
              AND Retailer__c != null
              AND (Checked_In_Time__c != null OR Start_Call_Time__c != null)
        ]) {
            totalCalls++;
            if (vt.Order_Placed__c == true) productive++;
        }
        b.totalCalls      = totalCalls;
        b.productiveCalls = productive;
        b.tcPcPercent     = (totalCalls == 0) ? 0
                            : (Decimal.valueOf(productive) / totalCalls * 100).round().intValue();

        // DF outlet vs PC: DF outlets = today's plan outlets (scheduled + added from
        // other beats) that have an ACTIVE asset (freezer) mapping. Counted for ALL plan
        // outlets regardless of who owns them, so added-from-other-beat outlets and their
        // freezers are included. PC = productive calls (order taken) at those outlets today.
        Set<Id> dfOutlets = new Set<Id>();
        if (!planOutletIds.isEmpty()) {
            for (Asset_Mapping__c am : [
                SELECT Retailer__c
                FROM Asset_Mapping__c
                WHERE Active__c = true
                  AND Retailer__c IN :planOutletIds
            ]) {
                dfOutlets.add(am.Retailer__c);
            }
        }
        b.dfOutlet = dfOutlets.size();
        Integer dfProd = (dfOutlets.isEmpty()) ? 0 : [
            SELECT COUNT()
            FROM Visit_Task__c
            WHERE Visitor_Name__c = :userId
              AND Task_Planned_Date__c = :today
              AND Order_Placed__c = true
              AND Retailer__c IN :dfOutlets
        ];
        b.dfProductive = dfProd;
        b.dfPcPercent  = (b.dfOutlet == 0) ? 0
                         : (Decimal.valueOf(dfProd) / b.dfOutlet * 100).round().intValue();
        return b;
    }

    // =========================================================================
    // 6. Order Details  (Total value + LPC + Through Put)
    // =========================================================================
    private static OrderDTO buildOrder(Id userId, Date today) {
        OrderDTO od = new OrderDTO();

        Decimal totalOrderValue = 0;
        Set<Id> orderOutlets    = new Set<Id>();
        Set<Id> orderIds        = new Set<Id>();

        for (Order__c o : [
            SELECT Id, Total_Order_Value__c, Account__c
            FROM Order__c
            WHERE OwnerId = :userId
              AND RecordType.DeveloperName = :SECONDARY_ORDER_RT
              AND DAY_ONLY(CreatedDate) = :today
        ]) {
            orderIds.add(o.Id);
            if (o.Total_Order_Value__c != null) totalOrderValue += o.Total_Order_Value__c;
            if (o.Account__c != null) orderOutlets.add(o.Account__c);
        }
        od.totalOrderValue = totalOrderValue.setScale(2);

        // LPC = total SKU line items today / total productive calls today.
        Integer lineItems = (orderIds.isEmpty()) ? 0 : [
            SELECT COUNT() FROM Order_Line_Item__c WHERE Order__c IN :orderIds
        ];
        Integer productiveCalls = [
            SELECT COUNT()
            FROM Visit_Task__c
            WHERE Visitor_Name__c = :userId
              AND Task_Planned_Date__c = :today
              AND Retailer__c != null
              AND Order_Placed__c = true
        ];
        od.lpc = (productiveCalls == 0) ? 0
                 : (Decimal.valueOf(lineItems) / productiveCalls).setScale(1);

        od.throughPut = (orderOutlets.isEmpty()) ? 0
                        : (totalOrderValue / orderOutlets.size()).setScale(2);
        return od;
    }

    // =========================================================================
    // 7. Fill-Rate + Delivery rings
    // =========================================================================
    private static RingsDTO buildRings(Set<Id> userIds, Date monthStart, Date asOf) {
        RingsDTO r = new RingsDTO();

        AggregateResult ordAr = [
            SELECT SUM(Total_Order_Value__c) total
            FROM Order__c
            WHERE OwnerId IN :userIds
              AND DAY_ONLY(CreatedDate) >= :monthStart
              AND DAY_ONLY(CreatedDate) <= :asOf
        ];
        r.orderValue = (ordAr.get('total') == null) ? 0 : (Decimal) ordAr.get('total');

        AggregateResult saleAr = [
            SELECT SUM(Invoice_Amount__c) total
            FROM Invoice__c
            WHERE Retailer_Account__r.OwnerId IN :userIds
              AND Invoice_Date__c >= :monthStart
              AND Invoice_Date__c <= :asOf
              AND RecordType.DeveloperName = 'Secondary_Invoice'
              AND Status__c NOT IN ('Draft', 'Cancelled')
        ];
        r.saleValue = (saleAr.get('total') == null) ? 0 : (Decimal) saleAr.get('total');
        r.fillRatePercent = (r.orderValue == 0) ? 0
                            : (r.saleValue / r.orderValue * 100).setScale(1);

        // Delivery = billed-against-DF / DF outlets (as of yesterday).
        Set<Id> dfOutlets = getDfOutletIds(userIds);
        r.dfOutletsCount = dfOutlets.size();
        Integer billedDfCount = 0;
        if (!dfOutlets.isEmpty()) {
            AggregateResult dfAr = [
                SELECT COUNT_DISTINCT(Retailer_Account__c) c
                FROM Invoice__c
                WHERE Retailer_Account__r.OwnerId IN :userIds
                  AND Invoice_Date__c >= :monthStart
                  AND Invoice_Date__c <= :asOf
                  AND Retailer_Account__c IN :dfOutlets
                  AND RecordType.DeveloperName = 'Secondary_Invoice'
                  AND Status__c NOT IN ('Draft', 'Cancelled')
            ];
            billedDfCount = (Integer) dfAr.get('c');
        }
        r.billedOutletsAgainstDf = billedDfCount;
        r.deliveryPercent = (r.dfOutletsCount == 0) ? 0
                            : (Decimal.valueOf(billedDfCount) / r.dfOutletsCount * 100).round().intValue();
        return r;
    }

    /** Distinct retailer outlets across the team that have an active asset (freezer) mapping. */
    private static Set<Id> getDfOutletIds(Set<Id> userIds) {
        Set<Id> ids = new Set<Id>();
        for (Asset_Mapping__c am : [
            SELECT Retailer__c
            FROM Asset_Mapping__c
            WHERE Active__c = true
              AND Retailer__c != null
              AND Retailer__r.OwnerId IN :userIds
        ]) {
            ids.add(am.Retailer__c);
        }
        return ids;
    }

    // =========================================================================
    // Helpers
    // =========================================================================
    /** Calendar days in [startDate .. endDate] inclusive, excluding Sundays. */
    @TestVisible
    private static Integer countWorkingDays(Date startDate, Date endDate) {
        if (endDate < startDate) return 0;
        Integer days = 0;
        Date d = startDate;
        Date knownSunday = Date.newInstance(2024, 1, 7); // a Sunday
        while (d <= endDate) {
            Integer dow = Math.mod(knownSunday.daysBetween(d), 7); // 0 = Sunday
            if (dow != 0) days++;
            d = d.addDays(1);
        }
        return days;
    }

    // =========================================================================
    // DTOs
    // =========================================================================
    public class DashboardDTO {
        @AuraEnabled public AttendanceDTO attendance;
        @AuraEnabled public OutletsDTO    outlets;
        @AuraEnabled public TargetDTO     target;
        @AuraEnabled public BeatDTO       beat;
        @AuraEnabled public OrderDTO      order;
        @AuraEnabled public RingsDTO      rings;
        @AuraEnabled public YtdDTO        ytd;
    }
    public class YtdDTO {
        @AuraEnabled public Decimal target      = 0;
        @AuraEnabled public Decimal achievement = 0;
        @AuraEnabled public Decimal percent     = 0;
        @AuraEnabled public Integer fyStartYear = 0;
    }
    public class AttendanceTodayDTO {
        @AuraEnabled public Boolean  marked     = false;
        @AuraEnabled public String   status;
        @AuraEnabled public Datetime markedTime;
        @AuraEnabled public Boolean  eodMarked  = false;
        @AuraEnabled public Datetime eodTime;
    }
    public class AttendanceDTO {
        @AuraEnabled public Integer workingDays = 0;
        @AuraEnabled public Decimal present     = 0;
        @AuraEnabled public Decimal halfDay     = 0;
        @AuraEnabled public Decimal leaveCount  = 0;
        @AuraEnabled public Decimal absent      = 0;
    }
    public class OutletsDTO {
        @AuraEnabled public Integer totalOutlets         = 0;
        @AuraEnabled public Integer uniqueOutletsVisited = 0;
        @AuraEnabled public Integer uniqueOutletsBilled  = 0;
        @AuraEnabled public Decimal throughPut           = 0;
    }
    public class TargetDTO {
        @AuraEnabled public Decimal monthlyTarget = 0;
        @AuraEnabled public Decimal achievement   = 0;
        @AuraEnabled public Decimal percent       = 0;
        @AuraEnabled public Integer daysLeft      = 0;
    }
    public class BeatDTO {
        @AuraEnabled public String  beatName        = '';
        @AuraEnabled public Integer beatOutletCount = 0;
        @AuraEnabled public Integer totalCalls      = 0;
        @AuraEnabled public Integer productiveCalls = 0;
        @AuraEnabled public Integer tcPcPercent     = 0;
        @AuraEnabled public Integer dfOutlet        = 0;
        @AuraEnabled public Integer dfProductive    = 0;
        @AuraEnabled public Integer dfPcPercent     = 0;
    }
    public class OrderDTO {
        @AuraEnabled public Decimal totalOrderValue = 0;
        @AuraEnabled public Decimal lpc             = 0;
        @AuraEnabled public Decimal throughPut      = 0;
    }
    public class RingsDTO {
        @AuraEnabled public Decimal orderValue              = 0;
        @AuraEnabled public Decimal saleValue               = 0;
        @AuraEnabled public Decimal fillRatePercent         = 0;
        @AuraEnabled public Integer dfOutletsCount          = 0;
        @AuraEnabled public Integer billedOutletsAgainstDf  = 0;
        @AuraEnabled public Integer deliveryPercent         = 0;
    }
}