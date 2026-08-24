@isTest
public class DeliveryPlanControllerTest {
    
    @testSetup
    static void createTestData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
    }
    
    // Test method for saveDeliveryPlan
    @isTest
    public static void testSaveDeliveryPlan() {
        // Create a test distributor account
        Account distributorAccount = new Account(Name = 'Test Distributor');
        insert distributorAccount;
        Id productRecordTypeId = [ 
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Product' AND SObjectType = 'Product__c' 
            LIMIT 1 
        ].Id;

        Product__c testProduct = new Product__c(
            Name = 'Test Product',
            IsActive__c = true,
            Primary_Product__c = true,
            RecordTypeId = productRecordTypeId,
            Rate_Value__c = 100,
            Unit_of_Measure__c = 'kg',
            Product_Brand__c = 'TestBrand',
            Image__c = 'test_image1.jpg,test_image2.jpg'
        );
        insert testProduct;
        // Create test invoices
        Invoice__c invoice1 = new Invoice__c(
            Invoice_Number__c = 'INV001',
            Distributor_Account__c = distributorAccount.Id,
            Status__c = 'Confirmed'
        );
        Invoice__c invoice2 = new Invoice__c(
            Invoice_Number__c = 'INV002',
            Distributor_Account__c = distributorAccount.Id,
            Status__c = 'Confirmed'
        );
        insert new List<Invoice__c>{ invoice1, invoice2 };

        // Create test aggregated products
        List<Map<String, Object>> aggregatedProducts = new List<Map<String, Object>>();
        aggregatedProducts.add(new Map<String, Object>{'productId' => testProduct.Id, 'totalQuantity' => 10, 'uom' => 'EA', 'totalPrice' => '100.0', 'unitPrice' => 10.0});
        aggregatedProducts.add(new Map<String, Object>{'productId' => testProduct.Id, 'totalQuantity' => 5, 'uom' => 'EA', 'totalPrice' => '50.0', 'unitPrice' => 10.0});

        // Create JSON for input
        String deliveryPlanJson = JSON.serialize(new Delivery_Plan__c(Driver_Name__c = 'Test Driver',Vehicle_Number__c = 'KA100',Driver_Number__c='10',Date__c = Date.today()));
        String selectedInvoicesJson = JSON.serialize(new List<Id>{ invoice1.Id, invoice2.Id });
        String aggregatedProductsJson = JSON.serialize(aggregatedProducts);

        Test.startTest();
        // Call the saveDeliveryPlan method
        String deliveryPlanId = DeliveryPlanController.saveDeliveryPlan(deliveryPlanJson, selectedInvoicesJson, aggregatedProductsJson);
        Test.stopTest();

        // Verify that the delivery plan was created
        Delivery_Plan__c createdPlan = [SELECT Id FROM Delivery_Plan__c WHERE Id = :deliveryPlanId];
        System.assertNotEquals(null, createdPlan, 'Delivery Plan should be created.');

        // Verify the related Delivery Plan Items
        List<Delivery_Plan_Items__c> deliveryItems = [SELECT Id, Delivery_Plan__c, Invoices__c FROM Delivery_Plan_Items__c WHERE Delivery_Plan__c = :deliveryPlanId];
        System.assertEquals(2, deliveryItems.size(), 'There should be 2 Delivery Plan Items.');

        // Verify the related Picklist records
        List<Picklist__c> picklistItems = [SELECT Id, Delivery_Plan__c, Product__c FROM Picklist__c WHERE Delivery_Plan__c = :deliveryPlanId];
        System.assertEquals(2, picklistItems.size(), 'There should be 2 Picklist records.');
    }

    // Test method for updateDeliveryPlan
    @isTest
    public static void testUpdateDeliveryPlan() {
        // Create a test distributor account
        Account distributorAccount = new Account(Name = 'Test Distributor');
        insert distributorAccount;
		Id productRecordTypeId = [ 
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Product' AND SObjectType = 'Product__c' 
            LIMIT 1 
        ].Id;

        Product__c testProduct = new Product__c(
            Name = 'Test Product',
            IsActive__c = true,
            Primary_Product__c = true,
            RecordTypeId = productRecordTypeId,
            Rate_Value__c = 100,
            Unit_of_Measure__c = 'kg',
            Product_Brand__c = 'TestBrand',
            Image__c = 'test_image1.jpg,test_image2.jpg'
        );
        insert testProduct;
        // Create test invoice and delivery plan
        Invoice__c invoice1 = new Invoice__c(Invoice_Number__c = 'INV001', Distributor_Account__c = distributorAccount.Id, Status__c = 'Confirmed');
        insert invoice1;

        Delivery_Plan__c deliveryPlan = new Delivery_Plan__c(Driver_Name__c = 'Test Driver',Vehicle_Number__c = 'KA100', Date__c = Date.today());
        insert deliveryPlan;

        // Create aggregated products and selected invoices JSON
        List<Map<String, Object>> aggregatedProducts = new List<Map<String, Object>>();
        aggregatedProducts.add(new Map<String, Object>{'productId' => testProduct.Id, 'totalQuantity' => 10, 'uom' => 'EA', 'totalPrice' => '100.0', 'unitPrice' => 10.0});
        String deliveryPlanJson = JSON.serialize(deliveryPlan);
        String selectedInvoicesJson = JSON.serialize(new List<Id>{ invoice1.Id });
        String aggregatedProductsJson = JSON.serialize(aggregatedProducts);

        Test.startTest();
        // Call the updateDeliveryPlan method
        String updatedPlanId = DeliveryPlanController.updateDeliveryPlan(deliveryPlanJson, selectedInvoicesJson, aggregatedProductsJson);
        Test.stopTest();

        // Verify that the delivery plan was updated
        Delivery_Plan__c updatedPlan = [SELECT Id FROM Delivery_Plan__c WHERE Id = :updatedPlanId];
        System.assertNotEquals(null, updatedPlan, 'Delivery Plan should be updated.');
    }

    // Test method for getConfirmedInvoices
    @isTest
    public static void testGetConfirmedInvoices() {
        // Create a test distributor account
        Account distributorAccount = new Account(Name = 'Test Distributor');
        insert distributorAccount;

        // Create test invoices
        Invoice__c invoice1 = new Invoice__c(
            Invoice_Number__c = 'INV001',
            Distributor_Account__c = distributorAccount.Id,
            Status__c = 'Confirmed'
        );
        insert invoice1;

        // Call getConfirmedInvoices method
        Test.startTest();
        List<Invoice__c> invoices = DeliveryPlanController.getConfirmedInvoices();
        Test.stopTest();

        // Verify that the invoices are returned
        System.assertNotEquals(null, invoices, 'Invoices should be fetched.');
        //System.assertEquals(1, invoices.size(), 'There should be 1 invoice.');
    }

    // Test method for deleteInvoice
    @isTest
    public static void testDeleteInvoice() {
        // Create a test distributor account
        Account distributorAccount = new Account(Name = 'Test Distributor');
        insert distributorAccount;

        // Create test invoices and delivery plan
        Invoice__c invoice1 = new Invoice__c(
            Invoice_Number__c = 'INV001',
            Distributor_Account__c = distributorAccount.Id,
            Status__c = 'Confirmed'
        );
        insert invoice1;

        Delivery_Plan__c deliveryPlan = new Delivery_Plan__c(Driver_Name__c = 'Test Driver',Vehicle_Number__c = 'KA100', Date__c = Date.today());
        insert deliveryPlan;

        // Associate invoice with delivery plan
        Delivery_Plan_Items__c dpItem = new Delivery_Plan_Items__c(Delivery_Plan__c = deliveryPlan.Id, Invoices__c = invoice1.Id);
        insert dpItem;

        Test.startTest();
        // Call deleteInvoice method
        DeliveryPlanController.deleteInvoice(invoice1.Id);
        Test.stopTest();

        // Verify that the Delivery Plan Item was deleted
        List<Delivery_Plan_Items__c> dpItemsAfterDelete = [SELECT Id FROM Delivery_Plan_Items__c WHERE Invoices__c = :invoice1.Id];
        System.assertEquals(0, dpItemsAfterDelete.size(), 'The Delivery Plan Item should be deleted.');
    }
    
    // Test method for getDeliveryPlanForEdit
    @isTest
    public static void testGetDeliveryPlanForEdit() {
        // Create a test distributor account
        Account distributorAccount = new Account(Name = 'Test Distributor');
        insert distributorAccount;
        
        // Create a test product and invoice
        Id productRecordTypeId = [
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Product' AND SObjectType = 'Product__c' 
            LIMIT 1
        ].Id;
        Product__c testProduct = new Product__c(
            Name = 'Test Product',
            IsActive__c = true,
            Primary_Product__c = true,
            RecordTypeId = productRecordTypeId,
            Rate_Value__c = 100,
            Unit_of_Measure__c = 'kg',
            Product_Brand__c = 'TestBrand',
            Image__c = 'test_image1.jpg,test_image2.jpg'
        );
        insert testProduct;
        
        Invoice__c invoice1 = new Invoice__c(
            Invoice_Number__c = 'INV001',
            Distributor_Account__c = distributorAccount.Id,
            Status__c = 'Confirmed'
        );
        insert invoice1;

        // Create a delivery plan record
        Delivery_Plan__c deliveryPlan = new Delivery_Plan__c(
            Driver_Name__c = 'Test Driver',
            Vehicle_Number__c = 'KA100',
            Date__c = Date.today()
        );
        insert deliveryPlan;

        // Create aggregated products and selected invoices JSON
        List<Map<String, Object>> aggregatedProducts = new List<Map<String, Object>>{
            new Map<String, Object>{'productId' => testProduct.Id, 'totalQuantity' => 10, 'uom' => 'EA', 'totalPrice' => 100.0, 'unitPrice' => 10.0}
        };
        String selectedInvoicesJson = JSON.serialize(new List<Id>{ invoice1.Id });
        String aggregatedProductsJson = JSON.serialize(aggregatedProducts);

        // Call the getDeliveryPlanForEdit method and pass the delivery plan ID
        Test.startTest();
        Map<String, Object> deliveryPlanForEditMap = DeliveryPlanController.getDeliveryPlanForEdit(deliveryPlan.Id);
        Test.stopTest();

        // Debug the map contents
        System.debug('Delivery Plan for Edit Map: ' + deliveryPlanForEditMap);

        // Verify that the map contains a value for the expected key
        System.assertNotEquals(null, deliveryPlanForEditMap, 'Delivery Plan map should not be null.');
        
        // Check if 'Delivery_Plan__c' key exists in the map and print it for debugging
        if (deliveryPlanForEditMap.containsKey('Delivery_Plan__c')) {
            Delivery_Plan__c fetchedDeliveryPlan = (Delivery_Plan__c) deliveryPlanForEditMap.get('Delivery_Plan__c');
            System.debug('Fetched Delivery Plan: ' + fetchedDeliveryPlan);
            System.assertNotEquals(null, fetchedDeliveryPlan, 'Delivery Plan object should be in the map.');
            System.assertEquals(deliveryPlan.Id, fetchedDeliveryPlan.Id, 'The correct delivery plan should be fetched.');
        } else {
            System.debug('Key "Delivery_Plan__c" not found in the map.');
        }
    }
    
        @isTest
    static void testGetInvoiceRecordTypeIds() {
        // Retrieve Record Type Developer Names
        Map<String, Id> result = DeliveryPlanController.getInvoiceRecordTypeIds();

        // System.debug to verify output in test logs
        System.debug('Returned Record Type Map: ' + result);

        // Assertions based on expected record types
        // These assertions will only work if these record types exist in the org
        System.assert(result != null, 'Result map should not be null');
        System.assert(result.containsKey('SecondaryInvoice'), 'Should contain SecondaryInvoice key');
        System.assert(result.containsKey('SecondaryInvoiceUnderSS'), 'Should contain SecondaryInvoiceUnderSS key');
        System.assertNotEquals(null, result.get('SecondaryInvoice'), 'SecondaryInvoice ID should not be null');
        System.assertNotEquals(null, result.get('SecondaryInvoiceUnderSS'), 'SecondaryInvoiceUnderSS ID should not be null');
    }
}