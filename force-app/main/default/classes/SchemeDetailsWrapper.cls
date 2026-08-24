public class SchemeDetailsWrapper {
    @AuraEnabled
        public String id { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public Boolean isMatchExist { get; set; }
        @AuraEnabled
        public Boolean isApplied { get; set; }
        @AuraEnabled public Decimal promoQty;

        public SchemeDetailsWrapper(String id, String name, Boolean isMatchExist, Boolean isApplied, Decimal promoQty) {
            this.id = id;
            this.name = name;
            this.isMatchExist = isMatchExist;
            this.isApplied = isApplied;
            this.promoQty = promoQty;
        }

}