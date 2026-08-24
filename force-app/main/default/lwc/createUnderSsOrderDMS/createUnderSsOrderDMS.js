import { LightningElement, api, track, wire} from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import fetchProducts from '@salesforce/apex/UnderSsOrderComponentController.fetchProducts'
import generateProposal from '@salesforce/apex/UnderSsOrderComponentController.generateProposal'
import getTaxRates from '@salesforce/apex/UnderSsOrderComponentController.getTaxRates';
import fetchFocusedProducts from '@salesforce/apex/UnderSsOrderComponentController.fetchFocusedProducts';
import NO_Cart_SCHEME_AVAILABLE  from '@salesforce/label/c.No_Cart_Value_Scheme';
import productCodeLabel from '@salesforce/label/c.Product_Code';
import getqualityScheme from '@salesforce/apex/SchemeEvaluationService.getqualityScheme';
import getProductsWithSchemes from '@salesforce/apex/OrderProductController.getProductsWithSchemes';
import getvalueScheme from '@salesforce/apex/SchemeEvaluationService.getvalueScheme';
import getAppliedValueScheme from '@salesforce/apex/SchemeEvaluationService.getAppliedValueScheme';
import getAppliedValueSchemeName from '@salesforce/apex/SchemeEvaluationService.getAppliedValueSchemeName';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';
import ACCOUNT_REGION from '@salesforce/schema/Account.Primary_State__c';
import applyQuantityScheme from '@salesforce/apex/SchemeEvaluationService.applyQuantityScheme';
import getProductForValueScheme from '@salesforce/apex/SchemeEvaluationService.getProductForValueScheme';
import isOrderDateAllowed from '@salesforce/apex/SecondaryOrderComponentController.isOrderDateAllowed';

export default class CreateUnderSsOrderDms extends NavigationMixin(LightningElement) {
    @api storageKey = 'secondaryCart'; // Dynamic storage key with secondary order value
    @api retailer;
    @track isLoading = false;
    openCart = false;
    @track ShowprodutcList= true;
    @track searchValue = '';
    @track ShowfocusedProdutcList= false;
    @track selectedBrands ='' ;
    @track stockFilter ='' ;
    isOrderPlaced = false;
    @track allTAX=0;
    @track allowOrderDateSelection = false;
    @track isQualityScheme=false;
    @track isQualityFocusScheme=false;
    @track isValueScheme=false;
    @track schemeDetails = []; // Reset the scheme details
    @track valueSchemeDetails = []; // Reset the scheme details
    @track isNoSchemesMessage = false;
    @track noSchemesMessage = '';
    @track comment='';
    @track discountAmountGiven=0;
    @track discountAmountGivenCheck=false;
    @track discountPercemtageGiven=0;
    @track discountPercemtageGivenCheckca=0;
    @track priceAfterDiscount=0;
    @track discountPercentageAmount=0;
    @track objectOfProductToCart;
    @track valueSchemFinalId='';
    @track ValueSchemeFinalName='';
    @track ValueSchemeExist=false;
    @track latestOrders = [];
    selectedProductIdForDetailPage;
    productSlides = [];
    @track cartItems = [];
    cartSize = 0;
    @track productAddedForCart = [];
    @track quantityValue = 0;
    @track availableBrands = [];
    @track availableBrandsFocus = [];
    @track showBrandDropdown = false;  
    @track showAvailableStockDropdown = false;
    @track selectedBrandFromDropdown = 'All';  
    @track allBrandsList = [];
    @track allTabDisplayText = 'All';
    @track availableStockTabDisplayText = 'Available Stock';
    
    // added by Fuzail - Search By: 'Name' = default search (product name/brand), 'Code' = search by Product_Code__c (reactive)
    @track searchBy = 'Name';
    @track searchByDisplayText = 'Name';
    @track showSearchByDropdown = false;
    
    // Focused products dropdown variables
    @track showBrandDropdownFocus = false;  
    @track showAvailableStockDropdownFocus = false;
    @track selectedBrandFromDropdownFocus = 'All';  
    @track allBrandsListFocus = [];
    @track allTabDisplayTextFocus = 'All';
    @track availableStockTabDisplayTextFocus = 'Available Stock';
    
    // added by Fuzail - Search By for focused products (same: Name / Code)
    @track searchByFocus = 'Name';
    @track searchByDisplayTextFocus = 'Name';
    @track showSearchByDropdownFocus = false;
    
    // added by Fuzail - debounce timeouts for reactive search (oninput) to avoid too many Apex calls per keystroke
    searchDebounceTimeout;
    searchFocusedDebounceTimeout;
    
    // Custom brand order for dropdown
    brandOrder = [
        'Cones',
        'Gourmet',
        'Sticks',
        'Tubs 125 ml',
        'Tubs 1000 ml',
        'Tubs 1500 ml',
        'Bulk Packs 4000 ml',
        'Tubs 500 ml',
        'Parlour Tubs 4000 ml',
        'Cups',
        'Ball',
        'Sip Up'
    ];
    
    // Method to sort brands according to custom order
    sortBrandsByCustomOrder(brands) {
        //added by Fuzail - alphabetically sort brands
        const sortedBrands = [...brands].sort((a, b) => {
            return a.localeCompare(b, undefined, { sensitivity: 'base' });
        });
        return sortedBrands;
    }  
    showtotalIGSTtax = false;
    showtotalCGSTtax = false;
    percentIGST = 0;
    percentCGST = 0;
    percentSGST = 0;
    totalOrderAmount = 0;
    //order Summary
    @track orderSummary = {
        'totalItems': 0,
        'totalPrice': 0,
        'totalDiscount': 0,
        'totalOrderValue': 0,
        'totalQuantity': 0,
        'totalSGST' : 0,
        'totalCGST' : 0,
        'totalIGST' : 0,
        'totalDiscountRupees': 0,
        'valuseSchemeIdOnOrder' :'',
        'valueSchemeDiscount' : 0,
        'subTotal': 0,
        'orderDate': '',
        'totalCrates': '0 Crate'   // ✅ CRATE: added totalCrates to order summary (mirrors ProductListingComponentPortal)
    }
 
    totalCartPrice = 0.0; // Decimal (Floating Point)

    @api isCreateOrderComponenet;
    @track visitedShowFocusedProductList;
    @track visitedCartPage;
    @track selectedAccountId;
    @track buyerRegion;
    @track schemeSource; // 'PRODUCT' | 'CART'
    @track activeProductId;
    selectedSchemeId;
    isCartContext = false;
    @track valueSchemeMinCart = 0;

    //This method will be called when component loaded which will show create order component

    connectedCallback() {
        // #region agent log
        fetch('http://127.0.0.1:7242/ingest/cc8529e3-1fa0-4ad5-9cb2-c2dde768895b',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'createSecondaryOrderComponentDms.js:143',message:'connectedCallback entry',data:{openCartBefore:this.openCart},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'A'})}).catch(()=>{});
        // #endregion
        this.isCreateOrderComponenet=true;
        if (this.retailer && Array.isArray(this.retailer) && this.retailer.length > 0) {
            this.selectedAccountId = this.retailer[0]; 
            console.log('this.selectedAccountId: ' , this.selectedAccountId);
        } else {
            this.selectedAccountId = null;
        }
        this.isOrderDateAllowed();
        this.ShowprodutcList=true;
        this.openCart=false;
        // #region agent log
        fetch('http://127.0.0.1:7242/ingest/cc8529e3-1fa0-4ad5-9cb2-c2dde768895b',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'createSecondaryOrderComponentDms.js:151',message:'openCart set to false',data:{openCartAfter:this.openCart},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'A'})}).catch(()=>{});
        // #endregion
        this.ShowfocusedProdutcList=false;
        this.showtotalCGSTtax = false;
        this.showtotalIGSTtax = false;
        this.searchValue = '';
        // Set default to "All" - no brand filter, no stock filter
        this.selectedBrands = '';
        this.stockFilter = '';
        this.selectedBrandFromDropdown = 'All';
        this.allTabDisplayText = 'All';
        this.availableStockTabDisplayText = 'Available Stock';
        this.isLoading = true;
        // 🔥 Detect fresh cart reliably
        const raw = localStorage.getItem(this.storageKey);
        if (!raw || raw === '[]') {
            this.removeStoredValues();   // only at the birth of a new order
        }

        this.fetchProducts(); 
        this.loadCartFromStorage();
        this.fetchProductSchemes();
        this.getstoreInLocalStorage();
        this.searchValue = '';
        console.log('retailer:- ' , this.retailer);
        console.log('ValueSchemeExist--',this.ValueSchemeExist);
        console.log('ValueSchemeFinalName--',this.ValueSchemeFinalName);
        // #region agent log
        setTimeout(() => {
            const cartContainer = this.template.querySelector('.cart-container');
            if (cartContainer) {
                const styles = window.getComputedStyle(cartContainer);
                const rect = cartContainer.getBoundingClientRect();
                const parent = cartContainer.parentElement;
                const parentStyles = parent ? window.getComputedStyle(parent) : null;
                fetch('http://127.0.0.1:7242/ingest/cc8529e3-1fa0-4ad5-9cb2-c2dde768895b',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'createSecondaryOrderComponentDms.js:169',message:'cart container found after render',data:{exists:true,display:styles.display,visibility:styles.visibility,opacity:styles.opacity,position:styles.position,top:styles.top,left:styles.left,width:rect.width,height:rect.height,rectTop:rect.top,rectLeft:rect.left,rectRight:rect.right,rectBottom:rect.bottom,zIndex:styles.zIndex,parentTag:parent?.tagName,parentPosition:parentStyles?.position,parentOverflow:parentStyles?.overflow},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'B,C,D,E'})}).catch(()=>{});
            } else {
                fetch('http://127.0.0.1:7242/ingest/cc8529e3-1fa0-4ad5-9cb2-c2dde768895b',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'createSecondaryOrderComponentDms.js:169',message:'cart container NOT found in DOM',data:{exists:false,openCart:this.openCart},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'A'})}).catch(()=>{});
            }
        }, 1000);
        // #endregion
        // Add click listener to close dropdowns when clicking outside
        this.handleClickOutside = this.handleClickOutside.bind(this);
        document.addEventListener('click', this.handleClickOutside);
    }

    disconnectedCallback() {
        // Remove click listener when component is destroyed
        if (this.handleClickOutside) {
            document.removeEventListener('click', this.handleClickOutside);
        }
    }

    isOrderDateAllowed(){
        isOrderDateAllowed()
        .then(result => {
            this.allowOrderDateSelection = result === true;
        })
        .catch(error => {
            console.error('Error checking order date permission:', error);
            this.allowOrderDateSelection = false;
        });
    }

    // added by Fuzail - Method to handle clicks outside dropdown containers (includes Search By dropdown)
    handleClickOutside(event) {
        // Check if click is outside all dropdown containers
        const allDropdownContainers = this.template.querySelectorAll('.custom-tab-container');
        const searchByDropdowns = this.template.querySelectorAll('.search-by-dropdown-wrapper'); // added by Fuzail
        let clickedOutside = true;

        if (allDropdownContainers && allDropdownContainers.length > 0) {
            allDropdownContainers.forEach(container => {
                if (container && container.contains(event.target)) {
                    clickedOutside = false;
                }
            });
        }

        // added by Fuzail - Also check Search By dropdown wrappers
        if (searchByDropdowns && searchByDropdowns.length > 0) {
            searchByDropdowns.forEach(container => {
                if (container && container.contains(event.target)) {
                    clickedOutside = false;
                }
            });
        }

        // If clicked outside and a dropdown is open, close it
        if (clickedOutside) {
            if (this.showBrandDropdown) {
                this.showBrandDropdown = false;
            }
            if (this.showAvailableStockDropdown) {
                this.showAvailableStockDropdown = false;
            }
            if (this.showBrandDropdownFocus) {
                this.showBrandDropdownFocus = false;
            }
            if (this.showAvailableStockDropdownFocus) {
                this.showAvailableStockDropdownFocus = false;
            }
            // added by Fuzail - Close Search By dropdowns when clicking outside
            if (this.showSearchByDropdown) {
                this.showSearchByDropdown = false;
            }
            if (this.showSearchByDropdownFocus) {
                this.showSearchByDropdownFocus = false;
            }
        }
    }

    handleOrderDateChange(event) {
        this.orderSummary.orderDate = event.target.value;
    }

     get todayDate() {
        const today = new Date();
        const yyyy = today.getFullYear();
        const mm = String(today.getMonth() + 1).padStart(2, '0');
        const dd = String(today.getDate()).padStart(2, '0');
        return `${yyyy}-${mm}-${dd}`;
    }

    get minAllowedDate() {
        const date = new Date();
        date.setDate(date.getDate() - 3);
        const yyyy = date.getFullYear();
        const mm = String(date.getMonth() + 1).padStart(2, '0');
        const dd = String(date.getDate()).padStart(2, '0');
        return `${yyyy}-${mm}-${dd}`;
    }

    closeCart() {    
        this.openCart = false;
        this.ShowprodutcList = true;
        this.searchValue = '';
        localStorage.removeItem(`visitedCartPage`); 
    }
       //This method is used for back button which is for ShowprodutcList 
    closeShowProductList() {   
        this.searchValue = '';
        this.isCreateOrderComponenet=false;
        localStorage.removeItem(`visitedShowProductList`); 
        const event = new CustomEvent('isorderchanged', {
            detail: this.isCreateOrderComponent
        });
        this.dispatchEvent(event);
    }

    //This method is used for back button which is for ShowfocusedProdutcList
    closeShowFocusProductList() { 
        this.searchValue = '';
        this.openCart = false;
        this.ShowprodutcList = true;
        this.ShowfocusedProdutcList=false;
        localStorage.removeItem(`visitedShowFocusedProduct`); 
    }
       //This method is used to fetch focsed products page
    fetchFocusedProductsMethod(){
        localStorage.removeItem(`visitedShowProductList`); 
        localStorage.removeItem(`visitedCartPage`); 
        localStorage.setItem('visitedShowFocusedProduct', true);
        this.ShowfocusedProdutcList=true;
        this.ShowprodutcList=false;
        this.openCart=false;
        this.searchValue = '';
        // Reset focused products dropdown state
        this.selectedBrands = '';
        this.stockFilter = '';
        this.selectedBrandFromDropdownFocus = 'All';
        this.allTabDisplayTextFocus = 'All';
        this.availableStockTabDisplayTextFocus = 'Available Stock';
        this.showBrandDropdownFocus = false;
        this.showAvailableStockDropdownFocus = false;
        this.fetchFocusedProducts();
    }
       //This method is used to fetch focsed products list

    fetchFocusedProducts() {
        const focusedProductIdsInCart = this.productAddedForCart
        .filter(product => product.focusProduct === true)
        .map(product => product.productId);
        this.availableBrandsFocus=[];
        // added by Fuzail - pass searchBy for Name vs Code (use searchByFocus for focused products)
        fetchFocusedProducts({'searchValue':null,'brandFilter': null, excludedProductIds: focusedProductIdsInCart,retailerSelected: this.retailer , stockFilter:this.stockFilter, searchBy: this.searchByFocus})
        .then(result => {
            this.data = JSON.parse(result);
            const brandsSet = new Set(['All','Available Stock']);
            const allBrandsSet = new Set(); // For storing all product brands
            this.updateProductQuantitiesFromCart(); 
            this.data.forEach(product => {
                if (product.productBrand) {  // Assuming productBrand is mapped to 'Product_Brand__c'
                    brandsSet.add(product.productBrand); // Add the brand to the Set
                    if (product.productBrand !== 'All' && product.productBrand !== 'Available Stock') {
                        allBrandsSet.add(product.productBrand);
                    }
                }
                this.retailerState = product.retailerState;
                console.log('this.retailerState:' , this.retailerState);
                this.distributorState = product.distributorState;
                console.log('this.distributorState:' , this.distributorState);
            });    
            brandsSet.forEach(brand => {
                this.availableBrandsFocus.push(brand);
            });     
            // Separate "All" and "Available Stock" from other brands for focused products
            this.allBrandsListFocus = this.sortBrandsByCustomOrder([...allBrandsSet]); // All other brands for dropdown in custom order
        })
        .catch(error => {
            console.error('Error in fetchFocusedProducts:', error);
        });
    }
    
    //This method is used for search bar to search products
    // added by Fuzail - use event.detail.value for lightning-input (event.target.value can be wrong); onchange = old search behaviour for Name (70, aam masti, etc.)
    handleChangeSearchValue(event){
        const value = (event.detail && event.detail.value !== undefined) ? event.detail.value : (event.target ? event.target.value : '');
        this.searchValue = value != null ? value : '';
        if (this.searchDebounceTimeout) {
            clearTimeout(this.searchDebounceTimeout);
        }
        this.searchDebounceTimeout = setTimeout(() => {
            this.isLoading = true;
        this.loadProducts();
        }, 300);
    }

    //This method is used for search bar to serach focused products
    // added by Fuzail - same: use event.detail.value for lightning-input so Name search works (aam masti, etc.)
    handleChangeFocusedSearchValue(event){
        const value = (event.detail && event.detail.value !== undefined) ? event.detail.value : (event.target ? event.target.value : '');
        this.searchValue = value != null ? value : '';
        if (this.searchFocusedDebounceTimeout) {
            clearTimeout(this.searchFocusedDebounceTimeout);
        }
        this.searchFocusedDebounceTimeout = setTimeout(() => {
            this.isLoading = true;
    this.loadFocusProducts();
        }, 300);
    }
    loadFocusProducts() {
        // Step 1: Extract the productIds of Focused products in the cart
        const focusedProductIdsInCart = this.productAddedForCart
        .filter(product => product.focusProduct === true)
        .map(product => product.productId);
        const visitTaskIdToPass = this.visitTaskId;
        // added by Fuzail - pass searchBy (searchByFocus for focused products)
        fetchFocusedProducts({'searchValue':this.searchValue,'brandFilter': this.selectedBrands === 'All' ? '' : this.selectedBrands,
            excludedProductIds: focusedProductIdsInCart ,retailerSelected: this.retailer , stockFilter : this.stockFilter, searchBy: this.searchByFocus })
        .then(result => {
            this.data = JSON.parse(result);
            this.updateProductQuantitiesFromCart(); 
            
            // Filter products with available stock > 0 when Available Stock filter is active
            if (this.stockFilter === 'Available Stock') {
                this.data = this.data.filter(product => {
                    const availableQty = product.availableQuantity || 0;
                    return availableQty > 0;
                });
            }
            
            // added by Fuzail - only apply exact name filter when Search By = Name; when Code, Apex filtered by Product_Code__c
            if (this.searchByFocus === 'Name') {
                this.filterProductsByExactSearch();
            }
            this.isLoading=false; // added by Fuzail
        })
        .catch(error => {
        });
    }
    
    //This method is used to update product quantity
    updateProductQuantitiesFromCart() {
        if (this.data && this.productAddedForCart) {
            this.data = this.data.map(product => {
                let productInCart = this.productAddedForCart.find(item => item.productId === product.productId);
                return {
                    ...product,
                    addedQuantity: productInCart ? productInCart.quantity : 0
                };
            });
        }
    }

    //This method filters products to ensure search term appears as whole word/number
    // added by Fuzail
    filterProductsByExactSearch() {
        if (!this.searchValue || !this.data) {
            return;
        }
        
        const searchTerm = this.searchValue.trim();
        if (searchTerm === '') {
            return;
        }
        
        // Escape special regex characters
        const escapedSearchTerm = searchTerm.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        
        // Check if search term is a number
        const isNumeric = /^\d+$/.test(searchTerm);
        
        this.data = this.data.filter(product => {
            const productName = product.productShortDescription || '';
            
            // Extract main product name (everything before the first opening parenthesis)
            const mainNameMatch = productName.split('(')[0].trim();
            const mainProductName = mainNameMatch || '';
            
            // Extract content inside parentheses
            const parenthesesMatch = productName.match(/\(([^)]+)\)/);
            const parenthesesContent = parenthesesMatch ? parenthesesMatch[1] : '';
            
            let matchesInMainName = false;
            let matchesInParentheses = false;
            
            if (isNumeric) {
                // For numbers, ensure it's not part of a larger number
                // Check in main product name (before parentheses)
                if (mainProductName) {
                    const regexMain = new RegExp(`(^|[^0-9])${escapedSearchTerm}([^0-9]|$)`, 'i');
                    matchesInMainName = regexMain.test(mainProductName);
                }
                
                // Check inside parentheses
                if (parenthesesContent) {
                    const regexParentheses = new RegExp(`(^|[^0-9])${escapedSearchTerm}([^0-9]|$)`, 'i');
                    matchesInParentheses = regexParentheses.test(parenthesesContent);
                }
            } else {
                // For text, use partial/substring matching (case-insensitive)
                // Check in main product name (before parentheses)
                if (mainProductName) {
                    matchesInMainName = mainProductName.toLowerCase().includes(searchTerm.toLowerCase());
                }
                
                // Check inside parentheses
                if (parenthesesContent) {
                    matchesInParentheses = parenthesesContent.toLowerCase().includes(searchTerm.toLowerCase());
                }
            }
            
            // Return true if matches in main product name OR inside parentheses
            return matchesInMainName || matchesInParentheses;
        });
    }

    //This method is used to search products by Tabs
   //added by Fuzail 
        handleTabChange(event) {
            this.isLoading=true;
            const tabValue = event.target.value;
            if (tabValue === 'Available Stock') {
                this.selectedBrands = '';
                this.stockFilter = 'Available Stock';
            } else {
                this.selectedBrands = '';
                this.stockFilter = '';
            }
            this.loadProducts();  
        }
        // Add method to toggle dropdown (for arrow click)
         toggleBrandDropdown(event) {
          event.stopPropagation(); // Prevent event bubbling
          this.showBrandDropdown = !this.showBrandDropdown;
          this.showAvailableStockDropdown = false; // Close Available Stock dropdown if open
          this.showSearchByDropdown = false; // added by Fuzail - close Search By when opening All dropdown
         }

    // Add method to handle "All" text click - show all products
    handleAllTabClick() {
        this.selectedBrands = '';
        this.selectedBrandFromDropdown = 'All';
        this.allTabDisplayText = 'All'; // Reset display text
        this.stockFilter = '';
        // Reset Available Stock tab to default when clicking on All tab
        this.availableStockTabDisplayText = 'Available Stock';
        this.showBrandDropdown = false; // Close dropdown if open
        this.showAvailableStockDropdown = false; // Close Available Stock dropdown if open
        this.showSearchByDropdown = false; // added by Fuzail - close Search By dropdown when switching tab
        this.isLoading = true;
        this.loadProducts();
    }

    // Add method to toggle Available Stock dropdown (for arrow click)
    toggleAvailableStockDropdown(event) {
        event.stopPropagation(); // Prevent event bubbling
        this.showAvailableStockDropdown = !this.showAvailableStockDropdown;
        this.showBrandDropdown = false; // Close All dropdown if open
        this.showSearchByDropdown = false; // added by Fuzail - close Search By when opening Available Stock dropdown
    }

    // Add method to handle "Available Stock" text click - show only products with stock > 0
    handleAvailableStockTabClick() {
        this.selectedBrands = '';
        this.selectedBrandFromDropdown = 'Available Stock';
        this.availableStockTabDisplayText = 'Available Stock'; // Reset display text
        this.stockFilter = 'Available Stock';
        // Reset All tab to default when clicking on Available Stock tab
        this.allTabDisplayText = 'All';
        this.showAvailableStockDropdown = false; // Close dropdown if open
        this.showBrandDropdown = false; // Close All dropdown if open
        this.showSearchByDropdown = false; // added by Fuzail - close Search By when clicking Available Stock tab
        this.isLoading = true;
        this.loadProducts();
    }

    // Add method to handle brand selection from All dropdown
    handleBrandDropdownSelect(event) {
        const selectedBrand = event.currentTarget.dataset.brand;
        this.selectedBrandFromDropdown = selectedBrand;
        this.selectedBrands = selectedBrand === 'All' ? '' : selectedBrand;
        // Update display text to show "All (Brand Name)" or just "All"
        this.allTabDisplayText = selectedBrand === 'All' ? 'All' : `All (${selectedBrand})`;
        this.stockFilter = ''; // Reset stock filter when selecting brand from All
        // Reset Available Stock tab to default when selecting from All dropdown
        this.availableStockTabDisplayText = 'Available Stock';
        this.showBrandDropdown = false;
        this.showSearchByDropdown = false; // added by Fuzail - close Search By when selecting from All dropdown
        this.isLoading = true;
        this.loadProducts();
    }

    // Add method to handle brand selection from Available Stock dropdown
    handleAvailableStockBrandSelect(event) {
        const selectedBrand = event.currentTarget.dataset.brand;
        this.selectedBrandFromDropdown = selectedBrand;
        this.selectedBrands = selectedBrand === 'All' ? '' : selectedBrand;
        // Update display text to show "Available Stock (Brand Name)" or just "Available Stock"
        this.availableStockTabDisplayText = selectedBrand === 'All' ? 'Available Stock' : `Available Stock (${selectedBrand})`;
        this.stockFilter = 'Available Stock'; // Keep stock filter active
        // Reset All tab to default when selecting from Available Stock dropdown
        this.allTabDisplayText = 'All';
        this.showAvailableStockDropdown = false;
        this.showSearchByDropdown = false; // added by Fuzail - close Search By when selecting from Available Stock dropdown
        this.isLoading = true;
        this.loadProducts();
    }

    // added by Fuzail - Toggle "Search By" dropdown (Name / Code). Code = search by Product_Code__c (starts with, reactive).
    toggleSearchByDropdown(event) {
        event.stopPropagation();
        this.showSearchByDropdown = !this.showSearchByDropdown;
        this.showBrandDropdown = false;
        this.showAvailableStockDropdown = false;
    }

    // added by Fuzail - When user selects Name or Code from Search By dropdown, update and reload products.
    handleSearchByOptionSelect(event) {
        const selected = event.currentTarget.dataset.searchby; // 'Name' or 'Code'
        this.searchBy = selected;
        this.searchByDisplayText = selected;
        this.showSearchByDropdown = false;
        this.isLoading = true;
        this.loadProducts();
    }

      //This method is used to load all products
    loadProducts() {
        console.log('this.searchValue in loadProducts:- ',this.searchValue);
        let select = this.selectedBrands === 'All' ? '' : this.selectedBrands;
        console.log('this.selectedBrands in loadProducts:- ', select);
        // added by Fuzail - pass searchBy so Apex can filter by Name (default) or Product_Code__c (Code)
        console.log('this.retailer: ', this.retailer);
        fetchProducts({'searchValue':this.searchValue,'brandFilter': this.selectedBrands === 'All' ? '' : this.selectedBrands,retailerSelected: this.retailer , stockFilter:this.stockFilter, searchBy: this.searchBy})
        .then(result => {
            this.data = JSON.parse(result);
            this.updateProductQuantitiesFromCart();
            
            // Filter products with available stock > 0 when Available Stock filter is active
            if (this.stockFilter === 'Available Stock') {
                this.data = this.data.filter(product => {
                    const availableQty = product.availableQuantity || 0;
                    return availableQty > 0;
                });
            }
            
            // added by Fuzail - only apply exact name search when Search By = Name; when Code, Apex already filtered by Product_Code__c
            if (this.searchBy === 'Name') {
                this.filterProductsByExactSearch();
            }
            this.isLoading=false; // added by Fuzail
        })
        .catch(error => {
            console.error('Error loadProducts', error);
        });
    }
       //This method is used to load all products from callback
    fetchProducts() {
        console.log('this.searchValue:- ',this.searchValue);
        // added by Fuzail - pass searchBy for Name vs Code search
        fetchProducts({'searchValue':this.searchValue,'brandFilter': this.selectedBrands === 'All' ? '' : this.selectedBrands,retailerSelected: this.retailer , stockFilter:this.stockFilter, searchBy: this.searchBy})
        .then(result => {
            this.data = JSON.parse(result);
            const brandsSet = new Set(['All','Available Stock']);
            const allBrandsSet = new Set(); // For storing all product brands
            this.updateProductQuantitiesFromCart(); 
            this.data.forEach(product => {
                if (product.productBrand) {  // Assuming productBrand is mapped to 'Product_Brand__c'
                    brandsSet.add(product.productBrand); // Add the brand to the Set
                    if (product.productBrand !== 'All' && product.productBrand !== 'Available Stock') {
                        allBrandsSet.add(product.productBrand);
                    }
                }
                this.retailerState = product.retailerState;
                this.distributorState = product.distributorState;
                localStorage.setItem('Userstate', this.state);
            });
    
        // Separate "All" and "Available Stock" from other brands
        this.availableBrands = ['All', 'Available Stock']; // Only these two as tabs
        this.allBrandsList = this.sortBrandsByCustomOrder([...allBrandsSet]); // All other brands for dropdown in custom order
        // added by Fuzail - only apply exact name filter when Search By = Name
        if (this.searchBy === 'Name') {
            this.filterProductsByExactSearch();
        }
        this.isLoading = false; // Set loading to false after products are loaded
        })
        .catch(error => {
            console.error('error fetching prod:', error);
            this.isLoading = false; // Set loading to false even on error
        });
    }
    //This method is used to search focused products by Tabs
    handleTabChangeFocus(event) {
        this.isLoading=true;
        this.selectedBrands = event.target.value;
        this.stockFilter = event.target.value;
        this.loadFocusProducts();
    }

    // Add method to toggle dropdown (for arrow click) - Focused Products
    toggleBrandDropdownFocus(event) {
        event.stopPropagation(); // Prevent event bubbling
        this.showBrandDropdownFocus = !this.showBrandDropdownFocus;
        this.showAvailableStockDropdownFocus = false; // Close Available Stock dropdown if open
        this.showSearchByDropdownFocus = false; // added by Fuzail - close Search By when opening All dropdown (focused)
    }

    // Add method to handle "All" text click - show all focused products
    handleAllTabClickFocus() {
        this.selectedBrands = '';
        this.selectedBrandFromDropdownFocus = 'All';
        this.allTabDisplayTextFocus = 'All'; // Reset display text
        this.stockFilter = '';
        // Reset Available Stock tab to default when clicking on All tab
        this.availableStockTabDisplayTextFocus = 'Available Stock';
        this.showBrandDropdownFocus = false; // Close dropdown if open
        this.showAvailableStockDropdownFocus = false; // Close Available Stock dropdown if open
        this.showSearchByDropdownFocus = false; // added by Fuzail - close Search By when switching tab (focused)
        this.isLoading = true;
        this.loadFocusProducts();
    }

    // Add method to toggle Available Stock dropdown (for arrow click) - Focused Products
    toggleAvailableStockDropdownFocus(event) {
        event.stopPropagation(); // Prevent event bubbling
        this.showAvailableStockDropdownFocus = !this.showAvailableStockDropdownFocus;
        this.showBrandDropdownFocus = false; // Close All dropdown if open
        this.showSearchByDropdownFocus = false; // added by Fuzail - close Search By when opening Available Stock (focused)
    }

    // Add method to handle "Available Stock" text click - show only focused products with stock > 0
    handleAvailableStockTabClickFocus() {
        this.selectedBrands = '';
        this.selectedBrandFromDropdownFocus = 'Available Stock';
        this.availableStockTabDisplayTextFocus = 'Available Stock'; // Reset display text
        this.stockFilter = 'Available Stock';
        // Reset All tab to default when clicking on Available Stock tab
        this.allTabDisplayTextFocus = 'All';
        this.showAvailableStockDropdownFocus = false; // Close dropdown if open
        this.showBrandDropdownFocus = false; // Close All dropdown if open
        this.isLoading = true;
        this.loadFocusProducts();
    }

    // Add method to handle brand selection from All dropdown - Focused Products
    handleBrandDropdownSelectFocus(event) {
        const selectedBrand = event.currentTarget.dataset.brand;
        this.selectedBrandFromDropdownFocus = selectedBrand;
        this.selectedBrands = selectedBrand === 'All' ? '' : selectedBrand;
        // Update display text to show "All (Brand Name)" or just "All"
        this.allTabDisplayTextFocus = selectedBrand === 'All' ? 'All' : `All (${selectedBrand})`;
        this.stockFilter = ''; // Reset stock filter when selecting brand from All
        // Reset Available Stock tab to default when selecting from All dropdown
        this.availableStockTabDisplayTextFocus = 'Available Stock';
        this.showBrandDropdownFocus = false;
        this.showSearchByDropdownFocus = false; // added by Fuzail - close Search By when selecting from All (focused)
        this.isLoading = true;
        this.loadFocusProducts();
    }

    // Add method to handle brand selection from Available Stock dropdown - Focused Products
    handleAvailableStockBrandSelectFocus(event) {
        const selectedBrand = event.currentTarget.dataset.brand;
        this.selectedBrandFromDropdownFocus = selectedBrand;
        this.selectedBrands = selectedBrand === 'All' ? '' : selectedBrand;
        // Update display text to show "Available Stock (Brand Name)" or just "Available Stock"
        this.availableStockTabDisplayTextFocus = selectedBrand === 'All' ? 'Available Stock' : `Available Stock (${selectedBrand})`;
        this.stockFilter = 'Available Stock'; // Keep stock filter active
        // Reset All tab to default when selecting from Available Stock dropdown
        this.allTabDisplayTextFocus = 'All';
        this.showAvailableStockDropdownFocus = false;
        this.showSearchByDropdownFocus = false; // added by Fuzail - close Search By when selecting from Available Stock (focused)
        this.isLoading = true;
        this.loadFocusProducts();
    }

    // added by Fuzail - Toggle "Search By" dropdown for focused products (Name / Code).
    toggleSearchByDropdownFocus(event) {
        event.stopPropagation();
        this.showSearchByDropdownFocus = !this.showSearchByDropdownFocus;
        this.showBrandDropdownFocus = false;
        this.showAvailableStockDropdownFocus = false;
    }

    // added by Fuzail - When user selects Name or Code from Search By dropdown (focused products), update and reload.
    handleSearchByOptionSelectFocus(event) {
        const selected = event.currentTarget.dataset.searchby; // 'Name' or 'Code'
        this.searchByFocus = selected;
        this.searchByDisplayTextFocus = selected;
        this.showSearchByDropdownFocus = false;
        this.isLoading = true;
        this.loadFocusProducts();
    }

    getCrateDisplay(quantity, crateconversion) {
        if (crateconversion > 0) {
            const fullCrates = Math.floor(quantity / crateconversion);
            const remainingUnits = quantity % crateconversion;
            if (fullCrates > 0 && remainingUnits > 0) {
                return `${fullCrates} Crate ${remainingUnits} EA`;
            } else if (fullCrates > 0) {
                return `${fullCrates} Crate`;
            } else {
                return `0 Crate ${remainingUnits} EA`;
            }
        }
        return '';
    }

    calculateTotalCrates() {
        let totalCrates = 0;
        let totalEAFromCrates = 0;

        for (let item of this.productAddedForCart) {
            if (item.crateconversion && item.crateconversion > 0) {
                const fullCrates = Math.floor(item.quantity / item.crateconversion);
                const remainingEA = item.quantity % item.crateconversion;
                totalCrates += fullCrates;
                totalEAFromCrates += remainingEA;
            }
        }

        let result = '';
        if (totalCrates > 0 || totalEAFromCrates > 0) {
            result += `${totalCrates} Crate${totalCrates !== 1 ? 's' : ''}`;
            if (totalEAFromCrates > 0) {
                result += ` ${totalEAFromCrates} EA`;
            }
        }
        return result || '0';
    }

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
        const currentQty = this.getCurrentProductQty(productId);
        
        this.selectedSchemeId = null;   

        console.log('openDialogForQualityScheme productId', productId);
        console.log('openDialogForQualityScheme selectedAccountId', this.selectedAccountId);
        console.log('openDialogForQualityScheme buyerRegion', this.buyerRegion);

        if (!productId || !this.selectedAccountId || !this.buyerRegion) {
            console.warn('Missing context for quantity scheme');
            return;
        }

        getqualityScheme({
            productId: productId,
            buyerAccountId: this.selectedAccountId,
            buyerRegion: this.buyerRegion,
            isUnderSS: false   // Secondary order = Retailer
        })
        .then(result => {
            this.schemeDetails = (Array.isArray(result) ? result : []).map(s => ({
                ...s,
                isDisabled: currentQty < s.minQty
            }));

            this.isQualityScheme = true;   

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

    get availableBrandsWithoutAll() {
        return this.availableBrands.filter(brand => brand !== 'All' && brand !== 'Available Stock');
    }


  //This method is used close dialof box for Quantity schemes
    closeQualitySchemeDialog() {
        this.isQualityScheme = false; // Set the flag to false to hide the modal
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

    logCart(label, data) {
        console.log(label, JSON.parse(JSON.stringify(data)));
    }

   applyScheme() {
        const cart = JSON.parse(localStorage.getItem(this.storageKey)) || [];

        applyQuantityScheme({
            cartItems: cart,
            buyerAccountId: this.selectedAccountId,
            buyerRegion: this.buyerRegion,
            selectedSchemeId: this.selectedSchemeId,
            isUnderSS: false   // Secondary order = Retailer
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


    openDialogForQualitySchemeFocus(event) {
        const productId = event.currentTarget.dataset.productId;

        if (!productId || !this.selectedAccountId || !this.buyerRegion) {
            console.warn('Missing context for focused quantity scheme');
            return;
        }

        getqualityScheme({
            productId: productId,
            buyerAccountId: this.selectedAccountId,
            buyerRegion: this.buyerRegion,
            isUnderSS: false   // Secondary order = Retailer
        })
        .then(result => {
            this.schemeDetails = Array.isArray(result) ? result : [];

            this.isQualityFocusScheme = true;   
            this.ShowfocusedProdutcList = true;

            if (this.schemeDetails.length === 0) {
                this.noSchemeMessage = NO_SCHEME_AVAILABLE;
            } else {
                this.noSchemeMessage = '';
            }
        })
        .catch(error => {
            this.schemeDetails = [];
            this.noSchemeMessage = NO_SCHEME_AVAILABLE;
            this.isQualityFocusScheme = true;   

            console.error('Error fetching quantity schemes');
            console.error(error?.body?.message);
        });

    }


//This method is used close dialog box for Quantity schemes for focused products
    closeQualitySchemeDialogFocus() {
        this.isQualityFocusScheme = false; // Set the flag to false to hide the modal
        this.ShowfocusedProdutcList=true;
    }

  //This method is used close dialog box for Values schemes on cart page
    closeValueSchemeDialog() {
        this.isValueScheme = false; // Set the flag to false to hide the modal
        this.openCart=true;
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

             // ✅ Keep VALUE scheme promos always
            if (item.promoType === 'VALUE') return true;

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

//This method is used to reduce Quantity from addtocart
    minusQuantity(event) {
        this.isLoading=true;
            const productId = event.target.name; // Use product ID to identify the correct product
            const element = this.template.querySelector (`[data-id="${productId}"]`);
        const product = this.data.find(prod => prod.productId === productId);
            if (product) {
            product.productQuantity = (parseInt(element.value) - 1) > 0 ? parseInt(element.value) - 1 : 0;
            this.isLoading=false;
        }
       
    }
      
//This method is used for Quantity Changefrom AddToCart
    valueQtyHandle(event) {
        const productId = event.target.dataset.id;
        const newQuantity = event.target.value;
        // Find the product in the list and update the quantity
        const product = this.data.find(prod => prod.productId === productId);
        if (product) {
            product.productQuantity = parseInt(newQuantity, 10) || 0; // Ensure the value is a number
        }
    }

        //This method is used for add Quantity to AddToCart
    addtionQuantity(event) {
        this.isLoading=true;
        const productId = event.target.name; // Use product ID to identify the correct product
        const element = this.template.querySelector (`[data-id="${productId}"]`);           
        // Find the product in the products list and update its quantity
        const product = this.data.find(prod => prod.productId === productId);           
        if (product) {
            product.productQuantity = parseInt(element.value) + 1;
            
        this.isLoading=false;
        }
    }

 //This method is used for Product Add To Cart
    addToCart(event) {
        const restrictedProductCodes = productCodeLabel.split(',').map(code => code.trim());

        this.isLoading = true;
        let selectedProductId = event.currentTarget.dataset.productId;
        this.selectedProductForCart = selectedProductId;
        let largeGroup = this.data.filter(activity => (activity.productId == selectedProductId));
        //this.fetchProductSchemes();

        let productsImages = [];
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
            'focusProduct': largeGroup[0].focusProduct,
            'productFullName': largeGroup[0].productShortDescription,
            'productListPrice': largeGroup[0].productListPrice,
            'productOfferPrice': largeGroup[0].productOfferPrice,
            'prodmeasure': largeGroup[0].uom || 'N/A',
            'availableStockQuantity': largeGroup[0].availableQuantity,
            'selectedScheme':'',
            'unittotalPrice': 0 ,
            'index': 0,
            'productCode': largeGroup[0].productCode,
            'isPromotional': false,
            'parentProductId': null,
            'selectedSchemeId': null,
            'crateconversion': largeGroup[0].crateConversion || 0,  // ✅ CRATE: capture crate conversion from Apex response
            'crateDisplay': ''                                        // ✅ CRATE: initialise display string
        };

        for (let key in dataOfImages) {
            productsImages.push({
                images: dataOfImages[key],
                heading: largeGroup[0].productBrand,
                description: largeGroup[0].productShortDescription
            });
        }
        this.productSlides = productsImages;
        this.selectedProductIdForDetailPage = selectedProductId;

        // Retrieve the existing cart from localStorage
        let validateCartProducts = JSON.parse(localStorage.getItem(this.storageKey)) || [];
        let productExisting = false;

        // Check if the product is already in the cart
        for (let key in validateCartProducts) {
            if (validateCartProducts[key].productId == this.objectOfProductToCart.productId) {
                productExisting = true;

                // ✅ stock validation for restricted products
                console.log('restrictedProductCodes:- ',restrictedProductCodes);
                console.log('largeGroup[0].productCode:- ',largeGroup[0].productCode);
                if (restrictedProductCodes.includes(largeGroup[0].productCode)) {
                    if (validateCartProducts[key].quantity + largeGroup[0].productQuantity > largeGroup[0].availableQuantity) {
                        this.showToast(
                            '',
                            `${validateCartProducts[key].quantity} units of ${largeGroup[0].productShortDescription} already exists in cart. You can only add up to available stock (${largeGroup[0].availableQuantity}).`,
                            'error'
                        );
                        this.isLoading = false;
                        return;
                    }
                }

                validateCartProducts[key].quantity += largeGroup[0].productQuantity;
                // ✅ CRATE: refresh crateDisplay after quantity increase on existing item
                validateCartProducts[key].crateDisplay = this.getCrateDisplay(
                    validateCartProducts[key].quantity,
                    validateCartProducts[key].crateconversion || 0
                );
                break;
            }
        }

        if (largeGroup[0].productQuantity <= 0) {
            this.showToast('', 'Please Add Valid Quantity', 'error');
        } else {
            if (!productExisting) {
                // ✅ validate before pushing new restricted product
                console.log('restrictedProductCodes:- ',restrictedProductCodes);
                console.log('largeGroup[0].productCode:- ',largeGroup[0].productCode);
                if (restrictedProductCodes.includes(largeGroup[0].productCode)) {
                    if (largeGroup[0].productQuantity > largeGroup[0].availableQuantity) {
                        this.showToast('', `Cannot exceed available stock (${largeGroup[0].availableQuantity}) for ${largeGroup[0].productShortDescription}`, 'error');
                        this.isLoading = false;
                        return;
                    }
                }

                if (largeGroup[0].productQuantity > 0) {
                    this.objectOfProductToCart.quantity = largeGroup[0].productQuantity;
                    this.objectOfProductToCart.unittotalPrice = 
                        (largeGroup[0].productQuantity * largeGroup[0].productOfferPrice).toFixed(2);
                    // ✅ CRATE: compute crateDisplay for new cart item
                    this.objectOfProductToCart.crateDisplay = this.getCrateDisplay(
                        largeGroup[0].productQuantity,
                        this.objectOfProductToCart.crateconversion
                    );
                    this.objectOfProductToCart.index = validateCartProducts.length + 1;
                    validateCartProducts.push(this.objectOfProductToCart);
                    largeGroup[0].productQuantity = 0;
                }
            }

            largeGroup[0].productQuantity = 0;
            this.cartSize = validateCartProducts.length;

            // Save the updated cart to localStorage
            localStorage.setItem(this.storageKey, JSON.stringify(validateCartProducts));
            this.productAddedForCart = validateCartProducts;  // Update the cart in memory
            this.prepareOrderSummary();
            this.showToast('', 'Item is added to cart', 'success');
            this.updateProductQuantitiesFromCart();
        }
        this.isLoading = false;
    }
 //This method is used to show toast message
      showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(evt);
    }
    //This method is used fetch tax rates
    prepareOrderSummary() {
        this.fetchTaxRates(); 
    }

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

    
    // //This method is used to calculateOrderSummary
    calculateOrderSummary(taxRates){

        console.log('taxRates***',taxRates);
        let totalItems = this.productAddedForCart.length;
        let totalPrice = 0;
        let totalQuantity = 0;
        let totalSGSTtax = 0;
        let totalCGSTtax = 0;
        let totalIGSTtax = 0;
        let discountPercentAmount = 0;
        let totalAmount = 0;

        for (let key in this.productAddedForCart) {
            console.log('this.productAddedForCart[key].productListPrice ', this.productAddedForCart[key].productListPrice );
            if (this.productAddedForCart[key].productListPrice > 0) {
            totalPrice = totalPrice + (this.productAddedForCart[key].productOfferPrice * this.productAddedForCart[key].quantity);
            console.log('productAddedForCart-  ', this.productAddedForCart[key].quantity );
            totalQuantity = totalQuantity + this.productAddedForCart[key].quantity;
            } else {
            totalPrice = totalPrice + 0;
            totalQuantity = totalQuantity + this.productAddedForCart[key].quantity;
            }

            this.orderSummary.totalItems = totalItems;
            this.priceBeforeDiscount = totalPrice.toFixed(2);
            this.orderSummary.totalQuantity = totalQuantity;
            this.totalCartPrice = this.priceBeforeDiscount;
            this.orderSummary.subTotal = totalPrice.toFixed(2);
            this.orderSummary.totalOrderValue = totalPrice.toFixed(2);

            if(this.discountAmountGiven!=0){
                console.log('this.discountAmountGiven:- ',this.discountAmountGiven);
                this.orderSummary.totalDiscountRupees=  this.discountAmountGiven;  
                this.orderSummary.totalOrderValue = (totalPrice - this.discountAmountGiven).toFixed(2);
                localStorage.setItem('discountAmountGiven', this.discountAmountGiven.toString());
                localStorage.setItem('priceAfterDiscount', this.priceAfterDiscount.toString());
            }
            if(this.discountPercemtageGiven!=0){
                discountPercentAmount = this.orderSummary.totalOrderValue;
                const discountAmountPer = (discountPercentAmount * this.discountPercemtageGiven) / 100;
                this.discountPercentageAmount = discountAmountPer.toFixed(2);
                this.orderSummary.totalOrderValue = (totalPrice - discountAmountPer).toFixed(2);
                this.orderSummary.totalDiscountRupees=  this.discountPercentageAmount;
                localStorage.setItem('discountPercemtageGiven', this.discountPercemtageGiven.toString());
                localStorage.setItem('discountPercentageAmount', this.discountPercentageAmount.toString());
                localStorage.setItem('priceAfterDiscount', this.priceAfterDiscount.toString());
            }

            if(this.valueSchemFinalId!=null && this.valueSchemFinalId!=''){
                this.orderSummary.valuseSchemeIdOnOrder=this.valueSchemFinalId;
                this.orderSummary.valueSchemeDiscount = this.discountAmountGivenCheck ? Number(this.discountAmountGiven || 0)
                                                        : this.discountPercemtageGivenCheck ? Number(this.discountPercentageAmount || 0) : 0;
            }
            
            console.log('totalQuantity-==  ', totalQuantity );
        }
        console.log('this.retailerState-==  ', this.retailerState );
        console.log('taxRates.CGST-==  ', taxRates.CGST );
        if(this.retailerState.toLowerCase() === this.distributorState.toLowerCase()){
            console.log('this.orderSummary.totalOrderValue in KA:- ',this.orderSummary.totalOrderValue);
            totalSGSTtax += (this.orderSummary.totalOrderValue * taxRates.CGST) / 100;
            totalCGSTtax += (this.orderSummary.totalOrderValue * taxRates.SGST) / 100;
            console.log('totalSGSTtax:- ',totalSGSTtax);
            this.percentSGST = taxRates.SGST; 
            this.percentCGST = taxRates.CGST;
            
            this.showtotalCGSTtax = true;
            console.log('tax rate ka',taxRates.CGST)
        }else{
            this.percentIGST = taxRates.IGST;
            console.log('other');
            totalIGSTtax += (this.orderSummary.totalOrderValue * taxRates.IGST) / 100;
            console.log(totalIGSTtax);
            this.showtotalIGSTtax = true;
        }
        
        this.orderSummary.totalDiscountGiverByUser = this.discountAmount;
        console.log('this.orderSummary.totalOrderValue:- ',this.orderSummary.totalOrderValue);
        console.log('totalCGSTtax:- ',totalCGSTtax);
        console.log('totalIGSTtax:- ',totalIGSTtax);
        console.log('totalSGSTtax:- ',totalSGSTtax);
        
        totalAmount = this.orderSummary.totalOrderValue;
        console.log('totalAmount:- ',totalAmount);
        console.log('Type of totalAmount:- ', isNaN(totalAmount));
        this.orderSummary.totalSGST = totalSGSTtax.toFixed(2);
        this.orderSummary.totalCGST = totalCGSTtax.toFixed(2);
        this.orderSummary.totalIGST = totalIGSTtax.toFixed(2);
        this.totalOrderAmount = (Number(totalAmount) + totalCGSTtax + totalSGSTtax + totalIGSTtax).toFixed(2);
        console.log('this.totalOrderAmount:- ',this.totalOrderAmount);
        this.orderSummary.totalPrice = this.totalOrderAmount;
        console.log('this.orderSummary.totalPrice:- ',this.orderSummary.totalPrice);
        
        this.cartSize = this.productAddedForCart.length;

        // ✅ CRATE: update totalCrates on every order summary recalculation
        this.orderSummary.totalCrates = this.calculateTotalCrates();

        this.validateValueSchemeEligibility();
    }

       //This method is used to open cart page
    openCartModal() {
        localStorage.setItem('visitedCartPage', true);
        localStorage.removeItem(`visitedShowFocusedProduct`); 
        localStorage.removeItem(`visitedShowProductList`); 
        this.openCart = true;   
        this.ShowprodutcList =false; 
        this.ShowfocusedProdutcList=false;
        this.fetchTaxRates();
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
        //This method is used to fetchTaxRates
    fetchTaxRates() {
        console.log('this.retailerState at line 1628:' , this.retailerState);
        console.log('this.distributorState at line 1629:' , this.distributorState);
        getTaxRates({ retailerPrimaryState: this.retailerState , distributorPrimaryState:this.distributorState })
        .then((taxRates) => {
            this.calculateOrderSummary(taxRates);
        })
        .catch((error) => {
            console.error('Error fetching tax rates:', error);
        });
    }
    
      //This method is called save order in database
    generateProposal() {
        const finanJSONfromProposal = JSON.stringify(this.productAddedForCart);
        generateProposal({ productsFromCart: finanJSONfromProposal, retailerSelected: this.retailer, orderComment: this.comment, orderSummary: JSON.stringify(this.orderSummary) })
        .then(result => {
            if (result.status === 'Success') {
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
                    'totalDiscountRupees': 0,
                    'valuseSchemeIdOnOrder' :'',
                    'valueSchemeDiscount' : 0,
                    'subTotal': 0,
                    'orderDate': '',
                    'totalCrates': '0 Crate'   // ✅ CRATE: reset totalCrates on order success
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
                this.isOrderPlaced = false;
                this.updateAllCalculateCheck();
                this.removeStoredValues();
                localStorage.removeItem(`visitedCartPage`); 
                localStorage.removeItem(`visitedShowProductList`); 

                localStorage.removeItem(`commentGiven`); 
            } else {
                this.isOrderPlaced = false; // Re-enable the button if not successful
            }
        })
        .catch(error => {
            console.error('Error in placing order',error);
            let errorMessage = 'An unexpected error occurred while placing the order.';
              if (error && error.body && error.body.message) {
                errorMessage = error.body.message;
                }

                console.error('errorMessage = ',errorMessage);
                this.showToast('Error', errorMessage, 'error');
            this.isOrderPlaced = false; // Re-enable the button if there is an error
        });
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
        this.valueSchemeMinCart = Number(localStorage.getItem('valueSchemeMinCart')) || 0;
        this.comment = localStorage.getItem('commentGiven') || '';
    }
  // this method called when apply button is clicked
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
        
        getAppliedValueScheme({ valueSchemId: valueSchemId})
        .then(result => {
            console.log('discountAmountGiven is : ',result.discountAmount);
            console.log('discountPercemtageGiven is : ',result.discountPercentage);
            this.valueSchemeMinCart = result.cartAmount;   
            localStorage.setItem('valueSchemeMinCart', result.cartAmount);
            this.getAppliedValueSchemeNameMethod();
            if(result.discountAmount!='undefined' && result.discountAmount!=null){
                    this.discountAmountGiven=result.discountAmount;
                    this.discountAmountGivenCheck=true;
                    this.discountPercemtageGivenCheck=false;
                    this.fetchTaxRates(); 
                    localStorage.setItem('discountAmountGivenCheck', 'true');
            }
            else  if(result.discountPercentage!='undefined' && result.discountPercentage!=null){
                this.discountPercemtageGiven=result.discountPercentage;
                this.discountPercemtageGivenCheck=true;
                this.discountAmountGivenCheck=false;
                this.fetchTaxRates(); 
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
                    unittotalPrice: 0,

                    // ✅ CRATE: promo products carry crateconversion if present; display is intentionally blank for promos
                    crateconversion: product.crateConversion || 0,
                    crateDisplay: ''
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

    validateValueSchemeEligibility() {

        if (!this.ValueSchemeExist || !this.valueSchemFinalId) return;

        const cartValue = Number(this.orderSummary.subTotal || 0);
        const minCart = Number(this.valueSchemeMinCart || 0);

        console.log('Value scheme check', cartValue, '>=', minCart);

        if (cartValue < minCart) {
            console.warn('Value scheme invalid – removing');

            // Remove VALUE promos only
            this.productAddedForCart = this.productAddedForCart.filter(
                p => !(p.isPromotional && p.promoType === 'VALUE')
            );

            // Clear scheme data
            this.discountAmountGiven = 0;
            this.discountPercemtageGiven = 0;
            this.discountAmountGivenCheck = false;
            this.discountPercemtageGivenCheck = false;
            this.discountPercentageAmount = 0;
            this.priceAfterDiscount = 0;

            this.valueSchemFinalId = '';
            this.ValueSchemeFinalName = '';
            this.ValueSchemeExist = false;

            localStorage.removeItem('valueSchemFinalId');
            localStorage.removeItem('ValueSchemeFinalName');
            localStorage.removeItem('ValueSchemeExist');
            localStorage.removeItem('discountAmountGiven');
            localStorage.removeItem('discountPercemtageGiven');
            localStorage.removeItem('discountAmountGivenCheck');
            localStorage.removeItem('discountPercemtageGivenCheck');

            localStorage.setItem(this.storageKey, JSON.stringify(this.productAddedForCart));

            this.showToast(
                'Value Scheme Removed',
                'Cart value is below minimum required for this scheme',
                'warning'
            );
        }
    }


// this method called to get values for cartitems from localstaorage
    loadCartFromStorage() {
        const savedCart = JSON.parse(localStorage.getItem(this.storageKey)) || [];
            if (savedCart.length > 0) {
            this.productAddedForCart = savedCart; 
            this.cartSize = this.productAddedForCart.length;  
            this.prepareOrderSummary();  
            this.updateProductQuantitiesFromCart(); 
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
    
       //  this method called to  reduce - Quantity from Cart Update
    minusQuantityCart(event) {
        let nameOf = String(event.target.name);
        for (let key in this.productAddedForCart) {
            let tempCartId = this.productAddedForCart[key];
        
            if (tempCartId.productIdForCart == nameOf) {
                tempCartId.quantity = (tempCartId.quantity - 1) >= 1 ? tempCartId.quantity - 1 : tempCartId.quantity;
                tempCartId.unittotalPrice = (tempCartId.quantity * tempCartId.productOfferPrice).toFixed(2);
                // ✅ CRATE: refresh crateDisplay after minus
                tempCartId.crateDisplay = this.getCrateDisplay(tempCartId.quantity, tempCartId.crateconversion || 0);
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
        this.updateProductQuantitiesFromCart();
    }

    valueQtyHandleCart(event) {
        const restrictedProductCodes = productCodeLabel.split(',').map(code => code.trim());

        let quantityValue = +parseInt(event.target.value);
        if (quantityValue <= 0) {
            this.showToast('Error', 'Please enter a valid quantity.', 'error');
            return;
        }

        let nameOf = String(event.target.name);
        for (let key in this.productAddedForCart) {
            let tempCartId = this.productAddedForCart[key];

            if (tempCartId.productIdForCart == nameOf) {
                // ✅ validate against restricted product stock
                if (restrictedProductCodes.includes(tempCartId.productCode)) {
                    if (quantityValue > tempCartId.availableStockQuantity) {
                        this.showToast(
                            '',
                            `Quantity cannot exceed available stock (${tempCartId.availableStockQuantity}) for ${tempCartId.productName}`,
                            'error'
                        );
                    }
                }

                tempCartId.quantity = quantityValue <= 1 ? 1 : quantityValue;
                tempCartId.unittotalPrice = (
                    tempCartId.quantity * tempCartId.productOfferPrice
                ).toFixed(2);
                // ✅ CRATE: refresh crateDisplay after manual quantity entry
                tempCartId.crateDisplay = this.getCrateDisplay(tempCartId.quantity, tempCartId.crateconversion || 0);
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
    }

    //  this method called to  increase - Quantity from Cart Update
    additionQuantityCart(event) {

        const restrictedProductCodes = productCodeLabel.split(',').map(code => code.trim());
        const nameOf = String(event.target.name); // Get the name (productId) of the clicked button
        for (let key in this.productAddedForCart) {
            const tempCartItem = this.productAddedForCart[key];

            if (tempCartItem.productIdForCart === nameOf) {
                // ✅ validation for restricted products
                if (restrictedProductCodes.includes(tempCartItem.productCode)) {
                    if (tempCartItem.quantity + 1 > tempCartItem.availableStockQuantity) {
                        this.showToast(
                            '',
                            `Cannot exceed available stock (${tempCartItem.availableStockQuantity}) for ${tempCartItem.productName}`,
                            'error'
                        );
                        return; // ❌ Stop increment
                    }
                }

                tempCartItem.quantity += 1; // Increment the quantity
                tempCartItem.unittotalPrice = (tempCartItem.quantity * tempCartItem.productOfferPrice).toFixed(2);
                // ✅ CRATE: refresh crateDisplay after plus
                tempCartItem.crateDisplay = this.getCrateDisplay(tempCartItem.quantity, tempCartItem.crateconversion || 0);
                if (!tempCartItem.isPromotional && tempCartItem.selectedSchemeId) {
                    this.reapplySchemeForBase(tempCartItem.productId);
                    return; // prevent double calc
                }
                tempCartItem.schemeNeedsRevalidation = true;
                this.recomputeSchemeEligibility();

                break; // Exit loop once product found
            }
        }

        this.removeInvalidPromos();
        // Update cart summary and sync with localStorage
        this.prepareOrderSummary();
        localStorage.setItem(this.storageKey, JSON.stringify(this.productAddedForCart));
        this.updateProductQuantitiesFromCart();
    }
      
    //Remove product from Cart
    removeProductFromCart(event) {

        const itemToRemove = this.productAddedForCart.find(
            item => item.productIdForCart === event.target.name
        );

        // 🛑 SAFETY GUARD
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
            this.orderSummary.totalCrates = '0 Crate';  // ✅ CRATE: reset crate display when cart is emptied
        }
        this.prepareOrderSummary();
        localStorage.setItem(this.storageKey, JSON.stringify(this.productAddedForCart));
    }

    //  this method called to  getvalueScheme
    openDialogForValueScheme(event){
        console.log('this.totalCartPrice',this.totalCartPrice);
        console.log('openDialogForQualityScheme selectedAccountId', this.selectedAccountId);
        console.log('openDialogForQualityScheme buyerRegion', this.buyerRegion);

        if (!this.totalCartPrice || !this.selectedAccountId || !this.buyerRegion) {
            console.warn('Missing context for value scheme');
            return;
        }
        getvalueScheme({totalCartPrice:this.totalCartPrice, buyerAccountId: this.selectedAccountId,
    buyerRegion: this.buyerRegion, isUnderSS: false })
        .then(result => {
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
    });
    }
//  this method called to  update comments on order
    handleCommentChange(event) {
        this.comment = event.target.value;
        localStorage.setItem('commentGiven', this.comment.toString());
    }
      
 //  this method called when  place order button clicked
    generateProposalAndCloseCart() {
        if (this.isOrderPlaced) {
            return; // Prevent further clicks if already in progress
        }

        if (this.cartSize === 0) {
            this.showToast('', 'Please Add Products To Generate Proposal', 'error');
            return; // Stop execution if cart empty
        }

        const restrictedProductCodes = productCodeLabel.split(',').map(code => code.trim());
        let hasError = false; // Track if any restricted product has error
        // Validate restricted products
        for (let item of this.productAddedForCart) {
            if (restrictedProductCodes.includes(item.productCode)) {
                if (item.quantity > item.availableStockQuantity) {
                    this.showToast(
                        '',
                        `Warning: Quantity for ${item.productName} exceeds available stock (${item.availableStockQuantity}).`,
                        'error'
                    );
                    hasError = true;
                    console.log('hasError at line 1140:- ',hasError);
                }
            }
        }
        
        console.log('hasError:- ',hasError);
        // If there was an error, mark it but allow the user to click again to confirm
        if (!hasError) {
            this.isOrderPlaced = true; // Disable button
            this.generateProposal(); // Proceed with order
        }   
    }
}