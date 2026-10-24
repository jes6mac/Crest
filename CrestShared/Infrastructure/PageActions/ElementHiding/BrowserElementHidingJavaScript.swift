import Foundation

enum BrowserElementHidingJavaScript {
    // MARK: - Static Variables

    static let source = #"""
        (() => {
            if (globalThis.__crestElementHiding) return;
            const identityBytes = crypto.getRandomValues(new Uint8Array(16));
            identityBytes[6] = (identityBytes[6] & 15) | 64;
            identityBytes[8] = (identityBytes[8] & 63) | 128;
            const identityHex = [...identityBytes].map(value => value.toString(16).padStart(2,'0')).join('');
            const documentID = [identityHex.slice(0,8),identityHex.slice(8,12),identityHex.slice(12,16),identityHex.slice(16,20),identityHex.slice(20)].join('-');
            const hidden = new Map();
            const protectedTags = new Set(['HTML', 'BODY', 'HEAD', 'SCRIPT', 'STYLE', 'LINK', 'META', 'NOSCRIPT']);
            const labelFor = node => (node.getAttribute('aria-label') || node.getAttribute('title') || node.textContent || node.tagName)
                .replace(/\s+/g,' ').trim().slice(0,80);
            let rules = [], revision = -1, timer = null, suspended = false;
            let overlay = null, selection = null, selectionToken = null, previews = [], geometryFrame = null;
            let touchStart = null, touchMoved = false;
            const post = (kind, fields = {}) => {
                globalThis.webkit?.messageHandlers?.crestElementHiding?.postMessage(
                    JSON.stringify({kind, documentID, ...fields}));
            };
            const roots = () => {
                const found = [document];
                for (let index = 0; index < found.length; index++) {
                    for (const node of found[index].querySelectorAll('*')) {
                        if (node !== overlay && node.shadowRoot) found.push(node.shadowRoot);
                    }
                }
                return found;
            };
            const matches = (selector, searchRoots = roots()) => {
                try { return searchRoots.flatMap(root => [...root.querySelectorAll(selector)]); }
                catch { return []; }
            };
            const restore = node => {
                const previous = hidden.get(node);
                if (!previous) return;
                if (node.style.getPropertyValue('display') === 'none' && node.style.getPropertyPriority('display') === 'important') {
                    if (previous.value) node.style.setProperty('display', previous.value, previous.priority);
                    else node.style.removeProperty('display');
                }
                hidden.delete(node);
            };
            const observed = new WeakSet();
            const observer = new MutationObserver(records => {
                if (records.some(record => record.target !== overlay)) { schedule(); scheduleGeometry(); }
            });
            const observe = searchRoots => {
                for (const root of searchRoots) {
                    if (observed.has(root)) continue;
                    observer.observe(root, {subtree:true, childList:true, attributes:true, attributeFilter:['id','class','style']});
                    observed.add(root);
                }
            };
            const apply = () => {
                timer = null;
                if (suspended) return;
                const desired = new Set(), searchRoots = roots();
                for (const rule of rules) {
                    const found = matches(rule.selector, searchRoots);
                    if (found.length !== 1) continue;
                    const node = found[0];
                    if (!node.style || node.tagName !== rule.tagName || protectedTags.has(node.tagName)) continue;
                    if (rule.selector.includes(':nth-of-type(') && labelFor(node) !== rule.label) continue;
                    desired.add(node);
                    if (!hidden.has(node)) hidden.set(node, {
                        value:node.style.getPropertyValue('display'), priority:node.style.getPropertyPriority('display')
                    });
                    if (node.style.getPropertyValue('display') !== 'none' || node.style.getPropertyPriority('display') !== 'important') {
                        node.style.setProperty('display','none','important');
                    }
                }
                for (const item of previews) {
                    if (!item.node.isConnected) continue;
                    desired.add(item.node);
                    if (!hidden.has(item.node)) hidden.set(item.node, {
                        value:item.node.style.getPropertyValue('display'), priority:item.node.style.getPropertyPriority('display')
                    });
                    if (item.node.style.getPropertyValue('display') !== 'none' || item.node.style.getPropertyPriority('display') !== 'important') {
                        item.node.style.setProperty('display','none','important');
                    }
                }
                for (const node of [...hidden.keys()]) if (!desired.has(node)) restore(node);
                observe(searchRoots);
            };
            const schedule = () => {
                if (timer !== null || suspended || (!rules.length && !previews.length)) return;
                timer = setTimeout(apply, 50);
            };
            const selectorFor = node => {
                const searchRoots = roots();
                const unique = value => {
                    const found = matches(value,searchRoots);
                    return found.length === 1 && found[0] === node;
                };
                if (node.id) {
                    const value = '#' + CSS.escape(node.id);
                    if (value.length <= 1024 && unique(value)) return value;
                }
                for (const attribute of ['data-testid','data-test','aria-label','name']) {
                    const value = node.getAttribute(attribute);
                    if (!value || value.length > 100) continue;
                    const candidate = node.localName + '[' + attribute + '="' + CSS.escape(value) + '"]';
                    if (unique(candidate)) return candidate;
                }
                const parts = [];
                let current = node;
                for (let depth = 0; current && depth < 12; depth++, current = current.parentElement) {
                    let part = CSS.escape(current.localName);
                    if (current.id) part = '#' + CSS.escape(current.id);
                    else if (current.parentElement) {
                        const siblings = [...current.parentElement.children].filter(sibling => sibling.localName === current.localName);
                        if (siblings.length > 1) part += ':nth-of-type(' + (siblings.indexOf(current) + 1) + ')';
                    }
                    parts.unshift(part);
                    const candidate = parts.join(' > ');
                    if (candidate.length > 1024) return null;
                    if (unique(candidate)) return candidate;
                }
                return null;
            };
            const stop = () => {
                selectionToken = null; selection = null; previews = []; touchStart = null;
                overlay?.remove(); overlay = null;
                if (geometryFrame !== null) cancelAnimationFrame(geometryFrame);
                geometryFrame = null;
                apply();
            };
            const publishSelection = () => {
                geometryFrame = null;
                if (!selectionToken || !selection) return;
                const node = selection.node;
                if (!node.isConnected || !validate(documentID,selectionToken,selection.selector)) {
                    selection = null; post('unavailable',{selectionToken}); return;
                }
                const rect = node.getBoundingClientRect(), viewport = window.visualViewport;
                if (rect.width <= 0 || rect.height <= 0) {
                    selection = null; post('unavailable',{selectionToken}); return;
                }
                post('selected',{selectionToken,selector:selection.selector,tagName:node.tagName,label:labelFor(node),
                    canSelectParent:!!node.parentElement && !protectedTags.has(node.parentElement.tagName),
                    bounds:{x:rect.left-(viewport?.offsetLeft||0),y:rect.top-(viewport?.offsetTop||0),
                        width:rect.width,height:rect.height,viewportWidth:viewport?.width||innerWidth}});
            };
            const scheduleGeometry = () => {
                if (selection && geometryFrame === null) geometryFrame = requestAnimationFrame(publishSelection);
            };
            const choose = node => {
                if (!(node instanceof Element) || !node.style || protectedTags.has(node.tagName)) return;
                const selector = selectorFor(node);
                if (!selector) { selection = null; post('unavailable',{selectionToken}); return; }
                selection = {node,selector};
                publishSelection();
            };
            const pointTarget = (x,y) => {
                overlay.style.setProperty('pointer-events','none','important');
                let node = document.elementFromPoint(x,y);
                while (node?.shadowRoot?.elementFromPoint) {
                    const inner = node.shadowRoot.elementFromPoint(x,y);
                    if (!inner || inner === node) break;
                    node = inner;
                }
                overlay.style.setProperty('pointer-events','auto','important');
                return node;
            };
            const validate = (expectedDocument,token,selector) => {
                if (expectedDocument !== documentID || token !== selectionToken || !selection?.node.isConnected || selector !== selection.selector) return false;
                const found = matches(selector); return found.length === 1 && found[0] === selection.node;
            };
            const intercept = event => {
                if (!selectionToken || !overlay) return;
                event.stopImmediatePropagation();
                if (event.type === 'touchstart') {
                    touchStart = event.touches.length === 1 ? {x:event.touches[0].clientX,y:event.touches[0].clientY} : null;
                    touchMoved = !touchStart;
                } else if (event.type === 'touchmove' && touchStart) {
                    const touch = event.touches[0];
                    if (touch && Math.hypot(touch.clientX-touchStart.x,touch.clientY-touchStart.y) > 8) touchMoved = true;
                } else if (event.type === 'touchend') {
                    if (!touchMoved && touchStart && event.changedTouches.length) {
                        event.preventDefault();
                        const touch = event.changedTouches[0]; choose(pointTarget(touch.clientX,touch.clientY));
                    }
                    touchStart = null;
                } else if (['click','dblclick','auxclick','contextmenu'].includes(event.type)) {
                    event.preventDefault();
                    if (event.type === 'click' && !touchMoved) choose(pointTarget(event.clientX,event.clientY));
                    touchMoved = false;
                }
            };
            for (const name of ['pointerdown','pointerup','mousedown','mouseup','click','dblclick','auxclick','contextmenu','touchstart','touchmove','touchend']) {
                window.addEventListener(name,intercept,{capture:true,passive:false});
            }
            window.addEventListener('scroll',scheduleGeometry,true);
            window.addEventListener('resize',scheduleGeometry);
            window.visualViewport?.addEventListener('scroll',scheduleGeometry);
            window.visualViewport?.addEventListener('resize',scheduleGeometry);
            window.addEventListener('keydown',event => {
                if (!selectionToken) return;
                if (['Escape','Enter',' '].includes(event.key)) {
                    event.preventDefault(); event.stopImmediatePropagation();
                    if (event.key === 'Escape') { stop(); post('cancelled'); }
                }
            },true);
            window.addEventListener('pagehide',() => {
                stop(); suspended = true;
                if (timer !== null) clearTimeout(timer);
                timer = null;
            });
            const ready = () => { suspended = false; post('ready'); };
            window.addEventListener('pageshow',ready);
            if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded',ready,{once:true});
            else ready();
            globalThis.__crestElementHiding = {
                update(expectedDocument,nextRevision,nextRules) {
                    if (expectedDocument !== documentID || nextRevision < revision) return false;
                    revision = nextRevision; rules = nextRules.slice(0,512); apply(); return true;
                },
                start(expectedDocument,token) {
                    if (expectedDocument !== documentID || !document.body) return false;
                    stop(); selectionToken = token;
                    overlay = document.createElement('div');
                    overlay.setAttribute('aria-hidden','true');
                    for (const [property,value] of Object.entries({all:'initial',position:'fixed','z-index':'2147483647',
                        inset:'0',background:'transparent',cursor:'crosshair','pointer-events':'auto','touch-action':'pan-x pan-y pinch-zoom'})) {
                        overlay.style.setProperty(property,value,'important');
                    }
                    document.documentElement.append(overlay); return true;
                },
                parent(expectedDocument,token) {
                    if (expectedDocument !== documentID || token !== selectionToken || !selection) return false;
                    choose(selection.node.parentElement); return true;
                },
                validate,
                preview(expectedDocument,token,selector) {
                    if (!validate(expectedDocument,token,selector) || previews.length >= 100) return false;
                    previews.push({node:selection.node,selector,tagName:selection.node.tagName,label:labelFor(selection.node)});
                    selection = null; apply(); return true;
                },
                undo(expectedDocument,token) {
                    if (expectedDocument !== documentID || token !== selectionToken || !previews.length) return false;
                    previews.pop(); selection = null; apply(); return true;
                },
                validatePreviews(expectedDocument,token) {
                    if (expectedDocument !== documentID || token !== selectionToken) return false;
                    return previews.every(item => {
                        const found = matches(item.selector);
                        return item.node.isConnected && found.length === 1 && found[0] === item.node
                            && item.node.tagName === item.tagName
                            && (!item.selector.includes(':nth-of-type(') || labelFor(item.node) === item.label);
                    });
                },
                stop(expectedDocument,token) { if (expectedDocument === documentID && token === selectionToken) stop(); }
            };
            observe([document]);
        })();
        """#
}
