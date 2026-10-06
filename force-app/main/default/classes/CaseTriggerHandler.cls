public without sharing class CaseTriggerHandler {
    public static void handleAfterUpdate(List<Case__c> cases, Map<Id, Case__c> oldMap) {
        Set<Id> caseIds = new Set<Id>();
        for (Case__c c : cases) {
            if (c.Case_Type__c != null && c.Status__c == 'Approved' && c.Sync__c == true) {
                caseIds.add(c.Id);
            }
        }
        if (!caseIds.isEmpty()) {
            List<Case__c> transferCases = [
                SELECT Id, Status__c, Case_Type__c, Case_Type__r.Name,
                       OEM_serial_number__c, Request_type__c,
                       Retailer_Transfer_To__c, Distributor_Transfer_To__c,
                       Scrap__c, Retailer_Transfer_From__c,
                       Distributor_Transfer_From__c, Sync__c,
                       New_Asset_Code__c, Old_Asset_Code__c,
                       Serial_Number__c, Make__c, Model__c, Capacity__c,
                       Retailer__c, Distributor__c
                FROM Case__c
                WHERE Id IN :caseIds
            ];
            processAssetTransfers(transferCases);
        }
    }

    private static void processAssetTransfers(List<Case__c> cases) {
        // ================= COLLECT QR CODES =================
        Set<String> qrCodes = new Set<String>();
        Set<Id> retailerIds = new Set<Id>();
        Set<Id> distributorIds = new Set<Id>();
        for (Case__c c : cases) {
            if (String.isNotBlank(c.OEM_serial_number__c)) {
                qrCodes.add(c.OEM_serial_number__c);
            }
            if (c.Retailer_Transfer_From__c != null) retailerIds.add(c.Retailer_Transfer_From__c);
            if (c.Retailer_Transfer_To__c != null) retailerIds.add(c.Retailer_Transfer_To__c);
            if (c.Distributor_Transfer_From__c != null) distributorIds.add(c.Distributor_Transfer_From__c);
        }

        // ================= QUERY ASSET MAPPINGS =================
        Map<String, Asset_Mapping__c> qrToMapping = new Map<String, Asset_Mapping__c>();
        if (!qrCodes.isEmpty()) {
            for (Asset_Mapping__c am : [
                SELECT Id, Retailer__c, Distributor__c, Super_Stockist__c, Active__c, Scrapped__c,
                       Asset_Master__c, Asset_Master__r.OEM_Serial_Number__c
                FROM Asset_Mapping__c
                WHERE Asset_Master__r.OEM_Serial_Number__c IN :qrCodes
                AND Active__c = true
            ]) {
                String fromId = am.Retailer__c != null ? am.Retailer__c :
                               (am.Distributor__c != null ? am.Distributor__c : am.Super_Stockist__c);
                String key = am.Asset_Master__r.OEM_Serial_Number__c + '_' + fromId;
                qrToMapping.put(key, am);
            }
        }

        // ================= QUERY RETAILER ACCOUNTS =================
        Map<Id, Account> retailerMap = new Map<Id, Account>();
        if (!retailerIds.isEmpty()) {
            for (Account acc : [
                SELECT Id, Distributor__c, Distributor__r.RecordType.Name,
                       Distributor__r.Super_Stockist_Name__c,
                       Super_Stockist_Name__c, RecordType.Name
                FROM Account
                WHERE Id IN :retailerIds
            ]) {
                retailerMap.put(acc.Id, acc);
            }
        }

        // ================= QUERY DISTRIBUTOR ACCOUNTS =================
        Map<Id, Account> distributorMap = new Map<Id, Account>();
        if (!distributorIds.isEmpty()) {
            for (Account acc : [
                SELECT Id, Super_Stockist_Name__c, RecordType.Name
                FROM Account
                WHERE Id IN :distributorIds
            ]) {
                distributorMap.put(acc.Id, acc);
            }
        }

        // ================= PROCESS EACH CASE =================
        List<Asset_Mapping__c> mappingsToUpdate = new List<Asset_Mapping__c>();
        List<Asset_Master__c> mastersToUpdate = new List<Asset_Master__c>();

        for (Case__c c : cases) {
            if (c.Case_Type__r.Name == 'Asset Tagging Request' ||
                c.Case_Type__r.Name == 'Existing outlet Asset Code Change Request') continue;
            if (String.isBlank(c.OEM_serial_number__c)) continue;

            String qrCode = c.OEM_serial_number__c;
            String requestType = c.Request_type__c;
            String scrapValue = c.Scrap__c;

            String fromId = c.Retailer_Transfer_From__c != null ?
                c.Retailer_Transfer_From__c : c.Distributor_Transfer_From__c;
            String key = qrCode + '_' + fromId;
            Asset_Mapping__c mapping = qrToMapping.get(key);
            if (mapping == null) continue;

            // ================= OUTLET TO OUTLET =================
            if (requestType == 'Outlet to Outlet') {
                mapping.Retailer__c = c.Retailer_Transfer_To__c;
                if (c.Retailer_Transfer_To__c != null) {
                    Account toRetailer = retailerMap.get(c.Retailer_Transfer_To__c);
                    if (toRetailer != null) {
                        mapping.Distributor__c = toRetailer.Distributor__c;
                    }
                }
                mappingsToUpdate.add(mapping);
            }
            // ================= OUTLET TO DISTRIBUTOR =================
            else if (requestType == 'Outlet to Distributor') {
                mapping.Retailer__c = null;
                mapping.Distributor__c = c.Distributor_Transfer_To__c != null ?
                    c.Distributor_Transfer_To__c : mapping.Distributor__c;
                mappingsToUpdate.add(mapping);
            }
            // ================= DISTRIBUTOR TO OUTLET =================
            else if (requestType == 'Distributor to Outlet') {
                mapping.Retailer__c = c.Retailer_Transfer_To__c;
                if (c.Retailer_Transfer_To__c != null) {
                    Account toRetailer = retailerMap.get(c.Retailer_Transfer_To__c);
                    if (toRetailer != null) {
                        mapping.Distributor__c = toRetailer.Distributor__c;
                    }
                }
                mappingsToUpdate.add(mapping);
            }
            // ================= DISTRIBUTOR TO DISTRIBUTOR =================
            else if (requestType == 'Distributor to Distributor') {
                mapping.Retailer__c = null;
                if (c.Distributor_Transfer_To__c != null) {
                    List<Account> destAccount = [
                        SELECT Id, RecordType.Name
                        FROM Account
                        WHERE Id = :c.Distributor_Transfer_To__c LIMIT 1
                    ];
                    if (!destAccount.isEmpty() && destAccount[0].RecordType.Name == 'Super Stockist') {
                        mapping.Super_Stockist__c = c.Distributor_Transfer_To__c;
                        mapping.Distributor__c = null;
                    } else {
                        mapping.Distributor__c = c.Distributor_Transfer_To__c;
                        mapping.Super_Stockist__c = null;
                    }
                }
                mappingsToUpdate.add(mapping);
            }
            // ================= SCRAP =================
            else if (requestType == 'Scrap' || String.isNotBlank(scrapValue)) {
                mapping.Active__c = false;
                mapping.Scrapped__c = true;
                mapping.Retailer__c = null;
                mapping.Distributor__c = null;
                mapping.Super_Stockist__c = null;
                if (c.Retailer_Transfer_From__c != null) {
                    Account retailer = retailerMap.get(c.Retailer_Transfer_From__c);
                    if (retailer != null) {
                        if (retailer.Super_Stockist_Name__c != null) {
                            mapping.Super_Stockist__c = retailer.Super_Stockist_Name__c;
                        } else if (retailer.Distributor__c != null) {
                            if (retailer.Distributor__r != null &&
                                retailer.Distributor__r.RecordType != null &&
                                retailer.Distributor__r.RecordType.Name == 'Super Stockist') {
                                mapping.Super_Stockist__c = retailer.Distributor__c;
                            } else {
                                mapping.Distributor__c = retailer.Distributor__c;
                            }
                        }
                    }
                } else if (c.Distributor_Transfer_From__c != null) {
                    Account distributor = distributorMap.get(c.Distributor_Transfer_From__c);
                    if (distributor != null && distributor.RecordType?.Name == 'Super Stockist') {
                        mapping.Super_Stockist__c = c.Distributor_Transfer_From__c;
                    } else {
                        mapping.Distributor__c = c.Distributor_Transfer_From__c;
                    }
                }
                mappingsToUpdate.add(mapping);
                if (mapping.Asset_Master__c != null) {
                    mastersToUpdate.add(new Asset_Master__c(
                        Id = mapping.Asset_Master__c,
                        Scrapped__c = true
                    ));
                }
            }
        }

        // ================= ASSET CODE CHANGE =================
        List<Asset_Master__c> assetMastersToUpdateCode = new List<Asset_Master__c>();
        for (Case__c c : cases) {
            if (c.Case_Type__r.Name != 'Existing outlet Asset Code Change Request') continue;
            if (String.isBlank(c.New_Asset_Code__c)) continue;

            List<Asset_Mapping__c> retailerMappings = [
                SELECT Id, Asset_Master__c
                FROM Asset_Mapping__c
                WHERE Retailer__c = :c.Retailer__c
                AND Active__c = true
                AND Asset_Master__r.OEM_Serial_Number__c = :c.Old_Asset_Code__c
                LIMIT 1
            ];

            if (!retailerMappings.isEmpty()) {
                // Check OEM duplicate
                List<Asset_Master__c> dupOEM = [
                    SELECT Id FROM Asset_Master__c
                    WHERE OEM_Serial_Number__c = :c.New_Asset_Code__c
                    AND Id != :retailerMappings[0].Asset_Master__c
                    LIMIT 1
                ];
                if (!dupOEM.isEmpty()) {
                    System.debug('Asset Code Change skipped - duplicate OEM: ' + c.New_Asset_Code__c + ' Case: ' + c.Name);
                    continue;
                }
                // Check Serial Number duplicate
                if (String.isNotBlank(c.Serial_Number__c)) {
                    List<Asset_Master__c> dupSerialList = [
    SELECT Id, Asset_Serial_No__c FROM Asset_Master__c
    WHERE Id != :retailerMappings[0].Asset_Master__c
    LIMIT 200
];
                    Boolean serialDup = false;
                    for (Asset_Master__c am : dupSerialList) {
                        if (am.Asset_Serial_No__c == c.Serial_Number__c) { serialDup = true; break; }
                    }
                    if (serialDup) {
                        System.debug('Asset Code Change skipped - duplicate Serial: ' + c.Serial_Number__c + ' Case: ' + c.Name);
                        continue;
                    }
                }
                Asset_Master__c master = new Asset_Master__c(
                    Id = retailerMappings[0].Asset_Master__c
                );
                master.OEM_Serial_Number__c = c.New_Asset_Code__c;
                if (String.isNotBlank(c.Serial_Number__c)) {
                    master.Asset_Serial_No__c = c.Serial_Number__c;
                }
                assetMastersToUpdateCode.add(master);
            }
        }
        if (!assetMastersToUpdateCode.isEmpty()) {
            Database.update(assetMastersToUpdateCode, AccessLevel.SYSTEM_MODE);
        }

        // ================= ASSET TAGGING REQUEST =================
        for (Case__c c : cases) {
            if (c.Case_Type__r.Name != 'Asset Tagging Request') continue;
            if (String.isBlank(c.New_Asset_Code__c)) continue;
            if (c.Retailer__c == null && c.Distributor__c == null) continue;

            // Check OEM Serial Number duplicate
            List<Asset_Master__c> existingMaster = [
                SELECT Id FROM Asset_Master__c
                WHERE OEM_Serial_Number__c = :c.New_Asset_Code__c
                LIMIT 1
            ];
            if (!existingMaster.isEmpty()) {
                System.debug('Asset Tagging skipped - duplicate OEM: ' + c.New_Asset_Code__c + ' Case: ' + c.Name);
                continue;
            }
            // Check Serial Number duplicate
            if (String.isNotBlank(c.Serial_Number__c)) {
                List<Asset_Master__c> existingSerial = [
    SELECT Id, Asset_Serial_No__c FROM Asset_Master__c
    WHERE OEM_Serial_Number__c != :c.New_Asset_Code__c
    LIMIT 200
];
                Boolean serialDup = false;
                for (Asset_Master__c am : existingSerial) {
                    if (am.Asset_Serial_No__c == c.Serial_Number__c) { serialDup = true; break; }
                }
                if (serialDup) {
                    System.debug('Asset Tagging skipped - duplicate Serial: ' + c.Serial_Number__c + ' Case: ' + c.Name);
                    continue;
                }
            }

            // Create Asset Master
            Asset_Master__c newMaster = new Asset_Master__c(
                OEM_Serial_Number__c = c.New_Asset_Code__c,
                Make__c = c.Make__c,
                Model__c = c.Model__c,
                Capacity__c = c.Capacity__c
            );
            if (String.isNotBlank(c.Serial_Number__c)) {
                newMaster.Asset_Serial_No__c = c.Serial_Number__c;
            }
            Database.insert(newMaster, AccessLevel.SYSTEM_MODE);

            // Create Asset Mapping
            Asset_Mapping__c newMapping = new Asset_Mapping__c(
                Asset_Master__c = newMaster.Id,
                Retailer__c = c.Retailer__c,
                Distributor__c = c.Distributor__c,
                Active__c = true,
                Allocation_Start_Date__c = Date.today()
            );
            Database.insert(newMapping, AccessLevel.SYSTEM_MODE);

            // ================= LINK PHOTO TO ASSET MASTER =================
            List<ContentDocumentLink> caseLinks = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :c.Id
                LIMIT 1
            ];
            if (!caseLinks.isEmpty()) {
                List<ContentVersion> versions = [
                    SELECT Id
                    FROM ContentVersion
                    WHERE ContentDocumentId = :caseLinks[0].ContentDocumentId
                    AND IsLatest = true
                    LIMIT 1
                ];
                if (!versions.isEmpty()) {
                    Asset_Master__c masterToUpdate = new Asset_Master__c(
                        Id = newMaster.Id,
                        Asset_Image__c = System.URL.getOrgDomainUrl().toExternalForm() +
                                        '/sfc/servlet.shepherd/version/download/' + versions[0].Id
                    );
                    Database.update(masterToUpdate, AccessLevel.SYSTEM_MODE);
                    ContentDocumentLink masterLink = new ContentDocumentLink(
                        ContentDocumentId = caseLinks[0].ContentDocumentId,
                        LinkedEntityId = newMaster.Id,
                        ShareType = 'V',
                        Visibility = 'AllUsers'
                    );
                    Database.insert(masterLink, AccessLevel.SYSTEM_MODE);
                }
            }
        }

        // ================= DML =================
        if (!mappingsToUpdate.isEmpty()) {
            Database.update(mappingsToUpdate, AccessLevel.SYSTEM_MODE);
        }
        if (!mastersToUpdate.isEmpty()) {
            Database.update(mastersToUpdate, AccessLevel.SYSTEM_MODE);
        }
    }
}