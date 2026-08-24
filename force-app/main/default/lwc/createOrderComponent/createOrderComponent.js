import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import fetchProducts from '@salesforce/apex/OrderProductController.fetchProducts'
import generateProposal from '@salesforce/apex/OrderProductController.generateProposal'
import getTaxRates from '@salesforce/apex/OrderProductCounterPageController.getTaxRates';
import fetchFocusedProducts from '@salesforce/apex/OrderProductController.fetchFocusedProducts';
import getOrdersByAccountForVisitTask from '@salesforce/apex/VisitController.getOrdersByAccountForVisitTask';
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
import getVisitTaskContext from '@salesforce/apex/OrderProductController.getVisitTaskContext';


export default class CreateOrderComponent extends NavigationMixin(LightningElement) {
  @track visitTaskIdTest;
@track showVisitAccDetailComponentInCreateOrd=false;
  @track visitTaskId ;
  @track isLoading = false;
  @api recordId;
    openCart = false;
    @track ShowprodutcList= true;
    @track searchValue = '';
    @track ShowfocusedProdutcList= false;
    @track selectedBrands ='' ;
    isOrderPlaced = false;
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
@track discountPercemtageGivenCheck=0;
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
showtotalIGSTtax = false;
showtotalCGSTtax = false;
percentIGST = 0;
percentCGST = 0;
percentSGST = 0;
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
    'subTotal': 0
  }
 
    totalCartPrice = 0.0; // Decimal (Floating Point)

    @track isCreateOrderComponenet;
    @track  visitedShowFocusedProductList;
    @track  visitedCartPage;
    @track selectedAccountId;
    @track buyerRegion;
    @track schemeSource; // 'PRODUCT' | 'CART'
    @track activeProductId;
    selectedSchemeId;
    isCartContext = false;

    //This method will be called when component loaded which will show create order component

    connectedCallback() {
      this.visitTaskId = this.recordId;
      console.log('visitTaskId--',this.visitTaskId);
      this.loadVisitTaskContext();
      this.isCreateOrderComponenet=true;
      this.ShowprodutcList=true;
      this.openCart=false;
      this.ShowfocusedProdutcList=false;
      this.searchValue = '';
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

        localStorage.setItem('visitedShowProductList', true);
        localStorage.removeItem(`visitedSelfie`); 

        this.visitedShowFocusedProductList = localStorage.getItem('visitedShowFocusedProduct');
        if (this.visitedShowFocusedProductList) {
            this.ShowfocusedProdutcList = true;
            this.ShowprodutcList = false;
            this.fetchFocusedProducts();
        }

        this.visitedCartPage = localStorage.getItem('visitedCartPage');
        if (this.visitedCartPage) {
          this.ShowfocusedProdutcList = false;
          this.ShowprodutcList = false;
          this.openCart = true;

          
        }
  
    }

    loadVisitTaskContext() {
        getVisitTaskContext({ visitTaskId: this.visitTaskId })
            .then(result => {
                console.log('VisitTask Context:', result);

                this.selectedAccountId = result.selectedAccountId;
                this.buyerRegion = result.buyerRegion;

                console.log('selectedAccountId:', this.selectedAccountId);
                console.log('buyerRegion:', this.buyerRegion);
            })
            .catch(error => {
                console.error('Error fetching VisitTask context', error);
            });
    }

     //This method will be called to close cart page
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
        //window.location.reload();
                  this.showVisitAccDetailComponentInCreateOrd=true;

 this.visitTaskIdTest=this.visitTaskId;
      // Wait for LWC to render the child component before accessing it
    setTimeout(() => {
        const childComponent = this.template.querySelector('c-visit-account-detail-component');
        if (childComponent) {
            childComponent.callMeFromParentTest(this.visitTaskIdTest);
        } else {
            console.error('Child component not found!');
        }
    }, 0); // Delay just enough to let DOM update
 
       
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
        this.fetchFocusedProducts();
    }
        
    fetchFocusedProducts() {
        const focusedProductIdsInCart = this.productAddedForCart
            .filter(product => product.focusProduct === true)
            .map(product => product.productId);
        this.availableBrandsFocus = [];
        const visitTaskIdToPass = this.visitTaskId;
        fetchFocusedProducts({'searchValue':null,'brandFilter': null, excludedProductIds: focusedProductIdsInCart, visitTaskIdSelected: visitTaskIdToPass })
            .then(result => {
                this.data = JSON.parse(result);
                const brandsSet = new Set(['All']);
                this.updateProductQuantitiesFromCart(); 
                
                this.data.forEach(product => {
                    if (product.productBrand) {
                        brandsSet.add(product.productBrand);
                    }
                    this.state = product.state;
                    localStorage.setItem('Userstate', this.state);
                });

                brandsSet.forEach(brand => {
                    this.availableBrandsFocus.push({
                        brand,
                        tabClass: brand === (this.activeTab || 'All') ? 'active-brand-tab' : ''
                    });
                });
                this.filterProductsByExactSearch();  
            })
            .catch(error => {
                this.showToast('Error', error?.body?.message || 'Error in fetching focused products.','error' );
            });
    }

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
              
    handleChangeSearchValue(event){
        this.isLoading=true;
        this.searchValue = event.target.value;
        this.loadProducts();
    }

    handleChangeFocusedSearchValue(event){
        this.isLoading=true;
        this.searchValue = event.target.value;
        this.loadFocusProducts();
    }

    loadFocusProducts() {
        const focusedProductIdsInCart = this.productAddedForCart
            .filter(product => product.focusProduct === true)
            .map(product => product.productId);
        const visitTaskIdToPass = this.visitTaskId;
        fetchFocusedProducts({'searchValue':this.searchValue,'brandFilter': this.selectedBrands === 'All' ? '' : this.selectedBrands,
            excludedProductIds: focusedProductIdsInCart ,visitTaskIdSelected: visitTaskIdToPass })
        .then(result => {
            this.data = JSON.parse(result);
            this.updateProductQuantitiesFromCart(); 
            this.filterProductsByExactSearch();  
            this.isLoading=false; 
        })
        .catch(error => {
        });
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

    handleTabChange(event) {
        this.isLoading = true;
        this.selectedBrands = event.target.dataset.brand;
        this.activeTab = this.selectedBrands;
        this.updateBrandTabClasses();
        this.loadProducts();
    }

    loadProducts() {
        const visitTaskIdToPass = this.visitTaskId; 
        fetchProducts({'searchValue':this.searchValue,'brandFilter': this.selectedBrands === 'All' ? '' : this.selectedBrands,visitTaskIdSelected: visitTaskIdToPass  })
        .then(result => {
            this.data = JSON.parse(result);
            this.updateProductQuantitiesFromCart();
            this.filterProductsByExactSearch();
            this.isLoading=false; 
        })
        .catch(error => {
            this.showToast('Error', error?.body?.message || 'Error loading products.', 'error');   
        });
    }

    fetchProducts() {
        const visitTaskIdToPass = this.visitTaskId; 
        fetchProducts({'searchValue':this.searchValue,'brandFilter': this.selectedBrands,visitTaskIdSelected: visitTaskIdToPass })
            .then(result => {
                this.data = JSON.parse(result);
                const brandsSet = new Set(['All']);
                this.updateProductQuantitiesFromCart(); 
                this.data.forEach(product => {
                    if (product.productBrand) {
                        brandsSet.add(product.productBrand);
                    }
                    this.state = product.state;
                    localStorage.setItem('Userstate', this.state);
                });

                this.availableBrands = [...brandsSet].map(brand => ({
                    brand,
                    tabClass: brand === (this.activeTab || 'All') ? 'active-brand-tab' : ''
                }));
                this.filterProductsByExactSearch();
            })
            .catch(error => {
                this.showToast('Error',  error?.body?.message || 'Error fetching product data.', 'error');            
            });
    }

    updateBrandTabClasses() {
        this.availableBrands = this.availableBrands.map(item => ({
            ...item,
            tabClass: item.brand === this.activeTab ? 'active-brand-tab' : ''
        }));
        this.availableBrandsFocus = this.availableBrandsFocus.map(item => ({
            ...item,
            tabClass: item.brand === this.activeTab ? 'active-brand-tab' : ''
        }));
    }
      //This method is used to search focused products by Tabs
      /*handleTabChangeFocus(event) {
        this.isLoading=true;
          this.selectedBrands = event.target.value;

          this.loadFocusProducts();
      }*/
    handleTabChangeFocus(event) {
        this.isLoading = true;
        this.selectedBrands = event.target.dataset.brand;
        this.activeTab = this.selectedBrands;
        this.updateBrandTabClasses();
        this.loadFocusProducts();
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

//This method is used for get dialog box which includes Quantity schemes

    openDialogForQualityScheme(productId) {
        //const productId = event.currentTarget.dataset.productId;
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
            isUnderSS: false
        })
        .then(result => {
            // ✅ ALWAYS normalize to array
           // this.schemeDetails = Array.isArray(result) ? result : [];
            this.schemeDetails = (Array.isArray(result) ? result : []).map(s => ({
                ...s,
                isDisabled: currentQty < s.minQty
            }));

            this.isQualityScheme = true;   
            //this.ShowprodutcList = true;

            if (this.schemeDetails.length === 0) {
                this.noSchemeMessage = NO_Cart_SCHEME_AVAILABLE;
            } else {
                this.noSchemeMessage = '';
            }
        })
        .catch(error => {
            this.schemeDetails = [];
            this.noSchemeMessage = NO_Cart_SCHEME_AVAILABLE;
            this.isQualityScheme = true;  

            console.error('Error fetching quantity schemes');
            console.error(error?.body?.message);
        });


    }

    get hasSchemes() {
        return this.schemeDetails && this.schemeDetails.length > 0;
    }

//This method is used for get dialog box which includes Quantity schemes
  //     openDialogForQualityScheme(event){
  //       const productId = event.target.getAttribute('data-product-id');
  //       getqualityScheme({ productId: productId })
  //       .then(result => {
  //           if (result && result.length > 0) {
  //               this.schemeDetails = result; // Assign the array of scheme details
  //               this.isQualityScheme = true; // Show the dialog if there are schemes
  //           this.ShowprodutcList=false;
  //           } else {
  //               this.isQualityScheme = false; // Hide the dialog if no schemes
  //           }
  //       })
  //       .catch(error => {
  //         this.showToast(
  //           'Error',
  //           error?.body?.message || 'Error retrieving quality scheme.',
  //           'error'
  //       );     
  //        });
  // }

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
        const cart = JSON.parse(localStorage.getItem('cartItems')) || [];
        console.log('cart--',cart);

        applyQuantityScheme({
            cartItems: cart,
            buyerAccountId: this.selectedAccountId,
            buyerRegion: this.buyerRegion,
            selectedSchemeId: this.selectedSchemeId,
            isUnderSS: false
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
            localStorage.setItem('cartItems', JSON.stringify(this.productAddedForCart));

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

//This method is used for get dialog box which includes Quantity schemes for focused products
// openDialogForQualitySchemeFocus(event){
//     const productId = event.target.getAttribute('data-product-id');
//     getqualityScheme({ productId: productId })
//     .then(result => {
//         if (result && result.length > 0) {
//             this.schemeDetails = result; // Assign the array of scheme details
//             this.isQualityFocusScheme = true; // Show the dialog if there are schemes
//         this.ShowfocusedProdutcList=false;
//         } else {
//             this.isQualityFocusScheme = false; // Hide the dialog if no schemes
//         }
//     })
//     .catch(error => {
//       this.showToast(
//         'Error',
//         error?.body?.message || 'Error retrieving quality scheme.',
//         'error'
//     );  
//     });
// }

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
            isUnderSS: false
        })
        .then(result => {
            // ✅ ALWAYS normalize to array
            this.schemeDetails = Array.isArray(result) ? result : [];

            this.isQualityFocusScheme = true;   
            this.ShowfocusedProdutcList = true;

            if (this.schemeDetails.length === 0) {
                this.noSchemeMessage = NO_Cart_SCHEME_AVAILABLE;
            } else {
                this.noSchemeMessage = '';
            }
        })
        .catch(error => {
            this.schemeDetails = [];
            this.noSchemeMessage = NO_Cart_SCHEME_AVAILABLE;
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
                'cartItems',
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
    /*addToCart(event) {
      this.isLoading=true;
        let selectedProductId = event.currentTarget.dataset.productId;
        this.selectedProductForCart = selectedProductId;
        let largeGroup = this.data.filter(activity => (activity.productId == selectedProductId));
      this.fetchProductSchemes();
        let productsImages = [];
        let dataOfImages = largeGroup[0].productImages;
        let nameOfProduct = largeGroup[0].productShortDescription;
        if (nameOfProduct.length >= 12) {
            nameOfProduct = nameOfProduct.substring(0, 11);
        }

        this.objectOfProductToCart = {
          'index': 0,  // Default index, will be updated before pushing

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
            'selectedScheme':'',
            'selectedSchemeId':''
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
        let validateCartProducts = JSON.parse(localStorage.getItem(`cartItems`)) || [];
        let productExisting = false;
        // Check if the product is already in the cart
        for (let key in validateCartProducts) {
            if (validateCartProducts[key].productId == this.objectOfProductToCart.productId) {
                productExisting = true;
              validateCartProducts[key].quantity += largeGroup[0].productQuantity;
                break;
            }
        }
        if(largeGroup[0].productQuantity <= 0){
              this.showToast('', 'Please Add Valid Quantity', 'error');
          }
          else{
      if (!productExisting){
                if (largeGroup[0].productQuantity > 0 ) {
                  this.objectOfProductToCart.index = validateCartProducts.length + 1;

                this.objectOfProductToCart.quantity = largeGroup[0].productQuantity;
                validateCartProducts.push(this.objectOfProductToCart);
                largeGroup[0].productQuantity = 0;
                    }                 
          }          
            largeGroup[0].productQuantity = 0;                   
                this.cartSize = validateCartProducts.length;
                // Save the updated cart to localStorage
                localStorage.setItem(`cartItems`, JSON.stringify(validateCartProducts));     
                this.productAddedForCart = validateCartProducts;  // Update the cart in memory
                this.prepareOrderSummary();
                this.showToast('', 'Item is added to cart', 'success');
              this.updateProductQuantitiesFromCart();
          
          }
          this.isLoading=false;
      }*/

      addToCart(event) {
          this.isLoading = true;
          let selectedProductId = event.currentTarget.dataset.productId;
          this.selectedProductForCart = selectedProductId;

          let largeGroup = this.data.filter(activity => activity.productId == selectedProductId);
          this.fetchProductSchemes();

          let productsImages = [];
          let dataOfImages = largeGroup[0].productImages;

          this.objectOfProductToCart = {
              'index': 0,
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
              'selectedScheme': '',
              'selectedSchemeId': '',
              'availableQuantity': largeGroup[0].availableQuantity,  // ✅ use availableQuantity
              'availableQuantitySent': largeGroup[0].availableQuantitySent,
              'productCode': largeGroup[0].productCode
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

          // Existing cart
          let validateCartProducts = JSON.parse(localStorage.getItem('cartItems')) || [];
          let productExisting = false;

          // Restricted product codes list
          const restrictedProductCodes = productCodeLabel.split(',').map(code => code.trim());

          if (largeGroup[0].productQuantity <= 0) {
              this.showToast('', 'Please Add Valid Quantity', 'error');
              this.isLoading = false;
              return;
          }

          // Check if product already in cart
          for (let item of validateCartProducts) {
              if (item.productId === this.objectOfProductToCart.productId) {
                  productExisting = true;

                  let newQty = item.quantity + largeGroup[0].productQuantity;

                  // 🔹 Restriction check with availableQuantity
                  if (restrictedProductCodes.includes(item.productCode) && newQty > item.availableQuantity) {
                      this.showToast(
                          '',
                          `You cannot add more than available stock (${item.availableQuantity}) for ${item.productName}.`,
                          'error'
                      );
                      this.isLoading = false;
                      return;
                  }

                  item.quantity = newQty;
                  break;
              }
          }

          if (!productExisting) {
              // 🔹 Restriction check with availableQuantity
              if (
                  restrictedProductCodes.includes(this.objectOfProductToCart.productCode) &&
                  largeGroup[0].productQuantity > this.objectOfProductToCart.availableQuantity
              ) {
                  this.showToast(
                      '',
                      `You cannot add more than available stock (${this.objectOfProductToCart.availableQuantity}) for ${this.objectOfProductToCart.productName}.`,
                      'error'
                  );
                  this.isLoading = false;
                  return;
              }

              this.objectOfProductToCart.index = validateCartProducts.length + 1;
              this.objectOfProductToCart.quantity = largeGroup[0].productQuantity;
              validateCartProducts.push(this.objectOfProductToCart);
          }

          largeGroup[0].productQuantity = 0;

          this.cartSize = validateCartProducts.length;
          localStorage.setItem('cartItems', JSON.stringify(validateCartProducts));
          this.productAddedForCart = validateCartProducts;

          this.prepareOrderSummary();
          this.showToast('', 'Item is added to cart', 'success');
          this.updateProductQuantitiesFromCart();
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
                index: index + 1,

                // 🔒 delete rules
                disableDelete: hasPromo
            };
        });
    }
      //This method is used to calculateOrderSummary
      // calculateOrderSummary(taxRates){
      //   let totalItems = this.productAddedForCart.length;
      //   let totalPrice = 0;
      //   let totalDiscount = 0;
      //   let totalQuantity = 0;
      //   let totalOrderValue = 0;
      //   let totalSGSTtax = 0;
      //   let totalCGSTtax = 0;
      //   let totalIGSTtax = 0;
        
      //   for (let key in this.productAddedForCart) {
      //     if (this.productAddedForCart[key].productListPrice > 0) {
      //       totalPrice = totalPrice + (this.productAddedForCart[key].productOfferPrice * this.productAddedForCart[key].quantity);
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
      //     if (this.state === 'state matching' ) {

      //       totalSGSTtax += (this.productAddedForCart[key].productOfferPrice * this.productAddedForCart[key].quantity * taxRates.CGST) / 100;
      //       totalCGSTtax += (this.productAddedForCart[key].productOfferPrice * this.productAddedForCart[key].quantity * taxRates.SGST) / 100;
      //       this.percentSGST = taxRates.SGST; 
      //       this.percentCGST = taxRates.CGST;
      //       this.showtotalCGSTtax = true;
      //     } else {
      //       this.percentIGST = taxRates.IGST;
      //       totalIGSTtax += (this.productAddedForCart[key].productOfferPrice * this.productAddedForCart[key].quantity * taxRates.IGST) / 100;

      //       this.showtotalIGSTtax = true;
      //     }
      //   }
        
      //   this.orderSummary.totalItems = totalItems;
      //   this.orderSummary.totalPrice = (totalPrice + totalIGSTtax + totalCGSTtax + totalSGSTtax).toFixed(2);
      //   this.orderSummary.totalSGST = totalSGSTtax.toFixed(2);
      //   this.orderSummary.totalCGST = totalCGSTtax.toFixed(2);
      //   this.orderSummary.totalIGST = totalIGSTtax.toFixed(2);
      //   this.orderSummary.totalOrderValue = totalOrderValue.toFixed(2);
      //   if(this.discountAmountGiven!=0){
      //       this.orderSummary.totalDiscountRupees=  this.discountAmountGiven;  
      //       this.priceAfterDiscount = (this.orderSummary.totalOrderValue - this.discountAmountGiven).toFixed(2); // Optional: if you need the discount amount separately
      //       this.orderSummary.subTotal=this.priceAfterDiscount;
      //       localStorage.setItem('discountAmountGiven', this.discountAmountGiven.toString());
      //       localStorage.setItem('priceAfterDiscount', this.priceAfterDiscount.toString());
      //   }
      //   if(this.discountPercemtageGiven!=0){
      //       const discountAmount = (this.orderSummary.totalOrderValue * this.discountPercemtageGiven) / 100;
      //       this.discountPercentageAmount = discountAmount.toFixed(2); // Optional: if you need the discount amount separately
      //       this.priceAfterDiscount = (this.orderSummary.totalOrderValue - discountAmount).toFixed(2); // Optional: if you need the discount amount separately
  
      //       this.orderSummary.totalPrice=(this.orderSummary.totalPrice-this.discountPercentageAmount).toFixed(2);
      //       this.orderSummary.totalDiscountRupees=  this.discountPercentageAmount;  
      //       this.orderSummary.subTotal=this.priceAfterDiscount;

      //       localStorage.setItem('discountPercemtageGiven', this.discountPercemtageGiven.toString());
      //       localStorage.setItem('discountPercentageAmount', this.discountPercentageAmount.toString());
      //       localStorage.setItem('priceAfterDiscount', this.priceAfterDiscount.toString());

      //   }

      //   if(this.valueSchemFinalId!=null && this.valueSchemFinalId!=''){
      //       this.orderSummary.valuseSchemeIdOnOrder=this.valueSchemFinalId;
      //       totalCGSTtax=0;
      //       totalSGSTtax=0;
      //       totalIGSTtax=0;
      //       this.showtotalCGSTtax = false;
      //       this.showtotalIGSTtax = false;
      //       if (this.state === 'state matching' ) {
      //           totalSGSTtax = (this.priceAfterDiscount * taxRates.CGST) / 100;
      //           totalCGSTtax = ( this.priceAfterDiscount * taxRates.SGST) / 100;
      //           this.percentSGST = taxRates.SGST; 
      //           this.percentCGST = taxRates.CGST;
      //           this.showtotalCGSTtax = true;
        
      //         } else {
      //           this.percentIGST = taxRates.IGST;
      //           totalIGSTtax = (this.priceAfterDiscount * taxRates.IGST) / 100;
       
      //           this.showtotalIGSTtax = true;
      //         }
      //         this.orderSummary.totalSGST = totalSGSTtax.toFixed(2);
      //         this.orderSummary.totalCGST = totalCGSTtax.toFixed(2);
      //         this.orderSummary.totalIGST = totalIGSTtax.toFixed(2);
              
      //        this.orderSummary.totalPrice = (parseFloat(this.priceAfterDiscount) + parseFloat(totalSGSTtax)+ parseFloat(totalCGSTtax)+ parseFloat(totalIGSTtax)).toFixed(2);;
      //   }
      //   this.totalCartPrice=totalOrderValue;
      //   this.orderSummary.totalDiscount = totalDiscount;
      //   this.orderSummary.totalQuantity = totalQuantity;
      //   this.cartSize = this.productAddedForCart.length;
      // }

      calculateOrderSummary(taxRates) {

          let totalItems = this.productAddedForCart.length;
          let totalQuantity = 0;

          let subTotal = 0;        // Offer price × qty (promo included)
          let listTotal = 0;       // List price × qty
          let totalDiscount = 0;

          let totalSGSTtax = 0;
          let totalCGSTtax = 0;
          let totalIGSTtax = 0;

          /* -----------------------------
            1️⃣ CALCULATE SUBTOTAL
            ----------------------------- */
          this.productAddedForCart.forEach(item => {

              const qty = item.quantity || 0;
              const listPrice = item.productListPrice || 0;
              const offerPrice = item.productOfferPrice || 0;

              totalQuantity += qty;
              listTotal += listPrice * qty;
              subTotal += offerPrice * qty;
          });

          totalDiscount = (listTotal - subTotal).toFixed(2);

          /* -----------------------------
            2️⃣ APPLY VALUE SCHEME
            ----------------------------- */
          let discountedSubTotal = subTotal;

          // Flat discount
          if (this.discountAmountGiven && this.discountAmountGiven > 0) {
              discountedSubTotal = Math.max(
                  subTotal - this.discountAmountGiven,
                  0
              );

              this.orderSummary.totalDiscountRupees = this.discountAmountGiven;
              this.priceAfterDiscount = discountedSubTotal.toFixed(2);
              localStorage.setItem('discountAmountGiven', this.discountAmountGiven.toString());
              localStorage.setItem('priceAfterDiscount', this.priceAfterDiscount.toString());
          }

          // Percentage discount
          if (this.discountPercemtageGiven && this.discountPercemtageGiven > 0) {
              const percentDiscount =
                  (subTotal * this.discountPercemtageGiven) / 100;

              discountedSubTotal = Math.max(
                  subTotal - percentDiscount,
                  0
              );

              this.discountPercentageAmount = percentDiscount.toFixed(2);
              this.orderSummary.totalDiscountRupees =
                  this.discountPercentageAmount;

              this.priceAfterDiscount = discountedSubTotal.toFixed(2);
               localStorage.setItem('discountPercemtageGiven', this.discountPercemtageGiven.toString());
                localStorage.setItem('discountPercentageAmount', this.discountPercentageAmount.toString());
                localStorage.setItem('priceAfterDiscount', this.priceAfterDiscount.toString());
          }

          /* -----------------------------
            3️⃣ TAX CALCULATION
            ----------------------------- */
          this.showtotalCGSTtax = false;
          this.showtotalIGSTtax = false;

          if (this.state === 'state matching') {

              totalSGSTtax =
                  (discountedSubTotal * taxRates.SGST) / 100;

              totalCGSTtax =
                  (discountedSubTotal * taxRates.CGST) / 100;

              this.percentSGST = taxRates.SGST;
              this.percentCGST = taxRates.CGST;
              this.showtotalCGSTtax = true;

          } else {

              totalIGSTtax =
                  (discountedSubTotal * taxRates.IGST) / 100;

              this.percentIGST = taxRates.IGST;
              this.showtotalIGSTtax = true;
          }

          /* -----------------------------
            4️⃣ FINAL TOTAL
            ----------------------------- */
          const finalTotal =
              discountedSubTotal +
              totalSGSTtax +
              totalCGSTtax +
              totalIGSTtax;

          /* -----------------------------
            5️⃣ ASSIGN SUMMARY
            ----------------------------- */
          this.orderSummary.totalItems = totalItems;
          this.orderSummary.totalQuantity = totalQuantity;

          this.orderSummary.totalOrderValue = subTotal.toFixed(2);
          this.orderSummary.subTotal = discountedSubTotal.toFixed(2);

          this.orderSummary.totalSGST = totalSGSTtax.toFixed(2);
          this.orderSummary.totalCGST = totalCGSTtax.toFixed(2);
          this.orderSummary.totalIGST = totalIGSTtax.toFixed(2);

          this.orderSummary.totalDiscount = totalDiscount;
          this.orderSummary.totalPrice = finalTotal.toFixed(2);

          this.totalCartPrice = subTotal;
          this.cartSize = totalItems;

          if (this.valueSchemFinalId) {
            this.orderSummary.valuseSchemeIdOnOrder = this.valueSchemFinalId;
            this.orderSummary.valueSchemeDiscount = this.discountAmountGivenCheck ? Number(this.discountAmountGiven || 0)
                                                        : this.discountPercemtageGivenCheck ? Number(this.discountPercentageAmount || 0) : 0;
          }
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
        this.state=localStorage.getItem('Userstate') || '';
      
        getTaxRates({ state: this.state })
          .then((taxRates) => {
        
            this.calculateOrderSummary(taxRates);
          })
          .catch((error) => {
            this.showToast(
              'Error',
              error?.body?.message || 'Error fetching tax rates.',
              'error'
          );         
         });
      }
    
      //This method is called save order in database
      generateProposal() {
                    const visitTaskIdToPass = this.visitTaskId;
                    const finanJSONfromProposal = JSON.stringify(this.productAddedForCart);
                    generateProposal({ productsFromCart: finanJSONfromProposal, visitIdSelected: visitTaskIdToPass, orderComment: this.comment, orderSummary: JSON.stringify(this.orderSummary) })
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
                                    'valuseSchemeIdOnOrder' :null,
                                    'valueSchemeDiscount' : 0,
                                    'subTotal': 0
                              
                                };
                                localStorage.removeItem(`cartItems`); // Clear the cart from localStorage
                                setTimeout(() => {},0.9);
                       this.isOrderPlaced = false;
                      this.updateAllCalculateCheck();
                    this.removeStoredValues();
                    localStorage.removeItem(`visitedCartPage`); 
                    localStorage.removeItem(`visitedShowProductList`); 

        this.backToVisitTaskMethod();
        localStorage.removeItem(`commentGiven`); 
                            } else {
                                this.isOrderPlaced = false; // Re-enable the button if not successful
                                this.showToast('Error', 'error.', 'error');

                            }
                        })
                        .catch(error => {
                            this.isOrderPlaced = false; // Re-enable the button if there is an error
                            //this.showToast('Error', 'Cant place an order due to some internal error, please reach out to Hangyo Admin', 'error');
                            let errorMessage = 'An unexpected error occurred while placing the order.';
                            if (error && error.body && error.body.message) {
                            errorMessage = error.body.message;
                            }
                            console.error('errorMessage = ',errorMessage);
                            this.showToast('Error', errorMessage, 'error');

                        });
                }
                 //This method is called to show visit task record
                backToVisitTaskMethod(){
                  this.isCreateOrderComponenet=false;
                window.location.reload();
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

        //this.fetchTaxRates();

             this.state=localStorage.getItem('Userstate') || '';

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
                            this.valueSchemeMinCart = result.cartAmount;   
                            localStorage.setItem('valueSchemeMinCart', result.cartAmount);
                        // 🟢 ALWAYS set scheme name for any scheme type
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
                                  // this.getAppliedValueSchemeNameMethod();
                                 localStorage.setItem('discountPercemtageGivenCheck', 'true');                      
                               }
                               else {
                                   // If neither condition is met, clear both values from localStorage
                                   localStorage.removeItem('discountAmountGivenCheck');
                                   localStorage.removeItem('discountPercemtageGivenCheck');
                               }
                               if (result.schemeType === 'Free Product' && result.freeProductId) {
                                 // 🔥 CLEAR ALL DISCOUNT STATE
                                    this.discountAmountGiven = 0;
                                    this.discountPercemtageGiven = 0;
                                    this.discountAmountGivenCheck = false;
                                    this.discountPercemtageGivenCheck = false;
                                    this.priceAfterDiscount = 0;
                                    this.discountPercentageAmount = 0;

                                    localStorage.removeItem('discountAmountGiven');
                                    localStorage.removeItem('discountPercemtageGiven');
                                    localStorage.removeItem('discountPercentageAmount');
                                    localStorage.removeItem('priceAfterDiscount');
                                    localStorage.removeItem('discountAmountGivenCheck');
                                    localStorage.removeItem('discountPercemtageGivenCheck');
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
                    this.showToast(
                      'Error',
                      error?.body?.message || 'An error occurred while applying scheme.',
                      'error'
                  );              
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
                    'cartItems',
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
                      this.showToast(
                        'Error',
                        error?.body?.message || 'An error occurred while retrieving the applied Scheme name.',
                        'error'
                    );                
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
                const savedCart = JSON.parse(localStorage.getItem(`cartItems`)) || [];
                  if (savedCart.length > 0) {
                    this.productAddedForCart = savedCart; 
                    this.cartSize = this.productAddedForCart.length;  
                    this.prepareOrderSummary();  
                    this.updateProductQuantitiesFromCart(); 
                }
                
              }
// this method called to getProductsWithSchemes
    //   fetchProductSchemes() {
    //     getProductsWithSchemes()
    //         .then((schemeMap) => {
    //             this.schemeMap = schemeMap; // Store the scheme map
    //             // Iterate over the products and assign schemes based on quantity criteria
    //             this.productAddedForCart = this.productAddedForCart.map((product) => {
    //                 const schemeDetails = this.schemeMap[product.productId]; // Get the scheme details for the product
    
    //                 // If there are no schemes for the product, assign default values
    //                 if (!schemeDetails || schemeDetails.length === 0) {
    //                     return {
    //                         ...product,
    //                         selectedScheme: 'No scheme available', // Default message for display
    //                         selectedSchemeId: null, // Null for backend
    //                     };
    //                 }
    
    //                 // Filter schemes based on the quantity criteria
    //                 const validSchemes = schemeDetails.filter(scheme => {
    //                     const minimumQuantity = scheme.MinimumPurchaseQuantity;
    //                     return minimumQuantity && product.quantity >= minimumQuantity;
    //                 });
    
    //                 // If there are valid schemes, pick the one with the highest MinimumPurchaseQuantity
    //                 const selectedScheme = validSchemes.length > 0
    //                     ? validSchemes.sort((a, b) => b.MinimumPurchaseQuantity - a.MinimumPurchaseQuantity)[0]
    //                     : null;
    
    //                 // Assign both SchemeDetails and SchemeId
    //                 return {
    //                     ...product,
    //                     selectedScheme: selectedScheme 
    //                         ? `${selectedScheme.SchemeDetails} scheme applied` 
    //                         : 'No scheme available',
    //                     selectedSchemeId: selectedScheme ? selectedScheme.Id : null, // Assign the Scheme Id
    //                 };
    //             });
    
    //         })
    //         .catch((error) => {
    //           this.showToast(
    //             'Error',
    //             error?.body?.message || 'Error fetching schemes.',
    //             'error'
    //         );         
    //          });
    // }

     fetchProductSchemes() {

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
            if (!tempCartId.isPromotional && tempCartId.selectedSchemeId) {
                this.reapplySchemeForBase(tempCartId.productId);
                return;
            }
          }
      
        }
         this.removeInvalidPromos();
        this.prepareOrderSummary();
        this.recomputeSchemeEligibility();
        localStorage.setItem(`cartItems`, JSON.stringify(this.productAddedForCart));
        this.fetchProductSchemes();
      //this.updateAllCalculateCheck();
      //this.removeStoredValues();
      this.updateProductQuantitiesFromCart();
      }
  // Value Change Quantity from Cart Update
  /*valueQtyHandleCart(event) {
    this.updateAllCalculateCheck();
    this.removeStoredValues();
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
      }
  
    }
    this.prepareOrderSummary();
   this.fetchProductSchemes();
  

  localStorage.setItem(`cartItems`, JSON.stringify(this.productAddedForCart));
  }*/

  valueQtyHandleCart(event) {
        this.updateAllCalculateCheck();
        this.removeStoredValues();

        let quantityValue = +parseInt(event.target.value);

        if (quantityValue <= 0 || isNaN(quantityValue)) {
            this.showToast('Error', 'Please enter a valid quantity.', 'error');
            return;
        }

        let nameOf = String(event.target.name);
        // Restricted product codes list
        const restrictedProductCodes = productCodeLabel.split(',').map(code => code.trim());

        for (let key in this.productAddedForCart) {
            let tempCartItem = this.productAddedForCart[key];

            if (tempCartItem.productIdForCart === nameOf) {
                if (
                    restrictedProductCodes.includes(tempCartItem.productCode) &&
                    quantityValue > tempCartItem.availableQuantity
                ) {
                    this.showToast(
                        '',
                        `You cannot enter more than available stock (${tempCartItem.availableQuantity}) for ${tempCartItem.productName}.`,
                        'error'
                    );
                    //return; // 🚫 stop execution, don’t update cart quantity
                }

                // Normal case → update cart
                tempCartItem.quantity = quantityValue <= 1 ? 1 : quantityValue;
                if (!tempCartId.isPromotional && tempCartId.selectedSchemeId) {
                    this.reapplySchemeForBase(tempCartId.productId);
                    return;
                }
                break;
            }
        }

        this.removeInvalidPromos();
        this.prepareOrderSummary();
        this.recomputeSchemeEligibility();
        this.fetchProductSchemes();
        localStorage.setItem('cartItems', JSON.stringify(this.productAddedForCart));
    }

       //  this method called to  increase - Quantity from Cart Update
       /*additionQuantityCart(event) {

        const nameOf = String(event.target.name); // Get the name (productId) of the clicked button
        for (let key in this.productAddedForCart) {
            const tempCartItem = this.productAddedForCart[key];
            // Ensure comparison uses consistent data types
            if (tempCartItem.productIdForCart === nameOf) {
                tempCartItem.quantity += 1; // Increment the quantity
                break; // Exit the loop as the item has been found
            }
        }
      
        // Update cart summary and sync with localStorage
        this.prepareOrderSummary();
        localStorage.setItem('cartItems', JSON.stringify(this.productAddedForCart));
        this.fetchProductSchemes();
      
        this.updateProductQuantitiesFromCart();
      }*/

    additionQuantityCart(event) {
        const nameOf = String(event.target.name); // productIdForCart of the clicked item

        // Restricted product codes list
        const restrictedProductCodes = productCodeLabel.split(',').map(code => code.trim());

        for (let key in this.productAddedForCart) {
            const tempCartItem = this.productAddedForCart[key];
            if (tempCartItem.productIdForCart === nameOf) {
                let newQty = tempCartItem.quantity + 1;
                if (
                    restrictedProductCodes.includes(tempCartItem.productCode) &&
                    newQty > tempCartItem.availableQuantity
                ) {
                    this.showToast(
                        '',
                        `You cannot add more than available stock (${tempCartItem.availableQuantity}) for ${tempCartItem.productName}.`,
                        'error'
                    );
                    return; // 🚫 stop increment
                }
                tempCartItem.quantity = newQty; // ✅ safe to increment
                 if (!tempCartItem.isPromotional && tempCartItem.selectedSchemeId) {
                    this.reapplySchemeForBase(tempCartItem.productId);
                    return; // prevent double calc
                }
                 this.recomputeSchemeEligibility();
                break;
            }
        }

        this.removeInvalidPromos();
        // Update cart summary and sync with localStorage
        this.prepareOrderSummary();
        localStorage.setItem('cartItems', JSON.stringify(this.productAddedForCart));
        this.fetchProductSchemes();
        this.updateProductQuantitiesFromCart();
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
          }
            this.prepareOrderSummary();
              localStorage.setItem(`cartItems`, JSON.stringify(this.productAddedForCart));
              //this.updateAllCalculateCheck();
             // this.removeStoredValues();
     
    }

       //  this method called to  getvalueScheme
          openDialogForValueScheme(event){
    
            //const cartPrice=orderSummary.totalOrderValue;
             console.log('this.totalCartPrice',this.totalCartPrice);
            console.log('openDialogForQualityScheme selectedAccountId', this.selectedAccountId);
            console.log('openDialogForQualityScheme buyerRegion', this.buyerRegion);

            if (!this.totalCartPrice || !this.selectedAccountId || !this.buyerRegion) {
                console.warn('Missing context for value scheme');
                return;
            }
            getvalueScheme({totalCartPrice:this.totalCartPrice, buyerAccountId: this.selectedAccountId,
    buyerRegion: this.buyerRegion, isUnderSS: false})
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
              this.showToast(
                'Error',
                error?.body?.message || 'Error retrieving value scheme.',
                'error'
            );          
            });
          }
 //  this method called to  update comments on order
          handleCommentChange(event) {
            this.comment = event.target.value;
            localStorage.setItem('commentGiven', this.comment.toString());

        }
      
 //  this method called when  place order button clicked
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
                    if (item.quantity > item.availableQuantity) {
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


        //This method will be called to  format the order date
        formatDate(dateString) {
          if (!dateString) return '';
          const date = new Date(dateString);
          const day = String(date.getDate()).padStart(2, '0');
          const month = String(date.getMonth() + 1).padStart(2, '0');
          const year = date.getFullYear();
          return `${day}/${month}/${year}`;
      }
}