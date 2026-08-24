public class GenerateRetailerCreationCode {

    public static void retailerCreationCode(List<Account> newAccounts) {
        // Get Retailer Record Type Id
        Map<String, Schema.RecordTypeInfo> rtMap = Schema.SObjectType.Account.getRecordTypeInfosByName();
        Id retailerRecordTypeId = rtMap.get('Retailer').getRecordTypeId();

        // Try to get the Custom Setting
        RetailerCodeSetting__c setting = RetailerCodeSetting__c.getInstance('SF');
        Integer latestCode;
        String prefix = 'SF';

        if (setting == null) {
            // Fallback: Get max existing retailer code from Retailer Accounts
            List<Account> latestRetailerAccounts = [
                SELECT Retailer_Code__c
                FROM Account
                WHERE Retailer_Code__c != null
                ORDER BY Retailer_Code__c DESC
                LIMIT 1
            ];

            if (!latestRetailerAccounts.isEmpty()) {
                String lastCode = latestRetailerAccounts[0].Retailer_Code__c;
                String numericPart = lastCode.replace(prefix, '');
                if (String.isNotBlank(numericPart)) {
                    latestCode = Integer.valueOf(numericPart) + 1;
                }
            }
            
            // Create new setting
            setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = latestCode);
            insert setting;
        } else {
            latestCode = Integer.valueOf(setting.Latest_Code__c);
        }

        // Assign codes to new retailer accounts
        for (Account acc : newAccounts) {
            if (acc.RecordTypeId == retailerRecordTypeId) {
                latestCode++;
                acc.Retailer_Code__c = prefix + String.valueOf(latestCode);
            }
        }

        // Update the setting
        setting.Latest_Code__c = latestCode;
        update setting;
    }
}