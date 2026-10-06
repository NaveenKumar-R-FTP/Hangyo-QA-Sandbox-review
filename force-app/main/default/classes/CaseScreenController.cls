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
                           Retailer_Transfer_To__r.Name, Status__c, CreatedBy.Name
                    FROM Case__c
                    WHERE Status__c = 'Approved' AND Case_Type__c != null
                    ORDER BY CreatedDate DESC LIMIT 20
                ];
                List<Case__c> openCases = [
                    SELECT Id, Name, Case_Type__r.Name, Retailer__r.Name, Retailer_Transfer_From__r.Name,
                           Retailer_Transfer_To__r.Name, Status__c, CreatedBy.Name
                    FROM Case__c
                    WHERE Status__c != 'Approved' AND Status__c != null AND Case_Type__c != null
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
                           Retailer_Transfer_To__r.Name, Status__c, CreatedBy.Name
                    FROM Case__c
                    WHERE (Retailer__c = :accountId OR Retailer_Transfer_From__c = :accountId OR Retailer_Transfer_To__c = :accountId
                           OR Distributor__c = :accountId OR Distributor_Transfer_From__c = :accountId OR Distributor_Transfer_To__c = :accountId)
                    AND Status__c = 'Approved' AND Case_Type__c != null
                    ORDER BY CreatedDate DESC LIMIT 20
                ];
                List<Case__c> openCase = [
                    SELECT Id, Name, Case_Type__r.Name, Retailer__r.Name, Retailer_Transfer_From__r.Name,
                           Retailer_Transfer_To__r.Name, Status__c, CreatedBy.Name
                    FROM Case__c
                    WHERE (Retailer__c = :accountId OR Retailer_Transfer_From__c = :accountId OR Retailer_Transfer_To__c = :accountId
                           OR Distributor__c = :accountId OR Distributor_Transfer_From__c = :accountId OR Distributor_Transfer_To__c = :accountId)
                    AND Status__c != 'Approved' AND Status__c != null AND Case_Type__c != null
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

            // ================= APPROVAL SUBMISSION =================
            // ================= APPROVAL SUBMISSION =================
Case__c caseObj = [
    SELECT Id, Name, Retailer__r.Name, CreatedBy.Name, Case_Type__r.Name, Case_Type__c, OwnerId
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
        if (!Test.isRunningTest()) {
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(caseObj.Id);
            req.setProcessDefinitionNameOrId('Branding_Marketing_Asset_Inventory');
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
            caseToUpdate.L1__c = uniqueChain.size() > 0 ? uniqueChain[0] : maheshId;
            caseToUpdate.L2__c = uniqueChain.size() > 1 ? uniqueChain[1] : maheshId;
            caseToUpdate.L3__c = uniqueChain.size() > 2 ? uniqueChain[2] : maheshId;
            caseToUpdate.L4__c = maheshId;
            update caseToUpdate;
            if (!Test.isRunningTest()) {
                Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
                req.setObjectId(caseObj.Id);
                req.setProcessDefinitionNameOrId('Branding_Marketing_Asset');
                Approval.ProcessResult res = Approval.process(req);
                if (!res.isSuccess()) System.debug('Approval submission failed: ' + res);
            }
        } else {
            if (!Test.isRunningTest()) {
                Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
                req.setObjectId(caseObj.Id);
                req.setProcessDefinitionNameOrId('Branding_Marketing_Asset_R_and_A_T_R');
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
        } catch (Exception e) {
            System.debug('e.getMessage: ' + e.getMessage() + ' ' + e.getLineNumber());
            throw new AuraHandledException('Error saving case: ' + e.getMessage());
        }
    }

    // ================= GET ASSETS =================
    
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
            if (files == null || files.isEmpty()) return;
            List<ContentVersion> listCV = new List<ContentVersion>();
            for (Map<String, String> f : files) {
                ContentVersion cv = new ContentVersion();
                cv.Title = f.get('fileName');
                cv.PathOnClient = f.get('fileName');
                cv.VersionData = EncodingUtil.base64Decode(f.get('base64'));
                listCV.add(cv);
            }
            insert listCV;
            List<ContentDocumentLink> links = new List<ContentDocumentLink>();
            for (ContentVersion cv : listCV) {
                Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
                links.add(new ContentDocumentLink(
                    ContentDocumentId = docId,
                    LinkedEntityId = caseId,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                ));
            }
            if (!links.isEmpty()) insert links;
        } catch (Exception e) {
            throw new AuraHandledException('Error uploading files: ' + e.getMessage());
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