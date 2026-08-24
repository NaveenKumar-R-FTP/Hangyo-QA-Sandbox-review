@isTest
private class ExpenseControllerTest {
    
    @TestSetup
    static void setupTestData() {
        // Query the required profile. (Ensure 'SFA Profile' exists in production.)
        Profile sfaProfile = [SELECT Id FROM Profile WHERE Name = 'SFA Profile' LIMIT 1];
        
          // Create test users
        User testUserSOl1 = new User(
            ProfileId         = sfaProfile.Id,
            LastName          = 'TestUserl1',
            Email             = 'test.userl1+' + System.currentTimeMillis() + '@example.com',
            Username          = 'test.userl1+' + System.currentTimeMillis() + '@example.com',
            Alias             = 'tuserl1',
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Employee_Role__c  = 'SO'
        );
        insert testUserSOl1;
        
        // Create test users
        User testUserSO = new User(
            ProfileId         = sfaProfile.Id,
            LastName          = 'TestUser',
            Email             = 'test.user+' + System.currentTimeMillis() + '@example.com',
            Username          = 'test.user+' + System.currentTimeMillis() + '@example.com',
            Alias             = 'tuser',
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Employee_Role__c  = 'SO',
            L1_Approver__c = testUserSOl1.id
        );
        insert testUserSO;
        
        User testUserSSO = new User(
            ProfileId         = sfaProfile.Id,
            LastName          = 'Testsso',
            Email             = 'test.user1+' + System.currentTimeMillis() + '@example.com',
            Username          = 'test.user1+' + System.currentTimeMillis() + '@example.com',
            Alias             = 'tuser',
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Employee_Role__c  = 'SSO'
        );
        insert testUserSSO;
        
        // To avoid mixed DML errors, insert non‑setup custom objects within System.runAs
        
        // Insert Expense Entitlements (run as each user for their role)
        System.runAs(testUserSO) {
            Expense_Entitlement__c entitlementSO = new Expense_Entitlement__c(
                Role__c                          = 'SO',
                Active__c                        = true,
                Flight_Allowance_Amount__c       = 5000,
                Bus_Allowance_Amount__c          = 1000,
                Train_Allowance_Amount__c        = 2000,
                Car_Allowance_Amount_per_km__c   = 12,
                Bike_Allowance_Amount_per_Km__c  = 8,
                Class_A_Cities_Amount__c         = 3000,
                Other_Cities_Amount__c           = 1500
            );
            insert entitlementSO;
        }
        
        System.runAs(testUserSSO) {
            Expense_Entitlement__c entitlementSSO = new Expense_Entitlement__c(
                Role__c                          = 'SSO',
                Active__c                        = true,
                Flight_Allowance_Amount__c       = 0,
                Bus_Allowance_Amount__c          = 0,
                Train_Allowance_Amount__c        = 0,
                Car_Allowance_Amount_per_km__c   = 0,
                Bike_Allowance_Amount_per_Km__c  = 0,
                Class_A_Cities_Amount__c         = 0,
                Other_Cities_Amount__c           = 0
            );
            insert entitlementSSO;
        }
        
        // Insert Expense Claims for the current month (run as the respective user)
        System.runAs(testUserSO) {
            Expense_Claim__c claimSO = new Expense_Claim__c(
                User__c       = testUserSO.Id,
                Start_Date__c = Date.today().toStartOfMonth()
            );
            insert claimSO;
        }
        
        System.runAs(testUserSSO) {
            Expense_Claim__c claimSSO = new Expense_Claim__c(
                User__c       = testUserSSO.Id,
                Start_Date__c = Date.today().toStartOfMonth()
            );
            insert claimSSO;
        }
    }
    
    // Helper method to get the SO user
    private static User getTestUser() {
        return [SELECT Id, Employee_Role__c FROM User WHERE LastName = 'TestUser' LIMIT 1];
    }
    
    // Helper method to get the SSO user
    private static User getTestUserSSO() {
        return [SELECT Id, Employee_Role__c FROM User WHERE LastName = 'Testsso' LIMIT 1];
    }
    
    // Test getUserRoleAndEntitlements
    @isTest 
    static void testGetUserRoleAndEntitlements() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.startTest();
            ExpenseController.UserEntitlementWrapper result = ExpenseController.getUserRoleAndEntitlements();
            Test.stopTest();
            System.assertEquals('SO', result.userRole);
            System.assertEquals(1000, result.busAllowanceAmount);
            System.assertEquals(2000, result.trainAllowanceAmount);
        }
    }
    
    // Test entitlement exception when entitlement is missing
    @isTest 
    static void testEntitlementException() {
        User testUser = getTestUser();
        // Delete the SO entitlement to force an exception
        Expense_Entitlement__c ent = [SELECT Id FROM Expense_Entitlement__c WHERE Role__c = 'SO' LIMIT 1];
        delete ent;
        
        System.runAs(testUser) {
            Test.startTest();
            try {
                ExpenseController.getUserRoleAndEntitlements();
                System.assert(false, 'Expected exception was not thrown');
            } catch (AuraHandledException e) {
                // Expected exception; optionally check the error message.
            }
            Test.stopTest();
        }
    }
    
    // Test getClassACities
    @isTest 
    static void testGetClassACities() {
        Test.startTest();
        List<Map<String, String>> cities = ExpenseController.getClassACities();
        Test.stopTest();
        System.assert(!cities.isEmpty(), 'Should return picklist values');
        System.assert(cities[0].containsKey('value'));
        System.assert(cities[0].containsKey('label'));
    }
    
    // Test validateExpense for Bus under limit
    @isTest 
    static void testValidateBusUnderLimit() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.startTest();
            ExpenseController.ExpenseResponse res = ExpenseController.validateExpense(
                'SO',
                'Travel_Expense_Request',
                'Bus',
                null,
                900,
                null
            );
            Test.stopTest();
            // Uncomment assertions based on desired behavior:
            // System.assertEquals(null, res.errorMessage);
            // System.assertEquals(false, res.blockSave);
        }
    }
    
    // Test validateExpense for Train under limit and a subsequent Bus save
    @isTest 
    static void testValidateTrainUnderLimit() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.startTest();
            ExpenseController.ExpenseResponse res = ExpenseController.validateExpense(
                'SO',
                'Travel_Expense_Request',
                'Train',
                null,
                900,
                null
            );
            ExpenseController.ExpenseResponse res1 = ExpenseController.saveExpense(
                'SO',
                'Travel_Expense_Request',
                'Bus',
                null,
                null,
                null,
                800,
                null,
                Date.today(),
                new List<String>(),
                null,
                null
            );
            Test.stopTest();
            // Add assertions as needed.
        }
    }
    
    // Test validateExpense when no entitlement exists
    @isTest 
    static void testValidatenoexp() {
        List<Expense_Entitlement__c> entList = [SELECT Id FROM Expense_Entitlement__c WHERE Role__c = 'SO'];
        delete entList;
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.startTest();
            ExpenseController.ExpenseResponse res = ExpenseController.validateExpense(
                'SO',
                'Travel_Expense_Request',
                'Bus',
                null,
                900,
                null
            );
            Test.stopTest();
            // Add your assertions as needed.
        }
    }
    
    // Test validateExpense for Accommodation Request (Other Cities)
    @isTest 
    static void testValidateAccUnderLimit() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.startTest();
            ExpenseController.ExpenseResponse res = ExpenseController.validateExpense(
                'SO',
                'Accommodation Request',
                'null',
                'Other Cities',
                900,
                null
            );
            Test.stopTest();
            // Add your assertions as needed.
        }
    }
    
    // Test validateExpense for Accommodation Request (Class A cities)
    @isTest 
    static void testValidateAccAUnderLimit() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.startTest();
            ExpenseController.ExpenseResponse res = ExpenseController.validateExpense(
                'SO',
                'Accommodation Request',
                'null',
                'Class A cities',
                900,
                null
            );
            Test.stopTest();
            // Add your assertions as needed.
        }
    }
    
    // Test validateExpense for Train expense over limit
    @isTest 
    static void testValidateTrainOverLimit() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.startTest();
            ExpenseController.ExpenseResponse res = ExpenseController.validateExpense(
                'SO',
                'Travel_Expense_Request',
                'Train',
                null,
                2500,
                null
            );
            Test.stopTest();
            // Optionally assert that a warning message is returned:
            // System.assert(res.errorMessage.contains('Do you still wish'));
            // System.assertEquals(false, res.blockSave);
        }
    }
    
    // Test saveExpense for Bus expense within limit
    @isTest 
    static void testSaveBusExpense() {
        User testUser = getTestUser();
        Expense_Claim__c claim = [SELECT Id FROM Expense_Claim__c WHERE User__c = :testUser.Id LIMIT 1];
        List<String> fileIds = new List<String>();
        System.runAs(testUser) {
            Test.startTest();
            ExpenseController.ExpenseResponse res = ExpenseController.saveExpense(
                'SO',
                'Travel_Expense_Request',
                'Bus',
                null,
                null,
                null,
                800,
                null,
                Date.today(),
                fileIds,
                claim.Id,
                null
            );
            Test.stopTest();
            System.assertNotEquals(null, res.expenseId);
            Expense__c savedExpense = [SELECT Status__c FROM Expense__c WHERE Id = :res.expenseId];
            System.assertEquals('Approved', savedExpense.Status__c);
        }
    }
    
    // Test saveExpense for Bike expense when entitlement is zero
    @isTest 
    static void testzeroentitlementbike() {
        User testUserSSO = getTestUserSSO();
        Expense_Claim__c claim = [SELECT Id FROM Expense_Claim__c WHERE User__c = :testUserSSO.Id LIMIT 1];
        List<String> fileIds = new List<String>();
        System.runAs(testUserSSO) {
            Test.startTest();
            ExpenseController.ExpenseResponse res = ExpenseController.saveExpense(
                'SSO',
                'Travel_Expense_Request',
                'Bike',
                null,
                null,
                null,
                800,
                20,
                Date.today(),
                fileIds,
                claim.Id,
                null
            );
            Test.stopTest();
            System.assertNotEquals(null, res.expenseId);
            Expense__c savedExpense = [SELECT Status__c FROM Expense__c WHERE Id = :res.expenseId];
            System.assertEquals('Approved', savedExpense.Status__c);
        }
    }
    
    // Test saveExpense for Bus expense when entitlement is zero (SSO)
    @isTest 
    static void testzeroentitlement() {
        User testUserSSO = getTestUserSSO();
        Expense_Claim__c claim = [SELECT Id FROM Expense_Claim__c WHERE User__c = :testUserSSO.Id LIMIT 1];
        List<String> fileIds = new List<String>();
        System.runAs(testUserSSO) {
            Test.startTest();
            ExpenseController.ExpenseResponse res = ExpenseController.saveExpense(
                'SSO',
                'Travel_Expense_Request',
                'Bus',
                null,
                null,
                null,
                800,
                null,
                Date.today(),
                fileIds,
                claim.Id,
                null
            );
            Test.stopTest();
            System.assertNotEquals(null, res.expenseId);
            Expense__c savedExpense = [SELECT Status__c FROM Expense__c WHERE Id = :res.expenseId];
            System.assertEquals('Submitte_for_Approval', savedExpense.Status__c);
        }
    }
    
    // Test saveExpense for over limit Bus expense
    @isTest 
    static void testSaveOverLimit() {
        User testUser = getTestUser();
        Expense_Claim__c claim = [SELECT Id FROM Expense_Claim__c WHERE User__c = :testUser.Id LIMIT 1];
        System.runAs(testUser) {
            Test.startTest();
            ExpenseController.ExpenseResponse res = ExpenseController.saveExpense(
                'SO',
                'Travel_Expense_Request',
                'Bus',
                null,
                null,
                null,
                1500,
                null,
                Date.today(),
                null,
                claim.Id,
                null
            );
            Test.stopTest();
            Expense__c savedExpense = [SELECT Status__c FROM Expense__c WHERE Id = :res.expenseId];
            System.assertEquals('Submitte_for_Approval', savedExpense.Status__c);
        }
    }
    
    // Test saveExpense for Car expense with calculated amount based on km
    @isTest 
    static void testSaveCarExpense() {
        User testUser = getTestUser();
        Expense_Claim__c claim = [SELECT Id FROM Expense_Claim__c WHERE User__c = :testUser.Id LIMIT 1];
        System.runAs(testUser) {
            Test.startTest();
            ExpenseController.ExpenseResponse res = ExpenseController.saveExpense(
                'SO',
                'Travel_Expense_Request',
                'Car',
                null,
                null,
                null,
                null,
                100,
                Date.today(),
                null,
                claim.Id,
                null
            );
            Test.stopTest();
            Expense__c savedExpense = [SELECT Amount__c, Car_Run_Km__c FROM Expense__c WHERE Id = :res.expenseId];
            System.assertEquals(1200, savedExpense.Amount__c); // 100 km * 12 per km
            System.assertEquals(100, savedExpense.Car_Run_Km__c);
        }
    }
    
    // Test validateExpense for Flight expense (even though Flight validations are commented in controller)
    @isTest 
    static void testValidateFlightExpense() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.startTest();
            ExpenseController.ExpenseResponse res = ExpenseController.validateExpense(
                'SO',
                'Travel_Expense_Request',
                'Flight',
                null,
                6000,
                null
            );
            Test.stopTest();
            System.assertEquals(null, res.errorMessage);
            System.assertEquals(null, res.blockSave);
        }
    }
    
    // Test saveExpense for Bike expense with distance calculation
    @isTest 
    static void testSaveBikeExpense() {
        User testUser = getTestUser();
        Expense_Claim__c claim = [SELECT Id FROM Expense_Claim__c WHERE User__c = :testUser.Id LIMIT 1];
        System.runAs(testUser) {
            Test.startTest();
            ExpenseController.ExpenseResponse res = ExpenseController.saveExpense(
                'SO',
                'Travel_Expense_Request',
                'Bike',
                null,
                null,
                null,
                null,
                50,
                Date.today(),
                null,
                claim.Id,
                null
            );
            Test.stopTest();
            Expense__c savedExpense = [SELECT Amount__c, Bike_Run_Km__c, Status__c FROM Expense__c WHERE Id = :res.expenseId];
            System.assertEquals(400, savedExpense.Amount__c); // 50 km * 8 per km
            System.assertEquals(50, savedExpense.Bike_Run_Km__c);
            System.assertEquals('Approved', savedExpense.Status__c);
        }
    }
    
    // Test saveExpense for Accommodation Request over the Class A cities limit
    @isTest 
    static void testSaveClassAAccommodationOverLimit() {
        User testUser = getTestUser();
        Expense_Claim__c claim = [SELECT Id FROM Expense_Claim__c WHERE User__c = :testUser.Id LIMIT 1];
        System.runAs(testUser) {
            Test.startTest();
            ExpenseController.ExpenseResponse res = ExpenseController.saveExpense(
                'SO',
                'Accommodation Request',
                null,
                'Class A cities',
                'Mumbai',
                null,
                3500,   // Over the limit of 3000
                null,
                Date.today(),
                null,
                claim.Id,
                null
            );
            Test.stopTest();
            Expense__c savedExpense = [SELECT Status__c FROM Expense__c WHERE Id = :res.expenseId];
            System.assertEquals('Submitte_for_Approval', savedExpense.Status__c);
            // Optionally assert that a warning message was generated.
        }
    }
    
    // Test validateExpense for Accommodation Request over limit (Class A cities)
    @isTest 
    static void testValidateAccommodationClassAOverLimit() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.startTest();
            ExpenseController.ExpenseResponse res = ExpenseController.validateExpense(
                'SO',
                'Accommodation Request',
                null,
                'Class A cities',
                3500,
                null
            );
            Test.stopTest();
            System.assert(res.errorMessage.contains('Do you still wish'));
            System.assertEquals(null, res.blockSave);
        }
    }
    
    // Test validateExpense for a transport type not configured (null entitlement)
    @isTest 
    static void testValidateUnconfiguredTransport() {
        // Update the entitlement to remove the Bus allowance
        Expense_Entitlement__c ent = [SELECT Id, Bus_Allowance_Amount__c FROM Expense_Entitlement__c WHERE Role__c = 'SO' LIMIT 1];
        ent.Bus_Allowance_Amount__c = null;
        update ent;
        
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.startTest();
            ExpenseController.ExpenseResponse res = ExpenseController.validateExpense(
                'SO',
                'Travel_Expense_Request',
                'Bus',
                null,
                500,
                null
            );
            Test.stopTest();
            System.assert(res.errorMessage.contains('no entitlement'));
            System.assertEquals(true, res.blockSave);
        }
    }
}