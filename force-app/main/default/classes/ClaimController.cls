public with sharing class ClaimController {

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getFieldHelpTexts(String objectApiName, List<String> fieldApiNames) {
        Map<String, String> fieldHelpTexts = new Map<String, String>();
        Schema.DescribeSObjectResult objDescribe = Schema.getGlobalDescribe().get(objectApiName).getDescribe();
        
        for (String fieldApiName : fieldApiNames) {
            if (objDescribe.fields.getMap().containsKey(fieldApiName)) {
                fieldHelpTexts.put(
                    fieldApiName,
                    objDescribe.fields.getMap().get(fieldApiName).getDescribe().getInlineHelpText()
                );
            }
        }
        System.debug('msg help texts- ' + fieldHelpTexts);
        return fieldHelpTexts;
    }

    @AuraEnabled
    public static Map<String, Decimal> fetchInvoicesByOrder(String formattedMonth) {
        validateFormattedMonth(formattedMonth);
        
        Date[] dateRange = getDateRange(formattedMonth);
        Date startDate = dateRange[0];
        Date endDate = dateRange[1];
        
           
        // Get User Info
        Id userId = UserInfo.getUserId();
         Id accId;
        User usr = [SELECT ContactId FROM User WHERE Id = :userId LIMIT 1];
        
        String userState = '';
        if (usr.ContactId != null) {
            Contact userContact = [SELECT AccountId FROM Contact WHERE Id = :usr.ContactId LIMIT 1];
            accId = userContact.AccountId;
        }

        Decimal primaryPurchase = getPrimaryInvoiceTotal(startDate, endDate,accId);
        Decimal secondarySales = getSecondaryInvoiceTotal(startDate, endDate,accId);

        Map<String, Decimal> results = new Map<String, Decimal>();
        results.put('primaryPurchase', primaryPurchase);
        results.put('secondarySales', secondarySales);

        System.debug('Results: ' + results);
        return results;
    }

    private static void validateFormattedMonth(String formattedMonth) {
        if (String.isBlank(formattedMonth)) {
            throw new AuraHandledException('Blank date');
        }
        List<String> parts = formattedMonth.split('-');
        if (parts.size() != 2) {
            throw new AuraHandledException('Invalid month-year format');
        }
    }

    private static Date[] getDateRange(String formattedMonth) {
        List<String> parts = formattedMonth.split('-');
        Integer year = Integer.valueOf(parts[0]);
        Integer month = Integer.valueOf(parts[1]);

        Date startDate = Date.newInstance(year, month, 1);
        Date endDate = startDate.addMonths(1).addDays(-1);

        System.debug('startDate- ' + startDate + ' endDate- ' + endDate);
        return new Date[] { startDate, endDate };
    }

    private static Decimal getPrimaryInvoiceTotal(Date startDate, Date endDate, Id accountId) {
        List<AggregateResult> primaryResults = [
            SELECT SUM(Taxable_Amount__c) totalPrimary
            FROM Invoice__c
            WHERE Createddate >= :startDate AND Createddate <= :endDate AND RecordType.Name = 'Primary Invoice' AND OwnerId = :UserInfo.getUserId()
        ];

        System.debug('primaryResults- ' + primaryResults);
        return (primaryResults.isEmpty() || primaryResults[0].get('totalPrimary') == null) 
            ? 0 
            : (Decimal) primaryResults[0].get('totalPrimary');
    }

    private static Decimal getSecondaryInvoiceTotal(Date startDate, Date endDate, Id accountId) {
        List<AggregateResult> secondaryResults = [
            SELECT SUM(CGST_Amount__c) totalCGST, SUM(SGST_Amount__c) totalSGST, SUM(IGST_Amount__c) totalIGST, SUM(Invoice_Amount__c) totalAmt
            FROM Invoice__c
            WHERE Createddate >= :startDate AND Createddate <= :endDate AND RecordType.Name = 'Secondary Invoice' AND Distributor_Account__c = :accountId AND Status__c = 'Delivered'
        ];

        System.debug('secondaryResults- ' + secondaryResults);
        Decimal totalAmt = (!secondaryResults.isEmpty() && secondaryResults[0].get('totalAmt') != null) 
            ? (Decimal) secondaryResults[0].get('totalAmt') 
            : 0;

        return totalAmt;
    }

@AuraEnabled
public static String saveExpenseClaim(String claimDataStr) {
// Declare a variable to hold the result
String resultMessage = 'Claim saved successfully';
system.debug('Msg json - '+claimDataStr);

try {
    // Deserialize the JSON string into a Map
    Map<String, Object> claimData = (Map<String, Object>) JSON.deserializeUntyped(claimDataStr);
Id recordTypeId = Schema.SObjectType.Expense_Claim__c.getRecordTypeInfosByDeveloperName().get('DMS_Claims').getRecordTypeId();

    // Initialize the Expense_Claim__c record
    Expense_Claim__c claim = new Expense_Claim__c();
    //claim.Order__c = (Id) claimData.get('orderId');
    
    // Safely convert the fields to Decimal
    claim.Primary_Purchase__c = safeConvertToDecimal(claimData.get('primaryPurchase'));
    claim.Secondary_Sales__c = safeConvertToDecimal(claimData.get('secondarySales'));
    claim.Dealer_Discount__c = safeConvertToDecimal(claimData.get('dealerDiscount'));
    claim.Product_Complaint__c = safeConvertToDecimal(claimData.get('productComplaint'));
    claim.Outstation_Transport_Support__c = safeConvertToDecimal(claimData.get('transportSupport'));
    claim.Freezer_subsidy_Repairs__c = safeConvertToDecimal(claimData.get('freezerSubsidy'));
    claim.Schemes__c = safeConvertToDecimal(claimData.get('schemes'));
    claim.Stall_Rents_Event_Sales_Discounts__c = safeConvertToDecimal(claimData.get('eventSalesDiscounts'));
    claim.Party_Orders_institutional_Discounts__c = safeConvertToDecimal(claimData.get('institutionalDiscounts'));
    claim.Cold_Room_Support__c = safeConvertToDecimal(claimData.get('coldRoomSupport'));
    claim.Approved_Special_claims_if_any__c = safeConvertToDecimal(claimData.get('approvedSpecialClaims'));
    claim.RecordTypeid = recordTypeId;
    claim.Name='Distributor Claim';
    
    // Check for specialClaimType
    claim.Type__c = claimData.containsKey('specialClaimType') ? (String) claimData.get('specialClaimType') : null;

    // Insert the Expense Claim record
    insert claim;

} catch (Exception e) {
    // If any error occurs, set the result message to the error message
    resultMessage = 'Error saving claim: ' + e.getMessage();
        System.debug('Line number: ' + e.getLineNumber());    
}
system.debug('Msg- '+resultMessage);
// Return the result message
return resultMessage;
}
                                                                                                // Helper method to safely convert String to Decimal
public static Decimal safeConvertToDecimal(Object value) {
if (value == null) {
    return 0;
}

if (value instanceof Decimal) {
    return (Decimal) value;
} else if (value instanceof String) {
    try {
        return Decimal.valueOf((String) value);
    } catch (Exception e) {
        return 0; // Return 0 if conversion fails
    }
}
return 0;
}


@AuraEnabled(cacheable=true)
public static List<String> getTypePicklistValues() {
    Schema.DescribeFieldResult fieldResult = Expense_Claim__c.Type__c.getDescribe();
    if (fieldResult != null) {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry : fieldResult.getPicklistValues()) {
            values.add(entry.getValue());
        }
        return values;
    }
    return new List<String>(); // Return empty list if no values are found
}

/*@AuraEnabled
public static List<Order__c> searchOrders(String searchTerm) {
    return [
        SELECT Id, Name, Order_Number__c
        FROM Order__c
        WHERE Name LIKE :('%' + searchTerm + '%') OR Order_Number__c LIKE :('%' + searchTerm + '%')
        LIMIT 10
    ];
}*/
}