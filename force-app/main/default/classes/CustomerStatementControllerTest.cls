@isTest
private class CustomerStatementControllerTest {
    
    @testSetup
    static void setupTestData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
    }

    private static User createPortalUser(Account acc, String profileName) {
        // Ensure account has a portal-compatible owner
        Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
        Contact c = new Contact(
            FirstName = 'Test',
            LastName  = 'User' + acc.Id,
            AccountId = acc.Id,
            Email     = 'testuser' + acc.Id + '@example.com'
        );
        insert c;
        User u = new User(
            FirstName       = 'Test',
            LastName        = 'User',
            Email           = 'testuser' + acc.Id + '@hangyo.in',
            Username        = 'testuser' + acc.Id + '@example.testorg',
            Alias           = 'tuser',
            TimeZoneSidKey  = 'America/New_York',
            LocaleSidKey    = 'en_US',
            EmailEncodingKey= 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId       = p.Id,
            ContactId       = c.Id
        );
        insert u;
        return u;
    }

    private static Id getRecordTypeId(String sObjectName, String devName) {
        return Schema.getGlobalDescribe()
                     .get(sObjectName)
                     .getDescribe()
                     .getRecordTypeInfosByDeveloperName()
                     .get(devName)
                     .getRecordTypeId();
    }

    private static Account makeDistributorAccount() {
        Id rtId = getRecordTypeId('Account', 'Distributor');
        Account a = new Account(
            Name       = 'Test Distributor',
            RecordTypeId = rtId
        );
        insert a;
        return a;
    }

    private static Account makeSuperStockistAccount() {
        Id rtId = getRecordTypeId('Account', 'SuperStockist');
        Account a = new Account(
            Name       = 'Test SS',
            RecordTypeId = rtId
        );
        insert a;
        return a;
    }

    private static Account makeRetailerAccount(Id distributorId) {
        Id rtId = getRecordTypeId('Account', 'Retailer');
        Account a = new Account(
            Name            = 'Test Retailer',
            RecordTypeId    = rtId,
            Distributor__c  = distributorId,
            Is_Active__c    = true
        );
        insert a;
        return a;
    }

    private static Account makeDistributorUnderSS(Id ssAccountId) {
        Id rtId = getRecordTypeId('Account', 'Distributor');
        Account a = new Account(
            Name                    = 'Dist Under SS',
            RecordTypeId            = rtId,
            Super_Stockist_Name__c  = ssAccountId,
            Is_Active__c            = true
        );
        insert a;
        return a;
    }

    private static Invoice__c makeInvoice(
            Id distributorId, Id retailerId, Id underSSId,
            String devName, Date invDate, Decimal amount, String status) {
        Id rtId = getRecordTypeId('Invoice__c', devName);
        Invoice__c inv = new Invoice__c(
            Distributor_Account__c = distributorId,
            Retailer_Account__c    = retailerId,
            Under_SS__c            = underSSId,
            Invoice_Date__c        = invDate,
            Invoice_Amount__c      = amount,
            Status__c              = status,
            RecordTypeId           = rtId
        );
        insert inv;
        return inv;
    }

    // ── Helper: build a Returns__c record ────────────────────────────────────
    private static Returns__c makeReturn(Id invoiceId, Decimal amount) {
        Returns__c r = new Returns__c(
            Invoice__c = invoiceId,
            Return_Amount__c = amount,
            CGST__c = amount * 1.025,
            SGST__c = amount * 1.025
        );
        insert r;
        return r;
    }

    // ── Helper: build a Collection__c record ─────────────────────────────────
    private static Collection__c makeCollection(Id invoiceId, Date payDate, Decimal amount) {
        Collection__c c = new Collection__c(
            Invoice__c          = invoiceId,
            Payment_Date__c     = payDate,
            Amount_Collected__c = amount,
            Payment_Method__c   = 'Cash'
        );
        insert c;
        return c;
    }

    // ════════════════════════════════════════════════════════════════════════
    // Tests for getContextAndCustomers()
    // ════════════════════════════════════════════════════════════════════════

    @isTest
    static void testGetContextAndCustomers_Distributor() {
        Account distAcc = makeDistributorAccount();
        Account retAcc  = makeRetailerAccount(distAcc.Id);
        User u = createPortalUser(distAcc, 'DMS Partner Community Custom'); // adjust profile name

        Test.startTest();
        Map<String,Object> ctx;
        System.runAs(u) {
            ctx = CustomerStatementController.getContextAndCustomers();
        }
        Test.stopTest();

        System.assertEquals(distAcc.Id,      (Id)ctx.get('accountId'),    'accountId should match distributor');
        System.assertEquals('Distributor',   (String)ctx.get('accountType'), 'accountType should be Distributor');
        System.assertEquals('Retailer',      (String)ctx.get('customerLabel'));

        List<Map<String,String>> customers = (List<Map<String,String>>)ctx.get('customers');
        System.assertNotEquals(0, customers.size(), 'Should return at least one retailer');
        System.assertEquals(String.valueOf(retAcc.Id), customers[0].get('value'));
    }

    @isTest
    static void testGetContextAndCustomers_SuperStockist() {
        Account ssAcc   = makeSuperStockistAccount();
        Account distAcc = makeDistributorUnderSS(ssAcc.Id);
        User u = createPortalUser(ssAcc, 'DMS Partner Community Custom');

        Test.startTest();
        Map<String,Object> ctx;
        System.runAs(u) {
            ctx = CustomerStatementController.getContextAndCustomers();
        }
        Test.stopTest();

        System.assertEquals('SuperStockist', (String)ctx.get('accountType'));
    }

    @isTest
    static void testGetContextAndCustomers_NoAccountLinked() {
        // Internal user with no AccountId
        Profile p = [SELECT Id FROM Profile WHERE Name = 'SFA Profile' LIMIT 1];
        User u = new User(
            FirstName        = 'No',
            LastName         = 'Account',
            Email            = 'noaccount@hangyo.in',
            Username         = 'noaccount@example.testorg',
            Alias            = 'noacc',
            TimeZoneSidKey   = 'America/New_York',
            LocaleSidKey     = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId        = p.Id
        );
        insert u;

        Test.startTest();
        Map<String,Object> ctx;
        System.runAs(u) {
            ctx = CustomerStatementController.getContextAndCustomers();
        }
        Test.stopTest();

        System.assertNotEquals(null, ctx.get('error'), 'Should return error when no account');
    }

    @isTest
    static void testGetStatement_Distributor_BasicStatement() {
        Account distAcc = makeDistributorAccount();
        Account retAcc  = makeRetailerAccount(distAcc.Id);
        User u = createPortalUser(distAcc, 'DMS Partner Community Custom');

        Date today    = Date.today();
        Date fromDate = today.addDays(-30);
        Date toDate   = today;

        Invoice__c inv = makeInvoice(distAcc.Id, retAcc.Id, null,
                                     'Secondary_Invoice', today.addDays(-10), 1000, 'Delivered');
        makeReturn(inv.Id, 200);
        makeCollection(inv.Id, today.addDays(-5), 500);

        Test.startTest();
        CustomerStatementController.StatementResult res;
        System.runAs(u) {
            res = CustomerStatementController.getStatement(
                String.valueOf(retAcc.Id),
                String.valueOf(fromDate),
                String.valueOf(toDate)
            );
        }
        Test.stopTest();

        System.assertEquals(null, res.errorMessage, 'No error expected: ' + res.errorMessage);
        System.assertNotEquals(0,  res.lines.size(),  'Should have transaction lines');
        System.assertEquals(1000,  res.totalSales,    'Total sales should be 1000');
    }

    @isTest
    static void testGetStatement_Distributor_CancelledInvoice() {
        Account distAcc = makeDistributorAccount();
        Account retAcc  = makeRetailerAccount(distAcc.Id);
        User u = createPortalUser(distAcc, 'DMS Partner Community Custom');

        Date today    = Date.today();
        Date fromDate = today.addDays(-30);

        makeInvoice(distAcc.Id, retAcc.Id, null, 'Secondary_Invoice', today.addDays(-5), 500, 'Cancelled');

        Test.startTest();
        CustomerStatementController.StatementResult res;
        System.runAs(u) {
            res = CustomerStatementController.getStatement(
                String.valueOf(retAcc.Id),
                String.valueOf(fromDate),
                String.valueOf(today)
            );
        }
        Test.stopTest();

        System.assertEquals(null, res.errorMessage);
        // Cancelled invoice goes to credit / totalReturns bucket
        System.assertEquals(500, res.totalReturns, 'Cancelled invoice should be in totalReturns');
        System.assertEquals(0,   res.totalSales,   'No active sales');
    }

    @isTest
    static void testGetStatement_Distributor_OpeningBalanceCalculation() {
        Account distAcc = makeDistributorAccount();
        Account retAcc  = makeRetailerAccount(distAcc.Id);
        User u = createPortalUser(distAcc, 'DMS Partner Community Custom');

        Date fromDate = Date.today();
        Date toDate   = Date.today();
        // Invoice dated before the from date – should contribute to opening balance
        makeInvoice(distAcc.Id, retAcc.Id, null, 'Secondary_Invoice',
                    fromDate.addDays(-10), 2000, 'Delivered');

        Test.startTest();
        CustomerStatementController.StatementResult res;
        System.runAs(u) {
            res = CustomerStatementController.getStatement(
                String.valueOf(retAcc.Id),
                String.valueOf(fromDate),
                String.valueOf(toDate)
            );
        }
        Test.stopTest();

        System.assertEquals(null,  res.errorMessage);
        System.assertEquals(2000,  res.openingBalance, 'Opening balance should include prior invoice');
        System.assertEquals(0,     res.lines.size(),   'No in-period transactions');
        System.assertEquals(2000,  res.closingBalance, 'Closing should equal opening when no in-period txns');
    }

    @isTest
    static void testGetStatement_Distributor_NoTransactions() {
        Account distAcc = makeDistributorAccount();
        Account retAcc  = makeRetailerAccount(distAcc.Id);
        User u = createPortalUser(distAcc, 'DMS Partner Community Custom');

        Date fromDate = Date.today().addDays(-30);
        Date toDate   = Date.today();

        Test.startTest();
        CustomerStatementController.StatementResult res;
        System.runAs(u) {
            res = CustomerStatementController.getStatement(
                String.valueOf(retAcc.Id),
                String.valueOf(fromDate),
                String.valueOf(toDate)
            );
        }
        Test.stopTest();

        System.assertEquals(null, res.errorMessage);
        System.assertEquals(0,    res.lines.size(),      'No lines expected');
        System.assertEquals(0,    res.openingBalance,    'Opening balance should be 0');
        System.assertEquals(0,    res.closingBalance,    'Closing balance should be 0');
    }

    @isTest
    static void testGetStatement_SuperStockist_BasicStatement() {
        Account ssAcc      = makeSuperStockistAccount();
        Account distUnderSS = makeDistributorUnderSS(ssAcc.Id);
        User u = createPortalUser(ssAcc, 'DMS Partner Community Custom');

        Date today    = Date.today();
        Date fromDate = today.addDays(-30);

        Invoice__c inv = makeInvoice(ssAcc.Id, null, distUnderSS.Id,
                                     'Secondary_Invoice_Under_SS',
                                     today.addDays(-10), 3000, 'Delivered');
        makeReturn(inv.Id, 500);
        makeCollection(inv.Id, today.addDays(-3), 1000);

        Test.startTest();
        CustomerStatementController.StatementResult res;
        System.runAs(u) {
            res = CustomerStatementController.getStatement(
                String.valueOf(distUnderSS.Id),
                String.valueOf(fromDate),
                String.valueOf(today)
            );
        }
        Test.stopTest();

        System.assertEquals(null, res.errorMessage, 'No error: ' + res.errorMessage);
        System.assertEquals(3000, res.totalSales,       'Total sales 3000');
    }

    @isTest
    static void testGetStatement_SuperStockist_CancelledInvoice() {
        Account ssAcc      = makeSuperStockistAccount();
        Account distUnderSS = makeDistributorUnderSS(ssAcc.Id);
        User u = createPortalUser(ssAcc, 'DMS Partner Community Custom');

        Date today    = Date.today();
        Date fromDate = today.addDays(-30);

        makeInvoice(ssAcc.Id, null, distUnderSS.Id,
                    'Secondary_Invoice_Under_SS',
                    today.addDays(-5), 1500, 'Cancelled');

        Test.startTest();
        CustomerStatementController.StatementResult res;
        System.runAs(u) {
            res = CustomerStatementController.getStatement(
                String.valueOf(distUnderSS.Id),
                String.valueOf(fromDate),
                String.valueOf(today)
            );
        }
        Test.stopTest();

        System.assertEquals(null, res.errorMessage);
        System.assertEquals(0,    res.totalSales,   'No active sales');
        System.assertEquals(1500, res.totalReturns, 'Cancelled invoice in returns');
    }

    @isTest
    static void testGetStatement_InvalidCustomerId() {
        Account distAcc = makeDistributorAccount();
        User u = createPortalUser(distAcc, 'DMS Partner Community Custom');

        Test.startTest();
        CustomerStatementController.StatementResult res;
        System.runAs(u) {
            res = CustomerStatementController.getStatement(
                'NonExistentCustomer',
                String.valueOf(Date.today().addDays(-30)),
                String.valueOf(Date.today())
            );
        }
        Test.stopTest();

        System.assertNotEquals(null, res.errorMessage, 'Should error on invalid customer');
    }

    @isTest
    static void testGetStatement_NoAccountLinkedToUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName        = 'No',
            LastName         = 'Account',
            Email            = 'noacc2@hangyo.in',
            Username         = 'noacc2@example.testorg',
            Alias            = 'nac2',
            TimeZoneSidKey   = 'America/New_York',
            LocaleSidKey     = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId        = p.Id
        );
        insert u;

        Test.startTest();
        CustomerStatementController.StatementResult res;
        System.runAs(u) {
            res = CustomerStatementController.getStatement(
                'SomeId',
                String.valueOf(Date.today().addDays(-30)),
                String.valueOf(Date.today())
            );
        }
        Test.stopTest();

        System.assertEquals('No account linked to this portal user.', res.errorMessage);
    }

    @isTest
    static void testGetStatement_RunningBalanceOrder() {
        // Verify lines are sorted chronologically and running balance is cumulative
        Account distAcc = makeDistributorAccount();
        Account retAcc  = makeRetailerAccount(distAcc.Id);
        User u = createPortalUser(distAcc, 'DMS Partner Community Custom');

        Date today    = Date.today();
        Date fromDate = today.addDays(-30);

        Invoice__c inv1 = makeInvoice(distAcc.Id, retAcc.Id, null, 'Secondary_Invoice',
                                       today.addDays(-20), 1000, 'Delivered');
        Invoice__c inv2 = makeInvoice(distAcc.Id, retAcc.Id, null, 'Secondary_Invoice',
                                       today.addDays(-10), 2000, 'Delivered');
        makeCollection(inv1.Id, today.addDays(-15), 400);

        Test.startTest();
        CustomerStatementController.StatementResult res;
        System.runAs(u) {
            res = CustomerStatementController.getStatement(
                String.valueOf(retAcc.Id),
                String.valueOf(fromDate),
                String.valueOf(today)
            );
        }
        Test.stopTest();

        System.assertEquals(null, res.errorMessage);
        System.assertEquals(3000, res.totalSales);
        System.assertEquals(400,  res.totalCollections);

        // Lines sorted: inv1 (-20d), collection (-15d), inv2 (-10d)
        // Balance after inv1 = 1000, after collection = 600, after inv2 = 2600
        List<CustomerStatementController.StatementLine> lines = res.lines;
        System.assertEquals(3, lines.size(), 'Should have 3 lines');
        System.assertEquals(1000, lines[0].balance, 'After first sale balance = 1000');
        System.assertEquals(600,  lines[1].balance, 'After collection balance = 600');
        System.assertEquals(2600, lines[2].balance, 'After second sale balance = 2600');
    }

    @isTest
    static void testGetStatement_MultipleCollectionsAndReturns() {
        Account distAcc = makeDistributorAccount();
        Account retAcc  = makeRetailerAccount(distAcc.Id);
        User u = createPortalUser(distAcc, 'DMS Partner Community Custom');

        Date today    = Date.today();
        Date fromDate = today.addDays(-30);

        Invoice__c inv = makeInvoice(distAcc.Id, retAcc.Id, null, 'Secondary_Invoice',
                                      today.addDays(-20), 5000, 'Delivered');
        makeReturn(inv.Id, 300);
        makeReturn(inv.Id, 200);
        makeCollection(inv.Id, today.addDays(-10), 1000);
        makeCollection(inv.Id, today.addDays(-5),  500);

        Test.startTest();
        CustomerStatementController.StatementResult res;
        System.runAs(u) {
            res = CustomerStatementController.getStatement(
                String.valueOf(retAcc.Id),
                String.valueOf(fromDate),
                String.valueOf(today)
            );
        }
        Test.stopTest();

        System.assertEquals(null, res.errorMessage);
        System.assertEquals(5000, res.totalSales);
    }
}