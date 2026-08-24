public with sharing class GetPicklistHelper {

    public class PicklistOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getPicklistValues(String sobjectApiName, String fieldApiName) {
        List<PicklistOption> options = new List<PicklistOption>();

        Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(sobjectApiName);
        if (sObjType == null) {
            return options; 
        }

        Schema.DescribeFieldResult fieldResult =
            sObjType.getDescribe().fields.getMap().get(fieldApiName).getDescribe();

        if (fieldResult == null) {
            return options; 
        }

        for (Schema.PicklistEntry ple : fieldResult.getPicklistValues()) {
            PicklistOption opt = new PicklistOption();
            opt.label = ple.getLabel();
            opt.value = ple.getValue();
            options.add(opt);
        }
        return options;
    }
}