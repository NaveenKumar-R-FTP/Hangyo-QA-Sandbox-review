public without sharing class DistributorUtility {
    // Fetch Existing Accounts
    public static Map<String, Id> fetchExistingAccounts(List<DistributorAPI.DistributorInfo> data) {
        Set<String> accCodes = new Set<String>();
        for (DistributorAPI.DistributorInfo disInfo : data) {
            if (String.isNotBlank(disInfo.code)){
                accCodes.add(disInfo.code);
            } 
        }
        Map<String, Id> accMap = new Map<String, Id>();
        if (!accCodes.isEmpty()) {
            for (Account acc : [SELECT Id, Code__c FROM Account WHERE Code__c IN :accCodes]) {
                accMap.put(acc.Code__c, acc.Id);
            }
        }
        return accMap;
    }

    // Fetch Distribution Channels
    public static Map<String, Id> fetchDistributionChannels(List<DistributorAPI.DistributorInfo> data) {
        Set<String> distChanelCodes = new Set<String>();
        for (DistributorAPI.DistributorInfo disInfo : data) {
            if (String.isNotBlank(disInfo.distributionChannelCode)){
                distChanelCodes.add(disInfo.distributionChannelCode);
            }
        }
        Map<String, Id> distributionMap = new Map<String, Id>();
        if (!distChanelCodes.isEmpty()) {
            for (Distribution_Channel__c dist : [SELECT Name, Id, Distribution_Channel__c 
                                                  FROM Distribution_Channel__c 
                                                  WHERE Distribution_Channel__c IN :distChanelCodes]) {
                distributionMap.put(dist.Distribution_Channel__c, dist.Id);
            }
        }
        return distributionMap;
    }

    // Fetch Pricing Groups
    public static Map<String, Id> fetchPricingGroups(List<DistributorAPI.DistributorInfo> data) {
        Set<String> categoryCodes = new Set<String>();
        for (DistributorAPI.DistributorInfo disInfo : data) {
            if (String.isNotBlank(disInfo.categoryCode)){
                categoryCodes.add(disInfo.categoryCode);
            }
        }
        Map<String, Id> pricingMap = new Map<String, Id>();
        if (!categoryCodes.isEmpty()) {
            for (Pricing_Group__c prGP : [SELECT Id, Name, Code__c FROM Pricing_Group__c 
                                           WHERE Code__c IN :categoryCodes AND Type__c ='Customer']) {
                pricingMap.put(prGP.Code__c, prGP.Id);
            }
        }
        return pricingMap;
    }

    // Fetch Sales Offices
    public static Map<String, Id> fetchSalesOffices(List<DistributorAPI.DistributorInfo> data) {
        Set<String> zoneCodes = new Set<String>();
        for (DistributorAPI.DistributorInfo disInfo : data) {
            if (String.isNotBlank(disInfo.zoneCode)){
                zoneCodes.add(disInfo.zoneCode);
            }
        }
        Map<String, Id> salesMap = new Map<String, Id>();
        if (!zoneCodes.isEmpty()) {
            for (Sales_Office__c sof : [SELECT Id, Name, Sales_Office__c FROM Sales_Office__c 
                                         WHERE Sales_Office__c IN :zoneCodes]) {
                salesMap.put(sof.Sales_Office__c, sof.Id);
            }
        }
        return salesMap;
    }

    // Fetch Regions
    public static Map<String, Region__c> fetchRegions(List<DistributorAPI.DistributorInfo> data) {
        Set<String> regionCodes = new Set<String>();
        for (DistributorAPI.DistributorInfo disInfo : data) {
            if (String.isNotBlank(disInfo.regionCode)){
                regionCodes.add(disInfo.regionCode);
            } 
             
        }
        Map<String, Region__c> regionMap = new Map<String, Region__c>();
        if (!regionCodes.isEmpty()) {
            for (Region__c rg : [SELECT Id, Name, Region__c FROM Region__c 
                                   WHERE Region__c IN :regionCodes]) {
                regionMap.put(rg.Region__c, rg);
            }
        }
        return regionMap;
    }
}