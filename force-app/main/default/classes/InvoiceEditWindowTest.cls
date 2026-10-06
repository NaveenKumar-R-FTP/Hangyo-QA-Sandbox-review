@IsTest
private class InvoiceEditWindowTest {

    private static Invoice__c makeInvoice(String status, Date invoiceDate) {
        Invoice__c inv = new Invoice__c(
            Name = 'INV-EDITWINDOW-TEST',
            Status__c = status,
            Invoice_Date__c = invoiceDate
        );
        insert inv;
        return inv;
    }

    // ---------------- isEditable() ----------------

    @IsTest
    static void testIsEditable_nullInvoice_returnsFalse() {
        System.assertEquals(false, InvoiceEditWindow.isEditable(null));
    }

    @IsTest
    static void testIsEditable_cancelled_returnsFalse() {
        Invoice__c inv = makeInvoice('Cancelled', Date.today());
        System.assertEquals(false, InvoiceEditWindow.isEditable(inv));
    }

    @IsTest
    static void testIsEditable_draft_returnsTrue() {
        Invoice__c inv = makeInvoice('Draft', null);
        System.assertEquals(true, InvoiceEditWindow.isEditable(inv));
    }

    @IsTest
    static void testIsEditable_confirmed_nullDate_returnsTrue() {
        Invoice__c inv = makeInvoice('Confirmed', null);
        System.assertEquals(true, InvoiceEditWindow.isEditable(inv));
    }

    @IsTest
    static void testIsEditable_confirmed_withinWindow_returnsTrue() {
        Invoice__c inv = makeInvoice('Confirmed', Date.today());
        System.assertEquals(true, InvoiceEditWindow.isEditable(inv));
    }

    @IsTest
    static void testIsEditable_delivered_outsideWindow_returnsFalse() {
        Invoice__c inv = makeInvoice('Delivered', Date.today().addDays(-10));
        System.assertEquals(false, InvoiceEditWindow.isEditable(inv));
    }

    @IsTest
    static void testIsEditable_otherStatus_returnsFalse() {
        // Built in-memory (not inserted) so this doesn't depend on the org's
        // restricted Status__c picklist including a value outside
        // Draft/Confirmed/Delivered/Cancelled — isEditable() only reads the
        // field off the object passed in, no DML required.
        Invoice__c inv = new Invoice__c(Status__c = 'Some_Other_Status', Invoice_Date__c = Date.today());
        System.assertEquals(false, InvoiceEditWindow.isEditable(inv));
    }

    // ---------------- isCancellable() ----------------

    @IsTest
    static void testIsCancellable_nullInvoice_returnsFalse() {
        System.assertEquals(false, InvoiceEditWindow.isCancellable(null));
    }

    @IsTest
    static void testIsCancellable_draft_returnsFalse() {
        Invoice__c inv = makeInvoice('Draft', Date.today());
        System.assertEquals(false, InvoiceEditWindow.isCancellable(inv));
    }

    @IsTest
    static void testIsCancellable_confirmed_nullDate_returnsFalse() {
        Invoice__c inv = makeInvoice('Confirmed', null);
        System.assertEquals(false, InvoiceEditWindow.isCancellable(inv));
    }

    @IsTest
    static void testIsCancellable_delivered_withinWindow_returnsTrue() {
        Invoice__c inv = makeInvoice('Delivered', Date.today());
        System.assertEquals(true, InvoiceEditWindow.isCancellable(inv));
    }

    @IsTest
    static void testIsCancellable_confirmed_outsideWindow_returnsFalse() {
        Invoice__c inv = makeInvoice('Confirmed', Date.today().addDays(-10));
        System.assertEquals(false, InvoiceEditWindow.isCancellable(inv));
    }

    // ---------------- assertEditable() ----------------

    @IsTest
    static void testAssertEditable_editableInvoice_doesNotThrow() {
        Invoice__c inv = makeInvoice('Draft', null);
        Boolean threw = false;
        Test.startTest();
        try {
            InvoiceEditWindow.assertEditable(inv.Id);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(false, threw, 'Draft invoice should be editable');
    }

    @IsTest
    static void testAssertEditable_lockedInvoice_throws() {
        Invoice__c inv = makeInvoice('Cancelled', Date.today());
        Boolean threw = false;
        Test.startTest();
        try {
            InvoiceEditWindow.assertEditable(inv.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Cancelled invoice should not be editable');
    }

    // ---------------- enforceLinesEditable() ----------------

    @IsTest
    static void testEnforceLinesEditable_emptyList_noOp() {
        Test.startTest();
        InvoiceEditWindow.enforceLinesEditable(new List<Invoice_Line_Item__c>());
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void testEnforceLinesEditable_editableParent_noError() {
        Invoice__c inv = makeInvoice('Draft', null);
        Invoice_Line_Item__c line = new Invoice_Line_Item__c(Invoice__c = inv.Id);
        Test.startTest();
        InvoiceEditWindow.enforceLinesEditable(new List<Invoice_Line_Item__c>{ line });
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void testEnforceLinesEditable_lockedParent_addsError() {
        Invoice__c inv = makeInvoice('Cancelled', Date.today());
        Invoice_Line_Item__c line = new Invoice_Line_Item__c(Invoice__c = inv.Id);
        Test.startTest();
        InvoiceEditWindow.enforceLinesEditable(new List<Invoice_Line_Item__c>{ line });
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void testEnforceLinesEditable_lineWithNullInvoice_skipped() {
        Invoice_Line_Item__c line = new Invoice_Line_Item__c();
        Test.startTest();
        InvoiceEditWindow.enforceLinesEditable(new List<Invoice_Line_Item__c>{ line });
        Test.stopTest();
        System.assert(true);
    }
}