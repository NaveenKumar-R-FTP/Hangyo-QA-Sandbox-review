/**
 * @description Strongly typed JSON response wrappers for the Tally pull-based
 *              Invoice REST API. 
 */
public class TallyInvoiceResponseWrapper {
    public Boolean success;
    public String message;
    public List<InvoiceWrapper> invoices;

    /**
     * @description Invoice header payload mapped from Invoice__c.
     */
    public class InvoiceWrapper {
        public String invoiceId;
        public String voucherNumber;
        public String invoiceNumber;
        public Date invoiceDate;
        public Date voucherDate;
        public String voucherType;
        public String customerName;
        public String remarks;
        public String ownerId;

        public Decimal cgstAmount;
        public Decimal sgstAmount;
        public Decimal igstAmount;
        public Decimal cgstPercent;
        public Decimal sgstPercent;
        public Decimal igstPercent;

        public Decimal taxableAmount;
        public Decimal totalGst;
        public Decimal invoiceTotal;
        public Decimal netInvoiceAmount;
        public Decimal subTotal;
        public Decimal totalQuantity;

        public List<LineItemWrapper> lineItems;
    }

    /**
     * @description Invoice line payload mapped from Invoice_Line_Item__c
     *              and related Product__c fields.
     */
    public class LineItemWrapper {
        public String lineItemId;
        public String lineItemName;
        public String productId;

        public String productName;
        public String productCode;
        public String hsn;
        public String unitOfMeasure;
        public String productBrand;
        public String categoryName;
        public String categoryCode;
        public String priceType;
        public String alternateUom;
        public String uomConversion;

        public Decimal quantity;
        public Decimal rate;
        public Decimal amount;
        public Decimal discount;
        public Decimal mrp;
        public Decimal tax;
        public Decimal gstPercent;
        public Decimal cgstAmount;
        public Decimal sgstAmount;
        public Decimal igstAmount;
        public Decimal cgstPercent;
        public Decimal sgstPercent;
        public Decimal igstPercent;
        public Decimal subTotal;
        public Decimal totalAmount;
        public Decimal perPieces;
        public Decimal crateConversion;
    }
}