/*
 * Test Class Name : VisitTaskControllerTest
 * Author          : Shyam
 * CreatedDate     : 22-01-25
 * Description     : Test class for VisitTaskController to cover all its methods.
 */
@isTest
public class VisitTaskControllerTest {

    @testSetup
    static void setup() {
        // Create a test user
        User testUser = [SELECT Id FROM User LIMIT 1];   
        
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
       
        // Query for the RecordType Id for 'Retailer'
        String recordTypeName = 'Retailer';
        RecordType recordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND Name = :recordTypeName LIMIT 1];
    
        // Check if the RecordType exists
        if(recordType == null) {
            //System.debug('RecordType ' + recordTypeName + ' not found');
        }

        // Create test accounts
        Account acc1 = new Account(Name = 'Test Account 1', ShippingStreet = '123 Test St',
                                    ShippingCity = 'Test City', ShippingState = 'Test State',
                                    ShippingPostalCode = '12345', ShippingCountry = 'Test Country', 
                                    PAN_Number__c = 'ABC112',  RecordTypeId = recordType.Id);
        insert acc1;

        // Create a test visit
        Visit__c visit = new Visit__c(Account__c = acc1.Id, Visitor_Name__c = testUser.Id,
                                      Visit_Planned_Date__c = Date.today());
        //system.debug('Visit_Planned_Date__c ='+ visit.Visit_Planned_Date__c);
        insert visit;

        // Create visit tasks
        Visit_Task__c task1 = new Visit_Task__c(Retailer__c = acc1.Id, Visitor_Name__c = testUser.Id, Visit__c = visit.Id,
                                                Task_Planned_Date__c = Date.today(), Status__c = 'Completed');
        Visit_Task__c task2 = new Visit_Task__c(Retailer__c = acc1.Id, Visitor_Name__c = testUser.Id,Visit__c = visit.Id,
                                                Task_Planned_Date__c = Date.today(), Status__c = 'Not Started');
        insert new List<Visit_Task__c>{task1, task2};
            
        //system.debug('Task_Planned_Date__c ='+task1.Task_Planned_Date__c);

        
    }

    @isTest
    static void testGetVisitRecordsByDate() {
        // Prepare input data
        DateTime today = DateTime.now();
        //String selectedDate = Date.today().format();
        String selectedDate = today.format('yyyy-MM-dd');
        Map<String, String> filters = new Map<String, String>{ 'account' => 'Test' };
        List<String> checkboxfilter = new List<String>{ 'Completed' };

        // Call the method
        Test.startTest();
        List<Visit_Task__c> result = VisitTaskController.getVisitRecordsByDate(selectedDate, filters, checkboxfilter);

        Test.stopTest();

        // Validate results
        System.assertNotEquals(null, result, 'Result should not be null');
    }
    @isTest
    static void testGetVisitRecordsByDateTest() {
        // Prepare input data
        DateTime today = DateTime.now();
        //String selectedDate = Date.today().format();
        String selectedDate = today.format('yyyy-MM-dd');
        Map<String, String> filters = new Map<String, String>{ 'account' => 'Test' };
        List<String> checkboxfilter = new List<String>{ 'Completed' };

        // Call the method
        Test.startTest();
        List<Visit_Task__c> result = VisitTaskController.getVisitRecordsByDateTest(selectedDate);

        Test.stopTest();

        // Validate results
        System.assertNotEquals(null, result, 'Result should not be null');
    }

    

    @isTest
    static void testSearchAccounts() {
        // Call the method
        Test.startTest();
        List<Account> accounts = VisitTaskController.searchAccounts('Test');
        Test.stopTest();

        // Validate results
        System.assertEquals(1, accounts.size(), 'Expected 1 account');
        System.assertEquals('Test Account 1', accounts[0].Name, 'Expected account name to match');
    }

    @isTest
static void testCheckAnyVisitTaskInprogress() {
    // Setup test data
    User testUser = [SELECT Id FROM User LIMIT 1];
    Account testAccount = new Account(Name = 'Visit Task Inprogress Account');
    insert testAccount;

    Visit__c visit = new Visit__c(Account__c = testAccount.Id, Visitor_Name__c = testUser.Id,
                                  Visit_Planned_Date__c = Date.today());
    insert visit;

    Visit_Task__c taskInProgress = new Visit_Task__c(
        Retailer__c = testAccount.Id,
        Visitor_Name__c = testUser.Id,
        Visit__c = visit.Id,
        Task_Planned_Date__c = Date.today(),
        Status__c = 'In-Progress'
    );
    insert taskInProgress;

    // Run the method
    Test.startTest();
    Boolean result = VisitTaskController.checkAnyVisitTaskInprogress();
    Test.stopTest();

    System.assertEquals(false, result, 'Should return true when there is an In-Progress task');
}

@isTest
static void testCheckAnyVisitTaskStatus() {
    // Setup test data
    User testUser = [SELECT Id FROM User LIMIT 1];
    Account testAccount = new Account(Name = 'Visit Task Status Account');
    insert testAccount;

    Visit__c visit = new Visit__c(Account__c = testAccount.Id, Visitor_Name__c = testUser.Id,
                                  Visit_Planned_Date__c = Date.today());
    insert visit;

    Visit_Task__c task = new Visit_Task__c(
        Retailer__c = testAccount.Id,
        Visitor_Name__c = testUser.Id,
        Visit__c = visit.Id,
        Task_Planned_Date__c = Date.today(),
        Status__c = 'Not Started'
    );
    insert task;

    // Run the method
    Test.startTest();
    Boolean result = VisitTaskController.checkAnyVisitTaskStatus(task.Id);
    Test.stopTest();

    System.assertEquals(true, result, 'Should return true when status is Not Started');
}
    
@isTest
static void testCheckUserChecking() {
    // Setup test data
    User testUser = [SELECT Id FROM User LIMIT 1];
    Account testAccount = new Account(Name = 'Visit Task Status Account');
    insert testAccount;

    Visit__c visit = new Visit__c(
        Account__c = testAccount.Id,
        Visitor_Name__c = testUser.Id,
        Visit_Planned_Date__c = Date.today()
    );
    insert visit;

    // 1. ✅ Valid case: Checked in and In-Progress
    Visit_Task__c validTask = new Visit_Task__c(
        Retailer__c = testAccount.Id,
        Visitor_Name__c = testUser.Id,
        Visit__c = visit.Id,
        Task_Planned_Date__c = Date.today(),
        Status__c = 'In-Progress',
        Checked_In_Time__c = DateTime.now()
    );
    insert validTask;

    // 2. ❌ Not Started and no check-in
    Visit_Task__c notStartedTask = new Visit_Task__c(
        Retailer__c = testAccount.Id,
        Visitor_Name__c = testUser.Id,
        Visit__c = visit.Id,
        Task_Planned_Date__c = Date.today(),
        Status__c = 'Not Started'
        // No Checked_In_Time__c
    );
    insert notStartedTask;

    // 3. ❌ Shop closed
    Visit_Task__c shopClosedTask = new Visit_Task__c(
        Retailer__c = testAccount.Id,
        Visitor_Name__c = testUser.Id,
        Visit__c = visit.Id,
        Task_Planned_Date__c = Date.today(),
        Status__c = 'In-Progress',
        Checked_In_Time__c = DateTime.now(),
        Unproductive_Reasons__c = 'Shop closed'
    );
    insert shopClosedTask;

    Test.startTest();

    // 1. Check validTask
    VisitTaskController.DFCheckResponse result1 = VisitTaskController.checkUserChecking(validTask.Id , 'NoOrder');
    System.assertEquals(true, result1.isAllowed, 'Should allow No Order');
    System.assertEquals(null, result1.errorMessage, 'No error expected');

    // 2. Check notStartedTask
    VisitTaskController.DFCheckResponse result2 = VisitTaskController.checkUserChecking(notStartedTask.Id , 'DFAction');
    System.assertEquals(false, result2.isAllowed, 'Should not allow DF actions');
    System.assertEquals('Please Check-In to perform DF actions.', result2.errorMessage);

    // 3. Check shopClosedTask
    VisitTaskController.DFCheckResponse result3 = VisitTaskController.checkUserChecking(shopClosedTask.Id , 'DFAction' );
    System.assertEquals(false, result3.isAllowed, 'Should not allow DF actions');
    System.assertEquals('DF actions cannot be performed as shop is closed.', result3.errorMessage);

    // 4. ❌ Record not found (optional)
    VisitTaskController.DFCheckResponse result4 = VisitTaskController.checkUserChecking(Id.valueOf('001000000000000AAA') , 'DFAction');
    System.assertEquals(false, result4.isAllowed, 'Invalid task ID should return false');
    System.assertEquals('Task not found.', result4.errorMessage);

    Test.stopTest();
}

    
}