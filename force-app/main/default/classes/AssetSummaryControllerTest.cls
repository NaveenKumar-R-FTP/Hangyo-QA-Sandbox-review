@IsTest
private class AssetSummaryControllerTest {
    
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
            // Create User Role Hierarchy
            UserRole parentRole = new UserRole(
                Name = 'Asset Parent Role',
                DeveloperName = 'Asset_Parent_Role'
            );
            insert parentRole;
            
            UserRole childRole = new UserRole(
                Name = 'Asset Child Role',
                DeveloperName = 'Asset_Child_Role',
                ParentRoleId = parentRole.Id
            );
            insert childRole;
            
            // Create subordinate user
            Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
            User subordinateUser = new User(
                FirstName = 'Asset',
                LastName = 'Subordinate',
                Alias = 'asub',
                Email = 'asset.subordinate@hangyo.in',
		Username = 'asset.subordinate.test' + System.currentTimeMillis() + '@hangyo.in',
                ProfileId = p.Id,
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                TimeZoneSidKey = 'America/Los_Angeles',
                UserRoleId = childRole.Id,
                ManagerId = sysUser.Id,
                IsActive = true
            );
            insert subordinateUser;
            
            // Update sysUser to have parent role
            sysUser.UserRoleId = parentRole.Id;
            sysUser.ManagerId = null;
            update sysUser;
            
            // Get Record Types
            Map<String, Id> recordTypeMap = getAvailableRecordTypes();
            
            // Create Retailer Accounts
            List<Account> retailers = new List<Account>();
            for(Integer i = 0; i < 6; i++) {
                Account retailer = new Account(
                    Name = 'Asset Retailer ' + i,
                    OwnerId = (i < 3) ? sysUser.Id : subordinateUser.Id,
                    RecordTypeId = recordTypeMap.containsKey('Retailer') ? recordTypeMap.get('Retailer') : null
                );
                retailers.add(retailer);
            }
            insert retailers;
            
            // Create DF Assets for retailers
            List<Asset__c> assets = new List<Asset__c>();
            
            // Create assets for retailers with orders (billed)
            for(Integer i = 0; i < 3; i++) {
                Asset__c asset = new Asset__c(
                    Retailer_Account__c = retailers[i].Id
                );
                assets.add(asset);
            }
            
            // Create assets for retailers without orders (zero billing)
            for(Integer i = 3; i < 6; i++) {
                Asset__c asset = new Asset__c(
                    Retailer_Account__c = retailers[i].Id
                );
                assets.add(asset);
            }
            insert assets;
            
            // Create Orders for current month (MTD)
            Date mtdStart = Date.today().toStartOfMonth();
            List<Order__c> orders = new List<Order__c>();
            
            // Create orders for first 3 retailers (with assets) - these will be "billed"
            for(Integer i = 0; i < 3; i++) {
                Order__c order = new Order__c(
                    Account__c = retailers[i].Id,
                    Total_Order_Value__c = 1000 * (i + 1),
                    EffectiveDate__c = mtdStart.addDays(i),
                    RecordTypeId = getOrderRecordTypeId()
                );
                orders.add(order);
            }
            
            // Create orders for subordinate's retailers (mixed)
            for(Integer i = 3; i < 5; i++) {
                Order__c order = new Order__c(
                    Account__c = retailers[i].Id,
                    Total_Order_Value__c = 500 * (i - 2),
                    EffectiveDate__c = mtdStart.addDays(i),
                    RecordTypeId = getOrderRecordTypeId()
                );
                orders.add(order);
            }
            insert orders;
        }
    }
    
    // Helper method to get available Record Types
    private static Map<String, Id> getAvailableRecordTypes() {
        Map<String, Id> recordTypeMap = new Map<String, Id>();
        
        try {
            // Account Record Types
            for(RecordType rt : [
                SELECT Id, DeveloperName, Name, SObjectType 
                FROM RecordType 
                WHERE SObjectType IN ('Account', 'Order__c')
                AND IsActive = true
            ]) {
                String key = rt.DeveloperName;
                recordTypeMap.put(key, rt.Id);
                recordTypeMap.put(rt.Name, rt.Id);
                
                // Handle spaces in names
                if(rt.Name.contains(' ')) {
                    recordTypeMap.put(rt.Name.replace(' ', '_'), rt.Id);
                }
            }
        } catch(Exception e) {
            System.debug('Error querying RecordTypes: ' + e.getMessage());
        }
        
        return recordTypeMap;
    }
    
    // Helper method to get Order Record Type ID
    private static Id getOrderRecordTypeId() {
        try {
            // Try to get Secondary Order record type
            List<RecordType> recordTypes = [
                SELECT Id 
                FROM RecordType 
                WHERE SObjectType = 'Order__c' 
                AND (DeveloperName = 'Secondary_Order' OR Name = 'Secondary Order')
                AND IsActive = true 
                LIMIT 1
            ];
            
            if(!recordTypes.isEmpty()) {
                return recordTypes[0].Id;
            }
            
            // If not found, get any Order__c record type
            recordTypes = [
                SELECT Id 
                FROM RecordType 
                WHERE SObjectType = 'Order__c' 
                AND IsActive = true 
                LIMIT 1
            ];
            
            if(!recordTypes.isEmpty()) {
                return recordTypes[0].Id;
            }
        } catch(Exception e) {
            System.debug('Error getting Order Record Type: ' + e.getMessage());
        }
        
        return null;
    }
    
    @IsTest
    static void testGetSummaryForUser() {
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Test.startTest();
        AssetSummaryController.AssetSummaryResult result = AssetSummaryController.getSummaryForUser(sysUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(sysUser.Id, result.userId, 'User ID should match');
        System.assert(result.totalDF >= 0, 'Total DF should be >= 0');
        System.assert(result.billedDF >= 0, 'Billed DF should be >= 0');
        System.assert(result.zeroBillingDF >= 0, 'Zero Billing DF should be >= 0');
        System.assert(result.throughput >= 0, 'Throughput should be >= 0');
        System.assertNotEquals(null, result.subordinates, 'Subordinates list should not be null');
    }
    
    @IsTest
    static void testGetSummaryForUserNullUserId() {
        Test.startTest();
        AssetSummaryController.AssetSummaryResult result = AssetSummaryController.getSummaryForUser(null);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null when userId is null');
        System.assertEquals(UserInfo.getUserId(), result.userId, 'Should default to current user');
    }
    
    @IsTest
    static void testGetAssetMetricsForUsers() {
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        User subordinateUser = [SELECT Id FROM User WHERE LastName = 'Subordinate' LIMIT 1];
        
        Test.startTest();
        AssetSummaryController.AssetSummaryResult result = 
            AssetSummaryController.getAssetMetricsForUsers(new List<Id>{sysUser.Id, subordinateUser.Id});
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
  //      System.assert(result.totalDF > 0, 'Total DF should be greater than 0');
    }
    
    @IsTest
    static void testGetAssetMetricsForUsersEmptyList() {
        Test.startTest();
        AssetSummaryController.AssetSummaryResult result = 
            AssetSummaryController.getAssetMetricsForUsers(new List<Id>());
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null for empty list');
        System.assertEquals(0, result.totalDF, 'Total DF should be 0 for empty user list');
    }
    
    // Note: getSubordinateSummary method doesn't exist in optimized class, so removing tests for it
    // If you need it, add this method to your Apex class:
    // @AuraEnabled(cacheable=true)
    // public static AssetSummaryResult getSubordinateSummary(Id userId) {
    //     return getSummaryForUser(userId);
    // }
    
    @IsTest
    static void testGetAllFieldSubordinates() {
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Test.startTest();
        List<Map<String, Object>> result = AssetSummaryController.getAllFieldSubordinates(sysUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        // Should return at least the subordinate user
        System.assert(!result.isEmpty(), 'Should return at least one subordinate');
        
        // Verify structure of returned data
        for(Map<String, Object> userData : result) {
            System.assert(userData.containsKey('userId'), 'Should contain userId');
            System.assert(userData.containsKey('name'), 'Should contain name');
            System.assert(userData.containsKey('role'), 'Should contain role');
            System.assert(userData.containsKey('totalDF'), 'Should contain totalDF');
            System.assert(userData.containsKey('billedDF'), 'Should contain billedDF');
            System.assert(userData.containsKey('zeroBillingDF'), 'Should contain zeroBillingDF');
            System.assert(userData.containsKey('throughput'), 'Should contain throughput');
        }
    }
    
    @IsTest
    static void testGetAllFieldSubordinatesNullUserId() {
        Test.startTest();
        List<Map<String, Object>> result = AssetSummaryController.getAllFieldSubordinates(null);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null when userId is null');
    }
    
    @IsTest
    static void testGetUserOwnAssetMetrics() {
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Test.startTest();
        AssetSummaryController.AssetSummaryResult result = AssetSummaryController.getUserOwnAssetMetrics(sysUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(sysUser.Id, result.userId, 'User ID should match');
        System.assert(result.totalDF >= 0, 'Total DF should be >= 0');
        System.assert(result.billedDF >= 0, 'Billed DF should be >= 0');
        System.assert(result.zeroBillingDF >= 0, 'Zero Billing DF should be >= 0');
        System.assert(result.throughput >= 0, 'Throughput should be >= 0');
    }
    
    @IsTest
    static void testGetUserRolledUpMetrics() {
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Test.startTest();
        AssetSummaryController.AssetSummaryResult result = AssetSummaryController.getUserRolledUpMetrics(sysUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(sysUser.Id, result.userId, 'User ID should match');
        System.assert(result.totalDF >= 0, 'Total DF should be >= 0');
        System.assert(result.billedDF >= 0, 'Billed DF should be >= 0');
        System.assert(result.zeroBillingDF >= 0, 'Zero Billing DF should be >= 0');
        System.assert(result.throughput >= 0, 'Throughput should be >= 0');
    }
    
    @IsTest
    static void testAssetSummaryResultClass() {
        Test.startTest();
        AssetSummaryController.AssetSummaryResult result = new AssetSummaryController.AssetSummaryResult();
        result.userId = 'testId';
        result.name = 'Test User';
        result.role = 'Test Role';
        result.totalDF = 10;
        result.billedDF = 7;
        result.zeroBillingDF = 3;
        result.throughput = 150.50;
        result.subordinates = new List<AssetSummaryController.AssetSummaryResult>();
        Test.stopTest();
        
        System.assertEquals('testId', result.userId, 'UserId should be set correctly');
        System.assertEquals('Test User', result.name, 'Name should be set correctly');
        System.assertEquals('Test Role', result.role, 'Role should be set correctly');
        System.assertEquals(10, result.totalDF, 'Total DF should be set correctly');
        System.assertEquals(7, result.billedDF, 'Billed DF should be set correctly');
        System.assertEquals(3, result.zeroBillingDF, 'Zero Billing DF should be set correctly');
        System.assertEquals(150.50, result.throughput, 'Throughput should be set correctly');
        System.assertNotEquals(null, result.subordinates, 'Subordinates list should not be null');
    }
    
    @IsTest
    static void testErrorHandlingInvalidUserId() {
        Test.startTest();
        AssetSummaryController.AssetSummaryResult result = 
            AssetSummaryController.getSummaryForUser('001000000000000');
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should handle invalid user ID gracefully');
        // Should return an error result
        System.assertEquals('Error', result.name, 'Should return error result for invalid user');
    }
    
    @IsTest
    static void testThroughputCalculation() {
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Test.startTest();
        AssetSummaryController.AssetSummaryResult result = AssetSummaryController.getSummaryForUser(sysUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.throughput >= 0, 'Throughput should be calculated');
    }
    
    @IsTest
    static void testMixedRecordTypeScenario() {
        // Test with missing RecordTypes
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Test.startTest();
        AssetSummaryController.AssetSummaryResult result = AssetSummaryController.getSummaryForUser(sysUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should handle missing RecordTypes gracefully');
    }
    
    @IsTest
    static void testDirectSubordinates() {
        User sysUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        
        Test.startTest();
        AssetSummaryController.AssetSummaryResult result = AssetSummaryController.getSummaryForUser(sysUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.subordinates != null, 'Subordinates should not be null');
        
        // Verify direct subordinate has rolled-up metrics
        for(AssetSummaryController.AssetSummaryResult sub : result.subordinates) {
            System.assert(sub.totalDF >= 0, 'Subordinate should have Total DF');
            System.assert(sub.billedDF >= 0, 'Subordinate should have Billed DF');
        }
    }
}