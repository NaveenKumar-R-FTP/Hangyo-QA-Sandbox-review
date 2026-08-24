import { LightningElement, track, api, wire } from 'lwc';
import getDraftInvoice from '@salesforce/apex/SecondaryInvoiceHandler.getDraftInvoice';
import createInvoiceData from '@salesforce/apex/SecondaryInvoiceHandler.createInvoiceData';
import getProductName from '@salesforce/apex/SecondaryInvoiceHandler.getProductName';
import getPriceByProduct from '@salesforce/apex/SecondaryInvoiceHandler.getPriceByProduct';
import getPriceForProduct from '@salesforce/apex/CounterInvoiceController.getPriceForProduct';
import getMRPByProduct from '@salesforce/apex/SecondaryInvoiceHandler.getMRPByProduct';
import getStockByProducts from '@salesforce/apex/SecondaryInvoiceHandler.getStockByProducts';
import saveInvoiceAndItems from '@salesforce/apex/SecondaryInvoiceHandler.saveInvoiceAndLineItems';
import generatePDF from '@salesforce/apex/SecondaryInvoicePdfController.generatePDF';
import getProductsWithStock from '@salesforce/apex/SecondaryInvoiceHandler.getProductsWithStock';
import INVOICE_HSN_LABEL from '@salesforce/label/c.Invoice_HSN';
import { isNullEmptyUndefined, isNullEmptyUndefinedObject, showToast } from 'c/dmsUtility';
import { NavigationMixin } from 'lightning/navigation';
import getqualitySchemeFromOrder from '@salesforce/apex/SecondaryInvoiceHandler.getqualitySchemeFromOrder';
import applyQuantitySchemeFromOrder from '@salesforce/apex/SecondaryInvoiceHandler.applyQuantitySchemeFromOrder';
import getvalueSchemeFromOrder from '@salesforce/apex/SecondaryInvoiceHandler.getvalueSchemeFromOrder';
import getAppliedValueScheme from '@salesforce/apex/SchemeEvaluationService.getAppliedValueScheme';
// getAppliedValueSchemeForOrder resolves the ACTUAL Scheme_Slab__c-based discount for Flat
// Discount schemes (cart lines built server-side from the Order's line items) — the old
// getAppliedValueScheme(valueSchemId) above only reads Scheme__c.Discount_Amount__c/
// Discount_Percentage__c directly, which are blank for Flat Discount schemes.
import getAppliedValueSchemeForOrder from '@salesforce/apex/SecondaryInvoiceHandler.getAppliedValueSchemeForOrder';
import getActiveSchemes from '@salesforce/apex/MultiSchemeReimbursementService.getActiveSchemes';
import saveAppliedLines from '@salesforce/apex/MultiSchemeReimbursementService.saveAppliedLines';
import getAppliedValueSchemeName from '@salesforce/apex/SchemeEvaluationService.getAppliedValueSchemeName';
import getProductForValueScheme from '@salesforce/apex/SchemeEvaluationService.getProductForValueScheme';
import NO_Cart_SCHEME_AVAILABLE from '@salesforce/label/c.No_Cart_Value_Scheme';
import getFreeOfferMessageForProducts from '@salesforce/apex/ModernTradeSchemeService.getFreeOfferMessageForProducts';


export default class SecondaryInvoice extends NavigationMixin(LightningElement) {

  @track dmsUserInfo = {};
  @track disAccountName;
  @track disBillingAddress;
  @track dmsuserPhone;
  @track dmsuserFSSAI;
  @track retailerInfo = {};
  @track invoiceInfo = {};
  @track invoiceLineItemsInfo = [];
  originalItemList = [];
  @track itemList;
  deletedItemIds = [];

 @api order;
  @api orderLineItems;
  @api orderFound = false;
  @api isCounterFlow = false;
  @api priceType = 'MRP';
  @track freeOfferMessage = null;

  initialized = false;
  isLoading = false;
  readMode = false;
  showModal = false;
  rowIndex;
  rowAction;
  iliEdit = false;
  iliProduct;
  iliQuantity;
  iliPrice;
  iliStockInHand;
  @track isSaving = false;
  @track isProductSaving = false;

  @track totalDisPercent = 0;
  @track totalDiscount = 0; //dis1 + dis2
  @track totalDiscount1 = 0;
  @track totalDiscount2 = 0;
  @track roundOff = 0; // added by Fuzail - Property to store round off value
  @track originalInvoiceDate;

  @track orderDate;

  searchQuery = '';
  productResults = [];
  selectedProduct = null; // { Id, Name, Stock }
  showDropdown = false;
  searchDebounce; // timer id
  searchDebounceTime = 300; // ms

  // added by Fuzail - Search By: 'Name' = normal product search (old behaviour),
  //                               'Code' = search by Product_Code__c (starts with, e.g. 5300105)
  @track searchBy = 'Name';
  @track searchByDisplayText = 'Name';
  @track showSearchByDropdown = false;

  @track valueSchemeThreshold = 0;
  @track activeProductId;
  selectedSchemeId;
  isCartContext = false;
  @track isQualityScheme = false;
  @track isValueScheme = false;
  @track schemeDetails = []; // Reset the scheme details
  @track valueSchemeDetails = []; // Reset the scheme details
  @track isNoSchemesMessage = false;
  @track noSchemesMessage = '';
  @track discountAmountGiven = 0;
  @track discountAmountGivenCheck = false;
  @track discountPercemtageGiven = 0;
  // The pre-tax subtotal a % Value Scheme discount is actually computed against — the
  // matched Product/Brand lines' subtotal for a scoped Flat Discount scheme (Apex's
  // qualifyingSubtotal), or null for a global/non-scoped scheme (falls back to the
  // whole taxable/cart total). Prevents a scheme scoped to specific SKUs from applying
  // its % discount against unrelated line items too. See decision log, 2026-08-21.
  @track valueSchemeQualifyingSubtotal = null;
  @track valueSchemFinalId = '';
  @track ValueSchemeFinalName = '';
  @track ValueSchemeExist = false;
  @track grossCartTotal = 0;
  @track skipValueSchemeValidationOnce = false;

  // ── Multi-Scheme Retailer Reimbursement ────────────────────────────────
  @track activeSchemes = []; // [{allocationId, schemeName, balance, isApplied, amountApplied}]
@track netPayable = 0;
  @track isReimbursementDialog = false;

  _baseColumns = [
  { label: "#", fieldName: "rowNo", type: "text", readonly: true, initialWidth: 10, cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  { label: "Item Description", fieldName: "ProductName", type: "text", wrapText: true, cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  { label: "HSN", fieldName: "hsn", type: "text", readonly: true, cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  { label: "Stock In Hand", fieldName: "CurrentStock", type: "text", readonly: true, cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  { label: "Quantity", fieldName: "Quantity__c", type: "text", cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  { label: "MRP", fieldName: "mrp", type: "text", readonly: true, cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  // Rate/Amount are bound to displayPrice__c/displayTotalAmount__c rather than the raw
  // Price__c/Total_Amount__c — for Counter Invoice + MRP these show the tax-EXCLUDED
  // value (so Amount lines up with Taxable Amount below), computed in
  // handlePriceCalculations(). Neither column is inline-editable (no `editable: true`
  // here — edits happen via the pencil-icon modal), so this is display-only and doesn't
  // affect what actually gets saved to Invoice_Line_Item__c.
  { label: "Rate", fieldName: "displayPrice__c", type: "text", cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  { label: "Amount", fieldName: "displayTotalAmount__c", type: "text", readonly: true, cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  { label: "TOD", fieldName: "discount1Amt", type: "text", readonly: true, cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  // Purchase Quantity Discount scheme amount for this line (₹ only, no scheme name —
  // the name stays available via Quantity_Scheme_Applied__r.Name but isn't surfaced
  // in this column per requirement). Positioned right after TOD.
  { label: "Scheme", fieldName: "schemeDiscountAmt", type: "text", readonly: true, cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  // Same displayXxx pattern as Rate/Amount above — discount2Amt (raw, saved to
  // Discount_2__c) is untouched; displayDiscount2Amt is the tax-extracted value shown
  // for Counter Invoice + MRP so it lines up with the extracted Amount column.
  { label: "Dis2", fieldName: "displayDiscount2Amt", type: "text", readonly: true, cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  { type: "button-icon", typeAttributes: { iconName: "utility:edit", name: "edit", disabled: { fieldName: 'isPromotional' } }, fixedWidth: 40 },
  { type: "button-icon", typeAttributes: { iconName: "utility:add", name: "add", iconClass: "slds-icon-text-success", disabled: { fieldName: 'isPromotional' } }, fixedWidth: 40 },
  { type: "button-icon", typeAttributes: { iconName: "utility:percent", name: "scheme", title: "Apply Quantity Scheme", iconClass: "slds-icon-text-success", disabled: { fieldName: 'isPromotional' } }, fixedWidth: 40 },
  { type: "button-icon", typeAttributes: { iconName: "utility:delete", name: "delete", iconClass: "slds-icon-text-error", disabled: { fieldName: 'hasPromoChild' }, title: { fieldName: 'deleteTooltip' } }, fixedWidth: 40 }];

  // Counter Orders don't use TOD (Trade Offer Discount) or Purchase Quantity Discount
  // schemes — hide both columns when in the Counter flow rather than maintaining a
  // second hard-coded column array.
  get __columns() {
    if (this.isCounterFlow) {
      return this._baseColumns.filter((col) => col.label !== "TOD" && col.label !== "Scheme");
    }
    // Most invoices never use a Purchase Quantity Discount scheme — hide the "Scheme"
    // column entirely (not just show zeros) unless at least one line actually has one,
    // to keep the datatable from getting needlessly crowded.
    if (!this.hasSchemeDiscount) {
      return this._baseColumns.filter((col) => col.label !== "Scheme");
    }
    return this._baseColumns;
  }

  get hasSchemeDiscount() {
    return (this.itemList || []).some((item) => Number(item.schemeDiscountAmt) > 0);
  }

  // Display-only total for the "Discount Total" row — totalDiscount itself is
  // dis1 + dis2 + per-line scheme discount ONLY (used internally, twice, in
  // handlePriceCalculations()'s taxable value math), so it never included the
  // Value Scheme discount even though Taxable Value was already correctly
  // reduced by it separately. Adding it here (display only) doesn't touch that
  // math — it just makes the "Discount Total" row match what the customer
  // actually sees deducted from Taxable Value.
  get displayDiscountTotal() {
    const lineDiscounts = Number(this.totalDiscount) || 0;
    const valueSchemeDiscount = this.ValueSchemeExist
      ? Number(this.invoiceInfo?.Value_Scheme_Discount__c) || 0
      : 0;
    return this.roundNum(lineDiscounts + valueSchemeDiscount);
  }


  connectedCallback() {
    if (!this.initialized) {
      this.initialized = true;
      if (this.orderFound) {


        this.getDraftInvoiceFromOrder();
      }
    }
    // added by Fuzail - Close dropdown when clicking outside
    this.closeDropdownHandler = this.closeDropdownOnOutsideClick.bind(this);
    document.addEventListener('click', this.closeDropdownHandler);
  }

  disconnectedCallback() {
    // added by Fuzail - Remove event listener on component destroy
    if (this.closeDropdownHandler) {
      document.removeEventListener('click', this.closeDropdownHandler);
    }
  }

  // added by Fuzail - Close Search By dropdown when clicking outside
  closeDropdownOnOutsideClick(event) {
    if (this.showSearchByDropdown) {
      const target = event.target;
      const isInsideDropdown = target.closest('[data-searchby-container]');
      if (!isInsideDropdown) {
        this.showSearchByDropdown = false;
      }
    }
  }

  getDraftInvoiceFromOrder() {
    this.isLoading = true;
    getDraftInvoice({ recordId: this.order.Id }).
    then((result) => {
      if (result && result.invoice && result.invoice.Status__c === 'Draft') {

        this.handleExistingInvoice(result);
      } else {

        this.getInvoiceFromOrder(); // Fallback to existing logic
      }
    }).
    catch((error) => {

      this.dispatchEvent(showToast('Error', error.body?.message || 'Error fetching invoice', [], 'error', ''));
      this.dispatchEvent(new CustomEvent('cancelled', { detail: { message: 'Operation Cancelled' } }));
    }).
    finally(() => {

    });
  }

  handleExistingInvoice(result) {
    this.isLoading = true;
    try {


      if (isNullEmptyUndefinedObject(result)) {

        this.dispatchEvent(showToast(
          'Error',
          'Error while creating invoice, missing either of required details: Order, Retailer, or Order Line items!',
          [],
          'error',
          'sticky'
        ));
        this.dispatchEvent(new CustomEvent('cancelled', { detail: { message: 'Operation Cancelled' } }));
        return;
      }


      this.dmsUserInfo = Object.assign(result.dmsUser);
      this.disAccountName = this.dmsUserInfo?.Contact?.Account?.Name;
      const account = this.dmsUserInfo?.Contact?.Account;

      const addressParts = [
      account?.BillingStreet,
      account?.BillingCity,
      account?.BillingState,
      account?.BillingPostalCode,
      account?.BillingCountry].
      filter((part) => part); // removes undefined/null/empty
      this.dmsuserPhone = account.Phone_1__c;
      this.disBillingAddress = addressParts.join(', ');
      this.retailerInfo = Object.assign(result.retailerAccount);




      this.constructInvoiceData(result);




    } catch (error) {

      this.dispatchEvent(showToast('Error', error?.body?.message || String(error), [], 'error', 'sticky'));
      this.dispatchEvent(new CustomEvent('cancelled', { detail: { message: 'Operation Cancelled' } }));
    } finally {
      this.isLoading = false;
    }
  }

  getInvoiceFromOrder() {
    this.isLoading = true;
    createInvoiceData({ order: this.order, orderItemsList: this.orderLineItems }).then((result) => {

      // Restore applied value scheme from invoice
      this.valueSchemFinalId = result.valueSchemeId;
      this.ValueSchemeExist = !!result.valueSchemeId;
      this.ValueSchemeFinalName = result.valueSchemeName;
      this.valueSchemeDiscount = result.valueSchemeDiscount;
      if (isNullEmptyUndefinedObject(result)) {

        this.dispatchEvent(showToast('Error', 'Error while creating invoice, missing either of required details Order/Retailer/Order Line items!', [], 'error', 'sticky'));
        this.dispatchEvent(new CustomEvent('cancelled', { detail: { 'message': 'Operation Cancelled' } }));
      } else if (Object.hasOwn(result, 'message') && result.message != 'Success') {

        this.dispatchEvent(showToast('Error', result.message, [], 'error', 'sticky'));
        this.dispatchEvent(new CustomEvent('cancelled', { detail: { 'message': 'Operation Cancelled' } }));
      } else {

        this.dmsUserInfo = Object.assign(result.dmsUser);
        this.disAccountName = this.dmsUserInfo?.Contact?.Account?.Name;
        const account = this.dmsUserInfo?.Contact?.Account;
        const addressParts = [
        account?.BillingStreet,
        account?.BillingCity,
        account?.BillingState,
        account?.BillingPostalCode,
        account?.BillingCountry].
        filter((part) => part); // removes undefined/null/empty
        this.dmsuserPhone = account.Phone_1__c;
        this.dmsuserFSSAI = account.FSSAI__c;
        this.disBillingAddress = addressParts.join(', ');
        this.retailerInfo = Object.assign(result.retailerAccount);



        this.constructInvoiceData(result);


      }
    }).catch((error) => {
      this.dispatchEvent(showToast('Error', error.body.message, [], 'error', ''));
      this.dispatchEvent(new CustomEvent('cancelled', { detail: { 'message': 'Operation Cancelled' } }));
    }).finally(() => {
      this.isLoading = false;
    });
  }

  constructInvoiceData(data) {
    this.invoiceInfo = Object.assign(data.invoice);
    this.originalInvoiceDate = this.invoiceInfo.Invoice_Date__c;



    if (data.orderDate) {
      this.orderDate = data.orderDate;
    } else if (this.order && this.order.EffectiveDate__c) {
      this.orderDate = this.order.EffectiveDate__c;
    } else {
      this.orderDate = this.getTodayDateString();

    }


    // Restore applied value scheme from invoice
    this.valueSchemFinalId = this.invoiceInfo.Value_Scheme_Applied__c || data.valueSchemeId;
    this.ValueSchemeExist = !!this.valueSchemFinalId;
    if (this.ValueSchemeExist && data.valueSchemeDiscount > 0) {
      this.discountAmountGiven = data.valueSchemeDiscount;
      this.discountAmountGivenCheck = true;
    }

    if (this.ValueSchemeExist) {
      this.getAppliedValueSchemeNameMethod();
      this.restoreValueSchemeThreshold();
    }

    // ── Multi-Scheme Retailer Reimbursement — fetch currently valid schemes ──
    if (this.retailerInfo?.Id) {
      getActiveSchemes({ retailerAccountId: this.retailerInfo.Id }).
      then((result) => {
        this.activeSchemes = (result || []).map((s) => ({
          allocationId: s.allocationId,
          schemeName: s.schemeName,
          balance: s.balance,
          // "CR/DR (HSU)" auto-applies up to its balance — no manual
          // selection needed. Every other scheme still requires the
          // distributor to pick it via the Reimbursement dialog.
          isApplied: s.schemeName === 'CR/DR (HSU)',
          amountApplied: 0
        }));
        this.handlePriceCalculations();
      }).
      catch((error) => { console.error('getActiveSchemes error:', error); });
    }


    this.invoiceLineItemsInfo = Object.assign(data.invoiceItems);
    this.itemList = this.invoiceLineItemsInfo.map((element) => ({ ...element }));

    let totalDis1 = 0;
    let totalDis2 = 0;
    let totalDis3 = 0;


    const retailerLevelDiscount = this.invoiceInfo?.Discount_1__c || 0; // Retailer-level discount %

    this.itemList.forEach((element, index) => {
      element.rowNo = index + 1;
      element.hsn = INVOICE_HSN_LABEL;
      element.mrp = element.MRP__c;

      element.isPromotional = element.Is_Promotional__c === true;
      element.selectedSchemeId = element.Quantity_Scheme_Applied__c || null;
      element.promoMinQty = element.Promo_Min_Qty__c;
      element.parentProductId = element.Parent_Product__c;
      if (element.isPromotional && !element.selectedSchemeId) {
        element.promoType = 'VALUE'; // Free-product value scheme
      }

      if (element.CurrentStock == null) {
        element.CurrentStock = data.stockByProduct?.[element.Product__c] || 0;
      }

      const quantity = parseFloat(element.Quantity__c) || 0;
      const stock = parseFloat(element.CurrentStock) || 0;
      element.quantityCellClass = stock < quantity ? 'background-color: #fff8c4; color: #7a6600;' : '';




      // TOD eligibility gate
      const todEligible = element.isTodEligible !== false;


      if (!todEligible) {
        element.discount1Amt = 0;
      } else {
        let productDiscount = parseFloat(element.Discount_Percentage__c);
        let discountToUse = productDiscount && productDiscount > 0 ? productDiscount : retailerLevelDiscount;

        if (discountToUse > 0) {
          element.discount1Amt = (element.Quantity__c * element.Price__c * discountToUse / 100).toFixed(2);
        } else {
          element.discount1Amt = 0;
        }

        if (this.invoiceInfo?.Status__c === 'Draft' && element.Discount_1__c > 0) {
          element.discount1Amt = element.Discount_1__c || 0;
        }
      }

      element.isTodEligible = todEligible;

      element.discount2Amt = element.Discount_2__c || 0;

      // Purchase Quantity Discount scheme amount — computed fresh from the FULL
      // (undiscounted) Price__c and the scheme's stored %, same shape as TOD's calc
      // above. Rate/Price__c is never reduced for this scheme type (unlike MRP tax
      // extraction), so this is a straightforward forward calculation. Falls back to
      // the stored Scheme_Discount_Amount__c if the relationship isn't populated on
      // this particular load, so it can't silently show 0 when a value truly exists.
      const schemeInfo = element.Quantity_Scheme_Applied__r;
      if (!element.isPromotional && element.Quantity_Scheme_Applied__c
          && schemeInfo && schemeInfo.Type__c === 'Purchase Quantity Discount') {
        const schemePercent = Number(schemeInfo.Discount_Percentage__c) || 0;
        element.schemeDiscountAmt = (element.Quantity__c * element.Price__c * schemePercent / 100).toFixed(2);
      } else {
        element.schemeDiscountAmt = element.Scheme_Discount_Amount__c || 0;
      }

      totalDis1 += Number(element.discount1Amt) || 0;
      totalDis2 += Number(element.discount2Amt) || 0;
      totalDis3 += Number(element.schemeDiscountAmt) || 0;

      // fallback for ProductName
      if (!element.ProductName && Object.hasOwn(element, 'Product__r')) {
        element.ProductName = element.Product__r.Name;
      }

      if (element.isPromotional && element.ProductName && !element.ProductName.startsWith('🎁')) {
        element.ProductName = `🎁 ${element.ProductName}`;
      }




      this.itemList.forEach((row) => {
        if (row.isPromotional && row.selectedSchemeId) {
          const baseRow = this.itemList.find(
            (r) => !r.isPromotional &&
            r.Parent_Product__c === row.Parent_Product__c
          );
          if (baseRow) {
            baseRow.selectedSchemeId = row.selectedSchemeId;
          }
        }
      });
    });

    this.itemList = [...this.itemList];

    this.itemList = this.recalculatePromoLocks(this.itemList);

    this.totalDisPercent = retailerLevelDiscount;
    this.totalDiscount1 = totalDis1;
    this.totalDiscount2 = totalDis2;
    this.totalSchemeDiscount = Math.round(totalDis3 * 100) / 100;
    this.totalDiscount = Math.round((totalDis1 + totalDis2 + totalDis3) * 100) / 100;
    this.originalItemList = [...this.itemList];

    this.handlePriceCalculations();
  }

  invoiceDateHandler(event) {

    const selectedDate = event.target.value;


    if (!selectedDate) return;

    const todayStr = this.getTodayDateString();
    const earliestStr = this.getEarliestAllowedDate();

    if (selectedDate > todayStr) {
      this.dispatchEvent(showToast('Error', 'Invoice Date cannot be in the future.', [], 'error', 'sticky'));
      event.target.value = this.invoiceInfo.Invoice_Date__c;
      return;
    }

    if (selectedDate < earliestStr) {
      const formattedEarliest = this.formatDateForDisplay(earliestStr);
      const isOrderDateBinding = this.orderDate && earliestStr === this.orderDate;
      const message = isOrderDateBinding ?
      `Invoice Date cannot be before the Order Date (${this.formatDateForDisplay(this.orderDate)}).` :
      `Invoice Date cannot be more than 3 days in the past. Earliest allowed date is ${formattedEarliest}.`;
      this.dispatchEvent(showToast('Error', message, [], 'error', 'sticky'));
      event.target.value = this.invoiceInfo.Invoice_Date__c;
      return;
    }

    this.invoiceInfo.Invoice_Date__c = selectedDate;

  }

  // Returns YYYY-MM-DD that is N calendar days before the given YYYY-MM-DD string
  getDateMinusCalendarDays(dateStr, days) {
    const [y, m, d] = dateStr.split('-').map(Number);
    const date = new Date(y, m - 1, d);
    date.setDate(date.getDate() - days);
    const yyyy = date.getFullYear();
    const mm = String(date.getMonth() + 1).padStart(2, '0');
    const dd = String(date.getDate()).padStart(2, '0');
    return `${yyyy}-${mm}-${dd}`;
  }

  // Returns the earliest selectable invoice date (later of: today-3 days OR order date)
  getEarliestAllowedDate() {
    const todayStr = this.getTodayDateString();
    const minFromToday = this.getDateMinusCalendarDays(todayStr, 3);
    const minFromOrder = this.orderDate || minFromToday;

    // Take whichever lower bound is later (more restrictive)
    return minFromOrder > minFromToday ? minFromOrder : minFromToday;
  }

  get minInvoiceDate() {
    return this.getEarliestAllowedDate();
  }

  get maxInvoiceDate() {
    return this.getTodayDateString();
  }

  getTodayDateString() {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const yyyy = today.getFullYear();
    const mm = String(today.getMonth() + 1).padStart(2, '0');
    const dd = String(today.getDate()).padStart(2, '0');
    return `${yyyy}-${mm}-${dd}`;
  }

  formatDateForDisplay(dateStr) {
    if (!dateStr) return '';
    // Append T00:00:00 to avoid UTC offset shifting the date
    return new Date(dateStr + 'T00:00:00').toLocaleDateString('en-IN', {
      year: 'numeric',
      month: 'long',
      day: 'numeric'
    });
  }

  creditPeriodHandler(event) {

    this.invoiceInfo.Credit_Period__c = event.target.value;

  }

  dis2PercentHandler(event) {
    const inputCmp = event.target;
    let dis2 = inputCmp.value;



    // Treat blank as 0 with no error
    if (dis2 === '') {
      dis2 = 0;
    }

    dis2 = parseFloat(dis2);

    // Validate input
    if (isNaN(dis2) || dis2 !== 0 && (dis2 < 1 || dis2 > 100)) {
      this.invoiceInfo.Discount_2__c = ' ';
      dis2 = ' ';

      inputCmp.setCustomValidity("Please enter a Discount 2% between 1 and 100.");
      inputCmp.reportValidity();

      this.dispatchEvent(
        showToast('Warning!', 'Please enter a Discount 2% between 1 and 100.', [], 'error', '')
      );
    } else {
      inputCmp.setCustomValidity(""); // Clear error
      inputCmp.reportValidity();

      this.invoiceInfo.Discount_2__c = dis2;
    }

    // Recalculate item discount amounts
    let totalDis1 = 0;
    let totalDis2 = 0;
    let totalDis3 = 0;

    this.itemList.forEach((element) => {
      const qty = parseFloat(element.Quantity__c || 0);
      const price = parseFloat(element.Price__c || 0);

      // Discount 2 applies to all items regardless of TOD eligibility
      const dis2Amt = qty * price * dis2 / 100;
      element.discount2Amt = Math.round(dis2Amt * 100) / 100;

      // Re-compute discount1Amt only for TOD-eligible items
      const todEligible = element.isTodEligible !== false;
      if (!todEligible) {
        element.discount1Amt = 0;
      }

      element.totalDiscountAmt = Math.round(((element.discount1Amt || 0) + element.discount2Amt) * 100) / 100;

      totalDis1 += Number(element.discount1Amt) || 0;
      totalDis2 += element.discount2Amt || 0;
      // Scheme discount doesn't change when Discount 2% changes — carry forward the
      // value already computed at construction time so it isn't dropped from the total.
      totalDis3 += Number(element.schemeDiscountAmt) || 0;
    });

    this.totalDisPercent = (this.invoiceInfo.Discount_1__c + dis2).toFixed(2);
    this.totalDiscount1 = Math.round(totalDis1 * 100) / 100;
    this.totalDiscount2 = Math.round(totalDis2 * 100) / 100;
    this.totalSchemeDiscount = Math.round(totalDis3 * 100) / 100;
    this.totalDiscount = Math.round((totalDis1 + totalDis2 + totalDis3) * 100) / 100;

    this.itemList = [...this.itemList];
    this.handlePriceCalculations();
  }

  handleSearchChange(event) {
    this.searchQuery = event.target.value;
    // debounce
    window.clearTimeout(this.searchDebounce);
    if (!this.searchQuery || this.searchQuery.length < 2) {
      this.productResults = [];
      this.showDropdown = false;
      return;
    }
    this.searchDebounce = window.setTimeout(() => {
      this.performProductSearch(this.searchQuery);
    }, this.searchDebounceTime);
  }

  // added by Fuzail - Toggle Search By dropdown
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
    // Trigger search again if there's a search query
    if (this.searchQuery && this.searchQuery.length >= 2) {
      this.performProductSearch(this.searchQuery);
    }
  }

  handleSearchFocus() {
    if (this.productResults && this.productResults.length > 0) {
      this.showDropdown = true;
    }
  }

  // added by Fuzail - pass searchBy so Apex can switch between Name and Product_Code__c search
  performProductSearch(searchKey) {
    this.isLoading = true;
    getProductsWithStock({ searchKey: searchKey, searchBy: this.searchBy }).
    then((result) => {
      this.productResults = (result || []).map((r) => ({
        Id: r.Id,
        Name: r.Name,
        Stock: r.Stock
      }));
      this.showDropdown = this.productResults.length > 0;
    }).
    catch((err) => {

      this.productResults = [];
      this.showDropdown = false;
    }).
    finally(() => {
      this.isLoading = false;
    });
  }

  handleSelectProduct(event) {
    const pid = event.currentTarget.dataset.id;
    const sel = this.productResults.find((p) => p.Id === pid);
    if (!sel) return;

    this.selectedProduct = sel;
    this.searchQuery = sel.Name;
    this.showDropdown = false;

    this.iliProduct = sel.Id;
    this.iliStockInHand = sel.Stock || 0;

    this.fetchPriceAndStock(sel.Id);
  }

  clearProductSelection() {
    this.selectedProduct = null;
    this.searchQuery = '';
    this.productResults = [];
    this.showDropdown = false;
    this.iliProduct = undefined;
    this.iliStockInHand = undefined;
    this.iliPrice = undefined;
  }

  async handleProductChange(event) {
    const productId = this.iliProduct;

    const state = this.retailerInfo.Primary_State__c;

    const type = this.retailerInfo.Distributor_Type__c ?? 'Retailer';




    if (!productId) return;

    try {
      const result = await getPriceByProduct({
        productId: productId,
        state: state,
        accountType: type
      });

      this.iliPrice = result.price ? parseFloat(result.price).toFixed(2) : 0;
      this.iliStockInHand = result.stockInHand != null ? parseFloat(result.stockInHand) : this.iliStockInHand || 0;

    } catch (error) {
      this.dispatchEvent(
        showToast('Error', 'Error fetching price for selected product', [], 'error', '')
      );
    }
  }

 async fetchPriceAndStock(productId) {
    try {
      if (this.isCounterFlow) {
        // Counter Invoice: price depends on the Price Type (MRP/Dealer Price)
        // picked back in Step 1, not on retailer state/type at all.
        const result = await getPriceForProduct({
          productId: productId,
          priceType: this.priceType
        });
        this.iliPrice = result.price ? parseFloat(result.price).toFixed(2) : 0;
                return;
      }
      const state = this.retailerInfo.Primary_State__c;
      const type = this.retailerInfo.Distributor_Type__c ?? 'Retailer';
      const result = await getPriceByProduct({
        productId: productId,
        state: state,
        accountType: type
      });
      this.iliPrice = result.price ? parseFloat(result.price).toFixed(2) : 0;
      this.iliStockInHand = result.stockInHand != null ? parseFloat(result.stockInHand) : this.iliStockInHand || 0;
      const mrpResult = await getMRPByProduct({ productId: productId });
        } catch (err) {
    }
  }

  handleRowAction(event) {

    if (this.readMode) return;
    const actionname = event.detail.action.name;
    const row = event.detail.row;
    switch (actionname) {
      case 'edit':

        this.showModal = true;
        this.rowIndex = row.rowNo;
        this.rowAction = 'edit';
        this.iliProduct = row.Product__c;
        this.iliQuantity = row.Quantity__c;
        this.iliPrice = row.Price__c;
        this.iliStockInHand = row.CurrentStock;
        this.iliEdit = true;
        this.searchQuery = row.ProductName || '';
        this.selectedProduct = { Id: row.Product__c, Name: row.ProductName, Stock: row.CurrentStock };
        break;
      case 'add':

        this.showModal = true;
        this.rowIndex = row.rowNo;
        this.iliEdit = false;
        this.iliProduct = undefined;
        this.iliQuantity = '';
        this.iliPrice = '';
        this.iliStockInHand = '';
        this.rowAction = 'add';
        this.searchQuery = '';
        this.selectedProduct = null;
        break;
      case 'delete':

        let tempData = [...this.itemList];
        if (tempData.length == 1) {
          this.dispatchEvent(showToast('Important!', 'There should be atleast one line item present, use Edit option to modify.', [], 'info', ''));
          return;
        }
        const itemToDelete = tempData.find((ele) => ele.rowNo === row.rowNo);
        const itemId = itemToDelete?.Id;
        if (itemId) {
          this.deletedItemIds.push(itemId);

        }
        if (itemToDelete?.isPromotional && itemToDelete?.promoType === 'VALUE') {
          this.clearValueScheme();
        }
        if (itemToDelete?.isPromotional && !itemToDelete?.promoType) {
          const parentId = itemToDelete.parentProductId;
          tempData.forEach((r) => {
            if (!r.isPromotional && r.Product__c === parentId) {
              r.selectedSchemeId = null;
            }
          });
        }
        tempData = tempData.filter((ele) => ele.rowNo !== row.rowNo);
        tempData = this.recalculatePromoLocks(tempData);
        tempData.forEach((element, index) => element.rowNo = index + 1);
        this.itemList = [...tempData];
        this.recalculateDiscountTotals();
        this.handlePriceCalculations();
        this.applyStockValidationUI();
        this.removeInvalidValueSchemeFromInvoice();
        break;
      case 'scheme':
        this.openQuantitySchemeFromInvoice(row);
        break;
    }
  }

  recalculateDiscountTotals() {
    let totalDis1 = 0;
    let totalDis2 = 0;
    let totalDis3 = 0;

    this.itemList.forEach((item) => {


      totalDis1 += Number(item.discount1Amt) || 0;
      totalDis2 += Number(item.discount2Amt) || 0;
      totalDis3 += Number(item.schemeDiscountAmt) || 0;
    });

    this.totalDiscount1 = Number(Math.round(totalDis1 * 100) / 100);
    this.totalDiscount2 = Number(Math.round(totalDis2 * 100) / 100);
    this.totalSchemeDiscount = Number(Math.round(totalDis3 * 100) / 100);
    this.totalDiscount = Number(Math.round((totalDis1 + totalDis2 + totalDis3) * 100) / 100);



  }

  async handleLineItemSave() {
    if (this.isProductSaving) return;
    this.isProductSaving = true;

    const ili_product = this.iliProduct;
    const ili_quantity_raw = this.template.querySelector('lightning-input-field[data-id=ili_quantity]').value;
    const ili_price_raw = this.iliPrice;

    if (
    isNullEmptyUndefined(ili_product) ||
    isNullEmptyUndefined(ili_quantity_raw) ||
    isNullEmptyUndefined(ili_price_raw))
    {
      this.dispatchEvent(showToast('Error', 'Fill all the field information to proceed with Save', [], 'error', ''));
      this.isProductSaving = false;
      return;
    }

    const ili_quantity = parseInt(ili_quantity_raw);
    const ili_price = parseFloat(ili_price_raw);

    if (isNaN(ili_quantity) || ili_quantity <= 0) {
      this.dispatchEvent(showToast('Error', 'Quantity should be a valid number greater than 0', [], 'error', ''));
      this.isProductSaving = false;
      return;
    }

    if (isNaN(ili_price) || ili_price <= 0) {
      this.dispatchEvent(showToast('Error', 'Price should be a valid number greater than 0', [], 'error', ''));
      this.isProductSaving = false;
      return;
    }

    let productName = "";
    let productMRP = 0;
    let stockQuantity = 0;
    let productLevelDiscount = 0;
    let todEligible = true;
    let success = false;

    try {
      const result = await getProductName({
        productId: ili_product,
        accountId: this.invoiceInfo?.Retailer_Account__c || this.invoiceInfo?.Under_SS__c
      });

      if (!isNullEmptyUndefined(result)) {
        productName = result.name;
        productLevelDiscount = result.discount ?? 0;
        todEligible = result.isTodEligible !== false;

        success = true;
      }

      const [mrpResult, stockResult] = await Promise.all([
      getMRPByProduct({ productId: ili_product }),
      getStockByProducts({ productIds: [ili_product] })]
      );

      if (mrpResult) productMRP = mrpResult;
      if (stockResult && stockResult[ili_product]) stockQuantity = stockResult[ili_product];

    } catch (error) {
      this.dispatchEvent(showToast('Error', 'Error while fetching product information', [], 'error', ''));
      this.isProductSaving = false;
      return;
    }

    if (!success) {
      this.dispatchEvent(showToast('Error', 'Unable to fetch product details', [], 'error', ''));
      this.isProductSaving = false;
      return;
    }

    const discount1 = todEligible ?
    productLevelDiscount > 0 ? productLevelDiscount : this.invoiceInfo.Discount_1__c ?? 0 :
    0;

    const discount2 = this.invoiceInfo.Discount_2__c ?? 0;

    const totalAmount = (ili_price * ili_quantity).toFixed(2);
    const newdiscount1 = todEligible ? +(totalAmount * (discount1 / 100)).toFixed(2) : 0;
    const newdiscount2 = +(totalAmount * (discount2 / 100)).toFixed(2);
    const quantityCellClass = stockQuantity < ili_quantity ? 'background-color: #fff8c4; color: #7a6600;' : '';

    // Prevent duplicate product when adding a new item
    if (this.rowAction === 'add') {
      const duplicateItem = this.itemList.find(
        (item) => item.Product__c === ili_product
      );
      if (duplicateItem) {
        const duplicateLineNumber = duplicateItem.rowNo || this.itemList.indexOf(duplicateItem) + 1;
        this.dispatchEvent(
          showToast('Error', `You've already added ${productName} in line #${duplicateLineNumber}. To make changes, please edit that line item.`, [], 'error', '')
        );
        this.isProductSaving = false;
        return;
      }

      const newItem = {
        "Price__c": ili_price,
        "Product__c": ili_product,
        "Quantity__c": ili_quantity,
        "Total_Amount__c": Number(totalAmount),
        "rowNo": this.rowIndex,
        "hsn": INVOICE_HSN_LABEL,
        "mrp": productMRP,
        "ProductName": productName,
        "CurrentStock": stockQuantity,
        "discount1Amt": Number(newdiscount1),
        "discount2Amt": Number(newdiscount2),
        "Discount_Percentage__c": productLevelDiscount,
        "quantityCellClass": quantityCellClass,
        "isTodEligible": todEligible
      };
      this.itemList.splice(this.rowIndex, 0, newItem);
      this.itemList.forEach((element, index) => element.rowNo = index + 1);
      this.itemList = [...this.itemList];
    } else
    if (this.rowAction === 'edit') {
      this.itemList.forEach((element, index) => {
        if (this.rowIndex === index + 1) {
          element.Price__c = ili_price;
          element.Product__c = ili_product;
          element.Quantity__c = ili_quantity;
          element.Total_Amount__c = Number(totalAmount);
          element.ProductName = productName;
          element.discount1Amt = Number(newdiscount1);
          element.discount2Amt = Number(newdiscount2);
          element.Discount_Percentage__c = productLevelDiscount;
          element.quantityCellClass = quantityCellClass;
          element.isTodEligible = todEligible;
        }
      });
      this.itemList = [...this.itemList];
    }

    // Final cleanup
    this.recalculateDiscountTotals();
    this.selectedProduct = null;
    this.searchQuery = '';
    this.iliProduct = undefined;
    this.iliQuantity = undefined;
    this.iliPrice = undefined;
    this.iliStockInHand = undefined;
    this.showModal = false;
    this.handlePriceCalculations();
    const editedProductId = ili_product;
    this.removeInvalidPromosFromInvoice(editedProductId);
    this.reapplyQuantitySchemeFromInvoice(editedProductId);
    this.applyStockValidationUI();

    this.isProductSaving = false;
  }

  handleLineItemCancel() {
    this.showModal = false;
  }

  handlePriceCalculations() {
    let data = [...this.itemList];
    let totalQuantity = 0;
    let taxableValue = 0;
    let totalGST = 0;
    let invoiceAmount = 0;
    let sgstAmount = 0;
    let cgstAmount = 0;
    let igstAmount = 0;
    let grossCartTotal = 0;

    // Restore value scheme discount from Invoice on first calculation
    if (
    this.ValueSchemeExist &&
    !this.discountAmountGivenCheck &&
    !this.discountPercemtageGivenCheck &&
    Number(this.invoiceInfo.Value_Scheme_Discount__c) > 0)
    {
      this.discountAmountGiven =
      Number(this.invoiceInfo.Value_Scheme_Discount__c);
      this.discountAmountGivenCheck = true;
    }

    // Legal requirement: MRP is tax-inclusive under Indian Legal Metrology rules — the
    // price already contains GST. Per Finance's clarification, GST must still be
    // calculated/shown (for GST return filing) but EXTRACTED from within the MRP rather
    // than zeroed out or added on top — see the taxableValue extraction below. Per
    // explicit business decision this applies ONLY to the Counter Invoice flow — regular
    // Secondary Orders must always be taxed normally (added on top) regardless of
    // Price_Type__c, so isMrp is gated on isCounterFlow as well (mirrors
    // SecondaryInvoiceHandler.cls's Counter_OrderId gate and InvoiceLineItemTrigger's
    // Origin__c gate on the Apex side). The percentages themselves are NOT zeroed —
    // they're the same normal applicable rate as Dealer Price.
    const isMrp = this.isCounterFlow && (this.invoiceInfo.Price_Type__c || this.priceType) === 'MRP';
    let sgstPercent = this.invoiceInfo.SGST__c && Number(this.invoiceInfo.SGST__c) ? this.invoiceInfo.SGST__c : 0;
    let cgstPercent = this.invoiceInfo.CGST__c && Number(this.invoiceInfo.CGST__c) ? this.invoiceInfo.CGST__c : 0;
    let igstPercent = !sgstPercent && !cgstPercent && this.invoiceInfo.IGST__c && Number(this.invoiceInfo.IGST__c) ? this.invoiceInfo.IGST__c : 0;

    // Per-line display values (Rate/Amount columns on the confirmation screen table).
    // Counter Invoice + MRP only: show the tax-EXCLUDED Rate/Amount so Basic Amount and
    // Taxable Amount line up (no confusing gap between them), per Finance's request.
    // IMPORTANT: this only changes what's DISPLAYED in the datatable (displayPrice__c /
    // displayTotalAmount__c) — the real Price__c / Total_Amount__c fields that actually
    // get saved to Invoice_Line_Item__c are left completely untouched, since other parts
    // of the system may depend on those representing the true MRP-based amount.
    const lineTotalRatePercent = sgstPercent + cgstPercent + igstPercent;
    data.forEach((item) => {
      if (!isNullEmptyUndefined(item.Quantity__c))
      totalQuantity = totalQuantity + parseInt(item.Quantity__c);
      if (!isNullEmptyUndefined(item.Total_Amount__c))
      taxableValue = taxableValue + parseFloat(item.Total_Amount__c);
      if (!isNullEmptyUndefined(item.Total_Amount__c)) {
        grossCartTotal += parseFloat(item.Total_Amount__c);
      }

      const rawAmount = !isNullEmptyUndefined(item.Total_Amount__c) ? parseFloat(item.Total_Amount__c) : 0;
      const rawQty = !isNullEmptyUndefined(item.Quantity__c) ? parseFloat(item.Quantity__c) : 0;
      if (isMrp && lineTotalRatePercent > 0) {
        const extractedAmount = rawAmount / (1 + lineTotalRatePercent / 100);
        item.displayTotalAmount__c = this.roundNum(extractedAmount);
        item.displayPrice__c = rawQty > 0 ? this.roundNum(extractedAmount / rawQty) : item.Price__c;
        // Discount 2 must be extracted by the SAME factor as Amount/Rate above, so that
        // displayTotalAmount__c - displayDiscount2Amt reconstructs to the true taxable
        // value for this line. discount2Amt itself (raw) is left untouched since it's
        // what actually gets saved to Discount_2__c.
        item.displayDiscount2Amt = this.roundNum((Number(item.discount2Amt) || 0) / (1 + lineTotalRatePercent / 100));
      } else {
        item.displayTotalAmount__c = item.Total_Amount__c;
        item.displayPrice__c = item.Price__c;
        item.displayDiscount2Amt = item.discount2Amt;
      }

      // Purchase Quantity Discount: Total_Amount__c/Price__c intentionally stay at the
      // FULL (undiscounted) price server-side (see SecondaryInvoiceHandler.
      // createNewInvoiceItems()) — Taxable Value is reduced by this same schemeDiscountAmt
      // separately via totalDis3 below, so Total_Amount__c must stay gross or the discount
      // would be double-counted there. The DISPLAYED Amount/Rate columns, though, should
      // show the discount already netted in — matching what the Order page shows for the
      // same line — so subtract it here, display-only, same pattern as displayDiscountTotal.
      // See decision log, 2026-08-21.
      const qtySchemeType = item.Quantity_Scheme_Applied__r?.Type__c || item.schemeType;
      if (!item.isPromotional && qtySchemeType === 'Purchase Quantity Discount' && Number(item.schemeDiscountAmt) > 0) {
        const schemeDiscount = Number(item.schemeDiscountAmt) || 0;
        item.displayTotalAmount__c = this.roundNum((Number(item.displayTotalAmount__c) || 0) - schemeDiscount);
        item.displayPrice__c = rawQty > 0 ? this.roundNum(item.displayTotalAmount__c / rawQty) : item.displayPrice__c;
      }
    });

    const cartTotalBeforeValueScheme = this.roundNum(grossCartTotal - this.totalDiscount);
    this.grossCartTotal = cartTotalBeforeValueScheme;

    // RE-EVALUATE VALUE SCHEME against the CURRENT cart total on every calculation pass —
    // not just once the cart drops below the threshold it was originally applied at. Flat
    // Discount schemes are tiered (Scheme_Slab__c), so ANY change to the cart total —
    // increase or decrease — can change which slab applies. The old version of this block
    // only ever removed the scheme entirely once below its global minimum; it never
    // re-resolved to a different (higher OR lower) still-valid slab, which is why the
    // discount % used to get stuck at whatever it was when a quantity was last changed and
    // "Apply" re-clicked. See decision log, 2026-08-21.
    this.reapplyValueSchemeOnInvoice();

    // After taxableValue is calculated
    if (this.discountAmountGivenCheck) {
      taxableValue = taxableValue - this.discountAmountGiven;
    }

    if (this.discountPercemtageGivenCheck) {
      // Scoped Flat Discount schemes must discount only the matched SKUs' subtotal
      // (valueSchemeQualifyingSubtotal), not the whole cart's taxableValue — otherwise
      // the % leaks onto non-matching SKUs. Falls back to taxableValue for global
      // schemes (no Scheme_Applicability__c rows), same as before. See decision log,
      // 2026-08-21.
      const pctBase = this.valueSchemeQualifyingSubtotal != null ?
      this.valueSchemeQualifyingSubtotal : taxableValue;
      taxableValue = taxableValue - pctBase * this.discountPercemtageGiven / 100;
    }



    taxableValue = taxableValue - this.totalDiscount;

    // MRP extraction (Counter Invoice + MRP only): back the taxable value out of the
    // tax-inclusive amount so that taxableValue + GST reconstructs to the original
    // MRP-based amount instead of adding GST on top of it.
    const totalRatePercent = sgstPercent + cgstPercent + igstPercent;
    if (isMrp && totalRatePercent > 0) {
      taxableValue = taxableValue / (1 + totalRatePercent / 100);
    }

    // ── Multi-Scheme Retailer Reimbursement — applied AFTER other
    //    discounts, one scheme at a time, each capped at its own
    //    remaining balance against whatever taxable value is left
    //    after the previous scheme (if any) already reduced it.
  sgstAmount = taxableValue * sgstPercent / 100;
    cgstAmount = taxableValue * cgstPercent / 100;
    igstAmount = taxableValue * igstPercent / 100;
    totalGST = (Number(sgstAmount) ? sgstAmount : 0) + (Number(cgstAmount) ? cgstAmount : 0) + (Number(igstAmount) ? igstAmount : 0);

    this.invoiceInfo.Total_Quantity__c = totalQuantity;
    this.invoiceInfo.Taxable_Amount__c = this.roundNum(taxableValue);
    this.invoiceInfo.SGST_Amount__c = this.roundNum(sgstAmount);
    this.invoiceInfo.CGST_Amount__c = this.roundNum(cgstAmount);
    this.invoiceInfo.IGST_Amount__c = this.roundNum(igstAmount);
    this.invoiceInfo.Total_GST__c = this.roundNum(totalGST);

    // added by Fuzail - Calculate round off
    let taxablePlusGST = this.invoiceInfo.Taxable_Amount__c + this.invoiceInfo.Total_GST__c;
    let totalInvoiceAmountRounded = Math.round(taxablePlusGST);
    this.roundOff = this.roundNum(totalInvoiceAmountRounded - taxablePlusGST);
    invoiceAmount = totalInvoiceAmountRounded;
    this.invoiceInfo.Invoice_Amount__c = totalInvoiceAmountRounded;

    // ── Multi-Scheme Retailer Reimbursement — display-only figure.
    //    Taxable_Amount__c, GST fields, and Invoice_Amount__c above
    //    (the true, legally-invoiced Net Amount) are never touched
    //    by this. This only produces netPayable — what the retailer
    //    actually owes after reimbursement — for display purposes.
    let netPayable = this.invoiceInfo.Invoice_Amount__c;
    if (this.activeSchemes && this.activeSchemes.length > 0) {
      this.activeSchemes = this.activeSchemes.map((s) => {
        if (!s.isApplied) {
          return { ...s, amountApplied: 0 };
        }
        let amt = Math.min(s.balance, netPayable);
        if (amt < 0) amt = 0;
        netPayable -= amt;
        return { ...s, amountApplied: this.roundNum(amt) };
      });
    }
    this.netPayable = this.roundNum(netPayable);
    this.invoiceInfo.Invoice_Amount_In_Words__c = this.amountToWords(this.invoiceInfo.Invoice_Amount__c);

    // Persist VALUE SCHEME discount for backend audit
    if (this.ValueSchemeExist) {
      if (this.discountAmountGivenCheck) {
        this.invoiceInfo.Value_Scheme_Discount__c =
        Number(this.discountAmountGiven) || 0;
      } else if (this.discountPercemtageGivenCheck) {
        const pctBase = this.valueSchemeQualifyingSubtotal != null ?
        this.valueSchemeQualifyingSubtotal : this.grossCartTotal;
        // For Counter Invoice + MRP invoices, pctBase (and taxableValue/grossCartTotal at
        // the point the REAL discount math runs, above) are still tax-INCLUSIVE — the MRP
        // extraction division only happens later in this function, after the discount is
        // already netted into taxableValue, so the real Taxable Value ends up correct
        // automatically (the raw discount gets divided down along with everything else).
        // This persisted/displayed figure is computed independently of that flow and must
        // apply the same extraction explicitly here, or it shows the bigger tax-inclusive
        // discount amount instead of the pre-tax figure actually reflected in Taxable
        // Value. See decision log, 2026-08-21.
        const displayPctBase = isMrp && lineTotalRatePercent > 0 ?
        pctBase / (1 + lineTotalRatePercent / 100) : pctBase;
        // Kept at 2 decimal places (not rounded to a whole rupee) per user request,
        // 2026-08-21 — matches how the Order page's equivalent figure is kept
        // (createSecondaryOrderComponentDms.js uses .toFixed(2), never Math.round).
        this.invoiceInfo.Value_Scheme_Discount__c =
        this.roundNum(displayPctBase * this.discountPercemtageGiven / 100);
      }
    } else {
      this.invoiceInfo.Value_Scheme_Discount__c = 0;
    }













    this.applyStockValidationUI();
    this.refreshFreeOfferMessage();
  }

  // Modern Trade free-goods scheme — recomputed any time the cart/line items change so it
  // always reflects the current summed quantity of qualifying products.
  refreshFreeOfferMessage() {
    const productQty = (this.itemList || [])
      .filter((i) => i.Product__c)
      .map((i) => ({ productId: i.Product__c, quantity: parseFloat(i.Quantity__c) || 0 }));

    if (productQty.length === 0) {
      this.freeOfferMessage = null;
      return;
    }

    getFreeOfferMessageForProducts({ productQtyJson: JSON.stringify(productQty) })
      .then((message) => { this.freeOfferMessage = message || null; })
      .catch(() => { this.freeOfferMessage = null; });
  }

  roundNum(num) {
    return Math.round((num + Number.EPSILON) * 100) / 100;
  }
  remarksHandler(event) {
    this.invoiceInfo.Remarks__c = event.target.value;
  }

  // ── Multi-Scheme Retailer Reimbursement handlers ───────────────────────
  openReimbursementDialog() {
    this.isReimbursementDialog = true;
  }

  closeReimbursementDialog() {
    this.isReimbursementDialog = false;
  }

  toggleActiveScheme(event) {
    const id = event.target.dataset.id;
    this.activeSchemes = this.activeSchemes.map((s) =>
    s.allocationId === id ? { ...s, isApplied: !s.isApplied } : s
    );
    this.handlePriceCalculations();
  }

  // Purchase Quantity Discount schemes no longer touch Price__c (Rate stays at the
  // full list price) — the discount is captured separately per line in
  // schemeDiscountAmt / Scheme_Discount_Amount__c. This groups those amounts by
  // scheme Id for display just above Taxable Value.
  get appliedQuantityDiscountSchemes() {
    const schemeMap = new Map();
    (this.itemList || []).forEach((item) => {
      const schemeInfo = item.Quantity_Scheme_Applied__r;
      if (item.Is_Promotional__c || !item.Quantity_Scheme_Applied__c || !schemeInfo) return;
      if (schemeInfo.Type__c !== 'Purchase Quantity Discount') return;

      const discountPercent = Number(schemeInfo.Discount_Percentage__c) || 0;
      const savedTotal = Number(item.schemeDiscountAmt) || 0;
      if (savedTotal <= 0) return;

      const key = item.Quantity_Scheme_Applied__c;
      const existing = schemeMap.get(key);
      if (existing) {
        existing.discountAmount = this.roundNum(Number(existing.discountAmount) + savedTotal);
      } else {
        schemeMap.set(key, {
          schemeId: key,
          schemeName: schemeInfo.Name,
          discountPercent,
          discountAmount: this.roundNum(savedTotal)
        });
      }
    });
    return Array.from(schemeMap.values());
  }

 get appliedSchemeCount() {
    return this.activeSchemes.filter((s) => s.isApplied).length;
  }
  get appliedSchemesList() {
    return (this.activeSchemes || []).filter((s) => s.isApplied && s.amountApplied > 0);
  }
  get amountInWordsRowspan() {
    // Fixed rows always present: Total Unit, Discount 2, Discount Total,
    // Taxable Value, Total GST, Round Off, Invoice Value = 7
    // Plus exactly one row per applied scheme, plus 1 more for Net Payable
    // only when at least one scheme is actually showing.
    const baseRows = 7;
    const schemeRows = this.appliedSchemesList.length;
    const netPayableRow = schemeRows > 0 ? 1 : 0;
    return baseRows + schemeRows + netPayableRow;
  }

  roundNumber(num) {
    return Math.round(num);
  }

  amountToWords(amount) {
    if (amount < 0) return '';
    if (amount == 0) return 'Zero';

    const units = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten',
    'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
    const tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

    function convert(num) {
      if (num < 20) return units[Math.trunc(num)] + ' ';
      if (num < 100) return tens[Math.trunc(num / 10)] + (num % 10 > 0 ? ' ' + convert(num % 10) : ' ');
      if (num < 1000) return units[Math.trunc(num / 100)] + ' Hundred and' + (num % 100 > 0 ? ' ' + convert(num % 100) : '');
      if (num < 10000) return units[Math.trunc(num / 1000)] + ' Thousand ' + (num % 1000 > 0 ? ' ' + convert(num % 1000) : '');
      if (num < 100000) return convert(num / 1000) + ' Thousand ' + (num % 1000 > 0 ? '' + convert(num % 1000) : '');
      if (num < 1000000) return units[Math.trunc(num / 100000)] + ' Lakh ' + (num % 100000 > 0 ? '' + convert(num % 100000) : '');
      if (num < 10000000) return convert(num / 100000) + ' Lakh ' + (num % 100000 > 0 ? '' + convert(num % 100000) : '');
      if (num < 100000000) return units[Math.trunc(num / 10000000)] + ' Crore ' + (num % 10000000 > 0 ? '' + convert(num % 10000000) : '');
      if (num < 1000000000) return convert(num / 10000000) + 'Crore ' + (num % 10000000 > 0 ? '' + convert(num % 10000000) : '');
      return 'Sorry, Too Big';
    }

    let amountInWord = convert(amount);

    let decimalPart = amountInWord !== 'Sorry, Too Big' ? amount.toString().split(".") : '';

    if (!isNullEmptyUndefinedObject(decimalPart[1])) {

      let fraction = decimalPart[1].split("");
      let decimalPlaces = '';
      if (!isNullEmptyUndefinedObject(fraction)) {
        for (let i = 0; i < fraction.length; i++) {
          let num = units[parseInt(fraction[i])];
          decimalPlaces = i === 0 ? 'point ' + num : decimalPlaces + ' ' + num;
        }
        amountInWord = amountInWord + decimalPlaces;
      }
    }


    return amountInWord + ' Only';
  }

  onclickHandleCancel() {

    this.dispatchEvent(new CustomEvent('cancelled', { detail: { 'message': 'Operation Cancelled' } }));
    window.history.back();
  }

  onclickHandleEdit() {

    this.readMode = false;
    window.scrollTo(0, 0);
    this.getInvoiceFromOrder();
  }

  onclickHandleInvoiceSave() {
    const selectedInvoiceDate = this.invoiceInfo.Invoice_Date__c;
    const todayStr = this.getTodayDateString();
    const earliestStr = this.getEarliestAllowedDate();

    if (selectedInvoiceDate > todayStr) {
      this.dispatchEvent(showToast('Error', 'Invoice Date cannot be in the future.', [], 'error', 'sticky'));
      return;
    }

    if (selectedInvoiceDate < earliestStr) {
      const formattedEarliest = this.formatDateForDisplay(earliestStr);
      const isOrderDateBinding = this.orderDate && earliestStr === this.orderDate;
      const message = isOrderDateBinding ?
      `Invoice Date cannot be before the Order Date (${this.formatDateForDisplay(this.orderDate)}).` :
      `Invoice Date cannot be more than 3 days in the past. Earliest allowed date is ${formattedEarliest}.`;
      this.dispatchEvent(showToast('Error', message, [], 'error', 'sticky'));
      return;
    }

    const stockMap = this.getProductStockUsageMap();

    const insufficientStockItems = [];
    stockMap.forEach((val, key) => {
      if (val.used > val.stock) {
        insufficientStockItems.push(key);
      }
    });

    if (insufficientStockItems.length > 0) {
      this.dispatchEvent(showToast(
        'Error',
        'Some items in your invoice exceed the available stock. Please adjust the quantities before proceeding.',
        [],
        'error',
        'sticky'
      ));
      return;
    }
    const discount2Raw = this.invoiceInfo.Discount_2__c;
    const discount2 = Number(discount2Raw);

    if (discount2Raw !== '' && discount2Raw !== null && discount2Raw !== undefined) {
      if (isNaN(discount2) || discount2 < 0 || discount2 > 100) {
        this.dispatchEvent(showToast(
          'Error',
          'Please enter a valid Discount 2 between 1 and 100.',
          [],
          'error',
          'sticky'
        ));
        return;
      }
    }

    this.invoiceLineItemsInfo = this.itemList.map((item) => ({
      Id: item.Id,
      Invoice__c: this.invoiceInfo.Id,
      Product__c: item.Product__c,
      Quantity__c: item.Quantity__c,
      Price__c: item.Price__c,
      Total_Amount__c: item.Total_Amount__c,
      MRP__c: item.mrp || item.MRP__c || 0,

      Discount_1__c: item.discount1Amt || 0,
      Discount_2__c: item.discount2Amt || 0,
      Scheme_Discount_Amount__c: item.schemeDiscountAmt || 0,

      Is_Promotional__c: item.isPromotional === true,
      Quantity_Scheme_Applied__c: item.selectedSchemeId || null,
      Promo_Min_Qty__c: item.Promo_Min_Qty__c || item.promoMinQty || null,
      Parent_Product__c: item.parentProductId || null
    }));




    let invLineItemStringify = JSON.stringify(this.invoiceLineItemsInfo);


    // persist value scheme
    if (this.ValueSchemeExist && this.valueSchemFinalId) {
      this.invoiceInfo.Value_Scheme_Applied__c = this.valueSchemFinalId;
      this.invoiceInfo.Value_Scheme_Discount__c = this.roundNum(this.invoiceInfo.Value_Scheme_Discount__c || 0);
    } else {
      this.invoiceInfo.Value_Scheme_Applied__c = null;
      this.invoiceInfo.Value_Scheme_Discount__c = 0;
    }
    this.isSaving = true;
    saveInvoiceAndItems({ invoice: this.invoiceInfo, invItemList: invLineItemStringify, deletedItemIds: this.deletedItemIds }).then((result) => {

      if (!isNullEmptyUndefinedObject(result)) {

        // ── Multi-Scheme Retailer Reimbursement — persist applied lines ──
        const appliedLines = (this.activeSchemes || []).
        filter((s) => s.isApplied && s.amountApplied > 0).
        map((s) => ({ allocationId: s.allocationId, amount: s.amountApplied }));
        saveAppliedLines({
          invoiceId: result.invoice.Id,
          appliedLinesJson: JSON.stringify(appliedLines)
        }).catch((error) => void 0);

        this.dispatchEvent(showToast('Success', 'Invoice And Invoice Line Items Saved Successfully', [], 'success', ''));
        this[NavigationMixin.Navigate]({
          type: 'standard__recordPage',
          attributes: {
            recordId: result.invoice.Id,
            objectApiName: 'Invoice__c',
            actionName: 'view'
          }
        });
      }
    }).
    catch((error) => {


      this.dispatchEvent(showToast('Error', 'Error while saving.' + (error?.body?.message || error.message || ''), [], 'error', 'sticky'));
      this.isSaving = false;
      return '';
    });

    return 'Success';
  }

  async onclickHandlePDFGeneration() {
    this.invoiceLineItemsInfo = [...this.itemList];
    const insufficientStockItems = this.itemList.filter((item) => item.Quantity__c > item.CurrentStock);

    if (insufficientStockItems.length > 0) {
      this.dispatchEvent(showToast(
        'Error',
        'Some items in your invoice exceed the available stock. Please adjust the quantities before generating the PDF.',
        [],
        'error',
        'sticky'
      ));
      return;
    }

    this.invoiceLineItemsInfo = this.itemList.map(({ CurrentStock, ...rest }) => ({
      ...rest,
      Discount_1__c: rest.discount1Amt || 0,
      Discount_2__c: rest.discount2Amt || 0,
      Scheme_Discount_Amount__c: rest.schemeDiscountAmt || 0
    }));

    let statusMsg = '';
    await saveInvoiceAndItems({ invoice: this.invoiceInfo, invItemList: this.invoiceLineItemsInfo }).then((result) => {

      if (!isNullEmptyUndefinedObject(result)) {
        this.constructInvoiceData(result);
        this.dispatchEvent(showToast('Success', 'Generating PDF...', [], 'success', ''));
        statusMsg = 'success';
      }
    }).
    catch((error) => {
      this.dispatchEvent(showToast('Error', 'Error while generating PDF...' + (error?.body?.message || error.message || ''), [], 'error', 'sticky'));
    });
    if (!isNullEmptyUndefined(statusMsg)) {
      await generatePDF({ oInvoice: this.invoiceInfo, distributorId: this.dmsUserInfo.Id, retailerId: this.retailerInfo.Id }).then((result) => {
        if (!isNullEmptyUndefined(result)) {

        }
        window.open(window.location.origin + '/dms/sfc/servlet.shepherd/version/download/' + result);
      }).catch((error) => {

      }).finally(() => {
        this.isLoading = false;
      });
    } else {
      this.isLoading = false;
    }
    window.scrollTo(0, 0);
  }

  openQuantitySchemeFromInvoice(row) {
    this.isCartContext = true;
    this.activeProductId = row.Product__c;
    this.selectedSchemeId = null;

    getqualitySchemeFromOrder({
      productId: row.Product__c,
      orderId: this.order.Id
    }).
    then((result) => {
      const currentQty = row.Quantity__c;

      this.schemeDetails = (Array.isArray(result) ? result : []).map((s) => ({
        ...s,
        isDisabled: currentQty < s.minQty
      }));

      this.isQualityScheme = true;
    }).
    catch((err) => {

      this.schemeDetails = [];
      this.isQualityScheme = true;
    });
  }

  get hasSchemes() {
    return this.schemeDetails && this.schemeDetails.length > 0;
  }

  closeQualitySchemeDialog() {
    this.isQualityScheme = false;
  }

  handleSchemeSelection(event) {
    const selectedId = event.target.value;
    this.selectedSchemeId = selectedId;

    this.schemeDetails = this.schemeDetails.map((s) => ({
      ...s,
      isSelected: s.schemeId === selectedId
    }));
  }

  get isApplyDisabled() {
    return !this.selectedSchemeId;
  }

  applyScheme() {
    if (!this.selectedSchemeId || !this.activeProductId) {
      this.dispatchEvent(
        showToast('Error', 'Please select a scheme', [], 'error', '')
      );
      return;
    }

    // Purchase Quantity Discount schemes never add a bonus/promo line — the shared
    // Apex (SchemeEvaluationService.applyQuantityScheme) deliberately returns an empty
    // list for this type, which would otherwise look like "no promo applicable" below
    // and silently do nothing. Apply it directly here instead, same as the order cart's
    // applyScheme() does — no Apex round-trip needed since there's no bonus line to
    // resolve, just the line's own schemeDiscountAmt.
    const selectedSchemeDetail = (this.schemeDetails || []).find(
      (s) => s.schemeId === this.selectedSchemeId
    );
    if (selectedSchemeDetail?.schemeType === 'Purchase Quantity Discount') {
      const baseProductId = this.activeProductId;
      const cleanedList = this.itemList.filter(
        (row) => !(row.isPromotional && row.parentProductId === baseProductId)
      );
      const baseItem = cleanedList.find(
        (row) => row.Product__c === baseProductId && !row.isPromotional
      );

      if (!baseItem) {
        this.dispatchEvent(showToast('Error', 'Could not find the line item to apply the scheme to', [], 'error', ''));
        return;
      }

      const discountPercent = Number(selectedSchemeDetail.discountPercentage) || 0;
      baseItem.selectedSchemeId = this.selectedSchemeId;
      baseItem.schemeType = selectedSchemeDetail.schemeType;
      baseItem.Quantity_Scheme_Applied__r = {
        Name: selectedSchemeDetail.schemeName,
        Discount_Percentage__c: discountPercent,
        Type__c: selectedSchemeDetail.schemeType
      };
      baseItem.schemeDiscountAmt = (
        (Number(baseItem.Quantity__c) || 0) * (Number(baseItem.Price__c) || 0) * discountPercent / 100
      ).toFixed(2);

      this.itemList = [...this.recalculatePromoLocks(cleanedList)];
      this.recalculateDiscountTotals();
      this.handlePriceCalculations();
      this.isQualityScheme = false;

      this.dispatchEvent(showToast('Success', 'Quantity scheme applied', [], 'success', ''));
      return;
    }

    this.isLoading = true;

    const normalizedItems = this.itemList.
    filter((r) => !r.isPromotional).
    map((row) => ({
      productId: row.Product__c,
      quantity: row.Quantity__c,
      productOfferPrice: row.Price__c,
      productName: row.ProductName,
      productFullName: row.ProductName,
      availableStockQuantity: row.CurrentStock || 0,
      productBrand: '',
      prodmeasure: '',
      hsn: INVOICE_HSN_LABEL,
      mrp: row.MRP__c
    }));

    applyQuantitySchemeFromOrder({
      cartItems: normalizedItems,
      orderId: this.order.Id,
      selectedSchemeId: this.selectedSchemeId
    }).
    then((promoLines) => {

      if (!promoLines || promoLines.length === 0) {
        this.dispatchEvent(
          showToast('Info', 'No promotional items applicable', [], 'info', '')
        );
        this.isQualityScheme = false;
        return;
      }

      const baseProductId = this.activeProductId;

      let cleanedList = this.itemList.filter(
        (row) => !(row.isPromotional && row.parentProductId === baseProductId)
      );

      const baseIndex = cleanedList.findIndex(
        (row) => row.Product__c === baseProductId && !row.isPromotional
      );

      cleanedList[baseIndex].selectedSchemeId = this.selectedSchemeId;

      if (baseIndex === -1) {

        return;
      }

      promoLines.forEach((promo, idx) => {

        const originalRate = promo.productListPrice;
        const qty = promo.quantity;
        let grossAmount = 0;
        let discountAmt = 0;
        let discountedTotal = 0;

        const isFreeProduct =
        promo.discountPercentage === null ||
        promo.discountPercentage === 100;

        if (!isFreeProduct) {
          grossAmount = originalRate * qty;
          discountedTotal = promo.unittotalPrice || 0;
          discountAmt = grossAmount - discountedTotal;
        }

        const promoRow = {
          Product__c: promo.productId,
          Parent_Product__c: baseProductId,
          ProductName: `🎁 ${promo.productName}`,
          Quantity__c: qty,
          Price__c: originalRate,
          mrp: promo.mrp,
          Total_Amount__c: grossAmount,
          discount1Amt: this.roundNum(discountAmt),
          discount2Amt: 0,
          hsn: promo.hsn || '',
          CurrentStock: promo.availableStockQuantity || 0,
          Is_Promotional__c: true,
          Quantity_Scheme_Applied__c: this.selectedSchemeId,
          Promo_Min_Qty__c: promo.promoMinQty,
          isPromotional: true,
          parentProductId: baseProductId,
          selectedSchemeId: this.selectedSchemeId,
          isReadOnly: true,
          promoMinQty: promo.promoMinQty,
          isFreePromo: isFreeProduct
        };

        cleanedList.splice(baseIndex + 1 + idx, 0, promoRow);
      });

      cleanedList = this.recalculatePromoLocks(cleanedList);
      cleanedList.forEach((row, i) => row.rowNo = i + 1);
      const baseItem = cleanedList.find(
        (i) => i.Product__c === baseProductId && !i.isPromotional
      );
      if (baseItem) {
        baseItem.selectedSchemeId = this.selectedSchemeId;
      }

      this.itemList = [...cleanedList];

      this.recalculateDiscountTotals();
      this.handlePriceCalculations();
      this.removeInvalidValueSchemeFromInvoice();

      this.isQualityScheme = false;

      this.dispatchEvent(
        showToast('Success', 'Quantity scheme applied', [], 'success', '')
      );
      this.applyStockValidationUI();
    }).
    catch((err) => {

      this.dispatchEvent(
        showToast(
          'Error',
          err?.body?.message || 'Failed to apply scheme',
          [],
          'error',
          ''
        )
      );
    }).
    finally(() => {
      this.isLoading = false;
    });
  }

  recalculatePromoLocks(list) {
    const baseIdsWithPromo = new Set(
      list.
      filter((r) => r.isPromotional).
      map((r) => r.parentProductId)
    );

    return list.map((row) => {
      const isBaseWithPromo =
      !row.isPromotional &&
      baseIdsWithPromo.has(row.Product__c);

      return {
        ...row,
        hasPromoChild: isBaseWithPromo,
        deleteTooltip: isBaseWithPromo ?
        'Remove promo item first' :
        'Delete'
      };
    });
  }

  closeValueSchemeDialog() {
    this.isValueScheme = false;
    this.openCart = true;
  }

  removeInvalidPromosFromInvoice(editedProductId) {


    const baseRow = this.itemList.find(
      (r) => !r.isPromotional && r.Product__c === editedProductId
    );
    if (!baseRow) return;

    const baseQty = Number(baseRow.Quantity__c) || 0;
    const before = this.itemList.length;




    let cleaned = this.itemList.filter((item) => {

      if (!item.isPromotional) return true;
      if (item.promoType === 'VALUE') return true;

      const realParentId =
      item.parentProductId ||
      this.itemList.find(
        (r) =>
        !r.isPromotional &&
        r.selectedSchemeId === item.selectedSchemeId
      )?.Product__c;




      if (realParentId !== editedProductId) return true;

      return baseQty >= item.promoMinQty;
    });

    if (cleaned.length !== before) {
      this.itemList = this.recalculatePromoLocks(cleaned);
      this.itemList.forEach((r, i) => r.rowNo = i + 1);
      this.recalculateDiscountTotals();
      this.handlePriceCalculations();

      this.dispatchEvent(
        showToast(
          'Info',
          'Promotional items removed as base product quantity changed',
          [],
          'info',
          ''
        )
      );
    }
  }

  // Builds one CartLineWrapper (productId, productBrand, lineAmount) per LIVE invoice line
  // item — mirrors createSecondaryOrderComponentDms.js's buildCartLinesForSchemeEvaluation().
  // Reads from this.itemList (the current, possibly user-edited working set shown on
  // screen) rather than the original Order, so a Flat Discount scheme's slab always
  // resolves against what the invoice actually shows right now, including any quantity
  // edits made after the scheme was first applied. Product_Brand__c is looked up two ways
  // since itemList rows can come from either the fresh-create path (flat
  // item.Product_Brand__c, built server-side in createNewInvoiceItems()) or an existing
  // draft invoice reload (nested item.Product__r.Product_Brand__c, from invoiceItemFields'
  // SOQL) — see decision log, 2026-08-21.
  buildCartLinesForInvoice() {
    return (this.itemList || [])
      .filter((item) => !item.Is_Promotional__c && item.Product__c)
      .map((item) => ({
        productId: item.Product__c,
        productBrand: item.Product_Brand__c || item.Product__r?.Product_Brand__c || '',
        lineAmount: Number(item.Total_Amount__c) || 0
      }));
  }

  openDialogForValueSchemeFromInvoice() {

    const totalInvoiceValue = this.invoiceInfo?.Taxable_Amount__c;

    if (!totalInvoiceValue || !this.order?.Id) {

      return;
    }

    getvalueSchemeFromOrder({
      totalAmount: totalInvoiceValue,
      orderId: this.order.Id,
      cartLinesJson: JSON.stringify(this.buildCartLinesForInvoice())
    }).
    then((result) => {

      if (result && result.length > 0) {

        if (this.valueSchemFinalId) {
          result = result.map((scheme) => {
            if (scheme.id === this.valueSchemFinalId) {
              return { ...scheme, isApplied: true };
            }
            return scheme;
          });

          result.sort((a, b) => (b.isApplied ? 1 : 0) - (a.isApplied ? 1 : 0));
        }

        this.valueSchemeDetails = result;
        this.isValueScheme = true;
        this.isNoSchemesMessage = false;

      } else {
        this.isNoSchemesMessage = true;
        this.isValueScheme = true;
        this.noSchemesMessage = NO_Cart_SCHEME_AVAILABLE;
      }
    }).
    catch((error) => {
      console.error('Error in openDialogForValueSchemeFromInvoice:', error);
    });
  }

  applyValueSchemeOnInvoice(event) {

    const valueSchemId = event.target.dataset.applyId;
    this.valueSchemFinalId = valueSchemId;

    // Reset the reapplyValueSchemeOnInvoice() guard so the very next quantity
    // change after freshly applying a scheme is always re-checked against Apex
    // (the guard key below is keyed on schemeId+cartTotal, and a stale key from
    // a PRIOR scheme/cart-total combo could otherwise suppress the first check).
    this._lastReappliedInvoiceValueSchemeKey = null;

    this.isValueScheme = false;
    this.openCart = true;

    this.clearExistingValueSchemeFromInvoice();

    getAppliedValueSchemeForOrder({
      valueSchemId,
      orderId: this.order.Id,
      cartTotal: this.grossCartTotal || this.invoiceInfo?.Taxable_Amount__c,
      cartLinesJson: JSON.stringify(this.buildCartLinesForInvoice())
    }).
    then((result) => {
      this.valueSchemeThreshold = result.cartAmount;
      localStorage.setItem('valueSchemeThreshold', this.valueSchemeThreshold);
      this.ValueSchemeExist = true;
      this.getAppliedValueSchemeNameMethod();
      this.valueSchemeQualifyingSubtotal = result.qualifyingSubtotal != null ?
      result.qualifyingSubtotal : null;
      if (result.discountAmount != null) {
        this.discountAmountGiven = result.discountAmount;
        this.discountPercemtageGivenCheck = false;
        this.discountAmountGivenCheck = true;
      } else
      if (result.discountPercentage != null) {
        this.discountPercemtageGiven = result.discountPercentage;
        this.discountAmountGivenCheck = false;
        this.discountPercemtageGivenCheck = true;
      }

      if (result.schemeType === 'Free Product' && result.freeProductId) {
        const promoQty = result.promoQty || 1;
        this.addValuePromoProductToInvoice(result.freeProductId, promoQty);
      }

      this.skipValueSchemeValidationOnce = true;
      this.recalculateDiscountTotals();
      this.handlePriceCalculations();

      this.dispatchEvent(
        showToast('Success', 'Value scheme applied on invoice', [], 'success', '')
      );
    }).
    catch((error) => {
      console.error('Error in applyValueSchemeOnInvoice:', error);
    });
  }

  restoreValueSchemeThreshold() {
    if (!this.valueSchemFinalId) return;

    getAppliedValueSchemeForOrder({
      valueSchemId: this.valueSchemFinalId,
      orderId: this.order?.Id,
      cartTotal: this.grossCartTotal || this.invoiceInfo?.Taxable_Amount__c,
      cartLinesJson: JSON.stringify(this.buildCartLinesForInvoice())
    }).
    then((result) => {
      this.valueSchemeThreshold = result.cartAmount;
      this.valueSchemeQualifyingSubtotal = result.qualifyingSubtotal != null ?
      result.qualifyingSubtotal : null;
      if (result.discountAmount != null) {
        this.discountAmountGiven = result.discountAmount;
        this.discountAmountGivenCheck = true;
        this.discountPercemtageGivenCheck = false;
      } else
      if (result.discountPercentage != null) {
        this.discountPercemtageGiven = result.discountPercentage;
        this.discountPercemtageGivenCheck = true;
        this.discountAmountGivenCheck = false;
      }

      this.handlePriceCalculations();

    }).
    catch((err) => {

    });
  }

  addValuePromoProductToInvoice(productId, promoQty) {

    if (this.itemList.some((r) => r.isPromotional && r.Product__c === productId)) {
      return;
    }

    getProductForValueScheme({ productId }).
    then((product) => {

      const promoRow = {
        Product__c: product.productId,
        ProductName: `🎁 ${product.productName}`,
        Quantity__c: promoQty,
        Price__c: product.productOfferPrice || 0,
        mrp: product.mrp || 0,
        Total_Amount__c: 0,
        discount1Amt: 0,
        discount2Amt: 0,
        hsn: product?.hsn || '',
        CurrentStock: product.availableStockQuantity || 0,
        Is_Promotional__c: true,
        Quantity_Scheme_Applied__c: null,
        Promo_Min_Qty__c: 0,
        isPromotional: true,
        promoType: 'VALUE',
        parentProductId: null,
        isReadOnly: true
      };

      this.itemList.push(promoRow);
      this.itemList.forEach((r, i) => r.rowNo = i + 1);
      this.itemList = [...this.itemList];

      this.recalculateDiscountTotals();
      this.handlePriceCalculations();
    }).
    catch((error) => {

    });
  }

  getAppliedValueSchemeNameMethod() {
    getAppliedValueSchemeName({ valueSchemActiveId: this.valueSchemFinalId }).
    then((result) => {
      if (result != null && result !== '' && result != undefined)
      {
        this.ValueSchemeExist = true;
        this.ValueSchemeFinalName = result;
        localStorage.setItem('ValueSchemeFinalName', this.ValueSchemeFinalName.toString());
        localStorage.setItem('ValueSchemeExist', this.ValueSchemeExist.toString());
      }
    }).
    catch((error) => {

    });
  }

  // Re-evaluates the currently applied Value Scheme's discount against the CURRENT
  // cart total/lines — called on every handlePriceCalculations() pass once a scheme
  // is applied. For Flat Discount schemes this lets the discount move to a lower OR
  // higher Scheme_Slab__c as quantities change, instead of staying stuck on whatever
  // % it had when "Apply" was last clicked. Mirrors
  // createSecondaryOrderComponentDms.js's reapplyValueSchemeDiscount(). See decision
  // log, 2026-08-21.
  reapplyValueSchemeOnInvoice() {
    if (!this.ValueSchemeExist || !this.valueSchemFinalId) return;

    // Guard against re-entrant loops: this method's own success path calls
    // handlePriceCalculations() again to push the recalculated discount into the
    // totals, which would otherwise re-enter this same method. Skip the Apex
    // round-trip when neither the applied scheme nor the cart total has actually
    // changed since the last check.
    const reapplyKey = this.valueSchemFinalId + '|' + this.grossCartTotal;
    if (this._lastReappliedInvoiceValueSchemeKey === reapplyKey) return;
    this._lastReappliedInvoiceValueSchemeKey = reapplyKey;

    getAppliedValueSchemeForOrder({
      valueSchemId: this.valueSchemFinalId,
      orderId: this.order?.Id,
      cartTotal: this.grossCartTotal || this.invoiceInfo?.Taxable_Amount__c,
      cartLinesJson: JSON.stringify(this.buildCartLinesForInvoice())
    }).
    then((result) => {
      const hasDiscountAmount = result.discountAmount != null;
      const hasDiscountPercentage = result.discountPercentage != null;

      if (!hasDiscountAmount && !hasDiscountPercentage) {
        // No Scheme_Slab__c qualifies at the new cart total (dropped below the
        // scheme's lowest tier) — remove the scheme entirely, same as
        // removeInvalidValueSchemeFromInvoice() does for the below-minimum case.
        this.itemList = this.itemList.filter(
          (item) => !(item.isPromotional && item.promoType === 'VALUE')
        );
        this.clearValueScheme();
        this.itemList.forEach((r, i) => r.rowNo = i + 1);
        this.itemList = [...this.itemList];

        this.dispatchEvent(
          showToast('Info', 'Value scheme removed as cart total is below threshold', [], 'info', '')
        );
        return;
      }

      this.valueSchemeThreshold = result.cartAmount;
      localStorage.setItem('valueSchemeThreshold', this.valueSchemeThreshold);
      this.valueSchemeQualifyingSubtotal = result.qualifyingSubtotal != null ?
      result.qualifyingSubtotal : null;

      if (hasDiscountAmount) {
        this.discountAmountGiven = result.discountAmount;
        this.discountAmountGivenCheck = true;
        this.discountPercemtageGiven = 0;
        this.discountPercemtageGivenCheck = false;
      } else {
        this.discountPercemtageGiven = result.discountPercentage;
        this.discountPercemtageGivenCheck = true;
        this.discountAmountGiven = 0;
        this.discountAmountGivenCheck = false;
      }

      this.skipValueSchemeValidationOnce = true;
      this.recalculateDiscountTotals();
      this.handlePriceCalculations();
    }).
    catch((error) => {
      console.error('Error in reapplyValueSchemeOnInvoice:', error);
    });
  }

  clearExistingValueSchemeFromInvoice() {
    this.itemList = this.itemList.filter(
      (row) => !(row.isPromotional && row.promoType === 'VALUE')
    );

    this.discountAmountGiven = 0;
    this.discountPercemtageGiven = 0;
    this.discountAmountGivenCheck = false;
    this.discountPercemtageGivenCheck = false;
    this.invoiceInfo.Value_Scheme_Applied__c = null;
    this.invoiceInfo.Value_Scheme_Discount__c = 0;

    this.itemList.forEach((r, i) => r.rowNo = i + 1);
    this.itemList = [...this.itemList];
  }

  clearValueScheme() {
    this.ValueSchemeExist = false;
    this.ValueSchemeFinalName = '';
    this.valueSchemFinalId = '';
    this.valueSchemeThreshold = null;
    this.valueSchemeQualifyingSubtotal = null;

    this.discountAmountGiven = 0;
    this.discountPercemtageGiven = 0;
    this.discountAmountGivenCheck = false;
    this.discountPercemtageGivenCheck = false;

    this.invoiceInfo.Value_Scheme_Applied__c = null;
    this.invoiceInfo.Value_Scheme_Discount__c = 0;



    localStorage.removeItem('valueSchemFinalId');
    localStorage.removeItem('valueSchemeThreshold');
  }

  removeInvalidValueSchemeFromInvoice() {
    const hasValuePromo = this.itemList.some(
      (item) => item.isPromotional && item.promoType === 'VALUE'
    );









    if (this.skipValueSchemeValidationOnce) {
      this.skipValueSchemeValidationOnce = false;
      return;
    }

    if (this.ValueSchemeExist && !hasValuePromo) {
      this.clearValueScheme();
      return;
    }

    if (!this.ValueSchemeExist) return;
    if (this.valueSchemeThreshold == null) return;

    if (this.grossCartTotal < this.valueSchemeThreshold) {
      this.itemList = this.itemList.filter(
        (item) => !(item.isPromotional && item.promoType === 'VALUE')
      );

      this.clearValueScheme();

      this.itemList.forEach((r, i) => r.rowNo = i + 1);
      this.itemList = [...this.itemList];

      this.recalculateDiscountTotals();
      this.handlePriceCalculations();

      this.dispatchEvent(
        showToast(
          'Info',
          'Value scheme removed as cart total is below threshold',
          [],
          'info',
          ''
        )
      );
    }
  }

  getProductStockUsageMap() {
    const usageMap = new Map();

    this.itemList.forEach((item) => {
      const pid = item.Product__c;
      const qty = Number(item.Quantity__c) || 0;

      if (!usageMap.has(pid)) {
        usageMap.set(pid, {
          used: 0,
          stock: Number(item.CurrentStock) || 0
        });
      }

      usageMap.get(pid).used += qty;
    });

    return usageMap;
  }

  applyStockValidationUI() {
    const stockMap = this.getProductStockUsageMap();

    this.itemList = this.itemList.map((item) => {
      const stockInfo = stockMap.get(item.Product__c);
      const isOver = stockInfo.used > stockInfo.stock;

      return {
        ...item,
        quantityCellClass: isOver ?
        'background-color: #fff8c4; color: #7a6600;' :
        ''
      };
    });
  }


  reapplyQuantitySchemeFromInvoice(baseProductId) {
    const baseRow = this.itemList.find(
      (r) => !r.isPromotional && r.Product__c === baseProductId
    );

    if (!baseRow || !baseRow.selectedSchemeId) return;

    const normalizedItems = this.itemList.
    filter((r) => !r.isPromotional).
    map((row) => ({
      productId: row.Product__c,
      quantity: row.Quantity__c,
      productOfferPrice: row.Price__c,
      productName: row.ProductName,
      productFullName: row.ProductName,
      availableStockQuantity: row.CurrentStock || 0,
      productBrand: '',
      prodmeasure: '',
      hsn: INVOICE_HSN_LABEL,
      mrp: row.MRP__c
    }));

    applyQuantitySchemeFromOrder({
      cartItems: normalizedItems,
      orderId: this.order.Id,
      selectedSchemeId: baseRow.selectedSchemeId
    }).
    then((promoLines) => {
      let cleaned = this.itemList.filter(
        (r) => !(r.isPromotional && r.parentProductId === baseProductId)
      );

      const baseIndex = cleaned.findIndex(
        (r) => r.Product__c === baseProductId && !r.isPromotional
      );

      promoLines.forEach((promo, idx) => {

        const isFree =
        promo.discountPercentage === null ||
        promo.discountPercentage === 100 ||
        promo.unittotalPrice === 0;

        let totalAmount = 0;
        let discountAmt = 0;

        if (!isFree) {
          const gross = promo.productListPrice * promo.quantity;
          totalAmount = gross;
          discountAmt = gross - (promo.unittotalPrice || 0);
        }

        cleaned.splice(baseIndex + 1 + idx, 0, {
          Product__c: promo.productId,
          Parent_Product__c: baseProductId,
          ProductName: `🎁 ${promo.productName}`,
          Quantity__c: promo.quantity,
          Price__c: promo.productListPrice,
          mrp: promo.mrp,
          Total_Amount__c: totalAmount,
          discount1Amt: this.roundNum(discountAmt),
          discount2Amt: 0,
          hsn: promo.hsn || '',
          CurrentStock: promo.availableStockQuantity || 0,
          isPromotional: true,
          parentProductId: baseProductId,
          selectedSchemeId: baseRow.selectedSchemeId,
          isReadOnly: true,
          promoMinQty: promo.promoMinQty,
          isFreePromo: isFree
        });
      });

      cleaned = this.recalculatePromoLocks(cleaned);
      cleaned.forEach((r, i) => r.rowNo = i + 1);
      this.itemList = [...cleaned];

      this.recalculateDiscountTotals();
      this.handlePriceCalculations();
    });
  }
}