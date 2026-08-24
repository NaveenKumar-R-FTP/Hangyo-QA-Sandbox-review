@IsTest
private class OrderInvoiceSearchControllerTest {

    private static final String SS_USER_KEY = 'SSUser';
    private static final String DIRECT_USER_KEY = 'DirectUser';
    private static final String UNDER_SS_USER_KEY = 'UnderSSUser';
    private static final String SS_ACCOUNT_NAME = 'OISC Test Super Stockist';
    private static final String DIRECT_ACCOUNT_NAME = 'OISC Test Direct Distributor';
    private static final String UNDER_SS_ACCOUNT_NAME = 'OISC Test Under SS Distributor';

    @TestSetup
    static void setupTestData() {
        Map<String, Id> accountRts = getRecordTypeIds('Account');
        Map<String, Id> orderRts = getRecordTypeIds('Order__c');
        Map<String, Id> invoiceRts = getRecordTypeIds('Invoice__c');

        if (!accountRts.containsKey('SuperStockist') || !accountRts.containsKey('Distributor')) {
            return;
        }

        Account ssAccount = findOrInsertAccount(
            SS_ACCOUNT_NAME,
            accountRts.get('SuperStockist'),
            new Map<String, Object>()
        );

        Account directAccount = findOrInsertAccount(
            DIRECT_ACCOUNT_NAME,
            accountRts.get('Distributor'),
            new Map<String, Object>{ 'Distributor_Type__c' => 'Direct Distributor' }
        );

        Account underSsAccount = findOrInsertAccount(
            UNDER_SS_ACCOUNT_NAME,
            accountRts.get('Distributor'),
            new Map<String, Object>{
                'Distributor_Type__c' => 'Under Super Stockist',
                'Super_Stockist_Name__c' => ssAccount.Id,
                'Distributor__c' => ssAccount.Id
            }
        );

        insert new Contact(LastName = SS_USER_KEY, AccountId = ssAccount.Id);
        insert new Contact(LastName = DIRECT_USER_KEY, AccountId = directAccount.Id);
        insert new Contact(LastName = UNDER_SS_USER_KEY, AccountId = underSsAccount.Id);

        Map<String, Contact> contactsByLastName = new Map<String, Contact>();
        for (Contact c : [
            SELECT Id, LastName FROM Contact
            WHERE LastName IN :new Set<String>{ SS_USER_KEY, DIRECT_USER_KEY, UNDER_SS_USER_KEY }
        ]) {
            contactsByLastName.put(c.LastName, c);
        }

        insert new List<User>{
            createPortalUser(contactsByLastName.get(SS_USER_KEY), SS_USER_KEY),
            createPortalUser(contactsByLastName.get(DIRECT_USER_KEY), DIRECT_USER_KEY),
            createPortalUser(contactsByLastName.get(UNDER_SS_USER_KEY), UNDER_SS_USER_KEY)
        };

        User underSsUser = [SELECT Id FROM User WHERE LastName = :UNDER_SS_USER_KEY LIMIT 1];

        Date today = Date.today();
        List<Order__c> orders = new List<Order__c>();

        if (orderRts.containsKey('Primary_Order')) {
            orders.add(new Order__c(
                RecordTypeId = orderRts.get('Primary_Order'),
                AccountId__c = ssAccount.Id,
                EffectiveDate__c = today,
                Status__c = 'Order Placed',
                GRN_Status__c = 'Pending'
            ));
        }
        if (orderRts.containsKey('Secondary_Order')) {
            orders.add(new Order__c(
                RecordTypeId = orderRts.get('Secondary_Order'),
                AccountId__c = ssAccount.Id,
                Account__c = directAccount.Id,
                EffectiveDate__c = today,
                Status__c = 'Delivered',
                Invoice_Created__c = 'Invoice Created'
            ));
        }
        if (orderRts.containsKey('Under_SS_Secondary_Order')) {
            Order__c underSsSecondaryOrder = new Order__c(
                RecordTypeId = orderRts.get('Under_SS_Secondary_Order'),
                AccountId__c = ssAccount.Id,
                Account__c = directAccount.Id,
                EffectiveDate__c = today,
                Status__c = 'Delivered',
                Invoice_Created__c = 'Invoice Created'
            );
            setOrderedByReference(underSsSecondaryOrder, underSsAccount.Id, underSsUser.Id);
            orders.add(underSsSecondaryOrder);
        }
        if (orderRts.containsKey('Under_SS_Order')) {
            orders.add(new Order__c(
                RecordTypeId = orderRts.get('Under_SS_Order'),
                AccountId__c = underSsAccount.Id,
                EffectiveDate__c = today,
                Status__c = 'Order Placed'
            ));
        }
        if (orderRts.containsKey('Counter_Order')) {
            orders.add(new Order__c(
                RecordTypeId = orderRts.get('Counter_Order'),
                AccountId__c = ssAccount.Id,
                EffectiveDate__c = today,
                Status__c = 'Order Placed'
            ));
        }
        if (!orders.isEmpty()) {
            insert orders;
        }

        List<Invoice__c> invoices = new List<Invoice__c>();
        if (invoiceRts.containsKey('Primary_Invoice')) {
            invoices.add(new Invoice__c(
                RecordTypeId = invoiceRts.get('Primary_Invoice'),
                Distributor_Account__c = ssAccount.Id,
                Invoice_Date__c = today,
                Status__c = 'Delivered',
                Payment_Status__c = 'Paid'
            ));
        }
        if (invoiceRts.containsKey('Secondary_Invoice')) {
            invoices.add(new Invoice__c(
                RecordTypeId = invoiceRts.get('Secondary_Invoice'),
                Distributor_Account__c = ssAccount.Id,
                Retailer_Account__c = directAccount.Id,
                Invoice_Date__c = today,
                Status__c = 'Delivered',
                Payment_Status__c = 'Not Paid'
            ));
        }
        if (invoiceRts.containsKey('Secondary_Invoice_Under_SS')) {
            invoices.add(new Invoice__c(
                RecordTypeId = invoiceRts.get('Secondary_Invoice_Under_SS'),
                Distributor_Account__c = ssAccount.Id,
                Under_SS__c = underSsAccount.Id,
                Invoice_Date__c = today,
                Status__c = 'Confirmed'
            ));
        }
        if (!invoices.isEmpty()) {
            insert invoices;
        }

        User ssUser = [SELECT Id FROM User WHERE LastName = :SS_USER_KEY LIMIT 1];

        if (!invoices.isEmpty()) {
            insert new Collection__c(
                Invoice__c = invoices[0].Id,
                Payment_Date__c = today,
                Payment_Method__c = 'Cash',
                Amount_Collected__c = 100
            );
        }

        if (!invoices.isEmpty()) {
            insert new Returns__c(
                Invoice__c = invoices[0].Id,
                Order__c = orders.isEmpty() ? null : orders[0].Id
            );
        }

        insert new Delivery_Plan__c(
            OwnerId = ssUser.Id,
            Date__c = today,
            Driver_Name__c = 'Driver One',
            Driver_Number__c = '9999999999',
            Vehicle_Number__c = 'KA01AB1234'
        );
    }

    @IsTest
    static void testGetInitData_superStockist() {
        User ssUser = getUser(SS_USER_KEY);
        System.runAs(ssUser) {
            OrderInvoiceSearchController.InitData data = OrderInvoiceSearchController.getInitData();
            System.assertEquals(
                OrderInvoiceSearchController.DIST_TYPE_SUPER_STOCKIEST,
                data.distributorType
            );
            System.assertNotEquals(null, data.accountId);
            System.assertNotEquals(0, data.objectOptions.size());
            System.assertNotEquals(0, data.invoiceRecordTypeOptions.size());
            System.assertNotEquals(0, data.orderStatusOptions.size());
            System.assertNotEquals(0, data.grnStatusOptions.size());
        }
    }

    @IsTest
    static void testGetInitData_directDistributor() {
        User directUser = getUser(DIRECT_USER_KEY);
        System.runAs(directUser) {
            OrderInvoiceSearchController.InitData data = OrderInvoiceSearchController.getInitData();
            System.assertEquals(
                OrderInvoiceSearchController.DIST_TYPE_DIRECT_DISTRIBUTOR,
                data.distributorType
            );
        }
    }

    @IsTest
    static void testGetInitData_underSsDistributor() {
        User underSsUser = getUser(UNDER_SS_USER_KEY);
        System.runAs(underSsUser) {
            OrderInvoiceSearchController.InitData data = OrderInvoiceSearchController.getInitData();
            System.assertEquals(
                OrderInvoiceSearchController.DIST_TYPE_UNDER_SS,
                data.distributorType
            );
        }
    }

    @IsTest
    static void testGetInitData_invalidUserContext() {
        Boolean threw = false;
        try {
            OrderInvoiceSearchController.getInitData();
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage() != null);
        }
        System.assertEquals(true, threw, 'Expected distributor context error for user without contact.');
    }

    @IsTest
    static void testSearchLookup_shortTermAndSuperStockist() {
        User ssUser = getUser(SS_USER_KEY);
        System.runAs(ssUser) {
            System.assertEquals(0, OrderInvoiceSearchController.searchLookup('A').size());
            System.assertEquals(0, OrderInvoiceSearchController.searchLookup('').size());

            List<OrderInvoiceSearchController.LookupResult> results =
                OrderInvoiceSearchController.searchLookup('Test');
            System.assertNotEquals(null, results);
        }
    }

    @IsTest
    static void testSearchLookup_directDistributor() {
        User directUser = getUser(DIRECT_USER_KEY);
        System.runAs(directUser) {
            List<OrderInvoiceSearchController.LookupResult> results =
                OrderInvoiceSearchController.searchLookup('Test');
            System.assertNotEquals(null, results);
        }
    }

    @IsTest
    static void testSearchRecords_orderSearches() {
        User ssUser = getUser(SS_USER_KEY);
        Account directAccount = getDirectAccount();
        Account underSs = getUnderSsAccount();
        String today = String.valueOf(Date.today());

        System.runAs(ssUser) {
            List<OrderInvoiceSearchController.SearchResult> primaryResults =
                OrderInvoiceSearchController.searchRecords(
                    'Primary Order', today, today, null, 'Order Placed', 'Pending', null, null
                );
            System.assertNotEquals(null, primaryResults);

            List<OrderInvoiceSearchController.SearchResult> secondaryResults =
                OrderInvoiceSearchController.searchRecords(
                    'Secondary Order', null, null, directAccount.Id, 'Delivered', null, 'Invoice Created', null
                );
            System.assertNotEquals(null, secondaryResults);

            List<OrderInvoiceSearchController.SearchResult> underSsResults =
                OrderInvoiceSearchController.searchRecords(
                    'Under SS Secondary Order', null, null, underSs.Id, null, null, null, null
                );
            System.assertNotEquals(null, underSsResults);

            List<OrderInvoiceSearchController.SearchResult> counterResults =
                OrderInvoiceSearchController.searchRecords(
                    'Counter Order', null, null, null, 'Order Placed', null, null, null
                );
            System.assertNotEquals(null, counterResults);
        }
    }

    @IsTest
    static void testSearchRecords_invoiceSearches() {
        User ssUser = getUser(SS_USER_KEY);
        Account directAccount = getDirectAccount();
        Account underSs = getUnderSsAccount();

        System.runAs(ssUser) {
            List<OrderInvoiceSearchController.SearchResult> primaryInvoices =
                OrderInvoiceSearchController.searchRecords(
                    'Invoice', null, null, null, null, null, null, 'Primary Invoice'
                );
            System.assertNotEquals(null, primaryInvoices);

            List<OrderInvoiceSearchController.SearchResult> secondaryInvoices =
                OrderInvoiceSearchController.searchRecords(
                    'Invoice', null, null, directAccount.Id, 'Delivered + Paid', null, null, 'Secondary Invoice'
                );
            System.assertNotEquals(null, secondaryInvoices);

            List<OrderInvoiceSearchController.SearchResult> underSsInvoices =
                OrderInvoiceSearchController.searchRecords(
                    'Invoice', null, null, underSs.Id, 'Delivered + Not Paid', null, null,
                    'Secondary Invoice Under SS'
                );
            System.assertNotEquals(null, underSsInvoices);
        }
    }

    @IsTest
    static void testSearchRecords_collectionReturnDeliveryPlan() {
        User ssUser = getUser(SS_USER_KEY);
        String today = String.valueOf(Date.today());

        System.runAs(ssUser) {
            List<OrderInvoiceSearchController.SearchResult> collections =
                OrderInvoiceSearchController.searchRecords(
                    'Collection', today, today, null, null, null, null, null
                );
            System.assertNotEquals(null, collections);

            List<OrderInvoiceSearchController.SearchResult> returns =
                OrderInvoiceSearchController.searchRecords(
                    'Return', today, today, null, null, null, null, null
                );
            System.assertNotEquals(null, returns);

            List<OrderInvoiceSearchController.SearchResult> plans =
                OrderInvoiceSearchController.searchRecords(
                    'Delivery Plan', today, today, null, null, null, null, null
                );
            System.assertNotEquals(null, plans);
        }
    }

    @IsTest
    static void testSearchRecords_underSsUserInvoice() {
        User underSsUser = getUser(UNDER_SS_USER_KEY);
        System.runAs(underSsUser) {
            List<OrderInvoiceSearchController.SearchResult> invoices =
                OrderInvoiceSearchController.searchRecords(
                    'Invoice', null, null, null, 'Confirmed', null, null, null
                );
            System.assertNotEquals(null, invoices);
        }
    }

    @IsTest
    static void testSearchRecords_validationErrors() {
        User ssUser = getUser(SS_USER_KEY);
        Account ssAccount = getSuperStockistAccount();
        Account underSs = getUnderSsAccount();
        Account directAccount = getDirectAccount();

        System.runAs(ssUser) {
            expectAuraError(
                'Please select an object to search.',
                new SearchAction('searchRecords', new Map<String, Object>{ 'objectName' => null })
            );
            expectAuraError(
                'From Date cannot be after To Date.',
                new SearchAction('searchRecords', new Map<String, Object>{
                    'objectName' => 'Primary Order',
                    'fromDate' => '2026-07-10',
                    'toDate' => '2026-07-01'
                })
            );
            expectAuraError(
                'Please select a Retailer.',
                new SearchAction('searchRecords', new Map<String, Object>{
                    'objectName' => 'Secondary Order',
                    'searchAccountId' => underSs.Id
                })
            );
            expectAuraError(
                'Please select an Under SS Distributor.',
                new SearchAction('searchRecords', new Map<String, Object>{
                    'objectName' => 'Under SS Secondary Order',
                    'searchAccountId' => ssAccount.Id
                })
            );
            expectAuraError(
                'Retailer / Under SS selection is not applicable for Primary Invoice.',
                new SearchAction('searchRecords', new Map<String, Object>{
                    'objectName' => 'Invoice',
                    'searchAccountId' => directAccount.Id,
                    'invoiceRecordType' => 'Primary Invoice'
                })
            );
            expectAuraError(
                'Please select a Retailer, not an Under SS Distributor, for Secondary Invoice.',
                new SearchAction('searchRecords', new Map<String, Object>{
                    'objectName' => 'Invoice',
                    'searchAccountId' => underSs.Id,
                    'invoiceRecordType' => 'Secondary Invoice'
                })
            );
        }
    }

    @IsTest
    static void testSearchRecords_retailerInvoiceValidationErrors() {
        Account retailerAccount = queryRetailerAccountIfAvailable();
        if (retailerAccount == null) {
            return;
        }

        User ssUser = getUser(SS_USER_KEY);
        System.runAs(ssUser) {
            expectAuraError(
                'Please select an Under SS Distributor, not a Retailer, for Under SS Secondary Invoice.',
                new SearchAction('searchRecords', new Map<String, Object>{
                    'objectName' => 'Invoice',
                    'searchAccountId' => retailerAccount.Id,
                    'invoiceRecordType' => 'Secondary Invoice Under SS'
                })
            );
        }
    }

    @IsTest
    static void testSearchRecords_underSsUserRetailerInvoiceValidation() {
        Account retailerAccount = queryRetailerAccountIfAvailable();
        if (retailerAccount == null) {
            return;
        }

        User underSsUser = getUser(UNDER_SS_USER_KEY);
        System.runAs(underSsUser) {
            expectAuraError(
                'Please select an Under SS Distributor, not a Retailer, for Under SS Secondary Invoice.',
                new SearchAction('searchRecords', new Map<String, Object>{
                    'objectName' => 'Invoice',
                    'searchAccountId' => retailerAccount.Id,
                    'invoiceRecordType' => 'Secondary Invoice Under SS'
                })
            );
        }
    }

    @IsTest
    static void testSearchRecords_invalidObjectForDistributor() {
        User directUser = getUser(DIRECT_USER_KEY);
        System.runAs(directUser) {
            expectAuraError(
                'The selected Object is not valid for your distributor type.',
                new SearchAction('searchRecords', new Map<String, Object>{
                    'objectName' => 'Under SS Secondary Order'
                })
            );
        }
    }

    @IsTest
    static void testSearchRecords_invalidInvoiceRecordType() {
        User ssUser = getUser(SS_USER_KEY);
        System.runAs(ssUser) {
            expectAuraError(
                'Please select a valid Invoice Record Type.',
                new SearchAction('searchRecords', new Map<String, Object>{
                    'objectName' => 'Invoice',
                    'invoiceRecordType' => 'Invalid Invoice Type'
                })
            );
        }
    }

    @IsTest
    static void testSearchRecords_underSsUserReturnSearch() {
        User underSsUser = getUser(UNDER_SS_USER_KEY);
        String today = String.valueOf(Date.today());
        System.runAs(underSsUser) {
            List<OrderInvoiceSearchController.SearchResult> returns =
                OrderInvoiceSearchController.searchRecords(
                    'Return', today, today, null, null, null, null, null
                );
            System.assertNotEquals(null, returns);
        }
    }

    @IsTest
    static void testSearchRecords_underSsUserPrimaryOrder() {
        User underSsUser = getUser(UNDER_SS_USER_KEY);
        System.runAs(underSsUser) {
            List<OrderInvoiceSearchController.SearchResult> orders =
                OrderInvoiceSearchController.searchRecords(
                    'Primary Order', null, null, null, 'Order Placed', null, null, null
                );
            System.assertNotEquals(null, orders);
        }
    }

    @IsTest
    static void testSearchLookup_underSsDistributor() {
        User underSsUser = getUser(UNDER_SS_USER_KEY);
        System.runAs(underSsUser) {
            List<OrderInvoiceSearchController.LookupResult> results =
                OrderInvoiceSearchController.searchLookup('OISC');
            System.assertNotEquals(null, results);
        }
    }

    @IsTest
    static void testSearchRecords_directDistributorSearches() {
        User directUser = getUser(DIRECT_USER_KEY);
        String today = String.valueOf(Date.today());

        System.runAs(directUser) {
            List<OrderInvoiceSearchController.SearchResult> primaryOrders =
                OrderInvoiceSearchController.searchRecords(
                    'Primary Order', today, today, null, 'Order Placed', null, null, null
                );
            System.assertNotEquals(null, primaryOrders);

            List<OrderInvoiceSearchController.SearchResult> secondaryInvoices =
                OrderInvoiceSearchController.searchRecords(
                    'Invoice', null, null, null, null, null, null, 'Secondary Invoice'
                );
            System.assertNotEquals(null, secondaryInvoices);
        }
    }

    @IsTest
    static void testSearchRecords_dateFilters() {
        User ssUser = getUser(SS_USER_KEY);
        String today = String.valueOf(Date.today());

        System.runAs(ssUser) {
            List<OrderInvoiceSearchController.SearchResult> orders =
                OrderInvoiceSearchController.searchRecords(
                    'Primary Order', today, today, null, null, null, null, null
                );
            System.assertNotEquals(null, orders);

            List<OrderInvoiceSearchController.SearchResult> invoices =
                OrderInvoiceSearchController.searchRecords(
                    'Invoice', today, today, null, null, null, null, 'Primary Invoice'
                );
            System.assertNotEquals(null, invoices);
        }
    }

    @IsTest
    static void testSearchRecords_underSsSecondaryOrderWithFilter() {
        User ssUser = getUser(SS_USER_KEY);
        Account underSs = getUnderSsAccount();

        System.runAs(ssUser) {
            List<OrderInvoiceSearchController.SearchResult> results =
                OrderInvoiceSearchController.searchRecords(
                    'Under SS Secondary Order', null, null, underSs.Id, 'Delivered', null, 'Invoice Created', null
                );
            System.assertNotEquals(null, results);
        }
    }

    @IsTest
    static void testGetInitData_invalidDistributorConfiguration() {
        Map<String, Id> accountRts = getRecordTypeIds('Account');
        if (!accountRts.containsKey('Distributor')) {
            return;
        }

        Account invalidAccount = new Account(
            Name = 'OISC Invalid Dist ' + System.currentTimeMillis(),
            RecordTypeId = accountRts.get('Distributor')
        );
        applyAccountDefaults(invalidAccount);
        insert invalidAccount;

        Contact invalidContact = new Contact(
            LastName = 'InvalidDistUser',
            AccountId = invalidAccount.Id
        );
        insert invalidContact;

        User invalidUser = createPortalUser(invalidContact, 'InvalidDistUser');
        insert invalidUser;

        System.runAs(invalidUser) {
            expectAuraError(
                'Unable to load your distributor context.',
                new SearchAction('getInitData', new Map<String, Object>())
            );
        }
    }

    @IsTest
    static void testSearchRecords_returnWithAccountFilter() {
        User ssUser = getUser(SS_USER_KEY);
        Account directAccount = getDirectAccount();
        String today = String.valueOf(Date.today());

        System.runAs(ssUser) {
            List<OrderInvoiceSearchController.SearchResult> returns =
                OrderInvoiceSearchController.searchRecords(
                    'Return', today, today, directAccount.Id, null, null, null, null
                );
            System.assertNotEquals(null, returns);
        }
    }

    @IsTest
    static void testSearchRecords_invoiceStatusFilters() {
        User ssUser = getUser(SS_USER_KEY);
        System.runAs(ssUser) {
            List<OrderInvoiceSearchController.SearchResult> draftInvoices =
                OrderInvoiceSearchController.searchRecords(
                    'Invoice', null, null, null, 'Draft', null, null, 'Primary Invoice'
                );
            System.assertNotEquals(null, draftInvoices);

            List<OrderInvoiceSearchController.SearchResult> confirmedInvoices =
                OrderInvoiceSearchController.searchRecords(
                    'Invoice', null, null, null, 'Confirmed', null, null, 'Secondary Invoice Under SS'
                );
            System.assertNotEquals(null, confirmedInvoices);
        }
    }

    @IsTest
    static void testSearchRecords_underSsOrderWithMissingAccountName() {
        User ssUser = getUser(SS_USER_KEY);
        Id fakeAccountId = buildFakeAccountId();

        System.runAs(ssUser) {
            List<OrderInvoiceSearchController.SearchResult> results =
                OrderInvoiceSearchController.searchRecords(
                    'Under SS Secondary Order', null, null, fakeAccountId, null, null, null, null
                );
            System.assertEquals(0, results.size());
        }
    }

    @IsTest
    static void testSearchRecords_withOrgRetailerIfPresent() {
        Account retailerAccount = queryRetailerAccountIfAvailable();
        if (retailerAccount == null) {
            return;
        }

        User ssUser = getUser(SS_USER_KEY);
        System.runAs(ssUser) {
            List<OrderInvoiceSearchController.SearchResult> secondaryResults =
                OrderInvoiceSearchController.searchRecords(
                    'Secondary Order', null, null, retailerAccount.Id, null, null, null, null
                );
            System.assertNotEquals(null, secondaryResults);
        }
    }

    private static void setOrderedByReference(Order__c order, Id accountId, Id userId) {
        Map<String, Schema.SObjectField> fieldMap = Order__c.SObjectType.getDescribe().fields.getMap();
        if (!fieldMap.containsKey('Ordered_By__c')) {
            return;
        }
        Schema.DescribeFieldResult fieldDescribe = fieldMap.get('Ordered_By__c').getDescribe();
        if (!fieldDescribe.isCreateable() || fieldDescribe.isCalculated()) {
            return;
        }
        List<Schema.SObjectType> references = fieldDescribe.getReferenceTo();
        if (references.isEmpty()) {
            return;
        }
        String referenceName = String.valueOf(references[0]);
        if (referenceName == 'Account') {
            order.put('Ordered_By__c', accountId);
        } else if (referenceName == 'User') {
            order.put('Ordered_By__c', userId);
        }
    }

    private static Account findOrInsertAccount(
        String accountName,
        Id recordTypeId,
        Map<String, Object> fieldValues
    ) {
        List<Account> existing = [
            SELECT Id, Name
            FROM Account
            WHERE Name = :accountName AND RecordTypeId = :recordTypeId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }

        Account acc = new Account(
            Name = accountName,
            RecordTypeId = recordTypeId
        );
        applyAccountDefaults(acc);
        applyFieldValues(acc, fieldValues);
        try {
            insert acc;
        } catch (DmlException e) {
            if (e.getMessage().contains('DUPLICATE_VALUE')) {
                List<Account> retryLookup = [
                    SELECT Id, Name
                    FROM Account
                    WHERE Name = :accountName AND RecordTypeId = :recordTypeId
                    LIMIT 1
                ];
                if (!retryLookup.isEmpty()) {
                    return retryLookup[0];
                }
            }
            throw e;
        }
        return acc;
    }

    private static String buildUniqueKey() {
        return String.valueOf(Math.abs(Crypto.getRandomInteger()))
            + String.valueOf(System.currentTimeMillis());
    }

    private static String buildUniqueGstin(String uniqueKey) {
        String digits = uniqueKey.replaceAll('[^0-9]', '');
        if (digits.length() < 10) {
            digits = digits + '1234567890';
        }
        return '29' + digits.substring(0, 10) + '1Z5';
    }

    private static String buildUniquePhone(String uniqueKey) {
        String digits = uniqueKey.replaceAll('[^0-9]', '');
        if (digits.length() < 10) {
            digits = digits + '9876543210';
        }
        return digits.substring(0, 10);
    }

    private static void applyAccountDefaults(Account acc) {
        String uniqueKey = buildUniqueKey();
        acc.BillingStreet = 'Test Street ' + uniqueKey.left(8);
        acc.BillingCity = 'Bangalore';
        acc.BillingState = 'Karnataka';
        acc.BillingPostalCode = '560001';
        acc.BillingCountry = 'India';
        acc.Phone = buildUniquePhone(uniqueKey);
        putFieldIfCreateable(acc, 'Mobile__c', buildUniquePhone(uniqueKey + 'M'));
        putFieldIfCreateable(acc, 'State__c', 'Karnataka');
        putFieldIfCreateable(acc, 'District__c', 'Bangalore');
        putFieldIfCreateable(acc, 'City__c', 'Bangalore');
        putFieldIfCreateable(acc, 'Pincode__c', '560001');
        putFieldIfCreateable(acc, 'GSTIN__c', buildUniqueGstin(uniqueKey));
        putFieldIfCreateable(acc, 'Distributor_Code__c', 'DC' + uniqueKey.left(8));
    }

    private static void applyFieldValues(Account acc, Map<String, Object> fieldValues) {
        if (fieldValues == null) {
            return;
        }
        for (String fieldName : fieldValues.keySet()) {
            putFieldIfCreateable(acc, fieldName, fieldValues.get(fieldName));
        }
    }

    private static void putFieldIfCreateable(SObject record, String fieldName, Object value) {
        Map<String, Schema.SObjectField> fieldMap = record.getSObjectType().getDescribe().fields.getMap();
        if (!fieldMap.containsKey(fieldName)) {
            return;
        }
        Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
        if (fieldDescribe.isCreateable() && !fieldDescribe.isCalculated()) {
            record.put(fieldName, value);
        }
    }

    private static Account getSuperStockistAccount() {
        Map<String, Id> accountRts = getRecordTypeIds('Account');
        List<Account> accounts = [
            SELECT Id
            FROM Account
            WHERE Name = :SS_ACCOUNT_NAME
              AND RecordTypeId = :accountRts.get('SuperStockist')
            LIMIT 1
        ];
        System.assert(!accounts.isEmpty(), 'Super Stockist test account was not created in setup.');
        return accounts[0];
    }

    private static Account getDirectAccount() {
        Map<String, Id> accountRts = getRecordTypeIds('Account');
        List<Account> accounts = [
            SELECT Id
            FROM Account
            WHERE Name = :DIRECT_ACCOUNT_NAME
              AND RecordTypeId = :accountRts.get('Distributor')
            LIMIT 1
        ];
        System.assert(!accounts.isEmpty(), 'Direct distributor test account was not created in setup.');
        return accounts[0];
    }

    private static Account getUnderSsAccount() {
        Map<String, Id> accountRts = getRecordTypeIds('Account');
        List<Account> underSsAccounts = [
            SELECT Id, Name
            FROM Account
            WHERE Name = :UNDER_SS_ACCOUNT_NAME
              AND RecordTypeId = :accountRts.get('Distributor')
            LIMIT 1
        ];
        System.assert(!underSsAccounts.isEmpty(), 'Under SS test account was not created in setup.');
        return underSsAccounts[0];
    }

    private static Account queryRetailerAccountIfAvailable() {
        Map<String, Id> accountRts = getRecordTypeIds('Account');
        if (!accountRts.containsKey('Retailer')) {
            return null;
        }
        List<Account> retailers = [
            SELECT Id
            FROM Account
            WHERE RecordTypeId = :accountRts.get('Retailer')
            LIMIT 1
        ];
        return retailers.isEmpty() ? null : retailers[0];
    }

    private static Map<String, Id> getRecordTypeIds(String sObjectApiName) {
        Map<String, Id> result = new Map<String, Id>();
        for (RecordType rt : [
            SELECT Id, DeveloperName
            FROM RecordType
            WHERE SObjectType = :sObjectApiName AND IsActive = true
        ]) {
            result.put(rt.DeveloperName, rt.Id);
        }
        return result;
    }

    private static User createPortalUser(Contact contactRecord, String key) {
        Profile portalProfile = getPortalProfile();
        String unique = String.valueOf(System.currentTimeMillis())
            + key
            + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        String alias = key.length() > 8 ? key.substring(0, 8) : key;
        if (alias.length() < 2) {
            alias = 'TU';
        }

        User portalUser = new User(
            FirstName = 'Test',
            LastName = key,
            Email = unique + '@example.com',
            Username = unique + '@example.com.test',
            Alias = alias,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = portalProfile.Id,
            ContactId = contactRecord.Id
        );
        putFieldIfCreateable(portalUser, 'CommunityNickname', ('OISC' + unique).left(40));
        return portalUser;
    }

    private static Profile getPortalProfile() {
        Set<Id> portalLicenseIds = new Set<Id>();
        for (UserLicense licenseRecord : [
            SELECT Id, Name
            FROM UserLicense
            WHERE Name LIKE '%Community%'
               OR Name LIKE '%Partner%'
               OR Name LIKE '%Portal%'
               OR Name = 'External Identity'
        ]) {
            portalLicenseIds.add(licenseRecord.Id);
        }

        if (!portalLicenseIds.isEmpty()) {
            List<Profile> licenseProfiles = [
                SELECT Id, Name, UserType, UserLicense.Name
                FROM Profile
                WHERE UserLicenseId IN :portalLicenseIds
                  AND UserType NOT IN ('Guest', 'Standard')
                ORDER BY Name
                LIMIT 1
            ];
            if (!licenseProfiles.isEmpty()) {
                return licenseProfiles[0];
            }
        }

        List<Profile> typedProfiles = [
            SELECT Id, Name, UserType
            FROM Profile
            WHERE UserType IN (
                'PowerPartner', 'CspLitePortal', 'PowerCustomerSuccess',
                'CsnOnly', 'CustomerSuccess'
            )
            ORDER BY Name
            LIMIT 1
        ];
        if (!typedProfiles.isEmpty()) {
            return typedProfiles[0];
        }

        List<Profile> namedProfiles = [
            SELECT Id, Name, UserType
            FROM Profile
            WHERE (Name LIKE '%Community%' OR Name LIKE '%Partner%' OR Name LIKE '%Portal%')
              AND UserType NOT IN ('Guest', 'Standard')
            ORDER BY Name
            LIMIT 1
        ];
        if (!namedProfiles.isEmpty()) {
            return namedProfiles[0];
        }

        throw new DmlException(
            'OrderInvoiceSearchControllerTest requires a Customer or Partner Community profile in the org.'
        );
    }

    private static User getUser(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1];
    }

    private static Id buildFakeAccountId() {
        String prefix = Schema.SObjectType.Account.getKeyPrefix();
        return (Id) (prefix + '000000000AAA');
    }

    private static void expectAuraError(String expectedMessage, SearchAction action) {
        Boolean threw = false;
        try {
            action.run();
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(
                e.getMessage().contains(expectedMessage),
                'Expected message containing "' + expectedMessage + '" but got "' + e.getMessage() + '"'
            );
        }
        System.assertEquals(true, threw, 'Expected AuraHandledException for message: ' + expectedMessage);
    }

    private class SearchAction {
        private String methodName;
        private Map<String, Object> params;

        SearchAction(String methodName, Map<String, Object> params) {
            this.methodName = methodName;
            this.params = params;
        }

        void run() {
            if (methodName == 'searchRecords') {
                OrderInvoiceSearchController.searchRecords(
                    (String) params.get('objectName'),
                    (String) params.get('fromDate'),
                    (String) params.get('toDate'),
                    (Id) params.get('searchAccountId'),
                    (String) params.get('status'),
                    (String) params.get('grnStatus'),
                    (String) params.get('invoiceCreated'),
                    (String) params.get('invoiceRecordType')
                );
            } else if (methodName == 'getInitData') {
                OrderInvoiceSearchController.getInitData();
            }
        }
    }
}