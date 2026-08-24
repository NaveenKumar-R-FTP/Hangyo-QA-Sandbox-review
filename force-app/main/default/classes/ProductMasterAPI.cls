@RestResource(urlMapping='/ProductMaster/')
global without sharing class ProductMasterAPI {

    
    //Method to receive the data from SAP to salesforce
    // @data parameter helps to receive the data in procustInfor wrapper class format
    @HttpPost
    global static ProductResponseData loadProductMasterFromSAP(List<ProductInfo> data) {
        ProductResponseData responseData = new ProductResponseData();
        responseData.data = new list<ResponseData>();        
        Integration_Log__c log = new Integration_Log__c(Name='ProductMasterAPI',Request__c=Json.serialize(data),Status__c='Success');
        try {
            // Extract unique product and category codes
            Set<String> prdCodes = extractProductCodes(data);
            Set<String> categoryCodes = extractCategoryCodes(data);
        
            // Fetch necessary mappings
            Map<String, Id> priceMap                =   fetchPricingGroups(categoryCodes);
            ProductWithUOMs prodUOMs                =   fetchExistingProducts(prdCodes);
        
            // Map ProductInfo to Product__c records
            responseData = mapProductInfoToProductRecords(data, priceMap, prodUOMs);
        
            
       } catch(Exception excp){            
            log.Error_Message__c    =   excp.getMessage();
            log.Status__c           =   'Fail';
            ResponseData res = new ResponseData();                
                res.apiResponse = excp.getMessage();
                res.status = 'Failure';
            responseData.data.add(res);
        
        }

        log.Response__c  = Json.serialize(responseData);
        Insert log;

        return responseData;
    }
    
    // Extract unique product codes
    private static Set<String> extractProductCodes(List<ProductInfo> data) {
        Set<String> prdCodes = new Set<String>();
        for (ProductInfo prod : data) {
            if (String.isNotBlank(prod.ProductCode)) {
                prdCodes.add(prod.ProductCode);
            }
        }
        return prdCodes;
    }
    
    // Extract unique category codes
    private static Set<String> extractCategoryCodes(List<ProductInfo> data) {
        Set<String> categoryCodes = new Set<String>();
        for (ProductInfo prod : data) {
            if (String.isNotBlank(prod.categoryCode)) {
                categoryCodes.add(prod.categoryCode);
            }
        }
        return categoryCodes;
    }
    
    // Map ProductInfo to Product__c objects
    private static ProductResponseData mapProductInfoToProductRecords(
        List<ProductInfo> data, 
        Map<String, Id> priceMap, 
        ProductWithUOMs prodUOMs
    ) {
        Map<string,Product__c> productsMap = new Map<String,Product__c>();
        Id productRecordTypeId = [
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Product' AND SObjectType = 'Product__c' 
            LIMIT 1
        ].Id;
        
        for (ProductInfo prod : data) {
            Product__c prd = new Product__c();
            prd.Product_Code__c = prod.ProductCode;
            prd.Name = prod.ProductName;
            prd.Release_Status__c = prod.ReleaseStatus;
            prd.Rate_Currency__c = prod.RateCurrency;
            prd.Rate_Value__c = String.isNotBlank(prod.RateValue) ? Integer.valueOf(prod.RateValue) : null;
            prd.Validity_Start_Date__c = String.isNotBlank(prod.ValidityStartDate) ? Date.valueOf(prod.ValidityStartDate) : null;
            prd.Validity_End_Date__c = String.isNotBlank(prod.ValidityEndDate) ? Date.valueOf(prod.ValidityEndDate) : null;
            prd.Quantity__c = String.isNotBlank(prod.Quantity) ? Decimal.valueOf(prod.Quantity) : null;
            prd.Unit_of_Measure__c = prod.UnitofMeasurement;
            prd.Pricing_Group__c = priceMap.get(prod.categoryCode);
            prd.Volume_Per_UOM__c = prod.VolumePerUOM;
            //prd.Alternate_UOM__c = prod.AlternateUOM;
            prd.Tax_Percentage__c = String.isNotBlank(prod.TaxPercentage) ? Decimal.valueOf(prod.TaxPercentage) : null;
            prd.HSN__C = prod.HSN;
            //prd.UOM_Conversion__c = prod.UOMConversion;
            prd.Bulk__c = prod.bulkProd.equalsIgnoreCase('Yes');
            prd.RecordTypeId = productRecordTypeId;

            if (prodUOMs.prodMap.containsKey(prod.ProductCode)) {
                prd.Id = prodUOMs.prodMap.get(prod.ProductCode);
            } else {
                prd.IsActive__c = true;
                prd.Primary_Product__c = true;
                prd.Secondary_Product__c =(prd.Bulk__c)?false:true;
                prd.Image_Long__c = System.label.Product_Default_Image_URL;
            }
            
            productsMap.put(prd.Product_Code__c,prd);
        }

        return upsertProducts(productsMap,prodUOMs.alternateUOMs,data);
    }
    
    // Upsert products and process responses
    private static ProductResponseData upsertProducts(Map<string,Product__c> productsMap, map<string,map<string,Alternate_UOM__c>> UOMMap,List<ProductInfo> Data) {
        ProductResponseData responseData = new ProductResponseData();
        responseData.data = new List<ResponseData>();
    
        map<Id,map<string,Database.UpsertResult>> altUOMMap =  new map<Id,map<string,Database.UpsertResult>>();
        
        Database.UpsertResult[] results = Database.upsert(productsMap.values(), Product__c.Id);

        List<Alternate_UOM__c> alternateUOMList = new List<Alternate_UOM__c>();
        for (ProductInfo prod : data) {            
            for(AlternateUOMs alt: prod.alternateUOMs){
                Alternate_UOM__c altUom = new Alternate_UOM__c();
                    if(UOMMap.get(prod.ProductCode) != null && UOMMap.get(prod.ProductCode).get(alt.alternateUOM) != null){
                        altUom.Id = UOMMap.get(prod.ProductCode).get(alt.alternateUOM).Id;
                    }
                    altUom.Product__c = productsMap.get(prod.ProductCode).Id;
                    altUom.Name = alt.alternateUOM;
                    altUom.UOM_Conversion_D__c = alt.UOMConversionD;
                    altUom.UOM_Conversion_N__c = alt.UOMConversionN;
                alternateUOMList.add(altUom);
            }
            
        }


        integer temp = 0;
        for(Database.UpsertResult altResult: Database.upsert(alternateUOMList, Alternate_UOM__c.Id)){
            if(altUOMMap.get(alternateUOMList[temp].Product__c) != null){
                altUOMMap.get(alternateUOMList[temp].Product__c).put(alternateUOMList[temp].Name,altResult);
            } else {
                altUOMMap.put(alternateUOMList[temp].Product__c,new map<string,Database.UpsertResult>{alternateUOMList[temp].Name=>altResult});
            }
            temp = temp +1;
        }
        
        for (Integer i = 0; i < results.size(); i++) {
            ResponseData res = new ResponseData();
                res.alternateUOMs = new List<UOMResponse>();
                res.ref = String.valueOf(productsMap.values()[i].Product_Code__c);
                res.id = results[i].isSuccess() ? results[i].getId():'';
                res.apiResponse = results[i].isSuccess() ? (results[i].isCreated() ? 'Product Created in Salesforce.' : 'Product Updated in Salesforce.'):results[i].getErrors()[0].getMessage();
                res.status = results[i].isSuccess() ? 'Success':'Failure';
                for(string each:altUOMMap.get(res.id).keySet()){
                    
                    Database.UpsertResult altRes = altUOMMap.get(res.Id).get(each);
                        UOMResponse uRes = new UOMResponse();
                            uRes.alternateUOM = each;
                            uRes.apiResponse = altRes.isSuccess()?(altRes.isCreated()?'Alternate UOM Created.':'Alternate UOM Updated.'):altRes.getErrors()[0].getMessage();
                            uRes.id = altRes.isSuccess()?altRes.getId():'';
                            uRes.status = altRes.isSuccess()?'Success':'Failure';
                        res.alternateUOMs.add(uRes);
                    
                }
             responseData.data.add(res);
        }
    
        return responseData;
    }
    
    
    

    public static ProductWithUOMs fetchExistingProducts(set<string> prdCodes){
        ProductWithUOMs prodUOMs = new ProductWithUOMs();
        prodUOMs.prodMap        = new map<string,Id>();
        prodUOMs.alternateUOMs  = new map<string,Map<String,Alternate_UOM__c>>();
        if(!prdCodes.isEmpty()){
            for(Product__c prd:[SELECT Id,Product_Code__c,(SELECT Id,Name FROM Alternate_UOMs__r) FROM Product__c WHERE Product_Code__c IN:prdCodes]){
                prodUOMs.prodMap.put(prd.Product_Code__c,prd.id);
                for(Alternate_UOM__c alt:prd.Alternate_UOMs__r){
                    if(prodUOMs.alternateUOMs.get(prd.Product_Code__c) != null){
                        prodUOMs.alternateUOMs.get(prd.Product_Code__c).put(alt.Name,alt);
                    } else {
                        prodUOMs.alternateUOMs.put(prd.Product_Code__c,new map<String,Alternate_UOM__c>{alt.Name => alt});
                    }
                    
                }
            }
        }
        return prodUOMs;
    }

    public static Map<String, Id> fetchPricingGroups(Set<String> categoryCodes) {
        
        Map<String, Id> pricingMap = new Map<String, Id>();
        if (!categoryCodes.isEmpty()) {
            for (Pricing_Group__c prGP : [SELECT Id, Name, Code__c FROM Pricing_Group__c 
                                           WHERE Code__c IN :categoryCodes AND Type__c ='Product']) {
                pricingMap.put(prGP.Code__c, prGP.Id);
            }
        }
        return pricingMap;
    }
    //Wrapper class for the receiving the data
    global class ProductInfo{
        global string productCode;
        global string productName;
        global string releaseStatus;        
        global string validityStartDate;
        global string validityEndDate;
        global string rateValue;
        global string rateCurrency;
        global string quantity;
        global string unitofMeasurement;
        global string categoryCode;
        global string categoryName;
        global string volumePerUOM;
        //global string alternateUOM;
        global string taxPercentage;
        global string hSN;
        //global string uOMConversion;
        global string bulkProd;
        global List<AlternateUOMs> alternateUOMs;
    }

    global class AlternateUOMs{
        global string alternateUOM;
        global string UOMConversionN;
        global string UOMConversionD;
    }

    //main wrapper class for repsonse
    global class ProductResponseData{
        global list<ResponseData> data;
    }
    
    //Base response class
    global class ResponseData{
        global string ref;
        global string status;
        global string id;
        global string apiResponse;
        global list<UOMResponse> alternateUOMs;
    }

    global class UOMResponse{
        global string alternateUOM;
        global string status;
        global string id;
        global string apiResponse;

    }

    public class ProductWithUOMs{
        map<string,Id> prodMap;
        Map<string,Map<string,Alternate_UOM__c>> alternateUOMs;
    }

}