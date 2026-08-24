public class ClaimHeaderTriggerHelper {
    
    public static void enforceApprovalComments(List<Claim_Header__c> newRecords, Map<Id, Claim_Header__c> oldMap) {
        
        Set<Id> approvalIds = new Set<Id>();
        for (Claim_Header__c a : newRecords) {
            if (oldMap == null || !oldMap.containsKey(a.Id)) continue;
            
            Claim_Header__c oldA = oldMap.get(a.Id);
            if (oldA.Status__c != a.Status__c && a.Status__c == 'Reject') {
                approvalIds.add(a.Id);
            }
        }
        
        if (approvalIds.isEmpty()) return;
        
        List<ProcessInstanceStep> steps = [
            SELECT Id, Comments, ProcessInstance.TargetObjectId
            FROM ProcessInstanceStep
            WHERE ProcessInstance.TargetObjectId IN :approvalIds
            ORDER BY CreatedDate DESC
        ];
        
        Map<Id, ProcessInstanceStep> latestStepByTarget = new Map<Id, ProcessInstanceStep>();
        for (ProcessInstanceStep s : steps) {
            Id targetId = s.ProcessInstance.TargetObjectId;
            
            if (!latestStepByTarget.containsKey(targetId)) {
                latestStepByTarget.put(targetId, s);
            }
        }
        
        for (Claim_Header__c a : newRecords) {
            if (!approvalIds.contains(a.Id)) continue;
            
            ProcessInstanceStep step = latestStepByTarget.get(a.Id);
            if (step == null || String.isBlank(step.Comments)) {
                a.addError('Comments are mandatory when rejecting. Please add comments in the approval action.');
            }else {
                a.Rejected_Reason__c = step.Comments;
            }
        }
    }
}