/**
 * @description Maps Invoice__c SObjects (with line items and Product__r)
 *              into TallyInvoiceResponseWrapper DTOs for the pull API.
 *              Contains no SOQL, REST, or JSON logic.
 */
public with sharing class TallyInvoiceMapper {
    /**
     * @description Converts queried invoices into InvoiceWrapper records.
     * @param invoices Invoice__c records with Invoice_Line_Items__r populated
     * @return Mapped list of InvoiceWrapper instances
     */
    public static List<TallyInvoiceResponseWrapper.InvoiceWrapper> mapInvoices(
        List<Invoice__c> invoices
    ) {
        List<TallyInvoiceResponseWrapper.InvoiceWrapper> mappedInvoices =
            new List<TallyInvoiceResponseWrapper.InvoiceWrapper>();

        if (invoices == null || invoices.isEmpty()) {
            return mappedInvoices;
        }

        for (Invoice__c invoice : invoices) {
            mappedInvoices.add(mapInvoice(invoice));
        }

        return mappedInvoices;
    }

    private static TallyInvoiceResponseWrapper.InvoiceWrapper mapInvoice(Invoice__c invoice) {
        TallyInvoiceResponseWrapper.InvoiceWrapper wrapper =
            new TallyInvoiceResponseWrapper.InvoiceWrapper();

        wrapper.invoiceId = invoice.Id;
        wrapper.voucherNumber = invoice.Name;
        wrapper.invoiceNumber = invoice.Invoice_Number__c;
        wrapper.invoiceDate = invoice.Invoice_Date__c;
        wrapper.voucherDate = invoice.Invoice_Date__c;
        wrapper.voucherType = resolveVoucherType(invoice);
        wrapper.customerName = invoice.Customer_Name__c;
        wrapper.remarks = invoice.Remarks__c;
        wrapper.ownerId = invoice.OwnerId;

        wrapper.cgstAmount = invoice.CGST_Amount__c;
        wrapper.sgstAmount = invoice.SGST_Amount__c;
        wrapper.igstAmount = invoice.IGST_Amount__c;
        wrapper.cgstPercent = invoice.CGST__c;
        wrapper.sgstPercent = invoice.SGST__c;
        wrapper.igstPercent = invoice.IGST__c;

        wrapper.taxableAmount = invoice.Taxable_Amount__c;
        wrapper.totalGst = invoice.Total_GST__c;
        wrapper.invoiceTotal = invoice.Invoice_Total__c;
        wrapper.netInvoiceAmount = invoice.Net_Invoice_Amount_c__c;
        wrapper.subTotal = invoice.Sub_Total__c;
        wrapper.totalQuantity = invoice.Total_Quantity__c;

        wrapper.lineItems = new List<TallyInvoiceResponseWrapper.LineItemWrapper>();

        if (invoice.Invoice_Line_Items__r != null) {
            for (Invoice_Line_Item__c lineItem : invoice.Invoice_Line_Items__r) {
                wrapper.lineItems.add(mapLineItem(lineItem));
            }
        }

        return wrapper;
    }

    private static TallyInvoiceResponseWrapper.LineItemWrapper mapLineItem(
        Invoice_Line_Item__c lineItem
    ) {
        TallyInvoiceResponseWrapper.LineItemWrapper wrapper =
            new TallyInvoiceResponseWrapper.LineItemWrapper();

        wrapper.lineItemId = lineItem.Id;
        wrapper.lineItemName = lineItem.Name;
        wrapper.productId = lineItem.Product__c;

        wrapper.quantity = lineItem.Quantity__c;
        wrapper.rate = lineItem.Price__c;
        wrapper.amount = lineItem.Total_Amount__c;
        wrapper.discount = lineItem.Discount__c;
        wrapper.mrp = lineItem.MRP__c;
        wrapper.tax = lineItem.Tax__c;
        wrapper.cgstAmount = lineItem.CGST_Amount__c;
        wrapper.sgstAmount = lineItem.SGST_Amount__c;
        wrapper.igstAmount = lineItem.IGST_Amount__c;
        wrapper.cgstPercent = lineItem.CGST_Percentage__c;
        wrapper.sgstPercent = lineItem.SGST_Percentage__c;
        wrapper.igstPercent = lineItem.IGST_Percentage__c;
        wrapper.subTotal = lineItem.Sub_Total__c;
        wrapper.totalAmount = lineItem.Total_Amount__c;
        wrapper.unitOfMeasure = lineItem.Unit_Of_Measure__c;

        if (lineItem.Product__r != null) {
            wrapper.productName = lineItem.Product__r.Name;
            wrapper.productCode = lineItem.Product__r.Product_Code__c;
            wrapper.hsn = lineItem.Product__r.HSN__c;
            wrapper.productBrand = lineItem.Product__r.Product_Brand__c;
            wrapper.categoryName = lineItem.Product__r.Category_Name__c;
            wrapper.categoryCode = lineItem.Product__r.Category_Code__c;
            wrapper.priceType = lineItem.Product__r.Price_Type__c;
            wrapper.alternateUom = lineItem.Product__r.Alternate_UOM__c;
            wrapper.uomConversion = lineItem.Product__r.UOM_Conversion__c;
            wrapper.gstPercent = lineItem.Product__r.Tax_Percentage__c;
            wrapper.perPieces = lineItem.Product__r.Per_Pieces__c;
            wrapper.crateConversion = lineItem.Product__r.Crate_Conversion__c;

            if (String.isNotBlank(lineItem.Product__r.Unit_of_Measure__c)) {
                wrapper.unitOfMeasure = lineItem.Product__r.Unit_of_Measure__c;
            }

            if (wrapper.mrp == null) {
                wrapper.mrp = lineItem.Product__r.MRP__c;
            }

            if (wrapper.rate == null) {
                wrapper.rate = lineItem.Product__r.Rate_Value__c;
            }
        }

        return wrapper;
    }

    /**
     * @description Prefer Sale transaction type; fall back to Purchase.
     */
    private static String resolveVoucherType(Invoice__c invoice) {
        if (String.isNotBlank(invoice.Transaction_Type_Sale__c)) {
            return invoice.Transaction_Type_Sale__c;
        }
        return invoice.Transaction_Type_Purchase__c;
    }
}