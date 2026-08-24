@IsTest
private class OutletSummaryControllerTest {
    
    @TestSetup
    static void setupData() {
             insert new RetailerCodeSetting__c(
            Name = 'SF',
            Latest_Code__c = 0
        );
        // Get System Administrator user
        User sysUser = [SELECT Id, Name FROM User 
                       WHERE Profile.Name = 'System Administrator' 
                       AND IsActive = true 
                       LIMIT 1];
        
        System.runAs(sysUser) {
            // Get available Record Types for the current user
            Map<String, Id> recordTypeMap = getAvailableRecordTypes();
            
            // Get Distributor Record Type ID (use any available)
            Id distRT = recordTypeMap.containsKey('Distributor') ? recordTypeMap.get('Distributor') : 
                       recordTypeMap.containsKey('Customer') ? recordTypeMap.get('Customer') : 
                       [SELECT Id FROM RecordType WHERE SObjectType = 'Account' LIMIT 1].Id;
            
            // Get Retailer Record Type ID (or use the same if specific not available)
            Id retailRT = recordTypeMap.containsKey('Retailer') ? recordTypeMap.get('Retailer') : 
                         recordTypeMap.containsKey('Customer') ? recordTypeMap.get('Customer') : 
                         distRT;
            
            // Create User Role Hierarchy for testing
            UserRole parentRole = new UserRole(
                Name = 'Parent Role',
                DeveloperName = 'Parent_Role'
            );
            insert parentRole;
            
            UserRole childRole = new UserRole(
                Name = 'Child Role',
                DeveloperName = 'Child_Role',
                ParentRoleId = parentRole.Id
            );
            insert childRole;
            
            // Create subordinate user
            Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
            User subordinateUser = new User(
                FirstName = 'Test',
                LastName = 'Subordinate',
                Alias = 'tsub',
                Email = 'test.subordinate@test.com',
                Username = 'test.subordinate@test.com.test' + System.currentTimeMillis(),
                ProfileId = p.Id,
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                TimeZoneSidKey = 'America/Los_Angeles',
                UserRoleId = childRole.Id,
                IsActive = true
            );
            insert subordinateUser;
            
            // Update sysUser to have parent role
            sysUser.UserRoleId = parentRole.Id;
            update sysUser;
            
            // Create Distributor Account
            Account distributor1 = new Account(
                Name = 'Test Distributor 1',
                OwnerId = sysUser.Id
            );
            Visit__c v = new Visit__c(
            OwnerId = sysUser.Id,
            Visit_Planned_Date__c = Date.today().toStartOfMonth().addDays(1)
        );
        insert v;
            
            // Set RecordTypeId only if we have a valid one
            if (distRT != null) {
                distributor1.RecordTypeId = distRT;
            }
            
            insert distributor1;
            
            // Create Retailer Accounts
            List<Account> retailers = new List<Account>();
            for(Integer i = 0; i < 5; i++) {
                Account retailer = new Account(
                    Name = 'Test Retailer ' + i,
                    OwnerId = i < 3 ? sysUser.Id : subordinateUser.Id
                );
                if (retailRT != null) {
                    retailer.RecordTypeId = retailRT;
                }
                retailers.add(retailer);
            }
            insert retailers;
            
            // Create Beats
            Beat__c beat1 = new Beat__c(
                Name = 'Test Beat 1',
                OwnerId = sysUser.Id
            );
            
            Beat__c beat2 = new Beat__c(
                Name = 'Test Beat 2',
                OwnerId = subordinateUser.Id
            );
            insert new List<Beat__c>{beat1, beat2};
            
            // Create Visit Tasks for current month (checked in with orders)
            List<Visit_Task__c> visitTasks = new List<Visit_Task__c>();
            Date today = Date.today();
            Date startOfMonth = today.toStartOfMonth();
            
            // Create visited tasks with orders (for UPC calculation)
            for(Integer i = 0; i < 3; i++) {
                Visit_Task__c vt = new Visit_Task__c(
                    Visitor_Name__c = sysUser.Id,
                    Retailer__c = retailers[i].Id,
                    Visit__c =v.id,
                    Checked_In_Time__c = DateTime.newInstance(startOfMonth.addDays(i), Time.newInstance(10, 0, 0, 0)),
                    Task_Planned_Date__c = startOfMonth.addDays(i)
                );
                visitTasks.add(vt);
            }
            
            // Create visited tasks without orders (for zero order calculation)
            for(Integer i = 3; i < 4; i++) {
                Visit_Task__c vt = new Visit_Task__c(
                    Visitor_Name__c = sysUser.Id,
                    Retailer__c = retailers[i].Id,
                     Visit__c =v.id,
                    Checked_In_Time__c = DateTime.newInstance(startOfMonth.addDays(i), Time.newInstance(10, 0, 0, 0)),
                    Task_Planned_Date__c = startOfMonth.addDays(i)
                );
                visitTasks.add(vt);
            }
            
            // Create unvisited tasks (for UTC calculation)
            for(Integer i = 4; i < 5; i++) {
                Visit_Task__c vt = new Visit_Task__c(
                    Visitor_Name__c = sysUser.Id,
                     Visit__c =v.id,
                    Retailer__c = retailers[i].Id,
                    Checked_In_Time__c = null, // Not visited
                    Task_Planned_Date__c = startOfMonth.addDays(i)
                );
                visitTasks.add(vt);
            }
            
            // Create subordinate user visits
            Visit_Task__c subVisit = new Visit_Task__c(
                Visitor_Name__c = subordinateUser.Id,
                Retailer__c = retailers[0].Id,
                 Visit__c =v.id,
                Checked_In_Time__c = DateTime.newInstance(today, Time.newInstance(9, 0, 0, 0)),
                Task_Planned_Date__c = today
            );
            visitTasks.add(subVisit);
            
            insert visitTasks;
            
            // Create Orders for visited tasks (for UPC)
            List<Order__c> orders = new List<Order__c>();
            for(Integer i = 0; i < 3; i++) {
                orders.add(new Order__c(
                    Visit_Task__c = visitTasks[i].Id,
                    Total_Order_Value__c = 1000 * (i + 1),
                    EffectiveDate__c = startOfMonth.addDays(i)
                ));
            }
            
            // Create order for subordinate user
            orders.add(new Order__c(
                Visit_Task__c = visitTasks[5].Id, // Subordinate visit
                Total_Order_Value__c = 500,
                EffectiveDate__c = today
            ));
            
            insert orders;
        }
    }
    
    // Helper method to get available Record Types for current user
    private static Map<String, Id> getAvailableRecordTypes() {
        Map<String, Id> recordTypeMap = new Map<String, Id>();
        
        try {
            // Try to get RecordTypes that are available to the current user
            for(RecordType rt : [
                SELECT Id, DeveloperName, Name 
                FROM RecordType 
                WHERE SObjectType = 'Account'
                AND IsActive = true
            ]) {
                recordTypeMap.put(rt.DeveloperName, rt.Id);
                recordTypeMap.put(rt.Name, rt.Id);
            }
        } catch(Exception e) {
            // If we can't query RecordTypes, return empty map
            System.debug('Error querying RecordTypes: ' + e.getMessage());
        }
        
        return recordTypeMap;
    }
    
    @IsTest
    static void testGetOutletSummaryFTD() {
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Test.startTest();
        Map<String, Object> result = OutletSummaryController.getOutletSummary(sysUser.Id, 'FTD');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert((Integer)result.get('totalTC') >= 0, 'Total TC should be >= 0');
    }
    
    @IsTest
    static void testGetOutletSummaryMTD() {
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Test.startTest();
        Map<String, Object> result = OutletSummaryController.getOutletSummary(sysUser.Id, 'MTD');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert((Integer)result.get('totalTC') >= 0, 'Total TC should be >= 0');
    }
    
    @IsTest
    static void testGetOutletSummaryNoUserId() {
        Test.startTest();
        Map<String, Object> result = OutletSummaryController.getOutletSummary(null, 'MTD');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null when userId is null');
    }
    
    @IsTest
    static void testGetBulkOutletSummary() {
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        User subordinateUser = [SELECT Id FROM User WHERE LastName = 'Subordinate' LIMIT 1];
        
        Test.startTest();
        Map<String, OutletSummaryController.SummaryMetrics> result = 
            OutletSummaryController.getBulkOutletSummary(new List<Id>{sysUser.Id, subordinateUser.Id}, 'MTD');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(2, result.size(), 'Should return metrics for both users');
    }
    
    @IsTest
    static void testGetBulkOutletSummaryEmptyList() {
        Test.startTest();
        Map<String, OutletSummaryController.SummaryMetrics> result = 
            OutletSummaryController.getBulkOutletSummary(new List<Id>(), 'MTD');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Result map should be empty for empty input');
    }
    
    @IsTest
    static void testGetSubordinateHierarchy() {
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Test.startTest();
        OutletSummaryController.HierarchyData result = 
            OutletSummaryController.getSubordinateHierarchy(sysUser.Id, Date.today().month(), Date.today().year());
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.currentUser, 'Current user should not be null');
    }
    
    @IsTest
    static void testGetSubordinateHierarchyNoUserId() {
        Test.startTest();
        OutletSummaryController.HierarchyData result = 
            OutletSummaryController.getSubordinateHierarchy(null, Date.today().month(), Date.today().year());
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null when userId is null');
    }
    
    @IsTest
    static void testGetSubordinatesIncludesSelf() {
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Test.startTest();
        List<Map<String, Object>> result = 
            OutletSummaryController.getSubordinatesincludeself(sysUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(!result.isEmpty(), 'Result should not be empty');
    }
    
    @IsTest
    static void testGetUserOwnMetricsOnly() {
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        User subordinateUser = [SELECT Id FROM User WHERE LastName = 'Subordinate' LIMIT 1];
        
        Test.startTest();
        Map<String, OutletSummaryController.SummaryMetrics> result = 
            OutletSummaryController.getUserOwnMetricsOnly(new List<Id>{sysUser.Id, subordinateUser.Id}, 'MTD');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(2, result.size(), 'Should return metrics for both users');
    }
    
    @IsTest
    static void testGetUserOwnMetricsOnlyEmptyList() {
        Test.startTest();
        Map<String, OutletSummaryController.SummaryMetrics> result = 
            OutletSummaryController.getUserOwnMetricsOnly(new List<Id>(), 'MTD');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Result map should be empty for empty input');
    }
    
    @IsTest
    static void testSummaryMetricsClass() {
        Test.startTest();
        OutletSummaryController.SummaryMetrics metrics = new OutletSummaryController.SummaryMetrics();
        metrics.distributors = 5;
        metrics.beats = 10;
        metrics.outlets = 50;
        metrics.outletPlanned = 40;
        metrics.upc = 30;
        metrics.utc = 10;
        metrics.totalTC = 40;
        metrics.productiveCalls = 30;
        metrics.zeroOrderCount = 5;
        metrics.coveragePct = 75.0;
        metrics.productivity = 75.0;
        metrics.netValue = 10000.0;
        Test.stopTest();
        
        System.assertEquals(5, metrics.distributors, 'Distributors should be set correctly');
        System.assertEquals(10, metrics.beats, 'Beats should be set correctly');
        System.assertEquals(50, metrics.outlets, 'Outlets should be set correctly');
        System.assertEquals(30, metrics.upc, 'UPC should be set correctly');
        System.assertEquals(75.0, metrics.coveragePct, 'Coverage percentage should be set correctly');
    }
    
    @IsTest
    static void testHierarchyDataClass() {
        Test.startTest();
        OutletSummaryController.HierarchyData hierarchyData = new OutletSummaryController.HierarchyData();
        hierarchyData.currentUser = new Map<String, Object>{
            'userId' => UserInfo.getUserId(),
            'userName' => 'Test User'
        };
        hierarchyData.directReports = new List<Map<String, Object>>();
        Test.stopTest();
        
        System.assertNotEquals(null, hierarchyData.currentUser, 'Current user should not be null');
        System.assertNotEquals(null, hierarchyData.directReports, 'Direct reports should not be null');
    }
    
    @IsTest
    static void testErrorHandling() {
        Test.startTest();
        Map<String, OutletSummaryController.SummaryMetrics> result = 
            OutletSummaryController.getUserOwnMetricsOnly(new List<Id>{'001000000000000'}, 'MTD');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should handle invalid user IDs gracefully');
    }
    
    // Test the collectAllSubordinateIdsBulk method directly
    @IsTest
    static void testCollectAllSubordinateIdsBulk() {
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Test.startTest();
        Set<Id> allUserIds = new Set<Id>();
        allUserIds.add(sysUser.Id);
        
        // We need to test the private method indirectly through public methods
        Map<String, Object> result = OutletSummaryController.getOutletSummary(sysUser.Id, 'MTD');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should return result without error');
    }
}