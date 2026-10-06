public without sharing class InvoiceCancellationService {
    // R2 Phase E: lets same-transaction roll-up updates (e.g. the Collection roll-up that fires
    // from the reversal insert) touch a Cancelled invoice without tripping the finality guard.
    public static Boolean bypassCancelledGuard = false;
    // R2 Issue 2: true ONLY while a genuine Cancel-Invoice-button cancellation runs, so the
    // trigger can tell it apart from a Lightning Path / manual status change to Cancelled.
    public static Boolean cancelInitiatedByButton = false;

    // R2 Phase E: when an invoice is cancelled, reverse its collections by inserting a
    // mirrored NEGATIVE Collection__c for each original payment. Nets the customer ledger
    // to zero and preserves full audit history (nothing is deleted). Fires once, because
    // Cancelled is terminal (the trigger blocks any change out of Cancelled).
    public static void reverseCollectionsOnCancel(List<Invoice__c> newList, Map<Id, Invoice__c> oldMap) {
        if (newList == null || oldMap == null) return;

        Set<Id> cancelledInvIds = new Set<Id>();
        for (Invoice__c inv : newList) {
            Invoice__c oldInv = oldMap.get(inv.Id);
            if (oldInv == null) continue;
            if (inv.Status__c == 'Cancelled' && oldInv.Status__c != 'Cancelled') {
                cancelledInvIds.add(inv.Id);
            }
        }
        if (cancelledInvIds.isEmpty()) return;

        // Only reverse real (positive) payments; skip any prior reversal entries.
        List<Collection__c> originals = [
            SELECT Id, Invoice__c, Amount_Collected__c, Credit_Amount_Used__c, Payment_Method__c
            FROM Collection__c
            WHERE Invoice__c IN :cancelledInvIds
            AND Amount_Collected__c > 0
        ];
        if (originals.isEmpty()) return;

        List<Collection__c> reversals = new List<Collection__c>();
        for (Collection__c c : originals) {
            Collection__c rev = new Collection__c();
            rev.Invoice__c            = c.Invoice__c;
            rev.Amount_Collected__c   = (c.Amount_Collected__c != null) ? -c.Amount_Collected__c : 0;
            rev.Credit_Amount_Used__c = (c.Credit_Amount_Used__c != null) ? -c.Credit_Amount_Used__c : null;
            rev.Payment_Method__c     = c.Payment_Method__c;
            rev.Payment_Date__c       = Date.today();
            rev.Narration__c          = 'Reversal - invoice cancelled (Ref: ' + c.Id + ')';
            reversals.add(rev);
        }
                        if (!reversals.isEmpty()) {
            bypassCancelledGuard = true;
            try {
                insert reversals;
            } finally {
                bypassCancelledGuard = false;
            }
        }
    }

    // R2 Phase H: LWC entry point. Sets status to Cancelled; the InvoiceTrigger enforces
    // the window/finality guard and performs stock restore + collection reversal. Any guard
    // failure surfaces back to the screen as the addError message.
    @AuraEnabled
    public static void cancelInvoice(Id invoiceId) {
        if (invoiceId == null) {
            throw buildError('No invoice specified to cancel.');
        }
        Invoice__c inv = [SELECT Id, Status__c, Invoice_Date__c, IRN_Number__c FROM Invoice__c WHERE Id = :invoiceId LIMIT 1];
                if (inv.Status__c == 'Cancelled') {
            throw buildError('This invoice is already cancelled.');
        }
        // R3: once the Under SS distributor has completed the GRN (any Good_receipt_notes__c
        // record linked to this invoice), the Super Stockist can no longer cancel it.
               // Check the GRN via InvoiceEditWindow.hasCompletedGRN (line-item based) so the block also
        // works for the Super Stockist community user, who can't read the Good_receipt_notes__c object.
        if (InvoiceEditWindow.hasCompletedGRN(invoiceId)) {
            throw buildError('The Under SS distributor has already completed the GRN for this invoice, so it can no longer be cancelled.');
        }
                inv.Status__c = 'Cancelled';
        cancelInitiatedByButton = true;
        try {
            update inv;
        } catch (DmlException e) {
            throw buildError(e.getNumDml() > 0 ? e.getDmlMessage(0) : e.getMessage());
        } finally {
            cancelInitiatedByButton = false;
        }
    }

        // R2: when an invoice is cancelled, revert its related Order back to 'Order Placed'.
    public static void revertOrdersOnCancel(List<Invoice__c> newList, Map<Id, Invoice__c> oldMap) {
        if (newList == null || oldMap == null) return;
        Set<Id> orderIds = new Set<Id>();
        for (Invoice__c inv : newList) {
            Invoice__c oldInv = oldMap.get(inv.Id);
            if (oldInv == null) continue;
            if (inv.Status__c == 'Cancelled' && oldInv.Status__c != 'Cancelled' && inv.Order__c != null) {
                orderIds.add(inv.Order__c);
            }
        }
        if (orderIds.isEmpty()) return;
        List<Order__c> ordersToUpdate = new List<Order__c>();
        for (Id oId : orderIds) {
            ordersToUpdate.add(new Order__c(Id = oId, Status__c = 'Order Placed'));
        }
                update ordersToUpdate;
    }

    // R2 Issue 5: when an invoice is cancelled, release any Retailer Reimbursement it consumed.
    // Balance is now a DERIVED value (Initial minus the sum of Amount_Applied__c on Confirmed/
    // Delivered invoices), so once these invoices are Cancelled their lines no longer count and
    // recomputing each affected allocation restores exactly what was released — no incremental
    // add-back that could drift out of sync with the lines. This runs after-update (status change
    // committed) and fires once, because Cancelled is terminal. Value Schemes are computed
    // discounts with no shared budget pool, so there is nothing to reverse there today.
    public static void reverseReimbursementsOnCancel(List<Invoice__c> newList, Map<Id, Invoice__c> oldMap) {
        if (newList == null || oldMap == null) return;

        Set<Id> cancelledInvIds = new Set<Id>();
        for (Invoice__c inv : newList) {
            Invoice__c oldInv = oldMap.get(inv.Id);
            if (oldInv == null) continue;
            if (inv.Status__c == 'Cancelled' && oldInv.Status__c != 'Cancelled') {
                cancelledInvIds.add(inv.Id);
            }
        }
        if (cancelledInvIds.isEmpty()) return;

        Set<Id> affectedAllocations = new Set<Id>();
        for (Invoice_Reimbursement_Line__c line : [
            SELECT Retailer_Reimbursement_Scheme__c
            FROM Invoice_Reimbursement_Line__c
            WHERE Invoice__c IN :cancelledInvIds
        ]) {
            if (line.Retailer_Reimbursement_Scheme__c != null) {
                affectedAllocations.add(line.Retailer_Reimbursement_Scheme__c);
            }
        }
        if (affectedAllocations.isEmpty()) return;

        MultiSchemeReimbursementService.recomputeBalances(affectedAllocations);
    }

    private static AuraHandledException buildError(String msg) {
        AuraHandledException ex = new AuraHandledException(msg);
        ex.setMessage(msg);
        return ex;
    }
}