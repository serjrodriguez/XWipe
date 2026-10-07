import SwiftUI
import WebKit

enum Web {
    /// Shared web view; uses the default persistent data store so the login survives restarts.
    static let view: WKWebView = {
        let cfg = WKWebViewConfiguration()
        // Records the exact GraphQL GET requests x.com itself makes, so scans can replay them (right queryId + features).
        let hook = """
        (function(){
          window.__xwReq = window.__xwReq || {}; window.__xwBuf = []; window.__xwPages = 0; window.__xwSeen = 0;
          const me = () => decodeURIComponent((document.cookie.match(/(?:^|; )twid=([^;]+)/) || [])[1] || '').replace(/\\D/g, '');
          window.__xwOps = {}; window.__xwStats = {};
          const note = (u, method) => { try { const s = String(u); const m = s.match(/\\/graphql\\/[^\\/]+\\/(\\w+)/);
            if (m) { window.__xwOps[(method || 'GET') + ' ' + m[1]] = (window.__xwOps[(method || 'GET') + ' ' + m[1]] || 0) + 1; if (s.includes('?')) window.__xwReq[m[1]] = s; } } catch (e) {} };
          const parse = (u, text) => {
            const m = String(u).match(/\\/graphql\\/[^\\/]+\\/(\\w+)/); if (!m) return;
            if (!text.includes('tweet_results')) return;
            const id = me(), hl = (window.__xwHandle || '').toLowerCase();
            const j = JSON.parse(text); window.__xwPages++;
            const st = (window.__xwStats[m[1]] = window.__xwStats[m[1]] || {n: 0, seen: 0, mine: 0, authors: {}}); st.n++;
            const walk = o => {
              if (!o || typeof o !== 'object') return;
              if (Array.isArray(o)) { o.forEach(walk); return; }
              if (o.tweet_results && o.tweet_results.result) {
                let t = o.tweet_results.result; if (t.tweet) t = t.tweet;
                if (t.rest_id) {
                  window.__xwSeen++; st.seen++;
                  const l = t.legacy || {};
                  const ur = t.core && t.core.user_results && t.core.user_results.result;
                  const author = l.user_id_str || (ur && ur.rest_id);
                  const sn = ((ur && ((ur.core && ur.core.screen_name) || (ur.legacy && ur.legacy.screen_name))) || '').toLowerCase();
                  { const k = String(author || sn || '?'); if (Object.keys(st.authors).length < 6 || st.authors[k]) st.authors[k] = (st.authors[k] || 0) + 1; }
                  if (author === id || (sn && sn === hl)) st.mine++;
                  if (author === id || (sn && sn === hl)) window.__xwBuf.push({id: t.rest_id, rt: !!l.retweeted_status_result});
                }
              }
              Object.values(o).forEach(walk);
            };
            walk(j);
          };
          const of = window.fetch; window.__xwFetch = of.bind(window);
          window.fetch = function(i, init) {
            const u = i && i.url ? i.url : i; note(u, (init && init.method) || (i && i.method));
            const p = of.apply(this, arguments);
            try { if (/\\/graphql\\//.test(String(u))) p.then(r => r.clone().text().then(t => { try { parse(u, t); } catch (e) {} })).catch(() => {}); } catch (e) {}
            return p;
          };
          const oo = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function(m, u) {
            note(u, m);
            try { this.addEventListener('load', () => { try { if (/\\/graphql\\//.test(String(u))) parse(u, this.responseText); } catch (e) {} }); } catch (e) {}
            return oo.apply(this, arguments);
          };
        })();
        """
        cfg.userContentController.addUserScript(WKUserScript(source: hook, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        v.load(URLRequest(url: URL(string: "https://x.com/login")!))
        return v
    }()
}

struct WebViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { Web.view }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
