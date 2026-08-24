@RestResource(urlMapping='/Distributors/')
global without sharing class DistributorAPI {

    @HttpPost
    global static DistributorResponseData loadDirectDistributorsFromSAP(List<DistributorInfo> data) {
        DistributorResponseData responseData = new DistributorResponseData();
        responseData.data = new List<ResponseData>();
        Integration_Log__c log = new Integration_Log__c(Name='DistributorAPI',Request__c=Json.serialize(data),Status__c='Success');
        try {
            if (data.isEmpty()){
                return responseData;
            } 

            // Create lookup maps
            Map<String, Id> accMap = DistributorUtility.fetchExistingAccounts(data);
            Map<String, Id> distributionMap = DistributorUtility.fetchDistributionChannels(data);
            Map<String, Id> pricingMap = DistributorUtility.fetchPricingGroups(data);
            Map<String, Id> salesMap = DistributorUtility.fetchSalesOffices(data);
            Map<String, Region__c> regionMap = DistributorUtility.fetchRegions(data);
            
            List<Account> disAccList = new List<Account>();
            
            // Use the schema describe to get the Distributor Record Type Id
            Id distributorRTId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Distributor').getRecordTypeId();
            RecordType accDisRecType = new RecordType(Id=distributorRTId);

            Id superStockistRTId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('SuperStockist').getRecordTypeId();
            RecordType accSSRecType = new RecordType(Id=superStockistRTId);

            for (DistributorInfo disInfo : data) {  
                MappingData tempMap = new MappingData();
                tempMap.accMap = accMap;
                tempMap.distributionMap = distributionMap;
                tempMap.pricingMap  = pricingMap;
                tempMap.salesMap    = salesMap;
                tempMap.regionMap   = regionMap;
                RecordType recType = (disInfo.categoryCode == '01')?accSSRecType:accDisRecType;
                Account acc = mapDistributorInfoToAccount(disInfo, recType, tempMap);
                disAccList.add(acc);
            }

            responseData =  upsertAccounts(disAccList, responseData);
        } catch(Exception excp){            
            log.Error_Message__c    =   excp.getMessage();
            log.Status__c           =   'Fail';
            ResponseData res = new ResponseData();                
                res.status = 'Failure';
                res.apiResponse = excp.getMessage();
            responseData.data.add(res);                
        }

        log.Response__c  = Json.serialize(responseData);
        Insert log;

        return responseData;
    }

    

    // Map DistributorInfo to Account Object
    private static Account mapDistributorInfoToAccount(DistributorInfo disInfo, RecordType recType, MappingData mappingData) {
        Account acc = new Account(RecordTypeId = recType.Id);
    
        if (String.IsNotBlank(disInfo.code) && mappingData.accMap.containsKey(disInfo.code)) {
            acc.Id = mappingData.accMap.get(disInfo.code);
        }

        if (String.IsNotBlank(disInfo.distributionChannelCode) && 
            mappingData.distributionMap.containsKey(disInfo.distributionChannelCode)) {
            acc.Distribution_Channel__c = mappingData.distributionMap.get(disInfo.distributionChannelCode);
        }

        if (String.IsNotBlank(disInfo.zoneCode) && 
            mappingData.salesMap.containsKey(disInfo.zoneCode)) {
            acc.Sales_Office__c = mappingData.salesMap.get(disInfo.zoneCode);
        }

        if (String.IsNotBlank(disInfo.regionCode) &&  
            mappingData.regionMap.containsKey(disInfo.regionCode)) {
            acc.RegionSAP__c = mappingData.regionMap.get(disInfo.regionCode).Id;
            acc.Primary_State__c = mappingData.regionMap.get(disInfo.regionCode).Name;
        
        }

        if (String.IsNotBlank(disInfo.categoryCode) && 
            mappingData.pricingMap.containsKey(disInfo.categoryCode)) {
            acc.Pricing_Group__c = mappingData.pricingMap.get(disInfo.categoryCode);
        }
    
        acc.Code__c = disInfo.code;
        acc.Name = disInfo.name;
        acc.GSTIN__c = disInfo.gSTIN;
        acc.PAN_Number__c = disInfo.pAN;
        acc.FSSAI__c = disInfo.FSSAI;
        acc.Country__c = disInfo.country;
        acc.Email__c = disInfo.email;
        acc.Credit_Limit__c = String.isNotBlank(disInfo.creditLimit) ? Decimal.valueOf(disInfo.creditLimit) : null;
        acc.Payment_Terms__c = disInfo.paymentTerms;
        acc.Payment_Mode__c = disInfo.paymentMode;
        acc.GST_Applicable__c = String.isNotBlank(disInfo.gSTApplicable) ? Boolean.valueOf(disInfo.gSTApplicable) : false;
        acc.Primary_PINCode__c = String.isNotBlank(disInfo.PrimaryPINCode)?Integer.valueOf(disInfo.PrimaryPINCode):null;        
        acc.Primary_Address_1__c = disInfo.primaryAdd1;
        acc.Primary_Address_2__c = disInfo.primaryAdd2;
        acc.Primary_Address_3__c = disInfo.primaryAdd3;
        acc.Primary_Address_4__c = disInfo.primaryAdd4;
        acc.Primary_City__c = disInfo.primaryCity;
        acc.Primary_State_Code__c = disInfo.primaryStateCode;
        acc.Ship_To_Address_1__c = disInfo.shipToAdd1;
        acc.Ship_To_Address_2__c = disInfo.shipToAdd2;
        acc.Ship_To_City__c = disInfo.shipToCity;
        acc.Ship_to_District__c = disInfo.shiptoDistrict;
        acc.Ship_To_State__c = disInfo.shiptoState;
        acc.Ship_to_PIN_Code__c = disInfo.shiptoPINCode;
        acc.First_Name__c = disInfo.FirstName;
        acc.Last_Name__c = disInfo.LastName;
        acc.Phone_1__c = disInfo.phone1;
        acc.Onboard_Date__c =  String.isNotBlank(disInfo.OnboardDate)?Date.valueOf(disInfo.OnboardDate):null;
        acc.Partner_Code__c = disInfo.PartnerCode;
        acc.partner_Type__C = disInfo.PartnerType;
        return acc;
    }

    // Upsert Accounts and Return Response
    private static DistributorResponseData upsertAccounts(List<Account> disAccList, DistributorResponseData responseData) {
        if (!disAccList.isEmpty()) {
            Database.UpsertResult[] results = Database.upsert(disAccList, Account.Id);
            for (Integer i = 0; i < results.size(); i++) {
                ResponseData res = new ResponseData();
                res.ref = disAccList[i].Code__c;
                res.id = results[i].isSuccess() ? results[i].getId() : null;
                res.apiResponse = results[i].isSuccess() ? (results[i].isCreated()?'Distributor Created in Salesforce.':'Distributor Updated in Salesforce.') : results[i].getErrors()[0].getMessage();
                res.status = results[i].isSuccess() ? 'Success' : 'Failure';
                responseData.data.add(res);
            }
        }
        return responseData;
    }

    global class DistributorResponseData{
        global List<ResponseData> data;
    }
    global class ResponseData{
        global string ref;
        global string status;
        global string id;        
        global string apiResponse;
    }
    global class DistributorInfo{
        global string code;
        global string name;
        global string pAN;
        global string gSTIN;
        global string fSSAI;
        global string primaryAdd1;
        global string primaryAdd2;
        global string primaryAdd3;
        global string primaryAdd4;
        global string primaryCity;
        global string primaryState;
        global string primaryStateCode;
        global string primaryPINCode;
        global string shipToAdd1;
        global string shipToAdd2;
        global string shipToCity;
        global string shiptoDistrict;
        global string shiptoState;
        global string shiptoPINCode;
        global string country;
        global string email;
        global string creditLimit;
        global string firstName;
        global string lastName;
        global string phone1;
        global string onboardDate;
        global string paymentTerms;
        global string paymentMode;
        global string gSTApplicable;
        global string categoryCode;
        global string categoryName;
        global string zoneCode;
        global string zoneName;
        global string regionCode;
        global string regionName;
        global string distributionChannelCode;
        global string distributionChannelName;  
        global string PartnerCode;
        global string PartnerType;      

    }

    public class MappingData {
        public Map<String, Id> accMap;
        public Map<String, Id> distributionMap;
        public Map<String, Id> pricingMap;
        public Map<String, Id> salesMap;
        public Map<String, Region__c> regionMap;
    
        
    }
}