/**
 * Class : EODController Class
 * Test Class : TestEODController
 * Author : Hariprasad
 * LastModifiedDate : 13/02/2026
 * Descriprtion : End of the working day controller class 
 **/

public with sharing class EODController 
{
    private static final String STATUS_NOT_STARTED = 'Not Started';
    
    public class EODWrapper {
        @AuraEnabled public Integer scheduledCalls;
        @AuraEnabled public Integer totalCalls;
        @AuraEnabled public Integer productiveCalls;
        @AuraEnabled public Integer notVisitedOutlet;
        @AuraEnabled public Integer newOutletOnboarded;
        @AuraEnabled public Integer dfTransfer;
        @AuraEnabled public Integer distributorVisit;
        @AuraEnabled public String firstCheckInTime;
        @AuraEnabled public String lastCheckOutTime;
        @AuraEnabled public String totalTimeSpent;
        @AuraEnabled public Decimal totalOrderValue;
        @AuraEnabled public String message;

        public EODWrapper() {
            scheduledCalls = 0;
            totalCalls = 0;
            productiveCalls = 0;
            notVisitedOutlet = 0;
            newOutletOnboarded = 0;
            dfTransfer = 0;
            distributorVisit = 0;
            firstCheckInTime = '';
            lastCheckOutTime = '';
            totalTimeSpent = '';
            totalOrderValue = 0;
            message = '';
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static EODWrapper getDailyPerformance() {
        return getDailyPerformanceInternal();
    }

    // Added by hari - Non-cacheable version for imperative call from EOD button (cacheable can fail when called from button)
    @AuraEnabled(cacheable=false)
    public static EODWrapper getDailyPerformanceForEOD() {
        return getDailyPerformanceInternal();
    }

    // Added by hari - Same as Dheeraj testing method but non-cacheable for LWC: optional targetUserId (null = current user), else that user's EOD
    @AuraEnabled(cacheable=false)
    public static EODWrapper getDailyPerformanceForUserEOD(Id targetUserId) {
        if (targetUserId == null) {
            return getDailyPerformanceInternal();
        }
        return getDailyPerformanceForUserAndDate(targetUserId, String.valueOf(Date.today()));
    }

    private static EODWrapper getDailyPerformanceInternal() {
        EODWrapper result = new EODWrapper();
        Id userId = UserInfo.getUserId();
        Date today = Date.today();

        try {
            result.scheduledCalls = getScheduledCallsCount(userId, today);
            aggregateVisitTaskMetrics(userId, today, result);
            result.newOutletOnboarded = getNewOutletOnboardedCount(userId, today);
            result.dfTransfer = getDfTransferCount(userId, today);
            setCheckInCheckOutTimes(userId, today, result);
            result.totalOrderValue = getTotalOrderValueForDay(userId, today);

            System.debug(LoggingLevel.INFO, 'Scheduled Call       - ' + result.scheduledCalls);
            System.debug(LoggingLevel.INFO, 'Total Calls          - ' + result.totalCalls);
            System.debug(LoggingLevel.INFO, 'Productive Calls     - ' + result.productiveCalls);
            System.debug(LoggingLevel.INFO, 'Not Visited Outlet   - ' + result.notVisitedOutlet);
            System.debug(LoggingLevel.INFO, 'New Outlet Onboarded - ' + result.newOutletOnboarded);
            System.debug(LoggingLevel.INFO, 'DF Transfer          - ' + result.dfTransfer);
            System.debug(LoggingLevel.INFO, 'Distributor Visit    - ' + result.distributorVisit);
            System.debug(LoggingLevel.INFO, 'First Check in Time  - ' + result.firstCheckInTime);
            System.debug(LoggingLevel.INFO, 'Last Check Out Time  - ' + result.lastCheckOutTime);
            System.debug(LoggingLevel.INFO, 'Total Time Spent     - ' + result.totalTimeSpent);
            System.debug(LoggingLevel.INFO, 'Total Order Value    - ' + result.totalOrderValue);

        } catch (Exception e) {
            result.message = 'Error loading EOD summary: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'EODController.getDailyPerformance - Exception: ' + e.getMessage() + ' | ' + e.getStackTraceString());
        }

        return result;
    }
    
		 /*======================================================== TESTING PURPOSE USING DHEERAJ USER ==================================================================*/    

   // FOR TESTING: EOD for a specific user to see Dheeraj's data (Dheeraj SO-SSO-ASM-VP BLR Mrinal Test user5) 
     
    @AuraEnabled(cacheable=true)
    public static EODWrapper getDailyPerformanceForUser(Id targetUserId) {
        if (targetUserId == null) {
            return getDailyPerformance();
        }
        return getDailyPerformanceForUserAndDate(targetUserId, String.valueOf(Date.today()));
    }

    
    // FOR TESTING: EOD for a specific user and date
     
    @AuraEnabled(cacheable=true)
    public static EODWrapper getDailyPerformanceForUserAndDate(Id targetUserId, String dateStr) {
        Id userId = (targetUserId != null) ? targetUserId : UserInfo.getUserId();
        if (String.isBlank(dateStr)) {
            dateStr = String.valueOf(Date.today());
        }
        try {
            Date targetDate = Date.valueOf(dateStr);
            EODWrapper result = new EODWrapper();
            result.scheduledCalls = getScheduledCallsCount(userId, targetDate);
            aggregateVisitTaskMetrics(userId, targetDate, result);
            result.newOutletOnboarded = getNewOutletOnboardedCount(userId, targetDate);
            result.dfTransfer = getDfTransferCount(userId, targetDate);
            setCheckInCheckOutTimes(userId, targetDate, result);
            result.totalOrderValue = getTotalOrderValueForDay(userId, targetDate);

            System.debug(LoggingLevel.INFO, 'EOD User: ' + userId);
            System.debug(LoggingLevel.INFO, 'Scheduled Call - ' + result.scheduledCalls);
            System.debug(LoggingLevel.INFO, 'Total Calls - ' + result.totalCalls);
            System.debug(LoggingLevel.INFO, 'Productive Calls - ' + result.productiveCalls);
            System.debug(LoggingLevel.INFO, 'Not Visited Outlet - ' + result.notVisitedOutlet);
            System.debug(LoggingLevel.INFO, 'New Outlet Onboarded - ' + result.newOutletOnboarded);
            System.debug(LoggingLevel.INFO, 'DF Transfer - ' + result.dfTransfer);
            System.debug(LoggingLevel.INFO, 'Distributor Visit - ' + result.distributorVisit);
            System.debug(LoggingLevel.INFO, 'First Check in - ' + result.firstCheckInTime);
            System.debug(LoggingLevel.INFO, 'Last Check Out - ' + result.lastCheckOutTime);
            System.debug(LoggingLevel.INFO, 'Total Time Spent - ' + result.totalTimeSpent);
            System.debug(LoggingLevel.INFO, 'Total Order Value - ₹' + result.totalOrderValue);
            return result;
        } catch (Exception e) {
            EODWrapper err = new EODWrapper();
            err.message = 'Error: ' + e.getMessage();
            return err;
        }
    }
    
			/*================================================================================================================================================================*/
    
    //Scheduled Call
    private static Integer getScheduledCallsCount(Id userId, Date today) {
        List<AggregateResult> aggr = [
            SELECT COUNT(Id) cnt
            FROM Visit_Task__c
            WHERE Visitor_Name__c = :userId
            AND Task_Planned_Date__c = :today
            AND (Account__c != null OR Distributor__c != null)
            AND Type_Formula__c != 'Distributor Type'
        ];
        return aggr.isEmpty() ? 0 : Integer.valueOf(aggr[0].get('cnt'));
    }

    //Total & Productive Calls, Not Visited Outlet, Distributor visit
    private static void aggregateVisitTaskMetrics(Id userId, Date today, EODWrapper result) {
        List<Visit_Task__c> tasks = [
            SELECT Id, Status__c, Order_Placed__c, Account__c, Distributor__c , Type_Formula__c
            FROM Visit_Task__c
            WHERE Visitor_Name__c = :userId
            AND Task_Planned_Date__c = :today
            AND (Account__c != null OR Distributor__c != null)
        ];

        for (Visit_Task__c t : tasks) {
            Boolean isNotStarted = (t.Status__c == STATUS_NOT_STARTED);
            if (!isNotStarted) result.totalCalls++;
            if (t.Order_Placed__c == true) result.productiveCalls++;
            if (t.Account__c != null && isNotStarted) result.notVisitedOutlet++;
            //if (t.Distributor__c != null && !isNotStarted) result.distributorVisit++;
            if (t.Type_Formula__c == 'Distributor Type') result.distributorVisit++;
        }
    }
	
    //New Outlet Onboarded
    private static Integer getNewOutletOnboardedCount(Id userId, Date today) {
        Datetime startOfDay = Datetime.newInstance(today, Time.newInstance(0, 0, 0, 0));
        Datetime endOfDay = startOfDay.addDays(1);
        List<AggregateResult> aggr = [
            SELECT COUNT(Id) cnt
            FROM Account
            WHERE CreatedById = :userId
            AND RecordType.Name = 'Retailer'
            AND CreatedDate >= :startOfDay
            AND CreatedDate < :endOfDay
        ];
        return aggr.isEmpty() ? 0 : Integer.valueOf(aggr[0].get('cnt'));
    }

    //DF Transfer
    private static Integer getDfTransferCount(Id userId, Date today) {
        Datetime startOfDay = Datetime.newInstance(today, Time.newInstance(0, 0, 0, 0));
        Datetime endOfDay = startOfDay.addDays(1);
        List<AggregateResult> aggr = [
            SELECT COUNT(Id) cnt
            FROM Freezer_Request__c
            WHERE CreatedById = :userId
            AND CreatedDate >= :startOfDay
            AND CreatedDate < :endOfDay
        ];
        return aggr.isEmpty() ? 0 : Integer.valueOf(aggr[0].get('cnt'));
    }

    //First Check & Last Check and Total Time Spent
    private static void setCheckInCheckOutTimes(Id userId, Date today, EODWrapper result) {
        List<Visit_Task__c> tasks = [
            SELECT Id, Checked_In_Time__c, Checked_Out_Time__c, End_Call_Time__c
            FROM Visit_Task__c
            WHERE Visitor_Name__c = :userId
            AND Task_Planned_Date__c = :today
            AND (Checked_In_Time__c != null OR Checked_Out_Time__c != null OR End_Call_Time__c != null)
        ];

        Datetime firstCheckIn = null;
        Datetime lastCheckOut = null;

        for (Visit_Task__c t : tasks) {
            if (t.Checked_In_Time__c != null) {
                if (firstCheckIn == null || t.Checked_In_Time__c < firstCheckIn) firstCheckIn = t.Checked_In_Time__c;
            }
            Datetime checkout = t.Checked_Out_Time__c != null ? t.Checked_Out_Time__c : t.End_Call_Time__c;
            if (checkout != null && (lastCheckOut == null || checkout > lastCheckOut)) lastCheckOut = checkout;
        }

        if (firstCheckIn != null) result.firstCheckInTime = firstCheckIn.format('h:mm a');
        if (lastCheckOut != null) result.lastCheckOutTime = lastCheckOut.format('h:mm a');
        if (firstCheckIn != null && lastCheckOut != null && lastCheckOut > firstCheckIn) {
            Long diffMs = lastCheckOut.getTime() - firstCheckIn.getTime();
            Long hours = diffMs / (60 * 60 * 1000);
            Long mins = (diffMs / (60 * 1000)) - (hours * 60);
            result.totalTimeSpent = String.valueOf(hours) + 'h ' + String.valueOf(mins) + 'm';
        }
    }

    //Total Order Value
    private static Decimal getTotalOrderValueForDay(Id userId, Date today) {
    List<Order__c> orders = [
        SELECT Id, Total_Order_Value__c
        FROM Order__c
        WHERE OwnerId = :userId
        AND EffectiveDate__c = :today
    ];
    Decimal total = 0;
    for (Order__c o : orders) {
        total += (o.Total_Order_Value__c != null ? o.Total_Order_Value__c : 0);
    }
    return total;
  }

  // Added by hari - Update EOD_Date_Time__c on Attendance__c with current server time on modal submit
  @AuraEnabled
  public static void updateEODDateTime(Id attendanceRecordId) {
    if (attendanceRecordId == null) {
      throw new AuraHandledException('Attendance record Id is required.');
    }
    try {
      List<Attendance__c> attList = [SELECT Id, EOD_Date_Time__c FROM Attendance__c WHERE Id = :attendanceRecordId LIMIT 1];
      if (attList.isEmpty()) {
        throw new AuraHandledException('Attendance record not found or you do not have access to it.');
      }
      Attendance__c att = attList[0];
      att.EOD_Date_Time__c = Datetime.now();
      update att;
    } catch (QueryException e) {
      throw new AuraHandledException('Invalid object or field: ' + e.getMessage());
    } catch (DmlException e) {
      throw new AuraHandledException('Update failed: ' + e.getDmlMessage(0));
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }
}