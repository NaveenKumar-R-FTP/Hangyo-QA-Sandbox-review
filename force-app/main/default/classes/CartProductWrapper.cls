public class CartProductWrapper {
    @TestVisible
    public class ProductWrapper{
        @AuraEnabled public String productId{get;set;}
        @AuraEnabled public List<String> customURL{get;set;}
        @AuraEnabled public String productImage{get;set;}
        @AuraEnabled public String productBrand{get;set;}
        @AuraEnabled public Integer quantity{get;set;}
        @AuraEnabled public Integer price{get;set;}
        @AuraEnabled public String productFullName{get;set;}
        @AuraEnabled public Boolean cutomImagesData{get;set;}
        @AuraEnabled public decimal productListPrice{get;set;}
        @AuraEnabled public decimal productOfferPrice{get;set;}
        @AuraEnabled public String sellebleSKU {get;set;}
        @AuraEnabled public Boolean isHidePrice {get;set;}
        @AuraEnabled public Boolean isBlankListPrice {get;set;}
        @AuraEnabled public Boolean isBlankOfferPrice {get;set;}
        @AuraEnabled public Boolean lastImage {get;set;}
        @AuraEnabled public String selectedScheme {get;set;}
        @AuraEnabled public String selectedSchemeId {get;set;}
        /* ================= 🔥 NEW REQUIRED FIELDS ================= */

        @AuraEnabled public Boolean isPromotional { get; set; }
        @AuraEnabled public String parentProductId { get; set; }
        @AuraEnabled public Decimal discountPercentage { get; set; }
        @AuraEnabled public Boolean isReadOnly { get; set; }
        @AuraEnabled public Integer sortOrder;
        @AuraEnabled public String promoType;          
		@AuraEnabled public Id promoProductId; 
        @AuraEnabled Public Decimal unittotalPrice;
        @AuraEnabled Public String productName;
        // ✅ ADD THESE (already used by UI)
        @AuraEnabled public String prodmeasure { get; set; }
        @AuraEnabled public Integer availableStockQuantity { get; set; }
        @AuraEnabled public String productIdForCart { get; set; }
        @AuraEnabled public Decimal promoMinQty { get; set; }
        @AuraEnabled public String hsn { get; set; }
        @AuraEnabled public Decimal mrp { get; set; }
         @AuraEnabled public Boolean isFreePromo { get; set; }
        
    }
}