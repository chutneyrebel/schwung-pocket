import SwiftUI
import UIKit
import WebKit

struct ManagerWebView: UIViewRepresentable {
    let url: URL
    var pageZoom: CGFloat = 1.0
    var mirrorDisplayMode: String? = nil
    var fitMirrorViewport: Bool = false
    var recordTrigger: UUID? = nil
    var audioTrigger: UUID? = nil
    var onAudioControlResult: ((String) -> Void)? = nil
    var onRecordControlResult: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let audioContextObserver = WKUserScript(
            source: #"""
            (() => {
              const contexts = window.__spAudioContexts = window.__spAudioContexts || [];
              for (const name of ['AudioContext', 'webkitAudioContext']) {
                const Original = window[name];
                if (!Original || Original.__spWrapped) continue;
                function WrappedAudioContext(...args) {
                  const context = new Original(...args);
                  contexts.push(context);
                  return context;
                }
                WrappedAudioContext.prototype = Original.prototype;
                Object.setPrototypeOf(WrappedAudioContext, Original);
                WrappedAudioContext.__spWrapped = true;
                window[name] = WrappedAudioContext;
              }
            })();
            """#,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(audioContextObserver)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = UIColor(red: 0.055, green: 0.067, blue: 0.09, alpha: 1.0)
        webView.isOpaque = false
        webView.scrollView.backgroundColor = UIColor(red: 0.055, green: 0.067, blue: 0.09, alpha: 1.0)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.pageZoom = pageZoom
        context.coordinator.mirrorDisplayMode = mirrorDisplayMode
        context.coordinator.fitMirrorViewport = fitMirrorViewport
        context.coordinator.onRecordControlResult = onRecordControlResult
        context.coordinator.onAudioControlResult = onAudioControlResult
        if let recordTrigger { context.coordinator.pendingRecordTrigger = recordTrigger; context.coordinator.lastRecordTrigger = recordTrigger }
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 12))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.pageZoom = pageZoom
        context.coordinator.mirrorDisplayMode = mirrorDisplayMode
        context.coordinator.fitMirrorViewport = fitMirrorViewport
        context.coordinator.onRecordControlResult = onRecordControlResult
        context.coordinator.onAudioControlResult = onAudioControlResult

        if let audioTrigger, audioTrigger != context.coordinator.lastAudioTrigger {
            context.coordinator.lastAudioTrigger = audioTrigger
            if webView.isLoading { context.coordinator.pendingAudioTrigger = audioTrigger }
            else { context.coordinator.enablePortalAudio(in: webView) }
        }

        if let recordTrigger, recordTrigger != context.coordinator.lastRecordTrigger {
            context.coordinator.lastRecordTrigger = recordTrigger
            if webView.isLoading {
                context.coordinator.pendingRecordTrigger = recordTrigger
            } else {
                context.coordinator.triggerPortalRecording(in: webView)
            }
        }

        guard webView.url?.absoluteString != url.absoluteString else {
            if !webView.isLoading, mirrorDisplayMode != nil || fitMirrorViewport { context.coordinator.applyMirrorOptions(to: webView) }
            return
        }
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 12))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        var mirrorDisplayMode: String?
        var fitMirrorViewport = false
        var onRecordControlResult: ((String) -> Void)?
        var onAudioControlResult: ((String) -> Void)?
        var pendingAudioTrigger: UUID?
        var lastAudioTrigger: UUID?
        var pendingRecordTrigger: UUID?
        var lastRecordTrigger: UUID?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if mirrorDisplayMode != nil || fitMirrorViewport { applyMirrorOptions(to: webView) }
            if pendingAudioTrigger != nil {
                pendingAudioTrigger = nil
                enablePortalAudio(in: webView)
            }
            if pendingRecordTrigger != nil {
                pendingRecordTrigger = nil
                triggerPortalRecording(in: webView)
            }
        }

        func applyMirrorOptions(to webView: WKWebView) {
            guard mirrorDisplayMode != nil || fitMirrorViewport else { return }
            let mode = mirrorDisplayMode ?? "both"
            let fit = fitMirrorViewport ? "true" : "false"
            let script = #"""
            (() => {
              const mode = '__MODE__';
              const fit = __FIT__;
              const styleId = 'schwung-pocket-mirror-overrides';
              let style = document.getElementById(styleId);
              if (!style) { style = document.createElement('style'); style.id = styleId; document.head.appendChild(style); }
              style.textContent = `
                html, body { width:100% !important; min-width:0 !important; max-width:100% !important; margin:0 !important; }
                body { box-sizing:border-box !important; }
                ${fit ? 'overflow-x:hidden !important;' : ''}
                canvas, img, video, svg { max-width:100% !important; max-height:100dvh !important; object-fit:contain !important; }
              `;
              if (fit) {
                let viewport = document.querySelector('meta[name="viewport"]');
                if (!viewport) { viewport = document.createElement('meta'); viewport.name = 'viewport'; document.head.appendChild(viewport); }
                viewport.content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
              }
              const selector = 'canvas, img, video, svg, [role="img"], [class*="screen" i], [id*="screen" i], [class*="display" i], [id*="display" i], [class*="push-container" i], [class*="push-grid" i], [class*="push-panel" i], [id*="push" i]';
              const visible = el => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el); return r.width > 70 && r.height > 25 && s.visibility !== 'hidden'; };
              // Cache candidates before hiding anything. Hidden elements remain in this list so modes can always be switched back.
              if (!window.__spMirrorRoots || !window.__spMirrorRoots.some(el => el && el.isConnected)) {
                const all = [...document.querySelectorAll(selector)].filter(visible);
                window.__spMirrorRoots = all.filter(el => !all.some(other => other !== el && el.contains(other)));
                window.__spMirrorRoots.sort((a,b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top);
                window.__spMirrorRoots.forEach((el, i) => { if (!el.dataset.spOriginalDisplay) el.dataset.spOriginalDisplay = el.style.display || '__default__'; el.dataset.spMirrorIndex = String(i); });
              }
              const roots = (window.__spMirrorRoots || []).filter(el => el && el.isConnected);
              // Hide portal chrome containing connection status, without hiding a display container.
              const chromeSelector = 'header, nav, [role="banner"], [class*="header" i], [id*="header" i], [class*="navbar" i], [class*="connection-status" i], [class*="status-bar" i]';
              for (const el of document.querySelectorAll(chromeSelector)) {
                const wrapsDisplay = roots.some(root => el === root || el.contains(root));
                const text = (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim();
                const looksLikeStatus = /move\s*(is\s*)?(reachable|connected|offline)|connection\s*status|connected\s*to\s*move/i.test(text);
                if (!wrapsDisplay && (looksLikeStatus || /header|navbar|connection-status|status-bar/i.test((el.className || '') + ' ' + (el.id || '')))) {
                  if (!el.dataset.spMirrorChromeDisplay) el.dataset.spMirrorChromeDisplay = el.style.display || '__default__';
                  el.style.display = 'none';
                } else if (el.dataset.spMirrorChromeDisplay) {
                  el.style.display = el.dataset.spMirrorChromeDisplay === '__default__' ? '' : el.dataset.spMirrorChromeDisplay;
                  delete el.dataset.spMirrorChromeDisplay;
                }
              }
              // Also hide standalone status labels nested inside layout wrappers that
              // contain the display. Do not hide any element that wraps a mirror root.
              for (const el of document.querySelectorAll('body *')) {
                if (roots.some(root => el === root || el.contains(root))) continue;
                const text = (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim();
                if (!text || text.length > 110 || !/move\s*(is\s*)?(reachable|connected|offline)|connection\s*status|connected\s*to\s*move/i.test(text)) continue;
                if (el.querySelector('canvas, img, video, svg')) continue;
                if (!el.dataset.spMirrorStatusDisplay) el.dataset.spMirrorStatusDisplay = el.style.display || '__default__';
                el.style.display = 'none';
              }
              roots.forEach((el, i) => {
                const original = el.dataset.spOriginalDisplay || '__default__';
                const show = mode === 'both' || (mode === 'top' && i === 0) || (mode === 'bottom' && i === roots.length - 1);
                el.style.display = show ? (original === '__default__' ? '' : original) : 'none';
                el.style.width = ''; el.style.height = '';
                if (show && fit) {
                  el.style.maxWidth = '100vw'; el.style.maxHeight = '100dvh'; el.style.boxSizing = 'border-box';
                  if (mode !== 'both') { el.style.width = '100vw'; el.style.height = '100dvh'; el.style.objectFit = 'contain'; }
                }
              });
              document.documentElement.style.width = '100%'; document.body.style.width = '100%';
              window.__spApplyMirrorLayout = () => {
                const current = (window.__spMirrorRoots || []).filter(el => el && el.isConnected);
                // Restore original visibility before measuring. Otherwise a previously hidden
                // top/bottom panel has a zero-sized rectangle and rotation cannot re-order panels.
                current.forEach(el => {
                  const original = el.dataset.spOriginalDisplay || '__default__';
                  el.style.display = original === '__default__' ? '' : original;
                  el.style.width = ''; el.style.height = '';
                });
                current.sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top);
                window.__spMirrorRoots = current;
                current.forEach((el, i) => {
                  const original = el.dataset.spOriginalDisplay || '__default__';
                  const show = mode === 'both' || (mode === 'top' && i === 0) || (mode === 'bottom' && i === current.length - 1);
                  el.style.display = show ? (original === '__default__' ? '' : original) : 'none';
                  if (show && fit) {
                    el.style.maxWidth = '100vw';
                    el.style.maxHeight = '100vh';
                    el.style.maxHeight = '100dvh';
                    el.style.boxSizing = 'border-box';
                    if (mode !== 'both') {
                      el.style.width = '100vw';
                      el.style.height = '100vh';
                      el.style.height = '100dvh';
                      el.style.objectFit = 'contain';
                    }
                  }
                });
                document.documentElement.style.width = '100%';
                document.body.style.width = '100%';
                window.scrollTo(0,0);
              };
              if (!window.__spResizeHandlerInstalled) {
                window.__spResizeHandlerInstalled = true;
                const refit = () => setTimeout(() => { if (window.__spApplyMirrorLayout) window.__spApplyMirrorLayout(); }, 180);
                window.addEventListener('resize', refit, {passive:true});
                window.addEventListener('orientationchange', refit, {passive:true});
              }
              return roots.length;
            })();
            """#
            .replacingOccurrences(of: "__MODE__", with: mode)
            .replacingOccurrences(of: "__FIT__", with: fit)
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func enablePortalAudio(in webView: WKWebView) {
            let script = #"""
            (() => {
              const visible = el => { const r = el.getBoundingClientRect(), s = getComputedStyle(el); return s.display !== 'none' && s.visibility !== 'hidden' && r.width > 0 && r.height > 0; };
              const label = el => [el.innerText, el.textContent, el.getAttribute('aria-label'), el.getAttribute('title'), el.getAttribute('data-testid'), el.getAttribute('data-tooltip-content'), el.value, el.querySelector('svg')?.innerHTML].filter(Boolean).join(' ').replace(/\s+/g,' ').trim();
              const controls = [...document.querySelectorAll('button,[role="button"],a,[onclick],input[type="button"],label')].filter(visible);
              const unmute = controls.find(el => /unmute|enable\s*(sound|audio)|sound\s*on|audio\s*on/i.test(label(el)));
              if (unmute) unmute.click();
              let mediaCount = 0;
              document.querySelectorAll('audio,video').forEach(media => { media.muted = false; media.volume = 1; mediaCount++; const p = media.play(); if (p && p.catch) p.catch(() => {}); });
              const contexts = window.__spAudioContexts || [];
              let resumedContexts = 0;
              contexts.forEach(context => {
                if (context && context.state !== 'closed') {
                  if (context.state === 'suspended') context.resume().catch(() => {});
                  resumedContexts++;
                }
              });
              return (unmute || mediaCount > 0 || resumedContexts > 0) ? 'enabled' : 'not-found';
            })();
            """#
            webView.evaluateJavaScript(script) { [weak self] result, error in
                DispatchQueue.main.async {
                    if let error { NSLog("Schwung Pocket could not enable portal audio: %@", error.localizedDescription); self?.onAudioControlResult?("not-found") }
                    else { self?.onAudioControlResult?((result as? String) ?? "not-found") }
                }
            }
        }

        func triggerPortalRecording(in webView: WKWebView) {
            let script = #"""
            (() => {
              const visible = el => {
                const s = getComputedStyle(el), r = el.getBoundingClientRect();
                return s.display !== 'none' && s.visibility !== 'hidden' && Number(s.opacity || 1) > 0 && r.width > 0 && r.height > 0;
              };
              const labelFor = el => {
                const svg = el.querySelector && el.querySelector('svg');
                const svgText = svg ? [svg.getAttribute('aria-label'), svg.getAttribute('title'), svg.getAttribute('data-testid'), svg.innerHTML].filter(Boolean).join(' ') : '';
                const image = el.querySelector && el.querySelector('img');
                return [el.innerText, el.textContent, el.getAttribute('aria-label'), el.getAttribute('title'), el.getAttribute('data-testid'), el.getAttribute('data-state'), el.getAttribute('data-tooltip-content'), el.value, image && image.alt, svgText].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim();
              };
              const candidates = [...document.querySelectorAll('button, [role="button"], a, input[type="button"], input[type="submit"], [onclick], [tabindex], label')].filter(visible);
              const scored = candidates.map(el => {
                const text = labelFor(el);
                let score = 0;
                if (/\bstop\b/i.test(text)) score = 100;
                else if (/\b(record|recording|capture screen|screen capture)\b/i.test(text)) score = 80;
                else if (/record|capture/i.test(text)) score = 35;
                if (el.matches('button,[role="button"],input[type="button"],input[type="submit"]')) score += 10;
                return {el, text, score};
              }).filter(x => x.score >= 80).sort((a,b) => b.score-a.score);
              let match = scored[0];
              // Some portals use an icon-only button with no accessible text. Search for recording icon metadata.
              if (!match) {
                const icons = [...document.querySelectorAll('button,[role="button"],a,[onclick]')].filter(visible).map(el => ({el, text: labelFor(el)})).filter(x => /record|capture|video|circle-dot|circle-stop/i.test(x.text));
                if (icons.length) match = {el: icons[0].el, text: icons[0].text, score: 50};
              }
              if (!match) return 'not-found';
              const isStop = /\bstop\b/i.test(match.text) || /recording.*active|active.*recording/i.test(match.text);
              match.el.click();
              return isStop ? 'stopped' : 'started';
            })();
            """#
            webView.evaluateJavaScript(script) { [weak self] result, error in
                DispatchQueue.main.async {
                    if let error {
                        NSLog("Schwung Pocket could not activate portal recording: %@", error.localizedDescription)
                        self?.onRecordControlResult?("not-found")
                    } else {
                        self?.onRecordControlResult?((result as? String) ?? "not-found")
                    }
                }
            }
        }
        // WKWebView does not display JavaScript confirm()/alert() panels unless
        // the UI delegate implements them. Schwung Manager uses confirm() for bulk updates.
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            presentJavaScriptDialog(on: webView, title: "Schwung Manager", message: message, confirm: true) { accepted in
                completionHandler(accepted)
            }
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            presentJavaScriptDialog(on: webView, title: "Schwung Manager", message: message, confirm: false) { _ in
                completionHandler()
            }
        }

        private func presentJavaScriptDialog(on webView: WKWebView, title: String, message: String, confirm: Bool, completion: @escaping (Bool) -> Void) {
            DispatchQueue.main.async {
                guard let root = webView.window?.rootViewController else {
                    completion(false)
                    return
                }
                var presenter = root
                while let presented = presenter.presentedViewController { presenter = presented }
                let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                if confirm {
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(false) })
                    alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in completion(true) })
                } else {
                    alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completion(true) })
                }
                presenter.present(alert, animated: true)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NSLog("Schwung Pocket web navigation failed: %@", error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NSLog("Schwung Pocket could not load page: %@", error.localizedDescription)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                decisionHandler(.cancel)
                return
            }

            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        // Some Manager links request a new window. Reuse the current in-app browser
        // rather than letting a tap silently do nothing.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url,
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                completionHandler(nil)
                return
            }

            let folder = documents.appendingPathComponent("Downloads", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let safeName = URL(fileURLWithPath: suggestedFilename).lastPathComponent
                let name = safeName.isEmpty ? "Schwung-Download" : safeName
                var destination = folder.appendingPathComponent(name)
                var suffix = 2
                while FileManager.default.fileExists(atPath: destination.path) {
                    let ext = destination.pathExtension
                    let stem = destination.deletingPathExtension().lastPathComponent
                    let nextName = ext.isEmpty ? "\(stem) (\(suffix))" : "\(stem) (\(suffix)).\(ext)"
                    destination = folder.appendingPathComponent(nextName)
                    suffix += 1
                }
                completionHandler(destination)
            } catch {
                NSLog("Schwung Pocket could not prepare Downloads folder: %@", error.localizedDescription)
                completionHandler(nil)
            }
        }

        func downloadDidFinish(_ download: WKDownload) {
            NotificationCenter.default.post(name: .schwungPocketDownloadFinished, object: nil)
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            NSLog("Schwung Pocket download failed: %@", error.localizedDescription)
        }
    }
}

extension Notification.Name {
    static let schwungPocketDownloadFinished = Notification.Name("SchwungPocketDownloadFinished")
}
