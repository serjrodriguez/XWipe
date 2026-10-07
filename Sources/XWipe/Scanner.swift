import Foundation
import WebKit

extension Engine {
    private static let scanJS = """
    const bearer = 'AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA';
    const ct0 = (document.cookie.match(/(?:^|; )ct0=([^;]+)/) || [])[1];
    const twid = decodeURIComponent((document.cookie.match(/(?:^|; )twid=([^;]+)/) || [])[1] || '');
    const me = twid.replace(/\\D/g, '');
    if (!ct0 || !me) return {status: -1, body: 'sin sesión'};
    const loadIds = async () => {
      const ids = window.__xwIds || {};
      const srcs = [...document.scripts].map(s => s.src).filter(s => s.includes('/client-web'));
      for (const s of srcs) {
        try {
          const t = await (await fetch(s)).text();
          for (const m of t.matchAll(/queryId:"([^"]+)",operationName:"(\\w+)"/g)) ids[m[2]] = m[1];
        } catch (e) {}
      }
      window.__xwIds = ids;
    };
    const headers = {'authorization': 'Bearer ' + bearer, 'x-csrf-token': ct0, 'x-twitter-auth-type': 'OAuth2Session',
                     'x-twitter-active-user': 'yes'};
    const doFetch = window.__xwFetch || fetch.bind(window);
    const cap = (window.__xwReq || {})[op];
    let r, text, src = 'captured';
    if (cap) {
      const u = new URL(cap, location.origin);
      const v = JSON.parse(u.searchParams.get('variables') || '{}');
      v.count = 100; if (cursor) v.cursor = cursor; else delete v.cursor;
      u.searchParams.set('variables', JSON.stringify(v));
      r = await doFetch(u.toString(), {credentials: 'include', headers});
      text = await r.text();
    } else {
      src = 'built';
      if (!window.__xwIds || !window.__xwIds[op]) await loadIds();
      const id = window.__xwIds[op];
      if (!id) return {status: -2, body: 'no encontré queryId de ' + op};
      const vars = {userId: me, count: 100, includePromotedContent: false, withCommunity: true,
                    withVoice: true, withV2Timeline: true, withClientEventToken: false, withBirdwatchNotes: false};
      if (cursor) vars.cursor = cursor;
      const feats = {rweb_tipjar_consumption_enabled: true, responsive_web_graphql_exclude_directive_enabled: true,
        verified_phone_label_enabled: false, creator_subscriptions_tweet_preview_api_enabled: true,
        responsive_web_graphql_timeline_navigation_enabled: true,
        responsive_web_graphql_skip_user_profile_image_extensions_enabled: false,
        communities_web_enable_tweet_community_results_fetch: true, c9s_tweet_anatomy_moderator_badge_enabled: true,
        articles_preview_enabled: true, responsive_web_edit_tweet_api_enabled: true,
        graphql_is_translatable_rweb_tweet_is_translatable_enabled: true, view_counts_everywhere_api_enabled: true,
        longform_notetweets_consumption_enabled: true, responsive_web_twitter_article_tweet_consumption_enabled: true,
        tweet_awards_web_tipping_enabled: false, creator_subscriptions_quote_tweet_preview_enabled: false,
        freedom_of_speech_not_reach_fetch_enabled: true, standardized_nudges_misinfo: true,
        tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled: true,
        rweb_video_timestamps_enabled: true, longform_notetweets_rich_text_read_enabled: true,
        longform_notetweets_inline_media_enabled: true, responsive_web_enhance_cards_enabled: false};
      for (let i = 0; i < 6; i++) {
        const url = 'https://x.com/i/api/graphql/' + id + '/' + op + '?variables=' + encodeURIComponent(JSON.stringify(vars))
                  + '&features=' + encodeURIComponent(JSON.stringify(feats))
                  + '&fieldToggles=' + encodeURIComponent(JSON.stringify({withArticlePlainText: false}));
        r = await doFetch(url, {credentials: 'include', headers});
        text = await r.text();
        if (r.status === 400) {
          const m = text.match(/cannot be null: ([^"\\\\]+)/);
          if (m) { m[1].split(',').forEach(f => feats[f.trim()] = false); continue; }
        }
        break;
      }
    }
    if (r.status !== 200) return {status: r.status, src, reset: r.headers.get('x-rate-limit-reset'), body: text.slice(0, 300)};
    const j = JSON.parse(text);
    const out = []; let next = null; let seen = 0;
    const hl = (handle || '').toLowerCase();
    const walk = o => {
      if (!o || typeof o !== 'object') return;
      if (Array.isArray(o)) { o.forEach(walk); return; }
      if (o.tweet_results && o.tweet_results.result) {
        let t = o.tweet_results.result; if (t.tweet) t = t.tweet;
        if (t.rest_id) {
          seen++;
          const l = t.legacy || {};
          const ur = t.core && t.core.user_results && t.core.user_results.result;
          const author = l.user_id_str || (ur && ur.rest_id);
          const sn = ((ur && ((ur.core && ur.core.screen_name) || (ur.legacy && ur.legacy.screen_name))) || '').toLowerCase();
          if (kind === 'like' || author === me || (sn && sn === hl)) out.push({id: t.rest_id, rt: !!l.retweeted_status_result});
        }
      }
      if (typeof o.entryId === 'string' && o.entryId.startsWith('cursor-bottom') && o.content && o.content.value) next = o.content.value;
      Object.values(o).forEach(walk);
    };
    walk(j);
    return {status: 200, items: out, cursor: next, seen, src};
    """

    private func openAndWait(_ url: String, render: Bool = true) async {
        Web.view.load(URLRequest(url: URL(string: url)!))
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        while Web.view.isLoading { try? await Task.sleep(nanoseconds: 500_000_000) }
        if !render { try? await Task.sleep(nanoseconds: 3_000_000_000); return }
        // Wait for the X app itself to render; reload once if it never does.
        for attempt in 0..<2 {
            for _ in 0..<15 {
                let ok = (try? await Web.view.evaluateJavaScript("!!document.querySelector('[data-testid=\"primaryColumn\"]')") as? Bool) ?? false
                if ok { try? await Task.sleep(nanoseconds: 2_500_000_000); return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if attempt == 0 {
                append("La página no terminó de cargar; recargando…")
                Web.view.reload()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                while Web.view.isLoading { try? await Task.sleep(nanoseconds: 500_000_000) }
            }
        }
    }

    private func profileHandle() async -> String? {
        await openAndWait("https://x.com/home")
        let js = "document.querySelector('a[data-testid=\"AppTabBar_Profile_Link\"]')?.getAttribute('href') || ''"
        for _ in 0..<15 {
            if let path = try? await Web.view.evaluateJavaScript(js) as? String, path.count > 1 {
                let h = String(path.dropFirst())
                UserDefaults.standard.set(h, forKey: "xwipe.handle")
                return h
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return UserDefaults.standard.string(forKey: "xwipe.handle")
    }

    /// Opens the profile through the sidebar (in-app navigation), since a direct load of the profile URL renders blank in this web view.
    private func spaOpenProfile(handle: String) async -> Bool {
        let click = "(() => { const a = document.querySelector('a[data-testid=\"AppTabBar_Profile_Link\"]'); if (!a) return false; a.click(); return true; })()"
        guard (try? await Web.view.evaluateJavaScript(click) as? Bool) == true else { return false }
        let want = "/" + handle.lowercased()
        var arrived = false
        for _ in 0..<20 {
            let path = (try? await Web.view.evaluateJavaScript("location.pathname.toLowerCase()") as? String) ?? ""
            if path == want { arrived = true; break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        guard arrived else { return false }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        return true
    }

    private func openRepliesTab() async {
        let tab = "(() => { const a = [...document.querySelectorAll('a[role=\"tab\"]')].find(x => (x.getAttribute('href') || '').toLowerCase().endsWith('/with_replies')); if (!a) return false; a.click(); return true; })()"
        let clicked = (try? await Web.view.evaluateJavaScript(tab) as? Bool) ?? false
        if !clicked { append("No encontré la pestaña Respuestas.") }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        _ = try? await Web.view.evaluateJavaScript("window.scrollTo(0, 0)")
    }

    /// Posts/reposts: scroll the profile like a user would and read the responses the page itself receives.
    private func scrollScan(handle: String, deleteAsYouGo: Bool, existing: inout Set<String>) async -> Int {
        _ = try? await Web.view.evaluateJavaScript("window.__xwHandle = '\(handle)';")
        var added = 0, idle = 0, lastPages = -1, alreadyDone = 0
        for _ in 0..<2000 {
            if cancelled { break }
            let js = "(() => { const b = window.__xwBuf || []; window.__xwBuf = []; return {items: b, pages: window.__xwPages || 0, seen: window.__xwSeen || 0}; })()"
            guard let res = try? await Web.view.evaluateJavaScript(js) as? [String: Any] else { break }
            let pages = (res["pages"] as? NSNumber)?.intValue ?? 0
            var batch: [Item] = []
            for d in (res["items"] as? [[String: Any]]) ?? [] {
                guard let id = d["id"] as? String else { continue }
                let k: Kind = (d["rt"] as? Bool) == true ? .repost : .post
                let it = Item(kind: k, id: id)
                guard existing.insert(it.key).inserted else { continue }
                items.append(it)
                if done.contains(it.key) { alreadyDone += 1; continue }
                added += 1
                if (k == .post && doPosts) || (k == .repost && doReposts) { batch.append(it) }
            }
            if pages != lastPages {
                append("[posts] páginas recibidas \(pages) · elementos vistos \((res["seen"] as? NSNumber)?.intValue ?? 0) · tuyos nuevos \(batch.count)")
                lastPages = pages; idle = 0
            } else { idle += 1 }
            if deleteAsYouGo && !batch.isEmpty { await run(only: batch); if cancelled { break } }
            if idle >= 8 { break }
            _ = try? await Web.view.evaluateJavaScript("window.scrollTo(0, document.documentElement.scrollHeight); window.scrollBy(0, -300); window.scrollBy(0, 400);")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        append("[posts] ya marcados como borrados pero X aún los devuelve: \(alreadyDone)")
        if let d = try? await Web.view.evaluateJavaScript("JSON.stringify({me: decodeURIComponent((document.cookie.match(/(?:^|; )twid=([^;]+)/) || [])[1] || ''), path: location.pathname, stats: window.__xwStats})") as? String {
            append("[detalle] \(d)")
        }
        if lastPages <= 0 {
            let diag = "JSON.stringify({url: location.href, title: document.title, ready: document.readyState, col: !!document.querySelector('[data-testid=\"primaryColumn\"]'), text: (document.body.innerText || '').slice(0, 250), hook: typeof window.__xwBuf, ops: window.__xwOps || null, cookieSession: /ct0=/.test(document.cookie)})"
            if let d = try? await Web.view.evaluateJavaScript(diag) as? String { append("[diagnóstico] \(d)") }
        }
        if lastPages <= 0 { append("[posts] la página no cargó ningún listado (¿perfil sin posts o sesión caída?)") }
        return added
    }

    /// Reads the timeline page by page; returns how many new pending items were found.
    func scanAccount(deleteAsYouGo: Bool = false) async -> Int {
        guard let handle = await profileHandle() else {
            append("No pude detectar tu perfil. ¿Hay sesión iniciada?"); return 0
        }
        var existing = Set(items.map { $0.key })
        var added = 0
        var passes: [(String, String, String)] = []
        if doPosts || doReposts { passes.append(("posts", "UserTweetsAndReplies", "https://x.com/\(handle)/with_replies")) }
        if doLikes { passes.append(("like", "Likes", "https://x.com/\(handle)/likes")) }

        for (kind, op, page) in passes {
            if kind == "posts" {
                await openAndWait("https://x.com/home")
                guard await spaOpenProfile(handle: handle) else { append("No pude abrir tu perfil desde la barra lateral."); continue }
                append("[posts] pestaña Posts…")
                added += await scrollScan(handle: handle, deleteAsYouGo: deleteAsYouGo, existing: &existing)
                if cancelled { return added }
                append("[posts] pestaña Respuestas…")
                await openRepliesTab()
                added += await scrollScan(handle: handle, deleteAsYouGo: deleteAsYouGo, existing: &existing)
                continue
            }
            await openAndWait(page, render: false)
            var cursor: String? = nil
            var stale = 0
            for _ in 0..<800 {
                if cancelled { return added }
                let args: [String: Any] = ["op": op, "kind": kind, "cursor": cursor as Any? ?? NSNull(), "handle": handle]
                guard let res = try? await Web.view.callAsyncJavaScript(Self.scanJS, arguments: args, in: nil, contentWorld: .page) as? [String: Any]
                else { append("Error ejecutando el escaneo"); break }
                let status = (res["status"] as? NSNumber)?.intValue ?? 0
                if status == 429 {
                    var wait = 60
                    if let s = res["reset"] as? String, let e = Double(s) { wait = min(900, max(5, Int(e - Date().timeIntervalSince1970) + 2)) }
                    append("Límite al escanear. Esperando \(wait)s…")
                    for _ in 0..<wait { if cancelled { return added }; try? await Task.sleep(nanoseconds: 1_000_000_000) }
                    continue
                }
                guard status == 200 else { append("Escaneo falló (\(status)): \((res["body"] as? String) ?? "")"); break }
                var newOnPage = 0
                var batch: [Item] = []
                var page = 0
                for d in (res["items"] as? [[String: Any]]) ?? [] {
                    guard let id = d["id"] as? String else { continue }
                    let k: Kind = kind == "like" ? .like : ((d["rt"] as? Bool) == true ? .repost : .post)
                    let it = Item(kind: k, id: id)
                    page += 1
                    if existing.insert(it.key).inserted {
                        items.append(it); newOnPage += 1
                        if !done.contains(it.key) {
                            added += 1
                            switch it.kind {
                            case .post where doPosts, .repost where doReposts, .like where doLikes: batch.append(it)
                            default: break
                            }
                        }
                    }
                }
                if cursor == nil || page == 0 {
                    append("[\(kind)] fuente: \((res["src"] as? String) ?? "?") · vistos \((res["seen"] as? NSNumber)?.intValue ?? 0) · tuyos \(page)")
                }
                if deleteAsYouGo && !batch.isEmpty {
                    await run(only: batch)
                    if cancelled { return added }
                }
                status_scan(kind, handle)
                stale = newOnPage == 0 ? stale + 1 : 0
                guard let next = res["cursor"] as? String, next != cursor, stale < 4 else { break }
                cursor = next
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        return added
    }

    private func status_scan(_ kind: String, _ handle: String) {
        status = "Escaneando @\(handle): \(count(.post)) posts, \(count(.repost)) reposts, \(count(.like)) likes"
    }

    /// Scan → delete → rescan until nothing is left (or a pass makes no progress).
    func autoWipe() async {
        guard !running, !scanning else { return }
        cancelled = false
        var pass = 0
        scanning = true
        while !cancelled {
            pass += 1
            let before = done.count
            append("Pasada \(pass): escaneando y borrando por páginas de 100…")
            _ = await scanAccount(deleteAsYouGo: true)
            let removed = done.count - before
            append("Pasada \(pass): \(removed) borrados")
            if removed == 0 { break }
        }
        scanning = false
        status = cancelled ? "Detenido. Puedes reanudar." : "Listo. Si queda algo, revisa el registro."
        append(status)
    }
}
