/**
 * dmsCartStore - per-user, Salesforce-backed replacement for localStorage, used by the
 * DMS order screens (productListingComponentPortal, createSecondaryOrderComponentDms,
 * createUnderSsOrderDMS). Same getItem / setItem / removeItem API as localStorage.
 *
 * - Every key is prefixed with the logged-in user's Id, so users sharing a browser
 *   never see each other's cart, scheme, discount or comment.
 * - Only the values that change are sent to Salesforce and merged into the user's saved
 *   cart (DMS_Cart__c), so a browser or device holding an older copy can never wipe a
 *   newer cart saved from somewhere else.
 * - init() saves any pending change and reloads the saved cart every time an order
 *   screen opens, so every screen starts from the latest cart on any browser or device.
 * - Pending changes are also saved when the page is hidden or closed.
 * - If Salesforce cannot be reached, the screens keep working with this browser's copy.
 */
import USER_ID from '@salesforce/user/Id';
import getCartState from '@salesforce/apex/DmsCartController.getCartState';
import saveCartChanges from '@salesforce/apex/DmsCartController.saveCartChanges';

const PREFIX = 'dmsCart_' + USER_ID + '_';
const SAVE_DELAY_MS = 300;

let pendingSet = {};
let pendingRemove = {};
let hasPending = false;
let saveTimer;
let saveChain = Promise.resolve();
let loadChain = Promise.resolve();
let leaveHandlersAdded = false;

function userKeys() {
    const keys = [];
    for (let i = 0; i < localStorage.length; i++) {
        const k = localStorage.key(i);
        if (k && k.startsWith(PREFIX)) {
            keys.push(k);
        }
    }
    return keys;
}

function markSet(key, value) {
    pendingSet[key] = value;
    delete pendingRemove[key];
    hasPending = true;
}

function markRemove(key) {
    pendingRemove[key] = true;
    delete pendingSet[key];
    hasPending = true;
}

function flush() {
    if (saveTimer) {
        clearTimeout(saveTimer);
        saveTimer = undefined;
    }
    if (!hasPending) {
        return saveChain;
    }
    const changes = { set: pendingSet, remove: Object.keys(pendingRemove) };
    pendingSet = {};
    pendingRemove = {};
    hasPending = false;
    // Saves run one after another, in the order the changes were made.
    saveChain = saveChain
        .then(() => saveCartChanges({ changesJson: JSON.stringify(changes) }))
        .catch((error) => {
            console.error('dmsCartStore: saving cart changes to Salesforce failed', error);
            // Keep the failed changes so the next save retries them (newer changes win).
            Object.keys(changes.set).forEach((k) => {
                if (!(k in pendingSet) && !(k in pendingRemove)) {
                    pendingSet[k] = changes.set[k];
                    hasPending = true;
                }
            });
            changes.remove.forEach((k) => {
                if (!(k in pendingSet) && !(k in pendingRemove)) {
                    pendingRemove[k] = true;
                    hasPending = true;
                }
            });
        });
    return saveChain;
}

function scheduleSave() {
    if (saveTimer) {
        clearTimeout(saveTimer);
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    saveTimer = setTimeout(flush, SAVE_DELAY_MS);
}

function addLeaveHandlers() {
    if (leaveHandlersAdded) {
        return;
    }
    leaveHandlersAdded = true;
    window.addEventListener('pagehide', () => flush());
    document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'hidden') {
            flush();
        }
    });
}

function applySavedState(stateJson) {
    if (!stateJson) {
        // Nothing saved yet: keep this user's browser copy and save it.
        const keys = userKeys();
        if (keys.length > 0) {
            keys.forEach((k) => markSet(k.substring(PREFIX.length), localStorage.getItem(k)));
            scheduleSave();
        }
        return;
    }
    // The saved cart replaces this user's browser copy...
    const state = JSON.parse(stateJson);
    userKeys().forEach((k) => localStorage.removeItem(k));
    Object.keys(state).forEach((k) => {
        if (state[k] !== null && state[k] !== undefined) {
            localStorage.setItem(PREFIX + k, state[k]);
        }
    });
    // ...except changes made here that are not saved yet.
    Object.keys(pendingSet).forEach((k) => localStorage.setItem(PREFIX + k, pendingSet[k]));
    Object.keys(pendingRemove).forEach((k) => localStorage.removeItem(PREFIX + k));
}

const cartStore = {
    init() {
        addLeaveHandlers();
        loadChain = loadChain
            .then(() => flush())
            .then(() => getCartState())
            .then((stateJson) => applySavedState(stateJson))
            .catch((error) => {
                console.error('dmsCartStore: loading saved cart failed; using this browser copy', error);
            });
        return loadChain;
    },
    getItem(key) {
        return localStorage.getItem(PREFIX + key);
    },
    setItem(key, value) {
        localStorage.setItem(PREFIX + key, value);
        markSet(key, localStorage.getItem(PREFIX + key));
        scheduleSave();
    },
    removeItem(key) {
        localStorage.removeItem(PREFIX + key);
        markRemove(key);
        scheduleSave();
    }
};

// DMS cart: each order screen gets its own storage area (cart, buyer, scheme, discount, comment),
// so Primary, Retailer Secondary and Under SS never clear or pick up each other's values.
// Secondary and Under SS also keep a separate cart per retailer/distributor (setBuyer).
export function screenStore(scope) {
    const base = scope + ':';
    let p = base;
    return {
        init: () => cartStore.init(),
        setBuyer: (buyerId) => {
            p = buyerId ? base + buyerId + ':' : base;
            if (buyerId) {
                moveLegacyCart(base, p, buyerId);
            }
        },
        getItem: (key) => cartStore.getItem(p + key),
        setItem: (key, value) => cartStore.setItem(p + key, value),
        removeItem: (key) => cartStore.removeItem(p + key)
    };
}

// One-time move: a cart saved before per-buyer carts existed (directly in the screen's area)
// is moved into its own buyer's area the first time that buyer is opened.
function moveLegacyCart(base, buyerPrefix, buyerId) {
    if (cartStore.getItem(base + 'secondaryCartRetailer') !== buyerId) {
        return;
    }
    if (cartStore.getItem(buyerPrefix + 'secondaryCart')) {
        return;
    }
    userKeys().forEach((k) => {
        const rest = k.substring(PREFIX.length);
        if (rest.startsWith(base) && rest.indexOf(':', base.length) === -1) {
            cartStore.setItem(buyerPrefix + rest.substring(base.length), localStorage.getItem(k));
            cartStore.removeItem(rest);
        }
    });
}
export default cartStore;