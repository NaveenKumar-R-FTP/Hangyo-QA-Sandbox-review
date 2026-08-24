@isTest
private class ProductMasterAPI_Test {
    @testSetup
    static void setupTestData() {
        // Insert Pricing Group
        List<Pricing_Group__c> pricingGroups = new List<Pricing_Group__c>{
            new Pricing_Group__c(Name='Electronics', Code__c='ELEC',Type__c='Product'),
            new Pricing_Group__c(Name='Furniture', Code__c='FURN',Type__c='Product')
        };
        insert pricingGroups;
        
        // Insert Product
        List<Product__c> products = new List<Product__c>{
            new Product__c(Name='Laptop', Product_Code__c='P001', Pricing_Group__c=pricingGroups[0].Id),
            new Product__c(Name='Chair', Product_Code__c='P002', Pricing_Group__c=pricingGroups[1].Id)
        };
        insert products;
        

    }
    
    @isTest
    static void testLoadProductMasterFromSAP_Success() {
        ProductMasterAPI.ProductInfo data = new ProductMasterAPI.ProductInfo();
        List<ProductMasterAPI.ProductInfo> productInfoList = new List<ProductMasterAPI.ProductInfo>{};

        data.productCode='P001';
        data.productName='Updated Laptop';
        data.releaseStatus='Active';
        data.rateValue='1000';
        data.rateCurrency='USD';
        data.validityStartDate='2024-01-01';
        data.validityEndDate='2025-01-01';
        data.quantity='10';
        data.unitofMeasurement='KG';
        data.categoryCode='ELEC';
        data.bulkProd='Yes';
        data.taxPercentage='5';
        data.hSN='1234';
        data.alternateUOMs=new List<ProductMasterAPI.AlternateUOMs>();
        ProductMasterAPI.AlternateUOMs altUOm = new ProductMasterAPI.AlternateUOMs();
        altUOm.alternateUOM='KG';
        altUOm.UOMConversionN='1';
        altUOm.UOMConversionD='10';
        data.alternateUOMs.add(altUOm);
        ProductMasterAPI.AlternateUOMs altUOm2 = new ProductMasterAPI.AlternateUOMs();
        altUOm2.alternateUOM='E';
        altUOm2.UOMConversionN='1';
        altUOm2.UOMConversionD='10';

        data.alternateUOMs.add(altUOm2);
        productInfoList.add(data);
        
        Test.startTest();
        ProductMasterAPI.ProductResponseData response = ProductMasterAPI.loadProductMasterFromSAP(productInfoList);
        ProductMasterAPI.ProductResponseData response2 = ProductMasterAPI.loadProductMasterFromSAP(productInfoList);
        Test.stopTest();
        
        System.assertNotEquals(response, null, 'Response should not be null');
        System.assertEquals(response.data.size(), 1, 'Response should contain one record');
        System.assertEquals(response.data[0].status, 'Success', 'Product should be inserted successfully');
        System.assertEquals(response2.data.size(), 1, 'Response should contain one record');
        System.assertEquals(response2.data[0].status, 'Success', 'Product should be updated successfully');
    }
    
    @isTest
    static void testLoadProductMasterFromSAP_Failure() {
        ProductMasterAPI.ProductInfo data = new ProductMasterAPI.ProductInfo();
        List<ProductMasterAPI.ProductInfo> productInfoList = new List<ProductMasterAPI.ProductInfo>{};

        data.productCode='';
        //data.Name='Invalid Product';
        data.releaseStatus='Active';
        data.rateValue='1000';
        data.rateCurrency='USD';
        data.validityStartDate='2024-01-01';
        data.validityEndDate='2025-01-01';
        data.quantity='10';
        data.unitofMeasurement='KG';
        data.categoryCode='ELEC';
        //data.bulkProd='Yes';
        data.taxPercentage='5';
        data.hSN='1234';
        data.alternateUOMs=new List<ProductMasterAPI.AlternateUOMs>();
        ProductMasterAPI.AlternateUOMs altUOm = new ProductMasterAPI.AlternateUOMs();
        altUOm.alternateUOM='BOX';
        altUOm.UOMConversionN='1';
        altUOm.UOMConversionD='10';

        data.alternateUOMs.add(altUOm);
        productInfoList.add(data);
        
        
        Test.startTest();
        ProductMasterAPI.ProductResponseData response = ProductMasterAPI.loadProductMasterFromSAP(productInfoList);
        Test.stopTest();
        
        System.assertNotEquals(response, null, 'Response should not be null');
        System.assertEquals(response.data.size(), 1, 'Response should contain one record');
        System.assertEquals(response.data[0].status, 'Failure', 'Product update should fail due to missing product code');
    }
    
    @isTest
    static void testBulkProcessing() {
        List<ProductMasterAPI.ProductInfo> bulkProductInfoList = new List<ProductMasterAPI.ProductInfo>();
        for (Integer i = 0; i < 200; i++) {

            ProductMasterAPI.ProductInfo data = new ProductMasterAPI.ProductInfo();

                data.productCode='Bulk' + i+1;
                data.productName='Bulk Product ' + i;
                data.releaseStatus='Active';
                data.rateValue='1000';
                data.rateCurrency='USD';
                data.validityStartDate='2024-01-01';
                data.validityEndDate='2025-01-01';
                data.quantity='10';
                data.unitofMeasurement='KG';
                data.categoryCode='ELEC';
                data.bulkProd='Yes';
                data.taxPercentage='5';
                data.hSN='1234';
                data.alternateUOMs=new List<ProductMasterAPI.AlternateUOMs>();
                ProductMasterAPI.AlternateUOMs altUOm = new ProductMasterAPI.AlternateUOMs();
                altUOm.alternateUOM='BOX';
                altUOm.UOMConversionN='1';
                altUOm.UOMConversionD='10';

                data.alternateUOMs.add(altUOm);
        
            bulkProductInfoList.add(data);
        }
        
        Test.startTest();
        ProductMasterAPI.ProductResponseData response = ProductMasterAPI.loadProductMasterFromSAP(bulkProductInfoList);
        Test.stopTest();
        
        System.assertEquals(response.data.size(), 200, 'Response should contain 200 records');
        for (ProductMasterAPI.ResponseData res : response.data) {
            System.assertEquals(res.status, 'Success', 'Each bulk product should be processed successfully');
        }
    }
}