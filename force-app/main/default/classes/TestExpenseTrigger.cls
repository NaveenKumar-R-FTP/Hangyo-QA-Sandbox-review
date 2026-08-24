@isTest
public class TestExpenseTrigger {

    @isTest static void testExpenseClaimUpdate() {
        // Create test data
        Date today = Date.today();
        Date startOfNextMonth = today.toStartOfMonth().addMonths(1);
        Date endOfMonth = startOfNextMonth.addDays(-1);
        Expense_Claim__c claim = new Expense_Claim__c(Start_Date__c = Date.today().toStartOfMonth(), 
                                                      End_Date__c = endOfMonth,
                                                      User__c = UserInfo.getUserId()
                                                     );
        insert claim;

        Expense__c expense1 = new Expense__c(Expense_Claim__c = claim.Id, 
                                             Expense_Date__c = Date.today(), 
                                             Amount__c = 100
                                            );
        insert expense1;

        Test.startTest();
        
        // Perform an update to trigger the future method
        expense1.Amount__c = 150;
        update expense1;
        
        // Perform a delete to trigger the future method
        delete expense1;
        
        Test.stopTest();
        
        // Query and assert the results
        claim = [SELECT Total_Expense_For_This_Month__c FROM Expense_Claim__c WHERE Id = :claim.Id];
        System.assertEquals(0, claim.Total_Expense_For_This_Month__c);
    }
}