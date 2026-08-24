/**
 * @description Queries Invoice__c records (with line items and related Product__c)
 *              for the Tally pull-based REST API. Contains no mapping or REST logic.
 */
public with sharing class TallyInvoiceQueryService {
    /**
     * @description Fetches invoices owned by the allowed users, optionally filtered by date.
     * @param allowedUserIds Owner Ids permitted for Tally data access
     * @param fromDate Optional inclusive start date on Invoice_Date__c
     * @param toDate Optional inclusive end date on Invoice_Date__c
     * @return Matching Invoice__c records with Invoice_Line_Items__r and Product__r populated
     */
    public static List<Invoice__c> getInvoices(
        Set<Id> allowedUserIds,
        Date fromDate,
        Date toDate
    ) {
        if (allowedUserIds == null || allowedUserIds.isEmpty()) {
            return new List<Invoice__c>();
        }

        String soql =
            'SELECT Id, Name, Invoice_Number__c, Invoice_Date__c, ' +
            'Transaction_Type_Sale__c, Transaction_Type_Purchase__c, ' +
            'Customer_Name__c, Remarks__c, OwnerId, ' +
            'CGST_Amount__c, SGST_Amount__c, IGST_Amount__c, ' +
            'CGST__c, SGST__c, IGST__c, ' +
            'Taxable_Amount__c, Total_GST__c, Invoice_Total__c, ' +
            'Net_Invoice_Amount_c__c, Sub_Total__c, Total_Quantity__c, ' +
            '(SELECT Id, Name, Product__c, Quantity__c, Price__c, ' +
            'Discount__c, MRP__c, Tax__c, ' +
            'CGST_Amount__c, SGST_Amount__c, IGST_Amount__c, ' +
            'CGST_Percentage__c, SGST_Percentage__c, IGST_Percentage__c, ' +
            'Sub_Total__c, Total_Amount__c, Unit_Of_Measure__c, ' +
            'Product__r.Name, Product__r.Product_Code__c, Product__r.HSN__c, ' +
            'Product__r.Unit_of_Measure__c, Product__r.Tax_Percentage__c, ' +
            'Product__r.Product_Brand__c, Product__r.Category_Name__c, ' +
            'Product__r.Category_Code__c, Product__r.Rate_Value__c, ' +
            'Product__r.MRP__c, Product__r.Price_Type__c, ' +
            'Product__r.Alternate_UOM__c, Product__r.UOM_Conversion__c, ' +
            'Product__r.Per_Pieces__c, Product__r.Crate_Conversion__c ' +
            'FROM Invoice_Line_Items__r) ' +
            'FROM Invoice__c ' +
            'WHERE OwnerId IN :allowedUserIds';

        if (fromDate != null) {
            soql += ' AND Invoice_Date__c >= :fromDate';
        }
        if (toDate != null) {
            soql += ' AND Invoice_Date__c <= :toDate';
        }

        soql += ' ORDER BY Invoice_Date__c DESC';

        Map<String, Object> bindVars = new Map<String, Object>();
        bindVars.put('allowedUserIds', allowedUserIds);
        if (fromDate != null) {
            bindVars.put('fromDate', fromDate);
        }
        if (toDate != null) {
            bindVars.put('toDate', toDate);
        }

        return Database.queryWithBinds(soql, bindVars, AccessLevel.USER_MODE);
    }
}