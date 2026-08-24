/**
* Class Name : MonthlyExpenseClaimSchedulerJob
* Test Class  : MonthlyExpenseClaimSchedulerTest
* author      : Pradvith
* CreatedDate : 05-12-24
* Description : Scheduler to cretae the monthly expense records.
* */
public with sharing class MonthlyExpenseClaimScheduler {

    public static void createMonthlyExpenseClaim() {
        // Get all active users for whom expense claims need to be created
     //   List<User> users = [SELECT Id, FirstName, LastName FROM User WHERE IsActive = true];
  List<User> users = [
            SELECT Id, FirstName, LastName, Profile.Name
    FROM User
    //WHERE IsActive = true AND  Profile.Name = 'SFA Profile'  ];
    WHERE IsActive = true AND  Profile.Name IN ('SFA Profile','SFA Profile - Light')  ];
        // Get current month and year
        String monthName = getMonthName(Date.today().month());
        String year = String.valueOf(Date.today().year());

        List<Expense_Claim__c> expenseClaims = new List<Expense_Claim__c>();
     

        for (User  user : users) {
            Expense_Claim__c expenseClaim = new Expense_Claim__c(
                Name = monthName + '-' + year + '-Expense Claim For-' + user.FirstName + ' ' + user.LastName,
                Start_Date__c = Date.newInstance(Date.today().year(), Date.today().month(), 1),
                End_Date__c = Date.newInstance(Date.today().year(), Date.today().month(), Date.daysInMonth(Date.today().year(), Date.today().month())),
                User__c = user.Id
            );
            
            
            expenseClaims.add(expenseClaim);
        }

        if (!expenseClaims.isEmpty()) {
            insert expenseClaims;
        }
    }

    // Helper method to get month name
    public static String getMonthName(Integer month) {
        return new Map<Integer, String>{
            1 => 'January', 2 => 'February', 3 => 'March',
            4 => 'April', 5 => 'May', 6 => 'June',
            7 => 'July', 8 => 'August', 9 => 'September',
            10 => 'October', 11 => 'November', 12 => 'December'
        }.get(month);
    }
}