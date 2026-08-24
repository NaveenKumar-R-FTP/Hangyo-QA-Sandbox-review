/**
 * Test data for Cygnet integration tests only. Not referenced from production code.
 */
public class CygnetIntegrationTestDataFactory {
    static final String GSTIN_29_A = '29AACPH8447G1Z5';
    static final String GSTIN_29_B = '29AABCU9603R1Z2';

    public static void insertCygnetHierarchySettings() {
        Cygnet_Integration_Setting__c s = new Cygnet_Integration_Setting__c();
        s.SetupOwnerId = UserInfo.getUserId();
        s.Base_Url__c = 'https://mock.cygnet.example';
        s.Client_Id__c = 'test-client-id';
        s.Client_Secret__c = 'test-client-secret';
        s.Username__c = 'api-user';
        s.Password__c = 'api-pass';
        s.SF_User_Name__c = UserInfo.getUserName();
        insert s;
    }

    public static void insertCygnetUnderSsHierarchySettings() {
        Cygnet_Integration_Setting_Under_SS__c s = new Cygnet_Integration_Setting_Under_SS__c();
        s.SetupOwnerId = UserInfo.getUserId();
        s.Base_Url__c = 'https://mock.cygnet-under-ss.example';
        s.Client_Id__c = 'test-client-id-ss';
        s.Client_Secret__c = 'test-client-secret-ss';
        s.Username__c = 'api-user-ss';
        s.Password__c = 'api-pass-ss';
        s.SF_User_Name__c = UserInfo.getUserName();
        insert s;
    }

    /**
     * @param underSsRecordType if true, uses Secondary_Invoice_Under_SS when available; else Secondary_Invoice
     */
    public static Id createInvoiceWithLineForMapper(Boolean underSsRecordType) {
        if (!Schema.getGlobalDescribe().containsKey('Product__c')
            || !Schema.getGlobalDescribe().containsKey('Invoice_Line_Item__c')) {
            return null;
        }

        Id rtId = resolveInvoiceRecordTypeId(underSsRecordType);
        if (rtId == null) {
            return null;
        }

        Account dist = newAccountWithGstin('Dist Seller', GSTIN_29_A);
        Account retailer = newAccountWithGstin('Retail Buyer', GSTIN_29_B);
        assignAccountRecordTypeForIntegrationTests(dist);
        assignAccountRecordTypeForIntegrationTests(retailer);
        insert new List<Account>{ dist, retailer };

        Account underSsBuyer;
        if (underSsRecordType) {
            underSsBuyer = newAccountWithGstin('Under SS Buyer', GSTIN_29_A);
            assignAccountRecordTypeForIntegrationTests(underSsBuyer);
            insert underSsBuyer;
        }

        SObject inv = new Invoice__c();
        inv.put('RecordTypeId', rtId);
        putIfFieldExists(inv, 'Status__c', 'Confirmed');
        putIfFieldExists(inv, 'Invoice_Number__c', 'INV-UT-' + String.valueOf(DateTime.now().getTime()));
        putIfFieldExists(inv, 'Invoice_Date__c', Date.today());
        putIfFieldExists(inv, 'Distributor_Account__c', dist.Id);
        putIfFieldExists(inv, 'Retailer_Account__c', retailer.Id);
        // Tax / discount / totals often formula or read-only — only write if createable.
        putIfFieldExists(inv, 'Taxable_Amount__c', 1000);
        putIfFieldExists(inv, 'CGST_Amount__c', 90);
        putIfFieldExists(inv, 'SGST_Amount__c', 90);
        putIfFieldExists(inv, 'IGST_Amount__c', 0);
        putIfFieldExists(inv, 'Invoice_Total__c', 1180);
        putIfFieldExists(inv, 'Total_Discount__c', 0);
        putIfFieldExists(inv, 'Place_of_Supply__c', 'Karnataka');
        if (underSsRecordType && underSsBuyer != null) {
            putIfFieldExists(inv, 'Under_SS__c', underSsBuyer.Id);
        }
        insert inv;

        SObject prod = Schema.getGlobalDescribe().get('Product__c').newSObject();
        prod.put('Name', 'Unit Test Product');
        putIfFieldExists(prod, 'HSN_Code__c', '0405');
        putIfFieldExists(prod, 'HSN__c', '0405');
        prepareProductForInvoiceLineLookupFilter(prod, dist.Id, retailer.Id);
        insert prod;

        SObject line = Schema.getGlobalDescribe().get('Invoice_Line_Item__c').newSObject();
        line.put('Invoice__c', inv.Id);
        line.put('Product__c', prod.Id);
        putIfFieldExists(line, 'Quantity__c', 1);
        putIfFieldExists(line, 'Price__c', 1000);
        putIfFieldExists(line, 'CGST_Amount__c', 90);
        putIfFieldExists(line, 'SGST_Amount__c', 90);
        putIfFieldExists(line, 'IGST_Amount__c', 0);
        insert line;

        return (Id) inv.get('Id');
    }

    public static Id createInvoiceForEWayBillQueueable(Id invoiceId) {
        if (invoiceId == null) {
            return null;
        }
        SObject inv = new Invoice__c(Id = invoiceId);
        putIfFieldExists(inv, 'IRN_Number__c', CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX);
        putIfFieldExists(inv, 'Vehicle_Number__c', 'KA01AB1234');
        putIfFieldExists(inv, 'Transport_Mode__c', 'Road');
        putIfFieldExists(inv, 'Transport_Distance__c', 10);
        putIfFieldExists(inv, 'Transporter_Doc_Number__c', 'DOC12345678901');
        putIfFieldExists(inv, 'Transporter_Doc_Date__c', Date.today());
        update inv;
        return invoiceId;
    }

    /**
     * Prefer non-Retailer Account RTs so org BeforeInsert logic (e.g. GenerateRetailerCreationCode) does not NPE in tests.
     */
    private static void assignAccountRecordTypeForIntegrationTests(Account a) {
        if (a == null || a.RecordTypeId != null) {
            return;
        }
        Schema.DescribeSObjectResult d = Account.SObjectType.getDescribe();
        Id fallbackAny = null;
        for (Schema.RecordTypeInfo rti : d.getRecordTypeInfos()) {
            if (rti == null || !rti.isAvailable() || rti.isMaster()) {
                continue;
            }
            if (fallbackAny == null) {
                fallbackAny = rti.getRecordTypeId();
            }
            String dn = rti.getDeveloperName() != null ? rti.getDeveloperName().toLowerCase() : '';
            if ((dn.contains('retail') && !dn.contains('dist')) || dn.contains('customer') || dn == 'buyer') {
                continue;
            }
            if (dn.contains('dist') || dn.contains('super') || dn.contains('stockist') || dn.contains('vendor')) {
                a.RecordTypeId = rti.getRecordTypeId();
                return;
            }
        }
        if (a.RecordTypeId == null && fallbackAny != null) {
            a.RecordTypeId = fallbackAny;
        }
    }

    private static Account newAccountWithGstin(String name, String gstin) {
        Account a = new Account(Name = name);
        putIfFieldExists(a, 'GSTIN__c', gstin);
        a.BillingStreet = 'Line 1 Street Address Here';
        a.BillingCity = 'Bengaluru';
        a.BillingState = '29';
        a.BillingPostalCode = '560001';
        a.Phone = '9876543210';
        putIfFieldExists(a, 'Primary_Address_1__c', 'Line 1 Street Address Here');
        putIfFieldExists(a, 'Primary_City__c', 'Bengaluru');
        putIfFieldExists(a, 'Primary_PINCode__c', 560001);
        putIfFieldExists(a, 'Primary_State_Code__c', '29');
        return a;
    }

    /**
     * Invoice_Line_Item__c.Product__c often has a lookup filter (e.g. product must match invoice distributor).
     * Set Account lookups on Product__c heuristically so test inserts pass without org-specific field API names.
     */
    public static void prepareProductForInvoiceLineLookupFilter(
        SObject prod,
        Id distributorAccountId,
        Id retailerAccountId
    ) {
        if (prod == null) {
            return;
        }
        Map<String, Schema.SObjectField> fm = prod.getSObjectType().getDescribe().fields.getMap();
        for (String key : fm.keySet()) {
            Schema.DescribeFieldResult d = fm.get(key).getDescribe();
            if (d == null || !d.isCreateable() || d.isCalculated()) {
                continue;
            }
            if (d.getType() != Schema.DisplayType.REFERENCE) {
                continue;
            }
            Boolean pointsToAccount = false;
            for (Schema.SObjectType rt : d.getReferenceTo()) {
                if (rt == Account.SObjectType) {
                    pointsToAccount = true;
                    break;
                }
            }
            if (!pointsToAccount) {
                continue;
            }
            String api = d.getName().toLowerCase();
            try {
                if (api.contains('dist')
                    || api.contains('super')
                    || api.contains('stockist')
                    || api.contains('vendor')
                    || api.contains('principal')) {
                    if (distributorAccountId != null) {
                        prod.put(d.getName(), distributorAccountId);
                    }
                } else if (api.contains('retail') || api.contains('dealer') || api.contains('buyer')) {
                    if (retailerAccountId != null) {
                        prod.put(d.getName(), retailerAccountId);
                    }
                }
            } catch (Exception e) {
                // ignore field-level validation; other lookups may satisfy filter
            }
        }
        putIfFieldExists(prod, 'Active__c', true);
        putIfFieldExists(prod, 'Is_Active__c', true);
        putIfFieldExists(prod, 'IsActive__c', true);
        assignProductRecordTypeIfNeeded(prod);
    }

    private static void assignProductRecordTypeIfNeeded(SObject prod) {
        if (prod == null || prod.get('RecordTypeId') != null) {
            return;
        }
        Schema.DescribeSObjectResult d = prod.getSObjectType().getDescribe();
        for (Schema.RecordTypeInfo rti : d.getRecordTypeInfos()) {
            if (rti != null && rti.isAvailable() && !rti.isMaster()) {
                prod.put('RecordTypeId', rti.getRecordTypeId());
                return;
            }
        }
    }

    private static Id resolveInvoiceRecordTypeId(Boolean underSs) {
        Schema.DescribeSObjectResult d = Invoice__c.SObjectType.getDescribe();
        String devName = underSs ? 'Secondary_Invoice_Under_SS' : 'Secondary_Invoice';
        Map<String, Schema.RecordTypeInfo> byDev = d.getRecordTypeInfosByDeveloperName();
        if (byDev.containsKey(devName)) {
            return byDev.get(devName).getRecordTypeId();
        }
        return null;
    }

    private static void putIfFieldExists(SObject row, String fieldApi, Object val) {
        if (row == null || String.isBlank(fieldApi)) {
            return;
        }
        Map<String, Schema.SObjectField> fm = row.getSObjectType().getDescribe().fields.getMap();
        if (fm.containsKey(fieldApi.toLowerCase())) {
            Schema.DescribeFieldResult d = fm.get(fieldApi.toLowerCase()).getDescribe();
            if (!d.isCreateable() || d.isCalculated()) {
                return;
            }
            Schema.DisplayType t = d.getType();
            Object v = val;
            // Coerce common numeric fields when tests pass a string.
            if (v != null && v instanceof String && (
                t == Schema.DisplayType.Double ||
                t == Schema.DisplayType.Currency ||
                t == Schema.DisplayType.Integer ||
                t == Schema.DisplayType.Percent
            )) {
                try {
                    String s = ((String) v).replaceAll('[^0-9\\.-]', '');
                    v = String.isNotBlank(s) ? Decimal.valueOf(s) : null;
                } catch (Exception e) {
                    v = null;
                }
            }
            row.put(fieldApi, v);
        }
    }
}