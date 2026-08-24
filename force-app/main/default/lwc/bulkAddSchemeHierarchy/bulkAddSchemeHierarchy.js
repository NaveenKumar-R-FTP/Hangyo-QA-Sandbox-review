import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import searchDistributors from '@salesforce/apex/SchemeHierarchyBulkController.searchDistributors';
import searchRegions from '@salesforce/apex/SchemeHierarchyBulkController.searchRegions';
import searchHubs from '@salesforce/apex/SchemeHierarchyBulkController.searchHubs';
import searchRetailers from '@salesforce/apex/SchemeHierarchyBulkController.searchRetailers';
import createDistributorRows from '@salesforce/apex/SchemeHierarchyBulkController.createDistributorRows';
import createRegionRows from '@salesforce/apex/SchemeHierarchyBulkController.createRegionRows';
import createHubRows from '@salesforce/apex/SchemeHierarchyBulkController.createHubRows';
import createRetailerRows from '@salesforce/apex/SchemeHierarchyBulkController.createRetailerRows';

const HOLDER_TYPE_OPTIONS = [
    { label: 'Distributor', value: 'Distributor' },
    { label: 'Region', value: 'Region' },
    { label: 'Hub', value: 'Hub' },
    { label: 'Retailer', value: 'Retailer' }
];

export default class BulkAddSchemeHierarchy extends LightningElement {
    // Automatically populated with the Scheme__c record Id since this component
    // is wired up as a lightning__RecordAction (Quick Action) on the Scheme object.
    @api recordId;

    holderTypeOptions = HOLDER_TYPE_OPTIONS;
    holderType = 'Distributor';

    // Distributor multi-select
    distributorSearchTerm = '';
    distributorSearchResults = [];
    selectedDistributorIds = new Set();
    distributorSearchTimeout;

    // Region multi-select
    regionSearchTerm = '';
    regionSearchResults = [];
    selectedRegionIds = new Set();
    regionSearchTimeout;

    // Hub multi-select — Hub is a fixed picklist, so results appear on any search
    // (including an empty one) rather than requiring 2+ characters like the others.
    hubSearchTerm = '';
    hubSearchResults = [];
    selectedHubs = new Set();
    hubSearchTimeout;

    // Retailer multi-select
    retailerSearchTerm = '';
    retailerSearchResults = [];
    selectedRetailerIds = new Set();
    retailerSearchTimeout;

    errorMessage = '';
    isSaving = false;

    connectedCallback() {
        this.runHubSearch();
    }

    get isDistributorMode() {
        return this.holderType === 'Distributor';
    }

    get isRegionMode() {
        return this.holderType === 'Region';
    }

    get isHubMode() {
        return this.holderType === 'Hub';
    }

    get isRetailerMode() {
        return this.holderType === 'Retailer';
    }

    get hasDistributorSearchResults() {
        return this.distributorSearchResults && this.distributorSearchResults.length > 0;
    }

    get hasSelectedDistributors() {
        return this.selectedDistributorIds.size > 0;
    }

    get selectedDistributorCount() {
        return this.selectedDistributorIds.size;
    }

    get hasRegionSearchResults() {
        return this.regionSearchResults && this.regionSearchResults.length > 0;
    }

    get hasSelectedRegions() {
        return this.selectedRegionIds.size > 0;
    }

    get selectedRegionCount() {
        return this.selectedRegionIds.size;
    }

    get hasHubSearchResults() {
        return this.hubSearchResults && this.hubSearchResults.length > 0;
    }

    get hasSelectedHubs() {
        return this.selectedHubs.size > 0;
    }

    get selectedHubCount() {
        return this.selectedHubs.size;
    }

    get hasRetailerSearchResults() {
        return this.retailerSearchResults && this.retailerSearchResults.length > 0;
    }

    get hasSelectedRetailers() {
        return this.selectedRetailerIds.size > 0;
    }

    get selectedRetailerCount() {
        return this.selectedRetailerIds.size;
    }

    get isSaveDisabled() {
        if (this.isSaving) {
            return true;
        }
        if (this.isDistributorMode) return this.selectedDistributorIds.size === 0;
        if (this.isRegionMode) return this.selectedRegionIds.size === 0;
        if (this.isHubMode) return this.selectedHubs.size === 0;
        return this.selectedRetailerIds.size === 0;
    }

    handleHolderTypeChange(event) {
        this.holderType = event.detail.value;
        this.errorMessage = '';
    }

    // ---- Distributor multi-select ----

    handleDistributorSearchChange(event) {
        this.distributorSearchTerm = event.target.value;
        this.errorMessage = '';

        window.clearTimeout(this.distributorSearchTimeout);
        if (!this.distributorSearchTerm || this.distributorSearchTerm.trim().length < 2) {
            this.distributorSearchResults = [];
            return;
        }
        this.distributorSearchTimeout = window.setTimeout(() => {
            this.runDistributorSearch();
        }, 300);
    }

    runDistributorSearch() {
        searchDistributors({ searchTerm: this.distributorSearchTerm.trim() })
            .then((results) => {
                this.distributorSearchResults = results.map((r) => ({
                    id: r.id,
                    displayLabel: r.extra ? `${r.name} (${r.extra})` : r.name,
                    selected: this.selectedDistributorIds.has(r.id)
                }));
            })
            .catch((error) => {
                this.errorMessage = this.extractError(error);
            });
    }

    handleDistributorToggle(event) {
        const id = event.target.dataset.id;
        if (event.target.checked) {
            this.selectedDistributorIds.add(id);
        } else {
            this.selectedDistributorIds.delete(id);
        }
        this.distributorSearchResults = this.distributorSearchResults.map((r) => ({
            ...r,
            selected: this.selectedDistributorIds.has(r.id)
        }));
    }

    // ---- Region multi-select ----

    handleRegionSearchChange(event) {
        this.regionSearchTerm = event.target.value;
        this.errorMessage = '';

        window.clearTimeout(this.regionSearchTimeout);
        if (!this.regionSearchTerm || this.regionSearchTerm.trim().length < 2) {
            this.regionSearchResults = [];
            return;
        }
        this.regionSearchTimeout = window.setTimeout(() => {
            this.runRegionSearch();
        }, 300);
    }

    runRegionSearch() {
        searchRegions({ searchTerm: this.regionSearchTerm.trim() })
            .then((results) => {
                this.regionSearchResults = results.map((r) => ({
                    id: r.id,
                    displayLabel: r.name,
                    selected: this.selectedRegionIds.has(r.id)
                }));
            })
            .catch((error) => {
                this.errorMessage = this.extractError(error);
            });
    }

    handleRegionToggle(event) {
        const id = event.target.dataset.id;
        if (event.target.checked) {
            this.selectedRegionIds.add(id);
        } else {
            this.selectedRegionIds.delete(id);
        }
        this.regionSearchResults = this.regionSearchResults.map((r) => ({
            ...r,
            selected: this.selectedRegionIds.has(r.id)
        }));
    }

    // ---- Hub multi-select ----
    // Hub is a small fixed picklist (~24 values), so we load the full list up front
    // (connectedCallback) and re-filter it as the user types, rather than requiring a
    // 2-character minimum like the free-text-backed searches above.

    handleHubSearchChange(event) {
        this.hubSearchTerm = event.target.value;
        this.errorMessage = '';

        window.clearTimeout(this.hubSearchTimeout);
        this.hubSearchTimeout = window.setTimeout(() => {
            this.runHubSearch();
        }, 300);
    }

    runHubSearch() {
        searchHubs({ searchTerm: this.hubSearchTerm ? this.hubSearchTerm.trim() : '' })
            .then((results) => {
                this.hubSearchResults = results.map((hub) => ({
                    value: hub,
                    selected: this.selectedHubs.has(hub)
                }));
            })
            .catch((error) => {
                this.errorMessage = this.extractError(error);
            });
    }

    handleHubToggle(event) {
        const hub = event.target.dataset.hub;
        if (event.target.checked) {
            this.selectedHubs.add(hub);
        } else {
            this.selectedHubs.delete(hub);
        }
        this.hubSearchResults = this.hubSearchResults.map((r) => ({
            ...r,
            selected: this.selectedHubs.has(r.value)
        }));
    }

    // ---- Retailer multi-select ----

    handleRetailerSearchChange(event) {
        this.retailerSearchTerm = event.target.value;
        this.errorMessage = '';

        window.clearTimeout(this.retailerSearchTimeout);
        if (!this.retailerSearchTerm || this.retailerSearchTerm.trim().length < 2) {
            this.retailerSearchResults = [];
            return;
        }
        this.retailerSearchTimeout = window.setTimeout(() => {
            this.runRetailerSearch();
        }, 300);
    }

    runRetailerSearch() {
        searchRetailers({ searchTerm: this.retailerSearchTerm.trim() })
            .then((results) => {
                this.retailerSearchResults = results.map((r) => ({
                    id: r.id,
                    displayLabel: r.name,
                    selected: this.selectedRetailerIds.has(r.id)
                }));
            })
            .catch((error) => {
                this.errorMessage = this.extractError(error);
            });
    }

    handleRetailerToggle(event) {
        const id = event.target.dataset.id;
        if (event.target.checked) {
            this.selectedRetailerIds.add(id);
        } else {
            this.selectedRetailerIds.delete(id);
        }
        this.retailerSearchResults = this.retailerSearchResults.map((r) => ({
            ...r,
            selected: this.selectedRetailerIds.has(r.id)
        }));
    }

    // ---- Save / cancel ----

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleSave() {
        this.errorMessage = '';
        this.isSaving = true;

        let savePromise;
        if (this.isDistributorMode) {
            savePromise = createDistributorRows({
                schemeId: this.recordId,
                distributorIds: Array.from(this.selectedDistributorIds)
            });
        } else if (this.isRegionMode) {
            savePromise = createRegionRows({
                schemeId: this.recordId,
                regionIds: Array.from(this.selectedRegionIds)
            });
        } else if (this.isHubMode) {
            savePromise = createHubRows({
                schemeId: this.recordId,
                hubs: Array.from(this.selectedHubs)
            });
        } else {
            savePromise = createRetailerRows({
                schemeId: this.recordId,
                retailerIds: Array.from(this.selectedRetailerIds)
            });
        }

        savePromise
            .then((result) => {
                this.isSaving = false;
                if (result) {
                    // Non-null result means at least one row failed validation (e.g. duplicate).
                    this.errorMessage = result;
                } else {
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Success',
                        message: 'Scheme Hierarchy saved.',
                        variant: 'success'
                    }));
                    this.dispatchEvent(new RefreshEvent());
                    this.dispatchEvent(new CloseActionScreenEvent());
                }
            })
            .catch((error) => {
                this.isSaving = false;
                this.errorMessage = this.extractError(error);
            });
    }

    extractError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return 'Something went wrong. Please try again.';
    }
}