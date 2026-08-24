public without sharing class SchemeHierarchyTriggerHandler {

    // Only checks duplicates for rows that use the new Scheme_Holder_Type__c-driven
    // levels (Distributor/Region/Hub/Retailer via the bulkAddSchemeHierarchy screen).
    // Rows without Scheme_Holder_Type__c set (the original Account__c/Region__c combo
    // rows, or anything created before this field existed) are left untouched — same
    // "only fires if explicitly set" philosophy as Scheme_Holder_Type_Field_Must_Match.
    public static void validate(List<Scheme_Hierarchy__c> newRecords) {
        Set<Id> schemeIds = new Set<Id>();

        for (Scheme_Hierarchy__c rec : newRecords) {
            if (String.isNotBlank(rec.Scheme_Holder_Type__c) && rec.Scheme__c != null) {
                schemeIds.add(rec.Scheme__c);
            }
        }

        if (schemeIds.isEmpty()) {
            return;
        }

        // Pull ALL existing hierarchy rows for these schemes (siblings), so duplicate
        // checks run against the full set, not just the records being saved.
        Map<Id, List<Scheme_Hierarchy__c>> existingByScheme = new Map<Id, List<Scheme_Hierarchy__c>>();
        for (Scheme_Hierarchy__c s : [
            SELECT Id, Scheme__c, Scheme_Holder_Type__c, Account__c, Region__c, Distributor__c, Hub__c
            FROM Scheme_Hierarchy__c
            WHERE Scheme__c IN :schemeIds
        ]) {
            if (!existingByScheme.containsKey(s.Scheme__c)) {
                existingByScheme.put(s.Scheme__c, new List<Scheme_Hierarchy__c>());
            }
            existingByScheme.get(s.Scheme__c).add(s);
        }

        // Merge: replace any existing record with its incoming (edited) version, add new
        // ones, so duplicate checks run against the post-save picture.
        Map<Id, Map<Id, Scheme_Hierarchy__c>> mergedByScheme = new Map<Id, Map<Id, Scheme_Hierarchy__c>>();
        for (Id schemeId : existingByScheme.keySet()) {
            Map<Id, Scheme_Hierarchy__c> byId = new Map<Id, Scheme_Hierarchy__c>();
            for (Scheme_Hierarchy__c s : existingByScheme.get(schemeId)) {
                byId.put(s.Id, s);
            }
            mergedByScheme.put(schemeId, byId);
        }
        for (Scheme_Hierarchy__c rec : newRecords) {
            if (rec.Scheme__c == null) continue;
            if (!mergedByScheme.containsKey(rec.Scheme__c)) {
                mergedByScheme.put(rec.Scheme__c, new Map<Id, Scheme_Hierarchy__c>());
            }
            mergedByScheme.get(rec.Scheme__c).put(rec.Id, rec);
        }

        for (Scheme_Hierarchy__c incoming : newRecords) {
            if (String.isBlank(incoming.Scheme_Holder_Type__c) || incoming.Scheme__c == null) {
                continue;
            }

            List<Scheme_Hierarchy__c> siblings = mergedByScheme.get(incoming.Scheme__c).values();

            for (Scheme_Hierarchy__c other : siblings) {
                if (other.Id == incoming.Id) continue;
                if (other.Scheme_Holder_Type__c != incoming.Scheme_Holder_Type__c) continue;

                if (incoming.Scheme_Holder_Type__c == 'Distributor'
                    && incoming.Distributor__c != null
                    && other.Distributor__c == incoming.Distributor__c) {
                    incoming.addError('This Distributor is already listed for this scheme.');
                } else if (incoming.Scheme_Holder_Type__c == 'Region'
                    && incoming.Region__c != null
                    && other.Region__c == incoming.Region__c) {
                    incoming.addError('This Region is already listed for this scheme.');
                } else if (incoming.Scheme_Holder_Type__c == 'Hub'
                    && incoming.Hub__c != null
                    && other.Hub__c == incoming.Hub__c) {
                    incoming.addError('This Hub is already listed for this scheme.');
                } else if (incoming.Scheme_Holder_Type__c == 'Retailer'
                    && incoming.Account__c != null
                    && other.Account__c == incoming.Account__c) {
                    incoming.addError('This Retailer is already listed for this scheme.');
                }
            }
        }
    }
}