@IsTest
public class HangyoDashboardControllerTest {
    // -----------------------------------------
    // TEST SETUP – RUNS IN SEPARATE TRANSACTION
    // -----------------------------------------
    
    @TestSetup
    static void setupData() {
        
        // Get existing System Admin user
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        // Record Type helper
        Id secOrderRT = getRecordTypeId('Order__c','Secondary_Order');
        Id targetRT   = getRecordTypeId('Sales_Target__c','Sales_Target_Month');
        
        Visit__c v = new Visit__c(
            OwnerId = sysUser.Id,
            Visit_Planned_Date__c = Date.today().toStartOfMonth().addDays(1)
        );
        insert v;
        
        Order__c ord = new Order__c(
            OwnerId = sysUser.Id,
            Total_Order_Value__c = 10000,
            RecordTypeId = secOrderRT,
            Visit__c = v.Id
        );
        insert ord;
        
        Sales_Target__c tgt = new Sales_Target__c(
            Assigned_To__c = sysUser.Id,
            Number_of_Month__c = Integer.valueOf(Date.today().month()),
            Secondary_Sales_Target__c = 25000,
            RecordTypeId = targetRT
        );
        insert tgt;
    }
    
    @IsTest
    static void testGetSubordinateHierarchy() {
        
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Integer m = Date.today().month();
        Integer y = Date.today().year();
        
        Test.startTest();
        HangyoDashboardController.getSubordinateHierarchy(sysUser.Id, m, y);
        Test.stopTest();
    }
    
    @IsTest
    static void testGetPositionWiseOrders() {
        
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Integer m = Date.today().month();
        Integer y = Date.today().year();
        
        Test.startTest();
        HangyoDashboardController.getPositionWiseOrders( m, y);
        Test.stopTest();
    }
    
    @IsTest
    static void testGetUserKPIAndSubordinates() {
        
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Integer m = Date.today().month();
        Integer y = Date.today().year();
        
        Test.startTest();
        HangyoDashboardController.getUserKPIAndSubordinates( m, y);
        Test.stopTest();
    }
    
    @IsTest
    static void testGetSubordinatesCoverage() {
        
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Integer m = Date.today().month();
        Integer y = Date.today().year();
        
        Test.startTest();
        HangyoDashboardController.getSubordinatesCoverage( m, y);
        Test.stopTest();
    }
    
    @IsTest
    static void testGetTeamCoverage() {
        
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Integer m = Date.today().month();
        Integer y = Date.today().year();
        
        Test.startTest();
        HangyoDashboardController.getTeamCoverage(sysUser.Id, m, y);
        Test.stopTest();
    }
    
    @IsTest
    static void testGetSubordinatesnosameroleusers() {
        
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Integer m = Date.today().month();
        Integer y = Date.today().year();
        
        Test.startTest();
        HangyoDashboardController.getSubordinatesnosameroleusers(sysUser.Id);
        Test.stopTest();
    }
    
    @IsTest
    static void testGetChildRolesRecursive() {
        // Get the existing System Admin user
        User sysUser = [SELECT Id, UserRoleId FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Set<Id> roleIds = new Set<Id>();
        
        if (sysUser != null && sysUser.UserRoleId != null) {
            roleIds.add(sysUser.UserRoleId);
        }
        
      //  Test.startTest();
      //  HangyoDashboardController.getChildRolesRecursive(roleIds);
      //  Test.stopTest();
    }
    
    
    public static Id getRecordTypeId(String obj, String devName) {
        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = :obj
            AND DeveloperName = :devName
            LIMIT 1
        ].Id;
    }
    
}