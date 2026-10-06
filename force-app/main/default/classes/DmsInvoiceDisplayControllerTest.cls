@IsTest
private class DmsInvoiceDisplayControllerTest {
    @IsTest
    static void userWithoutDistributorAccountSeesTaxInvoice() {
        System.assertEquals(false, DmsInvoiceDisplayController.isDuplicateInvoice(), 'Users without a flagged distributor account see Tax Invoice');
    }
}