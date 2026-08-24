public with sharing class OrderProductCounterPageController {
    //This method is to getTaxRates
    @AuraEnabled(cacheable=true)
    public static Map<String, Decimal> getTaxRates(String state) {
        
        // Retrieve tax rates from the custom setting based on the state
        Map<String, Decimal> taxRates = new Map<String, Decimal>();
        List<Order_tax_value__c> settings = [SELECT Name, SGST__c, IGST__c, CGST__c 
                                             FROM Order_tax_value__c 
                                             WHERE Name = 'General GST Settings' 
                                             LIMIT 1];
        
        if (!settings.isEmpty()) {
            Order_tax_value__c taxSetting = settings[0];
            taxRates.put('CGST', taxSetting.CGST__c);
            taxRates.put('SGST', taxSetting.SGST__c);
            taxRates.put('IGST', taxSetting.IGST__c);
        } else {
            taxRates.put('IGST', 0);
            taxRates.put('CGST', 0);
            taxRates.put('SGST', 0);
        }
        
        return taxRates;   
        
        
    }
}