@isTest
public class InvoiceLineItemTriggerTest {
    @isTest
    static void testTaxCalculationOnInsert() {
        // Create Invoice with tax percentages
        Invoice__c invoice = new Invoice__c(
            Name = 'Test Invoice',
            CGST__c = 5,
            SGST__c = 5,
            IGST__c = 12
        );
        insert invoice;

        // Create Invoice Line Item
        Invoice_Line_Item__c item = new Invoice_Line_Item__c(
            Invoice__c = invoice.Id,
            Total_Amount__c = 1000,
            Discount_1__c = 100,
            Discount_2__c = 50
        );
        insert item;

        // Query inserted item to validate calculations
        item = [SELECT Tax__c, CGST_Amount__c, SGST_Amount__c, IGST_Amount__c FROM Invoice_Line_Item__c WHERE Id = :item.Id];

        Decimal expectedTax = 1000 - 100 - 50; // 850
        Decimal expectedCGST = (expectedTax * 5) / 100;
        Decimal expectedSGST = (expectedTax * 5) / 100;
        Decimal expectedIGST = (expectedTax * 12) / 100;

        System.assertEquals(expectedTax.setScale(2), item.Tax__c, 'Tax should be calculated correctly');
        System.assertEquals(expectedCGST.setScale(2), item.CGST_Amount__c, 'CGST should be correct');
        System.assertEquals(expectedSGST.setScale(2), item.SGST_Amount__c, 'SGST should be correct');
        System.assertEquals(expectedIGST.setScale(2), item.IGST_Amount__c, 'IGST should be correct');
    }

    // Covers the MRP-extraction branch: Counter Invoice + Price_Type__c = MRP must EXTRACT
    // the taxable value out of the tax-inclusive amount (Tax__c = amountAfterDiscount /
    // (1 + rate%)) instead of using the amount as-is, so that Tax__c + GST reconstructs
    // back to the original amountAfterDiscount rather than exceeding it.
    @isTest
    static void testTaxExtractionForMrpCounterInvoice() {
        Invoice__c invoice = new Invoice__c(
            Name = 'Test MRP Counter Invoice',
            CGST__c = 2.5,
            SGST__c = 2.5,
            IGST__c = 0,
            Price_Type__c = 'MRP',
            Origin__c = 'Counter Invoice'
        );
        insert invoice;

        Invoice_Line_Item__c item = new Invoice_Line_Item__c(
            Invoice__c = invoice.Id,
            Total_Amount__c = 300,
            Discount_1__c = 0,
            Discount_2__c = 0
        );
        insert item;

        item = [SELECT Tax__c, CGST_Amount__c, SGST_Amount__c, IGST_Amount__c FROM Invoice_Line_Item__c WHERE Id = :item.Id];

        // amountAfterDiscount = 300, total rate = 5% -> extracted taxable value = 300 / 1.05
        Decimal expectedTaxableValue = (300 / 1.05).setScale(2, RoundingMode.HALF_UP);
        Decimal expectedCGST = ((expectedTaxableValue * 2.5) / 100).setScale(2, RoundingMode.HALF_UP);
        Decimal expectedSGST = ((expectedTaxableValue * 2.5) / 100).setScale(2, RoundingMode.HALF_UP);

        System.assertEquals(expectedTaxableValue, item.Tax__c, 'MRP Counter Invoice should extract the taxable value, not use the full amount');
        System.assertEquals(expectedCGST, item.CGST_Amount__c, 'CGST should be computed on the extracted taxable value');
        System.assertEquals(expectedSGST, item.SGST_Amount__c, 'SGST should be computed on the extracted taxable value');
        System.assertEquals(0, item.IGST_Amount__c, 'IGST should be zero for same-state MRP invoice');

        // The whole point: taxable value + GST reconstructs back to the original amount (300),
        // instead of exceeding it the way the old add-on-top formula did.
        Decimal reconstructed = item.Tax__c + item.CGST_Amount__c + item.SGST_Amount__c + item.IGST_Amount__c;
        System.assertEquals(300, reconstructed.setScale(0, RoundingMode.HALF_UP), 'Extracted taxable value + GST should reconstruct to the original tax-inclusive amount');
    }

    // Covers that a Secondary Order/Invoice marked Price_Type__c = MRP must NOT use the
    // extraction formula — only Origin__c = 'Counter Invoice' triggers extraction. Secondary
    // Invoices always use the normal add-on-top formula regardless of Price_Type__c.
    @isTest
    static void testNoExtractionForMrpSecondaryInvoice() {
        Invoice__c invoice = new Invoice__c(
            Name = 'Test MRP Secondary Invoice',
            CGST__c = 2.5,
            SGST__c = 2.5,
            IGST__c = 0,
            Price_Type__c = 'MRP',
            Origin__c = null // Secondary Invoices never get Origin__c = 'Counter Invoice'
        );
        insert invoice;

        Invoice_Line_Item__c item = new Invoice_Line_Item__c(
            Invoice__c = invoice.Id,
            Total_Amount__c = 300,
            Discount_1__c = 0,
            Discount_2__c = 0
        );
        insert item;

        item = [SELECT Tax__c, CGST_Amount__c, SGST_Amount__c FROM Invoice_Line_Item__c WHERE Id = :item.Id];

        System.assertEquals(300, item.Tax__c, 'Secondary Invoice marked MRP should NOT extract — taxable value should be the full amount');
        System.assertEquals(7.5, item.CGST_Amount__c, 'CGST should be added on top of the full amount for Secondary Invoices, even if marked MRP');
        System.assertEquals(7.5, item.SGST_Amount__c, 'SGST should be added on top of the full amount for Secondary Invoices, even if marked MRP');
    }

    // Covers that Scheme_Discount_Amount__c (Purchase Quantity Discount) is subtracted
    // from the taxable base the same way Discount_1__c (TOD) and Discount_2__c already are —
    // this was missing before and caused the per-line Taxable Amount to not reflect an
    // applied scheme even though the invoice-level total correctly did.
    @isTest
    static void testTaxCalculationSubtractsSchemeDiscount() {
        Invoice__c invoice = new Invoice__c(
            Name = 'Test Invoice Scheme Discount',
            CGST__c = 5,
            SGST__c = 5,
            IGST__c = 0
        );
        insert invoice;

        Invoice_Line_Item__c item = new Invoice_Line_Item__c(
            Invoice__c = invoice.Id,
            Total_Amount__c = 1000,
            Discount_1__c = 0,
            Discount_2__c = 0,
            Scheme_Discount_Amount__c = 200
        );
        insert item;

        item = [SELECT Tax__c, CGST_Amount__c, SGST_Amount__c FROM Invoice_Line_Item__c WHERE Id = :item.Id];

        Decimal expectedTax = 1000 - 200; // 800
        System.assertEquals(expectedTax.setScale(2), item.Tax__c, 'Taxable base should subtract the Scheme_Discount_Amount__c');
        System.assertEquals((expectedTax * 5 / 100).setScale(2), item.CGST_Amount__c, 'CGST should be computed on the scheme-reduced taxable base');
        System.assertEquals((expectedTax * 5 / 100).setScale(2), item.SGST_Amount__c, 'SGST should be computed on the scheme-reduced taxable base');
    }
}