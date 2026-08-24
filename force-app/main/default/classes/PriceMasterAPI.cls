@RestResource(urlMapping='/PriceMaster/')
global without sharing class PriceMasterAPI {

    @HttpPost
    global static PriceResponseData loadPriceDataFromSAP(List<PriceInfo> data) {
        PriceResponseData responseData      =   new PriceResponseData();
        responseData.data = new List<ResponseData>();
        Integration_Log__c log = new Integration_Log__c(Name='PriceMasterAPI',Request__c=Json.serialize(data),Status__c='Success');
        if (data == null){
            ResponseData res = new ResponseData();
            res.status = 'Failure';
            res.apiResponse = 'Requested data is blank';
            responseData.data.add(res);
            return responseData;
        } 
        try{
            set<string> custGrps        =   new set<string>();
            set<string> materialNums    =   new set<string>();
            set<string> materialPricings = new set<string>();
            set<string> regions         =   new set<string>();
            List<PriceInfo> mrpPrice    =   new List<PriceInfo>();
            List<PriceInfo> priceBookEntries    =   new List<PriceInfo>();
            for (PriceInfo price:data) {
                if(price.conditiontype == 'Z011'){
                    if(String.isNotBlank(price.customergroup)){
                        custGrps.add(price.customergroup);
                    }
                    if(String.isNotBlank(price.material)){
                        materialNums.add(price.material);
                    } else if(String.isNotBlank(price.materialpricinggroup)){
                        materialPricings.add(price.materialpricinggroup);
                    }
                    if(String.isNotBlank(price.region)){                
                        regions.add(price.region);
                    }
                    priceBookEntries.add(price);
                } else if(price.conditiontype == 'ZPR0'){
                    mrpPrice.add(price);
                }
                
            }
            if(!mrpPrice.isEmpty()){
                PriceMasterUtility.updateProductsMRP(mrpPrice,responseData);
            }
            if(!priceBookEntries.isEmpty()){
                MapData md = new MapData();
                md.custGrpMap       =   PriceMasterUtility.fetchCustomerGroups(custGrps);
                md.prdGrpMap        =   PriceMasterUtility.fetchPriceGroups(materialPricings);
                md.materialNumMap   =   PriceMasterUtility.fetchProducts(materialNums);
                md.materialPricemap =   priceMasterUtility.fetchProductsforPrice(materialPricings);
                md.regionMap        =   PriceMasterUtility.fetchRegions(regions);
                md.priceBookMap     =   PriceMasterUtility.fetchPriceBooks(regions);
                md.existPriceList   =   getExistingPriceBooks(md);

                System.debug('*******existing list******'+md.existPriceList);
                List<Price_Book_Entry__c> priceList = processData(priceBookEntries,md);
                upsertPriceData(priceList,responseData);
            }
            
        } catch(Exception excp){
            log.Error_Message__c    =   excp.getMessage();
            log.Status__c           =   'Fail';
            ResponseData res = new ResponseData();                
                res.apiResponse = excp.getMessage();
                res.status = 'Failure';
            responseData.data.add(res);        
        }

        string tempStr = Json.serialize(responseData);
        log.Response__c = (tempStr.length() > 130000) ? tempStr.substring(0,130000):tempStr;
        
        Insert log;
        return responseData;

    }

    public static List<Price_Book_Entry__c> processData(List<PriceInfo> data, MapData md) {
        List<Price_Book_Entry__c> priceList = new List<Price_Book_Entry__c>();
        
        for (PriceInfo price : data) {
            if(String.isNotBlank(price.material) && md.materialNumMap.get(price.material) != null){
                Price_Book_Entry__c pb = createPriceBook(price, md, md.materialNumMap.get(price.material));
                pb = PriceMasterUtility.getExistingProd(pb, md.existPriceList);
                priceList.add(pb);
            } else if(String.isNotBlank(price.materialpricinggroup) && md.materialPricemap.get(price.materialpricinggroup)!=null){
                for(product__c prd:md.materialPricemap.get(price.materialpricinggroup)){
                    Price_Book_Entry__c pb = createPriceBook(price, md, prd);
                    pb = PriceMasterUtility.getExistingProd(pb, md.existPriceList);
                    priceList.add(pb);
                }
            }
            
        }
        
        return priceList;
    }
    
    private static Price_Book_Entry__c createPriceBook(PriceInfo price, MapData md,product__c prd) {
        Price_Book_Entry__c pb = new Price_Book_Entry__c();
        pb.Name = generateName(price,md,prd);
        pb.Condition_Type__c = price.conditiontype;
        pb.Sales_Organization__c = price.salesorganization;
        pb.Validity_Start_Date__c = parseDate(price.validitystartdate);
        pb.Validity_End_Date__c = parseDate(price.validityenddate);
        //pb.Condition_Amount__c = parseDecimal(price.conditionamount);
        pb.Currency__c = price.currencyStr;
        pb.Pricing_Unit__c = parseDecimal(price.pricingunit);
        pb.Unit_of_Measure__c = price.pricingunituom;
        pb.Material_Group__c = getMappedId(md.prdGrpMap, price.materialpricinggroup);
        pb.Customer_Group__c = getMappedId(md.custGrpMap, price.customergroup);
        pb.Region__C = getMappedId(md.regionMap, price.region);
        pb.Product__c = prd.Id;
        //pb.Product__c = (getMappedId(md.materialNumMap, price.material)!=null)?getMappedId(md.materialNumMap, price.material):getMappedId(md.materialPricemap, price.materialpricinggroup);
        pb.Price_Book__c = getMappedId(md.priceBookMap, price.region);
        pb.isActive__c = (pb.Validity_Start_Date__c <=System.today() && pb.Validity_End_Date__c>=System.today());
        if(price.customergroup == '01'){
            if(prd.MRP__c !=null){
                pb.PTSS_Margin__c = parseDecimal(price.conditionamount);
                pb.PTSS__c = (prd.MRP__c/(1+(pb.PTSS_Margin__c/100)))/1.05;
            }
            
            pb.Type__c = 'Super Stockist';    
        } else 
        if(price.customergroup == '02'){
            if(prd.MRP__c !=null){
                pb.PTD_Margin__c = parseDecimal(price.conditionamount);
                pb.PTD__c = (prd.MRP__c/(1+(pb.PTD_Margin__c/100)))/1.05;
            }
            pb.Type__c = 'Direct Distributor';
        } else
        if(price.customergroup == '07'){
            if(prd.MRP__c !=null){
                pb.PTSS_Margin__c = parseDecimal(price.conditionamount);
                pb.PTSS__c = (prd.MRP__c/(1+(pb.PTSS_Margin__c/100)))/1.05;
            }
            pb.Type__c = 'Stash'; 
        }

        
        
        return pb;
    }
    
    private static String generateName(PriceInfo price,MapData md,product__c prd) {
        return prd.Name + ' - '+getMappedName(md.regionMap, price.region)+' - ' + getMappedName(md.custGrpMap, price.customergroup);
    }
    
    private static Date parseDate(String dateStr) {
        return String.isNotBlank(dateStr) ? Date.valueOf(dateStr) : null;
    }
    
    private static Decimal parseDecimal(String decimalStr) {
        return String.isNotBlank(decimalStr) ? Decimal.valueOf(decimalStr) : null;
    }
    
    private static String getMappedId(Map<String, Sobject> tempMap, String keystr) {
        return tempMap.get(keystr) != null ? tempMap.get(keystr).Id : null;
    } 
    
    private static String getMappedName(Map<String, Sobject> tempMap, String keystr) {
        return tempMap.get(keystr) != null ? string.valueOf(tempMap.get(keystr).get('Name')) : '';
    } 

    

    public static void upsertPriceData(List<Price_Book_Entry__c> priceList,PriceResponseData responseData){
        

        if(priceList != null && !priceList.isEmpty()){
            Database.UpsertResult[] priceResults = Database.upsert(priceList, Price_Book_Entry__c.Id);
            for (Integer i = 0; i < priceResults.size(); i++) {
                ResponseData res = new ResponseData();
                    res.ref = priceList[i].Name;
                    res.id = priceResults[i].isSuccess() ? priceResults[i].getId() : '';
                    res.apiResponse = priceResults[i].isSuccess() ? (priceResults[i].isCreated()?'Price Created in Salesforce.':'Price Updated in Salesforce.') : priceResults[i].getErrors()[0].getMessage();
                    res.status = priceResults[i].isSuccess() ? 'Success': 'Failure';
                responseData.data.add(res);    
            }
        }
    }
    

    public static List<Price_Book_Entry__c> getExistingPriceBooks(MapData md){        

        return [SELECT Id, Condition_Type__c,Product__c,Type__c,Customer_Group__c, Region__c, Material_Group__c, Validity_Start_Date__c, Validity_End_Date__c 
                FROM Price_Book_Entry__c 
                WHERE (Product__r.Product_Code__c IN: md.materialNumMap.keySet() OR Product__r.Pricing_Group__r.code__c IN: md.materialPricemap.keySet()) 
                AND ( Customer_Group__r.Code__c IN: md.custGrpMap.keySet())
                AND (Region__r.Region__c IN:md.regionMap.keySet())];
        
    }

    global class PriceResponseData{
        global List<ResponseData> data;
    }

    global class ResponseData{
        global string ref;
        global string status;
        global string id;        
        global string apiResponse;
    }
    
    global class PriceInfo{

        global string conditiontype;
        global string salesorganization;
        global string material;
        global string validitystartdate;
        global string validityenddate;
        global string conditionamount;
        global string currencyStr;
        global string pricingunit;
        global String pricingunituom;
        global string customergroup;
        global string region;
        global string materialpricinggroup;
        
    }

    global class MapData{
        map<string,Pricing_Group__c> custGrpMap;
        map<string,Pricing_Group__c> prdGrpMap;
        map<string,Product__c> materialNumMap;
        map<string,List<Product__c>> materialPricemap;
        map<string,Region__c> regionMap;
        map<string,Price_Book__c> pricebookMap;
        List<Price_Book_Entry__c>   existPriceList;   
    }
}