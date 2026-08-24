public without sharing class OrderInvoiceSearchController {

    public static final String DIST_TYPE_SUPER_STOCKIEST    = 'SUPER_STOCKIEST';
    public static final String DIST_TYPE_DIRECT_DISTRIBUTOR  = 'DIRECT_DISTRIBUTOR';
    public static final String DIST_TYPE_UNDER_SS            = 'UNDER_SS';

    private static final String ACCOUNT_RT_SUPER_STOCKIEST = 'SuperStockist'; 
    private static final String ACCOUNT_RT_DISTRIBUTOR     = 'Distributor';

    private static final String ACCOUNT_DIST_TYPE_DIRECT   = 'Direct Distributor';
    private static final String ACCOUNT_DIST_TYPE_UNDER_SS = 'Under Super Stockist';

    private static final String ORDER_RT_PRIMARY             = 'Primary_Order';
    private static final String ORDER_RT_SECONDARY           = 'Secondary_Order';
    private static final String ORDER_RT_COUNTER             = 'Counter_Order';
    private static final String ORDER_RT_UNDER_SS            = 'Under_SS_Order';
    private static final String ORDER_RT_UNDER_SS_SECONDARY  = 'Under_SS_Secondary_Order';

    private static final String INVOICE_RT_PRIMARY            = 'Primary_Invoice';
    private static final String INVOICE_RT_SECONDARY          = 'Secondary_Invoice';
    private static final String INVOICE_RT_SECONDARY_UNDER_SS = 'Secondary_Invoice_Under_SS';

    private static final String OBJ_PRIMARY_ORDER           = 'Primary Order';
    private static final String OBJ_SECONDARY_ORDER          = 'Secondary Order';
    private static final String OBJ_COUNTER_ORDER            = 'Counter Order';
    private static final String OBJ_UNDER_SS_SECONDARY_ORDER = 'Under SS Secondary Order';
    private static final String OBJ_INVOICE                  = 'Invoice';
    private static final String OBJ_COLLECTION = 'Collection';
    private static final String OBJ_RETURN = 'Return';
    private static final String OBJ_DELIVERY_PLAN = 'Delivery Plan';
    
    private static final String INV_RT_PRIMARY_LOGICAL = 'Primary Invoice';
    private static final String INV_RT_SECONDARY_LOGICAL = 'Secondary Invoice';
    private static final String INV_RT_SECONDARY_UNDER_SS_LOGICAL = 'Secondary Invoice Under SS';

    private static Map<String, Id> orderRecordTypeIdsByDevName {
        get {
            if (orderRecordTypeIdsByDevName == null) {
                orderRecordTypeIdsByDevName = loadRecordTypeIds('Order__c');
            }
            return orderRecordTypeIdsByDevName;
        }
        set;
    }

    private static Map<String, Id> invoiceRecordTypeIdsByDevName {
        get {
            if (invoiceRecordTypeIdsByDevName == null) {
                invoiceRecordTypeIdsByDevName = loadRecordTypeIds('Invoice__c');
            }
            return invoiceRecordTypeIdsByDevName;
        }
        set;
    }

    private static Map<String, Id> loadRecordTypeIds(String sobjectApiName) {
        Map<String, Id> result = new Map<String, Id>();
        for (RecordType rt : [SELECT Id, DeveloperName FROM RecordType WHERE SObjectType = :sobjectApiName]) {
            result.put(rt.DeveloperName, rt.Id);
        }
        return result;
    }

    public class InitData {
        @AuraEnabled public String distributorType;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public List<OptionWrapper> objectOptions;
        @AuraEnabled public List<OptionWrapper> orderStatusOptions;
        @AuraEnabled public List<OptionWrapper> counterOrderStatusOptions;
        @AuraEnabled public List<OptionWrapper> invoiceStatusOptions;
        @AuraEnabled public List<OptionWrapper> grnStatusOptions;
        @AuraEnabled public List<OptionWrapper> invoiceRecordTypeOptions;
    }

    public class OptionWrapper {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public OptionWrapper(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class LookupResult {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String code;
        @AuraEnabled public String type;
    }

    public class SearchFilter {
        @AuraEnabled public String distributorType;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String objectName;
        @AuraEnabled public String fromDate;
        @AuraEnabled public String toDate;
        @AuraEnabled public Id searchAccountId;
        @AuraEnabled public String status;
        @AuraEnabled public String grnStatus;
        @AuraEnabled public String invoiceCreated;
        @AuraEnabled public String invoiceRecordType;
    }

    public class SearchResult {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String recordName;
        @AuraEnabled public String recordTypeLabel;
        @AuraEnabled public Date recordDate;
        @AuraEnabled public String status;
        @AuraEnabled public String grnStatus;
        @AuraEnabled public String invoiceCreated;
        @AuraEnabled public String paymentStatus;
        @AuraEnabled public String retailerName;
        @AuraEnabled public String distributorName;
        @AuraEnabled public String isInvoice;
        @AuraEnabled public String customerName;
        @AuraEnabled public String invoiceName;
        @AuraEnabled public Id invoiceId; //Added by Hari for the Return URL
        @AuraEnabled public String orderName;
        @AuraEnabled public String paymentMethod;
        @AuraEnabled public Decimal amountCollected;
        @AuraEnabled public Decimal returnQuantity;
        @AuraEnabled public Decimal returnAmount;
        @AuraEnabled public String driverName;
        @AuraEnabled public String driverNumber;
        @AuraEnabled public String vehicleNumber;
        //Added by hari - Onclick Details
        @AuraEnabled public Decimal totalQuantity;
        @AuraEnabled public Decimal totalOrderValue;
        @AuraEnabled public String beatName;
        @AuraEnabled public String orderedBy;
        @AuraEnabled public String superStockistName;
        @AuraEnabled public String underSsName;
        @AuraEnabled public Decimal invoiceAmount;
        @AuraEnabled public Decimal totalPayableBalance;
    }

    @AuraEnabled(cacheable=true)
    public static InitData getInitData() {
        try {
            DistributorContext ctx = resolveDistributorContext();

            InitData data = new InitData();
            data.distributorType = ctx.distributorType;
            data.accountId = ctx.accountId;
            data.accountName = ctx.accountName;
            data.objectOptions = buildObjectOptions(ctx.distributorType);
            data.orderStatusOptions = buildStaticOptions(new List<String>{
                'Order Placed', 'Partially Invoiced', 'Invoiced', 'Delivered'
            });
            data.counterOrderStatusOptions = buildStaticOptions(new List<String>{
                'Order Placed', 'Delivered'
            });
            data.invoiceStatusOptions = buildStaticOptions(new List<String>{
                'Draft', 'Confirmed', 'Delivered', 'Delivered + Paid', 'Delivered + Not Paid'
            });
            data.grnStatusOptions = buildGrnStatusOptions(new List<String>{
                'Pending', 'Partially GRN', 'Fully GRN'
            });
            data.invoiceRecordTypeOptions = buildInvoiceRecordTypeOptions(ctx.distributorType);
            return data;
        } catch (Exception e) {
            throw wrapException('Unable to load your distributor context.', e);
        }
    }

    private static List<OptionWrapper> buildObjectOptions(String distributorType) {
        List<OptionWrapper> options = new List<OptionWrapper>();
        options.add(new OptionWrapper('Primary Order', OBJ_PRIMARY_ORDER));
        options.add(new OptionWrapper('Secondary Order', OBJ_SECONDARY_ORDER));
        if (distributorType == DIST_TYPE_SUPER_STOCKIEST) {
            options.add(new OptionWrapper('Under SS Secondary Order', OBJ_UNDER_SS_SECONDARY_ORDER));
        }
        //options.add(new OptionWrapper('Counter Order', OBJ_COUNTER_ORDER));
        options.add(new OptionWrapper('Invoice', OBJ_INVOICE));
        options.add(new OptionWrapper('Collection', OBJ_COLLECTION));
        options.add(new OptionWrapper('Return', OBJ_RETURN));
        options.add(new OptionWrapper('Delivery Plan', OBJ_DELIVERY_PLAN));
        return options;
    }
    
    private static List<OptionWrapper> buildInvoiceRecordTypeOptions(String distributorType) {
        List<OptionWrapper> options = new List<OptionWrapper>();
        if (distributorType == DIST_TYPE_SUPER_STOCKIEST) {
            options.add(new OptionWrapper('Primary Invoice', INV_RT_PRIMARY_LOGICAL));
            options.add(new OptionWrapper('Secondary Invoice', INV_RT_SECONDARY_LOGICAL));
            options.add(new OptionWrapper('Secondary Invoice Under SS', INV_RT_SECONDARY_UNDER_SS_LOGICAL));
        } else if (distributorType == DIST_TYPE_DIRECT_DISTRIBUTOR) {
            options.add(new OptionWrapper('Primary Invoice', INV_RT_PRIMARY_LOGICAL));
            options.add(new OptionWrapper('Secondary Invoice', INV_RT_SECONDARY_LOGICAL));
        } else if (distributorType == DIST_TYPE_UNDER_SS) {
            options.add(new OptionWrapper('Secondary Invoice', INV_RT_SECONDARY_LOGICAL));
            options.add(new OptionWrapper('Secondary Invoice Under SS', INV_RT_SECONDARY_UNDER_SS_LOGICAL));
        }
        return options;
    }

    private static List<OptionWrapper> buildStaticOptions(List<String> values) {
        List<OptionWrapper> options = new List<OptionWrapper>();
        for (String v : values) {
            options.add(new OptionWrapper(v, v));
        }
        return options;
    }

    private static List<OptionWrapper> buildGrnStatusOptions(List<String> values) {
        List<OptionWrapper> options = new List<OptionWrapper>();
        for (String v : values) {
            options.add(new OptionWrapper(v, v));
        }
        return options;
    }

    private class DistributorContext {
        String distributorType;
        Id accountId;
        String accountName;
    }

    private static DistributorContext resolveDistributorContext() {
        List<User> users = [
            SELECT Id, ContactId, Contact.AccountId,
                   Contact.Account.Name,
                   Contact.Account.RecordType.DeveloperName,
                   Contact.Account.Distributor_Type__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        if (users.isEmpty() || users[0].ContactId == null || users[0].Contact.AccountId == null) {
            throw newAhe('Your user is not linked to a distributor account. Please contact your administrator.');
        }

        User u = users[0];
        DistributorContext ctx = new DistributorContext();
        ctx.accountId = u.Contact.AccountId;
        ctx.accountName = u.Contact.Account.Name;

        String accountRt = u.Contact.Account.RecordType?.DeveloperName;
        String distType = u.Contact.Account.Distributor_Type__c;

        if (accountRt == ACCOUNT_RT_SUPER_STOCKIEST) {
            ctx.distributorType = DIST_TYPE_SUPER_STOCKIEST;
        } else if (accountRt == ACCOUNT_RT_DISTRIBUTOR && distType == ACCOUNT_DIST_TYPE_DIRECT) {
            ctx.distributorType = DIST_TYPE_DIRECT_DISTRIBUTOR;
        } else if (accountRt == ACCOUNT_RT_DISTRIBUTOR && distType == ACCOUNT_DIST_TYPE_UNDER_SS) {
            ctx.distributorType = DIST_TYPE_UNDER_SS;
        } else {
            throw newAhe('Your account is not configured as a valid distributor type. Please contact your administrator.');
        }
        return ctx;
    }

    @AuraEnabled(cacheable=true)
    public static List<LookupResult> searchLookup(String searchTerm) {
        try {
            if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
                return new List<LookupResult>();
            }
            DistributorContext ctx = resolveDistributorContext();
            String term = '%' + searchTerm.trim() + '%';

            List<LookupResult> results = new List<LookupResult>();

            if (ctx.distributorType == DIST_TYPE_SUPER_STOCKIEST) {
                // Match retailers linked via Distributor__c (common), Super_Stockist_Name__c,
                // or under an Under-SS distributor of this SS.
                for (Account acc : [
                    SELECT Id, Name, Retailer_Code__c
                    FROM Account
                    WHERE RecordType.DeveloperName = 'Retailer'
                      AND (
                            Distributor__c = :ctx.accountId
                         OR Super_Stockist_Name__c = :ctx.accountId
                         OR Distributor__r.Super_Stockist_Name__c = :ctx.accountId
                      )
                      AND (Name LIKE :term OR Retailer_Code__c LIKE :term)
                    ORDER BY Name
                    LIMIT 25
                ]) {
                    LookupResult lr = new LookupResult();
                    lr.id = acc.Id;
                    lr.name = acc.Name;
                    lr.code = acc.Retailer_Code__c;
                    lr.type = 'Retailer';
                    results.add(lr);
                }
                //Added By Hari - Rectify the Under SS Lookup on Superstockist
                Map<String, Object> underSsBinds = new Map<String, Object>{
                    'ssAccountId' => ctx.accountId,
                    'term' => term,
                    'rtDist' => ACCOUNT_RT_DISTRIBUTOR,
                    //'distTypeUnderSs' => ACCOUNT_DIST_TYPE_UNDER_SS
                    'distTypeUnderSs' => 'Under Super Stockist'
                };
                String underSsQuery =
                    'SELECT Id, Name, Distributor_Code__c FROM Account ' +
                    'WHERE RecordType.DeveloperName = :rtDist ' +
                    'AND Distributor_Type__c = :distTypeUnderSs ' +
                    'AND (Super_Stockist_Name__c = :ssAccountId OR Distributor__c = :ssAccountId) ' +
                    'AND (Name LIKE :term OR Distributor_Code__c LIKE :term) ' +
                    'ORDER BY Name LIMIT 25';

                //Added by Hari - for Error testing
                System.debug(LoggingLevel.INFO, 'Under SS Lookup - ssAccountId: ' + underSsBinds.get('ssAccountId'));
                System.debug(LoggingLevel.INFO, 'Under SS Lookup - term: ' + underSsBinds.get('term'));
                System.debug(LoggingLevel.INFO, 'Under SS Lookup - rtDist: ' + underSsBinds.get('rtDist'));
                System.debug(LoggingLevel.INFO, 'Under SS Lookup - distTypeUnderSs: ' + underSsBinds.get('distTypeUnderSs'));
                System.debug(LoggingLevel.INFO, 'Under SS Lookup - underSsBinds: ' + JSON.serialize(underSsBinds));
                System.debug(LoggingLevel.INFO, 'Under SS Lookup - Query: ' + underSsQuery);
                String underSsQueryResolved =
                    'SELECT Id, Name, Distributor_Code__c FROM Account ' +
                    'WHERE RecordType.DeveloperName = \'' + String.escapeSingleQuotes(String.valueOf(underSsBinds.get('rtDist'))) + '\' ' +
                    'AND Distributor_Type__c = \'' + String.escapeSingleQuotes(String.valueOf(underSsBinds.get('distTypeUnderSs'))) + '\' ' +
                    'AND (Super_Stockist_Name__c = \'' + String.valueOf(underSsBinds.get('ssAccountId')) + '\' OR Distributor__c = \'' + String.valueOf(underSsBinds.get('ssAccountId')) + '\') ' +
                    'AND (Name LIKE \'' + String.escapeSingleQuotes(String.valueOf(underSsBinds.get('term'))) + '\' OR Distributor_Code__c LIKE \'' + String.escapeSingleQuotes(String.valueOf(underSsBinds.get('term'))) + '\') ' +
                    'ORDER BY Name LIMIT 25';
                System.debug(LoggingLevel.INFO, 'Under SS Lookup - Query Resolved: ' + underSsQueryResolved);
                List<Account> underSsAccounts = (List<Account>) Database.queryWithBinds(
                    underSsQuery, underSsBinds, AccessLevel.SYSTEM_MODE
                );

                //Added by Hari - for Error testing
                System.debug(LoggingLevel.INFO, 'Under SS Lookup - Result Count: ' + underSsAccounts.size());
                for (Account acc : underSsAccounts) {
                    LookupResult lr = new LookupResult();
                    lr.id = acc.Id;
                    lr.name = acc.Name;
                    lr.code = acc.Distributor_Code__c;
                    lr.type = 'Under SS Distributor';
                    results.add(lr);
                }
            } else {
                for (Account acc : [
                    SELECT Id, Name, Retailer_Code__c
                    FROM Account
                    WHERE Distributor__c = :ctx.accountId
                      AND RecordType.DeveloperName = 'Retailer'
                      AND (Name LIKE :term OR Retailer_Code__c LIKE :term)
                    ORDER BY Name
                    LIMIT 25
                ]) {
                    LookupResult lr = new LookupResult();
                    lr.id = acc.Id;
                    lr.name = acc.Name;
                    lr.code = acc.Retailer_Code__c;
                    lr.type = 'Retailer';
                    results.add(lr);
                }
            }
            return results;
        } catch (Exception e) {
            throw wrapException('Unable to search retailers/distributors.', e);
        }
    }

    /*@AuraEnabled
    public static List<SearchResult> searchRecords(SearchFilter filters) {
        System.debug(LoggingLevel.INFO, 'searchRecords raw payload: ' + JSON.serialize(filters));

        try {
            if (filters == null || String.isBlank(filters.objectName)) {
                throw newAhe('Please select an object to search.');
            }

            DistributorContext ctx = resolveDistributorContext();

            Date fromDate = parseDate(filters.fromDate);
            Date toDate = parseDate(filters.toDate);
            if (fromDate != null && toDate != null && fromDate > toDate) {
                throw newAhe('From Date cannot be after To Date.');
            }

            if (filters.objectName == OBJ_INVOICE) {
                return searchInvoices(ctx, filters, fromDate, toDate);
            } else {
                return searchOrders(ctx, filters, fromDate, toDate);
            }
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw wrapException('Unable to complete the search. Please refine your filters and try again.', e);
        }
    }*/
    
    @AuraEnabled
    public static List<SearchResult> searchRecords(
        String objectName, String fromDate, String toDate, Id searchAccountId,
        String status, String grnStatus, String invoiceCreated, String invoiceRecordType
    ) {
        System.debug(LoggingLevel.INFO,
            'searchRecords params -> objectName=' + objectName +
            ', fromDate=' + fromDate + ', toDate=' + toDate +
            ', searchAccountId=' + searchAccountId + ', status=' + status +
            ', grnStatus=' + grnStatus + ', invoiceCreated=' + invoiceCreated +
            ', invoiceRecordType=' + invoiceRecordType);
    
        try {
            if (String.isBlank(objectName)) {
                throw newAhe('Please select an object to search.');
            }
    
            DistributorContext ctx = resolveDistributorContext();
    
            Date fromDateVal = parseDate(fromDate);
            Date toDateVal = parseDate(toDate);
            if (fromDateVal != null && toDateVal != null && fromDateVal > toDateVal) {
                throw newAhe('From Date cannot be after To Date.');
            }
    
            if (objectName == OBJ_INVOICE) {
                validateInvoiceSelection(ctx.distributorType, invoiceRecordType, searchAccountId);
            } else {
                validateSearchAccountForObject(searchAccountId, objectName);
            }
    
            SearchFilter filters = new SearchFilter();
            filters.objectName = objectName;
            filters.searchAccountId = searchAccountId;
            filters.status = status;
            filters.grnStatus = grnStatus;
            filters.invoiceCreated = invoiceCreated;
            filters.invoiceRecordType = invoiceRecordType;
    
            if (objectName == OBJ_INVOICE) {
                return searchInvoices(ctx, filters, fromDateVal, toDateVal);
            } else if (objectName == OBJ_COLLECTION) {
                return searchCollections(ctx, filters, fromDateVal, toDateVal);
            } else if (objectName == OBJ_RETURN) {
                return searchReturns(ctx, filters, fromDateVal, toDateVal);
            } else if (objectName == OBJ_DELIVERY_PLAN) {
                return searchDeliveryPlans(ctx, filters, fromDateVal, toDateVal);
            } else {
                return searchOrders(ctx, filters, fromDateVal, toDateVal);
            }
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw wrapException('Unable to complete the search. Please refine your filters and try again.', e);
        }
    }
    
    private static void validateInvoiceSelection(String distributorType, String invoiceRecordType, Id searchAccountId) {
        if (searchAccountId == null) {
            return;
        }
    
        // d) Primary Invoice never allows a Retailer/Under SS selection, for any distributor type.
        if (invoiceRecordType == INV_RT_PRIMARY_LOGICAL) {
            throw newAhe('Retailer / Under SS selection is not applicable for Primary Invoice.');
        }
    
        List<Account> accs = [
            SELECT Id, RecordType.DeveloperName, Distributor_Type__c FROM Account WHERE Id = :searchAccountId LIMIT 1
        ];
        if (accs.isEmpty()) {
            return;
        }
    
        Account acc = accs[0];
        Boolean isUnderSsDistributor = acc.RecordType?.DeveloperName == ACCOUNT_RT_DISTRIBUTOR
            && acc.Distributor_Type__c == ACCOUNT_DIST_TYPE_UNDER_SS;
        Boolean isRetailer = acc.RecordType?.DeveloperName == 'Retailer';
    
        // e) SS + Secondary Invoice -> must be a Retailer, not an Under SS Distributor.
        if (distributorType == DIST_TYPE_SUPER_STOCKIEST
            && invoiceRecordType == INV_RT_SECONDARY_LOGICAL
            && isUnderSsDistributor) {
            throw newAhe('Please select a Retailer, not an Under SS Distributor, for Secondary Invoice.');
        }
    
        // f) SS + Under SS Secondary Invoice -> must be an Under SS Distributor, not a Retailer.
        if (distributorType == DIST_TYPE_SUPER_STOCKIEST
            && invoiceRecordType == INV_RT_SECONDARY_UNDER_SS_LOGICAL
            && isRetailer) {
            throw newAhe('Please select an Under SS Distributor, not a Retailer, for Under SS Secondary Invoice.');
        }
    
        // g) Under SS user + Under SS Secondary Invoice -> must be an Under SS Distributor, not a Retailer.
        if (distributorType == DIST_TYPE_UNDER_SS
            && invoiceRecordType == INV_RT_SECONDARY_UNDER_SS_LOGICAL
            && isRetailer) {
            throw newAhe('Please select an Under SS Distributor, not a Retailer, for Under SS Secondary Invoice.');
        }
    }
    
    private static Id resolveInvoiceRecordTypeId(String distributorType, String invoiceRecordTypeLogical) {
        if (String.isBlank(invoiceRecordTypeLogical)) {
            if (distributorType == DIST_TYPE_SUPER_STOCKIEST) {
                return invoiceRecordTypeIdsByDevName.get(INVOICE_RT_PRIMARY);
            }
            if (distributorType == DIST_TYPE_UNDER_SS) {
                return invoiceRecordTypeIdsByDevName.get(INVOICE_RT_SECONDARY_UNDER_SS);
            }
            return invoiceRecordTypeIdsByDevName.get(INVOICE_RT_SECONDARY);
        }
        if (invoiceRecordTypeLogical == INV_RT_PRIMARY_LOGICAL) {
            return invoiceRecordTypeIdsByDevName.get(INVOICE_RT_PRIMARY);
        }
        if (invoiceRecordTypeLogical == INV_RT_SECONDARY_LOGICAL) {
            return invoiceRecordTypeIdsByDevName.get(INVOICE_RT_SECONDARY);
        }
        if (invoiceRecordTypeLogical == INV_RT_SECONDARY_UNDER_SS_LOGICAL) {
            return invoiceRecordTypeIdsByDevName.get(INVOICE_RT_SECONDARY_UNDER_SS);
        }
        return null;
    }
    
    private static void validateSearchAccountForObject(Id searchAccountId, String objectName) {
        if (searchAccountId == null) {
            return;
        }
        if (objectName != OBJ_SECONDARY_ORDER && objectName != OBJ_UNDER_SS_SECONDARY_ORDER) {
            return;
        }
    
        List<Account> accs = [
            SELECT Id, RecordType.DeveloperName, Distributor_Type__c FROM Account
            WHERE Id = :searchAccountId LIMIT 1
        ];
        if (accs.isEmpty()) {
            return;
        }
    
        Account acc = accs[0];
        Boolean isUnderSsDistributor = acc.RecordType?.DeveloperName == ACCOUNT_RT_DISTRIBUTOR
            && acc.Distributor_Type__c == ACCOUNT_DIST_TYPE_UNDER_SS;

        if (objectName == OBJ_SECONDARY_ORDER && isUnderSsDistributor) {
            throw newAhe('Please select a Retailer.');
        }
        // Under SS Secondary Orders store the Under SS Distributor on Under_SS_Distributor__c.
        if (objectName == OBJ_UNDER_SS_SECONDARY_ORDER && !isUnderSsDistributor) {
            throw newAhe('Please select an Under SS Distributor.');
        }
    }

    private static Date parseDate(String isoDate) {
        if (String.isBlank(isoDate)) {
            return null;
        }
        return Date.valueOf(isoDate);
    }

    private static String resolveAccountName(Id accountId) {
        if (accountId == null) {
            return null;
        }
        Map<String, Object> nameBinds = new Map<String, Object>{ 'accountId' => accountId };
        List<Account> accs = (List<Account>) Database.queryWithBinds(
            'SELECT Name FROM Account WHERE Id = :accountId LIMIT 1',
            nameBinds,
            AccessLevel.SYSTEM_MODE
        );
        return accs.isEmpty() ? null : accs[0].Name;
    }

    private static List<SearchResult> searchOrders(DistributorContext ctx, SearchFilter filters, Date fromDate, Date toDate) {
        Id recordTypeId = resolveOrderRecordTypeId(ctx.distributorType, filters.objectName);
        if (recordTypeId == null) {
            throw newAhe('The selected Object is not valid for your distributor type.');
        }
    
        List<String> whereClauses = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();
    
        whereClauses.add('RecordTypeId = :rtId');
        binds.put('rtId', recordTypeId);

        // Under SS Secondary Orders store the Super Stockiest on AccountId__c (Distributor Name).
        // Do not use Under_SS_Distributor__r — that relationship is invalid in this org.
        whereClauses.add('AccountId__c = :scopeAccountId');
        binds.put('scopeAccountId', ctx.accountId);

        if (filters.searchAccountId != null) {
            if (filters.objectName == OBJ_UNDER_SS_SECONDARY_ORDER) {
                String underSsDistributorName = resolveAccountName(filters.searchAccountId);
                if (String.isBlank(underSsDistributorName)) {
                    return new List<SearchResult>();
                }
                whereClauses.add('Under_SS_Distributor__c = :underSsDistributorName');
                binds.put('underSsDistributorName', underSsDistributorName);
            } else {
                whereClauses.add('Account__c = :searchAccId');
                binds.put('searchAccId', filters.searchAccountId);
            }
        }

        if (fromDate != null) {
            whereClauses.add('EffectiveDate__c >= :fromDate');
            binds.put('fromDate', fromDate);
        }
        if (toDate != null) {
            whereClauses.add('EffectiveDate__c <= :toDate');
            binds.put('toDate', toDate);
        }
        if (String.isNotBlank(filters.status)) {
            whereClauses.add('Status__c = :statusVal');
            binds.put('statusVal', filters.status);
        }

        boolean grnApplicable = filters.objectName == OBJ_PRIMARY_ORDER;
        if (grnApplicable && String.isNotBlank(filters.grnStatus)) {
            whereClauses.add('GRN_Status__c = :grnStatusVal');
            binds.put('grnStatusVal', filters.grnStatus);
        }

        boolean invoiceCreatedApplicable = filters.objectName == OBJ_SECONDARY_ORDER
            || filters.objectName == OBJ_UNDER_SS_SECONDARY_ORDER;
        if (invoiceCreatedApplicable && String.isNotBlank(filters.invoiceCreated)) {
            whereClauses.add('Invoice_Created__c = :invoiceCreatedVal');
            binds.put('invoiceCreatedVal', filters.invoiceCreated);
        }

        //Added by hari - Onclick Details
        String query =
            'SELECT Id, Name, EffectiveDate__c, Status__c, GRN_Status__c, Invoice_Created__c, ' +
            'Total_Quantity__c, Total_Order_Value__c, Beat_Name__c, Ordered_By__r.Name, ' +
            'Super_Stockist_Name__r.Name, Under_SS_Distributor__c, ' +
            'Account__r.Name, AccountId__r.Name, RecordType.Name ' +
            'FROM Order__c ' +
            'WHERE ' + String.join(whereClauses, ' AND ') +
            ' ORDER BY EffectiveDate__c DESC, Name DESC LIMIT 200';

        System.debug('Query:- ' + query);

        List<SObject> rawResults = Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
        List<Order__c> orders = (List<Order__c>) rawResults;

        List<SearchResult> output = new List<SearchResult>();
        for (Order__c ord : orders) {
            SearchResult sr = new SearchResult();
            sr.recordId = ord.Id;
            sr.recordName = ord.Name;
            sr.recordTypeLabel = ord.RecordType?.Name;
            sr.recordDate = ord.EffectiveDate__c;
            sr.status = ord.Status__c;
            sr.grnStatus = ord.GRN_Status__c;
            sr.invoiceCreated = ord.Invoice_Created__c;
            sr.retailerName = ord.Account__r?.Name;
            sr.distributorName = ord.AccountId__r?.Name;
            //Added by hari - Onclick Details
            sr.totalQuantity = ord.Total_Quantity__c;
            sr.totalOrderValue = ord.Total_Order_Value__c;
            sr.beatName = ord.Beat_Name__c;
            sr.orderedBy = ord.Ordered_By__r?.Name;
            sr.superStockistName = ord.Super_Stockist_Name__r?.Name;
            sr.underSsName = ord.Under_SS_Distributor__c;
            sr.isInvoice = 'false';
            output.add(sr);
        }
        return output;
    }

    private static Id resolveOrderRecordTypeId(String distributorType, String objectName) {
        if (objectName == OBJ_PRIMARY_ORDER) {
            if (distributorType == DIST_TYPE_UNDER_SS) {
                return orderRecordTypeIdsByDevName.get(ORDER_RT_UNDER_SS);
            }
            return orderRecordTypeIdsByDevName.get(ORDER_RT_PRIMARY);
        }
        if (objectName == OBJ_SECONDARY_ORDER) {
            return orderRecordTypeIdsByDevName.get(ORDER_RT_SECONDARY);
        }
        if (objectName == OBJ_COUNTER_ORDER) {
            return orderRecordTypeIdsByDevName.get(ORDER_RT_COUNTER);
        }
        if (objectName == OBJ_UNDER_SS_SECONDARY_ORDER && distributorType == DIST_TYPE_SUPER_STOCKIEST) {
            return orderRecordTypeIdsByDevName.get(ORDER_RT_UNDER_SS_SECONDARY);
        }
        return null;
    }

    private static List<SearchResult> searchInvoices(DistributorContext ctx, SearchFilter filters, Date fromDate, Date toDate) {
        Id recordTypeId = resolveInvoiceRecordTypeId(ctx.distributorType, filters.invoiceRecordType);
        if (recordTypeId == null) {
            throw newAhe('Please select a valid Invoice Record Type.');
        }
        
        RecordType secondaryUnderSsRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Invoice__c' AND Name = 'Secondary Invoice Under SS' LIMIT 1];
    
        List<String> whereClauses = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();
    
        whereClauses.add('RecordTypeId = :rtId');
        binds.put('rtId', recordTypeId);
    
        if (ctx.distributorType == DIST_TYPE_UNDER_SS && recordTypeId == secondaryUnderSsRecordType.Id) {
            whereClauses.add('Under_SS__c = :scopeAccountId');
        } else {
            whereClauses.add('Distributor_Account__c = :scopeAccountId');
        }
        binds.put('scopeAccountId', ctx.accountId);
    
        if (filters.searchAccountId != null) {
            whereClauses.add('(Retailer_Account__c = :searchAccId OR Under_SS__c = :searchAccId)');
            binds.put('searchAccId', filters.searchAccountId);
        }
    
        if (fromDate != null) {
            whereClauses.add('Invoice_Date__c >= :fromDate');
            binds.put('fromDate', fromDate);
        }
        if (toDate != null) {
            whereClauses.add('Invoice_Date__c <= :toDate');
            binds.put('toDate', toDate);
        }
    
        if (String.isNotBlank(filters.status)) {
            if (filters.status == 'Delivered + Paid') {
                whereClauses.add('Status__c = :deliveredStatus AND Payment_Status__c = :paidStatus');
                binds.put('deliveredStatus', 'Delivered');
                binds.put('paidStatus', 'Paid');
            } else if (filters.status == 'Delivered + Not Paid') {
                whereClauses.add('Status__c = :deliveredStatus AND Payment_Status__c = :notPaidStatus');
                binds.put('deliveredStatus', 'Delivered');
                binds.put('notPaidStatus', 'Not Paid');
            } else {
                whereClauses.add('Status__c = :statusVal');
                binds.put('statusVal', filters.status);
            }
        }
    
        //Added by hari - Onclick Details
        String query =
            'SELECT Id, Name, Invoice_Date__c, Status__c, Payment_Status__c, ' +
            'Total_Quantity__c, Invoice_Amount__c, Collected_Amount__c, Total_Payable_Balance__c, ' +
            'Retailer_Account__r.Name, Distributor_Account__r.Name, Under_SS__r.Name, ' +
            'RecordType.Name, RecordType.DeveloperName ' +
            'FROM Invoice__c ' +
            'WHERE ' + String.join(whereClauses, ' AND ') +
            ' ORDER BY Invoice_Date__c DESC, Name DESC LIMIT 200';
    
        List<SObject> rawResults = Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
        List<Invoice__c> invoices = (List<Invoice__c>) rawResults;
    
        List<SearchResult> output = new List<SearchResult>();
        for (Invoice__c inv : invoices) {
            SearchResult sr = new SearchResult();
            sr.recordId = inv.Id;
            sr.recordName = inv.Name;
            sr.recordTypeLabel = inv.RecordType?.Name;
            sr.recordDate = inv.Invoice_Date__c;
            sr.status = inv.Status__c;
            sr.paymentStatus = inv.Payment_Status__c;
            sr.retailerName = inv.Retailer_Account__r?.Name;
            sr.distributorName = (inv.Under_SS__r != null)
                ? inv.Under_SS__r.Name
                : inv.Distributor_Account__r?.Name;
            //Added by hari - Onclick Details
            sr.totalQuantity = inv.Total_Quantity__c;
            sr.invoiceAmount = inv.Invoice_Amount__c;
            sr.totalOrderValue = inv.Invoice_Amount__c;
            sr.amountCollected = inv.Collected_Amount__c;
            sr.totalPayableBalance = inv.Total_Payable_Balance__c;
            if (inv.RecordType?.DeveloperName == INVOICE_RT_SECONDARY_UNDER_SS) {
                if (ctx.distributorType == DIST_TYPE_SUPER_STOCKIEST) {
                    sr.underSsName = inv.Under_SS__r?.Name;
                } else {
                    sr.superStockistName = inv.Distributor_Account__r?.Name;
                }
            }
            sr.isInvoice = 'true';
            output.add(sr);
        }
        return output;
    }
    
    private static List<SearchResult> searchCollections(DistributorContext ctx, SearchFilter filters, Date fromDate, Date toDate) {
        List<String> whereClauses = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();
    
        whereClauses.add('Distributor__c = :scopeAccountId');
        binds.put('scopeAccountId', String.valueOf(ctx.accountId).left(15));
    
        if (filters.searchAccountId != null) {
            whereClauses.add('Retailer__c = :searchAccIdText');
            binds.put('searchAccIdText', String.valueOf(filters.searchAccountId).left(15));
        }
    
        if (fromDate != null) {
            whereClauses.add('Payment_Date__c >= :fromDate');
            binds.put('fromDate', fromDate);
        }
        if (toDate != null) {
            whereClauses.add('Payment_Date__c <= :toDate');
            binds.put('toDate', toDate);
        }
    
        String query =
            'SELECT Id, Name, Retailer_Name__c, Payment_Date__c, Payment_Method__c, Amount_Collected__c, ' +
            'Invoice__c, Invoice__r.Name ' +
            'FROM Collection__c ' +
            'WHERE ' + String.join(whereClauses, ' AND ') +
            ' ORDER BY Payment_Date__c DESC, Name DESC LIMIT 200';
    
        System.debug('query:- ' + query);
    
        List<SObject> rawResults = Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
        List<Collection__c> collections = (List<Collection__c>) rawResults;
    
        List<SearchResult> output = new List<SearchResult>();
        for (Collection__c c : collections) {
            SearchResult sr = new SearchResult();
            sr.recordId = c.Id;
            sr.recordName = c.Name;
            sr.customerName = c.Retailer_Name__c;
            sr.recordDate = c.Payment_Date__c;
            sr.paymentMethod = c.Payment_Method__c;
            sr.amountCollected = c.Amount_Collected__c;
            sr.invoiceName = c.Invoice__r?.Name;
            sr.isInvoice = 'false';
            output.add(sr);
        }
        return output;
    }
    
    private static List<SearchResult> searchReturns(DistributorContext ctx, SearchFilter filters, Date fromDate, Date toDate) {
        List<String> whereClauses = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();
    
        if (ctx.distributorType == DIST_TYPE_UNDER_SS) {
            whereClauses.add('(Invoice__r.Under_SS__c = :scopeAccountId OR Order__r.AccountId__c = :scopeAccountId)');
        } else {
            whereClauses.add('(Invoice__r.Distributor_Account__c = :scopeAccountId OR Order__r.AccountId__c = :scopeAccountId)');
        }
        binds.put('scopeAccountId', ctx.accountId);
    
        if (filters.searchAccountId != null) {
            whereClauses.add('Customer__c = :searchAccIdText');
            binds.put('searchAccIdText', String.valueOf(filters.searchAccountId).left(15));
        }
    
        if (fromDate != null) {
            whereClauses.add('CreatedDate >= :fromDateTime');
            binds.put('fromDateTime', DateTime.newInstance(fromDate, Time.newInstance(0, 0, 0, 0)));
        }
        if (toDate != null) {
            whereClauses.add('CreatedDate <= :toDateTime');
            binds.put('toDateTime', DateTime.newInstance(toDate, Time.newInstance(23, 59, 59, 999)));
        }
    
        String query =
            'SELECT Id, Name, CreatedDate, Total_return_quantity__c, Total_return_Incl_tax__c, ' +
            'Customer_Name__c, Invoice__c, Invoice__r.Name, Order__c, Order__r.Name ' +
            'FROM Returns__c ' +
            'WHERE ' + String.join(whereClauses, ' AND ') +
            ' ORDER BY CreatedDate DESC, Name DESC LIMIT 200';
    
        List<SObject> rawResults = Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
        List<Returns__c> returns = (List<Returns__c>) rawResults;
    
        List<SearchResult> output = new List<SearchResult>();
        for (Returns__c r : returns) {
            SearchResult sr = new SearchResult();
            sr.recordId = r.Id;
            sr.recordName = r.Name;
            sr.recordDate = Date.valueOf(r.CreatedDate);
            sr.returnQuantity = r.Total_return_quantity__c;
            sr.returnAmount = r.Total_return_Incl_tax__c;
            sr.customerName = r.Customer_Name__c;
            sr.invoiceName = r.Invoice__r?.Name;
            sr.invoiceId = r.Invoice__c;
            sr.orderName = r.Order__r?.Name;
            sr.isInvoice = 'false';
            output.add(sr);
        }
        return output;
    }
    
    private static List<SearchResult> searchDeliveryPlans(DistributorContext ctx, SearchFilter filters, Date fromDate, Date toDate) {
        Set<Id> ownerIds = getOwnerIdsForAccount(ctx.accountId);
    
        List<String> whereClauses = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();
    
        whereClauses.add('OwnerId IN :ownerIds');
        binds.put('ownerIds', ownerIds);
    
        if (fromDate != null) {
            whereClauses.add('Date__c >= :fromDate');
            binds.put('fromDate', fromDate);
        }
        if (toDate != null) {
            whereClauses.add('Date__c <= :toDate');
            binds.put('toDate', toDate);
        }
    
        String query =
            'SELECT Id, Name, Date__c, Driver_Name__c, Driver_Number__c, Vehicle_Number__c ' +
            'FROM Delivery_Plan__c ' +
            'WHERE ' + String.join(whereClauses, ' AND ') +
            ' ORDER BY Date__c DESC, Name DESC LIMIT 200';
    
        List<SObject> rawResults = Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
        List<Delivery_Plan__c> plans = (List<Delivery_Plan__c>) rawResults;
    
        List<SearchResult> output = new List<SearchResult>();
        for (Delivery_Plan__c dp : plans) {
            SearchResult sr = new SearchResult();
            sr.recordId = dp.Id;
            sr.recordName = dp.Name;
            sr.recordDate = dp.Date__c;
            sr.driverName = dp.Driver_Name__c;
            sr.driverNumber = dp.Driver_Number__c;
            sr.vehicleNumber = dp.Vehicle_Number__c;
            sr.isInvoice = 'false';
            output.add(sr);
        }
        return output;
    }
    
    private static Set<Id> getOwnerIdsForAccount(Id accountId) {
        Set<Id> ownerIds = new Set<Id>();
        for (User u : [SELECT Id FROM User WHERE ContactId != null AND Contact.AccountId = :accountId LIMIT 1]) {
            ownerIds.add(u.Id);
        }
        return ownerIds;
    }

    private static AuraHandledException newAhe(String msg) {
        AuraHandledException ahe = new AuraHandledException(msg);
        ahe.setMessage(msg);
        return ahe;
    }

    private static AuraHandledException wrapException(String userMessage, Exception e) {
        System.debug(LoggingLevel.ERROR, userMessage + ' | ' + e.getMessage() + ' | ' + e.getStackTraceString());
        return newAhe(userMessage);
    }
}