/**
* Class Name  : RetailerTargetController
* Test Class  : RetailerTargetControllerTest
* author      : Shyam
* CreatedDate : 15-01-25	
* Description : This is controller for downloading & Uploading the retailers target data.
                
* */
public with sharing class RetailerTargetController {

    @AuraEnabled(cacheable=true)
    public static List<Account> getRetailerTargets() {
        return [
            SELECT Id, Name, Shipping_Address_text__c, Location_Text__c,
                (SELECT MonthYear__c, Target_Amount__c, Amount__c FROM Retailer_Targets__r)
            FROM Account
            WHERE RecordType.Name = 'Retailer'
            AND OwnerId = :userInfo.getUserId()
        ];
    }   

    @AuraEnabled
    public static List<Retailer_Target__c> saveFile(String base64Data) {
        // Decode base64 and split the CSV data
        String data = JSON.deserializeUntyped(base64Data).toString();
        List<String> csvLines = data.split('\n');
        
        // Extract and validate data
        String currentMonthYear = getCurrentMonthYear();
        Map<String, Retailer_Target__c> existingTargetsMap = getExistingTargetsMap(currentMonthYear);
        List<Retailer_Target__c> retailerTargetsToInsertOrUpdate = processCSVData(csvLines, existingTargetsMap);

        // Perform upsert operation
        performUpsert(retailerTargetsToInsertOrUpdate);
        
        // Update Monthly_Target__c on Retailer__c after saving/updating targets
        updateRetailerMonthlyTarget(retailerTargetsToInsertOrUpdate);

        return retailerTargetsToInsertOrUpdate;
    }

    // Helper method to get current month and year
    public static String getCurrentMonthYear() {
        return Datetime.now().format('MMM yyyy', 'en_IN');
    }

    // Helper method to fetch existing targets as a map
    private static Map<String, Retailer_Target__c> getExistingTargetsMap(String monthYear) {
        Map<String, Retailer_Target__c> targetsMap = new Map<String, Retailer_Target__c>();

        List<Retailer_Target__c> existingTargets = [
            SELECT Id, Retailer__c, Target_Amount__c, MonthYear__c, Amount__c
            FROM Retailer_Target__c
            WHERE MonthYear__c = :monthYear
        ];

        for (Retailer_Target__c target : existingTargets) {
            targetsMap.put(target.Retailer__c, target);
        }

        return targetsMap;
    }

    // Helper method to process CSV data
    private static List<Retailer_Target__c> processCSVData(List<String> csvLines, Map<String, Retailer_Target__c> existingTargetsMap) {
        List<Retailer_Target__c> targetsToUpsert = new List<Retailer_Target__c>();

        for (Integer i = 1; i < csvLines.size(); i++) {
            String csvLine = csvLines[i];
            List<String> rowData = splitCSVLine(csvLine);

            if (rowData.size() >= 5) {
                String retailerId = rowData[0];
                String newTargetAmount = String.valueOf(rowData[4]);

                processTargetRow(new TargetRowData(retailerId, newTargetAmount), existingTargetsMap, targetsToUpsert);
            }
        }

        return targetsToUpsert;
    }

    // Helper method to process individual target rows
    public static void processTargetRow(TargetRowData targetData, Map<String, Retailer_Target__c> existingTargetsMap, List<Retailer_Target__c> targetsToUpsert) {
        if (existingTargetsMap.containsKey(targetData.retailerId)) {
            Retailer_Target__c existingTarget = existingTargetsMap.get(targetData.retailerId);
            if (existingTarget.Amount__c != targetData.newTargetAmount) {
                existingTarget.Amount__c = targetData.newTargetAmount;
                targetsToUpsert.add(existingTarget);
            } else {
                throw new AuraHandledException('Only Target Amount can be updated.');
            }
        } else {
            Retailer_Target__c newTarget = new Retailer_Target__c();
            newTarget.Retailer__c = targetData.retailerId;
            newTarget.Amount__c = targetData.newTargetAmount;
            targetsToUpsert.add(newTarget);
        }
    }

    // Helper method to perform upsert operation
    public static void performUpsert(List<Retailer_Target__c> targetsToUpsert) {
        if (!targetsToUpsert.isEmpty()) {
            try {
                upsert targetsToUpsert;
            } catch (Exception e) {
                throw new AuraHandledException('Error during upsert: ' + e.getMessage());
            }
        }
    }

    // Helper method to split a CSV line considering quoted fields
    public static List<String> splitCSVLine(String line) {
        List<String> result = new List<String>();
        String regex = '"([^"]*)"|([^,]+)';
        Pattern pattern = Pattern.compile(regex);
        Matcher matcher = pattern.matcher(line);

        while (matcher.find()) {
            if (matcher.group(1) != null) {
                result.add(matcher.group(1).replaceAll('""', '"'));
            } else if (matcher.group(2) != null) {
                result.add(matcher.group(2));
            }
        }

        return result;
    }
    
    // Helper method to update Monthly_Target__c on Retailer__c after target update
    public static void updateRetailerMonthlyTarget(List<Retailer_Target__c> retailerTargetsToInsertOrUpdate) {
        // Collect retailer Ids that need to be updated
        Set<Id> retailerIdsToUpdate = new Set<Id>();

        for (Retailer_Target__c target : retailerTargetsToInsertOrUpdate) {
            retailerIdsToUpdate.add(target.Retailer__c);
        }

        // Retrieve the retailer records and update Monthly_Target__c field
        List<Account> retailersToUpdate = [
            SELECT Id, Monthly_Target__c, (SELECT Amount__c FROM Retailer_Targets__r)
            FROM Account
            WHERE Id IN :retailerIdsToUpdate
        ];

        for (Account retailer : retailersToUpdate) {
            Decimal totalTargetAmount = 0;

            // Sum up the target amounts for the current month
            for (Retailer_Target__c target : retailer.Retailer_Targets__r) {
                totalTargetAmount += Decimal.valueOf(target.Amount__c);
            }

            // Update the Monthly_Target__c field on Retailer__c
            retailer.Monthly_Target__c = totalTargetAmount;

        }

        // Perform the update operation on Retailer__c objects
        update retailersToUpdate;
    }

    // Inner class to encapsulate target row data
    public class TargetRowData {
        public String retailerId;
        public String newTargetAmount;

        public TargetRowData(String retailerId, String newTargetAmount) {
            this.retailerId = retailerId;
            this.newTargetAmount = newTargetAmount;
        }
    }
}