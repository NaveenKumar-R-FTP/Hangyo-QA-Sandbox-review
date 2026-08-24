import { LightningElement, api, track } from 'lwc';
import fetchProducts from '@salesforce/apex/CounterInvoiceController.fetchProducts';
import getTaxRates from '@salesforce/apex/CounterInvoiceController.getTaxRates';
import createCounterOrder from '@salesforce/apex/CounterInvoiceController.createCounterOrder';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const STORAGE_KEY = 'counterInvoiceCart';

export default class CounterInvoiceProductPage extends LightningElement {

    @api state;
    @api firstname;
    @api lastname;
    @api phone;
    @api email;
    @api addressline;
    @api city;
    @api postalcode;
    @api country;
    @api company;
    @api gstin;
    @api saleType  = 'Cash Sales';
    @api priceType = 'MRP';

    @track data                       = [];
    @track productAddedForCart        = [];
    @track openCart                   = false;
    @track showInvoicePage            = false;
    @track allBrandsList              = [];
    @track showBrandDropdown          = false;
    @track showAvailableStockDropdown = false;
    @track allTabDisplayText          = 'All';
    @track availableStockTabDisplayText = 'Available Stock';

    @track orderSummary = {
        totalItems: 0, totalPrice: 0, totalOrderValue: 0,
        totalQuantity: 0, totalSGST: 0, totalCGST: 0, totalIGST: 0,
        totalPriceExcludingTax: 0
    };

    cartSize         = 0;
    selectedBrands   = '';
    stockFilter      = '';
    searchValue      = '';
    priceWithoutTax  = 0;
    percentCGST      = 0;
    percentSGST      = 0;
    percentIGST      = 0;
    showtotalCGSTtax = false;
    showtotalIGSTtax = false;
    isSubmitting     = false;
    createdOrderId   = '';
    searchDebounce;

    get isDealerPrice() { return this.priceType === 'Dealer Price'; }

    connectedCallback() {
        this.loadProducts();
        this.loadCartFromStorage();
        this.handleClickOutside = this.handleClickOutside.bind(this);
        document.addEventListener('click', this.handleClickOutside);
    }

    disconnectedCallback() {
        document.removeEventListener('click', this.handleClickOutside);
    }

    handleClickOutside(event) {
        const containers = this.template.querySelectorAll('.custom-tab-container');
        let outside = true;
        containers.forEach(c => { if (c && c.contains(event.target)) outside = false; });
        if (outside) {
            this.showBrandDropdown          = false;
            this.showAvailableStockDropdown = false;
        }
    }

    loadProducts() {
        fetchProducts({
            searchValue: this.searchValue,
            brandFilter: this.selectedBrands === 'All' ? '' : this.selectedBrands,
            stockFilter: this.stockFilter,
            searchBy: 'Name',
            priceType: this.priceType
        }).then(result => {
            this.data = JSON.parse(result);
            this.extractBrands();
            this.updateCartQuantities();
            if (this.stockFilter === 'Available Stock') {
                this.data = this.data.filter(p => p.availableQuantity > 0);
            }
            if (this.searchValue) {
                this.filterProductsByExactSearch();
            }
        }).catch(() => {});
    }

    extractBrands() {
        const brandSet = new Set();
        this.data.forEach(p => {
            if (p.productBrand && p.productBrand !== 'All' && p.productBrand !== 'Available Stock') {
                brandSet.add(p.productBrand);
            }
        });
        this.allBrandsList = [...brandSet].sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' }));
    }

    filterProductsByExactSearch() {
        if (!this.searchValue || !this.data) return;
        const searchTerm = this.searchValue.trim();
        if (searchTerm === '') return;
        const escapedTerm = searchTerm.replace(/[.*+?^${}()|\[\]\\]/g, '\\$&');
        const isNumeric = /^\d+$/.test(searchTerm);
        this.data = this.data.filter(product => {
            const name = product.productShortDescription || '';
            const mainName = name.split('(')[0].trim();
            const inParens = (name.match(/\(([^)]+)\)/) || [])[1] || '';
            if (isNumeric) {
                const rx = new RegExp('(^|[^0-9])' + escapedTerm + '([^0-9]|$)', 'i');
                return rx.test(mainName) || rx.test(inParens);
            }
            return mainName.toLowerCase().includes(searchTerm.toLowerCase()) ||
                   inParens.toLowerCase().includes(searchTerm.toLowerCase());
        });
    }

    loadCartFromStorage() {
        const saved = JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
        if (saved.length > 0) {
            this.productAddedForCart = saved;
            this.cartSize = saved.length;
            this.fetchTaxRates();
            this.updateCartQuantities();
        }
    }

    updateCartQuantities() {
        this.data = this.data.map(p => {
            const inCart = this.productAddedForCart.find(i => i.productId === p.productId);
            return { ...p, addedQuantity: inCart ? inCart.quantity : 0 };
        });
    }

    // Tab handlers
    handleAllTabClick() {
        this.selectedBrands = '';
        this.stockFilter    = '';
        this.allTabDisplayText = 'All';
        this.availableStockTabDisplayText = 'Available Stock';
        this.showBrandDropdown = false;
        this.loadProducts();
    }

    handleAvailableStockTabClick() {
        this.selectedBrands = '';
        this.stockFilter    = 'Available Stock';
        this.availableStockTabDisplayText = 'Available Stock';
        this.allTabDisplayText = 'All';
        this.showAvailableStockDropdown = false;
        this.loadProducts();
    }

    toggleBrandDropdown(event) {
        event.stopPropagation();
        this.showBrandDropdown = !this.showBrandDropdown;
        this.showAvailableStockDropdown = false;
    }

    toggleAvailableStockDropdown(event) {
        event.stopPropagation();
        this.showAvailableStockDropdown = !this.showAvailableStockDropdown;
        this.showBrandDropdown = false;
    }

    handleBrandSelect(event) {
        const brand = event.currentTarget.dataset.brand;
        this.selectedBrands    = brand === 'All' ? '' : brand;
        this.allTabDisplayText = brand === 'All' ? 'All' : `All (${brand})`;
        this.stockFilter       = '';
        this.availableStockTabDisplayText = 'Available Stock';
        this.showBrandDropdown = false;
        this.loadProducts();
    }

    handleAvailableStockBrandSelect(event) {
        const brand = event.currentTarget.dataset.brand;
        this.selectedBrands = brand === 'All' ? '' : brand;
        this.availableStockTabDisplayText = brand === 'All' ? 'Available Stock' : `Available Stock (${brand})`;
        this.stockFilter    = 'Available Stock';
        this.allTabDisplayText = 'All';
        this.showAvailableStockDropdown = false;
        this.loadProducts();
    }

    handleSearchChange(event) {
        this.searchValue = (event.detail && event.detail.value !== undefined)
            ? event.detail.value : (event.target ? event.target.value : '');
        clearTimeout(this.searchDebounce);
        this.searchDebounce = setTimeout(() => this.loadProducts(), 300);
    }

    // Quantity controls on product grid
    minusQuantity(event) {
        const productId = event.target.name;
        const el = this.template.querySelector(`[data-id="${productId}"]`);
        const product = this.data.find(p => p.productId === productId);
        if (product) product.productQuantity = (parseInt(el.value) - 1) > 0 ? parseInt(el.value) - 1 : 0;
    }

    addQuantity(event) {
        const productId = event.target.name;
        const el = this.template.querySelector(`[data-id="${productId}"]`);
        const product = this.data.find(p => p.productId === productId);
        if (product) product.productQuantity = parseInt(el.value) + 1;
    }

    valueQtyHandle(event) {
        const productId   = event.target.dataset.id;
        const product     = this.data.find(p => p.productId === productId);
        if (product) product.productQuantity = parseInt(event.target.value, 10) || 0;
    }

    addToCart(event) {
        const productId  = event.currentTarget.dataset.productId;
        const product    = this.data.find(p => p.productId === productId);
        const desiredQty = product.productQuantity;
        const available  = product.availableQuantity;

        if (!desiredQty || desiredQty <= 0) {
            this.showToast('', 'Please enter a valid quantity', 'error'); return;
        }
        if (desiredQty > available) {
            this.showToast('', 'Insufficient stock for ' + product.productShortDescription + '. Available: ' + available, 'error');
            return;
        }

        let cart = JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
        let existing = false;
        for (let i = 0; i < cart.length; i++) {
            if (cart[i].productId === productId) {
                const newQty = cart[i].quantity + desiredQty;
                if (newQty > available) {
                    this.showToast('', 'Total qty exceeds available stock. Available: ' + available, 'error');
                    return;
                }
                cart[i].quantity       = newQty;
                cart[i].unittotalPrice = (newQty * product.productOfferPrice).toFixed(2);
                existing = true;
                break;
            }
        }

        if (!existing) {
            cart.push({
                productId:            productId,
                productIdForCart:     productId + 'Cart',
                productName:          product.productShortDescription,
                productBrand:         product.productBrand,
                productOfferPrice:    product.productOfferPrice,
                quantity:             desiredQty,
                unittotalPrice:       (desiredQty * product.productOfferPrice).toFixed(2),
                prodmeasure:          product.uom || 'N/A',
                availableStockQuantity: available
            });
        }

        product.productQuantity = 0;
        this.cartSize = cart.length;
        localStorage.setItem(STORAGE_KEY, JSON.stringify(cart));
        this.productAddedForCart = cart;
        this.fetchTaxRates();
        this.updateCartQuantities();
        this.showToast('', 'Item added to cart', 'success');
    }

    get serializedCartItems() {
        return this.productAddedForCart.map((item, index) => ({ ...item, serialNumber: index + 1 }));
    }

    openCartModal() {
        this.openCart = true;
        this.fetchTaxRates();
    }

    handleGoBack() {
        this.dispatchEvent(new CustomEvent('goback'));
    }

    closeCart() {
        this.openCart = false;
    }

    // Cart quantity controls
    minusQuantityCart(event) {
        const nameOf = String(event.target.name);
        this.productAddedForCart = this.productAddedForCart.map(item => {
            if (item.productIdForCart === nameOf) {
                const newQty = item.quantity > 1 ? item.quantity - 1 : item.quantity;
                return { ...item, quantity: newQty, unittotalPrice: (newQty * item.productOfferPrice).toFixed(2) };
            }
            return item;
        });
        this.syncCart();
    }

    addQuantityCart(event) {
        const nameOf = String(event.target.name);
        this.productAddedForCart = this.productAddedForCart.map(item => {
            if (item.productIdForCart === nameOf) {
                const prod = this.data.find(p => p.productId === item.productId);
                const avail = prod ? prod.availableQuantity : 9999;
                if (item.quantity + 1 > avail) {
                    this.showToast('', 'Insufficient stock. Available: ' + avail, 'error');
                    return item;
                }
                const newQty = item.quantity + 1;
                return { ...item, quantity: newQty, unittotalPrice: (newQty * item.productOfferPrice).toFixed(2) };
            }
            return item;
        });
        this.syncCart();
    }

    valueQtyHandleCart(event) {
        const nameOf = String(event.target.name);
        const qty    = parseInt(event.target.value, 10);
        if (isNaN(qty) || qty <= 0) { this.showToast('Error', 'Enter a valid quantity', 'error'); return; }
        this.productAddedForCart = this.productAddedForCart.map(item => {
            if (item.productIdForCart === nameOf) {
                const prod  = this.data.find(p => p.productId === item.productId);
                const avail = prod ? prod.availableQuantity : 9999;
                if (qty > avail) {
                    this.showToast('', 'Insufficient stock. Available: ' + avail, 'error');
                    return { ...item, quantity: qty };
                }
                return { ...item, quantity: qty, unittotalPrice: (qty * item.productOfferPrice).toFixed(2) };
            }
            return item;
        });
        this.syncCart();
    }

    removeFromCart(event) {
        this.productAddedForCart = this.productAddedForCart.filter(i => i.productIdForCart !== event.target.name);
        if (this.productAddedForCart.length === 0) {
            this.cartSize = 0;
            localStorage.removeItem(STORAGE_KEY);
            this.openCart = false;
            return;
        }
        this.syncCart();
    }

    syncCart() {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(this.productAddedForCart));
        this.cartSize = this.productAddedForCart.length;
        this.fetchTaxRates();
        this.updateCartQuantities();
    }

    fetchTaxRates() {
        getTaxRates().then(rates => this.calculateSummary(rates)).catch(() => {});
    }

    calculateSummary(rates) {
        let totalItems = this.productAddedForCart.length;
        let totalQty   = 0;
        let totalPrice = 0;

        this.productAddedForCart.forEach(item => {
            totalQty   += item.quantity;
            totalPrice += item.productOfferPrice * item.quantity;
        });

        const cgst = rates.CGST || 0;
        const sgst = rates.SGST || 0;
        const igst = rates.IGST || 0;

        const taxRate       = cgst + sgst > 0 ? cgst + sgst : igst;
        const excTax        = parseFloat((totalPrice / (1 + taxRate / 100)).toFixed(2));
        const cgstAmt       = parseFloat(((excTax * cgst) / 100).toFixed(2));
        const sgstAmt       = parseFloat(((excTax * sgst) / 100).toFixed(2));
        const igstAmt       = parseFloat(((excTax * igst) / 100).toFixed(2));

        this.priceWithoutTax        = excTax;
        this.percentCGST            = cgst;
        this.percentSGST            = sgst;
        this.percentIGST            = igst;
        this.showtotalCGSTtax       = cgst > 0 && sgst > 0;
        this.showtotalIGSTtax       = igst > 0;

        this.orderSummary = {
            totalItems,
            totalQuantity:          totalQty,
            totalPrice:             totalPrice.toFixed(2),
            totalPriceExcludingTax: excTax,
            totalCGST:              cgstAmt,
            totalSGST:              sgstAmt,
            totalIGST:              igstAmt
        };
        this.cartSize = totalItems;
    }

    // Next → create order then navigate to invoice
    handleNext() {
        if (this.cartSize === 0) {
            this.showToast('', 'Cart is empty. Add products first.', 'error'); return;
        }
        if (this.isSubmitting) return;
        this.isSubmitting = true;

        const summary = {
            firstName:             this.firstname,
            lastName:              this.lastname,
            phone:                 this.phone,
            email:                 this.email,
            addressLine:           this.addressline,
            city:                  this.city,
            postalCode:            this.postalcode,
            state:                 this.state,
            country:               this.country,
            company:               this.company,
            gstin:                 this.gstin,
            saleType:              this.saleType,
            priceType:             this.priceType,
            totalPrice:            parseFloat(this.orderSummary.totalPrice),
            totalPriceExcludingTax: this.orderSummary.totalPriceExcludingTax,
            totalQuantity:         this.orderSummary.totalQuantity,
            totalCGST:             this.orderSummary.totalCGST,
            totalSGST:             this.orderSummary.totalSGST,
            totalIGST:             this.orderSummary.totalIGST
        };

        createCounterOrder({
            productsFromCart: JSON.stringify(this.productAddedForCart),
            orderSummary:     JSON.stringify(summary)
        }).then(result => {
            if (result.status === 'Success') {
                localStorage.removeItem(STORAGE_KEY);
                this.createdOrderId      = result.orderId;
                this.productAddedForCart = [];
                this.cartSize            = 0;
                this.openCart            = false;
                this.showInvoicePage     = true;
            }
        }).catch(error => {
            this.showToast('Error', error.body ? error.body.message : 'Error creating order', 'error');
        }).finally(() => {
            this.isSubmitting = false;
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}