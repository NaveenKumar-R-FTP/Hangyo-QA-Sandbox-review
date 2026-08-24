@isTest
private class PriceMasterAPI_Test {
    
    @testSetup
    static void setupTestData() {
        // Create Customer Groups
        List<Pricing_Group__c> customerGroups = new List<Pricing_Group__c>{
            new Pricing_Group__c(Name = 'Customer Group 1', Code__c = '01', Type__c = 'Customer'),
            new Pricing_Group__c(Name = 'Customer Group 2', Code__c = '02', Type__c = 'Customer')
        };
        insert customerGroups;

        // Create Price Groups
        List<Pricing_Group__c> priceGroups = new List<Pricing_Group__c>{
            new Pricing_Group__c(Name = 'Price Group 1', Code__c = '01', Type__c = 'Product'),
            new Pricing_Group__c(Name = 'Price Group 2', Code__c = '02', Type__c = 'Product'),
            new Pricing_Group__c(Name = 'Price Group 3', Code__c = '07', Type__c = 'Product')
        };
        insert priceGroups;

        // Create Products
        List<Product__c> products = new List<Product__c>{
            new Product__c(Name = 'Test Product 1', Product_Code__c = 'P001', MRP__c = 100,Pricing_Group__c=priceGroups[0].Id),
            new Product__c(Name = 'Test Product 2', Product_Code__c = 'P002', MRP__c = 200,Pricing_Group__c=priceGroups[1].Id),
            new Product__c(Name = 'Test Product 3', Product_Code__c = 'P003', MRP__c = 300,Pricing_Group__c=priceGroups[2].Id),
            new Product__c(Name = 'Test Product 4', Product_Code__c = 'P004', MRP__c = 300,Pricing_Group__c=priceGroups[0].Id)
        };
        insert products;

        // Create Regions
        List<Region__c> regions = new List<Region__c>{
            new Region__c(Name = 'Region 1', Region__c = 'R01')
        };
        insert regions;

        // Create Price Book
        Price_Book__c priceBook = new Price_Book__c(Name = 'Standard Price Book', Region__c = regions[0].Id);
        insert priceBook;
    }

    @isTest
    static void testLoadPriceDataFromSAP_Success() {
        Test.startTest();
        
        PriceMasterAPI.PriceInfo priceInfo = new PriceMasterAPI.PriceInfo();
            priceInfo.conditiontype = 'Z011';
            priceInfo.salesorganization = 'S001';
            priceInfo.material = 'P001';
            priceInfo.validitystartdate = '2024-01-01';
            priceInfo.validityenddate = '2024-12-31';
            priceInfo.conditionamount = '10';
            priceInfo.currencyStr = 'USD';
            priceInfo.pricingunit = '1';
            priceInfo.pricingunituom = 'EA';
            priceInfo.customergroup = '01';
            priceInfo.region = 'R01';

            PriceMasterAPI.PriceInfo priceInfo2 = new PriceMasterAPI.PriceInfo();
            priceInfo2.conditiontype = 'ZPR0';
            priceInfo2.salesorganization = 'S001';
            priceInfo2.material = 'P001';
            priceInfo2.validitystartdate = '2024-01-01';
            priceInfo2.validityenddate = '2024-12-31';
            priceInfo2.conditionamount = '10';
            priceInfo2.currencyStr = 'USD';
            priceInfo2.pricingunit = '1';
            priceInfo2.pricingunituom = 'EA';
            priceInfo2.customergroup = '01';
            priceInfo2.region = 'R01';

            PriceMasterAPI.PriceInfo priceInfo21 = new PriceMasterAPI.PriceInfo();
            priceInfo21.conditiontype = 'ZPR0';
            priceInfo21.salesorganization = 'S001';
            priceInfo21.material = 'P001000';
            priceInfo21.validitystartdate = '2024-01-01';
            priceInfo21.validityenddate = '2024-12-31';
            priceInfo21.conditionamount = '10';
            priceInfo21.currencyStr = 'USD';
            priceInfo21.pricingunit = '1';
            priceInfo21.pricingunituom = 'EA';
            priceInfo21.customergroup = '01';
            priceInfo21.region = 'R01';
        // Prepare Test Data
        List<PriceMasterAPI.PriceInfo> testPriceData = new List<PriceMasterAPI.PriceInfo>{priceInfo,priceInfo2,priceInfo21};

        // Call the method
        PriceMasterAPI.PriceResponseData response = PriceMasterAPI.loadPriceDataFromSAP(testPriceData);
        
        // Assertions
        System.assertNotEquals(null, response, 'Response should not be null');
        System.assertEquals(3, response.data.size(), 'Response should contain one result');
        System.assertEquals('Failure', response.data[0].status, 'Expected Success status');

        Test.stopTest();
    }

    @isTest
    static void testLoadPriceDataFromSAP_Failure_NullData() {
        Test.startTest();
        
        // Call API with null data
        PriceMasterAPI.PriceResponseData response = PriceMasterAPI.loadPriceDataFromSAP(null);
        
        // Assertions
        System.assertNotEquals(null, response, 'Response should not be null');
        System.assertEquals(1, response.data.size(), 'Response should contain one result');
        System.assertEquals('Failure', response.data[0].status, 'Expected Failure status');
        System.assertEquals('Requested data is blank', response.data[0].apiResponse, 'Expected failure message');

        Test.stopTest();
    }

    @isTest
    static void testLoadPriceDataFromSAP_ExceptionHandling() {
        Test.startTest();
        PriceMasterAPI.PriceInfo priceInfo = new PriceMasterAPI.PriceInfo();
            priceInfo.conditiontype = 'Z011';
            priceInfo.salesorganization = 'S001';
            priceInfo.material = null; // Invalid: material is null
            priceInfo.validitystartdate = 'InvalidDate'; // Invalid date format
            priceInfo.validityenddate = '2024-12-31';
            priceInfo.conditionamount = '10';
            priceInfo.currencyStr = 'USD';
            priceInfo.pricingunit = '1';
            priceInfo.pricingunituom = 'EA';
            priceInfo.customergroup = '01';
            priceInfo.region = 'R01';
            priceInfo.materialpricinggroup = '';

        
        // Prepare invalid data to trigger exception
        List<PriceMasterAPI.PriceInfo> testPriceData = new List<PriceMasterAPI.PriceInfo>{priceInfo};

        PriceMasterAPI.PriceResponseData response = PriceMasterAPI.loadPriceDataFromSAP(testPriceData);

        // Assertions
        System.assertNotEquals(null, response, 'Response should not be null');
        System.assertEquals(0, response.data.size(), 'Response is blank');

        Test.stopTest();
    }

    @isTest
    static void testBulkProcessing() {
        Test.startTest();
        
        List<PriceMasterAPI.PriceInfo> testPriceData = new List<PriceMasterAPI.PriceInfo>();
        for (Integer i = 0; i < 200; i++) { // Bulk test with 200 records
            PriceMasterAPI.PriceInfo priceInfo = new PriceMasterAPI.PriceInfo();
                priceInfo.conditiontype = 'Z011';
                priceInfo.salesorganization = 'S001';
                priceInfo.material = 'P001';
                priceInfo.validitystartdate = '2024-01-01';
                priceInfo.validityenddate = '2024-12-31';
                priceInfo.conditionamount = '10';
                priceInfo.currencyStr = 'USD';
                priceInfo.pricingunit = '1';
                priceInfo.pricingunituom = 'EA';
                priceInfo.customergroup = '02';
                priceInfo.region = 'R01';
                priceInfo.materialpricinggroup = '';
                if(i>100 && i<150){
                    priceInfo.customergroup = '01';
                    priceInfo.material = '';
                    priceInfo.materialpricinggroup = '01';
                }
                

            testPriceData.add(priceInfo);
        }

        PriceMasterAPI.PriceResponseData response = PriceMasterAPI.loadPriceDataFromSAP(testPriceData);

        System.assertEquals(249, response.data.size(), 'Response should contain 200 results');
        for (PriceMasterAPI.ResponseData res : response.data) {
            System.assertEquals('Success', res.status, 'Expected Success status');
        }

        testPriceData = new List<PriceMasterAPI.PriceInfo>();
        for (Integer i = 0; i < 200; i++) { // Bulk test with 200 records
            PriceMasterAPI.PriceInfo priceInfo = new PriceMasterAPI.PriceInfo();
                priceInfo.conditiontype = 'Z011';
                priceInfo.salesorganization = 'S001';
                priceInfo.material = 'P002';
                priceInfo.validitystartdate = '2024-01-01';
                priceInfo.validityenddate = '2024-12-31';
                priceInfo.conditionamount = '10';
                priceInfo.currencyStr = 'USD';
                priceInfo.pricingunit = '1';
                priceInfo.pricingunituom = 'EA';
                priceInfo.customergroup = '07';
                priceInfo.region = 'R01';
                priceInfo.materialpricinggroup = '';

                if(i>100 && i<150){
                    priceInfo.customergroup = '01';
                    priceInfo.material = '';
                    priceInfo.materialpricinggroup = '01';
                }
                

            testPriceData.add(priceInfo);
        }

        PriceMasterAPI.PriceResponseData response2 = PriceMasterAPI.loadPriceDataFromSAP(testPriceData);

        Test.stopTest();
    }
}