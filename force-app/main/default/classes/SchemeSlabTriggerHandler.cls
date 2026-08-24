public without sharing class SchemeSlabTriggerHandler {

    public static void validateSlabs(List<Scheme_Slab__c> newSlabs) {
        Set<Id> schemeIds = new Set<Id>();
        for (Scheme_Slab__c s : newSlabs) {
            if (s.Scheme__c != null) {
                schemeIds.add(s.Scheme__c);
            }
        }
        if (schemeIds.isEmpty()) {
            return;
        }

        // Pull the parent Scheme's Discount_Mode__c
        Map<Id, Scheme__c> schemesById = new Map<Id, Scheme__c>(
            [SELECT Id, Discount_Mode__c FROM Scheme__c WHERE Id IN :schemeIds]
        );

        // Pull ALL existing slabs for these schemes (siblings), so the check
        // is against the full slab set, not just the records being saved.
        Map<Id, List<Scheme_Slab__c>> existingSlabsByScheme = new Map<Id, List<Scheme_Slab__c>>();
        for (Scheme_Slab__c s : [
            SELECT Id, Scheme__c, For_Amount__c, Cash_Discount__c, Discount_Percent__c
            FROM Scheme_Slab__c
            WHERE Scheme__c IN :schemeIds
        ]) {
            if (!existingSlabsByScheme.containsKey(s.Scheme__c)) {
                existingSlabsByScheme.put(s.Scheme__c, new List<Scheme_Slab__c>());
            }
            existingSlabsByScheme.get(s.Scheme__c).add(s);
        }

        // Merge: replace any existing record with its incoming (edited) version,
        // and add new ones, so we validate against the post-save picture.
        Map<Id, Map<Id, Scheme_Slab__c>> mergedByScheme = new Map<Id, Map<Id, Scheme_Slab__c>>();
        for (Id schemeId : existingSlabsByScheme.keySet()) {
            Map<Id, Scheme_Slab__c> byId = new Map<Id, Scheme_Slab__c>();
            for (Scheme_Slab__c s : existingSlabsByScheme.get(schemeId)) {
                byId.put(s.Id, s);
            }
            mergedByScheme.put(schemeId, byId);
        }
        for (Scheme_Slab__c s : newSlabs) {
            if (s.Scheme__c == null) continue;
            if (!mergedByScheme.containsKey(s.Scheme__c)) {
                mergedByScheme.put(s.Scheme__c, new Map<Id, Scheme_Slab__c>());
            }
            // s.Id is null for new records — Map handles that as a distinct key fine
            mergedByScheme.get(s.Scheme__c).put(s.Id, s);
        }

        for (Scheme_Slab__c incoming : newSlabs) {
            if (incoming.Scheme__c == null) continue;

            Scheme__c parentScheme = schemesById.get(incoming.Scheme__c);
            String mode = parentScheme != null ? parentScheme.Discount_Mode__c : null;

            // Rule: populated discount field must match parent's Discount_Mode__c
            if (mode == 'Percentage' && incoming.Cash_Discount__c != null) {
                incoming.addError('This scheme is set to Percentage mode — enter Discount Percent, not Cash Discount.');
            }
            if (mode == 'Cash Discount' && incoming.Discount_Percent__c != null) {
                incoming.addError('This scheme is set to Cash Discount mode — enter Cash Discount, not Discount Percent.');
            }

            List<Scheme_Slab__c> siblings = mergedByScheme.get(incoming.Scheme__c).values();

            // Rule: no duplicate For_Amount__c within the scheme
            for (Scheme_Slab__c other : siblings) {
                if (other.Id == incoming.Id) continue;
                if (other.For_Amount__c != null && incoming.For_Amount__c != null
                    && other.For_Amount__c == incoming.For_Amount__c) {
                    incoming.addError('Another slab on this scheme already uses this For Amount.');
                }
            }

            // Rule: discount must be strictly ascending with For_Amount__c
            for (Scheme_Slab__c other : siblings) {
                if (other.Id == incoming.Id) continue;
                if (other.For_Amount__c == null || incoming.For_Amount__c == null) continue;

                Decimal otherDiscount = other.Discount_Percent__c != null ? other.Discount_Percent__c : other.Cash_Discount__c;
                Decimal thisDiscount  = incoming.Discount_Percent__c != null ? incoming.Discount_Percent__c : incoming.Cash_Discount__c;
                if (otherDiscount == null || thisDiscount == null) continue;

                if (other.For_Amount__c < incoming.For_Amount__c && otherDiscount >= thisDiscount) {
                    incoming.addError('A slab with a lower For Amount must not have an equal or higher discount than this slab.');
                }
                if (other.For_Amount__c > incoming.For_Amount__c && otherDiscount <= thisDiscount) {
                    incoming.addError('A slab with a higher For Amount must have a higher discount than this slab.');
                }
            }
        }
    }
}