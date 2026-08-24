import { LightningElement, api, track } from 'lwc';
import loadInvoiceData from '@salesforce/apex/CounterInvoiceController.loadInvoiceData';
import createCounterInvoice from '@salesforce/apex/CounterInvoiceController.createCounterInvoice';
import saveInvoice from '@salesforce/apex/CounterInvoiceController.saveInvoice';
import getProductsWithStock from '@salesforce/apex/CounterInvoiceController.getProductsWithStock';
import getPriceForProduct from '@salesforce/apex/CounterInvoiceController.getPriceForProduct';
import getFreeOfferMessageForProducts from '@salesforce/apex/ModernTradeSchemeService.getFreeOfferMessageForProducts';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class CounterInvoiceEdit extends NavigationMixin(LightningElement) {

    @api orderId;
    @api priceType = 'MRP';

    @track isLoading       = false;
    @track isSaving        = false;
    @track isProductSaving = false;
    @track showModal       = false;

    @track dmsUserInfo  = {};
    @track invoiceInfo  = {};
    @track orderInfo    = {};
    @track itemList     = [];
    @track deletedIds   = [];

    @track totalDiscount = 0;
    @track roundOff      = 0;
    @track discount2Percent = 0;
    @track freeOfferMessage = null;

    // modal state
    @track iliEdit          = false;
    @track iliQuantity;
    @track iliPrice;
    @track iliDiscountInput = 0;
    @track iliDiscountType  = 'Value';
    @track iliSkuDiscountPercent = 0;
    @track iliStockInHand;
    @track iliProduct;
    @track iliMrp           = 0;
    @track rowIndex;
    @track rowAction;
    @track selectedProduct  = null;
    @track searchQuery      = '';
    @track productResults   = [];
    @track showDropdown     = false;
    searchDebounce;

    disAccountName    = '';
    disBillingAddress = '';
    dmsuserPhone      = '';
    dmsuserFSSAI      = '';
    invoiceId         = '';

    get isDraft()     { return this.invoiceInfo.Status__c === 'Draft'; }
    get skuDiscountActive() {
    return (this.itemList || []).some((i) => Number(i.SKU_Discount_Percent__c) > 0);
}

get overallDiscountActive() {
    return Number(this.discount2Percent) > 0;
}
    get isConfirmed() { return this.invoiceInfo.Status__c === 'Confirmed'; }
    get modalTitle()  { return this.iliEdit ? 'Edit Line Item' : 'Add Line Item'; }
    get isDiscountValue()      { return this.iliDiscountType === 'Value'; }
    get isDiscountPercentage() { return this.iliDiscountType === 'Percentage'; }

    get calculatedDiscountAmt() {
        const qty   = parseFloat(this.iliQuantity) || 0;
        const price = parseFloat(this.iliPrice)    || 0;
        const input = parseFloat(this.iliDiscountInput) || 0;
        const gross = qty * price;
        if (this.iliDiscountType === 'Percentage') {
            return parseFloat(((gross * input) / 100).toFixed(2));
        }
        return parseFloat(input.toFixed(2));
    }

    columns = [
        { label: '#',             fieldName: 'rowNo',           type: 'text', initialWidth: 40 },
        { label: 'Item Description', fieldName: 'ProductName',  type: 'text', wrapText: true },
        { label: 'HSN',           fieldName: 'hsn',             type: 'text', initialWidth: 100 },
        { label: 'Stock In Hand', fieldName: 'CurrentStock',    type: 'text', initialWidth: 100 },
        { label: 'Quantity',      fieldName: 'Quantity__c',     type: 'text', initialWidth: 80 },
        { label: 'MRP',           fieldName: 'mrp',             type: 'text', initialWidth: 80 },
        { label: 'Rate',          fieldName: 'Price__c',        type: 'text', initialWidth: 80 },
        { label: 'Amount',        fieldName: 'Total_Amount__c', type: 'text', initialWidth: 90 },
        { label: 'Discount (₹)', fieldName: 'discountAmt',     type: 'text', initialWidth: 100 },
        { label: 'Discount 2 (₹)', fieldName: 'discount2Amt',  type: 'text', initialWidth: 100 },
        { label: 'Net Amount',    fieldName: 'netAmount',       type: 'text', initialWidth: 100 },
        { type: 'button-icon', typeAttributes: { iconName: 'utility:edit',   name: 'edit'   }, fixedWidth: 40 },
        { type: 'button-icon', typeAttributes: { iconName: 'utility:add',    name: 'add'    }, fixedWidth: 40 },
        { type: 'button-icon', typeAttributes: { iconName: 'utility:delete', name: 'delete', iconClass: 'slds-icon-text-error' }, fixedWidth: 40 }
    ];

    connectedCallback() {
        this.isLoading = true;
        createCounterInvoice({ orderId: this.orderId })
            .then(result => {
                if (result.status === 'Success') {
                    this.invoiceId = result.invoiceId;
                    return loadInvoiceData({ invoiceId: this.invoiceId });
                }
                throw new Error('Failed to create invoice');
            })
            .then(data => {
                if (data.message !== 'Success') {
                    this.showToast('Error', data.message, 'error');
                    return;
                }
                this.buildFromData(data);
            })
            .catch(err => {
                this.showToast('Error', err.body ? err.body.message : err.message, 'error');
            })
            .finally(() => { this.isLoading = false; });
    }

    buildFromData(data) {
        this.dmsUserInfo = data.dmsUser || {};
        this.invoiceInfo = { ...data.invoice };
        this.orderInfo   = data.order || {};

        // Price Type is set once on the Order at creation time (CounterInvoiceController
        // .createCounterOrder()) and never exposed to this component otherwise — @api
        // priceType has no App Builder / URL-parameter binding, so without this it always
        // stayed at its 'MRP' default even when the order was placed as Dealer Price.
        this.priceType = this.orderInfo?.Price_Type__c || this.priceType || 'MRP';

        // CRITICAL: loadInvoiceData()'s Apex query never selects Price_Type__c on the
        // Invoice__c record, so `this.invoiceInfo` (spread from data.invoice above) never
        // carried it — meaning every saveInvoice() call sent Price_Type__c as undefined,
        // and the server-side "isMrp" check in CounterInvoiceController.saveInvoice() always
        // evaluated false, regardless of the actual price type. This is why MRP invoices
        // kept showing real GST even after the server-side zero-GST logic was deployed.
        // The Order's Price Type (already resolved into this.priceType just above) is the
        // authoritative source, so thread it into invoiceInfo explicitly here.
        this.invoiceInfo = { ...this.invoiceInfo, Price_Type__c: this.priceType };

        const acct = this.dmsUserInfo?.Contact?.Account;
        this.disAccountName   = acct?.Name || '';
        this.dmsuserPhone     = acct?.Phone_1__c || '';
        this.dmsuserFSSAI     = acct?.FSSAI__c || '';
        this.disBillingAddress = [
            acct?.BillingStreet, acct?.BillingCity,
            acct?.BillingState, acct?.BillingPostalCode, acct?.BillingCountry
        ].filter(Boolean).join(', ');

        const stockMap = data.stockMap || {};
        this.itemList = (data.lineItems || []).map((li, idx) => ({
            ...li,
            rowNo:        idx + 1,
            hsn:          '21050000',
            mrp:          li.MRP__c || 0,
            ProductName:  li.Product__r?.Name || '',
            CurrentStock: stockMap[li.Product__c] || 0,
            discountAmt:  li.Discount_1__c || 0,
            discount2Amt: li.Discount_2__c || 0,
            SKU_Discount_Percent__c: li.SKU_Discount_Percent__c || 0,
            discountType: 'Value',
            netAmount:    ((li.Quantity__c * li.Price__c) - (li.Discount_1__c || 0) - (li.Discount_2__c || 0)).toFixed(2)
        }));

        this.recalculateTotals();
    }

    recalculateTotals() {
        let totalQty     = 0;
        let taxableValue = 0;
        let totalDisc    = 0;

        const dis2Pct = parseFloat(this.discount2Percent) || 0;

        this.itemList.forEach(item => {
            const qty       = parseFloat(item.Quantity__c)  || 0;
            const price     = parseFloat(item.Price__c)     || 0;
            const discount  = parseFloat(item.discountAmt)  || 0;
            const gross     = qty * price;

            // Discount 2 is a single invoice-wide percentage, applied line-by-line against
            // each line's own gross amount — same pattern as secondaryInvoice.js/
            // editSecondaryInvoice.js — so it scales per line instead of being a flat,
            // invoice-level lump sum that ignores line composition.
            const skuPct    = parseFloat(item.SKU_Discount_Percent__c) || 0;
            const effPct    = skuPct > 0 ? skuPct : dis2Pct;
            const discount2 = Math.round((gross * dis2Pct / 100) * 100) / 100;
            item.discount2Amt = discount2;

            const net = gross - discount - discount2;
            totalQty      += qty;
            taxableValue  += net;
            totalDisc     += discount + discount2;
            item.Total_Amount__c = parseFloat(gross.toFixed(2));
            item.netAmount       = parseFloat(net.toFixed(2));
        });

        this.itemList      = [...this.itemList];
        this.totalDiscount = parseFloat(totalDisc.toFixed(2));

        // Legal requirement: MRP is tax-inclusive under Indian Legal Metrology rules — the
        // displayed MRP already contains GST, so no GST is shown/charged separately when
        // the distributor has selected Price Type = MRP. Only apply GST for non-MRP price
        // types (e.g. Dealer Price).
        const isMrp   = this.priceType === 'MRP';
        const cgstPct = isMrp ? 0 : (parseFloat(this.invoiceInfo.CGST__c) || 0);
        const sgstPct = isMrp ? 0 : (parseFloat(this.invoiceInfo.SGST__c) || 0);
        const igstPct = isMrp ? 0 : (parseFloat(this.invoiceInfo.IGST__c) || 0);

        const cgstAmt  = (taxableValue * cgstPct) / 100;
        const sgstAmt  = (taxableValue * sgstPct) / 100;
        const igstAmt  = (taxableValue * igstPct) / 100;
        const totalGST = cgstAmt + sgstAmt + igstAmt;
        const rawTotal = taxableValue + totalGST;
        const rounded  = Math.round(rawTotal);

        this.roundOff = parseFloat((rounded - rawTotal).toFixed(2));

        this.invoiceInfo = {
            ...this.invoiceInfo,
            Total_Quantity__c:          totalQty,
            Taxable_Amount__c:          parseFloat(taxableValue.toFixed(2)),
            CGST_Amount__c:             parseFloat(cgstAmt.toFixed(2)),
            SGST_Amount__c:             parseFloat(sgstAmt.toFixed(2)),
            IGST_Amount__c:             parseFloat(igstAmt.toFixed(2)),
            Total_GST__c:               parseFloat(totalGST.toFixed(2)),
            Invoice_Amount__c:          rounded,
            Invoice_Amount_In_Words__c: this.amountToWords(rounded)
        };

        this.refreshFreeOfferMessage();
    }

    // Modern Trade free-goods scheme — recomputed any time the cart changes (load, add,
    // edit, delete line item) so it always reflects the current summed quantity of
    // qualifying products, not just a stale snapshot from when the invoice was opened.
    refreshFreeOfferMessage() {
        const productQty = this.itemList
            .filter(i => i.Product__c)
            .map(i => ({ productId: i.Product__c, quantity: parseFloat(i.Quantity__c) || 0 }));

        if (productQty.length === 0) {
            this.freeOfferMessage = null;
            return;
        }

        getFreeOfferMessageForProducts({ productQtyJson: JSON.stringify(productQty) })
            .then(message => { this.freeOfferMessage = message || null; })
            .catch(() => { this.freeOfferMessage = null; });
    }

    handleRowAction(event) {
        const action = event.detail.action.name;
        const row    = event.detail.row;

        if (action === 'edit') {
            this.rowIndex         = row.rowNo;
            this.rowAction        = 'edit';
            this.iliEdit          = true;
            this.iliProduct       = row.Product__c;
            this.iliQuantity      = row.Quantity__c;
            this.iliPrice         = row.Price__c;
            this.iliDiscountType  = row.discountType || 'Value';
            this.iliDiscountInput = row.discountAmt  || 0;
            this.iliSkuDiscountPercent = row.SKU_Discount_Percent__c || 0;
            this.iliStockInHand   = row.CurrentStock;
            this.iliMrp           = row.mrp || 0;
            this.selectedProduct  = { Id: row.Product__c, Name: row.ProductName };
            this.showModal        = true;

        } else if (action === 'add') {
            this.rowIndex         = row.rowNo;
            this.rowAction        = 'add';
            this.iliEdit          = false;
            this.iliProduct       = '';
            this.iliQuantity      = '';
            this.iliPrice         = '';
            this.iliDiscountType  = 'Value';
            this.iliDiscountInput = 0;
            this.iliStockInHand   = '';
            this.iliMrp           = 0;
            this.iliSkuDiscountPercent = 0;
            this.selectedProduct  = null;
            this.searchQuery      = '';
            this.showModal        = true;

        } else if (action === 'delete') {
            if (this.itemList.length === 1) {
                this.showToast('Info', 'At least one line item is required.', 'info'); return;
            }
            const item = this.itemList.find(i => i.rowNo === row.rowNo);
            if (item?.Id) this.deletedIds.push(item.Id);
            this.itemList = this.itemList
                .filter(i => i.rowNo !== row.rowNo)
                .map((i, idx) => ({ ...i, rowNo: idx + 1 }));
            this.recalculateTotals();
        }
    }

    handleDiscountTypeChange(event) {
        this.iliDiscountType  = event.target.value;
        this.iliDiscountInput = 0;
    }

    handleDiscountInputChange(event) {
        this.iliDiscountInput = parseFloat(event.target.value) || 0;
    }

    handleSearchChange(event) {
        this.searchQuery = event.target.value;
        clearTimeout(this.searchDebounce);
        if (!this.searchQuery || this.searchQuery.length < 2) {
            this.productResults = []; this.showDropdown = false; return;
        }
        this.searchDebounce = setTimeout(() => {
            getProductsWithStock({ searchKey: this.searchQuery })
                .then(res => {
                    this.productResults = res || [];
                    this.showDropdown   = this.productResults.length > 0;
                }).catch(() => { this.productResults = []; this.showDropdown = false; });
        }, 300);
    }

    handleSearchFocus() {
        if (this.productResults.length > 0) this.showDropdown = true;
    }

    handleSelectProduct(event) {
        const pid = event.currentTarget.dataset.id;
        const sel = this.productResults.find(p => p.Id === pid);
        if (!sel) return;
        this.selectedProduct = sel;
        this.searchQuery     = sel.Name;
        this.showDropdown    = false;
        this.iliProduct      = sel.Id;
        this.iliStockInHand  = sel.Stock || 0;
        getPriceForProduct({ productId: sel.Id, priceType: this.priceType })
            .then(res => {
                this.iliPrice = res.price || 0;
                this.iliMrp   = res.mrp   || 0;
            }).catch(() => {});
    }

    clearProductSelection() {
        this.selectedProduct  = null;
        this.searchQuery      = '';
        this.productResults   = [];
        this.showDropdown     = false;
        this.iliProduct       = '';
        this.iliPrice         = '';
        this.iliDiscountInput = 0;
        this.iliDiscountType  = 'Value';
        this.iliStockInHand   = '';
        this.iliMrp           = 0;
    }

    handleQtyChange(event) {
        this.iliQuantity = parseInt(event.target.value) || 0;
    }

    async handleModalSave() {
        if (this.isProductSaving) return;
        this.isProductSaving = true;

        const qtyEl = this.template.querySelector('lightning-input-field[data-id="ili_quantity"]');
        // Always read fresh from the field, fallback to tracked value
        const rawQty = qtyEl ? qtyEl.value : this.iliQuantity;
        const qty    = parseInt(rawQty) || 0;
        const price = parseFloat(this.iliPrice);
        const gross = qty * price;

        let discountAmt = 0;
        if (this.iliDiscountType === 'Percentage') {
            const pct = parseFloat(this.iliDiscountInput) || 0;
            if (pct < 0 || pct > 100) {
                this.showToast('Error', 'Percentage must be between 0 and 100.', 'error');
                this.isProductSaving = false; return;
            }
            discountAmt = parseFloat(((gross * pct) / 100).toFixed(2));
        } else {
            discountAmt = parseFloat(this.iliDiscountInput) || 0;
        }
        const skuPct = parseFloat(this.iliSkuDiscountPercent) || 0;
        if (skuPct < 0 || skuPct > 100) {
            this.showToast('Error', 'SKU Discount % must be between 0 and 100.', 'error');
            this.isProductSaving = false; return;
        }
        if (skuPct > 0 && Number(this.discount2Percent) > 0) {
            this.showToast('Error', 'Overall Discount and SKU-wise Discount cannot be applied together. Please clear one before saving.', 'error');
            this.isProductSaving = false; return;
        }

        if (!this.iliProduct) {
            this.showToast('Error', 'Please select a product.', 'error');
            this.isProductSaving = false; return;
        }
        if (!qty || qty <= 0) {
            this.showToast('Error', 'Quantity must be greater than 0.', 'error');
            this.isProductSaving = false; return;
        }
        if (!price || price <= 0) {
            this.showToast('Error', 'Price must be greater than 0.', 'error');
            this.isProductSaving = false; return;
        }
        if (discountAmt > gross) {
            this.showToast('Error', 'Discount cannot exceed line item amount (' + gross.toFixed(2) + ').', 'error');
            this.isProductSaving = false; return;
        }

        const productName = this.selectedProduct?.Name || '';

        if (this.rowAction === 'add') {
            const duplicate = this.itemList.find(i => i.Product__c === this.iliProduct);
            if (duplicate) {
                this.showToast('Error', productName + ' already exists at line #' + duplicate.rowNo + '.', 'error');
                this.isProductSaving = false; return;
            }
            const newItem = {
                Product__c:      this.iliProduct,
                ProductName:     productName,
                Quantity__c:     qty,
                Price__c:        price,
                mrp:             this.iliMrp || 0,
                Total_Amount__c: gross,
                discountAmt:     discountAmt,
                discountType:    this.iliDiscountType,
                 SKU_Discount_Percent__c: skuPct,
                netAmount:       parseFloat((gross - discountAmt).toFixed(2)),
                CurrentStock:    this.iliStockInHand || 0,
                hsn:             '21050000',
                rowNo:           this.rowIndex
            };
            this.itemList.splice(this.rowIndex, 0, newItem);
            this.itemList.forEach((i, idx) => i.rowNo = idx + 1);
        } else {
            this.itemList = this.itemList.map((i, idx) => {
                if (idx + 1 === this.rowIndex) {
                    return {
                        ...i,
                        Quantity__c:     qty,
                        Price__c:        price,
                        Total_Amount__c: gross,
                        discountAmt:     discountAmt,
                        discountType:    this.iliDiscountType,
                        SKU_Discount_Percent__c: skuPct,
                        netAmount:       parseFloat((gross - discountAmt).toFixed(2))
                    };
                }
                return i;
            });
        }

        this.itemList = [...this.itemList];
        this.recalculateTotals();
        this.showModal       = false;
        this.isProductSaving = false;
    }

    handleSkuDiscountChange(event) {
        this.iliSkuDiscountPercent = parseFloat(event.target.value) || 0;
    }
    handleModalCancel() { this.showModal = false; }

    handleInvoiceDateChange(event) {
        const selectedDate = event.target.value;
        // Validate: invoice date cannot be earlier than order date
        if (this.orderInfo && this.orderInfo.CreatedDate__c && selectedDate < this.orderInfo.CreatedDate__c) {
            this.showToast('Error', 'Invoice Date cannot be earlier than the Order Date.', 'error');
            return;
        }
        this.invoiceInfo = { ...this.invoiceInfo, Invoice_Date__c: selectedDate };
    }

    handleCreditPeriodChange(event) {
        this.invoiceInfo = { ...this.invoiceInfo, Credit_Period__c: event.target.value };
    }

    // Save draft and stay on page
    handleSave() {
        this.isSaving = true;
        const lineItems = this.buildLineItemsForSave();
        saveInvoice({
            invoice:    this.invoiceInfo,
            lineItems:  lineItems,
            deletedIds: this.deletedIds
        }).then(() => {
            this.showToast('Success', 'Invoice saved successfully.', 'success');
            this.deletedIds = [];
        }).catch(err => {
            this.showToast('Error', err.body ? err.body.message : 'Error saving invoice.', 'error');
        }).finally(() => { this.isSaving = false; });
    }

    // Save and navigate to record page for user to confirm via standard path
    handleConfirm() {
        this.isSaving = true;
        const lineItems = this.buildLineItemsForSave();
        saveInvoice({
            invoice:    this.invoiceInfo,
            lineItems:  lineItems,
            deletedIds: this.deletedIds
        }).then(() => {
            this.showToast('Success', 'Invoice saved. Please confirm using the status path on the record page.', 'success');
            this.deletedIds = [];
            // Navigate to record page where user can confirm via standard path
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.invoiceId,
                    objectApiName: 'Invoice__c',
                    actionName: 'view'
                }
            });
        }).catch(err => {
            this.showToast('Error', err.body ? err.body.message : 'Error saving invoice.', 'error');
        }).finally(() => { this.isSaving = false; });
    }

    handleDownload() {
        // Open counter invoice PDF
        const baseUrl = window.location.origin;
        window.open(baseUrl + '/apex/CounterInvoicePdf?id=' + this.invoiceId);
    }


    handleBack() { window.history.back(); }

    buildLineItemsForSave() {
        return this.itemList.map(i => ({
            Id:             i.Id,
            Invoice__c:     this.invoiceId,
            Product__c:     i.Product__c,
            Quantity__c:    i.Quantity__c,
            Price__c:       i.Price__c,
            Total_Amount__c: i.Total_Amount__c,
            MRP__c:         i.mrp || i.MRP__c || 0,
            Discount_1__c:  i.discountAmt || 0,
            Discount_2__c:  i.discount2Amt || 0,
            SKU_Discount_Percent__c: i.SKU_Discount_Percent__c || 0
        }));
    }

    amountToWords(amount) {
        if (!amount || amount === 0) return 'Zero Only';
        const units = ['','One','Two','Three','Four','Five','Six','Seven','Eight','Nine','Ten',
                       'Eleven','Twelve','Thirteen','Fourteen','Fifteen','Sixteen','Seventeen','Eighteen','Nineteen'];
        const tens  = ['','','Twenty','Thirty','Forty','Fifty','Sixty','Seventy','Eighty','Ninety'];
        function convert(n) {
            if (n < 20)     return units[Math.trunc(n)] + ' ';
            if (n < 100)    return tens[Math.trunc(n/10)] + (n%10>0?' '+convert(n%10):'') + ' ';
            if (n < 1000)   return units[Math.trunc(n/100)] + ' Hundred ' + (n%100>0?convert(n%100):'');
            if (n < 100000) return convert(n/1000) + ' Thousand ' + (n%1000>0?convert(n%1000):'');
            if (n < 10000000) return convert(n/100000) + ' Lakh ' + (n%100000>0?convert(n%100000):'');
            return convert(n/10000000) + ' Crore ' + (n%10000000>0?convert(n%10000000):'');
        }
        return convert(amount).trim() + ' Only';
    }

    handleDiscount2Change(event) {
        this.discount2Percent = parseFloat(event.target.value) || 0;
        this.recalculateTotals();
    }

    handleValueScheme() {
        this.showToast('Info', 'Value Scheme not applicable for Counter Invoices.', 'info');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}