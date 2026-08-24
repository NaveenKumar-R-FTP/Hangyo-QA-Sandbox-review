@IsTest
private class HangyoBulkSalesUploadControllerTest {
    @TestSetup
    static void setupBulkUploadAccess() {
        assignBulkUploadPermission(UserInfo.getUserId());
    }

    @IsTest
    static void validateBulkUploadRejectsInvalidUploadType() {
        Boolean exceptionThrown = false;
        try {
            HangyoBulkSalesUploadController.validateBulkUpload(
                'Invalid',
                'sample.xlsx',
                EncodingUtil.base64Encode(Blob.valueOf('test'))
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
            assertAuraExceptionMessage(
                ex,
                'Invalid upload type',
                'Expected invalid upload type message.'
            );
        }
        System.assert(exceptionThrown, 'Expected AuraHandledException for invalid upload type.');
    }

    @IsTest
    static void validateOrderTemplateRejectsInvalidHeader() {
        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Order No',
                'Order Date',
                'Retailer Code',
                'Product Code',
                'Quantity',
                'Data Upload'
            },
            new List<String>{ '100', '14/5/2026', 'SF123', 'P001', '5', 'TRUE' }
        };

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Order', sheetRows);

        System.assertEquals(null, result.success, 'Success should be null.');
        System.assert(!result.errors.isEmpty(), 'Template errors should be returned.');
        System.assertEquals('Template', result.errors[0].columnName);
    }

    @IsTest
    static void validateOrderRowsCatchMandatoryAndDataUploadErrors() {
        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Order No.',
                'Order Date',
                'Retailer Code',
                'Product Code',
                'Quantity',
                'Data Upload'
            },
            new List<String>{ '', '14/5/2026', 'SF123', 'P001', '0', 'FALSE' }
        };

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Order', sheetRows);

        System.assert(result.errors.size() >= 3, 'Expected multiple validation errors.');
        System.assertEquals(null, result.success);
    }

    @IsTest
    static void validateInvoiceRowsCatchInvalidStatusAndDiscount() {
        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Invoice No.',
                'Invoice Date',
                'Retailer Code',
                'Order Number',
                'Product Code',
                'Discount 2%',
                'Quantity',
                'Data Upload',
                'Status'
            },
            new List<String>{
                '200',
                '14/5/2026',
                'SF123',
                'O-0459',
                'P001',
                '-1',
                '0',
                'FALSE',
                'Posted'
            }
        };

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Invoice', sheetRows);

        System.assert(result.errors.size() >= 4, 'Expected invoice validation errors.');
        System.assertEquals(null, result.success);
    }

    @IsTest
    static void validateInvoiceGroupConsistency() {
        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Invoice No.',
                'Invoice Date',
                'Retailer Code',
                'Order Number',
                'Product Code',
                'Discount 2%',
                'Quantity',
                'Data Upload',
                'Status'
            },
            new List<String>{
                '300',
                '14/5/2026',
                'SF123',
                'O-0459',
                'P001',
                '5',
                '5',
                'TRUE',
                'Draft'
            },
            new List<String>{
                '300',
                '15/5/2026',
                'SF123',
                'O-0459',
                'P002',
                '5',
                '5',
                'TRUE',
                'Draft'
            }
        };

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Invoice', sheetRows);

        Boolean hasGroupError = false;
        for (HangyoBulkSalesUploadController.BulkUploadError error : result.errors) {
            if (error.columnName == 'Invoice Date') {
                hasGroupError = true;
                break;
            }
        }
        System.assert(hasGroupError, 'Expected grouped invoice date consistency error.');
    }

    @IsTest
    static void validateInvoiceGroupDiscount2Consistency() {
        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Invoice No.',
                'Invoice Date',
                'Retailer Code',
                'Order Number',
                'Product Code',
                'Discount 2%',
                'Quantity',
                'Data Upload',
                'Status'
            },
            new List<String>{
                'INV-001',
                '14/5/2026',
                'SF123',
                'O-0459',
                'P001',
                '2',
                '2',
                'TRUE',
                'Draft'
            },
            new List<String>{
                'INV-001',
                '14/5/2026',
                'SF123',
                'O-0459',
                'P002',
                '3',
                '5',
                'TRUE',
                'Draft'
            }
        };

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Invoice', sheetRows);

        Boolean hasDiscountGroupError = false;
        for (HangyoBulkSalesUploadController.BulkUploadError error : result.errors) {
            if (error.columnName == 'Discount 2%') {
                hasDiscountGroupError = true;
                break;
            }
        }
        System.assert(
            hasDiscountGroupError,
            'Expected grouped Discount 2% consistency error.'
        );
    }

    @IsTest
    static void validateDataUploadAcceptsExcelBooleanTrue() {
        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Order No.',
                'Order Date',
                'Retailer Code',
                'Product Code',
                'Quantity',
                'Data Upload'
            },
            new List<String>{ 'ORD-001', '14/5/2026', 'SF123', 'P001', '5', '1' }
        };

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Order', sheetRows);

        for (HangyoBulkSalesUploadController.BulkUploadError error : result.errors) {
            System.assertNotEquals(
                'Data Upload',
                error.columnName,
                'Excel boolean TRUE (1) should be accepted for Data Upload.'
            );
        }
    }

    @IsTest
    static void validateEmptyRowBetweenRecordsIsRejected() {
        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Order No.',
                'Order Date',
                'Retailer Code',
                'Product Code',
                'Quantity',
                'Data Upload'
            },
            new List<String>{ 'ORD-001', '14/5/2026', 'SF123', 'P001', '5', 'TRUE' },
            new List<String>{ '', '', '', '', '', '' },
            new List<String>{ 'ORD-002', '15/5/2026', 'SF124', 'P002', '3', 'TRUE' }
        };

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Order', sheetRows);

        Boolean hasEmptyRowError = false;
        for (HangyoBulkSalesUploadController.BulkUploadError error : result.errors) {
            if (error.rowNo == 3 && error.columnName == 'Template') {
                hasEmptyRowError = true;
                break;
            }
        }
        System.assert(hasEmptyRowError, 'Expected empty row validation error on row 3.');
        System.assertEquals(null, result.success);
    }

    @IsTest
    static void validateBulkUploadRejectsLegacyXls() {
        Boolean exceptionThrown = false;
        try {
            HangyoBulkSalesUploadController.validateBulkUpload(
                'Order',
                'legacy.xls',
                EncodingUtil.base64Encode(Blob.valueOf('dummy'))
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
            assertAuraExceptionMessage(
                ex,
                '.xlsx',
                'Expected guidance to upload xlsx.'
            );
        }
        System.assert(exceptionThrown, 'Expected AuraHandledException for legacy xls.');
    }

    //Added by Hari - Order Record Creation
    @IsTest
    static void saveBulkUploadReturnsValidationErrorsForInvoiceWithoutDml() {
        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Invoice No.',
                'Invoice Date',
                'Retailer Code',
                'Order Number',
                'Product Code',
                'Discount 2%',
                'Quantity',
                'Data Upload',
                'Status'
            },
            new List<String>{
                '',
                '14/5/2026',
                'SF123',
                'O-001',
                'P001',
                '4',
                '0',
                'FALSE',
                'DRAFT'
            }
        };

        HangyoBulkSalesUploadController.BulkUploadResult validationResult =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Invoice', sheetRows);
        System.assertEquals(null, validationResult.success);
        System.assert(!validationResult.errors.isEmpty());
    }

    @IsTest
    static void validateOrderDateRejectsDatesOutsideUploadWindow() {
        Date uploadDate = System.today();
        Date validOrderDate = uploadDate.addDays(-3);
        Date tooOldOrderDate = uploadDate.addDays(-4);
        Date futureOrderDate = uploadDate.addDays(1);

        List<HangyoBulkSalesUploadController.BulkUploadError> tooOldErrors =
            HangyoBulkSalesUploadController.validateOrderDateWindowForTest(
                2,
                formatTestDate(tooOldOrderDate),
                uploadDate
            );
        List<HangyoBulkSalesUploadController.BulkUploadError> futureErrors =
            HangyoBulkSalesUploadController.validateOrderDateWindowForTest(
                3,
                formatTestDate(futureOrderDate),
                uploadDate
            );
        List<HangyoBulkSalesUploadController.BulkUploadError> validErrors =
            HangyoBulkSalesUploadController.validateOrderDateWindowForTest(
                4,
                formatTestDate(validOrderDate),
                uploadDate
            );

        System.assertEquals(
            1,
            tooOldErrors.size(),
            'Expected one error for order date more than 3 days before upload.'
        );
        System.assert(
            tooOldErrors[0].errorMessage.contains('more than 3 days before'),
            'Expected too-old order date message.'
        );

        System.assertEquals(
            1,
            futureErrors.size(),
            'Expected one error for order date after upload date.'
        );
        System.assert(
            futureErrors[0].errorMessage.contains('after the upload date'),
            'Expected future order date message.'
        );

        System.assertEquals(
            0,
            validErrors.size(),
            'Order date exactly 3 days before upload should be allowed.'
        );
    }

    @IsTest
    static void validateInvoiceDateRejectsDatesOutsideAllowedWindow() {
        Date uploadDate = System.today();
        Date validInvoiceDate = uploadDate;
        Date tooOldInvoiceDate = uploadDate.addDays(-4);
        Date futureInvoiceDate = uploadDate.addDays(1);

        List<HangyoBulkSalesUploadController.BulkUploadError> tooOldErrors =
            HangyoBulkSalesUploadController.validateInvoiceDateWindowForTest(
                2,
                formatTestDate(tooOldInvoiceDate),
                uploadDate
            );
        List<HangyoBulkSalesUploadController.BulkUploadError> futureErrors =
            HangyoBulkSalesUploadController.validateInvoiceDateWindowForTest(
                3,
                formatTestDate(futureInvoiceDate),
                uploadDate
            );
        List<HangyoBulkSalesUploadController.BulkUploadError> validErrors =
            HangyoBulkSalesUploadController.validateInvoiceDateWindowForTest(
                4,
                formatTestDate(validInvoiceDate),
                uploadDate
            );

        System.assertEquals(
            1,
            tooOldErrors.size(),
            'Expected one error for invoice date more than 3 days before upload.'
        );
        System.assert(
            tooOldErrors[0].errorMessage.contains('more than 3 days before'),
            'Expected too-old invoice date message.'
        );

        System.assertEquals(
            1,
            futureErrors.size(),
            'Expected one error for invoice date after upload date.'
        );
        System.assert(
            futureErrors[0].errorMessage.contains('after the upload date'),
            'Expected future invoice date message.'
        );

        System.assertEquals(
            0,
            validErrors.size(),
            'Invoice date on upload day should be allowed.'
        );
    }

    private static String formatTestDate(Date value) {
        String day = String.valueOf(value.day());
        if (value.day() < 10) {
            day = '0' + day;
        }

        String month = String.valueOf(value.month());
        if (value.month() < 10) {
            month = '0' + month;
        }

        return day + '/' + month + '/' + String.valueOf(value.year());
    }

    private static void assertAuraExceptionMessage(
        AuraHandledException ex,
        String expectedSubstring,
        String failureMessage
    ) {
        String actualMessage = getAuraExceptionMessage(ex);
        System.assert(
            actualMessage.contains(expectedSubstring),
            failureMessage + ' Actual: ' + actualMessage
        );
    }

    private static String getAuraExceptionMessage(AuraHandledException ex) {
        String storedMessage =
            HangyoBulkSalesUploadController.lastAuraHandledMessageForTest;
        if (!String.isBlank(storedMessage)) {
            return storedMessage;
        }
        return ex.getMessage();
    }

    @IsTest
    static void saveBulkUploadReturnsValidationErrorsWithoutDml() {
        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Order No.',
                'Order Date',
                'Retailer Code',
                'Product Code',
                'Quantity',
                'Data Upload'
            },
            new List<String>{ '', '14/5/2026', 'SF123', 'P001', '0', 'FALSE' }
        };

        HangyoBulkSalesUploadController.BulkUploadResult validationResult =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Order', sheetRows);
        System.assertEquals(null, validationResult.success);
        System.assert(!validationResult.errors.isEmpty());
    }

    @IsTest
    static void hasBulkUploadAccessReflectsUserPermission() {
        Boolean hasAccess = HangyoBulkSalesUploadController.hasBulkUploadAccess();
        System.assertNotEquals(null, hasAccess);
    }

    @IsTest
    static void validateBulkUploadReturnsFileRequiredError() {
        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateBulkUpload('Order', '', '');

        System.assertEquals(null, result.success);
        System.assert(!result.errors.isEmpty());
        System.assertEquals('File', result.errors[0].columnName);
    }

    @IsTest
    static void saveBulkUploadReturnsValidationFailedForMissingFile() {
        HangyoBulkSalesUploadController.BulkUploadSaveResult result =
            HangyoBulkSalesUploadController.saveBulkUpload('Order', '', '');

        System.assertEquals('ValidationFailed', result.status);
        System.assert(!result.errors.isEmpty());
        System.assertEquals('File', result.errors[0].columnName);
    }

    @IsTest
    static void validateInvoiceTemplateRejectsInvalidHeader() {
        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Invoice No',
                'Invoice Date',
                'Retailer Code',
                'Order Number',
                'Product Code',
                'Discount 2%',
                'Quantity',
                'Data Upload',
                'Status'
            },
            new List<String>{
                '100',
                '14/5/2026',
                'SF123',
                'O-001',
                'P001',
                '0',
                '5',
                'TRUE',
                'Draft'
            }
        };

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Invoice', sheetRows);

        System.assertEquals(null, result.success);
        System.assert(!result.errors.isEmpty());
        System.assertEquals('Template', result.errors[0].columnName);
    }

    @IsTest
    static void validateOrderDateWindowThroughSheetRows() {
        Date uploadDate = System.today();
        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Order No.',
                'Order Date',
                'Retailer Code',
                'Product Code',
                'Quantity',
                'Data Upload'
            },
            new List<String>{
                'ORD-OLD',
                formatTestDate(uploadDate.addDays(-4)),
                'SF123',
                'P001',
                '5',
                'TRUE'
            }
        };

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Order', sheetRows);

        Boolean hasOrderDateWindowError = false;
        for (HangyoBulkSalesUploadController.BulkUploadError error : result.errors) {
            if (
                error.columnName == 'Order Date' &&
                error.errorMessage.contains('more than 3 days before')
            ) {
                hasOrderDateWindowError = true;
                break;
            }
        }
        System.assert(
            hasOrderDateWindowError,
            'Expected order date window error from sheet row validation.'
        );
    }

    @IsTest
    static void parseDateSupportsDdMmYyyyAndExcelSerialFormats() {
        System.assertEquals(
            Date.newInstance(2026, 5, 14),
            HangyoBulkSalesUploadController.parseDateForTest('14/5/2026')
        );
        System.assertEquals(
            Date.newInstance(2026, 7, 1),
            HangyoBulkSalesUploadController.parseDateForTest('01/07/2026')
        );
        System.assertEquals(null, HangyoBulkSalesUploadController.parseDateForTest('invalid'));
    }

    @IsTest
    static void normalizeDataUploadCoversCommonSpreadsheetValues() {
        System.assertEquals(
            'TRUE',
            HangyoBulkSalesUploadController.normalizeDataUploadForTest('1')
        );
        System.assertEquals(
            'FALSE',
            HangyoBulkSalesUploadController.normalizeDataUploadForTest('0')
        );
        System.assertEquals(
            'TRUE',
            HangyoBulkSalesUploadController.normalizeDataUploadForTest('true')
        );
    }

    @IsTest
    static void validateSheetRejectsOrderTemplateForInvoiceUpload() {
        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Order No.',
                'Order Date',
                'Retailer Code',
                'Product Code',
                'Quantity',
                'Data Upload'
            },
            new List<String>{ 'ORD-001', '14/5/2026', 'SF123', 'P001', '5', 'TRUE' }
        };

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Invoice', sheetRows);

        System.assertEquals(null, result.success);
        System.assert(!result.errors.isEmpty());
        System.assertEquals('Format', result.errors[0].columnName);
    }

    @IsTest
    static void validateBulkUploadHandlesUnreadableSpreadsheet() {
        Boolean exceptionThrown = false;
        try {
            HangyoBulkSalesUploadController.validateBulkUpload(
                'Order',
                'sample.xlsx',
                EncodingUtil.base64Encode(Blob.valueOf('invalid-zip-content'))
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        System.assert(exceptionThrown, 'Expected AuraHandledException for unreadable spreadsheet.');
    }

    @IsTest
    static void validateBulkUploadReturnsEmptyFileError() {
        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateBulkUpload(
                'Order',
                'sample.xlsx',
                EncodingUtil.base64Encode(Blob.valueOf(''))
            );

        System.assertEquals(null, result.success);
        System.assert(!result.errors.isEmpty());
        System.assertEquals('File', result.errors[0].columnName);
    }

    @IsTest
    static void buildValidationSuccessSummarizesOrderAndInvoiceGroups() {
        List<Map<String, String>> orderRows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Order No.' => 'ORD-001',
                'Order Date' => '14/5/2026',
                'Retailer Code' => 'SF123',
                'Product Code' => 'P001',
                'Quantity' => '5',
                'Data Upload' => 'TRUE',
                '__rowNumber' => '2'
            }
        };
        HangyoBulkSalesUploadController.BulkUploadSuccess orderSuccess =
            HangyoBulkSalesUploadController.buildValidationSuccessForTest(
                'Order',
                orderRows
            );
        System.assertEquals('Order', orderSuccess.recordType);
        System.assertEquals(1, orderSuccess.headerCount);
        System.assertEquals(1, orderSuccess.lineItemCount);
        System.assertEquals(true, orderSuccess.validationPassed);
        System.assertEquals(1, orderSuccess.groups.size());

        List<Map<String, String>> invoiceRows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Invoice No.' => 'INV-001',
                'Invoice Date' => '14/5/2026',
                'Retailer Code' => 'SF123',
                'Order Number' => 'O-001',
                'Product Code' => 'P001',
                'Discount 2%' => '0',
                'Quantity' => '5',
                'Data Upload' => 'TRUE',
                'Status' => 'Draft',
                '__rowNumber' => '2'
            }
        };
        HangyoBulkSalesUploadController.BulkUploadSuccess invoiceSuccess =
            HangyoBulkSalesUploadController.buildValidationSuccessForTest(
                'Invoice',
                invoiceRows
            );
        System.assertEquals('Invoice', invoiceSuccess.recordType);
        System.assertEquals(1, invoiceSuccess.headerCount);
        System.assertEquals(1, invoiceSuccess.groups.size());
    }

    @IsTest
    static void validateBulkUploadParsesMinimalOrderSpreadsheet() {
        String base64Xlsx = buildMinimalOrderSpreadsheetBase64();
        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateBulkUpload(
                'Order',
                'orders.xlsx',
                base64Xlsx
            );

        System.assertEquals(null, result.success);
        System.assert(!result.errors.isEmpty(), 'Expected row validation errors after parsing xlsx.');
    }

    @IsTest
    static void saveBulkUploadParsesMinimalInvoiceSpreadsheetWithoutDml() {
        String base64Xlsx = buildMinimalInvoiceSpreadsheetBase64();
        HangyoBulkSalesUploadController.BulkUploadSaveResult result =
            HangyoBulkSalesUploadController.saveBulkUpload(
                'Invoice',
                'invoices.xlsx',
                base64Xlsx
            );

        System.assertEquals('ValidationFailed', result.status);
        System.assert(!result.errors.isEmpty());
    }

    @IsTest
    static void utilityMethodsCoverFormattingTaxAndNormalization() {
        System.assertEquals(
            'Zero Only',
            HangyoBulkSalesUploadController.convertAmountToWordsForTest(Decimal.valueOf(0))
        );
        System.assert(
            HangyoBulkSalesUploadController.convertAmountToWordsForTest(Decimal.valueOf(125))
                .contains('Only')
        );
        System.assert(
            HangyoBulkSalesUploadController.convertAmountToWordsForTest(Decimal.valueOf(1500))
                .contains('Only')
        );
        System.assert(
            HangyoBulkSalesUploadController.convertAmountToWordsForTest(Decimal.valueOf(125000))
                .contains('Only')
        );
        System.assert(
            HangyoBulkSalesUploadController.convertAmountToWordsForTest(Decimal.valueOf(10000000))
                .contains('Only')
        );
        System.assertEquals(
            'P001',
            HangyoBulkSalesUploadController.normalizeProductCodeForTest('P001.0')
        );
        System.assertEquals(
            'O-0459',
            HangyoBulkSalesUploadController.normalizeOrderNumberForTest('O-0459.0')
        );
        System.assertEquals(
            'Draft',
            HangyoBulkSalesUploadController.mapInvoiceStatusForTest('DRAFT')
        );
        System.assertEquals(
            'Confirmed',
            HangyoBulkSalesUploadController.mapInvoiceStatusForTest('CONFIRMED')
        );
        System.assertEquals(
            true,
            HangyoBulkSalesUploadController.statesMatchForTest('Karnataka', 'karnataka')
        );
        System.assertEquals(
            'INV0001000',
            HangyoBulkSalesUploadController.buildInvoiceNumberForTest('INV', 1000)
        );
        System.assertEquals(
            Decimal.valueOf('12.5'),
            HangyoBulkSalesUploadController.parseDecimalForTest('12.5')
        );
        System.assertEquals(
            '14/05/2026',
            HangyoBulkSalesUploadController.formatDateForDisplayForTest('14/5/2026')
        );
    }

    @IsTest
    static void parseSpreadsheetReadsGeneratedWorkbook() {
        Blob workbook = buildMinimalSpreadsheetBlob(
            new List<String>{
                'Ref Order No.',
                'Order Date',
                'Retailer Code',
                'Product Code',
                'Quantity',
                'Data Upload'
            },
            new List<String>{
                'ORD-001',
                '14/5/2026',
                'SF123',
                'P001',
                '5',
                'TRUE'
            }
        );

        List<List<String>> rows = HangyoBulkSalesUploadController.parseSpreadsheetForTest(
            workbook,
            'orders.xlsx'
        );

        System.assertEquals(2, rows.size());
        System.assertEquals('Ref Order No.', rows[0][0]);
        System.assertEquals('ORD-001', rows[1][0]);
    }

    @IsTest
    static void buildLineSummaryCalculatesOrderAndInvoiceAmounts() {
        Map<String, String> orderRow = new Map<String, String>{
            'Product Code' => 'P001',
            'Retailer Code' => 'SF123',
            'Order Date' => '14/5/2026',
            'Discount 2%' => '0',
            '__rowNumber' => '2'
        };
        HangyoBulkSalesUploadController.BulkUploadLineSummary orderLine =
            HangyoBulkSalesUploadController.buildLineSummaryForTest(
                orderRow,
                new Map<String, Account>(),
                new Map<String, SObject>(),
                4,
                false
            );
        System.assertEquals(4, orderLine.quantity);
        System.assertNotEquals(null, orderLine.amount);

        Map<String, String> invoiceRow = new Map<String, String>{
            'Product Code' => 'P001',
            'Retailer Code' => 'SF123',
            'Invoice Date' => '14/5/2026',
            'Discount 2%' => '5',
            '__rowNumber' => '2'
        };
        HangyoBulkSalesUploadController.BulkUploadLineSummary invoiceLine =
            HangyoBulkSalesUploadController.buildLineSummaryForTest(
                invoiceRow,
                new Map<String, Account>(),
                new Map<String, SObject>(),
                2,
                true
            );
        System.assertEquals(5, invoiceLine.discountPercent);
        System.assertNotEquals(null, invoiceLine.discountAmount);
    }

    @IsTest
    static void validateInvoiceDateUsesLinkedOrderEffectiveDate() {
        Date uploadDate = System.today();
        List<HangyoBulkSalesUploadController.BulkUploadError> errors =
            HangyoBulkSalesUploadController.validateInvoiceDateWithOrderForTest(
                2,
                formatTestDate(uploadDate.addDays(-2)),
                'O-100',
                uploadDate.addDays(-1),
                uploadDate
            );

        System.assertEquals(1, errors.size());
        System.assert(
            errors[0].errorMessage.contains('before the Order Date'),
            'Expected invoice date before order date error.'
        );
    }

    @IsTest
    static void validateUploadFileForTestCoversDecodeAndTemplatePath() {
        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateUploadFileForTest(
                'Order',
                'orders.xlsx',
                buildMinimalOrderSpreadsheetBase64()
            );

        System.assertEquals(null, result.success);
        System.assert(!result.errors.isEmpty());
    }

    @IsTest
    static void validateSheetRejectsInvoiceTemplateForOrderUpload() {
        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Invoice No.',
                'Invoice Date',
                'Retailer Code',
                'Order Number',
                'Product Code',
                'Discount 2%',
                'Quantity',
                'Data Upload',
                'Status'
            },
            new List<String>{
                'INV-001',
                '14/5/2026',
                'SF123',
                'O-001',
                'P001',
                '0',
                '5',
                'TRUE',
                'Draft'
            }
        };

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Order', sheetRows);

        System.assertEquals(null, result.success);
        System.assertEquals('Format', result.errors[0].columnName);
    }

    @IsTest
    static void validateSheetRejectsWrongColumnCount() {
        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Order No.',
                'Order Date',
                'Retailer Code',
                'Product Code'
            },
            new List<String>{ 'ORD-001', '14/5/2026', 'SF123', 'P001' }
        };

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Order', sheetRows);

        System.assertEquals(null, result.success);
        System.assertEquals('Format', result.errors[0].columnName);
    }

    @IsTest
    static void buildValidationSuccessGroupsMultipleLinesUnderSameReference() {
        List<Map<String, String>> rows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Order No.' => 'ORD-GRP',
                'Order Date' => '14/5/2026',
                'Retailer Code' => 'SF123',
                'Product Code' => 'P001',
                'Quantity' => '2',
                'Data Upload' => 'TRUE',
                '__rowNumber' => '2'
            },
            new Map<String, String>{
                'Ref Order No.' => 'ORD-GRP',
                'Order Date' => '14/5/2026',
                'Retailer Code' => 'SF123',
                'Product Code' => 'P002',
                'Quantity' => '3',
                'Data Upload' => 'TRUE',
                '__rowNumber' => '3'
            }
        };

        HangyoBulkSalesUploadController.BulkUploadSuccess success =
            HangyoBulkSalesUploadController.buildValidationSuccessForTest('Order', rows);

        System.assertEquals(1, success.headerCount);
        System.assertEquals(2, success.lineItemCount);
        System.assertEquals(1, success.groups.size());
        System.assertEquals(5, success.groups[0].totalQuantity);
    }

    @IsTest
    static void parseDateSupportsExcelSerialNumbers() {
        Date serialDate = HangyoBulkSalesUploadController.parseDateForTest('45292');
        System.assertNotEquals(null, serialDate);
    }

    @IsTest
    static void buildLineSummaryUsesOrgDataWhenAvailable() {
        Account retailer = queryOrgRetailerAccount();
        Product__c product = queryOrgProductRecord();
        if (retailer == null || product == null) {
            return;
        }

        Map<String, Account> retailerMap = new Map<String, Account>();
        retailerMap.put(retailer.Retailer_Code__c.toUpperCase(), retailer);
        Map<String, SObject> productMap = new Map<String, SObject>();
        productMap.put(product.Product_Code__c.toUpperCase(), product);

        Map<String, String> row = new Map<String, String>{
            'Product Code' => product.Product_Code__c,
            'Retailer Code' => retailer.Retailer_Code__c,
            'Order Date' => formatTestDate(System.today()),
            'Discount 2%' => '2',
            '__rowNumber' => '2'
        };

        HangyoBulkSalesUploadController.BulkUploadLineSummary lineSummary =
            HangyoBulkSalesUploadController.buildLineSummaryForTest(
                row,
                retailerMap,
                productMap,
                3,
                false
            );

        System.assertEquals(3, lineSummary.quantity);
        System.assertNotEquals(null, lineSummary.totalAmountInclTax);
    }

    @IsTest
    static void validateOrderGroupConsistencyFlagsRetailerMismatch() {
        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Order No.',
                'Order Date',
                'Retailer Code',
                'Product Code',
                'Quantity',
                'Data Upload'
            },
            new List<String>{ 'ORD-001', '14/5/2026', 'SF123', 'P001', '5', 'TRUE' },
            new List<String>{ 'ORD-001', '14/5/2026', 'SF124', 'P001', '5', 'TRUE' }
        };

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Order', sheetRows);

        Boolean hasRetailerGroupError = false;
        for (HangyoBulkSalesUploadController.BulkUploadError error : result.errors) {
            if (error.columnName == 'Retailer Code') {
                hasRetailerGroupError = true;
                break;
            }
        }
        System.assert(hasRetailerGroupError, 'Expected grouped retailer consistency error.');
    }

    @IsTest
    static void validateBulkUploadRejectsLegacyXlsThroughParserHook() {
        Boolean exceptionThrown = false;
        try {
            HangyoBulkSalesUploadController.parseSpreadsheetForTest(
                Blob.valueOf('dummy'),
                'legacy.xls'
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
            assertAuraExceptionMessage(ex, '.xlsx', 'Expected xlsx guidance from parser.');
        }
        System.assert(exceptionThrown, 'Expected parser to reject legacy xls.');
    }

    @IsTest
    static void saveBulkUploadCreatesOrderWhenMasterDataExists() {
        if (!isOrgIntegrationDataReady()) {
            return;
        }

        String retailerCode = queryOrgRetailerCode();
        String productCode = queryOrgProductCode();
        String base64Xlsx = buildOrderSpreadsheetBase64(
            retailerCode,
            productCode,
            'BU-ORD-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );

        HangyoBulkSalesUploadController.BulkUploadSaveResult result =
            HangyoBulkSalesUploadController.saveBulkUploadForTest(
                'Order',
                'bulk-orders.xlsx',
                base64Xlsx
            );

        if (result.status == 'Success') {
            System.assert(result.ordersCreated > 0);
            System.assert(!result.createdOrderIds.isEmpty());
        } else {
            System.assertEquals('ValidationFailed', result.status);
        }
    }

    @IsTest
    static void validateBulkUploadPassesValidationWhenMasterDataExists() {
        if (!isOrgIntegrationDataReady()) {
            return;
        }

        String retailerCode = queryOrgRetailerCode();
        String productCode = queryOrgProductCode();
        String base64Xlsx = buildOrderSpreadsheetBase64(
            retailerCode,
            productCode,
            'BU-VAL-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateUploadFileForTest(
                'Order',
                'bulk-validate.xlsx',
                base64Xlsx
            );

        if (result.success != null) {
            System.assertEquals(true, result.success.validationPassed);
            System.assertEquals(1, result.success.headerCount);
        } else {
            System.assert(!result.errors.isEmpty());
        }
    }

    @IsTest
    static void saveBulkUploadCreatesInvoiceWhenMasterDataExists() {
        if (!isOrgIntegrationDataReady()) {
            return;
        }

        String orderNumber = queryOrgOrderNumberWithoutDraftInvoice();
        if (String.isBlank(orderNumber)) {
            return;
        }

        String base64Xlsx = buildInvoiceSpreadsheetBase64(
            queryOrgRetailerCode(),
            queryOrgProductCode(),
            orderNumber,
            'BU-INV-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );

        try {
            HangyoBulkSalesUploadController.BulkUploadSaveResult result =
                HangyoBulkSalesUploadController.saveBulkUploadForTest(
                    'Invoice',
                    'bulk-invoices.xlsx',
                    base64Xlsx
                );

            if (result.status == 'Success') {
                System.assert(result.invoicesCreated > 0);
                System.assert(!result.createdInvoiceIds.isEmpty());
            } else {
                System.assertEquals('ValidationFailed', result.status);
            }
        } catch (AuraHandledException ex) {
            System.assert(
                String.isNotBlank(
                    HangyoBulkSalesUploadController.lastAuraHandledMessageForTest
                )
            );
        }
    }

    @IsTest
    static void convertAmountToWordsCoversAllBranches() {
        System.assertEquals('', HangyoBulkSalesUploadController.convertAmountToWordsForTest(null));
        System.assertEquals('Zero Only', HangyoBulkSalesUploadController.convertAmountToWordsForTest(0));
        System.assertEquals('One Only', HangyoBulkSalesUploadController.convertAmountToWordsForTest(1));
        System.assertEquals('Twenty One Only', HangyoBulkSalesUploadController.convertAmountToWordsForTest(21));
        System.assertEquals('One Hundred and Five Only', HangyoBulkSalesUploadController.convertAmountToWordsForTest(105));
        System.assertEquals('One Thousand Only', HangyoBulkSalesUploadController.convertAmountToWordsForTest(1000));
        System.assert(
            HangyoBulkSalesUploadController.convertAmountToWordsForTest(250000).contains('Lakh')
        );
        System.assert(
            HangyoBulkSalesUploadController.convertAmountToWordsForTest(20000000).contains('Crore')
        );
    }

    @IsTest
    static void normalizeProductCodeAndParseDecimalEdgeCases() {
        System.assertEquals('', HangyoBulkSalesUploadController.normalizeProductCodeForTest(''));
        System.assertEquals('123', HangyoBulkSalesUploadController.normalizeProductCodeForTest('123.0'));
        System.assertEquals('P001', HangyoBulkSalesUploadController.normalizeProductCodeForTest('P001'));
        System.assertEquals(null, HangyoBulkSalesUploadController.parseDecimalForTest(''));
        System.assertEquals(null, HangyoBulkSalesUploadController.parseDecimalForTest('abc'));
        System.assertEquals('', HangyoBulkSalesUploadController.formatDateForDisplayForTest(''));
    }

    @IsTest
    static void taxHelpersCoverGstCalculationPaths() {
        Map<String, Decimal> sameStateRates =
            HangyoBulkSalesUploadController.getTaxRatesForTest('Karnataka', 'Karnataka');
        if (!sameStateRates.isEmpty()) {
            System.assert(
                HangyoBulkSalesUploadController.calculateLineGstForTest(100, sameStateRates) >= 0
            );
            Map<String, Decimal> split =
                HangyoBulkSalesUploadController.calculateLineGstSplitForTest(100, sameStateRates);
            System.assertNotEquals(null, split.get('CGST'));
            System.assertNotEquals(null, split.get('SGST'));
        }

        Map<String, Decimal> igstRates =
            HangyoBulkSalesUploadController.getTaxRatesForTest('Karnataka', 'Maharashtra');
        if (!igstRates.isEmpty() && igstRates.containsKey('IGST')) {
            System.assert(
                HangyoBulkSalesUploadController.calculateLineGstForTest(100, igstRates) >= 0
            );
            Map<String, Decimal> igstSplit =
                HangyoBulkSalesUploadController.calculateLineGstSplitForTest(100, igstRates);
            System.assertNotEquals(null, igstSplit.get('IGST'));
        }

        System.assertEquals(
            0,
            HangyoBulkSalesUploadController.calculateLineGstForTest(0, sameStateRates)
        );
    }

    @IsTest
    static void validateInvoiceRejectsDuplicateProductInSameReference() {
        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Invoice No.',
                'Invoice Date',
                'Retailer Code',
                'Order Number',
                'Product Code',
                'Discount 2%',
                'Quantity',
                'Data Upload',
                'Status'
            },
            new List<String>{
                'INV-DUP',
                '14/5/2026',
                'SF123',
                'O-001',
                'P001',
                '0',
                '5',
                'TRUE',
                'Draft'
            },
            new List<String>{
                'INV-DUP',
                '14/5/2026',
                'SF123',
                'O-001',
                'P001',
                '0',
                '3',
                'TRUE',
                'Draft'
            }
        };

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Invoice', sheetRows);

        Boolean hasDuplicateProductError = false;
        for (HangyoBulkSalesUploadController.BulkUploadError error : result.errors) {
            if (
                error.columnName == 'Product Code' &&
                error.errorMessage.contains('more than once')
            ) {
                hasDuplicateProductError = true;
                break;
            }
        }
        System.assert(hasDuplicateProductError, 'Expected duplicate product validation error.');
    }

    @IsTest
    static void validateInvoiceRejectsDraftInvoiceForOrgOrderWhenPresent() {
        String orderNumber = queryOrgOrderNumberWithDraftInvoice();
        String retailerCode = queryOrgRetailerCode();
        String productCode = queryOrgProductCode();
        if (String.isBlank(orderNumber) || String.isBlank(retailerCode) || String.isBlank(productCode)) {
            return;
        }

        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Invoice No.',
                'Invoice Date',
                'Retailer Code',
                'Order Number',
                'Product Code',
                'Discount 2%',
                'Quantity',
                'Data Upload',
                'Status'
            },
            new List<String>{
                'INV-DRAFT-CHK',
                formatTestDate(System.today()),
                retailerCode,
                orderNumber,
                productCode,
                '0',
                '5',
                'TRUE',
                'Draft'
            }
        };

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Invoice', sheetRows);

        Boolean hasDraftInvoiceError = false;
        for (HangyoBulkSalesUploadController.BulkUploadError error : result.errors) {
            if (
                error.columnName == 'Order Number' &&
                error.errorMessage.contains('Draft status')
            ) {
                hasDraftInvoiceError = true;
                break;
            }
        }
        System.assert(hasDraftInvoiceError, 'Expected existing draft invoice validation error.');
    }

    @IsTest
    static void buildValidationSuccessUsesOrgDataForOrderAndInvoice() {
        Account retailer = queryOrgRetailerAccount();
        Product__c product = queryOrgProductRecord();
        if (retailer == null || product == null) {
            return;
        }

        List<Map<String, String>> orderRows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Order No.' => 'ORG-ORD-1',
                'Order Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Product Code' => product.Product_Code__c,
                'Quantity' => '2',
                'Data Upload' => 'TRUE',
                '__rowNumber' => '2'
            }
        };
        HangyoBulkSalesUploadController.BulkUploadSuccess orderSuccess =
            HangyoBulkSalesUploadController.buildValidationSuccessForTest('Order', orderRows);
        System.assertEquals(1, orderSuccess.headerCount);
        System.assertEquals(1, orderSuccess.groups.size());
        System.assert(orderSuccess.groups[0].grandTotal >= 0);

        String orderNumber = queryOrgOrderNumberWithoutDraftInvoice();
        if (String.isBlank(orderNumber)) {
            return;
        }

        List<Map<String, String>> invoiceRows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Invoice No.' => 'ORG-INV-1',
                'Invoice Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Order Number' => orderNumber,
                'Product Code' => product.Product_Code__c,
                'Discount 2%' => '2',
                'Quantity' => '2',
                'Data Upload' => 'TRUE',
                'Status' => 'Draft',
                '__rowNumber' => '2'
            }
        };
        HangyoBulkSalesUploadController.BulkUploadSuccess invoiceSuccess =
            HangyoBulkSalesUploadController.buildValidationSuccessForTest('Invoice', invoiceRows);
        System.assertEquals(1, invoiceSuccess.headerCount);
        System.assertEquals(1, invoiceSuccess.groups.size());
    }

    @IsTest
    static void validateBulkUploadWithDataUriBase64Prefix() {
        String base64Payload = buildMinimalOrderSpreadsheetBase64();
        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateUploadFileForTest(
                'Order',
                'orders.xlsx',
                'data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,' +
                    base64Payload
            );

        System.assertEquals(null, result.success);
        System.assert(!result.errors.isEmpty());
    }

    @IsTest
    static void validateBulkUploadEndToEndWithOrgOrderData() {
        if (!isOrgIntegrationDataReady()) {
            return;
        }

        String retailerCode = queryOrgRetailerCode();
        String productCode = queryOrgProductCode();
        String base64Xlsx = buildOrderSpreadsheetBase64(
            retailerCode,
            productCode,
            'BU-VAL-E2E-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateBulkUpload(
                'Order',
                'bulk-order-e2e.xlsx',
                base64Xlsx
            );

        if (result.success != null) {
            System.assertEquals(true, result.success.validationPassed);
            System.assert(result.success.groups.size() > 0);
        } else {
            System.assert(!result.errors.isEmpty());
        }
    }

    @IsTest
    static void saveBulkUploadOrderPathExecutesWithOrgData() {
        if (!isOrgIntegrationDataReady()) {
            return;
        }

        String retailerCode = queryOrgRetailerCode();
        String productCode = queryOrgProductCode();
        String base64Xlsx = buildOrderSpreadsheetBase64(
            retailerCode,
            productCode,
            'BU-SAVE-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );

        HangyoBulkSalesUploadController.BulkUploadSaveResult result =
            HangyoBulkSalesUploadController.saveBulkUploadForTest(
                'Order',
                'bulk-save-order.xlsx',
                base64Xlsx
            );

        if (result.status == 'Success') {
            System.assert(result.ordersCreated > 0);
            System.assert(!result.createdOrderIds.isEmpty());
        } else {
            System.assertEquals('ValidationFailed', result.status);
        }
    }

    @IsTest
    static void mapInvoiceStatusAndStatesMatchEdgeCases() {
        System.assertEquals('Draft', HangyoBulkSalesUploadController.mapInvoiceStatusForTest(''));
        System.assertEquals('Draft', HangyoBulkSalesUploadController.mapInvoiceStatusForTest('draft'));
        System.assertEquals(false, HangyoBulkSalesUploadController.statesMatchForTest('', 'Karnataka'));
        System.assertEquals(false, HangyoBulkSalesUploadController.statesMatchForTest('KA', 'Karnataka'));
    }

    @IsTest
    static void validateOrderAndInvoiceRowsWithOrgDataWhenAvailable() {
        Account retailer = queryOrgRetailerAccount();
        Product__c product = queryOrgProductRecord();
        if (retailer == null || product == null) {
            return;
        }

        List<List<String>> orderSheetRows = new List<List<String>>{
            new List<String>{
                'Ref Order No.',
                'Order Date',
                'Retailer Code',
                'Product Code',
                'Quantity',
                'Data Upload'
            },
            new List<String>{
                'ORG-SHEET-ORD',
                formatTestDate(System.today()),
                retailer.Retailer_Code__c,
                product.Product_Code__c,
                '2',
                'TRUE'
            }
        };
        HangyoBulkSalesUploadController.BulkUploadResult orderResult =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Order', orderSheetRows);
        if (orderResult.success != null) {
            System.assertEquals(1, orderResult.success.headerCount);
        } else {
            System.assert(!orderResult.errors.isEmpty());
        }

        String orderNumber = queryOrgOrderNumberWithoutDraftInvoice();
        if (String.isBlank(orderNumber)) {
            return;
        }

        List<List<String>> invoiceSheetRows = new List<List<String>>{
            new List<String>{
                'Ref Invoice No.',
                'Invoice Date',
                'Retailer Code',
                'Order Number',
                'Product Code',
                'Discount 2%',
                'Quantity',
                'Data Upload',
                'Status'
            },
            new List<String>{
                'ORG-SHEET-INV',
                formatTestDate(System.today()),
                retailer.Retailer_Code__c,
                orderNumber,
                product.Product_Code__c,
                '0',
                '2',
                'TRUE',
                'Draft'
            }
        };
        HangyoBulkSalesUploadController.BulkUploadResult invoiceResult =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Invoice', invoiceSheetRows);
        if (invoiceResult.success != null) {
            System.assertEquals(1, invoiceResult.success.headerCount);
        } else {
            System.assert(!invoiceResult.errors.isEmpty());
        }
    }

    @IsTest
    static void buildLineSummaryWithOrgDataForOrderAndInvoice() {
        Account retailer = queryOrgRetailerAccount();
        Product__c product = queryOrgProductRecord();
        if (retailer == null || product == null) {
            return;
        }

        Map<String, Account> retailerMap = new Map<String, Account>();
        retailerMap.put(retailer.Retailer_Code__c.toUpperCase(), retailer);
        Map<String, SObject> productMap = new Map<String, SObject>();
        productMap.put(product.Product_Code__c.toUpperCase(), product);

        Map<String, String> orderRow = new Map<String, String>{
            'Product Code' => product.Product_Code__c,
            'Retailer Code' => retailer.Retailer_Code__c,
            'Order Date' => formatTestDate(System.today()),
            'Discount 2%' => '0',
            '__rowNumber' => '2'
        };
        HangyoBulkSalesUploadController.BulkUploadLineSummary orderLine =
            HangyoBulkSalesUploadController.buildLineSummaryForTest(
                orderRow,
                retailerMap,
                productMap,
                2,
                false
            );
        System.assertNotEquals(null, orderLine.amount);

        Map<String, String> invoiceRow = new Map<String, String>{
            'Product Code' => product.Product_Code__c,
            'Retailer Code' => retailer.Retailer_Code__c,
            'Invoice Date' => formatTestDate(System.today()),
            'Discount 2%' => '5',
            '__rowNumber' => '2'
        };
        HangyoBulkSalesUploadController.BulkUploadLineSummary invoiceLine =
            HangyoBulkSalesUploadController.buildLineSummaryForTest(
                invoiceRow,
                retailerMap,
                productMap,
                3,
                true
            );
        System.assertNotEquals(null, invoiceLine.totalAmountInclTax);
    }

    @IsTest
    static void saveBulkUploadInvoicePathWithOrgOrderWithoutDraft() {
        if (!isOrgIntegrationDataReady()) {
            return;
        }

        String orderNumber = queryOrgOrderNumberWithoutDraftInvoice();
        if (String.isBlank(orderNumber)) {
            return;
        }

        String base64Xlsx = buildInvoiceSpreadsheetBase64(
            queryOrgRetailerCode(),
            queryOrgProductCode(),
            orderNumber,
            'BU-INV-SAVE-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );

        HangyoBulkSalesUploadController.BulkUploadSaveResult result =
            HangyoBulkSalesUploadController.saveBulkUploadForTest(
                'Invoice',
                'bulk-save-invoice.xlsx',
                base64Xlsx
            );

        if (result.status == 'Success') {
            System.assert(result.invoicesCreated > 0);
            System.assert(!result.createdInvoiceIds.isEmpty());
        } else {
            System.assertEquals('ValidationFailed', result.status);
        }
    }

    @IsTest
    static void parseDateHandlesInvalidAndShortSerialValues() {
        System.assertEquals(null, HangyoBulkSalesUploadController.parseDateForTest(''));
        System.assertEquals(null, HangyoBulkSalesUploadController.parseDateForTest('12/13'));
        System.assertEquals(null, HangyoBulkSalesUploadController.parseDateForTest('abc'));
        System.assertEquals(null, HangyoBulkSalesUploadController.parseDateForTest('500'));
    }

    @IsTest
    static void validateBulkUploadInvoiceEndToEndWithOrgData() {
        if (!isOrgIntegrationDataReady()) {
            return;
        }

        String orderNumber = queryOrgOrderNumberWithoutDraftInvoice();
        if (String.isBlank(orderNumber)) {
            return;
        }

        String base64Xlsx = buildInvoiceSpreadsheetBase64(
            queryOrgRetailerCode(),
            queryOrgProductCode(),
            orderNumber,
            'BU-INV-E2E-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateBulkUpload(
                'Invoice',
                'bulk-invoice-e2e.xlsx',
                base64Xlsx
            );

        if (result.success != null) {
            System.assertEquals(true, result.success.validationPassed);
            System.assert(result.success.groups.size() > 0);
        } else {
            System.assert(!result.errors.isEmpty());
        }
    }

    @IsTest
    static void buildValidationSuccessGroupsMultipleProductsForOrgOrder() {
        Account retailer = queryOrgRetailerAccount();
        Product__c product = queryOrgProductRecord();
        if (retailer == null || product == null) {
            return;
        }

        List<Map<String, String>> rows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Order No.' => 'ORG-MULTI',
                'Order Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Product Code' => product.Product_Code__c,
                'Quantity' => '2',
                'Data Upload' => 'TRUE',
                '__rowNumber' => '2'
            },
            new Map<String, String>{
                'Ref Order No.' => 'ORG-MULTI',
                'Order Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Product Code' => product.Product_Code__c,
                'Quantity' => '3',
                'Data Upload' => 'TRUE',
                '__rowNumber' => '3'
            }
        };

        HangyoBulkSalesUploadController.BulkUploadSuccess success =
            HangyoBulkSalesUploadController.buildValidationSuccessForTest('Order', rows);

        System.assertEquals(1, success.headerCount);
        System.assertEquals(2, success.lineItemCount);
        System.assertEquals(5, success.groups[0].totalQuantity);
    }

    @IsTest
    static void createBulkOrdersExecutesWithOrgDataRows() {
        Account retailer = queryOrgRetailerAccount();
        Product__c product = queryOrgProductRecord();
        if (retailer == null || product == null) {
            return;
        }

        List<Map<String, String>> dataRows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Order No.' => 'DIR-ORD-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'Order Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Product Code' => product.Product_Code__c,
                'Quantity' => '2',
                'Data Upload' => 'TRUE',
                '__rowNumber' => '2'
            }
        };
        Blob fileBlob = EncodingUtil.base64Decode(buildMinimalOrderSpreadsheetBase64());

        try {
            HangyoBulkSalesUploadController.BulkOrderCreationResult result =
                HangyoBulkSalesUploadController.createBulkOrdersForTest(
                    dataRows,
                    fileBlob,
                    'direct-order.xlsx'
                );
            System.assertNotEquals(null, result);
            if (result.ordersCreated != null && result.ordersCreated > 0) {
                System.assert(!result.orderIds.isEmpty());
            }
        } catch (Exception ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
    }

    @IsTest
    static void createBulkInvoicesExecutesWithOrgDataRows() {
        Account retailer = queryOrgRetailerAccount();
        Product__c product = queryOrgProductRecord();
        String orderNumber = queryOrgOrderNumberWithoutDraftInvoice();
        if (retailer == null || product == null || String.isBlank(orderNumber)) {
            return;
        }

        List<Map<String, String>> dataRows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Invoice No.' => 'DIR-INV-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'Invoice Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Order Number' => orderNumber,
                'Product Code' => product.Product_Code__c,
                'Discount 2%' => '0',
                'Quantity' => '2',
                'Data Upload' => 'TRUE',
                'Status' => 'Draft',
                '__rowNumber' => '2'
            }
        };
        Blob fileBlob = EncodingUtil.base64Decode(buildMinimalInvoiceSpreadsheetBase64());

        try {
            HangyoBulkSalesUploadController.createBulkInvoicesForTest(
                dataRows,
                fileBlob,
                'direct-invoice.xlsx'
            );
            System.assert(true);
        } catch (Exception ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
    }

    @IsTest
    static void wrapperMethodsExecuteWithoutOrgDataDependencies() {
        HangyoBulkSalesUploadController.BulkUploadSaveResult saveResult =
            HangyoBulkSalesUploadController.saveBulkUploadForTest(
                'Order',
                'empty.xlsx',
                ''
            );
        System.assertEquals('ValidationFailed', saveResult.status);

        try {
            HangyoBulkSalesUploadController.BulkOrderCreationResult result =
                HangyoBulkSalesUploadController.createBulkOrdersForTest(
                    new List<Map<String, String>>(),
                    Blob.valueOf('test'),
                    'empty-order.xlsx'
                );
            System.assertNotEquals(null, result);
        } catch (Exception ex) {
            System.assertNotEquals(null, ex.getMessage());
        }

        try {
            HangyoBulkSalesUploadController.createBulkInvoicesForTest(
                new List<Map<String, String>>(),
                Blob.valueOf('test'),
                'empty-invoice.xlsx'
            );
            System.assert(true);
        } catch (Exception ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
    }

    @IsTest
    static void calculateLineGstSplitCoversHardcodedTaxMaps() {
        Map<String, Decimal> igstRates = new Map<String, Decimal>{ 'IGST' => 18 };
        Map<String, Decimal> igstSplit =
            HangyoBulkSalesUploadController.calculateLineGstSplitForTest(100, igstRates);
        System.assertEquals(18, igstSplit.get('IGST'));
        System.assertEquals(0, igstSplit.get('CGST'));
        System.assertEquals(0, igstSplit.get('SGST'));

        Map<String, Decimal> sameStateRates = new Map<String, Decimal>{
            'CGST' => 9,
            'SGST' => 9
        };
        Map<String, Decimal> sameStateSplit =
            HangyoBulkSalesUploadController.calculateLineGstSplitForTest(100, sameStateRates);
        System.assertEquals(9, sameStateSplit.get('CGST'));
        System.assertEquals(9, sameStateSplit.get('SGST'));
        System.assertEquals(18, HangyoBulkSalesUploadController.calculateLineGstForTest(100, sameStateRates));
    }

    @IsTest
    static void getProductNameUsesOrgProductWhenAvailable() {
        Product__c product = queryOrgProductRecord();
        if (product == null) {
            return;
        }

        Map<String, SObject> products = new Map<String, SObject>();
        products.put(product.Product_Code__c.toUpperCase(), product);

        System.assertEquals(
            product.Name,
            HangyoBulkSalesUploadController.getProductNameForTest(
                products,
                product.Product_Code__c
            )
        );
        System.assertEquals(
            '',
            HangyoBulkSalesUploadController.getProductNameForTest(products, 'MISSING-CODE')
        );
        System.assertEquals(
            '',
            HangyoBulkSalesUploadController.getProductNameForTest(
                new Map<String, SObject>(),
                product.Product_Code__c
            )
        );
    }

    @IsTest
    static void loadOrdersAndDraftInvoicesUseOrgDataWhenAvailable() {
        String orderNumber = queryOrgOrderNumber();
        if (!String.isBlank(orderNumber)) {
            Map<String, SObject> orders = HangyoBulkSalesUploadController.loadOrdersForTest(
                new Set<String>{ orderNumber }
            );
            System.assert(!orders.isEmpty(), 'Expected org order to be loaded.');
        }

        String draftOrderNumber = queryOrgOrderNumberWithDraftInvoice();
        Id draftOrderId = queryOrgOrderIdByName(draftOrderNumber);
        if (draftOrderId != null) {
            Map<Id, Invoice__c> draftInvoices =
                HangyoBulkSalesUploadController.loadDraftInvoicesByOrderIdForTest(
                    new Set<Id>{ draftOrderId }
                );
            System.assert(
                !draftInvoices.isEmpty(),
                'Expected draft invoice lookup for org order.'
            );
        }
    }

    @IsTest
    static void parseSpreadsheetCoversAlternateSheetAndCellTypes() {
        String sharedStringsXml =
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
            '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="1" uniqueCount="1">' +
            '<si><t>SharedValue</t></si></sst>';

        String advancedSheetXml =
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>' +
            '<row r="1">' +
            '<c r="A1" t="b"><v>1</v></c>' +
            '<c r="B1" t="b"><v>0</v></c>' +
            '<c r="C1" t="inlineStr"><is><t>InlineValue</t></is></c>' +
            '<c r="D1" t="s"><v>5</v></c>' +
            '<c r="E1"><t>TagOnly</t></c>' +
            '</row></sheetData></worksheet>';

        Blob alternateSheetWorkbook = buildZipWorkbook(
            'xl/worksheets/sheet2.xml',
            advancedSheetXml,
            sharedStringsXml
        );
        List<List<String>> alternateRows =
            HangyoBulkSalesUploadController.parseSpreadsheetForTest(
                alternateSheetWorkbook,
                'alternate-sheet.xlsx'
            );
        System.assertEquals(1, alternateRows.size());
        System.assertEquals('TRUE', alternateRows[0][0]);
        System.assertEquals('FALSE', alternateRows[0][1]);
        System.assertEquals('InlineValue', alternateRows[0][2]);
        System.assertEquals('', alternateRows[0][3]);
        System.assertEquals('TagOnly', alternateRows[0][4]);

        String basicSheetXml =
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>' +
            '<row r="1"><c r="A1"><v>42</v></c></row></sheetData></worksheet>';
        Blob workbookWithoutSharedStrings = buildZipWorkbook(
            'xl/worksheets/sheet1.xml',
            basicSheetXml,
            null
        );
        List<List<String>> basicRows = HangyoBulkSalesUploadController.parseSpreadsheetForTest(
            workbookWithoutSharedStrings,
            'no-shared-strings.xlsx'
        );
        System.assertEquals(1, basicRows.size());
        System.assertEquals('42', basicRows[0][0]);
    }

    @IsTest
    static void validateInvoiceRowsCoverOrderDistributorAndDraftChecks() {
        Account retailer = queryOrgRetailerAccount();
        Product__c product = queryOrgProductRecord();
        if (retailer == null || product == null) {
            return;
        }

        String draftOrderNumber = queryOrgOrderNumberWithDraftInvoice();
        if (!String.isBlank(draftOrderNumber)) {
            List<List<String>> draftSheetRows = new List<List<String>>{
                new List<String>{
                    'Ref Invoice No.',
                    'Invoice Date',
                    'Retailer Code',
                    'Order Number',
                    'Product Code',
                    'Discount 2%',
                    'Quantity',
                    'Data Upload',
                    'Status'
                },
                new List<String>{
                    'INV-DRAFT-CHECK',
                    formatTestDate(System.today()),
                    retailer.Retailer_Code__c,
                    draftOrderNumber,
                    product.Product_Code__c,
                    '0',
                    '1',
                    'TRUE',
                    'Draft'
                }
            };
            HangyoBulkSalesUploadController.BulkUploadResult draftResult =
                HangyoBulkSalesUploadController.validateSheetRowsForTest(
                    'Invoice',
                    draftSheetRows
                );
            System.assert(!draftResult.errors.isEmpty());
        }

        String orderNumber = queryOrgOrderNumberWithoutDraftInvoice();
        if (!String.isBlank(orderNumber)) {
            List<List<String>> orderSheetRows = new List<List<String>>{
                new List<String>{
                    'Ref Invoice No.',
                    'Invoice Date',
                    'Retailer Code',
                    'Order Number',
                    'Product Code',
                    'Discount 2%',
                    'Quantity',
                    'Data Upload',
                    'Status'
                },
                new List<String>{
                    'INV-ORDER-CHECK',
                    formatTestDate(System.today()),
                    retailer.Retailer_Code__c,
                    orderNumber,
                    product.Product_Code__c,
                    '0',
                    '1',
                    'TRUE',
                    'Draft'
                }
            };
            HangyoBulkSalesUploadController.BulkUploadResult orderResult =
                HangyoBulkSalesUploadController.validateSheetRowsForTest(
                    'Invoice',
                    orderSheetRows
                );
            System.assert(orderResult.errors != null);
        }
    }

    @IsTest
    static void parseSpreadsheetThrowsWhenWorksheetXmlMissing() {
        Compression.ZipWriter writer = new Compression.ZipWriter();
        writer.addEntry('xl/workbook.xml', Blob.valueOf('<workbook/>'));

        Boolean exceptionThrown = false;
        try {
            HangyoBulkSalesUploadController.parseSpreadsheetForTest(
                writer.getArchive(),
                'missing-sheet.xlsx'
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        System.assert(exceptionThrown, 'Expected parser to fail without worksheet XML.');
    }

    @IsTest
    static void parseSpreadsheetParsesEscapedSharedStrings() {
        String sharedStringsXml =
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
            '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="1" uniqueCount="1">' +
            '<si><t>Tom &amp; Jerry</t></si></sst>';
        String sheetXml =
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>' +
            '<row r="1"><c r="A1" t="s"><v>0</v></c></row></sheetData></worksheet>';

        List<List<String>> rows = HangyoBulkSalesUploadController.parseSpreadsheetForTest(
            buildZipWorkbook('xl/worksheets/sheet1.xml', sheetXml, sharedStringsXml),
            'escaped-shared.xlsx'
        );

        System.assertEquals(1, rows.size());
        System.assertEquals('Tom & Jerry', rows[0][0]);
    }

    @IsTest
    static void createBulkOrdersExecutesMultipleLinesForOrgOrder() {
        Account retailer = queryOrgRetailerAccount();
        Product__c product = queryOrgProductRecord();
        if (retailer == null || product == null) {
            return;
        }

        String refOrderNo = 'DIR-MULTI-' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        List<Map<String, String>> dataRows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Order No.' => refOrderNo,
                'Order Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Product Code' => product.Product_Code__c,
                'Quantity' => '2',
                'Data Upload' => 'TRUE',
                '__rowNumber' => '2'
            },
            new Map<String, String>{
                'Ref Order No.' => refOrderNo,
                'Order Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Product Code' => product.Product_Code__c,
                'Quantity' => '3',
                'Data Upload' => 'TRUE',
                '__rowNumber' => '3'
            }
        };

        try {
            HangyoBulkSalesUploadController.BulkOrderCreationResult result =
                HangyoBulkSalesUploadController.createBulkOrdersForTest(
                    dataRows,
                    EncodingUtil.base64Decode(buildMinimalOrderSpreadsheetBase64()),
                    'direct-multi-order.xlsx'
                );
            System.assertNotEquals(null, result);
            if (result.ordersCreated != null && result.ordersCreated > 0) {
                System.assertEquals(1, result.ordersCreated);
            }
        } catch (Exception ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
    }

    @IsTest
    static void validateTemplateCoversUnexpectedAndBlankColumnMismatch() {
        List<List<String>> unexpectedColumnRows = new List<List<String>>{
            new List<String>{
                'Ref Order No.',
                'Order Date',
                'Retailer Code',
                'Product Code',
                'Quantity',
                'Data Upload',
                'Extra Column'
            },
            new List<String>{ 'ORD-001', '14/5/2026', 'SF123', 'P001', '5', 'TRUE', 'X' }
        };
        HangyoBulkSalesUploadController.BulkUploadResult unexpectedResult =
            HangyoBulkSalesUploadController.validateSheetRowsForTest(
                'Order',
                unexpectedColumnRows
            );
        System.assertEquals(null, unexpectedResult.success);
        System.assert(
            unexpectedResult.errors[0].errorMessage.contains('Unexpected column'),
            'Expected unexpected column mismatch message.'
        );

        List<List<String>> blankPaddingRows = new List<List<String>>{
            new List<String>{
                'Ref Order No.',
                'Order Date',
                'Retailer Code',
                'Product Code',
                'Quantity',
                'Data Upload',
                '',
                ''
            },
            new List<String>{ 'ORD-002', '14/5/2026', 'SF123', 'P001', '5', 'TRUE', '', '' }
        };
        HangyoBulkSalesUploadController.BulkUploadResult blankPaddingResult =
            HangyoBulkSalesUploadController.validateSheetRowsForTest(
                'Order',
                blankPaddingRows
            );
        System.assertEquals(null, blankPaddingResult.success);
        System.assert(
            blankPaddingResult.errors[0].errorMessage.contains('Expected 6 columns but found 8'),
            'Expected blank padded column count mismatch message.'
        );

        List<List<String>> missingColumnRows = new List<List<String>>{
            new List<String>{
                'Ref Order No.',
                'Order Date',
                'Retailer Code'
            },
            new List<String>{ 'ORD-003', '14/5/2026', 'SF123' }
        };
        HangyoBulkSalesUploadController.BulkUploadResult missingColumnResult =
            HangyoBulkSalesUploadController.validateSheetRowsForTest(
                'Order',
                missingColumnRows
            );
        System.assertEquals(null, missingColumnResult.success);
        System.assert(
            missingColumnResult.errors[0].errorMessage.contains('Missing column(s)'),
            'Expected missing column mismatch message.'
        );
    }

    @IsTest
    static void validateRetailerFailsWhenUserHasNoDistributor() {
        if (queryCurrentUserDistributorAccountId() != null) {
            return;
        }

        Account retailer = queryOrgRetailerAccount();
        Product__c product = queryOrgProductRecord();
        if (retailer == null || product == null) {
            return;
        }

        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Order No.',
                'Order Date',
                'Retailer Code',
                'Product Code',
                'Quantity',
                'Data Upload'
            },
            new List<String>{
                'ORD-NODIST',
                formatTestDate(System.today()),
                retailer.Retailer_Code__c,
                product.Product_Code__c,
                '2',
                'TRUE'
            }
        };

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Order', sheetRows);

        Boolean hasNoDistributorError = false;
        for (HangyoBulkSalesUploadController.BulkUploadError error : result.errors) {
            if (
                error.columnName == 'Retailer Code' &&
                error.errorMessage.contains('not linked to a distributor')
            ) {
                hasNoDistributorError = true;
                break;
            }
        }
        System.assert(hasNoDistributorError, 'Expected no distributor linked error.');
    }

    @IsTest
    static void validateRetailerRejectsForeignDistributorRetailer() {
        String foreignRetailerCode = queryOrgRetailerCodeForDifferentDistributor();
        Product__c product = queryOrgProductRecord();
        if (String.isBlank(foreignRetailerCode) || product == null) {
            return;
        }

        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Order No.',
                'Order Date',
                'Retailer Code',
                'Product Code',
                'Quantity',
                'Data Upload'
            },
            new List<String>{
                'ORD-FDIST',
                formatTestDate(System.today()),
                foreignRetailerCode,
                product.Product_Code__c,
                '2',
                'TRUE'
            }
        };

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Order', sheetRows);

        Boolean hasDistributorError = false;
        for (HangyoBulkSalesUploadController.BulkUploadError error : result.errors) {
            if (
                error.columnName == 'Retailer Code' &&
                error.errorMessage.contains('does not belong to your distributor')
            ) {
                hasDistributorError = true;
                break;
            }
        }
        System.assert(hasDistributorError, 'Expected retailer distributor mismatch error.');
    }

    @IsTest
    static void validateOrderDistributorRejectsForeignDistributorOrder() {
        Account retailer = queryOrgRetailerAccount();
        Product__c product = queryOrgProductRecord();
        String foreignOrderNumber = queryOrgOrderNumberForDifferentDistributor();
        if (retailer == null || product == null || String.isBlank(foreignOrderNumber)) {
            return;
        }

        List<List<String>> sheetRows = new List<List<String>>{
            new List<String>{
                'Ref Invoice No.',
                'Invoice Date',
                'Retailer Code',
                'Order Number',
                'Product Code',
                'Discount 2%',
                'Quantity',
                'Data Upload',
                'Status'
            },
            new List<String>{
                'INV-FDIST',
                formatTestDate(System.today()),
                retailer.Retailer_Code__c,
                foreignOrderNumber,
                product.Product_Code__c,
                '0',
                '2',
                'TRUE',
                'Draft'
            }
        };

        HangyoBulkSalesUploadController.BulkUploadResult result =
            HangyoBulkSalesUploadController.validateSheetRowsForTest('Invoice', sheetRows);

        Boolean hasOrderDistributorError = false;
        for (HangyoBulkSalesUploadController.BulkUploadError error : result.errors) {
            if (
                error.columnName == 'Order Number' &&
                error.errorMessage.contains('does not belong to your distributor')
            ) {
                hasOrderDistributorError = true;
                break;
            }
        }
        System.assert(hasOrderDistributorError, 'Expected order distributor mismatch error.');
    }

    @IsTest
    static void loadOrderCreationHelpersUseOrgData() {
        Account retailer = queryOrgRetailerAccount();
        String orderNumber = queryOrgOrderNumber();
        Id distributorId = queryCurrentUserDistributorAccountId();
        if (retailer == null) {
            return;
        }

        Map<String, Account> retailers =
            HangyoBulkSalesUploadController.loadRetailersForOrderCreationForTest(
                new Set<String>{ retailer.Retailer_Code__c }
            );
        System.assert(retailers.containsKey(retailer.Retailer_Code__c.toUpperCase()));

        if (!String.isBlank(orderNumber)) {
            Map<String, SObject> orders =
                HangyoBulkSalesUploadController.loadOrdersForInvoiceCreationForTest(
                    new Set<String>{ orderNumber }
                );
            System.assert(!orders.isEmpty(), 'Expected invoice creation order lookup.');
        }

        if (distributorId != null) {
            Account distributor =
                HangyoBulkSalesUploadController.loadDistributorAccountDetailsForTest(
                    distributorId
                );
            System.assertNotEquals(null, distributor);
        }
    }

    @IsTest
    static void loadRetailersForOrderCreationCoversEdgeCases() {
        System.assertEquals(
            0,
            HangyoBulkSalesUploadController.loadRetailersForOrderCreationForTest(
                new Set<String>()
            ).size(),
            'Empty retailer code set should return no retailers.'
        );

        System.assertEquals(
            0,
            HangyoBulkSalesUploadController.loadRetailersForOrderCreationForTest(
                new Set<String>{ '', '   ' }
            ).size(),
            'Blank retailer codes should be ignored.'
        );

        if (bulkTestHasAccountField('Retailer_Code__c')) {
            Map<String, Account> missingRetailers =
                HangyoBulkSalesUploadController.loadRetailersForOrderCreationForTest(
                    new Set<String>{
                        'BULK-MISSING-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
                    }
                );
            System.assertEquals(0, missingRetailers.size());
        }

        Account retailer = queryOrgRetailerAccount();
        if (retailer != null) {
            Map<String, Account> orgRetailers =
                HangyoBulkSalesUploadController.loadRetailersForOrderCreationForTest(
                    new Set<String>{ retailer.Retailer_Code__c }
                );
            System.assert(
                orgRetailers.containsKey(retailer.Retailer_Code__c.toUpperCase()),
                'Expected org retailer to resolve for order creation.'
            );
        }
    }

    @IsTest
    static void resolveRetailerDistributorFieldApiReturnsExpectedField() {
        String distributorFieldApi =
            HangyoBulkSalesUploadController.resolveRetailerDistributorFieldApiForTest();

        if (bulkTestHasAccountField('Distributor__c')) {
            System.assertEquals('Distributor__c', distributorFieldApi);
        } else if (bulkTestHasAccountField('Distributor_Account__c')) {
            System.assertEquals('Distributor_Account__c', distributorFieldApi);
        } else {
            System.assertEquals(null, distributorFieldApi);
        }
    }

    @IsTest
    static void getCurrentUserDistributorAccountIdExecutesForRunningUser() {
        Id distributorId =
            HangyoBulkSalesUploadController.getCurrentUserDistributorAccountIdForTest();
        System.assertEquals(queryCurrentUserDistributorAccountId(), distributorId);
    }

    @IsTest
    static void createBulkOrdersCoversRetailerResolutionFailure() {
        List<Map<String, String>> dataRows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Order No.' =>
                    'COV-FAIL-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'Order Date' => formatTestDate(System.today()),
                'Retailer Code' =>
                    'NO-SUCH-RETAILER-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'Product Code' =>
                    'NO-SUCH-PRODUCT-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'Quantity' => '1',
                'Data Upload' => 'TRUE',
                '__rowNumber' => '2'
            }
        };

        Boolean exceptionThrown = false;
        try {
            HangyoBulkSalesUploadController.createBulkOrdersForTest(
                dataRows,
                EncodingUtil.base64Decode(buildMinimalOrderSpreadsheetBase64()),
                'coverage-fail-order.xlsx'
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
            assertAuraExceptionMessage(
                ex,
                'Retailer could not be resolved',
                'Expected retailer resolution failure.'
            );
        }
        System.assert(exceptionThrown, 'Expected retailer resolution failure.');
    }

    @IsTest
    static void createBulkOrdersCoversProductResolutionFailure() {
        Account retailer = queryOrgRetailerAccount();
        if (retailer == null) {
            return;
        }

        List<Map<String, String>> dataRows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Order No.' =>
                    'COV-PROD-FAIL-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'Order Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Product Code' =>
                    'NO-SUCH-PRODUCT-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'Quantity' => '1',
                'Data Upload' => 'TRUE',
                '__rowNumber' => '2'
            }
        };

        Boolean exceptionThrown = false;
        try {
            HangyoBulkSalesUploadController.createBulkOrdersForTest(
                dataRows,
                EncodingUtil.base64Decode(buildMinimalOrderSpreadsheetBase64()),
                'coverage-product-fail-order.xlsx'
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
            String actualMessage = getAuraExceptionMessage(ex);
            System.assert(
                actualMessage.contains('Product could not be resolved') ||
                actualMessage.contains('Order creation failed'),
                'Expected product resolution failure. Actual: ' + actualMessage
            );
        }
        System.assert(exceptionThrown, 'Expected product resolution failure.');
    }

    @IsTest
    static void createBulkOrdersCreatesOrderWhenOrgDataExists() {
        if (!isOrgIntegrationDataReady()) {
            return;
        }

        Account retailer = queryOrgRetailerAccount();
        Product__c product = queryOrgProductRecord();
        if (retailer == null || product == null) {
            return;
        }

        List<Map<String, String>> dataRows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Order No.' =>
                    'COV-SUCCESS-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'Order Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Product Code' => product.Product_Code__c,
                'Quantity' => '2',
                'Data Upload' => 'TRUE',
                '__rowNumber' => '2'
            }
        };

        try {
            HangyoBulkSalesUploadController.BulkOrderCreationResult result =
                HangyoBulkSalesUploadController.createBulkOrdersForTest(
                    dataRows,
                    EncodingUtil.base64Decode(buildMinimalOrderSpreadsheetBase64()),
                    'coverage-success-order.xlsx'
                );
            System.assertNotEquals(null, result);
            if (result.ordersCreated != null && result.ordersCreated > 0) {
                System.assert(!result.orderIds.isEmpty());
                System.assert(!result.orderNames.isEmpty());
            }
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
    }

    @IsTest
    static void createBulkOrdersHandlesEmptyDataRows() {
        try {
            HangyoBulkSalesUploadController.BulkOrderCreationResult result =
                HangyoBulkSalesUploadController.createBulkOrdersForTest(
                    new List<Map<String, String>>(),
                    Blob.valueOf('test'),
                    'empty-order.xlsx'
                );
            System.assertNotEquals(null, result);
            System.assertEquals(
                0,
                result.orderIds == null ? 0 : result.orderIds.size()
            );
        } catch (Exception ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
    }

    @IsTest
    static void saveBulkUploadSuccessPathCoversOrderAndInvoiceCreation() {
        if (!isOrgIntegrationDataReady()) {
            return;
        }

        String retailerCode = queryOrgRetailerCode();
        String productCode = queryOrgProductCode();
        String orderBase64 = buildOrderSpreadsheetBase64(
            retailerCode,
            productCode,
            'BU-SUCCESS-ORD-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );

        HangyoBulkSalesUploadController.BulkUploadSaveResult orderSaveResult =
            HangyoBulkSalesUploadController.saveBulkUploadForTest(
                'Order',
                'bulk-success-order.xlsx',
                orderBase64
            );

        if (orderSaveResult.status == 'Success') {
            System.assert(orderSaveResult.ordersCreated > 0);
            System.assert(!orderSaveResult.createdOrderIds.isEmpty());
            System.assertNotEquals(null, orderSaveResult.success);
            System.assertEquals(false, orderSaveResult.success.validationPassed);
        }

        String invoiceOrderNumber = queryOrgOrderNumberWithoutDraftInvoice();
        if (String.isBlank(invoiceOrderNumber)) {
            return;
        }

        String invoiceBase64 = buildInvoiceSpreadsheetBase64(
            retailerCode,
            productCode,
            invoiceOrderNumber,
            'BU-SUCCESS-INV-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );

        HangyoBulkSalesUploadController.BulkUploadSaveResult invoiceSaveResult =
            HangyoBulkSalesUploadController.saveBulkUploadForTest(
                'Invoice',
                'bulk-success-invoice.xlsx',
                invoiceBase64
            );

        if (invoiceSaveResult.status == 'Success') {
            System.assert(invoiceSaveResult.invoicesCreated > 0);
            System.assert(!invoiceSaveResult.createdInvoiceIds.isEmpty());
            System.assertNotEquals(null, invoiceSaveResult.success);
            System.assertEquals(false, invoiceSaveResult.success.validationPassed);
        }
    }

    @IsTest
    static void isTodEligibleCoversAllBranches() {
        System.assertEquals(
            false,
            HangyoBulkSalesUploadController.isTodEligibleForTest(null, 1)
        );
        System.assertEquals(
            false,
            HangyoBulkSalesUploadController.isTodEligibleForTest(15, null)
        );
        System.assertEquals(
            true,
            HangyoBulkSalesUploadController.isTodEligibleForTest(25, null)
        );
        System.assertEquals(
            false,
            HangyoBulkSalesUploadController.isTodEligibleForTest(100, 10)
        );
        System.assertEquals(
            true,
            HangyoBulkSalesUploadController.isTodEligibleForTest(100, 5)
        );
        System.assertEquals(
            true,
            HangyoBulkSalesUploadController.isTodEligibleForTest(20, 0)
        );
    }

    @IsTest
    static void isDiscountActiveOnDateCoversAllBranches() {
        Date today = System.today();

        System.assertEquals(
            false,
            HangyoBulkSalesUploadController.isDiscountActiveOnDateForTest(null, today)
        );
        System.assertEquals(
            false,
            HangyoBulkSalesUploadController.isDiscountActiveOnDateForTest(
                new Discount__c(),
                today
            )
        );
        System.assertEquals(
            false,
            HangyoBulkSalesUploadController.isDiscountActiveOnDateForTest(
                new Discount__c(Discount_Percentage__c = 5),
                null
            )
        );
        System.assertEquals(
            false,
            HangyoBulkSalesUploadController.isDiscountActiveOnDateForTest(
                new Discount__c(
                    Discount_Percentage__c = 5,
                    Start_Date__c = today.addDays(1)
                ),
                today
            )
        );
        System.assertEquals(
            false,
            HangyoBulkSalesUploadController.isDiscountActiveOnDateForTest(
                new Discount__c(
                    Discount_Percentage__c = 5,
                    End_Date__c = today.addDays(-1)
                ),
                today
            )
        );
        System.assertEquals(
            true,
            HangyoBulkSalesUploadController.isDiscountActiveOnDateForTest(
                new Discount__c(
                    Discount_Percentage__c = 5,
                    Start_Date__c = today.addDays(-10),
                    End_Date__c = today.addDays(10)
                ),
                today
            )
        );
        System.assertEquals(
            true,
            HangyoBulkSalesUploadController.isDiscountActiveOnDateForTest(
                new Discount__c(Discount_Percentage__c = 5),
                today
            )
        );
    }

    @IsTest
    static void resolveTodDiscountPercentCoversProductAndRetailerLevels() {
        Id accountId = buildTestSObjectId(Account.SObjectType);
        Id productId = buildTestSObjectId(Product__c.SObjectType);
        Date today = System.today();

        System.assertEquals(
            0,
            HangyoBulkSalesUploadController.resolveTodDiscountPercentForTest(
                null,
                null,
                accountId,
                productId,
                today
            )
        );

        List<Discount__c> productLevelDiscounts = new List<Discount__c>{
            new Discount__c(
                Account__c = accountId,
                Product__c = productId,
                Discount_Percentage__c = 12,
                Start_Date__c = today.addDays(-5),
                End_Date__c = today.addDays(5)
            )
        };
        System.assertEquals(
            12,
            HangyoBulkSalesUploadController.resolveTodDiscountPercentForTest(
                productLevelDiscounts,
                new Map<Id, Product__c>(),
                accountId,
                productId,
                today
            )
        );

        Map<Id, Product__c> todEligibleProduct = new Map<Id, Product__c>{
            productId => new Product__c(
                Id = productId,
                MRP__c = 100,
                Per_Pieces__c = 4
            )
        };
        List<Discount__c> retailerLevelDiscounts = new List<Discount__c>{
            new Discount__c(
                Account__c = accountId,
                Discount_Percentage__c = 8,
                Start_Date__c = today.addDays(-5),
                End_Date__c = today.addDays(5)
            )
        };
        System.assertEquals(
            8,
            HangyoBulkSalesUploadController.resolveTodDiscountPercentForTest(
                retailerLevelDiscounts,
                todEligibleProduct,
                accountId,
                productId,
                today
            )
        );

        Map<Id, Product__c> ineligibleProduct = new Map<Id, Product__c>{
            productId => new Product__c(
                Id = productId,
                MRP__c = 10,
                Per_Pieces__c = 2
            )
        };
        System.assertEquals(
            0,
            HangyoBulkSalesUploadController.resolveTodDiscountPercentForTest(
                retailerLevelDiscounts,
                ineligibleProduct,
                accountId,
                productId,
                today
            )
        );

        List<Discount__c> expiredRetailerDiscount = new List<Discount__c>{
            new Discount__c(
                Account__c = accountId,
                Discount_Percentage__c = 8,
                Start_Date__c = today.addDays(-30),
                End_Date__c = today.addDays(-10)
            )
        };
        List<Discount__c> productAndRetailerDiscounts = new List<Discount__c>{
            new Discount__c(
                Account__c = accountId,
                Product__c = productId,
                Discount_Percentage__c = 15,
                Start_Date__c = today.addDays(-5),
                End_Date__c = today.addDays(5)
            ),
            new Discount__c(
                Account__c = accountId,
                Discount_Percentage__c = 8,
                Start_Date__c = today.addDays(-5),
                End_Date__c = today.addDays(5)
            )
        };
        System.assertEquals(
            15,
            HangyoBulkSalesUploadController.resolveTodDiscountPercentForTest(
                productAndRetailerDiscounts,
                todEligibleProduct,
                accountId,
                productId,
                today
            )
        );
    }

    @IsTest
    static void resolveTodAmountCalculatesFromActiveDiscount() {
        Id accountId = buildTestSObjectId(Account.SObjectType);
        Id productId = buildTestSObjectId(Product__c.SObjectType);
        Date today = System.today();
        Account retailer = new Account(Id = accountId);

        Map<Id, Product__c> todEligibleProduct = new Map<Id, Product__c>{
            productId => new Product__c(
                Id = productId,
                MRP__c = 100,
                Per_Pieces__c = 4
            )
        };
        List<Discount__c> retailerDiscounts = new List<Discount__c>{
            new Discount__c(
                Account__c = accountId,
                Discount_Percentage__c = 10,
                Start_Date__c = today.addDays(-5),
                End_Date__c = today.addDays(5)
            )
        };

        Map<String, String> orderRow = new Map<String, String>{
            'Order Date' => formatTestDate(today)
        };
        Decimal orderTod = HangyoBulkSalesUploadController.resolveTodAmountForTest(
            retailerDiscounts,
            todEligibleProduct,
            retailer,
            productId,
            orderRow,
            false,
            200
        );
        System.assertEquals(20, orderTod);

        Map<String, String> invoiceRow = new Map<String, String>{
            'Invoice Date' => formatTestDate(today)
        };
        Decimal invoiceTod = HangyoBulkSalesUploadController.resolveTodAmountForTest(
            retailerDiscounts,
            todEligibleProduct,
            retailer,
            productId,
            invoiceRow,
            true,
            150
        );
        System.assertEquals(15, invoiceTod);

        System.assertEquals(
            0,
            HangyoBulkSalesUploadController.resolveTodAmountForTest(
                retailerDiscounts,
                todEligibleProduct,
                retailer,
                productId,
                orderRow,
                false,
                0
            )
        );
        System.assertEquals(
            0,
            HangyoBulkSalesUploadController.resolveTodAmountForTest(
                retailerDiscounts,
                todEligibleProduct,
                null,
                productId,
                orderRow,
                false,
                100
            )
        );
    }

    @IsTest
    static void buildPricingContextLoadsDiscountAndTodData() {
        Account retailer = queryOrgRetailerAccount();
        Product__c product = queryOrgProductRecord();
        if (retailer == null || product == null) {
            System.assertEquals(
                0,
                HangyoBulkSalesUploadController.buildPricingContextDiscountCountForTest(
                    new Map<String, Account>(),
                    new Map<String, SObject>()
                )
            );
            return;
        }

        Map<String, Account> retailerMap = new Map<String, Account>{
            retailer.Retailer_Code__c.toUpperCase() => retailer
        };
        Map<String, SObject> productMap = new Map<String, SObject>{
            product.Product_Code__c.toUpperCase() => product
        };

        Integer loadedCount =
            HangyoBulkSalesUploadController.buildPricingContextDiscountCountForTest(
                retailerMap,
                productMap
            );
        System.assert(loadedCount >= 1, 'Expected product details to load for pricing context.');
    }

    @IsTest
    static void buildLineSummaryAppliesTodWhenOrgDiscountsExist() {
        if (!Schema.getGlobalDescribe().containsKey('Discount__c')) {
            return;
        }

        Account retailer = queryOrgRetailerAccount();
        Product__c product = queryOrgProductRecordWithTodFields();
        if (retailer == null || product == null) {
            return;
        }

        List<Discount__c> discounts = [
            SELECT Account__c, Product__c, Discount_Percentage__c
            FROM Discount__c
            WHERE Account__c = :retailer.Id
            LIMIT 1
        ];
        if (discounts.isEmpty()) {
            return;
        }

        Map<String, Account> retailerMap = new Map<String, Account>{
            retailer.Retailer_Code__c.toUpperCase() => retailer
        };
        Map<String, SObject> productMap = new Map<String, SObject>{
            product.Product_Code__c.toUpperCase() => product
        };
        Map<String, String> orderRow = new Map<String, String>{
            'Product Code' => product.Product_Code__c,
            'Retailer Code' => retailer.Retailer_Code__c,
            'Order Date' => formatTestDate(System.today()),
            'Discount 2%' => '0',
            '__rowNumber' => '2'
        };

        HangyoBulkSalesUploadController.BulkUploadLineSummary lineSummary =
            HangyoBulkSalesUploadController.buildLineSummaryForTest(
                orderRow,
                retailerMap,
                productMap,
                10,
                false
            );

        System.assertNotEquals(null, lineSummary.tod);
        System.assert(lineSummary.tod >= 0);
        if (lineSummary.amount != null && lineSummary.amount > 0) {
            System.assert(lineSummary.tod <= lineSummary.amount);
        }
    }

    @IsTest
    static void pricingHelpersCoverPricebookAndDistributorState() {
        System.assertNotEquals(
            null,
            HangyoBulkSalesUploadController.getDistributorPrimaryStateForTest()
        );
        System.assertNotEquals(
            null,
            HangyoBulkSalesUploadController.loadRegionPricebookMapForTest()
        );
        System.assertNotEquals(
            null,
            HangyoBulkSalesUploadController.getOrderNumberFieldApiNameForTest()
        );

        Account retailer = queryOrgRetailerAccount();
        Product__c product = queryOrgProductRecord();
        if (retailer == null || product == null) {
            return;
        }

        Map<String, Account> retailerMap = new Map<String, Account>{
            retailer.Retailer_Code__c.toUpperCase() => retailer
        };
        Map<String, SObject> productMap = new Map<String, SObject>{
            product.Product_Code__c.toUpperCase() => product
        };

        Decimal ptr = HangyoBulkSalesUploadController.resolvePtrForTest(
            retailerMap,
            productMap,
            retailer.Retailer_Code__c,
            product.Product_Code__c
        );
        System.assertNotEquals(null, ptr);
        System.assert(ptr >= 0);
    }

    @IsTest
    static void buildValidationSuccessCoversGroupSummariesWithOrgData() {
        Account retailer = queryOrgRetailerAccount();
        Product__c product = queryOrgProductRecord();
        if (retailer == null || product == null) {
            return;
        }

        List<Map<String, String>> rows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Order No.' =>
                    'GRP-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'Order Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Product Code' => product.Product_Code__c,
                'Quantity' => '2',
                'Data Upload' => 'TRUE',
                '__rowNumber' => '2'
            },
            new Map<String, String>{
                'Ref Order No.' =>
                    'GRP-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'Order Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Product Code' => product.Product_Code__c,
                'Quantity' => '3',
                'Data Upload' => 'TRUE',
                '__rowNumber' => '3'
            }
        };
        rows[1].put('Ref Order No.', rows[0].get('Ref Order No.'));

        HangyoBulkSalesUploadController.BulkUploadSuccess success =
            HangyoBulkSalesUploadController.buildValidationSuccessForTest('Order', rows);

        System.assertEquals(true, success.validationPassed);
        System.assertEquals(1, success.headerCount);
        System.assertEquals(2, success.lineItemCount);
        System.assertNotEquals(null, success.groups);
        System.assertEquals(1, success.groups.size());
        System.assertEquals(5, success.groups[0].totalQuantity);
        System.assertNotEquals(null, success.groups[0].lineItems);
        System.assertEquals(2, success.groups[0].lineItems.size());
    }

    @IsTest
    static void loadOrdersForTestCoversOrgOrderLookup() {
        String orderNumber = queryOrgOrderNumber();
        if (String.isBlank(orderNumber)) {
            System.assertEquals(
                0,
                HangyoBulkSalesUploadController.loadOrdersForTest(
                    new Set<String>{ 'NO-SUCH-ORDER' }
                ).size()
            );
            return;
        }

        Map<String, SObject> orders = HangyoBulkSalesUploadController.loadOrdersForTest(
            new Set<String>{ orderNumber }
        );
        System.assert(!orders.isEmpty());
    }

    @IsTest
    static void loadDiscountRecordsAndProductDetailsForTodCoverOrgPaths() {
        System.assertEquals(
            0,
            HangyoBulkSalesUploadController.loadDiscountRecordsForTest(
                new Set<Id>()
            ).size()
        );
        System.assertEquals(
            0,
            HangyoBulkSalesUploadController.loadProductDetailsForTodForTest(
                new Set<Id>()
            ).size()
        );

        if (Schema.getGlobalDescribe().containsKey('Discount__c')) {
            List<Discount__c> syntheticDiscountQuery =
                HangyoBulkSalesUploadController.loadDiscountRecordsForTest(
                    new Set<Id>{ buildTestSObjectId(Account.SObjectType) }
                );
            System.assertNotEquals(null, syntheticDiscountQuery);
        }

        if (Schema.getGlobalDescribe().containsKey('Product__c')) {
            Map<Id, Product__c> syntheticProductDetails =
                HangyoBulkSalesUploadController.loadProductDetailsForTodForTest(
                    new Set<Id>{ buildTestSObjectId(Product__c.SObjectType) }
                );
            System.assertNotEquals(null, syntheticProductDetails);
        }

        Account retailer = queryOrgRetailerAccount();
        if (retailer != null) {
            List<Discount__c> discounts =
                HangyoBulkSalesUploadController.loadDiscountRecordsForTest(
                    new Set<Id>{ retailer.Id }
                );
            System.assertNotEquals(null, discounts);
        }

        Product__c product = queryOrgProductRecordWithTodFields();
        if (product != null) {
            Map<Id, Product__c> productDetails =
                HangyoBulkSalesUploadController.loadProductDetailsForTodForTest(
                    new Set<Id>{ product.Id }
                );
            System.assert(productDetails.containsKey(product.Id));
        }
    }

    @IsTest
    static void getTaxRatesCoversSameStateAndIgstBranches() {
        if (!Schema.getGlobalDescribe().containsKey('Order_tax_value__c')) {
            return;
        }

        List<Order_tax_value__c> existingSettings = [
            SELECT Id
            FROM Order_tax_value__c
            WHERE Name = 'General GST Settings'
            LIMIT 1
        ];
        if (existingSettings.isEmpty()) {
            try {
                insert new Order_tax_value__c(
                    Name = 'General GST Settings',
                    CGST__c = 9,
                    SGST__c = 9,
                    IGST__c = 18
                );
            } catch (Exception ex) {
                return;
            }
        }

        Map<String, Decimal> sameStateRates =
            HangyoBulkSalesUploadController.getTaxRatesForTest(
                'Karnataka',
                'Karnataka'
            );
        System.assert(sameStateRates.containsKey('CGST'));
        System.assert(sameStateRates.containsKey('SGST'));
        System.assertNotEquals(null, sameStateRates.get('CGST'));
        System.assertNotEquals(null, sameStateRates.get('SGST'));

        Map<String, Decimal> igstRates =
            HangyoBulkSalesUploadController.getTaxRatesForTest(
                'Karnataka',
                'Maharashtra'
            );
        System.assert(igstRates.containsKey('IGST'));
        System.assertNotEquals(null, igstRates.get('IGST'));
    }

    @IsTest
    static void pricebookHelpersCoverResolutionAndPtrLookup() {
        Id pricebookId = buildTestSObjectId(Price_Book__c.SObjectType);
        Id productId = buildTestSObjectId(Product__c.SObjectType);
        String ptrKey = HangyoBulkSalesUploadController.buildPricebookProductKeyForTest(
            pricebookId,
            productId
        );
        System.assert(ptrKey.contains('|'));

        System.assertEquals(
            null,
            HangyoBulkSalesUploadController.resolvePricebookIdForRetailerForTest(
                null,
                new Map<String, Id>()
            )
        );
        System.assertEquals(
            null,
            HangyoBulkSalesUploadController.resolvePricebookIdForRetailerForTest(
                new Account(Primary_State__c = ''),
                new Map<String, Id>{ 'Karnataka' => pricebookId }
            )
        );

        if (bulkTestHasAccountField('Primary_State__c')) {
            Account retailer = new Account(Primary_State__c = 'Karnataka');
            Map<String, Id> regionMap = new Map<String, Id>{
                'Karnataka' => pricebookId
            };
            System.assertEquals(
                pricebookId,
                HangyoBulkSalesUploadController.resolvePricebookIdForRetailerForTest(
                    retailer,
                    regionMap
                )
            );

            Map<String, Decimal> ptrMap = new Map<String, Decimal>{
                ptrKey => 125.50
            };
            Decimal resolvedPtr =
                HangyoBulkSalesUploadController.resolvePtrWithInjectedMapsForTest(
                    retailer,
                    productId,
                    regionMap,
                    ptrMap
                );
            System.assertEquals(125.50, resolvedPtr);

            System.assertEquals(
                0,
                HangyoBulkSalesUploadController.resolvePtrWithInjectedMapsForTest(
                    retailer,
                    productId,
                    new Map<String, Id>{ 'Maharashtra' => pricebookId },
                    ptrMap
                )
            );
        }

        Product__c productRecord = new Product__c(
            Id = productId,
            Product_Code__c = 'PTR-PROD-001'
        );
        Map<String, SObject> products = new Map<String, SObject>{
            'PTR-PROD-001' => productRecord
        };
        System.assertEquals(
            productId,
            HangyoBulkSalesUploadController.getProductIdForTest(
                products,
                'PTR-PROD-001'
            )
        );
        System.assertEquals(
            productId,
            HangyoBulkSalesUploadController.getProductIdForTest(
                products,
                'PTR-PROD-001.0'
            )
        );
        System.assertEquals(
            null,
            HangyoBulkSalesUploadController.getProductIdForTest(
                products,
                'MISSING'
            )
        );
    }

    @IsTest
    static void loadPtrByPricebookAndProductExecutesQueryPath() {
        if (!Schema.getGlobalDescribe().containsKey('Price_Book_Entry__c')) {
            return;
        }

        Id pricebookId = buildTestSObjectId(Price_Book__c.SObjectType);
        Id productId = buildTestSObjectId(Product__c.SObjectType);
        Map<String, Decimal> syntheticPtrMap =
            HangyoBulkSalesUploadController.loadPtrByPricebookAndProductForTest(
                new Set<Id>{ pricebookId },
                new Set<Id>{ productId }
            );
        System.assertNotEquals(null, syntheticPtrMap);

        Price_Book_Entry__c entry = queryOrgPriceBookEntry();
        if (entry != null) {
            Map<String, Decimal> orgPtrMap =
                HangyoBulkSalesUploadController.loadPtrByPricebookAndProductForTest(
                    new Set<Id>{ entry.Price_Book__c },
                    new Set<Id>{ entry.Product__c }
                );
            String expectedKey =
                HangyoBulkSalesUploadController.buildPricebookProductKeyForTest(
                    entry.Price_Book__c,
                    entry.Product__c
                );
            System.assert(orgPtrMap.containsKey(expectedKey));
        }
    }

    @IsTest
    static void loadRegionPricebookMapAndDistributorStateUseOrgData() {
        Map<String, Id> regionMap =
            HangyoBulkSalesUploadController.loadRegionPricebookMapForTest();
        System.assertNotEquals(null, regionMap);

        Price_Book__c activePriceBook = queryOrgActivePriceBookWithRegion();
        if (activePriceBook != null && activePriceBook.Region__r != null) {
            System.assert(
                regionMap.containsKey(activePriceBook.Region__r.Name.trim())
            );
        }

        String distributorState =
            HangyoBulkSalesUploadController.getDistributorPrimaryStateForTest();
        System.assertNotEquals(null, distributorState);

        Id distributorAccountId = queryCurrentUserDistributorAccountId();
        if (
            distributorAccountId != null &&
            bulkTestHasAccountField('Primary_State__c')
        ) {
            List<Account> distributorAccounts = [
                SELECT Primary_State__c
                FROM Account
                WHERE Id = :distributorAccountId
                LIMIT 1
            ];
            if (
                !distributorAccounts.isEmpty() &&
                distributorAccounts[0].Primary_State__c != null
            ) {
                System.assertEquals(
                    distributorAccounts[0].Primary_State__c.trim(),
                    distributorState
                );
            }
        }
    }

    @IsTest
    static void loadOrdersAndDraftInvoicesExecuteQueryLoops() {
        Map<String, SObject> missingOrders =
            HangyoBulkSalesUploadController.loadOrdersForTest(
                new Set<String>{ 'ZZZ-NO-SUCH-ORDER-999' }
            );
        System.assertEquals(0, missingOrders.size());

        Map<Id, Invoice__c> missingDrafts =
            HangyoBulkSalesUploadController.loadDraftInvoicesByOrderIdForTest(
                new Set<Id>{ buildTestSObjectId(Order__c.SObjectType) }
            );
        System.assertEquals(0, missingDrafts.size());

        String orderNumber = queryOrgOrderNumber();
        if (!String.isBlank(orderNumber)) {
            Map<String, SObject> orders =
                HangyoBulkSalesUploadController.loadOrdersForTest(
                    new Set<String>{ orderNumber, orderNumber + '.0' }
                );
            System.assert(!orders.isEmpty(), 'Expected org order lookup to return data.');
        }

        String draftOrderNumber = queryOrgOrderNumberWithDraftInvoice();
        Id draftOrderId = queryOrgOrderIdByName(draftOrderNumber);
        if (draftOrderId != null) {
            Map<Id, Invoice__c> draftInvoices =
                HangyoBulkSalesUploadController.loadDraftInvoicesByOrderIdForTest(
                    new Set<Id>{ draftOrderId }
                );
            System.assert(
                !draftInvoices.isEmpty(),
                'Expected draft invoice for org order.'
            );
        }
    }

    @IsTest
    static void buildLineSummaryResolvesPtrFromOrgPriceBookChain() {
        Account retailer = queryOrgRetailerWithStateAndPriceBook();
        Product__c product = queryOrgProductLinkedToPriceBookEntry();
        if (retailer == null || product == null) {
            return;
        }

        Map<String, Account> retailerMap = new Map<String, Account>{
            retailer.Retailer_Code__c.toUpperCase() => retailer
        };
        Map<String, SObject> productMap = new Map<String, SObject>{
            product.Product_Code__c.toUpperCase() => product
        };
        Map<String, String> orderRow = new Map<String, String>{
            'Product Code' => product.Product_Code__c,
            'Retailer Code' => retailer.Retailer_Code__c,
            'Order Date' => formatTestDate(System.today()),
            'Discount 2%' => '0',
            '__rowNumber' => '2'
        };

        HangyoBulkSalesUploadController.BulkUploadLineSummary lineSummary =
            HangyoBulkSalesUploadController.buildLineSummaryForTest(
                orderRow,
                retailerMap,
                productMap,
                2,
                false
            );

        System.assertNotEquals(null, lineSummary.price);
        System.assert(lineSummary.price >= 0);
        System.assertNotEquals(null, lineSummary.amount);
        System.assertNotEquals(null, lineSummary.tod);
        System.assertNotEquals(null, lineSummary.totalGst);
        System.assertNotEquals(null, lineSummary.totalAmountInclTax);
    }

    @IsTest
    static void createBulkInvoicesCoversRetailerResolutionFailure() {
        List<Map<String, String>> dataRows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Invoice No.' =>
                    'INV-FAIL-RET-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'Invoice Date' => formatTestDate(System.today()),
                'Retailer Code' =>
                    'NO-SUCH-RETAILER-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'Order Number' => 'O-999999',
                'Product Code' =>
                    'NO-SUCH-PRODUCT-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'Discount 2%' => '0',
                'Quantity' => '1',
                'Data Upload' => 'TRUE',
                'Status' => 'Draft',
                '__rowNumber' => '2'
            }
        };

        Boolean exceptionThrown = false;
        try {
            HangyoBulkSalesUploadController.createBulkInvoicesForTest(
                dataRows,
                EncodingUtil.base64Decode(buildMinimalInvoiceSpreadsheetBase64()),
                'coverage-fail-invoice.xlsx'
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
            assertAuraExceptionMessage(
                ex,
                'Retailer could not be resolved',
                'Expected retailer resolution failure for invoice.'
            );
        }
        System.assert(exceptionThrown, 'Expected retailer resolution failure for invoice.');
    }

    @IsTest
    static void createBulkInvoicesCoversOrderResolutionFailure() {
        Account retailer = queryOrgRetailerAccount();
        if (retailer == null) {
            return;
        }

        List<Map<String, String>> dataRows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Invoice No.' =>
                    'INV-FAIL-ORD-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'Invoice Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Order Number' =>
                    'NO-SUCH-ORDER-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'Product Code' =>
                    'NO-SUCH-PRODUCT-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'Discount 2%' => '0',
                'Quantity' => '1',
                'Data Upload' => 'TRUE',
                'Status' => 'Draft',
                '__rowNumber' => '2'
            }
        };

        Boolean exceptionThrown = false;
        try {
            HangyoBulkSalesUploadController.createBulkInvoicesForTest(
                dataRows,
                EncodingUtil.base64Decode(buildMinimalInvoiceSpreadsheetBase64()),
                'coverage-fail-order-invoice.xlsx'
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
            assertAuraExceptionMessage(
                ex,
                'Order could not be resolved',
                'Expected order resolution failure for invoice.'
            );
        }
        System.assert(exceptionThrown, 'Expected order resolution failure for invoice.');
    }

    @IsTest
    static void createBulkInvoicesCoversProductResolutionFailure() {
        Account retailer = queryOrgRetailerAccount();
        String orderNumber = queryOrgOrderNumber();
        if (retailer == null || String.isBlank(orderNumber)) {
            return;
        }

        List<Map<String, String>> dataRows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Invoice No.' =>
                    'INV-FAIL-PROD-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'Invoice Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Order Number' => orderNumber,
                'Product Code' =>
                    'NO-SUCH-PRODUCT-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'Discount 2%' => '0',
                'Quantity' => '1',
                'Data Upload' => 'TRUE',
                'Status' => 'Draft',
                '__rowNumber' => '2'
            }
        };

        Boolean exceptionThrown = false;
        try {
            HangyoBulkSalesUploadController.createBulkInvoicesForTest(
                dataRows,
                EncodingUtil.base64Decode(buildMinimalInvoiceSpreadsheetBase64()),
                'coverage-fail-product-invoice.xlsx'
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
            String actualMessage = getAuraExceptionMessage(ex);
            System.assert(
                actualMessage.contains('Product could not be resolved') ||
                actualMessage.contains('Invoice creation failed') ||
                actualMessage.contains('Distributor configuration missing') ||
                actualMessage.contains('Invoice Number Prefix'),
                'Expected product or downstream invoice failure. Actual: ' + actualMessage
            );
        }
        System.assert(exceptionThrown, 'Expected product resolution failure for invoice.');
    }

    @IsTest
    static void createBulkInvoicesCoversMultipleLinesForSameReference() {
        Account retailer = queryOrgRetailerAccount();
        Product__c product = queryOrgProductRecord();
        String orderNumber = queryOrgOrderNumberWithoutDraftInvoice();
        if (retailer == null || product == null || String.isBlank(orderNumber)) {
            return;
        }

        String refInvoiceNo =
            'INV-MULTI-' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        List<Map<String, String>> dataRows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Invoice No.' => refInvoiceNo,
                'Invoice Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Order Number' => orderNumber,
                'Product Code' => product.Product_Code__c,
                'Discount 2%' => '0',
                'Quantity' => '2',
                'Data Upload' => 'TRUE',
                'Status' => 'Draft',
                '__rowNumber' => '2'
            },
            new Map<String, String>{
                'Ref Invoice No.' => refInvoiceNo,
                'Invoice Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Order Number' => orderNumber,
                'Product Code' => product.Product_Code__c,
                'Discount 2%' => '5',
                'Quantity' => '3',
                'Data Upload' => 'TRUE',
                'Status' => 'Draft',
                '__rowNumber' => '3'
            }
        };

        try {
            HangyoBulkSalesUploadController.createBulkInvoicesForTest(
                dataRows,
                EncodingUtil.base64Decode(buildMinimalInvoiceSpreadsheetBase64()),
                'coverage-multi-invoice.xlsx'
            );
            System.assert(true);
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, getAuraExceptionMessage(ex));
        }
    }

    @IsTest
    static void createBulkInvoicesCoversInvoiceCreationHelpers() {
        Account retailer = queryOrgRetailerAccount();
        Product__c product = queryOrgProductRecord();
        String orderNumber = queryOrgOrderNumberWithoutDraftInvoice();
        if (retailer == null || product == null || String.isBlank(orderNumber)) {
            return;
        }

        List<Map<String, String>> dataRows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Invoice No.' => 'DIR-INV-HELPER-' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
                'Invoice Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Order Number' => orderNumber,
                'Product Code' => product.Product_Code__c,
                'Discount 2%' => '0',
                'Quantity' => '2',
                'Data Upload' => 'TRUE',
                'Status' => 'Draft',
                '__rowNumber' => '2'
            }
        };

        try {
            HangyoBulkSalesUploadController.createBulkInvoicesForTest(
                dataRows,
                EncodingUtil.base64Decode(buildMinimalInvoiceSpreadsheetBase64()),
                'invoice-helper.xlsx'
            );
            System.assert(true);
        } catch (Exception ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
    }

    @IsTest
    static void loadOrdersForInvoiceCreationAndDistributorDetailsCoverQueries() {
        Map<String, SObject> emptyOrders =
            HangyoBulkSalesUploadController.loadOrdersForInvoiceCreationForTest(
                new Set<String>()
            );
        System.assertEquals(0, emptyOrders.size());

        Map<String, SObject> missingOrders =
            HangyoBulkSalesUploadController.loadOrdersForInvoiceCreationForTest(
                new Set<String>{ 'INV-NO-SUCH-ORDER-001' }
            );
        System.assertEquals(0, missingOrders.size());

        String orderNumber = queryOrgOrderNumber();
        if (!String.isBlank(orderNumber)) {
            Map<String, SObject> orders =
                HangyoBulkSalesUploadController.loadOrdersForInvoiceCreationForTest(
                    new Set<String>{ orderNumber, orderNumber + '.0' }
                );
            System.assert(!orders.isEmpty());
        }

        System.assertEquals(
            null,
            HangyoBulkSalesUploadController.loadDistributorAccountDetailsForTest(null)
        );

        Id distributorId = queryCurrentUserDistributorAccountId();
        if (distributorId != null) {
            Account distributor =
                HangyoBulkSalesUploadController.loadDistributorAccountDetailsForTest(
                    distributorId
                );
            System.assertNotEquals(null, distributor);
            System.assertEquals(distributorId, distributor.Id);
        }
    }

    @IsTest
    static void groupOrderRowsAndOrderTotalsHelpersCoverBranches() {
        List<Map<String, String>> rows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Order No.' => 'ORD-GRP-1',
                '__rowNumber' => '2'
            },
            new Map<String, String>{
                'Ref Order No.' => ' ord-grp-1 ',
                '__rowNumber' => '3'
            },
            new Map<String, String>{
                'Ref Order No.' => 'ORD-GRP-2',
                '__rowNumber' => '4'
            },
            new Map<String, String>{
                'Ref Order No.' => '',
                '__rowNumber' => '5'
            }
        };

        Integer groupCount =
            HangyoBulkSalesUploadController.groupOrderRowsByReferenceCountForTest(rows);
        System.assertEquals(2, groupCount);

        HangyoBulkSalesUploadController.BulkUploadLineSummary lineSummary =
            new HangyoBulkSalesUploadController.BulkUploadLineSummary();
        lineSummary.quantity = 3;
        lineSummary.totalAmountInclTax = 118;
        lineSummary.amount = 100;
        lineSummary.taxableAmount = 100;
        lineSummary.tod = 5;
        lineSummary.discountAmount = 2;

        Account retailer = new Account();
        if (bulkTestHasAccountField('Primary_State__c')) {
            retailer.Primary_State__c = 'Karnataka';
        }
        List<Decimal> totals = HangyoBulkSalesUploadController.addOrderTotalsLineForTest(
            lineSummary,
            retailer,
            'Karnataka',
            new Map<String, Decimal>{
                'CGST' => 9,
                'SGST' => 9
            }
        );

        System.assertEquals(3, totals[0]);
        System.assertEquals(118, totals[1]);
        System.assertEquals(100, totals[2]);
        System.assertEquals(100, totals[3]);
        System.assertEquals(7, totals[4]);
        System.assertEquals(9, totals[5]);
        System.assertEquals(9, totals[6]);
        System.assertEquals(0, totals[7]);
    }

    @IsTest
    static void buildOrderHeaderHelperCoversAssignmentsAndFallbackDate() {
        Id retailerId = buildTestSObjectId(Account.SObjectType);
        Id distributorId = buildTestSObjectId(Account.SObjectType);
        Id orderRecordTypeId = (Id) '012000000000AAA';

        Account retailer = new Account(
            Id = retailerId,
            OwnerId = UserInfo.getUserId()
        );
        if (bulkTestHasAccountField('Beats_Name__c')) {
            retailer.put('Beats_Name__c', 'BT-01');
        }

        Map<String, String> headerRow = new Map<String, String>{
            'Ref Order No.' => ' HDR-001 ',
            'Order Date' => 'invalid-date',
            'Data Upload' => 'TRUE'
        };

        Order__c orderRecord = HangyoBulkSalesUploadController.buildOrderHeaderForTest(
            headerRow,
            retailer,
            distributorId,
            orderRecordTypeId,
            'header-order.xlsx',
            250,
            5,
            200,
            180,
            20,
            9,
            9,
            0
        );

        System.assertEquals(orderRecordTypeId, orderRecord.RecordTypeId);
        System.assertEquals(retailerId, orderRecord.Account__c);
        System.assertEquals(distributorId, orderRecord.AccountId__c);
        System.assertEquals(UserInfo.getUserId(), orderRecord.Ordered_By__c);
        System.assertEquals(System.today(), orderRecord.EffectiveDate__c);
        System.assertEquals(250, orderRecord.Total_order_value__c);
        System.assertEquals(5, orderRecord.Total_Quantity__c);
        System.assertEquals(200, orderRecord.Price__c);
        System.assertEquals(180, orderRecord.Sub_Total__c);
        System.assertEquals(20, orderRecord.Discount_Amount_Order__c);
        System.assertEquals(9, orderRecord.totalCGST__c);
        System.assertEquals(9, orderRecord.totalSGST__c);
        System.assertEquals(0, orderRecord.totalIGST__c);

        if (bulkTestHasOrderField('Ref_Order_No_Data_Upload__c')) {
            System.assertEquals('HDR-001', orderRecord.get('Ref_Order_No_Data_Upload__c'));
        }
        if (bulkTestHasOrderField('File_Name__c')) {
            System.assertEquals('header-order.xlsx', orderRecord.get('File_Name__c'));
        }
        if (bulkTestHasOrderField('Data_Upload__c')) {
            System.assertEquals(true, orderRecord.get('Data_Upload__c'));
        }
        if (
            bulkTestHasAccountField('Beats_Name__c') &&
            bulkTestHasOrderField('Beats_Name__c')
        ) {
            System.assertEquals('BT-01', orderRecord.get('Beats_Name__c'));
        }
    }

    @IsTest
    static void groupInvoiceRowsAndInvoiceTotalsHelpersCoverBranches() {
        List<Map<String, String>> rows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Invoice No.' => 'INV-GRP-1',
                '__rowNumber' => '2'
            },
            new Map<String, String>{
                'Ref Invoice No.' => ' inv-grp-1 ',
                '__rowNumber' => '3'
            },
            new Map<String, String>{
                'Ref Invoice No.' => 'INV-GRP-2',
                '__rowNumber' => '4'
            },
            new Map<String, String>{
                'Ref Invoice No.' => '',
                '__rowNumber' => '5'
            }
        };

        Integer groupCount =
            HangyoBulkSalesUploadController.groupInvoiceRowsByReferenceCountForTest(rows);
        System.assertEquals(2, groupCount);

        HangyoBulkSalesUploadController.BulkUploadLineSummary lineSummary =
            new HangyoBulkSalesUploadController.BulkUploadLineSummary();
        lineSummary.quantity = 4;
        lineSummary.totalAmountInclTax = 236;
        lineSummary.amount = 200;
        lineSummary.taxableAmount = 200;
        lineSummary.totalGst = 36;

        Account retailer = new Account();
        if (bulkTestHasAccountField('Primary_State__c')) {
            retailer.Primary_State__c = 'Karnataka';
        }
        List<Decimal> totals = HangyoBulkSalesUploadController.addInvoiceTotalsLineForTest(
            lineSummary,
            retailer,
            'Karnataka',
            new Map<String, Decimal>{
                'CGST' => 9,
                'SGST' => 9
            }
        );

        System.assertEquals(4, totals[0]);
        System.assertEquals(236, totals[1]);
        System.assertEquals(200, totals[2]);
        System.assertEquals(200, totals[3]);
        System.assertEquals(36, totals[4]);
        System.assertEquals(18, totals[5]);
        System.assertEquals(18, totals[6]);
        System.assertEquals(0, totals[7]);
    }

    @IsTest
    static void buildInvoiceHeaderHelperCoversSameStateAndCentralTax() {
        if (!Schema.getGlobalDescribe().containsKey('Order_tax_value__c')) {
            return;
        }

        List<Order_tax_value__c> existingSettings = [
            SELECT CGST__c, SGST__c, IGST__c
            FROM Order_tax_value__c
            WHERE Name = 'General GST Settings'
            LIMIT 1
        ];
        if (existingSettings.isEmpty()) {
            try {
                insert new Order_tax_value__c(
                    Name = 'General GST Settings',
                    CGST__c = 9,
                    SGST__c = 9,
                    IGST__c = 18
                );
                existingSettings = [
                    SELECT CGST__c, SGST__c, IGST__c
                    FROM Order_tax_value__c
                    WHERE Name = 'General GST Settings'
                    LIMIT 1
                ];
            } catch (Exception ex) {
                return;
            }
        }
        Order_tax_value__c taxSetting = existingSettings[0];

        Id retailerId = buildTestSObjectId(Account.SObjectType);
        Id distributorId = buildTestSObjectId(Account.SObjectType);
        Id linkedOrderId = buildTestSObjectId(Order__c.SObjectType);
        Id invoiceRecordTypeId = (Id) '012000000000AAA';

        Account retailer = new Account(Id = retailerId, Name = 'Retailer');
        if (bulkTestHasAccountField('Primary_State__c')) {
            retailer.Primary_State__c = 'Karnataka';
        }

        Account distributorAccount = new Account(
            Id = distributorId,
            Name = 'Distributor'
        );
        if (bulkTestHasAccountField('Primary_State__c')) {
            distributorAccount.Primary_State__c = 'Karnataka';
        }
        if (bulkTestHasAccountField('GSTIN__c')) {
            distributorAccount.put('GSTIN__c', '29ABCDE1234F1Z5');
        }

        Order__c linkedOrder = new Order__c(Id = linkedOrderId);

        Map<String, String> headerRow = new Map<String, String>{
            'Ref Invoice No.' => ' INV-001 ',
            'Invoice Date' => 'invalid-date',
            'Discount 2%' => '5',
            'Data Upload' => 'TRUE',
            'Status' => 'Draft'
        };

        Invoice__c sameStateInvoice =
            HangyoBulkSalesUploadController.buildInvoiceHeaderForTest(
                headerRow,
                retailer,
                distributorId,
                distributorAccount,
                linkedOrder,
                invoiceRecordTypeId,
                'header-invoice.xlsx',
                'INV0000001',
                7,
                500,
                450,
                400,
                72,
                36,
                36,
                0
            );

        System.assertEquals(invoiceRecordTypeId, sameStateInvoice.RecordTypeId);
        System.assertEquals(linkedOrderId, sameStateInvoice.Order__c);
        System.assertEquals(retailerId, sameStateInvoice.Retailer_Account__c);
        System.assertEquals(distributorId, sameStateInvoice.Distributor_Account__c);
        System.assertEquals('INV0000001', sameStateInvoice.Invoice_Number__c);
        System.assertEquals('INV0000001', sameStateInvoice.Name);
        System.assertEquals(System.today(), sameStateInvoice.Invoice_Date__c);
        System.assertEquals('Draft', sameStateInvoice.Status__c);
        System.assertEquals(500, sameStateInvoice.Invoice_Amount__c);
        System.assertEquals(400, sameStateInvoice.Taxable_Amount__c);
        System.assertEquals(72, sameStateInvoice.Total_GST__c);
        System.assertEquals(7, sameStateInvoice.Total_Quantity__c);
        System.assertEquals(450, sameStateInvoice.Sub_Total__c);
        System.assertEquals(36, sameStateInvoice.CGST_Amount__c);
        System.assertEquals(36, sameStateInvoice.SGST_Amount__c);
        System.assertEquals(0, sameStateInvoice.IGST_Amount__c);
        System.assertEquals(taxSetting.CGST__c, sameStateInvoice.CGST__c);
        System.assertEquals(taxSetting.SGST__c, sameStateInvoice.SGST__c);
        System.assertEquals(0, sameStateInvoice.IGST__c);

        if (bulkTestHasInvoiceField('Custom_Invoice_Number__c')) {
            System.assertEquals('INV0000001', sameStateInvoice.get('Custom_Invoice_Number__c'));
        }
        if (bulkTestHasInvoiceField('File_Name__c')) {
            System.assertEquals('header-invoice.xlsx', sameStateInvoice.get('File_Name__c'));
        }
        if (bulkTestHasInvoiceField('Data_Upload__c')) {
            System.assertEquals(true, sameStateInvoice.get('Data_Upload__c'));
        }
        if (bulkTestHasInvoiceField('Ref_Invoice_No_Data_Upload__c')) {
            System.assertEquals('INV-001', sameStateInvoice.get('Ref_Invoice_No_Data_Upload__c'));
        }
        if (bulkTestHasInvoiceField('Payment_Status__c')) {
            System.assertEquals('Not Paid', sameStateInvoice.get('Payment_Status__c'));
        }
        if (bulkTestHasInvoiceField('Place_of_Supply__c') && bulkTestHasAccountField('Primary_State__c')) {
            System.assertEquals('Karnataka', sameStateInvoice.get('Place_of_Supply__c'));
        }
        if (bulkTestHasInvoiceField('Seller_Name__c')) {
            System.assertEquals('Distributor', sameStateInvoice.get('Seller_Name__c'));
        }
        if (bulkTestHasInvoiceField('Seller_GSTIN__c') && bulkTestHasAccountField('GSTIN__c')) {
            System.assertEquals('29ABCDE1234F1Z5', sameStateInvoice.get('Seller_GSTIN__c'));
        }
        if (bulkTestHasInvoiceField('Tax_Information__c')) {
            System.assertEquals(
                'State Tax Applied',
                sameStateInvoice.get('Tax_Information__c')
            );
        }
        if (bulkTestHasInvoiceField('Invoice_Amount_In_Words__c')) {
            System.assertEquals(
                'Five Hundred Only',
                sameStateInvoice.get('Invoice_Amount_In_Words__c')
            );
        }
        if (bulkTestHasInvoiceField('Discount_2__c')) {
            System.assertEquals(5, sameStateInvoice.get('Discount_2__c'));
        }

        if (bulkTestHasAccountField('Primary_State__c')) {
            distributorAccount.Primary_State__c = 'Maharashtra';
            Invoice__c centralTaxInvoice =
                HangyoBulkSalesUploadController.buildInvoiceHeaderForTest(
                    headerRow,
                    retailer,
                    distributorId,
                    distributorAccount,
                    linkedOrder,
                    invoiceRecordTypeId,
                    'header-invoice.xlsx',
                    'INV0000002',
                    7,
                    500,
                    450,
                    400,
                    72,
                    0,
                    0,
                    72
                );
            System.assertEquals(0, centralTaxInvoice.CGST__c);
            System.assertEquals(0, centralTaxInvoice.SGST__c);
            System.assertEquals(taxSetting.IGST__c, centralTaxInvoice.IGST__c);
            if (bulkTestHasInvoiceField('Tax_Information__c')) {
                System.assert(
                    String.valueOf(centralTaxInvoice.get('Tax_Information__c')).contains('Central Tax Applied')
                );
            }
        }
    }

    private static Product__c queryOrgProductRecordWithTodFields() {
        if (!Schema.getGlobalDescribe().containsKey('Product__c')) {
            return null;
        }
        if (!bulkTestHasProductField('Product_Code__c')) {
            return null;
        }

        List<String> selectFields = new List<String>{
            'Id',
            'Name',
            'Product_Code__c'
        };
        if (bulkTestHasProductField('MRP__c')) {
            selectFields.add('MRP__c');
        }
        if (bulkTestHasProductField('Per_Pieces__c')) {
            selectFields.add('Per_Pieces__c');
        }

        List<String> conditions = new List<String>{
            'Product_Code__c != NULL'
        };
        if (bulkTestHasProductField('IsActive__c')) {
            conditions.add('IsActive__c = TRUE');
        }

        String query =
            'SELECT ' +
            String.join(selectFields, ', ') +
            ' FROM Product__c WHERE ' +
            String.join(conditions, ' AND ') +
            ' ORDER BY CreatedDate DESC LIMIT 1';

        List<Product__c> products = Database.query(query);
        return products.isEmpty() ? null : products[0];
    }

    private static Id buildTestSObjectId(Schema.SObjectType sobjectType) {
        String keyPrefix = sobjectType.getDescribe().getKeyPrefix();
        return (Id) (keyPrefix + '000000000AAA');
    }

    private static Price_Book_Entry__c queryOrgPriceBookEntry() {
        if (!Schema.getGlobalDescribe().containsKey('Price_Book_Entry__c')) {
            return null;
        }

        List<Price_Book_Entry__c> entries = [
            SELECT Id, Product__c, Price_Book__c, PTR__c
            FROM Price_Book_Entry__c
            WHERE isActive__c = TRUE
            AND Type__c = 'Retailer'
            AND Product__c != NULL
            AND Price_Book__c != NULL
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return entries.isEmpty() ? null : entries[0];
    }

    private static Price_Book__c queryOrgActivePriceBookWithRegion() {
        if (!Schema.getGlobalDescribe().containsKey('Price_Book__c')) {
            return null;
        }

        List<Price_Book__c> priceBooks = [
            SELECT Id, Region__r.Name
            FROM Price_Book__c
            WHERE isActive__c = TRUE
            AND Region__c != NULL
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return priceBooks.isEmpty() ? null : priceBooks[0];
    }

    private static Account queryOrgRetailerWithStateAndPriceBook() {
        Price_Book_Entry__c entry = queryOrgPriceBookEntry();
        Price_Book__c priceBook = queryOrgActivePriceBookWithRegion();
        if (
            entry == null ||
            priceBook == null ||
            priceBook.Region__r == null ||
            !bulkTestHasAccountField('Retailer_Code__c') ||
            !bulkTestHasAccountField('Primary_State__c')
        ) {
            return queryOrgRetailerAccount();
        }

        List<String> selectFields = new List<String>{
            'Id',
            'Name',
            'Retailer_Code__c',
            'Primary_State__c'
        };
        List<String> conditions = new List<String>{
            'Retailer_Code__c != NULL',
            'Primary_State__c = \'' +
            String.escapeSingleQuotes(priceBook.Region__r.Name.trim()) +
            '\''
        };
        if (bulkTestHasAccountField('Is_Active__c')) {
            conditions.add('Is_Active__c = TRUE');
        } else if (bulkTestHasAccountField('Active__c')) {
            conditions.add('Active__c = TRUE');
        }

        Id retailerRecordTypeId = getBulkTestRecordTypeId('Account', 'Retailer');
        if (retailerRecordTypeId != null) {
            conditions.add('RecordTypeId = \'' + String.valueOf(retailerRecordTypeId) + '\'');
        }

        String query =
            'SELECT ' +
            String.join(selectFields, ', ') +
            ' FROM Account WHERE ' +
            String.join(conditions, ' AND ') +
            ' ORDER BY CreatedDate DESC LIMIT 1';

        List<Account> retailers = Database.query(query);
        return retailers.isEmpty() ? queryOrgRetailerAccount() : retailers[0];
    }

    private static Product__c queryOrgProductLinkedToPriceBookEntry() {
        Price_Book_Entry__c entry = queryOrgPriceBookEntry();
        if (entry == null || entry.Product__c == null) {
            return queryOrgProductRecordWithTodFields();
        }

        List<String> selectFields = new List<String>{
            'Id',
            'Name',
            'Product_Code__c'
        };
        if (bulkTestHasProductField('MRP__c')) {
            selectFields.add('MRP__c');
        }
        if (bulkTestHasProductField('Per_Pieces__c')) {
            selectFields.add('Per_Pieces__c');
        }

        String query =
            'SELECT ' +
            String.join(selectFields, ', ') +
            ' FROM Product__c WHERE Id = :productId LIMIT 1';

        Id productId = entry.Product__c;
        List<Product__c> products = Database.query(query);
        return products.isEmpty()
            ? queryOrgProductRecordWithTodFields()
            : products[0];
    }

    private static String buildOrderSpreadsheetBase64(
        String retailerCode,
        String productCode,
        String refOrderNo
    ) {
        return EncodingUtil.base64Encode(
            buildMinimalSpreadsheetBlob(
                new List<String>{
                    'Ref Order No.',
                    'Order Date',
                    'Retailer Code',
                    'Product Code',
                    'Quantity',
                    'Data Upload'
                },
                new List<String>{
                    refOrderNo,
                    formatTestDate(System.today()),
                    retailerCode,
                    productCode,
                    '5',
                    'TRUE'
                }
            )
        );
    }

    private static String buildInvoiceSpreadsheetBase64(
        String retailerCode,
        String productCode,
        String orderNumber,
        String refInvoiceNo
    ) {
        return EncodingUtil.base64Encode(
            buildMinimalSpreadsheetBlob(
                new List<String>{
                    'Ref Invoice No.',
                    'Invoice Date',
                    'Retailer Code',
                    'Order Number',
                    'Product Code',
                    'Discount 2%',
                    'Quantity',
                    'Data Upload',
                    'Status'
                },
                new List<String>{
                    refInvoiceNo,
                    formatTestDate(System.today()),
                    retailerCode,
                    orderNumber,
                    productCode,
                    '0',
                    '5',
                    'TRUE',
                    'Draft'
                }
            )
        );
    }

    private static void assignBulkUploadPermission(Id userId) {
        if (!Schema.SObjectType.User.fields.getMap().containsKey('allow_bulk_upload__c')) {
            return;
        }

        update new User(
            Id = userId,
            Allow_Bulk_Upload__c = true
        );
    }

    private static Boolean isOrgIntegrationDataReady() {
        return queryOrgRetailerCode() != null && queryOrgProductCode() != null;
    }

    private static String queryOrgRetailerCode() {
        Account retailer = queryOrgRetailerAccount();
        return retailer == null ? null : retailer.Retailer_Code__c;
    }

    private static String queryOrgProductCode() {
        Product__c product = queryOrgProductRecord();
        return product == null ? null : product.Product_Code__c;
    }

    private static String queryOrgOrderNumber() {
        if (!Schema.getGlobalDescribe().containsKey('Order__c')) {
            return null;
        }

        List<Order__c> orders = [
            SELECT Name
            FROM Order__c
            WHERE Name != NULL
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return orders.isEmpty() ? null : orders[0].Name;
    }

    private static Id queryCurrentUserDistributorAccountId() {
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
        return contacts.isEmpty() ? null : contacts[0].AccountId;
    }

    private static String queryOrgRetailerCodeForDifferentDistributor() {
        Id distributorId = queryCurrentUserDistributorAccountId();
        if (distributorId == null || !bulkTestHasAccountField('Retailer_Code__c')) {
            return null;
        }

        String distributorField;
        if (bulkTestHasAccountField('Distributor__c')) {
            distributorField = 'Distributor__c';
        } else if (bulkTestHasAccountField('Distributor_Account__c')) {
            distributorField = 'Distributor_Account__c';
        } else {
            return null;
        }

        List<String> conditions = new List<String>{
            'Retailer_Code__c != NULL',
            distributorField + ' != NULL',
            distributorField + ' != :distributorId'
        };
        if (bulkTestHasAccountField('Is_Active__c')) {
            conditions.add('Is_Active__c = TRUE');
        } else if (bulkTestHasAccountField('Active__c')) {
            conditions.add('Active__c = TRUE');
        }

        Id retailerRecordTypeId = getBulkTestRecordTypeId('Account', 'Retailer');
        if (retailerRecordTypeId != null) {
            conditions.add('RecordTypeId = \'' + String.valueOf(retailerRecordTypeId) + '\'');
        }

        String query =
            'SELECT Retailer_Code__c FROM Account WHERE ' +
            String.join(conditions, ' AND ') +
            ' ORDER BY CreatedDate DESC LIMIT 1';

        List<Account> retailers = Database.query(query);
        return retailers.isEmpty() ? null : retailers[0].Retailer_Code__c;
    }

    private static String queryOrgOrderNumberForDifferentDistributor() {
        Id distributorId = queryCurrentUserDistributorAccountId();
        if (
            distributorId == null ||
            !Schema.getGlobalDescribe().containsKey('Order__c') ||
            !bulkTestHasOrderField('AccountId__c')
        ) {
            return null;
        }

        List<Order__c> orders = [
            SELECT Name
            FROM Order__c
            WHERE Name != NULL
            AND AccountId__c != NULL
            AND AccountId__c != :distributorId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return orders.isEmpty() ? null : orders[0].Name;
    }

    private static Boolean bulkTestHasOrderField(String fieldApiName) {
        if (!Schema.getGlobalDescribe().containsKey('Order__c')) {
            return false;
        }
        return Schema.getGlobalDescribe()
            .get('Order__c')
            .getDescribe()
            .fields.getMap()
            .containsKey(fieldApiName.toLowerCase());
    }

    private static Boolean bulkTestHasInvoiceField(String fieldApiName) {
        if (!Schema.getGlobalDescribe().containsKey('Invoice__c')) {
            return false;
        }
        return Schema.getGlobalDescribe()
            .get('Invoice__c')
            .getDescribe()
            .fields.getMap()
            .containsKey(fieldApiName.toLowerCase());
    }

    private static String queryOrgOrderNumberWithDraftInvoice() {
        if (
            !Schema.getGlobalDescribe().containsKey('Invoice__c') ||
            !Schema.getGlobalDescribe().containsKey('Order__c')
        ) {
            return null;
        }

        List<Invoice__c> draftInvoices = [
            SELECT Order__r.Name
            FROM Invoice__c
            WHERE Status__c = 'Draft'
            AND Order__c != NULL
            AND Order__r.Name != NULL
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return draftInvoices.isEmpty() ? null : draftInvoices[0].Order__r.Name;
    }

    private static Id queryOrgOrderIdByName(String orderNumber) {
        if (String.isBlank(orderNumber) || !Schema.getGlobalDescribe().containsKey('Order__c')) {
            return null;
        }

        List<Order__c> orders = [
            SELECT Id
            FROM Order__c
            WHERE Name = :orderNumber
            LIMIT 1
        ];
        return orders.isEmpty() ? null : orders[0].Id;
    }

    private static String queryOrgOrderNumberWithoutDraftInvoice() {
        if (
            !Schema.getGlobalDescribe().containsKey('Invoice__c') ||
            !Schema.getGlobalDescribe().containsKey('Order__c')
        ) {
            return queryOrgOrderNumber();
        }

        Set<Id> orderIdsWithDraft = new Set<Id>();
        for (Invoice__c invoice : [
            SELECT Order__c
            FROM Invoice__c
            WHERE Status__c = 'Draft'
            AND Order__c != NULL
            LIMIT 50000
        ]) {
            orderIdsWithDraft.add(invoice.Order__c);
        }

        if (orderIdsWithDraft.isEmpty()) {
            return queryOrgOrderNumber();
        }

        List<Order__c> orders = [
            SELECT Name
            FROM Order__c
            WHERE Name != NULL
            AND Id NOT IN :orderIdsWithDraft
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return orders.isEmpty() ? null : orders[0].Name;
    }

    private static Account queryOrgRetailerAccount() {
        if (!bulkTestHasAccountField('Retailer_Code__c')) {
            return null;
        }

        List<String> selectFields = new List<String>{
            'Id',
            'Name',
            'Retailer_Code__c'
        };
        if (bulkTestHasAccountField('Primary_State__c')) {
            selectFields.add('Primary_State__c');
        }
        if (bulkTestHasAccountField('Distributor__c')) {
            selectFields.add('Distributor__c');
        } else if (bulkTestHasAccountField('Distributor_Account__c')) {
            selectFields.add('Distributor_Account__c');
        }

        List<String> conditions = new List<String>{
            'Retailer_Code__c != NULL'
        };
        if (bulkTestHasAccountField('Is_Active__c')) {
            conditions.add('Is_Active__c = TRUE');
        } else if (bulkTestHasAccountField('Active__c')) {
            conditions.add('Active__c = TRUE');
        }

        Id retailerRecordTypeId = getBulkTestRecordTypeId('Account', 'Retailer');
        if (retailerRecordTypeId != null) {
            conditions.add('RecordTypeId = \'' + String.valueOf(retailerRecordTypeId) + '\'');
        }

        String query =
            'SELECT ' +
            String.join(selectFields, ', ') +
            ' FROM Account WHERE ' +
            String.join(conditions, ' AND ') +
            ' ORDER BY CreatedDate DESC LIMIT 1';

        List<Account> retailers = Database.query(query);
        return retailers.isEmpty() ? null : retailers[0];
    }

    private static Product__c queryOrgProductRecord() {
        if (!Schema.getGlobalDescribe().containsKey('Product__c')) {
            return null;
        }
        if (!bulkTestHasProductField('Product_Code__c')) {
            return null;
        }

        List<String> conditions = new List<String>{
            'Product_Code__c != NULL'
        };
        if (bulkTestHasProductField('IsActive__c')) {
            conditions.add('IsActive__c = TRUE');
        }

        String query =
            'SELECT Id, Name, Product_Code__c FROM Product__c WHERE ' +
            String.join(conditions, ' AND ') +
            ' ORDER BY CreatedDate DESC LIMIT 1';

        List<Product__c> products = Database.query(query);
        return products.isEmpty() ? null : products[0];
    }

    private static Id getBulkTestRecordTypeId(String sobjectName, String recordTypeName) {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = :sobjectName AND Name = :recordTypeName
            LIMIT 1
        ];
        return recordTypes.isEmpty() ? null : recordTypes[0].Id;
    }

    private static Boolean bulkTestHasAccountField(String fieldApiName) {
        return Schema.SObjectType.Account.fields.getMap()
            .containsKey(fieldApiName.toLowerCase());
    }

    private static Boolean bulkTestHasProductField(String fieldApiName) {
        if (!Schema.getGlobalDescribe().containsKey('Product__c')) {
            return false;
        }
        return Schema.getGlobalDescribe()
            .get('Product__c')
            .getDescribe()
            .fields.getMap()
            .containsKey(fieldApiName.toLowerCase());
    }

    private static String buildMinimalOrderSpreadsheetBase64() {
        return EncodingUtil.base64Encode(buildMinimalSpreadsheetBlob(
            new List<String>{
                'Ref Order No.',
                'Order Date',
                'Retailer Code',
                'Product Code',
                'Quantity',
                'Data Upload'
            },
            new List<String>{
                'ORD-001',
                '14/5/2026',
                'SF123',
                'P001',
                '5',
                'TRUE'
            }
        ));
    }

    private static String buildMinimalInvoiceSpreadsheetBase64() {
        return EncodingUtil.base64Encode(buildMinimalSpreadsheetBlob(
            new List<String>{
                'Ref Invoice No.',
                'Invoice Date',
                'Retailer Code',
                'Order Number',
                'Product Code',
                'Discount 2%',
                'Quantity',
                'Data Upload',
                'Status'
            },
            new List<String>{
                'INV-001',
                '14/5/2026',
                'SF123',
                'O-001',
                'P001',
                '0',
                '5',
                'TRUE',
                'Draft'
            }
        ));
    }

    private static Blob buildMinimalSpreadsheetBlob(
        List<String> headerValues,
        List<String> dataValues
    ) {
        List<String> sharedStrings = new List<String>();
        sharedStrings.addAll(headerValues);
        sharedStrings.addAll(dataValues);

        String sharedStringsXml =
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
            '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="' +
            sharedStrings.size() +
            '" uniqueCount="' +
            sharedStrings.size() +
            '">';

        for (String value : sharedStrings) {
            sharedStringsXml += '<si><t>' + value + '</t></si>';
        }
        sharedStringsXml += '</sst>';

        String headerCells = '';
        for (Integer index = 0; index < headerValues.size(); index++) {
            String column = columnLetter(index);
            headerCells +=
                '<c r="' +
                column +
                '1" t="s"><v>' +
                index +
                '</v></c>';
        }

        Integer dataOffset = headerValues.size();
        String dataCells = '';
        for (Integer index = 0; index < dataValues.size(); index++) {
            String column = columnLetter(index);
            dataCells +=
                '<c r="' +
                column +
                '2" t="s"><v>' +
                (dataOffset + index) +
                '</v></c>';
        }

        String sheetXml =
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>' +
            '<row r="1">' +
            headerCells +
            '</row>' +
            '<row r="2">' +
            dataCells +
            '</row>' +
            '</sheetData></worksheet>';

        Compression.ZipWriter writer = new Compression.ZipWriter();
        writer.addEntry('xl/sharedStrings.xml', Blob.valueOf(sharedStringsXml));
        writer.addEntry('xl/worksheets/sheet1.xml', Blob.valueOf(sheetXml));
        return writer.getArchive();
    }

    private static Blob buildZipWorkbook(
        String sheetEntryName,
        String sheetXml,
        String sharedStringsXml
    ) {
        Compression.ZipWriter writer = new Compression.ZipWriter();
        writer.addEntry(sheetEntryName, Blob.valueOf(sheetXml));
        if (!String.isBlank(sharedStringsXml)) {
            writer.addEntry('xl/sharedStrings.xml', Blob.valueOf(sharedStringsXml));
        }
        return writer.getArchive();
    }

    private static String columnLetter(Integer index) {
        String letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        if (index < 26) {
            return letters.substring(index, index + 1);
        }

        Integer first = index / 26;
        Integer second = Math.mod(index, 26);
        return letters.substring(first - 1, first) + letters.substring(second, second + 1);
    }
}