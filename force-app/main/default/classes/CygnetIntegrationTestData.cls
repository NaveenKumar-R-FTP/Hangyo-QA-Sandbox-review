@IsTest
public class CygnetIntegrationTestData {
    public static final String GSTIN_29_A = '29AACPH8447G1Z5';
    public static final String GSTIN_29_B = '29AABCU9603R1Z2';

    public static Id createInvoiceWithLine(Boolean underSsRecordType) {
        if (!Schema.getGlobalDescribe().containsKey('Product__c')
            || !Schema.getGlobalDescribe().containsKey('Invoice_Line_Item__c')) {
            System.assert(false, 'Missing Product__c or Invoice_Line_Item__c in this org.');
        }

        Account seller = new Account(Name = 'Dist Seller');
        putIfFieldExists(seller, 'GSTIN__c', GSTIN_29_A);
        assignAccountRecordTypeForIntegrationTests(seller);
        populateRequiredFields(seller);
        insert seller;

        Account buyer = new Account(Name = 'Retail Buyer');
        putIfFieldExists(buyer, 'GSTIN__c', GSTIN_29_B);
        assignAccountRecordTypeForIntegrationTests(buyer);
        populateRequiredFields(buyer);
        insert buyer;

        Account underSsBuyer;
        if (underSsRecordType == true) {
            underSsBuyer = new Account(Name = 'Under SS Buyer');
            putIfFieldExists(underSsBuyer, 'GSTIN__c', GSTIN_29_A);
            assignAccountRecordTypeForIntegrationTests(underSsBuyer);
            populateRequiredFields(underSsBuyer);
            insert underSsBuyer;
        }

        Invoice__c inv = new Invoice__c();
        inv.RecordTypeId = resolveInvoiceRecordTypeId(underSsRecordType);
        putIfFieldExists(inv, 'Status__c', 'Confirmed');
        putIfFieldExists(inv, 'Invoice_Number__c', 'INV-UT-' + String.valueOf(DateTime.now().getTime()));
        putIfFieldExists(inv, 'Invoice_Date__c', Date.today());
        putIfFieldExists(inv, 'Distributor_Account__c', seller.Id);
        putIfFieldExists(inv, 'Retailer_Account__c', buyer.Id);
        putIfFieldExists(inv, 'Retailer_GSTIN__c', GSTIN_29_B);
        putIfFieldExists(inv, 'Taxable_Amount__c', 1000);
        putIfFieldExists(inv, 'CGST_Amount__c', 90);
        putIfFieldExists(inv, 'SGST_Amount__c', 90);
        putIfFieldExists(inv, 'IGST_Amount__c', 0);
        putIfFieldExists(inv, 'Invoice_Total__c', 1180);
        putIfFieldExists(inv, 'Total_Discount__c', 0);
        putIfFieldExists(inv, 'Place_of_Supply__c', 'Karnataka');
        if (underSsRecordType == true && underSsBuyer != null) {
            putIfFieldExists(inv, 'Under_SS__c', underSsBuyer.Id);
            putIfFieldExists(inv, 'Under_SS_GSTIN__c', GSTIN_29_A);
        }
        populateRequiredFields(inv);
        insert inv;

        SObject prod = Schema.getGlobalDescribe().get('Product__c').newSObject();
        prod.put('Name', 'Unit Test Product');
        putIfFieldExists(prod, 'HSN_Code__c', '0405');
        putIfFieldExists(prod, 'HSN__c', '0405');
        CygnetIntegrationTestDataFactory.prepareProductForInvoiceLineLookupFilter(prod, seller.Id, buyer.Id);
        populateRequiredFields(prod);
        insert prod;

        SObject line = Schema.getGlobalDescribe().get('Invoice_Line_Item__c').newSObject();
        line.put('Invoice__c', inv.Id);
        line.put('Product__c', (Id) prod.get('Id'));
        putIfFieldExists(line, 'Quantity__c', 1);
        putIfFieldExists(line, 'Price__c', 1000);
        putIfFieldExists(line, 'CGST_Amount__c', 90);
        putIfFieldExists(line, 'SGST_Amount__c', 90);
        putIfFieldExists(line, 'IGST_Amount__c', 0);
        populateRequiredFields(line);
        insert line;

        return inv.Id;
    }

    public static void makeInvoiceEwayBillReady(Id invoiceId) {
        System.assertNotEquals(null, invoiceId, 'invoiceId required');
        SObject inv = new Invoice__c(Id = invoiceId);
        putIfFieldExists(inv, 'IRN_Number__c', CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX);
        putIfFieldExists(inv, 'Vehicle_Number__c', 'KA01AB1234');
        putIfFieldExists(inv, 'Transport_Mode__c', 'Road');
        putIfFieldExists(inv, 'Transport_Distance__c', 10);
        putIfFieldExists(inv, 'Transporter_Doc_Number__c', 'DOC12345678901');
        putIfFieldExists(inv, 'Transporter_Doc_Date__c', Date.today());
        update inv;
    }

    private static Id resolveInvoiceRecordTypeId(Boolean underSs) {
        Schema.DescribeSObjectResult d = Invoice__c.SObjectType.getDescribe();
        Map<String, Schema.RecordTypeInfo> byDev = d.getRecordTypeInfosByDeveloperName();
        String preferred = (underSs == true) ? 'Secondary_Invoice_Under_SS' : 'Secondary_Invoice';
        if (byDev != null && byDev.containsKey(preferred)) {
            return byDev.get(preferred).getRecordTypeId();
        }
        // Fallback: use any available record type (avoid returning null in orgs with different dev names).
        for (Schema.RecordTypeInfo rti : d.getRecordTypeInfos()) {
            if (rti != null && rti.isAvailable() && !rti.isMaster()) {
                return rti.getRecordTypeId();
            }
        }
        // If only master exists, let it be null (master) to keep insert working in orgs without RTs.
        return null;
    }

    /**
     * Avoid org Account BeforeInsert automation (e.g. GenerateRetailerCreationCode) that NPEs in tests when
     * Retailer record types or config are missing. Prefer distributor / superstockist record types.
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

    private static void populateRequiredFields(SObject row) {
        if (row == null) return;
        Schema.DescribeSObjectResult dsr = row.getSObjectType().getDescribe();
        Map<String, Schema.SObjectField> fm = dsr.fields.getMap();
        for (String api : fm.keySet()) {
            Schema.DescribeFieldResult d = fm.get(api).getDescribe();
            if (d == null) continue;
            if (!d.isCreateable()) continue;
            if (d.isNillable()) continue;
            if (d.isDefaultedOnCreate()) continue;
            if (d.isCalculated()) continue;
            if (d.getName() == 'Id') continue;
            if (row.get(d.getName()) != null) continue;

            Schema.DisplayType t = d.getType();
            Object v;
            if (t == Schema.DisplayType.Boolean) v = true;
            else if (t == Schema.DisplayType.Date) v = Date.today();
            else if (t == Schema.DisplayType.DateTime) v = System.now();
            else if (t == Schema.DisplayType.Integer) v = 1;
            else if (t == Schema.DisplayType.Double || t == Schema.DisplayType.Currency || t == Schema.DisplayType.Percent) v = 1;
            else if (t == Schema.DisplayType.String || t == Schema.DisplayType.TextArea || t == Schema.DisplayType.Phone || t == Schema.DisplayType.Url || t == Schema.DisplayType.Email) {
                Integer len = d.getLength();
                String base = 'UT';
                v = (len != null && len > 0) ? base.left(Math.min(len, base.length())) : base;
            } else if (t == Schema.DisplayType.Picklist) {
                List<Schema.PicklistEntry> pvs = d.getPicklistValues();
                if (pvs != null) {
                    for (Schema.PicklistEntry pe : pvs) {
                        if (pe != null && pe.isActive()) {
                            v = pe.getValue();
                            break;
                        }
                    }
                }
            } else if (t == Schema.DisplayType.MultiPicklist) {
                List<Schema.PicklistEntry> pvs = d.getPicklistValues();
                if (pvs != null) {
                    for (Schema.PicklistEntry pe : pvs) {
                        if (pe != null && pe.isActive()) {
                            v = pe.getValue();
                            break;
                        }
                    }
                }
            } else {
                // For required lookup/reference and other complex types, we cannot safely auto-populate.
                v = null;
            }

            if (v != null) {
                try { row.put(d.getName(), v); } catch (Exception e) { }
            }
        }
    }

    private static void putIfFieldExists(SObject row, String fieldApi, Object val) {
        if (row == null || String.isBlank(fieldApi)) return;
        Map<String, Schema.SObjectField> fm = row.getSObjectType().getDescribe().fields.getMap();
        if (!fm.containsKey(fieldApi.toLowerCase())) return;

        Schema.DescribeFieldResult d = fm.get(fieldApi.toLowerCase()).getDescribe();
        if (!d.isCreateable() || d.isCalculated()) {
            return;
        }
        Schema.DisplayType t = d.getType();
        Object v = val;
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