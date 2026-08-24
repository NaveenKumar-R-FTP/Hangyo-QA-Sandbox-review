/**
* Class Name  : OrderProductController
* Test Class  : OrderProductControllerTest
* author      : Ashwini
* CreatedDate : 25-12-24
* Description : Created to update Monthly target value on account
* */
public without sharing class RetailerTargetTriggerHandler {
    //This method is to updateAmountOnAccount
    public static void updateAmountOnAccount(List<Retailer_Target__c> targetList) {
        Set<Id> accountIds = extractAccountIds(targetList);
        
        if (accountIds.isEmpty()) {
            return;
        }
        
        List<Retailer_Target__c> retList = queryRetailerTargets(accountIds);
        
        String currentMonth = getCurrentMonth();
        
        Map<Id, Decimal> accountMonthlyTargets = processTargetRecords(retList, currentMonth);
        
        List<Account> accountsToUpdate = prepareAccountsToUpdate(accountIds, accountMonthlyTargets);
        
        updateAccounts(accountsToUpdate);
    }
    //This method is to extractAccountIds
    
    private static Set<Id> extractAccountIds(List<Retailer_Target__c> targetList) {
        Set<Id> accountIds = new Set<Id>();
        for (Retailer_Target__c ret : targetList) {
            if (ret.Retailer__c != null) {
                accountIds.add(ret.Retailer__c);
            }
        }
        return accountIds;
    }
    //This method is to queryRetailerTargets
    
    private static List<Retailer_Target__c> queryRetailerTargets(Set<Id> accountIds) {
        return [
            SELECT Id, Retailer__c, Amount__c, MonthYear__c
            FROM Retailer_Target__c
            WHERE Retailer__c IN :accountIds
        ];
    }
    //This method is to getCurrentMonth
    private static String getCurrentMonth() {
        return DateTime.now().format('MMM yyyy');
    }
    //This method is to processTargetRecords
    
    private static Map<Id, Decimal> processTargetRecords(List<Retailer_Target__c> retList, String currentMonth) {
        Map<Id, Decimal> accountMonthlyTargets = new Map<Id, Decimal>();
        for (Retailer_Target__c ret : retList) {
            if (ret.MonthYear__c == currentMonth && ret.Amount__c != null && ret.Amount__c != '') {
                try {
                    Decimal amountDecimal = Decimal.valueOf(ret.Amount__c);
                    accountMonthlyTargets.put(ret.Retailer__c, amountDecimal);
                } catch (Exception e) {
                    System.debug('Error converting Amount__c to Decimal: ' + e.getMessage());
                }
            }
        }
        return accountMonthlyTargets;
    }
    //This method is to prepareAccountsToUpdate
    
    private static List<Account> prepareAccountsToUpdate(Set<Id> accountIds, Map<Id, Decimal> accountMonthlyTargets) {
        List<Account> accountsToUpdate = new List<Account>();
        for (Id accountId : accountIds) {
            if (accountMonthlyTargets.containsKey(accountId)) {
                Account acc = new Account(Id = accountId);
                acc.Monthly_Target__c = accountMonthlyTargets.get(accountId);
                accountsToUpdate.add(acc);
            }
        }
        return accountsToUpdate;
    }
    //This method is to updateAccounts
    
    private static void updateAccounts(List<Account> accountsToUpdate) {
        if (!accountsToUpdate.isEmpty()) {
            try {
                update accountsToUpdate;
            } catch (DmlException dmlEx) {
                // Log the error for debugging and visibility
                System.debug('Error updating accounts: ' + dmlEx.getMessage());
            }
        }
    }
}