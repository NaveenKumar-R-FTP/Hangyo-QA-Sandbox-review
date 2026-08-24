public without sharing class HangyoBulkSalesUploadController {
    private static final String UPLOAD_TYPE_ORDER = 'Order';
    private static final String UPLOAD_TYPE_INVOICE = 'Invoice';

    private static final String USER_ALLOW_BULK_FIELD = 'Allow_Bulk_Upload__c';
    private static final String RETAILER_CODE_FIELD = 'Retailer_Code__c';
    private static final String RETAILER_ACTIVE_FIELD = 'Is_Active__c';
    private static final String RETAILER_RECORD_TYPE_NAME = 'Retailer';
    private static final String PRODUCT_SOBJECT = 'Product__c';
    private static final String PRODUCT_CODE_FIELD = 'Product_Code__c';
    private static final String PRODUCT_ACTIVE_FIELD = 'IsActive__c';
    private static final String ORDER_SOBJECT = 'Order__c';
    private static final String ORDER_NUMBER_FIELD = 'Name';
    private static final String ORDER_NUMBER_FALLBACK_FIELD = 'Name';

    private static final String RETAILER_STATE_FIELD = 'Primary_State__c';
    private static final String PRICE_BOOK_SOBJECT = 'Price_Book__c';
    private static final String PRICE_BOOK_ENTRY_SOBJECT = 'Price_Book_Entry__c';       
    private static final String PRICE_BOOK_ACTIVE_FIELD = 'isActive__c';
    private static final String PRICE_BOOK_ENTRY_TYPE_RETAILER = 'Retailer';
    private static final String PRICE_BOOK_ENTRY_PTR_FIELD = 'PTR__c';
    private static final String TAX_SETTING_NAME = 'General GST Settings';

    private static final String DISCOUNT_SOBJECT = 'Discount__c';
    private static final String PRODUCT_MRP_FIELD = 'MRP__c';
    private static final String PRODUCT_PER_PIECES_FIELD = 'Per_Pieces__c';

    //Added by Hari - Order Record Creation
    private static final String ORDER_RECORD_TYPE_NAME = 'Secondary Order';
    private static final String ORDER_LINE_ITEM_RECORD_TYPE_NAME = 'Secondary Order Line Item';
    private static final String ORDER_LINE_ITEM_SOBJECT = 'Order_Line_Item__c';
    private static final String ORDER_TYPE_BULK_UPLOAD = 'Bulk Upload';
    private static final String ORDER_STATUS_PLACED = 'Order Placed';
    private static final String ORDER_REF_FIELD = 'Ref_Order_No_Data_Upload__c';
    private static final String ORDER_FILE_NAME_FIELD = 'File_Name__c';
    private static final String ORDER_DATA_UPLOAD_FIELD = 'Data_Upload__c';
    private static final String ORDER_BEATS_FIELD = 'Beats_Name__c';
    private static final String RETAILER_BEATS_SOURCE_FIELD = 'Beats_Name__c';
    private static final String RECEIVED_DOCUMENT_SOBJECT = 'ReceivedDocument';
    private static final String BULK_UPLOAD_DOCUMENT_SOURCE = 'Bulk Upload';

    //Added by Hari - Invoice Record Creation
    private static final String INVOICE_SOBJECT = 'Invoice__c';
    private static final String INVOICE_LINE_ITEM_SOBJECT = 'Invoice_Line_Item__c';
    private static final String INVOICE_RECORD_TYPE_NAME = 'Secondary Invoice';
    private static final String INVOICE_TYPE_BULK_UPLOAD = 'Bulk Upload';
    private static final String INVOICE_REF_FIELD = 'Ref_Invoice_No_Data_Upload__c';
    private static final String INVOICE_PAYMENT_STATUS_NOT_PAID = 'Not Paid';
    private static final String TAX_INFO_STATE_MATCH = 'State Tax Applied';
    private static final String TAX_INFO_CENTRAL =
        'Central Tax Applied.\n\nReason: Either eligible for Central Tax or State Tax not found';

    private static final Set<String> ALLOWED_INVOICE_STATUSES = new Set<String>{
        'DRAFT',
        'CONFIRMED'
    };
    private static final Integer ORDER_DATE_MAX_PAST_DAYS = 3;
    private static final String ORDER_TEMPLATE_STATIC_RESOURCE = 'Hangyo_Order_Bulk_Upload_Template';
    private static final String INVOICE_TEMPLATE_STATIC_RESOURCE = 'Hangyo_Invoice_Bulk_Upload_Template';

    // -------------------------------------------------------------------------
    // New Requirement — Duplicate Reference Handling
    // -------------------------------------------------------------------------
    private static final String ORDER_REF_FALLBACK_FIELD = 'Ref_Order_No_Data_Upload__c';
    private static final String INVOICE_REF_FALLBACK_FIELD = 'Ref_Invoice_No_Data_Upload__c';

    @AuraEnabled
    public static BulkUploadTemplateResult downloadUploadTemplate(String uploadType) {
        try {
            validateUploadType(uploadType);
            checkUserAccess();
    
            String resourceName = UPLOAD_TYPE_ORDER.equalsIgnoreCase(uploadType)
                ? ORDER_TEMPLATE_STATIC_RESOURCE
                : INVOICE_TEMPLATE_STATIC_RESOURCE;
    
            List<StaticResource> resources = [
                SELECT Body FROM StaticResource WHERE Name = :resourceName LIMIT 1
            ];
    
            if (resources.isEmpty() || resources[0].Body == null) {
                throwAuraHandledException(
                    'Bulk upload format template is not configured. Contact your Hangyo administrator.'
                );
            }
    
            BulkUploadTemplateResult templateResult = new BulkUploadTemplateResult();
            templateResult.fileName =
                (UPLOAD_TYPE_ORDER.equalsIgnoreCase(uploadType) ? 'Order' : 'Invoice') +
                '_Bulk_Upload_Format.xlsx';
            templateResult.base64Data = EncodingUtil.base64Encode(resources[0].Body);
            return templateResult;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throwAuraHandledException('Unable to download template: ' + ex.getMessage());
            return null;
        }
    }
    
    public class BulkUploadTemplateResult {
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String base64Data { get; set; }
    }

    @TestVisible
    private static String lastAuraHandledMessageForTest;

    private static void throwAuraHandledException(String message) {
        lastAuraHandledMessageForTest = message;
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        throw ex;
    }

    private static final List<String> ORDER_TEMPLATE_COLUMNS = new List<String>{
        'Ref Order No.',
        'Order Date',
        'Retailer Code',
        'Product Code',
        'Quantity',
        'Data Upload'
    };

    private static final List<String> INVOICE_TEMPLATE_COLUMNS = new List<String>{
        'Ref Invoice No.',
        'Invoice Date',
        'Retailer Code',
        'Order Number',
        'Product Code',
        'Discount 2%',
        'Quantity',
        'Data Upload',
        'Status'
    };

    @AuraEnabled(cacheable=true)
    public static Boolean hasBulkUploadAccess() {
        try {
            checkUserAccess();
            return true;
        } catch (AuraHandledException ex) {
            return false;
        }
    }

    @AuraEnabled
    public static BulkUploadResult validateBulkUpload(
        String uploadType,
        String fileName,
        String base64Data
    ) {
        BulkUploadResult result = new BulkUploadResult();
        result.errors = new List<BulkUploadError>();

        try {
            BulkUploadValidationContext validationContext = validateUploadFile(
                uploadType,
                fileName,
                base64Data
            );
            result.errors = validationContext.errors;
            if (!result.errors.isEmpty()) {
                return result;
            }

            result.success = buildValidationSuccess(
                uploadType,
                validationContext.dataRows
            );
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throwAuraHandledException(
                'Bulk upload validation failed: ' + ex.getMessage()
            );
        }

        return result;
    }

    //Added by Hari - Order Record Creation
    @AuraEnabled
    public static BulkUploadSaveResult saveBulkUpload(
        String uploadType,
        String fileName,
        String base64Data
    ) {
        BulkUploadSaveResult saveResult = new BulkUploadSaveResult();
        saveResult.errors = new List<BulkUploadError>();
        saveResult.createdOrderIds = new List<Id>();
        saveResult.createdOrderNames = new List<String>();
        saveResult.createdInvoiceIds = new List<Id>();
        saveResult.createdInvoiceNames = new List<String>();

        try {
            validateUploadType(uploadType);
            checkUserAccess();

            BulkUploadValidationContext validationContext = validateUploadFile(
                uploadType,
                fileName,
                base64Data
            );
            saveResult.errors = validationContext.errors;
            if (!saveResult.errors.isEmpty()) {
                saveResult.status = 'ValidationFailed';
                return saveResult;
            }

            if (UPLOAD_TYPE_ORDER.equalsIgnoreCase(uploadType)) {
                BulkOrderCreationResult creationResult = createBulkOrders(
                    validationContext.dataRows,
                    validationContext.fileBlob,
                    fileName
                );
                saveResult.status = 'Success';
                saveResult.ordersCreated = creationResult.ordersCreated;
                saveResult.createdOrderIds = creationResult.orderIds;
                saveResult.createdOrderNames = creationResult.orderNames;
            } else {
                BulkInvoiceCreationResult creationResult = createBulkInvoices(
                    validationContext.dataRows,
                    validationContext.fileBlob,
                    fileName
                );
                saveResult.status = 'Success';
                saveResult.invoicesCreated = creationResult.invoicesCreated;
                saveResult.createdInvoiceIds = creationResult.invoiceIds;
                saveResult.createdInvoiceNames = creationResult.invoiceNames;
            }

            saveResult.success = buildValidationSuccess(
                uploadType,
                validationContext.dataRows
            );
            saveResult.success.validationPassed = false;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throwAuraHandledException(
                'Bulk upload save failed: ' + ex.getMessage()
            );
        }

        return saveResult;
    }

    // -------------------------------------------------------------------------
    // New Requirement — Public entry points
    // -------------------------------------------------------------------------

    /**
     * Checks whether any rows in the uploaded file reference an Order/Invoice
     * that already exists in the system (matched on the Ref No. Data Upload field).
     * Does NOT perform any DML. Safe to call repeatedly.
     */
    @AuraEnabled
    public static DuplicateCheckResult checkExistingReferences(
        String uploadType,
        String fileName,
        String base64Data
    ) {
        DuplicateCheckResult checkResult = new DuplicateCheckResult();
        checkResult.duplicateRefs = new List<String>();
        checkResult.hasDuplicates = false;
        checkResult.hasValidationErrors = false;

        try {
            validateUploadType(uploadType);
            checkUserAccess();

            BulkUploadValidationContext validationContext = validateUploadFile(
                uploadType,
                fileName,
                base64Data
            );

            if (!validationContext.errors.isEmpty()) {
                checkResult.hasValidationErrors = true;
                return checkResult;
            }

            String refColumn = UPLOAD_TYPE_ORDER.equalsIgnoreCase(uploadType)
                ? 'Ref Order No.'
                : 'Ref Invoice No.';

            Set<String> refNumbers = new Set<String>();
            for (Map<String, String> row : validationContext.dataRows) {
                collectCode(refNumbers, row.get(refColumn));
            }

            if (UPLOAD_TYPE_ORDER.equalsIgnoreCase(uploadType)) {
                checkResult.duplicateRefs = findExistingOrderRefs(refNumbers);
            } else {
                checkResult.duplicateRefs = findExistingInvoiceRefs(refNumbers);
            }

            checkResult.hasDuplicates = !checkResult.duplicateRefs.isEmpty();
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throwAuraHandledException(
                'Unable to check existing references: ' + ex.getMessage()
            );
        }

        return checkResult;
    }

    /**
     * New save entry point supporting mixed insert/update.
     * - When no duplicate reference numbers exist, behaves exactly like saveBulkUpload
     *   (pure insert), regardless of the confirmedUpdateExisting flag.
     * - When duplicates exist and confirmedUpdateExisting is not TRUE, no DML is performed
     *   and status 'DuplicatesFound' is returned so the client can show a confirmation modal.
     * - When duplicates exist and confirmedUpdateExisting is TRUE, matching reference groups
     *   are updated (Quantity-only on line items) while non-matching groups are inserted.
     *
     * This method is fully additive; saveBulkUpload above is untouched and continues to
     * work exactly as before for any existing callers.
     */
    @AuraEnabled
    public static BulkUploadSaveResult saveBulkUploadWithUpdateSupport(
        String uploadType,
        String fileName,
        String base64Data,
        Boolean confirmedUpdateExisting
    ) {
        BulkUploadSaveResult saveResult = new BulkUploadSaveResult();
        saveResult.errors = new List<BulkUploadError>();
        saveResult.createdOrderIds = new List<Id>();
        saveResult.createdOrderNames = new List<String>();
        saveResult.createdInvoiceIds = new List<Id>();
        saveResult.createdInvoiceNames = new List<String>();

        try {
            validateUploadType(uploadType);
            checkUserAccess();

            BulkUploadValidationContext validationContext = validateUploadFile(
                uploadType,
                fileName,
                base64Data
            );
            saveResult.errors = validationContext.errors;
            if (!saveResult.errors.isEmpty()) {
                saveResult.status = 'ValidationFailed';
                return saveResult;
            }

            String refColumn = UPLOAD_TYPE_ORDER.equalsIgnoreCase(uploadType)
                ? 'Ref Order No.'
                : 'Ref Invoice No.';

            Set<String> refNumbers = new Set<String>();
            for (Map<String, String> row : validationContext.dataRows) {
                collectCode(refNumbers, row.get(refColumn));
            }

            List<String> duplicateRefs = UPLOAD_TYPE_ORDER.equalsIgnoreCase(uploadType)
                ? findExistingOrderRefs(refNumbers)
                : findExistingInvoiceRefs(refNumbers);

            if (!duplicateRefs.isEmpty() && confirmedUpdateExisting != true) {
                saveResult.status = 'DuplicatesFound';
                saveResult.errors = new List<BulkUploadError>();
                for (String dupRef : duplicateRefs) {
                    addError(
                        saveResult.errors,
                        0,
                        refColumn,
                        'A record with reference "' + dupRef + '" already exists.'
                    );
                }
                return saveResult;
            }

            Set<String> duplicateRefSet = new Set<String>();
            for (String dupRef : duplicateRefs) {
                duplicateRefSet.add(dupRef.trim().toUpperCase());
            }

            List<Map<String, String>> newRows = new List<Map<String, String>>();
            List<Map<String, String>> updateRows = new List<Map<String, String>>();

            for (Map<String, String> row : validationContext.dataRows) {
                String refNo = row.get(refColumn);
                String refKey = String.isBlank(refNo) ? '' : refNo.trim().toUpperCase();
                if (!String.isBlank(refKey) && duplicateRefSet.contains(refKey)) {
                    updateRows.add(row);
                } else {
                    newRows.add(row);
                }
            }

            if (UPLOAD_TYPE_ORDER.equalsIgnoreCase(uploadType)) {
                if (!newRows.isEmpty()) {
                    BulkOrderCreationResult creationResult = createBulkOrders(
                        newRows,
                        validationContext.fileBlob,
                        fileName
                    );
                    saveResult.ordersCreated = creationResult.ordersCreated;
                    saveResult.createdOrderIds.addAll(creationResult.orderIds);
                    saveResult.createdOrderNames.addAll(creationResult.orderNames);
                }

                if (!updateRows.isEmpty()) {
                    OrderUpdateResult updateResult = updateExistingOrders(updateRows);
                    if (!updateResult.errors.isEmpty()) {
                        saveResult.errors.addAll(updateResult.errors);
                    }
                    saveResult.ordersCreated =
                        (saveResult.ordersCreated == null ? 0 : saveResult.ordersCreated) +
                        updateResult.updatedCount;
                    saveResult.createdOrderIds.addAll(updateResult.updatedOrderIds);
                    saveResult.createdOrderNames.addAll(updateResult.updatedOrderNames);
                }
            } else {
                if (!newRows.isEmpty()) {
                    BulkInvoiceCreationResult creationResult = createBulkInvoices(
                        newRows,
                        validationContext.fileBlob,
                        fileName
                    );
                    saveResult.invoicesCreated = creationResult.invoicesCreated;
                    saveResult.createdInvoiceIds.addAll(creationResult.invoiceIds);
                    saveResult.createdInvoiceNames.addAll(creationResult.invoiceNames);
                }

                if (!updateRows.isEmpty()) {
                    InvoiceUpdateResult updateResult = updateExistingInvoices(updateRows);
                    if (!updateResult.errors.isEmpty()) {
                        saveResult.errors.addAll(updateResult.errors);
                    }
                    saveResult.invoicesCreated =
                        (saveResult.invoicesCreated == null ? 0 : saveResult.invoicesCreated) +
                        updateResult.updatedCount;
                    saveResult.createdInvoiceIds.addAll(updateResult.updatedInvoiceIds);
                    saveResult.createdInvoiceNames.addAll(updateResult.updatedInvoiceNames);
                }
            }

            saveResult.status = saveResult.errors.isEmpty() ? 'Success' : 'PartialFailure';
            saveResult.success = buildValidationSuccess(uploadType, validationContext.dataRows);
            saveResult.success.validationPassed = false;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throwAuraHandledException(
                'Bulk upload save failed: ' + ex.getMessage()
            );
        }

        return saveResult;
    }

    private static BulkUploadValidationContext validateUploadFile(
        String uploadType,
        String fileName,
        String base64Data
    ) {
        BulkUploadValidationContext context = new BulkUploadValidationContext();
        context.errors = new List<BulkUploadError>();

        validateUploadType(uploadType);
        if (!String.isBlank(fileName)) {
            rejectLegacySpreadsheetFileName(fileName);
        }
        checkUserAccess();

        if (String.isBlank(fileName) || String.isBlank(base64Data)) {
            addError(context.errors, 0, 'File', 'Upload file is required.');
            return context;
        }

        context.fileBlob = decodeBase64(base64Data);
        if (context.fileBlob == null || context.fileBlob.size() == 0) {
            addError(context.errors, 0, 'File', 'Upload file is empty or unreadable.');
            return context;
        }

        List<List<String>> sheetRows = parseSpreadsheet(context.fileBlob, fileName);
        if (sheetRows.isEmpty()) {
            addError(context.errors, 0, 'File', 'No data found in the uploaded file.');
            return context;
        }

        List<String> expectedColumns = getExpectedColumns(uploadType);
        context.errors.addAll(validateTemplate(sheetRows, expectedColumns, uploadType));
        if (!context.errors.isEmpty()) {
            return context;
        }

        context.errors.addAll(validateEmptyDataRows(sheetRows));
        if (!context.errors.isEmpty()) {
            return context;
        }

        context.dataRows = buildDataRows(sheetRows, expectedColumns);
        if (context.dataRows.isEmpty()) {
            addError(
                context.errors,
                1,
                'Template',
                'At least one data row is required after the header row.'
            );
            return context;
        }

        if (UPLOAD_TYPE_ORDER.equalsIgnoreCase(uploadType)) {
            context.errors.addAll(validateOrderRows(context.dataRows));
        } else {
            context.errors.addAll(validateInvoiceRows(context.dataRows));
        }

        return context;
    }

    // -------------------------------------------------------------------------
    // Access & file helpers
    // -------------------------------------------------------------------------

    private static void validateUploadType(String uploadType) {
        if (
            String.isBlank(uploadType) ||
            (!UPLOAD_TYPE_ORDER.equalsIgnoreCase(uploadType) &&
            !UPLOAD_TYPE_INVOICE.equalsIgnoreCase(uploadType))
        ) {
            throwAuraHandledException(
                'Invalid upload type. Please select Order or Invoice.'
            );
        }
    }

    private static void checkUserAccess() {
        Map<String, Schema.SObjectField> userFields = Schema.SObjectType.User.fields.getMap();
        if (!userFields.containsKey('allow_bulk_upload__c')) {
            throwAuraHandledException(
                'Bulk upload is not configured. Missing User field Allow Bulk Upload.'
            );
        }

        Id currentUserId = UserInfo.getUserId();
        String accessQuery =
            'SELECT Id FROM User WHERE Id = :currentUserId AND ' +
            USER_ALLOW_BULK_FIELD +
            ' = TRUE LIMIT 1';
        List<User> users = Database.query(accessQuery);

        if (users.isEmpty()) {
            throwAuraHandledException(
                'You are not authorized for bulk upload. Contact your Hangyo administrator.'
            );
        }
    }

    private static void rejectLegacySpreadsheetFileName(String fileName) {
        String lowerName = fileName == null ? '' : fileName.toLowerCase();
        if (lowerName.endsWith('.xls') && !lowerName.endsWith('.xlsx')) {
            throwAuraHandledException(
                'Legacy .xls files are not supported. Please upload an .xlsx file.'
            );
        }
    }

    private static Blob decodeBase64(String base64Data) {
        String payload = base64Data;
        Integer commaIndex = payload.indexOf(',');
        if (commaIndex > -1) {
            payload = payload.substring(commaIndex + 1);
        }
        return EncodingUtil.base64Decode(payload);
    }

    private static List<String> getExpectedColumns(String uploadType) {
        return UPLOAD_TYPE_ORDER.equalsIgnoreCase(uploadType)
            ? ORDER_TEMPLATE_COLUMNS
            : INVOICE_TEMPLATE_COLUMNS;
    }

    // -------------------------------------------------------------------------
    // Template validation
    // -------------------------------------------------------------------------

    private static List<BulkUploadError> validateTemplate(
        List<List<String>> sheetRows,
        List<String> expectedColumns,
        String uploadType
    ) {
        List<BulkUploadError> errors = new List<BulkUploadError>();
        List<String> headerRow = sheetRows[0];
        List<String> actualHeaders = getTrimmedHeaders(headerRow);

        if (UPLOAD_TYPE_ORDER.equalsIgnoreCase(uploadType) && looksLikeInvoiceTemplate(actualHeaders)) {
            addError(
                errors,
                1,
                'Format',
                'Invalid format. Order Excel template required but Invoice Excel template was uploaded.'
            );
            return errors;
        }

        if (UPLOAD_TYPE_INVOICE.equalsIgnoreCase(uploadType) && looksLikeOrderTemplate(actualHeaders)) {
            addError(
                errors,
                1,
                'Format',
                'Invalid format. Invoice Excel template required but Order Excel template was uploaded.'
            );
            return errors;
        }

        if (headerRow.size() != expectedColumns.size()) {
            addError(
                errors,
                1,
                'Format',
                buildColumnMismatchMessage(expectedColumns, actualHeaders)
            );
            return errors;
        }

        for (Integer index = 0; index < expectedColumns.size(); index++) {
            String expected = normalizeHeader(expectedColumns[index]);
            String actual = index < headerRow.size()
                ? normalizeHeader(headerRow[index])
                : '';

            if (actual != expected) {
                addError(
                    errors,
                    1,
                    'Template',
                    'Invalid template. Expected column "' +
                        expectedColumns[index] +
                        '" at position ' +
                        (index + 1) +
                        ' but found "' +
                        (index < headerRow.size() ? headerRow[index] : '') +
                        '".'
                );
            }
        }

        return errors;
    }

    private static String buildColumnMismatchMessage(
        List<String> expectedColumns,
        List<String> actualHeaders
    ) {
        List<String> missingColumns = getMissingColumns(expectedColumns, actualHeaders);
        List<String> unexpectedColumns = getUnexpectedColumns(expectedColumns, actualHeaders);
        List<String> messageParts = new List<String>{ 'Invalid format.' };

        if (!missingColumns.isEmpty()) {
            messageParts.add(
                'Missing column(s): ' + String.join(missingColumns, ', ') + '.'
            );
        }

        if (!unexpectedColumns.isEmpty()) {
            messageParts.add(
                'Unexpected column(s): ' + String.join(unexpectedColumns, ', ') + '.'
            );
        }

        if (missingColumns.isEmpty() && unexpectedColumns.isEmpty()) {
            messageParts.add(
                'Expected ' +
                    expectedColumns.size() +
                    ' columns but found ' +
                    actualHeaders.size() +
                    '.'
            );
        }

        return String.join(messageParts, ' ');
    }

    private static List<String> getMissingColumns(
        List<String> expectedColumns,
        List<String> actualHeaders
    ) {
        List<String> missingColumns = new List<String>();
        Set<String> actualNormalized = new Set<String>();

        for (String actualHeader : actualHeaders) {
            if (!String.isBlank(actualHeader)) {
                actualNormalized.add(normalizeHeader(actualHeader));
            }
        }

        for (String expectedColumn : expectedColumns) {
            if (!actualNormalized.contains(normalizeHeader(expectedColumn))) {
                missingColumns.add(expectedColumn);
            }
        }

        return missingColumns;
    }

    private static List<String> getUnexpectedColumns(
        List<String> expectedColumns,
        List<String> actualHeaders
    ) {
        List<String> unexpectedColumns = new List<String>();
        Set<String> expectedNormalized = new Set<String>();

        for (String expectedColumn : expectedColumns) {
            expectedNormalized.add(normalizeHeader(expectedColumn));
        }

        for (String actualHeader : actualHeaders) {
            if (
                !String.isBlank(actualHeader) &&
                !expectedNormalized.contains(normalizeHeader(actualHeader))
            ) {
                unexpectedColumns.add(actualHeader);
            }
        }

        return unexpectedColumns;
    }

    private static List<String> getTrimmedHeaders(List<String> headerRow) {
        List<String> headers = new List<String>();
        for (String header : headerRow) {
            headers.add(header == null ? '' : header.trim());
        }
        return headers;
    }

    private static Boolean looksLikeInvoiceTemplate(List<String> actualHeaders) {
        Set<String> normalizedHeaders = new Set<String>();
        for (String header : actualHeaders) {
            if (!String.isBlank(header)) {
                normalizedHeaders.add(normalizeHeader(header));
            }
        }

        return normalizedHeaders.contains(normalizeHeader('Ref Invoice No.')) ||
            (normalizedHeaders.contains(normalizeHeader('Order Number')) &&
            normalizedHeaders.contains(normalizeHeader('Status')));
    }

    private static Boolean looksLikeOrderTemplate(List<String> actualHeaders) {
        Set<String> normalizedHeaders = new Set<String>();
        for (String header : actualHeaders) {
            if (!String.isBlank(header)) {
                normalizedHeaders.add(normalizeHeader(header));
            }
        }

        return normalizedHeaders.contains(normalizeHeader('Ref Order No.')) &&
            !normalizedHeaders.contains(normalizeHeader('Ref Invoice No.'));
    }

    private static List<BulkUploadError> validateEmptyDataRows(List<List<String>> sheetRows) {
        List<BulkUploadError> errors = new List<BulkUploadError>();

        for (Integer rowIndex = 1; rowIndex < sheetRows.size(); rowIndex++) {
            if (isBlankRow(sheetRows[rowIndex])) {
                addError(
                    errors,
                    rowIndex + 1,
                    'Template',
                    'Empty row is not allowed. Remove blank rows between records and ensure every data row is filled.'
                );
            }
        }

        return errors;
    }

    private static List<Map<String, String>> buildDataRows(
        List<List<String>> sheetRows,
        List<String> expectedColumns
    ) {
        List<Map<String, String>> dataRows = new List<Map<String, String>>();

        for (Integer rowIndex = 1; rowIndex < sheetRows.size(); rowIndex++) {
            List<String> rawRow = sheetRows[rowIndex];
            if (isBlankRow(rawRow)) {
                continue;
            }

            Map<String, String> rowMap = new Map<String, String>();
            for (Integer colIndex = 0; colIndex < expectedColumns.size(); colIndex++) {
                String value = colIndex < rawRow.size() ? rawRow[colIndex] : '';
                value = value == null ? '' : value.trim();
                if (expectedColumns[colIndex] == 'Data Upload') {
                    value = normalizeDataUploadCellValue(value);
                }
                rowMap.put(expectedColumns[colIndex], value);
            }
            rowMap.put('__rowNumber', String.valueOf(rowIndex + 1));
            dataRows.add(rowMap);
        }

        return dataRows;
    }

    // -------------------------------------------------------------------------
    // Order validation
    // -------------------------------------------------------------------------

    private static List<BulkUploadError> validateOrderRows(
        List<Map<String, String>> dataRows
    ) {
        List<BulkUploadError> errors = new List<BulkUploadError>();
        Set<String> retailerCodes = new Set<String>();
        Set<String> productCodes = new Set<String>();

        for (Map<String, String> row : dataRows) {
            collectCode(retailerCodes, row.get('Retailer Code'));
            collectCode(productCodes, row.get('Product Code'));
        }

        Map<String, Account> retailers = loadRetailers(retailerCodes);
        Map<String, SObject> products = loadProducts(productCodes);
        Map<String, Map<String, String>> groupHeaders = new Map<String, Map<String, String>>();
        Id loggedInDistributorAccountId = getCurrentUserDistributorAccountId();

        for (Map<String, String> row : dataRows) {
            Integer rowNo = getRowNumber(row);

            validateRequired(errors, rowNo, 'Ref Order No.', row.get('Ref Order No.'));
            validateRequired(errors, rowNo, 'Order Date', row.get('Order Date'));
            validateRequired(errors, rowNo, 'Retailer Code', row.get('Retailer Code'));
            validateRequired(errors, rowNo, 'Product Code', row.get('Product Code'));
            validateRequired(errors, rowNo, 'Quantity', row.get('Quantity'));
            validateRequired(errors, rowNo, 'Data Upload', row.get('Data Upload'));

            validateDate(errors, rowNo, 'Order Date', row.get('Order Date'));
            validateOrderDate(errors, rowNo, row.get('Order Date'));
            validateDataUpload(errors, rowNo, row.get('Data Upload'));
            validateQuantity(errors, rowNo, row.get('Quantity'));
            validateRetailer(
                errors,
                rowNo,
                row.get('Retailer Code'),
                retailers,
                loggedInDistributorAccountId
            );
            validateProduct(errors, rowNo, row.get('Product Code'), products);
            validateOrderGroupConsistency(errors, rowNo, row, groupHeaders);
        }

        return errors;
    }

    private static void validateOrderGroupConsistency(
        List<BulkUploadError> errors,
        Integer rowNo,
        Map<String, String> row,
        Map<String, Map<String, String>> groupHeaders
    ) {
        String refNo = row.get('Ref Order No.');
        if (String.isBlank(refNo)) {
            return;
        }

        String groupKey = refNo.trim().toUpperCase();
        Map<String, String> header = new Map<String, String>{
            'Order Date' => row.get('Order Date'),
            'Retailer Code' => row.get('Retailer Code'),
            'Data Upload' => row.get('Data Upload')
        };

        if (!groupHeaders.containsKey(groupKey)) {
            groupHeaders.put(groupKey, header);
            return;
        }

        Map<String, String> existing = groupHeaders.get(groupKey);
        compareGroupedValue(errors, rowNo, 'Order Date', existing.get('Order Date'), header.get('Order Date'), refNo);
        compareGroupedValue(errors, rowNo, 'Retailer Code', existing.get('Retailer Code'), header.get('Retailer Code'), refNo);
        compareGroupedValue(errors, rowNo, 'Data Upload', existing.get('Data Upload'), header.get('Data Upload'), refNo);
    }

    // -------------------------------------------------------------------------
    // Invoice validation
    // -------------------------------------------------------------------------

    private static List<BulkUploadError> validateInvoiceRows(
        List<Map<String, String>> dataRows
    ) {
        List<BulkUploadError> errors = new List<BulkUploadError>();
        Set<String> retailerCodes = new Set<String>();
        Set<String> productCodes = new Set<String>();
        Set<String> orderNumbers = new Set<String>();

        for (Map<String, String> row : dataRows) {
            collectCode(retailerCodes, row.get('Retailer Code'));
            collectCode(productCodes, row.get('Product Code'));
            collectCode(orderNumbers, row.get('Order Number'));
        }

        Map<String, Account> retailers = loadRetailers(retailerCodes);
        Map<String, SObject> products = loadProducts(productCodes);
        Map<String, SObject> orders = loadOrders(orderNumbers);
        Map<String, Map<String, String>> groupHeaders = new Map<String, Map<String, String>>();
        Map<String, Set<String>> productCodesByInvoiceRef = new Map<String, Set<String>>();
        Id loggedInDistributorAccountId = getCurrentUserDistributorAccountId();

        Set<Id> orderIds = new Set<Id>();
        for (SObject orderRecord : orders.values()) {
            orderIds.add(orderRecord.Id);
        }
        Map<Id, Invoice__c> draftInvoicesByOrderId = loadDraftInvoicesByOrderId(orderIds);

        for (Map<String, String> row : dataRows) {
            Integer rowNo = getRowNumber(row);

            validateRequired(errors, rowNo, 'Ref Invoice No.', row.get('Ref Invoice No.'));
            validateRequired(errors, rowNo, 'Invoice Date', row.get('Invoice Date'));
            validateRequired(errors, rowNo, 'Retailer Code', row.get('Retailer Code'));
            validateRequired(errors, rowNo, 'Order Number', row.get('Order Number'));
            validateRequired(errors, rowNo, 'Product Code', row.get('Product Code'));
            validateRequired(errors, rowNo, 'Discount 2%', row.get('Discount 2%'));
            validateRequired(errors, rowNo, 'Quantity', row.get('Quantity'));
            validateRequired(errors, rowNo, 'Data Upload', row.get('Data Upload'));
            validateRequired(errors, rowNo, 'Status', row.get('Status'));

            validateDate(errors, rowNo, 'Invoice Date', row.get('Invoice Date'));
            validateInvoiceDate(
                errors,
                rowNo,
                row.get('Invoice Date'),
                row.get('Order Number'),
                orders
            );
            validateDataUpload(errors, rowNo, row.get('Data Upload'));
            validateQuantity(errors, rowNo, row.get('Quantity'));
            validateDiscount(errors, rowNo, row.get('Discount 2%'));
            validateStatus(errors, rowNo, row.get('Status'));
            validateRetailer(
                errors,
                rowNo,
                row.get('Retailer Code'),
                retailers,
                loggedInDistributorAccountId
            );
            validateProduct(errors, rowNo, row.get('Product Code'), products);
            validateOrderNumber(errors, rowNo, row.get('Order Number'), orders);
            validateOrderDistributor(
                errors,
                rowNo,
                row.get('Order Number'),
                orders,
                loggedInDistributorAccountId
            );
            /*validateNoExistingDraftInvoice(
                errors,
                rowNo,
                row.get('Order Number'),
                orders,
                draftInvoicesByOrderId
            );*/
            validateInvoiceLineProductUniqueness(
                errors,
                rowNo,
                row,
                productCodesByInvoiceRef
            );
            validateInvoiceGroupConsistency(errors, rowNo, row, groupHeaders);
        }

        return errors;
    }

    private static void validateInvoiceGroupConsistency(
        List<BulkUploadError> errors,
        Integer rowNo,
        Map<String, String> row,
        Map<String, Map<String, String>> groupHeaders
    ) {
        String refNo = row.get('Ref Invoice No.');
        if (String.isBlank(refNo)) {
            return;
        }

        String groupKey = refNo.trim().toUpperCase();
        Map<String, String> header = new Map<String, String>{
            'Invoice Date' => row.get('Invoice Date'),
            'Retailer Code' => row.get('Retailer Code'),
            'Order Number' => row.get('Order Number'),
            'Discount 2%' => row.get('Discount 2%'),
            'Data Upload' => row.get('Data Upload'),
            'Status' => row.get('Status')
        };

        if (!groupHeaders.containsKey(groupKey)) {
            groupHeaders.put(groupKey, header);
            return;
        }

        Map<String, String> existing = groupHeaders.get(groupKey);
        compareGroupedValue(errors, rowNo, 'Invoice Date', existing.get('Invoice Date'), header.get('Invoice Date'), refNo);
        compareGroupedValue(errors, rowNo, 'Retailer Code', existing.get('Retailer Code'), header.get('Retailer Code'), refNo);
        compareGroupedValue(errors, rowNo, 'Order Number', existing.get('Order Number'), header.get('Order Number'), refNo);
        compareGroupedDecimalValue(
            errors,
            rowNo,
            'Discount 2%',
            existing.get('Discount 2%'),
            header.get('Discount 2%'),
            refNo
        );
        compareGroupedValue(errors, rowNo, 'Data Upload', existing.get('Data Upload'), header.get('Data Upload'), refNo);
        compareGroupedValue(errors, rowNo, 'Status', existing.get('Status'), header.get('Status'), refNo);
    }

    // -------------------------------------------------------------------------
    // Field-level validators
    // -------------------------------------------------------------------------

    private static void validateRequired(
        List<BulkUploadError> errors,
        Integer rowNo,
        String columnName,
        String value
    ) {
        if (String.isBlank(value)) {
            addError(errors, rowNo, columnName, columnName + ' is required.');
        }
    }

    private static void validateDataUpload(
        List<BulkUploadError> errors,
        Integer rowNo,
        String value
    ) {
        if (String.isBlank(value)) {
            return;
        }
        if (!isDataUploadTrue(value)) {
            addError(errors, rowNo, 'Data Upload', 'Data Upload must be TRUE.');
        }
    }

    private static Boolean isDataUploadTrue(String value) {
        if (String.isBlank(value)) {
            return false;
        }

        String normalized = value.trim().toUpperCase();
        return normalized == 'TRUE' || normalized == '1';
    }

    private static String normalizeDataUploadCellValue(String value) {
        if (isDataUploadTrue(value)) {
            return 'TRUE';
        }
        if (String.isBlank(value)) {
            return '';
        }

        String normalized = value.trim().toUpperCase();
        if (normalized == 'FALSE' || normalized == '0') {
            return 'FALSE';
        }

        return value.trim();
    }

    private static void validateQuantity(
        List<BulkUploadError> errors,
        Integer rowNo,
        String value
    ) {
        if (String.isBlank(value)) {
            return;
        }
        Decimal quantity = parseDecimal(value);
        if (quantity == null) {
            addError(errors, rowNo, 'Quantity', 'Quantity must be a valid number.');
            return;
        }
        if (quantity <= 0) {
            addError(errors, rowNo, 'Quantity', 'Quantity must be greater than zero.');
        }
    }

    private static void validateDiscount(
        List<BulkUploadError> errors,
        Integer rowNo,
        String value
    ) {
        if (String.isBlank(value)) {
            return;
        }
        Decimal discount = parseDecimal(value);
        if (discount == null) {
            addError(errors, rowNo, 'Discount 2%', 'Discount 2% must be a valid number.');
            return;
        }
        if (discount < 0) {
            addError(errors, rowNo, 'Discount 2%', 'Discount 2% must be greater than or equal to zero.');
        }
    }

    private static void validateStatus(
        List<BulkUploadError> errors,
        Integer rowNo,
        String value
    ) {
        if (String.isBlank(value)) {
            return;
        }
        if (!ALLOWED_INVOICE_STATUSES.contains(value.trim().toUpperCase())) {
            addError(
                errors,
                rowNo,
                'Status',
                'Status must be Draft or Confirmed.'
            );
        }
    }

    private static void validateDate(
        List<BulkUploadError> errors,
        Integer rowNo,
        String columnName,
        String value
    ) {
        if (String.isBlank(value)) {
            return;
        }
        if (parseDate(value) == null) {
            addError(
                errors,
                rowNo,
                columnName,
                columnName + ' must be a valid date in DD/MM/YYYY format.'
            );
        }
    }

    private static void validateOrderDate(
        List<BulkUploadError> errors,
        Integer rowNo,
        String value
    ) {
        validateOrderDate(errors, rowNo, value, System.today());
    }

    private static void validateOrderDate(
        List<BulkUploadError> errors,
        Integer rowNo,
        String value,
        Date uploadDate
    ) {
        if (String.isBlank(value)) {
            return;
        }

        Date orderDate = parseDate(value);
        if (orderDate == null) {
            return;
        }

        Date earliestAllowedDate = uploadDate.addDays(-ORDER_DATE_MAX_PAST_DAYS);

        if (orderDate < earliestAllowedDate) {
            addError(
                errors,
                rowNo,
                'Order Date',
                'Order Date cannot be more than 3 days before the upload date.'
            );
            return;
        }

        if (orderDate > uploadDate) {
            addError(
                errors,
                rowNo,
                'Order Date',
                'Order Date cannot be after the upload date.'
            );
        }
    }

    private static void validateInvoiceDate(
        List<BulkUploadError> errors,
        Integer rowNo,
        String invoiceDateValue,
        String orderNumber,
        Map<String, SObject> orders
    ) {
        validateInvoiceDate(
            errors,
            rowNo,
            invoiceDateValue,
            orderNumber,
            orders,
            System.today()
        );
    }

    private static void validateInvoiceDate(
        List<BulkUploadError> errors,
        Integer rowNo,
        String invoiceDateValue,
        String orderNumber,
        Map<String, SObject> orders,
        Date uploadDate
    ) {
        if (String.isBlank(invoiceDateValue)) {
            return;
        }

        Date invoiceDate = parseDate(invoiceDateValue);
        if (invoiceDate == null) {
            return;
        }

        if (invoiceDate > uploadDate) {
            addError(
                errors,
                rowNo,
                'Invoice Date',
                'Invoice Date cannot be after the upload date.'
            );
            return;
        }

        Date earliestAllowedDate = uploadDate.addDays(-ORDER_DATE_MAX_PAST_DAYS);
        Date orderDate = null;

        if (!String.isBlank(orderNumber)) {
            String orderKey = normalizeOrderNumber(orderNumber).toUpperCase();
            if (orders.containsKey(orderKey)) {
                orderDate = (Date) orders.get(orderKey).get('EffectiveDate__c');
            }
        }

        if (orderDate != null && orderDate > earliestAllowedDate) {
            earliestAllowedDate = orderDate;
        }

        if (invoiceDate < earliestAllowedDate) {
            if (orderDate != null && earliestAllowedDate == orderDate) {
                addError(
                    errors,
                    rowNo,
                    'Invoice Date',
                    'Invoice Date cannot be before the Order Date (' +
                        formatDateForDisplay(
                            orderDate.day() +
                                '/' +
                                orderDate.month() +
                                '/' +
                                orderDate.year()
                        ) +
                        ').'
                );
            } else {
                addError(
                    errors,
                    rowNo,
                    'Invoice Date',
                    'Invoice Date cannot be more than 3 days before the upload date.'
                );
            }
        }
    }

    private static void validateRetailer(
        List<BulkUploadError> errors,
        Integer rowNo,
        String retailerCode,
        Map<String, Account> retailers,
        Id loggedInDistributorAccountId
    ) {
        if (String.isBlank(retailerCode)) {
            return;
        }
        String key = retailerCode.trim().toUpperCase();
        if (!retailers.containsKey(key)) {
            addError(
                errors,
                rowNo,
                'Retailer Code',
                'Retailer Code "' + retailerCode + '" does not exist, is inactive, or is not a Retailer account.'
            );
            return;
        }

        if (loggedInDistributorAccountId == null) {
            addError(
                errors,
                rowNo,
                'Retailer Code',
                'Your user profile is not linked to a distributor. Contact your administrator.'
            );
            return;
        }

        Account retailer = retailers.get(key);
        Id retailerDistributorId = resolveDistributorIdForRetailer(retailer, null);
        if (retailerDistributorId != loggedInDistributorAccountId) {
            addError(
                errors,
                rowNo,
                'Retailer Code',
                'Retailer Code "' +
                    retailerCode +
                    '" does not belong to your distributor.'
            );
        }
    }

    private static void validateProduct(
        List<BulkUploadError> errors,
        Integer rowNo,
        String productCode,
        Map<String, SObject> products
    ) {
        if (String.isBlank(productCode)) {
            return;
        }
        String key = normalizeProductCode(productCode).toUpperCase();
        if (!products.containsKey(key)) {
            addError(
                errors,
                rowNo,
                'Product Code',
                'Product Code "' + productCode + '" does not exist or is inactive.'
            );
        }
    }

    private static void validateOrderNumber(
        List<BulkUploadError> errors,
        Integer rowNo,
        String orderNumber,
        Map<String, SObject> orders
    ) {
        if (String.isBlank(orderNumber)) {
            return;
        }
        String key = normalizeOrderNumber(orderNumber).toUpperCase();
        if (!orders.containsKey(key)) {
            addError(
                errors,
                rowNo,
                'Order Number',
                'Order Number "' + orderNumber + '" not found in Salesforce.'
            );
        }
    }

    private static void validateOrderDistributor(
        List<BulkUploadError> errors,
        Integer rowNo,
        String orderNumber,
        Map<String, SObject> orders,
        Id loggedInDistributorAccountId
    ) {
        if (String.isBlank(orderNumber) || loggedInDistributorAccountId == null) {
            return;
        }

        SObject orderRecord = orders.get(normalizeOrderNumber(orderNumber).toUpperCase());
        if (orderRecord == null) {
            return;
        }

        Id orderDistributorId = orderRecord.get('AccountId__c') != null
            ? (Id) orderRecord.get('AccountId__c')
            : null;
        if (orderDistributorId != loggedInDistributorAccountId) {
            addError(
                errors,
                rowNo,
                'Order Number',
                'Order Number "' +
                    orderNumber +
                    '" does not belong to your distributor.'
            );
        }
    }

    /*private static void validateNoExistingDraftInvoice(
        List<BulkUploadError> errors,
        Integer rowNo,
        String orderNumber,
        Map<String, SObject> orders,
        Map<Id, Invoice__c> draftInvoicesByOrderId
    ) {
        if (String.isBlank(orderNumber)) {
            return;
        }

        SObject orderRecord = orders.get(normalizeOrderNumber(orderNumber).toUpperCase());
        if (orderRecord == null) {
            return;
        }

        if (draftInvoicesByOrderId.containsKey(orderRecord.Id)) {
            addError(
                errors,
                rowNo,
                'Order Number',
                'One invoice already exists in Draft status for this order. Please make changes in the existing invoice.'
            );
        }
    }*/

    private static void validateInvoiceLineProductUniqueness(
        List<BulkUploadError> errors,
        Integer rowNo,
        Map<String, String> row,
        Map<String, Set<String>> productCodesByInvoiceRef
    ) {
        String refNo = row.get('Ref Invoice No.');
        String productCode = row.get('Product Code');
        if (String.isBlank(refNo) || String.isBlank(productCode)) {
            return;
        }

        String groupKey = refNo.trim().toUpperCase();
        String normalizedProduct = normalizeProductCode(productCode).toUpperCase();
        if (!productCodesByInvoiceRef.containsKey(groupKey)) {
            productCodesByInvoiceRef.put(groupKey, new Set<String>());
        }

        Set<String> productsInGroup = productCodesByInvoiceRef.get(groupKey);
        if (productsInGroup.contains(normalizedProduct)) {
            addError(
                errors,
                rowNo,
                'Product Code',
                'Product Code "' +
                    productCode +
                    '" appears more than once for invoice reference "' +
                    refNo +
                    '".'
            );
            return;
        }

        productsInGroup.add(normalizedProduct);
    }

    private static void compareGroupedValue(
        List<BulkUploadError> errors,
        Integer rowNo,
        String columnName,
        String existingValue,
        String newValue,
        String refNo
    ) {
        String left = existingValue == null ? '' : existingValue.trim();
        String right = newValue == null ? '' : newValue.trim();
        if (left != right) {
            addError(
                errors,
                rowNo,
                columnName,
                columnName +
                    ' must be consistent for all rows with reference "' +
                    refNo +
                    '".'
            );
        }
    }

    private static void compareGroupedDecimalValue(
        List<BulkUploadError> errors,
        Integer rowNo,
        String columnName,
        String existingValue,
        String newValue,
        String refNo
    ) {
        Decimal left = parseDecimal(existingValue);
        Decimal right = parseDecimal(newValue);
        if (left == null && right == null) {
            return;
        }
        if (left == null || right == null || left != right) {
            addError(
                errors,
                rowNo,
                columnName,
                columnName +
                    ' must be consistent for all rows with reference "' +
                    refNo +
                    '".'
            );
        }
    }

    // -------------------------------------------------------------------------
    // Reference data loaders
    // -------------------------------------------------------------------------

    private static Map<String, Account> loadRetailers(Set<String> retailerCodes) {
        Map<String, Account> retailerMap = new Map<String, Account>();
        if (retailerCodes.isEmpty()) {
            return retailerMap;
        }

        if (!Schema.SObjectType.Account.fields.getMap().containsKey('retailer_code__c')) {
            return retailerMap;
        }

        Set<String> normalizedCodes = new Set<String>();
        for (String code : retailerCodes) {
            if (!String.isBlank(code)) {
                normalizedCodes.add(code.trim());
            }
        }

        if (normalizedCodes.isEmpty()) {
            return retailerMap;
        }

        List<String> selectFields = new List<String>{
            'Id',
            'Name',
            RETAILER_CODE_FIELD
        };

        if (hasRetailerStateField()) {
            selectFields.add(RETAILER_STATE_FIELD);
        }

        String distributorFieldApi = resolveRetailerDistributorFieldApi();
        if (!String.isBlank(distributorFieldApi)) {
            selectFields.add(distributorFieldApi);
        }

        String query =
            'SELECT ' +
            String.join(selectFields, ', ') +
            ' FROM Account WHERE ' +
            RETAILER_CODE_FIELD +
            ' IN :normalizedCodes' +
            ' AND RecordType.Name = :retailerRecordTypeName';

        if (hasAccountActiveField()) {
            query += ' AND ' + getRetailerActiveFieldApiName() + ' = TRUE';
        }

        Map<String, Object> bindVars = new Map<String, Object>{
            'normalizedCodes' => normalizedCodes,
            'retailerRecordTypeName' => RETAILER_RECORD_TYPE_NAME
        };

        for (SObject retailerRecord : Database.queryWithBinds(
            query,
            bindVars,
            AccessLevel.SYSTEM_MODE
        )) {
            Account retailer = (Account) retailerRecord;
            Object codeValue = retailer.get(RETAILER_CODE_FIELD);
            if (codeValue != null) {
                retailerMap.put(String.valueOf(codeValue).trim().toUpperCase(), retailer);
            }
        }

        return retailerMap;
    }

    //Added by Hari - Order Record Creation
    private static Map<String, Account> loadRetailersForOrderCreation(Set<String> retailerCodes) {
        Map<String, Account> retailerMap = new Map<String, Account>();
        if (retailerCodes.isEmpty()) {
            return retailerMap;
        }

        if (!Schema.SObjectType.Account.fields.getMap().containsKey('retailer_code__c')) {
            return retailerMap;
        }

        Set<String> normalizedCodes = new Set<String>();
        for (String code : retailerCodes) {
            if (!String.isBlank(code)) {
                normalizedCodes.add(code.trim());
            }
        }

        if (normalizedCodes.isEmpty()) {
            return retailerMap;
        }

        List<String> selectFields = new List<String>{
            'Id',
            'Name',
            'OwnerId',
            RETAILER_CODE_FIELD
        };

        if (hasRetailerStateField()) {
            selectFields.add(RETAILER_STATE_FIELD);
        }

        String distributorFieldApi = resolveRetailerDistributorFieldApi();
        if (!String.isBlank(distributorFieldApi)) {
            selectFields.add(distributorFieldApi);
        }

        if (
            hasAccountField('AccountId__c') &&
            !selectFields.contains('AccountId__c')
        ) {
            selectFields.add('AccountId__c');
        }

        for (String retailerOwnerField : new List<String>{
            'Retailer_Owner__c',
            'User__c',
            'Assigned_To__c',
            'ASM__c',
            'Sales_Executive__c'
        }) {
            if (
                hasAccountField(retailerOwnerField) &&
                !selectFields.contains(retailerOwnerField)
            ) {
                selectFields.add(retailerOwnerField);
            }
        }

        if (hasAccountField(RETAILER_BEATS_SOURCE_FIELD)) {
            selectFields.add(RETAILER_BEATS_SOURCE_FIELD);
        }

        String query =
            'SELECT ' +
            String.join(selectFields, ', ') +
            ' FROM Account WHERE ' +
            RETAILER_CODE_FIELD +
            ' IN :normalizedCodes' +
            ' AND RecordType.Name = :retailerRecordTypeName';

        if (hasAccountActiveField()) {
            query += ' AND ' + getRetailerActiveFieldApiName() + ' = TRUE';
        }

        Map<String, Object> bindVars = new Map<String, Object>{
            'normalizedCodes' => normalizedCodes,
            'retailerRecordTypeName' => RETAILER_RECORD_TYPE_NAME
        };

        for (SObject retailerRecord : Database.queryWithBinds(
            query,
            bindVars,
            AccessLevel.SYSTEM_MODE
        )) {
            Account retailer = (Account) retailerRecord;
            Object codeValue = retailer.get(RETAILER_CODE_FIELD);
            if (codeValue != null) {
                retailerMap.put(String.valueOf(codeValue).trim().toUpperCase(), retailer);
            }
        }

        return retailerMap;
    }

    private static Boolean hasAccountField(String fieldApiName) {
        return Schema.SObjectType.Account.fields.getMap()
            .containsKey(fieldApiName == null ? '' : fieldApiName.toLowerCase());
    }

    private static String resolveRetailerDistributorFieldApi() {
        Map<String, Schema.SObjectField> accountFields = Schema.SObjectType.Account.fields.getMap();
        if (accountFields.containsKey('distributor__c')) {
            return 'Distributor__c';
        }
        if (accountFields.containsKey('distributor_account__c')) {
            return 'Distributor_Account__c';
        }
        return null;
    }

    //Added by Hari - Order Record Creation
    private static Boolean isUserLookupField(String objectApiName, String fieldApiName) {
        if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
            return false;
        }

        Map<String, Schema.SObjectField> fields = Schema.getGlobalDescribe()
            .get(objectApiName)
            .getDescribe()
            .fields.getMap();
        String normalizedField = fieldApiName.toLowerCase();
        if (!fields.containsKey(normalizedField)) {
            return false;
        }

        List<Schema.SObjectType> references = fields.get(normalizedField)
            .getDescribe()
            .getReferenceTo();
        return !references.isEmpty() && references[0] == User.SObjectType;
    }

    private static Id resolveOrderedByUserId(Account retailer) {
        if (retailer == null) {
            return null;
        }

        List<String> retailerOwnerUserFields = new List<String>{
            'AccountId__c',
            'Retailer_Owner__c',
            'User__c',
            'Assigned_To__c',
            'ASM__c',
            'Sales_Executive__c'
        };

        for (String fieldApi : retailerOwnerUserFields) {
            if (!isUserLookupField('Account', fieldApi)) {
                continue;
            }
            Object retailerOwnerUser = retailer.get(fieldApi);
            if (retailerOwnerUser != null) {
                return (Id) retailerOwnerUser;
            }
        }

        return retailer.OwnerId;
    }

    private static Id getCurrentUserDistributorAccountId() {
        List<User> users = [
            SELECT ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (users.isEmpty() || users[0].ContactId == null) {
            return null;
        }

        List<Contact> contacts = [
            SELECT AccountId
            FROM Contact
            WHERE Id = :users[0].ContactId
            LIMIT 1
        ];
        if (contacts.isEmpty()) {
            return null;
        }

        return contacts[0].AccountId;
    }

    private static Id resolveDistributorIdForRetailer(
        Account retailer,
        Id fallbackDistributorId
    ) {
        if (retailer == null) {
            return fallbackDistributorId;
        }

        String distributorFieldApi = resolveRetailerDistributorFieldApi();
        if (!String.isBlank(distributorFieldApi)) {
            Object distributorValue = retailer.get(distributorFieldApi);
            if (distributorValue != null) {
                return (Id) distributorValue;
            }
        }

        return fallbackDistributorId;
    }

    private static String resolveBeatsNameForRetailer(Account retailer) {
        if (
            retailer == null ||
            !hasAccountField(RETAILER_BEATS_SOURCE_FIELD)
        ) {
            return null;
        }

        Object beatsValue = retailer.get(RETAILER_BEATS_SOURCE_FIELD);
        return beatsValue == null ? null : String.valueOf(beatsValue);
    }

    private static Id getSecondaryOrderRecordTypeId() {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = :ORDER_SOBJECT
            AND Name = :ORDER_RECORD_TYPE_NAME
            LIMIT 1
        ];
        if (recordTypes.isEmpty()) {
            throwAuraHandledException(
                'Secondary Order record type was not found on Order.'
            );
        }
        return recordTypes[0].Id;
    }

    private static Id getSecondaryOrderLineItemRecordTypeId() {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = :ORDER_LINE_ITEM_SOBJECT
            AND Name = :ORDER_LINE_ITEM_RECORD_TYPE_NAME
            LIMIT 1
        ];
        if (recordTypes.isEmpty()) {
            throwAuraHandledException(
                'Secondary Order Line Item record type was not found on Order Line Item.'
            );
        }
        return recordTypes[0].Id;
    }

    private static BulkOrderCreationResult createBulkOrders(
        List<Map<String, String>> dataRows,
        Blob fileBlob,
        String fileName
    ) {
        BulkOrderCreationResult result = new BulkOrderCreationResult();
        result.orderIds = new List<Id>();
        result.orderNames = new List<String>();

        Set<String> retailerCodes = new Set<String>();
        Set<String> productCodes = new Set<String>();
        for (Map<String, String> row : dataRows) {
            collectCode(retailerCodes, row.get('Retailer Code'));
            collectCode(productCodes, row.get('Product Code'));
        }

        Map<String, Account> retailers = loadRetailersForOrderCreation(retailerCodes);
        Map<String, SObject> products = loadProducts(productCodes);
        BulkPricingContext pricingContext = buildPricingContext(retailers, products);
        Id orderRecordTypeId = getSecondaryOrderRecordTypeId();
        Id orderLineItemRecordTypeId = getSecondaryOrderLineItemRecordTypeId();
        Id fallbackDistributorId = getCurrentUserDistributorAccountId();

        Map<String, List<Map<String, String>>> rowsByRefOrder =
            groupOrderRowsByReference(dataRows);

        List<Order__c> ordersToInsert = new List<Order__c>();
        Map<String, Order__c> orderByRefKey = new Map<String, Order__c>();
        Map<String, List<Order_Line_Item__c>> lineItemsByRefKey =
            new Map<String, List<Order_Line_Item__c>>();
        Map<Id, Id> retailerAccountIdToOrderedByUser = new Map<Id, Id>();
        Set<Id> distributorIdsForAttachment = new Set<Id>();

        for (String refKey : rowsByRefOrder.keySet()) {
            List<Map<String, String>> groupRows = rowsByRefOrder.get(refKey);
            if (groupRows == null || groupRows.isEmpty()) {
                continue;
            }

            Map<String, String> headerRow = groupRows[0];
            String retailerCode = headerRow.get('Retailer Code');
            Account retailer = null;
            if (!String.isBlank(retailerCode)) {
                retailer = retailers.get(retailerCode.trim().toUpperCase());
            }
            if (retailer == null) {
                throwAuraHandledException(
                    'Retailer could not be resolved for reference "' +
                    headerRow.get('Ref Order No.') +
                    '".'
                );
            }

            Id distributorId = resolveDistributorIdForRetailer(
                retailer,
                fallbackDistributorId
            );
            if (distributorId != null) {
                distributorIdsForAttachment.add(distributorId);
            }

            OrderTotals orderTotals = new OrderTotals();
            List<Order_Line_Item__c> pendingLineItems = new List<Order_Line_Item__c>();

            for (Map<String, String> row : groupRows) {
                Decimal quantity = parseDecimal(row.get('Quantity'));
                if (quantity == null) {
                    quantity = 0;
                }

                Id productId = getProductId(products, row.get('Product Code'));
                if (productId == null) {
                    throwAuraHandledException(
                        'Product could not be resolved for reference "' +
                        headerRow.get('Ref Order No.') +
                        '".'
                    );
                }

                BulkUploadLineSummary lineSummary = buildLineSummary(
                    row,
                    products,
                    retailers,
                    pricingContext,
                    quantity,
                    false
                );
                orderTotals.addLine(lineSummary, retailer, pricingContext);

                Order_Line_Item__c lineItem = new Order_Line_Item__c();
                lineItem.RecordTypeId = orderLineItemRecordTypeId;
                lineItem.Products__c = productId;
                lineItem.Ordered_Quantity__c = quantity;
                lineItem.Product_Price__c = lineSummary.price;
                lineItem.Is_Promotional__c = false;
                pendingLineItems.add(lineItem);
            }

            Order__c order = buildOrderHeader(
                headerRow,
                retailer,
                distributorId,
                orderRecordTypeId,
                fileName,
                orderTotals
            );
            retailerAccountIdToOrderedByUser.put(
                retailer.Id,
                resolveOrderedByUserId(retailer)
            );
            ordersToInsert.add(order);
            orderByRefKey.put(refKey, order);
            lineItemsByRefKey.put(refKey, pendingLineItems);
        }

        Savepoint savepointBeforeDml = Database.setSavepoint();
        try {
            insert ordersToInsert;

            List<Order__c> orderedByUpdates = new List<Order__c>();
            for (Order__c insertedOrder : ordersToInsert) {
                Id orderedByUserId = retailerAccountIdToOrderedByUser.get(
                    insertedOrder.Account__c
                );
                if (orderedByUserId != null) {
                    orderedByUpdates.add(
                        new Order__c(
                            Id = insertedOrder.Id,
                            Ordered_By__c = orderedByUserId
                        )
                    );
                }
            }
            if (!orderedByUpdates.isEmpty()) {
                update orderedByUpdates;
            }

            List<Order_Line_Item__c> lineItemsToInsert = new List<Order_Line_Item__c>();
            for (String refKey : orderByRefKey.keySet()) {
                Order__c insertedOrder = orderByRefKey.get(refKey);
                for (Order_Line_Item__c lineItem : lineItemsByRefKey.get(refKey)) {
                    lineItem.Order__c = insertedOrder.Id;
                    lineItemsToInsert.add(lineItem);
                }
            }

            if (!lineItemsToInsert.isEmpty()) {
                insert lineItemsToInsert;
            }

            Set<Id> insertedOrderIds = new Set<Id>();
            for (Order__c insertedOrder : ordersToInsert) {
                insertedOrderIds.add(insertedOrder.Id);
            }

            Map<Id, Order__c> insertedOrdersById = new Map<Id, Order__c>([
                SELECT Id, Name
                FROM Order__c
                WHERE Id IN :insertedOrderIds
            ]);

            result.orderIds = new List<Id>();
            result.orderNames = new List<String>();
            for (Order__c insertedOrder : ordersToInsert) {
                Order__c persistedOrder = insertedOrdersById.get(insertedOrder.Id);
                result.orderIds.add(insertedOrder.Id);
                result.orderNames.add(
                    persistedOrder == null ? '' : persistedOrder.Name
                );
            }

            storeBulkUploadReceivedDocument(
                fileBlob,
                fileName,
                distributorIdsForAttachment,
                result.orderIds
            );

            result.ordersCreated = ordersToInsert.size();
        } catch (Exception ex) {
            Database.rollback(savepointBeforeDml);
            throwAuraHandledException(
                'Order creation failed: ' + ex.getMessage()
            );
        }

        return result;
    }

    //Added by Hari - Invoice Record Creation
    private static Id getSecondaryInvoiceRecordTypeId() {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = :INVOICE_SOBJECT
            AND Name = :INVOICE_RECORD_TYPE_NAME
            LIMIT 1
        ];
        if (recordTypes.isEmpty()) {
            throwAuraHandledException(
                'Secondary Invoice record type was not found on Invoice.'
            );
        }
        return recordTypes[0].Id;
    }

    private static Map<String, SObject> loadOrdersForInvoiceCreation(Set<String> orderNumbers) {
        Map<String, SObject> orderMap = new Map<String, SObject>();
        if (orderNumbers.isEmpty() || !Schema.getGlobalDescribe().containsKey(ORDER_SOBJECT)) {
            return orderMap;
        }

        String orderNumberField = getOrderNumberFieldApiName();
        Set<String> normalizedNumbers = new Set<String>();
        for (String orderNumber : orderNumbers) {
            String normalizedNumber = normalizeOrderNumber(orderNumber);
            if (!String.isBlank(normalizedNumber)) {
                normalizedNumbers.add(normalizedNumber);
            }
        }
        if (normalizedNumbers.isEmpty()) {
            return orderMap;
        }

        List<String> selectFields = new List<String>{ 'Id', orderNumberField, 'Account__c' };
        if (hasOrderField('AccountId__c')) {
            selectFields.add('AccountId__c');
        }

        String query =
            'SELECT ' +
            String.join(selectFields, ', ') +
            ' FROM ' +
            ORDER_SOBJECT +
            ' WHERE ' +
            orderNumberField +
            ' IN :normalizedNumbers';

        for (SObject orderRecord : Database.query(query)) {
            Object numberValue = orderRecord.get(orderNumberField);
            if (numberValue != null) {
                orderMap.put(
                    normalizeOrderNumber(String.valueOf(numberValue)).toUpperCase(),
                    orderRecord
                );
            }
        }

        return orderMap;
    }

    private static Account loadDistributorAccountDetails(Id distributorAccountId) {
        if (distributorAccountId == null) {
            return null;
        }

        List<String> selectFields = new List<String>{ 'Id', 'Name' };
        if (hasAccountField('GSTIN__c')) {
            selectFields.add('GSTIN__c');
        }
        if (hasRetailerStateField()) {
            selectFields.add(RETAILER_STATE_FIELD);
        }

        String query =
            'SELECT ' +
            String.join(selectFields, ', ') +
            ' FROM Account WHERE Id = :distributorAccountId LIMIT 1';
        List<Account> distributors = Database.query(query);
        return distributors.isEmpty() ? null : distributors[0];
    }

    private static String buildInvoiceNumber(String invPrefix, Integer num) {
        Integer padLen = 10 - invPrefix.length() - String.valueOf(num).length();
        String padding = '0'.repeat(padLen > 0 ? padLen : 0);
        return invPrefix + padding + num;
    }

    private static String generateNextInvoiceNumber(Id distributorAccountId) {
        List<User> userList = [
            SELECT
                Id,
                Invoice_Number_Prefix__c,
                Invoice_Start_Number__c,
                Reset_Invoice_Sequence__c
            FROM User
            WHERE AccountId = :distributorAccountId
            AND IsActive = TRUE
            AND Primary_Distributor__c = TRUE
            LIMIT 1
        ];

        if (userList.isEmpty()) {
            throwAuraHandledException(
                'Distributor configuration missing. Cannot generate invoice number. ' +
                'Please contact System Administrator.'
            );
        }

        User dist = userList[0];

        if (String.isBlank(dist.Invoice_Number_Prefix__c)) {
            throwAuraHandledException(
                'Update the "Invoice Number Prefix" in your Profile to continue creating new Invoices!'
            );
        }

        if (dist.Invoice_Start_Number__c == null) {
            throwAuraHandledException(
                'Update the "Invoice Start Number" in your Profile to continue creating new Invoices!'
            );
        }

        Integer startNum = Integer.valueOf(dist.Invoice_Start_Number__c);
        Boolean isReset = dist.Reset_Invoice_Sequence__c == true;
        Integer nextNum;

        try {
            List<Invoice_Sequence__c> seqList = [
                SELECT Id, Last_Number__c
                FROM Invoice_Sequence__c
                WHERE Distributor_Account__c = :distributorAccountId
                LIMIT 1
                FOR UPDATE
            ];

            Invoice_Sequence__c seq;

            if (isReset) {
                nextNum = startNum;
                seq = seqList.isEmpty()
                    ? new Invoice_Sequence__c(Distributor_Account__c = distributorAccountId)
                    : seqList[0];
            } else if (seqList.isEmpty()) {
                nextNum = startNum;
                seq = new Invoice_Sequence__c(Distributor_Account__c = distributorAccountId);
            } else {
                seq = seqList[0];
                nextNum = Integer.valueOf(seq.Last_Number__c) + 1;
            }

            seq.Last_Number__c = nextNum;
            upsert seq;

            if (isReset) {
                dist.Reset_Invoice_Sequence__c = false;
                update dist;
            }
        } catch (QueryException ex) {
            if (ex.getMessage().contains('UNABLE_TO_LOCK_ROW')) {
                throwAuraHandledException(
                    'Another invoice is being saved simultaneously. ' +
                    'Please try again in a moment.'
                );
            }
            throwAuraHandledException(
                'Error generating invoice number: ' + ex.getMessage()
            );
        }

        return buildInvoiceNumber(dist.Invoice_Number_Prefix__c, nextNum);
    }

    private static BulkInvoiceCreationResult createBulkInvoices(
        List<Map<String, String>> dataRows,
        Blob fileBlob,
        String fileName
    ) {
        BulkInvoiceCreationResult result = new BulkInvoiceCreationResult();
        result.invoiceIds = new List<Id>();
        result.invoiceNames = new List<String>();

        Set<String> retailerCodes = new Set<String>();
        Set<String> productCodes = new Set<String>();
        Set<String> orderNumbers = new Set<String>();
        for (Map<String, String> row : dataRows) {
            collectCode(retailerCodes, row.get('Retailer Code'));
            collectCode(productCodes, row.get('Product Code'));
            collectCode(orderNumbers, row.get('Order Number'));
        }

        Map<String, Account> retailers = loadRetailersForOrderCreation(retailerCodes);
        Map<String, SObject> products = loadProducts(productCodes);
        Map<String, SObject> orders = loadOrdersForInvoiceCreation(orderNumbers);
        BulkPricingContext pricingContext = buildPricingContext(retailers, products);
        Id invoiceRecordTypeId = getSecondaryInvoiceRecordTypeId();
        Id fallbackDistributorId = getCurrentUserDistributorAccountId();

        Map<String, List<Map<String, String>>> rowsByRefInvoice =
            groupInvoiceRowsByReference(dataRows);

        List<Invoice__c> invoicesToInsert = new List<Invoice__c>();
        Map<String, Invoice__c> invoiceByRefKey = new Map<String, Invoice__c>();
        Map<String, List<Invoice_Line_Item__c>> lineItemsByRefKey =
            new Map<String, List<Invoice_Line_Item__c>>();
        Set<Id> distributorIdsForAttachment = new Set<Id>();

        for (String refKey : rowsByRefInvoice.keySet()) {
            List<Map<String, String>> groupRows = rowsByRefInvoice.get(refKey);
            if (groupRows == null || groupRows.isEmpty()) {
                continue;
            }

            Map<String, String> headerRow = groupRows[0];
            String retailerCode = headerRow.get('Retailer Code');
            Account retailer = null;
            if (!String.isBlank(retailerCode)) {
                retailer = retailers.get(retailerCode.trim().toUpperCase());
            }
            if (retailer == null) {
                throwAuraHandledException(
                    'Retailer could not be resolved for reference "' +
                    headerRow.get('Ref Invoice No.') +
                    '".'
                );
            }

            SObject linkedOrder = null;
            String orderNumber = headerRow.get('Order Number');
            if (!String.isBlank(orderNumber)) {
                linkedOrder = orders.get(normalizeOrderNumber(orderNumber).toUpperCase());
            }
            if (linkedOrder == null) {
                throwAuraHandledException(
                    'Order could not be resolved for reference "' +
                    headerRow.get('Ref Invoice No.') +
                    '".'
                );
            }

            Id distributorId = resolveDistributorIdForRetailer(
                retailer,
                fallbackDistributorId
            );
            if (distributorId == null && linkedOrder.get('AccountId__c') != null) {
                distributorId = (Id) linkedOrder.get('AccountId__c');
            }
            if (distributorId != null) {
                distributorIdsForAttachment.add(distributorId);
            }

            if (distributorId == null) {
                throwAuraHandledException(
                    'Distributor could not be resolved for reference "' +
                    headerRow.get('Ref Invoice No.') +
                    '".'
                );
            }

            Account distributorAccount = loadDistributorAccountDetails(distributorId);
            InvoiceTotals invoiceTotals = new InvoiceTotals();
            List<Invoice_Line_Item__c> pendingLineItems = new List<Invoice_Line_Item__c>();

            for (Map<String, String> row : groupRows) {
                Decimal quantity = parseDecimal(row.get('Quantity'));
                if (quantity == null) {
                    quantity = 0;
                }

                Id productId = getProductId(products, row.get('Product Code'));
                if (productId == null) {
                    throwAuraHandledException(
                        'Product could not be resolved for reference "' +
                        headerRow.get('Ref Invoice No.') +
                        '".'
                    );
                }

                BulkUploadLineSummary lineSummary = buildLineSummary(
                    row,
                    products,
                    retailers,
                    pricingContext,
                    quantity,
                    true
                );
                invoiceTotals.addLine(lineSummary, retailer, pricingContext);

                Invoice_Line_Item__c lineItem = new Invoice_Line_Item__c();
                lineItem.Product__c = productId;
                lineItem.Quantity__c = quantity;
                lineItem.Price__c = lineSummary.price;
                lineItem.Total_Amount__c = lineSummary.totalAmountInclTax;
                lineItem.Discount_1__c = lineSummary.tod;
                lineItem.Discount_2__c = lineSummary.discountAmount;
                lineItem.Is_Promotional__c = false;
                pendingLineItems.add(lineItem);
            }

            String invoiceNumber = generateNextInvoiceNumber(distributorId);
            Invoice__c invoice = buildInvoiceHeader(
                headerRow,
                retailer,
                distributorId,
                distributorAccount,
                linkedOrder,
                invoiceRecordTypeId,
                fileName,
                invoiceNumber,
                invoiceTotals
            );
            invoicesToInsert.add(invoice);
            invoiceByRefKey.put(refKey, invoice);
            lineItemsByRefKey.put(refKey, pendingLineItems);
        }

        Savepoint savepointBeforeDml = Database.setSavepoint();
        try {
            insert invoicesToInsert;

            List<Invoice_Line_Item__c> lineItemsToInsert = new List<Invoice_Line_Item__c>();
            for (String refKey : invoiceByRefKey.keySet()) {
                Invoice__c insertedInvoice = invoiceByRefKey.get(refKey);
                for (Invoice_Line_Item__c lineItem : lineItemsByRefKey.get(refKey)) {
                    lineItem.Invoice__c = insertedInvoice.Id;
                    lineItemsToInsert.add(lineItem);
                }
            }

            if (!lineItemsToInsert.isEmpty()) {
                insert lineItemsToInsert;
            }

            Set<Id> insertedInvoiceIds = new Set<Id>();
            for (Invoice__c insertedInvoice : invoicesToInsert) {
                insertedInvoiceIds.add(insertedInvoice.Id);
            }

            Map<Id, Invoice__c> insertedInvoicesById = new Map<Id, Invoice__c>([
                SELECT Id, Name, Invoice_Number__c
                FROM Invoice__c
                WHERE Id IN :insertedInvoiceIds
            ]);

            result.invoiceIds = new List<Id>();
            result.invoiceNames = new List<String>();
            for (Invoice__c insertedInvoice : invoicesToInsert) {
                Invoice__c persistedInvoice = insertedInvoicesById.get(insertedInvoice.Id);
                result.invoiceIds.add(insertedInvoice.Id);
                result.invoiceNames.add(
                    persistedInvoice == null
                        ? insertedInvoice.Invoice_Number__c
                        : persistedInvoice.Invoice_Number__c
                );
            }

            storeBulkUploadReceivedDocument(
                fileBlob,
                fileName,
                distributorIdsForAttachment,
                result.invoiceIds
            );

            result.invoicesCreated = invoicesToInsert.size();
        } catch (Exception ex) {
            Database.rollback(savepointBeforeDml);
            throwAuraHandledException(
                'Invoice creation failed: ' + ex.getMessage()
            );
        }

        return result;
    }

    private static Map<String, List<Map<String, String>>> groupInvoiceRowsByReference(
        List<Map<String, String>> dataRows
    ) {
        Map<String, List<Map<String, String>>> rowsByRefInvoice =
            new Map<String, List<Map<String, String>>>();
        List<String> orderedRefKeys = new List<String>();

        for (Map<String, String> row : dataRows) {
            String refNo = row.get('Ref Invoice No.');
            if (String.isBlank(refNo)) {
                continue;
            }

            String refKey = refNo.trim().toUpperCase();
            if (!rowsByRefInvoice.containsKey(refKey)) {
                rowsByRefInvoice.put(refKey, new List<Map<String, String>>());
                orderedRefKeys.add(refKey);
            }
            rowsByRefInvoice.get(refKey).add(row);
        }

        Map<String, List<Map<String, String>>> orderedGroups =
            new Map<String, List<Map<String, String>>>();
        for (String refKey : orderedRefKeys) {
            orderedGroups.put(refKey, rowsByRefInvoice.get(refKey));
        }

        return orderedGroups;
    }

    private static Invoice__c buildInvoiceHeader(
        Map<String, String> headerRow,
        Account retailer,
        Id distributorId,
        Account distributorAccount,
        SObject linkedOrder,
        Id invoiceRecordTypeId,
        String fileName,
        String invoiceNumber,
        InvoiceTotals invoiceTotals
    ) {
        String retailerState = retailer != null && hasRetailerStateField()
            ? retailer.Primary_State__c
            : '';
        String distributorState = distributorAccount != null && hasRetailerStateField()
            ? distributorAccount.Primary_State__c
            : pricingContextDistributorState();
        Boolean sameState = statesMatch(retailerState, distributorState);
        Map<String, Decimal> taxRates = getTaxRates(retailerState, distributorState);

        Invoice__c invoice = new Invoice__c();
        invoice.RecordTypeId = invoiceRecordTypeId;
        invoice.Order__c = linkedOrder.Id;
        invoice.Retailer_Account__c = retailer.Id;
        invoice.Distributor_Account__c = distributorId;
        invoice.Invoice_Number__c = invoiceNumber;
        invoice.Name = invoiceNumber;
        invoice.Invoice_Date__c = parseDate(headerRow.get('Invoice Date'));
        if (invoice.Invoice_Date__c == null) {
            invoice.Invoice_Date__c = System.today();
        }
        invoice.Status__c = mapInvoiceStatus(headerRow.get('Status'));
        invoice.Type__c = INVOICE_TYPE_BULK_UPLOAD;

        if (hasInvoiceField('Custom_Invoice_Number__c')) {
            invoice.put('Custom_Invoice_Number__c', invoiceNumber);
        }
        if (hasInvoiceField(ORDER_FILE_NAME_FIELD)) {
            invoice.put(ORDER_FILE_NAME_FIELD, fileName);
        }
        if (hasInvoiceField(ORDER_DATA_UPLOAD_FIELD)) {
            invoice.put(
                ORDER_DATA_UPLOAD_FIELD,
                isDataUploadTrue(headerRow.get('Data Upload'))
            );
        }
        if (hasInvoiceField(INVOICE_REF_FIELD)) {
            invoice.put(INVOICE_REF_FIELD, headerRow.get('Ref Invoice No.').trim());
        }
        if (hasInvoiceField('Payment_Status__c')) {
            invoice.put('Payment_Status__c', INVOICE_PAYMENT_STATUS_NOT_PAID);
        }
        if (hasInvoiceField('Place_of_Supply__c') && !String.isBlank(retailerState)) {
            invoice.put('Place_of_Supply__c', retailerState);
        }
        if (hasInvoiceField('Seller_Name__c') && distributorAccount != null) {
            invoice.put('Seller_Name__c', distributorAccount.Name);
        }
        if (
            hasInvoiceField('Seller_GSTIN__c') &&
            distributorAccount != null &&
            hasAccountField('GSTIN__c')
        ) {
            invoice.put('Seller_GSTIN__c', distributorAccount.get('GSTIN__c'));
        }
        if (hasInvoiceField('Tax_Information__c')) {
            invoice.put(
                'Tax_Information__c',
                sameState ? TAX_INFO_STATE_MATCH : TAX_INFO_CENTRAL
            );
        }

        if (sameState) {
            invoice.SGST__c = taxRates.get('SGST');
            invoice.CGST__c = taxRates.get('CGST');
            invoice.IGST__c = 0;
        } else {
            invoice.SGST__c = 0;
            invoice.CGST__c = 0;
            invoice.IGST__c = taxRates.get('IGST');
        }

        invoice.Invoice_Amount__c = invoiceTotals.invoiceAmount;
        invoice.Taxable_Amount__c = invoiceTotals.taxableAmount;
        invoice.Total_GST__c = invoiceTotals.totalGst;
        invoice.Total_Quantity__c = invoiceTotals.totalQuantity;
        invoice.Sub_Total__c = invoiceTotals.subTotal;
        invoice.CGST_Amount__c = invoiceTotals.totalCgst;
        invoice.SGST_Amount__c = invoiceTotals.totalSgst;
        invoice.IGST_Amount__c = invoiceTotals.totalIgst;

        if (hasInvoiceField('Invoice_Amount_In_Words__c')) {
            invoice.put(
                'Invoice_Amount_In_Words__c',
                convertAmountToWords(invoiceTotals.invoiceAmount)
            );
        }

        Decimal headerDiscount2 = parseDecimal(headerRow.get('Discount 2%'));
        if (headerDiscount2 != null && hasInvoiceField('Discount_2__c')) {
            invoice.put('Discount_2__c', headerDiscount2);
        }

        return invoice;
    }

    private static String pricingContextDistributorState() {
        return getDistributorPrimaryState();
    }

    private static Boolean statesMatch(String retailerState, String distributorState) {
        String retailer = retailerState == null ? '' : retailerState.trim();
        String distributor = distributorState == null ? '' : distributorState.trim();
        return !String.isBlank(retailer) &&
            !String.isBlank(distributor) &&
            retailer.equalsIgnoreCase(distributor);
    }

    private static String mapInvoiceStatus(String excelStatus) {
        if (String.isBlank(excelStatus)) {
            return 'Draft';
        }

        String normalized = excelStatus.trim().toUpperCase();
        if (normalized == 'DRAFT') {
            return 'Draft';
        }
        if (normalized == 'CONFIRMED') {
            return 'Confirmed';
        }
        return excelStatus.trim();
    }

    private static Boolean hasInvoiceField(String fieldApiName) {
        if (!Schema.getGlobalDescribe().containsKey(INVOICE_SOBJECT)) {
            return false;
        }
        return Schema.getGlobalDescribe()
            .get(INVOICE_SOBJECT)
            .getDescribe()
            .fields.getMap()
            .containsKey(fieldApiName == null ? '' : fieldApiName.toLowerCase());
    }

    private static String convertAmountToWords(Decimal amount) {
        if (amount == null) {
            return '';
        }

        Long rupees = amount.setScale(0, System.RoundingMode.HALF_UP).longValue();
        if (rupees == 0) {
            return 'Zero Only';
        }

        return convertNumberToWords(rupees) + ' Only';
    }

    private static String convertNumberToWords(Long numberValue) {
        if (numberValue == 0) {
            return 'Zero';
        }

        List<String> belowTwenty = new List<String>{
            '',
            'One',
            'Two',
            'Three',
            'Four',
            'Five',
            'Six',
            'Seven',
            'Eight',
            'Nine',
            'Ten',
            'Eleven',
            'Twelve',
            'Thirteen',
            'Fourteen',
            'Fifteen',
            'Sixteen',
            'Seventeen',
            'Eighteen',
            'Nineteen'
        };
        List<String> tensWords = new List<String>{
            '',
            '',
            'Twenty',
            'Thirty',
            'Forty',
            'Fifty',
            'Sixty',
            'Seventy',
            'Eighty',
            'Ninety'
        };

        if (numberValue < 20) {
            return belowTwenty[Integer.valueOf(numberValue)];
        }
        if (numberValue < 100) {
            Integer tens = Integer.valueOf(numberValue / 10);
            Integer ones = Integer.valueOf(Math.mod(numberValue, 10));
            return tensWords[tens] +
                (ones > 0 ? ' ' + belowTwenty[ones] : '');
        }
        if (numberValue < 1000) {
            Integer hundreds = Integer.valueOf(numberValue / 100);
            Long remainder = Math.mod(numberValue, 100);
            return belowTwenty[hundreds] +
                ' Hundred' +
                (remainder > 0 ? ' and ' + convertNumberToWords(remainder) : '');
        }
        if (numberValue < 100000) {
            Long thousands = numberValue / 1000;
            Long remainder = Math.mod(numberValue, 1000);
            return convertNumberToWords(thousands) +
                ' Thousand' +
                (remainder > 0 ? ' ' + convertNumberToWords(remainder) : '');
        }
        if (numberValue < 10000000) {
            Long lakhs = numberValue / 100000;
            Long remainder = Math.mod(numberValue, 100000);
            return convertNumberToWords(lakhs) +
                ' Lakh' +
                (lakhs > 1 ? 's' : '') +
                (remainder > 0 ? ' ' + convertNumberToWords(remainder) : '');
        }

        Long crores = numberValue / 10000000;
        Long remainder = Math.mod(numberValue, 10000000);
        return convertNumberToWords(crores) +
            ' Crore' +
            (crores > 1 ? 's' : '') +
            (remainder > 0 ? ' ' + convertNumberToWords(remainder) : '');
    }

    private class InvoiceTotals {
        public Decimal totalQuantity = 0;
        public Decimal invoiceAmount = 0;
        public Decimal subTotal = 0;
        public Decimal taxableAmount = 0;
        public Decimal totalGst = 0;
        public Decimal totalCgst = 0;
        public Decimal totalSgst = 0;
        public Decimal totalIgst = 0;
 
        public void addLine(
            BulkUploadLineSummary lineSummary,
            Account retailer,
            BulkPricingContext pricingContext
        ) {
            Decimal quantity = lineSummary.quantity == null ? 0 : lineSummary.quantity;
            totalQuantity += quantity;
            invoiceAmount += zeroIfNull(lineSummary.totalAmountInclTax);
            subTotal += zeroIfNull(lineSummary.amount);
            taxableAmount += zeroIfNull(lineSummary.taxableAmount);
            totalGst += zeroIfNull(lineSummary.totalGst);

            String retailerState = retailer != null && hasRetailerStateField()
                ? retailer.Primary_State__c
                : '';
            Map<String, Decimal> taxRates = pricingContext == null
                ? new Map<String, Decimal>()
                : pricingContext.getTaxRatesForRetailer(retailerState);
            Map<String, Decimal> gstSplit = calculateLineGstSplit(
                lineSummary.taxableAmount,
                taxRates
            );
            totalCgst += zeroIfNull(gstSplit.get('CGST'));
            totalSgst += zeroIfNull(gstSplit.get('SGST'));
            totalIgst += zeroIfNull(gstSplit.get('IGST'));
        }
    }

    private class BulkInvoiceCreationResult {
        public Integer invoicesCreated;
        public List<Id> invoiceIds;
        public List<String> invoiceNames;
    }

    private static Map<String, List<Map<String, String>>> groupOrderRowsByReference(
        List<Map<String, String>> dataRows
    ) {
        Map<String, List<Map<String, String>>> rowsByRefOrder =
            new Map<String, List<Map<String, String>>>();
        List<String> orderedRefKeys = new List<String>();

        for (Map<String, String> row : dataRows) {
            String refNo = row.get('Ref Order No.');
            if (String.isBlank(refNo)) {
                continue;
            }

            String refKey = refNo.trim().toUpperCase();
            if (!rowsByRefOrder.containsKey(refKey)) {
                rowsByRefOrder.put(refKey, new List<Map<String, String>>());
                orderedRefKeys.add(refKey);
            }
            rowsByRefOrder.get(refKey).add(row);
        }

        Map<String, List<Map<String, String>>> orderedGroups =
            new Map<String, List<Map<String, String>>>();
        for (String refKey : orderedRefKeys) {
            orderedGroups.put(refKey, rowsByRefOrder.get(refKey));
        }

        return orderedGroups;
    }

    private static Order__c buildOrderHeader(
        Map<String, String> headerRow,
        Account retailer,
        Id distributorId,
        Id orderRecordTypeId,
        String fileName,
        OrderTotals orderTotals
    ) {
        Order__c order = new Order__c();
        order.RecordTypeId = orderRecordTypeId;
        order.Account__c = retailer.Id;
        order.Ordered_By__c = resolveOrderedByUserId(retailer);
        order.Type__c = ORDER_TYPE_BULK_UPLOAD;
        order.Status__c = ORDER_STATUS_PLACED;
        order.EffectiveDate__c = parseDate(headerRow.get('Order Date'));
        if (order.EffectiveDate__c == null) {
            order.EffectiveDate__c = System.today();
        }

        if (distributorId != null) {
            order.AccountId__c = distributorId;
        }

        if (hasOrderField(ORDER_REF_FIELD)) {
            order.put(ORDER_REF_FIELD, headerRow.get('Ref Order No.').trim());
        }
        if (hasOrderField(ORDER_FILE_NAME_FIELD)) {
            order.put(ORDER_FILE_NAME_FIELD, fileName);
        }
        if (hasOrderField(ORDER_DATA_UPLOAD_FIELD)) {
            order.put(
                ORDER_DATA_UPLOAD_FIELD,
                isDataUploadTrue(headerRow.get('Data Upload'))
            );
        }

        String beatsName = resolveBeatsNameForRetailer(retailer);
        if (!String.isBlank(beatsName) && hasOrderField(ORDER_BEATS_FIELD)) {
            order.put(ORDER_BEATS_FIELD, beatsName);
        }

        order.Total_order_value__c = orderTotals.totalOrderValue;
        order.Total_Quantity__c = orderTotals.totalQuantity;
        order.Price__c = orderTotals.priceTotal;
        order.Sub_Total__c = orderTotals.subTotal;
        order.Discount_Amount_Order__c = orderTotals.discountAmount;
        order.totalCGST__c = orderTotals.totalCgst;
        order.totalSGST__c = orderTotals.totalSgst;
        order.totalIGST__c = orderTotals.totalIgst;

        return order;
    }

    private static Boolean hasOrderField(String fieldApiName) {
        return Schema.SObjectType.Order__c.fields.getMap()
            .containsKey(fieldApiName == null ? '' : fieldApiName.toLowerCase());
    }

    private static void storeBulkUploadReceivedDocument(
        Blob fileBlob,
        String fileName,
        Set<Id> distributorAccountIds,
        List<Id> createdOrderIds
    ) {
        if (fileBlob == null || String.isBlank(fileName)) {
            return;
        }

        Schema.SObjectType receivedDocumentType = Schema.getGlobalDescribe()
            .get(RECEIVED_DOCUMENT_SOBJECT);
        if (receivedDocumentType == null) {
            throwAuraHandledException(
                'Received Document object is not available in this org.'
            );
        }

        SObject receivedDocument = buildReceivedDocumentRecord(
            receivedDocumentType,
            fileName,
            distributorAccountIds,
            createdOrderIds
        );
        insert receivedDocument;

        ContentVersion contentVersion = new ContentVersion();
        contentVersion.Title = fileName;
        contentVersion.PathOnClient = fileName;
        contentVersion.VersionData = fileBlob;
        contentVersion.IsMajorVersion = true;
        contentVersion.FirstPublishLocationId = receivedDocument.Id;
        insert contentVersion;
    }

    private static SObject buildReceivedDocumentRecord(
        Schema.SObjectType receivedDocumentType,
        String fileName,
        Set<Id> distributorAccountIds,
        List<Id> createdOrderIds
    ) {
        SObject receivedDocument = receivedDocumentType.newSObject();
        receivedDocument.put('Name', fileName);

        String statusValue = resolveReceivedDocumentPicklistValue(
            'Status',
            new List<String>{ 'New', 'Received', 'Pending' }
        );
        if (!String.isBlank(statusValue)) {
            receivedDocument.put('Status', statusValue);
        }

        String priorityValue = resolveReceivedDocumentPicklistValue(
            'Priority',
            new List<String>{ 'Normal', 'Medium', 'Low' }
        );
        if (!String.isBlank(priorityValue)) {
            receivedDocument.put('Priority', priorityValue);
        }

        if (hasReceivedDocumentField('Source')) {
            receivedDocument.put('Source', BULK_UPLOAD_DOCUMENT_SOURCE);
        }

        Id relatedRecordId = resolveReceivedDocumentRelatedRecordId(
            distributorAccountIds,
            createdOrderIds
        );
        if (relatedRecordId != null && hasReceivedDocumentField('RelatedRecordId')) {
            receivedDocument.put('RelatedRecordId', relatedRecordId);
        }

        return receivedDocument;
    }

    private static Id resolveReceivedDocumentRelatedRecordId(
        Set<Id> distributorAccountIds,
        List<Id> createdOrderIds
    ) {
        if (distributorAccountIds != null && !distributorAccountIds.isEmpty()) {
            for (Id distributorAccountId : distributorAccountIds) {
                if (distributorAccountId != null) {
                    return distributorAccountId;
                }
            }
        }

        if (createdOrderIds != null && !createdOrderIds.isEmpty()) {
            return createdOrderIds[0];
        }

        return null;
    }

    private static Boolean hasReceivedDocumentField(String fieldApiName) {
        if (!Schema.getGlobalDescribe().containsKey(RECEIVED_DOCUMENT_SOBJECT)) {
            return false;
        }

        return Schema.getGlobalDescribe()
            .get(RECEIVED_DOCUMENT_SOBJECT)
            .getDescribe()
            .fields.getMap()
            .containsKey(fieldApiName == null ? '' : fieldApiName.toLowerCase());
    }

    private static String resolveReceivedDocumentPicklistValue(
        String fieldApiName,
        List<String> preferredValues
    ) {
        if (!hasReceivedDocumentField(fieldApiName)) {
            return null;
        }

        Schema.DescribeFieldResult fieldDescribe = Schema.getGlobalDescribe()
            .get(RECEIVED_DOCUMENT_SOBJECT)
            .getDescribe()
            .fields.getMap()
            .get(fieldApiName.toLowerCase())
            .getDescribe();
        if (fieldDescribe.getType() != Schema.DisplayType.PICKLIST) {
            return null;
        }

        Map<String, String> activeValues = new Map<String, String>();
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive()) {
                activeValues.put(entry.getValue().toUpperCase(), entry.getValue());
            }
        }

        if (preferredValues != null) {
            for (String preferredValue : preferredValues) {
                if (
                    !String.isBlank(preferredValue) &&
                    activeValues.containsKey(preferredValue.toUpperCase())
                ) {
                    return activeValues.get(preferredValue.toUpperCase());
                }
            }
        }

        return activeValues.isEmpty() ? null : activeValues.values()[0];
    }

    private class OrderTotals {
        public Decimal totalQuantity = 0;
        public Decimal totalOrderValue = 0;
        public Decimal priceTotal = 0;
        public Decimal subTotal = 0;
        public Decimal discountAmount = 0;
        public Decimal totalCgst = 0;
        public Decimal totalSgst = 0;
        public Decimal totalIgst = 0;

        public void addLine(
            BulkUploadLineSummary lineSummary,
            Account retailer,
            BulkPricingContext pricingContext
        ) {
            Decimal quantity = lineSummary.quantity == null ? 0 : lineSummary.quantity;
            totalQuantity += quantity;
            totalOrderValue += zeroIfNull(lineSummary.totalAmountInclTax);
            priceTotal += zeroIfNull(lineSummary.amount);
            subTotal += zeroIfNull(lineSummary.taxableAmount);
            discountAmount += zeroIfNull(lineSummary.tod) + zeroIfNull(lineSummary.discountAmount);

            String retailerState = retailer != null && hasRetailerStateField()
                ? retailer.Primary_State__c
                : '';
            Map<String, Decimal> taxRates = pricingContext == null
                ? new Map<String, Decimal>()
                : pricingContext.getTaxRatesForRetailer(retailerState);
            Map<String, Decimal> gstSplit = calculateLineGstSplit(
                lineSummary.taxableAmount,
                taxRates
            );
            totalCgst += zeroIfNull(gstSplit.get('CGST'));
            totalSgst += zeroIfNull(gstSplit.get('SGST'));
            totalIgst += zeroIfNull(gstSplit.get('IGST'));
        }
    }

    private class BulkUploadValidationContext {
        public List<BulkUploadError> errors;
        public List<Map<String, String>> dataRows;
        public Blob fileBlob;
    }

    @TestVisible
    private class BulkOrderCreationResult {
        public Integer ordersCreated;
        public List<Id> orderIds;
        public List<String> orderNames;
    }

    private static Boolean hasAccountActiveField() {
        return getRetailerActiveFieldApiName() != null;
    }

    private static String getRetailerActiveFieldApiName() {
        Map<String, Schema.SObjectField> accountFields =
            Schema.SObjectType.Account.fields.getMap();

        if (accountFields.containsKey('is_active__c')) {
            return RETAILER_ACTIVE_FIELD;
        }

        if (accountFields.containsKey('active__c')) {
            return 'Active__c';
        }

        return null;
    }

    private static Boolean hasRetailerStateField() {
        return Schema.SObjectType.Account.fields.getMap()
            .containsKey('primary_state__c');
    }

    private static Map<String, SObject> loadProducts(Set<String> productCodes) {
        Map<String, SObject> productMap = new Map<String, SObject>();
        if (productCodes.isEmpty()) {
            return productMap;
        }

        if (!Schema.getGlobalDescribe().containsKey(PRODUCT_SOBJECT)) {
            return productMap;
        }

        Map<String, Schema.SObjectField> productFields = Schema.getGlobalDescribe()
            .get(PRODUCT_SOBJECT)
            .getDescribe()
            .fields.getMap();

        if (!productFields.containsKey('product_code__c')) {
            return productMap;
        }

        Set<String> normalizedCodes = new Set<String>();
        for (String code : productCodes) {
            String normalizedCode = normalizeProductCode(code);
            if (!String.isBlank(normalizedCode)) {
                normalizedCodes.add(normalizedCode);
            }
        }

        if (normalizedCodes.isEmpty()) {
            return productMap;
        }

        String query =
            'SELECT Id, Name, ' + PRODUCT_CODE_FIELD + ' FROM ' +
            PRODUCT_SOBJECT + ' WHERE ' + PRODUCT_CODE_FIELD + ' IN :normalizedCodes';

        if (productFields.containsKey('isactive__c')) {
            query += ' AND ' + PRODUCT_ACTIVE_FIELD + ' = TRUE';
        }

        for (SObject product : Database.query(query)) {
            Object codeValue = product.get(PRODUCT_CODE_FIELD);
            if (codeValue != null) {
                productMap.put(normalizeProductCode(String.valueOf(codeValue)).toUpperCase(),product);
            }
        }

        return productMap;
    }

    private static BulkPricingContext buildPricingContext(Map<String, Account> retailers,Map<String, SObject> products){
        BulkPricingContext context = new BulkPricingContext();
        context.distributorState = getDistributorPrimaryState();
        context.regionToPricebookId = loadRegionPricebookMap();

        Set<Id> productIds = new Set<Id>();
        for (SObject product : products.values()) {
            productIds.add(product.Id);
        }

        Set<Id> pricebookIds = new Set<Id>();
        for (Account retailer : retailers.values()) {
            Id pricebookId = resolvePricebookIdForRetailer(retailer, context.regionToPricebookId);
            if (pricebookId != null) {
                pricebookIds.add(pricebookId);
            }
        }

        context.ptrByPricebookProductKey = loadPtrByPricebookAndProduct(pricebookIds,productIds);

        Set<Id> retailerAccountIds = new Set<Id>();
        for (Account retailer : retailers.values()) {
            retailerAccountIds.add(retailer.Id);
        }
        context.discountRecords = loadDiscountRecords(retailerAccountIds);
        context.productDetailsById = loadProductDetailsForTod(productIds);

        return context;
    }

    private static String getDistributorPrimaryState() {
        if (!hasRetailerStateField()) {
            return '';
        }

        List<User> users = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (users.isEmpty() || users[0].ContactId == null) {
            return '';
        }

        List<Contact> contacts = [SELECT AccountId FROM Contact WHERE Id = :users[0].ContactId LIMIT 1];
        if (contacts.isEmpty() || contacts[0].AccountId == null) {
            return '';
        }

        List<Account> distributorAccounts = [SELECT Primary_State__c FROM Account WHERE Id = :contacts[0].AccountId LIMIT 1];
        if (distributorAccounts.isEmpty()) {
            return '';
        }

        return distributorAccounts[0].Primary_State__c == null ? '' : distributorAccounts[0].Primary_State__c.trim();
    }

    private static Map<String, Id> loadRegionPricebookMap() {
        Map<String, Id> regionToPricebook = new Map<String, Id>();
        if (!Schema.getGlobalDescribe().containsKey(PRICE_BOOK_SOBJECT)) {
            return regionToPricebook;
        }

        for (Price_Book__c priceBook : [SELECT Id, Region__r.Name FROM Price_Book__c WHERE isActive__c = TRUE]){
            if (priceBook.Region__r != null && !String.isBlank(priceBook.Region__r.Name)) {
                regionToPricebook.put(priceBook.Region__r.Name.trim(), priceBook.Id);
            }
        }

        return regionToPricebook;
    }

    private static Id resolvePricebookIdForRetailer(
        Account retailer,
        Map<String, Id> regionToPricebookId
    ) {
        if (retailer == null || regionToPricebookId.isEmpty() || !hasRetailerStateField()) {
            return null;
        }

        String retailerState = retailer.Primary_State__c == null
            ? ''
            : retailer.Primary_State__c.trim();
        if (String.isBlank(retailerState)) {
            return null;
        }

        return regionToPricebookId.get(retailerState);
    }

    private static Map<String, Decimal> loadPtrByPricebookAndProduct(
        Set<Id> pricebookIds,
        Set<Id> productIds
    ) {
        Map<String, Decimal> ptrMap = new Map<String, Decimal>();
        if (pricebookIds.isEmpty() || productIds.isEmpty()) {
            return ptrMap;
        }

        if (!Schema.getGlobalDescribe().containsKey(PRICE_BOOK_ENTRY_SOBJECT)) {
            return ptrMap;
        }

        for (Price_Book_Entry__c entry : [
            SELECT Product__c, PTR__c, Price_Book__c
            FROM Price_Book_Entry__c
            WHERE isActive__c = TRUE
            AND Price_Book__c IN :pricebookIds
            AND Product__c IN :productIds
            AND Type__c = :PRICE_BOOK_ENTRY_TYPE_RETAILER
        ]) {
            String key = buildPricebookProductKey(entry.Price_Book__c, entry.Product__c);
            if (entry.PTR__c != null) {
                ptrMap.put(
                    key,
                    entry.PTR__c.setScale(2, System.RoundingMode.HALF_UP)
                );
            } else {
                ptrMap.put(key, 0);
            }
        }

        return ptrMap;
    }

    private static Map<String, Decimal> getTaxRates(
        String retailerState,
        String distributorState
    ) {
        Map<String, Decimal> taxRates = new Map<String, Decimal>();
        if (!Schema.getGlobalDescribe().containsKey('Order_tax_value__c')) {
            return taxRates;
        }

        List<Order_tax_value__c> taxSettings = [
            SELECT SGST__c, IGST__c, CGST__c
            FROM Order_tax_value__c
            WHERE Name = :TAX_SETTING_NAME
            LIMIT 1
        ];
        if (taxSettings.isEmpty()) {
            return taxRates;
        }

        Order_tax_value__c taxSetting = taxSettings[0];
        String retailer = retailerState == null ? '' : retailerState.trim();
        String distributor = distributorState == null ? '' : distributorState.trim();

        if (retailer.equalsIgnoreCase(distributor)) {
            taxRates.put('CGST', taxSetting.CGST__c);
            taxRates.put('SGST', taxSetting.SGST__c);
        } else {
            taxRates.put('IGST', taxSetting.IGST__c);
        }

        return taxRates;
    }

    private static Decimal calculateLineGst(
        Decimal taxableAmount,
        Map<String, Decimal> taxRates
    ) {
        if (taxableAmount == null || taxableAmount <= 0 || taxRates == null || taxRates.isEmpty()) {
            return 0;
        }

        Decimal gstRate = 0;
        if (taxRates.containsKey('CGST') && taxRates.get('CGST') != null) {
            gstRate += taxRates.get('CGST');
        }
        if (taxRates.containsKey('SGST') && taxRates.get('SGST') != null) {
            gstRate += taxRates.get('SGST');
        }
        if (taxRates.containsKey('IGST') && taxRates.get('IGST') != null) {
            gstRate = taxRates.get('IGST');
        }

        return (taxableAmount * gstRate / 100).setScale(2, System.RoundingMode.HALF_UP);
    }

    //Added by Hari - Order Record Creation
    private static Map<String, Decimal> calculateLineGstSplit(
        Decimal taxableAmount,
        Map<String, Decimal> taxRates
    ) {
        Map<String, Decimal> split = new Map<String, Decimal>{
            'CGST' => 0,
            'SGST' => 0,
            'IGST' => 0
        };

        if (taxableAmount == null || taxableAmount <= 0 || taxRates == null || taxRates.isEmpty()) {
            return split;
        }

        if (taxRates.containsKey('IGST') && taxRates.get('IGST') != null) {
            split.put(
                'IGST',
                (taxableAmount * taxRates.get('IGST') / 100).setScale(2, System.RoundingMode.HALF_UP)
            );
            return split;
        }

        if (taxRates.containsKey('CGST') && taxRates.get('CGST') != null) {
            split.put(
                'CGST',
                (taxableAmount * taxRates.get('CGST') / 100).setScale(2, System.RoundingMode.HALF_UP)
            );
        }
        if (taxRates.containsKey('SGST') && taxRates.get('SGST') != null) {
            split.put(
                'SGST',
                (taxableAmount * taxRates.get('SGST') / 100).setScale(2, System.RoundingMode.HALF_UP)
            );
        }

        return split;
    }

    // -------------------------------------------------------------------------
    // Discount & TOD (Discount__c — product-level and retailer-level)
    // -------------------------------------------------------------------------

    private static List<Discount__c> loadDiscountRecords(Set<Id> retailerAccountIds) {
        if (retailerAccountIds == null || retailerAccountIds.isEmpty()) {
            return new List<Discount__c>();
        }
        if (!Schema.getGlobalDescribe().containsKey(DISCOUNT_SOBJECT)) {
            return new List<Discount__c>();
        }

        return [
            SELECT Account__c, Product__c, Discount_Percentage__c, Start_Date__c, End_Date__c
            FROM Discount__c
            WHERE Account__c IN :retailerAccountIds
        ];
    }

    private static Map<Id, Product__c> loadProductDetailsForTod(Set<Id> productIds) {
        Map<Id, Product__c> productDetailsById = new Map<Id, Product__c>();
        if (productIds == null || productIds.isEmpty()) {
            return productDetailsById;
        }
        if (!Schema.getGlobalDescribe().containsKey(PRODUCT_SOBJECT)) {
            return productDetailsById;
        }

        Map<String, Schema.SObjectField> productFields = Schema.getGlobalDescribe()
            .get(PRODUCT_SOBJECT)
            .getDescribe()
            .fields.getMap();

        List<String> selectFields = new List<String>{ 'Id' };
        if (productFields.containsKey('mrp__c')) {
            selectFields.add(PRODUCT_MRP_FIELD);
        }
        if (productFields.containsKey('per_pieces__c')) {
            selectFields.add(PRODUCT_PER_PIECES_FIELD);
        }

        String query =
            'SELECT ' +
            String.join(selectFields, ', ') +
            ' FROM ' +
            PRODUCT_SOBJECT +
            ' WHERE Id IN :productIds';

        for (Product__c product : Database.query(query)) {
            productDetailsById.put(product.Id, product);
        }

        return productDetailsById;
    }

    private static Boolean isTodEligible(Decimal mrp, Decimal perPieces) {
        if (mrp == null) {
            return false;
        }

        Decimal mrpPerPiece = (perPieces != null && perPieces > 0)
            ? (mrp / perPieces)
            : mrp;
        return mrpPerPiece >= 20;
    }

    private static Boolean isDiscountActiveOnDate(Discount__c discount, Date effectiveDate) {
        if (discount == null || discount.Discount_Percentage__c == null) {
            return false;
        }
        if (effectiveDate == null) {
            return false;
        }
        if (discount.Start_Date__c != null && effectiveDate < discount.Start_Date__c) {
            return false;
        }
        if (discount.End_Date__c != null && effectiveDate > discount.End_Date__c) {
            return false;
        }
        return true;
    }

    private static Decimal resolveTodDiscountPercent(
        BulkPricingContext pricingContext,
        Id accountId,
        Id productId,
        Date effectiveDate
    ) {
        if (
            pricingContext == null ||
            accountId == null ||
            productId == null ||
            pricingContext.discountRecords == null ||
            pricingContext.discountRecords.isEmpty()
        ) {
            return 0;
        }

        Decimal productLevelPercent = null;
        for (Discount__c discount : pricingContext.discountRecords) {
            if (
                discount.Account__c == accountId &&
                discount.Product__c == productId &&
                isDiscountActiveOnDate(discount, effectiveDate)
            ) {
                productLevelPercent = discount.Discount_Percentage__c;
            }
        }
        if (productLevelPercent != null) {
            return zeroIfNull(productLevelPercent);
        }

        Product__c product = pricingContext.productDetailsById == null
            ? null
            : pricingContext.productDetailsById.get(productId);
        Decimal mrp = product == null ? null : product.MRP__c;
        Decimal perPieces = product == null ? null : product.Per_Pieces__c;
        if (!isTodEligible(mrp, perPieces)) {
            return 0;
        }

        for (Discount__c discount : pricingContext.discountRecords) {
            if (
                discount.Account__c == accountId &&
                discount.Product__c == null &&
                isDiscountActiveOnDate(discount, effectiveDate)
            ) {
                return zeroIfNull(discount.Discount_Percentage__c);
            }
        }

        return 0;
    }

    private static Decimal resolveTodAmount(
        BulkPricingContext pricingContext,
        Account retailer,
        Id productId,
        Map<String, String> row,
        Boolean isInvoice,
        Decimal amount
    ) {
        if (pricingContext == null || retailer == null || productId == null || amount == null || amount <= 0) {
            return 0;
        }

        String dateValue = isInvoice ? row.get('Invoice Date') : row.get('Order Date');
        Date effectiveDate = parseDate(dateValue);
        Decimal todPercent = resolveTodDiscountPercent(
            pricingContext,
            retailer.Id,
            productId,
            effectiveDate
        );

        if (todPercent <= 0) {
            return 0;
        }

        return (amount * todPercent / 100).setScale(2, System.RoundingMode.HALF_UP);
    }

    private static String buildPricebookProductKey(Id pricebookId, Id productId) {
        return String.valueOf(pricebookId) + '|' + String.valueOf(productId);
    }

    private static Id getProductId(Map<String, SObject> products, String productCode) {
        if (String.isBlank(productCode) || products == null || products.isEmpty()) {
            return null;
        }

        SObject product = products.get(normalizeProductCode(productCode).toUpperCase());
        return product == null ? null : product.Id;
    }

    private static Decimal resolvePtr(
        BulkPricingContext pricingContext,
        Account retailer,
        Id productId
    ) {
        if (
            pricingContext == null ||
            productId == null ||
            retailer == null ||
            pricingContext.ptrByPricebookProductKey == null
        ) {
            return 0;
        }

        Id pricebookId = resolvePricebookIdForRetailer(
            retailer,
            pricingContext.regionToPricebookId
        );
        if (pricebookId == null) {
            return 0;
        }

        String key = buildPricebookProductKey(pricebookId, productId);
        return zeroIfNull(pricingContext.ptrByPricebookProductKey.get(key));
    }

    private class BulkPricingContext {
        public String distributorState;
        public Map<String, Id> regionToPricebookId;
        public Map<String, Decimal> ptrByPricebookProductKey;
        public List<Discount__c> discountRecords;
        public Map<Id, Product__c> productDetailsById;
        private Map<String, Map<String, Decimal>> taxRatesByRetailerState =
            new Map<String, Map<String, Decimal>>();

        public Map<String, Decimal> getTaxRatesForRetailer(String retailerState) {
            String stateKey = retailerState == null ? '' : retailerState.trim().toUpperCase();
            if (!taxRatesByRetailerState.containsKey(stateKey)) {
                taxRatesByRetailerState.put(
                    stateKey,
                    HangyoBulkSalesUploadController.getTaxRates(
                        retailerState,
                        distributorState
                    )
                );
            }
            return taxRatesByRetailerState.get(stateKey);
        }
    }

    private static String normalizeProductCode(String productCode) {
        if (String.isBlank(productCode)) {
            return '';
        }

        String trimmedCode = productCode.trim();
        if (!trimmedCode.contains('.')) {
            return trimmedCode;
        }

        try {
            Decimal numericCode = Decimal.valueOf(trimmedCode);
            if (numericCode == numericCode.intValue()) {
                return String.valueOf(numericCode.intValue());
            }
        } catch (Exception ex) {
            // Excel may append ".0" to alphanumeric codes (e.g. P001.0, O-0459.0).
            if (trimmedCode.endsWith('.0')) {
                return trimmedCode.substring(0, trimmedCode.length() - 2);
            }
        }

        return trimmedCode;
    }

    private static String getOrderNumberFieldApiName() {
        if (!Schema.getGlobalDescribe().containsKey(ORDER_SOBJECT)) {
            return ORDER_NUMBER_FALLBACK_FIELD;
        }

        Map<String, Schema.SObjectField> orderFields = Schema.getGlobalDescribe()
            .get(ORDER_SOBJECT)
            .getDescribe()
            .fields.getMap();

        if (orderFields.containsKey('order_number__c')) {
            return ORDER_NUMBER_FIELD;
        }

        if (orderFields.containsKey('order_no__c')) {
            return 'Order_No__c';
        }

        return ORDER_NUMBER_FALLBACK_FIELD;
    }

    private static String normalizeOrderNumber(String orderNumber) {
        return normalizeProductCode(orderNumber);
    }

    private static Map<String, SObject> loadOrders(Set<String> orderNumbers) {
        Map<String, SObject> orderMap = new Map<String, SObject>();
        if (orderNumbers.isEmpty()) {
            return orderMap;
        }

        if (!Schema.getGlobalDescribe().containsKey(ORDER_SOBJECT)) {
            return orderMap;
        }

        String orderNumberField = getOrderNumberFieldApiName();
        Set<String> normalizedNumbers = new Set<String>();
        for (String orderNumber : orderNumbers) {
            String normalizedNumber = normalizeOrderNumber(orderNumber);
            if (!String.isBlank(normalizedNumber)) {
                normalizedNumbers.add(normalizedNumber);
            }
        }
        System.debug('normalizedNumbers:- ' + normalizedNumbers);

        if (normalizedNumbers.isEmpty()) {
            return orderMap;
        }

        List<String> selectFields = new List<String>{
            'Id',
            'EffectiveDate__c',
            orderNumberField
        };
        if (hasOrderField('AccountId__c')) {
            selectFields.add('AccountId__c');
        }

        String query =
            'SELECT ' +
            String.join(selectFields, ', ') +
            ' FROM ' +
            ORDER_SOBJECT +
            ' WHERE ' +
            orderNumberField +
            ' IN :normalizedNumbers';

        for (SObject orderRecord : Database.query(query)) {
            Object numberValue = orderRecord.get(orderNumberField);
            if (numberValue != null) {
                orderMap.put(
                    normalizeOrderNumber(String.valueOf(numberValue)).toUpperCase(),
                    orderRecord
                );
            }
        }

        return orderMap;
    }

    private static Map<Id, Invoice__c> loadDraftInvoicesByOrderId(Set<Id> orderIds) {
        Map<Id, Invoice__c> draftByOrderId = new Map<Id, Invoice__c>();
        if (orderIds.isEmpty() || !Schema.getGlobalDescribe().containsKey(INVOICE_SOBJECT)) {
            return draftByOrderId;
        }

        for (Invoice__c invoice : [
            SELECT Id, Order__c
            FROM Invoice__c
            WHERE Order__c IN :orderIds
            AND Status__c = 'Draft'
        ]) {
            if (invoice.Order__c != null && !draftByOrderId.containsKey(invoice.Order__c)) {
                draftByOrderId.put(invoice.Order__c, invoice);
            }
        }

        return draftByOrderId;
    }

    // -------------------------------------------------------------------------
    // New Requirement — Duplicate lookup helpers
    // -------------------------------------------------------------------------

    private static Boolean hasOrderRefFallbackField() {
        return hasOrderField(ORDER_REF_FALLBACK_FIELD);
    }

    private static Boolean hasInvoiceRefFallbackField() {
        return hasInvoiceField(INVOICE_REF_FALLBACK_FIELD);
    }

    private static List<String> findExistingOrderRefs(Set<String> refNumbers) {
        List<String> foundRefs = new List<String>();
        if (refNumbers.isEmpty() || !hasOrderRefFallbackField()) {
            return foundRefs;
        }

        Set<String> normalizedRefs = new Set<String>();
        for (String refNo : refNumbers) {
            if (!String.isBlank(refNo)) {
                normalizedRefs.add(refNo.trim().toUpperCase());
            }
        }
        if (normalizedRefs.isEmpty()) {
            return foundRefs;
        }

        String query =
            'SELECT Id, ' + ORDER_REF_FALLBACK_FIELD +
            ' FROM ' + ORDER_SOBJECT +
            ' WHERE ' + ORDER_REF_FALLBACK_FIELD + ' != null';

        for (SObject orderRecord : Database.query(query)) {
            Object refValue = orderRecord.get(ORDER_REF_FALLBACK_FIELD);
            if (refValue != null) {
                String normalizedRef = String.valueOf(refValue).trim().toUpperCase();
                if (normalizedRefs.contains(normalizedRef)) {
                    foundRefs.add(String.valueOf(refValue).trim());
                }
            }
        }

        return foundRefs;
    }

    private static List<String> findExistingInvoiceRefs(Set<String> refNumbers) {
        List<String> foundRefs = new List<String>();
        if (refNumbers.isEmpty() || !hasInvoiceRefFallbackField()) {
            return foundRefs;
        }

        Set<String> normalizedRefs = new Set<String>();
        for (String refNo : refNumbers) {
            if (!String.isBlank(refNo)) {
                normalizedRefs.add(refNo.trim().toUpperCase());
            }
        }
        if (normalizedRefs.isEmpty()) {
            return foundRefs;
        }

        String query =
            'SELECT Id, ' + INVOICE_REF_FIELD +
            ' FROM ' + INVOICE_SOBJECT +
            ' WHERE ' + INVOICE_REF_FIELD + ' != null';

        for (SObject invoiceRecord : Database.query(query)) {
            Object refValue = invoiceRecord.get(INVOICE_REF_FIELD);
            if (refValue != null) {
                String normalizedRef = String.valueOf(refValue).trim().toUpperCase();
                if (normalizedRefs.contains(normalizedRef)) {
                    foundRefs.add(String.valueOf(refValue).trim());
                }
            }
        }

        return foundRefs;
    }

    // -------------------------------------------------------------------------
    // New Requirement — Order Update (Quantity-only)
    // -------------------------------------------------------------------------
    @TestVisible
    private class OrderUpdateResult {
        public List<BulkUploadError> errors = new List<BulkUploadError>();
        public Integer updatedCount = 0;
        public List<Id> updatedOrderIds = new List<Id>();
        public List<String> updatedOrderNames = new List<String>();
    }

    private static OrderUpdateResult updateExistingOrders(
        List<Map<String, String>> updateRows
    ) {
        OrderUpdateResult result = new OrderUpdateResult();

        if (!hasOrderRefFallbackField()) {
            addError(
                result.errors,
                0,
                'Ref Order No.',
                'Order reference field is not configured. Cannot update existing orders.'
            );
            return result;
        }

        Map<String, List<Map<String, String>>> rowsByRefOrder =
            groupOrderRowsByReference(updateRows);

        Set<String> refKeys = rowsByRefOrder.keySet();
        Map<String, Order__c> existingOrdersByRef = loadExistingOrdersByRef(refKeys);

        Set<Id> orderIds = new Set<Id>();
        for (Order__c existingOrder : existingOrdersByRef.values()) {
            orderIds.add(existingOrder.Id);
        }
        Map<Id, List<Order_Line_Item__c>> existingLineItemsByOrderId =
            loadExistingOrderLineItems(orderIds);

        Set<String> retailerCodes = new Set<String>();
        Set<String> productCodes = new Set<String>();
        for (Map<String, String> row : updateRows) {
            collectCode(retailerCodes, row.get('Retailer Code'));
            collectCode(productCodes, row.get('Product Code'));
        }
        Map<String, Account> retailers = loadRetailersForOrderCreation(retailerCodes);
        Map<String, SObject> products = loadProducts(productCodes);

        List<Order_Line_Item__c> lineItemsToUpdate = new List<Order_Line_Item__c>();
        Set<Id> processedOrderIds = new Set<Id>();

        for (String refKey : rowsByRefOrder.keySet()) {
            List<Map<String, String>> groupRows = rowsByRefOrder.get(refKey);
            Map<String, String> headerRow = groupRows[0];
            String refNo = headerRow.get('Ref Order No.');

            Order__c existingOrder = existingOrdersByRef.get(refKey);
            if (existingOrder == null) {
                addError(
                    result.errors,
                    getRowNumber(headerRow),
                    'Ref Order No.',
                    'Order with reference "' + refNo + '" could not be found for update.'
                );
                continue;
            }

            List<Order_Line_Item__c> existingLines =
                existingLineItemsByOrderId.get(existingOrder.Id);
            if (existingLines == null) {
                existingLines = new List<Order_Line_Item__c>();
            }

            // Lookup of existing lines by Product Id for immutability comparison.
            Map<Id, Order_Line_Item__c> existingLineByProduct =
                new Map<Id, Order_Line_Item__c>();
            for (Order_Line_Item__c existingLine : existingLines) {
                if (existingLine.Products__c != null) {
                    existingLineByProduct.put(existingLine.Products__c, existingLine);
                }
            }

            Boolean groupHasError = false;

            // Immutable header-level field checks (retailer/outlet, date).
            String retailerCode = headerRow.get('Retailer Code');
            Account retailer = String.isBlank(retailerCode)
                ? null
                : retailers.get(retailerCode.trim().toUpperCase());

            if (retailer != null && existingOrder.Account__c != retailer.Id) {
                addError(
                    result.errors,
                    getRowNumber(headerRow),
                    'Retailer Code',
                    'Retailer/Outlet cannot be changed for existing order "' + refNo + '". Update rejected.'
                );
                groupHasError = true;
            }

            Date uploadedOrderDate = parseDate(headerRow.get('Order Date'));
            if (
                uploadedOrderDate != null &&
                existingOrder.EffectiveDate__c != null &&
                uploadedOrderDate != existingOrder.EffectiveDate__c
            ) {
                addError(
                    result.errors,
                    getRowNumber(headerRow),
                    'Order Date',
                    'Order Date cannot be changed for existing order "' + refNo + '". Update rejected.'
                );
                groupHasError = true;
            }

            if (groupHasError) {
                continue;
            }

            List<Order_Line_Item__c> pendingUpdatesForGroup =
                new List<Order_Line_Item__c>();

            for (Map<String, String> row : groupRows) {
                Integer rowNo = getRowNumber(row);
                String productCode = row.get('Product Code');
                Id productId = getProductId(products, productCode);

                if (productId == null) {
                    addError(
                        result.errors,
                        rowNo,
                        'Product Code',
                        'Product "' + productCode + '" could not be resolved for order "' + refNo + '".'
                    );
                    continue;
                }

                Order_Line_Item__c existingLine = existingLineByProduct.get(productId);
                if (existingLine == null) {
                    addError(
                        result.errors,
                        rowNo,
                        'Product Code',
                        'Product "' + productCode + '" does not exist on the original order "' +
                            refNo + '". Adding new products via update is not supported.'
                    );
                    continue;
                }

                Decimal newQuantity = parseDecimal(row.get('Quantity'));
                if (newQuantity == null) {
                    addError(result.errors, rowNo, 'Quantity', 'Quantity must be a valid number.');
                    continue;
                }

                // Only Quantity is allowed to change; Product/Price are immutable by construction.
                pendingUpdatesForGroup.add(
                    new Order_Line_Item__c(
                        Id = existingLine.Id,
                        Ordered_Quantity__c = newQuantity
                    )
                );
            }

            if (!pendingUpdatesForGroup.isEmpty()) {
                lineItemsToUpdate.addAll(pendingUpdatesForGroup);
                processedOrderIds.add(existingOrder.Id);
                result.updatedOrderIds.add(existingOrder.Id);
                result.updatedOrderNames.add(existingOrder.Name);
            }
        }

        if (!lineItemsToUpdate.isEmpty()) {
            Savepoint sp = Database.setSavepoint();
            try {
                update lineItemsToUpdate;
                recalculateOrderTotals(processedOrderIds);
                result.updatedCount = processedOrderIds.size();
            } catch (Exception ex) {
                Database.rollback(sp);
                addError(
                    result.errors,
                    0,
                    'Order',
                    'Failed to update existing order line items: ' + ex.getMessage()
                );
                result.updatedOrderIds = new List<Id>();
                result.updatedOrderNames = new List<String>();
            }
        }

        return result;
    }

    private static Map<String, Order__c> loadExistingOrdersByRef(Set<String> refKeys) {
        Map<String, Order__c> ordersByRef = new Map<String, Order__c>();
        if (refKeys.isEmpty() || !hasOrderRefFallbackField()) {
            return ordersByRef;
        }

        for (Order__c existingOrder : [
            SELECT Id, Name, Account__c, EffectiveDate__c, AccountId__c,
                   Total_order_value__c, Total_Quantity__c, Price__c, Sub_Total__c,
                   Discount_Amount_Order__c, totalCGST__c, totalSGST__c, totalIGST__c,
                   Ref_Order_No_Data_Upload__c
            FROM Order__c
            WHERE Ref_Order_No_Data_Upload__c != null
        ]) {
            String key = existingOrder.Ref_Order_No_Data_Upload__c.trim().toUpperCase();
            if (refKeys.contains(key)) {
                ordersByRef.put(key, existingOrder);
            }
        }

        return ordersByRef;
    }

    private static Map<Id, List<Order_Line_Item__c>> loadExistingOrderLineItems(
        Set<Id> orderIds
    ) {
        Map<Id, List<Order_Line_Item__c>> lineItemsByOrderId =
            new Map<Id, List<Order_Line_Item__c>>();
        if (orderIds.isEmpty()) {
            return lineItemsByOrderId;
        }

        for (Order_Line_Item__c lineItem : [
            SELECT Id, Order__c, Products__c, Ordered_Quantity__c, Product_Price__c
            FROM Order_Line_Item__c
            WHERE Order__c IN :orderIds
        ]) {
            if (!lineItemsByOrderId.containsKey(lineItem.Order__c)) {
                lineItemsByOrderId.put(lineItem.Order__c, new List<Order_Line_Item__c>());
            }
            lineItemsByOrderId.get(lineItem.Order__c).add(lineItem);
        }

        return lineItemsByOrderId;
    }

    private static void recalculateOrderTotals(Set<Id> orderIds) {
        if (orderIds.isEmpty()) {
            return;
        }

        Map<Id, List<Order_Line_Item__c>> lineItemsByOrderId =
            loadExistingOrderLineItems(orderIds);

        List<Order__c> ordersToUpdate = new List<Order__c>();
        for (Id orderId : orderIds) {
            List<Order_Line_Item__c> lineItems = lineItemsByOrderId.get(orderId);
            if (lineItems == null) {
                continue;
            }

            Decimal totalQuantity = 0;
            Decimal totalValue = 0;
            for (Order_Line_Item__c lineItem : lineItems) {
                Decimal qty = zeroIfNull(lineItem.Ordered_Quantity__c);
                Decimal price = zeroIfNull(lineItem.Product_Price__c);
                totalQuantity += qty;
                totalValue += (qty * price).setScale(2, System.RoundingMode.HALF_UP);
            }

            ordersToUpdate.add(
                new Order__c(
                    Id = orderId,
                    Total_Quantity__c = totalQuantity,
                    Price__c = totalValue
                )
            );
        }

        if (!ordersToUpdate.isEmpty()) {
            update ordersToUpdate;
        }
    }

    // -------------------------------------------------------------------------
    // New Requirement — Invoice Update (Quantity-only)
    // -------------------------------------------------------------------------
    @TestVisible
    private class InvoiceUpdateResult {
        public List<BulkUploadError> errors = new List<BulkUploadError>();
        public Integer updatedCount = 0;
        public List<Id> updatedInvoiceIds = new List<Id>();
        public List<String> updatedInvoiceNames = new List<String>();
    }

    /*private static InvoiceUpdateResult updateExistingInvoices(List<Map<String, String>> updateRows){
        InvoiceUpdateResult result = new InvoiceUpdateResult();

        if (!hasInvoiceRefFallbackField()) {
            addError(
                result.errors,
                0,
                'Ref Invoice No.',
                'Invoice reference field is not configured. Cannot update existing invoices.'
            );
            return result;
        }

        Map<String, List<Map<String, String>>> rowsByRefInvoice =
            groupInvoiceRowsByReference(updateRows);

        Set<String> refKeys = rowsByRefInvoice.keySet();
        Map<String, Invoice__c> existingInvoicesByRef = loadExistingInvoicesByRef(refKeys);

        Set<Id> invoiceIds = new Set<Id>();
        for (Invoice__c existingInvoice : existingInvoicesByRef.values()) {
            invoiceIds.add(existingInvoice.Id);
        }
        Map<Id, List<Invoice_Line_Item__c>> existingLineItemsByInvoiceId =
            loadExistingInvoiceLineItems(invoiceIds);

        Set<String> retailerCodes = new Set<String>();
        Set<String> productCodes = new Set<String>();
        Set<String> orderNumbers = new Set<String>();
        for (Map<String, String> row : updateRows) {
            collectCode(retailerCodes, row.get('Retailer Code'));
            collectCode(productCodes, row.get('Product Code'));
            collectCode(orderNumbers, row.get('Order Number'));
        }
        Map<String, Account> retailers = loadRetailersForOrderCreation(retailerCodes);
        Map<String, SObject> products = loadProducts(productCodes);
        Map<String, SObject> orders = loadOrdersForInvoiceCreation(orderNumbers);

        List<Invoice_Line_Item__c> lineItemsToUpdate = new List<Invoice_Line_Item__c>();
        Set<Id> processedInvoiceIds = new Set<Id>();

        for (String refKey : rowsByRefInvoice.keySet()) {
            List<Map<String, String>> groupRows = rowsByRefInvoice.get(refKey);
            Map<String, String> headerRow = groupRows[0];
            String refNo = headerRow.get('Ref Invoice No.');

            Invoice__c existingInvoice = existingInvoicesByRef.get(refKey);
            if (existingInvoice == null) {
                addError(
                    result.errors,
                    getRowNumber(headerRow),
                    'Ref Invoice No.',
                    'Invoice with reference "' + refNo + '" could not be found for update.'
                );
                continue;
            }

            List<Invoice_Line_Item__c> existingLines =
                existingLineItemsByInvoiceId.get(existingInvoice.Id);
            if (existingLines == null) {
                existingLines = new List<Invoice_Line_Item__c>();
            }

            Map<Id, Invoice_Line_Item__c> existingLineByProduct =
                new Map<Id, Invoice_Line_Item__c>();
            for (Invoice_Line_Item__c existingLine : existingLines) {
                if (existingLine.Product__c != null) {
                    existingLineByProduct.put(existingLine.Product__c, existingLine);
                }
            }

            Boolean groupHasError = false;

            // Immutable header-level checks: retailer/outlet, order link, invoice date.
            String retailerCode = headerRow.get('Retailer Code');
            Account retailer = String.isBlank(retailerCode)
                ? null
                : retailers.get(retailerCode.trim().toUpperCase());

            if (retailer != null && existingInvoice.Retailer_Account__c != retailer.Id) {
                addError(
                    result.errors,
                    getRowNumber(headerRow),
                    'Retailer Code',
                    'Retailer/Outlet cannot be changed for existing invoice "' + refNo + '". Update rejected.'
                );
                groupHasError = true;
            }

            String orderNumber = headerRow.get('Order Number');
            SObject linkedOrder = String.isBlank(orderNumber)
                ? null
                : orders.get(normalizeOrderNumber(orderNumber).toUpperCase());
            if (linkedOrder != null && existingInvoice.Order__c != linkedOrder.Id) {
                addError(
                    result.errors,
                    getRowNumber(headerRow),
                    'Order Number',
                    'Order reference cannot be changed for existing invoice "' + refNo + '". Update rejected.'
                );
                groupHasError = true;
            }

            Date uploadedInvoiceDate = parseDate(headerRow.get('Invoice Date'));
            if (
                uploadedInvoiceDate != null &&
                existingInvoice.Invoice_Date__c != null &&
                uploadedInvoiceDate != existingInvoice.Invoice_Date__c
            ) {
                addError(
                    result.errors,
                    getRowNumber(headerRow),
                    'Invoice Date',
                    'Invoice Date cannot be changed for existing invoice "' + refNo + '". Update rejected.'
                );
                groupHasError = true;
            }

            if (groupHasError) {
                continue;
            }

            List<Invoice_Line_Item__c> pendingUpdatesForGroup =
                new List<Invoice_Line_Item__c>();

            for (Map<String, String> row : groupRows) {
                Integer rowNo = getRowNumber(row);
                String productCode = row.get('Product Code');
                Id productId = getProductId(products, productCode);

                if (productId == null) {
                    addError(
                        result.errors,
                        rowNo,
                        'Product Code',
                        'Product "' + productCode + '" could not be resolved for invoice "' + refNo + '".'
                    );
                    continue;
                }

                Invoice_Line_Item__c existingLine = existingLineByProduct.get(productId);
                if (existingLine == null) {
                    addError(
                        result.errors,
                        rowNo,
                        'Product Code',
                        'Product "' + productCode + '" does not exist on the original invoice "' +
                            refNo + '". Adding new products via update is not supported.'
                    );
                    continue;
                }

                Decimal newQuantity = parseDecimal(row.get('Quantity'));
                if (newQuantity == null) {
                    addError(result.errors, rowNo, 'Quantity', 'Quantity must be a valid number.');
                    continue;
                }

                // Only Quantity may change; recompute the dependent amount using the
                // originally stored unit price so Price/Product remain immutable.
                Decimal unitPrice = zeroIfNull(existingLine.Price__c);
                Decimal recalculatedAmount =
                    (unitPrice * newQuantity).setScale(2, System.RoundingMode.HALF_UP);

                pendingUpdatesForGroup.add(
                    new Invoice_Line_Item__c(
                        Id = existingLine.Id,
                        Quantity__c = newQuantity,
                        Total_Amount__c = recalculatedAmount
                    )
                );
            }

            if (!pendingUpdatesForGroup.isEmpty()) {
                lineItemsToUpdate.addAll(pendingUpdatesForGroup);
                processedInvoiceIds.add(existingInvoice.Id);
                result.updatedInvoiceIds.add(existingInvoice.Id);
                result.updatedInvoiceNames.add(existingInvoice.Invoice_Number__c);
            }
        }

        if (!lineItemsToUpdate.isEmpty()) {
            Savepoint sp = Database.setSavepoint();
            try {
                update lineItemsToUpdate;
                recalculateInvoiceTotals(processedInvoiceIds);
                result.updatedCount = processedInvoiceIds.size();
            } catch (Exception ex) {
                Database.rollback(sp);
                addError(
                    result.errors,
                    0,
                    'Invoice',
                    'Failed to update existing invoice line items: ' + ex.getMessage()
                );
                result.updatedInvoiceIds = new List<Id>();
                result.updatedInvoiceNames = new List<String>();
            }
        }

        return result;
    }

    private static Map<String, Invoice__c> loadExistingInvoicesByRef(Set<String> refKeys) {
        Map<String, Invoice__c> invoicesByRef = new Map<String, Invoice__c>();
        if (refKeys.isEmpty() || !hasInvoiceRefFallbackField()) {
            return invoicesByRef;
        }

        for (Invoice__c existingInvoice : [
            SELECT Id, Invoice_Number__c, Retailer_Account__c, Order__c, Invoice_Date__c,
                   Distributor_Account__c, Invoice_Amount__c, Taxable_Amount__c, Total_GST__c,
                   Total_Quantity__c, Sub_Total__c, CGST_Amount__c, SGST_Amount__c, IGST_Amount__c,
                   Ref_Invoice_No_Data_Upload__c
            FROM Invoice__c
            WHERE Ref_Invoice_No_Data_Upload__c != null
        ]) {
            String key = existingInvoice.Ref_Invoice_No_Data_Upload__c.trim().toUpperCase();
            if (refKeys.contains(key)) {
                invoicesByRef.put(key, existingInvoice);
            }
        }

        return invoicesByRef;
    }*/
    
    private static InvoiceUpdateResult updateExistingInvoices(List<Map<String, String>> updateRows){
        InvoiceUpdateResult result = new InvoiceUpdateResult();
    
        if (!hasInvoiceRefFallbackField()) {
            addError(
                result.errors,
                0,
                'Ref Invoice No.',
                'Invoice reference field is not configured. Cannot update existing invoices.'
            );
            return result;
        }
    
        Map<String, List<Map<String, String>>> rowsByRefInvoice =
            groupInvoiceRowsByReference(updateRows);
    
        Set<String> refKeys = rowsByRefInvoice.keySet();
        Map<String, Invoice__c> existingInvoicesByRef = loadExistingInvoicesByRef(refKeys);
    
        Set<Id> invoiceIds = new Set<Id>();
        for (Invoice__c existingInvoice : existingInvoicesByRef.values()) {
            invoiceIds.add(existingInvoice.Id);
        }
        Map<Id, List<Invoice_Line_Item__c>> existingLineItemsByInvoiceId =
            loadExistingInvoiceLineItems(invoiceIds);
    
        Set<String> retailerCodes = new Set<String>();
        Set<String> productCodes = new Set<String>();
        Set<String> orderNumbers = new Set<String>();
        for (Map<String, String> row : updateRows) {
            collectCode(retailerCodes, row.get('Retailer Code'));
            collectCode(productCodes, row.get('Product Code'));
            collectCode(orderNumbers, row.get('Order Number'));
        }
        Map<String, Account> retailers = loadRetailersForOrderCreation(retailerCodes);
        Map<String, SObject> products = loadProducts(productCodes);
        Map<String, SObject> orders = loadOrdersForInvoiceCreation(orderNumbers);
    
        List<Invoice_Line_Item__c> lineItemsToUpdate = new List<Invoice_Line_Item__c>();
        Set<Id> processedInvoiceIds = new Set<Id>();
    
        for (String refKey : rowsByRefInvoice.keySet()) {
            List<Map<String, String>> groupRows = rowsByRefInvoice.get(refKey);
            Map<String, String> headerRow = groupRows[0];
            String refNo = headerRow.get('Ref Invoice No.');
    
            Invoice__c existingInvoice = existingInvoicesByRef.get(refKey);
            if (existingInvoice == null) {
                addError(
                    result.errors,
                    getRowNumber(headerRow),
                    'Ref Invoice No.',
                    'Invoice with reference "' + refNo + '" could not be found for update.'
                );
                continue;
            }
    
            List<Invoice_Line_Item__c> existingLines =
                existingLineItemsByInvoiceId.get(existingInvoice.Id);
            if (existingLines == null) {
                existingLines = new List<Invoice_Line_Item__c>();
            }
    
            Map<Id, Invoice_Line_Item__c> existingLineByProduct =
                new Map<Id, Invoice_Line_Item__c>();
            for (Invoice_Line_Item__c existingLine : existingLines) {
                if (existingLine.Product__c != null) {
                    existingLineByProduct.put(existingLine.Product__c, existingLine);
                }
            }
    
            Boolean groupHasError = false;
    
            // NEW: Only Draft invoices can be updated. Confirmed (or any other status)
            // invoices are immutable via bulk upload and must be rejected outright.
            if (existingInvoice.Status__c != 'Draft') {
                addError(
                    result.errors,
                    getRowNumber(headerRow),
                    'Status',
                    'Invoice "' + refNo + '" is in "' + existingInvoice.Status__c +
                        '" status. Only invoices in Draft status can be updated via bulk upload.'
                );
                groupHasError = true;
            }
    
            // Immutable header-level checks: retailer/outlet, order link, invoice date.
            String retailerCode = headerRow.get('Retailer Code');
            Account retailer = String.isBlank(retailerCode)
                ? null
                : retailers.get(retailerCode.trim().toUpperCase());
    
            if (retailer != null && existingInvoice.Retailer_Account__c != retailer.Id) {
                addError(
                    result.errors,
                    getRowNumber(headerRow),
                    'Retailer Code',
                    'Retailer/Outlet cannot be changed for existing invoice "' + refNo + '". Update rejected.'
                );
                groupHasError = true;
            }
    
            String orderNumber = headerRow.get('Order Number');
            SObject linkedOrder = String.isBlank(orderNumber)
                ? null
                : orders.get(normalizeOrderNumber(orderNumber).toUpperCase());
            if (linkedOrder != null && existingInvoice.Order__c != linkedOrder.Id) {
                addError(
                    result.errors,
                    getRowNumber(headerRow),
                    'Order Number',
                    'Order reference cannot be changed for existing invoice "' + refNo + '". Update rejected.'
                );
                groupHasError = true;
            }
    
            Date uploadedInvoiceDate = parseDate(headerRow.get('Invoice Date'));
            if (
                uploadedInvoiceDate != null &&
                existingInvoice.Invoice_Date__c != null &&
                uploadedInvoiceDate != existingInvoice.Invoice_Date__c
            ) {
                addError(
                    result.errors,
                    getRowNumber(headerRow),
                    'Invoice Date',
                    'Invoice Date cannot be changed for existing invoice "' + refNo + '". Update rejected.'
                );
                groupHasError = true;
            }
    
            if (groupHasError) {
                continue;
            }
    
            List<Invoice_Line_Item__c> pendingUpdatesForGroup =
                new List<Invoice_Line_Item__c>();
    
            for (Map<String, String> row : groupRows) {
                Integer rowNo = getRowNumber(row);
                String productCode = row.get('Product Code');
                Id productId = getProductId(products, productCode);
    
                if (productId == null) {
                    addError(
                        result.errors,
                        rowNo,
                        'Product Code',
                        'Product "' + productCode + '" could not be resolved for invoice "' + refNo + '".'
                    );
                    continue;
                }
    
                Invoice_Line_Item__c existingLine = existingLineByProduct.get(productId);
                if (existingLine == null) {
                    addError(
                        result.errors,
                        rowNo,
                        'Product Code',
                        'Product "' + productCode + '" does not exist on the original invoice "' +
                            refNo + '". Adding new products via update is not supported.'
                    );
                    continue;
                }
    
                Decimal newQuantity = parseDecimal(row.get('Quantity'));
                if (newQuantity == null) {
                    addError(result.errors, rowNo, 'Quantity', 'Quantity must be a valid number.');
                    continue;
                }
    
                // Only Quantity may change; recompute the dependent amount using the
                // originally stored unit price so Price/Product remain immutable.
                Decimal unitPrice = zeroIfNull(existingLine.Price__c);
                Decimal recalculatedAmount =
                    (unitPrice * newQuantity).setScale(2, System.RoundingMode.HALF_UP);
    
                pendingUpdatesForGroup.add(
                    new Invoice_Line_Item__c(
                        Id = existingLine.Id,
                        Quantity__c = newQuantity,
                        Total_Amount__c = recalculatedAmount
                    )
                );
            }
    
            if (!pendingUpdatesForGroup.isEmpty()) {
                lineItemsToUpdate.addAll(pendingUpdatesForGroup);
                processedInvoiceIds.add(existingInvoice.Id);
                result.updatedInvoiceIds.add(existingInvoice.Id);
                result.updatedInvoiceNames.add(existingInvoice.Invoice_Number__c);
            }
        }
    
        if (!lineItemsToUpdate.isEmpty()) {
            Savepoint sp = Database.setSavepoint();
            try {
                update lineItemsToUpdate;
                recalculateInvoiceTotals(processedInvoiceIds);
                result.updatedCount = processedInvoiceIds.size();
            } catch (Exception ex) {
                Database.rollback(sp);
                addError(
                    result.errors,
                    0,
                    'Invoice',
                    'Failed to update existing invoice line items: ' + ex.getMessage()
                );
                result.updatedInvoiceIds = new List<Id>();
                result.updatedInvoiceNames = new List<String>();
            }
        }
    
        return result;
    }
    
    private static Map<String, Invoice__c> loadExistingInvoicesByRef(Set<String> refKeys) {
        Map<String, Invoice__c> invoicesByRef = new Map<String, Invoice__c>();
        if (refKeys.isEmpty() || !hasInvoiceRefFallbackField()) {
            return invoicesByRef;
        }
    
        for (Invoice__c existingInvoice : [
            SELECT Id, Invoice_Number__c, Retailer_Account__c, Order__c, Invoice_Date__c,
                   Distributor_Account__c, Invoice_Amount__c, Taxable_Amount__c, Total_GST__c,
                   Total_Quantity__c, Sub_Total__c, CGST_Amount__c, SGST_Amount__c, IGST_Amount__c,
                   Status__c, Ref_Invoice_No_Data_Upload__c
            FROM Invoice__c
            WHERE Ref_Invoice_No_Data_Upload__c != null AND OwnerId =: UserInfo.getUserId()
        ]) {
            String key = existingInvoice.Ref_Invoice_No_Data_Upload__c.trim().toUpperCase();
            if (refKeys.contains(key)) {
                invoicesByRef.put(key, existingInvoice);
            }
        }
    
        return invoicesByRef;
    }

    private static Map<Id, List<Invoice_Line_Item__c>> loadExistingInvoiceLineItems(
        Set<Id> invoiceIds
    ) {
        Map<Id, List<Invoice_Line_Item__c>> lineItemsByInvoiceId =
            new Map<Id, List<Invoice_Line_Item__c>>();
        if (invoiceIds.isEmpty()) {
            return lineItemsByInvoiceId;
        }

        for (Invoice_Line_Item__c lineItem : [
            SELECT Id, Invoice__c, Product__c, Quantity__c, Price__c, Total_Amount__c,
                   Discount_1__c, Discount_2__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c IN :invoiceIds
        ]) {
            if (!lineItemsByInvoiceId.containsKey(lineItem.Invoice__c)) {
                lineItemsByInvoiceId.put(lineItem.Invoice__c, new List<Invoice_Line_Item__c>());
            }
            lineItemsByInvoiceId.get(lineItem.Invoice__c).add(lineItem);
        }

        return lineItemsByInvoiceId;
    }

    private static void recalculateInvoiceTotals(Set<Id> invoiceIds) {
        if (invoiceIds.isEmpty()) {
            return;
        }

        Map<Id, List<Invoice_Line_Item__c>> lineItemsByInvoiceId =
            loadExistingInvoiceLineItems(invoiceIds);

        List<Invoice__c> invoicesToUpdate = new List<Invoice__c>();
        for (Id invoiceId : invoiceIds) {
            List<Invoice_Line_Item__c> lineItems = lineItemsByInvoiceId.get(invoiceId);
            if (lineItems == null) {
                continue;
            }

            Decimal totalQuantity = 0;
            Decimal invoiceAmount = 0;
            for (Invoice_Line_Item__c lineItem : lineItems) {
                totalQuantity += zeroIfNull(lineItem.Quantity__c);
                invoiceAmount += zeroIfNull(lineItem.Total_Amount__c);
            }

            invoicesToUpdate.add(
                new Invoice__c(
                    Id = invoiceId,
                    Total_Quantity__c = totalQuantity,
                    Invoice_Amount__c = invoiceAmount
                )
            );
        }

        if (!invoicesToUpdate.isEmpty()) {
            update invoicesToUpdate;
        }
    }

    // -------------------------------------------------------------------------
    // Spreadsheet parsing (.xlsx). Legacy .xls is not supported server-side.
    // -------------------------------------------------------------------------

    private static List<List<String>> parseSpreadsheet(Blob fileBlob, String fileName) {
        rejectLegacySpreadsheetFileName(fileName);
        return parseXlsx(fileBlob);
    }

    private static List<List<String>> parseXlsx(Blob fileBlob) {
        Map<String, Blob> zipEntries = extractZipEntries(fileBlob);
        List<String> sharedStrings = parseSharedStrings(
            zipEntries.get('xl/sharedStrings.xml')
        );
        String sheetXml = findFirstSheetXml(zipEntries);
        if (String.isBlank(sheetXml)) {
            throwAuraHandledException('Unable to read worksheet data from the Excel file.');
        }
        return parseSheetXml(sheetXml, sharedStrings);
    }

    private static Map<String, Blob> extractZipEntries(Blob fileBlob) {
        Map<String, Blob> entries = new Map<String, Blob>();
        Compression.ZipReader reader = new Compression.ZipReader(fileBlob);
        for (String entryName : reader.getEntryNames()) {
            entries.put(entryName, reader.extract(entryName));
        }
        return entries;
    }

    private static String findFirstSheetXml(Map<String, Blob> zipEntries) {
        if (zipEntries.containsKey('xl/worksheets/sheet1.xml')) {
            return zipEntries.get('xl/worksheets/sheet1.xml').toString();
        }
        for (String entryName : zipEntries.keySet()) {
            if (entryName.startsWith('xl/worksheets/sheet') && entryName.endsWith('.xml')) {
                return zipEntries.get(entryName).toString();
            }
        }
        return null;
    }

    private static List<String> parseSharedStrings(Blob sharedStringsBlob) {
        List<String> sharedStrings = new List<String>();
        if (sharedStringsBlob == null) {
            return sharedStrings;
        }

        String xml = sharedStringsBlob.toString();
        Pattern itemPattern = Pattern.compile('<si>(.*?)</si>');
        Matcher itemMatcher = itemPattern.matcher(xml);
        while (itemMatcher.find()) {
            String itemXml = itemMatcher.group(1);
            List<String> parts = new List<String>();
            Pattern textPattern = Pattern.compile('<t[^>]*>(.*?)</t>');
            Matcher textMatcher = textPattern.matcher(itemXml);
            while (textMatcher.find()) {
                parts.add(unescapeXml(textMatcher.group(1)));
            }
            sharedStrings.add(String.join(parts, ''));
        }
        return sharedStrings;
    }

    private static List<List<String>> parseSheetXml(
        String sheetXml,
        List<String> sharedStrings
    ) {
        Map<Integer, Map<Integer, String>> rowMap = new Map<Integer, Map<Integer, String>>();
        Integer maxColumnIndex = 0;

        Pattern rowPattern = Pattern.compile('<row[^>]*r="(\\d+)"[^>]*>(.*?)</row>');
        Matcher rowMatcher = rowPattern.matcher(sheetXml);
        while (rowMatcher.find()) {
            Integer rowNumber = Integer.valueOf(rowMatcher.group(1));
            String rowXml = rowMatcher.group(2);
            Map<Integer, String> columnValues = rowMap.containsKey(rowNumber)
                ? rowMap.get(rowNumber)
                : new Map<Integer, String>();

            Pattern cellPattern = Pattern.compile('<c[^>]*r="([A-Z]+)(\\d+)"([^>]*)>(.*?)</c>');
            Matcher cellMatcher = cellPattern.matcher(rowXml);
            while (cellMatcher.find()) {
                String columnLetters = cellMatcher.group(1);
                String cellAttributes = cellMatcher.group(3);
                String cellInnerXml = cellMatcher.group(4);
                Integer columnIndex = columnLettersToIndex(columnLetters);
                String cellValue = extractCellValue(cellInnerXml, cellAttributes, sharedStrings);
                columnValues.put(columnIndex, cellValue);
                if (columnIndex > maxColumnIndex) {
                    maxColumnIndex = columnIndex;
                }
            }

            rowMap.put(rowNumber, columnValues);
        }

        List<Integer> rowNumbers = new List<Integer>(rowMap.keySet());
        rowNumbers.sort();
        List<List<String>> rows = new List<List<String>>();

        for (Integer rowNumber : rowNumbers) {
            Map<Integer, String> columnValues = rowMap.get(rowNumber);
            List<String> rowValues = new List<String>();
            for (Integer columnIndex = 0; columnIndex <= maxColumnIndex; columnIndex++) {
                rowValues.add(
                    columnValues.containsKey(columnIndex)
                        ? columnValues.get(columnIndex)
                        : ''
                );
            }
            rows.add(rowValues);
        }

        return rows;
    }

    private static String extractCellValue(
        String cellInnerXml,
        String cellAttributes,
        List<String> sharedStrings
    ) {
        String value = extractXmlTagValue(cellInnerXml, 'v');
        if (String.isBlank(value)) {
            value = extractXmlTagValue(cellInnerXml, 't');
        }
        if (String.isBlank(value)) {
            return '';
        }

        if (cellAttributes != null && cellAttributes.contains('t="s"')) {
            Integer sharedIndex = Integer.valueOf(value);
            return sharedIndex < sharedStrings.size()
                ? sharedStrings[sharedIndex]
                : '';
        }

        if (cellAttributes != null && cellAttributes.contains('t="inlineStr"')) {
            return extractXmlTagValue(cellInnerXml, 't');
        }

        if (cellAttributes != null && cellAttributes.contains('t="b"')) {
            return '1'.equals(value) ? 'TRUE' : 'FALSE';
        }

        return value;
    }

    private static String extractXmlTagValue(String xml, String tagName) {
        Pattern pattern = Pattern.compile(
            '<' + tagName + '[^>]*>(.*?)</' + tagName + '>'
        );
        Matcher matcher = pattern.matcher(xml);
        if (matcher.find()) {
            return unescapeXml(matcher.group(1));
        }
        return '';
    }

    private static Integer columnLettersToIndex(String letters) {
        Integer index = 0;
        for (Integer i = 0; i < letters.length(); i++) {
            Integer charCode = letters.charAt(i);
            index = index * 26 + (charCode - 64);
        }
        return index - 1;
    }

    private static BulkUploadSuccess buildValidationSuccess(String uploadType,List<Map<String, String>> dataRows){
        Set<String> headerKeys = new Set<String>();
        String refColumn = UPLOAD_TYPE_ORDER.equalsIgnoreCase(uploadType)
            ? 'Ref Order No.'
            : 'Ref Invoice No.';

        for (Map<String, String> row : dataRows) {
            String refValue = row.get(refColumn);
            if (!String.isBlank(refValue)) {
                headerKeys.add(refValue.trim().toUpperCase());
            }
        }

        BulkUploadSuccess success = new BulkUploadSuccess();
        success.recordType = uploadType;
        success.headerCount = headerKeys.size();
        success.lineItemCount = dataRows.size();
        success.validationPassed = true;
        success.groups = buildGroupSummaries(uploadType, dataRows);
        return success;
    }

    private static List<BulkUploadGroupSummary> buildGroupSummaries(
        String uploadType,
        List<Map<String, String>> dataRows
    ) {
        String refColumn = UPLOAD_TYPE_ORDER.equalsIgnoreCase(uploadType)
            ? 'Ref Order No.'
            : 'Ref Invoice No.';
        Boolean isInvoice = UPLOAD_TYPE_INVOICE.equalsIgnoreCase(uploadType);

        Set<String> retailerCodes = new Set<String>();
        Set<String> productCodes = new Set<String>();
        for (Map<String, String> row : dataRows) {
            collectCode(retailerCodes, row.get('Retailer Code'));
            collectCode(productCodes, row.get('Product Code'));
        }

        Map<String, Account> retailers = loadRetailers(retailerCodes);
        Map<String, SObject> products = loadProducts(productCodes);
        BulkPricingContext pricingContext = buildPricingContext(retailers, products);
        Map<String, BulkUploadGroupSummary> groupMap = new Map<String, BulkUploadGroupSummary>();
        List<BulkUploadGroupSummary> orderedGroups = new List<BulkUploadGroupSummary>();

        for (Map<String, String> row : dataRows) {
            String refNo = row.get(refColumn);
            if (String.isBlank(refNo)) {
                continue;
            }

            String groupKey = refNo.trim().toUpperCase();
            BulkUploadGroupSummary groupSummary;

            if (!groupMap.containsKey(groupKey)) {
                groupSummary = new BulkUploadGroupSummary();
                groupSummary.refNo = refNo.trim();
                groupSummary.lineItems = new List<BulkUploadLineSummary>();
                groupSummary.totalQuantity = 0;
                groupSummary.grandTotal = 0;
                groupSummary.totalGst = 0;
                groupSummary.status = '';

                String retailerCode = row.get('Retailer Code');
                if (!String.isBlank(retailerCode)) {
                    Account retailer = retailers.get(retailerCode.trim().toUpperCase());
                    groupSummary.retailerName = retailer != null ? retailer.Name : retailerCode.trim();
                }

                if (isInvoice) {
                    groupSummary.orderNumber = row.get('Order Number');
                    groupSummary.status = row.get('Status');
                    groupSummary.invoiceDate = formatDateForDisplay(row.get('Invoice Date'));
                } else {
                    groupSummary.orderDate = formatDateForDisplay(row.get('Order Date'));
                }

                groupMap.put(groupKey, groupSummary);
                orderedGroups.add(groupSummary);
            } else {
                groupSummary = groupMap.get(groupKey);
            }

            Decimal quantity = parseDecimal(row.get('Quantity'));
            if (quantity == null) {
                quantity = 0;
            }
            groupSummary.totalQuantity += quantity;

            BulkUploadLineSummary lineItem = buildLineSummary(
                row,
                products,
                retailers,
                pricingContext,
                quantity,
                isInvoice
            );
            groupSummary.lineItems.add(lineItem);
            groupSummary.grandTotal += zeroIfNull(lineItem.totalAmountInclTax);
            groupSummary.totalGst += zeroIfNull(lineItem.totalGst);
        }

        return orderedGroups;
    }

    private static BulkUploadLineSummary buildLineSummary(
        Map<String, String> row,
        Map<String, SObject> products,
        Map<String, Account> retailers,
        BulkPricingContext pricingContext,
        Decimal quantity,
        Boolean isInvoice
    ) {
        BulkUploadLineSummary lineItem = new BulkUploadLineSummary();
        lineItem.rowNo = getRowNumber(row);
        lineItem.productCode = row.get('Product Code');
        lineItem.productName = getProductName(products, row.get('Product Code'));
        lineItem.quantity = quantity;

        lineItem.discountPercent = isInvoice
            ? zeroIfNull(parseDecimal(row.get('Discount 2%')))
            : 0;

        Account retailer = null;
        String retailerCode = row.get('Retailer Code');
        if (!String.isBlank(retailerCode)) {
            retailer = retailers.get(retailerCode.trim().toUpperCase());
        }

        Id productId = getProductId(products, row.get('Product Code'));
        // Price — PTR from the retailer's regional price book.
        lineItem.price = resolvePtr(pricingContext, retailer, productId);

        // Amount = Price × Quantity
        Decimal qty = quantity == null ? 0 : quantity;
        lineItem.amount = (lineItem.price * qty).setScale(2, System.RoundingMode.HALF_UP);

        // TOD Amount = Amount × TOD % ÷ 100 (from Discount__c; separate from Excel Discount 2%)
        lineItem.tod = resolveTodAmount(
            pricingContext,
            retailer,
            productId,
            row,
            isInvoice,
            lineItem.amount
        );

        // Discount Amount = Amount × Discount 2% ÷ 100 (invoice only; from Excel)
        lineItem.discountAmount = (
            lineItem.amount * lineItem.discountPercent / 100
        ).setScale(2, System.RoundingMode.HALF_UP);

        Decimal amountAfterDiscount = (
            lineItem.amount - lineItem.discountAmount
        ).setScale(2, System.RoundingMode.HALF_UP);

        // Taxable Amount = Amount − Discount Amount − TOD
        lineItem.taxableAmount = (
            amountAfterDiscount - lineItem.tod
        ).setScale(2, System.RoundingMode.HALF_UP);

        String retailerState = retailer != null && hasRetailerStateField()
            ? retailer.Primary_State__c
            : '';
        Map<String, Decimal> taxRates = pricingContext == null
            ? new Map<String, Decimal>()
            : pricingContext.getTaxRatesForRetailer(retailerState);

        // Total GST — per line item, calculated on taxable amount
        lineItem.totalGst = calculateLineGst(lineItem.taxableAmount, taxRates);

        // Total Amount (Incl Tax) = Taxable Amount + Total GST
        lineItem.totalAmountInclTax = (
            lineItem.taxableAmount + lineItem.totalGst
        ).setScale(2, System.RoundingMode.HALF_UP);

        return lineItem;
    }

    private static Decimal zeroIfNull(Decimal value) {
        return value == null ? 0 : value;
    }

    private static String getProductName(
        Map<String, SObject> products,
        String productCode
    ) {
        if (String.isBlank(productCode) || products == null || products.isEmpty()) {
            return '';
        }

        SObject product = products.get(normalizeProductCode(productCode).toUpperCase());
        if (product == null) {
            return '';
        }

        Object nameValue = product.get('Name');
        return nameValue == null ? '' : String.valueOf(nameValue);
    }

    private static void collectCode(Set<String> target, String value) {
        if (!String.isBlank(value)) {
            target.add(value.trim());
        }
    }

    private static Integer getRowNumber(Map<String, String> row) {
        return Integer.valueOf(row.get('__rowNumber'));
    }

    private static Boolean isBlankRow(List<String> rowValues) {
        if (rowValues == null || rowValues.isEmpty()) {
            return true;
        }
        for (String value : rowValues) {
            if (!String.isBlank(value)) {
                return false;
            }
        }
        return true;
    }

    private static String normalizeHeader(String value) {
        return value == null ? '' : value.trim().toLowerCase();
    }

    private static Decimal parseDecimal(String value) {
        try {
            return Decimal.valueOf(value.trim());
        } catch (Exception ex) {
            return null;
        }
    }

    private static Date parseDate(String value) {
        String trimmed = value == null ? '' : value.trim();
        if (String.isBlank(trimmed)) {
            return null;
        }

        if (!trimmed.contains('/')) {
            try {
                Decimal serial = Decimal.valueOf(trimmed);
                if (serial >= 1000) {
                    return Date.newInstance(1899, 12, 30)
                        .addDays(serial.intValue());
                }
            } catch (Exception ex) {
                return null;
            }
            return null;
        }

        List<String> parts = trimmed.split('/');
        if (parts.size() != 3) {
            return null;
        }

        try {
            Integer day = Integer.valueOf(parts[0]);
            Integer month = Integer.valueOf(parts[1]);
            Integer year = Integer.valueOf(parts[2]);
            return Date.newInstance(year, month, day);
        } catch (Exception ex) {
            return null;
        }
    }

    private static String formatDateForDisplay(String rawValue) {
        Date parsedDate = parseDate(rawValue);
        if (parsedDate == null) {
            return rawValue == null ? '' : rawValue.trim();
        }

        String day = String.valueOf(parsedDate.day());
        if (parsedDate.day() < 10) {
            day = '0' + day;
        }

        String month = String.valueOf(parsedDate.month());
        if (parsedDate.month() < 10) {
            month = '0' + month;
        }

        return day + '/' + month + '/' + String.valueOf(parsedDate.year());
    }

    private static String unescapeXml(String value) {
        if (value == null) {
            return '';
        }
        return value
            .replace('&lt;', '<')
            .replace('&gt;', '>')
            .replace('&quot;', '"')
            .replace('&apos;', '\'')
            .replace('&amp;', '&');
    }

    private static void addError(List<BulkUploadError> errors,Integer rowNo,String columnName,String message){
        BulkUploadError error = new BulkUploadError();
        error.rowNo = rowNo;
        error.columnName = columnName;
        error.errorMessage = message;
        errors.add(error);
    }

    @TestVisible
    private static Date parseDateForTest(String value) {
        return parseDate(value);
    }

    @TestVisible
    private static String normalizeDataUploadForTest(String value) {
        return normalizeDataUploadCellValue(value);
    }

    @TestVisible
    private static BulkUploadSuccess buildValidationSuccessForTest(String uploadType,List<Map<String, String>> dataRows){
        return buildValidationSuccess(uploadType, dataRows);
    }

    @TestVisible
    private static List<BulkUploadError> validateOrderDateWindowForTest(Integer rowNo,String orderDateValue,Date uploadDate){
        List<BulkUploadError> errors = new List<BulkUploadError>();
        validateOrderDate(errors, rowNo, orderDateValue, uploadDate);
        return errors;
    }

    @TestVisible
    private static List<BulkUploadError> validateInvoiceDateWindowForTest(Integer rowNo,String invoiceDateValue,Date uploadDate){
        List<BulkUploadError> errors = new List<BulkUploadError>();
        validateInvoiceDate(
            errors,
            rowNo,
            invoiceDateValue,
            null,
            new Map<String, SObject>(),
            uploadDate
        );
        return errors;
    }

    @TestVisible
    private static BulkUploadResult validateSheetRowsForTest(
        String uploadType,
        List<List<String>> sheetRows
    ) {
        BulkUploadResult result = new BulkUploadResult();
        result.errors = new List<BulkUploadError>();

        List<String> expectedColumns = getExpectedColumns(uploadType);
        result.errors.addAll(validateTemplate(sheetRows, expectedColumns, uploadType));
        if (!result.errors.isEmpty()) {
            return result;
        }

        result.errors.addAll(validateEmptyDataRows(sheetRows));
        if (!result.errors.isEmpty()) {
            return result;
        }

        List<Map<String, String>> dataRows = buildDataRows(sheetRows, expectedColumns);
        if (UPLOAD_TYPE_ORDER.equalsIgnoreCase(uploadType)) {
            result.errors.addAll(validateOrderRows(dataRows));
        } else {
            result.errors.addAll(validateInvoiceRows(dataRows));
        }

        if (result.errors.isEmpty()) {
            result.success = buildValidationSuccess(uploadType, dataRows);
        }
        return result;
    }

    @TestVisible
    private static String convertAmountToWordsForTest(Decimal amount) {
        return convertAmountToWords(amount);
    }

    @TestVisible
    private static Map<String, Decimal> getTaxRatesForTest(String retailerState,String distributorState){
        return getTaxRates(retailerState, distributorState);
    }

    @TestVisible
    private static Decimal calculateLineGstForTest(Decimal taxableAmount,Map<String, Decimal> taxRates){
        return calculateLineGst(taxableAmount, taxRates);
    }

    @TestVisible
    private static Map<String, Decimal> calculateLineGstSplitForTest(Decimal taxableAmount,Map<String, Decimal> taxRates){
        return calculateLineGstSplit(taxableAmount, taxRates);
    }

    @TestVisible
    private static String normalizeProductCodeForTest(String productCode) {
        return normalizeProductCode(productCode);
    }

    @TestVisible
    private static String normalizeOrderNumberForTest(String orderNumber) {
        return normalizeOrderNumber(orderNumber);
    }

    @TestVisible
    private static Decimal parseDecimalForTest(String value) {
        return parseDecimal(value);
    }

    @TestVisible
    private static String formatDateForDisplayForTest(String rawValue) {
        return formatDateForDisplay(rawValue);
    }

    @TestVisible
    private static String mapInvoiceStatusForTest(String excelStatus) {
        return mapInvoiceStatus(excelStatus);
    }

    @TestVisible
    private static Boolean statesMatchForTest(String retailerState,String distributorState){
        return statesMatch(retailerState, distributorState);
    }

    @TestVisible
    private static String buildInvoiceNumberForTest(String invPrefix, Integer num) {
        return buildInvoiceNumber(invPrefix, num);
    }

    @TestVisible
    private static List<List<String>> parseSpreadsheetForTest(
        Blob fileBlob,
        String fileName
    ) {
        return parseSpreadsheet(fileBlob, fileName);
    }

    @TestVisible
    private static BulkUploadLineSummary buildLineSummaryForTest(
        Map<String, String> row,
        Map<String, Account> retailers,
        Map<String, SObject> products,
        Decimal quantity,
        Boolean isInvoice
    ) {
        BulkPricingContext pricingContext = buildPricingContext(retailers, products);
        return buildLineSummary(
            row,
            products,
            retailers,
            pricingContext,
            quantity,
            isInvoice
        );
    }

    @TestVisible
    private static BulkUploadResult validateUploadFileForTest(
        String uploadType,
        String fileName,
        String base64Data
    ) {
        BulkUploadResult result = new BulkUploadResult();
        BulkUploadValidationContext context = validateUploadFile(
            uploadType,
            fileName,
            base64Data
        );
        result.errors = context.errors;
        if (result.errors.isEmpty()) {
            result.success = buildValidationSuccess(uploadType, context.dataRows);
        }
        return result;
    }

    @TestVisible
    private static List<BulkUploadError> validateInvoiceDateWithOrderForTest(
        Integer rowNo,
        String invoiceDateValue,
        String orderNumber,
        Date orderEffectiveDate,
        Date uploadDate
    ) {
        List<BulkUploadError> errors = new List<BulkUploadError>();
        Map<String, SObject> orders = new Map<String, SObject>();
        if (!String.isBlank(orderNumber) && Schema.getGlobalDescribe().containsKey(ORDER_SOBJECT)) {
            SObject orderRecord = Schema.getGlobalDescribe()
                .get(ORDER_SOBJECT)
                .newSObject();
            orderRecord.put('EffectiveDate__c', orderEffectiveDate);
            orders.put(
                normalizeOrderNumber(orderNumber).toUpperCase(),
                orderRecord
            );
        }
        validateInvoiceDate(
            errors,
            rowNo,
            invoiceDateValue,
            orderNumber,
            orders,
            uploadDate
        );
        return errors;
    }

    @TestVisible
    private static BulkUploadSaveResult saveBulkUploadForTest(
        String uploadType,
        String fileName,
        String base64Data
    ) {
        return saveBulkUpload(uploadType, fileName, base64Data);
    }

    @TestVisible
    private static BulkOrderCreationResult createBulkOrdersForTest(
        List<Map<String, String>> dataRows,
        Blob fileBlob,
        String fileName
    ) {
        return createBulkOrders(dataRows, fileBlob, fileName);
    }

    @TestVisible
    private static String resolveRetailerDistributorFieldApiForTest() {
        return resolveRetailerDistributorFieldApi();
    }

    @TestVisible
    private static Id getCurrentUserDistributorAccountIdForTest() {
        return getCurrentUserDistributorAccountId();
    }

    @TestVisible
    private static void createBulkInvoicesForTest(
        List<Map<String, String>> dataRows,
        Blob fileBlob,
        String fileName
    ) {
        createBulkInvoices(dataRows, fileBlob, fileName);
    }

    @TestVisible
    private static Map<String, SObject> loadOrdersForTest(Set<String> orderNumbers) {
        return loadOrders(orderNumbers);
    }

    @TestVisible
    private static Map<Id, Invoice__c> loadDraftInvoicesByOrderIdForTest(Set<Id> orderIds) {
        return loadDraftInvoicesByOrderId(orderIds);
    }

    @TestVisible
    private static String getProductNameForTest(
        Map<String, SObject> products,
        String productCode
    ) {
        return getProductName(products, productCode);
    }

    @TestVisible
    private static Map<String, Account> loadRetailersForOrderCreationForTest(
        Set<String> retailerCodes
    ) {
        return loadRetailersForOrderCreation(retailerCodes);
    }

    @TestVisible
    private static Map<String, SObject> loadOrdersForInvoiceCreationForTest(
        Set<String> orderNumbers
    ) {
        return loadOrdersForInvoiceCreation(orderNumbers);
    }

    @TestVisible
    private static Account loadDistributorAccountDetailsForTest(Id distributorAccountId) {
        return loadDistributorAccountDetails(distributorAccountId);
    }

    @TestVisible
    private static Boolean isTodEligibleForTest(Decimal mrp, Decimal perPieces) {
        return isTodEligible(mrp, perPieces);
    }

    @TestVisible
    private static Boolean isDiscountActiveOnDateForTest(
        Discount__c discount,
        Date effectiveDate
    ) {
        return isDiscountActiveOnDate(discount, effectiveDate);
    }

    @TestVisible
    private static List<Discount__c> loadDiscountRecordsForTest(Set<Id> retailerAccountIds) {
        return loadDiscountRecords(retailerAccountIds);
    }

    @TestVisible
    private static Map<Id, Product__c> loadProductDetailsForTodForTest(Set<Id> productIds) {
        return loadProductDetailsForTod(productIds);
    }

    @TestVisible
    private static Decimal resolveTodDiscountPercentForTest(
        List<Discount__c> discountRecords,
        Map<Id, Product__c> productDetailsById,
        Id accountId,
        Id productId,
        Date effectiveDate
    ) {
        BulkPricingContext context = new BulkPricingContext();
        context.discountRecords = discountRecords;
        context.productDetailsById = productDetailsById;
        return resolveTodDiscountPercent(context, accountId, productId, effectiveDate);
    }

    @TestVisible
    private static Decimal resolveTodAmountForTest(
        List<Discount__c> discountRecords,
        Map<Id, Product__c> productDetailsById,
        Account retailer,
        Id productId,
        Map<String, String> row,
        Boolean isInvoice,
        Decimal amount
    ) {
        BulkPricingContext context = new BulkPricingContext();
        context.discountRecords = discountRecords;
        context.productDetailsById = productDetailsById;
        return resolveTodAmount(context, retailer, productId, row, isInvoice, amount);
    }

    @TestVisible
    private static Integer buildPricingContextDiscountCountForTest(
        Map<String, Account> retailers,
        Map<String, SObject> products
    ) {
        BulkPricingContext context = buildPricingContext(retailers, products);
        Integer discountCount =
            context.discountRecords == null ? 0 : context.discountRecords.size();
        Integer productDetailCount =
            context.productDetailsById == null ? 0 : context.productDetailsById.size();
        return discountCount + productDetailCount;
    }

    @TestVisible
    private static String getDistributorPrimaryStateForTest() {
        return getDistributorPrimaryState();
    }

    @TestVisible
    private static Map<String, Id> loadRegionPricebookMapForTest() {
        return loadRegionPricebookMap();
    }

    @TestVisible
    private static Decimal resolvePtrForTest(
        Map<String, Account> retailers,
        Map<String, SObject> products,
        String retailerCode,
        String productCode
    ) {
        BulkPricingContext context = buildPricingContext(retailers, products);
        Account retailer = null;
        if (!String.isBlank(retailerCode)) {
            retailer = retailers.get(retailerCode.trim().toUpperCase());
        }
        Id productId = getProductId(products, productCode);
        return resolvePtr(context, retailer, productId);
    }

    @TestVisible
    private static String getOrderNumberFieldApiNameForTest() {
        return getOrderNumberFieldApiName();
    }

    @TestVisible
    private static Id resolvePricebookIdForRetailerForTest(
        Account retailer,
        Map<String, Id> regionToPricebookId
    ) {
        return resolvePricebookIdForRetailer(retailer, regionToPricebookId);
    }

    @TestVisible
    private static Map<String, Decimal> loadPtrByPricebookAndProductForTest(
        Set<Id> pricebookIds,
        Set<Id> productIds
    ) {
        return loadPtrByPricebookAndProduct(pricebookIds, productIds);
    }

    @TestVisible
    private static String buildPricebookProductKeyForTest(Id pricebookId, Id productId) {
        return buildPricebookProductKey(pricebookId, productId);
    }

    @TestVisible
    private static Id getProductIdForTest(Map<String, SObject> products, String productCode) {
        return getProductId(products, productCode);
    }

    @TestVisible
    private static Decimal resolvePtrWithInjectedMapsForTest(
        Account retailer,
        Id productId,
        Map<String, Id> regionToPricebookId,
        Map<String, Decimal> ptrByPricebookProductKey
    ) {
        BulkPricingContext context = new BulkPricingContext();
        context.regionToPricebookId = regionToPricebookId;
        context.ptrByPricebookProductKey = ptrByPricebookProductKey;
        return resolvePtr(context, retailer, productId);
    }

    @TestVisible
    private static Integer groupOrderRowsByReferenceCountForTest(List<Map<String, String>> dataRows){
        return groupOrderRowsByReference(dataRows).size();
    }
    
    

    @TestVisible
    private static List<Decimal> addOrderTotalsLineForTest(
        BulkUploadLineSummary lineSummary,
        Account retailer,
        String distributorState,
        Map<String, Decimal> taxRates
    ){
        BulkPricingContext context = new BulkPricingContext();
        context.distributorState = distributorState;
        context.taxRatesByRetailerState = new Map<String, Map<String, Decimal>>();
        String retailerState =
            retailer != null && retailer.Primary_State__c != null
                ? retailer.Primary_State__c.trim().toUpperCase()
                : '';
        context.taxRatesByRetailerState.put(retailerState, taxRates);

        OrderTotals totals = new OrderTotals();
        totals.addLine(lineSummary, retailer, context);
        return new List<Decimal>{
            totals.totalQuantity,
            totals.totalOrderValue,
            totals.priceTotal,
            totals.subTotal,
            totals.discountAmount,
            totals.totalCgst,
            totals.totalSgst,
            totals.totalIgst
        };
    }

    @TestVisible
    private static Order__c buildOrderHeaderForTest(
        Map<String, String> headerRow,
        Account retailer,
        Id distributorId,
        Id orderRecordTypeId,
        String fileName,
        Decimal totalOrderValue,
        Decimal totalQuantity,
        Decimal priceTotal,
        Decimal subTotal,
        Decimal discountAmount,
        Decimal totalCgst,
        Decimal totalSgst,
        Decimal totalIgst
    ) {
        OrderTotals orderTotals = new OrderTotals();
        orderTotals.totalOrderValue = totalOrderValue;
        orderTotals.totalQuantity = totalQuantity;
        orderTotals.priceTotal = priceTotal;
        orderTotals.subTotal = subTotal;
        orderTotals.discountAmount = discountAmount;
        orderTotals.totalCgst = totalCgst;
        orderTotals.totalSgst = totalSgst;
        orderTotals.totalIgst = totalIgst;
        return buildOrderHeader(
            headerRow,
            retailer,
            distributorId,
            orderRecordTypeId,
            fileName,
            orderTotals
        );
    }

    @TestVisible
    private static Integer groupInvoiceRowsByReferenceCountForTest(List<Map<String, String>> dataRows){
        return groupInvoiceRowsByReference(dataRows).size();
    }

    @TestVisible
    private static List<Decimal> addInvoiceTotalsLineForTest(
        BulkUploadLineSummary lineSummary,
        Account retailer,
        String distributorState,
        Map<String, Decimal> taxRates
    ) {
        BulkPricingContext context = new BulkPricingContext();
        context.distributorState = distributorState;
        context.taxRatesByRetailerState = new Map<String, Map<String, Decimal>>();
        String retailerState =
            retailer != null && retailer.Primary_State__c != null
                ? retailer.Primary_State__c.trim().toUpperCase()
                : '';
        context.taxRatesByRetailerState.put(retailerState, taxRates);

        InvoiceTotals totals = new InvoiceTotals();
        totals.addLine(lineSummary, retailer, context);
        return new List<Decimal>{
            totals.totalQuantity,
            totals.invoiceAmount,
            totals.subTotal,
            totals.taxableAmount,
            totals.totalGst,
            totals.totalCgst,
            totals.totalSgst,
            totals.totalIgst
        };
    }

    @TestVisible
    private static Invoice__c buildInvoiceHeaderForTest(
        Map<String, String> headerRow,
        Account retailer,
        Id distributorId,
        Account distributorAccount,
        SObject linkedOrder,
        Id invoiceRecordTypeId,
        String fileName,
        String invoiceNumber,
        Decimal totalQuantity,
        Decimal invoiceAmount,
        Decimal subTotal,
        Decimal taxableAmount,
        Decimal totalGst,
        Decimal totalCgst,
        Decimal totalSgst,
        Decimal totalIgst
    ) {
        InvoiceTotals invoiceTotals = new InvoiceTotals();
        invoiceTotals.totalQuantity = totalQuantity;
        invoiceTotals.invoiceAmount = invoiceAmount;
        invoiceTotals.subTotal = subTotal;
        invoiceTotals.taxableAmount = taxableAmount;
        invoiceTotals.totalGst = totalGst;
        invoiceTotals.totalCgst = totalCgst;
        invoiceTotals.totalSgst = totalSgst;
        invoiceTotals.totalIgst = totalIgst;
        return buildInvoiceHeader(
            headerRow,
            retailer,
            distributorId,
            distributorAccount,
            linkedOrder,
            invoiceRecordTypeId,
            fileName,
            invoiceNumber,
            invoiceTotals
        );
    }

    @TestVisible
    private static List<String> findExistingOrderRefsForTest(Set<String> refNumbers) {
        return findExistingOrderRefs(refNumbers);
    }

    @TestVisible
    private static List<String> findExistingInvoiceRefsForTest(Set<String> refNumbers) {
        return findExistingInvoiceRefs(refNumbers);
    }

    @TestVisible
    private static DuplicateCheckResult checkExistingReferencesForTest(String uploadType,String fileName,String base64Data){
        return checkExistingReferences(uploadType, fileName, base64Data);
    }

    @TestVisible
    private static BulkUploadSaveResult saveBulkUploadWithUpdateSupportForTest(
        String uploadType,String fileName,String base64Data,Boolean confirmedUpdateExisting
    ){
        return saveBulkUploadWithUpdateSupport(uploadType,fileName,base64Data,confirmedUpdateExisting);
    }

    @TestVisible
    private static Map<String, Order__c> loadExistingOrdersByRefForTest(Set<String> refKeys) {
        return loadExistingOrdersByRef(refKeys);
    }

    @TestVisible
    private static Map<String, Invoice__c> loadExistingInvoicesByRefForTest(Set<String> refKeys) {
        return loadExistingInvoicesByRef(refKeys);
    }
    
    @TestVisible
    private static OrderUpdateResult updateExistingOrdersForTest(List<Map<String, String>> updateRows){
        return updateExistingOrders(updateRows);
    }
    
    @TestVisible
    private static InvoiceUpdateResult updateExistingInvoicesForTest(List<Map<String, String>> updateRows){
        return updateExistingInvoices(updateRows);
    }
    
    @TestVisible
    private static void recalculateOrderTotalsForTest(Set<Id> orderIds) {
        recalculateOrderTotals(orderIds);
    }
    
    @TestVisible
    private static void recalculateInvoiceTotalsForTest(Set<Id> invoiceIds) {
        recalculateInvoiceTotals(invoiceIds);
    }
    
    @TestVisible
    private static Map<Id, List<Order_Line_Item__c>> loadExistingOrderLineItemsForTest(Set<Id> orderIds){
        return loadExistingOrderLineItems(orderIds);
    }
    
    @TestVisible
    private static Map<Id, List<Invoice_Line_Item__c>> loadExistingInvoiceLineItemsForTest(Set<Id> invoiceIds){
        return loadExistingInvoiceLineItems(invoiceIds);
    }
    
    public class BulkUploadResult {
        @AuraEnabled public List<BulkUploadError> errors { get; set; }
        @AuraEnabled public BulkUploadSuccess success { get; set; }
    }

    public class BulkUploadSaveResult {
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public List<BulkUploadError> errors { get; set; }
        @AuraEnabled public BulkUploadSuccess success { get; set; }
        @AuraEnabled public Integer ordersCreated { get; set; }
        @AuraEnabled public List<Id> createdOrderIds { get; set; }
        @AuraEnabled public List<String> createdOrderNames { get; set; }
        @AuraEnabled public Integer invoicesCreated { get; set; }
        @AuraEnabled public List<Id> createdInvoiceIds { get; set; }
        @AuraEnabled public List<String> createdInvoiceNames { get; set; }
    }

    public class BulkUploadError {
        @AuraEnabled public Integer rowNo { get; set; }
        @AuraEnabled public String columnName { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
    }

    public class BulkUploadSuccess {
        @AuraEnabled public String recordType { get; set; }
        @AuraEnabled public Integer headerCount { get; set; }
        @AuraEnabled public Integer lineItemCount { get; set; }
        @AuraEnabled public List<BulkUploadGroupSummary> groups { get; set; }
        @AuraEnabled public Boolean validationPassed { get; set; }
    }

    public class BulkUploadGroupSummary {
        @AuraEnabled public String refNo { get; set; }
        @AuraEnabled public String orderDate { get; set; }
        @AuraEnabled public String invoiceDate { get; set; }
        @AuraEnabled public String retailerName { get; set; }
        @AuraEnabled public String orderNumber { get; set; }
        @AuraEnabled public Decimal totalQuantity { get; set; }
        @AuraEnabled public Decimal grandTotal { get; set; }
        @AuraEnabled public Decimal totalGst { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public List<BulkUploadLineSummary> lineItems { get; set; }
    }

    public class BulkUploadLineSummary {
        @AuraEnabled public Integer rowNo { get; set; }
        @AuraEnabled public String productCode { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public Decimal price { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public Decimal tod { get; set; }
        @AuraEnabled public Decimal discountPercent { get; set; }
        @AuraEnabled public Decimal discountAmount { get; set; }
        @AuraEnabled public Decimal taxableAmount { get; set; }
        @AuraEnabled public Decimal totalGst { get; set; }
        @AuraEnabled public Decimal totalAmountInclTax { get; set; }
    }

    public class DuplicateCheckResult {
        @AuraEnabled public Boolean hasDuplicates { get; set; }
        @AuraEnabled public List<String> duplicateRefs { get; set; }
        @AuraEnabled public Boolean hasValidationErrors { get; set; }
    }
}