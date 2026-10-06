import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getObjectOptions from '@salesforce/apex/ArchivedRecordsController.getObjectOptions';
import searchArchivedRecords from '@salesforce/apex/ArchivedRecordsController.searchArchivedRecords';
import getArchivedRecordCount from '@salesforce/apex/ArchivedRecordsController.getArchivedRecordCount';

const RANGE_CUSTOM = 'CUSTOM';

/**
 * No date range. The default on load and after Reset, so nothing is fetched
 * until the user asks for something: Apply then needs either a real range or a
 * parent search term (see validateFilters).
 */
const RANGE_NONE = 'NONE';

/**
 * The report filters on archived date only. The "Dates apply to" choice was
 * removed; this is passed to the count explicitly so the rollup it reads is
 * never ambiguous.
 */
const DATE_BASIS_ARCHIVED = 'ARCHIVED';

/** Synthetic column the controller adds; redundant with one object selected. */
const OBJECT_COLUMN = '_objectLabel';

/** Shortest parent search accepted - matches the controller's own check. */
const MIN_PARENT_SEARCH_LENGTH = 2;

/**
 * Rows per page, fixed.
 *
 * The picker that used to set this is gone. The archive pages by continuation
 * token, not by offset, so one page is one callout whatever its size - asking
 * for fewer rows costs the same round trip and only moves the page boundaries,
 * which then invalidates every token already collected.
 */
const PAGE_SIZE = 200;

/**
 * Hard ceiling on the width of a date range, in days.
 *
 * Dates are not indexed in the archive - only PartitionKey is - so every date
 * filter is a table scan, and a wide one either times out or trips the read
 * service's six-hop scan budget and comes back as an unfinished search. Ninety
 * days is the widest window that reliably completes, so the longer presets were
 * removed and Custom is validated against the same limit.
 *
 * Measured as the gap between the two dates, not the inclusive day count, so
 * that the Last 90 days preset - which spans exactly 90 days - passes its own
 * rule rather than failing it by one.
 */
const MAX_RANGE_DAYS = 90;
const MS_PER_DAY = 86400000;

/** The Last week preset: the seven days before today, through today. */
const RANGE_LAST_WEEK = 'LAST_WEEK';

/**
 * Smallest useful table area, in pixels. Below about this the table shows one
 * row and the scrollbar, which is worse than letting the page scroll a little.
 */
const MIN_TABLE_HEIGHT = 160;

/** Breathing room under the card footer so it does not sit flush on the edge. */
const BOTTOM_GUTTER = 24;

/**
 * How often to ask how the count is getting on, in milliseconds.
 *
 * The count runs as a chain of Apex jobs - it has to, because the archive has no
 * row count and one transaction cannot read a million rows - so its progress is
 * only visible by polling. Three seconds is frequent enough that the number looks
 * live and slow enough that a four-minute count costs eighty requests, not
 * thousands.
 */
const COUNT_POLL_MS = 3000;

/**
 * Give up only after this long with the total not moving at all.
 *
 * Deliberately measured against progress rather than elapsed time. The first
 * version stopped watching after fifteen minutes of wall clock, which turned out
 * to be far too strict: counting the 9.65M archived Order Line Items takes about
 * thirty-five minutes, because it is ten thousand callouts and the archive
 * cannot go faster. A healthy count was being abandoned three-quarters of the
 * way through, so the number never appeared.
 *
 * A count that is still counting should be watched however long it takes. Only
 * one that has stopped moving is dead, and that is what this detects.
 */
const COUNT_STALL_TIMEOUT_MS = 4 * 60 * 1000;

/**
 * Absolute ceiling, as a last resort. Above any real count - the largest
 * measured is ~35 minutes - and only reached if progress somehow keeps ticking
 * without ever completing.
 */
const COUNT_POLL_TIMEOUT_MS = 2 * 60 * 60 * 1000;

export default class ArchivedRecordsReport extends LightningElement {
    @track objectOptions = [];
    @track columns = [];
    @track rows = [];

    /** One object at a time - the API name of the selected object. */
    selectedObject;
    /** Parent name, number or record Id, for objects that support parent search. */
    parentSearch = '';
    /** None by default: nothing is fetched until the user gives a criterion. */
    selectedRange = RANGE_NONE;
    fromDate;
    toDate;

    pageNumber = 1;
    pageSize = PAGE_SIZE;
    /** Rows on the current page. The result-set total is archiveTotal, below. */
    totalCount = 0;
    totalPages = 0;

    /**
     * Continuation tokens, indexed by the page they open.
     *
     * cursors[0] is always null - page one needs no token - and cursors[n] is the
     * token handed back when page n was fetched, which opens page n+1. The stack
     * exists because archive paging is forward-only: there is no token that walks
     * backwards and no page-by-number to fall back on, so the only way to return
     * to an earlier page is to still be holding the token that opened it.
     */
    cursors = [null];
    hasMore = false;
    tokenPaged = false;

    /**
     * The result-set total, from its own round trip. Separate from totalCount,
     * which on a token-paged read is only the rows on screen.
     */
    archiveTotal = 0;
    countComplete = false;
    countFailed = false;
    countError;
    countDegraded = false;
    isCounting = false;
    hasCount = false;
    countBuilding = false;
    countCalloutsUsed = 0;
    countPollStartedAt = 0;
    countLastProgressAt = 0;
    countLastTotal = -1;

    sortedBy;
    sortedDirection = 'desc';

    isLoading = false;
    isDegraded = false;
    degradedReason;
    errorMessage;
    hasRun = false;

    // The archive reports no row count, so totalCount is exact only while the
    // result fits inside the row cap the controller pulls per run.
    isCapped = false;
    scanIncomplete = false;
    rowCap = 0;
    /** Latest archive run on record, used to explain an empty result. */
    lastArchiveActivity;
    @track unavailableObjects = [];

    /** Seconds the current read has been running, for the loading panel. */
    loadingSeconds = 0;

    // Filters actually used for the current result set, so paging does not pick up
    // edits the user has made but not applied yet.
    appliedFilters;

    connectedCallback() {
        this.applyRangePreset(this.selectedRange);

        this.refitTable = () => this.fitTableToViewport();
        window.addEventListener('resize', this.refitTable);
    }

    renderedCallback() {
        // Every render can change the height above the table - a notice appears,
        // the filter summary wraps - so the fit is recomputed rather than done
        // once. Setting an inline style does not itself trigger a re-render, so
        // this cannot loop.
        this.fitTableToViewport();
    }

    disconnectedCallback() {
        window.removeEventListener('resize', this.refitTable);
        this.stopLoadingClock();
        this.stopCountPolling();
    }

    /**
     * Sizes the table to whatever vertical space is actually left, so the card
     * footer - the pager and the rows-per-page picker - always lands on screen
     * and the page itself never scrolls.
     *
     * This replaces a CSS calc(100vh - <constant>). The constant had to stand for
     * the Lightning global header, the app nav bar, the sandbox banner, this
     * card's header, the filter bar and up to four conditional notices - a total
     * that varies by tens of pixels between orgs, screens and result states, so
     * any single value was wrong somewhere. Measuring the element's own position
     * is exact by construction.
     */
    fitTableToViewport() {
        const wrapper = this.template.querySelector('.table-wrapper');
        if (!wrapper) {
            return;
        }

        // Collapse first, then measure. getBoundingClientRect is viewport-relative,
        // so a page scrolled down would report a top that is too small and yield a
        // table too tall to fit - which is the very thing that caused the scroll.
        // At the minimum height there is nothing left to scroll, so the reading is
        // taken from a page that is already at rest.
        wrapper.style.height = `${MIN_TABLE_HEIGHT}px`;

        const top = wrapper.getBoundingClientRect().top;
        const footer = this.template.querySelector('.table-footer');
        const footerHeight = footer ? footer.getBoundingClientRect().height : 0;

        const available = window.innerHeight - top - footerHeight - BOTTOM_GUTTER;
        wrapper.style.height = `${Math.max(Math.round(available), MIN_TABLE_HEIGHT)}px`;
    }

    @wire(getObjectOptions)
    wiredObjectOptions({ data, error }) {
        if (data) {
            this.objectOptions = data.map((opt) => ({
                label: opt.label,
                value: opt.value,
                parentSearchLabel: opt.parentSearchLabel
            }));
            if (!this.selectedObject && this.objectOptions.length) {
                this.selectedObject = this.objectOptions[0].value;
            }
        } else if (error) {
            this.errorMessage = this.extractError(error);
        }
    }

    // ------------------------------------------------------------------ options

    /**
     * Nothing wider than MAX_RANGE_DAYS. The six-month, twelve-month, financial
     * year and All time presets were removed for the reason documented on that
     * constant: the archive cannot serve them, and offering them only produced
     * long scans that ended in an unfinished search.
     */
    get rangeOptions() {
        // Yesterday was removed: the daily archival run lands after the count
        // index was last rebuilt, so a one-day range on the newest day is the one
        // the index cannot plan, and it came back as an unfinished search.
        return [
            { label: '--None--', value: RANGE_NONE },
            { label: 'Last week', value: RANGE_LAST_WEEK },
            { label: 'Last 30 days', value: 'LAST_30' },
            { label: 'Last 90 days', value: 'LAST_90' },
            { label: 'Custom', value: RANGE_CUSTOM }
        ];
    }

    get rangeHelpText() {
        return (
            `Filters on the date each record was archived. Dates are not indexed in ` +
            `the archive, so a wide range has to scan the whole table. Choose Custom ` +
            `to pick your own window; only a ${MAX_RANGE_DAYS}-day range can be ` +
            `selected. Leave it as None to search by Order, Invoice or Visit across ` +
            `all archived dates.`
        );
    }

    // ------------------------------------------------------------------ objects

    get selectedObjectOption() {
        return this.objectOptions.find((opt) => opt.value === this.selectedObject);
    }

    /** Only Order Line Item, Invoice Line Item and Visit Task have a parent search. */
    get showParentSearch() {
        const option = this.selectedObjectOption;
        return !!(option && option.parentSearchLabel);
    }

    get parentSearchLabel() {
        const option = this.selectedObjectOption;
        return option && option.parentSearchLabel ? `Search by ${option.parentSearchLabel}` : '';
    }

    get parentSearchPlaceholder() {
        const option = this.selectedObjectOption;
        if (!option || !option.parentSearchLabel) {
            return '';
        }
        return option.parentSearchLabel === 'Invoice'
            ? 'Invoice number or record Id'
            : `${option.parentSearchLabel} name or record Id`;
    }

    get parentSearchHelpText() {
        const option = this.selectedObjectOption;
        const parent = option && option.parentSearchLabel ? option.parentSearchLabel : 'parent';
        const field = parent === 'Invoice' ? 'Invoice Number' : `${parent} Name`;
        return (
            `Shows only records whose ${field} contains what you type (not case-sensitive), ` +
            `or enter the ${parent}'s 15- or 18-character record Id. With the date range ` +
            `set to None, every archived date is searched and the ${field} is matched from ` +
            `its start - type it from the beginning, e.g. the full ${parent} number.`
        );
    }

    // Column classes for the filter row. From medium screens up the row is
    // 3 + 2 + 2 + 2 + 3 with the parent search shown and 3 + 3 + 3 + 3 without,
    // so it always sums to 12 and every filter stays on one line. Phones stack
    // the fields; small screens put them two to a row, as before. These are
    // class bindings, so the widths re-balance as soon as the object changes.
    filterColumnClass(mediumSize, smallSize) {
        return (
            'slds-col slds-size_1-of-1 ' +
            `slds-small-size_${smallSize}-of-12 slds-medium-size_${mediumSize}-of-12 ` +
            'slds-p-horizontal_small filter-field'
        );
    }

    get objectColumnClass() {
        return this.filterColumnClass(3, 6);
    }

    get rangeColumnClass() {
        return this.filterColumnClass(this.showParentSearch ? 2 : 3, 6);
    }

    get dateColumnClass() {
        return this.filterColumnClass(this.showParentSearch ? 2 : 3, 6);
    }

    get searchColumnClass() {
        return this.filterColumnClass(3, 6);
    }

    get isParentSearchApplied() {
        return !!(this.appliedFilters && this.appliedFilters.parentSearch);
    }

    // ------------------------------------------------------------------ state

    get isCustomRangeDisabled() {
        return this.selectedRange !== RANGE_CUSTOM;
    }

    get isApplyDisabled() {
        return this.isLoading || !this.selectedObject;
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    // ------------------------------------------------------------------ loading

    /** Full panel on a first run; a light overlay when paging an existing table. */
    get showLoadingPanel() {
        return this.isLoading && !this.hasRows;
    }

    get showInlineSpinner() {
        return this.isLoading && this.hasRows;
    }

    get loadingTitle() {
        return this.loadingSeconds >= 15
            ? 'Still searching the archive…'
            : 'Retrieving archived records from Azure…';
    }

    /** Says what is being fetched, so a long wait is at least legible. */
    get loadingDetail() {
        const filters = this.appliedFilters;
        if (!filters) {
            return 'Contacting the Azure archive.';
        }
        const range =
            filters.fromDate || filters.toDate
                ? `${filters.fromDate || 'the beginning'} to ${filters.toDate || 'today'}`
                : 'all dates';
        const parent = filters.parentSearch
            ? `, ${filters.parentLabel} "${filters.parentSearch}"`
            : '';
        return `${filters.objectLabel}${parent}, ${range}`;
    }

    /**
     * Sets expectations as the wait grows. Worded as what the archive is doing
     * rather than faked progress - there is no progress to report, since the read
     * is a single Apex round trip.
     */
    get loadingHint() {
        if (this.isParentSearchApplied && this.loadingSeconds >= 6) {
            return (
                `The archive cannot look records up by ${this.appliedFilters.parentLabel}, ` +
                'so rows are read in batches and matched. Narrowing the date range is much faster.'
            );
        }
        if (this.loadingSeconds >= 15) {
            return (
                'Dates are not indexed in the archive, so this range has to scan the ' +
                'whole table. Narrowing the range is much faster.'
            );
        }
        if (this.loadingSeconds >= 6) {
            return 'Wider date ranges take longer to search.';
        }
        return '';
    }

    get loadingElapsedLabel() {
        return this.loadingSeconds ? `${this.loadingSeconds}s elapsed` : '';
    }

    get showEmptyState() {
        // An unfinished scan has its own notice: "nothing found yet" is not "nothing".
        return (
            this.hasRun &&
            !this.isLoading &&
            !this.rows.length &&
            !this.errorMessage &&
            !this.scanIncomplete
        );
    }

    get showInitialState() {
        return !this.hasRun && !this.isLoading && !this.errorMessage;
    }

    get isFirstPage() {
        return this.isLoading || this.pageNumber <= 1;
    }

    /**
     * On a token-paged read the archive itself says whether there is more, since
     * there is no total to compare a page number against. The log fallback still
     * pages by offset and does know its own length.
     */
    get isLastPage() {
        if (this.isLoading) {
            return true;
        }
        return this.tokenPaged ? !this.hasMore : this.pageNumber >= this.totalPages;
    }

    /**
     * Total pages for the current result, or null when it cannot honestly be known.
     *
     * - Offset-paged reads (the Archival Log fallback) know their own span.
     * - A token-paged read on its last page knows it: this page is the last one.
     * - Otherwise the span comes from the completed count - the archive itself
     *   reports none - divided into pages. The count and the rows now come from
     *   the same day-by-day plan, and every page but the last is filled to
     *   pageSize, so the arithmetic matches the pages Next actually produces.
     *   It is still clamped to at least one more page than this one while the
     *   archive says there is more, so the label can never claim "3 to 3" with
     *   Next still enabled.
     * - Unknown while the count is still running or has failed, and always for a
     *   parent search, which the count cannot answer (it counts days, not parents).
     */
    get knownTotalPages() {
        if (!this.tokenPaged) {
            return this.totalPages || null;
        }
        if (!this.hasMore) {
            return this.pageNumber;
        }
        if (
            this.isParentSearchApplied ||
            !this.hasCount ||
            !this.countComplete ||
            this.countFailed
        ) {
            return null;
        }
        const fromCount = Math.ceil(this.archiveTotal / this.pageSize);
        return Math.max(fromCount, this.pageNumber + 1);
    }

    /**
     * "Page 1 to 3 · 553 record(s) total". The '+' marks a total the archive
     * could only give us as a floor. When the page count cannot be known yet the
     * label says why rather than inventing a number.
     */
    get paginationLabel() {
        if (!this.hasRows) {
            return '';
        }
        const totalPages = this.knownTotalPages;
        const pages = totalPages
            ? `Page ${this.pageNumber} to ${totalPages}`
            : `Page ${this.pageNumber}`;

        if (this.tokenPaged) {
            // A parent search has no total above the table - the rollup counts
            // days, not parents - so say how many matched on this page instead.
            if (this.isParentSearchApplied) {
                return (
                    `${pages} · ${this.totalCount.toLocaleString()} ` +
                    `matching record(s) on this page`
                );
            }
            if (totalPages) {
                return pages;
            }
            return this.isCounting
                ? `${pages} · counting total pages…`
                : `${pages} · more pages available`;
        }
        const total = `${this.totalCount.toLocaleString()}${this.isCapped ? '+' : ''}`;
        return `${pages} · ${total} record(s) total`;
    }

    // ------------------------------------------------------------------- count

    /** Not for a parent search: the rollup is tallied per day and cannot answer it. */
    get showCountBar() {
        return (
            this.hasRun && !this.isParentSearchApplied && (this.isCounting || this.hasCount)
        );
    }

    /**
     * The headline number between the filters and the table.
     *
     * A running count shows its progress, but never as if it were the answer -
     * it is a floor that is still growing, and the wording says so. Only a
     * completed count is rendered as a plain total.
     */
    get countLabel() {
        if (this.countFailed) {
            return 'Count unavailable';
        }
        if (!this.hasCount && this.isCounting) {
            return 'Indexing the archive…';
        }
        if (!this.hasCount) {
            return '';
        }
        const total = this.archiveTotal.toLocaleString();
        if (this.countComplete) {
            return `${total} archived record${this.archiveTotal === 1 ? '' : 's'}`;
        }
        return `Indexing… ${total} so far`;
    }

    /** Context for anything other than a finished, exact count. */
    get countQualifier() {
        if (this.countFailed) {
            return (
                this.countError ||
                'The count could not be completed. The rows below are unaffected.'
            );
        }
        if (this.countComplete) {
            return '';
        }
        if (this.isCounting || this.hasCount) {
            return (
                'Azure Table Storage has no count operation, so totals come from an ' +
                'index of rows per day that is built by reading the archive once. ' +
                'That build is running now and takes about half an hour; after it, ' +
                'any date range totals instantly. The table below is already complete.'
            );
        }
        return '';
    }

    get hasCountQualifier() {
        return this.countQualifier !== '';
    }

    /** A spinner next to the number while the chain is still running. */
    get showCountSpinner() {
        return this.isCounting && !this.countComplete && !this.countFailed;
    }

    // ------------------------------------------------------------------ notices

    get showCappedNotice() {
        return this.isCapped && !this.scanIncomplete && !this.isDegraded;
    }

    get showScanIncompleteNotice() {
        return this.scanIncomplete && !this.isDegraded;
    }

    /**
     * A read that has found nothing yet but has more archive to read - with or
     * without a parent search. The pager lives in the footer, which only renders
     * with rows, so the notice carries its own way forward.
     */
    get showSearchFurther() {
        return this.tokenPaged && this.hasMore && !this.hasRows && !this.isLoading;
    }

    /**
     * What an unfinished scan means - which depends entirely on whether it found
     * anything, and the two cases need opposite advice.
     *
     * A scan that found rows was cut short, and narrowing the range finishes it.
     * A scan that found NOTHING cannot be helped by narrowing - the range may
     * already be a single day - and the real answer is almost always that nothing
     * was archived then. Telling someone who picked "Today" to narrow their range
     * is the advice that made an empty day look like a broken report.
     */
    get scanIncompleteMessage() {
        if (this.isParentSearchApplied && !this.totalCount) {
            const { parentLabel, parentSearch } = this.appliedFilters;
            return (
                `No records linked to ${parentLabel} "${parentSearch}" have been found in the ` +
                `part of the archive searched so far. The archive cannot look records up by ` +
                `${parentLabel} directly, so it is read in batches and matched here. Select ` +
                `Search further to keep looking, or narrow the date range.`
            );
        }
        if (this.totalCount) {
            return (
                `Found ${this.totalCount.toLocaleString()} so far, but there may be more. ` +
                `Dates are not indexed in the archive, so a wide range has to scan the ` +
                `whole table and this one did not finish. Narrow the date range to ` +
                `complete the search.`
            );
        }
        const next = this.showSearchFurther
            ? 'Select Search further to keep looking from where this search stopped. '
            : '';
        return (
            'No archived records have been found in this date range yet. Dates are not ' +
            'indexed in the archive, so ruling a range out means scanning the whole table, ' +
            'and that did not finish — which is why this took a while to report. ' +
            next +
            this.archiveActivityHint
        );
    }

    /**
     * Points at a range that does hold data. Without it an empty result leaves
     * the user trying neighbouring dates one at a time, at thirty seconds each.
     */
    get archiveActivityHint() {
        if (this.lastArchiveActivity) {
            return (
                `The most recent archive run on record was ${this.lastArchiveActivity}. ` +
                `Records are only archived on the days a run happens, so a range that ` +
                `does not include one will be empty — try a range covering that date.`
            );
        }
        return (
            'Records are only archived on the days an archival run happens, so a range ' +
            'that does not include one will be empty.'
        );
    }

    get emptyStateMessage() {
        if (this.isParentSearchApplied) {
            const { parentLabel, parentSearch } = this.appliedFilters;
            return (
                `No archived records linked to ${parentLabel} "${parentSearch}" were found in ` +
                `this date range. Check the ${parentLabel} name, number or record Id, or try a ` +
                `different date range. ${this.archiveActivityHint}`
            );
        }
        return `Nothing matched this object and date range. ${this.archiveActivityHint}`;
    }

    get cappedMessage() {
        const cap = (this.rowCap || this.totalCount).toLocaleString();
        return (
            `More than ${cap} archived records match these filters. The archive does not ` +
            `report a row count, so this run shows the first ${cap} it returned — in archive ` +
            `storage order, not date order. Narrow the date range for a complete, ` +
            `newest-first result.`
        );
    }

    get hasUnavailableObjects() {
        return this.unavailableObjects.length > 0;
    }

    get unavailableMessage() {
        return (
            `Not shown: ${this.unavailableObjects.join(', ')}. The archive has no retrieval ` +
            `route published for these yet, so they contribute no rows and are excluded from ` +
            `the count.`
        );
    }

    get filterSummary() {
        if (!this.appliedFilters) {
            return '';
        }
        const { fromDate, toDate, objectLabel, parentLabel, parentSearch } = this.appliedFilters;
        const range = fromDate || toDate
            ? `${fromDate || 'the beginning'} to ${toDate || 'today'}`
            : 'all dates';
        const parent = parentSearch ? ` Linked to ${parentLabel} "${parentSearch}".` : '';
        return `${objectLabel}, filtered on archived date, ${range}.${parent}`;
    }

    // ------------------------------------------------------------------ handlers

    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        // The search box means something different per object - an Order number
        // is not a Visit - so a term typed for one never carries over to another.
        this.parentSearch = '';
    }

    handleParentSearchChange(event) {
        this.parentSearch = event.detail.value || '';
    }

    /** Enter in the search box runs the report, as a search box is expected to. */
    handleParentSearchKeyUp(event) {
        if (event.key === 'Enter' && !this.isApplyDisabled) {
            this.handleApply();
        }
    }

    handleRangeChange(event) {
        this.selectedRange = event.detail.value;
        this.applyRangePreset(this.selectedRange);
        this.checkRangeWidth();
    }

    handleFromDateChange(event) {
        this.fromDate = event.detail.value;
        this.checkRangeWidth();
    }

    handleToDateChange(event) {
        this.toDate = event.detail.value;
        this.checkRangeWidth();
    }

    /** The message shown when a range is wider than MAX_RANGE_DAYS. */
    get rangeTooWideMessage() {
        return `Only a ${MAX_RANGE_DAYS}-day range can be selected.`;
    }

    /** True when both dates are set and further apart than MAX_RANGE_DAYS. */
    get isRangeTooWide() {
        return Boolean(this.fromDate && this.toDate) && this.rangeDays() > MAX_RANGE_DAYS;
    }

    /**
     * Shows the range limit on the To date as soon as the range goes over it,
     * rather than only when Apply is pressed, and clears it once the range fits.
     * Only Custom can go over - every preset sits within the limit - and the
     * fields are disabled otherwise, so the message is cleared for presets.
     */
    checkRangeWidth() {
        const toInput = this.template.querySelector('lightning-input[data-id="toDate"]');
        if (!toInput) {
            return;
        }
        const tooWide = this.selectedRange === RANGE_CUSTOM && this.isRangeTooWide;
        toInput.setCustomValidity(tooWide ? this.rangeTooWideMessage : '');
        toInput.reportValidity();
    }

    handleApply() {
        if (!this.validateFilters()) {
            return;
        }
        this.pageNumber = 1;
        // New filters invalidate every token: they were issued against the old
        // query and mean nothing against this one.
        this.cursors = [null];

        const option = this.selectedObjectOption;
        const parentSearch = this.showParentSearch ? (this.parentSearch || '').trim() : '';
        this.appliedFilters = {
            objectApiName: this.selectedObject,
            objectLabel: option ? option.label : this.selectedObject,
            parentSearch,
            parentLabel: parentSearch ? option.parentSearchLabel : undefined,
            fromDate: this.fromDate,
            toDate: this.toDate
        };
        this.loadPage();
        if (parentSearch) {
            // Nothing to count: a leftover total from the last run would be wrong.
            this.resetCountState();
        } else {
            this.loadCount(false);
        }
    }

    handleRefresh() {
        if (!this.appliedFilters) {
            this.handleApply();
            return;
        }
        this.loadPage();
        // Refresh means "go and look again", so a cached total is discarded.
        if (!this.isParentSearchApplied) {
            this.loadCount(true);
        }
    }

    handleReset() {
        this.selectedRange = RANGE_NONE;
        this.applyRangePreset(this.selectedRange);
        this.checkRangeWidth();
        this.selectedObject = this.objectOptions.length ? this.objectOptions[0].value : undefined;
        this.parentSearch = '';
        this.rows = [];
        this.columns = [];
        this.totalCount = 0;
        this.totalPages = 0;
        this.pageNumber = 1;
        this.cursors = [null];
        this.hasMore = false;
        this.tokenPaged = false;
        this.resetCountState();
        this.appliedFilters = undefined;
        this.errorMessage = undefined;
        this.isDegraded = false;
        this.isCapped = false;
        this.scanIncomplete = false;
        this.rowCap = 0;
        this.unavailableObjects = [];
        this.hasRun = false;
        this.sortedBy = undefined;
    }

    handlePrevious() {
        if (this.pageNumber > 1) {
            // The token for this page is already in the stack, so going back is a
            // re-read of a page we have the key to - not a backwards walk, which
            // the archive cannot do.
            this.pageNumber -= 1;
            this.loadPage();
        }
    }

    handleNext() {
        if (this.isLastPage) {
            return;
        }
        this.pageNumber += 1;
        this.loadPage();
    }

    /**
     * Sorts the rows currently on screen. Server-side ordering is not part of the
     * archive read contract, so this is page-local and labelled as such.
     */
    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        const multiplier = sortDirection === 'asc' ? 1 : -1;
        const sorted = [...this.rows].sort((a, b) => {
            const valueA = a[fieldName];
            const valueB = b[fieldName];
            if (valueA === valueB) return 0;
            if (valueA === null || valueA === undefined) return 1;
            if (valueB === null || valueB === undefined) return -1;
            return valueA > valueB ? multiplier : -multiplier;
        });
        this.rows = sorted;
        this.sortedBy = fieldName;
        this.sortedDirection = sortDirection;
    }

    // ------------------------------------------------------------------ data

    startLoadingClock() {
        this.stopLoadingClock();
        this.loadingSeconds = 0;
        this.loadingClock = setInterval(() => {
            this.loadingSeconds += 1;
        }, 1000);
    }

    stopLoadingClock() {
        if (this.loadingClock) {
            clearInterval(this.loadingClock);
            this.loadingClock = undefined;
        }
    }

    loadPage() {
        this.isLoading = true;
        this.errorMessage = undefined;
        this.startLoadingClock();

        const filters = this.appliedFilters;

        searchArchivedRecords({
            objectApiName: filters.objectApiName,
            fromDate: filters.fromDate,
            toDate: filters.toDate,
            pageSize: this.pageSize,
            pageNumber: this.pageNumber,
            // The token that opens this page. Null for page one, and null too if
            // the stack has been cleared by a filter change.
            continuation: this.cursors[this.pageNumber - 1] || null,
            parentSearch: filters.parentSearch || null
        })
            .then((page) => {
                // Columns follow the selected object; the Object column is dropped
                // because with one object it would repeat the same value on every row.
                this.columns = (page.columns || [])
                    .filter((col) => col.fieldName !== OBJECT_COLUMN)
                    .map((col) => ({
                        label: col.label,
                        fieldName: col.fieldName,
                        type: col.type,
                        sortable: col.sortable,
                        hideDefaultActions: true,
                        wrapText: false,
                        // Every column left-aligned, numbers and currency included:
                        // the datatable right-aligns those by default.
                        cellAttributes: { alignment: 'left' }
                    }));
                this.rows = page.rows || [];
                this.totalCount = page.totalCount || 0;
                this.totalPages = page.totalPages || 0;
                this.isDegraded = page.degraded === true;
                this.degradedReason = page.degradedReason;
                this.isCapped = page.isCapped === true;
                this.scanIncomplete = page.scanIncomplete === true;
                this.rowCap = page.rowCap || 0;
                this.lastArchiveActivity = page.lastArchiveActivity;
                this.unavailableObjects = page.unavailableObjects || [];
                this.tokenPaged = page.tokenPaged === true;
                this.hasMore = page.hasMore === true;

                // Remember how to reach the page after this one. Written by index
                // rather than pushed, so re-reading a page already visited
                // overwrites its entry instead of growing the stack.
                if (page.nextContinuation) {
                    this.cursors[this.pageNumber] = page.nextContinuation;
                }

                this.sortedBy = undefined;
                this.hasRun = true;
            })
            .catch((error) => {
                this.rows = [];
                this.columns = [];
                this.totalCount = 0;
                this.totalPages = 0;
                this.isCapped = false;
                this.scanIncomplete = false;
                this.hasMore = false;
                this.unavailableObjects = [];
                this.hasRun = true;
                this.errorMessage = this.extractError(error);
            })
            .finally(() => {
                this.isLoading = false;
                this.stopLoadingClock();
            });
    }

    /**
     * Starts the count, then polls it to completion.
     *
     * Both halves are the same Apex call: it enqueues the work if there is none
     * in flight and reports progress either way. That is forced by the archive -
     * it publishes no row count, so a total means reading every matching row at a
     * thousand a callout, and one Apex transaction allows a hundred callouts.
     * A million rows therefore cannot be counted in the request that asks for
     * them; a chain of jobs does it and this watches.
     *
     * Deliberately independent of loadPage: the table is complete as soon as its
     * own single callout returns, and must not wait minutes for a number.
     *
     * A failure here is not raised as an error over the report. The rows on
     * screen are correct whether or not the total arrived, so the count line says
     * so and the rest of the page carries on.
     *
     * @param forceRecount discard any cached total and count again.
     */
    loadCount(forceRecount) {
        const filters = this.appliedFilters;
        if (!filters) {
            return;
        }

        this.stopCountPolling();
        this.isCounting = true;
        this.countFailed = false;
        this.countError = undefined;
        this.countPollStartedAt = Date.now();
        this.countLastProgressAt = Date.now();
        this.countLastTotal = -1;

        this.pollCount(filters, forceRecount === true);
    }

    pollCount(filters, forceRecount) {
        getArchivedRecordCount({
            objectApiNames: [filters.objectApiName],
            fromDate: filters.fromDate,
            toDate: filters.toDate,
            dateBasis: DATE_BASIS_ARCHIVED,
            forceRecount: forceRecount
        })
            .then((result) => {
                // A late reply from a superseded run must not overwrite the
                // current one - the user may have applied new filters while the
                // previous count was still going.
                if (this.appliedFilters !== filters) {
                    return;
                }

                this.archiveTotal = result.total || 0;
                this.countComplete = result.isComplete === true;
                this.countBuilding = result.isBuilding === true;
                this.countFailed = result.isFailed === true;
                this.countError = result.errorMessage;
                this.countDegraded = result.degraded === true;
                this.countCalloutsUsed = result.calloutsUsed || 0;
                this.hasCount = true;

                if (this.countComplete || this.countFailed) {
                    this.isCounting = false;
                    return;
                }

                // Any movement means the chain is alive, however slow.
                if (this.archiveTotal !== this.countLastTotal) {
                    this.countLastTotal = this.archiveTotal;
                    this.countLastProgressAt = Date.now();
                }

                const stalled = Date.now() - this.countLastProgressAt > COUNT_STALL_TIMEOUT_MS;
                const exhausted = Date.now() - this.countPollStartedAt > COUNT_POLL_TIMEOUT_MS;
                if (stalled || exhausted) {
                    this.isCounting = false;
                    this.countFailed = true;
                    this.countError =
                        'The count has stopped making progress and is no longer being ' +
                        'watched. The rows below are unaffected. Select Refresh to try again.';
                    return;
                }

                // Never force on a poll: forcing would restart the very count
                // being watched, and it would never finish.
                this.countTimer = setTimeout(() => {
                    this.pollCount(filters, false);
                }, COUNT_POLL_MS);
            })
            .catch((error) => {
                if (this.appliedFilters !== filters) {
                    return;
                }
                this.isCounting = false;
                this.countFailed = true;
                this.countError = this.extractError(error);
            });
    }

    stopCountPolling() {
        if (this.countTimer) {
            clearTimeout(this.countTimer);
            this.countTimer = undefined;
        }
        this.isCounting = false;
    }

    /** Stops any count in flight and clears the count bar. */
    resetCountState() {
        this.stopCountPolling();
        this.archiveTotal = 0;
        this.countComplete = false;
        this.countFailed = false;
        this.countError = undefined;
        this.countDegraded = false;
        this.countBuilding = false;
        this.hasCount = false;
        this.countCalloutsUsed = 0;
    }

    // ------------------------------------------------------------------ helpers

    validateFilters() {
        if (!this.selectedObject) {
            this.showToast('Select an object', 'Choose the archived object to report on.', 'warning');
            return false;
        }
        const term = this.showParentSearch ? (this.parentSearch || '').trim() : '';
        const hasRange = this.selectedRange !== RANGE_NONE;

        // At least one search criterion, or nothing is fetched: a date range, or
        // a term in the parent search for objects that have one.
        if (!hasRange && !term) {
            const parent = this.showParentSearch
                ? this.selectedObjectOption.parentSearchLabel
                : null;
            this.showToast(
                'Add a search criterion',
                parent
                    ? `Choose an archived date range, or enter a ${parent} to search by, ` +
                          `before selecting Apply.`
                    : 'Choose an archived date range before selecting Apply.',
                'warning'
            );
            return false;
        }

        if (term && term.length < MIN_PARENT_SEARCH_LENGTH) {
            const parent = this.selectedObjectOption.parentSearchLabel;
            this.showToast(
                'Search too short',
                `Enter at least ${MIN_PARENT_SEARCH_LENGTH} characters of the ${parent} ` +
                    `name, number or record Id, or clear the search.`,
                'error'
            );
            return false;
        }

        // No range, but a parent search term: search it across all dates. The
        // date checks below are about a range, and there is none to check.
        if (!hasRange) {
            return true;
        }

        // Every preset sets both dates, so a missing one means the user cleared a
        // Custom field. Left unchecked it would reach the archive as an unbounded
        // range, which is exactly what the day cap exists to prevent.
        if (!this.fromDate || !this.toDate) {
            this.showToast(
                'Enter both dates',
                'A From and a To date are both required.',
                'error'
            );
            return false;
        }
        if (this.fromDate > this.toDate) {
            this.showToast('Invalid date range', 'From date must be on or before To date.', 'error');
            return false;
        }
        if (this.isRangeTooWide) {
            this.checkRangeWidth();
            this.showToast(
                'Date range too wide',
                `${this.rangeTooWideMessage} The dates chosen span ${this.rangeDays()} days; ` +
                    `move the From or To date closer together.`,
                'error'
            );
            return false;
        }
        return true;
    }

    /** Days between the two selected dates; see MAX_RANGE_DAYS on the measure. */
    rangeDays() {
        const from = Date.parse(`${this.fromDate}T00:00:00Z`);
        const to = Date.parse(`${this.toDate}T00:00:00Z`);
        if (Number.isNaN(from) || Number.isNaN(to)) {
            return 0;
        }
        return Math.round((to - from) / MS_PER_DAY);
    }

    applyRangePreset(preset) {
        if (preset === RANGE_CUSTOM) {
            return;
        }
        if (preset === RANGE_NONE) {
            // No range: the From/To fields show empty (and stay disabled).
            this.fromDate = undefined;
            this.toDate = undefined;
            return;
        }

        const today = new Date();
        // Built from local date parts, not toISOString(): in IST (UTC+5:30) an
        // evening "today" converts to tomorrow's UTC date, which would have made
        // the presets end on the wrong day.
        const toIso = (date) =>
            `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(
                date.getDate()
            ).padStart(2, '0')}`;
        const daysAgo = (count) => {
            const shifted = new Date(today.getTime());
            shifted.setDate(shifted.getDate() - count);
            return shifted;
        };

        // Every preset is a rolling window ending today, and none of them exceed
        // MAX_RANGE_DAYS - the wider ones were removed rather than capped, since
        // a silently shortened "Last 12 months" would be worse than no option.
        const days = { [RANGE_LAST_WEEK]: 7, LAST_30: 30, LAST_90: 90 }[preset];
        if (days === undefined) {
            return;
        }
        this.fromDate = toIso(daysAgo(days));
        this.toDate = toIso(today);
    }

    extractError(error) {
        if (!error) {
            return 'Unknown error.';
        }
        if (error.body && error.body.message) {
            return error.body.message;
        }
        if (Array.isArray(error.body) && error.body.length) {
            return error.body[0].message;
        }
        return error.message || 'Unable to load archived records.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}