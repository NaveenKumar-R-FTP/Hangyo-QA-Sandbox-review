/**
 * Class Name  : DailyExpenseRecordScheduler
 * Test Class  : DailyExpenseRecordSchedulerTest
 * Author      : Pradvith
 * CreatedDate : 22-12-24
 * Description : This class creates daily TA and DA Expense records for users who are active and present today.
 * Modified by : Ajay
 * Modified date:01-08-25
 * Modification: Added attendance check,active users and updated to new roles to provide daily TA and DA
 */
public with sharing class DailyExpenseRecordScheduler {

    public static void createDailyExpenses() {
        Date today = Date.today();

        // Step 1: Fetch Expense Claims for current month
        List<Expense_Claim__c> expenseClaims = [
            SELECT Id, Name, Start_Date__c, User__c
            FROM Expense_Claim__c
            WHERE CALENDAR_MONTH(Start_Date__c) = :today.month()
                AND CALENDAR_YEAR(Start_Date__c) = :today.year()
        ];

        if (expenseClaims.isEmpty()) return;

        // Step 2: Extract distinct User IDs from claims
        Set<Id> userIds = new Set<Id>();
        for (Expense_Claim__c claim : expenseClaims) {
            if (claim.User__c != null) {
                userIds.add(claim.User__c);
            }
        }

        if (userIds.isEmpty()) return;

        // Step 3: Fetch Active Users only
        Map<Id, User> activeUsersMap = new Map<Id, User>(
            [SELECT Id, Employee_Role__c
             FROM User
             WHERE Id IN :userIds AND IsActive = TRUE]
        );

        if (activeUsersMap.isEmpty()) return;

        // Step 4: Fetch Attendance records for active users for today with Status = 'Present'
        Map<Id, Attendance__c> attendanceMap = new Map<Id, Attendance__c>();
        for (Attendance__c attendance : [
            SELECT Id, User__c , Status__c
            FROM Attendance__c
            WHERE (Status__c = 'Present' OR Status__c = 'Present Half Day')
                AND Date_of_attendance__c = :today
                AND User__c IN :activeUsersMap.keySet()
        ]) {
            attendanceMap.put(attendance.User__c, attendance);
        }

        if (attendanceMap.isEmpty()) return;

        // Step 5: Load entitlement amounts
        Map<String, Map<String, Decimal>> entitlementAmounts = getEntitlementAmounts();

        // Step 6: Prepare Expense records
        List<Expense__c> expenseToInsert = new List<Expense__c>();

        for (Expense_Claim__c claim : expenseClaims) {
            Id userId = claim.User__c;

            // Skip if user is not active or doesn't have present attendance today
            if (!activeUsersMap.containsKey(userId) || !attendanceMap.containsKey(userId)) continue;

            User user = activeUsersMap.get(userId);
            String userRole = user.Employee_Role__c;

            Decimal dailyAllowance = entitlementAmounts.get('DA Allowance').get(userRole);
            Decimal travelAllowance = entitlementAmounts.get('TA Allowance').get(userRole);
            
            Decimal multiplier = (attendanceMap.get(userId).Status__c == 'Present Half Day') ? 0.5 : 1;
            Decimal dayValue = multiplier;

            if (dailyAllowance != null) {
                expenseToInsert.add(new Expense__c(
                    Expense_Claim__c = claim.Id,
                    Expense_Category__c = 'Daily Allowance',
                    Expense_Type__c = 'Daily Allowance',
                    Amount__c = dailyAllowance * multiplier,
                    Status__c = 'Approved',
                    DA_Days__c = dayValue,
                    Approval_status__c = 'Approved',
                    Expense_Date__c = today,
                    Description__c = 'Daily Allowance created',
                    Visitor_Name__c = userId,
                    OwnerId = userId
                ));
            }

            if (travelAllowance != null) {
                expenseToInsert.add(new Expense__c(
                    Expense_Claim__c = claim.Id,
                    Expense_Category__c = 'Travel Allowance',
                    Expense_Type__c = 'Travel Allowance',
                    Amount__c = travelAllowance * multiplier,
                    Status__c = 'Approved',
                    TA_Days__c = dayValue,
                    Approval_status__c = 'Approved',
                    Expense_Date__c = today,
                    Description__c = 'Travel Allowance created',
                    Visitor_Name__c = userId,
                    OwnerId = userId
                ));
            }
        }

        // Step 7: Insert Expenses
        if (!expenseToInsert.isEmpty()) {
            try {
                insert expenseToInsert;
            } catch (DmlException e) {
                throw new DmlException('Error creating expense records: ' + e.getMessage());
            }
        }
    }

    /**
     * Helper method to load DA and TA entitlement amounts per employee role
     */
    private static Map<String, Map<String, Decimal>> getEntitlementAmounts() {
        Map<String, Map<String, Decimal>> entitlementMap = new Map<String, Map<String, Decimal>>();
        entitlementMap.put('DA Allowance', new Map<String, Decimal>());
        entitlementMap.put('TA Allowance', new Map<String, Decimal>());

        List<Expense_Entitlement__c> entitlements = [
            SELECT Role__c, DA_Allowance__c, TA_Allowance__c
            FROM Expense_Entitlement__c
            WHERE Active__c = true
        ];

        for (Expense_Entitlement__c e : entitlements) {
            if (e.Role__c != null) {
                if (e.DA_Allowance__c != null) {
                    entitlementMap.get('DA Allowance').put(e.Role__c, e.DA_Allowance__c);
                }
                if (e.TA_Allowance__c != null) {
                    entitlementMap.get('TA Allowance').put(e.Role__c, e.TA_Allowance__c);
                }
            }
        }

        return entitlementMap;
    }
}