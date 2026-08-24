// Added by Hari - Cygnet API integration: authenticate, E-Invoice save/status, E-Way Bill by IRN, PDF export
public with sharing class CygnetApiService {
    private static final String AUTH_PATH = '/enriched/v0.1/authenticate/token';
    private static final String EINV_SAVE_PATH = '/enriched/v0.1/document/einvoiceCompliant/save';
    private static final String REFERENCE_STATUS_PATH = '/enriched/v0.1/reference/status';
    private static final String EWB_BY_IRN_SAVE_PATH = '/enriched/v0.1/document/ewaybillByIrnCompliant/save';
    private static final String EINV_EXPORT_PDF_PATH = '/enriched/v0.1/eInvoice/exportPdf';
    private static final String EWB_EXPORT_PDF_PATH = '/enriched/v0.1/ewaybill/exportPdf';
    // Added by hari (Under SS) - Increase max attempts so we can wait long enough
    // for Cygnet to finish asynchronous IRN generation without exhausting CPU.
    private static final Integer POLL_MAX_ATTEMPTS = 12;
    private static final Integer POLL_DELAY_MS = 2000;

    // Added by hari (Under SS) - Invoice record type: use Cygnet_Integration_Setting_Under_SS__c instead of Cygnet_Integration_Setting__c
    private static final String RECORDTYPE_SECONDARY_INVOICE_UNDER_SS_DEVNAME = 'Secondary_Invoice_Under_SS';

    // Added by Hari - Cached auth token per integration profile (Secondary vs Under SS)
    private static String cachedAuthTokenSecondary;
    private static String cachedAuthTokenUnderSs;
    // Added by Hari - Reuse auth token until expiry (per Cygnet: typically 6 hours)
    private static Datetime cachedAuthTokenSecondaryExpiresAt;
    private static Datetime cachedAuthTokenUnderSsExpiresAt;

    // Added by hari (Under SS) - One SOQL per transaction per Invoice Id for record-type resolution
    private static Map<Id, Boolean> invoiceIdToUseUnderSsSetting = new Map<Id, Boolean>();

    // Added by hari (Under SS) - Cache last E-Invoice save payload by referenceId so we can extract IRN directly when save response is already status=P.
    private static Map<String, Map<String, Object>> lastEinvSaveByReferenceId = new Map<String, Map<String, Object>>();

    private class IntegrationConfig {
        String baseUrl;
        String clientId;
        String clientSecret;
        String username;
        String password;
    }

    /**
     * Validation rule (UAT): allow integration for:
     * - Under Super Stockist users (Distributor / Under Super Stockist / has Super Stockist link), OR
     * - Superstockist users.
     *
     * Determination is based on the logged-in user's Account (portal-style):
     * Contact.Account (Experience) or User.AccountId (fallback).
     *
     * Note: Skipped during tests to avoid requiring portal user setup in unit tests.
     */
    private static void assertLoggedInUserEligibleForIntegration() {
        if (Test.isRunningTest()) {
            return;
        }

        User u;
        try {
            u = [
                SELECT Id, AccountId, ContactId,
                    Contact.AccountId,
                    Contact.Account.RecordType.DeveloperName,
                    Contact.Account.Distributor_Type__c,
                    Contact.Account.Super_Stockist_Name__c
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new CygnetApiException('Error validating user.');
        }

        String rtDevName;
        String distType;
        Id superStockistAccId;

        if (u != null && u.ContactId != null && u.Contact != null && u.Contact.AccountId != null) {
            rtDevName = (u.Contact.Account != null && u.Contact.Account.RecordType != null)
                ? u.Contact.Account.RecordType.DeveloperName
                : null;
            distType = u.Contact.Account != null ? u.Contact.Account.Distributor_Type__c : null;
            superStockistAccId = u.Contact.Account != null ? u.Contact.Account.Super_Stockist_Name__c : null;
        } else if (u != null && u.AccountId != null) {
            List<Account> accs = [
                SELECT RecordType.DeveloperName, Distributor_Type__c, Super_Stockist_Name__c
                FROM Account
                WHERE Id = :u.AccountId
                LIMIT 1
            ];
            if (!accs.isEmpty()) {
                rtDevName = accs[0].RecordType != null ? accs[0].RecordType.DeveloperName : null;
                distType = accs[0].Distributor_Type__c;
                superStockistAccId = accs[0].Super_Stockist_Name__c;
            }
        }

        String rt = String.isBlank(rtDevName) ? '' : rtDevName.trim().toLowerCase();
        Boolean isSuperStockistUser = rt.contains('superstockist') || rt.contains('super_stockist');
        Boolean isUnderSsUser =
            'distributor'.equalsIgnoreCase(rtDevName)
            && String.isNotBlank(distType)
            && 'Under Super Stockist'.equalsIgnoreCase(distType)
            && superStockistAccId != null;

        if (!(isUnderSsUser || isSuperStockistUser)) {
            throw new CygnetApiException('Error validating user.');
        }
    }

    // Added by hari (Under SS)
    private static Boolean useUnderSsIntegrationSetting(Id invoiceId) {
        if (invoiceId == null) {
            return false;
        }
        if (invoiceIdToUseUnderSsSetting.containsKey(invoiceId)) {
            return invoiceIdToUseUnderSsSetting.get(invoiceId);
        }
        List<Invoice__c> rows = [
            SELECT RecordType.DeveloperName FROM Invoice__c WHERE Id = :invoiceId LIMIT 1
        ];
        Boolean useUnder = false;
        if (!rows.isEmpty() && rows[0].RecordType != null
            && RECORDTYPE_SECONDARY_INVOICE_UNDER_SS_DEVNAME.equalsIgnoreCase(rows[0].RecordType.DeveloperName)) {
            useUnder = true;
        }
        invoiceIdToUseUnderSsSetting.put(invoiceId, useUnder);
        return useUnder;
    }

    // Added by Hari - Load hierarchy custom setting: Secondary Invoice vs Under SS by Invoice record type (invoiceId null = Secondary only)
    // Added by hari (Under SS)
    private static IntegrationConfig loadIntegrationConfig(String loggedInUserName, Id invoiceId) {
        assertLoggedInUserEligibleForIntegration();
        Boolean useUnderSs = useUnderSsIntegrationSetting(invoiceId);
        IntegrationConfig cfg = new IntegrationConfig();

        if (useUnderSs) {
            Cygnet_Integration_Setting_Under_SS__c s = Cygnet_Integration_Setting_Under_SS__c.getInstance(UserInfo.getUserId());
            if (s == null) s = Cygnet_Integration_Setting_Under_SS__c.getInstance();
            if (s == null) {
                throw new CygnetApiException('Validation failed: Cygnet Integration Setting (Under SS) not found.');
            }
            cfg.baseUrl = s.Base_Url__c;
            cfg.clientId = s.Client_Id__c;
            cfg.clientSecret = s.Client_Secret__c;
            cfg.username = s.Username__c;
            cfg.password = s.Password__c;
            return cfg;
        }

        Cygnet_Integration_Setting__c s = Cygnet_Integration_Setting__c.getInstance(UserInfo.getUserId());
        if (s == null) s = Cygnet_Integration_Setting__c.getInstance();
        if (s == null) {
            throw new CygnetApiException('Validation failed: Cygnet Integration Setting not found.');
        }
        cfg.baseUrl = s.Base_Url__c;
        cfg.clientId = s.Client_Id__c;
        cfg.clientSecret = s.Client_Secret__c;
        cfg.username = s.Username__c;
        cfg.password = s.Password__c;
        return cfg;
    }

    // Added by Hari - Authenticate and return auth token (used by all other APIs)
    public static String getAuthToken() {
        return getAuthToken(UserInfo.getUserName(), null);
    }

    public static String getAuthToken(String loggedInUserName) {
        return getAuthToken(loggedInUserName, null);
    }

    /**
     * After a fresh auth callout, defer hierarchy upsert until after any further HTTP callouts in the same
     * transaction (Salesforce does not allow callout after uncommitted DML).
     */
    private class PendingAuthTokenPersist {
        String token;
        Datetime expiresAt;
        PendingAuthTokenPersist(String t, Datetime e) {
            token = t;
            expiresAt = e;
        }
    }
    private static PendingAuthTokenPersist pendingAuthTokenSecondary;
    private static PendingAuthTokenPersist pendingAuthTokenUnderSs;

    private class AuthTokenPersistQueueable implements Queueable {
        private Boolean useUnderSs;
        private String token;
        private Datetime expiresAt;

        AuthTokenPersistQueueable(Boolean useUnder, String tok, Datetime exp) {
            useUnderSs = useUnder;
            token = tok;
            expiresAt = exp;
        }

        public void execute(QueueableContext ctx) {
            // Separate transaction avoids callout-after-DML and mixed-DML surprises in caller flows.
            persistTokenToSetting(useUnderSs, token, expiresAt);
        }
    }

    private static void recordPendingAuthTokenPersist(Boolean useUnderSs, String token, Datetime expiresAt) {
        if (String.isBlank(token) || expiresAt == null) {
            return;
        }
        PendingAuthTokenPersist p = new PendingAuthTokenPersist(token, expiresAt);
        if (useUnderSs) {
            pendingAuthTokenUnderSs = p;
        } else {
            pendingAuthTokenSecondary = p;
        }
    }

    private static void flushPendingAuthTokenPersistIfAny() {
        try {
            if (pendingAuthTokenSecondary != null) {
                PendingAuthTokenPersist p = pendingAuthTokenSecondary;
                pendingAuthTokenSecondary = null;
                System.enqueueJob(new AuthTokenPersistQueueable(false, p.token, p.expiresAt));
            }
            if (pendingAuthTokenUnderSs != null) {
                PendingAuthTokenPersist p = pendingAuthTokenUnderSs;
                pendingAuthTokenUnderSs = null;
                System.enqueueJob(new AuthTokenPersistQueueable(true, p.token, p.expiresAt));
            }
        } catch (Exception e) {
            // Never break integration due to cache persistence.
        }
    }

    private static void clearCachedToken(Boolean useUnderSs) {
        if (useUnderSs) {
            cachedAuthTokenUnderSs = null;
            cachedAuthTokenUnderSsExpiresAt = null;
        } else {
            cachedAuthTokenSecondary = null;
            cachedAuthTokenSecondaryExpiresAt = null;
        }
    }

    /**
     * HTTP 401/403 or known Cygnet auth error codes in body — avoid broad "AUTH" matches that cause unnecessary retries.
     */
    private static Boolean responseSuggestsInvalidAuthToken(HttpResponse res) {
        if (res == null) {
            return false;
        }
        Integer sc = res.getStatusCode();
        if (sc == 401 || sc == 403) {
            return true;
        }
        String b = res.getBody();
        if (String.isBlank(b)) {
            return false;
        }
        String u = b.toUpperCase();
        return u.contains('AUTH001') || u.contains('AUTH0');
    }

    /**
     * One Cygnet HTTP send; if auth looks invalid, clear memory cache, obtain a new token with forceRefresh (skips
     * hierarchy cache reload), then retry the same request once.
     */
    private static HttpResponse sendCygnetRequestWithOneAuthRetry(HttpRequest req, Id invoiceId, String currentToken) {
        req.setHeader('auth-token', currentToken);
        Http http = new Http();
        HttpResponse res = http.send(req);
        if (!responseSuggestsInvalidAuthToken(res)) {
            return res;
        }
        Boolean useUnder = useUnderSsIntegrationSetting(invoiceId);
        clearCachedToken(useUnder);
        String newTok = obtainAuthTokenDeferringHierarchyPersist(UserInfo.getUserName(), invoiceId, true);
        req.setHeader('auth-token', newTok);
        return http.send(req);
    }

    /** Delegates to three-arg overload with forceRefresh=false. */
    private static String obtainAuthTokenDeferringHierarchyPersist(String loggedInUserName, Id invoiceId) {
        return obtainAuthTokenDeferringHierarchyPersist(loggedInUserName, invoiceId, false);
    }

    /** Same as public getAuthToken but does not upsert hierarchy until {@link #flushPendingAuthTokenPersistIfAny()}. */
    private static String obtainAuthTokenDeferringHierarchyPersist(String loggedInUserName, Id invoiceId, Boolean forceRefresh) {
        Boolean useUnderSs = useUnderSsIntegrationSetting(invoiceId);
        if (!forceRefresh) {
            // Added by Hari - Reuse auth token until expiry (from hierarchy custom setting)
            String cached = getCachedTokenIfValid(useUnderSs);
            if (String.isNotBlank(cached)) {
                System.debug(LoggingLevel.DEBUG, 'Cygnet auth: cache hit (memory), useUnderSs=' + useUnderSs);
                return cached;
            }

            // Added by Hari - Reuse auth token until expiry: load persisted token if present
            loadCachedTokenFromSettingIfValid(useUnderSs);
            cached = getCachedTokenIfValid(useUnderSs);
            if (String.isNotBlank(cached)) {
                System.debug(LoggingLevel.DEBUG, 'Cygnet auth: cache hit (after settings load), useUnderSs=' + useUnderSs);
                return cached;
            }
        } else {
            // forceRefresh: must not reload stale token from hierarchy into static cache
            clearCachedToken(useUnderSs);
        }

        IntegrationConfig cfg = loadIntegrationConfig(loggedInUserName, invoiceId);
        String baseUrl = cfg.baseUrl != null ? cfg.baseUrl.replaceAll('/$', '') : '';
        String endpoint = baseUrl + AUTH_PATH;
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('client-id', cfg.clientId ?? '');
        req.setHeader('client-secret', cfg.clientSecret ?? '');
        req.setTimeout(120000);
        String body = Json.serialize(new Map<String, Object>{
            'forceRefresh' => forceRefresh,
            'username' => cfg.username ?? '',
            'password' => cfg.password ?? ''
        });
        req.setBody(body);
        Http http = new Http();
        HttpResponse res = http.send(req);
        if (res.getStatusCode() != 200) {
            throw new CygnetApiException('Cygnet authentication failed: ' + res.getStatus() + ' - ' + res.getBody());
        }
        Map<String, Object> json = parseResponseMap(res.getBody(), 'authentication');
        Object tok = json.get('token');
        if (tok == null) {
            throw new CygnetApiException('Cygnet authentication response did not contain token.');
        }
        String tokenStr = String.valueOf(tok);

        // Added by Hari - Reuse auth token until expiry: compute expiry from response
        Integer expiryMins = 360; // default 6 hours when not provided
        Object expiryObj = json.get('expiryTimeInMinutes');
        if (expiryObj == null) expiryObj = json.get('expiryMinutes');
        if (expiryObj != null) {
            try {
                expiryMins = Integer.valueOf(String.valueOf(expiryObj));
            } catch (Exception e) { }
        }
        if (expiryMins == null || expiryMins <= 0) expiryMins = 360;
        // guard against extreme values
        if (expiryMins > 24 * 60) expiryMins = 24 * 60;
        // Persisted expiry skew: treat token as expiring ~5 minutes before nominal API lifetime
        Integer storageMins = Math.max(1, expiryMins - 5);
        Datetime expiresAt = System.now().addMinutes(storageMins);

        cacheToken(useUnderSs, tokenStr, expiresAt);
        recordPendingAuthTokenPersist(useUnderSs, tokenStr, expiresAt);
        Integer tokLen = tokenStr != null ? tokenStr.length() : 0;
        System.debug(LoggingLevel.DEBUG, 'Cygnet auth: new token, len=' + tokLen + ', expiresAt=' + expiresAt + ', useUnderSs=' + useUnderSs + ', forceRefresh=' + forceRefresh);
        return tokenStr;
    }

    // Added by hari (Under SS) - Pass invoiceId so Under SS invoices use Cygnet_Integration_Setting_Under_SS__c
    public static String getAuthToken(String loggedInUserName, Id invoiceId) {
        try {
            return obtainAuthTokenDeferringHierarchyPersist(loggedInUserName, invoiceId, false);
        } finally {
            flushPendingAuthTokenPersistIfAny();
        }
    }

    // Added by Hari - Reuse auth token until expiry (per Cygnet)
    private static Boolean isTokenValid(String token, Datetime expiresAt) {
        if (String.isBlank(token) || expiresAt == null) return false;
        // Require several minutes of remaining validity before reuse (callouts + polling).
        return expiresAt.getTime() > (System.now().addMinutes(5)).getTime();
    }

    // Added by Hari - Reuse auth token until expiry (per Cygnet)
    private static String getCachedTokenIfValid(Boolean useUnderSs) {
        if (useUnderSs) {
            return isTokenValid(cachedAuthTokenUnderSs, cachedAuthTokenUnderSsExpiresAt) ? cachedAuthTokenUnderSs : null;
        }
        return isTokenValid(cachedAuthTokenSecondary, cachedAuthTokenSecondaryExpiresAt) ? cachedAuthTokenSecondary : null;
    }

    // Added by Hari - Reuse auth token until expiry (per Cygnet)
    private static void cacheToken(Boolean useUnderSs, String token, Datetime expiresAt) {
        if (useUnderSs) {
            cachedAuthTokenUnderSs = token;
            cachedAuthTokenUnderSsExpiresAt = expiresAt;
        } else {
            cachedAuthTokenSecondary = token;
            cachedAuthTokenSecondaryExpiresAt = expiresAt;
        }
    }

    // Added by Hari - Reuse auth token until expiry (per Cygnet)
    private static void loadCachedTokenFromSettingIfValid(Boolean useUnderSs) {
        try {
            if (useUnderSs) {
                Cygnet_Integration_Setting_Under_SS__c s = Cygnet_Integration_Setting_Under_SS__c.getInstance(UserInfo.getUserId());
                if (s == null) s = Cygnet_Integration_Setting_Under_SS__c.getInstance();
                if (s != null && isTokenValid(s.Auth_Token__c, s.Auth_Token_Expires_At__c)) {
                    cacheToken(true, s.Auth_Token__c, s.Auth_Token_Expires_At__c);
                }
            } else {
                Cygnet_Integration_Setting__c s = Cygnet_Integration_Setting__c.getInstance(UserInfo.getUserId());
                if (s == null) s = Cygnet_Integration_Setting__c.getInstance();
                if (s != null && isTokenValid(s.Auth_Token__c, s.Auth_Token_Expires_At__c)) {
                    cacheToken(false, s.Auth_Token__c, s.Auth_Token_Expires_At__c);
                }
            }
        } catch (Exception e) {
            // Do not break integration due to token cache read issues.
        }
    }

    // Added by Hari - Reuse auth token until expiry (per Cygnet)
    private static void persistTokenToSetting(Boolean useUnderSs, String token, Datetime expiresAt) {
        try {
            if (String.isBlank(token) || expiresAt == null) return;
            if (useUnderSs) {
                // Prefer user-level record, else org default.
                List<Cygnet_Integration_Setting_Under_SS__c> rows = [
                    SELECT Id, SetupOwnerId, Auth_Token__c, Auth_Token_Expires_At__c
                    FROM Cygnet_Integration_Setting_Under_SS__c
                    WHERE SetupOwnerId = :UserInfo.getUserId()
                    LIMIT 1
                ];
                Cygnet_Integration_Setting_Under_SS__c s = !rows.isEmpty()
                    ? rows[0]
                    : null;
                if (s == null) {
                    rows = [
                        SELECT Id, SetupOwnerId, Auth_Token__c, Auth_Token_Expires_At__c
                        FROM Cygnet_Integration_Setting_Under_SS__c
                        WHERE SetupOwnerId = :UserInfo.getOrganizationId()
                        LIMIT 1
                    ];
                    s = !rows.isEmpty()
                        ? rows[0]
                        : new Cygnet_Integration_Setting_Under_SS__c(SetupOwnerId = UserInfo.getOrganizationId());
                }
                s.Auth_Token__c = token;
                s.Auth_Token_Expires_At__c = expiresAt;
                upsert s;
            } else {
                List<Cygnet_Integration_Setting__c> rows = [
                    SELECT Id, SetupOwnerId, Auth_Token__c, Auth_Token_Expires_At__c
                    FROM Cygnet_Integration_Setting__c
                    WHERE SetupOwnerId = :UserInfo.getUserId()
                    LIMIT 1
                ];
                Cygnet_Integration_Setting__c s = !rows.isEmpty()
                    ? rows[0]
                    : null;
                if (s == null) {
                    rows = [
                        SELECT Id, SetupOwnerId, Auth_Token__c, Auth_Token_Expires_At__c
                        FROM Cygnet_Integration_Setting__c
                        WHERE SetupOwnerId = :UserInfo.getOrganizationId()
                        LIMIT 1
                    ];
                    s = !rows.isEmpty()
                        ? rows[0]
                        : new Cygnet_Integration_Setting__c(SetupOwnerId = UserInfo.getOrganizationId());
                }
                s.Auth_Token__c = token;
                s.Auth_Token_Expires_At__c = expiresAt;
                upsert s;
            }
        }
        
        //Testing Purpose -- Added by Hari
        catch (Exception e) {
            System.debug('TOKEN PERSIST ERROR: ' + e.getMessage());
            throw e;
        }
    }

    // Added by Hari - Save E-Invoice (NIC compliant); returns referenceId for status polling
    public static String saveEInvoice(String requestBody) {
        return saveEInvoice(requestBody, null);
    }

    // Added by hari (Under SS)
    public static String saveEInvoice(String requestBody, Id invoiceId) {
        try {
            String token = obtainAuthTokenDeferringHierarchyPersist(UserInfo.getUserName(), invoiceId);
            IntegrationConfig cfg = loadIntegrationConfig(UserInfo.getUserName(), invoiceId);
            String baseUrl = cfg.baseUrl != null ? cfg.baseUrl.replaceAll('/$', '') : '';
            HttpRequest req = new HttpRequest();
            req.setEndpoint(baseUrl + EINV_SAVE_PATH);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('auth-token', token);
            req.setBody(requestBody);
            req.setTimeout(120000);
            HttpResponse res = sendCygnetRequestWithOneAuthRetry(req, invoiceId, token);

            //added by hari - Cygnet may return Accepted (202) with referenceId for async processing
            if (res.getStatusCode() != 200 && res.getStatusCode() != 201 && res.getStatusCode() != 202) {
                throw new CygnetApiException('Cygnet E-Invoice save failed: ' + res.getStatus() + ' - ' + res.getBody());
            }
            Map<String, Object> json = parseResponseMap(res.getBody(), 'E-Invoice save');
            Object refId = json.get('referenceId');
            if (refId == null) {
                refId = json.get('reference_id');
            }
            if (refId == null) {
                throw new CygnetApiException('Cygnet E-Invoice save response did not contain referenceId.');
            }
            String refStr = String.valueOf(refId);
            // Added by hari (Under SS) - Remember full save response so pollUntilDone can use IRN from save when status=P.
            if (!String.isBlank(refStr)) {
                lastEinvSaveByReferenceId.put(refStr, json);
            }
            return refStr;
        } finally { }
    }

    // Added by Hari - Fetch status by referenceId; returns full response map (contains irn when success)
    public static Map<String, Object> getStatus(String referenceId) {
        return getStatus(referenceId, null);
    }

    // Added by hari (Under SS)
    public static Map<String, Object> getStatus(String referenceId, Id invoiceId) {
        try {
            String token = obtainAuthTokenDeferringHierarchyPersist(UserInfo.getUserName(), invoiceId);
            IntegrationConfig cfg = loadIntegrationConfig(UserInfo.getUserName(), invoiceId);
            String baseUrl = cfg.baseUrl != null ? cfg.baseUrl.replaceAll('/$', '') : '';
            String endpoint = baseUrl + REFERENCE_STATUS_PATH + '?referenceId=' + EncodingUtil.urlEncode(referenceId, 'UTF-8');
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(120000);
            HttpResponse res = sendCygnetRequestWithOneAuthRetry(req, invoiceId, token);
            //added by hari - status endpoint may return Accepted (202) while processing
            if (res.getStatusCode() != 200 && res.getStatusCode() != 202) {
                throw new CygnetApiException('Cygnet status check failed: ' + res.getStatus() + ' - ' + res.getBody());
            }
            String body = res.getBody();
            if (String.isBlank(body)) {
                throw new CygnetApiException('Cygnet status check returned empty body for referenceId: ' + referenceId);
            }
            Object parsed = JSON.deserializeUntyped(body);
            try {
                return (Map<String, Object>) parsed;
            } catch (Exception e) {
                throw new CygnetApiException('Cygnet status check returned unexpected payload: ' + body);
            }
        } finally { }
    }

    // Added by Hari - Poll status until done; TDD: status P=Processed, PE=Processed with errors, ER=Error, IP=In progress, YNS=Yet not started
    public static StatusResult pollUntilDone(String referenceId) {
        return pollUntilDone(referenceId, null);
    }

    // Added by hari (Under SS)
    public static StatusResult pollUntilDone(String referenceId, Id invoiceId) {
        Boolean underSs = useUnderSsIntegrationSetting(invoiceId);
        Integer maxAttempts = underSs ? Math.max(POLL_MAX_ATTEMPTS, 8) : POLL_MAX_ATTEMPTS;
        StatusResult result = new StatusResult();
        result.success = false;
        try {

        // Added by hari (Under SS) - If the E-Invoice save response itself was already status=P with IRN in dataReport.eInv, use that first.
        if (referenceId != null && lastEinvSaveByReferenceId.containsKey(referenceId)) {
            Map<String, Object> cachedStatus = lastEinvSaveByReferenceId.get(referenceId);
            if (cachedStatus != null) {
                String cachedSt = (String) cachedStatus.get('status');
                if (cachedSt == null) cachedSt = (String) cachedStatus.get('Status');
                if (cachedSt == 'P' || cachedSt == 'Success' || cachedSt == 'SUCCESS' || cachedSt == 'success') {
                    fillStatusResultFromResponse(result, cachedStatus);
                    if (invoiceId != null && String.isBlank(result.irn)) {
                        // Deep fallback: scan entire save payload for IRN and related fields.
                        result.irn = deepFindFirstString(cachedStatus, new Set<String>{
                            'irn', 'Irn', 'IRN',
                            'irnNumber', 'IrnNumber', 'IRNNumber',
                            'irn_no', 'Irn_No', 'IRN_No',
                            'irnNo', 'IrnNo', 'IRNNo'
                        });
                        if (String.isBlank(result.irn)) {
                            result.irn = deepFindFirstStringMatchingHex64(cachedStatus);
                        }
                        result.ackNo = String.isBlank(result.ackNo)
                            ? deepFindFirstString(cachedStatus, new Set<String>{ 'ackNo', 'AckNo', 'ackNumber', 'AckNumber' })
                            : result.ackNo;
                        result.signedInvoice = String.isBlank(result.signedInvoice)
                            ? deepFindFirstString(cachedStatus, new Set<String>{ 'signedInvoice' })
                            : result.signedInvoice;
                        result.signedQRCode = String.isBlank(result.signedQRCode)
                            ? deepFindFirstString(cachedStatus, new Set<String>{ 'signedQRCode' })
                            : result.signedQRCode;
                        result.qrCodeData = String.isBlank(result.qrCodeData)
                            ? deepFindFirstString(cachedStatus, new Set<String>{ 'qrCodeData', 'qrCode' })
                            : result.qrCodeData;
                    }
                    if (!String.isBlank(result.irn)) {
                        result.success = true;
                        return result;
                    }
                }
            }
        }

        for (Integer i = 0; i < maxAttempts; i++) {
            if (i > 0) {
                // Added by hari (Under SS) - Delay between polls.
                // Apex does not support System.sleep(Integer); we use a small CPU-limited busy wait instead.
                safeDelayBetweenPolls(POLL_DELAY_MS);
            }
            Map<String, Object> status = getStatus(referenceId, invoiceId);
            if (status == null) {
                result.errorMessage = 'Cygnet status check returned null response.';
                return result;
            }
            String st = (String) status.get('status');
            if (st == null) st = (String) status.get('Status');
            // TDD: P = Processed (success); also accept Success/SUCCESS
            if (st == 'P' || st == 'Success' || st == 'SUCCESS' || st == 'success') {
                fillStatusResultFromResponse(result, status);
                // Queueable: never treat "Processed" as success unless we extracted an IRN.
                // This prevents silent success when status payload is missing the expected keys.
                if (invoiceId != null && String.isBlank(result.irn)) {
                    // Deep fallback: Cygnet response shapes vary; scan the entire payload for IRN.
                    result.irn = deepFindFirstString(status, new Set<String>{
                        'irn', 'Irn', 'IRN',
                        'irnNumber', 'IrnNumber', 'IRNNumber',
                        'irn_no', 'Irn_No', 'IRN_No',
                        'irnNo', 'IrnNo', 'IRNNo'
                    });
                    // Value-based fallback: IRN is typically a 64-char hex string.
                    if (String.isBlank(result.irn)) {
                        result.irn = deepFindFirstStringMatchingHex64(status);
                    }

                    // Try also extracting the other fields (Ack/signatures/QR) for completeness.
                    result.ackNo = String.isBlank(result.ackNo)
                        ? deepFindFirstString(status, new Set<String>{ 'ackNo', 'AckNo', 'ackNumber', 'AckNumber' })
                        : result.ackNo;
                    result.signedInvoice = String.isBlank(result.signedInvoice)
                        ? deepFindFirstString(status, new Set<String>{ 'signedInvoice' })
                        : result.signedInvoice;
                    result.signedQRCode = String.isBlank(result.signedQRCode)
                        ? deepFindFirstString(status, new Set<String>{ 'signedQRCode' })
                        : result.signedQRCode;
                    result.qrCodeData = String.isBlank(result.qrCodeData)
                        ? deepFindFirstString(status, new Set<String>{ 'qrCodeData', 'qrCode' })
                        : result.qrCodeData;

                    if (String.isBlank(result.irn)) {
                        result.errorMessage = 'Cygnet returned Processed but IRN is missing in the status response.';
                        continue; // keep polling
                    }
                }

                result.success = true;
                return result;
            }
            // TDD: PE = Processed with errors, ER = Error
            if (st == 'PE' || st == 'ER' || st == 'Failed' || st == 'FAILED' || st == 'failure') {
                result.errorMessage = (String) status.get('message');
                if (result.errorMessage == null) result.errorMessage = (String) status.get('Message');
                if (String.isBlank(result.errorMessage)) result.errorMessage = JSON.serialize(status);
                return result;
            }
            // IP or YNS = still processing
        }
        if (String.isBlank(result.errorMessage)) {
            result.errorMessage = 'E-Invoice/E-Way Bill is still processing. Please try again in a minute.';
        }
        return result;
        } finally {
            // Important: persist token only AFTER all poll callouts complete,
            // otherwise the next poll callout can fail with "uncommitted work pending".
            flushPendingAuthTokenPersistIfAny();
        }
    }

    // Defensive JSON traversal to find a string value for any of the wanted keys (used only for Under SS IRN extraction).
    private static String deepFindFirstString(Object node, Set<String> wantedKeys) {
        if (node == null || wantedKeys == null || wantedKeys.isEmpty()) return null;

        // Avoid instanceof Map/List in this Apex org; just scan the serialized JSON for the first match.
        String json = JSON.serialize(node);
        if (String.isBlank(json)) return null;

        for (String key : wantedKeys) {
            if (String.isBlank(key)) continue;
            // Works for JSON string values: "key":"value"
            Pattern p = Pattern.compile('"' + key + '"\\s*:\\s*"([^"]+)"');
            Matcher m = p.matcher(json);
            if (m.find()) {
                String v = m.group(1);
                if (!String.isBlank(v)) return v;
            }
        }

        return null;
    }

    // Traverse the whole response and return the first string that looks like an IRN (64-char hex).
    private static String deepFindFirstStringMatchingHex64(Object node) {
        if (node == null) return null;

        // Regex against serialized JSON so we don't depend on instanceof Map/List support.
        String json = JSON.serialize(node);
        if (String.isBlank(json)) return null;

        // IRN is expected to be a 64-char hex string.
        Pattern p = Pattern.compile('[0-9a-fA-F]{64}');
        Matcher m = p.matcher(json);
        if (m.find()) {
            String irn = m.group(0);
            return String.isBlank(irn) ? null : irn;
        }

        return null;
    }

    // Cygnet E-Way Bill / GenerateByIrn status may return pin-pin distance on nested maps or dataReport[0].
    private static Decimal parseDistanceObject(Object distObj) {
        if (distObj == null) return null;
        try {
            if (distObj instanceof Decimal) return (Decimal) distObj;
            if (distObj instanceof Integer) return Decimal.valueOf((Integer) distObj);
            if (distObj instanceof Long) return Decimal.valueOf((Long) distObj);
            if (distObj instanceof String) {
                String s = ((String) distObj).trim();
                if (String.isBlank(s)) return null;
                return Decimal.valueOf(s);
            }
            return Decimal.valueOf(String.valueOf(distObj));
        } catch (Exception e) {
            return null;
        }
    }

    /** When allowOverride is false, keeps first non-null distance; when true, sets from map if key present (dataReport[0] wins over nested eawb). */
    private static void mergeDistanceFromMap(StatusResult result, Map<String, Object> m, Boolean allowOverride) {
        if (result == null || m == null) return;
        Object distObj = m.get('distance');
        if (distObj == null) distObj = m.get('Distance');
        if (distObj == null) return;
        if (!allowOverride && result.distanceKm != null) return;
        Decimal d = parseDistanceObject(distObj);
        if (d != null && d > 0) result.distanceKm = d;
    }

    // Added by Hari - TDD §7: when status=P, IRN/ack/QR come from dataReport[0].eInv; also support top-level
    private static void fillStatusResultFromResponse(StatusResult result, Map<String, Object> status) {
        Map<String, Object> eInv = null;
        Map<String, Object> firstReportMap = null;
        List<Object> dataReport = (List<Object>) status.get('dataReport');
        if (dataReport != null && !dataReport.isEmpty()) {
            Object first = dataReport[0];
            // Avoid instanceof Map/List checks in this Apex org; use safe casting.
            try {
                firstReportMap = (Map<String, Object>) first;
                Object eInvObj = firstReportMap.get('eInv');
                if (eInvObj != null) eInv = (Map<String, Object>) eInvObj;
            } catch (Exception ex) { }
        }
        if (eInv != null) {
            result.ackNo = (String) eInv.get('ackNumber');
            if (result.ackNo == null) result.ackNo = (String) eInv.get('ackNo');
            result.ackDate = (String) eInv.get('ackDate');
            if (result.ackDate == null) result.ackDate = (String) eInv.get('ackDt');
            result.irn = (String) eInv.get('irn');
            if (result.irn == null) result.irn = (String) eInv.get('Irn');
            result.signedInvoice = (String) eInv.get('signedInvoice');
            result.signedQRCode = (String) eInv.get('signedQRCode');
            result.qrCodeData = (String) eInv.get('qrCodeData');
            if (result.qrCodeData == null) result.qrCodeData = (String) eInv.get('qrCode');
            result.ewbNo = (String) eInv.get('ewayBillNo');
            if (result.ewbNo == null) result.ewbNo = (String) eInv.get('ewaybillNo');
            result.ewbGeneratedDate = (String) eInv.get('ewayBillDate');
            result.ewbValidUpto = (String) eInv.get('validUpto');

            // Added by Hari - Some Cygnet responses return EWB under nested eInv.eawb (as seen in Postman)
            Object eawbObj = eInv.get('eawb');
            if (eawbObj != null) {
                Map<String, Object> eawb;
                try {
                    eawb = (Map<String, Object>) eawbObj;
                } catch (Exception ex) {
                    eawb = null;
                }
                if (eawb != null) {
                if (result.ewbNo == null) {
                    // Common keys seen in responses
                    Object ewbNumObj = eawb.get('ewayBillNumber');
                    if (ewbNumObj == null) ewbNumObj = eawb.get('ewayBillNo');
                    if (ewbNumObj == null) ewbNumObj = eawb.get('ewaybillNo');
                    if (ewbNumObj != null) result.ewbNo = String.valueOf(ewbNumObj);
                }
                if (result.ewbGeneratedDate == null) {
                    Object genObj = eawb.get('generatedDate');
                    if (genObj == null) genObj = eawb.get('ewayBillDate');
                    if (genObj != null) result.ewbGeneratedDate = String.valueOf(genObj);
                }
                if (result.ewbValidUpto == null) {
                    Object validObj = eawb.get('validUpto');
                    if (validObj != null) result.ewbValidUpto = String.valueOf(validObj);
                }
                mergeDistanceFromMap(result, eawb, false);
            }
            }
        }

        // Added by Hari - EWB GenerateByIrn success often returns fields directly under dataReport[0]
        if (firstReportMap != null) {
            if (result.irn == null) {
                Object irnObj = firstReportMap.get('irn');
                if (irnObj == null) irnObj = firstReportMap.get('Irn');
                if (irnObj != null) result.irn = String.valueOf(irnObj);
            }
            if (result.ewbNo == null) {
                Object ewbNumObj = firstReportMap.get('ewayBillNumber');
                if (ewbNumObj == null) ewbNumObj = firstReportMap.get('ewayBillNo');
                if (ewbNumObj == null) ewbNumObj = firstReportMap.get('ewaybillNo');
                if (ewbNumObj != null) result.ewbNo = String.valueOf(ewbNumObj);
            }
            if (result.ewbGeneratedDate == null) {
                Object genObj = firstReportMap.get('generatedDate');
                if (genObj == null) genObj = firstReportMap.get('ewayBillDate');
                if (genObj != null) result.ewbGeneratedDate = String.valueOf(genObj);
            }
            if (result.ewbValidUpto == null) {
                Object validObj = firstReportMap.get('validUpto');
                if (validObj != null) result.ewbValidUpto = String.valueOf(validObj);
            }
            mergeDistanceFromMap(result, firstReportMap, true);
        }

        if (result.irn == null) result.irn = (String) status.get('irn');
        if (result.irn == null) result.irn = (String) status.get('Irn');
        if (result.ewbNo == null) result.ewbNo = (String) status.get('ewayBillNo');
        if (result.ewbNo == null) result.ewbNo = (String) status.get('ewaybillNo');
        if (result.ackNo == null) result.ackNo = (String) status.get('ackNo');
        if (result.ackNo == null) result.ackNo = (String) status.get('AckNo');
        if (result.ackDate == null) result.ackDate = (String) status.get('ackDt');
        if (result.ackDate == null) result.ackDate = (String) status.get('AckDt');
        if (result.signedInvoice == null) result.signedInvoice = (String) status.get('signedInvoice');
        if (result.signedQRCode == null) result.signedQRCode = (String) status.get('signedQRCode');
        if (result.qrCodeData == null) result.qrCodeData = (String) status.get('qrCodeData');
        if (result.ewbGeneratedDate == null) result.ewbGeneratedDate = (String) status.get('ewayBillDate');
        if (result.ewbValidUpto == null) result.ewbValidUpto = (String) status.get('validUpto');

        // Added by Hari - Also support nested eawb at top-level (defensive)
        if (result.ewbNo == null || result.ewbGeneratedDate == null || result.ewbValidUpto == null) {
            Object eawbObj2 = status.get('eawb');
            if (eawbObj2 != null) {
                Map<String, Object> eawb2;
                try {
                    eawb2 = (Map<String, Object>) eawbObj2;
                } catch (Exception ex2) {
                    eawb2 = null;
                }
                if (eawb2 != null) {
                if (result.ewbNo == null) {
                    Object ewbNumObj = eawb2.get('ewayBillNumber');
                    if (ewbNumObj == null) ewbNumObj = eawb2.get('ewayBillNo');
                    if (ewbNumObj == null) ewbNumObj = eawb2.get('ewaybillNo');
                    if (ewbNumObj != null) result.ewbNo = String.valueOf(ewbNumObj);
                }
                if (result.ewbGeneratedDate == null) {
                    Object genObj = eawb2.get('generatedDate');
                    if (genObj == null) genObj = eawb2.get('ewayBillDate');
                    if (genObj != null) result.ewbGeneratedDate = String.valueOf(genObj);
                }
                if (result.ewbValidUpto == null) {
                    Object validObj = eawb2.get('validUpto');
                    if (validObj != null) result.ewbValidUpto = String.valueOf(validObj);
                }
                mergeDistanceFromMap(result, eawb2, false);
                }
            }
        }
    }

    // Added by Hari - Save E-Way Bill by IRN (PartBDtls payload)
    public static String saveEwayBillByIrn(String requestBody) {
        return saveEwayBillByIrn(requestBody, null);
    }

    // Added by hari (Under SS)
    public static String saveEwayBillByIrn(String requestBody, Id invoiceId) {
        try {
            String token = obtainAuthTokenDeferringHierarchyPersist(UserInfo.getUserName(), invoiceId);
            IntegrationConfig cfg = loadIntegrationConfig(UserInfo.getUserName(), invoiceId);
            String baseUrl = cfg.baseUrl != null ? cfg.baseUrl.replaceAll('/$', '') : '';
            HttpRequest req = new HttpRequest();
            req.setEndpoint(baseUrl + EWB_BY_IRN_SAVE_PATH);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('auth-token', token);
            req.setBody(requestBody);
            req.setTimeout(120000);
            HttpResponse res = sendCygnetRequestWithOneAuthRetry(req, invoiceId, token);
            //added by hari - Cygnet may return Accepted (202) with referenceId for async processing
            if (res.getStatusCode() != 200 && res.getStatusCode() != 201 && res.getStatusCode() != 202) {
                throw new CygnetApiException('Cygnet E-Way Bill save failed: ' + res.getStatus() + ' - ' + res.getBody());
            }
            Map<String, Object> json = parseResponseMap(res.getBody(), 'E-Way Bill save');
            Object refId = json.get('referenceId');
            if (refId == null) refId = json.get('reference_id');
            if (refId == null) {
                throw new CygnetApiException('Cygnet E-Way Bill save response did not contain referenceId.');
            }
            return String.valueOf(refId);
        } finally {
            flushPendingAuthTokenPersistIfAny();
        }
    }

    // Added by Hari - Defensive JSON parsing to avoid null-pointer on malformed/empty payloads
    private static Map<String, Object> parseResponseMap(String body, String context) {
        if (String.isBlank(body)) {
            throw new CygnetApiException('Cygnet ' + context + ' response is empty.');
        }
        Object parsed = JSON.deserializeUntyped(body);
        try {
            return (Map<String, Object>) parsed;
        } catch (Exception e) {
            throw new CygnetApiException('Cygnet ' + context + ' response is invalid: ' + body);
        }
    }

    // Added by Hari - Export E-Invoice PDF; request body is JSON with criterias array; returns PDF as base64
    public static String exportEInvoicePdf(String requestBody) {
        return exportEInvoicePdf(requestBody, null);
    }

    // Added by hari (Under SS)
    public static String exportEInvoicePdf(String requestBody, Id invoiceId) {
        try {
            String token = obtainAuthTokenDeferringHierarchyPersist(UserInfo.getUserName(), invoiceId);
            IntegrationConfig cfg = loadIntegrationConfig(UserInfo.getUserName(), invoiceId);
            String baseUrl = cfg.baseUrl != null ? cfg.baseUrl.replaceAll('/$', '') : '';
            HttpRequest req = new HttpRequest();
            req.setEndpoint(baseUrl + EINV_EXPORT_PDF_PATH);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('auth-token', token);
            req.setBody(requestBody);
            req.setTimeout(120000);
            HttpResponse res = sendCygnetRequestWithOneAuthRetry(req, invoiceId, token);
            if (res.getStatusCode() != 200) {
                throw new CygnetApiException('Cygnet E-Invoice PDF export failed: ' + res.getStatus() + ' - ' + res.getBody());
            }
            return EncodingUtil.base64Encode(res.getBodyAsBlob());
        } finally {
            flushPendingAuthTokenPersistIfAny();
        }
    }

    // Added by Hari - Export E-Way Bill PDF; returns PDF as base64
    public static String exportEwayBillPdf(String requestBody) {
        return exportEwayBillPdf(requestBody, null);
    }

    // Added by hari (Under SS)
    public static String exportEwayBillPdf(String requestBody, Id invoiceId) {
        try {
            String token = obtainAuthTokenDeferringHierarchyPersist(UserInfo.getUserName(), invoiceId);
            IntegrationConfig cfg = loadIntegrationConfig(UserInfo.getUserName(), invoiceId);
            String baseUrl = cfg.baseUrl != null ? cfg.baseUrl.replaceAll('/$', '') : '';
            HttpRequest req = new HttpRequest();
            req.setEndpoint(baseUrl + EWB_EXPORT_PDF_PATH);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('auth-token', token);
            req.setBody(requestBody);
            req.setTimeout(120000);
            HttpResponse res = sendCygnetRequestWithOneAuthRetry(req, invoiceId, token);
            if (res.getStatusCode() != 200) {
                throw new CygnetApiException('Cygnet E-Way Bill PDF export failed: ' + res.getStatus() + ' - ' + res.getBody());
            }
            return EncodingUtil.base64Encode(res.getBodyAsBlob());
        } finally {
            flushPendingAuthTokenPersistIfAny();
        }
    }

    // Added by Hari - Result of status poll: IRN, EWB, and E-Invoice/EWB response fields per requirement
    public class StatusResult {
        public Boolean success;
        public String irn;
        public String ewbNo;
        public String errorMessage;
        public String ackNo;
        public String ackDate;
        public String signedInvoice;
        public String signedQRCode;
        public String qrCodeData;
        public String ewbGeneratedDate;
        public String ewbValidUpto;
        /** Pin-pin or API-computed distance (km) from status dataReport / eawb when present. */
        public Decimal distanceKm;
    }

    // Added by hari (Under SS) - Apex has no System.sleep; use wall-clock wait between polls.
    // Must match POLL_DELAY_MS (~2s) so Cygnet async IRN has time before maxAttempts exhausts (250ms cap caused false "still processing").
    private static void safeDelayBetweenPolls(Integer delayMs) {
        if (delayMs == null || delayMs <= 0) return;
        Integer waitMs = Math.min(delayMs, 3000);
        Long startMs = DateTime.now().getTime();
        Long targetMs = startMs + waitMs;
        while (DateTime.now().getTime() < targetMs) {
            if (Limits.getCpuTime() > 55000) break;
        }
    }

    public class CygnetApiException extends Exception {}
}