// Simple display wrapper for a "Purchase Quantity Discount" scheme applied to an
// invoice — one instance per distinct scheme (not per line item), showing the scheme
// name, its discount %, and the total rupee amount saved across every line item on the
// invoice that used that scheme. Built by SchemeEvaluationService.getAppliedQuantityDiscountSchemes()
// and consumed by every PDF controller that lists invoice line items (SecondaryInvoicePdfController,
// SecondaryInvoiceDownloaderCtl, DeliveryPlanInvoiceController).
public class AppliedSchemeDisplay {
    public String schemeName { get; set; }
    public Decimal discountPercent { get; set; }
    public Decimal discountAmount { get; set; }
}