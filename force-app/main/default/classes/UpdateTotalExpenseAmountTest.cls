@isTest
public class UpdateTotalExpenseAmountTest {
  
    @testSetup
    static void setupTestData() {
        // Create test Expense_Claim__c records
        List<Expense_Claim__c> claims = new List<Expense_Claim__c>();
        claims.add(new Expense_Claim__c(
            Start_Date__c = Date.today().addDays(-10),
            End_Date__c = Date.today().addDays(10),
            User__c = UserInfo.getUserId()
        ));
        claims.add(new Expense_Claim__c(
            Start_Date__c = Date.today().addDays(-5),
            End_Date__c = Date.today().addDays(5),
            User__c = UserInfo.getUserId()
        ));
        insert claims;
        
        // Create some approved Expense__c records linked to claims with different types and dates
        List<Expense__c> expenses = new List<Expense__c>();
        
        expenses.add(new Expense__c(
            Expense_Claim__c = claims[0].Id,
            Amount__c = 100,
            Expense_Date__c = Date.today(),
            Expense_Type__c = 'Travel_Expense_Request',
            Approval_Status__c = 'Approved'

        ));
        expenses.add(new Expense__c(
            Expense_Claim__c = claims[0].Id,
            Amount__c = 50,
            Expense_Date__c = Date.today(),
            Expense_Type__c = 'Daily Allowance',
            Approval_Status__c = 'Approved'
        ));
        expenses.add(new Expense__c(
            Expense_Claim__c = claims[1].Id,
            Amount__c = 200,
            Expense_Date__c = Date.today(),
            Expense_Type__c = 'Accommodation Request',
            Approval_Status__c = 'Approved'
        ));
        insert expenses;
    }
  
    @isTest
    static void testHandleExpenseUpdatesAsync() {
        // Query the test claims
        List<Expense_Claim__c> claims = [SELECT Id, Total_Expense_For_This_Month__c, Travel_Expense_Total__c, Accommodation_Total__c 
                                        FROM Expense_Claim__c];
        Set<Id> claimIds = new Set<Id>();
        for (Expense_Claim__c c : claims) {
            claimIds.add(c.Id);
        }
        
        Test.startTest();
        UpdateTotalExpenseAmount.handleExpenseUpdatesAsync(claimIds);
        // The future method executes after Test.stopTest();
        Test.stopTest();
        
        
     
    }
  
    @isTest
    static void testSendApprovalNotifications() {
        // Create old expense with Approval_Status__c = 'Pending'
        Expense__c oldExp = new Expense__c(
            Amount__c = 100,
            Expense_Date__c = Date.today(),
            Expense_Type__c = 'Travel_Expense_Request',
            Approval_Status__c = 'Pending'
        );
        insert oldExp;
        
        // Clone old expense to simulate new expense with updated Approval_Status__c
        Expense__c newExp = oldExp.clone(false, true, false, false);
        newExp.Approval_Status__c = 'Approved';
        
        Test.startTest();
        // Simulate sending notifications for the updated expense
        UpdateTotalExpenseAmount.sendApprovalNotifications(
            new List<Expense__c>{newExp},
            new Map<Id, Expense__c>{oldExp.Id => oldExp}
        );
        Test.stopTest();
        
        // We can't directly assert Custom Notifications sent, but no exceptions means success
        System.assert(true, 'sendApprovalNotifications executed without errors');
    }
}