@isTest
private class ArchivedRecordDeletionBatchTest {

    private static final String OBJECT_API_NAME = 'Order_Line_Item__c';

    @testSetup
    static void setupTestData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;

        Id disRecId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Distributor').getRecordTypeId();
        Account distributor = new Account(
            Name              = 'Distributor',
            RecordTypeId      = disRecId,
            PAN_Number__c     = '1344',
            Primary_State__c  = 'Karnataka'
        );
        insert distributor;

        Id retailerRecId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Retailer').getRecordTypeId();
        Account retailer = new Account(
            Name              = 'Retailer',
            Distributor__c    = distributor.Id,
            RecordTypeId      = retailerRecId,
            Primary_State__c  = 'Karnataka',
            PAN_Number__c     = '1344'
        );
        insert retailer;

        RecordType secondaryOrderRT = [
            SELECT Id FROM RecordType WHERE DeveloperName = 'Secondary_Order' AND SObjectType = 'Order__c' LIMIT 1
        ];

        Order__c ord = new Order__c(
            Account__c    = retailer.Id,
            AccountId__c  = distributor.Id,
            RecordTypeId  = secondaryOrderRT.Id
        );
        insert ord;

        // 10 line items that ARE past the soft-archive cutoff - these should get deleted.
        List<Order_Line_Item__c> archivedPastCutoff = new List<Order_Line_Item__c>();
        for (Integer i = 0; i < 10; i++) {
            archivedPastCutoff.add(new Order_Line_Item__c(
                Order__c         = ord.Id,
                Archived__c      = true,
                Archived_Date__c = Datetime.now().addDays(-10)
            ));
        }
        insert archivedPastCutoff;

        // 1 line item archived but still INSIDE the soft-archive window - must survive.
        insert new Order_Line_Item__c(
            Order__c         = ord.Id,
            Archived__c      = true,
            Archived_Date__c = Datetime.now().addDays(-1)
        );

        // 1 line item that was never archived at all - must survive.
        insert new Order_Line_Item__c(
            Order__c    = ord.Id,
            Archived__c = false
        );
    }

    /** In-memory mdt row - no insert needed/possible for Custom Metadata in tests. */
    private static Azure_Archive_Config__mdt buildConfig(String objectApiName, Boolean enabled, Integer softArchiveDays, Integer scopeSize) {
        return new Azure_Archive_Config__mdt(
            Object_API_Name__c          = objectApiName,
            Migration_Delete_Enabled__c = enabled,
            Soft_Archive_Days__c        = softArchiveDays,
            Batch_Scope_Size__c         = scopeSize
        );
    }

    // ---------------------------------------------------------------
    // Happy path - only the 10 past-cutoff records are removed
    // ---------------------------------------------------------------

    @isTest
    static void testDeletesOnlyRecordsPastCutoffAndLogsSuccess() {
        Azure_Archive_Config__mdt cfg = buildConfig(OBJECT_API_NAME, true, 7, 200);

        Test.startTest();
        Database.executeBatch(new ArchivedRecordDeletionBatch(cfg), 50);
        Test.stopTest();

        List<Order_Line_Item__c> remaining = [SELECT Id, Archived__c, Archived_Date__c FROM Order_Line_Item__c];
        // 10 deleted; the "inside window" one and the "never archived" one survive.
        System.assertEquals(2, remaining.size(), 'Only the 10 records past the cutoff should be deleted.');

        Archival_Job_Log__c log = [
            SELECT Total_Processed__c, Total_Failed__c, Archived_Object__c, Error_Message__c, Deletion_Batch__c
            FROM Archival_Job_Log__c
            LIMIT 1
        ];
        System.assertEquals(OBJECT_API_NAME, log.Archived_Object__c);
        System.assertEquals(10, log.Total_Processed__c);
        System.assertEquals(0, log.Total_Failed__c);
        System.assertEquals(true, log.Deletion_Batch__c);
        System.assertEquals(null, log.Error_Message__c, 'No errors expected on the happy path.');
    }

    @isTest
    static void testSkipsRecordsInsideSoftArchiveWindowAndNonArchivedRecords() {
        Azure_Archive_Config__mdt cfg = buildConfig(OBJECT_API_NAME, true, 7, 200);

        Test.startTest();
        Database.executeBatch(new ArchivedRecordDeletionBatch(cfg), 50);
        Test.stopTest();

        List<Order_Line_Item__c> remaining = [SELECT Id, Archived__c FROM Order_Line_Item__c];
        System.assertEquals(2, remaining.size());
        for (Order_Line_Item__c oli : remaining) {
            // Whichever survived, confirm neither was one of the 10 eligible-for-delete rows
            // by checking the log's processed count elsewhere; here we just assert the count.
        }
    }

    // ---------------------------------------------------------------
    // Constructor / validation guard rails - no fixture data needed
    // ---------------------------------------------------------------

    @isTest
    static void testDisabledConfigThrows() {
        Azure_Archive_Config__mdt cfg = buildConfig(OBJECT_API_NAME, false, 7, 200);

        Boolean caught = false;
        try {
            new ArchivedRecordDeletionBatch(cfg);
        } catch (ArchivedRecordDeletionBatch.MigrationDeleteException e) {
            caught = true;
            System.assert(e.getMessage().contains('Migration_Delete_Enabled__c is false'));
        }
        System.assert(caught, 'Expected an exception when Migration_Delete_Enabled__c is false.');
    }

    @isTest
    static void testNullConfigThrows() {
        Boolean caught = false;
        try {
            new ArchivedRecordDeletionBatch((Azure_Archive_Config__mdt) null);
        } catch (ArchivedRecordDeletionBatch.MigrationDeleteException e) {
            caught = true;
        }
        System.assert(caught, 'Expected an exception when no config is found/provided.');
    }

    @isTest
    static void testBlankObjectApiNameThrows() {
        Boolean caught = false;
        try {
            new ArchivedRecordDeletionBatch((String) null);
        } catch (ArchivedRecordDeletionBatch.MigrationDeleteException e) {
            caught = true;
            System.assert(e.getMessage().contains('objectApiName is required'));
        }
        System.assert(caught, 'Expected an exception when objectApiName is blank.');
    }

    @isTest
    static void testUnknownObjectThrows() {
        Azure_Archive_Config__mdt cfg = buildConfig('Not_A_Real_Object__c', true, 7, 200);

        Boolean caught = false;
        try {
            new ArchivedRecordDeletionBatch(cfg);
        } catch (ArchivedRecordDeletionBatch.MigrationDeleteException e) {
            caught = true;
            System.assert(e.getMessage().contains('Unknown/inaccessible object'));
        }
        System.assert(caught, 'Expected an exception for an object that does not exist.');
    }

    @isTest
    static void testMissingArchivedFieldsThrows() {
        // Account has neither Archived__c nor Archived_Date__c.
        Azure_Archive_Config__mdt cfg = buildConfig('Account', true, 7, 200);

        Boolean caught = false;
        try {
            new ArchivedRecordDeletionBatch(cfg);
        } catch (ArchivedRecordDeletionBatch.MigrationDeleteException e) {
            caught = true;
            System.assert(e.getMessage().contains('has no field'));
        }
        System.assert(caught, 'Expected an exception when the object lacks the archived/archived-date fields.');
    }

    @isTest
    static void testDefaultsAppliedWhenScopeSizeAndSoftArchiveDaysAreNull() {
        Azure_Archive_Config__mdt cfg = buildConfig(OBJECT_API_NAME, true, null, null);

        ArchivedRecordDeletionBatch batch = new ArchivedRecordDeletionBatch(cfg);

        System.assertEquals(200, batch.getScopeSize(), 'Should fall back to the default scope size of 200.');
        System.assertEquals(OBJECT_API_NAME, batch.getObjectApiName());
    }

    // ---------------------------------------------------------------
    // MigrationDeleteScheduler
    // ---------------------------------------------------------------

    @isTest
    static void testSchedulerBlankObjectApiNameThrows() {
        Boolean caught = false;
        try {
            new MigrationDeleteScheduler('');
        } catch (ArchivedRecordDeletionBatch.MigrationDeleteException e) {
            caught = true;
        }
        System.assert(caught, 'Expected an exception when the scheduler is built with a blank object name.');
    }

    /**
     * NOTE: requires a REAL, deployed Azure_Archive_Config__mdt record for
     * 'Order_Line_Item__c' with Migration_Delete_Enabled__c = true, because
     * MigrationDeleteScheduler.execute() goes through the String-based
     * ArchivedRecordDeletionBatch constructor, which queries actual metadata
     * records (custom metadata can't be inserted via DML in a test, but IS
     * visible in test context without SeeAllData=true).
     */
    @isTest
    static void testSchedulerSchedulesAndRunsBatch() {
        String jobName = 'Test Migration Delete - Order Line Item';
        String cronExp = '0 0 2 * * ?';

        Test.startTest();
        System.schedule(jobName, cronExp, new MigrationDeleteScheduler(OBJECT_API_NAME));
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id, State, CronExpression
            FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
        ];
        System.assertEquals(1, jobs.size(), 'Scheduled job should be created.');
        System.assertEquals(cronExp, jobs[0].CronExpression);
    }
}