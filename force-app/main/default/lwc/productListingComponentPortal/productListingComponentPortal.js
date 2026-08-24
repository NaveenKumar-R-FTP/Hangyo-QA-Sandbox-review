import { track, LightningElement, api, wire } from 'lwc';
import fetchProducts from '@salesforce/apex/ProductListingComponentControllerPortal.fetchProducts';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import generateProposal from '@salesforce/apex/ProductListingComponentControllerPortal.generateProposal';
import { NavigationMixin } from 'lightning/navigation';
import getTaxRates from '@salesforce/apex/ProductListingComponentControllerPortal.getTaxRates';
import getqualityScheme from '@salesforce/apex/ProductListingComponentControllerPortal.getqualityScheme';
import getProductsWithSchemes from '@salesforce/apex/ProductListingComponentControllerPortal.getProductsWithSchemes';
import getvalueScheme from '@salesforce/apex/ProductListingComponentControllerPortal.getvalueScheme';
import getAppliedValueScheme from '@salesforce/apex/ProductListingComponentControllerPortal.getAppliedValueScheme';
import getAppliedValueSchemeName from '@salesforce/apex/ProductListingComponentControllerPortal.getAppliedValueSchemeName';
import { getRecord } from 'lightning/uiRecordApi';
import ACCOUNT_REGION from '@salesforce/schema/Account.Primary_State__c';
import applyQuantityScheme from '@salesforce/apex/ProductListingComponentControllerPortal.applyQuantityScheme';
import getProductForValueScheme from '@salesforce/apex/ProductListingComponentControllerPortal.getProductForValueScheme';
import isUnderSSUser from '@salesforce/apex/ProductListingComponentControllerPortal.isUnderSSUser';
import NO_Cart_SCHEME_AVAILABLE  from '@salesforce/label/c.No_Cart_Value_Scheme';


export default class ProductListingComponentPortal extends NavigationMixin(LightningElement) {
    @api storageKey = 'primaryCart'; // Dynamic storage key with primary order value
    @track state;
    @track ShowprodutcList = true;
    @track data = [];
    @track activeTab = 'All';
    @track cartItems = [];
    @track objectOfProductToCart;
    cartSize = 0;
    @track productAddedForCart = [];
    @track quantityValue = 0;
    @track availableBrands = [];
    @track selectedBrands = '';
    @track searchValue = '';
    openCart = false;
    @track comment = '';
    recordId = '';
    @track showBrandFilters = false;
    showtotalIGSTtax = false;
    showtotalCGSTtax = false;
    percentIGST = 0;
    percentCGST = 0;
    percentSGST = 0;
    isOrderPlaced = false;
    @track orderSummary = {
        'totalItems': 0,
        'totalPrice': 0,
        'totalDiscount': 0,
        'totalOrderValue': 0,
        'totalQuantity': 0,
        'totalSGST': 0,
        'totalCGST': 0,
        'totalIGST': 0,
        'totalCrates': '0 Crate'
    };

    @track isQualityScheme=false;
    @track isQualityFocusScheme=false;
    @track isValueScheme=false;
    @track schemeDetails = []; // Reset the scheme details
    @track valueSchemeDetails = []; // Reset the scheme details
    @track isNoSchemesMessage = false;
    @track noSchemesMessage = '';
    @track valueSchemFinalId='';
    @track ValueSchemeFinalName='';
    @track ValueSchemeExist=false;
    totalCartPrice = 0.0; // Decimal (Floating Point)
    @track selectedAccountId;
    @track buyerRegion;
    @track schemeSource; // 'PRODUCT' | 'CART'
    @track activeProductId;
    selectedSchemeId;
    isCartContext = false;
    isUnderSS = false;
    @track discountAmountGiven=0;
    @track discountAmountGivenCheck=false;
    @track discountPercemtageGiven=0;
    @track discountPercemtageGivenCheckca=0;
    @track priceAfterDiscount=0;
    @track discountPercentageAmount=0;

    // added by Fuzail - Search By: 'Name' = normal product search (old behaviour),
    //                               'Code' = search by Product_Code__c (starts with, e.g. 5300105)
    @track searchBy = 'Name';
    @track searchByDisplayText = 'Name';
    @track showSearchByDropdown = false;

    // added by Fuzail - debounce for search so we don't spam Apex on every keystroke
    searchDebounceTimeout;

    /* OLD connectedCallback (commented by Fuzail)
    connectedCallback() {
        this.fetchProducts();
                isUnderSSUser()
            .then(result => {
                this.isUnderSS = result;
            })
            .catch(error => {
                this.isUnderSS = false;
                console.error('Under SS check failed', error);
            });

        this.loadCartFromStorage();
    }
    */

    // added by Fuzail - connectedCallback with click listener for closing Search By dropdown
    connectedCallback() {
        this.fetchProducts();
        isUnderSSUser()
            .then(result => {
                this.isUnderSS = result;
            })
            .catch(error => {
                this.isUnderSS = false;
                console.error('Under SS check failed', error);
            });

        this.loadCartFromStorage();
        
        // added by Fuzail - Add click listener to close Search By dropdown when clicking outside
        this.handleClickOutside = this.handleClickOutside.bind(this);
        document.addEventListener('click', this.handleClickOutside);
    }

    // added by Fuzail - Remove click listener when component is destroyed
    disconnectedCallback() {
        if (this.handleClickOutside) {
            document.removeEventListener('click', this.handleClickOutside);
        }
    }

    // added by Fuzail - Method to handle clicks outside Search By dropdown
    handleClickOutside(event) {
        const searchByDropdowns = this.template.querySelectorAll('.search-by-dropdown-wrapper');
        let clickedOutside = true;

        if (searchByDropdowns && searchByDropdowns.length > 0) {
            searchByDropdowns.forEach(container => {
                if (container && container.contains(event.target)) {
                    clickedOutside = false;
                }
            });
        }

        // If clicked outside and Search By dropdown is open, close it
        if (clickedOutside && this.showSearchByDropdown) {
            this.showSearchByDropdown = false;
        }
    }

    /* OLD handleTabChange (commented by Fuzail)
    handleTabChange(event) {
        this.selectedBrands = event.target.value;
        this.loadProducts();
    }
    */

    // added by Fuzail - handleTabChange with Search By dropdown close
    handleTabChange(event) {
        this.selectedBrands = event.target.value;
        this.showSearchByDropdown = false; // added by Fuzail - close Search By dropdown when clicking any tab
        this.loadProducts();
    }

    loadCartFromStorage() {
        const savedCart = JSON.parse(localStorage.getItem(this.storageKey)) || [];
        if (savedCart.length > 0) {
            this.productAddedForCart = savedCart.map(item => ({
            ...item,
            totalPrice: item.totalPrice || (item.quantity * item.productOfferPrice).toFixed(2)
        }));
            this.cartSize = this.productAddedForCart.length;
            this.prepareOrderSummary();
            this.updateProductQuantitiesFromCart();
        }
    }

    updateProductQuantitiesFromCart() {
        if (this.data && this.productAddedForCart) {
            this.data = this.data.map(product => {
                let productInCart = this.productAddedForCart.find(item => item.productId === product.productId);
                return {
                    ...product,
                    productQuantity: product.productQuantity || 0,
                    addedQuantity: productInCart ? productInCart.quantity : 0
                };
            });
        }
    }

    getCrateDisplay(quantity, crateconversion) {
        if(crateconversion>0){ 
          const fullCrates = Math.floor(quantity / crateconversion);
          const remainingUnits = quantity % crateconversion;
          if (fullCrates > 0 && remainingUnits > 0) {
            //console.log('Enter line 93');
              return `${fullCrates} Crate ${remainingUnits} EA`;
          } else if (fullCrates > 0) {
              return `${fullCrates} Crate`;
          } else {
              return `0 Crate ${remainingUnits} EA`;
          }
        }
    }

    //This method is used for search bar to search products
    // added by Fuzail - use event.detail.value for lightning-input; debounce + keep existing filter behaviour
    handleChangeSearchValue(event) {
        const value = (event.detail && event.detail.value !== undefined)
            ? event.detail.value
            : (event.target ? event.target.value : '');
        this.searchValue = value != null ? value : '';
        
        if (this.searchDebounceTimeout) {
            clearTimeout(this.searchDebounceTimeout);
        }
        this.searchDebounceTimeout = setTimeout(() => {
            this.loadProducts();
        }, 300);
    }

    // added by Fuzail - Toggle Search By dropdown (Name / Code)
    toggleSearchByDropdown(event) {
        event.stopPropagation();
        this.showSearchByDropdown = !this.showSearchByDropdown;
    }

    // added by Fuzail - When user selects Name or Code in Search By
    handleSearchByOptionSelect(event) {
        const selected = event.currentTarget.dataset.searchby; // 'Name' or 'Code'
        this.searchBy = selected;
        this.searchByDisplayText = selected;
        this.showSearchByDropdown = false;
        this.loadProducts();
    }

    // Same logic as counterOrderProductPage: filter so "70" matches "70" but not "170" or "700" (whole word/number)
    filterProductsByExactSearch() {
        if (!this.searchValue || !this.data) {
            return;
        }
        const searchTerm = this.searchValue.trim();
        if (searchTerm === '') {
            return;
        }
        const escapedSearchTerm = searchTerm.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        const isNumeric = /^\d+$/.test(searchTerm);
        this.data = this.data.filter(product => {
            const productName = product.productShortDescription || '';
            const mainNameMatch = productName.split('(')[0].trim();
            const mainProductName = mainNameMatch || '';
            const parenthesesMatch = productName.match(/\(([^)]+)\)/);
            const parenthesesContent = parenthesesMatch ? parenthesesMatch[1] : '';
            let matchesInMainName = false;
            let matchesInParentheses = false;
            if (isNumeric) {
                if (mainProductName) {
                    const regexMain = new RegExp(`(^|[^0-9])${escapedSearchTerm}([^0-9]|$)`, 'i');
                    matchesInMainName = regexMain.test(mainProductName);
                }
                if (parenthesesContent) {
                    const regexParentheses = new RegExp(`(^|[^0-9])${escapedSearchTerm}([^0-9]|$)`, 'i');
                    matchesInParentheses = regexParentheses.test(parenthesesContent);
                }
            } else {
                if (mainProductName) {
                    matchesInMainName = mainProductName.toLowerCase().includes(searchTerm.toLowerCase());
                }
                if (parenthesesContent) {
                    matchesInParentheses = parenthesesContent.toLowerCase().includes(searchTerm.toLowerCase());
                }
            }
            return matchesInMainName || matchesInParentheses;
        });
    }

    loadProducts() {
        // added by Fuzail - pass searchBy so Apex can switch between Name and Product_Code__c search
        fetchProducts({ 'searchValue': this.searchValue, 'brandFilter': this.selectedBrands === 'All' ? '' : this.selectedBrands, 'searchBy': this.searchBy })
            .then(result => {
                this.data = JSON.parse(result);
                this.updateProductQuantitiesFromCart();
                if (this.searchBy === 'Name') {
                    this.filterProductsByExactSearch();
                }
            })
            .catch(error => {
                console.error('Error loading products:', error);
            });
    }

    fetchProducts() {
        // added by Fuzail - include searchBy in initial fetch as well
        fetchProducts({ 'searchValue': this.searchValue, 'brandFilter': this.selectedBrands, 'searchBy': this.searchBy })
            .then(result => {
                this.data = JSON.parse(result);
                const brandsSet = new Set(['All']);
                this.updateProductQuantitiesFromCart();
                if (this.searchBy === 'Name') {
                    this.filterProductsByExactSearch();
                }
                this.data.forEach(product => {
                    if (product.productBrand) {
                        brandsSet.add(product.productBrand);
                    }
                    this.state = product.state;
                });
                this.availableBrands = [...brandsSet];
            })
            .catch(error => {
                console.error('Error fetching products:', error);
            });
    }


    handleCommentChange(event) {
        this.comment = event.target.value;
    }

    /*addToCart(event) {
        let selectedProductId = event.currentTarget.dataset.productId;
        let largeGroup = this.data.filter(activity => (activity.productId == selectedProductId));
        let dataOfImages = largeGroup[0].productImages;
        let nameOfProduct = largeGroup[0].productShortDescription;

        if (nameOfProduct.length >= 12) {
            nameOfProduct = nameOfProduct.substring(0, 11);
        }

        this.objectOfProductToCart = {
            'productId': largeGroup[0].productId,
            'productIdForCart': largeGroup[0].productId + 'Cart',
            'productImage': largeGroup[0].productDisplayImage,
            'quantity': 0,
            'productName': largeGroup[0].productShortDescription,
            'productBrand': largeGroup[0].productBrand,
            'productFullName': largeGroup[0].productShortDescription,
            'productListPrice': largeGroup[0].productListPrice,
            'productOfferPrice': largeGroup[0].productOfferPrice.toFixed(2),
            'prodmeasure': largeGroup[0].uom || 'N/A',
            'showMOQ': largeGroup[0].showMOQ,
            'availableStockQuantity': largeGroup[0].inventoryQty,
            'minOrderQuantity' : largeGroup[0].minOrderQuantity,
            'unittotalPrice': 0 ,
            'crateDisplay' : '',
            'index': 0,
            'crateconversion': largeGroup[0].crateconversion
        };

        let validateCartProducts = JSON.parse(localStorage.getItem(this.storageKey)) || [];
        let productExisting = false;

        for (let key in validateCartProducts) {
            if (validateCartProducts[key].productId == this.objectOfProductToCart.productId) {
                productExisting = true;
                validateCartProducts[key].quantity += largeGroup[0].productQuantity;
                validateCartProducts[key].crateDisplay = this.getCrateDisplay(validateCartProducts[key].quantity, largeGroup[0].crateconversion);
                break;
            }
        }

        if (largeGroup[0].productQuantity <= 0) {
            this.showToast('', 'Please Add Valid Quantity', 'error');
        } else {
            if (!productExisting) {
                if (largeGroup[0].productQuantity > 0) {
                    this.objectOfProductToCart.quantity = largeGroup[0].productQuantity;
                    this.objectOfProductToCart.unittotalPrice =(largeGroup[0].productQuantity * largeGroup[0].productOfferPrice).toFixed(2);
                    this.objectOfProductToCart.crateDisplay=this.getCrateDisplay(this.objectOfProductToCart.quantity, largeGroup[0].crateconversion);
                    this.objectOfProductToCart.index = validateCartProducts.length + 1;
                    validateCartProducts.push(this.objectOfProductToCart);
                    largeGroup[0].productQuantity = 0;
                }
            }
            largeGroup[0].productQuantity = 0;
            this.cartSize = validateCartProducts.length;
            localStorage.setItem(this.storageKey, JSON.stringify(validateCartProducts));
            this.productAddedForCart = validateCartProducts;
            this.prepareOrderSummary();
            this.showToast('', 'Item is added to cart', 'success');
            this.updateProductQuantitiesFromCart();
        }
    }*/

    addToCart(event) {
        let selectedProductId = event.currentTarget.dataset.productId;
        let largeGroup = this.data.filter(activity => (activity.productId == selectedProductId));
        let dataOfImages = largeGroup[0].productImages;
        let nameOfProduct = largeGroup[0].productShortDescription;

        if (nameOfProduct.length >= 12) {
            nameOfProduct = nameOfProduct.substring(0, 11);
        }

        const productQty = largeGroup[0].productQuantity;
        const moq = largeGroup[0].minOrderQuantity;
        const showMOQ = largeGroup[0].showMOQ;

        // ✅ Validate MOQ requirement if enabled
        if (showMOQ && moq > 0 && (productQty % moq !== 0 || productQty <= 0)) {
            this.showToast(
                'Invalid Quantity',
                `Please enter a valid quantity in multiples of ${moq} (MOQ)`,
                'error'
            );
            return;
        }

        if (productQty <= 0) {
            this.showToast('', 'Please Add Valid Quantity', 'error');
            return;
        }

        this.objectOfProductToCart = {
            'productId': largeGroup[0].productId,
            'productIdForCart': largeGroup[0].productId + 'Cart',
            'productImage': largeGroup[0].productDisplayImage,
            'quantity': 0,
            'productName': largeGroup[0].productShortDescription,
            'productBrand': largeGroup[0].productBrand,
            'productFullName': largeGroup[0].productShortDescription,
            'productListPrice': largeGroup[0].productListPrice,
            'productOfferPrice': largeGroup[0].productOfferPrice.toFixed(2),
            'prodmeasure': largeGroup[0].uom || 'N/A',
            'showMOQ': largeGroup[0].showMOQ,
            'availableStockQuantity': largeGroup[0].inventoryQty,
            'minOrderQuantity': largeGroup[0].minOrderQuantity,
            'unittotalPrice': 0,
            'crateDisplay': '',
            'index': 0,
            'crateconversion': largeGroup[0].crateconversion
        };

        let validateCartProducts = JSON.parse(localStorage.getItem(this.storageKey)) || [];
        let productExisting = false;

        for (let key in validateCartProducts) {
            if (validateCartProducts[key].productId == this.objectOfProductToCart.productId) {
                productExisting = true;
                validateCartProducts[key].quantity += productQty;
                validateCartProducts[key].crateDisplay = this.getCrateDisplay(
                    validateCartProducts[key].quantity,
                    largeGroup[0].crateconversion
                );
                validateCartProducts[key].unittotalPrice = (validateCartProducts[key].quantity * largeGroup[0].productOfferPrice).toFixed(2);
                break;
            }
        }

        if (!productExisting) {
            this.objectOfProductToCart.quantity = productQty;
            this.objectOfProductToCart.unittotalPrice = (productQty * largeGroup[0].productOfferPrice).toFixed(2);
            this.objectOfProductToCart.crateDisplay = this.getCrateDisplay(productQty, largeGroup[0].crateconversion);
            this.objectOfProductToCart.index = validateCartProducts.length + 1;
            validateCartProducts.push(this.objectOfProductToCart);
        }

        largeGroup[0].productQuantity = 0;
        this.cartSize = validateCartProducts.length;
        localStorage.setItem(this.storageKey, JSON.stringify(validateCartProducts));
        this.productAddedForCart = validateCartProducts;
        this.prepareOrderSummary();
        this.showToast('', 'Item is added to cart', 'success');
        this.updateProductQuantitiesFromCart();
    }



//calculates the order summary section  by fetching tax rates from controller

prepareOrderSummary() {
  this.fetchTaxRates(); 
}

// get serializedCartItems() {
//     return this.productAddedForCart.map((item, index) => ({
//         ...item,
//         serialNumber: index + 1
//     }));
// }

 get serializedCartItems() {
        return this.productAddedForCart.map((item, index) => {
            const hasPromo =
                !item.isPromotional &&
                this.hasPromoForProduct(item.productId);

            return {
                ...item,
                serialNumber: index + 1,

                // 🔒 delete rules
                disableDelete: hasPromo
            };
        });
    }

calculateTotalCrates() {
    let totalCrates = 0;        // Sum of crates from products with crate conversion
    let totalEAFromCrates = 0;  // Remaining EA from crate-products
    let totalEAWithoutCrates = 0; // EA from products without crate conversion

    for (let item of this.productAddedForCart) {
        if (item.crateconversion && item.crateconversion > 0) {
            // Split quantity into crates + EA for this product
            const fullCrates = Math.floor(item.quantity / item.crateconversion);
            const remainingEA = item.quantity % item.crateconversion;

            totalCrates += fullCrates;
            totalEAFromCrates += remainingEA;
        } else {
            // Product without crate conversion → all quantity as EA
            totalEAWithoutCrates += item.quantity;
        }
    }

    // Build display string
    let result = '';
    if (totalCrates > 0 || totalEAFromCrates > 0) {
        result += `${totalCrates} Crate${totalCrates !== 1 ? 's' : ''}`;
        if (totalEAFromCrates > 0) {
            result += ` ${totalEAFromCrates} EA`;
        }
    }

    /*if (totalEAWithoutCrates > 0) {
        if (result !== '') result += ' + '; // separate non-crate EA
        result += `${totalEAWithoutCrates} EA (non-crate products)`;
    }*/

    return result || '0';
}



//used to process the fetched rates of order summary
// calculateOrderSummary(taxRates){
//   let totalItems = this.productAddedForCart.length;
//   let totalPrice = 0;
//   let totalDiscount = 0;
//   let totalQuantity = 0;
//   let totalOrderValue = 0;
//   let totalSGSTtax = 0;
//   let totalCGSTtax = 0;
//   let totalIGSTtax = 0;
//   let discountPercentAmount = 0;


//   for (let key in this.productAddedForCart) {
//     console.log('this.productAddedForCart[key].productListPrice ', this.productAddedForCart[key].productListPrice );
//     if (this.productAddedForCart[key].productListPrice > 0) {
//       totalPrice = totalPrice + (this.productAddedForCart[key].productOfferPrice * this.productAddedForCart[key].quantity);
//       console.log('productAddedForCart-  ', this.productAddedForCart[key].quantity );
//       totalQuantity = totalQuantity + this.productAddedForCart[key].quantity;
//     } else {
//       totalPrice = totalPrice + 0;
//       totalQuantity = totalQuantity + this.productAddedForCart[key].quantity;
//     }

//     if (this.productAddedForCart[key].productOfferPrice > 0) {
//       let discount = this.productAddedForCart[key].productListPrice * this.productAddedForCart[key].quantity;
//       totalOrderValue = totalOrderValue + discount;
//       totalDiscount = totalPrice - totalOrderValue;
//     } else {
//       let discount = 0 * this.productAddedForCart[key].quantity;
//       totalOrderValue = totalOrderValue + discount;
//       totalDiscount = totalPrice - totalOrderValue;
//     }
// //if (this.state.toLowerCase() === 'karnataka' || this.state.toLowerCase() === 'ka' ||(taxRates.SS == 1) ) {
//   if (taxRates.SS == 1 ||(this.state.toLowerCase() === 'karnataka' && taxRates.DD == 1 ) ) {      console.log(this.state);
//       totalSGSTtax += (this.productAddedForCart[key].productOfferPrice * this.productAddedForCart[key].quantity * taxRates.SGST) / 100;
//       totalCGSTtax += (this.productAddedForCart[key].productOfferPrice * this.productAddedForCart[key].quantity * taxRates.CGST) / 100;
//       this.percentSGST = taxRates.SGST; 
//       this.percentCGST = taxRates.CGST;
//       this.showtotalCGSTtax = true;
//       console.log('tax rate ka',taxRates.CGST)
//     } else if(taxRates.SS == 0 || taxRates.DD ==0 ) {
//       this.percentIGST = taxRates.IGST;
//       console.log('other');
//       totalIGSTtax += (this.productAddedForCart[key].productOfferPrice * this.productAddedForCart[key].quantity * taxRates.IGST) / 100;
//       console.log(totalIGSTtax);
//       this.showtotalIGSTtax = true;
//     }
//   }
  
//   this.orderSummary.totalItems = totalItems;
//   this.orderSummary.totalPrice = (totalPrice + totalIGSTtax + totalCGSTtax + totalSGSTtax).toFixed(2);
//   this.orderSummary.totalOrderValue = totalOrderValue.toFixed(2);
//   this.orderSummary.totalDiscount = totalDiscount;
//     console.log('totalQuantity-==  ', totalQuantity );
//   this.orderSummary.totalQuantity = totalQuantity;
//   this.orderSummary.totalSGST = totalSGSTtax.toFixed(2);
//   this.orderSummary.totalCGST = totalCGSTtax.toFixed(2);
//   this.orderSummary.totalIGST = totalIGSTtax.toFixed(2);
//   this.cartSize = this.productAddedForCart.length;
//   this.orderSummary.totalCrates = this.calculateTotalCrates();

// }

calculateOrderSummary(taxRates) {
    let totalItems = this.productAddedForCart.length;
    let totalQuantity = 0;

    let grossSubTotal = 0;        // Sum before value scheme
    let totalDiscount = 0;

    let totalSGSTtax = 0;
    let totalCGSTtax = 0;
    let totalIGSTtax = 0;

    // -------------------------------
    // 1️⃣ BUILD SUBTOTAL FROM CART
    // -------------------------------
    for (let item of this.productAddedForCart) {
        const qty = item.quantity || 0;

        // 🔑 TRUST CART PRICE (promo-safe)
        const unitTotal = Number(item.unittotalPrice || 0);

        const listTotal =
            (item.productListPrice || 0) * qty;

        totalQuantity += qty;
        grossSubTotal += unitTotal;

        // product-level discount (promo / scheme)
        totalDiscount += Math.max(0, listTotal - unitTotal);
    }

    // -------------------------------
    // 2️⃣ APPLY VALUE SCHEME DISCOUNT
    // -------------------------------
    let discountedSubTotal = grossSubTotal;

    if (this.discountAmountGiven && this.discountAmountGiven > 0) {
        discountedSubTotal = grossSubTotal - this.discountAmountGiven;
        this.orderSummary.totalDiscount =
            this.discountAmountGiven.toFixed(2);

        localStorage.setItem(
            'discountAmountGiven',
            this.discountAmountGiven.toString()
        );
    }

    if (this.discountPercemtageGiven && this.discountPercemtageGiven > 0) {
        const percentDiscountAmount =
            (discountedSubTotal * this.discountPercemtageGiven) / 100;

        discountedSubTotal -= percentDiscountAmount;

        this.discountPercentageAmount =
            percentDiscountAmount.toFixed(2);

        this.orderSummary.totalDiscount =
            this.discountPercentageAmount;

        localStorage.setItem(
            'discountPercemtageGiven',
            this.discountPercemtageGiven.toString()
        );
        localStorage.setItem(
            'discountPercentageAmount',
            this.discountPercentageAmount.toString()
        );
    }

    // Safety guard
    if (discountedSubTotal < 0) {
        discountedSubTotal = 0;
    }

    // -------------------------------
    // 3️⃣ TAX CALCULATION (POST-DISCOUNT ✅)
    // -------------------------------
    if (
        taxRates?.SS === 1 ||
        (this.state?.toLowerCase() === 'karnataka' && taxRates?.DD === 1)
    ) {
        totalSGSTtax =
            (discountedSubTotal * (taxRates?.SGST || 0)) / 100;
        totalCGSTtax =
            (discountedSubTotal * (taxRates?.CGST || 0)) / 100;

        this.showtotalCGSTtax = true;
        this.showtotalIGSTtax = false;
    } else {
        totalIGSTtax =
            (discountedSubTotal * (taxRates?.IGST || 0)) / 100;

        this.showtotalIGSTtax = true;
        this.showtotalCGSTtax = false;
    }

    // -------------------------------
    // 4️⃣ FINAL SUMMARY VALUES
    // -------------------------------
    this.orderSummary.totalItems = totalItems;
    this.orderSummary.totalQuantity = totalQuantity;

    this.orderSummary.totalOrderValue =
        discountedSubTotal.toFixed(2);

    this.orderSummary.totalSGST =
        totalSGSTtax.toFixed(2);
    this.orderSummary.totalCGST =
        totalCGSTtax.toFixed(2);
    this.orderSummary.totalIGST =
        totalIGSTtax.toFixed(2);

    this.orderSummary.totalPrice = (
        discountedSubTotal +
        totalSGSTtax +
        totalCGSTtax +
        totalIGSTtax
    ).toFixed(2);

    this.orderSummary.totalCrates =
        this.calculateTotalCrates();

    // -------------------------------
    // 5️⃣ VALUE SCHEME TRACKING
    // -------------------------------
    if (this.valueSchemFinalId) {
        this.orderSummary.valuseSchemeIdOnOrder = this.valueSchemFinalId;
        this.orderSummary.valueSchemeDiscount = this.discountAmountGivenCheck ? Number(this.discountAmountGiven || 0)
        : this.discountPercemtageGivenCheck ? Number(this.discountPercentageAmount || 0) : 0;
    }

    // Used for value scheme eligibility
    this.totalCartPrice =
        discountedSubTotal.toFixed(2);
}



// - Quantity from AddToCart
minusQuantity(event) {
  /*const element = this.template.querySelector('[data-id=' + event.target.name + ']');
  this.quantityValue = (parseInt(element.value) - 1) > 0 ? parseInt(element.value) - 1 : 0;*/
    const productId = event.target.name; // Use product ID to identify the correct product
    const element = this.template.querySelector (`[data-id="${productId}"]`);
  
  const product = this.data.find(prod => prod.productId === productId);
  console.log(product);
    if (product) {
      product.productQuantity = (parseInt(element.value) - 1) > 0 ? parseInt(element.value) - 1 : 0;
  }
}


// + Quantity from AddToCart
addtionQuantity(event) {
  /*const element = this.template.querySelector('[data-id=' + event.target.name + ']');
  this.quantityValue = parseInt(element.value) + 1;*/
  const productId = event.target.name; // Use product ID to identify the correct product
  const element = this.template.querySelector (`[data-id="${productId}"]`);
  
  // Find the product in the products list and update its quantity
  const product = this.data.find(prod => prod.productId === productId);
  
  if (product) {
      product.productQuantity = parseInt(element.value) + 1;
  }

}

// Quantity Changefrom AddToCart
valueQtyHandle(event) {
    console.log(event.target.value);
    const productId = event.target.dataset.id;
    const newQuantity = event.target.value;

    // Find the product in the list and update the quantity
    const product = this.data.find(prod => prod.productId === productId);
    if (product) {
        product.productQuantity = parseInt(newQuantity, 10) || 0; // Ensure the value is a number
    }
}

ooenCartModal() {
    console.log('Cart modal opened');
  this.openCart = true;   
  this.ShowprodutcList =false; 
  this.fetchTaxRates();
}

closeCart() {    
  this.openCart = false;
  this.ShowprodutcList = true;
}

// - Quantity from Cart Update
minusQuantityCart(event) {

  let nameOf = String(event.target.name);
  console.log('nameOf'+nameOf);
  for (let key in this.productAddedForCart) {
    let tempCartId = this.productAddedForCart[key];

    if (tempCartId.productIdForCart == nameOf) {
      tempCartId.quantity = (tempCartId.quantity - 1) >= 1 ? tempCartId.quantity - 1 : tempCartId.quantity;
      tempCartId.crateDisplay =  this.getCrateDisplay(tempCartId.quantity, tempCartId.crateconversion);
      tempCartId.unittotalPrice = (tempCartId.quantity * tempCartId.productOfferPrice).toFixed(2);
      if (!tempCartId.isPromotional && tempCartId.selectedSchemeId) {
                this.reapplySchemeForBase(tempCartId.productId);
                return;
            }
    }

  }
  this.removeInvalidPromos();
  this.prepareOrderSummary();
  this.recomputeSchemeEligibility();
  localStorage.setItem(this.storageKey, JSON.stringify(this.productAddedForCart));
  this.updateAllCalculateCheck();
   this.removeStoredValues();
this.updateProductQuantitiesFromCart();
}

// + Quantity from Cart Update
additionQuantityCart(event) {
  console.log('event = ',+event.target.name);
  const nameOf = String(event.target.name); // Get the name (productId) of the clicked button
  for (let key in this.productAddedForCart) {
      const tempCartItem = this.productAddedForCart[key];
      // Ensure comparison uses consistent data types
      if (tempCartItem.productIdForCart === nameOf) {
          tempCartItem.quantity += 1; // Increment the quantity
          tempCartItem.crateDisplay = this.getCrateDisplay(tempCartItem.quantity, tempCartItem.crateconversion);
          tempCartItem.unittotalPrice = (tempCartItem.quantity * tempCartItem.productOfferPrice).toFixed(2);
          if (!tempCartItem.isPromotional && tempCartItem.selectedSchemeId) {
                    this.reapplySchemeForBase(tempCartItem.productId);
                    return; // prevent double calc
            }
          this.recomputeSchemeEligibility();
          break; // Exit the loop as the item has been found
      }
  }

  // Update cart summary and sync with localStorage
  this.removeInvalidPromos();
  this.prepareOrderSummary();
  localStorage.setItem(this.storageKey, JSON.stringify(this.productAddedForCart));
  this.updateProductQuantitiesFromCart();
}


// Value Change Quantity from Cart Update
/*valueQtyHandleCart(event) {
  let quantityValue = +parseInt(event.target.value);
  if(quantityValue <= 0){
    this.showToast('Error', 'Please enter a valid quantity.', 'error');
          return;
  }
  let nameOf = String(event.target.name);
  for (let key in this.productAddedForCart) {
    let tempCartId = this.productAddedForCart[key];
    if (tempCartId.productIdForCart == nameOf) {
      tempCartId.quantity = quantityValue <= 1 ? 1 : quantityValue;
      tempCartId.unittotalPrice = (tempCartId.quantity * tempCartId.productOfferPrice).toFixed(2); 
      tempCartId.crateDisplay = this.getCrateDisplay(tempCartId.quantity, tempCartId.crateconversion);
    }

  }
  this.prepareOrderSummary();

localStorage.setItem(this.storageKey, JSON.stringify(this.productAddedForCart));
}*/

valueQtyHandleCart(event) {
    this.updateAllCalculateCheck();
    this.removeStoredValues();
    let quantityValue = +parseInt(event.target.value);
    if (quantityValue <= 0) {
        this.showToast('Error', 'Please enter a valid quantity.', 'error');
        return;
    }

    let nameOf = String(event.target.name);
    for (let key in this.productAddedForCart) {
        let tempCartId = this.productAddedForCart[key];
        
        if (tempCartId.productIdForCart === nameOf) {
            const minOrderQuantity = tempCartId.minOrderQuantity || 1; // fallback to 1
            const showMOQ = tempCartId.showMOQ;

            if (showMOQ && minOrderQuantity > 0 && quantityValue % minOrderQuantity !== 0) {
                this.showToast(
                    'Invalid Quantity',
                    `Please enter quantity in multiples of ${minOrderQuantity} (MOQ)`,
                    'error'
                );
                return;
            }

            tempCartId.quantity = quantityValue;
            tempCartId.unittotalPrice = (tempCartId.quantity * tempCartId.productOfferPrice).toFixed(2);
            tempCartId.crateDisplay = this.getCrateDisplay(tempCartId.quantity, tempCartId.crateconversion);
            if (!tempCartId.isPromotional && tempCartId.selectedSchemeId) {
                    this.reapplySchemeForBase(tempCartId.productId);
                    return;
            }
            break; // Exit loop once item is updated
        }
    }
    this.removeInvalidPromos();
    this.prepareOrderSummary();
    this.recomputeSchemeEligibility();
    localStorage.setItem(this.storageKey, JSON.stringify(this.productAddedForCart));
}


//Remove product from Cart
removeProductFromCart(event) {

     const itemToRemove = this.productAddedForCart.find(
            item => item.productIdForCart === event.target.name
        );

        // 🛑 SAFETY GUARD (NEW)
        if (itemToRemove && !itemToRemove.isPromotional) {
            const hasPromo = this.productAddedForCart.some(
                p =>
                    p.isPromotional &&
                    p.parentProductId === itemToRemove.productId
            );

            if (hasPromo) {
                this.showToast(
                    'Remove Promo First',
                    'Please remove the promotional item before deleting this product.',
                    'warning'
                );
                return; // ❌ stop deletion
            }
        }
  
  this.productAddedForCart = this.productAddedForCart.filter(item => item.productIdForCart !== event.target.name)
  if(this.productAddedForCart.length === 0){
    this.showToast('', 'Cart is Empty', 'info');
    this.cartSize = 0;
    this.orderSummary.totalItems = 0;
    this.orderSummary.totalQuantity = 0;
    this.priceBeforeDiscount = 0;
    this.discountPercentageAmount = 0;
    this.discountAmountGiven = 0;
    this.orderSummary.totalOrderValue = 0;
    this.orderSummary.totalCGST = 0;
    this.orderSummary.totalSGST = 0;
    this.orderSummary.totalIGST = 0;
    this.totalOrderAmount = 0;
    localStorage.removeItem(this.storageKey);
    this.closeCart();
    return;
  }
  this.prepareOrderSummary();
    localStorage.setItem(this.storageKey, JSON.stringify(this.productAddedForCart));
    this.updateAllCalculateCheck();
    this.removeStoredValues();

}

      //This method is used to updateAllCalculateCheck variables
    updateAllCalculateCheck(){
        this.discountPercemtageGivenCheck=false;
        this.discountAmountGivenCheck=false;
        this.discountAmountGiven=0
        this.discountPercemtageGiven=0;
        this.discountPercemtageGivenCheck=0;
        this.priceAfterDiscount=0;
        this.valueSchemFinalId='';
        this.ValueSchemeFinalName='';
        this.ValueSchemeExist=false;
        this.showtotalCGSTtax=false;
        this.showtotalIGSTtax=false;
    }

//fetch tax rated from controller
  fetchTaxRates() {
  getTaxRates({ state: this.state })
    .then((taxRates) => {
      console.log('taxxx- ',+taxRates);
      this.calculateOrderSummary(taxRates);
    })
    .catch((error) => {
      console.error('Error fetching tax rates:', error);
    });
}

//method to generate proposal by placing primary order

    /*generateProposalAndCloseCart() {
      if (this.isOrderPlaced) {
          return; // Prevent further clicks if already in progress
      }
  
      if (this.cartSize === 0) {
          this.showToast('', 'Please Add Products To Generate Proposal', 'error');
      } else {
          this.isOrderPlaced = true; // Disable the button right away
          this.generateProposal();
      }
  }*/

  generateProposalAndCloseCart() {
    if (this.isOrderPlaced) {
        return; // Prevent duplicate clicks
    }

    if (this.cartSize === 0) {
        this.showToast('', 'Please Add Products To Generate Proposal', 'error');
        return;
    }

    // ✅ Validate MOQ for all items before proceeding
    for (let key in this.productAddedForCart) {
        const cartItem = this.productAddedForCart[key];
        const quantity = cartItem.quantity;
        const moq = cartItem.minOrderQuantity || 1;
        const showMOQ = cartItem.showMOQ;

        if (showMOQ && moq > 0 && (quantity % moq !== 0)) {
            this.showToast(
                'Invalid Quantity',
                `Product "${cartItem.productName}" must be ordered in multiples of ${moq} (MOQ)`,
                'error'
            );
            return;
        }
    }

    // ✅ All validations passed
    this.isOrderPlaced = true;
    this.generateProposal();
  }

  
  generateProposal() {
      const finanJSONfromProposal = JSON.stringify(this.productAddedForCart);
      generateProposal({ productsFromCart: finanJSONfromProposal, orderComment: this.comment, orderSummary: JSON.stringify(this.orderSummary) })
          .then(result => {
              console.log('result-->' + result.ordid);
              if (result.isSuccess) {
                  this.showToast('', 'Congratulations! You have successfully placed an order.', 'success');
                    // Clear the cart
                  this.productAddedForCart = [];
                  this.cartSize = 0;
                  this.recordId = result.ordid;
                  this.orderSummary = {
                      'totalItems': 0,
                      'totalPrice': 0,
                      'totalDiscount': 0,
                      'totalOrderValue': 0,
                      'totalQuantity': 0,
                      'totalSGST': 0,
                      'totalCGST': 0,
                      'totalCrates':'0 Crate'
                  };
                  localStorage.removeItem(this.storageKey); // Clear the cart from localStorage
                  
                  
                  setTimeout(() => {},0.9);
                  this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.recordId, // The record ID to navigate to
                objectApiName: 'Order__c', // Replace with your object's API name
                actionName: 'view' // The action to perform (view = record detail page)
            }
        });
              } else {
                  this.isOrderPlaced = false; // Re-enable the button if not successful
                   this.updateAllCalculateCheck();
                   this.removeStoredValues();
              }
          })
          .catch(error => {
              console.error('error = ',error);
              let errorMessage = 'An unexpected error occurred while placing the order.';
              if (error && error.body && error.body.message) {
                errorMessage = error.body.message;
                }

                console.error('errorMessage = ',errorMessage);
                this.showToast('Error', errorMessage, 'error');
              this.isOrderPlaced = false; // Re-enable the button if there is an error
          });
  }


goBackToMainPage(){
  
     
  
    
}

showToast(tilte, message, variant) {
  const event = new ShowToastEvent({
    title: tilte,
    message: message,
    variant: variant
  });
  this.dispatchEvent(event);
}
/*loadCartFromStorage(visitId) {
  const savedCart = sessionStorage.getItem(`cart_${visitId}`);
  if (savedCart) {
      this.productAddedForCart = JSON.parse(savedCart);
  }
}*/


     @wire(getRecord, {
            recordId: '$selectedAccountId',
            fields: [ACCOUNT_REGION]
        })
        wiredAccount({ data, error }) {
            if (data) {
                this.buyerRegion = data.fields.Primary_State__c.value;
                console.log('Buyer Region from Account:', this.buyerRegion);
            } 
            else if (error) {
                console.error('Error fetching Account Region:', error);
            }
        }
    
    
        openSchemeFromProduct(event) {
            this.schemeSource = 'PRODUCT';
            this.activeProductId = event.currentTarget.dataset.productId;
            this.openDialogForQualityScheme(this.activeProductId);
        }
    
        openSchemeFromCart(event) {
            this.schemeSource = 'CART';
            this.isCartContext = true;
            this.activeProductId = event.currentTarget.dataset.productId;
            this.openDialogForQualityScheme(this.activeProductId);
        }
    
        getCurrentProductQty(productId) {
            const item = this.productAddedForCart.find(
                p => p.productId === productId && !p.isPromotional
            );
            return item ? item.quantity : 0;
        }
    
        recomputeSchemeEligibility() {
            if (!this.isQualityScheme || !this.activeProductId) return;
    
            const currentQty = this.getCurrentProductQty(this.activeProductId);
    
            this.schemeDetails = this.schemeDetails.map(s => ({
                ...s,
                isDisabled: currentQty < s.minQty
            }));
        }
    
    
        openDialogForQualityScheme(productId) {
            //const productId = event.currentTarget.dataset.productId;
            const currentQty = this.getCurrentProductQty(productId);
            
            this.selectedSchemeId = null;   
    
            console.log('openDialogForQualityScheme productId', productId);
    
            if (!productId ) {
                console.warn('Missing context for quantity scheme');
                return;
            }
    
            getqualityScheme({
                productId: productId
            })
            .then(result => {

                console.log('openDialogForQualityScheme result', result);
                // ✅ ALWAYS normalize to array
               // this.schemeDetails = Array.isArray(result) ? result : [];
                this.schemeDetails = (Array.isArray(result) ? result : []).map(s => ({
                    ...s,
                    isDisabled: currentQty < s.minQty
                }));
    
                this.isQualityScheme = true;   
                //this.ShowprodutcList = true;
    
                if (this.schemeDetails.length === 0) {
                    this.noSchemeMessage = NO_SCHEME_AVAILABLE;
                } else {
                    this.noSchemeMessage = '';
                }
            })
            .catch(error => {
                this.schemeDetails = [];
                this.noSchemeMessage = NO_SCHEME_AVAILABLE;
                this.isQualityScheme = true;  
    
                console.error('Error fetching quantity schemes');
                console.error(error?.body?.message);
            });
    
    
        }
    
        get hasSchemes() {
            return this.schemeDetails && this.schemeDetails.length > 0;
        }
    
    
      //This method is used close dialof box for Quantity schemes
        closeQualitySchemeDialog() {
            this.isQualityScheme = false; // Set the flag to false to hide the modal
            //this.ShowprodutcList=true;
        }
    
    
        handleSchemeSelection(event) {
            const selectedId = event.target.value;
            this.selectedSchemeId = selectedId;
    
            this.schemeDetails = this.schemeDetails.map(s => ({
                ...s,
                isSelected: s.schemeId === selectedId
            }));
        }
    
        get isApplyDisabled() {
            return !this.selectedSchemeId;
        }
    
        applyScheme() {
        const cart = JSON.parse(localStorage.getItem(this.storageKey)) || [];

            applyQuantityScheme({
                cartItems: cart,
                selectedSchemeId: this.selectedSchemeId
            })
            .then(promoLines => {

                const baseProductId = this.activeProductId;

                // 1️⃣ Remove existing promos for this base product
                let cleanedCart = cart.filter(
                    i => !(i.isPromotional && i.parentProductId === baseProductId)
                );

                // 2️⃣ Find base product index
                const baseIndex = cleanedCart.findIndex(
                    i => i.productId === baseProductId && !i.isPromotional
                );

                if (baseIndex === -1) {
                    return; // safety
                }

                // 3️⃣ Insert promos immediately after base
                promoLines.forEach((promo, idx) => {
                    cleanedCart.splice(baseIndex + 1 + idx, 0, {
                        ...promo,
                        productIdForCart: promo.productId + '_PROMO_' + Date.now() + idx,
                        isReadOnly: true
                    });
                });
                const baseItem = cleanedCart.find(
                    i => i.productId === baseProductId && !i.isPromotional
                );
                if (baseItem) {
                    baseItem.selectedSchemeId = this.selectedSchemeId;
                }

                // 4️⃣ Update cart
                this.productAddedForCart = [...cleanedCart];
                this.prepareOrderSummary();
                localStorage.setItem(this.storageKey, JSON.stringify(this.productAddedForCart));

                this.isQualityScheme = false;
            
            });
    }

  hasPromoForProduct(baseProductId) {
        return this.productAddedForCart.some(
            item =>
                item.isPromotional &&
                item.parentProductId === baseProductId
        );
    }

    removeInvalidPromos() {
        const baseQtyMap = new Map();

        // Build base product quantity map
        this.productAddedForCart.forEach(item => {
            if (!item.isPromotional) {
                baseQtyMap.set(item.productId, item.quantity);
            }
        });

        const before = this.productAddedForCart.length;

        // Remove promo if base qty < promoMinQty
        this.productAddedForCart = this.productAddedForCart.filter(item => {
            if (!item.isPromotional) return true;

            const baseQty = baseQtyMap.get(item.parentProductId);
            return baseQty >= item.promoMinQty;
        });

        if (this.productAddedForCart.length !== before) {
            localStorage.setItem(
                this.storageKey,
                JSON.stringify(this.productAddedForCart)
            );
        }
    }

    fetchProductSchemes() {
        console.log('FETCH SCHEMES RUNNING');

        console.log(
        'CART BEFORE SCHEME MAP',
        JSON.parse(JSON.stringify(this.productAddedForCart))
        );

        getProductsWithSchemes()
        .then((schemeMap) => {
            this.schemeMap = schemeMap;

            this.productAddedForCart = this.productAddedForCart.map(product => {

                // ✅ DO NOT TOUCH PROMO LINES
                if (product.isPromotional) {
                    return product;
                }

                const schemeDetails = schemeMap[product.productId];

                if (!schemeDetails || schemeDetails.length === 0) {
                    return {
                        ...product,
                        selectedScheme: 'No Scheme',
                        availableSchemes: []
                    };
                }

                return {
                    ...product,
                    availableSchemes: schemeDetails,
                    selectedScheme:
                        product.selectedSchemeId
                            ? schemeDetails.find(s => s.Id === product.selectedSchemeId)?.Name
                            : 'Scheme Available',
                    schemeNeedsRevalidation: false
                };
            });
        });
    }

      //  this method called to  getvalueScheme
    openDialogForValueScheme(event){
        //const cartPrice=orderSummary.totalOrderValue;
        console.log('this.totalCartPrice',this.totalCartPrice);

        if (!this.totalCartPrice) {
            console.warn('Missing context for value scheme');
            return;
        }
        getvalueScheme({totalCartPrice:this.totalCartPrice})
        .then(result => {
            console.log('VALUE SCHEME RESULT', result);
            if (result && result.length > 0) {
            
                        // Check if valueSchemFinalId exists in the result
                        if (this.valueSchemFinalId) {
                            result = result.map(scheme => {
                                if (scheme.id === this.valueSchemFinalId) {
                                    return { ...scheme, isApplied: true }; // Update isApplied to true
                                }
                                return scheme;
                            });
                            // Reorder the list to move the record with isApplied: true to the top
                            result.sort((a, b) => (b.isApplied ? 1 : 0) - (a.isApplied ? 1 : 0));
                        }
                this.valueSchemeDetails = result; // Assign the array of scheme details
                this.isValueScheme = true; // Show the dialog if there are schemes
                this.isNoSchemesMessage = false; // Hide the no scheme message
                this.openCart=true;
            } else {
                // If no schemes are found, add the message to valueSchemeDetails
                this.isNoSchemesMessage = true; // Show the no scheme message
                this.isValueScheme = true; // Show the dialog even if there are no schemes
                this.noSchemesMessage=NO_Cart_SCHEME_AVAILABLE;
                this.openCart=true;
        }
    })
    .catch(error => {
        console.error('Error retrieving getvalueScheme:', error);
        console.error('FULL ERROR:', JSON.stringify(error));
        console.error('BODY MESSAGE:', error?.body?.message);
        console.error('ERROR MESSAGE:', error?.message);
    });
    }

     //This method is used close dialog box for Values schemes on cart page
    closeValueSchemeDialog() {
        this.isValueScheme = false; // Set the flag to false to hide the modal
        this.openCart=true;
    }

     // this method for List of keys to remove
    removeStoredValues() {
        const keysToRemove = [
            'valueSchemFinalId',
            'ValueSchemeFinalName',
            'discountAmountGivenCheck',
            'discountPercemtageGivenCheck',
            'discountAmountGiven',
            'discountPercemtageGiven',
            'discountPercentageAmount',
            'priceAfterDiscount',
            'ValueSchemeExist',
        ];
    
        // Loop through each key and remove it
        keysToRemove.forEach((key) => {
            localStorage.removeItem(key);
        });
    }
  // this method used to fetch values from local stoarage
    getstoreInLocalStorage() {
        // Retrieve data from localStorage
        this.valueSchemFinalId = localStorage.getItem('valueSchemFinalId') || '';
        this.ValueSchemeFinalName = localStorage.getItem('ValueSchemeFinalName') || '';
        this.discountAmountGivenCheck=localStorage.getItem('discountAmountGivenCheck') || false;
        this.discountPercemtageGivenCheck=localStorage.getItem('discountPercemtageGivenCheck') || false;
        this.discountAmountGiven = localStorage.getItem('discountAmountGiven') || 0; // Default to 0 if not found
        this.discountPercemtageGiven = localStorage.getItem('discountPercemtageGiven') || 0;
        this.discountPercentageAmount = localStorage.getItem('discountPercentageAmount') || 0; // Default to 0 if not found
        this.priceAfterDiscount = localStorage.getItem('priceAfterDiscount') || 0;
        this.ValueSchemeExist=localStorage.getItem('ValueSchemeExist') || false;
        //this.fetchTaxRates();
        this.comment = localStorage.getItem('commentGiven') || '';
    }

     // this method called when applu button is clicked
    applyButtonClicked(event){
        
        this.clearExistingValueScheme();
        this.removeStoredValues();
        this.isValueScheme = false; // Set the flag to false to hide the modal
        this.openCart=true;
        const valueSchemId = event.target.dataset.applyId; // Use dataset to access custom data attributes
        this.valueSchemFinalId=valueSchemId;
        localStorage.setItem('valueSchemFinalId', this.valueSchemFinalId.toString());
        this.discountPercemtageGivenCheck=false;
        this.discountAmountGivenCheck=false;
        this.discountAmountGiven=0
        this.discountPercemtageGiven=0;
        this.discountPercemtageGivenCheck=0;
        this.priceAfterDiscount=0;

            // Storing values in localStorage
        
        getAppliedValueScheme({ valueSchemId: valueSchemId})
        .then(result => {
            console.log('discountAmountGiven is : ',result.discountAmount);
            console.log('discountPercemtageGiven is : ',result.discountPercentage);
            this.getAppliedValueSchemeNameMethod();
            if(result.discountAmount!='undefined' && result.discountAmount!=null){
                    this.discountAmountGiven=result.discountAmount;
                    this.discountAmountGivenCheck=true;
                    this.discountPercemtageGivenCheck=false;
                    this.fetchTaxRates(); 
                    //this.getAppliedValueSchemeNameMethod();
                    localStorage.setItem('discountAmountGivenCheck', 'true');
            }
            else  if(result.discountPercentage!='undefined' && result.discountPercentage!=null){
                this.discountPercemtageGiven=result.discountPercentage;
                this.discountPercemtageGivenCheck=true;
                this.discountAmountGivenCheck=false;
                this.fetchTaxRates(); 
                //this.getAppliedValueSchemeNameMethod();
                localStorage.setItem('discountPercemtageGivenCheck', 'true');                      
            }
            else {
                // If neither condition is met, clear both values from localStorage
                localStorage.removeItem('discountAmountGivenCheck');
                localStorage.removeItem('discountPercemtageGivenCheck');
            }

             if (result.schemeType === 'Free Product' && result.freeProductId) {
                const promoQty =
                    result.promoQty !== undefined && result.promoQty !== null
                        ? result.promoQty
                        : 1;

                console.log('Promo Qty from backend:', promoQty);

                this.addValuePromoProduct(result.freeProductId, promoQty);
            }
            this.prepareOrderSummary();
        })
        .catch(error => {
            console.error('Error in applyButtonClicked:', error);
        });
    
    }

    addValuePromoProduct(productId, promoQty) {
        // ❌ Prevent duplicates
        if (
            this.productAddedForCart.some(
                p => p.isPromotional && p.productId === productId
            )
        ) {
            return;
        }

        getProductForValueScheme({ productId })
            .then(product => {

                const promo = {
                    ...product,

                    productIdForCart: product.productId + '_VALUE_PROMO',

                    quantity: promoQty,
                    isPromotional: true,
                    promoType: 'VALUE',
                    parentProductId: null,
                    isReadOnly: true,

                    // price safety
                    productOfferPrice: 0,
                    unittotalPrice: 0
                };

                this.productAddedForCart.push(promo);

                localStorage.setItem(
                    this.storageKey,
                    JSON.stringify(this.productAddedForCart)
                );

                this.prepareOrderSummary();
            })
            .catch(error => {
                console.error('Failed to load promo product details', error);
            });
    }

  // this method called to set AppliedValueScheme
    getAppliedValueSchemeNameMethod() {
    getAppliedValueSchemeName({ valueSchemActiveId: this.valueSchemFinalId })
        .then(result => {
            if(result!=null && result!=='' && result!=undefined)
            {
                this.ValueSchemeExist=true;
                this.ValueSchemeFinalName=result;
                localStorage.setItem('ValueSchemeFinalName', this.ValueSchemeFinalName.toString());
                localStorage.setItem('ValueSchemeExist', this.ValueSchemeExist.toString());
            }
        })
        .catch(error => {
            console.error('Error in getAppliedValueSchemeNameMethod:', error);
        });
    }

     clearExistingValueScheme() {

              // Remove ONLY value scheme promos
              this.productAddedForCart = this.productAddedForCart.filter(
                  item => !(item.isPromotional && item.promoType === 'VALUE')
              );

              // Clear discount state
              this.discountAmountGiven = 0;
              this.discountPercemtageGiven = 0;
              this.discountAmountGivenCheck = false;
              this.discountPercemtageGivenCheck = false;
              this.discountPercentageAmount = 0;
              this.priceAfterDiscount = 0;

              this.valueSchemFinalId = '';
              this.ValueSchemeFinalName = '';
              this.ValueSchemeExist = false;

              // Clear localStorage
              this.removeStoredValues();

              localStorage.setItem(
                  'cartItems',
                  JSON.stringify(this.productAddedForCart)
              );
          }

          reapplySchemeForBase(baseProductId) {
        const base = this.productAddedForCart.find(
            i => i.productId === baseProductId && !i.isPromotional
        );

        if (!base || !base.selectedSchemeId) return;

        // Call Apex again
        applyQuantityScheme({
            cartItems: this.productAddedForCart,
            buyerAccountId: this.selectedAccountId,
            buyerRegion: this.buyerRegion,
            selectedSchemeId: base.selectedSchemeId,
            isUnderSS: false
        })
        .then(promoLines => {
            // Remove old promos
            let cleaned = this.productAddedForCart.filter(
                i => !(i.isPromotional && i.parentProductId === baseProductId)
            );

            const baseIndex = cleaned.findIndex(
                i => i.productId === baseProductId && !i.isPromotional
            );

            promoLines.forEach((p, idx) => {
                cleaned.splice(baseIndex + 1 + idx, 0, {
                    ...p,
                    productIdForCart: p.productId + '_PROMO_' + Date.now() + idx,
                    isReadOnly: true
                });
            });

            this.productAddedForCart = [...cleaned];
            localStorage.setItem(this.storageKey, JSON.stringify(this.productAddedForCart));
            this.prepareOrderSummary();
        });
    }

}