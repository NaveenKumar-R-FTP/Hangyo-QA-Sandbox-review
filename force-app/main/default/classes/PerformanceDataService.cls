/**
 * PerformanceDataService
 * All reads for the Performance Dashboard. READ-ONLY: never inserts/updates/deletes any record.
 * New class - Performance Dashboard project. Does not modify or call any existing class.
 * Rule: every total is a GROUP BY aggregate filtered to the team (proven governor-safe in Production).
 */
public without sharing class PerformanceDataService {

    public static final String MODE_MTD = 'MTD';
    public static final String MODE_YTD = 'YTD';

    // ---------------------------------------------------------------- date windows
    public class Window {
        public String mode;
        public Date today;
        public Date startDate;      // period start (1st of month / 1 Apr)
        public Date endDate;        // today
        public Date periodEnd;      // month end / 31 Mar
        public Date lyStart;        // same period last year
        public Date lyEnd;
        public Integer remainingDays; // calendar days left INCLUDING today
    }

    public static String normaliseMode(String mode) {
        return (mode != null && mode.trim().toUpperCase() == MODE_YTD) ? MODE_YTD : MODE_MTD;
    }

    public static Window window(String mode, Date today) {
        Window w = new Window();
        w.mode = normaliseMode(mode);
        w.today = today;
        w.endDate = today;
        if (w.mode == MODE_YTD) {
            Integer fyYear = (today.month() >= 4) ? today.year() : today.year() - 1;
            w.startDate = Date.newInstance(fyYear, 4, 1);
            w.periodEnd = Date.newInstance(fyYear + 1, 3, 31);
        } else {
            w.startDate = today.toStartOfMonth();
            w.periodEnd = Date.newInstance(today.year(), today.month(), Date.daysInMonth(today.year(), today.month()));
        }
        w.remainingDays = today.daysBetween(w.periodEnd) + 1;
        w.lyStart = sameDateLastYear(w.startDate);
        w.lyEnd = sameDateLastYear(today);
        return w;
    }

    /** Same calendar date one year earlier; 29 Feb becomes 28 Feb. */
    public static Date sameDateLastYear(Date d) {
        Integer y = d.year() - 1;
        Integer day = Math.min(d.day(), Date.daysInMonth(y, d.month()));
        return Date.newInstance(y, d.month(), day);
    }

    // ---------------------------------------------------------------- user & access
    public static User currentUser() {
        return [SELECT Id, Name, Division, Employee_Role__c
                FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
    }

    /** True only if the user's Employee_Role__c matches an active Performance_Dashboard_Access__mdt record. */
    public static Boolean hasAccess(User u) {
        if (u == null || String.isBlank(u.Employee_Role__c)) return false;
        String role = u.Employee_Role__c.trim();
        for (Performance_Dashboard_Access__mdt r : Performance_Dashboard_Access__mdt.getAll().values()) {
            if (r.Is_Active__c && r.Designation__c != null && r.Designation__c.trim().equalsIgnoreCase(role)) {
                return true;
            }
        }
        return false;
    }

    // ---------------------------------------------------------------- team
    /** Self + all active users below rootId in the User.ManagerId hierarchy (all levels). */
    public static Set<Id> selfAndReports(Id rootId) {
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

    public static Integer directReportCount(Id userId) {
        return [SELECT COUNT() FROM User WHERE ManagerId = :userId AND IsActive = true];
    }

    // ---------------------------------------------------------------- Card 1
    public static PerformanceDashboardDTO.HeaderDTO buildHeader(User me) {
        PerformanceDashboardDTO.HeaderDTO h = new PerformanceDashboardDTO.HeaderDTO();
        h.userName = me.Name;
        h.division = me.Division;
        h.designation = me.Employee_Role__c;
        h.directReports = directReportCount(me.Id);
        return h;
    }

    // ---------------------------------------------------------------- secondary sales (grouped)
    /** Team secondary sales between two dates. GROUP BY owner: row cost = number of owners, not invoices. */
    public static Decimal secondarySales(Set<Id> teamIds, Date fromD, Date toD) {
        Decimal total = 0;
        for (AggregateResult ar : [
            SELECT Retailer_Account__r.OwnerId o, SUM(Invoice_Amount__c) t
            FROM Invoice__c
            WHERE Retailer_Account__r.OwnerId IN :teamIds
              AND Invoice_Date__c >= :fromD
              AND Invoice_Date__c <= :toD
              AND RecordType.DeveloperName = 'Secondary_Invoice'
              AND Status__c NOT IN ('Draft', 'Cancelled')
            GROUP BY Retailer_Account__r.OwnerId
        ]) {
            if (ar.get('t') != null) total += (Decimal) ar.get('t');
        }
        return total;
    }

    /** User's OWN uploaded secondary target: Sales_Target__c month rows whose month starts in [fromD..toD]. */
    public static Decimal ownTarget(Id userId, Date fromD, Date toD) {
        AggregateResult ar = [
            SELECT SUM(Secondary_Sales_Target__c) t
            FROM Sales_Target__c
            WHERE Assigned_To__c = :userId
              AND RecordType.DeveloperName = 'Sales_Target_Month'
              AND From_Date__c >= :fromD
              AND From_Date__c <= :toD
        ];
        return (ar.get('t') == null) ? 0 : (Decimal) ar.get('t');
    }

    /** Growth % vs last year; null when last year = 0 (card shows a dash). */
    public static Decimal growthPercent(Decimal current, Decimal lastYear) {
        if (lastYear == null || lastYear == 0) return null;
        return ((current - lastYear) / lastYear * 100).setScale(1);
    }

    // ---------------------------------------------------------------- Card 2
    public static PerformanceDashboardDTO.TargetDTO buildTarget(Id userId, Set<Id> teamIds, Window w) {
        PerformanceDashboardDTO.TargetDTO t = new PerformanceDashboardDTO.TargetDTO();
        t.target = ownTarget(userId, w.startDate, w.endDate);
        t.periodTarget = (w.mode == MODE_YTD) ? ownTarget(userId, w.startDate, w.periodEnd) : t.target;
        t.achievement = secondarySales(teamIds, w.startDate, w.endDate);
        t.percent = (t.target == 0) ? 0 : (t.achievement / t.target * 100).setScale(1);
        t.balance = (t.periodTarget > t.achievement) ? (t.periodTarget - t.achievement) : 0;
        t.remainingDays = w.remainingDays;
        t.rrr = (t.balance == 0 || w.remainingDays <= 0) ? 0 : (t.balance / w.remainingDays).setScale(0);
        return t;
    }

    // ---------------------------------------------------------------- Card 4
    public static PerformanceDashboardDTO.GrowthDTO buildGrowth(Set<Id> teamIds, Window w, Decimal current) {
        PerformanceDashboardDTO.GrowthDTO g = new PerformanceDashboardDTO.GrowthDTO();
        g.current = current;
        g.lastYear = secondarySales(teamIds, w.lyStart, w.lyEnd);
        g.growthPercent = growthPercent(g.current, g.lastYear);
        return g;
    }

    // ---------------------------------------------------------------- calls (grouped)
    /** Team calls in [fromD..toD]: [0] = total calls (check-in OR start-call at a real outlet), [1] = productive (order placed). */
    public static List<Integer> callCounts(Set<Id> teamIds, Date fromD, Date toD) {
        Integer tc = 0, pc = 0;
        for (AggregateResult ar : [
            SELECT Visitor_Name__c v, Order_Placed__c op, COUNT(Id) c
            FROM Visit_Task__c
            WHERE Visitor_Name__c IN :teamIds
              AND Task_Planned_Date__c >= :fromD
              AND Task_Planned_Date__c <= :toD
              AND Retailer__c != null
              AND (Checked_In_Time__c != null OR Start_Call_Time__c != null)
            GROUP BY Visitor_Name__c, Order_Placed__c
        ]) {
            Integer c = (Integer) ar.get('c');
            tc += c;
            if ((Boolean) ar.get('op') == true) pc += c;
        }
        return new List<Integer>{ tc, pc };
    }

    public static Decimal pct(Decimal part, Decimal whole) {
        return (whole == null || whole == 0) ? 0 : (part / whole * 100).setScale(1);
    }

    // ---------------------------------------------------------------- Card 3
    public static PerformanceDashboardDTO.CallsDTO buildCalls(Set<Id> teamIds, Window w) {
        PerformanceDashboardDTO.CallsDTO c = new PerformanceDashboardDTO.CallsDTO();
        List<Integer> r = callCounts(teamIds, w.startDate, w.endDate);
        c.totalCalls = r[0];
        c.productiveCalls = r[1];
        c.percent = pct(c.productiveCalls, c.totalCalls);
        return c;
    }

    // ---------------------------------------------------------------- Card 6 (today)
    /** Team members (excluding the viewer) on the SFA profiles, with today's latest attendance status. */
    public static PerformanceDashboardDTO.AttendanceDTO buildAttendance(Id selfId, Set<Id> teamIds, Date today) {
        PerformanceDashboardDTO.AttendanceDTO a = new PerformanceDashboardDTO.AttendanceDTO();
        Set<Id> sfa = new Map<Id, User>([
            SELECT Id FROM User
            WHERE Id IN :teamIds AND Id != :selfId AND IsActive = true
              AND Profile.Name IN ('SFA Profile', 'SFA Profile - Light')
        ]).keySet();
        a.total = sfa.size();
        if (sfa.isEmpty()) return a;

        Map<Id, String> statusByUser = new Map<Id, String>();
        for (Attendance__c att : [
            SELECT User__c, Status__c
            FROM Attendance__c
            WHERE User__c IN :sfa AND Date_of_attendance__c = :today
            ORDER BY CreatedDate DESC
        ]) {
            if (!statusByUser.containsKey(att.User__c)) statusByUser.put(att.User__c, att.Status__c);
        }
        for (String st : statusByUser.values()) {
            if (st == 'Present' || st == 'Late' || st == 'Present Half Day') a.present += 1;
            else if (st == 'Leave') a.leaveCount += 1;
            else if (st == 'Absent' || st == 'Present Half Day / Absent') a.absent += 1;
            else a.present += 1; // any other marked status counts as present
        }
        a.notMarked = a.total - statusByUser.size();
        return a;
    }

    // ---------------------------------------------------------------- primary (grouped by HUB)
    /** Distinct Divisions (= HUB names) of the team. */
    public static Set<String> teamDivisions(Set<Id> teamIds) {
        Set<String> hubs = new Set<String>();
        for (User u : [SELECT Division FROM User WHERE Id IN :teamIds AND Division != null]) hubs.add(u.Division);
        return hubs;
    }

    /** Primary sale per HUB: Primary_Invoice, all statuses, Super Stockist / Direct Distributor only. */
    public static Map<String, Decimal> primaryByHub(Set<String> hubs, Date fromD, Date toD) {
        Map<String, Decimal> m = new Map<String, Decimal>();
        if (hubs.isEmpty()) return m;
        for (AggregateResult ar : [
            SELECT Distributor_Account__r.Hub__c h, SUM(Invoice_Amount__c) t
            FROM Invoice__c
            WHERE RecordType.DeveloperName = 'Primary_Invoice'
              AND Distributor_Account__r.Distributor_Type__c IN ('Super Stockist', 'Direct Distributor')
              AND Distributor_Account__r.Hub__c IN :hubs
              AND Invoice_Date__c >= :fromD
              AND Invoice_Date__c <= :toD
            GROUP BY Distributor_Account__r.Hub__c
        ]) {
            m.put((String) ar.get('h'), ar.get('t') == null ? 0 : (Decimal) ar.get('t'));
        }
        return m;
    }

    public static Decimal sumValues(Map<String, Decimal> m) {
        Decimal s = 0;
        for (Decimal d : m.values()) s += d;
        return s;
    }

    // ---------------------------------------------------------------- Card 8
    public static PerformanceDashboardDTO.GrowthDTO buildPrimary(Set<String> hubs, Window w) {
        PerformanceDashboardDTO.GrowthDTO g = new PerformanceDashboardDTO.GrowthDTO();
        g.current = sumValues(primaryByHub(hubs, w.startDate, w.endDate));
        g.lastYear = sumValues(primaryByHub(hubs, w.lyStart, w.lyEnd));
        g.growthPercent = growthPercent(g.current, g.lastYear);
        return g;
    }

    // ---------------------------------------------------------------- Card 9 (today)
    public static PerformanceDashboardDTO.TodayDTO buildToday(Set<Id> teamIds, Date today) {
        PerformanceDashboardDTO.TodayDTO t = new PerformanceDashboardDTO.TodayDTO();
        // Secondary orders created today, Draft excluded.
        for (AggregateResult ar : [
            SELECT OwnerId o, SUM(Total_Order_Value__c) v, COUNT(Id) c
            FROM Order__c
            WHERE OwnerId IN :teamIds
              AND RecordType.DeveloperName = 'Secondary_Order'
              AND Status__c != 'Draft'
              AND CreatedDate = TODAY
            GROUP BY OwnerId
        ]) {
            if (ar.get('v') != null) t.orderValue += (Decimal) ar.get('v');
            t.orderCount += (Integer) ar.get('c');
        }
        // Calls today.
        List<Integer> r = callCounts(teamIds, today, today);
        t.totalCalls = r[0];
        t.productiveCalls = r[1];
        t.pcPercent = pct(t.productiveCalls, t.totalCalls);
        // Freezer (DF) outlets: order value today / DF outlets that ordered today.
        for (AggregateResult ar : [
            SELECT OwnerId o, SUM(Total_Order_Value__c) v, COUNT_DISTINCT(Account__c) c
            FROM Order__c
            WHERE OwnerId IN :teamIds
              AND RecordType.DeveloperName = 'Secondary_Order'
              AND Status__c != 'Draft'
              AND CreatedDate = TODAY
              AND Account__c IN (SELECT Retailer__c FROM Asset_Mapping__c
                                 WHERE Active__c = true AND Retailer__r.Is_Active__c = true)
            GROUP BY OwnerId
        ]) {
            if (ar.get('v') != null) t.dfOrderValue += (Decimal) ar.get('v');
            t.dfOutletsOrdered += (Integer) ar.get('c');
        }
        t.dfThroughPut = (t.dfOutletsOrdered == 0) ? 0 : (t.dfOrderValue / t.dfOutletsOrdered).setScale(0);
        return t;
    }

    // ---------------------------------------------------------------- Card 5 (separate call)
    /** Freezers = active Asset_Mapping__c at active outlets owned by the team. All grouped (org has ~45k freezers). */
    public static PerformanceDashboardDTO.FreezerDTO buildFreezer(Set<Id> teamIds, Window w) {
        PerformanceDashboardDTO.FreezerDTO f = new PerformanceDashboardDTO.FreezerDTO();
        Date fromD = w.startDate;
        Date toD = w.endDate;
        for (AggregateResult ar : [
            SELECT Retailer__r.OwnerId o, COUNT(Id) c
            FROM Asset_Mapping__c
            WHERE Active__c = true
              AND Retailer__r.Is_Active__c = true
              AND Retailer__r.OwnerId IN :teamIds
            GROUP BY Retailer__r.OwnerId
        ]) {
            f.activeFreezers += (Integer) ar.get('c');
        }
        if (f.activeFreezers == 0) return f;
        // Billed = freezers whose outlet had a secondary sale in the period.
        for (AggregateResult ar : [
            SELECT Retailer__r.OwnerId o, COUNT(Id) c
            FROM Asset_Mapping__c
            WHERE Active__c = true
              AND Retailer__r.Is_Active__c = true
              AND Retailer__r.OwnerId IN :teamIds
              AND Retailer__c IN (SELECT Retailer_Account__c FROM Invoice__c
                                  WHERE RecordType.DeveloperName = 'Secondary_Invoice'
                                    AND Status__c NOT IN ('Draft', 'Cancelled')
                                    AND Invoice_Date__c >= :fromD
                                    AND Invoice_Date__c <= :toD)
            GROUP BY Retailer__r.OwnerId
        ]) {
            f.billedFreezers += (Integer) ar.get('c');
        }
        // Secondary sale at freezer outlets in the period.
        for (AggregateResult ar : [
            SELECT Retailer_Account__r.OwnerId o, SUM(Invoice_Amount__c) t
            FROM Invoice__c
            WHERE Retailer_Account__r.OwnerId IN :teamIds
              AND RecordType.DeveloperName = 'Secondary_Invoice'
              AND Status__c NOT IN ('Draft', 'Cancelled')
              AND Invoice_Date__c >= :fromD
              AND Invoice_Date__c <= :toD
              AND Retailer_Account__c IN (SELECT Retailer__c FROM Asset_Mapping__c
                                          WHERE Active__c = true AND Retailer__r.Is_Active__c = true)
            GROUP BY Retailer_Account__r.OwnerId
        ]) {
            if (ar.get('t') != null) f.dfSale += (Decimal) ar.get('t');
        }
        f.billedPercent = pct(f.billedFreezers, f.activeFreezers);
        f.perFreezer = (f.dfSale / f.activeFreezers).setScale(0);
        return f;
    }

    // ---------------------------------------------------------------- Card 7 (separate call)
    /** HUB key: Division compared case-insensitively and trimmed ('GOA' = 'Goa', 'Pune city' = 'Pune City'). */
    public static String hubKey(String division) {
        return String.isBlank(division) ? null : division.trim().toUpperCase();
    }

    /** Secondary sales per owner (grouped) for the team in [fromD..toD]. */
    public static Map<Id, Decimal> salesByOwner(Set<Id> teamIds, Date fromD, Date toD) {
        Map<Id, Decimal> m = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Retailer_Account__r.OwnerId o, SUM(Invoice_Amount__c) t
            FROM Invoice__c
            WHERE Retailer_Account__r.OwnerId IN :teamIds
              AND Invoice_Date__c >= :fromD
              AND Invoice_Date__c <= :toD
              AND RecordType.DeveloperName = 'Secondary_Invoice'
              AND Status__c NOT IN ('Draft', 'Cancelled')
            GROUP BY Retailer_Account__r.OwnerId
        ]) {
            m.put((Id) ar.get('o'), ar.get('t') == null ? 0 : (Decimal) ar.get('t'));
        }
        return m;
    }

    /** Own uploaded targets per user (grouped) for months starting in [fromD..toD]. */
    public static Map<Id, Decimal> targetsByUser(Set<Id> userIds, Date fromD, Date toD) {
        Map<Id, Decimal> m = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Assigned_To__c u, SUM(Secondary_Sales_Target__c) t
            FROM Sales_Target__c
            WHERE Assigned_To__c IN :userIds
              AND RecordType.DeveloperName = 'Sales_Target_Month'
              AND From_Date__c >= :fromD
              AND From_Date__c <= :toD
            GROUP BY Assigned_To__c
        ]) {
            m.put((Id) ar.get('u'), ar.get('t') == null ? 0 : (Decimal) ar.get('t'));
        }
        return m;
    }

    /** In-memory hierarchy of the viewer's team, used by Card 7. */
    public class Team {
        public Map<Id, User> users = new Map<Id, User>();
        public Map<Id, List<Id>> children = new Map<Id, List<Id>>();
        public Map<Id, Decimal> sales = new Map<Id, Decimal>();
        private Map<Id, Decimal> subtreeSalesMemo = new Map<Id, Decimal>();
        private Map<Id, Set<String>> subtreeDivMemo = new Map<Id, Set<String>>();

        public Team(Set<Id> teamIds, Map<Id, Decimal> sales) {
            this.sales = sales;
            for (User u : [SELECT Id, Name, ManagerId, Division, Employee_Role__c FROM User WHERE Id IN :teamIds]) {
                users.put(u.Id, u);
            }
            for (User u : users.values()) {
                if (u.ManagerId != null && users.containsKey(u.ManagerId)) {
                    if (!children.containsKey(u.ManagerId)) children.put(u.ManagerId, new List<Id>());
                    children.get(u.ManagerId).add(u.Id);
                }
            }
        }

        public List<Id> kids(Id uid) {
            return children.containsKey(uid) ? children.get(uid) : new List<Id>();
        }

        public Decimal subtreeSales(Id uid) {
            if (subtreeSalesMemo.containsKey(uid)) return subtreeSalesMemo.get(uid);
            Decimal s = sales.containsKey(uid) ? sales.get(uid) : 0;
            for (Id k : kids(uid)) s += subtreeSales(k);
            subtreeSalesMemo.put(uid, s);
            return s;
        }

        public Set<String> subtreeDivisions(Id uid) {
            if (subtreeDivMemo.containsKey(uid)) return subtreeDivMemo.get(uid);
            Set<String> d = new Set<String>();
            String key = hubKey(users.get(uid).Division);
            if (key != null) d.add(key);
            for (Id k : kids(uid)) d.addAll(subtreeDivisions(k));
            subtreeDivMemo.put(uid, d);
            return d;
        }

        /** First ZSM walking up from uid (inclusive) inside the team, else first RSM, else uid itself. */
        public User labelFor(Id uid) {
            User rsm = null;
            Id cur = uid;
            while (cur != null && users.containsKey(cur)) {
                User u = users.get(cur);
                if (u.Employee_Role__c == 'ZSM') return u;
                if (rsm == null && u.Employee_Role__c == 'RSM') rsm = u;
                cur = u.ManagerId;
            }
            return (rsm != null) ? rsm : users.get(uid);
        }
    }

    public static PerformanceDashboardDTO.RegionDTO buildRegion(Id viewerId, Set<Id> teamIds, Window w) {
        PerformanceDashboardDTO.RegionDTO r = new PerformanceDashboardDTO.RegionDTO();
        Team t = new Team(teamIds, salesByOwner(teamIds, w.startDate, w.endDate));
        Map<Id, Decimal> targets = targetsByUser(teamIds, w.startDate, w.endDate);

        // HUB key -> members; display name = the spelling most members use
        Map<String, List<Id>> hubMembers = new Map<String, List<Id>>();
        Map<String, Map<String, Integer>> spellings = new Map<String, Map<String, Integer>>();
        Set<String> rawDivisions = new Set<String>();
        for (User u : t.users.values()) {
            String key = hubKey(u.Division);
            if (key == null) continue;
            rawDivisions.add(u.Division.trim());
            if (!hubMembers.containsKey(key)) { hubMembers.put(key, new List<Id>()); spellings.put(key, new Map<String, Integer>()); }
            hubMembers.get(key).add(u.Id);
            String sp = u.Division.trim();
            Map<String, Integer> sc = spellings.get(key);
            sc.put(sp, sc.containsKey(sp) ? sc.get(sp) + 1 : 1);
        }
        Map<String, Decimal> primary = new Map<String, Decimal>();
        Map<String, Decimal> primaryRaw = primaryByHub(rawDivisions, w.startDate, w.endDate);
        for (String k : primaryRaw.keySet()) {
            String pk = hubKey(k);
            primary.put(pk, (primary.containsKey(pk) ? primary.get(pk) : 0) + primaryRaw.get(k));
        }

        List<String> hubKeys = new List<String>(hubMembers.keySet());
        hubKeys.sort();
        for (String hub : hubKeys) {
            // A HUB whose only member is the viewer (e.g. the VP's own Division) is not a real HUB row.
            if (hubMembers.get(hub).size() == 1 && hubMembers.get(hub)[0] == viewerId) continue;
            String displayName = null;
            Integer best = -1;
            for (String sp : spellings.get(hub).keySet()) {
                if (spellings.get(hub).get(sp) > best) { best = spellings.get(hub).get(sp); displayName = sp; }
            }
            // Heads = HUB members whose manager is outside this HUB (or outside the team).
            List<Id> heads = new List<Id>();
            for (Id uid : hubMembers.get(hub)) {
                User u = t.users.get(uid);
                User mgr = (u.ManagerId != null) ? t.users.get(u.ManagerId) : null;
                if (mgr == null || hubKey(mgr.Division) != hub) heads.add(uid);
            }
            // Multi-HUB heads (e.g. a ZSM covering 3 HUBs) are replaced by their reports inside this HUB.
            Boolean expanded = true;
            Integer guard = 0;
            while (expanded && guard < 10) {
                expanded = false;
                guard++;
                List<Id> next = new List<Id>();
                for (Id h : heads) {
                    List<Id> inHub = new List<Id>();
                    if (t.subtreeDivisions(h).size() > 1) {
                        for (Id k : t.kids(h)) if (hubKey(t.users.get(k).Division) == hub) inHub.add(k);
                    }
                    if (inHub.isEmpty()) {
                        next.add(h);           // single-HUB head, or no reports inside this HUB: keep the head
                    } else {
                        next.addAll(inHub);
                        expanded = true;
                    }
                }
                heads = next;
            }

            PerformanceDashboardDTO.HubDTO h = new PerformanceDashboardDTO.HubDTO();
            h.hub = displayName;
            for (Id hid : heads) h.target += targets.containsKey(hid) ? targets.get(hid) : 0;
            for (Id uid : hubMembers.get(hub)) h.achievement += t.sales.containsKey(uid) ? t.sales.get(uid) : 0;
            h.percent = pct(h.achievement, h.target);
            h.primarySale = primary.containsKey(hub) ? primary.get(hub) : 0;
            if (!heads.isEmpty()) {
                User label = t.labelFor(heads[0]);
                h.headName = label.Name;
                h.headDesignation = label.Employee_Role__c;
            }
            // Drill (one level): a single head -> its reports in this HUB; several heads -> the heads.
            List<Id> drill = new List<Id>();
            if (heads.size() == 1) {
                for (Id k : t.kids(heads[0])) if (hubKey(t.users.get(k).Division) == hub) drill.add(k);
            } else {
                drill.addAll(heads);
            }
            for (Id mid : drill) {
                User mu = t.users.get(mid);
                PerformanceDashboardDTO.MemberDTO m = new PerformanceDashboardDTO.MemberDTO();
                m.userId = mid;
                m.name = mu.Name;
                m.designation = mu.Employee_Role__c;
                m.target = targets.containsKey(mid) ? targets.get(mid) : 0;
                m.achievement = t.subtreeSales(mid);
                m.percent = pct(m.achievement, m.target);
                h.members.add(m);
            }
            r.hubs.add(h);
        }
        return r;
    }
}