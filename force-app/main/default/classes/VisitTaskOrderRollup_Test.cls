/*
Created By : Fuzail
Created Date : 25/11/2025
Last Modified Date : 26/11/2025
*/

@isTest
public class VisitTaskOrderRollup_Test {

    @isTest
    static void simpleTest() {

        // Get the Secondary Order record type
        RecordType orderRT = [
            SELECT Id 
            FROM RecordType 
            WHERE SobjectType = 'Order__c'
            AND DeveloperName = 'Secondary_Order'
            LIMIT 1
        ];

        // First create a parent Order__c (required for Visit__c)
        Order__c parentOrder = new Order__c(
            RecordTypeId = orderRT.Id,
            Type__c = 'Field Order'
        );
        insert parentOrder;

        // Create Visit__c (Name is auto-number → don't set it)
        Visit__c visit = new Visit__c();
        insert visit;

        // Create Visit Task linked to Visit
        Visit_Task__c vt = new Visit_Task__c(
            Visit__c = visit.Id
        );
        insert vt;

        // Child orders that will be rolled up
        insert new Order__c(
            Visit_Task__c = vt.Id,
            Total_Order_Value__c = 150,
            RecordTypeId = orderRT.Id,
            Type__c = 'Field Order'
        );

        insert new Order__c(
            Visit_Task__c = vt.Id,
            Total_Order_Value__c = 250,
            RecordTypeId = orderRT.Id,
            Type__c = 'Field Order'
        );

        Test.startTest();

        // First run: manual rollup check
        VisitTaskOrderRollup.rollUp(
            [SELECT Id, Visit_Task__c FROM Order__c WHERE Visit_Task__c = :vt.Id]
        );

        // UPDATE SCENARIO — covers Trigger.old
        Order__c orderToUpdate = [
            SELECT Id, Total_Order_Value__c 
            FROM Order__c 
            WHERE Visit_Task__c = :vt.Id 
            LIMIT 1
        ];

        orderToUpdate.Total_Order_Value__c = 300;  // updated value
        update orderToUpdate;   // this triggers the update logic + Trigger.old path

        Test.stopTest();

        // Recalculate expected total = 300 + 250 = 550
        Visit_Task__c result = [
            SELECT Total_Order_Amount__c 
            FROM Visit_Task__c 
            WHERE Id = :vt.Id
        ];

        System.assertEquals(550, result.Total_Order_Amount__c, 'Update rollup failed');
    }
}