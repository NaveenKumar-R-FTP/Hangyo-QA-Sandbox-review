@isTest
private class DailyExpenseRecordSchedulerTest {

    @TestSetup
    static void setupTestData() {
        // Create User Roles
        UserRole userRoleSSO = new UserRole(Name = 'SSO');
        insert userRoleSSO;

        UserRole userRoleASM = new UserRole(Name = 'ASM');
        insert userRoleASM;

        // Unique suffix for usernames and emails to avoid conflicts
        String uniqueSuffix = String.valueOf(DateTime.now().getTime());

        // Create test user with Employee_Role__c = 'ASM'
        User testUserASM = new User(
            Alias = 'tuser',
            FirstName = 'Sam',
            LastName = 'Shaw',
            Email = 'samshaw' + uniqueSuffix + '@example.com',
            ProfileId = UserInfo.getProfileId(),
            UserRoleId = userRoleASM.Id,
            Username = 'samshaw' + uniqueSuffix + '@example.com',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Employee_Role__c = 'ASM'
        );
        insert testUserASM;

        // Create test user with Employee_Role__c = 'SSO'
        User testUserSSO = new User(
            Alias = 'tuser2',
            FirstName = 'Jam',
            LastName = 'Sez',
            Email = 'jamsez' + uniqueSuffix + '@example.com',
            ProfileId = UserInfo.getProfileId(),
            UserRoleId = userRoleSSO.Id,
            Username = 'jamsez' + uniqueSuffix + '@example.com',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            L1_Approver__c = testUserASM.Id,
            Employee_Role__c = 'SSO'
        );
        insert testUserSSO;

        System.runAs(testUserASM) {
            // Create active entitlement records
            List<Expense_Entitlement__c> entitlements = new List<Expense_Entitlement__c>{
                new Expense_Entitlement__c(
                    Role__c = 'SSO',
                    DA_Allowance__c = 100.00,
                    TA_Allowance__c = 200.00,
                    Active__c = true
                ),
                new Expense_Entitlement__c(
                    Role__c = 'ASM',
                    DA_Allowance__c = 100.00,
                    TA_Allowance__c = 200.00,
                    Active__c = true
                )
            };
            insert entitlements;

            // Create expense claim for testUserSSO
            Expense_Claim__c expenseClaim = new Expense_Claim__c(
                Name = 'Test Claim 1',
                Start_Date__c = Date.today(),
                User__c = testUserSSO.Id
            );
            insert expenseClaim;

            // ✅ Create attendance record for testUserSSO (must exist for expenses to be created)
            Attendance__c attendance = new Attendance__c(
                User__c = testUserSSO.Id,
                Status__c = 'Present',
                Date_of_attendance__c = Date.today()
            );
            insert attendance;
        }
    }

    @isTest
    static void testCreateDailyExpenses() {
        // Get the test claim created for the SSO user
        Expense_Claim__c claim = [SELECT Id FROM Expense_Claim__c LIMIT 1];

        Test.startTest();
        // Run scheduler method
        DailyExpenseRecordScheduler.createDailyExpenses();
        Test.stopTest();

        // Query expenses related to the test claim
        List<Expense__c> expenses = [
            SELECT Expense_Category__c, Amount__c 
            FROM Expense__c 
            WHERE Expense_Claim__c = :claim.Id
        ];

        // Assert 2 expenses created: Daily Allowance & Travel Allowance
        System.assertEquals(2, expenses.size(), 'Expected exactly 2 expense records.');

        Boolean foundDA = false;
        Boolean foundTA = false;

        for (Expense__c exp : expenses) {
            if (exp.Expense_Category__c == 'Daily Allowance') {
                System.assertEquals(100.00, exp.Amount__c, 'Daily Allowance amount mismatch.');
                foundDA = true;
            } else if (exp.Expense_Category__c == 'Travel Allowance') {
                System.assertEquals(200.00, exp.Amount__c, 'Travel Allowance amount mismatch.');
                foundTA = true;
            }
        }

        System.assert(foundDA, 'Daily Allowance expense was not created.');
        System.assert(foundTA, 'Travel Allowance expense was not created.');
    }
}