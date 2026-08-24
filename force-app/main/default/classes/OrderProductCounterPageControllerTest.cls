@isTest
public class OrderProductCounterPageControllerTest {

    @isTest
    static void testGetTaxRates_WithValidSetting() {
        // Insert a mock tax setting record
        Order_tax_value__c setting = new Order_tax_value__c(
            Name = 'General GST Settings',
            SGST__c = 9.0,
            IGST__c = 18.0,
            CGST__c = 9.0
        );
        insert setting;

        Test.startTest();
        Map<String, Decimal> result = OrderProductCounterPageController.getTaxRates('SomeState');
        Test.stopTest();

        System.assertEquals(3, result.size(), 'Should return 3 tax types');
        System.assertEquals(9.0, result.get('SGST'), 'SGST should be 9.0');
        System.assertEquals(9.0, result.get('CGST'), 'CGST should be 9.0');
        System.assertEquals(18.0, result.get('IGST'), 'IGST should be 18.0');
    }

@isTest
static void testGetTaxRates_WithoutSetting() {
    // Do not insert any tax settings to test the else block

    Test.startTest();
    Map<String, Decimal> result = OrderProductCounterPageController.getTaxRates('SomeState');
    Test.stopTest();

    System.assertEquals(3, result.size(), 'Should return 3 default tax types');
    System.assertEquals(0, result.get('SGST'), 'SGST should be 0 by default');
    System.assertEquals(0, result.get('CGST'), 'CGST should be 0 by default');
    System.assertEquals(0, result.get('IGST'), 'IGST should be 0 by default');
}
}