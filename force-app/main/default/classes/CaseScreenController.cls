/**
* ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
* Class Name      : CaseScreenController
* Author          : <YourName>
* Created Date    : Mar 27, 2026
* Last Modified By: Arul Selvan
* Last Modified On: Jun 21, 2026
* Description     : This class implements for......
*  a
* Change History  :
*  Date          │   Author       │   Change
* ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
*  Mar 27, 2026  │ <YourName>     │ Initial version
*  Jun 20, 2026  │ Arul Selvan    │ Approval process name fix, getDynamicFields null fix,
*                │                │ checkNewAssetCode added, checkAllAssetsAudited 30-day
*                │                │ logic removed, getUnproductiveReason added
*  Jun 21, 2026  │ Arul Selvan    │ getAssets — distributor assets added for Dist-to-Outlet
*                │                │ saveCase — general picklist translation for all fields
* ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
*/

public class CaseScreenController {

    // Statuses that count as "completed" for the case list tabs. Branding &
    // Marketing Asset Requests land on Installation Pending instead of Approved
    // once their approval process finishes, then move to Installed.
    // Completed / Closed are the terminal states of the Branding Return Case.
    private static final List<String> COMPLETED_STATUSES = new List<String>{
        'Approved', 'Installation Pending', 'Installed', 'Completed', 'Closed'
    };

    // ================= CASE TYPES =================
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getCaseTypes() {
        try {
            List<Map<String, String>> result = new List<Map<String, String>>();
            for (Case_Type__c ct : [
                SELECT Id, Name 
                FROM Case_Type__c 
                WHERE Type__c = 'Case' AND Active__c = true
                ORDER BY Name
            ]) {
                Map<String, String> mapItem = new Map<String, String>();
                mapItem.put('label', ct.Name);
                mapItem.put('value', ct.Id);
                result.add(mapItem);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching case types: ' + e.getMessage());
        }
    }
    
    // ================= CASE LIST =================
    @AuraEnabled
public static List<Case__c> getCases(Id visitTaskId) {
        List<Case__c> finalList = new List<Case__c>();
        try {
            if (visitTaskId == null) {
                List<Case__c> closedCases = [
                    SELECT Id, Name, Case_Type__r.Name, Retailer__r.Name, Retailer_Transfer_From__r.Name,
                           Retailer_Transfer_To__r.Name, Status__c, CreatedBy.Name, CreatedById
                    FROM Case__c
                    WHERE Status__c IN :COMPLETED_STATUSES AND Case_Type__c != null
                    ORDER BY CreatedDate DESC LIMIT 20
                ];
                List<Case__c> openCases = [
                    SELECT Id, Name, Case_Type__r.Name, Retailer__r.Name, Retailer_Transfer_From__r.Name,
                           Retailer_Transfer_To__r.Name, Status__c, CreatedBy.Name, CreatedById
                    FROM Case__c
                    WHERE Status__c NOT IN :COMPLETED_STATUSES AND Status__c != null AND Case_Type__c != null
                    ORDER BY CreatedDate DESC LIMIT 20
                ];
                finalList.addAll(openCases);
                finalList.addAll(closedCases);
                return finalList;
            }
           Visit_Task__c visitTask = [
                SELECT Retailer__c, Distributor__c FROM Visit_Task__c WHERE Id = :visitTaskId LIMIT 1
            ];
           Id accountId = visitTask.Retailer__c != null ? visitTask.Retailer__c : visitTask.Distributor__c;
            if (accountId != null) {
                List<Case__c> closedCase = [
                    SELECT Id, Name, Case_Type__r.Name, Retailer__r.Name, Retailer_Transfer_From__r.Name,
                           Retailer_Transfer_To__r.Name, Status__c, CreatedBy.Name, CreatedById
                    FROM Case__c
                    WHERE (Retailer__c = :accountId OR Retailer_Transfer_From__c = :accountId OR Retailer_Transfer_To__c = :accountId
                           OR Distributor__c = :accountId OR Distributor_Transfer_From__c = :accountId OR Distributor_Transfer_To__c = :accountId)
                    AND Status__c IN :COMPLETED_STATUSES AND Case_Type__c != null
                    ORDER BY CreatedDate DESC LIMIT 20
                ];
                List<Case__c> openCase = [
                    SELECT Id, Name, Case_Type__r.Name, Retailer__r.Name, Retailer_Transfer_From__r.Name,
                           Retailer_Transfer_To__r.Name, Status__c, CreatedBy.Name, CreatedById
                    FROM Case__c
                    WHERE (Retailer__c = :accountId OR Retailer_Transfer_From__c = :accountId OR Retailer_Transfer_To__c = :accountId
                           OR Distributor__c = :accountId OR Distributor_Transfer_From__c = :accountId OR Distributor_Transfer_To__c = :accountId)
                    AND Status__c NOT IN :COMPLETED_STATUSES AND Status__c != null AND Case_Type__c != null
                ];
                finalList.addAll(openCase);
                finalList.addAll(closedCase);
                return finalList;
            }
        } catch (Exception e) {
            return new List<Case__c>();
        }
        return new List<Case__c>();
    }

    // ================= GET DISTRIBUTOR =================
    @AuraEnabled(cacheable=true)
    public static Id getDistributorId(Id retailerId) {
        try {
            if (retailerId == null) return null;
            Account acc = [
                SELECT Distributor__c FROM Account
                WHERE Id = :retailerId AND RecordType.Name = 'Retailer' LIMIT 1
            ];
            if (acc.Distributor__c != null) {
                Account dAcc = [
    SELECT Id
    FROM Account
    WHERE Id = :acc.Distributor__c 
    AND RecordType.Name IN ('Distributor', 'Super Stockist')
    LIMIT 1
];
                if (dAcc.Id != null) return dAcc.Id;
            }
            return null;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching distributor');
        }
    }
    
    /**
     * Record type of an account, so caseScreen can tell whether it was opened from
     * a retailer or a distributor. A record page hands the component one id with no
     * indication of what it is, which previously landed a distributor in the
     * Retailer field.
     *
     * Returns 'Retailer', 'Distributor', 'SuperStockist' or null.
     */
    @AuraEnabled(cacheable=true)
    public static String getAccountRecordType(Id accountId) {
        try {
            if (accountId == null) return null;
            List<Account> accounts = [
                SELECT RecordType.DeveloperName FROM Account WHERE Id = :accountId LIMIT 1
            ];
            if (accounts.isEmpty() || accounts[0].RecordType == null) return null;
            return accounts[0].RecordType.DeveloperName;
        } catch (Exception e) {
            return null;
        }
    }

    // ================= CHECK ALL ASSETS AUDITED =================
    @AuraEnabled
    public static String checkAllAssetsAudited(Id visitTaskId) {
        try {
            Visit_Task__c visitTask = [
                SELECT Retailer__c FROM Visit_Task__c WHERE Id = :visitTaskId LIMIT 1
            ];
            List<Asset_Mapping__c> relatedAssets = [
                SELECT Id FROM Asset_Mapping__c WHERE Retailer__c = :visitTask.Retailer__c
AND Active__c = true
            ];
            if (relatedAssets.isEmpty()) return 'VISIT_AUDITED';
            Set<Id> assetIds = new Set<Id>();
            for (Asset_Mapping__c a : relatedAssets) assetIds.add(a.Id);
            Set<Id> auditedAssetIds = new Set<Id>();
            for (Asset_Audit__c audit : [
                SELECT Id, Asset__c FROM Asset_Audit__c
                WHERE Asset__c IN :assetIds AND Visit_Task__c = :visitTaskId
            ]) {
                auditedAssetIds.add(audit.Asset__c);
            }
            for (Id assetId : assetIds) {
                if (!auditedAssetIds.contains(assetId)) return 'NOT_AUDITED';
            }
            return 'VISIT_AUDITED';
        } catch (Exception e) {
            return null;
        }
    }



    /**
     * The outlet a visit is against - a retailer, or a distributor when the visit
     * has no retailer. Branding assets hang off Account, so both kinds of visit
     * audit exactly the same way; only the field the outlet is read from differs.
     */
    public class VisitOutlet {
        public Id accountId;
        public Boolean isDistributorVisit;
        public Datetime visitCreatedDate;
    }

    private static VisitOutlet resolveVisitOutlet(Id visitTaskId) {
        VisitOutlet outlet = new VisitOutlet();
        List<Visit_Task__c> visits = [
            SELECT Retailer__c, Distributor__c, CreatedDate
            FROM Visit_Task__c WHERE Id = :visitTaskId LIMIT 1
        ];
        if (visits.isEmpty()) return outlet;

        Visit_Task__c v = visits[0];
        outlet.visitCreatedDate = v.CreatedDate;
        if (v.Retailer__c != null) {
            outlet.accountId = v.Retailer__c;
            outlet.isDistributorVisit = false;
        } else {
            outlet.accountId = v.Distributor__c;
            outlet.isDistributorVisit = true;
        }
        return outlet;
    }

    // ================= CHECK ALL BRANDING AUDITED (every 3rd visit) =================
@AuraEnabled
public static String checkAllBrandingAudited(Id visitTaskId) {
    try {
        VisitOutlet outlet = resolveVisitOutlet(visitTaskId);

        // No outlet on the visit - nothing to audit
        if (outlet.accountId == null) return 'VISIT_AUDITED';

        // 1) Which visit number is this for the outlet? (this visit + earlier, ignoring cancelled)
        Integer visitNumber = brandingVisitNumber(outlet);

//------------- 2) Only mandatory on every 3rd visit-------------------------------
        if (Math.mod(visitNumber, 3) != 0) return 'VISIT_AUDITED';

        // 3) Does this outlet have active branding assets?
        List<Branding_Asset__c> brandingAssets = [
            SELECT Id FROM Branding_Asset__c
            WHERE Account__c = :outlet.accountId AND Active__c = true
        ];
        if (brandingAssets.isEmpty()) return 'VISIT_AUDITED'; // nothing to audit

        // 4) Which of those assets were audited on THIS visit?
        Set<Id> assetIds = new Set<Id>();
        for (Branding_Asset__c b : brandingAssets) assetIds.add(b.Id);

        Set<Id> auditedIds = new Set<Id>();
        for (Branding_Audit_Line__c line : [
            SELECT Branding_Asset__c
            FROM Branding_Audit_Line__c
            WHERE Branding_Asset__c IN :assetIds
              AND Branding_Audit__r.Visit_Task__c = :visitTaskId
        ]) {
            auditedIds.add(line.Branding_Asset__c);
        }

        // 5) Any active asset missing its audit ⇒ block checkout
        for (Id aId : assetIds) {
            if (!auditedIds.contains(aId)) return 'NOT_AUDITED';
        }
        return 'VISIT_AUDITED';
    } catch (Exception e) {
        return null;
    }
}

    // ================= LOAD ACTIVE BRANDING ASSETS FOR THE AUDIT SCREEN =================
    @AuraEnabled(cacheable=true)
    public static List<Branding_Asset__c> getBrandingAssets(Id visitTaskId) {
        VisitOutlet outlet = resolveVisitOutlet(visitTaskId);
        if (outlet.accountId == null) return new List<Branding_Asset__c>();
        return [
            SELECT Id, Name, Media_Type__c, Media_Sub_Type__c,
                   Installation_Image_URL__c, Request_Image_URL__c
            FROM Branding_Asset__c
            WHERE Account__c = :outlet.accountId AND Active__c = true
            ORDER BY Media_Type__c
        ];
    }
//--------------------------------------------------------------------------------
// ===== LOAD ACTIVE BRANDING ASSETS TAGGED TO A RETAILER (for return-case selection) =====
@AuraEnabled(cacheable=true)
public static List<Branding_Asset__c> getRetailerBrandingAssets(Id retailerId) {
    return [
        SELECT Id, Name, Media_Type__c, Media_Sub_Type__c
        FROM Branding_Asset__c
        WHERE Account__c = :retailerId AND Active__c = true
        ORDER BY Name
    ];
}

// ===== BLOCK DUPLICATE PENDING RETURN CASE FOR THE SAME ASSET =====
/**
 * True while a return case for this asset is still in flight.
 *
 * Only the three terminal states release the block. Anything else - Pending,
 * L1 Approved and so on - means a return is already under way, so a second one
 * must not be raised.
 */
@AuraEnabled
public static Boolean hasPendingReturnCase(Id brandingAssetId) {
    if (brandingAssetId == null) return false;
    return ![
        SELECT Id FROM Case__c
        WHERE Branding_Asset__c = :brandingAssetId
          AND Case_Type__r.Name = 'Branding & Marketing Asset transfer Request'
          AND Status__c NOT IN ('Completed', 'Closed', 'Reject')
        LIMIT 1
    ].isEmpty();
}
//--------------------------------------------------------------------------------



    /**
     * The photo bytes for each branding asset, as data: URIs keyed by asset Id.
     *
     * The photo fields hold a /sfc/servlet.shepherd/... link. That servlet needs a
     * UI session and its content type varies, so an <img> pointed at it may or may
     * not paint. Returning the bytes inline sidesteps the servlet completely - a
     * data: URI always renders. The ContentVersion Id is parsed back out of the
     * stored URL because the file is linked to the Case, not to the asset.
     */
    @AuraEnabled(cacheable=true)
    public static Map<Id, String> getBrandingAssetPhotos(Id visitTaskId) {
        Map<Id, String> photos = new Map<Id, String>();
        try {
            Map<Id, Id> versionToAsset = new Map<Id, Id>();
            for (Branding_Asset__c a : getBrandingAssets(visitTaskId)) {
                String url = String.isNotBlank(a.Installation_Image_URL__c)
                    ? a.Installation_Image_URL__c
                    : a.Request_Image_URL__c;
                Id versionId = extractVersionId(url);
                if (versionId != null) versionToAsset.put(versionId, a.Id);
            }
            if (versionToAsset.isEmpty()) return photos;

            for (ContentVersion cv : [
                SELECT Id, VersionData, FileType, ContentSize
                FROM ContentVersion WHERE Id IN :versionToAsset.keySet()
            ]) {
                // Guard the heap - a huge file is not worth inlining.
                if (cv.ContentSize == null || cv.ContentSize > 2000000) continue;
                String mime = (cv.FileType == 'PNG') ? 'image/png' : 'image/jpeg';
                photos.put(
                    versionToAsset.get(cv.Id),
                    'data:' + mime + ';base64,' + EncodingUtil.base64Encode(cv.VersionData)
                );
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Could not load branding photos: ' + e.getMessage());
        }
        return photos;
    }

    private static Id extractVersionId(String url) {
        if (String.isBlank(url)) return null;
        Matcher m = Pattern.compile('/version/download/([a-zA-Z0-9]{15,18})').matcher(url);
        if (!m.find()) return null;
        try {
            return Id.valueOf(m.group(1));
        } catch (Exception e) {
            return null;
        }
    }

    /** How many visits this outlet has had, counting this one. Shared so the
     *  check-out gate and the audit panel can never disagree on the number.
     *
     *  Distributor visits are counted on Distributor__c with no retailer: a
     *  retailer visit also carries the servicing distributor, and counting those
     *  would inflate the distributor's own visit number. */
    private static Integer brandingVisitNumber(VisitOutlet outlet) {
        if (outlet.isDistributorVisit == true) {
            return [
                SELECT COUNT()
                FROM Visit_Task__c
                WHERE Distributor__c = :outlet.accountId
                  AND Retailer__c = null
                  AND CreatedDate <= :outlet.visitCreatedDate
                  AND Status__c != 'Cancelled'
            ];
        }
        return [
            SELECT COUNT()
            FROM Visit_Task__c
            WHERE Retailer__c = :outlet.accountId
              AND CreatedDate <= :outlet.visitCreatedDate
              AND Status__c != 'Cancelled'
        ];
    }

    // whether the audit may be taken on this visit
    public class BrandingAuditWindow {
        @AuraEnabled public Integer visitNumber { get; set; }
        @AuraEnabled public Boolean auditDue { get; set; }
        @AuraEnabled public Integer visitsUntilDue { get; set; }
        @AuraEnabled public Boolean alreadySubmitted { get; set; }
        public BrandingAuditWindow() {
            this.visitNumber = 0;
            this.auditDue = false;
            this.visitsUntilDue = 0;
            this.alreadySubmitted = false;
        }
    }

    /** One branding audit per visit task. */
    private static Boolean hasAuditForVisit(Id visitTaskId) {
        return [SELECT COUNT() FROM Branding_Audit__c WHERE Visit_Task__c = :visitTaskId] > 0;
    }

    /**
     * The branding audit is only taken on every 3rd visit. Viewing the assets is
     * always allowed; this tells the panel whether to offer the audit form, and
     * uses the same visit count as the check-out gate.
     */
    @AuraEnabled(cacheable=true)
    public static BrandingAuditWindow getBrandingAuditWindow(Id visitTaskId) {
        BrandingAuditWindow window = new BrandingAuditWindow();
        try {
            VisitOutlet outlet = resolveVisitOutlet(visitTaskId);
            if (outlet.accountId == null) return window;

            window.visitNumber = brandingVisitNumber(outlet);
            Integer remainder = Math.mod(window.visitNumber, 3);
            window.auditDue = (remainder == 0);
            window.visitsUntilDue = window.auditDue ? 0 : (3 - remainder);
            window.alreadySubmitted = hasAuditForVisit(visitTaskId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Could not resolve branding audit window: ' + e.getMessage());
        }
        return window;
    }

    // audit state shown on each card in the audit panel
    public class BrandingAuditStatus {
        @AuraEnabled public Boolean auditedThisVisit { get; set; }
        @AuraEnabled public Datetime lastAuditDate { get; set; }
        public BrandingAuditStatus() { this.auditedThisVisit = false; }
    }

    /**
     * Per-asset audit state, keyed by branding asset Id.
     *
     * "Audited" means audited on THIS visit - the check-out gate works the same
     * way, so a card must not read as done because of an audit from an earlier
     * visit. lastAuditDate is the most recent audit whenever it happened.
     */
    @AuraEnabled(cacheable=true)
    public static Map<Id, BrandingAuditStatus> getBrandingAuditStatus(Id visitTaskId) {
        Map<Id, BrandingAuditStatus> result = new Map<Id, BrandingAuditStatus>();
        try {
            Set<Id> assetIds = new Set<Id>();
            for (Branding_Asset__c a : getBrandingAssets(visitTaskId)) assetIds.add(a.Id);
            if (assetIds.isEmpty()) return result;

            // Oldest first, so the last row written per asset is the newest audit.
            for (Branding_Audit_Line__c line : [
                SELECT Branding_Asset__c,
                       Branding_Audit__r.Audit_Date__c,
                       Branding_Audit__r.Visit_Task__c
                FROM Branding_Audit_Line__c
                WHERE Branding_Asset__c IN :assetIds
                ORDER BY Branding_Audit__r.Audit_Date__c ASC NULLS FIRST
            ]) {
                BrandingAuditStatus status = result.get(line.Branding_Asset__c);
                if (status == null) {
                    status = new BrandingAuditStatus();
                    result.put(line.Branding_Asset__c, status);
                }
                if (line.Branding_Audit__r.Audit_Date__c != null) {
                    status.lastAuditDate = line.Branding_Audit__r.Audit_Date__c;
                }
                if (line.Branding_Audit__r.Visit_Task__c == visitTaskId) {
                    status.auditedThisVisit = true;
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Could not load branding audit status: ' + e.getMessage());
        }
        return result;
    }

    // input wrapper — one per asset card from the audit screen
public class BrandingAuditLineInput {
    @AuraEnabled public Id brandingAssetId { get; set; }
    @AuraEnabled public String mediaType { get; set; }
    @AuraEnabled public String subMedia { get; set; }
    @AuraEnabled public String condition { get; set; }   // Present / Damage / Missing
    @AuraEnabled public String remarks { get; set; }
    @AuraEnabled public String fileName { get; set; }    // photo (Damage only)
    @AuraEnabled public String base64 { get; set; }      // photo (Damage only)
}

// ========= SAVE A BRANDING AUDIT (header + lines + photo links) =========
@AuraEnabled
public static Id submitBrandingAudit(Id visitTaskId, List<BrandingAuditLineInput> lines) {
    // Outside the try on purpose - the catch below re-wraps everything, which
    // would bury this message behind "Could not save branding audit".
    if (hasAuditForVisit(visitTaskId)) {
        throw new AuraHandledException('A branding audit has already been submitted for this visit.');
    }
    try {
        // same outlet and visit-number rules the gate uses, so a distributor
        // visit is audited exactly like a retailer one
        VisitOutlet outlet = resolveVisitOutlet(visitTaskId);
        Integer visitNumber = brandingVisitNumber(outlet);

        // 1) header. Retailer_Account__c is a plain Account lookup - it holds the
        //    distributor on a distributor visit despite the field name.
        Branding_Audit__c header = new Branding_Audit__c(
            Retailer_Account__c = outlet.accountId,
            Visit_Task__c       = visitTaskId,
            Employee_Name__c    = UserInfo.getUserId(),
            Audit_Date__c       = System.now(),
            Visit_Number__c     = visitNumber
        );
        insert header;

        // 2) one line per asset
        List<Branding_Audit_Line__c> lineRecords = new List<Branding_Audit_Line__c>();
        for (BrandingAuditLineInput li : lines) {
            lineRecords.add(new Branding_Audit_Line__c(
                Branding_Audit__c = header.Id,
                Branding_Asset__c = li.brandingAssetId,
                Media_Type__c     = li.mediaType,
                Sub_Media__c      = li.subMedia,
                Condition__c      = li.condition,
                Remarks__c        = li.remarks
            ));
        }
        insert lineRecords;

        // 3) Damage photos: attachFiles inserts the ContentVersion and links it to
        //    the line, then hands back the download URL we record on Photo_Link__c.
        List<Branding_Audit_Line__c> photoLines = new List<Branding_Audit_Line__c>();
        for (Integer i = 0; i < lines.size(); i++) {
            BrandingAuditLineInput li = lines[i];
            if (String.isBlank(li.base64)) continue;
            String photoUrl = attachFiles(
                lineRecords[i].Id,
                new List<Map<String, String>>{
                    new Map<String, String>{ 'fileName' => li.fileName, 'base64' => li.base64 }
                }
            );
            photoLines.add(new Branding_Audit_Line__c(
                Id = lineRecords[i].Id, Photo_Link__c = photoUrl
            ));
        }
        if (!photoLines.isEmpty()) update photoLines;

        return header.Id;
    } catch (Exception e) {
        throw new AuraHandledException('Could not save branding audit: ' + e.getMessage());
    }
}

    // ================= CHECK ALL AUDITED FOR ORDER =================
   @AuraEnabled
public static String checkAllAuditedForOrder(Id visitTaskId) {
    return 'VALID';
}
    // ================= GET VISIT CREATED DATE =================
    @AuraEnabled(cacheable=true)
    public static Datetime getVisitCreatedDate(Id visitTaskId) {
        if (visitTaskId == null) return null;
        Visit_Task__c vt = [SELECT CreatedDate FROM Visit_Task__c WHERE Id = :visitTaskId LIMIT 1];
        return vt.CreatedDate;
    }

    // ================= GET UNPRODUCTIVE REASON =================
    @AuraEnabled(cacheable=true)
    public static String getUnproductiveReason(Id visitTaskId) {
        try {
            if (visitTaskId == null) return null;
            Visit_Task__c vt = [
                SELECT Unproductive_Reasons__c FROM Visit_Task__c WHERE Id = :visitTaskId LIMIT 1
            ];
            return vt.Unproductive_Reasons__c;
        } catch (Exception e) {
            return null;
        }
    }
    
    // ================= GET CASE FIELDS =================
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getCaseFields(Id caseId) {
        try {
            if (caseId == null) throw new AuraHandledException('Case Id is required');
            Map<String, Schema.SObjectField> fieldsMap = Case__c.SObjectType.getDescribe().fields.getMap();
            List<String> apiFields = new List<String>();
            for (String fieldName : fieldsMap.keySet()) {
                apiFields.add(fieldName);
                Schema.DescribeFieldResult d = fieldsMap.get(fieldName).getDescribe();
                if (d.getType() == Schema.DisplayType.REFERENCE) {
                    String relName = d.getRelationshipName();
                    if (relName != null) apiFields.add(relName + '.Name');
                }
            }
            String soql = 'SELECT ' + String.join(apiFields, ',') + ' FROM Case__c WHERE Id = :caseId LIMIT 1';
            Case__c c = Database.query(soql);
            Map<String, Object> populatedFields = c.getPopulatedFieldsAsMap();
            List<Map<String, Object>> result = new List<Map<String, Object>>();
            for (String apiName : populatedFields.keySet()) {
                if (apiName == 'Id' || apiName == 'RecordTypeId') continue;
                if (!fieldsMap.containsKey(apiName)) continue;
                Schema.DescribeFieldResult fieldDesc = fieldsMap.get(apiName).getDescribe();
                if (!fieldDesc.isAccessible() || fieldDesc.isDefaultedOnCreate() || fieldDesc.isCalculated() ||
                    apiName == 'Id' || (!fieldDesc.isCustom() && apiName != 'Name')) continue;
                Object value = populatedFields.get(apiName);
                Object displayValue = value;
                if (fieldDesc.getType() == Schema.DisplayType.REFERENCE) {
                    String relName = fieldDesc.getRelationshipName();
                    if (relName != null) {
                        SObject relatedObj = c.getSObject(relName);
                        if (relatedObj != null) {
                            Object nameVal = relatedObj.get('Name');
                            if (nameVal != null) displayValue = nameVal;
                        }
                    }
                }
                result.add(new Map<String, Object>{
                    'apiName' => apiName,
                    'label' => fieldDesc.getLabel(),
                    'value' => value,
                    'displayValue' => displayValue
                });
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    // ================= GET DYNAMIC FIELDS =================
    @AuraEnabled(cacheable=true)
    public static List<FormFieldWrapper> getDynamicFields(String caseType, Id selectedId, Id ffId) {
        try {
            List<FormFieldWrapper> result = new List<FormFieldWrapper>();
            Set<Id> ffSet = new Set<Id>();
            Set<Id> controllingFieldIds = new Set<Id>();
            
            List<Form_Field__c> fields = [
                SELECT Id, API_Name__c, Label__c, Type__c, Required__c, Sequence__c, Query_Table__c, Controlling_Field__c, Visible__c
                FROM Form_Field__c
                WHERE Case_Type__r.Name = :caseType AND Visible__c = true
                ORDER BY Sequence__c ASC
            ];
            
            for (Form_Field__c ff : fields) {
                ffSet.add(ff.Id);
                if (ff.Controlling_Field__c != null) controllingFieldIds.add(ff.Controlling_Field__c);
            }
            
            Map<Id, List<PicklistOption>> picklistMap = new Map<Id, List<PicklistOption>>();
            Map<Id, Set<Id>> addedValuesMap = new Map<Id, Set<Id>>();
            
            if (!ffSet.isEmpty()) {
                for (Form_Field_Picklist__c p : [
                    SELECT Id, Form_Field__c, Name, Code__c, Parent_Picklist__c, Active__c
                    FROM Form_Field_Picklist__c
                    WHERE Form_Field__c IN :ffSet AND Active__c = true AND Parent_Picklist__c = null
                ]) {
                    if (!picklistMap.containsKey(p.Form_Field__c)) {
                        picklistMap.put(p.Form_Field__c, new List<PicklistOption>());
                        addedValuesMap.put(p.Form_Field__c, new Set<Id>());
                    }
                    if (!addedValuesMap.get(p.Form_Field__c).contains(p.Id)) {
                        PicklistOption opt = new PicklistOption();
                        opt.label = p.Name;
                        opt.value = p.Id;
                        picklistMap.get(p.Form_Field__c).add(opt);
                        addedValuesMap.get(p.Form_Field__c).add(p.Id);
                    }
                }
            }
            
            List<Form_Field_Picklist__c> dependPicklists = [
                SELECT Id, Name, Form_Field__c, Form_Field__r.Controlling_Field__c, Parent_Picklist__c, Active__c
                FROM Form_Field_Picklist__c
                WHERE Parent_Picklist__c = :selectedId AND Active__c = true AND Form_Field__r.Controlling_Field__c = :ffId
            ];
            
            if (selectedId == null && ffId == null) {
                for (Form_Field__c f : fields) {
                    FormFieldWrapper wrap = new FormFieldWrapper();
                    wrap.ffId = f.Id;
                    wrap.apiName = f.API_Name__c;
                    wrap.label = f.Label__c;
                    wrap.type = f.Type__c;
                    wrap.required = f.Required__c;
                    wrap.lookupObject = f.Query_Table__c;
                    wrap.options = picklistMap.containsKey(f.Id) ? picklistMap.get(f.Id) : null;
                    wrap.isControlling = controllingFieldIds.contains(f.Id);
                    result.add(wrap);
                }
                return result;
            }

            if (dependPicklists.isEmpty()) return result;
            
            for (Form_Field_Picklist__c p : dependPicklists) {
                if (!picklistMap.containsKey(p.Form_Field__c)) {
                    picklistMap.put(p.Form_Field__c, new List<PicklistOption>());
                    addedValuesMap.put(p.Form_Field__c, new Set<Id>());
                }
                if (!addedValuesMap.get(p.Form_Field__c).contains(p.Id)) {
                    PicklistOption opt = new PicklistOption();
                    opt.label = p.Name;
                    opt.value = p.Id;
                    picklistMap.get(p.Form_Field__c).add(opt);
                    addedValuesMap.get(p.Form_Field__c).add(p.Id);
                }
            }
            
            for (Form_Field__c f : fields) {
                FormFieldWrapper wrap = new FormFieldWrapper();
                wrap.ffId = f.Id;
                wrap.apiName = f.API_Name__c;
                wrap.label = f.Label__c;
                wrap.type = f.Type__c;
                wrap.required = f.Required__c;
                wrap.lookupObject = f.Query_Table__c;
                wrap.options = picklistMap.containsKey(f.Id) ? picklistMap.get(f.Id) : null;
                wrap.isControlling = controllingFieldIds.contains(f.Id);
                result.add(wrap);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading dynamic fields: ' + e.getMessage());
        }
    }
    
    // ================= MEDIA LINE OPTIONS =================
    /**
     * Media Type and Media Sub Type options for the repeatable line editor.
     * Sourced from the same Form_Field_Picklist__c records the single-line
     * Branding & Marketing Asset Request form uses, so both stay in step.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<PicklistOption>> getMediaLineOptions() {
        try {
            Map<String, List<PicklistOption>> result = new Map<String, List<PicklistOption>>{
                'mediaTypes' => new List<PicklistOption>(),
                'mediaSubTypes' => new List<PicklistOption>()
            };
            // The same option list is configured against more than one case type,
            // so the raw query returns each value once per case type. Dedupe by
            // name, otherwise the dropdown shows every option twice.
            Map<String, Set<String>> seen = new Map<String, Set<String>>{
                'mediaTypes' => new Set<String>(),
                'mediaSubTypes' => new Set<String>()
            };

            for (Form_Field_Picklist__c p : [
                SELECT Name, Parent_Picklist__r.Name, Form_Field__r.API_Name__c
                FROM Form_Field_Picklist__c
                WHERE Form_Field__r.API_Name__c IN ('Media_Type__c', 'Media_Sub_type__c')
                AND Active__c = true
                ORDER BY Name
            ]) {
                String key = p.Form_Field__r.API_Name__c == 'Media_Type__c'
                    ? 'mediaTypes' : 'mediaSubTypes';
                if (String.isBlank(p.Name)) continue;

                String parentName = p.Parent_Picklist__r != null ? p.Parent_Picklist__r.Name : null;
                // Dedupe on name AND parent, so the same sub type can legitimately
                // appear under two different media types once dependencies exist.
                if (!seen.get(key).add(p.Name + '||' + parentName)) continue;

                PicklistOption opt = new PicklistOption();
                opt.label = p.Name;
                // Value is the label: these are stored as text on the line, not as ids.
                opt.value = p.Name;
                opt.parent = parentName;
                result.get(key).add(opt);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading media options: ' + e.getMessage());
        }
    }

    /**
     * Saves an Inventory Management case together with its media lines.
     *
     * The summary is folded into formData BEFORE the case is inserted, because
     * saveCase submits for approval and the record is locked from that point on -
     * writing it afterwards would fail. The child lines are inserted after, which
     * is safe: they don't touch the locked parent.
     */
    // Handed to saveCase so the lines land while the case is still unlocked.
    private static List<Map<String, Object>> pendingMediaLines;

    @AuraEnabled
    public static Id saveCaseWithLines(Map<String, Object> formData, List<Map<String, Object>> lines) {
        try {
            if (lines == null || lines.isEmpty()) {
                throw new AuraHandledException('Add at least one media line before submitting.');
            }

            formData.put('Media_Lines_Summary__c', buildLinesSummary(lines));
            pendingMediaLines = lines;
            return saveCase(formData);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving case: ' + e.getMessage());
        } finally {
            pendingMediaLines = null;
        }
    }

    /**
     * Creates the media lines and their photos.
     *
     * Called immediately after the case is inserted and BEFORE it is submitted for
     * approval. Once submitted the case is locked, the submitter drops to
     * read-only, and inserting a master-detail child then fails with
     * INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY.
     */
    private static void insertMediaLines(Id caseId, List<Map<String, Object>> lines) {
        if (lines == null || lines.isEmpty()) return;

        List<Case_Media_Line__c> toInsert = new List<Case_Media_Line__c>();
        for (Map<String, Object> line : lines) {
            Case_Media_Line__c ml = new Case_Media_Line__c(
                Case__c = caseId,
                Media_Type__c = toText(line.get('mediaType')),
                Media_Sub_Type__c = toText(line.get('mediaSubType')),
                Quantity__c = toDecimal(line.get('quantity'))
            );

            // Each item carries its own photo. The file is linked to the case so it
            // stays visible there; the URL rides on the line and is copied to the
            // Branding Asset when the case is installed.
            String base64 = toText(line.get('photoBase64'));
            if (String.isNotBlank(base64)) {
                String fileName = toText(line.get('photoName'));
                ml.Image_URL__c = attachFiles(caseId, new List<Map<String, String>>{
                    new Map<String, String>{
                        'fileName' => String.isBlank(fileName) ? 'media-item.jpg' : fileName,
                        'base64' => base64
                    }
                });
            }
            toInsert.add(ml);
        }
        insert toInsert;
    }

    /** "Standee - ACP/LE Signage x3; Poster - Wall Wrap x2" */
    private static String buildLinesSummary(List<Map<String, Object>> lines) {
        List<String> parts = new List<String>();
        for (Map<String, Object> line : lines) {
            String type = toText(line.get('mediaType'));
            String sub = toText(line.get('mediaSubType'));
            Decimal qty = toDecimal(line.get('quantity'));

            String name = String.isBlank(sub) ? type
                        : (String.isBlank(type) ? sub : type + ' - ' + sub);
            if (String.isBlank(name)) continue;
            parts.add(name + (qty != null ? ' x' + qty.format() : ''));
        }
        return String.join(parts, '; ').abbreviate(255);
    }

    private static String toText(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Decimal toDecimal(Object value) {
        if (value == null) return null;
        String s = String.valueOf(value);
        return String.isBlank(s) ? null : Decimal.valueOf(s);
    }

    // ================= SAVE CASE =================
    @AuraEnabled
    public static Id saveCase(Map<String, Object> formData) {
        try {
            Case__c newCase = new Case__c();
            Map<String, Schema.SObjectField> fieldMap = Case__c.SObjectType.getDescribe().fields.getMap();
            
            // Build picklist translation map from Form_Field_Picklist__c
            // This translates record IDs back to Name (label) for all picklist fields
            Set<String> formValues = new Set<String>();
            for (String key : formData.keySet()) {
                if (formData.get(key) != null) {
                    String strVal = String.valueOf(formData.get(key));
                    if (strVal.length() == 18 || strVal.length() == 15) {
                        formValues.add(strVal);
                    }
                }
            }
            Map<String, Form_Field_Picklist__c> picklistRecordMap = new Map<String, Form_Field_Picklist__c>();
            if (!formValues.isEmpty()) {
                try {
                    for (Form_Field_Picklist__c ffp : [
                        SELECT Id, Name, Code__c, Form_Field__r.API_Name__c
                        FROM Form_Field_Picklist__c
                        WHERE Id IN :formValues
                    ]) {
                        picklistRecordMap.put(ffp.Id, ffp);
                    }
                } catch (Exception ex) {}
            }

            for (String key : formData.keySet()) {
                if (!fieldMap.containsKey(key)) continue;
                Object value = formData.get(key);
                if (value == null || String.isBlank(String.valueOf(value))) continue;
                
                Schema.DescribeFieldResult fieldDesc = fieldMap.get(key).getDescribe();
                String strVal = String.valueOf(value);

                // ================= PICKLIST TRANSLATION =================
                if (fieldDesc.getType() == Schema.DisplayType.Picklist && picklistRecordMap.containsKey(strVal)) {
                    Form_Field_Picklist__c ffp = picklistRecordMap.get(strVal);
                    // For Scrap__c use Code__c (maps to actual SF API value)
                    if (key == 'Scrap__c') {
                        Map<String, String> scrapMap = new Map<String, String>{
                            'Transfer to Distributor' => 'Transferred to warehouse',
                            'Transferred to Distributor' => 'Transferred to warehouse',
                            'Transferred to warehouse' => 'Transferred to warehouse'
                        };
                        String mappedVal = scrapMap.get(ffp.Name);
                        newCase.put(key, mappedVal != null ? mappedVal : ffp.Name);
                    } else {
                        // For all other picklists use Name (matches SF picklist label)
                        newCase.put(key, ffp.Name);
                    }
                    continue;
                }

                // ================= SCRAP DIRECT LABEL =================
                if (key == 'Scrap__c') {
                    Map<String, String> scrapMap = new Map<String, String>{
                        'Transfer to Distributor' => 'Transferred to warehouse',
                        'Transferred to Distributor' => 'Transferred to warehouse',
                        'Transferred to warehouse' => 'Transferred to warehouse'
                    };
                    String mappedVal = scrapMap.get(strVal);
                    if (mappedVal != null) {
                        newCase.put(key, mappedVal);
                        continue;
                    }
                }

                if (fieldDesc.getType() == Schema.DisplayType.Double ||
                    fieldDesc.getType() == Schema.DisplayType.Currency ||
                    fieldDesc.getType() == Schema.DisplayType.Integer) {
                    newCase.put(key, Decimal.valueOf(strVal));
                } else if (fieldDesc.getType() == Schema.DisplayType.Date) {
                    newCase.put(key, Date.valueOf(strVal));
                } else if (fieldDesc.getType() == Schema.DisplayType.Reference) {
                    newCase.put(key, (Id)value);
                } else {
                    newCase.put(key, strVal);
                }
            }
            newCase.Status__c = 'Open';
	insert newCase;

            // Must happen before the approval submission below: submitting locks
            // the case, and a locked parent blocks master-detail child inserts.
            insertMediaLines(newCase.Id, pendingMediaLines);
            pendingMediaLines = null;

            // ================= APPROVAL SUBMISSION =================
            // ================= APPROVAL SUBMISSION =================
Case__c caseObj = [
    SELECT Id, Name, Retailer__c, Retailer__r.Name, Distributor__c, Distributor__r.Name,
           CreatedBy.Name, Case_Type__r.Name, Case_Type__c, OwnerId
    FROM Case__c WHERE Id = :newCase.Id
];
User manager = [SELECT Id, ManagerId FROM User WHERE Id = :caseObj.OwnerId];

if (caseObj.Case_Type__c != null) {
    if ((caseObj.Case_Type__r.Name == 'Existing outlet Asset Code Change Request' ||
         caseObj.Case_Type__r.Name == 'Asset Transfer Request') && manager.ManagerId != null) {

        // ================= POPULATE L1 =================
        List<Id> chain = getApproverChain(caseObj.OwnerId, 1);
        Case__c caseToUpdate = new Case__c(Id = caseObj.Id);
        if (chain.size() > 0) caseToUpdate.L1__c = chain[0];
        update caseToUpdate;

        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(caseObj.Id);
        req.setProcessDefinitionNameOrId('Case_Type_By_Case_Approval');
        Approval.ProcessResult res = Approval.process(req);
        if (!res.isSuccess()) System.debug('Approval submission failed: ' + res);

    } else if (caseObj.Case_Type__r.Name == 'New Asset Request' && manager.ManagerId != null) {

        // ================= POPULATE L1 L2 L3 =================
         List<Id> chain = getApproverChain(caseObj.OwnerId, 3);
        Id fallback = manager.ManagerId;
        Case__c caseToUpdate = new Case__c(Id = caseObj.Id);
       caseToUpdate.L1__c = chain.size() > 0 ? chain[0] : fallback;
        caseToUpdate.L2__c = chain.size() > 1 ? chain[1] : fallback;
        caseToUpdate.L3__c = chain.size() > 2 ? chain[2] : fallback;
  update caseToUpdate;

        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(caseObj.Id);
        req.setProcessDefinitionNameOrId('New_Asset_Request');
        Approval.ProcessResult res = Approval.process(req);
        if (!res.isSuccess()) System.debug('Approval submission failed: ' + res);

   } else if (caseObj.Case_Type__r.Name == 'Asset Complaint Request') {
        if (!Test.isRunningTest()) {
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(caseObj.Id);
            req.setProcessDefinitionNameOrId('Asset_Complaint_Request_Case_Approval');
            Approval.ProcessResult res = Approval.process(req);
            if (!res.isSuccess()) System.debug('Approval submission failed: ' + res);
        }

  } else if (caseObj.Case_Type__r.Name == 'Branding & Marketing Asset Inventory Management') {
        // Same two-level chain as Branding & Marketing Asset Request: L1 from the
        // submitter's hierarchy, then Mahesh. The old Branding_Marketing_Asset_Inventory
        // process is obsolete, so this routes to the replacement.
        Id maheshId = '005fu00000DKEDpAAP';

        Case__c caseToUpdate = new Case__c(Id = caseObj.Id);
        caseToUpdate.L1__c = requireBrandingL1(caseObj.OwnerId);
        caseToUpdate.L2__c = maheshId;
        update caseToUpdate;

        applyDuplicateWarning(caseObj);

        if (!Test.isRunningTest()) {
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(caseObj.Id);
            req.setProcessDefinitionNameOrId('Branding_Marketing_Inventory_Approval');
            Approval.ProcessResult res = Approval.process(req);
            if (!res.isSuccess()) System.debug('Approval submission failed: ' + res);
        }

} else if (caseObj.Case_Type__r.Name == 'Branding & Marketing Asset transfer Request' ||
               caseObj.Case_Type__r.Name == 'Branding & Marketing Asset Request') {
        if (caseObj.Case_Type__r.Name == 'Branding & Marketing Asset Request') {
            List<Id> fullChain = getApproverChain(caseObj.OwnerId, 3);
            Id maheshId = '005fu00000DKEDpAAP';
            List<Id> uniqueChain = new List<Id>();
            Set<Id> seen = new Set<Id>();
            for (Id approverId : fullChain) {
                if (!seen.contains(approverId)) {
                    uniqueChain.add(approverId);
                    seen.add(approverId);
                }
            }
            Case__c caseToUpdate = new Case__c(Id = caseObj.Id);
            // L1 must be an ASM or RSM - never an SO, KAM, ZSM or VP.
            caseToUpdate.L1__c = requireBrandingL1(caseObj.OwnerId);
            caseToUpdate.L2__c = uniqueChain.size() > 1 ? uniqueChain[1] : maheshId;
            caseToUpdate.L3__c = uniqueChain.size() > 2 ? uniqueChain[2] : maheshId;
            caseToUpdate.L4__c = maheshId;
            update caseToUpdate;



applyDuplicateWarning(caseObj);

//---------------------------------------------------------------------------------------------

            if (!Test.isRunningTest()) {
                Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
                req.setObjectId(caseObj.Id);
                req.setProcessDefinitionNameOrId('Branding_Marketing_Asset');
                Approval.ProcessResult res = Approval.process(req);
                if (!res.isSuccess()) System.debug('Approval submission failed: ' + res);
            }
        } else {
            // Branding & Marketing Asset transfer Request: same two-level chain as
            // the other branding types. The old Branding_Marketing_Asset_R_and_A_T_R
            // process is obsolete, which made every submission fail with
            // NO_APPLICABLE_PROCESS, so this routes to the replacement.
            Id maheshId = '005fu00000DKEDpAAP';

            Case__c caseToUpdate = new Case__c(Id = caseObj.Id);
            caseToUpdate.L1__c = requireBrandingL1(caseObj.OwnerId);
            caseToUpdate.L2__c = maheshId;
            update caseToUpdate;

            applyDuplicateWarning(caseObj);

            if (!Test.isRunningTest()) {
                Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
                req.setObjectId(caseObj.Id);
                req.setProcessDefinitionNameOrId('Branding_Marketing_Transfer_Approval');
                Approval.ProcessResult res = Approval.process(req);
                if (!res.isSuccess()) System.debug('Approval submission failed: ' + res);
            }
        }
    }
     else if (caseObj.Case_Type__r.Name == 'Asset Tagging Request' && manager.ManagerId != null) {

        // ================= POPULATE L1 FOR ASSET ADDITION =================
        List<Id> chain = getApproverChain(caseObj.OwnerId, 1);
        Case__c caseToUpdate = new Case__c(Id = caseObj.Id);
        if (chain.size() > 0) caseToUpdate.L1__c = chain[0];
        update caseToUpdate;

        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(caseObj.Id);
        req.setProcessDefinitionNameOrId('Case_Type_By_Case_Approval');
        Approval.ProcessResult res = Approval.process(req);
        if (!res.isSuccess()) System.debug('Approval submission failed: ' + res);
    }
}
return newCase.Id;
        } catch (AuraHandledException e) {
            // Already a user-facing message (e.g. the ASM/RSM approver rule).
            // Re-wrapping would replace it with "Script-thrown exception".
            throw e;
        } catch (Exception e) {
            System.debug('e.getMessage: ' + e.getMessage() + ' ' + e.getLineNumber());
            throw new AuraHandledException('Error saving case: ' + e.getMessage());
        }
    }

    /**
     * 90-day duplicate check, applied to any branding case type.
     *
     * Looks for an earlier case of the SAME type against the SAME account within
     * 90 days. Works off whichever account the request is for, so distributor-only
     * requests are covered as well as outlets.
     *
     * Must run before the approval submission: it stamps Duplicate_Warning__c,
     * which drives both the approval page field and the notification body, and the
     * case is locked once submitted.
     */
    private static void applyDuplicateWarning(Case__c caseObj) {
        Id accountId = caseObj.Retailer__c != null ? caseObj.Retailer__c : caseObj.Distributor__c;
        if (accountId == null || caseObj.Case_Type__r == null) return;

        String accountLabel = caseObj.Retailer__c != null ? 'outlet' : 'distributor';
        String caseTypeName = caseObj.Case_Type__r.Name;

        List<Case__c> prevCases = [
            SELECT Id, Name, CreatedDate
            FROM Case__c
            WHERE Case_Type__r.Name = :caseTypeName
              AND (Retailer__c = :accountId OR Distributor__c = :accountId)
              AND CreatedDate >= LAST_N_DAYS:90
              AND Id != :caseObj.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (prevCases.isEmpty()) return;

        String warningText = '⚠️ Warning: A branding request ' + prevCases[0].Name +
            ' was already raised for this ' + accountLabel + ' on ' +
            prevCases[0].CreatedDate.format('dd-MMM-yyyy') +
            '. Please review before approving.';

        update new Case__c(Id = caseObj.Id, Duplicate_Warning__c = warningText.abbreviate(255));

        // Feed post is the audit trail only - deliberately NOT @mentioning
        // approvers, because that raised a second, competing notification.
        if (!Test.isRunningTest()) {
            postDuplicateWarning(caseObj.Id, warningText);
        }
    }

    /**
     * Posts the 90-day duplicate warning to the case feed as a record of what was
     * flagged. No @mentions - the approver is told once, via the approval
     * notification, and sees the detail on the approval page.
     *
     * Isolated with its own try/catch: a Chatter failure must never roll back a
     * case that has already been created and submitted.
     */
    private static void postDuplicateWarning(Id caseId, String warningText) {
        try {
            insert new FeedItem(ParentId = caseId, Body = warningText);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'Duplicate warning post failed for case ' + caseId + ': ' + e.getMessage());
        }
    }

    // ================= GET ASSETS =================
    // Returns assets for retailer AND distributor (for Distributor to Outlet scenario)
    @AuraEnabled
    public static List<AssetWrapper> getAssets(Id visitTaskId) {
        try {
            List<AssetWrapper> result = new List<AssetWrapper>();
            List<Visit_Task__c> vtList = [
                SELECT Id, Retailer__c, Distributor__c 
                FROM Visit_Task__c WHERE Id = :visitTaskId LIMIT 1
            ];
            if (vtList.isEmpty()) throw new AuraHandledException('Visit Task not found');
            Visit_Task__c visitTask = vtList[0];
            
            // Query retailer assets + distributor assets (no retailer mapped)
            List<Asset_Mapping__c> mappings = new List<Asset_Mapping__c>();
            
            if (visitTask.Retailer__c != null) {
                mappings = [
                    SELECT Id, Allocation_Start_Date__c, Last_Service_Date__c, Last_Audit_Date__c, Active__c,
                           Asset_Master__r.OEM_Serial_Number__c, Asset_Master__r.QR_Code__c,
                           Asset_Master__c, Asset_Master__r.Asset_Image__c, Asset_Master__r.Asset_Serial_No__c,
                           Retailer__c, Distributor__c
                    FROM Asset_Mapping__c 
                    WHERE Retailer__c = :visitTask.Retailer__c
                ];
            } else if (visitTask.Distributor__c != null) {
    mappings = [
        SELECT Id, Allocation_Start_Date__c, Last_Service_Date__c, Last_Audit_Date__c, Active__c,
               Asset_Master__r.OEM_Serial_Number__c, Asset_Master__r.QR_Code__c,
               Asset_Master__c, Asset_Master__r.Asset_Image__c, Asset_Master__r.Asset_Serial_No__c,
               Retailer__c, Distributor__c
        FROM Asset_Mapping__c 
        WHERE (Distributor__c = :visitTask.Distributor__c 
               OR Super_Stockist__c = :visitTask.Distributor__c)
        AND Retailer__c = null
        AND Active__c = true
    ];
}
            
            Set<Id> mappingIds = new Set<Id>();
            Set<Id> assetMasterIds = new Set<Id>();
            for (Asset_Mapping__c am : mappings) {
                mappingIds.add(am.Id);
                if (am.Asset_Master__c != null) assetMasterIds.add(am.Asset_Master__c);
            }
            
            Map<Id, List<Attribute_Mapping__c>> attrMap = new Map<Id, List<Attribute_Mapping__c>>();
            if (!assetMasterIds.isEmpty()) {
                for (Attribute_Mapping__c attr : [
                    SELECT Id, Asset_Master__c, Active__c, Attribute_Master__c,
                           Attribute_Master__r.Name, Attribute_Value__c, Attribute_Value__r.Name
                    FROM Attribute_Mapping__c WHERE Asset_Master__c IN :assetMasterIds
                ]) {
                    if (!attrMap.containsKey(attr.Asset_Master__c)) attrMap.put(attr.Asset_Master__c, new List<Attribute_Mapping__c>());
                    attrMap.get(attr.Asset_Master__c).add(attr);
                }
            }
            
            Map<Id, Asset_Audit__c> auditMap = new Map<Id, Asset_Audit__c>();
            if (!mappingIds.isEmpty()) {
                for (Asset_Audit__c audit : [
    SELECT Id, Asset__c, CreatedDate, Skip__c, Scan__c, Audit_Date__c, Visit_Task__c
    FROM Asset_Audit__c
    WHERE Asset__c IN :mappingIds
    ORDER BY CreatedDate DESC
]) {
                    if (!auditMap.containsKey(audit.Asset__c)) auditMap.put(audit.Asset__c, audit);
                }
            }
            
            for (Asset_Mapping__c am : mappings) {
                AssetWrapper wrap = new AssetWrapper();
                wrap.mappingId = am.Id;
                wrap.allocationDate = am.Allocation_Start_Date__c;
                wrap.lastServiceDate = am.Last_Service_Date__c;
                wrap.lastAuditDate = am.Last_Audit_Date__c;
                wrap.active = am.Active__c;
                if (am.Asset_Master__r != null) {
                    wrap.qrCode = am.Asset_Master__r.OEM_Serial_Number__c;
                    wrap.serialNo = am.Asset_Master__r.Asset_Serial_No__c;
                    wrap.freezerId = am.Asset_Master__c;
                    wrap.imageUrl = am.Asset_Master__r.Asset_Image__c;
                }
                wrap.attributes = new Map<String, String>();
                if (am.Asset_Master__c != null && attrMap.containsKey(am.Asset_Master__c)) {
                    for (Attribute_Mapping__c attr : attrMap.get(am.Asset_Master__c)) {
                        wrap.attributes.put(attr.Attribute_Master__r.Name, attr.Attribute_Value__r.Name);
                    }
                }
                if (auditMap.containsKey(am.Id)) {
                    Asset_Audit__c latest = auditMap.get(am.Id);
                    if (latest.Visit_Task__c == visitTaskId) {
    wrap.isAuditedToday = true;
    wrap.isSkipped = latest.Skip__c;
    wrap.isScanned = latest.Scan__c;
} else {
    wrap.isAuditedToday = false;
    wrap.isSkipped = false;
    wrap.isScanned = false;
}
                } else {
                    wrap.isAuditedToday = false;
                    wrap.isSkipped = false;
                    wrap.isScanned = false;
                }
                result.add(wrap);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading assets: ' + e.getMessage());
        }
    }
    
    // ================= CREATE AUDIT =================
    @AuraEnabled
    public static void createAssetAudit(Id mappingId, String reason, String type, Id visitTaskId) {
        try {
            List<Asset_Mapping__c> mappingList = [
                SELECT Id, Last_Audit_Date__c, Retailer__c FROM Asset_Mapping__c WHERE Id = :mappingId LIMIT 1
            ];
            if (mappingList.isEmpty()) throw new AuraHandledException('Asset mapping not found');
            Asset_Mapping__c mapping = mappingList[0];
            Asset_Audit__c audit = new Asset_Audit__c();
            if (type == 'SKIP') {
                audit.Skip__c = true;
                audit.Reason__c = reason;
            }
            if (type == 'SCAN') audit.Scan__c = true;
            audit.Asset__c = mapping.Id;
            audit.Visit_Task__c = visitTaskId;
            audit.Audit_Date__c = System.today();
            audit.Outlet_Id__c = mapping.Retailer__c;
            insert audit;
            mapping.Last_Audit_Date__c = System.today();
            update mapping;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating asset audit: ' + e.getMessage());
        }
    }

    // ================= CHECK NEW ASSET CODE =================
    @AuraEnabled
    public static String checkNewAssetCode(String assetCode) {
        try {
            if (String.isBlank(assetCode)) return 'OK';
            List<Case__c> existing = [
                SELECT Id, Name, Status__c FROM Case__c
                WHERE New_Asset_Code__c = :assetCode
                AND Case_Type__r.Name = 'Existing outlet Asset Code Change Request'
                AND Status__c != 'Rejected'
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                return 'DUPLICATE:' + existing[0].Name + ':' + existing[0].Status__c;
            }
            return 'OK';
        } catch (Exception e) {
            throw new AuraHandledException('Error checking asset code: ' + e.getMessage());
        }
    }

    // ====================== UPLOAD FILES ======================
    @AuraEnabled
    public static void uploadFiles(Id caseId, List<Map<String, String>> files) {
        try {
            String imageUrl = attachFiles(caseId, files);
            stampRequestImage(caseId, imageUrl);
        } catch (Exception e) {
            throw new AuraHandledException('Error uploading files: ' + e.getMessage());
        }
    }

    /**
     * Records the request photo URL on the case.
     *
     * By the time files are uploaded the case has already been submitted for
     * approval, so it is locked. Unlock, write, re-lock - the approval itself is
     * unaffected. Best effort throughout: attaching the file is the job that
     * matters, and a failure here must never fail the case save.
     */
    private static void stampRequestImage(Id caseId, String imageUrl) {
        if (imageUrl == null) return;
        try {
            Case__c existing = [SELECT Id, Request_Image_URL__c FROM Case__c WHERE Id = :caseId];
            // Never overwrite: an installation upload must not clobber the
            // original request image.
            if (String.isNotBlank(existing.Request_Image_URL__c)) return;

            Boolean wasLocked = Approval.isLocked(caseId);
            if (wasLocked) Approval.unlock(new List<Id>{ caseId }, false);
            try {
                update new Case__c(Id = caseId, Request_Image_URL__c = imageUrl);
            } finally {
                if (wasLocked) Approval.lock(new List<Id>{ caseId }, false);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'Could not record request image on case ' + caseId + ': ' + e.getMessage());
        }
    }

    /**
     * Uploads the installation photo, records it on the case, then moves the case
     * to Installed - in that order, so the Branding Asset records created by
     * CaseTriggerHandler can pick the image up.
     *
     * Single entry point so the photo and the status change can't drift apart.
     */
    @AuraEnabled
    public static void submitInstallation(Id caseId, List<Map<String, String>> files) {
        try {
            if (files == null || files.isEmpty()) {
                throw new AuraHandledException('An installation photo is required.');
            }

            String imageUrl = attachFiles(caseId, files);
            update new Case__c(Id = caseId, Installation_Image_URL__c = imageUrl);

            // Separate DML: the trigger requeries the case, so the image URL has
            // to already be committed before the status flips to Installed.
            update new Case__c(Id = caseId, Status__c = 'Installed');
        } catch (Exception e) {
            throw new AuraHandledException('Could not submit the installation: ' + e.getMessage());
        }
    }

    /**
     * Shared upload helper. Returns a rendered download URL for the first file,
     * matching the pattern already used for Asset_Master__c.Asset_Image__c.
     */
    private static String attachFiles(Id recordId, List<Map<String, String>> files) {
        if (files == null || files.isEmpty()) return null;

        List<ContentVersion> listCV = new List<ContentVersion>();
        for (Map<String, String> f : files) {
            ContentVersion cv = new ContentVersion();
            cv.Title = f.get('fileName');
            cv.PathOnClient = f.get('fileName');
            cv.VersionData = EncodingUtil.base64Decode(f.get('base64'));
            listCV.add(cv);
        }
        insert listCV;

        Map<Id, Id> versionToDoc = new Map<Id, Id>();
        for (ContentVersion cv : [
            SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :listCV
        ]) {
            versionToDoc.put(cv.Id, cv.ContentDocumentId);
        }

        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (ContentVersion cv : listCV) {
            Id docId = versionToDoc.get(cv.Id);
            if (docId == null) continue;
            links.add(new ContentDocumentLink(
                ContentDocumentId = docId,
                LinkedEntityId = recordId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
        }
        if (!links.isEmpty()) insert links;

        return System.URL.getOrgDomainUrl().toExternalForm() +
               '/sfc/servlet.shepherd/version/download/' + listCV[0].Id;
    }

//---------------------UPDATE CASE TO INSTALLED------------------------------

    @AuraEnabled
public static void updateCaseToInstalled(Id caseId) {
    try {
        update new Case__c(Id = caseId, Status__c = 'Installed');
    } catch (Exception e) {
        throw new AuraHandledException('Could not update case: ' + e.getMessage());
    }
}

    // ================= WRAPPERS =================
    public class FormFieldWrapper {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
        @AuraEnabled public Boolean required;
        @AuraEnabled public String lookupObject;
        @AuraEnabled public List<PicklistOption> options;
        @AuraEnabled public String ffId;
        @AuraEnabled public Boolean isControlling;
    }
    
    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        // Controlling value, when the option is dependent on a parent picklist.
        @AuraEnabled public String parent;
    }
    
    public class AssetWrapper {
        @AuraEnabled public Id mappingId;
        @AuraEnabled public Date allocationDate;
        @AuraEnabled public Date lastServiceDate;
        @AuraEnabled public Date lastAuditDate;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Boolean isAuditedToday;
        @AuraEnabled public Boolean isScanned;
        @AuraEnabled public Boolean isSkipped;
        @AuraEnabled public String serialNo;
        @AuraEnabled public String qrCode;
        @AuraEnabled public String freezerId;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Map<String, String> attributes;
    }

    @AuraEnabled
    public static String checkQRCodeDuplicate(String qrCode, Id retailerId) {
        try {
            if (String.isBlank(qrCode) || retailerId == null) return 'OK';
            List<Asset_Mapping__c> existing = [
                SELECT Id
                FROM Asset_Mapping__c
                WHERE Retailer__c = :retailerId
                AND Asset_Master__r.OEM_Serial_Number__c = :qrCode
                AND Active__c = true
                LIMIT 1
            ];
            return existing.isEmpty() ? 'OK' : 'DUPLICATE';
        } catch (Exception e) {
            throw new AuraHandledException('Error checking QR code: ' + e.getMessage());
        }
    }
    @AuraEnabled
public static List<AssetWrapper> getAssetsByAccount(Id retailerId, Id distributorId) {
    try {
        List<AssetWrapper> result = new List<AssetWrapper>();
        List<Asset_Mapping__c> mappings = new List<Asset_Mapping__c>();

        if (retailerId != null) {
            mappings = [
                SELECT Id, Allocation_Start_Date__c, Last_Service_Date__c, Last_Audit_Date__c, Active__c,
                       Asset_Master__r.OEM_Serial_Number__c, Asset_Master__r.QR_Code__c,
                       Asset_Master__c, Asset_Master__r.Asset_Image__c, Asset_Master__r.Asset_Serial_No__c,
                       Retailer__c, Distributor__c
                FROM Asset_Mapping__c 
                WHERE Retailer__c = :retailerId
            ];
      } else if (distributorId != null) {
            mappings = [
                SELECT Id, Allocation_Start_Date__c, Last_Service_Date__c, Last_Audit_Date__c, Active__c,
                       Asset_Master__r.OEM_Serial_Number__c, Asset_Master__r.QR_Code__c,
                       Asset_Master__c, Asset_Master__r.Asset_Image__c, Asset_Master__r.Asset_Serial_No__c,
                       Retailer__c, Distributor__c, Super_Stockist__c
                FROM Asset_Mapping__c 
                WHERE (Distributor__c = :distributorId OR Super_Stockist__c = :distributorId)
                AND Retailer__c = null
                AND Active__c = true
            ];
        }
        

        if (mappings.isEmpty()) return result;

        Set<Id> assetMasterIds = new Set<Id>();
        for (Asset_Mapping__c am : mappings) {
            if (am.Asset_Master__c != null) assetMasterIds.add(am.Asset_Master__c);
        }

        Map<Id, List<Attribute_Mapping__c>> attrMap = new Map<Id, List<Attribute_Mapping__c>>();
        if (!assetMasterIds.isEmpty()) {
            for (Attribute_Mapping__c attr : [
                SELECT Id, Asset_Master__c, Attribute_Master__r.Name, Attribute_Value__r.Name
                FROM Attribute_Mapping__c WHERE Asset_Master__c IN :assetMasterIds
            ]) {
                if (!attrMap.containsKey(attr.Asset_Master__c)) attrMap.put(attr.Asset_Master__c, new List<Attribute_Mapping__c>());
                attrMap.get(attr.Asset_Master__c).add(attr);
            }
        }

        for (Asset_Mapping__c am : mappings) {
            AssetWrapper wrap = new AssetWrapper();
            wrap.mappingId = am.Id;
            wrap.allocationDate = am.Allocation_Start_Date__c;
            wrap.lastServiceDate = am.Last_Service_Date__c;
            wrap.lastAuditDate = am.Last_Audit_Date__c;
            wrap.active = am.Active__c;
            if (am.Asset_Master__r != null) {
                wrap.qrCode = am.Asset_Master__r.OEM_Serial_Number__c;
                wrap.serialNo = am.Asset_Master__r.Asset_Serial_No__c;
                wrap.freezerId = am.Asset_Master__c;
                wrap.imageUrl = am.Asset_Master__r.Asset_Image__c;
            }
            wrap.attributes = new Map<String, String>();
            if (am.Asset_Master__c != null && attrMap.containsKey(am.Asset_Master__c)) {
                for (Attribute_Mapping__c attr : attrMap.get(am.Asset_Master__c)) {
                    wrap.attributes.put(attr.Attribute_Master__r.Name, attr.Attribute_Value__r.Name);
                }
            }
            wrap.isAuditedToday = false;
            wrap.isSkipped = false;
            wrap.isScanned = false;
            result.add(wrap);
        }
        return result;
    } catch (Exception e) {
        throw new AuraHandledException('Error loading assets: ' + e.getMessage());
    }
}
@AuraEnabled(cacheable=true)
public static List<Map<String, String>> getRetailersByUser() {
    try {
        List<Map<String, String>> result = new List<Map<String, String>>();
        for (Account acc : [
            SELECT Id, Name 
            FROM Account 
            WHERE OwnerId = :UserInfo.getUserId()
            AND RecordType.Name = 'Retailer'
            ORDER BY Name
        ]) {
            result.add(new Map<String, String>{
                'label' => acc.Name,
                'value' => acc.Id
            });
        }
        return result;
    } catch (Exception e) {
        throw new AuraHandledException('Error fetching retailers: ' + e.getMessage());
    }
}

@AuraEnabled(cacheable=true)
public static List<Map<String, String>> getDistributorsByUser() {
    try {
        List<Map<String, String>> result = new List<Map<String, String>>();
        for (Account acc : [
            SELECT Id, Name, RecordType.Name
            FROM Account 
            WHERE OwnerId = :UserInfo.getUserId()
            AND RecordType.Name IN ('Distributor', 'Super Stockist')
            ORDER BY Name
        ]) {
            result.add(new Map<String, String>{
                'label' => acc.Name,
                'value' => acc.Id
            });
        }
        return result;
    } catch (Exception e) {
        throw new AuraHandledException('Error fetching distributors: ' + e.getMessage());
    }
}
/**
 * First ASM or RSM above this user.
 *
 * getApproverChain can return a ZSM when that is the first manager it finds, so
 * branding approvals filter explicitly here: L1 must be an ASM or RSM - never an
 * SO, KAM, ZSM or VP. Returns null when the hierarchy contains neither.
 */
private static Id resolveBrandingL1(Id ownerId) {
    List<Id> chain = getApproverChain(ownerId, 3);
    if (chain.isEmpty()) return null;

    Map<Id, User> usersById = new Map<Id, User>([
        SELECT Id, UserRole.Name FROM User WHERE Id IN :chain
    ]);
    for (Id candidateId : chain) {
        User u = usersById.get(candidateId);
        if (u == null) continue;
        String level = getRoleLevel(u.UserRole?.Name);
        if (level == 'ASM' || level == 'RSM') return candidateId;
    }
    return null;
}

/** Blocks submission rather than routing a branding case to the wrong level. */
private static Id requireBrandingL1(Id ownerId) {
    Id l1 = resolveBrandingL1(ownerId);
    if (l1 == null) {
        throw new AuraHandledException(
            'No ASM or RSM approver was found in your reporting hierarchy. ' +
            'Please contact your administrator before raising this request.');
    }
    return l1;
}

// ================= GET ROLE LEVEL =================
private static String getRoleLevel(String roleName) {
    if (String.isBlank(roleName)) return 'UNKNOWN';
    String firstPart = roleName.split('-')[0].trim().toUpperCase();
    firstPart = firstPart.replaceAll('\\(.*\\)', '').trim();
    if (firstPart.startsWith('ZSM')) return 'ZSM';
    if (firstPart.startsWith('RSM')) return 'RSM';
    if (firstPart.startsWith('ASM')) return 'ASM';
    if (firstPart.startsWith('VP') || firstPart.startsWith('AVP') || 
        firstPart.startsWith('APTSKLNK')) return 'VP';
    if (firstPart.startsWith('SO') || firstPart.startsWith('SSO') || 
        firstPart.startsWith('PSR') || firstPart.startsWith('KAM')) return 'SO';
    return 'UNKNOWN';
}
private static List<Id> getApproverChain(Id userId, Integer maxLevels) {
    List<Id> chain = new List<Id>();
    Set<Id> visited = new Set<Id>();
    Id currentId = userId;
    Integer maxHops = 10;
    Id finalApproverId = null;

    while (currentId != null && maxHops > 0) {
        if (visited.contains(currentId)) break;
        visited.add(currentId);

        List<User> users = [
            SELECT Id, ManagerId, UserRole.Name
            FROM User
            WHERE Id = :currentId
            LIMIT 1
        ];
        if (users.isEmpty()) break;

        User u = users[0];
        currentId = u.ManagerId;
        if (currentId == null) break;

        List<User> managerList = [
            SELECT Id, ManagerId, UserRole.Name
            FROM User
            WHERE Id = :currentId
            LIMIT 1
        ];
        if (managerList.isEmpty()) break;

        User manager = managerList[0];
        String level = getRoleLevel(manager.UserRole?.Name);

        if (level == 'ZSM') {
            // ZSM found — stop here, ZSM is final approver
            finalApproverId = manager.Id;
            break;
        } else if (level == 'VP') {
            // VP found — stop here, use last ASM/RSM in chain as final approver
            // Do NOT include VP
            if (!chain.isEmpty()) {
                finalApproverId = chain[chain.size() - 1];
            }
            break;
        } else if (level == 'ASM' || level == 'RSM') {
            chain.add(manager.Id);
        }

        maxHops--;
    }

    // Build final chain with padding
    List<Id> result = new List<Id>();
    
    if (finalApproverId != null) {
        // Add all intermediate approvers except final
        for (Id id : chain) {
            if (id != finalApproverId) result.add(id);
        }
        // Add final approver
        result.add(finalApproverId);
    } else if (!chain.isEmpty()) {
        result.addAll(chain);
    }

    // Pad to maxLevels with last person
    if (!result.isEmpty()) {
        Id lastId = result[result.size() - 1];
        while (result.size() < maxLevels) {
            result.add(lastId);
        }
    }

    return result;
}
@AuraEnabled
public static String checkAssetCodeInMaster(String assetCode) {
    try {
        if (String.isBlank(assetCode)) return 'OK';
        
        // Check prefix validation
        if (!assetCode.startsWith('HIPL') && !assetCode.startsWith('TEST')) {
            return 'INVALID_PREFIX';
        }
        
        // Check if already exists in Asset Master
        List<Asset_Master__c> existing = [
            SELECT Id, OEM_Serial_Number__c
            FROM Asset_Master__c
            WHERE OEM_Serial_Number__c = :assetCode
            LIMIT 1
        ];
        if (!existing.isEmpty()) return 'DUPLICATE_MASTER';
        
        return 'OK';
    } catch (Exception e) {
        throw new AuraHandledException('Error checking asset code: ' + e.getMessage());
    }
}
@AuraEnabled
public static String checkSerialNumber(String serialNumber) {
    try {
        if (String.isBlank(serialNumber)) return 'OK';
        
        // Check in Cases only (Asset_Serial_No__c is Long Text - cannot filter)
        List<Case__c> existingCase = [
            SELECT Id, Name, Status__c
            FROM Case__c
            WHERE Serial_Number__c = :serialNumber
            AND Status__c != 'Rejected'
            AND Case_Type__r.Name IN (
    'Existing outlet Asset Code Change Request',
    'Asset Tagging Request'
)
            LIMIT 1
        ];
        if (!existingCase.isEmpty()) {
            return 'DUPLICATE_CASE:' + existingCase[0].Name + ':' + existingCase[0].Status__c;
        }
        
        return 'OK';
    } catch (Exception e) {
        throw new AuraHandledException('Error checking serial number: ' + e.getMessage());
    }
}
}