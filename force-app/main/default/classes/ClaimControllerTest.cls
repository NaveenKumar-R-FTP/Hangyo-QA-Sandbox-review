@isTest
public class ClaimControllerTest {

    @testSetup
    static void setupTestData() {
        // Create test data for Expense Claim
        RecordType rt = [SELECT Id FROM RecordType WHERE DeveloperName = 'DMS_Claims' AND SObjectType = 'Expense_Claim__c' LIMIT 1];

        Expense_Claim__c claim = new Expense_Claim__c(
            Primary_Purchase__c = 1000,
            Secondary_Sales__c = 2000,
            Dealer_Discount__c = 300,
            Product_Complaint__c = 400,
            Outstation_Transport_Support__c = 500,
            Freezer_subsidy_Repairs__c = 600,
            Schemes__c = 700,
            Stall_Rents_Event_Sales_Discounts__c = 800,
            Party_Orders_institutional_Discounts__c = 900,
            Cold_Room_Support__c = 1000,
            Approved_Special_claims_if_any__c = 1100,
            RecordTypeId = rt.Id,
            Name = 'Test Claim'
        );
        insert claim;

        // Create test data for Invoices
        RecordType rtPrimary = [SELECT Id FROM RecordType WHERE Name = 'Primary Invoice' LIMIT 1];
        RecordType rtSecondary = [SELECT Id FROM RecordType WHERE Name = 'Secondary Invoice' LIMIT 1];

        Invoice__c primaryInvoice = new Invoice__c(
            Name = 'Primary Invoice 1',
            Taxable_Amount__c = 500,
            RecordTypeId = rtPrimary.Id
        );
        insert primaryInvoice;

        Invoice__c secondaryInvoice = new Invoice__c(
            Name = 'Secondary Invoice 1',
            CGST_Amount__c = 50,
            SGST_Amount__c = 60,
            IGST_Amount__c = 70,
            Invoice_Amount__c = 1000,
            RecordTypeId = rtSecondary.Id
        );
        insert secondaryInvoice;
    }

    @isTest
    static void testGetFieldHelpTexts() {
        Test.startTest();
        
        List<String> fields = new List<String>{'Primary_Purchase__c', 'Secondary_Sales__c'};
        Map<String, String> result = ClaimController.getFieldHelpTexts('Expense_Claim__c', fields);
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(true, result.containsKey('Primary_Purchase__c'), 'Primary_Purchase__c should exist');
        
        Test.stopTest();
    }

    @isTest
    static void testFetchInvoicesByOrder() {
        Test.startTest();
        
        // Pass valid formattedMonth
        Map<String, Decimal> results = ClaimController.fetchInvoicesByOrder('2024-01');
        System.assert(results.containsKey('primaryPurchase'), 'Primary Purchase should be present');
        System.assert(results.containsKey('secondarySales'), 'Secondary Sales should be present');



        Test.stopTest();
    }

    @isTest
    static void testSaveExpenseClaim() {
        Test.startTest();
        
        String claimDataStr = '{"primaryPurchase":"1000","secondarySales":"2000","dealerDiscount":"100","productComplaint":"200","transportSupport":"300","freezerSubsidy":"400","schemes":"500","eventSalesDiscounts":"600","institutionalDiscounts":"700","coldRoomSupport":"800","approvedSpecialClaims":"900","specialClaimType":"Reliance"}';
         String claimDataStr1 = '{"primaryPurchase":"as",dealerDiscount":"100","productComplaint":"200","transportSupport":"300","freezerSubsidy":"400","schemes":"500","eventSalesDiscounts":"600","institutionalDiscounts":"700","coldRoomSupport":"800","approvedSpecialClaims":"900","specialClaimType":"Reliance"}';
        
        String resultMessage = ClaimController.saveExpenseClaim(claimDataStr);
        System.assertEquals('Claim saved successfully', resultMessage);

        

        Test.stopTest();
    }

    @isTest
    static void testSafeConvertToDecimal() {
        Decimal result1 = ClaimController.safeConvertToDecimal('123.45');
        System.assertEquals(123.45, result1, 'Conversion from string to Decimal failed');

        Decimal result2 = ClaimController.safeConvertToDecimal(null);
        System.assertEquals(0, result2, 'Null value should return 0');

        Decimal result3 = ClaimController.safeConvertToDecimal('invalid');
        System.assertEquals(0, result3, 'Invalid string should return 0');
    }

    @isTest
    static void testGetTypePicklistValues() {
        Test.startTest();
        
        List<String> picklistValues = ClaimController.getTypePicklistValues();
        System.assertNotEquals(null, picklistValues, 'Picklist values should not be null');
        
        Test.stopTest();
    }

}