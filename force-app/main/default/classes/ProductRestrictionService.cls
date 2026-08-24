/**
 * Per-Hub product visibility restriction — a DENY list, not an allow list.
 *
 * By default every distributor sees the full active product catalog, exactly as before
 * this feature existed. Adding a Product_Restriction__c record for a Hub + Product hides
 * that product from every Distributor Account whose Hub__c matches that Hub, everywhere
 * products are listed (Counter, Secondary, Primary, Under-SS, and the customer Portal).
 * Distributors whose Hub has no matching Product_Restriction__c row are completely
 * unaffected — this only ever removes products, it never grants extra access.
 *
 * Restrictions are keyed by Hub (Account.Hub__c), not by an individual Distributor Account,
 * so one row denies a product for every distributor sharing that Hub at once.
 *
 * Usage in a product-listing query:
 *   Set<Id> denied = ProductRestrictionService.getDeniedProductIds(distributorAccountId);
 *   ... WHERE Id NOT IN :denied ...   (skip the clause entirely if denied is empty)
 */
public without sharing class ProductRestrictionService {

    // Cache: Distributor Account Id -> its Hub__c value (avoids repeated SOQL per call in a transaction).
    private static Map<Id, String> hubByAccountCache = new Map<Id, String>();

    // Cache: Hub__c value -> denied Product Ids for that Hub.
    private static Map<String, Set<Id>> deniedProductIdsByHubCache = new Map<String, Set<Id>>();

    /**
     * @param distributorAccountId The Distributor Account (the account tied to the
     *                              currently logged-in DMS/portal user) to check.
     * @return Set of Product__c Ids that should be hidden from this distributor's Hub. Empty
     *         set (never null) if there are no restrictions for their Hub, or if the account
     *         has no Hub__c value set.
     */
    public static Set<Id> getDeniedProductIds(Id distributorAccountId) {
        if (distributorAccountId == null) return new Set<Id>();

        String hub = getHubForAccount(distributorAccountId);
        if (String.isBlank(hub)) return new Set<Id>();

        if (!deniedProductIdsByHubCache.containsKey(hub)) {
            Set<Id> denied = new Set<Id>();
            for (Product_Restriction__c pr : [
                SELECT Product__c
                FROM Product_Restriction__c
                WHERE Hub__c = :hub
                AND Product__c != null
            ]) {
                denied.add(pr.Product__c);
            }
            deniedProductIdsByHubCache.put(hub, denied);
        }
        return deniedProductIdsByHubCache.get(hub);
    }

    /**
     * Convenience filter for callers that already have a list of products in hand and just
     * want the denied ones stripped out, rather than adding a NOT IN clause to their SOQL.
     */
    public static List<Product__c> filterOutDeniedProducts(List<Product__c> products, Id distributorAccountId) {
        if (products == null || products.isEmpty()) return products;
        Set<Id> denied = getDeniedProductIds(distributorAccountId);
        if (denied.isEmpty()) return products;

        List<Product__c> allowed = new List<Product__c>();
        for (Product__c p : products) {
            if (!denied.contains(p.Id)) allowed.add(p);
        }
        return allowed;
    }

    private static String getHubForAccount(Id accountId) {
        if (!hubByAccountCache.containsKey(accountId)) {
            String hub = null;
            List<Account> accs = [SELECT Hub__c FROM Account WHERE Id = :accountId LIMIT 1];
            if (!accs.isEmpty()) {
                hub = accs[0].Hub__c;
            }
            hubByAccountCache.put(accountId, hub);
        }
        return hubByAccountCache.get(accountId);
    }
}