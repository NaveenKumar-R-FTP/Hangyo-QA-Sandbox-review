/**
 * Controller for the archivedRecordsReport LWC - a standalone, report-style view
 * of records that have been archived out of Salesforce into the Azure archive.
 *
 * The report reads one object at a time (searchArchivedRecords). The older
 * multi-object entry points - getArchivedRecords / getArchivedRecordsPage - are
 * kept unchanged for any other caller, and still order a mixed result set
 * newest-first on whichever date the range was applied to.
 *
 * The report itself always filters on when the record was archived. The
 * dateBasis parameter on the older entry points is retained only for backwards
 * compatibility and for the rollup count job, which keys its tallies by basis.
 *
 * Line-item objects can additionally be searched by the parent record they are
 * linked to - Order Line Item by Order, Invoice Line Item by Invoice, Visit Task
 * by Visit. See PARENT_SEARCH and buildParentFilter below.
 *
 * Source of truth is the Azure archive, read through ArchiveReadService via the
 * AzureArchiveRetrieval_NC named credential (the read-side data source; writes use
 * the separate AzureDataArchive_NC, whose Entra credential the read path must not
 * borrow - see ArchiveReadService). Retrieval routes for Order Line Item, Invoice
 * Line Item, Attendance, Inventory Adjustment and Visit Task are defaulted inside
 * ArchiveReadService.DEFAULT_PATHS; Azure_Archive_Config__mdt.Read_Path__c
 * overrides them.
 *
 * Dated reads walk the range one day at a time from each day's recorded start
 * position (see planDays), so any range inside the rollup is read directly
 * rather than by scanning the table from the top.
 * When none of the selected objects can be read from the archive, the controller
 * degrades to the in-org Archival_Log__c audit index so the report still shows
 * what was archived, flagged clearly to the user rather than failing silently.
 *
 * Object and field access is enforced against the running user - archived rows are
 * real business data and are not exempt from CRUD/FLS.
 */
public with sharing class ArchivedRecordsController {

    private static final Integer MAX_PAGE_SIZE = 200;
    /**
     * Fixed at the maximum. The rows-per-page picker was removed: with the archive
     * paged by continuation token rather than by offset, a page is one callout
     * whatever its size, so a smaller page costs the same round trip for less data
     * and only adds a control that changes where the page boundaries fall.
     */
    private static final Integer DEFAULT_PAGE_SIZE = 200;
    private static final Integer MAX_SOQL_OFFSET = 2000;

    /**
     * Widest date range the archive can actually serve, in days.
     *
     * Only PartitionKey is indexed in Table Storage, so every date filter is a
     * scan; a range much wider than this exhausts ArchiveReadService's hop budget
     * and returns an unfinished search rather than an answer. The LWC enforces the
     * same limit in its date-range picker - this is the server-side backstop, so
     * the cap holds for any caller, not just the one with the dropdown.
     *
     * Measured as the gap between the dates rather than the inclusive day count,
     * so that the UI's own "Last 90 days" preset sits exactly on the limit instead
     * of one day past it. Only enforced when both bounds are supplied; an open
     * range is a different question and is bounded by the row cap instead.
     */
    @TestVisible
    private static final Integer MAX_RANGE_DAYS = 90;

    /** Synthetic column holding the object each row came from. */
    private static final String OBJECT_COLUMN = '_objectLabel';

    /**
     * Field names as the archive actually stores them, per object.
     *
     * This is not cosmetic. Order Line Items are archived with exact Salesforce
     * casing - Id, CreatedDate, Archived_Date__c - while Invoice Line Items are
     * archived entirely in lower case: id, createddate, archived_date__c. Both
     * verified against the live endpoints on 2026-09-21; the two Azure Functions
     * were evidently written independently.
     *
     * The report maps datatable columns by field name, and Table Storage is
     * case-sensitive about them, so using the wrong case produces the right row
     * count with every column blank and no error at all - the worst failure this
     * report has, and the one ArchiveReadContractTest exists to prevent.
     *
     * Objects not listed here are assumed to use exact Salesforce casing. That
     * includes Attendance, Inventory Adjustment and Visit Task - verify against
     * their live endpoints and add an entry here if any of them is lower case.
     */
    private class ArchiveNaming {
        private final String idField;
        private final String archivedDateField;
        private final String createdDateField;
        private final String nameField;
        /** True when every field is archived lower-cased, as Invoice Line Item is. */
        private final Boolean lowerCaseFields;

        private ArchiveNaming(String idField, String archivedDateField,
                              String createdDateField, String nameField,
                              Boolean lowerCaseFields) {
            this.idField = idField;
            this.archivedDateField = archivedDateField;
            this.createdDateField = createdDateField;
            this.nameField = nameField;
            this.lowerCaseFields = lowerCaseFields;
        }
    }

    private static final ArchiveNaming SALESFORCE_CASING =
        new ArchiveNaming('Id', 'Archived_Date__c', 'CreatedDate', 'Name', false);

    private static final Map<String, ArchiveNaming> ARCHIVE_NAMING =
        new Map<String, ArchiveNaming>{
            'Order_Line_Item__c'   => SALESFORCE_CASING,
            'Invoice_Line_Item__c' =>
                new ArchiveNaming('id', 'archived_date__c', 'createddate', 'name', true)
        };

    /**
     * Naming for one object: the verified entry in ARCHIVE_NAMING when there is
     * one, otherwise whatever detectArchiveKeys learned from the live archive,
     * otherwise exact Salesforce casing.
     */
    private static ArchiveNaming namingFor(String objectApiName) {
        ArchiveNaming naming = ARCHIVE_NAMING.get(objectApiName);
        if (naming != null) {
            return naming;
        }
        Map<String, String> keys = cachedArchiveKeys(objectApiName);
        if (keys == null || keys.isEmpty()) {
            return SALESFORCE_CASING;
        }
        // Apex == on strings ignores case, so equals() is the only honest test here.
        Boolean lower =
            'archived_date__c'.equals(keys.get('archived_date__c'))
            || 'id'.equals(keys.get('id'));
        return new ArchiveNaming(
            detectedKey(keys, 'Id', lower),
            detectedKey(keys, 'Archived_Date__c', lower),
            detectedKey(keys, 'CreatedDate', lower),
            detectedKey(keys, 'Name', lower),
            lower);
    }

    private static String detectedKey(Map<String, String> keys, String apiName, Boolean lower) {
        String lowerName = apiName.toLowerCase();
        // Blank means "probed, never seen" - fall back to the convention.
        if (String.isNotBlank(keys.get(lowerName))) {
            return keys.get(lowerName);
        }
        return lower ? lowerName : apiName;
    }

    /**
     * The name one field is stored under in this object's archive. Verified
     * objects keep their documented behaviour; others use the detected key, then
     * the detected casing convention.
     */
    private static String archiveNameFor(String objectApiName, String apiName) {
        Map<String, String> keys = cachedArchiveKeys(objectApiName);
        // Blank means "probed, never seen" - fall back to the convention.
        if (keys != null && String.isNotBlank(keys.get(apiName.toLowerCase()))) {
            return keys.get(apiName.toLowerCase());
        }
        return namingFor(objectApiName).lowerCaseFields ? apiName.toLowerCase() : apiName;
    }

    // ---------------------------------------------------------------- casing detection

    /**
     * Archive field names learned from live rows, per object: lower-cased name to
     * the name as actually stored. Only for objects NOT in ARCHIVE_NAMING - Order
     * Line Item and Invoice Line Item are verified and never probed.
     *
     * Why this exists: Attendance, Inventory Adjustment and Visit Task were
     * archived by Azure Functions whose casing has not been verified, and the
     * wrong casing fails silently - the date filter names a property no entity
     * has, so every range scans the whole table and returns nothing. Learning the
     * casing from the archive itself removes that guess.
     */
    private static Map<String, Map<String, String>> archiveKeys = new Map<String, Map<String, String>>();

    /** Rows sampled by the casing probe. More rows, fewer fields that happen to be null. */
    private static final Integer ARCHIVE_PROBE_ROWS = 20;
    /** How long a detected casing is kept in the org cache, in seconds. */
    private static final Integer ARCHIVE_KEYS_TTL_SECONDS = 86400;

    /**
     * Detected keys from this transaction or the org cache, without any callout.
     * Null when nothing is known. Also safe for ArchiveCountQueueable to reach
     * through archiveDateField, since it never calls out.
     */
    private static Map<String, String> cachedArchiveKeys(String objectApiName) {
        if (String.isBlank(objectApiName) || ARCHIVE_NAMING.containsKey(objectApiName)) {
            return null;
        }
        if (archiveKeys.containsKey(objectApiName)) {
            return archiveKeys.get(objectApiName);
        }
        Map<String, String> keys = null;
        try {
            keys = (Map<String, String>) Cache.Org.get(archiveKeysCacheKey(objectApiName));
        } catch (Exception e) {
            // No org cache partition, or none allocated: detect per transaction.
            keys = null;
        }
        archiveKeys.put(objectApiName, keys);
        return keys;
    }

    private static String archiveKeysCacheKey(String objectApiName) {
        return 'ArchiveKeys' + objectApiName.replaceAll('[^A-Za-z0-9]', '');
    }

    /**
     * Learns how this object's archive cases its fields, by reading a few rows
     * with both casings of every field the read will use selected, and keeping
     * whichever casing actually carries a value. Works whether Table Storage
     * omits a projected property that does not exist or returns it as null.
     *
     * One small, unfiltered read - the first rows in the table, so no scan - and
     * only for fields not already known. A failed probe is logged and ignored: the
     * read then proceeds on the detected casing convention, as before.
     *
     * Fields are probed incrementally, never skipped because SOMETHING is known.
     * It used to stop as soon as any keys were cached - and the count job caches
     * four (Id and the dates) first, so the report's own columns were never
     * learned and fell back to a guessed casing, which on Inventory Adjustment
     * left Inventory_Name__c blank. A field probed but absent from every sampled
     * row is remembered with a blank value, so it is not probed again.
     */
    private static void detectArchiveKeys(
        String objectApiName,
        Azure_Archive_Config__mdt cfg,
        List<String> apiNames
    ) {
        if (ARCHIVE_NAMING.containsKey(objectApiName)) {
            return;
        }
        Map<String, String> known = cachedArchiveKeys(objectApiName);

        List<String> selectFields = new List<String>();
        List<String> probedLowerNames = new List<String>();
        Set<String> seen = new Set<String>();
        for (String apiName : apiNames) {
            if (String.isBlank(apiName)) {
                continue;
            }
            String lowerName = apiName.toLowerCase();
            if ((known != null && known.containsKey(lowerName)) || probedLowerNames.contains(lowerName)) {
                continue;
            }
            probedLowerNames.add(lowerName);
            for (String variant : new List<String>{ apiName, lowerName }) {
                if (seen.add(variant)) {
                    selectFields.add(variant);
                }
            }
        }
        if (selectFields.isEmpty()) {
            return;
        }

        Map<String, String> keys = known == null
            ? new Map<String, String>()
            : new Map<String, String>(known);
        Boolean probed = false;
        try {
            ArchiveReadService.PageResult result = ArchiveReadService.fetch(buildQuery(
                objectApiName, cfg, null, null, selectFields, null, ARCHIVE_PROBE_ROWS));
            if (result.isSuccess && result.records != null) {
                probed = true;
                for (Map<String, Object> source : result.records) {
                    for (String key : source.keySet()) {
                        String lowerKey = key.toLowerCase();
                        if (source.get(key) != null && String.isBlank(keys.get(lowerKey))) {
                            keys.put(lowerKey, key);
                        }
                    }
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'Archive casing probe failed for ' + objectApiName + ': ' + e.getMessage());
        }
        if (!probed) {
            return;
        }
        // Asked about but never seen with a value: remember that, so the next read
        // does not probe for it again.
        for (String lowerName : probedLowerNames) {
            if (!keys.containsKey(lowerName)) {
                keys.put(lowerName, '');
            }
        }

        archiveKeys.put(objectApiName, keys);
        // Logged so the casing can be made permanent in ARCHIVE_NAMING once seen.
        System.debug(LoggingLevel.INFO,
            'Archive field names for ' + objectApiName + ': ' + keys.values());
        try {
            Cache.Org.put(archiveKeysCacheKey(objectApiName), keys, ARCHIVE_KEYS_TTL_SECONDS);
        } catch (Exception e) {
            System.debug(LoggingLevel.FINE, 'Org cache unavailable: ' + e.getMessage());
        }
    }

    /**
     * Every Salesforce field a single-object read will touch, so the probe can
     * learn all of their archive names in one request.
     */
    private static void prepareArchiveNames(
        String objectApiName,
        Azure_Archive_Config__mdt cfg,
        ParentFilter filter
    ) {
        if (ARCHIVE_NAMING.containsKey(objectApiName)) {
            return;
        }
        List<String> apiNames = new List<String>{ 'Id', 'Archived_Date__c', 'CreatedDate', 'Name' };

        Map<String, Schema.SObjectField> fieldMap =
            Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap();
        Map<String, Schema.SObjectField> byLabel;
        for (String token : requestedFields(objectApiName, cfg)) {
            if (byLabel == null && !fieldMap.containsKey(token)) {
                byLabel = indexByLabel(fieldMap);
            }
            Schema.SObjectField field = fieldMap.get(token);
            if (field == null && byLabel != null) {
                field = byLabel.get(normaliseLabel(token));
            }
            if (field != null) {
                apiNames.add(field.getDescribe().getName());
            }
        }
        if (filter != null) {
            apiNames.addAll(filter.apiNames());
        }
        detectArchiveKeys(objectApiName, cfg, apiNames);
    }

    /**
     * Diagnostic, for Anonymous Apex: the first rows of one object's archive,
     * unprojected, exactly as the retrieval route returns them. Shows the real
     * field names, their casing and how dates are stored.
     *
     *   System.debug(JSON.serializePretty(
     *       ArchivedRecordsController.sampleArchiveRows('Visit_Task__c', 2)));
     */
    public static List<Map<String, Object>> sampleArchiveRows(String objectApiName, Integer rowCount) {
        List<String> objects = validateObjects(new List<String>{ objectApiName });
        Integer rows = (rowCount == null || rowCount < 1) ? 1 : Math.min(rowCount, 50);
        ArchiveReadService.PageResult result = ArchiveReadService.fetch(buildQuery(
            objects[0], configFor(objects[0]), null, null, null, null, rows));
        if (!result.isSuccess) {
            throw new AuraHandledException(
                'Archive read failed for ' + objects[0] + ' (' + result.errorCode + '): '
                + result.errorMessage
                + (result.endpointUnavailable ? ' [no route / endpoint unavailable]' : ''));
        }
        return result.records == null ? new List<Map<String, Object>>() : result.records;
    }

    /**
     * Fallback report columns per object, used when Report_Columns__c on
     * Azure_Archive_Config__mdt is blank.
     *
     * Each entry is either a field API name or a field LABEL. API names are tried
     * first (describe resolves them case-insensitively, and the entry's own casing
     * is kept as the archive field name, exactly as before). Anything that is not
     * an API name is matched against the object's field labels and mapped to that
     * field's API name in the casing the archive uses. Labels are used where the
     * business asked for a field by label and its API name is not already known
     * here, so a column cannot silently vanish because of a guessed API name.
     *
     * An entry that resolves to nothing, or to a field the user cannot read, is
     * skipped - the same behaviour the report has always had.
     */
    private static final Map<String, List<String>> DEFAULT_COLUMNS = new Map<String, List<String>>{
        // Order shows Order_Name__c, not the Order__c Id. Product is the Products__c
        // Id as archived, turned into the product's name at read time - see
        // LOOKUP_NAME_COLUMNS.
        'Order_Line_Item__c' => new List<String>{
            'Products__c', 'Order_Name__c', 'Total_Amount__c', 'Ordered_Quantity__c', 'Crate',
            'Total_Amount_Incl_Tax__c', 'Product_Price__c'
        },
        // Lower case where the API name is known - verified against the live
        // endpoint on 2026-09-21. Label entries are lower-cased on resolution
        // because this archive stores every field that way (see ARCHIVE_NAMING).
        // Invoice and Product show the archived invoice_number__c and
        // product_name__c rather than the lookup Ids.
        'Invoice_Line_Item__c' => new List<String>{
            'invoice_number__c', 'quantity__c', 'TOD', 'total_discount__c', 'Discount 1', 'Discount 2',
            'price__c', 'product_name__c', 'total_amount__c', 'CGST Amount', 'CGST Percentage',
            'SGST Amount', 'SGST Percentage', 'IGST Amount', 'IGST Percentage',
            'Is Promotional', 'MRP', 'Per Pieces', 'product_brand__c', 'product_code__c',
            'SKU Discount %', 'total_amount_incl_tax__c', 'Quantity Scheme Applied',
            'Scheme Discount Amount'
        },
        'Inventory_Adjustment__c' => new List<String>{
            'Inventory_Name__c', 'Adjustment_Date__c', 'Product__c', 'Quantity__c', 'Type__c',
            'Primary Invoice Transaction', 'Secondary Invoice Transaction', 'Secondary Return',
            'OwnerId'
        },
        // Visit shows Visit_Name__c, not the Visit__c Id.
        'Visit_Task__c' => new List<String>{
            'Name', 'Retailer', 'Distributor', 'Visit_Name__c', 'Retailer\'s Address',
            'Visit_Type__c', 'User', 'Monthly Target', 'Type', 'Visitor Name', 'Order',
            'Status__c', 'Beat__c', 'Unproductive Reasons', 'Order Placed', 'Purpose of Visit',
            'Checked-In Location', 'Checked_In_Time__c', 'Checked-Out Location',
            'Checked_Out_Time__c', 'Check-In Duration', 'Start Call Location', 'Start Call Time',
            'End Call Location', 'End Call Time', 'Start Call Duration',
            'CreatedById', 'LastModifiedById'
        },
        'Attendance__c' => new List<String>{
            'Name', 'Status__c', 'Work', 'Location', 'First Activity Time', 'Status Updated Time',
            'User__c', 'Date_of_attendance__c', 'Attendance Applied On', 'Total_Distance__c',
            'EOD Date Time', 'Leave For', 'Leave_Type__c', 'Reason for Leave', 'Leave Period',
            'Leave Record', 'CreatedById', 'LastModifiedById'
        }
    };

    /**
     * Column headings that differ from the field's own label, per object, keyed
     * by the lower-cased column entry. The name fields above stand in for the
     * lookups the business asked for, so they keep the lookup's heading - "Order",
     * not "Order Name". An entry listed here is also shown when the org has no
     * such field (text column), because the archive can carry fields the org
     * schema has since dropped.
     */
    private static final Map<String, Map<String, String>> COLUMN_LABELS =
        new Map<String, Map<String, String>>{
            'Order_Line_Item__c' => new Map<String, String>{
                'products__c'   => 'Product',
                'order_name__c' => 'Order'
            },
            'Invoice_Line_Item__c' => new Map<String, String>{
                'invoice_number__c' => 'Invoice',
                'product_name__c'   => 'Product'
            },
            'Visit_Task__c' => new Map<String, String>{
                'visit_name__c' => 'Visit'
            },
            'Inventory_Adjustment__c' => new Map<String, String>{
                'inventory_name__c' => 'Inventory'
            }
        };

    /**
     * Lookup columns whose archived Id is shown as the related record's name,
     * looked up in Salesforce for the rows on the page - one query per related
     * object (and display field) for the whole page, never per row.
     *
     * Entries are lower-cased and matched against a column's field name OR its
     * heading, because several of these columns are resolved from a label and
     * their API names are the org's own.
     *
     * User lookups need no entry: any column holding User Ids - User, Created By,
     * Last Modified By, Owner - is shown as the user's name on every object (see
     * presentRows). Owner ID is listed below as well, so that a record owned by a
     * queue shows the queue's name too.
     */
    private static final Map<String, Set<String>> LOOKUP_NAME_COLUMNS =
        new Map<String, Set<String>>{
            'Order_Line_Item__c' => new Set<String>{ 'products__c' },
            // Order__c and Beat__c point at the custom Order__c and Beat__c objects;
            // listed by field name and by heading, as the archive's casing varies.
            'Visit_Task__c' => new Set<String>{
                'retailer', 'distributor', 'order__c', 'order', 'beat__c', 'beat'
            },
            // Primary Invoice Transaction is not listed: InventoryAdjustmentWrapper
            // names it, alongside Inventory (see mapInventoryAdjustmentNames).
            'Inventory_Adjustment__c' => new Set<String>{
                'product__c', 'secondary invoice transaction', 'secondary return', 'ownerid'
            }
        };

    /**
     * For lookup columns that should show a field other than the related
     * record's Name - keyed like LOOKUP_NAME_COLUMNS, valued with the field on
     * the related record. Used only when the related object has that field and
     * the user can read it; otherwise the related record's Name is shown.
     *
     * Empty: the invoice lookups on Inventory Adjustment (Primary and Secondary
     * Invoice Transaction) show the Invoice's standard Name field, as asked.
     */
    @TestVisible
    private static final Map<String, Map<String, String>> LOOKUP_DISPLAY_FIELDS =
        new Map<String, Map<String, String>>();

    /**
     * Columns whose archive field name is known exactly, per object, keyed by the
     * lower-cased column entry. Used as-is - never re-cased by detection or by the
     * object's casing convention - because the archive matches names exactly and
     * a guessed casing returns the column blank.
     */
    private static final Map<String, Map<String, String>> EXACT_ARCHIVE_FIELDS =
        new Map<String, Map<String, String>>{
            'Inventory_Adjustment__c' => new Map<String, String>{
                'inventory_name__c' => 'Inventory_Name__c'
            }
        };

    /** Leading hh:mm of an archived Time value such as '09:28:04.000Z'. */
    private static final Pattern TIME_VALUE = Pattern.compile('^(\\d{1,2}):(\\d{2})');

    /** Columns shown when the report falls back to the Archival_Log__c index. */
    private static final List<String> LOG_COLUMNS = new List<String>{
        'Archived_Record_Id__c', 'Parent_Record_Name__c', 'Parent_Object__c',
        'Original_CreatedDate__c', 'Soft_Archived_Date__c', 'Hard_Deleted_Date__c',
        'Status__c', 'Archived_Location__c'
    };

    // ---------------------------------------------------------------- parent search

    /**
     * Which objects can be searched by the parent record they belong to, and how.
     *
     * textFields are the fields on the CHILD that carry the parent's name or
     * number - Order_Name__c, Invoice_Number__c, Visit_Name__c - and are what a
     * typed name is matched against. They are read from the archived row itself,
     * so the search works even when the parent has been archived out of
     * Salesforce too. Listed as Salesforce API names; the archive's own casing is
     * applied on use (Invoice Line Item's archive is lower case).
     *
     * lookupField (an API name or label) is the lookup holding the parent's Id,
     * used only when the search term is itself a record Id.
     */
    private class ParentSearchConfig {
        private final String label;
        private final String lookupField;
        private final List<String> textFields;

        private ParentSearchConfig(String label, String lookupField, List<String> textFields) {
            this.label = label;
            this.lookupField = lookupField;
            this.textFields = textFields;
        }
    }

    private static final Map<String, ParentSearchConfig> PARENT_SEARCH =
        new Map<String, ParentSearchConfig>{
            'Order_Line_Item__c'   => new ParentSearchConfig(
                'Order', 'Order__c', new List<String>{ 'Order_Name__c' }),
            'Invoice_Line_Item__c' => new ParentSearchConfig(
                'Invoice', 'Invoice', new List<String>{ 'Invoice_Number__c' }),
            'Visit_Task__c'        => new ParentSearchConfig(
                'Visit', 'Visit__c', new List<String>{ 'Visit_Name__c' })
        };

    private static final Integer MIN_PARENT_SEARCH_LENGTH = 2;
    private static final Integer MAX_PARENT_SEARCH_LENGTH = 255;

    /**
     * Budget for one token-paged page.
     *
     * Dates are not indexed and neither is the parent - only PartitionKey is - so
     * a read that has not filled its page keeps reading from wherever the archive
     * stopped. One page stops at whichever comes first: a full page, this many
     * archive reads, the callout headroom, or the time budget. The time budget
     * is 90 seconds - raised from 45 so a page searches roughly twice as far - and
     * no further: no new read starts after it, and the 30 seconds left under the
     * 120-second cumulative callout limit cover the read already in flight, which
     * can legitimately take that long. Past 120 seconds Salesforce throws an
     * uncatchable limit exception and the whole page is lost.
     *
     * SCAN_MAX_FETCHES was raised from 8 to 15 alongside it, so the read count
     * does not stop a page long before the time budget would. One archive read
     * can follow up to ArchiveReadService.MAX_PAGES continuation hops, so 15
     * reads could ask for more callouts than a transaction has; the callout
     * headroom check below stops the page first, keeping 10 in reserve. Stopping
     * early is never a lost result: the page carries a continuation and the user
     * can search further from exactly where this one stopped.
     *
     * An unfiltered read that fills its page on the first read - the normal case -
     * makes exactly one read, as it always did.
     */
    private static final Integer SCAN_MAX_FETCHES = 15;
    private static final Integer SCAN_CALLOUT_HEADROOM = 10;
    private static final Long SCAN_TIME_BUDGET_MS = 90000;

    /**
     * Share of the transaction's CPU limit a page may use before it starts no
     * further read. Added with the higher fetch cap: a parent search that matches
     * nothing parses up to MAX_ROWS rows per read, and fifteen such reads ran past
     * the 10-second synchronous CPU limit - an uncatchable LimitException, so the
     * user got an error instead of a "search further" page (measured 2026-10-05).
     * Half, not two thirds, because one read can itself cost several seconds of
     * CPU and has to finish inside what is left.
     */
    private static final Integer SCAN_CPU_SHARE_PERCENT = 50;

    /**
     * A parent search. Built from Salesforce API names; bound to the archive's
     * field names (bindParentFilter) once the archive's casing is known.
     */
    private class ParentFilter {
        private final String label;
        private final String term;
        private final String termLower;
        /** Lookup API name, set only when the term is a record Id. */
        private String lookupApiName;
        private final List<String> textApiNames = new List<String>();
        /** Parent record Id from the term, in 18-character form. */
        private final Set<String> recordIds = new Set<String>();
        /** Archive field names, filled by bindParentFilter. */
        private final List<String> idFields = new List<String>();
        private final List<String> textFields = new List<String>();

        private ParentFilter(String label, String term) {
            this.label = label;
            this.term = term;
            this.termLower = term.toLowerCase();
        }

        public List<String> apiNames() {
            List<String> names = new List<String>(textApiNames);
            if (lookupApiName != null) {
                names.add(lookupApiName);
            }
            return names;
        }

        /**
         * A record Id matches its lookup exactly. A name or number matches when
         * the archived Order Name / Invoice Number / Visit Name contains it,
         * ignoring case - so "ORD-0012" finds "ORD-00123" as a search box should.
         */
        public Boolean matches(Map<String, Object> source) {
            for (String fieldName : idFields) {
                Object value = source.get(fieldName);
                if (value != null
                    && recordIds.contains(ArchivedRecordsController.toId18(String.valueOf(value)))) {
                    return true;
                }
            }
            for (String fieldName : textFields) {
                Object value = source.get(fieldName);
                if (value != null && String.valueOf(value).toLowerCase().contains(termLower)) {
                    return true;
                }
            }
            return false;
        }
    }

    /** A column token resolved to a real field and the name the archive uses for it. */
    private class ResolvedField {
        private final String archiveName;
        private final Schema.DescribeFieldResult describe;

        private ResolvedField(String archiveName, Schema.DescribeFieldResult describe) {
            this.archiveName = archiveName;
            this.describe = describe;
        }
    }

    // ---------------------------------------------------------------- wrappers

    public class ObjectOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public Integer retentionDays;
        /**
         * Label of the parent this object can be searched by ('Order', 'Invoice',
         * 'Visit'), or null when the object has no parent search.
         */
        @AuraEnabled public String parentSearchLabel;

        public ObjectOption(String label, String value, Integer retentionDays) {
            this.label = label;
            this.value = value;
            this.retentionDays = retentionDays;
        }
    }

    public class ReportColumn {
        @AuraEnabled public String fieldName;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
        @AuraEnabled public Boolean sortable = true;
        /**
         * Server-side only (not sent to the LWC): the column is a Time field, so
         * presentRows rewrites its archived '09:28:04.000Z' as '9:28 AM'.
         */
        public Boolean isTime = false;
    }

    public class ReportPage {
        @AuraEnabled public List<ReportColumn> columns = new List<ReportColumn>();
        @AuraEnabled public List<Map<String, Object>> rows = new List<Map<String, Object>>();
        @AuraEnabled public Integer totalCount = 0;
        @AuraEnabled public Integer pageNumber = 1;
        @AuraEnabled public Integer pageSize = DEFAULT_PAGE_SIZE;
        @AuraEnabled public Integer totalPages = 0;
        /** True when rows came from Archival_Log__c instead of the Azure archive. */
        @AuraEnabled public Boolean degraded = false;
        @AuraEnabled public String degradedReason;
        @AuraEnabled public List<String> objectApiNames = new List<String>();
        /**
         * True when the archive held more matching rows than one transaction will
         * pull, so totalCount is a floor rather than an exact count.
         */
        @AuraEnabled public Boolean isCapped = false;
        @AuraEnabled public Integer rowCap = ArchiveReadService.MAX_ROWS;
        /**
         * True when the archive ran out of scan budget before reaching the end of
         * the table. An empty page in this state means "not found yet", never
         * "not there" - the UI must not show its empty state.
         */
        @AuraEnabled public Boolean scanIncomplete = false;
        /** Which date the range was applied to: 'ARCHIVED' or 'CREATED'. */
        @AuraEnabled public String dateBasis = 'ARCHIVED';
        /**
         * Selected objects the archive has no published read route for. Their rows
         * are absent from this page entirely - they are not silently counted.
         */
        @AuraEnabled public List<String> unavailableObjects = new List<String>();
        /**
         * True when more than one object is selected and the column set had to be
         * narrowed to the fields those objects share.
         */
        @AuraEnabled public Boolean columnsNarrowed = false;
        /**
         * Resume point for the following page, opaque to the client - hand it
         * straight back on the next call. Null when this is the last page.
         */
        @AuraEnabled public String nextContinuation;
        @AuraEnabled public Boolean hasMore = false;
        /**
         * True when this page came from the archive by continuation token, in
         * which case totalCount counts only the rows on THIS page and the real
         * total has to come from getArchivedRecordCount. False on the windowed
         * and log-fallback paths, where totalCount is the whole result set.
         */
        @AuraEnabled public Boolean tokenPaged = false;
        /**
         * The most recent archive run we have any record of, as ISO yyyy-MM-dd,
         * or null when nothing is known.
         *
         * Only populated when a read comes back empty, and only then because an
         * empty result from this archive is genuinely hard to interpret: dates are
         * not indexed, so "nothing found" and "did not finish looking" arrive
         * looking identical, and the honest next question is always "was anything
         * archived around then at all?". Answering it costs one SOQL aggregate.
         */
        @AuraEnabled public String lastArchiveActivity;
    }

    // ---------------------------------------------------------------- options

    /**
     * In-scope objects, driven by Azure_Archive_Config__mdt so the picker follows
     * configuration rather than a hardcoded list. Objects the running user cannot
     * read, or that do not exist in this org, are omitted.
     */
    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getObjectOptions() {
        List<ObjectOption> options = new List<ObjectOption>();
        Set<String> offered = new Set<String>();

        for (Azure_Archive_Config__mdt cfg : [
            SELECT MasterLabel, DeveloperName, Object_API_Name__c, Retention_Days__c, Order__c
            FROM Azure_Archive_Config__mdt
            ORDER BY Order__c NULLS LAST, MasterLabel
        ]) {
            String apiName = resolveObjectApiName(cfg);
            if (String.isBlank(apiName) || offered.contains(apiName.toLowerCase())) {
                continue;
            }
            ObjectOption option = objectOption(
                apiName,
                cfg.Retention_Days__c == null ? null : Integer.valueOf(cfg.Retention_Days__c));
            if (option != null) {
                options.add(option);
                offered.add(apiName.toLowerCase());
            }
        }

        // An object with a published retrieval route is readable whether or not
        // an archival config row exists for it - Attendance, notably, has none -
        // so it is offered anyway, after the configured objects.
        List<String> routed = new List<String>(ArchiveReadService.publishedObjects());
        routed.sort();
        for (String apiName : routed) {
            if (offered.contains(apiName.toLowerCase())) {
                continue;
            }
            ObjectOption option = objectOption(apiName, null);
            if (option != null) {
                options.add(option);
                offered.add(apiName.toLowerCase());
            }
        }

        return options;
    }

    /** One picker entry, or null when the object is missing or the user cannot read it. */
    private static ObjectOption objectOption(String apiName, Integer retentionDays) {
        Schema.SObjectType sobjType = globalDescribe().get(apiName);
        if (sobjType == null || !sobjType.getDescribe().isAccessible()) {
            return null;
        }
        ObjectOption option = new ObjectOption(
            sobjType.getDescribe().getLabelPlural(), apiName, retentionDays);
        ParentSearchConfig search = PARENT_SEARCH.get(apiName);
        option.parentSearchLabel = search == null ? null : search.label;
        return option;
    }

    private static Map<String, Schema.SObjectType> globalDescribeCache;

    private static Map<String, Schema.SObjectType> globalDescribe() {
        if (globalDescribeCache == null) {
            globalDescribeCache = Schema.getGlobalDescribe();
        }
        return globalDescribeCache;
    }

    /**
     * The object a config row is for.
     *
     * Object_API_Name__c, as written, when it names a real object - unchanged from
     * before. Otherwise the first of these that does: Object_API_Name__c + '__c'
     * (a value entered without its suffix), DeveloperName + '__c', MasterLabel
     * + '__c' with spaces as underscores (several rows carry only a label, e.g.
     * 'Visit_Task' or 'Visit Task').
     */
    private static String resolveObjectApiName(Azure_Archive_Config__mdt cfg) {
        Map<String, Schema.SObjectType> gd = globalDescribe();
        if (String.isNotBlank(cfg.Object_API_Name__c) && gd.containsKey(cfg.Object_API_Name__c.trim())) {
            return cfg.Object_API_Name__c.trim();
        }
        for (String candidate : new List<String>{
            cfg.Object_API_Name__c, cfg.DeveloperName, cfg.MasterLabel
        }) {
            if (String.isBlank(candidate)) {
                continue;
            }
            String guess = candidate.trim().replaceAll('[^A-Za-z0-9_]+', '_');
            if (!guess.endsWithIgnoreCase('__c')) {
                guess += '__c';
            }
            if (gd.containsKey(guess)) {
                // Describe's own casing, so it matches the maps keyed by API name.
                return gd.get(guess).getDescribe().getName();
            }
        }
        return null;
    }

    // ---------------------------------------------------------------- main read

    /**
     * One page of archived records.
     *
     * Overload kept for callers that do not page by token - notably the tests and
     * the log fallback, where offset paging is available and works.
     */
    @AuraEnabled
    public static ReportPage getArchivedRecords(
        List<String> objectApiNames,
        String fromDate,
        String toDate,
        Integer pageSize,
        Integer pageNumber,
        String dateBasis
    ) {
        return getArchivedRecordsPage(
            objectApiNames, fromDate, toDate, pageSize, pageNumber, dateBasis, null);
    }

    /**
     * One page of archived records, resuming from a continuation token.
     *
     * Pass continuation = null for the first page, then hand back the
     * nextContinuation from the previous page to advance. The archive has no
     * offset paging - $skip returns 501 - so this is the only way to reach page
     * two of an archive read, and it is forward-only: there is no token that goes
     * backwards, which is why the client keeps the tokens it has already been
     * given rather than asking for a page by number.
     */
    @AuraEnabled
    public static ReportPage getArchivedRecordsPage(
        List<String> objectApiNames,
        String fromDate,
        String toDate,
        Integer pageSize,
        Integer pageNumber,
        String dateBasis,
        String continuation
    ) {
        return readPage(
            validateObjects(objectApiNames), fromDate, toDate, pageSize, pageNumber,
            dateBasis, continuation, null);
    }

    /**
     * One page of ONE archived object, filtered on archived date, optionally
     * narrowed to the children of one parent record. This is what the report calls.
     *
     * Deliberately a separate method rather than a change to getArchivedRecordsPage:
     * AuraEnabled methods cannot be overloaded, and changing that signature would
     * break every existing caller. Everything below the parameter handling is the
     * same read path.
     *
     * @param objectApiName the single object to read.
     * @param parentSearch  optional. The parent's name, number or record Id - an
     *                      Order for Order Line Item, an Invoice for Invoice Line
     *                      Item, a Visit for Visit Task. Blank means no parent filter.
     */
    @AuraEnabled
    public static ReportPage searchArchivedRecords(
        String objectApiName,
        String fromDate,
        String toDate,
        Integer pageSize,
        Integer pageNumber,
        String continuation,
        String parentSearch
    ) {
        if (String.isBlank(objectApiName)) {
            throw new AuraHandledException('Select an object before running the report.');
        }
        List<String> objects = validateObjects(new List<String>{ objectApiName });

        ParentFilter filter = String.isBlank(parentSearch)
            ? null
            : buildParentFilter(objects[0], parentSearch);

        return readPage(
            objects, fromDate, toDate, pageSize, pageNumber, BASIS_ARCHIVED, continuation, filter);
    }

    /** The shared body of every page read. filter is null for an unfiltered read. */
    private static ReportPage readPage(
        List<String> objects,
        String fromDate,
        String toDate,
        Integer pageSize,
        Integer pageNumber,
        String dateBasis,
        String continuation,
        ParentFilter filter
    ) {
        Date parsedFrom = parseDate(fromDate, 'From date');
        Date parsedTo = parseDate(toDate, 'To date');
        if (parsedFrom != null && parsedTo != null) {
            if (parsedFrom > parsedTo) {
                throw new AuraHandledException('From date must be on or before To date.');
            }
            Integer span = parsedFrom.daysBetween(parsedTo);
            if (span > MAX_RANGE_DAYS) {
                // Same wording as the report's own check, which normally stops
                // the request first; this is the backstop for any other caller.
                throw new AuraHandledException(
                    'Only a ' + MAX_RANGE_DAYS + '-day range can be selected. The dates '
                    + 'chosen span ' + span + ' days; move the From or To date closer together.'
                );
            }
        }

        Integer resolvedPageSize = normalisePageSize(pageSize);
        Integer resolvedPageNumber = (pageNumber == null || pageNumber < 1) ? 1 : pageNumber;
        Integer globalOffset = (resolvedPageNumber - 1) * resolvedPageSize;

        Map<String, Azure_Archive_Config__mdt> configs = loadConfigs(objects);

        ReportPage page = readFromArchive(
            objects, configs, parsedFrom, parsedTo, resolvedPageSize, globalOffset, dateBasis,
            continuation, filter);

        if (page == null) {
            if (filter != null) {
                // The log index has no lookup to the parent, so there is nothing
                // honest to degrade to - say so rather than showing unfiltered rows.
                throw new AuraHandledException(
                    'Searching by ' + filter.label + ' needs the Azure archive retrieval route for '
                    + describeLabel(objects[0]) + ', which is not available. Clear the '
                    + filter.label + ' search to see the Archival Log index instead.');
            }
            // No selected object has a read route - fall back to the in-org index.
            page = readFromArchivalLog(
                objects, parsedFrom, parsedTo, resolvedPageSize, globalOffset, dateBasis);
        }

        // Archived lookup Ids shown as names, Time values as 12-hour clock times.
        if (!page.degraded && objects.size() == 1) {
            presentRows(objects[0], page);
        }

        // An empty or unfinished read needs context the archive cannot give it.
        if (page.rows.isEmpty() || page.scanIncomplete) {
            page.lastArchiveActivity = lastArchiveActivity(objects);
        }

        page.dateBasis = BASIS_CREATED.equalsIgnoreCase(dateBasis) ? BASIS_CREATED : BASIS_ARCHIVED;
        page.objectApiNames = objects;
        page.pageSize = resolvedPageSize;
        page.pageNumber = resolvedPageNumber;
        // A token-paged read knows only its own rows, so there is no total to
        // divide into pages. The count arrives separately, from
        // getArchivedRecordCount, and the client derives the page span from that.
        page.totalPages = page.tokenPaged ? 0 : calcTotalPages(page.totalCount, resolvedPageSize);
        return page;
    }

    // ---------------------------------------------------------------- count

    /**
     * How far a count has got, and whether it is finished.
     *
     * total is only an answer when isComplete is true. While a count is running it
     * is a floor that grows, and the UI must not present it as a total.
     */
    public class ArchiveCount {
        @AuraEnabled public Integer total = 0;
        @AuraEnabled public Boolean isComplete = false;
        @AuraEnabled public Boolean isFailed = false;
        /** True while the one-off rollup walk is still running. */
        @AuraEnabled public Boolean isBuilding = false;
        @AuraEnabled public String errorMessage;
        /** True when the count came from Archival_Log__c rather than the archive. */
        @AuraEnabled public Boolean degraded = false;
        @AuraEnabled public List<String> unavailableObjects = new List<String>();
        /** Callouts spent so far, across every chained job. Diagnostic. */
        @AuraEnabled public Integer calloutsUsed = 0;
        /** When a completed count was produced, so the UI can say how fresh it is. */
        @AuraEnabled public Datetime completedAt;
    }

    /**
     * How long a completed count stays usable before it is recounted.
     *
     * Archived rows are only ever added, never edited, so a stale count is wrong
     * only by however much was archived since - and archival runs are occasional,
     * not continuous. A day is long enough that the same question asked repeatedly
     * costs one count, and short enough that a new archival run shows up.
     */
    private static final Integer COUNT_FRESHNESS_HOURS = 24;

    /**
     * A count whose progress record has not been written to in this long is
     * presumed dead and restarted. Guards against a chain broken by an org-level
     * failure that left no Failed status behind - otherwise such a count would
     * stay Running for ever and the report would poll it indefinitely.
     *
     * Measured from the LAST write, not from the start. Measuring from the start
     * was a real bug: counting the 9.65M archived Order Line Items takes about
     * thirty-five minutes, so a thirty-minute limit declared a perfectly healthy
     * count dead and restarted it from zero - and since the restart also took
     * thirty-five minutes, a watched count could never have finished. Each job in
     * the chain writes its running total, so the record is touched every twenty
     * seconds or so while the count is alive; several minutes of silence really
     * does mean the chain is broken.
     */
    private static final Integer COUNT_STALL_MINUTES = 5;

    /**
     * The total matching the current filters - one SOQL aggregate, no callouts.
     *
     * This is the whole point of the rollup. Azure Table Storage has no count or
     * aggregate operation of any kind, so asking the archive "how many?" means
     * reading every matching entity: 9.65M rows, ~9,650 callouts and half an hour,
     * measured 2026-09-21. That is not a question that can be asked per page view.
     *
     * So it is asked once. ArchiveCountQueueable walks an object's whole archive
     * table and tallies the rows by day into Archive_Day_Count__c, and every
     * question after that is a SUM over the days a date range covers. Any range,
     * any object, immediately.
     *
     * When no rollup exists yet the walk is started and isBuilding comes back
     * true, with whatever the walk has counted so far as a floor. Pass
     * forceRecount = true - what Refresh does - to rebuild after an archival run.
     *
     * The rollup is tallied per day, not per parent, so it cannot answer a
     * parent-filtered question; the report does not ask it one.
     */
    @AuraEnabled
    public static ArchiveCount getArchivedRecordCount(
        List<String> objectApiNames,
        String fromDate,
        String toDate,
        String dateBasis,
        Boolean forceRecount
    ) {
        List<String> objects = validateObjects(objectApiNames);

        Date parsedFrom = parseDate(fromDate, 'From date');
        Date parsedTo = parseDate(toDate, 'To date');
        if (parsedFrom != null && parsedTo != null && parsedFrom > parsedTo) {
            throw new AuraHandledException('From date must be on or before To date.');
        }

        String basis = BASIS_CREATED.equalsIgnoreCase(dateBasis) ? BASIS_CREATED : BASIS_ARCHIVED;
        Map<String, Azure_Archive_Config__mdt> configs = loadConfigs(objects);
        List<String> routable = routableObjects(objects, configs);

        ArchiveCount outcome = new ArchiveCount();

        if (routable.isEmpty()) {
            // No archive route anywhere, so the page itself is showing the in-org
            // index. Count that instead - a SOQL aggregate, exact and immediate.
            // It counts log rows rather than archived records, and logging has
            // been off in the archival batch for most of the archive's life, so
            // degraded marks it as the different number it is.
            outcome.degraded = true;
            outcome.isComplete = true;
            outcome.total = countFromArchivalLog(objects, parsedFrom, parsedTo, dateBasis);
            return outcome;
        }

        for (String objectApiName : objects) {
            if (!routable.contains(objectApiName)) {
                outcome.unavailableObjects.add(describeLabel(objectApiName));
            }
        }

        // The one simple query. Everything above is scoping; this is the answer.
        outcome.total = sumDayCounts(routable, basis, parsedFrom, parsedTo);

        Set<String> datedObjects = objectsWithDatedDays(routable, basis);
        // Rollup days are UTC days, so an open range ends on today's UTC date.
        Date rangeEnd = parsedTo == null ? Datetime.now().dateGmt() : parsedTo;
        List<Archive_Row_Count__c> rollups = ensureRollups(
            routable, basis, forceRecount == true, datedObjects, rangeEnd);

        Boolean allComplete = true;
        Datetime oldest;
        for (Archive_Row_Count__c rollup : rollups) {
            outcome.calloutsUsed += (rollup.Callouts_Used__c == null)
                ? 0 : rollup.Callouts_Used__c.intValue();

            if (rollup.Status__c == 'Failed') {
                outcome.isFailed = true;
                outcome.errorMessage = rollup.Error_Message__c;
            }
            if (rollup.Status__c != 'Complete') {
                allComplete = false;
                // No published days yet for this object, so report the walk's own
                // running total as the floor rather than showing zero. Only then:
                // once an earlier walk has published days, sumDayCounts already
                // holds them, and adding a recount's running total on top would
                // count the same rows twice.
                if (rollup.Object_API_Name__c == null
                    || !datedObjects.contains(rollup.Object_API_Name__c.toLowerCase())) {
                    outcome.total += (rollup.Running_Total__c == null)
                        ? 0 : rollup.Running_Total__c.intValue();
                }
            } else if (oldest == null || rollup.Completed_At__c < oldest) {
                oldest = rollup.Completed_At__c;
            }
        }

        outcome.isComplete = allComplete && !outcome.isFailed;
        outcome.isBuilding = !allComplete && !outcome.isFailed;
        outcome.completedAt = outcome.isComplete ? oldest : null;
        return outcome;
    }

    /**
     * Sums the rollup across the days a range covers. This is the query the whole
     * design exists to make possible.
     *
     * A null bound means unbounded on that side, which sums every day the rollup
     * knows about. Objects whose rollup has not finished contribute nothing here -
     * their days are published only on completion, so a half-counted day can
     * never be summed as though it were whole.
     */
    private static Integer sumDayCounts(
        List<String> objects,
        String basis,
        Date fromDate,
        Date toDate
    ) {
        String soql =
            'SELECT SUM(Row_Count__c) total FROM Archive_Day_Count__c'
            + ' WHERE Object_API_Name__c IN :objects AND Date_Basis__c = :basis';
        if (fromDate != null) {
            soql += ' AND Day__c >= :fromDate';
        }
        if (toDate != null) {
            soql += ' AND Day__c <= :toDate';
        }

        List<AggregateResult> rows = Database.query(soql);
        if (rows.isEmpty() || rows[0].get('total') == null) {
            return 0;
        }
        return ((Decimal) rows[0].get('total')).intValue();
    }

    /**
     * Returns the cache row per object, starting a count for any that needs one.
     *
     * Upsert on the external id rather than query-then-insert so two users asking
     * the same question at the same moment converge on one count instead of
     * racing to start two.
     */
    private static List<Archive_Row_Count__c> ensureRollups(
        List<String> objects,
        String basis,
        Boolean forceRecount,
        Set<String> datedObjects,
        Date rangeEnd
    ) {
        Map<String, String> keyByObject = new Map<String, String>();
        for (String objectApiName : objects) {
            keyByObject.put(objectApiName, countCacheKey(objectApiName, null, null, basis));
        }

        Map<String, Archive_Row_Count__c> existing = new Map<String, Archive_Row_Count__c>();
        for (Archive_Row_Count__c row : [
            SELECT Id, Cache_Key__c, Object_API_Name__c, Status__c, Running_Total__c,
                   Callouts_Used__c, Chain_Depth__c, Completed_At__c, Started_At__c,
                   Error_Message__c, CreatedDate, LastModifiedDate, Partial_Tally__c
            FROM Archive_Row_Count__c
            WHERE Cache_Key__c IN :keyByObject.values()
        ]) {
            existing.put(row.Cache_Key__c, row);
        }

        List<Archive_Row_Count__c> toStart = new List<Archive_Row_Count__c>();
        List<Archive_Row_Count__c> outcome = new List<Archive_Row_Count__c>();

        for (String objectApiName : objects) {
            String key = keyByObject.get(objectApiName);
            Archive_Row_Count__c row = existing.get(key);

            if (row != null
                && !needsRecount(
                    row, forceRecount,
                    datedObjects.contains(objectApiName.toLowerCase()), rangeEnd)) {
                outcome.add(row);
                continue;
            }

            Archive_Row_Count__c fresh = new Archive_Row_Count__c(
                Cache_Key__c        = key,
                Object_API_Name__c  = objectApiName,
                Date_Basis__c       = basis,
                // No date bounds: the rollup walks the whole table once, and the
                // report's ranges are then answered by summing days out of it.
                From_Date__c        = null,
                To_Date__c          = null,
                Partial_Tally__c    = null,
                Running_Total__c    = 0,
                Callouts_Used__c    = 0,
                Chain_Depth__c      = 0,
                Next_Partition_Key__c = null,
                Next_Row_Key__c     = null,
                Error_Message__c    = null,
                Completed_At__c     = null,
                Started_At__c       = Datetime.now(),
                Status__c           = 'Running'
            );
            toStart.add(fresh);
            outcome.add(fresh);
        }

        if (!toStart.isEmpty()) {
            upsert toStart Cache_Key__c;
            for (Archive_Row_Count__c row : toStart) {
                System.enqueueJob(new ArchiveCountQueueable(row.Id));
            }
        }

        return outcome;
    }

    /**
     * How soon a finished count that dated none of its rows is retried. Such a
     * count tallied on a field name the archive does not carry (see
     * countDateField) and is wrong rather than stale, so it is retried almost at
     * once. The few minutes only stop a genuinely undated archive from being
     * recounted on every poll: a count that has just finished is left alone, so
     * the poll that sees it complete can stop.
     */
    private static final Integer UNDATED_RETRY_MINUTES = 5;

    /**
     * Rollups at or below this many rows are small enough - a handful of chained
     * jobs, a minute or two - to be kept current with the archive rather than
     * refreshed daily. Attendance, Inventory Adjustment and Visit Task sit here;
     * Order Line Item (9.65M rows, ~35 minutes a walk) does not, and keeps the
     * daily refresh it always had.
     */
    private static final Integer SMALL_ROLLUP_ROWS = 500000;

    /**
     * How old a small rollup may be before a range reaching past its walk
     * recounts it. See needsRecount.
     */
    private static final Integer SMALL_ROLLUP_FRESHNESS_MINUTES = 30;

    /** Objects whose rollup published at least one dated day, lower-cased. One query. */
    private static Set<String> objectsWithDatedDays(List<String> objects, String basis) {
        Set<String> dated = new Set<String>();
        for (AggregateResult row : [
            SELECT Object_API_Name__c
            FROM Archive_Day_Count__c
            WHERE Object_API_Name__c IN :objects
              AND Date_Basis__c = :basis
              AND Day__c != null
            GROUP BY Object_API_Name__c
        ]) {
            dated.add(((String) row.get('Object_API_Name__c')).toLowerCase());
        }
        return dated;
    }

    /**
     * Whether a cached count should be thrown away and run again.
     *
     * @param hasDatedDays whether this object's rollup published any dated day.
     * @param rangeEnd     last day of the range being asked about (UTC).
     */
    private static Boolean needsRecount(
        Archive_Row_Count__c row,
        Boolean forceRecount,
        Boolean hasDatedDays,
        Date rangeEnd
    ) {
        if (forceRecount) {
            return true;
        }
        if (row.Status__c == 'Failed') {
            return true;
        }
        if (row.Status__c == 'Complete') {
            if (row.Completed_At__c == null) {
                return true;
            }
            // Counted rows, dated none: every range sums to 0 while the report
            // shows rows. Recount it, now that the job tallies on the right field.
            if (!hasDatedDays
                && row.Running_Total__c != null && row.Running_Total__c > 0
                && row.Completed_At__c < Datetime.now().addMinutes(-UNDATED_RETRY_MINUTES)) {
                return true;
            }
            // A small rollup asked about a day it cannot have seen in full - the
            // walk started on or before that day ended - misses whatever was
            // archived after it passed. Small walks are cheap, so recount rather
            // than leave the total behind the rows the report is showing.
            Boolean small = row.Running_Total__c == null
                || row.Running_Total__c <= SMALL_ROLLUP_ROWS;
            Date fullyCountedBefore = row.Started_At__c == null
                ? null
                : row.Started_At__c.dateGmt();
            if (small
                && rangeEnd != null
                && (fullyCountedBefore == null || rangeEnd >= fullyCountedBefore)
                && row.Completed_At__c < Datetime.now().addMinutes(-SMALL_ROLLUP_FRESHNESS_MINUTES)) {
                return true;
            }
            return row.Completed_At__c < Datetime.now().addHours(-COUNT_FRESHNESS_HOURS);
        }
        // Running. Restart only if it has gone quiet - a chain that died without
        // recording a failure would otherwise be polled for ever. A long count is
        // not a stalled one, so this asks when the chain last wrote anything.
        Datetime lastProgress = row.LastModifiedDate == null
            ? row.CreatedDate
            : row.LastModifiedDate;
        return lastProgress == null
            || lastProgress < Datetime.now().addMinutes(-COUNT_STALL_MINUTES);
    }

    /**
     * Identifies one counting question. Dates are rendered as plain ISO so two
     * requests for the same window always produce the same key.
     */
    @TestVisible
    private static String countCacheKey(
        String objectApiName,
        Date fromDate,
        Date toDate,
        String basis
    ) {
        return String.join(new List<String>{
            objectApiName,
            basis,
            fromDate == null ? '*' : String.valueOf(fromDate),
            toDate == null ? '*' : String.valueOf(toDate)
        }, '|');
    }

    /**
     * The latest archive run these objects have a log entry for, as yyyy-MM-dd.
     *
     * Read from Archival_Log__c rather than the archive because the archive
     * cannot answer it: rows are ordered by PartitionKey, there is no ordering by
     * date and no aggregate, so finding the newest archived date there would mean
     * walking millions of rows. One SOQL aggregate over the log gives an answer
     * immediately.
     *
     * The log is badly incomplete - logging is commented out in the archival batch,
     * so it holds a few hundred rows against millions archived - which makes this
     * unusable as a count but perfectly good for this: the rows it does hold are
     * real, so the newest of them is a genuine archive run. It is a lower bound on
     * the last archive activity, and the UI words it as such rather than as "the
     * last time anything was archived".
     *
     * Returns null rather than throwing: this is context for an empty result, and
     * failing to find context must never turn a working read into an error.
     */
    private static String lastArchiveActivity(List<String> objects) {
        if (!Schema.SObjectType.Archival_Log__c.isAccessible()) {
            return null;
        }
        try {
            List<AggregateResult> rows = [
                SELECT MAX(Soft_Archived_Date__c) latest
                FROM Archival_Log__c
                WHERE Archived_Object__c IN :objects
            ];
            if (rows.isEmpty() || rows[0].get('latest') == null) {
                return null;
            }
            Datetime latest = (Datetime) rows[0].get('latest');
            return latest.format('yyyy-MM-dd');
        } catch (Exception e) {
            return null;
        }
    }

    /** The archive config row for one object, or null. Used by the count job. */
    public static Azure_Archive_Config__mdt configFor(String objectApiName) {
        Map<String, Azure_Archive_Config__mdt> configs =
            loadConfigs(new List<String>{ objectApiName });
        return configs.get(objectApiName);
    }

    /**
     * The configured read route for one object, or null to use
     * ArchiveReadService.DEFAULT_PATHS - the same rule ArchiveCountQueueable
     * applies, so the report and the count always read the same route.
     */
    public static String readPathFor(String objectApiName) {
        return readPathFor(objectApiName, configFor(objectApiName));
    }

    private static String readPathFor(String objectApiName, Azure_Archive_Config__mdt cfg) {
        return (cfg != null && String.isNotBlank(cfg.Read_Path__c)) ? cfg.Read_Path__c : null;
    }

    // ---------------------------------------------------------------- archive read

    /**
     * Which date the range filters on, and which field rows are ordered by.
     *
     * ARCHIVED (the default, and the only basis the report now uses) is when the
     * record left Salesforce; CREATED is when the record was originally made. The
     * distinction is not cosmetic here. The Order Line Items in the archive were
     * created in April 2025 and archived on 2026-08-30, so a recent window on
     * created date matches nothing at all - and because nothing matches, Table
     * Storage scans the entire table looking. The same window on archived date
     * matched on the first page: 0.25s versus 5.3s and zero rows, measured
     * 2026-09-17. CREATED remains only for the older entry points and the rollup.
     */
    private static final String BASIS_CREATED = 'CREATED';
    private static final String BASIS_ARCHIVED = 'ARCHIVED';

    /**
     * The date field to filter and tally on, in the casing this object's archive
     * uses. Public because the rollup job needs exactly the same answer - a
     * rollup tallied on the wrong field name would key every row UNDATED.
     */
    public static String archiveDateField(String objectApiName, String dateBasis) {
        ArchiveNaming naming = namingFor(objectApiName);
        return BASIS_CREATED.equalsIgnoreCase(dateBasis)
            ? naming.createdDateField
            : naming.archivedDateField;
    }

    /**
     * The date field ArchiveCountQueueable tallies on - archiveDateField, but made
     * certain first.
     *
     * The report learns an unverified archive's casing from the archive itself
     * (detectArchiveKeys) before it reads. The count job runs in its own
     * transaction and, without an org cache partition to share that answer,
     * used to fall back to 'Archived_Date__c' - so an archive that stores the
     * field under another casing filed every row as UNDATED, published no days,
     * and finished as a confident total of 0 while the report showed rows. This
     * runs the same detection in the job's own transaction, so the two always
     * agree.
     *
     * Verified objects (ARCHIVE_NAMING) are answered exactly as before, with no
     * callout. Otherwise at most one small read, before any DML - callers must
     * call it before they write, as the count job does.
     */
    public static String countDateField(String objectApiName, String dateBasis) {
        if (String.isNotBlank(objectApiName) && !ARCHIVE_NAMING.containsKey(objectApiName)) {
            detectArchiveKeys(
                objectApiName, configFor(objectApiName),
                new List<String>{ 'Id', 'Archived_Date__c', 'CreatedDate', 'Name' });
        }
        return archiveDateField(objectApiName, dateBasis);
    }

    /** The Archival_Log__c equivalents, for the degraded path. */
    private static String logDateField(String dateBasis) {
        return BASIS_CREATED.equalsIgnoreCase(dateBasis)
            ? 'Original_CreatedDate__c'
            : 'Soft_Archived_Date__c';
    }

    /**
     * Reads one global page across every selected object.
     *
     * The archive cannot serve a page directly: its responses carry no row count,
     * and $skip returns 501, so there is no offset paging to build page N on (see
     * ArchiveReadService). Instead each selected object contributes a bounded
     * window of matching rows - retrieved with $select limited to the report's own
     * columns, which keeps the payload small - and this method counts, orders and
     * slices that window in memory.
     *
     * Rows are ordered newest-first on CreatedDate, matching the Archival_Log__c
     * fallback, so the two sources read the same way round. When a window is capped
     * the retained rows are the archive's first N in PartitionKey/RowKey order,
     * which is unrelated to date - page.isCapped says so, and the LWC tells the
     * user to narrow the range rather than implying a complete result.
     *
     * Returns null only when no selected object has a published read route, which
     * is the caller's signal to degrade to the log index.
     */
    private static ReportPage readFromArchive(
        List<String> objects,
        Map<String, Azure_Archive_Config__mdt> configs,
        Date fromDate,
        Date toDate,
        Integer pageSize,
        Integer globalOffset,
        String dateBasis,
        String continuation,
        ParentFilter filter
    ) {
        ReportPage page = new ReportPage();

        // One readable object is the case the report always sends, and the only
        // case a continuation token can serve, because a token belongs to one
        // table and there is no way to interleave two of them into a single
        // ordered page. Two or more readable objects - only reachable through the
        // older multi-object entry points - keep the windowed read below. A
        // parent filter is only ever built for a single object.
        List<String> routable = routableObjects(objects, configs);
        if (routable.size() == 1) {
            // Before columns are named: an unverified archive's casing decides
            // what every column, the date filter and the id field are called.
            prepareArchiveNames(routable[0], configs.get(routable[0]), filter);
        }

        page.columns = buildColumns(objects, configs, page);

        List<String> selectFields = new List<String>();
        for (ReportColumn col : page.columns) {
            if (col.fieldName != OBJECT_COLUMN) {
                selectFields.add(col.fieldName);
            }
        }

        if (routable.size() == 1) {
            return readOneObjectByToken(
                page, routable[0], configs, objects, fromDate, toDate, pageSize,
                archiveDateField(routable[0], dateBasis), dateBasis, selectFields,
                continuation, filter);
        }

        List<ArchiveRow> collected = new List<ArchiveRow>();
        List<String> unavailable = new List<String>();
        Integer availableObjects = 0;

        for (String objectApiName : objects) {
            ArchiveReadService.PageResult result = callArchive(
                objectApiName, configs.get(objectApiName), fromDate, toDate, selectFields,
                archiveDateField(objectApiName, dateBasis));

            if (result == null) {
                unavailable.add(describeLabel(objectApiName));
                continue;
            }

            availableObjects++;
            if (result.isCapped) {
                page.isCapped = true;
            }
            if (result.scanIncomplete) {
                page.scanIncomplete = true;
            }

            String objectLabel = describeLabel(objectApiName);
            String objectDateField = archiveDateField(objectApiName, dateBasis);
            Integer rowIndex = 0;
            for (Map<String, Object> source : result.records) {
                collected.add(new ArchiveRow(
                    buildRow(source, selectFields, objectLabel, objectApiName, rowIndex),
                    source.get(objectDateField)));
                rowIndex++;
            }
        }

        if (availableObjects == 0) {
            return null;
        }

        page.unavailableObjects = unavailable;
        collected.sort();
        page.totalCount = collected.size();

        Integer startIndex = Math.min(globalOffset, collected.size());
        Integer stop = Math.min(startIndex + pageSize, collected.size());
        for (Integer i = startIndex; i < stop; i++) {
            page.rows.add(collected[i].data);
        }

        return page;
    }

    /** Selected objects that have an archive read path configured or defaulted. */
    private static List<String> routableObjects(
        List<String> objects,
        Map<String, Azure_Archive_Config__mdt> configs
    ) {
        List<String> routable = new List<String>();
        for (String objectApiName : objects) {
            if (ArchiveReadService.hasRoute(
                    objectApiName, readPathFor(objectApiName, configs.get(objectApiName)))) {
                routable.add(objectApiName);
            }
        }
        return routable;
    }

    /**
     * One page of one object, read straight from the archive by continuation token.
     *
     * This is the path the report actually takes, and it reads one of two ways.
     *
     * BY DAY (readByDay) - whenever the rollup covers the object. Archive_Day_Count__c
     * knows, for every day that holds archived rows, where in the table that day's
     * rows begin and how many there are. So the range is walked newest day first,
     * each day read with a one-day filter from its OWN start position, and a day is
     * finished the moment its known row count has been read - the read never scans
     * past a day's rows looking for more. Days the rollup has no row for held no
     * rows when it walked, and are never read at all.
     *
     * This replaced reading the whole range from the lowest start position of any
     * day in it. That was only as good as its weakest day: one day in range with
     * no recorded position - or a position that compared lower than it really was,
     * since continuation tokens need not order like the keys they encode - sent the
     * read back to the top of a 9.65M-row table, where the six-hop scan budget ran
     * out long before the range began. Which ranges escaped that depended on which
     * days they happened to include, which is why "Last 30 days" worked while Last
     * 90, Today, Yesterday and Custom came back empty.
     *
     * Days after the rollup last walked may hold rows it never saw, so they are read
     * too - last, and from the top, because nothing is known about them.
     *
     * WHOLE RANGE (readWholeRange) - when there is no rollup yet (a new object's
     * first count has not finished), when either date is open, or when resuming a
     * token issued by this read. This is the previous behaviour.
     *
     * Either way a page stops at pageSize rows or when SCAN_MAX_FETCHES, the callout
     * headroom or the time budget runs out, and an empty page with hasMore means
     * "not found yet": the UI offers to search further from exactly where it stopped.
     *
     * With a parent filter the same walk runs in larger batches and keeps only the
     * rows linked to that parent, so a filtered page may hold more or fewer than
     * pageSize rows.
     *
     * Rows are sorted newest-first within the page, and walking newest day first
     * means pages run newest to oldest by day as well.
     *
     * Returns null when the route turns out not to exist, so the caller degrades.
     */
    private static ReportPage readOneObjectByToken(
        ReportPage page,
        String objectApiName,
        Map<String, Azure_Archive_Config__mdt> configs,
        List<String> allObjects,
        Date fromDate,
        Date toDate,
        Integer pageSize,
        String dateField,
        String dateBasis,
        List<String> selectFields,
        String continuation,
        ParentFilter filter
    ) {
        page.tokenPaged = true;
        for (String other : allObjects) {
            if (other != objectApiName) {
                page.unavailableObjects.add(describeLabel(other));
            }
        }

        if (filter != null) {
            bindParentFilter(filter, objectApiName);
        }

        ArchiveReadService.ArchiveQuery q = buildQuery(
            objectApiName, configs.get(objectApiName), fromDate, toDate,
            fetchFields(selectFields, objectApiName, dateField, filter), dateField,
            filter == null ? pageSize : ArchiveReadService.MAX_ROWS);

        PageScan scan = new PageScan(
            q, pageSize, filter, selectFields, describeLabel(objectApiName),
            objectApiName, dateField);

        Map<String, Object> cursor = decodeCursor(continuation);

        // A parent search with no date range, on an archive partitioned by the
        // parent's name, is an indexed lookup rather than a scan. See readByPartition.
        Boolean undated = fromDate == null && toDate == null;
        if (filter != null && undated
            && partitionKeyIsParent(objectApiName, configs.get(objectApiName), filter)) {
            String partitionTerm = cursor.containsKey('pkTerm')
                ? (String) cursor.get('pkTerm')
                : filter.term;
            if (!readByPartition(scan, page, cursor, partitionTerm)) {
                return null;
            }
            return finishPage(page, scan);
        }

        if (objectApiName == INVENTORY_ADJUSTMENT && filter == null) {
            if (!readInventoryFirst(scan, page, cursor, dateBasis, fromDate, toDate)) {
                return null;
            }
            return finishPage(page, scan);
        }

        if (!readRange(scan, page, cursor, continuation, dateBasis, fromDate, toDate)) {
            return null;
        }
        return finishPage(page, scan);
    }

    /**
     * One page of the range, by day when the rollup can plan it and as a whole
     * otherwise. Returns false when the route does not exist.
     */
    private static Boolean readRange(
        PageScan scan,
        ReportPage page,
        Map<String, Object> cursor,
        String continuation,
        String dateBasis,
        Date fromDate,
        Date toDate
    ) {
        // A token from the whole-range read carries no day. It is honoured by that
        // read, so a page left open across a deploy still pages forward correctly.
        Boolean wholeRangeToken = String.isNotBlank(continuation) && !cursor.containsKey('day');
        List<DayPlan> plan = wholeRangeToken
            ? null
            : planDays(scan.objectApiName, dateBasis, fromDate, toDate);

        return plan == null
            ? readWholeRange(scan, page, cursor, continuation, dateBasis, fromDate, toDate)
            : readByDay(scan, page, plan, cursor);
    }

    /**
     * PartitionKey of archived Inventory Adjustments with no Inventory. The archive
     * partitions this object by Inventory__c Id, and this key sorts before every
     * Id, so a read in storage order shows nothing but rows without an Inventory
     * until it has walked past all of them.
     */
    private static final String NO_INVENTORY_PARTITION = 'NO_INVENTORY';

    /**
     * Inventory Adjustment key ranges, in the order the report reads them: keys
     * after NO_INVENTORY, keys before it - both rows with an Inventory - and then
     * NO_INVENTORY itself. Each pair is {partitionKeyFrom, partitionKeyBefore};
     * null is unbounded. A space is the smallest character a key can continue
     * with, so 'NO_INVENTORY ' is the first key after the bare 'NO_INVENTORY'.
     */
    private static final List<List<String>> INVENTORY_SEGMENTS = new List<List<String>>{
        new List<String>{ NO_INVENTORY_PARTITION + ' ', null },
        new List<String>{ null, NO_INVENTORY_PARTITION },
        new List<String>{ NO_INVENTORY_PARTITION, NO_INVENTORY_PARTITION + ' ' }
    };

    /**
     * Reads Inventory Adjustments with an Inventory before those without one, by
     * reading INVENTORY_SEGMENTS in turn. Each segment is an ordinary range read
     * bounded on PartitionKey - the archive's one indexed column, so a bound is a
     * seek, not a scan. The segment in progress rides in the continuation as
     * "seg", alongside that segment's own cursor; a page that finishes a segment
     * with room left carries on into the next one.
     *
     * Returns false when the route does not exist.
     */
    private static Boolean readInventoryFirst(
        PageScan scan,
        ReportPage page,
        Map<String, Object> cursor,
        String dateBasis,
        Date fromDate,
        Date toDate
    ) {
        Integer segment = cursor.containsKey('seg') ? Integer.valueOf(cursor.get('seg')) : 0;
        Map<String, Object> segmentCursor = new Map<String, Object>(cursor);
        segmentCursor.remove('seg');

        while (segment < INVENTORY_SEGMENTS.size()) {
            List<String> bounds = INVENTORY_SEGMENTS[segment];
            scan.q.partitionKeyFrom = bounds[0];
            scan.q.partitionKeyBefore = bounds[1];
            // A by-day read moves the dates on the query; each segment starts
            // from the range the user asked for.
            scan.q.fromDate = fromDate;
            scan.q.toDate = toDate;

            String segmentContinuation = segmentCursor.isEmpty()
                ? null
                : JSON.serialize(segmentCursor);
            if (!readRange(scan, page, segmentCursor, segmentContinuation,
                           dateBasis, fromDate, toDate)) {
                return false;
            }

            if (page.hasMore) {
                page.nextContinuation = withSegment(page.nextContinuation, segment);
                return true;
            }

            segment++;
            segmentCursor = new Map<String, Object>();
            if (segment < INVENTORY_SEGMENTS.size() && !canReadAgain(scan)) {
                // This segment is done and the page is full: the next page opens
                // the next segment from its start.
                page.hasMore = true;
                page.nextContinuation = JSON.serialize(new Map<String, Object>{ 'seg' => segment });
                return true;
            }
        }

        page.hasMore = false;
        page.nextContinuation = null;
        return true;
    }

    /** A segment's continuation with the segment number added. */
    private static String withSegment(String continuation, Integer segment) {
        Map<String, Object> token = String.isBlank(continuation)
            ? new Map<String, Object>()
            : decodeCursor(continuation);
        token.put('seg', segment);
        return JSON.serialize(token);
    }

    /** Orders the rows a scan kept onto the page and sets its totals. */
    private static ReportPage finishPage(ReportPage page, PageScan scan) {
        // Nothing found yet but there is more to read: "not found yet", so the UI
        // offers to search further instead of showing an empty state.
        page.scanIncomplete = page.hasMore && scan.ordered.isEmpty();

        scan.ordered.sort();
        for (ArchiveRow row : scan.ordered) {
            page.rows.add(row.data);
        }

        page.totalCount = page.rows.size();
        return page;
    }

    /**
     * A parent search with no date range, read by PartitionKey.
     *
     * With no range there are no days to plan by, so this search used to read the
     * table from the top and keep matching rows - at most a few thousand rows per
     * Apply out of millions, so a given Order was almost never reached. But where
     * the archive is partitioned by the parent's name - Order Line Items are
     * keyed on the Order number, O-811061 and so on - "every line of this Order"
     * is a range of the one indexed column, and the archive seeks straight to it.
     *
     * Matches keys that START with the term (PartitionKey ge term and lt the
     * term's successor), so "O-811061" finds that Order and "O-8110" every Order
     * beginning so. Rows still pass through the usual in-memory match on the
     * name field, as a guard. Keys are case-sensitive, so a term that finds
     * nothing as typed is tried once in upper case - how the names are stored -
     * before the answer is "none"; the variant used rides in the continuation so
     * later pages stay in the same range.
     */
    private static Boolean readByPartition(
        PageScan scan,
        ReportPage page,
        Map<String, Object> cursor,
        String partitionTerm
    ) {
        String term = partitionTerm;
        Boolean firstPage = !cursor.containsKey('pk');
        setPartitionPrefix(scan.q, term);
        scan.q.startPartitionKey = (String) cursor.get('pk');
        scan.q.startRowKey = (String) cursor.get('rk');

        while (true) {
            ArchiveReadService.PageResult result = scanRead(scan);
            if (result == null) {
                return false;
            }
            Boolean more = hasNext(result);

            if (firstPage && !more && scan.ordered.isEmpty() && !term.equals(term.toUpperCase())) {
                term = term.toUpperCase();
                setPartitionPrefix(scan.q, term);
                scan.q.startPartitionKey = null;
                scan.q.startRowKey = null;
                firstPage = false;
                continue;
            }
            firstPage = false;

            page.hasMore = more;
            page.nextContinuation = more
                ? JSON.serialize(new Map<String, String>{
                      'pk'     => result.nextPartitionKey,
                      'rk'     => result.nextRowKey,
                      'pkTerm' => term
                  })
                : null;
            if (!more || !canReadAgain(scan)) {
                return true;
            }
            scan.q.startPartitionKey = result.nextPartitionKey;
            scan.q.startRowKey = result.nextRowKey;
        }
        // Unreachable - the loop only exits by returning - but Apex requires it.
        return true;
    }

    /** Bounds a query to the keys that start with prefix. */
    private static void setPartitionPrefix(ArchiveReadService.ArchiveQuery q, String prefix) {
        Integer last = prefix.charAt(prefix.length() - 1);
        q.partitionKeyFrom = prefix;
        q.partitionKeyBefore = prefix.substring(0, prefix.length() - 1)
            + String.fromCharArray(new List<Integer>{ last + 1 });
    }

    /** Per transaction; the org cache carries the answer between transactions. */
    private static Map<String, Boolean> partitionIsParent = new Map<String, Boolean>();

    /**
     * Whether this object's archive is partitioned by the parent's name, i.e.
     * PartitionKey holds exactly what Order_Name__c / Invoice_Number__c /
     * Visit_Name__c holds.
     *
     * Checked against the archive rather than assumed: the first rows of the
     * table are read with both columns, and the answer is yes only when every
     * row that carries both agrees. Anything less - a mismatch, no comparable
     * rows, a failed read - is no, and the search falls back to the scan it has
     * always done, so a wrong guess can never hide rows. The answer is kept in
     * the org cache for a day when one is available.
     */
    private static Boolean partitionKeyIsParent(
        String objectApiName,
        Azure_Archive_Config__mdt cfg,
        ParentFilter filter
    ) {
        if (filter.textFields.isEmpty()) {
            return false;
        }
        if (partitionIsParent.containsKey(objectApiName)) {
            return partitionIsParent.get(objectApiName);
        }

        String cacheKey = 'ArchivePkParent' + objectApiName.replaceAll('[^A-Za-z0-9]', '');
        Boolean known = null;
        try {
            known = (Boolean) Cache.Org.get(cacheKey);
        } catch (Exception e) {
            known = null;
        }
        if (known == null) {
            known = probePartitionIsParent(objectApiName, cfg, filter.textFields[0]);
            if (known != null) {
                try {
                    Cache.Org.put(cacheKey, known, ARCHIVE_KEYS_TTL_SECONDS);
                } catch (Exception e) {
                    System.debug(LoggingLevel.FINE, 'Org cache unavailable: ' + e.getMessage());
                }
            }
        }

        Boolean answer = known == true;
        partitionIsParent.put(objectApiName, answer);
        return answer;
    }

    /** True / false from a sample of rows; null when the sample cannot decide. */
    private static Boolean probePartitionIsParent(
        String objectApiName,
        Azure_Archive_Config__mdt cfg,
        String nameField
    ) {
        try {
            ArchiveReadService.PageResult result = ArchiveReadService.fetch(buildQuery(
                objectApiName, cfg, null, null,
                new List<String>{ 'PartitionKey', nameField }, null, ARCHIVE_PROBE_ROWS));
            if (!result.isSuccess || result.records == null) {
                return null;
            }
            Integer compared = 0;
            for (Map<String, Object> source : result.records) {
                Object key = source.get('PartitionKey');
                Object name = source.get(nameField);
                if (key == null || name == null) {
                    continue;
                }
                if (!String.valueOf(key).equals(String.valueOf(name))) {
                    return false;
                }
                compared++;
            }
            return compared > 0 ? true : null;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'Partition probe failed for ' + objectApiName + ': ' + e.getMessage());
            return null;
        }
    }

    /** One page's reading in progress: the query, the rows so far, the budget spent. */
    private class PageScan {
        private final ArchiveReadService.ArchiveQuery q;
        private final Integer pageSize;
        private final ParentFilter filter;
        private final List<String> selectFields;
        private final String objectLabel;
        private final String objectApiName;
        private final String dateField;
        private final List<ArchiveRow> ordered = new List<ArchiveRow>();
        private final Long startedAt = System.currentTimeMillis();
        private Integer rowIndex = 0;
        private Integer fetches = 0;

        private PageScan(
            ArchiveReadService.ArchiveQuery q,
            Integer pageSize,
            ParentFilter filter,
            List<String> selectFields,
            String objectLabel,
            String objectApiName,
            String dateField
        ) {
            this.q = q;
            this.pageSize = pageSize;
            this.filter = filter;
            this.selectFields = selectFields;
            this.objectLabel = objectLabel;
            this.objectApiName = objectApiName;
            this.dateField = dateField;
        }
    }

    /**
     * One archive read from wherever scan.q points, keeping the rows that belong
     * on the page. Null when the route does not exist; throws on any other failure.
     *
     * Deliberately does NOT map result.isCapped onto the page. fetch() sets it
     * whenever it stopped with rows still available, which on a page-sized read
     * is simply "there is a next page" - hasMore's job. Forwarding it would raise
     * the partial-result banner on every page of a normal read.
     */
    private static ArchiveReadService.PageResult scanRead(PageScan scan) {
        if (scan.filter == null) {
            // Only top the page up - never past pageSize.
            scan.q.maxRows = scan.pageSize - scan.ordered.size();
        }
        ArchiveReadService.PageResult result = ArchiveReadService.fetch(scan.q);
        scan.fetches++;

        if (!result.isSuccess) {
            if (result.endpointUnavailable) {
                return null;
            }
            throw new AuraHandledException(
                'Archive read failed for ' + scan.objectApiName
                + ' (' + result.errorCode + '): ' + result.errorMessage);
        }

        if (result.records != null) {
            for (Map<String, Object> source : result.records) {
                if (scan.filter == null || scan.filter.matches(source)) {
                    scan.ordered.add(new ArchiveRow(
                        buildRow(source, scan.selectFields, scan.objectLabel,
                                 scan.objectApiName, scan.rowIndex),
                        source.get(scan.dateField)));
                }
                scan.rowIndex++;
            }
        }
        return result;
    }

    /** Whether the page wants, and can afford, another read. */
    private static Boolean canReadAgain(PageScan scan) {
        return scan.ordered.size() < scan.pageSize && canScanFurther(scan.fetches, scan.startedAt);
    }

    /**
     * Whether the archive has somewhere to resume from. An unfinished scan is not
     * the end of the table, so it counts whenever a continuation came back.
     */
    private static Boolean hasNext(ArchiveReadService.PageResult result) {
        return (result.hasMore || result.scanIncomplete)
            && String.isNotBlank(result.nextPartitionKey);
    }

    /** Whether one page still has budget for another archive read. */
    private static Boolean canScanFurther(Integer fetches, Long startedAt) {
        return fetches < SCAN_MAX_FETCHES
            && Limits.getCallouts() + SCAN_CALLOUT_HEADROOM < Limits.getLimitCallouts()
            && System.currentTimeMillis() - startedAt < SCAN_TIME_BUDGET_MS
            && Limits.getCpuTime() < Limits.getLimitCpuTime() * SCAN_CPU_SHARE_PERCENT / 100;
    }

    /**
     * The previous read: the whole range under one filter, from the rollup's range
     * start position on the first page, else from the continuation. Used when
     * there is no rollup to plan by. Returns false when the route does not exist.
     */
    private static Boolean readWholeRange(
        PageScan scan,
        ReportPage page,
        Map<String, Object> cursor,
        String continuation,
        String dateBasis,
        Date fromDate,
        Date toDate
    ) {
        scan.q.startPartitionKey = (String) cursor.get('pk');
        scan.q.startRowKey = (String) cursor.get('rk');

        // First page of a dated read: start where the rollup saw this range begin
        // rather than at the top of the table. Later pages already carry a real
        // continuation and must not be second-guessed.
        if (String.isBlank(continuation)) {
            ArchiveReadService.DayCursor startAt =
                rangeStartCursor(scan.objectApiName, dateBasis, fromDate, toDate);
            if (startAt != null) {
                scan.q.startPartitionKey = startAt.partitionKey;
                scan.q.startRowKey = startAt.rowKey;
            }
        }

        while (true) {
            ArchiveReadService.PageResult result = scanRead(scan);
            if (result == null) {
                return false;
            }
            Boolean more = hasNext(result);
            page.hasMore = more;
            page.nextContinuation = more
                ? encodeCursor(result.nextPartitionKey, result.nextRowKey)
                : null;
            if (!more || !canReadAgain(scan)) {
                return true;
            }
            scan.q.startPartitionKey = result.nextPartitionKey;
            scan.q.startRowKey = result.nextRowKey;
        }
        // Unreachable - the loop only exits by returning - but Apex requires it.
        return true;
    }

    /**
     * Walks the planned days in order, each under its own one-day filter from its
     * own start position, carrying the position within the current day in the
     * continuation: {"day":"yyyy-MM-dd","pk":..,"rk":..,"seen":n}.
     *
     * A day with a known row count is finished once that many rows have come back,
     * so the read moves on instead of scanning the rest of the table for rows the
     * rollup already says are not there. Returns false when the route does not exist.
     */
    private static Boolean readByDay(
        PageScan scan,
        ReportPage page,
        List<DayPlan> plan,
        Map<String, Object> cursor
    ) {
        Integer dayIndex = 0;
        String resumePartitionKey;
        String resumeRowKey;
        Integer seenInDay = 0;

        if (cursor.containsKey('day')) {
            dayIndex = indexOfDay(plan, (String) cursor.get('day'));
            resumePartitionKey = (String) cursor.get('pk');
            resumeRowKey = (String) cursor.get('rk');
            seenInDay = cursor.get('seen') == null ? 0 : Integer.valueOf(cursor.get('seen'));
        }

        while (dayIndex < plan.size()) {
            DayPlan day = plan[dayIndex];
            scan.q.fromDate = day.day;
            scan.q.toDate = day.day;
            if (String.isNotBlank(resumePartitionKey)) {
                scan.q.startPartitionKey = resumePartitionKey;
                scan.q.startRowKey = resumeRowKey;
            } else {
                // Blank for a day that begins at the top of the table - a real
                // position, and the right place to start that day.
                scan.q.startPartitionKey = day.partitionKey;
                scan.q.startRowKey = day.rowKey;
            }

            ArchiveReadService.PageResult result = scanRead(scan);
            if (result == null) {
                return false;
            }
            seenInDay += result.records == null ? 0 : result.records.size();

            Boolean dayDone = !hasNext(result)
                || (day.rowCount != null && seenInDay >= day.rowCount);
            if (dayDone) {
                dayIndex++;
                resumePartitionKey = null;
                resumeRowKey = null;
                seenInDay = 0;
            } else {
                resumePartitionKey = result.nextPartitionKey;
                resumeRowKey = result.nextRowKey;
            }

            if (!canReadAgain(scan)) {
                break;
            }
        }

        page.hasMore = dayIndex < plan.size();
        page.nextContinuation = page.hasMore
            ? JSON.serialize(new Map<String, Object>{
                  'day'  => String.valueOf(plan[dayIndex].day),
                  'pk'   => resumePartitionKey,
                  'rk'   => resumeRowKey,
                  'seen' => seenInDay
              })
            : null;
        return true;
    }

    /** Position of a day in the plan; past the end when it is no longer there. */
    private static Integer indexOfDay(List<DayPlan> plan, String day) {
        for (Integer i = 0; i < plan.size(); i++) {
            if (String.valueOf(plan[i].day) == day) {
                return i;
            }
        }
        return plan.size();
    }

    /** One day of a by-day read. rowCount is null for a day the rollup cannot vouch for. */
    private class DayPlan {
        private final Date day;
        private final String partitionKey;
        private final String rowKey;
        private final Integer rowCount;

        private DayPlan(Date day, String partitionKey, String rowKey, Integer rowCount) {
            this.day = day;
            this.partitionKey = partitionKey;
            this.rowKey = rowKey;
            this.rowCount = rowCount;
        }
    }

    /**
     * Hours allowed between a day ending and the rollup walk that counted it, so a
     * day is only trusted once a walk that started after it ended has published.
     * The longest walk measured - 9.65M Order Line Items - takes ~35 minutes.
     */
    private static final Integer ROLLUP_MARGIN_HOURS = 6;

    /**
     * The days a by-day read has to visit, or null to read the whole range instead.
     *
     * Null when either date is open, or when the rollup has never published for
     * this object - nothing is known about where anything is, so there is nothing
     * to plan with.
     *
     * Otherwise: every day the rollup counted rows for, newest first, with its
     * start position and row count; a day the rollup has no row for held nothing
     * when it walked, and is left out. Then every day since the rollup last walked,
     * newest first, with no position and no count - they may hold rows it never
     * saw, so they are read from the top and in full. They come last so that a
     * range the rollup covers shows its rows at once, rather than after a slow
     * scan of the most recent day.
     *
     * An empty plan is a proven-empty range: the report answers at once.
     */
    @TestVisible
    private static List<DayPlan> planDays(
        String objectApiName,
        String dateBasis,
        Date fromDate,
        Date toDate
    ) {
        if (fromDate == null || toDate == null) {
            return null;
        }
        String basis = BASIS_CREATED.equalsIgnoreCase(dateBasis) ? BASIS_CREATED : BASIS_ARCHIVED;

        // System mode, as rangeStartCursor: the rollup's own bookkeeping.
        List<AggregateResult> published = [
            SELECT MAX(Counted_At__c) asOf
            FROM Archive_Day_Count__c
            WHERE Object_API_Name__c = :objectApiName
              AND Date_Basis__c = :basis
        ];
        Datetime asOf = published.isEmpty() ? null : (Datetime) published[0].get('asOf');
        if (asOf == null) {
            return null;
        }
        // Rollup days are UTC calendar days - the first ten characters of the
        // archived ISO timestamp, e.g. '2026-09-11T13:45:22.123Z' - so the cut-off
        // is worked out in UTC as well.
        Date provenThrough = asOf.addHours(-ROLLUP_MARGIN_HOURS).dateGmt().addDays(-1);

        List<DayPlan> plan = new List<DayPlan>();
        for (Archive_Day_Count__c day : [
            SELECT Day__c, Row_Count__c, First_Partition_Key__c, First_Row_Key__c
            FROM Archive_Day_Count__c
            WHERE Object_API_Name__c = :objectApiName
              AND Date_Basis__c = :basis
              AND Day__c >= :fromDate
              AND Day__c <= :toDate
              AND Day__c <= :provenThrough
            ORDER BY Day__c DESC
        ]) {
            if (day.Row_Count__c == null || day.Row_Count__c <= 0) {
                continue;
            }
            plan.add(new DayPlan(
                day.Day__c, day.First_Partition_Key__c, day.First_Row_Key__c,
                day.Row_Count__c.intValue()));
        }

        Date firstUnproven = provenThrough.addDays(1);
        if (firstUnproven < fromDate) {
            firstUnproven = fromDate;
        }
        for (Date day = toDate; day >= firstUnproven; day = day.addDays(-1)) {
            plan.add(new DayPlan(day, null, null, null));
        }
        return plan;
    }

    /**
     * The fields to $select: the report's columns, plus the id and date fields the
     * row key and in-page ordering depend on, plus whatever a parent filter tests.
     * Without the date field here, a column set that does not display it would
     * leave every row's sort key null. Duplicates are dropped, case-sensitively,
     * because the archive is case-sensitive.
     */
    private static List<String> fetchFields(
        List<String> columnFields,
        String objectApiName,
        String dateField,
        ParentFilter filter
    ) {
        List<String> fields = new List<String>(columnFields);
        Set<String> seen = new Set<String>(columnFields);

        List<String> extras = new List<String>{ namingFor(objectApiName).idField, dateField };
        if (objectApiName == INVENTORY_ADJUSTMENT) {
            // The Inventory lookup the Inventory Name column is resolved from, in
            // both casings - the archive matches names exactly, and selecting a
            // property an entity lacks just returns nothing for it.
            extras.add(INVENTORY_LOOKUP_FIELD);
            extras.add(INVENTORY_LOOKUP_FIELD.toLowerCase());
            extras.add(INVENTORY_NAME_FIELD);
            extras.add(INVENTORY_NAME_FIELD.toLowerCase());
            extras.add(PRIMARY_INVOICE_FIELD);
            extras.add(PRIMARY_INVOICE_FIELD.toLowerCase());
        }
        if (filter != null) {
            extras.addAll(filter.idFields);
            extras.addAll(filter.textFields);
        }
        for (String fieldName : extras) {
            if (String.isNotBlank(fieldName) && !seen.contains(fieldName)) {
                fields.add(fieldName);
                seen.add(fieldName);
            }
        }
        return fields;
    }

    /**
     * The earliest point in the archive at which any day of this range was seen,
     * or null when there is nothing safe to skip to.
     *
     * Archived date is not indexed - PartitionKey is the only column that is - so
     * a dated read is a full scan that gives up long before it reaches a recent
     * day. Measured on 2026-09-21, reading 2026-09-20 from the top of the table
     * spent six seconds, returned no rows and was still scanning; resumed from
     * that day's recorded cursor it returned a full page in under a second. The
     * rollup already walks every row, so it records where each day began and this
     * reads that back.
     *
     * The minimum across the whole range, not the from date's own cursor: date
     * does not advance with key order - O-600000 is 2026-09-04 where O-620000 is
     * 2026-09-01 - so a later day in the range can begin earlier in the table
     * than the first one does. Only the smallest bound is safe for all of them.
     *
     * Returns null, meaning read from the beginning as before, when any day in
     * range has no recorded cursor. That covers both a day that genuinely starts
     * at the top of the table and a rollup taken before cursors were recorded,
     * and the safe response to either is the same: skip nothing. A hint is only
     * ever an optimisation, so withholding one costs speed and never rows.
     */
    @TestVisible
    private static ArchiveReadService.DayCursor rangeStartCursor(
        String objectApiName,
        String dateBasis,
        Date fromDate,
        Date toDate
    ) {
        if (fromDate == null) {
            // Unbounded below: the read has to start at the beginning anyway.
            return null;
        }
        String basis = BASIS_CREATED.equalsIgnoreCase(dateBasis) ? BASIS_CREATED : BASIS_ARCHIVED;
        Date upper = toDate == null ? Date.today() : toDate;

        // System mode, matching sumDayCounts above: this reads the rollup's own
        // bookkeeping, not archived data, and the caller has already passed the
        // CRUD/FLS checks for the read itself. Enforcing FLS here would let a
        // missing permission on an internal field throw in the middle of a report
        // that is otherwise entitled to run.
        List<Archive_Day_Count__c> days = [
            SELECT Day__c, First_Partition_Key__c, First_Row_Key__c
            FROM Archive_Day_Count__c
            WHERE Object_API_Name__c = :objectApiName
              AND Date_Basis__c = :basis
              AND Day__c >= :fromDate
              AND Day__c <= :upper
        ];
        if (days.isEmpty()) {
            return null;
        }

        Archive_Day_Count__c lowest = null;
        for (Archive_Day_Count__c day : days) {
            if (String.isBlank(day.First_Partition_Key__c)) {
                return null;
            }
            // Ordinal comparison, matching Table Storage's own ordering of the
            // key. Note that ordering is lexical, not numeric - O-106034 sorts
            // before O-2000 - so this must never be reasoned about as a number.
            if (lowest == null
                || day.First_Partition_Key__c.compareTo(lowest.First_Partition_Key__c) < 0) {
                lowest = day;
            }
        }
        return new ArchiveReadService.DayCursor(
            lowest.First_Partition_Key__c, lowest.First_Row_Key__c);
    }

    /**
     * The continuation pair as one opaque string for the client to hand back.
     *
     * JSON rather than the raw keys concatenated: a RowKey is arbitrary text and
     * can contain any separator that might be chosen.
     */
    private static String encodeCursor(String partitionKey, String rowKey) {
        if (String.isBlank(partitionKey)) {
            return null;
        }
        return JSON.serialize(new Map<String, String>{
            'pk' => partitionKey,
            'rk' => rowKey
        });
    }

    /** Inverse of encodeCursor; an empty map for a blank or unreadable token. */
    private static Map<String, Object> decodeCursor(String continuation) {
        if (String.isBlank(continuation)) {
            return new Map<String, Object>();
        }
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(continuation);
        } catch (Exception e) {
            // A token this method cannot read is a client-side bug, not a user
            // error; falling back to the first page is better than an exception.
            return new Map<String, Object>();
        }
    }

    /**
     * The archive query for one object - route, credential, casing and bounds -
     * shared by every read so a new object is wired up in exactly one place.
     */
    private static ArchiveReadService.ArchiveQuery buildQuery(
        String objectApiName,
        Azure_Archive_Config__mdt cfg,
        Date fromDate,
        Date toDate,
        List<String> selectFields,
        String dateField,
        Integer maxRows
    ) {
        ArchiveReadService.ArchiveQuery q = new ArchiveReadService.ArchiveQuery();
        q.objectApiName = objectApiName;
        q.fromDate = fromDate;
        q.toDate = toDate;
        q.dateField = dateField;
        q.selectFields = selectFields;
        q.idField = namingFor(objectApiName).idField;
        q.maxRows = maxRows;
        q.readPath = readPathFor(objectApiName, cfg);
        q.namedCredential = cfg == null ? null : cfg.Read_Named_Credential__c;
        return q;
    }

    /** One bounded archive read. Returns null when this object has no read route. */
    private static ArchiveReadService.PageResult callArchive(
        String objectApiName,
        Azure_Archive_Config__mdt cfg,
        Date fromDate,
        Date toDate,
        List<String> selectFields,
        String dateField
    ) {
        ArchiveReadService.ArchiveQuery q = buildQuery(
            objectApiName, cfg, fromDate, toDate, selectFields, dateField,
            ArchiveReadService.MAX_ROWS);

        ArchiveReadService.PageResult result = ArchiveReadService.fetch(q);

        if (result.isSuccess) {
            return result;
        }
        if (result.endpointUnavailable) {
            return null;
        }
        throw new AuraHandledException(
            'Archive read failed for ' + objectApiName
            + ' (' + result.errorCode + '): ' + result.errorMessage);
    }

    /** Projects one archive record onto the report's columns. */
    private static Map<String, Object> buildRow(
        Map<String, Object> source,
        List<String> selectFields,
        String objectLabel,
        String objectApiName,
        Integer rowIndex
    ) {
        Map<String, Object> row = new Map<String, Object>();
        for (String fieldName : selectFields) {
            row.put(fieldName, source.get(fieldName));
        }
        row.put(OBJECT_COLUMN, objectLabel);
        row.put('_rowKey', buildRowKey(source, objectApiName, rowIndex));
        if (objectApiName == INVENTORY_ADJUSTMENT) {
            // Kept for mapInventoryAdjustmentNames, which removes them once the
            // names are resolved.
            row.put(INVENTORY_ID_KEY, archivedValue(source, INVENTORY_LOOKUP_FIELD));
            row.put(INVENTORY_NAME_KEY, archivedValue(source, INVENTORY_NAME_FIELD));
            row.put(PRIMARY_INVOICE_ID_KEY, archivedValue(source, PRIMARY_INVOICE_FIELD));
            row.put(ADJUSTMENT_ID_KEY, archivedValue(source, 'Id'));
        }
        return row;
    }

    // ---------------------------------------------------------------- inventory adjustment names

    private static final String INVENTORY_ADJUSTMENT = 'Inventory_Adjustment__c';
    private static final String INVENTORY_LOOKUP_FIELD = 'Inventory__c';
    private static final String INVENTORY_NAME_FIELD = 'Inventory_Name__c';
    private static final String PRIMARY_INVOICE_FIELD = 'Primary_Invoice_transaction__c';
    /** Hidden row keys carrying archived values between read and display. */
    private static final String INVENTORY_ID_KEY = '_inventoryId';
    private static final String INVENTORY_NAME_KEY = '_inventoryName';
    private static final String PRIMARY_INVOICE_ID_KEY = '_primaryInvoiceId';
    private static final String ADJUSTMENT_ID_KEY = '_adjustmentId';

    /**
     * One Inventory Adjustment row on the page, with the names of the records its
     * lookups point at: Inventory (shown as Inventory_Name__c) and Primary Invoice
     * Transaction (an Invoice__c lookup).
     *
     * Each name is tried from these sources in order by mapInventoryAdjustmentNames,
     * every step only filling what the steps before left blank:
     *  1. the archived record itself - Inventory_Name__c, when the archive stored
     *     the formula value (there is no stored invoice name);
     *  2. the related record the archived Id points at - Inventory__c.Name,
     *     Invoice__c.Name;
     *  3. the Inventory Adjustment still in the org, for an archived record that
     *     has not been hard-deleted yet - its Inventory_Name__c and
     *     Primary_Invoice_transaction__r.Name.
     * A lookup no source can name is shown as its archived Id.
     */
    @TestVisible
    private class InventoryAdjustmentWrapper {
        @TestVisible private final Map<String, Object> row;
        @TestVisible private final Id adjustmentId;
        @TestVisible private final Id inventoryId;
        @TestVisible private String inventoryName;
        @TestVisible private final Id primaryInvoiceId;
        @TestVisible private String primaryInvoiceName;

        private InventoryAdjustmentWrapper(Map<String, Object> row) {
            this.row = row;
            this.adjustmentId = asRecordId(row.get(ADJUSTMENT_ID_KEY));
            this.inventoryId = asRecordId(row.get(INVENTORY_ID_KEY));
            this.primaryInvoiceId = asRecordId(row.get(PRIMARY_INVOICE_ID_KEY));
            Object archivedName = row.get(INVENTORY_NAME_KEY);
            this.inventoryName = archivedName == null || String.isBlank(String.valueOf(archivedName))
                ? null
                : String.valueOf(archivedName);
        }

        private Boolean needsInventoryName() {
            return String.isBlank(inventoryName) && inventoryId != null;
        }

        private Boolean needsPrimaryInvoiceName() {
            return String.isBlank(primaryInvoiceName) && primaryInvoiceId != null;
        }
    }

    /**
     * Shows each Inventory Adjustment's Inventory and Primary Invoice Transaction
     * by name: wraps the rows, fills each wrapper from the sources listed on
     * InventoryAdjustmentWrapper - one query per source for the whole page, in
     * user mode - and writes the wrapper's names into their columns.
     */
    @TestVisible
    private static void mapInventoryAdjustmentNames(String objectApiName, ReportPage page) {
        if (objectApiName != INVENTORY_ADJUSTMENT || page.rows.isEmpty()) {
            return;
        }

        String inventoryColumn = columnFor(page, INVENTORY_NAME_FIELD);
        String primaryInvoiceColumn = columnFor(page, PRIMARY_INVOICE_FIELD);

        List<InventoryAdjustmentWrapper> wrappers = new List<InventoryAdjustmentWrapper>();
        for (Map<String, Object> row : page.rows) {
            wrappers.add(new InventoryAdjustmentWrapper(row));
            row.remove(INVENTORY_ID_KEY);
            row.remove(INVENTORY_NAME_KEY);
            row.remove(PRIMARY_INVOICE_ID_KEY);
            row.remove(ADJUSTMENT_ID_KEY);
        }

        // No column: not configured, or not readable by this user. The hidden
        // keys are cleared above either way.
        if (inventoryColumn == null && primaryInvoiceColumn == null) {
            return;
        }

        namesFromRelatedRecords(wrappers);
        namesFromLiveAdjustment(wrappers);

        for (InventoryAdjustmentWrapper wrapper : wrappers) {
            // A record no source can name - typically one that exists only in the
            // org the archive was written from - shows its Id rather than a blank.
            if (inventoryColumn != null) {
                String inventory = String.isNotBlank(wrapper.inventoryName)
                    ? wrapper.inventoryName
                    : (wrapper.inventoryId == null ? null : String.valueOf(wrapper.inventoryId));
                if (inventory != null) {
                    wrapper.row.put(inventoryColumn, inventory);
                }
            }
            if (primaryInvoiceColumn != null) {
                String invoice = String.isNotBlank(wrapper.primaryInvoiceName)
                    ? wrapper.primaryInvoiceName
                    : (wrapper.primaryInvoiceId == null ? null : String.valueOf(wrapper.primaryInvoiceId));
                if (invoice != null) {
                    wrapper.row.put(primaryInvoiceColumn, invoice);
                }
            }
        }
    }

    /** The page's column for a field, in whatever casing it was built with. */
    private static String columnFor(ReportPage page, String fieldName) {
        for (ReportColumn col : page.columns) {
            if (col.fieldName != null && col.fieldName.equalsIgnoreCase(fieldName)) {
                return col.fieldName;
            }
        }
        return null;
    }

    /**
     * Source 2: the Name of the Inventory__c and Invoice__c records the archived
     * Ids point at.
     */
    private static void namesFromRelatedRecords(List<InventoryAdjustmentWrapper> wrappers) {
        Set<Id> inventoryIds = new Set<Id>();
        Set<Id> invoiceIds = new Set<Id>();
        for (InventoryAdjustmentWrapper wrapper : wrappers) {
            if (wrapper.needsInventoryName() && isRecordOf(wrapper.inventoryId, Inventory__c.SObjectType)) {
                inventoryIds.add(wrapper.inventoryId);
            }
            if (wrapper.needsPrimaryInvoiceName()
                && isRecordOf(wrapper.primaryInvoiceId, Invoice__c.SObjectType)) {
                invoiceIds.add(wrapper.primaryInvoiceId);
            }
        }

        Map<Id, Inventory__c> inventories = new Map<Id, Inventory__c>();
        if (!inventoryIds.isEmpty()) {
            try {
                inventories = new Map<Id, Inventory__c>(
                    [SELECT Id, Name FROM Inventory__c WHERE Id IN :inventoryIds WITH USER_MODE]);
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Inventory name lookup failed: ' + e.getMessage());
            }
        }

        Map<Id, String> invoiceNames = invoiceNames(invoiceIds);

        for (InventoryAdjustmentWrapper wrapper : wrappers) {
            if (wrapper.needsInventoryName() && inventories.containsKey(wrapper.inventoryId)) {
                wrapper.inventoryName = inventories.get(wrapper.inventoryId).Name;
            }
            if (wrapper.needsPrimaryInvoiceName() && invoiceNames.containsKey(wrapper.primaryInvoiceId)) {
                wrapper.primaryInvoiceName = invoiceNames.get(wrapper.primaryInvoiceId);
            }
        }
    }

    /**
     * Test seam: Invoice names by Id, used in place of the Invoice__c query when
     * set. Tests name invoices without inserting Invoice__c records - whose
     * triggers are not always deployable alongside this class (on 2026-10-06 a
     * handler deploy left InvoiceTrigger unable to compile, and every test that
     * inserted an Invoice failed with it).
     */
    @TestVisible
    private static Map<Id, String> invoiceNamesOverride;

    /** Invoice__c.Name by Id, for the Invoices the user can read. */
    private static Map<Id, String> invoiceNames(Set<Id> invoiceIds) {
        Map<Id, String> names = new Map<Id, String>();
        if (invoiceIds.isEmpty()) {
            return names;
        }
        if (invoiceNamesOverride != null) {
            for (Id invoiceId : invoiceIds) {
                if (invoiceNamesOverride.containsKey(invoiceId)) {
                    names.put(invoiceId, invoiceNamesOverride.get(invoiceId));
                }
            }
            return names;
        }
        try {
            for (Invoice__c invoice : [
                SELECT Id, Name FROM Invoice__c WHERE Id IN :invoiceIds WITH USER_MODE
            ]) {
                names.put(invoice.Id, invoice.Name);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Invoice name lookup failed: ' + e.getMessage());
        }
        return names;
    }

    /**
     * Source 3: the names on the Inventory Adjustment itself, for archived records
     * still in the org (soft-archived, not yet hard-deleted).
     */
    private static void namesFromLiveAdjustment(List<InventoryAdjustmentWrapper> wrappers) {
        Set<Id> adjustmentIds = new Set<Id>();
        for (InventoryAdjustmentWrapper wrapper : wrappers) {
            // Any unnamed Inventory, even with no archived Id: the live record's
            // formula may still know it.
            if ((String.isBlank(wrapper.inventoryName) || wrapper.needsPrimaryInvoiceName())
                && isRecordOf(wrapper.adjustmentId, Inventory_Adjustment__c.SObjectType)) {
                adjustmentIds.add(wrapper.adjustmentId);
            }
        }
        if (adjustmentIds.isEmpty()) {
            return;
        }

        Map<Id, Inventory_Adjustment__c> adjustments = new Map<Id, Inventory_Adjustment__c>();
        try {
            adjustments = new Map<Id, Inventory_Adjustment__c>([
                SELECT Id, Inventory_Name__c, Primary_Invoice_transaction__r.Name
                FROM Inventory_Adjustment__c
                WHERE Id IN :adjustmentIds
                WITH USER_MODE
            ]);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Inventory Adjustment lookup failed: ' + e.getMessage());
        }

        for (InventoryAdjustmentWrapper wrapper : wrappers) {
            Inventory_Adjustment__c adjustment = wrapper.adjustmentId == null
                ? null
                : adjustments.get(wrapper.adjustmentId);
            if (adjustment == null) {
                continue;
            }
            if (String.isBlank(wrapper.inventoryName) && String.isNotBlank(adjustment.Inventory_Name__c)) {
                wrapper.inventoryName = adjustment.Inventory_Name__c;
            }
            if (String.isBlank(wrapper.primaryInvoiceName)
                && adjustment.Primary_Invoice_transaction__r != null
                && String.isNotBlank(adjustment.Primary_Invoice_transaction__r.Name)) {
                wrapper.primaryInvoiceName = adjustment.Primary_Invoice_transaction__r.Name;
            }
        }
    }

    private static Boolean isRecordOf(Id recordId, Schema.SObjectType sobjType) {
        if (recordId == null) {
            return false;
        }
        try {
            return recordId.getSObjectType() == sobjType;
        } catch (Exception e) {
            // A key prefix this org does not know.
            return false;
        }
    }

    /**
     * A field from an archived record, matched case-insensitively: the first
     * casing that carries a value.
     *
     * The report selects some fields in both casings, and Table Storage answers a
     * selected property an entity lacks with an explicit null - so a row comes back
     * with Inventory__c = null AND inventory__c = 'a0Q...'. Taking the first key
     * that matches would return that null and lose the real value.
     */
    private static Object archivedValue(Map<String, Object> source, String fieldName) {
        Object value = source.get(fieldName);
        if (value != null && String.isNotBlank(String.valueOf(value))) {
            return value;
        }
        for (String key : source.keySet()) {
            Object candidate = source.get(key);
            if (key.equalsIgnoreCase(fieldName)
                && candidate != null && String.isNotBlank(String.valueOf(candidate))) {
                return candidate;
            }
        }
        return value;
    }

    /**
     * Sorts archive rows newest-first. The archive stores dates as ISO-8601
     * strings, which sort correctly lexicographically; nulls sort last either way.
     */
    private class ArchiveRow implements Comparable {
        private Map<String, Object> data;
        private String sortKey;

        private ArchiveRow(Map<String, Object> data, Object sortValue) {
            this.data = data;
            this.sortKey = sortValue == null ? null : String.valueOf(sortValue);
        }

        public Integer compareTo(Object other) {
            String otherKey = ((ArchiveRow) other).sortKey;
            if (sortKey == otherKey) {
                return 0;
            }
            if (sortKey == null) {
                return 1;
            }
            if (otherKey == null) {
                return -1;
            }
            return otherKey.compareTo(sortKey);
        }
    }

    // ---------------------------------------------------------------- lookup names

    /**
     * Turns the archived values on this page into what a person reads: lookup Ids
     * become names, Time values become 12-hour clock times. Display only - it runs
     * after the read and any parent-search matching, so it changes nothing about
     * which rows are found.
     */
    private static void presentRows(String objectApiName, ReportPage page) {
        if (page.rows.isEmpty()) {
            return;
        }
        formatTimeColumns(page);
        resolveLookupNames(objectApiName, page);
        mapInventoryAdjustmentNames(objectApiName, page);
    }

    /**
     * Diagnostic, for Anonymous Apex - read-only. Runs the report's own first-page
     * read, then says, column by column, which values are still record Ids after
     * the name lookups ran, what object those Ids belong to, how many of them
     * exist in THIS org, and how many the running user can see.
     *
     *   System.debug(ArchivedRecordsController.diagnoseDisplay(
     *       'Inventory_Adjustment__c', '2026-09-01', '2026-09-30'));
     *
     * Ids that do not exist here mean the archive was written from a different
     * org (a sandbox reading production's archive); no lookup can name those.
     */
    public static String diagnoseDisplay(String objectApiName, String fromDate, String toDate) {
        List<String> lines = new List<String>();
        Azure_Archive_Config__mdt cfg = configFor(objectApiName);
        lines.add('Object: ' + objectApiName);
        lines.add('Report_Columns__c: '
            + (cfg == null || String.isBlank(cfg.Report_Columns__c)
                ? '(blank - code defaults in use)'
                : cfg.Report_Columns__c + '   <-- overrides the code\'s column list'));

        ReportPage page = searchArchivedRecords(
            objectApiName, fromDate, toDate, DEFAULT_PAGE_SIZE, 1, null, null);
        Map<String, String> keys = cachedArchiveKeys(objectApiName);
        lines.add('Archive field names in use: '
            + (keys == null ? '(verified casing, not detected)' : String.valueOf(keys)));
        if (lastLookupError != null) {
            lines.add('Lookup error during the page read: ' + lastLookupError);
        }
        lines.add('Rows on page 1: ' + page.rows.size()
            + (page.degraded ? ' (Archival Log fallback - no lookups run)' : ''));

        for (ReportColumn col : page.columns) {
            Map<Schema.SObjectType, Set<Id>> idsByType = new Map<Schema.SObjectType, Set<Id>>();
            Integer blanks = 0;
            for (Map<String, Object> row : page.rows) {
                Object value = row.get(col.fieldName);
                if (value == null || String.isBlank(String.valueOf(value))) {
                    blanks++;
                    continue;
                }
                Id recordId = asRecordId(value);
                if (recordId == null) {
                    continue;
                }
                Schema.SObjectType sobjType;
                try {
                    sobjType = recordId.getSObjectType();
                } catch (Exception e) {
                    sobjType = null;
                }
                if (sobjType == null) {
                    continue;
                }
                if (!idsByType.containsKey(sobjType)) {
                    idsByType.put(sobjType, new Set<Id>());
                }
                idsByType.get(sobjType).add(recordId);
            }

            String line = '- ' + col.label + ' [' + col.fieldName + ']'
                + (col.isTime == true ? ' time' : '')
                + ': blank in ' + blanks + '/' + page.rows.size() + ' rows';
            if (idsByType.isEmpty()) {
                lines.add(line + '; no Ids left');
                continue;
            }
            for (Schema.SObjectType sobjType : idsByType.keySet()) {
                Set<Id> ids = idsByType.get(sobjType);
                String typeName = sobjType.getDescribe().getName();
                Integer found = 0;
                try {
                    // Runs with the user's sharing, so this is what the user can see.
                    found = Database.countQuery(
                        'SELECT COUNT() FROM ' + typeName + ' WHERE Id IN :ids');
                } catch (Exception e) {
                    line += '; ' + typeName + ' query failed: ' + e.getMessage();
                    continue;
                }
                String displayField = displayFieldFor(sobjType, null);
                line += '; STILL IDS: ' + ids.size() + ' distinct ' + typeName
                    + ' Id(s), ' + found + ' of them found in this org'
                    + ', object readable: ' + sobjType.getDescribe().isAccessible()
                    + ', display field: ' + displayField;
                if (displayField != null) {
                    // The exact query the page runs, so its outcome is not guessed.
                    lastLookupError = null;
                    Integer named = fetchDisplayValues(typeName, displayField, ids).size();
                    line += ', lookup query returned ' + named
                        + (lastLookupError == null ? '' : ' (ERROR ' + lastLookupError + ')');
                }
            }
            lines.add(line);
        }
        return String.join(lines, '\n');
    }

    /** Rewrites every Time column's values as 12-hour clock times. */
    private static void formatTimeColumns(ReportPage page) {
        for (ReportColumn col : page.columns) {
            if (col.isTime != true) {
                continue;
            }
            for (Map<String, Object> row : page.rows) {
                Object value = row.get(col.fieldName);
                if (value != null) {
                    row.put(col.fieldName, formatTime12h(String.valueOf(value)));
                }
            }
        }
    }

    /**
     * '09:28:04.000Z' -> '9:28 AM', '13:12:00.000Z' -> '1:12 PM'.
     *
     * Salesforce Time fields carry no time zone - the trailing Z is only how they
     * serialise - so the clock reading is kept exactly as stored, the same way
     * Salesforce itself displays a Time field. Anything that is not a readable
     * time is returned unchanged rather than guessed at.
     */
    @TestVisible
    private static String formatTime12h(String value) {
        if (String.isBlank(value)) {
            return value;
        }
        Matcher parts = TIME_VALUE.matcher(value.trim());
        if (!parts.find()) {
            return value;
        }
        Integer hours = Integer.valueOf(parts.group(1));
        Integer minutes = Integer.valueOf(parts.group(2));
        if (hours > 23 || minutes > 59) {
            return value;
        }
        Integer clockHour = Math.mod(hours, 12) == 0 ? 12 : Math.mod(hours, 12);
        return clockHour + ':' + parts.group(2) + (hours < 12 ? ' AM' : ' PM');
    }

    /**
     * Replaces archived lookup Ids with the related record's name (or its
     * LOOKUP_DISPLAY_FIELDS field), for the rows on this page.
     *
     * Two kinds of column are resolved:
     *  - the columns listed in LOOKUP_NAME_COLUMNS for this object, whatever
     *    they point at;
     *  - on every object, any column holding User Ids - User, Created By, Last
     *    Modified By, Owner - shown as the user's name.
     *
     * The related object is read from each Id's own key prefix, so this works
     * whatever a lookup points at, even for a field the org has since dropped.
     * All Ids on the page are gathered first and each related object (and
     * display field) is queried once for the whole page - never per row or per
     * column - in user mode (WITH USER_MODE). A value the user may not
     * see, or whose record has since been deleted, keeps showing its Id, as before.
     */
    private static void resolveLookupNames(String objectApiName, ReportPage page) {
        Set<String> configured = LOOKUP_NAME_COLUMNS.containsKey(objectApiName)
            ? LOOKUP_NAME_COLUMNS.get(objectApiName)
            : new Set<String>();
        Map<String, String> displayFields = LOOKUP_DISPLAY_FIELDS.containsKey(objectApiName)
            ? LOOKUP_DISPLAY_FIELDS.get(objectApiName)
            : new Map<String, String>();

        LookupContext ctx = new LookupContext();

        // Pass 1: gather every Id to look up, grouped by related object + field.
        Map<String, Set<Id>> idsByLookup = new Map<String, Set<Id>>();
        for (ReportColumn col : page.columns) {
            if (col.fieldName == null || col.fieldName == OBJECT_COLUMN) {
                continue;
            }
            String entry = configuredEntry(col, configured);
            String preferredField = entry == null ? null : displayFields.get(entry);
            for (Map<String, Object> row : page.rows) {
                Id recordId = asRecordId(row.get(col.fieldName));
                String lookupKey = lookupKeyFor(ctx, recordId, entry != null, preferredField);
                if (lookupKey == null) {
                    continue;
                }
                if (!idsByLookup.containsKey(lookupKey)) {
                    idsByLookup.put(lookupKey, new Set<Id>());
                }
                idsByLookup.get(lookupKey).add(recordId);
            }
        }
        if (idsByLookup.isEmpty()) {
            return;
        }

        // One query per related object + field.
        Map<String, Map<String, String>> valuesByLookup = new Map<String, Map<String, String>>();
        for (String lookupKey : idsByLookup.keySet()) {
            List<String> parts = lookupKey.split('\\|');
            valuesByLookup.put(
                lookupKey, fetchDisplayValues(parts[0], parts[1], idsByLookup.get(lookupKey)));
        }

        // Pass 2: replace each Id that came back with its value.
        for (ReportColumn col : page.columns) {
            if (col.fieldName == null || col.fieldName == OBJECT_COLUMN) {
                continue;
            }
            String entry = configuredEntry(col, configured);
            String preferredField = entry == null ? null : displayFields.get(entry);
            for (Map<String, Object> row : page.rows) {
                Id recordId = asRecordId(row.get(col.fieldName));
                String lookupKey = lookupKeyFor(ctx, recordId, entry != null, preferredField);
                if (lookupKey == null) {
                    continue;
                }
                Map<String, String> values = valuesByLookup.get(lookupKey);
                String id18 = String.valueOf(recordId);
                if (values != null && values.containsKey(id18)) {
                    row.put(col.fieldName, values.get(id18));
                }
            }
        }
    }

    /** Describe results reused across every cell of one page. */
    private class LookupContext {
        private final Map<Schema.SObjectType, String> typeNames = new Map<Schema.SObjectType, String>();
        private final Map<String, String> displayFieldCache = new Map<String, String>();
    }

    /**
     * 'Object|Field' to look this Id up by, or null when it is not to be looked
     * up: not an Id, a non-User Id in a column that is not configured, or an
     * object/field the user cannot read.
     */
    private static String lookupKeyFor(
        LookupContext ctx,
        Id recordId,
        Boolean configuredColumn,
        String preferredField
    ) {
        if (recordId == null) {
            return null;
        }
        Schema.SObjectType sobjType;
        try {
            sobjType = recordId.getSObjectType();
        } catch (Exception e) {
            return null;
        }
        if (sobjType == null || (!configuredColumn && sobjType != User.SObjectType)) {
            return null;
        }
        if (!ctx.typeNames.containsKey(sobjType)) {
            ctx.typeNames.put(sobjType, sobjType.getDescribe().getName());
        }
        String typeName = ctx.typeNames.get(sobjType);

        String cacheKey = typeName + '|' + (preferredField == null ? '' : preferredField);
        if (!ctx.displayFieldCache.containsKey(cacheKey)) {
            ctx.displayFieldCache.put(cacheKey, displayFieldFor(sobjType, preferredField));
        }
        String field = ctx.displayFieldCache.get(cacheKey);
        return field == null ? null : typeName + '|' + field;
    }

    /**
     * The field to show for a related record: preferredField when the object has
     * it and the user can read it, else the object's name field, else null.
     */
    @TestVisible
    private static String displayFieldFor(Schema.SObjectType sobjType, String preferredField) {
        Schema.DescribeSObjectResult related = sobjType.getDescribe();
        if (!related.isAccessible() || !related.isQueryable()) {
            return null;
        }
        Map<String, Schema.SObjectField> fieldMap = related.fields.getMap();
        if (String.isNotBlank(preferredField) && fieldMap.containsKey(preferredField)) {
            Schema.DescribeFieldResult preferred = fieldMap.get(preferredField).getDescribe();
            if (preferred.isAccessible()) {
                return preferred.getName();
            }
        }
        for (Schema.SObjectField field : fieldMap.values()) {
            Schema.DescribeFieldResult dfr = field.getDescribe();
            if (dfr.isNameField()) {
                return dfr.isAccessible() ? dfr.getName() : null;
            }
        }
        return null;
    }

    /**
     * Record Id (18-character) to display value, for records the user can read.
     * Empty on any error - the caller then shows the Ids unchanged.
     */
    private static Map<String, String> fetchDisplayValues(String typeName, String field, Set<Id> ids) {
        Map<String, String> values = new Map<String, String>();
        try {
            for (SObject rec : Database.query(
                'SELECT Id, ' + field + ' FROM ' + typeName
                + ' WHERE Id IN :ids WITH USER_MODE'
            )) {
                Object value = rec.get(field);
                if (value != null) {
                    values.put(String.valueOf(rec.Id), String.valueOf(value));
                }
            }
        } catch (Exception e) {
            lastLookupError = typeName + '.' + field + ': ' + e.getMessage();
            System.debug(LoggingLevel.WARN, 'Lookup of ' + lastLookupError);
        }
        return values;
    }

    /** The most recent lookup failure in this transaction, for diagnoseDisplay. */
    private static String lastLookupError;

    /** The LOOKUP_NAME_COLUMNS entry a column matches, by field name or heading. */
    private static String configuredEntry(ReportColumn col, Set<String> configured) {
        if (configured.isEmpty()) {
            return null;
        }
        String byField = col.fieldName == null ? null : col.fieldName.toLowerCase();
        if (byField != null && configured.contains(byField)) {
            return byField;
        }
        String byLabel = col.label == null ? null : col.label.trim().toLowerCase();
        if (byLabel != null && configured.contains(byLabel)) {
            return byLabel;
        }
        return null;
    }

    /** A cell's value as a record Id, or null when it is not one. */
    private static Id asRecordId(Object value) {
        if (value == null) {
            return null;
        }
        String id18 = toId18(String.valueOf(value));
        return id18 == null ? null : Id.valueOf(id18);
    }

    // ---------------------------------------------------------------- parent filter

    /**
     * Turns what the user typed into a filter the archive rows can be tested
     * against, or explains why it cannot.
     *
     * A name or number is matched against the child's own copy of it -
     * Order_Name__c, Invoice_Number__c, Visit_Name__c - as archived, so no query
     * against the parent is needed and a parent that has itself been archived is
     * still found. A term that is a record Id (15 or 18 characters) is also matched
     * against the lookup; both are tried because a 15-character order number is a
     * valid-looking Id too.
     */
    private static ParentFilter buildParentFilter(String objectApiName, String rawTerm) {
        ParentSearchConfig cfg = PARENT_SEARCH.get(objectApiName);
        if (cfg == null) {
            throw new AuraHandledException(
                describeLabel(objectApiName) + ' cannot be searched by a parent record.');
        }

        String term = rawTerm == null ? '' : rawTerm.trim();
        if (term.length() < MIN_PARENT_SEARCH_LENGTH) {
            throw new AuraHandledException(
                'Enter at least ' + MIN_PARENT_SEARCH_LENGTH + ' characters of the '
                + cfg.label + ' name, number or record Id.');
        }
        if (term.length() > MAX_PARENT_SEARCH_LENGTH) {
            throw new AuraHandledException(
                'The ' + cfg.label + ' search is limited to ' + MAX_PARENT_SEARCH_LENGTH
                + ' characters.');
        }

        Map<String, Schema.SObjectField> fieldMap =
            Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap();

        ParentFilter filter = new ParentFilter(cfg.label, term);

        // The name/number fields. One the user cannot read is an FLS failure, not
        // something to skip silently; one absent from the org schema is still
        // matched, since the archive can hold fields the org no longer has.
        for (String apiName : cfg.textFields) {
            Schema.SObjectField field = fieldMap.get(apiName);
            if (field != null && !field.getDescribe().isAccessible()) {
                throw new AuraHandledException(
                    'You do not have access to the ' + field.getDescribe().getLabel() + ' field on '
                    + describeLabel(objectApiName) + ', which the ' + cfg.label + ' search uses.');
            }
            filter.textApiNames.add(field == null ? apiName : field.getDescribe().getName());
        }

        String asId = toId18(term);
        if (asId != null) {
            ResolvedField lookup = resolveField(
                objectApiName, cfg.lookupField, fieldMap,
                fieldMap.containsKey(cfg.lookupField) ? null : indexByLabel(fieldMap));
            if (lookup != null && lookup.describe.isAccessible()) {
                filter.lookupApiName = lookup.describe.getName();
                filter.recordIds.add(asId);
            }
        }
        return filter;
    }

    /**
     * Points a parent filter at this object's archive field names. Separate from
     * buildParentFilter because an unverified archive's casing is only known once
     * prepareArchiveNames has run.
     */
    private static void bindParentFilter(ParentFilter filter, String objectApiName) {
        filter.idFields.clear();
        filter.textFields.clear();
        if (filter.lookupApiName != null && !filter.recordIds.isEmpty()) {
            filter.idFields.add(archiveNameFor(objectApiName, filter.lookupApiName));
        }
        for (String apiName : filter.textApiNames) {
            filter.textFields.add(archiveNameFor(objectApiName, apiName));
        }
    }

    /**
     * The 18-character form of a record Id, or null when the value is not one.
     * 15-character Ids are case-sensitive, so values are compared in this form
     * rather than by lower-casing them.
     */
    private static String toId18(String value) {
        if (value == null) {
            return null;
        }
        String candidate = value.trim();
        if ((candidate.length() != 15 && candidate.length() != 18) || !candidate.isAlphanumeric()) {
            return null;
        }
        try {
            return String.valueOf(Id.valueOf(candidate));
        } catch (Exception e) {
            return null;
        }
    }

    // ---------------------------------------------------------------- log fallback

    /**
     * Fallback when the archive gateway exposes no read operation. Archival_Log__c
     * is the in-org audit index written at archive time, so it can still answer
     * "what left the org, when, and where did it go" - just without field detail.
     *
     * Every selected object lives in the same table here, so one query serves the
     * whole page and the ordering is genuinely global rather than object-major.
     */
    /**
     * Row count from the in-org index, for the degraded path. Exact, unlike the
     * archive count - but it counts log rows, and logging has been disabled in the
     * archival batch since before most of the archive was written, so this number
     * is a floor on reality by a wide margin. The caller flags it as degraded.
     */
    private static Integer countFromArchivalLog(
        List<String> objects,
        Date fromDate,
        Date toDate,
        String dateBasis
    ) {
        if (!Schema.SObjectType.Archival_Log__c.isAccessible()) {
            throw new AuraHandledException(
                'The archive read endpoint is unavailable and you do not have access to the '
                + 'Archival Log fallback. Contact your administrator.');
        }

        Datetime fromTs = fromDate == null
            ? null : Datetime.newInstance(fromDate, Time.newInstance(0, 0, 0, 0));
        Datetime toTs = toDate == null
            ? null : Datetime.newInstance(toDate.addDays(1), Time.newInstance(0, 0, 0, 0));

        String logDateField = logDateField(dateBasis);
        String whereClause = ' WHERE Archived_Object__c IN :objects';
        if (fromTs != null) {
            whereClause += ' AND ' + logDateField + ' >= :fromTs';
        }
        if (toTs != null) {
            whereClause += ' AND ' + logDateField + ' < :toTs';
        }

        return Database.countQuery('SELECT COUNT() FROM Archival_Log__c' + whereClause);
    }

    private static ReportPage readFromArchivalLog(
        List<String> objects,
        Date fromDate,
        Date toDate,
        Integer pageSize,
        Integer globalOffset,
        String dateBasis
    ) {
        ReportPage page = new ReportPage();
        page.degraded = true;
        page.degradedReason =
            'Showing the in-org Archival Log index: the Azure archive has no read '
            + 'route for the selected object, so field-level detail is not available. '
            + 'Set Azure_Archive_Config__mdt.Read_Path__c / Read_Named_Credential__c once '
            + 'Azure publishes a retrieval operation for this object.';

        if (!Schema.SObjectType.Archival_Log__c.isAccessible()) {
            throw new AuraHandledException(
                'The archive read endpoint is unavailable and you do not have access to the '
                + 'Archival Log fallback. Contact your administrator.');
        }

        page.columns = buildLogColumns();

        Datetime fromTs = fromDate == null ? null : Datetime.newInstance(fromDate, Time.newInstance(0, 0, 0, 0));
        Datetime toTs = toDate == null ? null : Datetime.newInstance(toDate.addDays(1), Time.newInstance(0, 0, 0, 0));

        String logDateField = logDateField(dateBasis);
        String whereClause = ' WHERE Archived_Object__c IN :objects';
        if (fromTs != null) {
            whereClause += ' AND ' + logDateField + ' >= :fromTs';
        }
        if (toTs != null) {
            whereClause += ' AND ' + logDateField + ' < :toTs';
        }

        page.totalCount = Database.countQuery('SELECT COUNT() FROM Archival_Log__c' + whereClause);

        Integer offsetSize = globalOffset > MAX_SOQL_OFFSET ? MAX_SOQL_OFFSET : globalOffset;

        String recordQuery =
            'SELECT Id, Archived_Object__c, ' + String.join(LOG_COLUMNS, ', ') +
            ' FROM Archival_Log__c' + whereClause +
            ' ORDER BY ' + logDateField + ' DESC NULLS LAST, Id DESC' +
            ' LIMIT :pageSize OFFSET :offsetSize';

        for (Archival_Log__c logRow : (List<Archival_Log__c>) Database.query(recordQuery)) {
            Map<String, Object> row = new Map<String, Object>();
            for (String fieldName : LOG_COLUMNS) {
                row.put(fieldName, logRow.get(fieldName));
            }
            row.put(OBJECT_COLUMN, describeLabel(logRow.Archived_Object__c));
            row.put('_rowKey', logRow.Id);
            page.rows.add(row);
        }

        return page;
    }

    // ---------------------------------------------------------------- columns

    /**
     * Column set for an archive-sourced page. With one object selected this is that
     * object's configured columns. With several, it narrows to the fields they all
     * share - a union would produce a wide, mostly empty table.
     */
    private static List<ReportColumn> buildColumns(
        List<String> objects, Map<String, Azure_Archive_Config__mdt> configs, ReportPage page
    ) {
        List<ReportColumn> columns = new List<ReportColumn>();
        columns.add(objectColumn());

        List<String> requested = requestedFields(objects[0], configs.get(objects[0]));

        if (objects.size() > 1) {
            Integer before = requested.size();
            for (Integer i = 1; i < objects.size(); i++) {
                Set<String> other = new Set<String>(
                    requestedFields(objects[i], configs.get(objects[i])));
                List<String> intersection = new List<String>();
                for (String fieldName : requested) {
                    if (other.contains(fieldName)) {
                        intersection.add(fieldName);
                    }
                }
                requested = intersection;
            }
            if (requested.isEmpty()) {
                // Two objects whose archives disagree about casing share no field
                // names at all, so the intersection empties. Fall back to the
                // first object's own naming rather than a hardcoded pair that may
                // belong to neither.
                ArchiveNaming naming = namingFor(objects[0]);
                requested = new List<String>{ naming.nameField, naming.createdDateField };
            }
            page.columnsNarrowed = requested.size() < before;
        }

        // The surviving fields exist on every selected object, so describing them
        // against the first is enough to build labels and types.
        columns.addAll(describeColumns(objects[0], requested));

        return columns;
    }

    private static List<String> requestedFields(String objectApiName, Azure_Archive_Config__mdt cfg) {
        List<String> requested = new List<String>();

        if (cfg != null && String.isNotBlank(cfg.Report_Columns__c)) {
            for (String raw : cfg.Report_Columns__c.split(',')) {
                if (String.isNotBlank(raw)) {
                    requested.add(raw.trim());
                }
            }
        }
        if (requested.isEmpty() && DEFAULT_COLUMNS.containsKey(objectApiName)) {
            requested = new List<String>(DEFAULT_COLUMNS.get(objectApiName));
        }
        if (requested.isEmpty()) {
            requested = new List<String>{ 'Name', 'CreatedDate' };
        }
        return requested;
    }

    private static List<ReportColumn> describeColumns(String objectApiName, List<String> fieldNames) {
        Map<String, Schema.SObjectField> fieldMap =
            Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap();
        // Built only if some entry is not an API name, since it describes every field.
        Map<String, Schema.SObjectField> byLabel;

        Map<String, String> labelOverrides = COLUMN_LABELS.get(objectApiName);
        Map<String, String> exactNames = EXACT_ARCHIVE_FIELDS.get(objectApiName);

        List<ReportColumn> columns = new List<ReportColumn>();
        Set<String> added = new Set<String>();
        for (String token : fieldNames) {
            if (byLabel == null && !fieldMap.containsKey(token)) {
                byLabel = indexByLabel(fieldMap);
            }
            String tokenKey = String.isBlank(token) ? null : token.trim().toLowerCase();
            String labelOverride = (labelOverrides == null || tokenKey == null)
                ? null
                : labelOverrides.get(tokenKey);
            String exactName = (exactNames == null || tokenKey == null)
                ? null
                : exactNames.get(tokenKey);

            ResolvedField resolved = resolveField(objectApiName, token, fieldMap, byLabel);
            if (resolved != null && exactName != null) {
                resolved = new ResolvedField(exactName, resolved.describe);
            }
            if (resolved == null) {
                if (labelOverride != null || exactName != null) {
                    // Archive-only field: shown as text under its agreed heading.
                    String archiveName = exactName != null
                        ? exactName
                        : (ARCHIVE_NAMING.containsKey(objectApiName)
                            ? token
                            : archiveNameFor(objectApiName, token));
                    if (!added.contains(archiveName)) {
                        added.add(archiveName);
                        ReportColumn col = new ReportColumn();
                        col.fieldName = archiveName;
                        col.label = labelOverride != null ? labelOverride : token;
                        col.type = 'text';
                        columns.add(col);
                    }
                    continue;
                }
                System.debug(LoggingLevel.WARN,
                    'Report column "' + token + '" matches no field on ' + objectApiName);
                continue;
            }
            // Two entries can name the same field (an API name and its label).
            if (!resolved.describe.isAccessible() || added.contains(resolved.archiveName)) {
                continue;
            }
            added.add(resolved.archiveName);

            ReportColumn col = new ReportColumn();
            col.fieldName = resolved.archiveName;
            col.label = labelOverride != null ? labelOverride : resolved.describe.getLabel();
            col.type = toDatatableType(resolved.describe.getType());
            col.isTime = resolved.describe.getType() == Schema.DisplayType.TIME;
            columns.add(col);
        }
        return columns;
    }

    /**
     * Resolves a column entry to a field and the name the archive stores it under.
     *
     * An API name keeps the casing it was written in - NOT dfr.getName(). Describe
     * resolves names case-insensitively and hands back Salesforce's own casing, so
     * taking it would turn a lower-case archive field into a PascalCase column that
     * matches nothing in the row - a full table of blanks, with no error anywhere
     * to explain it. A label resolves to the field's API name in the casing the
     * object's archive uses (see ARCHIVE_NAMING).
     */
    private static ResolvedField resolveField(
        String objectApiName,
        String token,
        Map<String, Schema.SObjectField> fieldMap,
        Map<String, Schema.SObjectField> byLabel
    ) {
        if (String.isBlank(token)) {
            return null;
        }
        Schema.SObjectField field = fieldMap.get(token);
        if (field != null) {
            // Verified archives keep the entry's own casing, exactly as before;
            // the others take the casing detected from the archive itself.
            String archiveName = ARCHIVE_NAMING.containsKey(objectApiName)
                ? token
                : archiveNameFor(objectApiName, token);
            return new ResolvedField(archiveName, field.getDescribe());
        }
        if (byLabel == null) {
            return null;
        }
        field = byLabel.get(normaliseLabel(token));
        if (field == null) {
            return null;
        }
        Schema.DescribeFieldResult dfr = field.getDescribe();
        return new ResolvedField(archiveNameFor(objectApiName, dfr.getName()), dfr);
    }

    /** Fields keyed by normalised label. The first field with a given label wins. */
    private static Map<String, Schema.SObjectField> indexByLabel(Map<String, Schema.SObjectField> fieldMap) {
        Map<String, Schema.SObjectField> byLabel = new Map<String, Schema.SObjectField>();
        for (Schema.SObjectField field : fieldMap.values()) {
            String key = normaliseLabel(field.getDescribe().getLabel());
            if (!byLabel.containsKey(key)) {
                byLabel.put(key, field);
            }
        }
        return byLabel;
    }

    /** Case-, whitespace- and apostrophe-insensitive, so "Retailer’s Address" matches. */
    private static String normaliseLabel(String label) {
        return label == null
            ? ''
            : label.replace('’', '\'').normalizeSpace().toLowerCase();
    }

    private static List<ReportColumn> buildLogColumns() {
        List<ReportColumn> columns = new List<ReportColumn>();
        columns.add(objectColumn());

        Map<String, Schema.SObjectField> fieldMap =
            Archival_Log__c.SObjectType.getDescribe().fields.getMap();

        for (String fieldName : LOG_COLUMNS) {
            Schema.SObjectField field = fieldMap.get(fieldName);
            if (field == null) {
                continue;
            }
            Schema.DescribeFieldResult dfr = field.getDescribe();
            if (!dfr.isAccessible()) {
                continue;
            }

            ReportColumn col = new ReportColumn();
            col.fieldName = fieldName;
            col.label = dfr.getLabel();
            col.type = toDatatableType(dfr.getType());
            columns.add(col);
        }

        return columns;
    }

    private static ReportColumn objectColumn() {
        ReportColumn col = new ReportColumn();
        col.fieldName = OBJECT_COLUMN;
        col.label = 'Object';
        col.type = 'text';
        return col;
    }

    private static String toDatatableType(Schema.DisplayType dt) {
        switch on dt {
            when CURRENCY {
                return 'currency';
            }
            when PERCENT {
                return 'percent';
            }
            when DOUBLE, INTEGER, LONG {
                return 'number';
            }
            when DATE {
                return 'date-local';
            }
            when DATETIME {
                return 'date';
            }
            when BOOLEAN {
                return 'boolean';
            }
            when EMAIL {
                return 'email';
            }
            when PHONE {
                return 'phone';
            }
            when URL {
                return 'url';
            }
            when else {
                return 'text';
            }
        }
    }

    // ---------------------------------------------------------------- helpers

    /** Validates, de-duplicates and preserves the caller's object ordering. */
    private static List<String> validateObjects(List<String> requested) {
        if (requested == null || requested.isEmpty()) {
            throw new AuraHandledException('Select at least one object before running the report.');
        }

        List<String> resolved = new List<String>();
        Set<String> seen = new Set<String>();

        for (String raw : requested) {
            if (String.isBlank(raw)) {
                continue;
            }
            String objectApiName = raw.trim();
            if (seen.contains(objectApiName)) {
                continue;
            }
            seen.add(objectApiName);

            Schema.SObjectType sobjType = Schema.getGlobalDescribe().get(objectApiName);
            if (sobjType == null) {
                throw new AuraHandledException('Unknown object: ' + objectApiName);
            }
            if (!sobjType.getDescribe().isAccessible()) {
                throw new AuraHandledException(
                    'You do not have read access to ' + sobjType.getDescribe().getLabel() + '.');
            }
            resolved.add(objectApiName);
        }

        if (resolved.isEmpty()) {
            throw new AuraHandledException('Select at least one object before running the report.');
        }
        return resolved;
    }

    private static String describeLabel(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return '';
        }
        Schema.SObjectType sobjType = Schema.getGlobalDescribe().get(objectApiName);
        return sobjType == null ? objectApiName : sobjType.getDescribe().getLabelPlural();
    }

    /**
     * Custom Metadata SOQL does not support disjunctions, and the config table is
     * tiny, so every row is read once and resolved to its object in memory.
     */
    private static Map<String, Azure_Archive_Config__mdt> loadConfigs(List<String> objects) {
        Set<String> wanted = new Set<String>(objects);
        Map<String, Azure_Archive_Config__mdt> byObject = new Map<String, Azure_Archive_Config__mdt>();

        for (Azure_Archive_Config__mdt cfg : [
            SELECT MasterLabel, DeveloperName, Object_API_Name__c, Read_Path__c,
                   Read_Named_Credential__c, Report_Columns__c
            FROM Azure_Archive_Config__mdt
        ]) {
            String apiName = resolveObjectApiName(cfg);
            if (String.isNotBlank(apiName) && wanted.contains(apiName)) {
                byObject.put(apiName, cfg);
            }
        }

        return byObject;
    }

    private static Date parseDate(String value, String fieldLabel) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            // LWC lightning-input type="date" emits ISO yyyy-MM-dd.
            return Date.valueOf(value.substring(0, 10));
        } catch (Exception e) {
            throw new AuraHandledException(fieldLabel + ' is not a valid date.');
        }
    }

    private static Integer normalisePageSize(Integer requested) {
        if (requested == null || requested < 1) {
            return DEFAULT_PAGE_SIZE;
        }
        return requested > MAX_PAGE_SIZE ? MAX_PAGE_SIZE : requested;
    }

    private static Integer calcTotalPages(Integer totalCount, Integer pageSize) {
        if (totalCount == null || totalCount <= 0 || pageSize == null || pageSize <= 0) {
            return 0;
        }
        return (Integer) Math.ceil((Decimal) totalCount / pageSize);
    }

    private static String buildRowKey(Map<String, Object> source, String objectApiName, Integer rowIndex) {
        // Id / id / RowKey in turn: the id column is cased per object, and Table
        // Storage's own RowKey holds the record id whichever way it was written.
        for (String candidate : new List<String>{
            namingFor(objectApiName).idField, 'Id', 'id', 'RowKey'
        }) {
            Object recordId = source.get(candidate);
            if (recordId != null && String.isNotBlank(String.valueOf(recordId))) {
                return String.valueOf(recordId);
            }
        }
        return objectApiName + '-' + String.valueOf(rowIndex);
    }
}