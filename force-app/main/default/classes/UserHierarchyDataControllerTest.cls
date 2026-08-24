@IsTest
public class UserHierarchyDataControllerTest {
    
    @TestSetup
    static void setupData() {
        
        User u = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Id secOrderRT = getRecordTypeId('Order__c','Secondary_Order');
        
        // Visit (TODAY)
        Visit__c v = new Visit__c(
            OwnerId = u.Id,
            Visitor_Name__c = u.Id,
            Visit_Planned_Date__c = Date.today()
        );
        insert v;
        
        // Visit Task
        Visit_Task__c vt = new Visit_Task__c(
            Visit__c = v.Id,
            Visitor_Name__c = u.Id,
            Task_Planned_Date__c = Date.today(),
            Order_Placed__c = true
        );
        insert vt;
        
        // Order
        Order__c ord = new Order__c(
            OwnerId = u.Id,
            RecordTypeId = secOrderRT,
            Visit__c = v.Id,
            Visit_Task__c = vt.Id,
            Total_Order_Value__c = 5000
        );
        insert ord;
        
        // Order Line Items (for LPC/TLC)
        insert new List<Order_Line_Item__c>{
            new Order_Line_Item__c(Order__c = ord.Id),
            new Order_Line_Item__c(Order__c = ord.Id),
            new Order_Line_Item__c(Order__c = ord.Id) // duplicate
        };
    }
    
    @IsTest
    static void testGetHierarchyWithMetrics() {
        
        User u = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Test.startTest();
        UserHierarchyDataController.HierarchyResponse resp =
            UserHierarchyDataController.getHierarchyWithMetrics(u.Id);
        Test.stopTest();
        
        // Basic assertions
        System.assertNotEquals(null, resp);
        System.assertNotEquals(null, resp.parentUser);
        
        // Metrics should be populated
        System.assert(resp.parentUser.metrics.plannedCount >= 1);
        System.assert(resp.parentUser.metrics.netPay > 0);
        //System.assert(resp.parentUser.metrics.qty > 0);
     //   System.assert(resp.parentUser.metrics.lpcCount > 0);
     //   System.assert(resp.parentUser.metrics.tlcCount > 0);
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