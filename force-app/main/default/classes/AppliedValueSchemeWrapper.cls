public class AppliedValueSchemeWrapper {
        @AuraEnabled
        public Decimal discountAmount { get; set; }
        @AuraEnabled
        public Decimal discountPercentage { get; set; }
        @AuraEnabled
        public String freeProductId { get; set; }
        @AuraEnabled
        public String schemeType { get; set; }
        @AuraEnabled public Decimal promoQty;
        @AuraEnabled public Decimal cartAmount;
        // The pre-tax subtotal the discount % (or slab selection) was actually computed
        // against — the FULL cart total for schemes with no Scheme_Applicability__c rows,
        // or just the matched Product/Brand lines' subtotal for scoped Flat Discount
        // schemes. Callers must multiply discountPercentage against THIS value, not the
        // whole cart, or a scoped scheme's % discount leaks onto non-matching SKUs. See
        // decision log, 2026-08-21.
        @AuraEnabled public Decimal qualifyingSubtotal;
}