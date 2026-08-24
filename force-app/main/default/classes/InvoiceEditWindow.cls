public with sharing class InvoiceEditWindow {

    public static final Integer WINDOW_DAYS = 2;

    // Editable when Draft, or Confirmed/Delivered within 2 days of Invoice Date; never when Cancelled.
    public static Boolean isEditable(Invoice__c inv) {
        if (inv == null) return false;
        String st = inv.Status__c;
        if (st == 'Cancelled') return false;
        if (st == 'Draft') return true;
        if (st == 'Confirmed' || st == 'Delivered') {
            if (inv.Invoice_Date__c == null) return true;
            return System.today() <= inv.Invoice_Date__c.addDays(WINDOW_DAYS);
        }
        return false;
    }

    // Cancellable only from Confirmed/Delivered, inside the same 2-day window.
    public static Boolean isCancellable(Invoice__c inv) {
        if (inv == null) return false;
        if (inv.Status__c != 'Confirmed' && inv.Status__c != 'Delivered') return false;
        if (inv.Invoice_Date__c == null) return false;
        return System.today() <= inv.Invoice_Date__c.addDays(WINDOW_DAYS);
    }

    // Server-side gate for LWC save entry points (Phase H).
    public static void assertEditable(Id invoiceId) {
        Invoice__c inv = [SELECT Id, Status__c, Invoice_Date__c FROM Invoice__c WHERE Id = :invoiceId];
        if (!isEditable(inv)) {
            throw new AuraHandledException(
                'This invoice is locked. The 2-day edit window has closed or the invoice is cancelled.');
        }
    }

    // Trigger guard for line-item add / modify / remove.
    public static void enforceLinesEditable(List<Invoice_Line_Item__c> lines) {
        Set<Id> invIds = new Set<Id>();
        for (Invoice_Line_Item__c li : lines) {
            if (li.Invoice__c != null) invIds.add(li.Invoice__c);
        }
        if (invIds.isEmpty()) return;

        Map<Id, Invoice__c> parents = new Map<Id, Invoice__c>([
            SELECT Id, Status__c, Invoice_Date__c FROM Invoice__c WHERE Id IN :invIds
        ]);

        for (Invoice_Line_Item__c li : lines) {
            Invoice__c parent = parents.get(li.Invoice__c);
            if (parent != null && !isEditable(parent)) {
                li.addError('This invoice is locked. The 2-day edit window has closed or the invoice is cancelled, so line items cannot be added, changed, or removed.');
            }
        }
    }
}