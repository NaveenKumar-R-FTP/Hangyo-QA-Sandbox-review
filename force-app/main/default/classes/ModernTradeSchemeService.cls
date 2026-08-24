/**
 * Modern Trade free-goods scheme.
 *
 * Rule: if an invoice contains one or more of the qualifying "Modern-CP" SKUs (listed in
 * the Modern_Trade_Scheme_Product__mdt custom metadata), the customer gets 1 free piece of
 * "Modern Trade chips" for every 1 qualifying piece purchased (1:1), summed across ALL
 * qualifying line items on the invoice — not per line. Non-qualifying products contribute
 * nothing either way. e.g. 3 qualifying boxes at 12/13/15 pieces each = 40 qualifying
 * pieces = 40 free pieces.
 *
 * To add/remove/change qualifying SKUs, edit the Modern_Trade_Scheme_Product__mdt records
 * in Setup > Custom Metadata Types — no code deploy needed for the SKU list itself.
 *
 * NOTE: matching is done against both Product__r.Product_Code__c and
 * Product__r.Category_Code__c, since it wasn't confirmed which field actually stores the
 * "SAP Code" for this org's Product__c records. If the message isn't appearing for
 * qualifying products, check the Product__c record for the field that actually holds the
 * SAP Code shown in the source spreadsheet and confirm it matches one of those two.
 */
public without sharing class ModernTradeSchemeService {

    private static final String FREE_ITEM_LABEL = 'Modern Trade chips';

    // @TestVisible so tests can inject a known qualifying SKU set directly instead of
    // depending on real Modern_Trade_Scheme_Product__mdt records existing in whatever org
    // the test happens to run in. Custom Metadata rows can't be inserted via test DML, and
    // the actual record count legitimately varies by org/environment (e.g. zero until
    // someone adds the real SKUs in Setup) — coupling tests to that live data made them
    // fail purely based on deployment order, not actual code correctness.
    @TestVisible
    private static Set<String> qualifyingSapCodesCache;

    private static Set<String> getQualifyingSapCodes() {
        if (qualifyingSapCodesCache == null) {
            qualifyingSapCodesCache = new Set<String>();
            for (Modern_Trade_Scheme_Product__mdt rec : [
                SELECT SAP_Code__c FROM Modern_Trade_Scheme_Product__mdt
            ]) {
                if (String.isNotBlank(rec.SAP_Code__c)) {
                    qualifyingSapCodesCache.add(rec.SAP_Code__c.trim());
                }
            }
        }
        return qualifyingSapCodesCache;
    }

    /**
     * @param lineItems Invoice_Line_Item__c records with Quantity__c and
     *                  Product__r.Product_Code__c / Product__r.Category_Code__c populated.
     * @return the bold Free Offer message, or null if the invoice doesn't qualify.
     */
    public static String getFreeOfferMessage(List<Invoice_Line_Item__c> lineItems) {
        Decimal qualifyingQty = getQualifyingQuantity(lineItems);
        if (qualifyingQty <= 0) return null;

        // 1:1 — free pieces equal qualifying pieces, no multiplier.
        Integer freePieces = Integer.valueOf(Math.round(qualifyingQty));
        if (freePieces <= 0) return null;

        return 'Free Offer: You are eligible to receive ' + freePieces + ' pieces of '
             + FREE_ITEM_LABEL + ' free of charge with this purchase. Kindly collect them from distributor.';
    }

    /**
     * LWC-facing entry point. Takes just {productId, quantity} pairs — which every cart /
     * line-item list in every screen already has — instead of requiring full
     * Invoice_Line_Item__c records with Product__r pre-queried. This lets any screen
     * (Counter or Secondary, on-screen cart or saved invoice) recompute the message live
     * as products/quantities change, without threading SAP Code fields through every
     * product DTO in the codebase.
     *
     * @param productQtyJson JSON array like [{"productId":"01t...","quantity":10}, ...]
     */
    @AuraEnabled
    public static String getFreeOfferMessageForProducts(String productQtyJson) {
        if (String.isBlank(productQtyJson)) return null;

        List<ProductQtyWrapper> items = (List<ProductQtyWrapper>) JSON.deserialize(
            productQtyJson, List<ProductQtyWrapper>.class);
        if (items == null || items.isEmpty()) return null;

        Set<Id> productIds = new Set<Id>();
        for (ProductQtyWrapper w : items) {
            if (w.productId != null) productIds.add(w.productId);
        }
        if (productIds.isEmpty()) return null;

        Map<Id, Product__c> productMap = new Map<Id, Product__c>([
            SELECT Id, Product_Code__c, Category_Code__c, Per_Pieces__c
            FROM Product__c
            WHERE Id IN :productIds
        ]);

        List<Invoice_Line_Item__c> pseudoLineItems = new List<Invoice_Line_Item__c>();
        for (ProductQtyWrapper w : items) {
            if (w.productId == null || !productMap.containsKey(w.productId)) continue;
            Invoice_Line_Item__c li = new Invoice_Line_Item__c(
                Quantity__c = w.quantity != null ? w.quantity : 0
            );
            li.Product__r = productMap.get(w.productId);
            pseudoLineItems.add(li);
        }

        return getFreeOfferMessage(pseudoLineItems);
    }

    public class ProductQtyWrapper {
        public Id productId;
        public Decimal quantity;
    }

    /**
     * Exposed separately so LWC-facing Apex controllers can pull just the number if they
     * want to build their own message/formatting instead of using getFreeOfferMessage().
     */
    public static Decimal getQualifyingQuantity(List<Invoice_Line_Item__c> lineItems) {
        if (lineItems == null || lineItems.isEmpty()) return 0;

        Set<String> qualifyingCodes = getQualifyingSapCodes();
        if (qualifyingCodes.isEmpty()) return 0;

        Decimal qualifyingQty = 0;
        for (Invoice_Line_Item__c li : lineItems) {
            String productCode  = li.Product__r != null ? li.Product__r.Product_Code__c : null;
            String categoryCode = li.Product__r != null ? li.Product__r.Category_Code__c : null;
            Boolean matches = (String.isNotBlank(productCode) && qualifyingCodes.contains(productCode.trim()))
                            || (String.isNotBlank(categoryCode) && qualifyingCodes.contains(categoryCode.trim()));
            if (matches) {
                Decimal qty = li.Quantity__c != null ? li.Quantity__c : 0;
                // Quantity__c is in whatever unit was ordered (e.g. boxes), not pieces.
                // Product__r.Per_Pieces__c is "pieces per box" for that product (same field
                // already used for TOD eligibility elsewhere) — multiply through so the
                // scheme is always evaluated in actual pieces, matching the stated rule.
                // Falls back to 1 (i.e. treats Quantity__c as already-pieces) only if
                // Per_Pieces__c is missing/zero, so this can't break for products that
                // haven't had it set up yet.
                Decimal perPieces = (li.Product__r != null && li.Product__r.Per_Pieces__c != null && li.Product__r.Per_Pieces__c > 0)
                                     ? li.Product__r.Per_Pieces__c : 1;
                qualifyingQty += qty * perPieces;
            }
        }
        return qualifyingQty;
    }
}