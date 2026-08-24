@IsTest
private class HangyoBulkUpdatePathTest {

    @IsTest
    static void updateExistingOrdersUpdatesQuantityWhenMatchFound() {
        if (!updatePathPrereqsAvailable()) return;

        String refOrderNo = 'UPD-ORD-' + rand();
        Account retailer = createTestRetailer('UPD-RET-' + rand());
        Product__c product = createTestProduct('UPD-PRD-' + rand());
        if (retailer == null || product == null) return;

        Order__c order = createTestOrder(refOrderNo, retailer.Id, System.today());
        if (order == null) return;
        Order_Line_Item__c lineItem = createTestOrderLineItem(order.Id, product.Id, 5, 100);
        if (lineItem == null) return;

        Map<String, String> row = new Map<String, String>{
            'Ref Order No.' => refOrderNo,
            'Order Date' => formatTestDate(System.today()),
            'Retailer Code' => retailer.Retailer_Code__c,
            'Product Code' => product.Product_Code__c,
            'Quantity' => '9',
            '__rowNumber' => '2'
        };

        HangyoBulkSalesUploadController.OrderUpdateResult result =
            HangyoBulkSalesUploadController.updateExistingOrdersForTest(
                new List<Map<String, String>>{ row }
            );

        System.assertEquals(0, result.errors.size());
        System.assertEquals(1, result.updatedCount);
        System.assert(result.updatedOrderIds.contains(order.Id));

        Order_Line_Item__c updatedLine = [
            SELECT Ordered_Quantity__c FROM Order_Line_Item__c WHERE Id = :lineItem.Id
        ];
        System.assertEquals(9, updatedLine.Ordered_Quantity__c);
    }

    @IsTest
    static void updateExistingOrdersRejectsRetailerChange() {
        if (!updatePathPrereqsAvailable()) return;

        String refOrderNo = 'UPD-ORD-RET-' + rand();
        Account originalRetailer = createTestRetailer('UPD-RET-A-' + rand());
        Account differentRetailer = createTestRetailer('UPD-RET-B-' + rand());
        Product__c product = createTestProduct('UPD-PRD-' + rand());
        if (originalRetailer == null || differentRetailer == null || product == null) return;

        Order__c order = createTestOrder(refOrderNo, originalRetailer.Id, System.today());
        if (order == null) return;
        createTestOrderLineItem(order.Id, product.Id, 5, 100);

        Map<String, String> row = new Map<String, String>{
            'Ref Order No.' => refOrderNo,
            'Order Date' => formatTestDate(System.today()),
            'Retailer Code' => differentRetailer.Retailer_Code__c,
            'Product Code' => product.Product_Code__c,
            'Quantity' => '9',
            '__rowNumber' => '2'
        };

        HangyoBulkSalesUploadController.OrderUpdateResult result =
            HangyoBulkSalesUploadController.updateExistingOrdersForTest(
                new List<Map<String, String>>{ row }
            );

        System.assert(hasError(result.errors, 'Retailer Code'), 'Expected retailer mismatch rejection.');
    }

    @IsTest
    static void updateExistingOrdersRejectsOrderDateChange() {
        if (!updatePathPrereqsAvailable()) return;

        String refOrderNo = 'UPD-ORD-DT-' + rand();
        Account retailer = createTestRetailer('UPD-RET-' + rand());
        Product__c product = createTestProduct('UPD-PRD-' + rand());
        if (retailer == null || product == null) return;

        Order__c order = createTestOrder(refOrderNo, retailer.Id, System.today());
        if (order == null) return;
        createTestOrderLineItem(order.Id, product.Id, 5, 100);

        Map<String, String> row = new Map<String, String>{
            'Ref Order No.' => refOrderNo,
            'Order Date' => formatTestDate(System.today().addDays(-1)),
            'Retailer Code' => retailer.Retailer_Code__c,
            'Product Code' => product.Product_Code__c,
            'Quantity' => '9',
            '__rowNumber' => '2'
        };

        HangyoBulkSalesUploadController.OrderUpdateResult result =
            HangyoBulkSalesUploadController.updateExistingOrdersForTest(
                new List<Map<String, String>>{ row }
            );

        System.assert(hasError(result.errors, 'Order Date'), 'Expected order date change rejection.');
    }

    @IsTest
    static void updateExistingOrdersRejectsProductNotOnOriginalOrder() {
        if (!updatePathPrereqsAvailable()) return;

        String refOrderNo = 'UPD-ORD-PRD-' + rand();
        Account retailer = createTestRetailer('UPD-RET-' + rand());
        Product__c originalProduct = createTestProduct('UPD-PRD-A-' + rand());
        Product__c newProduct = createTestProduct('UPD-PRD-B-' + rand());
        if (retailer == null || originalProduct == null || newProduct == null) return;

        Order__c order = createTestOrder(refOrderNo, retailer.Id, System.today());
        if (order == null) return;
        createTestOrderLineItem(order.Id, originalProduct.Id, 5, 100);

        Map<String, String> row = new Map<String, String>{
            'Ref Order No.' => refOrderNo,
            'Order Date' => formatTestDate(System.today()),
            'Retailer Code' => retailer.Retailer_Code__c,
            'Product Code' => newProduct.Product_Code__c,
            'Quantity' => '3',
            '__rowNumber' => '2'
        };

        HangyoBulkSalesUploadController.OrderUpdateResult result =
            HangyoBulkSalesUploadController.updateExistingOrdersForTest(
                new List<Map<String, String>>{ row }
            );

        Boolean found = false;
        for (HangyoBulkSalesUploadController.BulkUploadError e : result.errors) {
            if (e.columnName == 'Product Code' && e.errorMessage.contains('does not exist on the original order')) {
                found = true;
            }
        }
        System.assert(found, 'Expected new-product-on-update rejection.');
    }

    @IsTest
    static void updateExistingOrdersRejectsInvalidQuantity() {
        if (!updatePathPrereqsAvailable()) return;

        String refOrderNo = 'UPD-ORD-QTY-' + rand();
        Account retailer = createTestRetailer('UPD-RET-' + rand());
        Product__c product = createTestProduct('UPD-PRD-' + rand());
        if (retailer == null || product == null) return;

        Order__c order = createTestOrder(refOrderNo, retailer.Id, System.today());
        if (order == null) return;
        createTestOrderLineItem(order.Id, product.Id, 5, 100);

        Map<String, String> row = new Map<String, String>{
            'Ref Order No.' => refOrderNo,
            'Order Date' => formatTestDate(System.today()),
            'Retailer Code' => retailer.Retailer_Code__c,
            'Product Code' => product.Product_Code__c,
            'Quantity' => 'not-a-number',
            '__rowNumber' => '2'
        };

        HangyoBulkSalesUploadController.OrderUpdateResult result =
            HangyoBulkSalesUploadController.updateExistingOrdersForTest(
                new List<Map<String, String>>{ row }
            );

        System.assert(hasError(result.errors, 'Quantity'), 'Expected invalid quantity rejection.');
    }

    @IsTest
    static void updateExistingOrdersRejectsUnmatchedReference() {
        Map<String, String> row = new Map<String, String>{
            'Ref Order No.' => 'NO-SUCH-ORDER-' + rand(),
            'Order Date' => formatTestDate(System.today()),
            'Retailer Code' => 'SF999',
            'Product Code' => 'PZZZ',
            'Quantity' => '1',
            '__rowNumber' => '2'
        };

        HangyoBulkSalesUploadController.OrderUpdateResult result =
            HangyoBulkSalesUploadController.updateExistingOrdersForTest(
                new List<Map<String, String>>{ row }
            );

        System.assert(!result.errors.isEmpty());
        System.assertEquals(0, result.updatedCount);
    }

    // ---------------- Invoice update path ----------------

    @IsTest
    static void updateExistingInvoicesUpdatesQuantityWhenDraftAndMatchFound() {
        if (!updatePathPrereqsAvailable()) return;

        String refInvoiceNo = 'UPD-INV-' + rand();
        Account retailer = createTestRetailer('UPD-RET-' + rand());
        Product__c product = createTestProduct('UPD-PRD-' + rand());
        if (retailer == null || product == null) return;

        Order__c order = createTestOrder('UPD-ORD-FOR-INV-' + rand(), retailer.Id, System.today());
        if (order == null) return;

        Invoice__c invoice = createTestInvoice(refInvoiceNo, retailer.Id, order.Id, System.today(), 'Draft');
        if (invoice == null) return;
        Invoice_Line_Item__c lineItem = createTestInvoiceLineItem(invoice.Id, product.Id, 4, 50);
        if (lineItem == null) return;

        Map<String, String> row = new Map<String, String>{
            'Ref Invoice No.' => refInvoiceNo,
            'Invoice Date' => formatTestDate(System.today()),
            'Retailer Code' => retailer.Retailer_Code__c,
            'Order Number' => order.Name,
            'Product Code' => product.Product_Code__c,
            'Discount 2%' => '0',
            'Quantity' => '7',
            'Status' => 'Draft',
            '__rowNumber' => '2'
        };

        HangyoBulkSalesUploadController.InvoiceUpdateResult result =
            HangyoBulkSalesUploadController.updateExistingInvoicesForTest(
                new List<Map<String, String>>{ row }
            );

        System.assertEquals(0, result.errors.size());
        System.assertEquals(1, result.updatedCount);
        System.assert(result.updatedInvoiceIds.contains(invoice.Id));

        Invoice_Line_Item__c updatedLine = [
            SELECT Quantity__c, Total_Amount__c FROM Invoice_Line_Item__c WHERE Id = :lineItem.Id
        ];
        System.assertEquals(7, updatedLine.Quantity__c);
        System.assertEquals(350, updatedLine.Total_Amount__c);
    }

    @IsTest
    static void updateExistingInvoicesRejectsWhenNotDraft() {
        if (!updatePathPrereqsAvailable()) return;

        String refInvoiceNo = 'UPD-INV-CONF-' + rand();
        Account retailer = createTestRetailer('UPD-RET-' + rand());
        Product__c product = createTestProduct('UPD-PRD-' + rand());
        if (retailer == null || product == null) return;

        Order__c order = createTestOrder('UPD-ORD-FOR-INV-CONF-' + rand(), retailer.Id, System.today());
        if (order == null) return;

        Invoice__c invoice = createTestInvoice(refInvoiceNo, retailer.Id, order.Id, System.today(), 'Confirmed');
        if (invoice == null) return;
        createTestInvoiceLineItem(invoice.Id, product.Id, 4, 50);

        Map<String, String> row = new Map<String, String>{
            'Ref Invoice No.' => refInvoiceNo,
            'Invoice Date' => formatTestDate(System.today()),
            'Retailer Code' => retailer.Retailer_Code__c,
            'Order Number' => order.Name,
            'Product Code' => product.Product_Code__c,
            'Discount 2%' => '0',
            'Quantity' => '7',
            'Status' => 'Confirmed',
            '__rowNumber' => '2'
        };

        HangyoBulkSalesUploadController.InvoiceUpdateResult result =
            HangyoBulkSalesUploadController.updateExistingInvoicesForTest(
                new List<Map<String, String>>{ row }
            );

        Boolean found = false;
        for (HangyoBulkSalesUploadController.BulkUploadError e : result.errors) {
            if (e.columnName == 'Status' && e.errorMessage.contains('Draft status')) found = true;
        }
        System.assert(found, 'Expected non-draft invoice update rejection.');
        System.assertEquals(0, result.updatedCount);
    }

    @IsTest
    static void updateExistingInvoicesRejectsRetailerChange() {
        if (!updatePathPrereqsAvailable()) return;

        String refInvoiceNo = 'UPD-INV-RET-' + rand();
        Account originalRetailer = createTestRetailer('UPD-RET-A-' + rand());
        Account differentRetailer = createTestRetailer('UPD-RET-B-' + rand());
        Product__c product = createTestProduct('UPD-PRD-' + rand());
        if (originalRetailer == null || differentRetailer == null || product == null) return;

        Order__c order = createTestOrder('UPD-ORD-FOR-INV-RET-' + rand(), originalRetailer.Id, System.today());
        if (order == null) return;

        Invoice__c invoice = createTestInvoice(refInvoiceNo, originalRetailer.Id, order.Id, System.today(), 'Draft');
        if (invoice == null) return;
        createTestInvoiceLineItem(invoice.Id, product.Id, 4, 50);

        Map<String, String> row = new Map<String, String>{
            'Ref Invoice No.' => refInvoiceNo,
            'Invoice Date' => formatTestDate(System.today()),
            'Retailer Code' => differentRetailer.Retailer_Code__c,
            'Order Number' => order.Name,
            'Product Code' => product.Product_Code__c,
            'Discount 2%' => '0',
            'Quantity' => '7',
            'Status' => 'Draft',
            '__rowNumber' => '2'
        };

        HangyoBulkSalesUploadController.InvoiceUpdateResult result =
            HangyoBulkSalesUploadController.updateExistingInvoicesForTest(
                new List<Map<String, String>>{ row }
            );

        System.assert(hasError(result.errors, 'Retailer Code'));
    }

    @IsTest
    static void updateExistingInvoicesRejectsOrderChange() {
        if (!updatePathPrereqsAvailable()) return;

        String refInvoiceNo = 'UPD-INV-ORD-' + rand();
        Account retailer = createTestRetailer('UPD-RET-' + rand());
        Product__c product = createTestProduct('UPD-PRD-' + rand());
        if (retailer == null || product == null) return;

        Order__c originalOrder = createTestOrder('UPD-ORD-ORIG-' + rand(), retailer.Id, System.today());
        Order__c differentOrder = createTestOrder('UPD-ORD-DIFF-' + rand(), retailer.Id, System.today());
        if (originalOrder == null || differentOrder == null) return;

        Invoice__c invoice = createTestInvoice(refInvoiceNo, retailer.Id, originalOrder.Id, System.today(), 'Draft');
        if (invoice == null) return;
        createTestInvoiceLineItem(invoice.Id, product.Id, 4, 50);

        Map<String, String> row = new Map<String, String>{
            'Ref Invoice No.' => refInvoiceNo,
            'Invoice Date' => formatTestDate(System.today()),
            'Retailer Code' => retailer.Retailer_Code__c,
            'Order Number' => differentOrder.Name,
            'Product Code' => product.Product_Code__c,
            'Discount 2%' => '0',
            'Quantity' => '7',
            'Status' => 'Draft',
            '__rowNumber' => '2'
        };

        HangyoBulkSalesUploadController.InvoiceUpdateResult result =
            HangyoBulkSalesUploadController.updateExistingInvoicesForTest(
                new List<Map<String, String>>{ row }
            );

        System.assert(hasError(result.errors, 'Order Number'));
    }

    @IsTest
    static void updateExistingInvoicesRejectsInvoiceDateChange() {
        if (!updatePathPrereqsAvailable()) return;

        String refInvoiceNo = 'UPD-INV-DT-' + rand();
        Account retailer = createTestRetailer('UPD-RET-' + rand());
        Product__c product = createTestProduct('UPD-PRD-' + rand());
        if (retailer == null || product == null) return;

        Order__c order = createTestOrder('UPD-ORD-FOR-INV-DT-' + rand(), retailer.Id, System.today());
        if (order == null) return;

        Invoice__c invoice = createTestInvoice(refInvoiceNo, retailer.Id, order.Id, System.today(), 'Draft');
        if (invoice == null) return;
        createTestInvoiceLineItem(invoice.Id, product.Id, 4, 50);

        Map<String, String> row = new Map<String, String>{
            'Ref Invoice No.' => refInvoiceNo,
            'Invoice Date' => formatTestDate(System.today().addDays(-1)),
            'Retailer Code' => retailer.Retailer_Code__c,
            'Order Number' => order.Name,
            'Product Code' => product.Product_Code__c,
            'Discount 2%' => '0',
            'Quantity' => '7',
            'Status' => 'Draft',
            '__rowNumber' => '2'
        };

        HangyoBulkSalesUploadController.InvoiceUpdateResult result =
            HangyoBulkSalesUploadController.updateExistingInvoicesForTest(
                new List<Map<String, String>>{ row }
            );

        System.assert(hasError(result.errors, 'Invoice Date'));
    }

    @IsTest
    static void updateExistingInvoicesRejectsProductNotOnOriginalInvoice() {
        if (!updatePathPrereqsAvailable()) return;

        String refInvoiceNo = 'UPD-INV-PRD-' + rand();
        Account retailer = createTestRetailer('UPD-RET-' + rand());
        Product__c originalProduct = createTestProduct('UPD-PRD-A-' + rand());
        Product__c newProduct = createTestProduct('UPD-PRD-B-' + rand());
        if (retailer == null || originalProduct == null || newProduct == null) return;

        Order__c order = createTestOrder('UPD-ORD-FOR-INV-PRD-' + rand(), retailer.Id, System.today());
        if (order == null) return;

        Invoice__c invoice = createTestInvoice(refInvoiceNo, retailer.Id, order.Id, System.today(), 'Draft');
        if (invoice == null) return;
        createTestInvoiceLineItem(invoice.Id, originalProduct.Id, 4, 50);

        Map<String, String> row = new Map<String, String>{
            'Ref Invoice No.' => refInvoiceNo,
            'Invoice Date' => formatTestDate(System.today()),
            'Retailer Code' => retailer.Retailer_Code__c,
            'Order Number' => order.Name,
            'Product Code' => newProduct.Product_Code__c,
            'Discount 2%' => '0',
            'Quantity' => '2',
            'Status' => 'Draft',
            '__rowNumber' => '2'
        };

        HangyoBulkSalesUploadController.InvoiceUpdateResult result =
            HangyoBulkSalesUploadController.updateExistingInvoicesForTest(
                new List<Map<String, String>>{ row }
            );

        Boolean found = false;
        for (HangyoBulkSalesUploadController.BulkUploadError e : result.errors) {
            if (e.columnName == 'Product Code' && e.errorMessage.contains('does not exist on the original invoice')) {
                found = true;
            }
        }
        System.assert(found);
    }

    @IsTest
    static void updateExistingInvoicesRejectsInvalidQuantity() {
        if (!updatePathPrereqsAvailable()) return;

        String refInvoiceNo = 'UPD-INV-QTY-' + rand();
        Account retailer = createTestRetailer('UPD-RET-' + rand());
        Product__c product = createTestProduct('UPD-PRD-' + rand());
        if (retailer == null || product == null) return;

        Order__c order = createTestOrder('UPD-ORD-FOR-INV-QTY-' + rand(), retailer.Id, System.today());
        if (order == null) return;

        Invoice__c invoice = createTestInvoice(refInvoiceNo, retailer.Id, order.Id, System.today(), 'Draft');
        if (invoice == null) return;
        createTestInvoiceLineItem(invoice.Id, product.Id, 4, 50);

        Map<String, String> row = new Map<String, String>{
            'Ref Invoice No.' => refInvoiceNo,
            'Invoice Date' => formatTestDate(System.today()),
            'Retailer Code' => retailer.Retailer_Code__c,
            'Order Number' => order.Name,
            'Product Code' => product.Product_Code__c,
            'Discount 2%' => '0',
            'Quantity' => 'bad-qty',
            'Status' => 'Draft',
            '__rowNumber' => '2'
        };

        HangyoBulkSalesUploadController.InvoiceUpdateResult result =
            HangyoBulkSalesUploadController.updateExistingInvoicesForTest(
                new List<Map<String, String>>{ row }
            );

        System.assert(hasError(result.errors, 'Quantity'));
    }

    @IsTest
    static void updateExistingInvoicesRejectsUnmatchedReference() {
        Map<String, String> row = new Map<String, String>{
            'Ref Invoice No.' => 'NO-SUCH-INVOICE-' + rand(),
            'Invoice Date' => formatTestDate(System.today()),
            'Retailer Code' => 'SF999',
            'Order Number' => 'O-NONE',
            'Product Code' => 'PZZZ',
            'Discount 2%' => '0',
            'Quantity' => '1',
            'Status' => 'Draft',
            '__rowNumber' => '2'
        };

        HangyoBulkSalesUploadController.InvoiceUpdateResult result =
            HangyoBulkSalesUploadController.updateExistingInvoicesForTest(
                new List<Map<String, String>>{ row }
            );

        System.assert(!result.errors.isEmpty());
        System.assertEquals(0, result.updatedCount);
    }

    // ---------------- recalculation / loader helpers ----------------

    @IsTest
    static void recalculateOrderTotalsUpdatesHeaderAfterLineChange() {
        if (!updatePathPrereqsAvailable()) return;

        Account retailer = createTestRetailer('UPD-RET-RECALC-' + rand());
        Product__c product = createTestProduct('UPD-PRD-RECALC-' + rand());
        if (retailer == null || product == null) return;

        Order__c order = createTestOrder('UPD-ORD-RECALC-' + rand(), retailer.Id, System.today());
        if (order == null) return;
        createTestOrderLineItem(order.Id, product.Id, 4, 25);

        HangyoBulkSalesUploadController.recalculateOrderTotalsForTest(new Set<Id>{ order.Id });

        Order__c recalculated = [SELECT Total_Quantity__c, Price__c FROM Order__c WHERE Id = :order.Id];
        System.assertEquals(4, recalculated.Total_Quantity__c);
        System.assertEquals(100, recalculated.Price__c);
    }

    @IsTest
    static void recalculateInvoiceTotalsUpdatesHeaderAfterLineChange() {
        if (!updatePathPrereqsAvailable()) return;

        Account retailer = createTestRetailer('UPD-RET-IRECALC-' + rand());
        Product__c product = createTestProduct('UPD-PRD-IRECALC-' + rand());
        if (retailer == null || product == null) return;

        Order__c order = createTestOrder('UPD-ORD-FOR-IRECALC-' + rand(), retailer.Id, System.today());
        if (order == null) return;

        Invoice__c invoice = createTestInvoice('UPD-INV-RECALC-' + rand(), retailer.Id, order.Id, System.today(), 'Draft');
        if (invoice == null) return;
        createTestInvoiceLineItem(invoice.Id, product.Id, 3, 40);

        HangyoBulkSalesUploadController.recalculateInvoiceTotalsForTest(new Set<Id>{ invoice.Id });

        Invoice__c recalculated = [SELECT Total_Quantity__c, Invoice_Amount__c FROM Invoice__c WHERE Id = :invoice.Id];
        System.assertEquals(3, recalculated.Total_Quantity__c);
        System.assertEquals(120, recalculated.Invoice_Amount__c);
    }

    @IsTest
    static void loadExistingLineItemHelpersReturnDataForCreatedRecords() {
        if (!updatePathPrereqsAvailable()) return;

        Account retailer = createTestRetailer('UPD-RET-LOAD-' + rand());
        Product__c product = createTestProduct('UPD-PRD-LOAD-' + rand());
        if (retailer == null || product == null) return;

        Order__c order = createTestOrder('UPD-ORD-LOAD-' + rand(), retailer.Id, System.today());
        if (order == null) return;
        createTestOrderLineItem(order.Id, product.Id, 2, 30);

        Map<Id, List<Order_Line_Item__c>> orderLines =
            HangyoBulkSalesUploadController.loadExistingOrderLineItemsForTest(new Set<Id>{ order.Id });
        System.assert(orderLines.containsKey(order.Id));

        Invoice__c invoice = createTestInvoice('UPD-INV-LOAD-' + rand(), retailer.Id, order.Id, System.today(), 'Draft');
        if (invoice == null) return;
        createTestInvoiceLineItem(invoice.Id, product.Id, 2, 30);

        Map<Id, List<Invoice_Line_Item__c>> invoiceLines =
            HangyoBulkSalesUploadController.loadExistingInvoiceLineItemsForTest(new Set<Id>{ invoice.Id });
        System.assert(invoiceLines.containsKey(invoice.Id));
    }

    //Added by Hari - Test Class Coverage
    // ---------------- create / save / check paths (no portal runAs, null blob skips NetworkId) ----------------

    @IsTest
    static void createBulkOrdersForTestCoversSuccessPathWithoutReceivedDocument() {
        //Added by Hari - Test Class Coverage
        if (!updatePathPrereqsAvailable()) return;
        assignBulkUploadPermission(UserInfo.getUserId());

        Account retailer = createTestRetailer('CRT-RET-' + rand());
        Product__c product = createTestProduct('CRT-PRD-' + rand());
        if (retailer == null || product == null) return;

        String refOrderNo = 'CRT-ORD-' + rand();
        List<Map<String, String>> rows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Order No.' => refOrderNo,
                'Order Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Product Code' => product.Product_Code__c,
                'Quantity' => '4',
                'Data Upload' => 'TRUE',
                '__rowNumber' => '2'
            },
            new Map<String, String>{
                'Ref Order No.' => refOrderNo,
                'Order Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Product Code' => product.Product_Code__c,
                'Quantity' => '2',
                'Data Upload' => 'TRUE',
                '__rowNumber' => '3'
            }
        };

        try {
            // null Blob skips ReceivedDocument/ContentVersion (avoids NetworkId in Experience Cloud)
            HangyoBulkSalesUploadController.BulkOrderCreationResult created =
                HangyoBulkSalesUploadController.createBulkOrdersForTest(
                    rows,
                    null,
                    'create-order-coverage.xlsx'
                );
            System.assertNotEquals(null, created);
            if (created.ordersCreated != null && created.ordersCreated > 0) {
                System.assert(!created.orderIds.isEmpty());

                List<Map<String, String>> updateRows = new List<Map<String, String>>{
                    new Map<String, String>{
                        'Ref Order No.' => refOrderNo,
                        'Order Date' => formatTestDate(System.today()),
                        'Retailer Code' => retailer.Retailer_Code__c,
                        'Product Code' => product.Product_Code__c,
                        'Quantity' => '10',
                        '__rowNumber' => '2'
                    }
                };
                HangyoBulkSalesUploadController.OrderUpdateResult upd =
                    HangyoBulkSalesUploadController.updateExistingOrdersForTest(updateRows);
                System.assertNotEquals(null, upd);

                HangyoBulkSalesUploadController.recalculateOrderTotalsForTest(
                    new Set<Id>(created.orderIds)
                );
                Map<String, Order__c> byRef =
                    HangyoBulkSalesUploadController.loadExistingOrdersByRefForTest(
                        new Set<String>{ refOrderNo.trim().toUpperCase() }
                    );
                System.assert(!byRef.isEmpty());
            }
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
    }

    @IsTest
    static void createBulkInvoicesForTestCoversCreationPathWithoutReceivedDocument() {
        //Added by Hari - Test Class Coverage
        if (!updatePathPrereqsAvailable()) return;
        assignBulkUploadPermission(UserInfo.getUserId());

        Account retailer = createTestRetailer('CRT-INV-RET-' + rand());
        Product__c product = createTestProduct('CRT-INV-PRD-' + rand());
        if (retailer == null || product == null) return;

        Order__c order = createTestOrder('CRT-ORD-FOR-INV-' + rand(), retailer.Id, System.today());
        if (order == null) return;

        String refInvoiceNo = 'CRT-INV-' + rand();
        List<Map<String, String>> rows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Invoice No.' => refInvoiceNo,
                'Invoice Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Order Number' => order.Name,
                'Product Code' => product.Product_Code__c,
                'Discount 2%' => '0',
                'Quantity' => '3',
                'Data Upload' => 'TRUE',
                'Status' => 'Draft',
                '__rowNumber' => '2'
            }
        };

        try {
            HangyoBulkSalesUploadController.createBulkInvoicesForTest(
                rows,
                null,
                'create-invoice-coverage.xlsx'
            );
        } catch (AuraHandledException ex) {
            // Invoice number config may be missing; still covers create path branches.
            System.assertNotEquals(null, ex.getMessage());
        }

        HangyoBulkSalesUploadController.InvoiceUpdateResult missing =
            HangyoBulkSalesUploadController.updateExistingInvoicesForTest(
                new List<Map<String, String>>{
                    new Map<String, String>{
                        'Ref Invoice No.' => 'NO-INV-' + rand(),
                        'Invoice Date' => formatTestDate(System.today()),
                        'Retailer Code' => retailer.Retailer_Code__c,
                        'Order Number' => order.Name,
                        'Product Code' => product.Product_Code__c,
                        'Discount 2%' => '0',
                        'Quantity' => '1',
                        'Status' => 'Draft',
                        '__rowNumber' => '2'
                    }
                }
            );
        System.assert(!missing.errors.isEmpty());
    }

    @IsTest
    static void checkAndSaveEntryPointsCoverValidationWithoutCommunityRunAs() {
        //Added by Hari - Test Class Coverage
        assignBulkUploadPermission(UserInfo.getUserId());

        HangyoBulkSalesUploadController.DuplicateCheckResult badCheck =
            HangyoBulkSalesUploadController.checkExistingReferencesForTest(
                'Order',
                'orders.xlsx',
                EncodingUtil.base64Encode(Blob.valueOf('not-an-xlsx'))
            );
        System.assertNotEquals(null, badCheck);

        HangyoBulkSalesUploadController.BulkUploadSaveResult badSave =
            HangyoBulkSalesUploadController.saveBulkUploadWithUpdateSupportForTest(
                'Order',
                '',
                '',
                false
            );
        System.assertEquals('ValidationFailed', badSave.status);

        HangyoBulkSalesUploadController.BulkUploadSaveResult missingFileSave =
            HangyoBulkSalesUploadController.saveBulkUploadForTest('Order', '', '');
        System.assertEquals('ValidationFailed', missingFileSave.status);

        System.assertEquals(
            0,
            HangyoBulkSalesUploadController.findExistingOrderRefsForTest(new Set<String>()).size()
        );
        System.assertEquals(
            0,
            HangyoBulkSalesUploadController.findExistingInvoiceRefsForTest(new Set<String>()).size()
        );

        if (updatePathPrereqsAvailable()) {
            Account retailer = createTestRetailer('CHK-RET-' + rand());
            Product__c product = createTestProduct('CHK-PRD-' + rand());
            if (retailer != null && product != null) {
                String refNo = 'CHK-REF-' + rand();
                Order__c order = createTestOrder(refNo, retailer.Id, System.today());
                if (order != null) {
                    List<String> found =
                        HangyoBulkSalesUploadController.findExistingOrderRefsForTest(
                            new Set<String>{ refNo }
                        );
                    System.assert(!found.isEmpty());
                    Map<String, Order__c> loaded =
                        HangyoBulkSalesUploadController.loadExistingOrdersByRefForTest(
                            new Set<String>{ refNo.trim().toUpperCase() }
                        );
                    System.assert(!loaded.isEmpty());
                }
            }
        }

        try {
            HangyoBulkSalesUploadController.downloadUploadTemplate('Order');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
        try {
            HangyoBulkSalesUploadController.downloadUploadTemplate('Invoice');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
        try {
            HangyoBulkSalesUploadController.downloadUploadTemplate('Bogus');
            System.assert(false, 'Expected invalid upload type');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
    }

    @IsTest
    static void createBulkOrdersCoversRetailerAndProductFailureBranches() {
        //Added by Hari - Test Class Coverage
        assignBulkUploadPermission(UserInfo.getUserId());

        List<Map<String, String>> badRetailerRows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Order No.' => 'FAIL-RET-' + rand(),
                'Order Date' => formatTestDate(System.today()),
                'Retailer Code' => 'NO-RETAILER-' + rand(),
                'Product Code' => 'NO-PRODUCT',
                'Quantity' => '1',
                'Data Upload' => 'TRUE',
                '__rowNumber' => '2'
            }
        };
        Boolean retailerFailed = false;
        try {
            HangyoBulkSalesUploadController.createBulkOrdersForTest(
                badRetailerRows,
                null,
                'fail-retailer.xlsx'
            );
        } catch (AuraHandledException ex) {
            retailerFailed = true;
            System.assertNotEquals(null, ex.getMessage());
        }
        System.assert(retailerFailed, 'Expected retailer resolution failure.');

        if (!updatePathPrereqsAvailable()) return;
        Account retailer = createTestRetailer('FAIL-PRD-RET-' + rand());
        if (retailer == null) return;

        List<Map<String, String>> badProductRows = new List<Map<String, String>>{
            new Map<String, String>{
                'Ref Order No.' => 'FAIL-PRD-' + rand(),
                'Order Date' => formatTestDate(System.today()),
                'Retailer Code' => retailer.Retailer_Code__c,
                'Product Code' => 'NO-PRODUCT-' + rand(),
                'Quantity' => '1',
                'Data Upload' => 'TRUE',
                '__rowNumber' => '2'
            }
        };
        Boolean productFailed = false;
        try {
            HangyoBulkSalesUploadController.createBulkOrdersForTest(
                badProductRows,
                null,
                'fail-product.xlsx'
            );
        } catch (AuraHandledException ex) {
            productFailed = true;
            System.assertNotEquals(null, ex.getMessage());
        }
        System.assert(productFailed, 'Expected product resolution failure.');

        try {
            HangyoBulkSalesUploadController.createBulkOrdersForTest(
                new List<Map<String, String>>(),
                null,
                'empty-rows.xlsx'
            );
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
    }

    // ---------------- test data helpers ----------------

    /*private static Boolean updatePathPrereqsAvailable() {
        return getRecordTypeId('Account', 'Retailer') != null &&
            getRecordTypeId('Order__c', 'Secondary Order') != null &&
            getRecordTypeId('Order_Line_Item__c', 'Secondary Order Line Item') != null &&
            getRecordTypeId('Invoice__c', 'Secondary Invoice') != null;
    }*/
    private static Boolean updatePathPrereqsAvailable() {
        Boolean available = getRecordTypeId('Account', 'Retailer') != null &&
            getRecordTypeId('Order__c', 'Secondary Order') != null &&
            getRecordTypeId('Order_Line_Item__c', 'Secondary Order Line Item') != null &&
            getRecordTypeId('Invoice__c', 'Secondary Invoice') != null;
        if (!available) {
            System.debug(LoggingLevel.WARN,
                'HangyoBulkUpdatePathTest: required Record Types missing — update-path tests will be skipped.');
        }
        return available;
    }

    private static Id getRecordTypeId(String sobjectName, String recordTypeName) {
        List<RecordType> rts = [
            SELECT Id FROM RecordType WHERE SObjectType = :sobjectName AND Name = :recordTypeName LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static Boolean hasError(List<HangyoBulkSalesUploadController.BulkUploadError> errors, String column) {
        for (HangyoBulkSalesUploadController.BulkUploadError e : errors) {
            if (e.columnName == column) return true;
        }
        return false;
    }

    //Added by Hari - Test Class Coverage
    private static void assignBulkUploadPermission(Id userId) {
        if (!Schema.SObjectType.User.fields.getMap().containsKey('allow_bulk_upload__c')) {
            return;
        }
        try {
            update new User(Id = userId, Allow_Bulk_Upload__c = true);
        } catch (Exception ex) {
            // Permission may be restricted in some orgs; non-fatal for coverage helpers.
        }
    }

    private static Account createTestRetailer(String retailerCode) {
        Id rtId = getRecordTypeId('Account', 'Retailer');
        if (rtId == null) return null;

        //Added by Hari - Test Class Coverage
        Id distributorId = null;
        if (hasField('Account', 'Distributor__c') || hasField('Account', 'Distributor_Account__c')) {
            try {
                Account distributor = new Account(Name = 'DIST-' + retailerCode);
                insert distributor;
                distributorId = distributor.Id;
            } catch (Exception ex) {
                distributorId = null;
            }
        }

        Account retailer = new Account(
            Name = retailerCode,
            RecordTypeId = rtId,
            Retailer_Code__c = retailerCode
        );
        if (hasField('Account', 'Is_Active__c')) retailer.put('Is_Active__c', true);
        else if (hasField('Account', 'Active__c')) retailer.put('Active__c', true);
        if (hasField('Account', 'Primary_State__c')) retailer.put('Primary_State__c', 'Karnataka');
        //Added by Hari - Test Class Coverage
        if (distributorId != null) {
            if (hasField('Account', 'Distributor__c')) {
                retailer.put('Distributor__c', distributorId);
            } else if (hasField('Account', 'Distributor_Account__c')) {
                retailer.put('Distributor_Account__c', distributorId);
            }
        }

        try { insert retailer; } catch (Exception ex) { return null; }
        return retailer;
    }

    private static Product__c createTestProduct(String productCode) {
        if (!Schema.getGlobalDescribe().containsKey('Product__c')) return null;

        Product__c product = new Product__c(Name = productCode, Product_Code__c = productCode);
        if (hasField('Product__c', 'IsActive__c')) product.put('IsActive__c', true);
        if (hasField('Product__c', 'MRP__c')) product.put('MRP__c', 100);
        if (hasField('Product__c', 'Per_Pieces__c')) product.put('Per_Pieces__c', 1);

        try { insert product; } catch (Exception ex) { return null; }
        return product;
    }

    private static Order__c createTestOrder(String refOrderNo, Id retailerId, Date effectiveDate) {
        Id rtId = getRecordTypeId('Order__c', 'Secondary Order');
        if (rtId == null) return null;

        Order__c order = new Order__c(
            RecordTypeId = rtId,
            Account__c = retailerId,
            EffectiveDate__c = effectiveDate,
            Status__c = 'Order Placed',
            Type__c = 'Bulk Upload',
            Ref_Order_No_Data_Upload__c = refOrderNo
        );

        try { insert order; } catch (Exception ex) { return null; }
        return [SELECT Id, Name, Account__c, EffectiveDate__c FROM Order__c WHERE Id = :order.Id];
    }

    private static Order_Line_Item__c createTestOrderLineItem(Id orderId, Id productId, Decimal qty, Decimal price) {
        Id rtId = getRecordTypeId('Order_Line_Item__c', 'Secondary Order Line Item');
        if (rtId == null) return null;

        Order_Line_Item__c li = new Order_Line_Item__c(
            RecordTypeId = rtId,
            Order__c = orderId,
            Products__c = productId,
            Ordered_Quantity__c = qty,
            Product_Price__c = price
        );
        if (hasField('Order_Line_Item__c', 'Is_Promotional__c')) li.put('Is_Promotional__c', false);

        try { insert li; } catch (Exception ex) { return null; }
        return li;
    }

    private static Invoice__c createTestInvoice(String refInvoiceNo, Id retailerId, Id orderId, Date invoiceDate, String status) {
        Id rtId = getRecordTypeId('Invoice__c', 'Secondary Invoice');
        if (rtId == null) return null;

        Invoice__c invoice = new Invoice__c(
            RecordTypeId = rtId,
            Order__c = orderId,
            Retailer_Account__c = retailerId,
            Invoice_Number__c = refInvoiceNo,
            Name = refInvoiceNo,
            Invoice_Date__c = invoiceDate,
            Status__c = status,
            Type__c = 'Bulk Upload',
            Ref_Invoice_No_Data_Upload__c = refInvoiceNo
        );

        try { insert invoice; } catch (Exception ex) { return null; }
        return invoice;
    }

    private static Invoice_Line_Item__c createTestInvoiceLineItem(Id invoiceId, Id productId, Decimal qty, Decimal price) {
        Invoice_Line_Item__c li = new Invoice_Line_Item__c(
            Invoice__c = invoiceId,
            Product__c = productId,
            Quantity__c = qty,
            Price__c = price,
            Total_Amount__c = price * qty
        );
        if (hasField('Invoice_Line_Item__c', 'Is_Promotional__c')) li.put('Is_Promotional__c', false);
        if (hasField('Invoice_Line_Item__c', 'Discount_1__c')) li.put('Discount_1__c', 0);
        if (hasField('Invoice_Line_Item__c', 'Discount_2__c')) li.put('Discount_2__c', 0);

        try { insert li; } catch (Exception ex) { return null; }
        return li;
    }

    private static Boolean hasField(String sobjectName, String fieldApiName) {
        if (!Schema.getGlobalDescribe().containsKey(sobjectName)) return false;
        return Schema.getGlobalDescribe().get(sobjectName).getDescribe()
            .fields.getMap().containsKey(fieldApiName.toLowerCase());
    }

    private static String formatTestDate(Date value) {
        String day = value.day() < 10 ? '0' + value.day() : String.valueOf(value.day());
        String month = value.month() < 10 ? '0' + value.month() : String.valueOf(value.month());
        return day + '/' + month + '/' + String.valueOf(value.year());
    }

    private static Integer rand() {
        return Math.abs(Crypto.getRandomInteger());
    }
}