/**
* Trigger Name : ExpenseTrigger
* Description : Updates Expense Claim totals and rollups by expense type
*/
trigger ExpenseTrigger on Expense__c (
  after insert, after update, after delete, after undelete
) {
  Set<Id> expenseClaimIds = new Set<Id>();
  
  // Handle all DML operations
  if (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete) {
    for (Expense__c exp : Trigger.new) {
      if (exp.Expense_Claim__c != null) {
        expenseClaimIds.add(exp.Expense_Claim__c);
      }
    }
  }
  
  if (Trigger.isUpdate || Trigger.isDelete) {
    for (Expense__c exp : Trigger.old) {
      if (exp.Expense_Claim__c != null) {
        expenseClaimIds.add(exp.Expense_Claim__c);
      }
    }
  }
  
  // Process expense claims
  if (!expenseClaimIds.isEmpty()) {
    UpdateTotalExpenseAmount.handleExpenseUpdatesAsync(expenseClaimIds);
  }
  
  // Handle approval notifications
  if (Trigger.isAfter && Trigger.isUpdate) {
    UpdateTotalExpenseAmount.sendApprovalNotifications(
      Trigger.new, 
      Trigger.oldMap
    );
  }
}