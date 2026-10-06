/**
* ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
* Class Name      : ApproveReturnCaseAction
* Description     : Approves a branding case in one step - stamps the mandatory
*                   values, then approves the running user's pending work item.
*
*                   Serves both branding approval flows. Vendor is always set.
*                   Branding Return Status is set only when the caller passes one,
*                   which is what separates the two:
*                     - Approve_Return_Case  (transfer/return) sends both
*                     - Approve_New_Request  (new request)     sends vendor only
*
*                   This exists because approval-process field updates bypass
*                   validation rules, so the standard Approve button could carry a
*                   case to Completed with no Vendor. CaseTriggerHandler blocks
*                   that; this action is the sanctioned way through, setting the
*                   values first so the guard is satisfied.
*
*                   The record is locked while pending, so the approval process
*                   must keep recordEditability = AdminOrCurrentApprover for the
*                   update below to succeed.
* ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
*/
public with sharing class ApproveReturnCaseAction {

    public class Request {
        @InvocableVariable(required=true) public Id caseId;
        // String, not Id: Flow choice sets have no Id data type, so the screen
        // hands this over as text and it is cast on the way into the field.
        @InvocableVariable(required=true) public String vendorId;
        // Optional: the transfer/return type sets it, the new request type does
        // not. Left blank, the field is not touched at all.
        @InvocableVariable public String returnStatus;
        @InvocableVariable public String comments;
    }

    public class Result {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String message;
    }

    @InvocableMethod(label='Approve Branding Case'
        description='Sets Vendor, and Branding Return Status when one is supplied, then approves the running approver\'s pending step')
    public static List<Result> approve(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result res = new Result();
            try {
                // 1. Set the mandatory values on the locked record. Vendor is
                //    always required; the return status only exists on the
                //    transfer type, so it is written only when one is passed.
                Case__c toStamp = new Case__c(
                    Id = req.caseId,
                    Vendor__c = (Id) req.vendorId
                );
                if (String.isNotBlank(req.returnStatus)) {
                    toStamp.Branding_Return_Status__c = req.returnStatus;
                }
                update toStamp;

                // 2. This approver's own pending work item - never anyone else's.
                List<ProcessInstanceWorkitem> items = [
                    SELECT Id FROM ProcessInstanceWorkitem
                    WHERE ProcessInstance.TargetObjectId = :req.caseId
                      AND ProcessInstance.Status = 'Pending'
                      AND ActorId = :UserInfo.getUserId()
                    LIMIT 1
                ];
                if (items.isEmpty()) {
                    res.success = false;
                    res.message = 'No pending approval assigned to you was found for this case.';
                    results.add(res);
                    continue;
                }

                // 3. Approve it.
                Approval.ProcessWorkitemRequest pwr = new Approval.ProcessWorkitemRequest();
                pwr.setWorkitemId(items[0].Id);
                pwr.setAction('Approve');
                if (String.isNotBlank(req.comments)) pwr.setComments(req.comments);
                Approval.process(pwr);

                res.success = true;
                res.message = 'Case approved.';
            } catch (Exception e) {
                res.success = false;
                res.message = e.getMessage();
            }
            results.add(res);
        }
        return results;
    }
}