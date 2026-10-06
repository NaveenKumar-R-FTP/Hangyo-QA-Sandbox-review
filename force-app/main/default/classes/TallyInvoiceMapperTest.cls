/**
 * @description Unit tests for TallyInvoiceMapper.
 */
@isTest
private class TallyInvoiceMapperTest {
    @isTest
    static void mapInvoices_returnsEmptyForNullOrEmptyInput() {
        System.assertEquals(0, TallyInvoiceMapper.mapInvoices(null).size());
        System.assertEquals(0, TallyInvoiceMapper.mapInvoices(new List<Invoice__c>()).size());
    }

    @isTest
    static void mapInvoices_mapsSaleInvoiceWithProductFallbacks() {
        Id ownerId = TallyInvoiceTestDataFactory.resolveAllowedOwnerId();
        Product__c product = TallyInvoiceTestDataFactory.createProduct('Aam Ras');
        product.Product_Code__c = '5301110';
        product.Rate_Value__c = 100;
        product.MRP__c = 120;
        update product;

        Invoice__c invoice = TallyInvoiceTestDataFactory.createInvoice(
            ownerId,
            Date.today(),
            TallyInvoiceTestDataFactory.TRANSACTION_TYPE_SALE,
            null
        );

        Invoice_Line_Item__c lineItem = new Invoice_Line_Item__c(
            Invoice__c = invoice.Id,
            Product__c = product.Id,
            Quantity__c = 2,
            Discount__c = 5,
            Tax__c = 18,
            CGST_Amount__c = 9,
            SGST_Amount__c = 9,
            IGST_Amount__c = 0,
            CGST_Percentage__c = 9,
            SGST_Percentage__c = 9,
            IGST_Percentage__c = 0,
            Sub_Total__c = 100,
            Total_Amount__c = 200
        );
        insert lineItem;

        Invoice__c queriedInvoice =
            TallyInvoiceTestDataFactory.queryInvoiceWithLineItems(invoice.Id);

        Test.startTest();
        List<TallyInvoiceResponseWrapper.InvoiceWrapper> mapped =
            TallyInvoiceMapper.mapInvoices(new List<Invoice__c>{ queriedInvoice });
        Test.stopTest();

        System.assertEquals(1, mapped.size());
        System.assertEquals(
            TallyInvoiceTestDataFactory.TRANSACTION_TYPE_SALE,
            mapped[0].voucherType
        );
        System.assertEquals(1, mapped[0].lineItems.size());
        System.assertEquals('Aam Ras', mapped[0].lineItems[0].productName);
        System.assertEquals('5301110', mapped[0].lineItems[0].productCode);
        System.assertEquals(
            queriedInvoice.Invoice_Line_Items__r[0].Product__r.Unit_of_Measure__c,
            mapped[0].lineItems[0].unitOfMeasure
        );
        System.assertEquals(120, mapped[0].lineItems[0].mrp);
        System.assertEquals(100, mapped[0].lineItems[0].rate);
    }

    @isTest
    static void mapInvoices_usesPurchaseVoucherTypeWhenSaleIsBlank() {
        Id ownerId = TallyInvoiceTestDataFactory.resolveAllowedOwnerId();
        Invoice__c invoice = TallyInvoiceTestDataFactory.createInvoice(
            ownerId,
            Date.today(),
            null,
            TallyInvoiceTestDataFactory.TRANSACTION_TYPE_PURCHASE
        );

        Invoice__c queriedInvoice =
            TallyInvoiceTestDataFactory.queryInvoiceWithLineItems(invoice.Id);

        List<TallyInvoiceResponseWrapper.InvoiceWrapper> mapped =
            TallyInvoiceMapper.mapInvoices(new List<Invoice__c>{ queriedInvoice });

        System.assertEquals(
            TallyInvoiceTestDataFactory.TRANSACTION_TYPE_PURCHASE,
            mapped[0].voucherType
        );
        System.assertEquals(0, mapped[0].lineItems.size());
    }

    @isTest
    static void mapInvoices_handlesNullLineItemsCollection() {
        Id ownerId = TallyInvoiceTestDataFactory.resolveAllowedOwnerId();

        Invoice__c invoiceWithoutLines = TallyInvoiceTestDataFactory.createInvoice(
            ownerId,
            Date.today(),
            TallyInvoiceTestDataFactory.TRANSACTION_TYPE_SALE,
            null
        );
        Invoice__c queriedWithoutLines =
            TallyInvoiceTestDataFactory.queryInvoiceHeaderOnly(invoiceWithoutLines.Id);

        Invoice__c invoiceWithLine = TallyInvoiceTestDataFactory.createInvoice(
            ownerId,
            Date.today(),
            TallyInvoiceTestDataFactory.TRANSACTION_TYPE_SALE,
            null
        );
        Product__c product = TallyInvoiceTestDataFactory.createProduct('Line Product');
        Invoice_Line_Item__c lineItem = new Invoice_Line_Item__c(
            Invoice__c = invoiceWithLine.Id,
            Product__c = product.Id,
            Price__c = 50,
            MRP__c = 55,
            Total_Amount__c = 50,
            Quantity__c = 1
        );
        insert lineItem;

        Invoice__c queriedWithLine =
            TallyInvoiceTestDataFactory.queryInvoiceWithLineItems(invoiceWithLine.Id);

        List<TallyInvoiceResponseWrapper.InvoiceWrapper> mapped =
            TallyInvoiceMapper.mapInvoices(
                new List<Invoice__c>{ queriedWithoutLines, queriedWithLine }
            );

        System.assertEquals(2, mapped.size());
        System.assertEquals(0, mapped[0].lineItems.size());
        System.assertEquals(1, mapped[1].lineItems.size());
        System.assertEquals(50, mapped[1].lineItems[0].rate);
        System.assertEquals(55, mapped[1].lineItems[0].mrp);
    }

    @isTest
    static void mapInvoices_mapsProductUnitOfMeasureFromProduct() {
        Id ownerId = TallyInvoiceTestDataFactory.resolveAllowedOwnerId();
        String productUom = TallyInvoiceTestDataFactory.getAlternateProductUnitOfMeasure();

        Product__c product = TallyInvoiceTestDataFactory.createProduct('Fallback Product');
        product.Unit_of_Measure__c = productUom;
        product.MRP__c = 999;
        product.Rate_Value__c = 888;
        update product;

        Invoice__c invoice = TallyInvoiceTestDataFactory.createInvoice(
            ownerId,
            Date.today(),
            TallyInvoiceTestDataFactory.TRANSACTION_TYPE_SALE,
            null
        );

        Invoice_Line_Item__c lineItem = new Invoice_Line_Item__c(
            Invoice__c = invoice.Id,
            Product__c = product.Id,
            Price__c = 75,
            MRP__c = 80,
            Quantity__c = 1,
            Total_Amount__c = 75
        );
        insert lineItem;

        Invoice__c queriedInvoice =
            TallyInvoiceTestDataFactory.queryInvoiceWithLineItems(invoice.Id);

        List<TallyInvoiceResponseWrapper.InvoiceWrapper> mapped =
            TallyInvoiceMapper.mapInvoices(new List<Invoice__c>{ queriedInvoice });

        System.assertEquals(productUom, mapped[0].lineItems[0].unitOfMeasure);
        System.assertEquals(80, mapped[0].lineItems[0].mrp);
        System.assertEquals(75, mapped[0].lineItems[0].rate);
    }
}