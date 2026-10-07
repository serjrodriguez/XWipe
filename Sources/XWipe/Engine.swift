import Foundation
import WebKit
import AppKit

enum Kind: String, Codable { case post, repost, like }

struct Item: Hashable {
    let kind: Kind
    let id: String
    var key: String { "\(kind.rawValue):\(id)" }
}

@MainActor
final class Engine: ObservableObject {
    @Published var items: [Item] = []
    @Published var doPosts = true
    @Published var doReposts = true
    @Published var doLikes = false
    @Published var running = false
    @Published var scanning = false
    @Published var processed = 0
    @Published var total = 0
    @Published var failed = 0
    @Published var log: [String] = []
    @Published var status = "Inicia sesión en X en el panel derecho y pulsa Escanear y borrar."

    var sampleCount = 0
    var done: Set<String> = []
    var cancelled = false

    private let doneURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("XWipe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("done.json")
    }()

    init() {
        if let d = try? Data(contentsOf: doneURL),
           let arr = try? JSONDecoder().decode([String].self, from: d) { done = Set(arr) }
    }

    // MARK: Counts

    func count(_ k: Kind) -> Int { items.filter { $0.kind == k && !done.contains($0.key) }.count }

    var pending: [Item] {
        items.filter { i in
            guard !done.contains(i.key) else { return false }
            switch i.kind {
            case .post: return doPosts
            case .repost: return doReposts
            case .like: return doLikes
            }
        }
    }

    // MARK: Run

    func stop() { cancelled = true }

    func run(only: [Item]? = nil) async {
        guard !running else { return }
        guard Web.view.url?.host?.hasSuffix("x.com") == true else {
            status = "Abre x.com (ya con sesión iniciada) en el panel derecho primero."; return
        }
        running = true; failed = 0; processed = 0
        if only == nil { cancelled = false }
        var queue = only ?? pending
        total = queue.count
        if only == nil { append("Iniciando: \(total) elementos") }
        var attempts: [String: Int] = [:]
        let width = 4
        while !queue.isEmpty && !cancelled {
            let chunk = Array(queue.prefix(width)); queue.removeFirst(chunk.count)
            let results = await withTaskGroup(of: (Item, Result).self) { g -> [(Item, Result)] in
                for it in chunk { g.addTask { (it, await self.call(it)) } }
                var out: [(Item, Result)] = []
                for await r in g { out.append(r) }
                return out
            }
            var wait = 0
            var retry: [Item] = []
            for (item, r) in results {
                if sampleCount < 8 {
                    sampleCount += 1
                    append("[resp] \(item.key) → \(r.status) \(r.body.prefix(160))")
                }
                if r.ok { done.insert(item.key); processed += 1; continue }
                if r.status == 429 { wait = max(wait, r.wait); retry.append(item); continue }
                if r.status == 401 || r.status == 403 || r.status == -1 {
                    append("Sesión no válida (\(r.status)). Inicia sesión de nuevo. \(r.body)")
                    cancelled = true; continue
                }
                let n = (attempts[item.key] ?? 0) + 1
                attempts[item.key] = n
                if n >= 2 { failed += 1; processed += 1; append("Falló \(item.key): \(r.status) \(r.body)") } else { retry.append(item) }
            }
            queue.insert(contentsOf: retry, at: 0)
            save()
            status = "Procesados \(processed)/\(total) · fallos \(failed)"
            if wait > 0 {
                append("Límite de X alcanzado. Esperando \(wait)s…")
                for _ in 0..<wait { if cancelled { break }; try? await Task.sleep(nanoseconds: 1_000_000_000) }
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        save()
        running = false
        status = cancelled ? "Detenido en \(processed)/\(total). Puedes reanudar." : "Terminado: \(processed)/\(total), fallos \(failed)."
        append(status)
    }

    func resetProgress() { done = []; save(); status = "Progreso reiniciado." }

    func save() {
        if let d = try? JSONEncoder().encode(Array(done)) { try? d.write(to: doneURL) }
    }

    func append(_ s: String) {
        log.append(s); if log.count > 300 { log.removeFirst(100) }
        let url = doneURL.deletingLastPathComponent().appendingPathComponent("log.txt")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }

    // MARK: Network (runs inside the logged-in page, so cookies/CSRF are the real session's)

    struct Result { var ok = false; var status = 0; var wait = 60; var body = "" }

    private static let js = """
    const bearer = 'AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA';
    const fallback = {DeleteTweet:'VaenaVgh5q5ih7kvyVjgtg', UnfavoriteTweet:'ZYKSe-w7KEslx3JhSIk5LA', DeleteRetweet:'iQtK4dl5hBmXewYZuEOKVw'};
    const ct0 = (document.cookie.match(/(?:^|; )ct0=([^;]+)/) || [])[1];
    if (!ct0) return {status: -1, body: 'sin cookie ct0 (no hay sesión)'};
    if (!window.__xwIds) {
      const ids = {};
      const srcs = [...document.scripts].map(s => s.src).filter(s => s.includes('/client-web'));
      for (const s of srcs) {
        try {
          const t = await (await fetch(s)).text();
          for (const m of t.matchAll(/queryId:"([^"]+)",operationName:"(\\w+)"/g)) ids[m[2]] = m[1];
        } catch (e) {}
      }
      window.__xwIds = ids;
    }
    const id = window.__xwIds[op] || fallback[op];
    const r = await fetch('https://x.com/i/api/graphql/' + id + '/' + op, {
      method: 'POST', credentials: 'include',
      headers: {
        'authorization': 'Bearer ' + bearer, 'x-csrf-token': ct0,
        'x-twitter-auth-type': 'OAuth2Session', 'x-twitter-active-user': 'yes',
        'content-type': 'application/json'
      },
      body: JSON.stringify({variables: vars, queryId: id})
    });
    const text = await r.text();
    return {status: r.status, reset: r.headers.get('x-rate-limit-reset'), body: text.slice(0, 300)};
    """

    private func call(_ item: Item) async -> Result {
        let (op, vars): (String, [String: Any]) = {
            switch item.kind {
            case .post, .repost: return ("DeleteTweet", ["tweet_id": item.id, "dark_request": false])
            case .like: return ("UnfavoriteTweet", ["tweet_id": item.id])
            }
        }()
        do {
            let any = try await Web.view.callAsyncJavaScript(Self.js, arguments: ["op": op, "vars": vars],
                                                              in: nil, contentWorld: .page)
            guard let d = any as? [String: Any] else { return Result(body: "respuesta inválida") }
            var r = Result()
            r.status = (d["status"] as? NSNumber)?.intValue ?? 0
            r.body = (d["body"] as? String) ?? ""
            if let s = d["reset"] as? String, let epoch = Double(s) {
                r.wait = min(900, max(5, Int(epoch - Date().timeIntervalSince1970) + 2))
            }
            let gone = r.body.contains("not found") || r.body.contains("\"code\":144") || r.body.contains("NotFound")
            r.ok = r.status == 200 && (!r.body.contains("\"errors\"") || gone)
            return r
        } catch {
            return Result(status: 0, body: error.localizedDescription)
        }
    }
}
