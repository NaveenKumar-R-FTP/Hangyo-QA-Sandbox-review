public with sharing class SchemeHierarchyBulkController {

    public class AccountOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String extra; // Hub, for Distributor rows only — blank otherwise
    }

    public class RegionOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
    }

    @AuraEnabled(cacheable=true)
    public static List<AccountOption> searchDistributors(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        List<AccountOption> options = new List<AccountOption>();
        for (Account a : [
            SELECT Id, Name, Hub__c
            FROM Account
            WHERE Name LIKE :term
              AND RecordType.Name IN ('Distributor', 'Super Stockist')
            ORDER BY Name ASC
            LIMIT 50
        ]) {
            AccountOption opt = new AccountOption();
            opt.id = a.Id;
            opt.name = a.Name;
            opt.extra = a.Hub__c;
            options.add(opt);
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<AccountOption> searchRetailers(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        List<AccountOption> options = new List<AccountOption>();
        for (Account a : [
            SELECT Id, Name
            FROM Account
            WHERE Name LIKE :term
              AND RecordType.Name = 'Retailer'
            ORDER BY Name ASC
            LIMIT 50
        ]) {
            AccountOption opt = new AccountOption();
            opt.id = a.Id;
            opt.name = a.Name;
            options.add(opt);
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<RegionOption> searchRegions(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        List<RegionOption> options = new List<RegionOption>();
        for (Region__c r : [
            SELECT Id, Name
            FROM Region__c
            WHERE Name LIKE :term
            ORDER BY Name ASC
            LIMIT 50
        ]) {
            RegionOption opt = new RegionOption();
            opt.id = r.Id;
            opt.name = r.Name;
            options.add(opt);
        }
        return options;
    }

    // Hub is a fixed picklist on Account, not a queried value — reading the picklist
    // metadata directly (rather than distinct-Account-values, like searchBrands does for
    // Product Brand) guarantees only real, currently-active Hub values are offered.
    @AuraEnabled(cacheable=true)
    public static List<String> searchHubs(String searchTerm) {
        List<String> hubs = new List<String>();
        String term = searchTerm == null ? '' : searchTerm.trim().toLowerCase();
        for (Schema.PicklistEntry pe : Account.Hub__c.getDescribe().getPicklistValues()) {
            if (!pe.isActive()) {
                continue;
            }
            if (String.isBlank(term) || pe.getLabel().toLowerCase().contains(term)) {
                hubs.add(pe.getValue());
            }
        }
        hubs.sort();
        return hubs;
    }

    @AuraEnabled
    public static String createDistributorRows(Id schemeId, List<Id> distributorIds) {
        if (distributorIds == null || distributorIds.isEmpty()) {
            return 'Select at least one distributor.';
        }
        Map<Id, Account> distributors = new Map<Id, Account>([
            SELECT Id, Name FROM Account WHERE Id IN :distributorIds
        ]);
        List<Scheme_Hierarchy__c> rows = new List<Scheme_Hierarchy__c>();
        for (Id distId : distributorIds) {
            Account d = distributors.get(distId);
            rows.add(new Scheme_Hierarchy__c(
                Name = 'Distributor: ' + (d != null ? d.Name : distId),
                Scheme__c = schemeId,
                Scheme_Holder_Type__c = 'Distributor',
                Distributor__c = distId,
                IsActive__c = true
            ));
        }
        return insertRowsAndSummarize(rows);
    }

    @AuraEnabled
    public static String createRegionRows(Id schemeId, List<Id> regionIds) {
        if (regionIds == null || regionIds.isEmpty()) {
            return 'Select at least one region.';
        }
        Map<Id, Region__c> regions = new Map<Id, Region__c>([
            SELECT Id, Name FROM Region__c WHERE Id IN :regionIds
        ]);
        List<Scheme_Hierarchy__c> rows = new List<Scheme_Hierarchy__c>();
        for (Id regionId : regionIds) {
            Region__c r = regions.get(regionId);
            rows.add(new Scheme_Hierarchy__c(
                Name = 'Region: ' + (r != null ? r.Name : regionId),
                Scheme__c = schemeId,
                Scheme_Holder_Type__c = 'Region',
                Region__c = regionId,
                IsActive__c = true
            ));
        }
        return insertRowsAndSummarize(rows);
    }

    @AuraEnabled
    public static String createHubRows(Id schemeId, List<String> hubs) {
        if (hubs == null || hubs.isEmpty()) {
            return 'Select at least one hub.';
        }
        List<Scheme_Hierarchy__c> rows = new List<Scheme_Hierarchy__c>();
        for (String hub : hubs) {
            rows.add(new Scheme_Hierarchy__c(
                Name = 'Hub: ' + hub,
                Scheme__c = schemeId,
                Scheme_Holder_Type__c = 'Hub',
                Hub__c = hub,
                IsActive__c = true
            ));
        }
        return insertRowsAndSummarize(rows);
    }

    @AuraEnabled
    public static String createRetailerRows(Id schemeId, List<Id> retailerIds) {
        if (retailerIds == null || retailerIds.isEmpty()) {
            return 'Select at least one retailer.';
        }
        Map<Id, Account> retailers = new Map<Id, Account>([
            SELECT Id, Name FROM Account WHERE Id IN :retailerIds
        ]);
        List<Scheme_Hierarchy__c> rows = new List<Scheme_Hierarchy__c>();
        for (Id retailerId : retailerIds) {
            Account r = retailers.get(retailerId);
            rows.add(new Scheme_Hierarchy__c(
                Name = 'Retailer: ' + (r != null ? r.Name : retailerId),
                Scheme__c = schemeId,
                Scheme_Holder_Type__c = 'Retailer',
                Account__c = retailerId,
                IsActive__c = true
            ));
        }
        return insertRowsAndSummarize(rows);
    }

    private static String insertRowsAndSummarize(List<Scheme_Hierarchy__c> rows) {
        Database.SaveResult[] results = Database.insert(rows, false);
        List<String> errors = new List<String>();
        Integer successCount = 0;
        for (Integer i = 0; i < results.size(); i++) {
            Database.SaveResult sr = results[i];
            if (sr.isSuccess()) {
                successCount++;
            } else {
                String label = rows[i].Name;
                for (Database.Error err : sr.getErrors()) {
                    errors.add(label + ': ' + err.getMessage());
                }
            }
        }
        if (errors.isEmpty()) {
            return null;
        }
        String prefix = successCount > 0 ? successCount + ' row(s) saved. ' : 'No rows saved. ';
        return prefix + String.join(errors, ' | ');
    }
}