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
        // setAccountsBranded is NOT called here. handleAfterUpdate only ever runs
        // from AssetTransferQueueable, which filters to Sync__c = true and passes
        // an empty oldMap - so branding never fired and old.Status__c would NPE.
        // CaseTrigger calls it directly with the real Trigger.oldMap instead.
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


    // The old transfer type, repurposed as the Branding Return Case.
    private static final String RETURN_CASE_TYPE = 'Branding & Marketing Asset transfer Request';

    /**
     * Retires the branding asset once its return case is Completed.
     *
     * Deactivating is enough and is deliberately all we do: every reader -
     * the audit panel, the return selector, and AccountBrandingService - filters
     * on Active__c = true, and BrandingAssetTrigger recalculates Is_Branded__c
     * off the back of this update. Account__c is left alone so the record still
     * shows which outlet held the asset.
     */
    public static void untagReturnedBrandingAssets(List<Case__c> newCases, Map<Id, Case__c> oldMap) {
        if (newCases == null || newCases.isEmpty()) return;

        Set<Id> caseIds = new Set<Id>();
        for (Case__c c : newCases) {
            Case__c old = (oldMap == null) ? null : oldMap.get(c.Id);
            String previousStatus = (old == null) ? null : old.Status__c;
            // Only on the transition INTO Completed - a later edit must not re-fire.
            if (c.Status__c == 'Completed' && previousStatus != 'Completed') {
                caseIds.add(c.Id);
            }
        }
        if (caseIds.isEmpty()) return;

        Set<Id> assetIds = new Set<Id>();
        for (Case__c c : [
            SELECT Branding_Asset__c
            FROM Case__c
            WHERE Id IN :caseIds
              AND Case_Type__r.Name = :RETURN_CASE_TYPE
              AND Branding_Asset__c != null
        ]) {
            assetIds.add(c.Branding_Asset__c);
        }
        if (assetIds.isEmpty()) return;

        List<Branding_Asset__c> toRetire = new List<Branding_Asset__c>();
        for (Branding_Asset__c ba : [
            SELECT Id FROM Branding_Asset__c WHERE Id IN :assetIds AND Active__c = true
        ]) {
            toRetire.add(new Branding_Asset__c(Id = ba.Id, Active__c = false));
        }
        if (!toRetire.isEmpty()) {
            Database.update(toRetire, AccessLevel.SYSTEM_MODE);
        }
    }

    /**
     * When a case reaches Installed, capture the branding material it delivered as
     * Branding_Asset__c records against the account, then recalculate the branded
     * flag. Before this, marketing assets only existed as text on the case and
     * were invisible from the account.
     */
    public static void setAccountsBranded(List<Case__c> newCases, Map<Id, Case__c> oldMap) {
        Set<Id> newlyInstalled = new Set<Id>();
        for (Case__c c : newCases) {
            Case__c old = oldMap != null ? oldMap.get(c.Id) : null;
            Boolean wasInstalled = old != null && old.Status__c == 'Installed';
            if (c.Status__c == 'Installed' && !wasInstalled) {
                newlyInstalled.add(c.Id);
            }
        }
        if (newlyInstalled.isEmpty()) return;

        // Requery: Case_Type__r.Name and the asset columns aren't loaded in Trigger.new.
        List<Case__c> installedCases = [
            SELECT Id, Case_Type__r.Name, Retailer__c, Distributor__c,
                   Retailer_Transfer_To__c, Distributor_Transfer_To__c,
                   Media_Type__c, Marketing_material_Media_Type__c,
                   Media_Sub_type__c, Quantity__c,
                   Installation_Image_URL__c, Request_Image_URL__c,
                   Asset_1__c, Asset_2__c, Asset_3__c, Asset_4__c, Asset_5__c,
                   Asset_Quantity_1__c, Asset_Quantity_2__c, Asset_Quantity_3__c,
                   Asset_Quantity_4__c, Asset_Quantity_5__c
            FROM Case__c
            WHERE Id IN :newlyInstalled
        ];

        // Media lines for the multi-line Inventory Management case type.
        Map<Id, List<Case_Media_Line__c>> linesByCase = new Map<Id, List<Case_Media_Line__c>>();
        for (Case_Media_Line__c line : [
            SELECT Case__c, Media_Type__c, Media_Sub_Type__c, Quantity__c, Image_URL__c
            FROM Case_Media_Line__c
            WHERE Case__c IN :newlyInstalled
        ]) {
            if (!linesByCase.containsKey(line.Case__c)) {
                linesByCase.put(line.Case__c, new List<Case_Media_Line__c>());
            }
            linesByCase.get(line.Case__c).add(line);
        }

        Set<Id> accountIds = new Set<Id>();
        List<Branding_Asset__c> toCreate = new List<Branding_Asset__c>();

        for (Case__c c : installedCases) {
            // Transfers land the asset on the receiving store, so the transfer-to
            // account wins when present.
            Id accountId = c.Retailer_Transfer_To__c != null    ? c.Retailer_Transfer_To__c
                         : c.Distributor_Transfer_To__c != null ? c.Distributor_Transfer_To__c
                         : c.Retailer__c != null                ? c.Retailer__c
                         : c.Distributor__c;
            if (accountId == null) continue;
            accountIds.add(accountId);

            String caseTypeName = c.Case_Type__r != null ? c.Case_Type__r.Name : null;
            if (caseTypeName == null || !caseTypeName.startsWith('Branding')) continue;

            // Primary shape: a branding request describes ONE asset as
            // Media Type + Media Sub Type + Quantity. Transfer requests store the
            // type in Marketing_material_Media_Type__c instead, so fall back to it.
            String mediaType = String.isNotBlank(c.Media_Type__c)
                ? c.Media_Type__c : c.Marketing_material_Media_Type__c;

            if (String.isNotBlank(mediaType) || String.isNotBlank(c.Media_Sub_type__c)) {
                toCreate.add(new Branding_Asset__c(
                    Account__c = accountId,
                    Branding_Case__c = c.Id,
                    Asset_Name__c = buildAssetName(mediaType, c.Media_Sub_type__c),
                    Media_Type__c = mediaType,
                    Media_Sub_Type__c = c.Media_Sub_type__c,
                    Quantity__c = c.Quantity__c,
                    Request_Image_URL__c = c.Request_Image_URL__c,
                    Installation_Image_URL__c = c.Installation_Image_URL__c,
                    Installed_Date__c = System.today(),
                    Active__c = true
                ));
            }

            // Multi-line shape: Inventory Management cases carry one
            // Case_Media_Line__c per requested item.
            if (linesByCase.containsKey(c.Id)) {
                for (Case_Media_Line__c line : linesByCase.get(c.Id)) {
                    toCreate.add(new Branding_Asset__c(
                        Account__c = accountId,
                        Branding_Case__c = c.Id,
                        Asset_Name__c = buildAssetName(line.Media_Type__c, line.Media_Sub_Type__c),
                        Media_Type__c = line.Media_Type__c,
                        Media_Sub_Type__c = line.Media_Sub_Type__c,
                        Quantity__c = line.Quantity__c,
                        Request_Image_URL__c = line.Image_URL__c,
                        Installation_Image_URL__c = c.Installation_Image_URL__c,
                        Installed_Date__c = System.today(),
                        Active__c = true
                    ));
                }
            }

            // Secondary shape: case types that itemise up to five assets instead.
            for (Integer i = 1; i <= 5; i++) {
                Object rawName = c.get('Asset_' + i + '__c');
                if (rawName == null || String.isBlank(String.valueOf(rawName))) continue;

                Object rawQty = c.get('Asset_Quantity_' + i + '__c');
                toCreate.add(new Branding_Asset__c(
                    Account__c = accountId,
                    Branding_Case__c = c.Id,
                    Asset_Name__c = String.valueOf(rawName),
                    Quantity__c = rawQty != null ? (Decimal) rawQty : null,
                    Installed_Date__c = System.today(),
                    Active__c = true
                ));
            }
        }

        if (!toCreate.isEmpty()) {
            Database.insert(toCreate, false, AccessLevel.SYSTEM_MODE);
        }

        // Covers accounts whose case carried no branding lines (e.g. a freezer
        // install), which the Branding_Asset__c trigger would never see.
        AccountBrandingService.recalculate(accountIds);
    }

    /** "Standee - ACP/LE Signage", or whichever half is populated. */
    private static String buildAssetName(String mediaType, String mediaSubType) {
        if (String.isBlank(mediaSubType)) return mediaType;
        if (String.isBlank(mediaType))    return mediaSubType;
        return mediaType + ' - ' + mediaSubType;
    }

}