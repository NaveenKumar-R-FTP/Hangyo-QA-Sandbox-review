/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClaimHeaderController
 * Author          : <YourName>
 * Created Date    : Mar 23, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Mar 23, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Mar 23, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClaimHeaderController
 * Author          : <YourName>
 * Created Date    : Mar 23, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Mar 23, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Mar 23, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public without sharing class ClaimHeaderController {

    @AuraEnabled(cacheable=true)
    public static Map<String, List<getPicklistHelper.PicklistOption>> getMultiplePicklistValues() {
        Map<String, List<getPicklistHelper.PicklistOption>> fieldValueMap = new Map<String, List<getPicklistHelper.PicklistOption>>();

        fieldValueMap.put(
            'statusoption',
            getPicklistHelper.getPicklistValues('Claim_Header__c', 'Status__c')
        );

        fieldValueMap.put(
            'yearoption',
            getPicklistHelper.getPicklistValues('Claim_Header__c', 'Year__c')
        );

        fieldValueMap.put(
            'monthoption',
            getPicklistHelper.getPicklistValues('Claim_Header__c', 'Month__c')
        );

        return fieldValueMap;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, List<Object>> getAccountsAndCaseTypesMap() {
        Map<String, List<Object>> responseMap = new Map<String, List<Object>>();

        User u = [
            SELECT Id, AccountId, IsPortalEnabled
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        
       Id accrt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Distributor').getRecordTypeId();


        List<Account> accounts;

        if (u.IsPortalEnabled && u.AccountId != null) {
            accounts = [
                SELECT Id, Name
                FROM Account
                WHERE Id = :u.AccountId
                LIMIT 1
            ];
        } else {
            accounts = [
                SELECT Id, Name
                FROM Account
                WHERE Status__c = 'Active' AND RecordTypeId =: accrt
                ORDER BY Name
                LIMIT 200
            ];
        }

        Id damageRTId = Schema.SObjectType.Case_Type__c.getRecordTypeInfosByDeveloperName().get('Claim').getRecordTypeId();

        List<Case_Type__c> caseTypes = [
            SELECT Id, Name, RecordType.DeveloperName
            FROM Case_Type__c
            WHERE RecordTypeId = :damageRTId AND Active__c = true AND Type__c = 'Claim'
            ORDER BY Name
        ];

        responseMap.put('accounts', (List<Account>)accounts);
        responseMap.put('caseTypes', (List<Case_Type__c>)caseTypes);

        return responseMap;
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, String> createClaimWithAttachment(String requestData) {
        Map<String, String> response = new Map<String, String>();
        String allErrors = '';
        Savepoint sp;

        try {
            sp = Database.setSavepoint();

            Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(requestData);
            Map<String, Claim_Header__c> claimHeaderMap = new Map<String, Claim_Header__c>();

            Map<String, Object> header = (Map<String, Object>) dataMap.get('header');

            String distributorId = (String) header.get('distributorId');
            String claimMonth    = (String) header.get('claimMonth');
            String claimYear     = (String) header.get('claimYear');
            
            Id accrt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Distributor').getRecordTypeId();

 
            Account acc = [
                SELECT Id,
                Approver_1__c, Approver_1__r.Name,
                Approver_2__c, Approver_2__r.Name,
                RSM_SSM__c, RSM_SSM__r.Name
                FROM Account
                WHERE Id = :distributorId AND RecordTypeId =: accrt
            ];

            List<Claim_Header__c> existingHeaders = [
                SELECT Id, Distributor__c,Distributor__r.Name, Month__c,Status__c, Year__c
                FROM Claim_Header__c
                WHERE Distributor__c = :distributorId
                AND Month__c = :claimMonth
                AND Year__c = :claimYear
                LIMIT 1
            ];
            system.debug('existingHeaders'+existingHeaders);


            if (!existingHeaders.isEmpty()) {
                Claim_Header__c headers = existingHeaders[0];

                if (headers.Status__c == 'Approved') {
                    String monthName = headers.Month__c;
                    response.put('status', 'ERROR');
                    response.put('message',monthName + ' month claim has already been approved. Please add claim for next month .');
                    return response;
                }
            }

            Claim_Header__c headerRec;

            if (!existingHeaders.isEmpty()) {

                headerRec = existingHeaders[0];

                List<ProcessInstance> approvalList = [
                    SELECT Id, Status, (SELECT StepStatus, Actor.Name FROM StepsAndWorkitems WHERE StepStatus = 'Pending')
                    FROM ProcessInstance
                    WHERE TargetObjectId = :headerRec.Id
                    AND Status = 'Pending'
                    LIMIT 1
                ];

                if (!approvalList.isEmpty()) {
                    ProcessInstance activeApproval = approvalList[0];
                    String approverName = '';

                    if (!activeApproval.StepsAndWorkitems.isEmpty()) {
                        approverName = activeApproval.StepsAndWorkitems[0].Actor.Name;
                    }

                    response.put('status', 'ERROR');
                    response.put(
                        'message',
                        'Claim for ' + headerRec.Month__c +
                        ' is already under approval by Manager ' +
                        (String.isNotBlank(approverName) ? approverName : 'Pending Approval')
                    );
                    return response;
                }

            } else {

                headerRec = new Claim_Header__c();
                headerRec.Distributor__c = distributorId;
                headerRec.Month__c = claimMonth;
                headerRec.Year__c = claimYear;
                headerRec.SO__c = acc.Approver_1__c;
                headerRec.RSM__c = acc.RSM_SSM__c;
                headerRec.ASM__c = acc.Approver_2__c;
                headerRec.Description__c = (String) header.get('claimDescription');

                if (!String.isBlank((String) header.get('submittedDate'))) {
                    headerRec.Submitted_Date__c = Date.valueOf((String) header.get('submittedDate'));
                }

                headerRec.Status__c = (String) header.get('claimStatus');

                insert headerRec;
            }

            List<Object> rawLines = (List<Object>) dataMap.get('lines');
            List<Claim_Line_Item__c> lineRecs = new List<Claim_Line_Item__c>();
            Map<String, Id> lineIdMapping = new Map<String, Id>();

            for (Object rawLine : rawLines) {
                Map<String, Object> line = (Map<String, Object>) rawLine;

                if (String.isBlank((String) line.get('caseTypeId'))) {
                    response.put('status', 'ERROR');
                    response.put('message','Claim Type is required for a line item.');
                    return response;
                }

                if (String.isBlank((String) line.get('amount'))) {
                    response.put('status', 'ERROR');
                    response.put('message','Amount is required for a line item.');
                    return response;
                }

                Claim_Line_Item__c lineRec = new Claim_Line_Item__c();
                lineRec.Claim__c      = headerRec.Id;
                lineRec.Status__c = 'Pending';
                lineRec.Case_Type__c = (String) line.get('caseTypeId');
                lineRec.Amount__c     = Decimal.valueOf(((String) line.get('amount')).replace(',', ''));
                lineRec.Approved_Amount__c = Decimal.valueOf(((String) line.get('amount')).replace(',', ''));

                if (!String.isBlank((String) line.get('date'))) {
                    lineRec.Claim_Date__c = Date.valueOf((String) line.get('date'));
                }

                lineRec.Remark__c     = (String) line.get('remarks');

                lineRecs.add(lineRec);
            }

            insert lineRecs;

            for (Integer i = 0; i < rawLines.size(); i++) {
                Map<String, Object> line = (Map<String, Object>) rawLines[i];
                String frontendLineId = (String) line.get('lineId');
                if (i < lineRecs.size()) {
                    lineIdMapping.put(frontendLineId, lineRecs[i].Id);
                }
            }

            List<ContentVersion> cvList = new List<ContentVersion>();
            List<Map<String, Object>> cdlMapping = new List<Map<String, Object>>();

            for (Integer i = 0; i < rawLines.size(); i++) {
                Map<String, Object> line = (Map<String, Object>) rawLines[i];
                List<Object> filesList = (List<Object>) line.get('files');
                String frontendLineId = (String) line.get('lineId');
                Id lineItemId = lineIdMapping.get(frontendLineId);

                if (filesList == null || filesList.isEmpty()) {
                    response.put('status', 'ERROR');
                    response.put('message','Please upload at least one file for each claim line.');
                    return response;
                }

                for (Object fileObj : filesList) {
                    Map<String, Object> fileMap = (Map<String, Object>) fileObj;
                    String base64Data = (String) fileMap.get('base64');
                    String fileName   = (String) fileMap.get('name');

                    if (String.isBlank(base64Data)) {
                        response.put('status', 'ERROR');
                        response.put('message','File data is missing for line item.');
                        return response;
                    }

                    if (String.isBlank(fileName)) {
                        response.put('status', 'ERROR');
                        response.put('message','File name is missing for line item.');
                        return response;
                    }

                    ContentVersion cv = new ContentVersion();
                    cv.Title = fileName.replaceAll('\\.[^.]+$', '') != '' ? fileName.replaceAll('\\.[^.]+$', '') : 'File';
                    cv.PathOnClient = fileName;
                    cv.VersionData  = EncodingUtil.base64Decode(base64Data);

                    cvList.add(cv);

                    cdlMapping.add(new Map<String, Object>{
                        'lineItemId' => lineItemId,
                        'frontendLineId' => frontendLineId,
                        'index' => cvList.size() - 1
                    });
                }
            }

            if (!cvList.isEmpty()) {
                insert cvList;

                List<ContentVersion> insertedCVs = [
                    SELECT Id, ContentDocumentId
                    FROM ContentVersion
                    WHERE Id IN :cvList
                ];

                Map<Id, ContentVersion> cvMap = new Map<Id, ContentVersion>(insertedCVs);

                List<ContentDocumentLink> cdlList = new List<ContentDocumentLink>();

                for (Map<String, Object> mapObj : cdlMapping) {
                    Id lineItemId = (Id) mapObj.get('lineItemId');
                    Integer idx = (Integer) mapObj.get('index');
                    ContentVersion cv = cvList[idx];

                    ContentDocumentLink cdl = new ContentDocumentLink();
                    cdl.ContentDocumentId = cvMap.get(cv.Id).ContentDocumentId;
                    cdl.LinkedEntityId = lineItemId;
                    cdl.ShareType = 'V';

                    cdlList.add(cdl);
                }

                insert cdlList;
            }

            response.put('status', 'SUCCESS');
            response.put('lineIdMapping', JSON.serialize(lineIdMapping));

        } catch (Exception e) {

            if (sp != null) {
                Database.rollback(sp);
            }

            response.put('status', 'ERROR');
            response.put('message', e.getMessage() + ' (Error at line: ' + e.getLineNumber() + ')');
            system.debug('Message : '+e.getMessage() + ' (Error at line: ' + e.getLineNumber() + ')');
            return response;
        }

        return response;
    }

    @AuraEnabled(cacheable=true)
public static Boolean isClaimHeaderApproved(Id distributorId, String month, String year) {
    List<Claim_Header__c> records = [
        SELECT Id 
        FROM Claim_Header__c
        WHERE Distributor__c = :distributorId
        AND Month__c = :month
        AND Year__c = :year
        AND (Status__c = 'Approved' OR Status__c = 'L1 Approved' OR Status__c = 'L2 Approved' OR Status__c = 'L3 Approved' OR Status__c = 'L4 Approved')
        LIMIT 1
    ];

    return !records.isEmpty();
}
}