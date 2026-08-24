public class QuantitySchemeModalWrapper {

    @AuraEnabled public Id      schemeId;
    @AuraEnabled public String  schemeName;

    @AuraEnabled public Decimal minQty;
    @AuraEnabled public Decimal promoQty;

    @AuraEnabled public Decimal discountPercentage;
    @AuraEnabled public String  schemeType;

    @AuraEnabled public String  displayMessage;
    @AuraEnabled public Boolean isEligible;

    public QuantitySchemeModalWrapper() {
        this.isEligible = false;
        this.displayMessage = '';
    }

   /* public void evaluateEligibility(Decimal selectedQty) {
        if (selectedQty == null || minQty == null) {
            isEligible = false;
            displayMessage = '';
            return;
        }

        if (selectedQty >= minQty) {
            isEligible = true;
            if (promoQty != null && promoQty > 0) {
                displayMessage = 'Eligible for ' + promoQty + ' promotional quantity';
            } else if (discountPercentage != null && discountPercentage > 0) {
                displayMessage = 'Eligible for ' + discountPercentage + '% discount';
            } else {
                displayMessage = 'Scheme applicable';
            }
        } else {
            isEligible = false;
            displayMessage =
                'Add ' + (minQty - selectedQty) + ' more qty to unlock this scheme';
        }
    }*/
}