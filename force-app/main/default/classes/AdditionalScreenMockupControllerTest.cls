@IsTest
public class AdditionalScreenMockupControllerTest {
    
    
    @TestSetup
    static void setupData() {
        
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        insert new RetailerCodeSetting__c(
            Name = 'SF',
            Latest_Code__c = 0
        );
        
        Id secOrderRT = getRecordTypeId('Order__c','Secondary_Order');
        Id targetRT   = getRecordTypeId('Sales_Target__c','Sales_Target_Month');
        Id distRT     = getRecordTypeId('Account','Distributor');
        Id retailRT   = getRecordTypeId('Account','Retailer');
        
        insert new Account(
            Name = 'Distributor 1',
            OwnerId = sysUser.Id,
            RecordTypeId = distRT
        );
        
        insert new Account(
            Name = 'Retail Outlet 1',
            OwnerId = sysUser.Id,
            RecordTypeId = retailRT
        );
        
        insert new Beat__c(
            Name = 'Beat 1',
            OwnerId = sysUser.Id
        );
        
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
    }
    
    @IsTest
    static void testGetHierarchyWithMetrics() {
        
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Test.startTest();
        AdditionalScreenMockupController.getKpiCounts(sysUser.Id);
        Test.stopTest();
    }
    
    private static Id getRecordTypeId(String obj, String devName) {
        return [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = :obj 
            AND DeveloperName = :devName 
            LIMIT 1
        ].Id;
    }
}