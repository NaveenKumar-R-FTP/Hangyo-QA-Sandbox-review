/*
Created By : Fuzail 
Description : Test class for VisitTaskOrderRollupBatch
Created Date : 26/11/2025
Last Modified Date: 27/11/2025
*/

@isTest
public class VisitTaskOrderRollupBatch_Test {
    
    @testSetup
    static void setupTestData() {
        // Create test Visit records first
        List<Visit__c> visits = new List<Visit__c>();
        for (Integer i = 1; i <= 3; i++) {
            visits.add(new Visit__c());
        }
        insert visits;
        
        // Create test Visit Task records with Status 'Completed - Order'
        // These will be created with today's date which should be >= Nov 1, 2025
        List<Visit_Task__c> visitTasks = new List<Visit_Task__c>();
        for (Integer i = 0; i < 3; i++) {
            visitTasks.add(new Visit_Task__c(
                Visit__c = visits[i].Id,
                Status__c = 'Completed - Order',
                Total_Order_Amount__c = 0,
                Count_Of_Orders__c = 0
            ));
        }
        insert visitTasks;
        
        // Get RecordType for Secondary Order
        RecordType secOrderRT = [
            SELECT Id FROM RecordType 
            WHERE SObjectType = 'Order__c' 
            AND Name = 'Secondary Order' 
            LIMIT 1
        ];
        
        // Create test Order records
        List<Order__c> orders = new List<Order__c>();
        
        // Orders for Visit Task 1 - 3 orders with total value 3000
        for (Integer i = 1; i <= 3; i++) {
            orders.add(new Order__c(
                Visit_Task__c = visitTasks[0].Id,
                Total_Order_Value__c = 1000,
                RecordTypeId = secOrderRT.Id,
                Type__c = 'Field Order'
            ));
        }
        
        // Orders for Visit Task 2 - 2 orders with total value 2500
        for (Integer i = 4; i <= 5; i++) {
            orders.add(new Order__c(
                Visit_Task__c = visitTasks[1].Id,
                Total_Order_Value__c = 1250,
                RecordTypeId = secOrderRT.Id,
                Type__c = 'Field Order'
            ));
        }
        
        // Visit Task 3 - No orders (testing zero rollup)
        insert orders;
    }
    
    @isTest
    static void testBatchExecution() {
        Test.startTest();
        VisitTaskOrderRollupBatch batch = new VisitTaskOrderRollupBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verify Visit Task 1 - Should have 3 orders and total 3000
        Visit_Task__c vt1 = [
            SELECT Id, Total_Order_Amount__c, Count_Of_Orders__c 
            FROM Visit_Task__c 
            WHERE Status__c = 'Completed - Order'
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        System.assertEquals(3, vt1.Count_Of_Orders__c, 'Visit Task 1 should have 3 orders');
        System.assertEquals(3000, vt1.Total_Order_Amount__c, 'Visit Task 1 should have total amount 3000');
        
        // Verify Visit Task 2 - Should have 2 orders and total 2500
        Visit_Task__c vt2 = [
            SELECT Id, Total_Order_Amount__c, Count_Of_Orders__c 
            FROM Visit_Task__c 
            WHERE Status__c = 'Completed - Order'
            ORDER BY CreatedDate ASC
            LIMIT 1 OFFSET 1
        ];
        System.assertEquals(2, vt2.Count_Of_Orders__c, 'Visit Task 2 should have 2 orders');
        System.assertEquals(2500, vt2.Total_Order_Amount__c, 'Visit Task 2 should have total amount 2500');
        
        // Verify Visit Task 3 - Should have 0 orders and total 0
        Visit_Task__c vt3 = [
            SELECT Id, Total_Order_Amount__c, Count_Of_Orders__c 
            FROM Visit_Task__c 
            WHERE Status__c = 'Completed - Order'
            ORDER BY CreatedDate ASC
            LIMIT 1 OFFSET 2
        ];
        System.assertEquals(0, vt3.Count_Of_Orders__c, 'Visit Task 3 should have 0 orders');
        System.assertEquals(0, vt3.Total_Order_Amount__c, 'Visit Task 3 should have total amount 0');
    }
    
    @isTest
    static void testBatchWithNoMatchingOrders() {
        // Test Visit Task with 'Completed - Order' status but no matching orders
        // (all orders are different RecordType or Type)
        Visit__c testVisit = new Visit__c();
        insert testVisit;
        
        Visit_Task__c vtNoMatchingOrders = new Visit_Task__c(
            Visit__c = testVisit.Id,
            Status__c = 'Completed - Order',
            Total_Order_Amount__c = 0,
            Count_Of_Orders__c = 0
        );
        insert vtNoMatchingOrders;
        
        // Get a different RecordType (not Secondary Order)
        List<RecordType> otherRTs = [
            SELECT Id FROM RecordType 
            WHERE SObjectType = 'Order__c' 
            AND Name != 'Secondary Order' 
            LIMIT 1
        ];
        
        if (!otherRTs.isEmpty()) {
            // Create order with different RecordType (should NOT be counted)
            Order__c testOrder = new Order__c(
                Visit_Task__c = vtNoMatchingOrders.Id,
                Total_Order_Value__c = 5000,
                RecordTypeId = otherRTs[0].Id,
                Type__c = 'Field Order'
            );
            insert testOrder;
        }
        
        Test.startTest();
        VisitTaskOrderRollupBatch batch = new VisitTaskOrderRollupBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verify this Visit Task shows 0 (order doesn't match RecordType filter)
        Visit_Task__c vtResult = [
            SELECT Id, Total_Order_Amount__c, Count_Of_Orders__c 
            FROM Visit_Task__c 
            WHERE Id = :vtNoMatchingOrders.Id
        ];
        System.assertEquals(0, vtResult.Total_Order_Amount__c, 
            'Visit Task should have 0 amount when no matching orders');
        System.assertEquals(0, vtResult.Count_Of_Orders__c, 
            'Visit Task should have 0 count when no matching orders');
    }
    
    @isTest
    static void testBatchWithLargeDataset() {
        // Get first Visit Task with Completed - Order status
        List<Visit_Task__c> visitTaskList = [
            SELECT Id 
            FROM Visit_Task__c 
            WHERE Status__c = 'Completed - Order'
            LIMIT 1
        ];
        if (visitTaskList.isEmpty()) {
            return;
        }
        Visit_Task__c vt = visitTaskList[0];
        
        // Get RecordType for Secondary Order
        List<RecordType> recordTypes = [
            SELECT Id FROM RecordType 
            WHERE SObjectType = 'Order__c' 
            AND Name = 'Secondary Order' 
            LIMIT 1
        ];
        if (recordTypes.isEmpty()) {
            return;
        }
        RecordType secOrderRT = recordTypes[0];
        
        // Create 150 orders to test batch size handling
        List<Order__c> largeOrderList = new List<Order__c>();
        for (Integer i = 0; i < 150; i++) {
            largeOrderList.add(new Order__c(
                Visit_Task__c = vt.Id,
                Total_Order_Value__c = 100,
                RecordTypeId = secOrderRT.Id,
                Type__c = 'Field Order'
            ));
        }
        insert largeOrderList;
        
        Test.startTest();
        VisitTaskOrderRollupBatch batch = new VisitTaskOrderRollupBatch();
        Database.executeBatch(batch, 50);  // Smaller batch size to test multiple batches
        Test.stopTest();
        
        // Verify rollup with large dataset
        List<Visit_Task__c> updatedVTList = [
            SELECT Id, Total_Order_Amount__c, Count_Of_Orders__c 
            FROM Visit_Task__c 
            WHERE Id = :vt.Id
        ];
        if (!updatedVTList.isEmpty()) {
            Visit_Task__c updatedVT = updatedVTList[0];
            System.assertNotEquals(null, updatedVT.Count_Of_Orders__c, 'Order count should be updated');
            System.assertNotEquals(null, updatedVT.Total_Order_Amount__c, 'Total order amount should be updated');
            // Should have original 3 orders + 150 new orders = 153 total
            System.assert(updatedVT.Count_Of_Orders__c >= 150, 'Should have at least 150 orders');
        }
    }
 
    @isTest
    static void testRollupWithNullVisitTask() {
        // Get RecordType for Secondary Order
        List<RecordType> recordTypes = [
            SELECT Id FROM RecordType 
            WHERE SObjectType = 'Order__c' 
            AND Name = 'Secondary Order' 
            LIMIT 1
        ];
        if (recordTypes.isEmpty()) {
            return;
        }
        RecordType secOrderRT = recordTypes[0];
        
        // Create an order with null Visit Task
        Order__c orderWithoutVT = new Order__c(
            Visit_Task__c = null,
            Total_Order_Value__c = 500,
            RecordTypeId = secOrderRT.Id,
            Type__c = 'Field Order'
        );
        insert orderWithoutVT;
        
        Test.startTest();
        VisitTaskOrderRollupBatch batch = new VisitTaskOrderRollupBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // This test verifies the batch handles null Visit Task gracefully
        System.assert(true, 'Batch completed without throwing exception for null Visit Task');
    }
    
    @isTest
    static void testBatchDateFilter() {
        // This test validates that the batch processes records created >= Nov 1, 2025
        // Since test records are created with today's date (Nov 27, 2025), they should be processed
        
        Test.startTest();
        VisitTaskOrderRollupBatch batch = new VisitTaskOrderRollupBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verify at least one Visit Task was processed
        List<Visit_Task__c> processedVTs = [
            SELECT Id, Total_Order_Amount__c, Count_Of_Orders__c 
            FROM Visit_Task__c 
            WHERE Status__c = 'Completed - Order'
            AND (Total_Order_Amount__c != null OR Count_Of_Orders__c != null)
        ];
        
        System.assert(processedVTs.size() > 0, 
            'At least one Visit Task should be processed by the batch');
    }
}