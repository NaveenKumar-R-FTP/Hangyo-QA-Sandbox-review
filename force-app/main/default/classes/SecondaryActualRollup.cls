/**
 * SecondaryActualRollup
 * ---------------------------------------------------------------------------
 * Computes month-to-date SECONDARY SALES actuals per user and rolls them up the
 * Manager (User.ManagerId) hierarchy, then stores the result on each user's
 * monthly Sales_Target__c row (record type "Sales Performance - Month").
 *
 *   Secondary_Sales_Actual__c        = the user's OWN mapped-outlet secondary sales
 *   Team_Secondary_Sales_Actual__c   = own + ALL descendants (every level below)
 *
 * "Individual" == a rep's own outlets (Invoice.Retailer_Account__r.OwnerId = user).
 * Targets are NOT touched here — they are uploaded per level separately; this job
 * only writes the two ACTUAL fields (matched to the uploaded row via Target_Key__c).
 *
 * READ-ONLY on Invoice__c — this never edits or cancels invoices.
 */
public without sharing class SecondaryActualRollup {

    private static final String MONTH_RT = 'Sales_Target_Month';

    /** Recompute current-month actuals. */
    public static void run() { run(Date.today()); }

    public static void run(Date asOf) {
        Map<Id, Decimal> individual = individualActuals(asOf);

        // Build the manager->children map from active users.
        Map<Id, List<Id>> children = new Map<Id, List<Id>>();
        Set<Id> users = new Set<Id>();
        for (User u : [SELECT Id, ManagerId FROM User WHERE IsActive = true]) {
            users.add(u.Id);
            if (u.ManagerId != null) {
                if (!children.containsKey(u.ManagerId)) children.put(u.ManagerId, new List<Id>());
                children.get(u.ManagerId).add(u.Id);
            }
        }

        // Roll each user up to own + all descendants.
        Map<Id, Decimal> team = new Map<Id, Decimal>();
        for (Id uid : users) computeTeam(uid, children, individual, team);

        persist(buildRows(individual, team, users, asOf));
    }

    /** Individual actual = SUM(Invoice_Amount__c) on each rep's mapped outlets, MTD. */
    @TestVisible
    private static Map<Id, Decimal> individualActuals(Date asOf) {
        Date monthStart = asOf.toStartOfMonth();
        Map<Id, Decimal> m = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Retailer_Account__r.OwnerId oid, SUM(Invoice_Amount__c) total
            FROM Invoice__c
            WHERE Invoice_Date__c >= :monthStart
              AND Invoice_Date__c <= :asOf
              AND Retailer_Account__r.OwnerId != null
              AND RecordType.DeveloperName = 'Secondary_Invoice'
              AND Status__c NOT IN ('Draft', 'Cancelled')
            GROUP BY Retailer_Account__r.OwnerId
        ]) {
            Decimal t = (Decimal) ar.get('total');
            m.put((Id) ar.get('oid'), (t == null ? 0 : t));
        }
        return m;
    }

    /** Team actual = own + every descendant (all levels). Memoized; cycle-safe. */
    @TestVisible
    private static Decimal computeTeam(Id uid, Map<Id, List<Id>> children,
                                       Map<Id, Decimal> individual, Map<Id, Decimal> team) {
        return computeTeam(uid, children, individual, team, new Set<Id>());
    }
    private static Decimal computeTeam(Id uid, Map<Id, List<Id>> children,
                                       Map<Id, Decimal> individual, Map<Id, Decimal> team, Set<Id> path) {
        if (team.containsKey(uid)) return team.get(uid);
        if (path.contains(uid)) return individual.containsKey(uid) ? individual.get(uid) : 0; // guard against cycles
        path.add(uid);
        Decimal total = individual.containsKey(uid) ? individual.get(uid) : 0;
        if (children.containsKey(uid)) {
            for (Id ch : children.get(uid)) {
                total += computeTeam(ch, children, individual, team, path);
            }
        }
        path.remove(uid);
        team.put(uid, total);
        return total;
    }

    /** Build the monthly Sales_Target__c rows to upsert (keyed to the uploaded target row). */
    @TestVisible
    private static List<Sales_Target__c> buildRows(Map<Id, Decimal> individual, Map<Id, Decimal> team,
                                                   Set<Id> users, Date asOf) {
        Integer monthNo   = asOf.month();
        Date    monthStart = asOf.toStartOfMonth();
        Date    monthEnd   = Date.newInstance(asOf.year(), asOf.month(),
                                              Date.daysInMonth(asOf.year(), asOf.month()));
        String  mm         = (monthNo < 10) ? '0' + monthNo : String.valueOf(monthNo);
        Id monthRt = Schema.SObjectType.Sales_Target__c
                        .getRecordTypeInfosByDeveloperName().get(MONTH_RT).getRecordTypeId();

        List<Sales_Target__c> rows = new List<Sales_Target__c>();
        for (Id uid : users) {
            Decimal ind = individual.containsKey(uid) ? individual.get(uid) : 0;
            Decimal tm  = team.containsKey(uid)       ? team.get(uid)       : ind;
            if (ind == 0 && tm == 0) continue; // nothing to store for this user this month
                        String key = String.valueOf(uid) + '-' + asOf.year() + '-' + mm;
            rows.add(new Sales_Target__c(
                Target_Key__c                   = key,
                Assigned_To__c                  = uid,
                Number_of_Month__c              = monthNo,
                From_Date__c                    = monthStart,
                To_Date__c                      = monthEnd,
                Secondary_Sales_Actual__c       = ind,
                Team_Secondary_Sales_Actual__c  = tm,
                RecordTypeId                    = monthRt
            ));
        }
        return rows;
    }

    /** Upsert on the external-id key so an uploaded target row gets its actuals filled in place. */
    @TestVisible
    private static void persist(List<Sales_Target__c> rows) {
        if (!rows.isEmpty()) upsert rows Target_Key__c;
    }
}