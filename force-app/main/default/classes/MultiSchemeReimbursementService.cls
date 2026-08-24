public without sharing class MultiSchemeReimbursementService {

    // ─────────────────────────────────────────────────────────────────────────
    // getAppliedLinesForInvoice — called from the EDIT screen when reopening
    // a draft, so previously-selected schemes can be restored as checked.
    // Returns a map of allocationId -> amount already recorded for this
    // invoice (0 entries if nothing was ever applied).
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static Map<Id, Decimal> getAppliedLinesForInvoice(Id invoiceId) {
        Map<Id, Decimal> result = new Map<Id, Decimal>();
        if (invoiceId == null) {
            return result;
        }
        for (Invoice_Reimbursement_Line__c line : [
            SELECT Retailer_Reimbursement_Scheme__c, Amount_Applied__c
            FROM Invoice_Reimbursement_Line__c
            WHERE Invoice__c = :invoiceId
        ]) {
            if (line.Retailer_Reimbursement_Scheme__c != null) {
                result.put(line.Retailer_Reimbursement_Scheme__c,
                           line.Amount_Applied__c == null ? 0 : line.Amount_Applied__c);
            }
        }
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getActiveSchemes — called from LWC when the invoice screen loads.
    // Returns every Retailer_Reimbursement_Scheme__c allocation for this
    // retailer whose linked Scheme Definition is CURRENTLY within its
    // validity window (today between Start_Date__c and End_Date__c).
    // Expired allocations are silently excluded — the distributor never
    // sees a button for them, no error message needed.
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<ActiveSchemeWrapper> getActiveSchemes(Id retailerAccountId) {
        List<ActiveSchemeWrapper> result = new List<ActiveSchemeWrapper>();
        if (retailerAccountId == null) {
            return result;
        }

        Date today = Date.today();

        List<Retailer_Reimbursement_Scheme__c> allocations = [
            SELECT Id, Balance__c,
                   Scheme_Definition__r.Name,
                   Scheme_Definition__r.Start_Date__c,
                   Scheme_Definition__r.End_Date__c
            FROM Retailer_Reimbursement_Scheme__c
            WHERE Account__c = :retailerAccountId
        ];

        for (Retailer_Reimbursement_Scheme__c alloc : allocations) {
            Date startDate = alloc.Scheme_Definition__r.Start_Date__c;
            Date endDate   = alloc.Scheme_Definition__r.End_Date__c;

            if (startDate == null || endDate == null) {
                continue; // incomplete definition — skip rather than guess
            }
            if (today < startDate || today > endDate) {
                continue; // expired or not yet started — hidden from distributor
            }

            ActiveSchemeWrapper w = new ActiveSchemeWrapper();
            w.allocationId = alloc.Id;
            w.schemeName   = alloc.Scheme_Definition__r.Name;
            w.balance      = alloc.Balance__c == null ? 0 : alloc.Balance__c;
            result.add(w);
        }

        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // saveAppliedLines — called from LWC right after the invoice itself is
    // saved (so we have a real Invoice Id). Replaces whatever lines existed
    // for this invoice with the current selection — safe to call on every
    // save of a Draft, however many times the distributor changes their mind.
    // No balance is touched here — this only records intent.
    //
    // Also maintains Invoice__c.Total_Reimbursement_Applied__c — a plain
    // rollup of every line's Amount_Applied__c, kept in sync here since
    // this is the single place these lines are ever created or changed.
    // (Not a native Roll-Up Summary field, since Invoice__c is a Lookup,
    // not Master-Detail, on Invoice_Reimbursement_Line__c.)
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static void saveAppliedLines(Id invoiceId, String appliedLinesJson) {
        if (invoiceId == null) {
            return;
        }

        List<Invoice_Reimbursement_Line__c> existing = [
            SELECT Id FROM Invoice_Reimbursement_Line__c WHERE Invoice__c = :invoiceId
        ];
        if (!existing.isEmpty()) {
            delete existing;
        }

        Decimal totalApplied = 0;

        if (String.isNotBlank(appliedLinesJson)) {
            List<AppliedLineInput> inputs = (List<AppliedLineInput>) JSON.deserialize(
                appliedLinesJson, List<AppliedLineInput>.class
            );

            List<Invoice_Reimbursement_Line__c> toInsert = new List<Invoice_Reimbursement_Line__c>();
            for (AppliedLineInput inp : inputs) {
                if (inp.allocationId == null || inp.amount == null || inp.amount <= 0) {
                    continue;
                }
                toInsert.add(new Invoice_Reimbursement_Line__c(
                    Invoice__c                       = invoiceId,
                    Retailer_Reimbursement_Scheme__c = inp.allocationId,
                    Amount_Applied__c                = inp.amount
                ));
                totalApplied += inp.amount;
            }

            if (!toInsert.isEmpty()) {
                insert toInsert;
            }
        }

        update new Invoice__c(
            Id = invoiceId,
            Total_Reimbursement_Applied__c = totalApplied
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // applyLinesOnConfirm — called from InvoiceTrigger's before-update block,
    // ONCE per bulk transaction, only for invoices genuinely transitioning
    // into 'Confirmed' for the first time. Reads whatever lines were already
    // persisted (via saveAppliedLines during Draft) and deducts each one's
    // amount from its allocation's real balance — exactly once, here.
    // ─────────────────────────────────────────────────────────────────────────
    public static void applyLinesOnConfirm(Set<Id> invoiceIds) {
        if (invoiceIds == null || invoiceIds.isEmpty()) {
            return;
        }

        List<Invoice_Reimbursement_Line__c> lines = [
            SELECT Id, Amount_Applied__c, Retailer_Reimbursement_Scheme__c
            FROM Invoice_Reimbursement_Line__c
            WHERE Invoice__c IN :invoiceIds
        ];
        if (lines.isEmpty()) {
            return;
        }

        Map<Id, Decimal> deductByAllocation = new Map<Id, Decimal>();
        for (Invoice_Reimbursement_Line__c line : lines) {
            if (line.Retailer_Reimbursement_Scheme__c == null || line.Amount_Applied__c == null) {
                continue;
            }
            Decimal existingAmt = deductByAllocation.containsKey(line.Retailer_Reimbursement_Scheme__c)
                ? deductByAllocation.get(line.Retailer_Reimbursement_Scheme__c)
                : 0;
            deductByAllocation.put(line.Retailer_Reimbursement_Scheme__c, existingAmt + line.Amount_Applied__c);
        }
        if (deductByAllocation.isEmpty()) {
            return;
        }

        List<Retailer_Reimbursement_Scheme__c> allocations = [
            SELECT Id, Balance__c
            FROM Retailer_Reimbursement_Scheme__c
            WHERE Id IN :deductByAllocation.keySet()
        ];

        List<Retailer_Reimbursement_Scheme__c> toUpdate = new List<Retailer_Reimbursement_Scheme__c>();
        for (Retailer_Reimbursement_Scheme__c alloc : allocations) {
            Decimal bal = alloc.Balance__c == null ? 0 : alloc.Balance__c;
            bal -= deductByAllocation.get(alloc.Id);
            if (bal < 0) {
                bal = 0;
            }
            alloc.Balance__c = bal;
            toUpdate.add(alloc);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Wrapper / input classes
    // ─────────────────────────────────────────────────────────────────────────
    public class ActiveSchemeWrapper {
        @AuraEnabled public Id      allocationId;
        @AuraEnabled public String  schemeName;
        @AuraEnabled public Decimal balance;
    }

    public class AppliedLineInput {
        public Id      allocationId;
        public Decimal amount;
    }
}