/**
 * @description Shared test data factory for Tally Invoice API test classes.
 */
@isTest
public class TallyInvoiceTestDataFactory {
    /** Active user from deployed Tally_Allowed_User__mdt User1 record. */
    public static final Id ALLOWED_OWNER_ID = '005e1000003GxGwAAK';

    /** Valid Transaction_Type_Sale__c picklist API values in Hangyo org. */
    public static final String TRANSACTION_TYPE_SALE = 'Sale to Retailer';
    public static final String TRANSACTION_TYPE_SALE_ALT = 'Sale to Under S';

    /** Valid Transaction_Type_Purchase__c picklist API values in Hangyo org. */
    public static final String TRANSACTION_TYPE_PURCHASE = 'Purchased from Hangyo';
    public static final String TRANSACTION_TYPE_PURCHASE_ALT = 'Purchased from Super Stockist';

    /** Keeps invoice editable for line-item DML in tests (InvoiceEditWindow trigger guard). */
    public static final String INVOICE_STATUS_DRAFT = 'Draft';

    public static Product__c createProduct(String productName) {
        Product__c product = new Product__c(
            Name = productName,
            Product_Code__c = 'PCODE-001',
            HSN__c = '21050000',
            Unit_of_Measure__c = getProductUnitOfMeasure(),
            Tax_Percentage__c = 18,
            Product_Brand__c = 'Hangyo',
            Category_Name__c = 'Ice Cream',
            Category_Code__c = 'IC01',
            Rate_Value__c = 100,
            MRP__c = 120,
            Price_Type__c = 'MRP',
            Alternate_UOM__c = 'BOX',
            UOM_Conversion__c = '12',
            Per_Pieces__c = 1,
            Crate_Conversion__c = 24
        );
        insert product;
        return product;
    }

    public static Invoice__c createInvoice(
        Id ownerId,
        Date invoiceDate,
        String voucherTypeSale,
        String voucherTypePurchase
    ) {
        Invoice__c invoice = new Invoice__c(
            OwnerId = ownerId,
            Status__c = INVOICE_STATUS_DRAFT,
            Data_Upload__c = false,
            Invoice_Number__c = buildUniqueInvoiceNumber(),
            Invoice_Date__c = invoiceDate,
            Transaction_Type_Sale__c = voucherTypeSale,
            Transaction_Type_Purchase__c = voucherTypePurchase,
            Remarks__c = 'Test remarks',
            CGST_Amount__c = 9,
            SGST_Amount__c = 9,
            IGST_Amount__c = 0,
            CGST__c = 9,
            SGST__c = 9,
            IGST__c = 0,
            Taxable_Amount__c = 100,
            Total_GST__c = 18,
            Invoice_Total__c = 118,
            Net_Invoice_Amount_c__c = 118,
            Sub_Total__c = 100,
            Total_Quantity__c = 2
        );
        insert invoice;
        return invoice;
    }

    public static Invoice_Line_Item__c createLineItem(Id invoiceId, Id productId) {
        Invoice_Line_Item__c lineItem = new Invoice_Line_Item__c(
            Invoice__c = invoiceId,
            Product__c = productId,
            Quantity__c = 2,
            Price__c = 50,
            Discount__c = 0,
            MRP__c = 60,
            Tax__c = 18,
            CGST_Amount__c = 9,
            SGST_Amount__c = 9,
            IGST_Amount__c = 0,
            CGST_Percentage__c = 9,
            SGST_Percentage__c = 9,
            IGST_Percentage__c = 0,
            Sub_Total__c = 100,
            Total_Amount__c = 118
        );
        insert lineItem;
        return lineItem;
    }

    public static Invoice__c createInvoiceWithLineItem(Id ownerId, Date invoiceDate) {
        Product__c product = createProduct('Test Product');
        Invoice__c invoice = createInvoice(
            ownerId,
            invoiceDate,
            TRANSACTION_TYPE_SALE,
            null
        );
        createLineItem(invoice.Id, product.Id);
        return queryInvoiceWithLineItems(invoice.Id);
    }

    public static String getProductUnitOfMeasure() {
        return getFirstActivePicklistValue(Product__c.Unit_of_Measure__c);
    }

    public static String getAlternateProductUnitOfMeasure() {
        List<Schema.PicklistEntry> entries =
            Product__c.Unit_of_Measure__c.getDescribe().getPicklistValues();

        String firstValue;
        for (Schema.PicklistEntry entry : entries) {
            if (!entry.isActive()) {
                continue;
            }
            if (firstValue == null) {
                firstValue = entry.getValue();
                continue;
            }
            if (entry.getValue() != firstValue) {
                return entry.getValue();
            }
        }
        return firstValue;
    }

    public static Invoice__c queryInvoiceWithLineItems(Id invoiceId) {
        return [
            SELECT Id, Name, Invoice_Number__c, Invoice_Date__c,
                Transaction_Type_Sale__c, Transaction_Type_Purchase__c,
                Customer_Name__c, Remarks__c, OwnerId,
                CGST_Amount__c, SGST_Amount__c, IGST_Amount__c,
                CGST__c, SGST__c, IGST__c,
                Taxable_Amount__c, Total_GST__c, Invoice_Total__c,
                Net_Invoice_Amount_c__c, Sub_Total__c, Total_Quantity__c,
                (
                    SELECT Id, Name, Product__c, Quantity__c, Price__c,
                        Discount__c, MRP__c, Tax__c,
                        CGST_Amount__c, SGST_Amount__c, IGST_Amount__c,
                        CGST_Percentage__c, SGST_Percentage__c, IGST_Percentage__c,
                        Sub_Total__c, Total_Amount__c, Unit_Of_Measure__c,
                        Product__r.Name, Product__r.Product_Code__c, Product__r.HSN__c,
                        Product__r.Unit_of_Measure__c, Product__r.Tax_Percentage__c,
                        Product__r.Product_Brand__c, Product__r.Category_Name__c,
                        Product__r.Category_Code__c, Product__r.Rate_Value__c,
                        Product__r.MRP__c, Product__r.Price_Type__c,
                        Product__r.Alternate_UOM__c, Product__r.UOM_Conversion__c,
                        Product__r.Per_Pieces__c, Product__r.Crate_Conversion__c
                    FROM Invoice_Line_Items__r
                )
            FROM Invoice__c
            WHERE Id = :invoiceId
        ];
    }

    public static Invoice__c queryInvoiceHeaderOnly(Id invoiceId) {
        return [
            SELECT Id, Name, Invoice_Number__c, Invoice_Date__c,
                Transaction_Type_Sale__c, Transaction_Type_Purchase__c,
                Customer_Name__c, Remarks__c, OwnerId,
                CGST_Amount__c, SGST_Amount__c, IGST_Amount__c,
                CGST__c, SGST__c, IGST__c,
                Taxable_Amount__c, Total_GST__c, Invoice_Total__c,
                Net_Invoice_Amount_c__c, Sub_Total__c, Total_Quantity__c
            FROM Invoice__c
            WHERE Id = :invoiceId
        ];
    }

    public static Id resolveAllowedOwnerId() {
        Set<Id> allowedUserIds = TallyAllowedUserService.getAllowedUserIds();
        if (!allowedUserIds.isEmpty()) {
            return allowedUserIds.iterator().next();
        }
        return UserInfo.getUserId();
    }

    private static String getFirstActivePicklistValue(Schema.SObjectField fieldToken) {
        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static String buildUniqueInvoiceNumber() {
        return 'INV-TEST-' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }
}