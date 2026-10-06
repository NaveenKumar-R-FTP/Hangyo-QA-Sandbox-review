/**
 * @description Resolves allowed Salesforce User Ids for the Tally pull API
 *              from Tally_Allowed_User__mdt.
 *              Uses getAll() instead of SOQL because Client Credentials /
 *              Integration User contexts reject SOQL against this CMDT type.
 */
public with sharing class TallyAllowedUserService {
    /** Picklist API value for active records on Is_Active__c. */
    private static final String ACTIVE_VALUE = 'True';

    /** Test hook to exercise the empty-metadata response branch. */
    @TestVisible
    private static Boolean testForceEmptyMetadata = false;

    /** Test hook supplying in-memory CMDT rows for deterministic coverage. */
    @TestVisible
    private static Map<String, Tally_Allowed_User__mdt> testMetadataOverride;

    /**
     * @description Backward-compatible overload — no customer key, so this
     *              only matches rows using the Integration_User_Id__c
     *              (dedicated Run-As User) path.
     * @return Set of active allowed User Ids (never null)
     */
    public static Set<Id> getAllowedUserIds() {
        return getAllowedUserIds(null);
    }

    /**
     * @description Returns User Ids from active Tally_Allowed_User__mdt records.
     *              When customerApiKey is provided (non-blank), matches ONLY
     *              records whose Customer_Api_Key__c equals it exactly — this
     *              is the header-based path for customers sharing the common
     *              Connected App/credential, needing no dedicated Run-As User
     *              or license of their own.
     *              When customerApiKey is blank, falls back to the original
     *              Integration_User_Id__c == currently-running-user check —
     *              unchanged behavior for existing customers (e.g. Prathiksha
     *              Enterprise) who each have their own dedicated Run-As User.
     * @param customerApiKey Optional secret from the X-Tally-Customer-Key header
     * @return Set of active allowed User Ids (never null)
     */
    public static Set<Id> getAllowedUserIds(String customerApiKey) {
        Set<Id> allowedUserIds = new Set<Id>();

        Boolean useApiKeyPath = String.isNotBlank(customerApiKey);
        String trimmedApiKey = useApiKeyPath ? customerApiKey.trim() : null;
        Id runningUserId = UserInfo.getUserId();

        Map<String, Tally_Allowed_User__mdt> allRecords = resolveMetadataRecords();
        if (allRecords == null || allRecords.isEmpty()) {
            System.debug(LoggingLevel.INFO, 'TallyAllowedUserService: no CMDT records found.');
            return allowedUserIds;
        }

        for (Tally_Allowed_User__mdt allowedUser : allRecords.values()) {
            if (allowedUser == null) {
                continue;
            }

            // Null-safe picklist check (handles null / casing differences like "true").
            if (!ACTIVE_VALUE.equalsIgnoreCase(allowedUser.Is_Active__c)) {
                continue;
            }

            if (useApiKeyPath) {
                // Header-based path: match ONLY on the customer's own secret key.
                String rowApiKey = allowedUser.Customer_Api_Key__c == null
                    ? null
                    : allowedUser.Customer_Api_Key__c.trim();
                if (String.isBlank(rowApiKey) || rowApiKey != trimmedApiKey) {
                    continue;
                }
            } else {
                // Original path: dedicated Run-As User per customer's own
                // Connected App — this is the per-customer isolation check.
                String integrationUserIdRaw = allowedUser.Integration_User_Id__c == null
                    ? null
                    : allowedUser.Integration_User_Id__c.trim();
                Id parsedIntegrationUserId = String.isBlank(integrationUserIdRaw)
                    ? null
                    : tryParseUserId(integrationUserIdRaw);
                if (parsedIntegrationUserId == null || parsedIntegrationUserId != runningUserId) {
                    continue;
                }
            }

            String userId = allowedUser.User_Id__c == null
                ? null
                : allowedUser.User_Id__c.trim();

            if (String.isBlank(userId)) {
                continue;
            }

            Id parsedUserId = tryParseUserId(userId);
            if (parsedUserId != null) 
            {
                allowedUserIds.add(parsedUserId);
            }
        }

        System.debug(
            LoggingLevel.INFO,
            'TallyAllowedUserService: allowed user count = ' + allowedUserIds.size()
        );
        return allowedUserIds;
    }

    @TestVisible
    private static Map<String, Tally_Allowed_User__mdt> resolveMetadataRecords() {
        if (Test.isRunningTest() && testMetadataOverride != null) {
            return testMetadataOverride;
        }
        if (Test.isRunningTest() && testForceEmptyMetadata) {
            return new Map<String, Tally_Allowed_User__mdt>();
        }
        return Tally_Allowed_User__mdt.getAll();
    }

    /**
     * @description Safely converts text to a Salesforce Id.
     * @param userIdValue Candidate User Id from CMDT
     * @return Parsed Id, or null when invalid
     */
    private static Id tryParseUserId(String userIdValue) {
        try {
            return Id.valueOf(userIdValue.trim());
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                'TallyAllowedUserService: skipping invalid User_Id__c value: ' + userIdValue
            );
            return null;
        }
    }
}