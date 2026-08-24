public with sharing class SchemeApplicabilityBulkController {

    public class ProductOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String brand;
    }

    // Typeahead search used by the bulk-add LWC's Product multi-select list.
    // Limited to active products; caps at 50 matches so the picklist stays usable.
    @AuraEnabled(cacheable=true)
    public static List<ProductOption> searchProducts(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        List<ProductOption> options = new List<ProductOption>();
        for (Product__c p : [
            SELECT Id, Name, Product_Brand__c
            FROM Product__c
            WHERE Name LIKE :term AND IsActive__c = true
            ORDER BY Name ASC
            LIMIT 50
        ]) {
            ProductOption opt = new ProductOption();
            opt.id = p.Id;
            opt.name = p.Name;
            opt.brand = p.Product_Brand__c;
            options.add(opt);
        }
        return options;
    }

    // Typeahead search used by the bulk-add LWC's Brand multi-select list.
    // Pulls DISTINCT brand values off existing active Products (via GROUP BY)
    // instead of letting the user free-type a brand name, so we don't end up
    // with near-duplicate brand strings (e.g. "Amul" vs "AMUl ") in Scheme
    // Applicability rows. Brand_Key__c normalization still runs on save as a
    // second line of defense, but this stops the typo at the source.
    @AuraEnabled(cacheable=true)
    public static List<String> searchBrands(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        List<String> brands = new List<String>();
        for (AggregateResult ar : [
            SELECT Product_Brand__c brand
            FROM Product__c
            WHERE Product_Brand__c LIKE :term
              AND Product_Brand__c != null
              AND IsActive__c = true
            GROUP BY Product_Brand__c
            ORDER BY Product_Brand__c ASC
            LIMIT 50
        ]) {
            brands.add((String) ar.get('brand'));
        }
        return brands;
    }

    // Creates one Scheme_Applicability__c row per selected product. Uses
    // Database.insert(allOrNone=false) so a duplicate/validation failure on one
    // product doesn't block the rest from saving — the trigger's duplicate check
    // (SchemeApplicabilityTriggerHandler) still runs per row as normal.
    @AuraEnabled
    public static String createProductRows(Id schemeId, List<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return 'Select at least one product.';
        }
        List<Scheme_Applicability__c> rows = new List<Scheme_Applicability__c>();
        for (Id productId : productIds) {
            rows.add(new Scheme_Applicability__c(
                Scheme__c = schemeId,
                Entity_Type__c = 'Product',
                Product__c = productId
            ));
        }
        return insertRowsAndSummarize(rows);
    }

    // Creates one Scheme_Applicability__c row per selected brand — mirrors
    // createProductRows above so both entity types support multi-select.
    @AuraEnabled
    public static String createBrandRows(Id schemeId, List<String> brands) {
        if (brands == null || brands.isEmpty()) {
            return 'Select at least one brand.';
        }
        List<Scheme_Applicability__c> rows = new List<Scheme_Applicability__c>();
        for (String brand : brands) {
            rows.add(new Scheme_Applicability__c(
                Scheme__c = schemeId,
                Entity_Type__c = 'Brand',
                Product_Brand__c = brand
            ));
        }
        return insertRowsAndSummarize(rows);
    }

    // Returns null on full success. Returns a summary string (partial or total
    // failure) otherwise, so the LWC can show it without throwing and losing the
    // rows that DID save.
    private static String insertRowsAndSummarize(List<Scheme_Applicability__c> rows) {
        Database.SaveResult[] results = Database.insert(rows, false);
        List<String> errors = new List<String>();
        Integer successCount = 0;
        for (Integer i = 0; i < results.size(); i++) {
            Database.SaveResult sr = results[i];
            if (sr.isSuccess()) {
                successCount++;
            } else {
                String label = rows[i].Entity_Type__c == 'Product'
                    ? String.valueOf(rows[i].Product__c)
                    : rows[i].Product_Brand__c;
                for (Database.Error err : sr.getErrors()) {
                    errors.add(label + ': ' + err.getMessage());
                }
            }
        }
        if (errors.isEmpty()) {
            return null;
        }
        String prefix = successCount > 0 ? successCount + ' row(s) saved. ' : 'No rows saved. ';
        return prefix + String.join(errors, ' | ');
    }
}