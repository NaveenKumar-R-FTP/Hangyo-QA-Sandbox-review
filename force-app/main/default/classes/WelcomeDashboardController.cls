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
    @AuraEnabled(cacheable=true)
    public static DashboardDTO getDashboard() {
        Id userId = UserInfo.getUserId();

        Date today      = Date.today();
        Date monthStart = today.toStartOfMonth();
        Date yesterday  = today.addDays(-1);
        Date asOf = (yesterday < monthStart) ? monthStart : yesterday;

        DashboardDTO dto = new DashboardDTO();
        dto.attendance = buildAttendance(userId, monthStart, asOf, today);
        dto.outlets    = buildOutlets(userId, monthStart, asOf);
        dto.target     = buildTarget(userId, monthStart, asOf, today);
        dto.beat       = buildBeat(userId, today);
        dto.order      = buildOrder(userId, today);
        dto.rings      = buildRings(userId, monthStart, asOf);
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

        // Attendance ring includes today (so a rep sees the attendance they just marked).
        for (AggregateResult ar : [
            SELECT Status__c status, COUNT(Id) cnt
            FROM Attendance__c
            WHERE User__c = :userId
              AND Date_of_attendance__c >= :monthStart
              AND Date_of_attendance__c <= :today
            GROUP BY Status__c
        ]) {
            String status = String.valueOf(ar.get('status'));
            Decimal cnt    = (Integer) ar.get('cnt');
            if (status == STATUS_PRESENT || status == STATUS_LATE) a.present   += cnt;
            else if (status == STATUS_LEAVE)       a.leaveCount += cnt;
            else if (status == STATUS_HALF_DAY)    a.halfDay    += cnt * 0.5;
            else if (status == STATUS_ABSENT)      a.absent     += cnt;
            else if (status == STATUS_HALF_ABSENT) a.absent     += cnt * 0.5;
        }
        return a;
    }

    // =========================================================================
    // 3. Outlet metrics
    // =========================================================================
    private static OutletsDTO buildOutlets(Id userId, Date monthStart, Date asOf) {
        OutletsDTO o = new OutletsDTO();

        // Retailer outlets owned by this rep (exclude Distributors etc.).
        o.totalOutlets = [
            SELECT COUNT()
            FROM Account
            WHERE OwnerId = :userId
              AND RecordType.Name = 'Retailer'
        ];

        // Unique outlets visited (a call = check-in OR start-call) as of yesterday.
        Set<Id> visited = new Set<Id>();
        for (Visit_Task__c vt : [
            SELECT Retailer__c
            FROM Visit_Task__c
            WHERE Visitor_Name__c = :userId
              AND (Checked_In_Time__c != null OR Start_Call_Time__c != null)
              AND Task_Planned_Date__c >= :monthStart
              AND Task_Planned_Date__c <= :asOf
        ]) {
            if (vt.Retailer__c != null) visited.add(vt.Retailer__c);
        }
        o.uniqueOutletsVisited = visited.size();

        // Unique billed outlets + overall sale amount as of yesterday.
        Set<Id> billed = new Set<Id>();
        Decimal saleAmount = 0;
        for (Invoice__c inv : [
            SELECT Retailer_Account__c, Invoice_Amount__c
            FROM Invoice__c
            WHERE Retailer_Account__r.OwnerId = :userId
              AND Invoice_Date__c >= :monthStart
              AND Invoice_Date__c <= :asOf
        ]) {
            if (inv.Retailer_Account__c != null) billed.add(inv.Retailer_Account__c);
            if (inv.Invoice_Amount__c != null) saleAmount += inv.Invoice_Amount__c;
        }
        o.uniqueOutletsBilled = billed.size();
        o.throughPut = (o.uniqueOutletsBilled == 0) ? 0
                       : (saleAmount / o.uniqueOutletsBilled).setScale(2);
        return o;
    }

    // =========================================================================
    // 4. Target vs Achievement
    // =========================================================================
    private static TargetDTO buildTarget(Id userId, Date monthStart, Date asOf, Date today) {
        TargetDTO t = new TargetDTO();

        User u = [SELECT Monthly_Target__c FROM User WHERE Id = :userId LIMIT 1];
        t.monthlyTarget = (u.Monthly_Target__c == null) ? 0 : u.Monthly_Target__c;

        AggregateResult ar = [
            SELECT SUM(Invoice_Amount__c) total
            FROM Invoice__c
            WHERE Retailer_Account__r.OwnerId = :userId
              AND Invoice_Date__c >= :monthStart
              AND Invoice_Date__c <= :asOf
        ];
        t.achievement = (ar.get('total') == null) ? 0 : (Decimal) ar.get('total');
        t.percent = (t.monthlyTarget == 0) ? 0
                    : (t.achievement / t.monthlyTarget * 100).setScale(0);

        Integer lastDay = Date.daysInMonth(today.year(), today.month());
        t.daysLeft = lastDay - today.day();
        return t;
    }

    // =========================================================================
    // 5. Today's Beat  (TC/PC + DF-outlet-vs-PC)
    // =========================================================================
    private static BeatDTO buildBeat(Id userId, Date today) {
        BeatDTO b = new BeatDTO();

        List<Visit_Task__c> todays = [
            SELECT Beat__c, Beat__r.Name, Beat__r.Number_Of_Retailers__c
            FROM Visit_Task__c
            WHERE Visitor_Name__c = :userId
              AND Task_Planned_Date__c = :today
              AND Beat__c != null
            LIMIT 1
        ];
        if (!todays.isEmpty()) {
            b.beatName        = todays[0].Beat__r.Name;
            b.beatOutletCount = (Integer) todays[0].Beat__r.Number_Of_Retailers__c;
        }

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

        // DF outlet vs PC: DF outlets = the rep's asset-mapped outlets; PC = productive
        // calls (order taken) at those outlets today.
        Set<Id> dfOutlets = getDfOutletIds(userId);
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
    private static RingsDTO buildRings(Id userId, Date monthStart, Date asOf) {
        RingsDTO r = new RingsDTO();

        AggregateResult ordAr = [
            SELECT SUM(Total_Order_Value__c) total
            FROM Order__c
            WHERE OwnerId = :userId
              AND DAY_ONLY(CreatedDate) >= :monthStart
              AND DAY_ONLY(CreatedDate) <= :asOf
        ];
        r.orderValue = (ordAr.get('total') == null) ? 0 : (Decimal) ordAr.get('total');

        AggregateResult saleAr = [
            SELECT SUM(Invoice_Amount__c) total
            FROM Invoice__c
            WHERE Retailer_Account__r.OwnerId = :userId
              AND Invoice_Date__c >= :monthStart
              AND Invoice_Date__c <= :asOf
        ];
        r.saleValue = (saleAr.get('total') == null) ? 0 : (Decimal) saleAr.get('total');
        r.fillRatePercent = (r.orderValue == 0) ? 0
                            : (r.saleValue / r.orderValue * 100).setScale(1);

        // Delivery = billed-against-DF / DF outlets (as of yesterday).
        Set<Id> dfOutlets = getDfOutletIds(userId);
        r.dfOutletsCount = dfOutlets.size();
        Set<Id> billedDf = new Set<Id>();
        if (!dfOutlets.isEmpty()) {
            for (Invoice__c inv : [
                SELECT Retailer_Account__c
                FROM Invoice__c
                WHERE Retailer_Account__r.OwnerId = :userId
                  AND Invoice_Date__c >= :monthStart
                  AND Invoice_Date__c <= :asOf
                  AND Retailer_Account__c IN :dfOutlets
            ]) {
                if (inv.Retailer_Account__c != null) billedDf.add(inv.Retailer_Account__c);
            }
        }
        r.billedOutletsAgainstDf = billedDf.size();
        r.deliveryPercent = (r.dfOutletsCount == 0) ? 0
                            : (Decimal.valueOf(billedDf.size()) / r.dfOutletsCount * 100).round().intValue();
        return r;
    }

    /** Distinct retailer outlets owned by this rep that have an active asset (freezer) mapping. */
    private static Set<Id> getDfOutletIds(Id userId) {
        Set<Id> ids = new Set<Id>();
        for (Asset_Mapping__c am : [
            SELECT Retailer__c
            FROM Asset_Mapping__c
            WHERE Active__c = true
              AND Retailer__c != null
              AND Retailer__r.OwnerId = :userId
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