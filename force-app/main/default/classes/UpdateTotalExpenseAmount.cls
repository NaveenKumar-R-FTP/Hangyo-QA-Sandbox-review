public with sharing class UpdateTotalExpenseAmount {
  private static final Map<String, String> EXPENSE_TYPE_FIELDS = 
    new Map<String, String>{
      'Travel_Expense_Request' => 'Travel_Expense_Total__c',
      'Accommodation Request' => 'Accommodation_Total__c',
      'Miscellaneous Request' => 'Total_Miscellaneous__c',
      'Daily Allowance' => 'Total_DA__c',
      'Travel Allowance' => 'Total_TA__c'
    };
  
  private static final Map<String, String> EXPENSE_TYPE_DAYS_FIELDS =
    new Map<String, String>{
      'Daily Allowance'  => 'Total_DA_Days__c',
      'Travel Allowance' => 'Total_TA_Days__c'
    };
  
  @future(callout=false)
  public static void handleExpenseUpdatesAsync(Set<Id> expenseClaimIds) {
    updateExpenseClaims(expenseClaimIds);
  }
  
  private static void updateExpenseClaims(Set<Id> claimIds) {
    if (claimIds.isEmpty()) return;
    
    Map<Id, Expense_Claim__c> claims = new Map<Id, Expense_Claim__c>([
      SELECT Id, Start_Date__c, End_Date__c
      FROM Expense_Claim__c
      WHERE Id IN :claimIds
    ]);
    
    // Initialize type totals and overall totals for all claims
    Map<Id, Map<String, Decimal>> claimTypeTotals = new Map<Id, Map<String, Decimal>>();
    Map<Id, Map<String, Decimal>> claimDaysTotals   = new Map<Id, Map<String, Decimal>>();
    Map<Id, Decimal> claimOverallTotals = new Map<Id, Decimal>();
    
    for (Id claimId : claimIds) {
      claimTypeTotals.put(claimId, new Map<String, Decimal>{
        'Travel_Expense_Request' => 0,
        'Accommodation Request' => 0,
        'Miscellaneous Request' => 0,
        'Daily Allowance' => 0,
        'Travel Allowance' => 0
      });
      
      claimDaysTotals.put(claimId, new Map<String, Decimal>{
         'Daily Allowance'  => 0,
         'Travel Allowance' => 0
      });
        
      claimOverallTotals.put(claimId, 0);
    }
    
    // Process APPROVED expenses matching types and date ranges
    for (Expense__c exp : [
      SELECT Expense_Claim__c, Amount__c, Expense_Date__c, Expense_Type__c,DA_Days__c,TA_Days__c
      FROM Expense__c 
      WHERE Expense_Claim__c IN :claimIds
        AND Expense_Date__c != null
        AND Amount__c != null
        AND Approval_Status__c = 'Approved' // Only approved expenses
        AND Expense_Type__c IN :EXPENSE_TYPE_FIELDS.keySet() // Optimize query
    ]) {
      Expense_Claim__c claim = claims.get(exp.Expense_Claim__c);
      if (claim != null && 
          claim.Start_Date__c <= exp.Expense_Date__c && 
          claim.End_Date__c >= exp.Expense_Date__c) {
        
        // Update type-specific total
        String expType = exp.Expense_Type__c;
        Decimal currentTypeTotal = claimTypeTotals.get(exp.Expense_Claim__c).get(expType);
        claimTypeTotals.get(exp.Expense_Claim__c).put(expType, currentTypeTotal + exp.Amount__c);
        
        // Update overall total for this claim
        Decimal currentOverall = claimOverallTotals.get(exp.Expense_Claim__c);
        claimOverallTotals.put(exp.Expense_Claim__c, currentOverall + exp.Amount__c);
      }
      
      if (EXPENSE_TYPE_DAYS_FIELDS.containsKey(exp.Expense_Type__c)) {
          Decimal daysToAdd = 0;
          if (exp.Expense_Type__c == 'Daily Allowance' && exp.DA_Days__c != null) {
              daysToAdd = exp.DA_Days__c;
          }
          else if (exp.Expense_Type__c == 'Travel Allowance' && exp.TA_Days__c != null) {
              daysToAdd = exp.TA_Days__c;
          }
          Decimal currentDays = claimDaysTotals.get(exp.Expense_Claim__c).get(exp.Expense_Type__c);
          claimDaysTotals.get(exp.Expense_Claim__c).put(exp.Expense_Type__c, currentDays + daysToAdd);
      }
    }
    
    // Prepare claims for update
    List<Expense_Claim__c> claimsToUpdate = new List<Expense_Claim__c>();
    for (Id claimId : claimTypeTotals.keySet()) {
      Expense_Claim__c claimUpdate = new Expense_Claim__c(Id = claimId);
      claimUpdate.Total_Expense_For_This_Month__c = claimOverallTotals.get(claimId);
      
      // Set type-specific fields
      Map<String, Decimal> typeTotals = claimTypeTotals.get(claimId);
      for (String expType : typeTotals.keySet()) {
        String fieldName = EXPENSE_TYPE_FIELDS.get(expType);
        claimUpdate.put(fieldName, typeTotals.get(expType));
      }
      for (String expType : claimDaysTotals.get(claimId).keySet()) {
          String fieldName = EXPENSE_TYPE_DAYS_FIELDS.get(expType);
          claimUpdate.put(fieldName, claimDaysTotals.get(claimId).get(expType));
      }
      claimsToUpdate.add(claimUpdate);
    }
    
    if (!claimsToUpdate.isEmpty()) {
      update claimsToUpdate;
    }
  }
  
  public static void sendApprovalNotifications(
    List<Expense__c> newExpenses, 
    Map<Id, Expense__c> oldExpenses
  ) {
    try {
      CustomNotificationType notifType = [
        SELECT Id FROM CustomNotificationType 
        WHERE DeveloperName = 'Approval_Outcome_Notification' 
        LIMIT 1
      ];
      
      for (Expense__c exp : newExpenses) {
        Expense__c oldExp = oldExpenses.get(exp.Id);
        if (exp.Approval_Status__c != oldExp.Approval_Status__c &&
            (exp.Approval_Status__c == 'Approved' || 
             exp.Approval_Status__c == 'Rejected')) {
                 
          Messaging.CustomNotification notification = new Messaging.CustomNotification();
          notification.setNotificationTypeId(notifType.Id);
          notification.setTitle('Expense Approval Update');
          notification.setBody('Your expense ' + exp.Name + ' has been ' + exp.Approval_Status__c + '.');
          notification.setSenderId(UserInfo.getUserId());
          notification.setTargetId(exp.Id);
          notification.send(new Set<String>{exp.CreatedById});
        }
      }
    } catch (Exception e) {
      System.debug('Notification error: ' + e.getMessage());
    }
  }
}