import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

import getDashboardAccess from '@salesforce/apex/UserTrackingController.getDashboardAccess';
import getUsers from '@salesforce/apex/UserTrackingController.getUsers';
import getDashboardData from '@salesforce/apex/UserTrackingController.getDashboardData';
import getUserTrackingMapEmbedUrl from '@salesforce/apex/UserTrackingController.getUserTrackingMapEmbedUrl';
import getUserTrackingMapIframePostMessageOrigin from '@salesforce/apex/UserTrackingController.getUserTrackingMapIframePostMessageOrigin';
import getGoogleMapsJavaScriptApiKey from '@salesforce/apex/UserTrackingController.getGoogleMapsJavaScriptApiKey';

const EMPTY_SUMMARY = Object.freeze({
    userId: null,
    userName: null,
    totalProductiveOutlets: 0,
    totalNonProductiveOutlets: 0,
    totalVisitedOutlets: 0,
    totalOrderValue: 0,
    attendanceCount: 0,
    eodCount: 0,
    newOutletAdded: 0,
    rawRowCount: 0
});

/** Default map view when there are no coordinates (Bangalore — adjust if needed). */
const DEFAULT_MAP_CENTER = Object.freeze({ lat: 12.9716, lng: 77.5946 });
const DEFAULT_MAP_ZOOM = 11;

/** Matches UserTrackingController.assertDashboardAccessAllowed AuraHandledException text. */
const ACCESS_DENIED_MESSAGE =
    'You do not have access to the User Tracking Dashboard.';
const ACCESS_DENIED_EMPLOYEE_ROLE_BLANK_MESSAGE =
    'Access Denied: Employee role for the logged in user is not defined.';
const ACCESS_DENIED_REDIRECT_DELAY_MS = 350;

/**
 * Explicit Salesforce hostname suffixes for postMessage origin checks.
 * Never use origin.includes('.force.com') — substring matching on the full origin
 * string accepts spoofed hosts such as https://fake-force.com.
 */
const HANGYO_TRUSTED_SF_HOST_SUFFIXES = Object.freeze([
    '.vf.force.com',
    '.sandbox.vf.force.com',
    '.visualforce.com',
    '.lightning.force.com',
    '.my.salesforce.com',
    '.sandbox.my.salesforce.com',
    '.cloudforce.com'
]);

const HANGYO_TRUSTED_VF_HOST_SUFFIXES = Object.freeze([
    '.vf.force.com',
    '.sandbox.vf.force.com',
    '.visualforce.com'
]);

function hangyoHostnameMatchesSuffixList(hostname, suffixList) {
    if (!hostname || typeof hostname !== 'string') {
        return false;
    }
    const h = hostname.toLowerCase();
    return suffixList.some((suffix) => h.endsWith(suffix));
}

/**
 * Strict postMessage origin validation — parses URL and checks hostname suffix only.
 */
function isTrustedSalesforceOrigin(origin) {
    if (origin == null || typeof origin !== 'string') {
        return false;
    }
    const trimmed = origin.trim();
    if (!trimmed) {
        return false;
    }
    try {
        const parsed = new URL(trimmed);
        if (parsed.protocol !== 'https:') {
            return false;
        }
        return hangyoHostnameMatchesSuffixList(
            parsed.hostname,
            HANGYO_TRUSTED_SF_HOST_SUFFIXES
        );
    } catch (e) {
        return false;
    }
}

/** VF iframe document origins (*.vf.force.com) for LWC → embed postMessage target. */
function isTrustedVisualforceOrigin(origin) {
    if (origin == null || typeof origin !== 'string') {
        return false;
    }
    const trimmed = origin.trim();
    if (!trimmed) {
        return false;
    }
    try {
        const parsed = new URL(trimmed);
        if (parsed.protocol !== 'https:') {
            return false;
        }
        return hangyoHostnameMatchesSuffixList(
            parsed.hostname,
            HANGYO_TRUSTED_VF_HOST_SUFFIXES
        );
    } catch (e) {
        return false;
    }
}

/** LEX / My Domain hosts — must not be used as postMessage target into the VF iframe. */
function isLightningHostOrigin(origin) {
    if (origin == null || typeof origin !== 'string') {
        return false;
    }
    const trimmed = origin.trim();
    if (!trimmed) {
        return false;
    }
    try {
        const h = new URL(trimmed).hostname.toLowerCase();
        return (
            h.endsWith('.lightning.force.com') ||
            h.endsWith('.my.salesforce.com') ||
            h.endsWith('.sandbox.my.salesforce.com')
        );
    } catch (e) {
        return false;
    }
}

function toRadians(degrees) {
    return (degrees * Math.PI) / 180;
}

/** Round to 2 decimals for display / postMessage parity with the map embed. */
function roundDistanceKm(n) {
    if (typeof n !== 'number' || !Number.isFinite(n)) {
        return 0;
    }
    return Math.round(Math.max(0, n) * 100) / 100;
}

/** Great-circle distance between two { lat, lng } points in kilometres. */
function haversineKm(a, b) {
    const R = 6371;
    const dLat = toRadians(b.lat - a.lat);
    const dLng = toRadians(b.lng - a.lng);
    const lat1 = toRadians(a.lat);
    const lat2 = toRadians(b.lat);
    const h =
        Math.sin(dLat / 2) ** 2 +
        Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

export default class UserTrackingDashboard extends NavigationMixin(LightningElement) {
    @track userOptions = [];
    @track users = [];
    @track rows = [];
    @track summary = { ...EMPTY_SUMMARY };

    selectedUserId;
    /** yyyy-MM-dd for native date input; never leave undefined or the browser warns / sends bad values */
    selectedDate = '';
    userSearchText = '';
    isUserDropdownOpen = false;

    isLoading = false;

    totalDistanceKm = 0;
    /** Straight-line (Haversine) along visited coordinates — fallback only when Directions fails or is unavailable. */
    _fallbackCrowDistanceKm = 0;
    /** How Total Distance is sourced: pending crow until embed answers • road = Google Directions sum • fallback = Haversine after Directions failure • haversine = straight-line (non-ZSM). */
    @track _distanceKmSource = 'road';

    /** 'directions' = ZSM (Google Directions); 'haversine' = ADMIN, RSM, ASM, SSO. */
    _routingMode = 'haversine';

    /** Shown only when the VF embed URL is missing (deploy / config). */
    @track mapOverlayMessage =
        'Map could not be loaded. Deploy the UserTrackingMapEmbed Visualforce page and UserTrackingController.getUserTrackingMapEmbedUrl.';
    @track showMapOverlay = false;
    @track mapHintText = '';

    /** Taller map area within the dashboard (distinct from Google Maps built-in fullscreen). */
    @track mapExpanded = false;

    /** Absolute VF embed URL from Apex (org domain — not lightning.force.com). */
    @track mapEmbedUrl;
    /** Set when @wire(getUserTrackingMapEmbedUrl) fails or returns blank. */
    @track mapEmbedWireError;

    wiredUsersResult;

    _mapEmbedReady = false;
    _mapShellReady = false;
    /** Best-known VF iframe origin (*.vf.force.com). Set from embed JSON postMessage embedOrigin when available; falls back to Apex getUserTrackingMapIframePostMessageOrigin. */
    _mapIframeTargetOrigin;
    _mapLoadFailureReported = false;
    _pendingMapPayload = null;
    /** Dedupes postMessage into VF when payload unchanged and embed is ready. */
    _lastPostedMapPayloadFingerprint = '';
    /** Timeouts from deferred map flush; cancelled on each new send. */
    _mapEmbedFlushTimerIds = [];
    _onMapEmbedWindowMessage;
    /** Windows that receive postMessage from the VF iframe (LEX may nest frames; parent ≠ LWC window). */
    _mapMessageListenerWindows = [];

    /** idle: no plotted route • table_only: Load Data succeeded (summary only — clear route in iframe) • route: View Map — plot rows. */
    _mapDisplayMode = 'idle';

    /** After wire resolves false, VF skips maps.googleapis.com entirely (custom label blank in org). */
    _mapsJsKeyWireResolved = false;
    _mapsJsApiKeyPresent = false;

    /** HTTPS …*.vf.force.com predicted from Apex (when My Domain sandbox/prod hostname is known); used if postMessage event.origin stays on LEX. */
    _apexSuggestedMapPostOrigin = '';

    accessAllowed = false;
    accessCheckComplete = false;
    _accessRedirectStarted = false;

    get showDashboard() {
        return this.accessCheckComplete && this.accessAllowed;
    }

    get showAccessCheckSpinner() {
        return !this.accessCheckComplete;
    }

    @wire(getUserTrackingMapIframePostMessageOrigin)
    wiredMapIframePostMessageOrigin({ data, error }) {
        if (error) {
            if (this._isAccessDeniedError(error)) {
                this._denyAccessAndRedirectHome();
            }
            return;
        }
        const s = data != null ? String(data).trim() : '';
        this._apexSuggestedMapPostOrigin = s && isTrustedVisualforceOrigin(s) ? s : '';
        if (this.mapEmbedUrl) {
            Promise.resolve().then(() => this._syncMapEmbedAfterInfrastructureWire());
        }
    }

    @wire(getGoogleMapsJavaScriptApiKey)
    wiredGoogleMapsJavascriptApiKey({ data, error }) {
        if (error) {
            if (this._isAccessDeniedError(error)) {
                this._denyAccessAndRedirectHome();
            }
            return;
        }
        this._mapsJsKeyWireResolved = true;
        this._mapsJsApiKeyPresent = String(data != null ? data : '').trim().length > 0;
        if (this.mapEmbedUrl) {
            Promise.resolve().then(() => this._syncMapEmbedAfterInfrastructureWire());
        }
    }

    @wire(getUserTrackingMapEmbedUrl)
    wiredMapEmbedUrl({ data, error }) {
        if (error) {
            if (this._isAccessDeniedError(error)) {
                this._denyAccessAndRedirectHome();
                return;
            }
            this.mapEmbedUrl = undefined;
            this.mapEmbedWireError = this.reduceError(error);
            // eslint-disable-next-line no-console
            console.error('[UserTrackingDashboard] Map embed URL (Apex wire):', this.mapEmbedWireError);
            this.notifyError('Map embed', this.mapEmbedWireError);
            return;
        }
        const url = data != null ? String(data).trim() : '';
        if (url) {
            this.mapEmbedWireError = undefined;
            this.mapEmbedUrl = url;
            this._mapEmbedReady = false;
            this._mapShellReady = false;
            this._mapIframeTargetOrigin = undefined;
            this._mapLoadFailureReported = false;
            Promise.resolve().then(() => this._syncMapEmbedAfterInfrastructureWire());
        } else if (data !== undefined) {
            this.mapEmbedUrl = undefined;
            this.mapEmbedWireError =
                'The map embed URL from Apex was empty. Deploy UserTrackingMapEmbed and confirm getUserTrackingMapEmbedUrl.';
            // eslint-disable-next-line no-console
            console.error('[UserTrackingDashboard] Map embed URL:', this.mapEmbedWireError);
            this.notifyError('Map embed', this.mapEmbedWireError);
        }
    }

    @wire(getUsers)
    wiredUsers(result) {
        this.wiredUsersResult = result;
        const { data, error } = result;
        if (data) {
            this.userOptions = data.map((u) => ({ label: u.name, value: u.id }));
            this.users = data.map((u) => ({
                userId: u.id,
                userName: u.name,
                role: '—',
                location: '—',
                lastActivity: '—',
                distance: '—'
            }));
            return;
        }
        if (error) {
            if (this._isAccessDeniedError(error)) {
                this._denyAccessAndRedirectHome();
                return;
            }
            this.notifyError('Failed to load users', this.reduceError(error));
        }
    }

    async connectedCallback() {
        try {
            const access = await getDashboardAccess();
            this.accessCheckComplete = true;
            if (!access || !access.allowed) {
                this.accessAllowed = false;
                this._denyAccessAndRedirectHome(
                    this._accessDeniedToastMessage(access)
                );
                return;
            }
            this.accessAllowed = true;
            this._routingMode =
                access.routingMode === 'directions' ? 'directions' : 'haversine';
            this._distanceKmSource =
                this._routingMode === 'directions' ? 'road' : 'haversine';
            await this._refreshWiresAfterAccessGranted();
        } catch (e) {
            this.accessCheckComplete = true;
            this.accessAllowed = false;
            this._denyAccessAndRedirectHome();
            return;
        }

        this._onMapEmbedWindowMessage = this.handleMapEmbedWindowMessage.bind(this);
        this._attachMapMessageListeners();
    }

    async _refreshWiresAfterAccessGranted() {
        const refreshes = [];
        if (this.wiredUsersResult) {
            refreshes.push(refreshApex(this.wiredUsersResult));
        }
        try {
            await Promise.all(refreshes);
        } catch (e) {
            // ignore stale wire refresh failures
        }
    }

    /** Blank Employee_Role__c on the running user (Apex returns null userRoleName). */
    _accessDeniedToastMessage(access) {
        const roleName = access?.userRoleName;
        if (roleName == null || String(roleName).trim() === '') {
            return ACCESS_DENIED_EMPLOYEE_ROLE_BLANK_MESSAGE;
        }
        return ACCESS_DENIED_MESSAGE;
    }

    /** Error toast, then Home — once per component load (guards duplicate wire/callback calls). */
    _denyAccessAndRedirectHome(message = ACCESS_DENIED_MESSAGE) {
        if (this._accessRedirectStarted) {
            return;
        }
        this._accessRedirectStarted = true;
        this.accessAllowed = false;
        this.notifyError('Access denied', message);
        window.setTimeout(() => {
            this[NavigationMixin.Navigate]({
                type: 'standard__namedPage',
                attributes: { pageName: 'home' }
            });
        }, ACCESS_DENIED_REDIRECT_DELAY_MS);
    }

    _isAccessDeniedError(error) {
        const msg = (this.reduceError(error) || '').toLowerCase();
        return msg.includes('do not have access') && msg.includes('user tracking dashboard');
    }

    _attachMapMessageListeners() {
        const fn = this._onMapEmbedWindowMessage;
        if (!fn) {
            return;
        }
        const seen = new Set();
        const tryAdd = (w) => {
            if (!w || seen.has(w)) {
                return;
            }
            try {
                w.addEventListener('message', fn);
                seen.add(w);
                this._mapMessageListenerWindows.push(w);
            } catch (e) {
                // LWS may block some windows; ignore.
            }
        };
        tryAdd(window);
        try {
            tryAdd(window.parent);
        } catch (e) {
            // ignore
        }
        try {
            tryAdd(window.top);
        } catch (e) {
            // ignore
        }
    }

    _detachMapMessageListeners() {
        const fn = this._onMapEmbedWindowMessage;
        if (!fn) {
            return;
        }
        for (const w of this._mapMessageListenerWindows) {
            try {
                w.removeEventListener('message', fn);
            } catch (e) {
                // ignore
            }
        }
        this._mapMessageListenerWindows = [];
    }

    /**
     * Iframe src must be the Visualforce URL from Apex (org / my domain or *.vf.force.com).
     * Do not replace an absolute URL with window.location.origin (LEX) — that serves the wrong document.
     */
    get mapIframeSrc() {
        if (!this.mapEmbedUrl) {
            return '';
        }
        if (typeof window === 'undefined') {
            return this.mapEmbedUrl;
        }
        try {
            const raw = String(this.mapEmbedUrl).trim();
            if (raw.startsWith('https://') || raw.startsWith('http://')) {
                return raw;
            }
            const path = raw.startsWith('/') ? raw : `/${raw}`;
            return `${window.location.origin}${path}`;
        } catch (e) {
            return this.mapEmbedUrl;
        }
    }

    get hangyoMapOuterClass() {
        const base = 'hangyoMapOuter';
        return this.mapExpanded ? `${base} hangyoMapOuter_expanded` : base;
    }

    get mapContainerClass() {
        const base = 'mapContainer';
        return this.mapExpanded ? `${base} mapContainer_expanded` : base;
    }

    get mapExpandToggleLabel() {
        return this.mapExpanded ? 'Collapse map' : 'Expand map';
    }

    get mapExpandToggleIcon() {
        return this.mapExpanded ? 'utility:contract_alt' : 'utility:expand_alt';
    }

    get mapExpandToggleDisabled() {
        return !this.mapEmbedUrl;
    }

    toggleMapExpanded() {
        this.mapExpanded = !this.mapExpanded;
        requestAnimationFrame(() => {
            requestAnimationFrame(() => {
                this._postToMapEmbed({ type: 'HANGYO_MAP_REFLOW' });
            });
        });
    }

    handleMapIframeLoad() {
        this._mapLoadFailureReported = false;
        // Do not clear _mapIframeTargetOrigin / shell / embed flags here: SHELL_READY can post
        // before the iframe "load" event; clearing would wipe the real *.vf.force.com origin and
        // cause Locker/LWS to substitute lightning.force.com → postMessage mismatch + grey map.
        Promise.resolve().then(() => this._syncMapEmbedAfterInfrastructureWire());
    }

    renderedCallback() {
        if (this._visibilityObserverSetup) {
            return;
        }
        const root = this.template.querySelector('[data-id="dashboardRoot"]');
        if (!root) {
            return;
        }
        this._bindVisibilityRefreshObserver(root);
        this._visibilityObserverSetup = true;
    }

    disconnectedCallback() {
        if (this._visibilityObserver) {
            this._visibilityObserver.disconnect();
            this._visibilityObserver = undefined;
        }
        if (this._visibilityRefreshTimer) {
            clearTimeout(this._visibilityRefreshTimer);
            this._visibilityRefreshTimer = undefined;
        }
        this._visibilityObserverSetup = false;
        this._detachMapMessageListeners();
        this._onMapEmbedWindowMessage = undefined;
    }

    _bindVisibilityRefreshObserver(rootEl) {
        if (typeof IntersectionObserver === 'undefined') {
            return;
        }

        this._visibilityIntersectionSeen = false;
        this._wasIntersecting = undefined;
        this._leftViewportOnce = false;

        this._visibilityObserver = new IntersectionObserver(
            (entries) => {
                const entry = entries[0];
                if (!entry) {
                    return;
                }
                const now = entry.isIntersecting;

                if (!this._visibilityIntersectionSeen) {
                    this._visibilityIntersectionSeen = true;
                    this._wasIntersecting = now;
                    return;
                }

                if (now && !this._wasIntersecting && this._leftViewportOnce) {
                    this._scheduleRefreshAfterTabReturn();
                }
                if (!now && this._wasIntersecting) {
                    this._leftViewportOnce = true;
                }
                this._wasIntersecting = now;
            },
            { threshold: 0.01 }
        );
        this._visibilityObserver.observe(rootEl);
    }

    _scheduleRefreshAfterTabReturn() {
        if (this._visibilityRefreshTimer) {
            clearTimeout(this._visibilityRefreshTimer);
        }
        this._visibilityRefreshTimer = window.setTimeout(() => {
            this._visibilityRefreshTimer = undefined;
            this.refreshDashboardAfterNavigationReturn();
        }, 200);
    }

    async refreshDashboardAfterNavigationReturn() {
        try {
            if (this.wiredUsersResult) {
                await refreshApex(this.wiredUsersResult);
            }
        } catch (e) {
            // refreshApex can fail if wire context is stale; ignore.
        }
        this.rows = [];
        this.summary = { ...EMPTY_SUMMARY };
        this.totalDistanceKm = 0;
        this._fallbackCrowDistanceKm = 0;
        this._distanceKmSource =
            this._routingMode === 'directions' ? 'road' : 'haversine';
        this.isUserDropdownOpen = false;
        this.isLoading = false;

        this.selectedUserId = undefined;
        this.selectedDate = '';
        this.userSearchText = '';
        this._resetMapToIdleMessage();
    }

    _defaultDistanceKmSource() {
        return this._routingMode === 'directions' ? 'road' : 'haversine';
    }

    _resetMapToIdleMessage() {
        this._mapDisplayMode = 'idle';
        this._pendingMapPayload = this.buildEmptyMapPayload();
        this.mapHintText = this._applyMapInfrastructureHints('');
        this._postMapPayloadToEmbed(this._pendingMapPayload);
        this.showMapOverlay = false;
    }

    buildEmptyMapPayload() {
        return {
            path: [],
            markers: [],
            defaultCenter: { ...DEFAULT_MAP_CENTER },
            defaultZoom: DEFAULT_MAP_ZOOM,
            recordCount: 0,
            plottedCount: 0,
            renderMode: 'full'
        };
    }

    /**
     * Parent window message events in LEX sometimes report lightning.force.com even when the child
     * document is *.vf.force.com; trust embedOrigin from the VF frame when hostname is VF.
     * Inbound messages must pass isTrustedSalesforceOrigin(event.origin) before any state update.
     */
    _parseVisualforceEmbedOrigin(data, fallbackEventOrigin) {
        const eo =
            data && typeof data.embedOrigin === 'string' ? data.embedOrigin.trim() : '';
        if (eo && isTrustedVisualforceOrigin(eo)) {
            return eo;
        }
        const fb = typeof fallbackEventOrigin === 'string' ? fallbackEventOrigin.trim() : '';
        if (fb && isTrustedVisualforceOrigin(fb)) {
            return fb;
        }
        return undefined;
    }

    handleMapEmbedWindowMessage(event) {
        let d = event.data;
        if (typeof d === 'string') {
            if (d.length < 14 || !d.includes('HANGYO_MAP')) {
                return;
            }
            try {
                d = JSON.parse(d);
            } catch (parseErr) {
                return;
            }
        }
        const type = d && typeof d.type === 'string' ? d.type : '';
        if (!type.startsWith('HANGYO_MAP')) {
            return;
        }

        if (!isTrustedSalesforceOrigin(event.origin)) {
            return;
        }

        const vfOriginHint = this._parseVisualforceEmbedOrigin(d, event.origin);

        if (type === 'HANGYO_MAP_SHELL_READY') {
            if (!vfOriginHint) {
                return;
            }
            this._mapIframeTargetOrigin = vfOriginHint;
            this._mapShellReady = true;
            if (!this._mapEmbedReady) {
                requestAnimationFrame(() => {
                    requestAnimationFrame(() => this._flushPendingMapPayloadToEmbed());
                });
            }
            return;
        }
        if (type === 'HANGYO_MAP_EMBED_READY') {
            if (!vfOriginHint) {
                return;
            }
            this._mapIframeTargetOrigin = vfOriginHint;
            const wasEmbedReady = this._mapEmbedReady;
            this._mapEmbedReady = true;
            if (!wasEmbedReady) {
                this._flushPendingMapPayloadToEmbed();
            }
            return;
        }
        if (type === 'HANGYO_MAP_ROAD_DISTANCE_KM') {
            if (this._routingMode === 'haversine') {
                return;
            }
            if (vfOriginHint) {
                this._mapIframeTargetOrigin = vfOriginHint;
            }
            const kmRaw = d.roadDistanceKm;
            const directionsFailed = d.directionsFailed === true;
            const roadOk =
                typeof kmRaw === 'number' && Number.isFinite(kmRaw) && kmRaw >= 0 && !directionsFailed;

            if (roadOk) {
                this.totalDistanceKm = roundDistanceKm(kmRaw);
                this._distanceKmSource = 'road';
                return;
            }

            if (directionsFailed) {
                const vfKm =
                    typeof kmRaw === 'number' && Number.isFinite(kmRaw) && kmRaw >= 0
                        ? roundDistanceKm(kmRaw)
                        : null;
                const fb =
                    vfKm != null && vfKm > 0
                        ? vfKm
                        : roundDistanceKm(this._fallbackCrowDistanceKm);
                this.totalDistanceKm = fb;
                this._distanceKmSource = 'fallback';
                return;
            }

            return;
        }
        //Added by Hari - For rectify the production issue for no line in map
        if (type === 'HANGYO_MAP_ROUTE_FALLBACK') {
            if (vfOriginHint) {
                this._mapIframeTargetOrigin = vfOriginHint;
            }
            const fallbackMsg =
                d.message != null && String(d.message).trim() !== ''
                    ? String(d.message).trim()
                    : 'Google driving route could not be drawn for this day\'s stops. Showing a straight-line path between visits instead.';
            this.mapHintText = this._applyMapInfrastructureHints(fallbackMsg);
            return;
        }
        //Added by Hari - Clear fallback hint when driving route draws successfully
        if (type === 'HANGYO_MAP_ROUTE_OK') {
            if (vfOriginHint) {
                this._mapIframeTargetOrigin = vfOriginHint;
            }
            this.mapHintText = this._applyMapInfrastructureHints('');
            return;
        }
        if (type === 'HANGYO_MAP_LOAD_FAILED') {
            if (vfOriginHint) {
                this._mapIframeTargetOrigin = vfOriginHint;
            }
            if (this._distanceKmSource === 'pending') {
                this.totalDistanceKm = roundDistanceKm(this._fallbackCrowDistanceKm);
                this._distanceKmSource = 'fallback';
            }
            const detail =
                (d && typeof d.message === 'string' && d.message.trim()) ||
                'Google Maps did not load in the embed frame.';
            if (this._reportMapLoadFailure(detail, 'Google Maps')) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Google Maps',
                        message: detail,
                        variant: 'error',
                        mode: 'dismissable'
                    })
                );
            }
        }
    }

    /**
     * Logs map load failures to the console; returns true the first time per iframe load.
     */
    _reportMapLoadFailure(message, logLabel = 'Map') {
        if (this._mapLoadFailureReported) {
            return false;
        }
        this._mapLoadFailureReported = true;
        // eslint-disable-next-line no-console
        console.error(`[UserTrackingDashboard] ${logLabel}: ${message}`);
        return true;
    }

    /**
     * postMessage structured-clone rejects LWC Proxies (e.g. Apex Id references). Produce JSON-safe plain objects.
     */
    _serializedRoutePayload(payload) {
        const p = payload || {};
        const pathIn = Array.isArray(p.path) ? p.path : [];
        const path = pathIn
            .map((pt) => ({ lat: Number(pt?.lat), lng: Number(pt?.lng) }))
            .filter((pt) => Number.isFinite(pt.lat) && Number.isFinite(pt.lng));
        const markersIn = Array.isArray(p.markers) ? p.markers : [];
        const markers = markersIn
            .map((m) => ({
                lat: Number(m?.lat),
                lng: Number(m?.lng),
                activityType: m?.activityType != null ? String(m.activityType) : '—',
                title: m?.title != null ? String(m.title) : 'Activity',
                outlet: m?.outlet != null ? String(m.outlet) : '',
                callType: m?.callType != null ? String(m.callType) : '—',
                timestampIso: m?.timestampIso != null ? String(m.timestampIso) : '',
                checkInIso: m?.checkInIso != null ? String(m.checkInIso) : '',
                checkOutIso: m?.checkOutIso != null ? String(m.checkOutIso) : '',
                orderValue:
                    m?.orderValue != null && Number.isFinite(Number(m.orderValue))
                        ? Number(m.orderValue)
                        : null,
                infoWindowMode:
                    m?.infoWindowMode != null ? String(m.infoWindowMode) : 'standard',
                attendanceAppliedOnIso:
                    m?.attendanceAppliedOnIso != null
                        ? String(m.attendanceAppliedOnIso)
                        : '',
                attendanceStatus:
                    m?.attendanceStatus != null ? String(m.attendanceStatus) : '',
                attendanceLocationDetail:
                    m?.attendanceLocationDetail != null
                        ? String(m.attendanceLocationDetail)
                        : '',
                eodDateTimeIso:
                    m?.eodDateTimeIso != null ? String(m.eodDateTimeIso) : '',
                eodLocationDetail:
                    m?.eodLocationDetail != null ? String(m.eodLocationDetail) : '',
                onboardDateIso:
                    m?.onboardDateIso != null ? String(m.onboardDateIso) : '',
                newOutletLocationDetail:
                    m?.newOutletLocationDetail != null
                        ? String(m.newOutletLocationDetail)
                        : ''
            }))
            .filter((m) => Number.isFinite(m.lat) && Number.isFinite(m.lng));
        const dc = p.defaultCenter || DEFAULT_MAP_CENTER;
        const dz = Number.isFinite(p.defaultZoom) ? p.defaultZoom : DEFAULT_MAP_ZOOM;
        return JSON.parse(
            JSON.stringify({
                type: 'HANGYO_MAP_ROUTE',
                path,
                markers,
                defaultCenter: {
                    lat: Number(dc.lat),
                    lng: Number(dc.lng)
                },
                defaultZoom: dz,
                recordCount: Number(p.recordCount ?? 0),
                plottedCount: Number(p.plottedCount ?? 0),
                renderMode:
                    p.renderMode === 'distanceOnly' ? 'distanceOnly' : 'full',
                routingMode:
                    p.routingMode === 'directions' ? 'directions' : 'haversine',
                forceRouteRender: p.forceRouteRender === true
            })
        );
    }

    /**
     * Target origin for postMessage into the VF map iframe (*.vf.force.com), never LEX lightning.force.com.
     */
    _getMapEmbedPostTargetOrigin() {
        let fromFrame =
            this._mapIframeTargetOrigin && isTrustedVisualforceOrigin(this._mapIframeTargetOrigin)
                ? this._mapIframeTargetOrigin.trim()
                : '';
        let fromApex =
            this._apexSuggestedMapPostOrigin && isTrustedVisualforceOrigin(this._apexSuggestedMapPostOrigin)
                ? this._apexSuggestedMapPostOrigin.trim()
                : '';
        const rejectLex = (o) =>
            typeof o !== 'string' || isLightningHostOrigin(o) ? '' : o;
        fromFrame = rejectLex(fromFrame);
        fromApex = rejectLex(fromApex);
        return fromApex || fromFrame;
    }

    _postToMapEmbed(dataObj) {
        const iframe = this.template.querySelector('[data-id="mapIframe"]');
        const cw = iframe?.contentWindow;
        const targetOrigin = this._getMapEmbedPostTargetOrigin();
        if (!cw || !targetOrigin) {
            return;
        }
        try {
            cw.postMessage(JSON.stringify(dataObj), targetOrigin);
        } catch (e) {
            const text = e && e.message ? e.message : String(e);
            // eslint-disable-next-line no-console
            console.error('[UserTrackingDashboard] Map postMessage:', text);
            this.notifyError('Map', text);
        }
    }

    /**
     * Send route JSON into the VF iframe.
     * Prefer Apex-predicted *.vf.force.com origin first (stable in LEX); VF embedOrigin second.
     * Never postMessage with *.lightning.force.com — browser rejects vs the actual iframe (*.vf.force.com).
     */
    _mapPayloadFingerprint(payload) {
        const p = payload || this.buildEmptyMapPayload();
        const path = Array.isArray(p.path) ? p.path : [];
        const markers = Array.isArray(p.markers) ? p.markers : [];
        const p0 = path[0];
        const pl = path.length > 0 ? path[path.length - 1] : null;
        return JSON.stringify({
            rm: p.renderMode === 'distanceOnly' ? 'distanceOnly' : 'full',
            rt: p.routingMode === 'directions' ? 'directions' : 'haversine',
            pc: path.length,
            mc: markers.length,
            p0lat: p0 != null ? p0.lat : null,
            p0lng: p0 != null ? p0.lng : null,
            pllat: pl != null ? pl.lat : null,
            pllng: pl != null ? pl.lng : null,
            dz: p.defaultZoom
        });
    }

    _cancelDeferredMapEmbedFlush() {
        if (this._mapEmbedFlushTimerIds && this._mapEmbedFlushTimerIds.length) {
            this._mapEmbedFlushTimerIds.forEach((id) => window.clearTimeout(id));
        }
        this._mapEmbedFlushTimerIds = [];
    }

    _postMapPayloadToEmbed(payload, force) {
        const resolved = payload || this.buildEmptyMapPayload();
        const fp = this._mapPayloadFingerprint(resolved);
        if (
            !force &&
            fp === this._lastPostedMapPayloadFingerprint &&
            this._mapEmbedReady
        ) {
            return;
        }
        this._lastPostedMapPayloadFingerprint = fp;
        const msg = this._serializedRoutePayload(resolved);
        this._postToMapEmbed(msg);
    }

    _flushPendingMapPayloadToEmbed() {
        let payload;
        if (this._pendingMapPayload != null) {
            payload = this._pendingMapPayload;
        } else if (
            this._mapDisplayMode === 'table_only' ||
            this._mapDisplayMode === 'idle'
        ) {
            payload = this.buildEmptyMapPayload();
        } else {
            payload = this.buildMapPayload(this.rows);
        }
        this._postMapPayloadToEmbed(payload, true);
    }

    /** Combines UX hint text with VF / Maps configuration warnings (e.g. missing API key). */
    _applyMapInfrastructureHints(primaryHint = '') {
        const extras = [];
        if (this._mapsJsKeyWireResolved && !this._mapsJsApiKeyPresent) {
            extras.push(
                'Custom Label Google_Maps_API_Key is empty in this org — the map frame will not call maps.googleapis.com. In Setup → Custom Labels, create that label (and value) in this sandbox, or deploy it with your package.'
            );
        }
        const primary = (primaryHint && String(primaryHint).trim()) || '';
        if (!extras.length) {
            return primary;
        }
        return primary ? `${extras.join(' ')} ${primary}`.trim() : extras.join(' ').trim();
    }

    /**
     * After Load Data: keep summary populated but clear the plotted route / markers in the embed.
     */
    parkMapEmbedForTableOnly() {
        if (!this.mapEmbedUrl) {
            this.showMapOverlay = true;
            this.mapHintText = '';
            this.mapOverlayMessage =
                'Map could not be loaded. Deploy the UserTrackingMapEmbed Visualforce page and UserTrackingController.getUserTrackingMapEmbedUrl.';
            // eslint-disable-next-line no-console
            console.error('[UserTrackingDashboard] Map embed:', this.mapOverlayMessage);
            return;
        }
        this._mapDisplayMode = 'table_only';
        const distancePayload = this.buildMapPayload(this.rows, {
            renderMode: 'distanceOnly'
        });
        this._pendingMapPayload = distancePayload;
        this.mapHintText = this._applyMapInfrastructureHints('');
        this.showMapOverlay = false;
        this._cancelDeferredMapEmbedFlush();
        this._postMapPayloadToEmbed(distancePayload);
        this._scheduleDeferredMapEmbedFlush();
    }

    /**
     * Apex wires / iframe load must not wipe a plotted driving route.
     * Only (re)post when the embed is still initializing or payload changed.
     */
    _syncMapEmbedAfterInfrastructureWire() {
        if (!this.mapEmbedUrl) {
            return;
        }
        if (this._mapDisplayMode === 'table_only') {
            if (this.rows && this.rows.length > 0) {
                this.parkMapEmbedForTableOnly();
            }
            return;
        }
        if (this._mapDisplayMode === 'route' && this.rows && this.rows.length > 0) {
            const payload = this.buildMapPayload(this.rows);
            const fp = this._mapPayloadFingerprint(payload);
            this._pendingMapPayload = payload;
            if (this._mapEmbedReady && fp === this._lastPostedMapPayloadFingerprint) {
                return;
            }
            if (!this._mapEmbedReady || fp !== this._lastPostedMapPayloadFingerprint) {
                this._cancelDeferredMapEmbedFlush();
                this._postMapPayloadToEmbed(payload, true);
                this._scheduleDeferredMapEmbedFlush();
            }
            return;
        }
        if (this._mapDisplayMode === 'idle') {
            this.showMapOverlay = false;
        }
    }

    syncMapEmbedView() {
        if (!this.mapEmbedUrl) {
            this.showMapOverlay = true;
            this.mapHintText = '';
            this.mapOverlayMessage =
                'Map could not be loaded. Deploy the UserTrackingMapEmbed Visualforce page and UserTrackingController.getUserTrackingMapEmbedUrl.';
            // eslint-disable-next-line no-console
            console.error('[UserTrackingDashboard] Map embed:', this.mapOverlayMessage);
            return;
        }

        if (this._mapDisplayMode === 'table_only') {
            this.parkMapEmbedForTableOnly();
            return;
        }

        const payload = this.buildMapPayload(this.rows, { forceRouteRender: true });
        this._pendingMapPayload = this.buildMapPayload(this.rows);

        let routeHint = '';
        if (payload.recordCount > 0 && payload.plottedCount === 0) {
            routeHint =
                'Records exist for this day, but latitude/longitude are not set — showing the default map. Add coordinates on User Location records to plot each Activity Type.';
        }

        this.mapHintText = this._applyMapInfrastructureHints(routeHint);
        this.showMapOverlay = false;
        this._cancelDeferredMapEmbedFlush();
        this._postMapPayloadToEmbed(payload, true);
        this._scheduleDeferredMapEmbedFlush();
    }

    /**
     * Re-send only while the VF iframe is not ready (LEX nested-frame timing).
     * When embed is ready, a single post is enough — avoids cancelling in-flight Directions chunks.
     */
    _scheduleDeferredMapEmbedFlush() {
        this._cancelDeferredMapEmbedFlush();
        if (this._mapEmbedReady) {
            return;
        }
        this._mapEmbedFlushTimerIds = [200, 520].map((ms) =>
            window.setTimeout(() => {
                if (!this._mapEmbedReady) {
                    this._flushPendingMapPayloadToEmbed();
                }
            }, ms)
        );
    }

    /** ISO string for map popups; Apex DateTime usually arrives as string already. */
    _mapFieldToIso(fieldVal) {
        if (fieldVal == null || fieldVal === '') {
            return '';
        }
        if (typeof fieldVal === 'string') {
            return fieldVal;
        }
        try {
            const d = new Date(fieldVal);
            return Number.isFinite(d.getTime()) ? d.toISOString() : '';
        } catch (e) {
            return '';
        }
    }

    /** Call type line in map hover card (aligned with client legend). */
    deriveMapCallType(row) {
        const raw = row?.Activity_Type__c;
        const v =
            raw != null && String(raw).trim() !== '' ? String(raw).trim().toLowerCase() : '';
        if (!v) {
            return '—';
        }
        if (v === 'attendance' || v.includes('attendance')) {
            return 'Attendance';
        }
        if (v === 'eod' || v.includes('eod')) {
            return 'EOD';
        }
        if (v.includes('new outlet') || v.includes('new-outlet')) {
            return 'New Outlet';
        }
        if (v.includes('non') && v.includes('productive')) {
            return 'Non-Productive';
        }
        if (v.includes('productive') && !v.includes('non')) {
            return 'Productive';
        }
        return String(raw).trim();
    }

    /** Maps Apex TrackingActivityDTO list to row shape used by map builders. */
    mapActivitiesToRows(activities) {
        const list = Array.isArray(activities) ? activities : [];
        return list.map((a) => ({
            Latitude__c: a?.latitude,
            Longitude__c: a?.longitude,
            Activity_Type__c: a?.activityType,
            Timestamp__c: a?.sortTime,
            Outlet_Name__r: a?.outletName ? { Name: a.outletName } : null,
            CheckIn_Time__c: a?.checkInTime,
            CheckOut_Time__c: a?.checkOutTime,
            Order_Value__c: a?.orderValue,
            Attendance_Applied_on__c: a?.attendanceAppliedOn,
            attendanceStatus: a?.attendanceStatus,
            attendanceLocationDetail: a?.attendanceLocationDetail,
            eodDateTime: a?.eodDateTime,
            eodLocationDetail: a?.eodLocationDetail,
            onboardDate: a?.onboardDate,
            newOutletLocationDetail: a?.newOutletLocationDetail
        }));
    }

    /**
     * When consecutive stops share the same GPS, nudge later stops slightly so route km/polyline
     * reflect every visit (aligned with VF hangyoPathForRouting / marker spiral).
     */
    expandPathForRouting(path) {
        const pts = Array.isArray(path) ? path.filter((p) => Number.isFinite(p?.lat) && Number.isFinite(p?.lng)) : [];
        if (pts.length < 2) {
            return pts;
        }
        const CLUSTER_SQ = 2.85e-7;
        const BASE_DEG = 0.000365;
        const planarSq = (a, b) => {
            const avgLatRad = (((a.lat + b.lat) / 2) * Math.PI) / 180;
            const dy = a.lat - b.lat;
            const scaledLng = (a.lng - b.lng) * Math.cos(avgLatRad);
            return dy * dy + scaledLng * scaledLng;
        };
        const offsetSlot = (lat, lng, slot) => {
            if (!slot) {
                return { lat, lng };
            }
            const ring = Math.floor((slot - 1) / 8);
            const posInRing = (slot - 1) % 8;
            const angle = ((2 * Math.PI) * (posInRing + 1)) / 8 + ring * 0.28;
            const step = BASE_DEG * (ring + 1);
            const latRad = (lat * Math.PI) / 180;
            return {
                lat: lat + step * Math.cos(angle),
                lng: lng + step * Math.sin(angle) / Math.cos(latRad || 1e-6)
            };
        };
        const out = [{ lat: pts[0].lat, lng: pts[0].lng }];
        let slot = 0;
        for (let i = 1; i < pts.length; i++) {
            const last = out[out.length - 1];
            const cur = pts[i];
            if (CLUSTER_SQ > planarSq(last, cur)) {
                slot += 1;
                out.push(offsetSlot(last.lat, last.lng, slot));
            } else {
                slot = 0;
                out.push({ lat: cur.lat, lng: cur.lng });
            }
        }
        return out;
    }

    buildMapPayload(rows, options = {}) {
        const list = Array.isArray(rows) ? rows : [];
        const path = this.expandPathForRouting(this.buildLatLngPath(list));
        const markers = [];
        for (const row of list) {
            const lat = Number(row?.Latitude__c);
            const lng = Number(row?.Longitude__c);
            if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
                continue;
            }
            const actRaw = row?.Activity_Type__c;
            const act =
                actRaw != null && String(actRaw).trim() !== ''
                    ? String(actRaw).trim()
                    : '—';
            const actLower = act.toLowerCase();
            const isEod = actLower === 'eod';
            const isAttendance =
                !isEod && (actLower === 'attendance' || actLower.includes('attendance'));
            const isNewOutlet =
                !isEod &&
                !isAttendance &&
                (actLower.includes('new outlet') || actLower.includes('new-outlet'));
            const outletRel = row?.Outlet_Name__r;
            const outletNameRaw =
                outletRel && outletRel.Name != null ? String(outletRel.Name) : '';
            const outlet =
                outletNameRaw.trim() !== '' ? outletNameRaw.trim() : '';
            let title = act !== '—' ? act : 'Activity';
            if (outlet) {
                title += ` · ${outlet}`;
            }
            const ov = row?.Order_Value__c;
            const attStatus =
                row?.attendanceStatus != null ? String(row.attendanceStatus).trim() : '';
            const attLocDetail =
                row?.attendanceLocationDetail != null
                    ? String(row.attendanceLocationDetail).trim()
                    : '';
            const eodLocDetail =
                row?.eodLocationDetail != null ? String(row.eodLocationDetail).trim() : '';
            const newOutletLocDetail =
                row?.newOutletLocationDetail != null
                    ? String(row.newOutletLocationDetail).trim()
                    : '';
            markers.push({
                lat,
                lng,
                activityType: act,
                title,
                outlet,
                callType: this.deriveMapCallType(row),
                infoWindowMode: isEod
                    ? 'eod'
                    : isAttendance
                      ? 'attendance'
                      : isNewOutlet
                        ? 'newOutlet'
                        : 'standard',
                attendanceAppliedOnIso: isAttendance
                    ? this._mapFieldToIso(row?.Attendance_Applied_on__c)
                    : '',
                attendanceStatus: isAttendance ? attStatus : '',
                attendanceLocationDetail: isAttendance ? attLocDetail : '',
                eodDateTimeIso: isEod ? this._mapFieldToIso(row?.eodDateTime) : '',
                eodLocationDetail: isEod ? eodLocDetail : '',
                onboardDateIso: isNewOutlet ? this._mapFieldToIso(row?.onboardDate) : '',
                newOutletLocationDetail: isNewOutlet ? newOutletLocDetail : '',
                timestampIso: this._mapFieldToIso(row?.Timestamp__c),
                checkInIso: this._mapFieldToIso(row?.CheckIn_Time__c),
                checkOutIso: this._mapFieldToIso(row?.CheckOut_Time__c),
                orderValue:
                    ov != null && Number.isFinite(Number(ov)) ? Number(ov) : null
            });
        }
        const renderMode =
            options && options.renderMode === 'distanceOnly' ? 'distanceOnly' : 'full';
        const forceRouteRender =
            options && options.forceRouteRender === true;
        return {
            path,
            markers,
            defaultCenter: { ...DEFAULT_MAP_CENTER },
            defaultZoom: DEFAULT_MAP_ZOOM,
            recordCount: list.length,
            plottedCount: markers.length,
            renderMode,
            routingMode: this._routingMode,
            forceRouteRender: forceRouteRender === true
        };
    }

    buildLatLngPath(rows) {
        const list = Array.isArray(rows) ? rows : [];
        const path = [];
        for (const row of list) {
            const lat = Number(row?.Latitude__c);
            const lng = Number(row?.Longitude__c);
            if (Number.isFinite(lat) && Number.isFinite(lng)) {
                path.push({ lat, lng });
            }
        }
        return path;
    }

    computePathDistanceKm(path) {
        const expanded = this.expandPathForRouting(path);
        if (!expanded || expanded.length < 2) {
            return 0;
        }
        let sum = 0;
        const MIN_LEG_KM = 0.04;
        for (let i = 1; i < expanded.length; i++) {
            const leg = haversineKm(expanded[i - 1], expanded[i]);
            sum += leg > 0.001 ? leg : MIN_LEG_KM;
        }
        return sum;
    }

    async clearUserSelectionAfterNoData() {
        try {
            if (this.wiredUsersResult) {
                await refreshApex(this.wiredUsersResult);
            }
        } catch (e) {
            // refreshApex can fail if wire context is stale; ignore.
        }
        this.rows = [];
        this.summary = { ...EMPTY_SUMMARY };
        this.totalDistanceKm = 0;
        this._fallbackCrowDistanceKm = 0;
        this._distanceKmSource = this._defaultDistanceKmSource();
        this.selectedUserId = undefined;
        this.userSearchText = '';
        this.isUserDropdownOpen = false;

        requestAnimationFrame(() => {
            const input = this.template.querySelector('#userSearchInput');
            if (input && typeof input.focus === 'function') {
                input.focus();
            }
        });
    }

    get isViewMapDisabled() {
        return !this.selectedUserId || !this.selectedDate || this.isLoading;
    }

    get isLoadDisabled() {
        return !this.selectedUserId || !this.selectedDate || this.isLoading;
    }

    get hasUserMatches() {
        return Array.isArray(this.userMatches) && this.userMatches.length > 0;
    }

    get userMatches() {
        const term = (this.userSearchText || '').trim().toLowerCase();
        if (!term) return [];
        return (this.users || [])
            .filter((u) => (u.userName || '').toLowerCase().includes(term))
            .slice(0, 20);
    }

    get summaryUserName() {
        return this.summary?.userName || '—';
    }

    get totalOrderValueDisplay() {
        return this.formatNumber(this.summary?.totalOrderValue ?? 0, {
            useGrouping: false
        });
    }

    get totalDistanceDisplay() {
        return this.formatNumber(this.totalDistanceKm, {
            useGrouping: false
        });
    }

    /** Hover hint for summary tile — clarifies Directions vs Haversine without changing layout. */
    get totalDistanceTileTitle() {
        if (this._distanceKmSource === 'haversine') {
            return 'Straight-line distance between visit coordinates (Haversine). Monitoring only.';
        }
        if (this._distanceKmSource === 'pending') {
            return 'Straight-line interim total; replacing with driving distance from Google Directions when the map responds.';
        }
        if (this._distanceKmSource === 'fallback') {
            return 'Straight-line distance between tracked coordinates (Google Directions unavailable for this route).';
        }
        return 'Driving distance from Google Directions (summed legs along the plotted route).';
    }

    get userSearchControlClass() {
        const base =
            'slds-form-element__control slds-input-has-icon slds-input-has-icon_left';
        return this.showUserClearButton ? `${base} slds-input-has-icon_right` : base;
    }

    get showUserClearButton() {
        const hasText = Boolean((this.userSearchText || '').trim());
        return hasText || Boolean(this.selectedUserId);
    }

    handleDateChange(event) {
        this.selectedDate = event.target.value ?? '';
    }

    handleClearUserSearch() {
        this.userSearchText = '';
        this.selectedUserId = undefined;
        this.isUserDropdownOpen = false;

        requestAnimationFrame(() => {
            const input = this.template.querySelector('#userSearchInput');
            if (input && typeof input.focus === 'function') {
                input.focus();
            }
        });
    }

    handleUserSearchInput(event) {
        this.userSearchText = event.target.value;
        this.isUserDropdownOpen = true;
    }

    handleUserSearchFocus() {
        this.isUserDropdownOpen = Boolean((this.userSearchText || '').trim());
    }

    handleUserPick(event) {
        const userId = event.currentTarget?.dataset?.userid;
        if (!userId) return;

        const user = (this.users || []).find((u) => u.userId === userId);
        this.selectedUserId = userId;
        this.userSearchText = user?.userName || this.userSearchText;
        this.isUserDropdownOpen = false;
    }

    handleLoad() {
        return this.loadDashboardData({ updateMap: false });
    }

    handleViewMapForSelected() {
        return this.loadDashboardData({ updateMap: true, scrollToMap: true });
    }

    async loadDashboardData(options = {}) {
        const updateMap = options.updateMap === true;
        const scrollToMap = options.scrollToMap === true;

        if (!this.selectedUserId || !this.selectedDate) {
            this.notifyError('Missing filters', 'Please select both user and date.');
            return;
        }

        if (this.isLoading) {
            return;
        }

        this.isLoading = true;
        try {
            const dashboard = await getDashboardData({
                userId: this.selectedUserId,
                selectedDate: this.selectedDate
            });

            const rowsResolved = this.mapActivitiesToRows(dashboard?.activities);
            const summaryResolved = dashboard?.summary || { ...EMPTY_SUMMARY };
            const hadLifecycleRows = Array.isArray(rowsResolved) && rowsResolved.length > 0;
            const rawRowCountForDay = Number(summaryResolved.rawRowCount ?? 0);

            this.rows = rowsResolved;
            this.summary = summaryResolved;

            const path = this.expandPathForRouting(this.buildLatLngPath(this.rows));
          
            //Fallback Haversine Formula distance for when Google Directions fails or is unavailable; also used as interim distance when waiting on map response to cover VF embed load delays and LEX nested iframe timing issues.
            this._fallbackCrowDistanceKm = roundDistanceKm(this.computePathDistanceKm(path));

            if (this._routingMode === 'haversine') {
                this.totalDistanceKm = this._fallbackCrowDistanceKm;
                this._distanceKmSource = 'haversine';
            } else if (
                hadLifecycleRows &&
                Array.isArray(path) &&
                path.length >= 2 &&
                this.mapEmbedUrl
            ) {
                this.totalDistanceKm = this._fallbackCrowDistanceKm;
                this._distanceKmSource = 'pending';
            } else {
                this.totalDistanceKm = this._fallbackCrowDistanceKm;
                if (hadLifecycleRows && path.length >= 2 && !this.mapEmbedUrl) {
                    this._distanceKmSource = 'fallback';
                } else {
                    this._distanceKmSource = 'road';
                }
            }

            if (hadLifecycleRows) {
                this.notifyLoadSuccess();
            } else if (rawRowCountForDay > 0) {
                this.notifyLifecycleWindowEmpty();
            } else {
                await this.clearUserSelectionAfterNoData();
                this.notifyNoDataForSelection();
            }

            try {
                if (!hadLifecycleRows) {
                    this._mapDisplayMode = 'idle';
                    this._resetMapToIdleMessage();
                } else if (updateMap) {
                    this._mapDisplayMode = 'route';
                    this.syncMapEmbedView();
                } else {
                    this.parkMapEmbedForTableOnly();
                }
            } catch (mapErr) {
                this.notifyError('Map', this.reduceError(mapErr));
            }

            if (hadLifecycleRows && scrollToMap) {
                requestAnimationFrame(() => {
                    requestAnimationFrame(() => this.scrollMapSectionIntoView());
                });
            }
        } catch (e) {
            this.rows = [];
            this.summary = { ...EMPTY_SUMMARY };
            this.totalDistanceKm = 0;
            this._fallbackCrowDistanceKm = 0;
            this._distanceKmSource = this._defaultDistanceKmSource();
            this._resetMapToIdleMessage();
            this.notifyError('Failed to load tracking data', this.reduceError(e));
        } finally {
            this.isLoading = false;
        }
    }

    scrollMapSectionIntoView() {
        const mapEl = this.template.querySelector('[data-id="map"]');
        if (mapEl && typeof mapEl.scrollIntoView === 'function') {
            mapEl.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }

    notifyLoadSuccess() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: 'Data was fetched successfully.',
                variant: 'success',
                mode: 'dismissable'
            })
        );
    }

    notifyLifecycleWindowEmpty() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'No route from attendance',
                message:
                    'Activity exists for this day but nothing falls on or after the first attendance mark.',
                variant: 'warning',
                mode: 'dismissable'
            })
        );
    }

    notifyNoDataForSelection() {
        this.notifyError(
            'No data',
            'There is no data to display for the selected user and date.'
        );
    }

    notifyError(title, message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant: 'error',
                mode: 'dismissable'
            })
        );
    }

    reduceError(err) {
        if (!err) return 'Unknown error';
        if (Array.isArray(err.body)) return err.body.map((e) => e.message).join(', ');
        if (typeof err.body?.message === 'string') return err.body.message;
        if (typeof err.message === 'string') return err.message;
        return 'Unknown error';
    }

    formatNumber(value, options = {}) {
        const n = Number(value || 0);
        return new Intl.NumberFormat(undefined, {
            maximumFractionDigits: 2,
            ...options
        }).format(n);
    }
}