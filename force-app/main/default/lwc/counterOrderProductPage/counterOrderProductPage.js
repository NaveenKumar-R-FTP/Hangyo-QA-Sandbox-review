import {track,wire,LightningElement,api } from 'lwc';
import fetchProducts from '@salesforce/apex/CounterOrderProductPageController.fetchProducts'
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import generateProposal from '@salesforce/apex/CounterOrderProductPageController.generateProposal'
import {NavigationMixin } from 'lightning/navigation';
import getTaxRates from '@salesforce/apex/CounterOrderProductPageController.getTaxRates';

export default class CounterOrderProductPage extends NavigationMixin(LightningElement) {
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
  @api storageKey = 'counterCart'; // Dynamic storage key with primary order value
  @track ShowprodutcList= true; //used for conditional rendering of template
  @track data = [];//holds the data from fetch products method
  @track activeTab = 'All'; // used to create sub tabs for brands
  @track cartItems = []; //holds cart items

@track objectOfProductToCart;//Holds collection of product data
cartSize = 0;//used to display cart size with cart symbol
@track productAddedForCart = [];//holds products added to cart
@track quantityValue = 0;
discountAmountText = '';
discountAmount = 0;
priceBeforeDiscount = 0;
priceWithoutTax = 0;

@track availableBrands = []; // used to create sub tabs for brands
@track selectedBrands ='' ; // used to create sub tabs for brands
@track stockFilter = ''; // Filter for available stock
@track showBrandDropdown = false;  
@track showAvailableStockDropdown = false;
@track selectedBrandFromDropdown = 'All';  
@track allBrandsList = [];
@track allTabDisplayText = 'All';
@track availableStockTabDisplayText = 'Available Stock';

// added by Fuzail - Search By: 'Name' = default search (product name/brand, e.g. 70 / aam masti),
//                               'Code' = search by Product_Code__c (starts with, e.g. 5300105)
@track searchBy = 'Name';
@track searchByDisplayText = 'Name';
@track showSearchByDropdown = false;

// added by Fuzail - debounce timeouts for search (to avoid too many Apex calls)
searchDebounceTimeout;

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
    /*const ordered = [];
    const unordered = [];
    
    // First, add brands in the specified order
    this.brandOrder.forEach(brand => {
        if (brands.includes(brand)) {
            ordered.push(brand);
        }
    });
    
    // Then, add any brands not in the custom order list (alphabetically)
    brands.forEach(brand => {
        if (!this.brandOrder.includes(brand)) {
            unordered.push(brand);
        }
    });
    unordered.sort();
    
    return [...ordered, ...unordered];*/
    //added by Fuzail - alphabetically sort brands
    const sortedBrands = [...brands].sort((a, b) => {
      return a.localeCompare(b, undefined, { sensitivity: 'base' });
  });
  return sortedBrands;
}

@track searchValue = '';// holds the string of search
openCart = false;//boolean to open and close cart
@track comment='';//holds comment before placing order
recordId = '';// to capture record id of newly created Order
@track showBrandFilters = false; // used to show sub tabs for brands
showtotalIGSTtax = false;//condition rendering of taxes w.r.t state
showtotalCGSTtax = false;//condition rendering of taxes w.r.t state
percentIGST = 0;//condition rendering of taxes w.r.t state
percentCGST = 0;//condition rendering of taxes w.r.t state
percentSGST = 0;//condition rendering of taxes w.r.t state

isOrderPlaced = false;//used to disable the place order once order placed
//order Summary to hold collection of order summary
@track orderSummary = {
  'totalItems': 0,
  'totalPrice': 0,
  'totalDiscount': 0,
  'totalOrderValue': 0,
  'totalQuantity': 0,
  'totalSGST' : 0,
  'totalCGST' : 0,
  'totalIGST' : 0 , 
  'firstName' : '',
  'lastName' : '' ,
  'email' : '' ,
  'phone' : '' ,
  'addressLine' : '',
  'state' : '',
  'country' : '',
  'city' : '',
  'postalCode' : '',
  'company' : '' , 
  'gstin' : '' ,
  'totalPrceBeforeDiscount' : 0 ,
  'totalPriceExcludingTax' : 0
}

connectedCallback() {
  // Set default to "All" - no brand filter, no stock filter
  this.selectedBrands = '';
  this.stockFilter = '';
  this.selectedBrandFromDropdown = 'All';
  this.allTabDisplayText = 'All';
  this.availableStockTabDisplayText = 'Available Stock';
  this.fetchProducts(); 
  this.loadCartFromStorage(); 
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

// OLD Method to handle clicks outside dropdown containers (commented by Fuzail)
/*
handleClickOutside(event) {
  // Check if click is outside all dropdown containers
  const allDropdownContainers = this.template.querySelectorAll('.custom-tab-container');
  let clickedOutside = true;

  if (allDropdownContainers && allDropdownContainers.length > 0) {
    allDropdownContainers.forEach(container => {
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
  }
}
*/

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
    // added by Fuzail - Close Search By dropdown when clicking outside
    if (this.showSearchByDropdown) {
      this.showSearchByDropdown = false;
    }
  }
}

// this method is used to toggle between brands of products
    handleTabChange(event) {
    console.log('this.selectedBrands: ' + this.selectedBrands);
      this.selectedBrands = event.target.value;
      console.log('this.selectedBrands: ' + this.selectedBrands);
      this.loadProducts();
  }

  // Add method to toggle dropdown (for arrow click)
  toggleBrandDropdown(event) {
    event.stopPropagation(); // Prevent event bubbling
    this.showBrandDropdown = !this.showBrandDropdown;
    this.showAvailableStockDropdown = false; // Close Available Stock dropdown if open
    this.showSearchByDropdown = false; // added by Fuzail - close Search By dropdown when opening All dropdown
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
    this.showSearchByDropdown = false; // added by Fuzail - close Search By dropdown when clicking All tab
    this.loadProducts();
  }

  // Add method to toggle Available Stock dropdown (for arrow click)
  toggleAvailableStockDropdown(event) {
    event.stopPropagation(); // Prevent event bubbling
    this.showAvailableStockDropdown = !this.showAvailableStockDropdown;
    this.showBrandDropdown = false; // Close All dropdown if open
    this.showSearchByDropdown = false; // added by Fuzail - close Search By dropdown when opening Available Stock dropdown
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
    this.showSearchByDropdown = false; // added by Fuzail - close Search By dropdown when clicking Available Stock tab
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
    this.showSearchByDropdown = false; // added by Fuzail - close Search By dropdown when selecting from All dropdown
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
    this.showSearchByDropdown = false; // added by Fuzail - close Search By dropdown when selecting from Available Stock dropdown
    this.loadProducts();
  }

//gets items from local storage
loadCartFromStorage() {
  const savedCart = JSON.parse(localStorage.getItem(this.storageKey)) || [];
    if (savedCart.length > 0) {
      this.productAddedForCart = savedCart; 
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

handlediscountAmountChange(event){
  this.discountAmountText = event.target.value;
  console.log('this.discountAmountText:- ' , this.discountAmountText);
  this.discountAmount = Number(this.discountAmountText);
  console.log('this.discountAmount:- ' , this.discountAmount);
  console.log('this.priceBeforeDiscount:- ' , this.priceBeforeDiscount);
  if(this.discountAmount > this.priceWithoutTax){
    this.showToast('Discount', 'Discount cannot be greater than price', 'Error');
  }else{
    this.prepareOrderSummary();
  }
}

// this method is used to handle and fetch the searched products
// added by Fuzail - use event.detail.value for lightning-input; debounce + keep existing filters
handleChangeSearchValue(event){
  const value = (event.detail && event.detail.value !== undefined) ? event.detail.value : (event.target ? event.target.value : '');
  this.searchValue = value != null ? value : '';
  
  // OLD CODE - If search is cleared, reset to default state
  // if (!this.searchValue || this.searchValue.trim() === '') {
  //   this.selectedBrands = '';
  //   this.stockFilter = '';
  //   this.selectedBrandFromDropdown = 'All';
  //   this.allTabDisplayText = 'All';
  //   this.availableStockTabDisplayText = 'Available Stock';
  //   this.showBrandDropdown = false;
  //   this.showAvailableStockDropdown = false;
  // }
  
  // added by Fuzail - Maintain filter state when search is cleared (old behaviour),
  // but debounce the Apex call so typing is smoother
  if (this.searchDebounceTimeout) {
    clearTimeout(this.searchDebounceTimeout);
  }
  this.searchDebounceTimeout = setTimeout(() => {
    this.loadProducts();
  }, 300);
}

// added by Fuzail - Toggle "Search By" dropdown (Name / Code)
toggleSearchByDropdown(event) {
  event.stopPropagation();
  this.showSearchByDropdown = !this.showSearchByDropdown;
  this.showBrandDropdown = false; // added by Fuzail - close All dropdown when opening Search By
  this.showAvailableStockDropdown = false; // added by Fuzail - close Available Stock dropdown when opening Search By
}

// added by Fuzail - handle user selecting Name or Code in Search By
handleSearchByOptionSelect(event) {
  const selected = event.currentTarget.dataset.searchby; // 'Name' or 'Code'
  this.searchBy = selected;
  this.searchByDisplayText = selected;
  this.showSearchByDropdown = false;
  // Reload products with the new search mode (Name / Code)
  this.loadProducts();
}

//this method fetches products to display from database
  loadProducts() {
      
      // added by Fuzail - pass searchBy so Apex can decide between Name and Product_Code__c search
      fetchProducts({'searchValue':this.searchValue,'brandFilter': this.selectedBrands === 'All' ? '' : this.selectedBrands, stockFilter: this.stockFilter, searchBy: this.searchBy })
      .then(result => {
        this.data = JSON.parse(result);
        // this.updateProductQuantitiesFromCart(); // commented by Fuzail
        this.updateProductQuantitiesFromCart(); 
        // Filter products with available stock > 0 when Available Stock filter is active
        if (this.stockFilter === 'Available Stock') {
          this.data = this.data.filter(product => {
            const availableQty = product.availableQuantity || 0;
            return availableQty > 0;
          });
        }
        // added by Fuzail - Apply exact name filter ONLY when Search By = Name
        // (when Search By = Code, Apex already filtered by Product_Code__c)
        if (this.searchBy === 'Name') {
          this.filterProductsByExactSearch();
        }
      })
      .catch(error => {
      });
  }

fetchProducts() {
    // added by Fuzail - include searchBy here as well so initial load + tab/brand filters respect Name / Code
    fetchProducts({'searchValue':this.searchValue,'brandFilter': this.selectedBrands === 'All' ? '' : this.selectedBrands, stockFilter: this.stockFilter, searchBy: this.searchBy })
      .then(result => {
        console.log('result:- ',result);
        this.data = JSON.parse(result);
        console.log('Data:- ',this.data);
        const brandsSet = new Set(['All','Available Stock']);
        const allBrandsSet = new Set(); // For storing all product brands
        // this.updateProductQuantitiesFromCart(); // commented by Fuzail
        this.updateProductQuantitiesFromCart(); 
        // added by Fuzail - Apply exact name filter ONLY when Search By = Name
        if (this.searchBy === 'Name') {
          this.filterProductsByExactSearch();
        }
        this.data.forEach(product => {
            if (product.productBrand) {  // Assuming productBrand is mapped to 'Product_Brand__c'
                brandsSet.add(product.productBrand); // Add the brand to the Set
                if (product.productBrand !== 'All' && product.productBrand !== 'Available Stock') {
                  allBrandsSet.add(product.productBrand);
                }
            }
            //this.state=product.state;
        });

      // Separate "All" and "Available Stock" from other brands
      this.availableBrands = ['All', 'Available Stock']; // Only these two as tabs
      this.allBrandsList = this.sortBrandsByCustomOrder([...allBrandsSet]); // All other brands for dropdown in custom order
      })
      .catch(error => {
        console.log('error fetching prods',error);
      });
}

// recieves and stores the comment before placing the order
handleCommentChange(event) {
      this.comment = event.target.value;
  }




//this method is used to add Product To  with +
addToCart(event) {
  let selectedProductId = event.currentTarget.dataset.productId;
    console.log('selectedProductId: ' + selectedProductId);

    this.selectedProductForCart = selectedProductId;
    let largeGroup = this.data.filter(activity => activity.productId === selectedProductId);
    console.log('largeGroup: ' + JSON.stringify(largeGroup));

    let productsImages = [];
    let dataOfImages = largeGroup[0].productImages;
    let nameOfProduct = largeGroup[0].productShortDescription;

    if (nameOfProduct.length >= 12) {
        nameOfProduct = nameOfProduct.substring(0, 11);
    }

    let desiredQty = largeGroup[0].productQuantity; // User-selected quantity
    let availableQty = largeGroup[0].availableQuantity; // Inventory stock

    // Block invalid quantities
    if (!desiredQty || desiredQty <= 0) {
        this.showToast('', 'Please enter a valid quantity', 'error');
        return;
    }

    // Check against inventory
    if (desiredQty > availableQty) {
        this.showToast('', 'Insufficient inventory for ' + largeGroup[0].productShortDescription + '. Available: ' + availableQty, 'error');
        return;
    }

    this.objectOfProductToCart = {
        productId: largeGroup[0].productId,
        productIdForCart: largeGroup[0].productId + 'Cart',
        productImage: largeGroup[0].productDisplayImage,
        quantity: desiredQty,
        productName: largeGroup[0].productShortDescription,
        productBrand: largeGroup[0].productBrand,
        productFullName: largeGroup[0].productShortDescription,
        productListPrice: largeGroup[0].productListPrice,
        productOfferPrice: largeGroup[0].productOfferPrice,
        unittotalPrice: (desiredQty * largeGroup[0].productOfferPrice).toFixed(2),
        index: 0,
        prodmeasure: largeGroup[0].uom || 'N/A',
        availableStockQuantity: largeGroup[0].availableQuantity
    };
    console.log('availableStockQuantity at line 225:- ', largeGroup[0].availableQuantity);
    //console.log('availableStockQuantity at line 226:- ', availableStockQuantity);

    for (let key in dataOfImages) {
        productsImages.push({
            images: dataOfImages[key],
            heading: largeGroup[0].productBrand,
            description: largeGroup[0].productShortDescription
        });
    }

    this.productSlides = productsImages;
    this.selectedProductIdForDetailPage = selectedProductId;

    let validateCartProducts = JSON.parse(localStorage.getItem(this.storageKey)) || [];
    let productExisting = false;

    // Update quantity if product already exists in cart
    for (let key in validateCartProducts) {
        if (validateCartProducts[key].productId === this.objectOfProductToCart.productId) {
            let newQty = validateCartProducts[key].quantity + desiredQty;
            if (newQty > availableQty) {
                this.showToast('', 'Total quantity in cart exceeds available stock for ' + largeGroup[0].productShortDescription + '. Available: ' + availableQty, 'error');
                return;
            }
            validateCartProducts[key].quantity = newQty;
            validateCartProducts[key].unittotalPrice = (newQty * largeGroup[0].productOfferPrice).toFixed(2);
            productExisting = true;
            break;
        }
    }

    if (!productExisting) {
        this.objectOfProductToCart.index = validateCartProducts.length + 1;
        validateCartProducts.push(this.objectOfProductToCart);
    }

    // Reset quantity for input tracking
    largeGroup[0].productQuantity = 0;

    this.cartSize = validateCartProducts.length;
    localStorage.setItem(this.storageKey, JSON.stringify(validateCartProducts));
    this.productAddedForCart = validateCartProducts;
    this.prepareOrderSummary();
    this.showToast('', 'Item added to cart', 'success');
    this.updateProductQuantitiesFromCart();
    
  //}
}

//calculates the order summary section  by fetching tax rates from controller

prepareOrderSummary() {
  this.fetchTaxRates(); 
}

get serializedCartItems() {
    return this.productAddedForCart.map((item, index) => ({
        ...item,
        serialNumber: index + 1
    }));
}

get availableBrandsWithoutAll() {
    return this.availableBrands.filter(brand => brand !== 'All' && brand !== 'Available Stock');
}

//used to process the fetched rates of order summary
calculateOrderSummary(taxRates){
  let totalItems = this.productAddedForCart.length;
  let totalPrice = 0;
  let totalDiscount = 0;
  let totalQuantity = 0;
  let totalOrderValue = 0;
  let totalSGSTtax = 0;
  let totalCGSTtax = 0;
  let totalIGSTtax = 0;



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
    this.orderSummary.totalPrceBeforeDiscount = Number(this.priceBeforeDiscount);
    this.priceWithoutTax = (totalPrice / (1 + (taxRates.CGST+taxRates.SGST) / 100)).toFixed(2);
    this.orderSummary.totalPriceExcludingTax = Number(this.priceWithoutTax);
    this.orderSummary.totalOrderValue = (this.priceWithoutTax - this.discountAmount).toFixed(2);
    this.orderSummary.totalDiscount = this.discountAmount;
    console.log('totalQuantity-==  ', totalQuantity );
    this.orderSummary.totalQuantity = totalQuantity;
  }

  totalSGSTtax += (this.orderSummary.totalOrderValue * taxRates.CGST) / 100;
  totalCGSTtax += (this.orderSummary.totalOrderValue * taxRates.SGST) / 100;
  this.percentSGST = taxRates.SGST; 
  this.percentCGST = taxRates.CGST;
  this.showtotalCGSTtax = true;
  console.log('tax rate ka',taxRates.CGST)
  
  this.orderSummary.totalPrice = ((this.priceWithoutTax - this.discountAmount) + totalIGSTtax + totalCGSTtax + totalSGSTtax).toFixed(2);
  this.orderSummary.totalSGST = totalSGSTtax.toFixed(2);
  this.orderSummary.totalCGST = totalCGSTtax.toFixed(2);
  this.orderSummary.totalIGST = totalIGSTtax.toFixed(2);
  this.orderSummary.firstName = this.firstname;
  this.orderSummary.lastName = this.lastname;
  this.orderSummary.email = this.email;
  this.orderSummary.phone = this.phone;
  this.orderSummary.addressLine = this.addressline;
  this.orderSummary.state = this.state;
  this.orderSummary.country = this.country;
  this.orderSummary.company = this.company;
  this.orderSummary.gstin = this.gstin;
  this.orderSummary.city = this.city;
  this.orderSummary.postalCode = this.postalcode;
  this.cartSize = this.productAddedForCart.length;

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
      tempCartId.unittotalPrice = (tempCartId.quantity * tempCartId.productOfferPrice).toFixed(2);
      this.isOrderPlaced = false;
    }

  }
  this.prepareOrderSummary();
  localStorage.setItem(this.storageKey, JSON.stringify(this.productAddedForCart));
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
          // Find the matching product in the original product list to check inventory
          const matchedProduct = this.data.find(prod => prod.productId === tempCartItem.productId);
          if (matchedProduct) {
              const availableQty = matchedProduct.availableQuantity || 0;
              const currentQty = tempCartItem.quantity;

              if (currentQty + 1 > availableQty) {
                  this.showToast('', 'Insufficient inventory for ' + matchedProduct.productShortDescription + '. Available: ' + availableQty, 'error');
                  return;
              }
              
              tempCartItem.quantity += 1;
              tempCartItem.unittotalPrice = (tempCartItem.quantity * tempCartItem.productOfferPrice).toFixed(2);
              this.isOrderPlaced = false;
              break;
          }
      }
  }

  // Update cart summary and sync with localStorage
  this.prepareOrderSummary();
  localStorage.setItem(this.storageKey, JSON.stringify(this.productAddedForCart));
  this.updateProductQuantitiesFromCart();
}


// Value Change Quantity from Cart Update
valueQtyHandleCart(event) {
  let quantityValue = parseInt(event.target.value, 10);
  if (isNaN(quantityValue) || quantityValue <= 0) {
      this.showToast('Error', 'Please enter a valid quantity.', 'error');
      return;
  }

  let nameOf = String(event.target.name); // This should be productIdForCart
  for (let key in this.productAddedForCart) {
      let tempCartItem = this.productAddedForCart[key];
      if (tempCartItem.productIdForCart === nameOf) {
          // Find matching product in main product list to check inventory
          const matchedProduct = this.data.find(prod => prod.productId === tempCartItem.productId);
          if (matchedProduct) {
              const availableQty = matchedProduct.availableQuantity || 0;

              if (quantityValue > availableQty) {
                  //this.showToast('Error', 'Entered quantity exceeds available stock (' + availableQty + ')', 'error');
                  this.showToast('', 'Insufficient inventory for ' + matchedProduct.productShortDescription + '. Available: ' + availableQty, 'error');
                  tempCartItem.quantity = quantityValue;
                  this.isOrderPlaced = true;
                  return;
              }else{
                tempCartItem.quantity = quantityValue;
                tempCartItem.unittotalPrice = (tempCartItem.quantity * tempCartItem.productOfferPrice).toFixed(2);
                this.isOrderPlaced = false;
              }
          }
          break;
      }
  }
  this.prepareOrderSummary();
  localStorage.setItem(this.storageKey, JSON.stringify(this.productAddedForCart));
}

//Remove product from Cart
removeProductFromCart(event) {
  
  this.productAddedForCart = this.productAddedForCart.filter(item => item.productIdForCart !== event.target.name)
  if(this.productAddedForCart.length === 0){
    this.showToast('', 'Cart is Empty', 'info');
    this.cartSize = 0;
    this.orderSummary.totalQuantity = 0;
    this.orderSummary.totalItems = 0;
    this.discountAmountText = '';
    this.discountAmount = 0;
    this.orderSummary.totalOrderValue = 0;
    this.priceBeforeDiscount = 0;
    localStorage.removeItem(this.storageKey);
    this.closeCart();
    return;
  }
  this.discountAmountText = '';
  this.discountAmount = 0;
  this.prepareOrderSummary();
  localStorage.setItem(this.storageKey, JSON.stringify(this.productAddedForCart));
}

//fetch tax rated from controller
  fetchTaxRates() {
  getTaxRates()
    .then((taxRates) => {
      console.log('taxxx- ',+taxRates);
      this.calculateOrderSummary(taxRates);
    })
    .catch((error) => {
      console.error('Error fetching tax rates:', error);
    });
}

//method to generate proposal by placing primary order

  generateProposalAndCloseCart() {
    if (this.isOrderPlaced) {
        return; // Prevent multiple clicks
    }
    if (this.cartSize === 0) {
        this.showToast('', 'Please Add Products To Generate Proposal', 'error');
        return;
    }

    // Inventory validation before placing order
    for (let item of this.productAddedForCart) {
        const matchedProduct = this.data.find(prod => prod.productId === item.productId);
        if (matchedProduct) {
            const availableQty = matchedProduct.availableQuantity || 0;
            if (item.quantity > availableQty) {
                this.showToast('',`Cannot place order. Insufficient inventory for ${item.productName}. Available: ${availableQty}`,'error');
                return; // Stop order placement
            }
        }
    }
 
    // Proceed with order placement if discount is valid
    if (this.discountAmount < this.priceWithoutTax) {
        this.isOrderPlaced = true;
        this.generateProposal();
    } else {
        this.showToast('Discount', 'Discount cannot be greater than price', 'error');
    }
 
  }
  
  generateProposal() {
      console.log('this.discountAmount:- ', this.discountAmount);
      const finanJSONfromProposal = JSON.stringify(this.productAddedForCart);
      console.log('this.orderSummary: ' , this.orderSummary);
      generateProposal({ productsFromCart: finanJSONfromProposal, orderComment: this.comment, orderSummary: JSON.stringify(this.orderSummary) })
      .then(result => {
          console.log('result-->' + result.ordid);
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
                  'totalPrceBeforeDiscount': 0 ,
                  'totalPriceExcludingTax': 0
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
          }
      })
      .catch(error => {
          console.error(error);
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
}