/**
 * Shared @TestSetup data for User Tracking dashboard tests (Attendance, Visit_Task, Order, Account).
 */
@IsTest
public class UserTrackingTestDataFactory {
    private static final String RT_RETAILER = 'Retailer';
    private static ScenarioData cachedScenario;

    public class ScenarioData {
        public Id userId;
        public Date selectedDate;
        public Id productiveVisitId;
        public Id attendanceId;
    }

    public static void createDashboardScenario() {
        ensureRetailerCodeSetting();
        User runUser = createStandardUser('utd_main');
        Date selectedDate = Date.today();

        Account outlet = createRetailerAccount('UTD Outlet ' + String.valueOf(Crypto.getRandomInteger()));
        Attendance__c att = createAttendance(
            runUser.Id,
            selectedDate,
            'Present',
            'HQ check-in notes',
            12.989024,
            77.592635,
            false,
            null,
            null
        );

        /* Workflow may set Attendance_Applied_on__c on insert; visits/EOD must be after that anchor. */
        att = [
            SELECT Attendance_Applied_on__c, Date_of_attendance__c, CreatedDate
            FROM Attendance__c
            WHERE Id = :att.Id
            LIMIT 1
        ];
        Datetime lifecycleAnchor = resolveAttendanceLifecycleAnchor(att, selectedDate);

        att.EOD_Date_Time__c = lifecycleAnchor.addHours(4);
        att.EOD_Location__Latitude__s = 12.988000;
        att.EOD_Location__Longitude__s = 77.590000;
        update att;

        Visit_Task__c productive = createVisitTask(
            runUser.Id,
            selectedDate,
            outlet.Id,
            true,
            lifecycleAnchor.addHours(1),
            13.001,
            77.601
        );
        createVisitTask(
            runUser.Id,
            selectedDate,
            outlet.Id,
            false,
            lifecycleAnchor.addHours(2),
            13.002,
            77.602
        );

        createOrder(productive.Id, runUser.Id, selectedDate, outlet.Id, 500);
        System.runAs(runUser) {
            createRetailerAccountWithGeo(lifecycleAnchor.addHours(3), 'UTD New Outlet');
        }

        cachedScenario = new ScenarioData();
        cachedScenario.userId = runUser.Id;
        cachedScenario.selectedDate = selectedDate;
        cachedScenario.productiveVisitId = productive.Id;
        cachedScenario.attendanceId = att.Id;
    }

    public static ScenarioData getScenario() {
        if (cachedScenario != null) {
            return cachedScenario;
        }
        User u = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'utd_main%@example.com'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        Date d = Date.today();
        List<Visit_Task__c> visits = [
            SELECT Id
            FROM Visit_Task__c
            WHERE Visitor_Name__c = :u.Id
              AND Task_Planned_Date__c = :d
              AND Order_Placed__c = TRUE
            LIMIT 1
        ];
        ScenarioData data = new ScenarioData();
        data.userId = u.Id;
        data.selectedDate = d;
        data.productiveVisitId = visits.isEmpty() ? null : visits[0].Id;
        List<Attendance__c> atts = [
            SELECT Id
            FROM Attendance__c
            WHERE User__c = :u.Id AND Date_of_attendance__c = :d
            LIMIT 1
        ];
        data.attendanceId = atts.isEmpty() ? null : atts[0].Id;
        return data;
    }

    public static User createStandardUser(String aliasPrefix) {
        return createStandardUser(aliasPrefix, null);
    }

    public static User createStandardUser(String aliasPrefix, String employeeRole) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String token = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User u = new User(
            Alias = (aliasPrefix + token).left(8),
            Email = aliasPrefix + token + '@hangyo.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TrackingTest',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = aliasPrefix + token + '@example.com'
        );
        if (
            String.isNotBlank(employeeRole) &&
            Schema.SObjectType.User.fields.getMap().containsKey('Employee_Role__c')
        ) {
            u.put('Employee_Role__c', employeeRole.trim());
        }
        insert u;
        return u;
    }

    /**
     * Account BeforeInsert runs GenerateRetailerCreationCode, which NPEs when
     * RetailerCodeSetting__c (Name=SF) is missing or Latest_Code__c is null.
     */
    public static void ensureRetailerCodeSetting() {
        if (!Schema.getGlobalDescribe().containsKey('RetailerCodeSetting__c')) {
            return;
        }
        List<RetailerCodeSetting__c> rows = [
            SELECT Id, Latest_Code__c
            FROM RetailerCodeSetting__c
            WHERE Name = 'SF'
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            insert new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 1);
            return;
        }
        if (rows[0].Latest_Code__c == null) {
            rows[0].Latest_Code__c = 1;
            update rows[0];
        }
    }

    public static Account createRetailerAccount(String name) {
        ensureRetailerCodeSetting();
        Id rtId = retailerRecordTypeId();
        Account acc = new Account(Name = name);
        if (rtId != null) {
            acc.RecordTypeId = rtId;
        }
        insert acc;
        return acc;
    }

    public static void createRetailerAccountWithGeo(Datetime createdAt, String name) {
        ensureRetailerCodeSetting();
        Id rtId = retailerRecordTypeId();
        Account acc = new Account(
            Name = name,
            BillingLatitude = 13.050000,
            BillingLongitude = 77.650000,
            Onboard_Date__c = createdAt.date(),
            Latitude__c = '13.050000',
            Longitude__c = '77.650000'
        );
        if (rtId != null) {
            acc.RecordTypeId = rtId;
        }
        insert acc;
        Test.setCreatedDate(acc.Id, createdAt);
    }

    public static Attendance__c createAttendance(
        Id userId,
        Date onDate,
        String status,
        String description,
        Decimal lat,
        Decimal lng,
        Boolean withEod,
        Decimal eodLat,
        Decimal eodLng
    ) {
        /* Date__c and Attendance_Applied_on__c are read-only in org (formula/workflow); use Date_of_attendance__c only. */
        String statusValue = String.isNotBlank(status) ? status : 'Present';
        Attendance__c att = new Attendance__c(
            User__c = userId,
            Date_of_attendance__c = onDate,
            Status__c = statusValue,
            Description__c = description,
            Location__Latitude__s = lat,
            Location__Longitude__s = lng
        );
        if (withEod) {
            att.EOD_Date_Time__c = DateTime.newInstance(onDate, Time.newInstance(18, 0, 0, 0));
            att.EOD_Location__Latitude__s = eodLat;
            att.EOD_Location__Longitude__s = eodLng;
        }
        insert att;
        return att;
    }

    public static Attendance__c createAttendanceOnly(
        Id userId,
        Date onDate,
        String status,
        Decimal lat,
        Decimal lng,
        Boolean withEod
    ) {
        return createAttendance(userId, onDate, status, null, lat, lng, withEod, null, null);
    }

    public static Visit_Task__c createVisitTask(
        Id visitorId,
        Date plannedDate,
        Id accountId,
        Boolean orderPlaced,
        Datetime checkIn,
        Decimal lat,
        Decimal lng
    ) {
        Datetime endCall = checkIn.addHours(1);
        Beat__c beat = new Beat__c(
            Name = 'UTD Beat ' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );
        insert beat;

        Visit__c visit = new Visit__c(
            Visit_planned_date__c = plannedDate,
            Visitor_Name__c = visitorId,
            Beat__c = beat.Id,
            Status__c = 'Not Started',
            Visit_Type__c = 'Planned'
        );
        insert visit;

        Visit_Task__c vt = new Visit_Task__c(
            Visit__c = visit.Id,
            Beat__c = beat.Id,
            Visitor_Name__c = visitorId,
            Task_Planned_Date__c = plannedDate,
            Account__c = accountId,
            Retailer__c = accountId,
            Order_Placed__c = orderPlaced,
            Status__c = 'In-Progress',
            Checked_In_Time__c = checkIn,
            Checked_Out_Time__c = endCall,
            End_Call_Time__c = endCall,
            Checked_In_Location__Latitude__s = lat,
            Checked_In_Location__Longitude__s = lng
        );
        insert vt;
        return vt;
    }

    public static void createVisitOnly(Id visitorId, Date plannedDate, Boolean productive) {
        ensureRetailerCodeSetting();
        Account outlet = createRetailerAccount('UTD Visit Only');
        createVisitTask(
            visitorId,
            plannedDate,
            outlet.Id,
            productive,
            DateTime.newInstance(plannedDate, Time.newInstance(9, 0, 0, 0)),
            13.01,
            77.61
        );
    }

    public static Order__c createOrder(
        Id visitTaskId,
        Id ownerId,
        Date effectiveDate,
        Id accountId,
        Decimal totalValue
    ) {
        Order__c ord = new Order__c(
            Visit_Task__c = visitTaskId,
            OwnerId = ownerId,
            EffectiveDate__c = effectiveDate,
            Account__c = accountId,
            Total_Order_Value__c = totalValue
        );
        Id orderRtId = primaryOrderRecordTypeId();
        if (orderRtId != null) {
            ord.RecordTypeId = orderRtId;
        }
        insert ord;
        return ord;
    }

    public static void addSecondOrderForVisit(
        Id visitTaskId,
        Id ownerId,
        Date effectiveDate,
        Decimal totalValue
    ) {
        List<Visit_Task__c> visits = [SELECT Account__c FROM Visit_Task__c WHERE Id = :visitTaskId LIMIT 1];
        Id accountId = visits.isEmpty() ? null : visits[0].Account__c;
        createOrder(visitTaskId, ownerId, effectiveDate, accountId, totalValue);
    }

    private static Datetime resolveAttendanceLifecycleAnchor(Attendance__c att, Date onDate) {
        if (att == null) {
            return DateTime.newInstance(onDate, Time.newInstance(8, 0, 0, 0));
        }
        if (att.Attendance_Applied_on__c != null) {
            return att.Attendance_Applied_on__c;
        }
        if (att.CreatedDate != null) {
            return att.CreatedDate;
        }
        return DateTime.newInstance(onDate, Time.newInstance(8, 0, 0, 0));
    }

    private static Id retailerRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account' AND Name = :RT_RETAILER
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static Id primaryOrderRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Order__c' AND Name = 'Primary Order'
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }
}