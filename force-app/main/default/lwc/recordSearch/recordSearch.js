import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getInitData from '@salesforce/apex/OrderInvoiceSearchController.getInitData';
import searchLookup from '@salesforce/apex/OrderInvoiceSearchController.searchLookup'; //Added by Hari - Record Search Error rectify
import searchRecords from '@salesforce/apex/OrderInvoiceSearchController.searchRecords';

const OBJ_PRIMARY_ORDER = 'Primary Order';
const OBJ_SECONDARY_ORDER = 'Secondary Order';
const OBJ_COUNTER_ORDER = 'Counter Order';
const OBJ_UNDER_SS_SECONDARY_ORDER = 'Under SS Secondary Order';
const OBJ_INVOICE = 'Invoice';
const OBJ_COLLECTION = 'Collection';
const OBJ_RETURN = 'Return';
const OBJ_DELIVERY_PLAN = 'Delivery Plan';

const INV_RT_PRIMARY = 'Primary Invoice';
const INV_RT_SECONDARY = 'Secondary Invoice';
const INV_RT_SECONDARY_UNDER_SS = 'Secondary Invoice Under SS';

const DIST_UNDER_SS = 'UNDER_SS';

const SEARCH_DEBOUNCE_MS = 300; //Added by Hari - Record Search Error rectify

const SERIAL_NUMBER_COLUMN = { label: 'S.No', fieldName: 'serialNumber', type: 'number', initialWidth: 70 };
const ORDER_NUMBER_COLUMN = {
    label: 'Order Number', fieldName: 'recordUrl', type: 'url',
    typeAttributes: { label: { fieldName: 'recordName' }, target: '_self' }
};
const INVOICE_NUMBER_COLUMN = {
    label: 'Invoice Number', fieldName: 'recordUrl', type: 'url',
    typeAttributes: { label: { fieldName: 'recordName' }, target: '_self' }
};
const ORDER_DATE_COLUMN = { label: 'Order Date', fieldName: 'recordDate', type: 'date-local' };
const INVOICE_DATE_COLUMN = { label: 'Invoice Date', fieldName: 'recordDate', type: 'date-local' };
const STATUS_COLUMN = { label: 'Status', fieldName: 'status', type: 'text' };
const GRN_STATUS_COLUMN = { label: 'GRN Status', fieldName: 'grnStatus', type: 'text' };
const INVOICE_CREATED_COLUMN = { label: 'Invoice Created', fieldName: 'invoiceCreated', type: 'text' };
const RETAILER_NAME_COLUMN = { label: 'Retailer Name', fieldName: 'retailerName', type: 'text' };
const BEAT_NAME_COLUMN = { label: 'Beat Name', fieldName: 'beatName', type: 'text' };
const ORDERED_BY_COLUMN = { label: 'Ordered By', fieldName: 'orderedBy', type: 'text' };
const UNDER_SS_NAME_COLUMN = { label: 'Under SS Name', fieldName: 'underSsName', type: 'text' };
const SUPER_STOCKIST_COLUMN = { label: 'Superstockist Name', fieldName: 'superStockistName', type: 'text' };
const TOTAL_QUANTITY_COLUMN = { label: 'Total Quantity', fieldName: 'totalQuantity', type: 'number' };
const TOTAL_ORDER_VALUE_COLUMN = { label: 'Total Order Value', fieldName: 'totalOrderValue', type: 'currency' };
const INVOICE_AMOUNT_COLUMN = { label: 'Invoice Amount', fieldName: 'invoiceAmount', type: 'currency' };
const COLLECTED_AMOUNT_COLUMN = { label: 'Collected Amount', fieldName: 'amountCollected', type: 'currency' };
const TOTAL_PAYABLE_BALANCE_COLUMN = { label: 'Total Payable Balance', fieldName: 'totalPayableBalance', type: 'currency' };

//Added by hari - Onclick Details
const PRIMARY_ORDER_COLUMNS = [
    SERIAL_NUMBER_COLUMN, ORDER_NUMBER_COLUMN, ORDER_DATE_COLUMN,
    STATUS_COLUMN, GRN_STATUS_COLUMN, TOTAL_QUANTITY_COLUMN, TOTAL_ORDER_VALUE_COLUMN
];
const PRIMARY_ORDER_UNDER_SS_COLUMNS = [
    SERIAL_NUMBER_COLUMN, ORDER_NUMBER_COLUMN, ORDER_DATE_COLUMN,
    STATUS_COLUMN, GRN_STATUS_COLUMN, TOTAL_QUANTITY_COLUMN, TOTAL_ORDER_VALUE_COLUMN,
    SUPER_STOCKIST_COLUMN
];
const SECONDARY_ORDER_COLUMNS = [
    SERIAL_NUMBER_COLUMN, ORDER_NUMBER_COLUMN, ORDER_DATE_COLUMN,
    RETAILER_NAME_COLUMN, BEAT_NAME_COLUMN, ORDERED_BY_COLUMN,
    STATUS_COLUMN, INVOICE_CREATED_COLUMN, TOTAL_QUANTITY_COLUMN, TOTAL_ORDER_VALUE_COLUMN
];
const UNDER_SS_SECONDARY_ORDER_COLUMNS = [
    SERIAL_NUMBER_COLUMN, ORDER_NUMBER_COLUMN, ORDER_DATE_COLUMN,
    UNDER_SS_NAME_COLUMN, BEAT_NAME_COLUMN, ORDERED_BY_COLUMN,
    STATUS_COLUMN, INVOICE_CREATED_COLUMN, TOTAL_QUANTITY_COLUMN, TOTAL_ORDER_VALUE_COLUMN
];
const PRIMARY_INVOICE_COLUMNS = [
    SERIAL_NUMBER_COLUMN, INVOICE_NUMBER_COLUMN, INVOICE_DATE_COLUMN,
    TOTAL_QUANTITY_COLUMN, TOTAL_ORDER_VALUE_COLUMN
];
const SECONDARY_INVOICE_COLUMNS = [
    SERIAL_NUMBER_COLUMN, INVOICE_NUMBER_COLUMN, INVOICE_DATE_COLUMN,
    RETAILER_NAME_COLUMN, STATUS_COLUMN, TOTAL_QUANTITY_COLUMN,
    INVOICE_AMOUNT_COLUMN, COLLECTED_AMOUNT_COLUMN, TOTAL_PAYABLE_BALANCE_COLUMN
];
const SECONDARY_UNDER_SS_INVOICE_COLUMNS = [
    SERIAL_NUMBER_COLUMN, INVOICE_NUMBER_COLUMN, INVOICE_DATE_COLUMN,
    STATUS_COLUMN, TOTAL_QUANTITY_COLUMN, TOTAL_ORDER_VALUE_COLUMN,
    SUPER_STOCKIST_COLUMN, COLLECTED_AMOUNT_COLUMN, TOTAL_PAYABLE_BALANCE_COLUMN
];

const SECONDARY_UNDER_SS_INVOICE_COLUMNS_FOR_SS = [
    SERIAL_NUMBER_COLUMN, INVOICE_NUMBER_COLUMN, INVOICE_DATE_COLUMN,
    STATUS_COLUMN, TOTAL_QUANTITY_COLUMN, TOTAL_ORDER_VALUE_COLUMN,
    UNDER_SS_NAME_COLUMN, COLLECTED_AMOUNT_COLUMN, TOTAL_PAYABLE_BALANCE_COLUMN
];

const COLLECTION_COLUMNS = [
    SERIAL_NUMBER_COLUMN,
    { label: 'Collection Name', fieldName: 'recordUrl', type: 'url',
        typeAttributes: { label: { fieldName: 'recordName' }, target: '_self' } },
    { label: 'Customer Name', fieldName: 'customerName', type: 'text' },
    { label: 'Invoice', fieldName: 'invoiceName', type: 'text' },
    { label: 'Payment Date', fieldName: 'recordDate', type: 'date-local' },
    { label: 'Payment Method', fieldName: 'paymentMethod', type: 'text' },
    { label: 'Amount Collected', fieldName: 'amountCollected', type: 'currency' }
];

const RETURN_COLUMNS = [
    SERIAL_NUMBER_COLUMN,
    { label: 'Returns Number', fieldName: 'recordUrl', type: 'url',
        typeAttributes: { label: { fieldName: 'recordName' }, target: '_self' } },
    { label: 'Customer Name', fieldName: 'customerName', type: 'text' },
    { label: 'Invoice', fieldName: 'invoiceName', type: 'text' },
    { label: 'Order', fieldName: 'orderName', type: 'text' },
    { label: 'Total Return Quantity', fieldName: 'returnQuantity', type: 'number' },
    { label: 'Total Return (Incl Tax)', fieldName: 'returnAmount', type: 'currency' }
];

const DELIVERY_PLAN_COLUMNS = [
    SERIAL_NUMBER_COLUMN,
    { label: 'Delivery Plan Name', fieldName: 'recordUrl', type: 'url',
        typeAttributes: { label: { fieldName: 'recordName' }, target: '_self' } },
    { label: 'Date', fieldName: 'recordDate', type: 'date-local' },
    { label: 'Driver Name', fieldName: 'driverName', type: 'text' },
    { label: 'Driver Number', fieldName: 'driverNumber', type: 'text' },
    { label: 'Vehicle Number', fieldName: 'vehicleNumber', type: 'text' }
];

export default class RecordSearch extends NavigationMixin(LightningElement) {
    @track isLoading = true;
    @track isSearching = false;
    @track initError;
    invoiceRecordTypeOptions = [];
    @track selectedInvoiceRecordType = '';

    distributorType; // SUPER_STOCKIEST | DIRECT_DISTRIBUTOR | UNDER_SS
    accountId;
    accountName;

    objectOptions = [];
    orderStatusOptions = [];
    counterOrderStatusOptions = [];
    invoiceStatusOptions = [];
    grnStatusOptions = [];

    @track selectedObject = '';
    @track fromDate = '';
    @track toDate = '';
    @track selectedStatus = '';
    @track selectedGrnStatus = '';
    @track selectedInvoiceCreated = '';
    @track selectedSearchAccountId;
    @track searchTerm = ''; //Added by Hari - Record Search Error rectify
    @track selectedSearchAccountLabel = ''; //Added by Hari - Record Search Error rectify
    @track lookupResults = []; //Added by Hari - Record Search Error rectify
    @track showLookupDropdown = false; //Added by Hari - Record Search Error rectify
    lookupSearchTimeout; //Added by Hari - Record Search Error rectify

    @track results = [];
    @track hasSearched = false;

    constructor() {
        super();
        console.log('Constructor called');
    }

    connectedCallback() {
        console.log('Connected Callback');
        this.loadInitData();
    }

    async loadInitData() {
        this.isLoading = true;
        try {
            const data = await getInitData();
            this.distributorType = data.distributorType;
            this.accountId = data.accountId;
            this.accountName = data.accountName;
            this.objectOptions = data.objectOptions;
            this.orderStatusOptions = data.orderStatusOptions;
            this.counterOrderStatusOptions = data.counterOrderStatusOptions;
            this.invoiceStatusOptions = data.invoiceStatusOptions;
            this.grnStatusOptions = data.grnStatusOptions;
            this.invoiceRecordTypeOptions = data.invoiceRecordTypeOptions;
        } catch (error) {
            console.error('Apex Error', error);
            console.log(JSON.stringify(error));
            this.initError = this.extractErrorMessage(error);
            this.showToast('Error', this.initError, 'error');
        } finally {
            console.log('Finally executed');
            this.isLoading = false;
        }
    }

    get isCollectionObject() {
        return this.selectedObject === OBJ_COLLECTION;
    }

    get isReturnObject() {
        return this.selectedObject === OBJ_RETURN;
    }

    get isDeliveryPlanObject() {
        return this.selectedObject === OBJ_DELIVERY_PLAN;
    }

    /*get showStatus() {
        return !this.isCollectionObject && !this.isReturnObject && !this.isDeliveryPlanObject;
    }*/

    get showStatus() {
        if (this.isCollectionObject || this.isReturnObject || this.isDeliveryPlanObject) {
            return false;
        }
        if (this.isInvoiceObject && this.selectedInvoiceRecordType === INV_RT_PRIMARY) {
            return false;
        }
        return true;
    }

    get showInvoiceRecordType() {
        return this.isInvoiceObject;
    }

    get invoiceRecordTypeComboOptions() {
        return [{ label: '-- Select Record Type --', value: '' }, ...this.invoiceRecordTypeOptions];
    }

    get isSuperStockiest() {
        return this.distributorType === 'SUPER_STOCKIEST';
    }

    get accountFieldLabel() {
        return this.isSuperStockiest ? 'Super Stockiest Account' : 'Distributor Account';
    }

    get searchFieldLabel() {
        return this.isSuperStockiest ? 'Search Retailer / Under SS' : 'Search Retailer';
    }

    get searchFieldPlaceholder() {
        return this.isSuperStockiest
            ? 'Search by Retailer/Distributor name or code…'
            : 'Search by Retailer name or code…';
    }

    get isInvoiceObject() {
        return this.selectedObject === OBJ_INVOICE;
    }

    get isPrimaryOrder() {
        return this.selectedObject === OBJ_PRIMARY_ORDER;
    }

    get isSecondaryOrder() {
        return this.selectedObject === OBJ_SECONDARY_ORDER;
    }

    get isUnderSsSecondaryOrder() {
        return this.selectedObject === OBJ_UNDER_SS_SECONDARY_ORDER;
    }

    get isUnderSsDistributor() {
        return this.distributorType === DIST_UNDER_SS;
    }

    get isSecondaryFamilyOrder() {
        return this.selectedObject === OBJ_SECONDARY_ORDER
            || this.selectedObject === OBJ_UNDER_SS_SECONDARY_ORDER;
    }

    get isGrnStatusDisabled() {
        return this.isInvoiceObject || this.isSecondaryFamilyOrder;
    }

    get isInvoiceCreatedDisabled() {
        return this.isInvoiceObject || this.isPrimaryOrder;
    }

    get currentStatusOptions() {
        let base;
        if (this.isInvoiceObject) {
            base = this.invoiceStatusOptions;
        } else if (this.isCounterOrder) {
            base = this.counterOrderStatusOptions;
        } else {
            base = this.orderStatusOptions;
        }
        return [{ label: '-- Any Status --', value: '' }, ...base];
    }

    get currentGrnStatusOptions() {
        return [{ label: '-- Any --', value: '' }, ...this.grnStatusOptions];
    }

    get invoiceCreatedOptions() {
        return [
            { label: '-- Any --', value: '' },
            { label: 'Invoice Created', value: 'Invoice Created' },
            { label: 'Invoice Not Created', value: 'Invoice Not Created' }
        ];
    }

    get columns() {
        if (this.isInvoiceObject) {
            if (this.selectedInvoiceRecordType === INV_RT_PRIMARY) {
                return PRIMARY_INVOICE_COLUMNS;
            }
            if (this.selectedInvoiceRecordType === INV_RT_SECONDARY) {
                return SECONDARY_INVOICE_COLUMNS;
            }
            if (this.selectedInvoiceRecordType === INV_RT_SECONDARY_UNDER_SS) {
                return this.isSuperStockiest ? SECONDARY_UNDER_SS_INVOICE_COLUMNS_FOR_SS : SECONDARY_UNDER_SS_INVOICE_COLUMNS;
            }
            return PRIMARY_INVOICE_COLUMNS;
        }
        if (this.isCollectionObject) {
            return COLLECTION_COLUMNS;
        }
        if (this.isReturnObject) {
            return RETURN_COLUMNS;
        }
        if (this.isDeliveryPlanObject) {
            return DELIVERY_PLAN_COLUMNS;
        }
        if (this.isPrimaryOrder) {
            return this.isUnderSsDistributor ? PRIMARY_ORDER_UNDER_SS_COLUMNS : PRIMARY_ORDER_COLUMNS;
        }
        if (this.isSecondaryOrder) {
            return SECONDARY_ORDER_COLUMNS;
        }
        if (this.isUnderSsSecondaryOrder) {
            return UNDER_SS_SECONDARY_ORDER_COLUMNS;
        }
        if (this.isCounterOrder) {
            return [
                SERIAL_NUMBER_COLUMN, ORDER_NUMBER_COLUMN, ORDER_DATE_COLUMN,
                RETAILER_NAME_COLUMN, STATUS_COLUMN, TOTAL_QUANTITY_COLUMN, TOTAL_ORDER_VALUE_COLUMN
            ];
        }
        return [SERIAL_NUMBER_COLUMN, ORDER_NUMBER_COLUMN, ORDER_DATE_COLUMN, STATUS_COLUMN];
    };

    get isApplyDisabled() {
        return !this.selectedObject || this.isSearching;
    }

    get hasResults() {
        return this.results && this.results.length > 0;
    }

    get showNoResults() {
        return this.hasSearched && !this.isSearching && !this.hasResults;
    }

    /*get showSearchAccountLookup() {
        return !!this.selectedObject
            && this.selectedObject !== OBJ_PRIMARY_ORDER
            && this.selectedObject !== OBJ_COUNTER_ORDER
            && this.selectedObject !== OBJ_COLLECTION
            && this.selectedObject !== OBJ_RETURN
            && this.selectedObject !== OBJ_DELIVERY_PLAN;
    }*/

    get showSearchAccountLookup() {
        if (!this.selectedObject) {
            return false;
        }
        if (this.selectedObject === OBJ_PRIMARY_ORDER
            || this.selectedObject === OBJ_COUNTER_ORDER
            || this.selectedObject === OBJ_DELIVERY_PLAN) {
            return false;
        }
        if (this.selectedObject === OBJ_INVOICE) {
            if (this.selectedInvoiceRecordType === INV_RT_PRIMARY) {
                return false;
            }
            if (this.isUnderSsDistributor && this.selectedInvoiceRecordType === INV_RT_SECONDARY_UNDER_SS) {
                return false;
            }
            return true;
        }
        return true;
    }

    get showLookupResults() { //Added by Hari - Record Search Error rectify
        return this.showLookupDropdown && this.lookupResults.length > 0;
    }

    get showLookupNoResults() { //Added by Hari - Record Search Error rectify
        return this.showLookupDropdown
            && this.lookupResults.length === 0
            && this.searchTerm
            && this.searchTerm.trim().length >= 2
            && !this.selectedSearchAccountId;
    }

    get lookupContainerClass() {
        return this.showLookupClearButton
            ? 'lookup-container lookup-container_selected'
            : 'lookup-container';
    }

    get showLookupClearButton() {
        return !!(this.searchTerm && this.searchTerm.trim().length > 0);
    }

    clearListedResults() {
        this.results = [];
        this.hasSearched = false;
    }

    /*handleInvoiceRecordTypeChange(event) {
        this.selectedInvoiceRecordType = event.detail.value;
        this.clearListedResults();
    }

    handleInvoiceRecordTypeChange(event) {
        this.selectedInvoiceRecordType = event.detail.value;
        if (!this.showSearchAccountLookup) {
            this.clearSearchAccountSelection();
        }
        this.clearListedResults();
    }*/

    handleInvoiceRecordTypeChange(event) {
        this.selectedInvoiceRecordType = event.detail.value;
        if (!this.showSearchAccountLookup) {
            this.clearSearchAccountSelection();
        }
        if (!this.showStatus) {
            this.selectedStatus = '';
        }
        this.clearListedResults();
    }

    handleSearchTermChange(event) { //Added by Hari - Record Search Error rectify
        const term = event.target.value;
        this.searchTerm = term;
        this.selectedSearchAccountId = undefined;
        this.selectedSearchAccountLabel = '';
        this.clearListedResults();

        window.clearTimeout(this.lookupSearchTimeout);

        if (!term || term.trim().length < 2) {
            this.lookupResults = [];
            this.showLookupDropdown = false;
            return;
        }

        this.lookupSearchTimeout = window.setTimeout(() => {
            this.runLookupSearch(term.trim());
        }, SEARCH_DEBOUNCE_MS);
    }

    async runLookupSearch(term) { //Added by Hari - Record Search Error rectify
        try {
            const results = await searchLookup({ searchTerm: term });
            this.lookupResults = (results || []).map((r) => ({
                ...r,
                displayLabel: r.code ? `${r.name} (${r.code})` : r.name
            }));
            this.showLookupDropdown = true;
        } catch (error) {
            this.lookupResults = [];
            this.showLookupDropdown = false;
            this.showToast('Error', this.extractErrorMessage(error), 'error');
        }
    }

    handleSelectLookupResult(event) { //Added by Hari - Record Search Error rectify
        const id = event.currentTarget.dataset.id;
        const selected = this.lookupResults.find((r) => r.id === id);
        if (!selected) {
            return;
        }
        this.selectedSearchAccountId = selected.id;
        this.selectedSearchAccountLabel = selected.displayLabel;
        this.searchTerm = selected.displayLabel;
        this.showLookupDropdown = false;
        this.lookupResults = [];
        this.clearListedResults();
    }

    clearSearchAccountSelection() { //Added by Hari - Record Search Error rectify
        this.selectedSearchAccountId = undefined;
        this.selectedSearchAccountLabel = '';
        this.searchTerm = '';
        this.lookupResults = [];
        this.showLookupDropdown = false;
    }

    handleClearSearchAccount() { //Added by Hari - Record Search Error rectify
        this.clearSearchAccountSelection();
        this.clearListedResults();
    }

    handleSearchBlur() {
        window.setTimeout(() => {
            this.showLookupDropdown = false;
        }, 200);
    }

    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.selectedStatus = '';
        if (!this.showGrnStatus) {
            this.selectedGrnStatus = '';
        }
        if (!this.showInvoiceCreated) {
            this.selectedInvoiceCreated = '';
        }
        if (!this.showInvoiceRecordType) {
            this.selectedInvoiceRecordType = '';
        }
        if (!this.showSearchAccountLookup) {
            this.clearSearchAccountSelection();
        }
        this.clearListedResults();
    }

    handleFromDateChange(event) {
        this.fromDate = event.detail.value;
        this.clearListedResults();
    }

    handleToDateChange(event) {
        this.toDate = event.detail.value;
        this.clearListedResults();
    }

    handleStatusChange(event) {
        this.selectedStatus = event.detail.value;
        this.clearListedResults();
    }

    handleGrnStatusChange(event) {
        this.selectedGrnStatus = event.detail.value;
        this.clearListedResults();
    }

    handleInvoiceCreatedChange(event) {
        this.selectedInvoiceCreated = event.detail.value;
        this.clearListedResults();
    }

    /*handleSearchTermChange(event) {
        const term = event.target.value;
        this.searchTerm = term;
        this.selectedSearchAccountId = undefined;

        window.clearTimeout(this.lookupSearchTimeout);

        if (!term || term.trim().length < 2) {
            this.lookupResults = [];
            this.showLookupDropdown = false;
            return;
        }

        this.lookupSearchTimeout = window.setTimeout(() => {
            this.runLookupSearch(term.trim());
        }, SEARCH_DEBOUNCE_MS);
    }

    async runLookupSearch(term) {
        try {
            const results = await searchLookup({ searchTerm: term });
            this.lookupResults = results.map((r) => ({
                ...r,
                displayLabel: r.code ? `${r.name} (${r.code})` : r.name
            }));
            this.showLookupDropdown = true;
        } catch (error) {
            this.showToast('Error', this.extractErrorMessage(error), 'error');
        }
    }

    handleSelectLookupResult(event) {
        const id = event.currentTarget.dataset.id;
        const selected = this.lookupResults.find((r) => r.id === id);
        if (!selected) {
            return;
        }
        this.selectedSearchAccountId = selected.id;
        this.selectedSearchAccountLabel = selected.displayLabel;
        this.searchTerm = selected.displayLabel;
        this.showLookupDropdown = false;
        this.lookupResults = [];
    }

    handleClearSearchAccount() {
        this.selectedSearchAccountId = undefined;
        this.selectedSearchAccountLabel = '';
        this.searchTerm = '';
        this.lookupResults = [];
        this.showLookupDropdown = false;
    }

    handleSearchBlur() {
        window.setTimeout(() => {
            this.showLookupDropdown = false;
        }, 200);
    }

    async handleApply() {
        if (!this.selectedObject) {
            this.showToast('Missing Object', 'Please select an Object before applying filters.', 'warning');
            return;
        }
        if (this.fromDate && this.toDate && this.fromDate > this.toDate) {
            this.showToast('Invalid Date Range', 'From Date cannot be after To Date.', 'warning');
            return;
        }

        this.isSearching = true;
        this.hasSearched = true;
        try {
            const searchPayload = JSON.parse(JSON.stringify({
                distributorType: this.distributorType || null,
                accountId: this.accountId || null,
                objectName: this.selectedObject || null,
                fromDate: this.fromDate || null,
                toDate: this.toDate || null,
                searchAccountId: this.selectedSearchAccountId || null,
                status: this.selectedStatus || null,
                grnStatus: this.showGrnStatus ? (this.selectedGrnStatus || null) : null,
                invoiceCreated: this.showInvoiceCreated ? (this.selectedInvoiceCreated || null) : null
            }));

            if (!searchPayload.objectName) {
                this.showToast('Missing Object', 'Please select an Object before applying filters.', 'warning');
                this.isSearching = false;
                this.hasSearched = false;
                return;
            }

            const records = await searchRecords({ filters: searchPayload });
            this.results = records.map((r) => ({
                ...r,
                recordUrl: `/${r.recordId}`
            }));
        } catch (error) {
            this.results = [];
            this.showToast('Search Error', this.extractErrorMessage(error), 'error');
        } finally {
            this.isSearching = false;
        }
    }*/

    async handleApply() {
        if (!this.selectedObject) {
            this.showToast('Missing Object', 'Please select an Object before applying filters.', 'warning');
            return;
        }
        console.log('isInvoiceObject:- ' , this.isInvoiceObject);
        console.log('selectedInvoiceRecordType:- ' , this.selectedInvoiceRecordType);
        if (this.isInvoiceObject && !this.selectedInvoiceRecordType) {
            this.showToast('Missing Record Type', 'Please select an Invoice Record Type before applying filters.', 'error');
            return;
        }
        if (this.fromDate && this.toDate && this.fromDate > this.toDate) {
            this.showToast('Invalid Date Range', 'From Date cannot be after To Date.', 'error');
            return;
        }

        this.isSearching = true;
        this.hasSearched = true;
        const searchedObject = this.selectedObject;
        try {
            const records = await searchRecords({
                objectName: this.selectedObject,
                fromDate: this.fromDate || null,
                toDate: this.toDate || null,
                searchAccountId: this.selectedSearchAccountId || null,
                status: this.showStatus ? (this.selectedStatus || null) : null,
                grnStatus: this.showGrnStatus ? (this.selectedGrnStatus || null) : null,
                invoiceCreated: this.showInvoiceCreated ? (this.selectedInvoiceCreated || null) : null,
                invoiceRecordType: this.showInvoiceRecordType ? (this.selectedInvoiceRecordType || null) : null
            });
            /*this.results = (records || []).map((r, index) => ({
                ...r,
                serialNumber: index + 1,
                recordUrl: this.buildRecordUrl(r, searchedObject)
            }));*/

            const withSerials = (records || []).map((r, index) => ({
                ...r,
                serialNumber: index + 1
            }));

            this.results = await this.attachRecordUrls(withSerials, searchedObject);
        } catch (error) {
            this.results = [];
            this.showToast('Search Error', this.extractErrorMessage(error), 'error');
        } finally {
            this.isSearching = false;
        }
    }

    get isCounterOrder() {
        return this.selectedObject === OBJ_COUNTER_ORDER;
    }

    get showGrnStatus() {
        return this.selectedObject === OBJ_PRIMARY_ORDER;
    }

    get showInvoiceCreated() {
        return this.isSecondaryFamilyOrder;
    }

    /*handleReset() {
        this.selectedObject = '';
        this.fromDate = '';
        this.toDate = '';
        this.selectedStatus = '';
        this.selectedGrnStatus = '';
        this.selectedInvoiceCreated = '';
        this.handleClearSearchAccount();
        this.results = [];
        this.hasSearched = false;
    }*/

    handleReset() {
        this.selectedObject = '';
        this.fromDate = '';
        this.toDate = '';
        this.selectedStatus = '';
        this.selectedGrnStatus = '';
        this.selectedInvoiceCreated = '';
        this.selectedInvoiceRecordType = '';
        this.clearSearchAccountSelection();
        this.results = [];
        this.hasSearched = false;
    }

    /*buildRecordUrl(record, objectName) {
        const slug = (record.recordName || '').toLowerCase().replace(/-/g, '');
        const prefix = this.getPagePrefix(objectName);
        return `/${prefix}/${record.recordId}/${slug}`;
    }

    getPagePrefix(objectName) {
        switch (objectName) {
            case OBJ_INVOICE:
                return 'invoice';
            case OBJ_COLLECTION:
                return 'collection';
            case OBJ_RETURN:
                return 'returns';
            case OBJ_DELIVERY_PLAN:
                return 'delivery-plan';
            default:
                return 'order';
        }
    }*/

    getObjectApiName(objectName) {
        switch (objectName) {
            case OBJ_INVOICE:
                return 'Invoice__c';
            case OBJ_COLLECTION:
                return 'Collection__c';
            case OBJ_RETURN:
                return 'Returns__c';
            case OBJ_DELIVERY_PLAN:
                return 'Delivery_Plan__c';
            default:
                return 'Order__c';
        }
    }

    async attachRecordUrls(records, objectName) {
        const objectApiName = this.getObjectApiName(objectName);
        const withUrls = await Promise.all(
            records.map(async (r) => {
                const url = await this[NavigationMixin.GenerateUrl]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: r.recordId,
                        objectApiName,
                        actionName: 'view'
                    }
                });
                return { ...r, recordUrl: url };
            })
        );
        return withUrls;
    }

    extractErrorMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        if (error && error.message) {
            return error.message;
        }
        return 'An unexpected error occurred. Please try again.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}