import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import searchProducts from '@salesforce/apex/SchemeApplicabilityBulkController.searchProducts';
import searchBrands from '@salesforce/apex/SchemeApplicabilityBulkController.searchBrands';
import createProductRows from '@salesforce/apex/SchemeApplicabilityBulkController.createProductRows';
import createBrandRows from '@salesforce/apex/SchemeApplicabilityBulkController.createBrandRows';

const ENTITY_TYPE_OPTIONS = [
    { label: 'Product', value: 'Product' },
    { label: 'Brand', value: 'Brand' }
];

export default class BulkAddSchemeApplicability extends LightningElement {
    // Automatically populated with the Scheme__c record Id since this component
    // is wired up as a lightning__RecordAction (Quick Action) on the Scheme object.
    @api recordId;

    entityTypeOptions = ENTITY_TYPE_OPTIONS;
    entityType = 'Product';

    // Product multi-select
    searchTerm = '';
    searchResults = [];
    selectedProductIds = new Set();
    searchTimeout;

    // Brand multi-select — brands come from distinct Product_Brand__c values on
    // existing Products (via SchemeApplicabilityBulkController.searchBrands),
    // not free-typed, so we don't end up with near-duplicate brand strings.
    brandSearchTerm = '';
    brandSearchResults = [];
    selectedBrands = new Set();
    brandSearchTimeout;

    errorMessage = '';
    isSaving = false;

    get isProductMode() {
        return this.entityType === 'Product';
    }

    get isBrandMode() {
        return this.entityType === 'Brand';
    }

    get hasSearchResults() {
        return this.searchResults && this.searchResults.length > 0;
    }

    get hasSelectedProducts() {
        return this.selectedProductIds.size > 0;
    }

    get selectedProductCount() {
        return this.selectedProductIds.size;
    }

    get hasBrandSearchResults() {
        return this.brandSearchResults && this.brandSearchResults.length > 0;
    }

    get hasSelectedBrands() {
        return this.selectedBrands.size > 0;
    }

    get selectedBrandCount() {
        return this.selectedBrands.size;
    }

    get isSaveDisabled() {
        if (this.isSaving) {
            return true;
        }
        if (this.isProductMode) {
            return this.selectedProductIds.size === 0;
        }
        return this.selectedBrands.size === 0;
    }

    handleEntityTypeChange(event) {
        this.entityType = event.detail.value;
        this.errorMessage = '';
    }

    // ---- Product multi-select ----

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.errorMessage = '';

        window.clearTimeout(this.searchTimeout);
        if (!this.searchTerm || this.searchTerm.trim().length < 2) {
            this.searchResults = [];
            return;
        }
        this.searchTimeout = window.setTimeout(() => {
            this.runProductSearch();
        }, 300);
    }

    runProductSearch() {
        searchProducts({ searchTerm: this.searchTerm.trim() })
            .then((results) => {
                this.searchResults = results.map((r) => ({
                    id: r.id,
                    displayLabel: r.brand ? `${r.name} (${r.brand})` : r.name,
                    selected: this.selectedProductIds.has(r.id)
                }));
            })
            .catch((error) => {
                this.errorMessage = this.extractError(error);
            });
    }

    handleProductToggle(event) {
        const productId = event.target.dataset.id;
        if (event.target.checked) {
            this.selectedProductIds.add(productId);
        } else {
            this.selectedProductIds.delete(productId);
        }
        this.searchResults = this.searchResults.map((r) => ({
            ...r,
            selected: this.selectedProductIds.has(r.id)
        }));
    }

    // ---- Brand multi-select ----

    handleBrandSearchChange(event) {
        this.brandSearchTerm = event.target.value;
        this.errorMessage = '';

        window.clearTimeout(this.brandSearchTimeout);
        if (!this.brandSearchTerm || this.brandSearchTerm.trim().length < 2) {
            this.brandSearchResults = [];
            return;
        }
        this.brandSearchTimeout = window.setTimeout(() => {
            this.runBrandSearch();
        }, 300);
    }

    runBrandSearch() {
        searchBrands({ searchTerm: this.brandSearchTerm.trim() })
            .then((results) => {
                this.brandSearchResults = results.map((brand) => ({
                    value: brand,
                    selected: this.selectedBrands.has(brand)
                }));
            })
            .catch((error) => {
                this.errorMessage = this.extractError(error);
            });
    }

    handleBrandToggle(event) {
        const brand = event.target.dataset.brand;
        if (event.target.checked) {
            this.selectedBrands.add(brand);
        } else {
            this.selectedBrands.delete(brand);
        }
        this.brandSearchResults = this.brandSearchResults.map((r) => ({
            ...r,
            selected: this.selectedBrands.has(r.value)
        }));
    }

    // ---- Save / cancel ----

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleSave() {
        this.errorMessage = '';
        this.isSaving = true;

        const savePromise = this.isProductMode
            ? createProductRows({ schemeId: this.recordId, productIds: Array.from(this.selectedProductIds) })
            : createBrandRows({ schemeId: this.recordId, brands: Array.from(this.selectedBrands) });

        savePromise
            .then((result) => {
                this.isSaving = false;
                if (result) {
                    // Non-null result means at least one row failed validation (e.g. duplicate).
                    this.errorMessage = result;
                } else {
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Success',
                        message: 'Scheme Applicability saved.',
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