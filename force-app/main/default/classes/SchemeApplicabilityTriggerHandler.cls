public without sharing class SchemeApplicabilityTriggerHandler {

    public static void normalizeAndValidate(List<Scheme_Applicability__c> newRecords) {
        Set<Id> schemeIds = new Set<Id>();

        for (Scheme_Applicability__c rec : newRecords) {
            // Normalise Brand_Key__c so "AMUL", "Amul ", " amul" all match the same
            // brand at evaluation time. Only meaningful for Entity_Type__c = 'Brand' —
            // cleared for Product rows so a leftover value can't accidentally match.
            if (rec.Entity_Type__c == 'Brand' && String.isNotBlank(rec.Product_Brand__c)) {
                rec.Brand_Key__c = normalizeBrand(rec.Product_Brand__c);
            } else {
                rec.Brand_Key__c = null;
            }

            if (rec.Scheme__c != null) {
                schemeIds.add(rec.Scheme__c);
            }
        }

        if (schemeIds.isEmpty()) {
            return;
        }

        // Pull ALL existing applicability rows for these schemes (siblings), so
        // duplicate checks run against the full set, not just the records being saved.
        Map<Id, List<Scheme_Applicability__c>> existingByScheme = new Map<Id, List<Scheme_Applicability__c>>();
        for (Scheme_Applicability__c s : [
            SELECT Id, Scheme__c, Entity_Type__c, Product__c, Brand_Key__c
            FROM Scheme_Applicability__c
            WHERE Scheme__c IN :schemeIds
        ]) {
            if (!existingByScheme.containsKey(s.Scheme__c)) {
                existingByScheme.put(s.Scheme__c, new List<Scheme_Applicability__c>());
            }
            existingByScheme.get(s.Scheme__c).add(s);
        }

        // Merge: replace any existing record with its incoming (edited) version, add new
        // ones, so duplicate checks run against the post-save picture.
        Map<Id, Map<Id, Scheme_Applicability__c>> mergedByScheme = new Map<Id, Map<Id, Scheme_Applicability__c>>();
        for (Id schemeId : existingByScheme.keySet()) {
            Map<Id, Scheme_Applicability__c> byId = new Map<Id, Scheme_Applicability__c>();
            for (Scheme_Applicability__c s : existingByScheme.get(schemeId)) {
                byId.put(s.Id, s);
            }
            mergedByScheme.put(schemeId, byId);
        }
        for (Scheme_Applicability__c rec : newRecords) {
            if (rec.Scheme__c == null) continue;
            if (!mergedByScheme.containsKey(rec.Scheme__c)) {
                mergedByScheme.put(rec.Scheme__c, new Map<Id, Scheme_Applicability__c>());
            }
            mergedByScheme.get(rec.Scheme__c).put(rec.Id, rec);
        }

        for (Scheme_Applicability__c incoming : newRecords) {
            if (incoming.Scheme__c == null) continue;

            List<Scheme_Applicability__c> siblings = mergedByScheme.get(incoming.Scheme__c).values();

            for (Scheme_Applicability__c other : siblings) {
                if (other.Id == incoming.Id) continue;

                if (incoming.Product__c != null && other.Product__c == incoming.Product__c) {
                    incoming.addError('This Product is already listed for this scheme.');
                }
                if (incoming.Brand_Key__c != null && other.Brand_Key__c == incoming.Brand_Key__c) {
                    incoming.addError('This Product Brand is already listed for this scheme.');
                }
            }
        }
    }

    private static String normalizeBrand(String rawBrand) {
        return rawBrand.trim().toUpperCase().replaceAll('\\s+', ' ');
    }
}