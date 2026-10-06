/**
 * @description Unit tests for TallyInvoiceResponseWrapper DTOs.
 */
@isTest
private class TallyInvoiceResponseWrapperTest {
    @isTest
    static void wrapperFields_canBeInstantiatedAndSerialized() {
        TallyInvoiceResponseWrapper response = new TallyInvoiceResponseWrapper();
        response.success = true;
        response.message = 'OK';
        response.invoices = new List<TallyInvoiceResponseWrapper.InvoiceWrapper>();

        TallyInvoiceResponseWrapper.InvoiceWrapper invoice =
            new TallyInvoiceResponseWrapper.InvoiceWrapper();
        invoice.invoiceId = 'a0X000001';
        invoice.voucherNumber = 'VCH-1';
        invoice.invoiceNumber = 'INV-1';
        invoice.invoiceDate = Date.today();
        invoice.voucherDate = Date.today();
        invoice.voucherType = 'Sales';
        invoice.customerName = 'Test Customer';
        invoice.remarks = 'Remarks';
        invoice.ownerId = UserInfo.getUserId();
        invoice.cgstAmount = 9;
        invoice.sgstAmount = 9;
        invoice.igstAmount = 0;
        invoice.cgstPercent = 9;
        invoice.sgstPercent = 9;
        invoice.igstPercent = 0;
        invoice.taxableAmount = 100;
        invoice.totalGst = 18;
        invoice.invoiceTotal = 118;
        invoice.netInvoiceAmount = 118;
        invoice.subTotal = 100;
        invoice.totalQuantity = 2;
        invoice.lineItems = new List<TallyInvoiceResponseWrapper.LineItemWrapper>();

        TallyInvoiceResponseWrapper.LineItemWrapper line =
            new TallyInvoiceResponseWrapper.LineItemWrapper();
        line.lineItemId = 'a0Y000001';
        line.lineItemName = 'LI-1';
        line.productId = 'a0Z000001';
        line.productName = 'Test Product';
        line.productCode = 'PCODE-001';
        line.hsn = '21050000';
        line.unitOfMeasure = 'NOS';
        line.productBrand = 'Hangyo';
        line.categoryName = 'Ice Cream';
        line.categoryCode = 'IC01';
        line.priceType = 'MRP';
        line.alternateUom = 'BOX';
        line.uomConversion = '12';
        line.quantity = 2;
        line.rate = 50;
        line.amount = 100;
        line.discount = 0;
        line.mrp = 60;
        line.tax = 18;
        line.gstPercent = 18;
        line.cgstAmount = 9;
        line.sgstAmount = 9;
        line.igstAmount = 0;
        line.cgstPercent = 9;
        line.sgstPercent = 9;
        line.igstPercent = 0;
        line.subTotal = 100;
        line.totalAmount = 118;
        line.perPieces = 1;
        line.crateConversion = 24;
        invoice.lineItems.add(line);
        response.invoices.add(invoice);

        Test.startTest();
        String jsonBody = JSON.serialize(response);
        Test.stopTest();

        System.assert(jsonBody.contains('"success":true'), 'Success flag should serialize');
        System.assert(
            jsonBody.contains('"productName":"Test Product"'),
            'Nested line item fields should serialize'
        );
    }
}