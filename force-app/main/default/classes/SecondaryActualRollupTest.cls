/**
 * SecondaryActualRollupTest
 * ---------------------------------------------------------------------------
 * The rollup math (own + all descendants) and the row building are pure and are
 * unit-tested deterministically with synthetic hierarchies — no dependency on
 * org data or automation. persist() is covered against Sales_Target__c (which has
 * no triggers), and run()/schedule are exercised end to end for the SOQL paths.
 */
@isTest
private class SecondaryActualRollupTest {

    // A,B,C,D each 1,00,000 report to X -> X team = 4,00,000 (own 0 + four reports).
    @isTest
    static void teamRollup_ownPlusAllDescendants() {
        Id x = fakeUserId(1), a = fakeUserId(2), b = fakeUserId(3), c = fakeUserId(4), d = fakeUserId(5);
        Map<Id, List<Id>> children = new Map<Id, List<Id>>{ x => new List<Id>{ a, b, c, d } };
        Map<Id, Decimal> individual = new Map<Id, Decimal>{
            a => 100000, b => 100000, c => 100000, d => 100000
        };
        Map<Id, Decimal> team = new Map<Id, Decimal>();

        System.assertEquals(400000, SecondaryActualRollup.computeTeam(x, children, individual, team),
            'X team = A+B+C+D (own 0)');
        System.assertEquals(100000, team.get(a), 'A team = own only (no reports)');
    }

    // Multi-level: X <- Y <- Z. Each has own 100000 -> X = 300000, Y = 200000.
    @isTest
    static void teamRollup_multiLevel() {
        Id x = fakeUserId(11), y = fakeUserId(12), z = fakeUserId(13);
        Map<Id, List<Id>> children = new Map<Id, List<Id>>{
            x => new List<Id>{ y }, y => new List<Id>{ z }
        };
        Map<Id, Decimal> individual = new Map<Id, Decimal>{ x => 100000, y => 100000, z => 100000 };
        Map<Id, Decimal> team = new Map<Id, Decimal>();
        System.assertEquals(300000, SecondaryActualRollup.computeTeam(x, children, individual, team), 'X = own + Y + Z');
        System.assertEquals(200000, team.get(y), 'Y = own + Z');
        System.assertEquals(100000, team.get(z), 'Z = own only');
    }

    @isTest
    static void buildRows_skipsZeroAndKeysProperly() {
        Id a = fakeUserId(21), zero = fakeUserId(22);
        Set<Id> users = new Set<Id>{ a, zero };
        Map<Id, Decimal> individual = new Map<Id, Decimal>{ a => 50000, zero => 0 };
        Map<Id, Decimal> team       = new Map<Id, Decimal>{ a => 50000, zero => 0 };
        Date asOf = Date.newInstance(2026, 8, 15);

        List<Sales_Target__c> rows = SecondaryActualRollup.buildRows(individual, team, users, asOf);
        System.assertEquals(1, rows.size(), 'zero-actual user is skipped');
                System.assertEquals(String.valueOf(a) + '-2026-08', rows[0].Target_Key__c, 'key = 18charId-YYYY-MM');
        System.assertEquals(50000, rows[0].Secondary_Sales_Actual__c, 'individual set');
        System.assertEquals(8, rows[0].Number_of_Month__c, 'month number set');
    }

    @isTest
    static void persist_upsertsRow() {
        Id monthRt = Schema.SObjectType.Sales_Target__c
                        .getRecordTypeInfosByDeveloperName().get('Sales_Target_Month').getRecordTypeId();
        Sales_Target__c r = new Sales_Target__c(
            Target_Key__c                   = 'TESTKEY-' + UserInfo.getUserId(),
            Assigned_To__c                  = UserInfo.getUserId(),
            Number_of_Month__c              = Date.today().month(),
            From_Date__c                    = Date.today().toStartOfMonth(),
            To_Date__c                      = Date.today(),
            Secondary_Sales_Actual__c       = 100,
            Team_Secondary_Sales_Actual__c  = 100,
            RecordTypeId                    = monthRt
        );
        Test.startTest();
        SecondaryActualRollup.persist(new List<Sales_Target__c>{ r });
        Test.stopTest();
        System.assertEquals(1,
            [SELECT COUNT() FROM Sales_Target__c WHERE Target_Key__c = :r.Target_Key__c],
            'row upserted');
    }

    @isTest
    static void run_and_schedule_execute() {
        Test.startTest();
        SecondaryActualRollup.run();                       // exercises SOQL + orchestration
        new SecondaryActualRollupSchedule().execute(null); // schedulable wrapper
        Test.stopTest();
        System.assert(true, 'ran without unhandled exception');
    }

    // Deterministic fake 15-char User Id for pure-logic tests.
    static Id fakeUserId(Integer idx) {
        String prefix = User.SObjectType.getDescribe().getKeyPrefix(); // 005
        String suffix = String.valueOf(idx);
        String zeros  = '000000000000000';
        return Id.valueOf(prefix + zeros.substring(0, 15 - prefix.length() - suffix.length()) + suffix);
    }
}