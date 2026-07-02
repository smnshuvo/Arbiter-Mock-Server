package auravation.arbiter.mock_server

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import fi.iki.elonen.NanoHTTPD
import java.io.FilterInputStream
import java.io.InputStream
import java.net.URLDecoder
import java.net.URLEncoder
import java.util.concurrent.ConcurrentHashMap

/**
 * Embedded HTTP server (NanoHTTPD) that serves the user-picked shared folder over the
 * local Wi-Fi network. Folder access is granted through the Storage Access Framework, so
 * the root is a persisted tree [Uri] navigated via [DocumentFile].
 *
 * Routes:
 *   GET /                       → redirect to the file browser (later: library grid)
 *   GET /files/ , /files/a/b/   → directory listing HTML
 *   GET /raw/<path>            → file bytes, with HTTP Range support (?dl=1 forces download)
 *
 * This class is free of Android UI/service concerns; [FileServerService] owns its
 * lifecycle and the foreground notification.
 */
class FileServer(
    private val context: Context,
    private val rootUri: Uri,
    port: Int,
) : NanoHTTPD(port) {

    /**
     * Tree document id of the shared root; null if the URI is invalid or the persisted
     * permission was lost. All navigation goes through DocumentsContract queries keyed by
     * document id — one ContentResolver round-trip per directory — instead of
     * DocumentFile, whose every property access (name/size/mtime/isDirectory) is a
     * separate IPC query and made large folder listings take seconds.
     */
    private val rootDocId: String? = try {
        DocumentsContract.getTreeDocumentId(rootUri)
    } catch (e: Exception) {
        null
    }

    /** Display name of the shared root (single query, cached). */
    private val rootName: String by lazy {
        DocumentFile.fromTreeUri(context, rootUri)?.name ?: "Shared"
    }

    /** A child row from a DocumentsContract children query. */
    private data class ChildDoc(
        val documentId: String,
        val name: String,
        val mime: String,
        val size: Long,
        val lastModified: Long,
    ) {
        val isDirectory: Boolean get() = mime == DocumentsContract.Document.MIME_TYPE_DIR
    }

    /**
     * Tiny expiring cache. Path→id mappings are stable enough to reuse across the burst
     * of requests a page view or video seek session produces, but must not outlive
     * renames/rescans for long — hence the short TTL instead of explicit invalidation.
     */
    private class TtlCache<K : Any, V : Any>(private val ttlMs: Long) {
        private val map = ConcurrentHashMap<K, Pair<Long, V>>()

        operator fun get(key: K): V? {
            val entry = map[key] ?: return null
            if (System.currentTimeMillis() - entry.first > ttlMs) {
                map.remove(key)
                return null
            }
            return entry.second
        }

        operator fun set(key: K, value: V) {
            map[key] = System.currentTimeMillis() to value
        }

        fun clear() = map.clear()
    }

    private val dirIdCache = TtlCache<String, String>(60_000)
    private val fileDocCache = TtlCache<String, ChildDoc>(60_000)
    private val mediaInfoCache = TtlCache<Long, Pair<String, Long>>(60_000)

    /** Scanned-media store, backing the /thumb and /library routes. */
    private val library: LibraryDatabase by lazy { LibraryDatabase(context) }

    /** Requests served since this server instance started (surfaced to the UI). */
    private val requestCounter = java.util.concurrent.atomic.AtomicInteger(0)

    companion object {
        /**
         * App-side toggle: when false, every POST /upload is refused. Volatile so a flip
         * from the Flutter screen takes effect on the already-running server.
         */
        @Volatile
        var uploadsEnabled: Boolean = false

        /**
         * Bytes moved (served + uploaded) since the server last started. The app polls
         * this over the MethodChannel for its speed / total-bandwidth display.
         */
        val totalBytes = java.util.concurrent.atomic.AtomicLong(0)
    }

    /** Wraps served streams so every byte read lands in [totalBytes]. */
    private class CountingInputStream(delegate: InputStream) : FilterInputStream(delegate) {
        override fun read(): Int {
            val b = super.read()
            if (b >= 0) totalBytes.incrementAndGet()
            return b
        }

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            val n = super.read(b, off, len)
            if (n > 0) totalBytes.addAndGet(n.toLong())
            return n
        }
    }

    override fun serve(session: IHTTPSession): Response {
        FileServerEvents.requestCount(requestCounter.incrementAndGet())
        return try {
            when {
                rootDocId == null ->
                    text(
                        Response.Status.INTERNAL_ERROR,
                        "Shared folder is unavailable. Re-pick it in the app.",
                    )
                session.method == Method.POST && (session.uri ?: "") == "/upload" ->
                    handleUpload(session)
                session.method != Method.GET && session.method != Method.HEAD ->
                    text(Response.Status.METHOD_NOT_ALLOWED, "Only GET/HEAD are supported")
                else -> route(session)
            }
        } catch (e: Exception) {
            text(Response.Status.INTERNAL_ERROR, "Server error: ${e.message}")
        }
    }

    // ---- Uploads --------------------------------------------------------------

    /**
     * POST /upload?dir=<path> — multipart form upload into the shared folder (or a
     * subdirectory). Refused unless the user enabled uploads in the app. NanoHTTPD
     * buffers each part to a temp file; we then copy it into the SAF tree.
     */
    private fun handleUpload(session: IHTTPSession): Response {
        if (!uploadsEnabled) {
            return text(Response.Status.FORBIDDEN, "Uploads are disabled in the app")
        }
        // parseBody consumes the multipart stream; temp-file paths land in this map
        // keyed "f", "f2", "f3"… in insertion order, matching parameters["f"].
        val tempFiles = LinkedHashMap<String, String>()
        try {
            session.parseBody(tempFiles)
        } catch (e: Exception) {
            return text(Response.Status.BAD_REQUEST, "Upload failed: ${e.message}")
        }
        val dirParam = session.parameters["dir"]?.firstOrNull() ?: ""
        val segments = splitPath(dirParam)
        val parentId = resolveDirDocId(segments)
            ?: return text(Response.Status.NOT_FOUND, "Target folder not found")
        val names = session.parameters["f"] ?: emptyList()
        if (names.isEmpty()) return text(Response.Status.BAD_REQUEST, "No file supplied")

        var saved = 0
        var firstError: String? = null
        names.forEachIndexed { idx, rawName ->
            val key = if (idx == 0) "f" else "f${idx + 1}"
            val tempPath = tempFiles[key] ?: return@forEachIndexed
            // Some browsers send a full client path; keep only the file name.
            val displayName = rawName.substringAfterLast('/').substringAfterLast('\\')
                .ifBlank { "upload" }
            try {
                val target = DocumentsContract.createDocument(
                    context.contentResolver, docUriFor(parentId),
                    FileTypes.mimeFor(displayName), displayName,
                ) ?: throw IllegalStateException("could not create file")
                val out = context.contentResolver.openOutputStream(target)
                    ?: throw IllegalStateException("cannot open output stream")
                out.use { output ->
                    java.io.FileInputStream(tempPath).use { input ->
                        val buf = ByteArray(64 * 1024)
                        while (true) {
                            val n = input.read(buf)
                            if (n < 0) break
                            output.write(buf, 0, n)
                            totalBytes.addAndGet(n.toLong())
                        }
                    }
                }
                saved++
            } catch (e: Exception) {
                if (firstError == null) firstError = e.message
            }
        }

        if (saved == 0) {
            return text(
                Response.Status.INTERNAL_ERROR,
                "Upload failed (${firstError ?: "unknown error"}). If the shared folder was " +
                    "picked before uploads existed, re-pick it in the app to grant write access.",
            )
        }
        // 303 → the browser re-GETs the directory listing, which now shows the file(s).
        val back = "/files/" + segments.joinToString("") { encode(it) + "/" }
        val res = newFixedLengthResponse(
            Response.Status.REDIRECT_SEE_OTHER, "text/plain", "Uploaded $saved file(s)",
        )
        res.addHeader("Location", back)
        return res
    }

    private fun route(session: IHTTPSession): Response {
        val uri = session.uri ?: "/"
        return when {
            uri == "/" || uri == "/library" -> libraryPage(session)
            uri == "/files" || uri == "/files/" -> listDirectory(emptyList())
            uri.startsWith("/files/") -> listDirectory(splitPath(uri.removePrefix("/files/")))
            uri.startsWith("/raw/") -> serveFile(session, splitPath(uri.removePrefix("/raw/")))
            uri == "/media" -> serveMedia(session)
            uri == "/player" -> playerPage(session)
            uri == "/thumb" -> serveThumb(session)
            uri == "/storyboard" -> serveStoryboard(session)
            uri == "/subs" -> serveSubtitle(session)
            else -> text(Response.Status.NOT_FOUND, "Not found")
        }
    }

    // ---- Directory listing (T5) ---------------------------------------------

    private fun listDirectory(segments: List<String>): Response {
        var docId = resolveDirDocId(segments)
            ?: return text(Response.Status.NOT_FOUND, "Folder not found")
        var children = listChildren(docId)
        if (children == null && segments.isNotEmpty()) {
            // A cached id may have gone stale (rename/move); re-resolve once from scratch.
            dirIdCache.clear()
            fileDocCache.clear()
            docId = resolveDirDocId(segments)
                ?: return text(Response.Status.NOT_FOUND, "Folder not found")
            children = listChildren(docId)
        }
        if (children == null) {
            return text(Response.Status.INTERNAL_ERROR, "Cannot read folder")
        }

        val folders = children.filter { it.isDirectory }.sortedBy { it.name.lowercase() }
        val files = children.filter { !it.isDirectory }.sortedBy { it.name.lowercase() }

        val title = if (segments.isEmpty()) rootName else segments.last()
        // Esc/Back goes to the parent folder, or the library when already at the root.
        val upHref = if (segments.isEmpty()) {
            "/library"
        } else {
            "/files/" + segments.dropLast(1).joinToString("") { encode(it) + "/" }
        }

        val sb = StringBuilder()
        sb.append(htmlHead(escape(title)))
        sb.append("<div class='wrap'>")
        sb.append(breadcrumbs(segments))
        sb.append("<p class='summary'>${folders.size} folders · ${files.size} files</p>")
        if (uploadsEnabled) {
            val dirParam = segments.joinToString("") { encode(it) + "/" }
            sb.append("<form class='upload' method='POST' action='/upload?dir=${escape(dirParam)}'")
            sb.append(" enctype='multipart/form-data'>")
            sb.append("<input type='file' name='f' multiple required>")
            sb.append("<button type='submit'>⬆ Upload here</button></form>")
        }
        sb.append("<div id='grid' data-up-href='${escape(upHref)}'>")

        // Leading nav tile back to the media library (reachable by the D-pad).
        sb.append(tile(mediaIcon = "🎬", name = "Library", meta = "Media grid", nav = true))
        sb.append(actionRow(viewHref = "/library", viewLabel = "🎬 Open", dlHref = null))
        sb.append("</div>")

        if (segments.isNotEmpty()) {
            sb.append(tile(mediaIcon = "⬆️", name = "Parent Directory", meta = "Up one level"))
            sb.append(actionRow(viewHref = upHref, viewLabel = "⬆ Open", dlHref = null))
            sb.append("</div>") // close the parent tile
        }

        val basePath = segments.joinToString("") { encode(it) + "/" }
        for (f in folders) {
            val name = f.name
            val href = "/files/" + basePath + encode(name) + "/"
            sb.append(tile(mediaIcon = FileTypes.iconFor(name, true), name = name, meta = "Folder"))
            sb.append(actionRow(viewHref = href, viewLabel = "📂 Open", dlHref = null))
            sb.append("</div>")
        }

        for (f in files) {
            val name = f.name
            val rawHref = "/raw/" + basePath + encode(name)
            val meta = "${FileTypes.humanSize(f.size)} · ${FileTypes.formatDate(f.lastModified)}"
            val viewHref: String? = when {
                FileTypes.isPlayable(name) -> "/player?v=" + encode(rawHref)
                FileTypes.isViewableInline(name) -> rawHref
                else -> null
            }
            sb.append(tile(mediaIcon = FileTypes.iconFor(name, false), name = name, meta = meta))
            sb.append(actionRow(viewHref = viewHref, viewLabel = "▶ View", dlHref = "$rawHref?dl=1"))
            sb.append("</div>")
        }

        sb.append("</div>") // #grid
        sb.append("<p class='hint'>◀ ▶ move · ▲ View · ▼ Download · OK select · Back = up</p>")
        sb.append("</div>") // .wrap
        sb.append(tvStyles())
        sb.append(tvNavScript())
        sb.append("</body></html>")
        return html(sb.toString())
    }

    /**
     * Opens a tile div (media + name + meta). Caller appends an [actionRow] and closes it.
     * [nav] marks a leading navigation tile so the D-pad script skips it for initial focus.
     */
    private fun tile(
        mediaIcon: String,
        name: String,
        meta: String,
        mediaHtml: String? = null,
        nav: Boolean = false,
    ): String {
        val media = mediaHtml ?: mediaIcon
        val navAttr = if (nav) " data-nav" else ""
        return "<div class='tile'$navAttr><div class='tile-media'>$media</div>" +
            "<div class='tile-name'>${escape(name)}</div>" +
            "<div class='tile-meta'>${escape(meta)}</div>"
    }

    /** The View/Download action pair inside a tile. Either action may be omitted. */
    private fun actionRow(viewHref: String?, viewLabel: String, dlHref: String?): String {
        val sb = StringBuilder("<div class='tile-actions'>")
        if (viewHref != null) {
            sb.append("<a class='act view' href='${escape(viewHref)}'>$viewLabel</a>")
        }
        if (dlHref != null) {
            sb.append("<a class='act dl' href='${escape(dlHref)}'>⬇ Download</a>")
        }
        sb.append("</div>")
        return sb.toString()
    }

    // ---- Library grid (T11) -------------------------------------------------

    /** GET / or /library[?q=term] — Jellyfin-style media grid backed by media_items. */
    private fun libraryPage(session: IHTTPSession): Response {
        val query = session.parameters["q"]?.firstOrNull()?.trim()
        val items = library.getAll(query)

        val sb = StringBuilder()
        sb.append(htmlHead("Library"))
        sb.append("<div class='wrap'>")
        sb.append("<div class='lib-head'>")
        sb.append("<h1>Library</h1>")
        sb.append("<div class='lib-actions'>")
        sb.append("<input id='q' class='search' type='search' placeholder='Search…' ")
        sb.append("value='${escape(query ?: "")}' oninput='filterCards()'>")
        sb.append("<a class='btn' href='/files/'>📁 Browse Files</a>")
        sb.append("</div></div>")

        sb.append("<div id='grid'>")
        // Leading nav tile to the full file browser (always present + D-pad reachable).
        sb.append(tile(mediaIcon = "📁", name = "Browse Files", meta = "All files", nav = true))
        sb.append(actionRow(viewHref = "/files/", viewLabel = "📂 Open", dlHref = null))
        sb.append("</div>")

        if (items.isEmpty()) {
            sb.append("</div>") // #grid
            sb.append("<div class='empty'>")
            sb.append(if (query.isNullOrEmpty()) "No media scanned yet." else "No matches.")
            sb.append("<p class='muted'>Pick a folder and run a scan from the app to populate this grid.</p>")
            sb.append("</div>")
        } else {
            for (item in items) {
                val badge = resolutionBadge(item.height)
                val dur = durationLabel(item.durationMs)
                val media = StringBuilder("<img loading='lazy' src='/thumb?id=${item.id}' alt=''>")
                if (badge != null) media.append("<span class='badge res'>$badge</span>")
                if (dur != null) media.append("<span class='badge dur'>$dur</span>")
                sb.append("<div class='tile' data-title='${escape(item.title.lowercase())}'>")
                sb.append("<div class='tile-media'>$media</div>")
                sb.append("<div class='tile-name'>${escape(item.title)}</div>")
                sb.append(
                    actionRow(
                        viewHref = "/player?id=${item.id}",
                        viewLabel = "▶ View",
                        dlHref = "/media?id=${item.id}&dl=1",
                    ),
                )
                sb.append("</div>")
            }
            sb.append("</div>")
            sb.append("<p class='hint'>◀ ▶ move · ▲ View · ▼ Download · OK select</p>")
        }
        sb.append("</div>")
        sb.append(tvStyles())
        sb.append(
            """
            <style>
              .lib-head{display:flex;align-items:center;justify-content:space-between;gap:12px;
                        flex-wrap:wrap;padding-top:16px}
              .lib-actions{display:flex;gap:8px;align-items:center}
              .search{background:var(--card);border:1px solid var(--line);color:var(--fg);
                      border-radius:8px;padding:7px 10px;font-size:14px}
              .empty{margin-top:64px;text-align:center;color:var(--fg)}
              .empty .muted{color:var(--muted)}
            </style>
            <script>
              function filterCards(){
                var q=(document.getElementById('q').value||'').toLowerCase();
                document.querySelectorAll('#grid .tile').forEach(function(c){
                  var t=c.getAttribute('data-title')||'';
                  c.style.display=t.indexOf(q)>=0?'':'none';
                });
              }
            </script>
            """.trimIndent(),
        )
        sb.append(tvNavScript())
        sb.append("</body></html>")
        return html(sb.toString())
    }

    private fun durationLabel(ms: Long): String? {
        if (ms <= 0) return null
        val totalSec = ms / 1000
        val h = totalSec / 3600
        val m = (totalSec % 3600) / 60
        val s = totalSec % 60
        return if (h > 0) {
            String.format(java.util.Locale.ROOT, "%d:%02d:%02d", h, m, s)
        } else {
            String.format(java.util.Locale.ROOT, "%d:%02d", m, s)
        }
    }

    private fun resolutionBadge(height: Int): String? = when {
        height <= 0 -> null
        height >= 2160 -> "4K"
        height >= 1080 -> "1080p"
        height >= 720 -> "720p"
        height >= 480 -> "480p"
        else -> "SD"
    }

    // ---- Player page (T8) ---------------------------------------------------

    /**
     * GET /player?v=/raw/path/to/file (file browser) or /player?id=<media_id> (library) —
     * a clean in-browser video/audio player.
     */
    private fun playerPage(session: IHTTPSession): Response {
        val id = session.parameters["id"]?.firstOrNull()?.toLongOrNull()
        val src: String
        val name: String
        val mime: String
        var item: MediaItem? = null
        if (id != null) {
            item = library.getById(id)
                ?: return text(Response.Status.NOT_FOUND, "Unknown media")
            src = "/media?id=$id"
            name = item.title
            // The title has no extension, so trust the MIME captured at scan time
            // (falling back to a best guess) instead of guessing from the title.
            mime = item.mimeType.takeIf { it.startsWith("video/") || it.startsWith("audio/") }
                ?: FileTypes.mimeFor(name)
        } else {
            val v = session.parameters["v"]?.firstOrNull()
                ?: return text(Response.Status.BAD_REQUEST, "Missing 'v' parameter")
            // Only allow playing files served by this server.
            if (!v.startsWith("/raw/")) {
                return text(Response.Status.BAD_REQUEST, "Invalid media path")
            }
            src = v
            name = v.substringAfterLast('/').let { decode(it) }
            mime = FileTypes.mimeFor(name)
            // Browser-launched videos live in the library too (the scan covers the whole
            // root), so look the row up by SAF URI to reuse its seek-preview storyboard.
            item = try {
                resolveChildDoc(splitPath(v.removePrefix("/raw/")))
                    ?.let { library.getByPath(docUriFor(it.documentId).toString()) }
            } catch (e: Exception) {
                null
            }
        }
        val isVideo = mime.startsWith("video/")
        // Seek-preview storyboard config for the player script (null = time-only bubble).
        val sbConfig = item?.takeIf {
            !it.storyboardPath.isNullOrEmpty() && it.storyboardFrames > 0 &&
                it.storyboardIntervalMs > 0 && it.storyboardCols > 0
        }?.let {
            "{url:'/storyboard?id=${it.id}',frames:${it.storyboardFrames}," +
                "interval:${it.storyboardIntervalMs},cols:${it.storyboardCols}}"
        } ?: "null"
        val srcAttr = escape(src)
        val dlHref = escape(appendParam(src, "dl", "1"))

        // Sidecar .srt/.vtt files next to the video, exposed as <track> elements served
        // (converted to WebVTT) by /subs. Off by default; the CC button cycles them.
        val subs = if (isVideo) {
            subtitlesFor(id, session.parameters["v"]?.firstOrNull())
        } else {
            emptyList()
        }
        val trackTags = subs.mapIndexed { i, (_, label) ->
            val subSrc = if (id != null) "/subs?id=$id&n=$i" else "/subs?v=${encode(src)}&n=$i"
            val lang = label.takeIf { it.length in 2..3 && it.all(Char::isLetter) }
                ?.lowercase() ?: "und"
            "<track kind='subtitles' label='${escape(label)}' srclang='$lang' src='$subSrc'>"
        }.joinToString("")

        // Native controls are omitted on purpose — TV browsers don't expose them to a
        // D-pad remote. Custom, focusable controls are driven by the script below.
        val mediaEl = if (isVideo) {
            "<video id='media' autoplay playsinline><source src='$srcAttr' type='${escape(mime)}'>" +
                "${trackTags}Your browser cannot play this video.</video>"
        } else {
            "<audio id='media' autoplay><source src='$srcAttr' type='${escape(mime)}'>" +
                "Your browser cannot play this audio.</audio>"
        }

        val sb = StringBuilder()
        sb.append(htmlHead(escape(name)))
        sb.append("<div class='player-wrap ${if (isVideo) "video" else "audio"}'>")
        sb.append("<div class='stage'>")
        if (!isVideo) sb.append("<div class='audio-glyph'>🎵</div>")
        sb.append(mediaEl)
        sb.append("</div>")
        sb.append("<div class='seekprev hidden' id='seekprev'>")
        sb.append("<div class='sbframe' id='sbframe'></div>")
        sb.append("<span class='sbtime' id='sbtime'>0:00</span>")
        sb.append("</div>")
        sb.append("<div class='pbar' id='pbar'>")
        sb.append("<button class='pctl' data-act='back' title='Back'>←</button>")
        sb.append("<button class='pctl play' data-act='play' title='Play/Pause'>⏸</button>")
        sb.append("<div class='pctl seek' data-act='seek'><div class='seek-fill' id='seekfill'></div>")
        sb.append("<div class='seek-knob' id='seekknob'></div>")
        sb.append("<div class='seek-target hidden' id='seektarget'></div></div>")
        sb.append("<span class='ptime' id='ptime'>0:00 / 0:00</span>")
        sb.append("<button class='pctl' data-act='settings' title='Settings'>⚙</button>")
        sb.append("<a class='pctl' data-act='download' href='$dlHref' title='Download'>⬇</a>")
        sb.append("</div>")
        sb.append("<div class='pmenu hidden' id='pmenu'></div>")
        sb.append("<div class='ptoast hidden' id='ptoast'></div>")
        sb.append("<div class='ptitle' id='ptitle'>${escape(name)}</div>")
        sb.append("</div>")
        sb.append(playerStyles())
        sb.append("<script>var SB=$sbConfig;</script>")
        sb.append(playerScript())
        sb.append("</body></html>")
        return html(sb.toString())
    }

    private fun playerStyles(): String = """
        <style>
          .player-wrap{position:fixed;inset:0;background:#000;overflow:hidden}
          .stage{position:absolute;inset:0;display:flex;align-items:center;justify-content:center}
          .stage video{max-width:100%;max-height:100%}
          .player-wrap.audio .stage{background:var(--bg)}
          .audio-glyph{position:absolute;font-size:96px;opacity:.25}
          .stage audio{width:min(640px,90%)}
          .pbar{position:absolute;left:0;right:0;bottom:0;display:flex;align-items:center;gap:12px;
                padding:14px 18px;background:linear-gradient(transparent,rgba(0,0,0,.85));
                transition:opacity .25s ease}
          .pbar.hidden{opacity:0;pointer-events:none}
          .pctl{background:rgba(255,255,255,.12);color:#fff;border:2px solid transparent;border-radius:10px;
                min-width:44px;height:44px;padding:0 12px;font-size:18px;cursor:pointer;
                text-decoration:none;display:inline-flex;align-items:center;justify-content:center}
          .pctl.focused{border-color:var(--accent);background:var(--accent)}
          .pctl.seek{flex:1;min-width:60px;height:12px;padding:0;overflow:visible;
                justify-content:flex-start;border-radius:6px;
                background:rgba(255,255,255,.25);position:relative}
          .pctl.seek.focused{height:18px;border-color:var(--accent);background:rgba(255,255,255,.25)}
          .seek-fill{height:100%;width:0;background:var(--accent);border-radius:6px}
          .seek-knob{position:absolute;top:50%;left:0;width:14px;height:14px;margin-left:-7px;
                border-radius:50%;background:#fff;transform:translateY(-50%);
                box-shadow:0 0 4px rgba(0,0,0,.6)}
          .seek-target{position:absolute;top:0;bottom:0;width:4px;margin-left:-2px;
                background:#fff;border-radius:2px;box-shadow:0 0 4px rgba(0,0,0,.8)}
          .seek-target.hidden{display:none}
          .ptime{color:#fff;font-size:13px;white-space:nowrap;font-variant-numeric:tabular-nums}
          .seekprev{position:absolute;bottom:78px;display:flex;flex-direction:column;align-items:center;
                gap:4px;transform:translateX(-50%);transition:opacity .15s ease;pointer-events:none}
          .seekprev.hidden{opacity:0}
          .sbframe{width:160px;height:90px;border:2px solid var(--accent);border-radius:8px;
                background-color:#000;background-repeat:no-repeat;box-shadow:0 4px 16px rgba(0,0,0,.6)}
          .sbframe.off{display:none}
          .sbtime{color:#fff;font-size:14px;font-weight:600;background:rgba(0,0,0,.75);
                padding:2px 10px;border-radius:8px;font-variant-numeric:tabular-nums}
          .ptitle{position:absolute;top:0;left:0;right:0;padding:14px 18px;color:#fff;font-size:15px;
                  font-weight:600;background:linear-gradient(rgba(0,0,0,.85),transparent);
                  transition:opacity .25s ease;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
          .ptitle.hidden{opacity:0}
          .pmenu{position:absolute;right:18px;bottom:76px;background:rgba(20,24,30,.95);
                border-radius:12px;padding:8px;min-width:230px;display:flex;
                flex-direction:column;gap:4px;box-shadow:0 8px 24px rgba(0,0,0,.5)}
          .pmenu.hidden{display:none}
          .mitem{color:#fff;padding:10px 14px;border-radius:8px;font-size:15px;
                border:2px solid transparent;cursor:pointer;white-space:nowrap}
          .mitem.focused{border-color:var(--accent);background:var(--accent)}
          .mitem.disabled{opacity:.5;cursor:default}
          .ptoast{position:absolute;top:64px;left:50%;transform:translateX(-50%);
                background:rgba(0,0,0,.75);color:#fff;padding:6px 16px;border-radius:10px;
                font-size:15px;transition:opacity .2s ease;pointer-events:none}
          .ptoast.hidden{opacity:0}
          video::cue{background:rgba(0,0,0,.65);color:#fff;font-size:1.1em}
        </style>
    """.trimIndent()

    /**
     * Custom D-pad player: OK=play/pause, ←/→=seek 10s, ↑/↓ move controls, Back=exit.
     * Seeking is deferred (Netflix-style): arrow presses move only a preview bubble
     * (storyboard frame + target time); currentTime is written once, 600ms after the
     * last press, so a burst of presses costs a single Range request + re-buffer.
     */
    private fun playerScript(): String = """
        <script>
        (function(){
          var media=document.getElementById('media');
          var pbar=document.getElementById('pbar');
          var ptitle=document.getElementById('ptitle');
          var playBtn=pbar.querySelector('.pctl.play');
          var fill=document.getElementById('seekfill');
          var timeEl=document.getElementById('ptime');
          var seekprev=document.getElementById('seekprev');
          var sbframe=document.getElementById('sbframe');
          var sbtime=document.getElementById('sbtime');
          var seekBar=pbar.querySelector('.pctl.seek');
          var seektarget=document.getElementById('seektarget');
          var ctrls=Array.prototype.slice.call(pbar.querySelectorAll('.pctl'));
          var ci=1; // default focus = play/pause
          var hideTimer=null;
          var pending=-1; // scrub target in seconds; <0 = not scrubbing
          var scrubDir=0; // +1/-1 while scrubbing
          var commitTimer=null;
          var ptoast=document.getElementById('ptoast');
          var toastTimer=null;
          var seekknob=document.getElementById('seekknob');
          var pmenu=document.getElementById('pmenu');
          var menuOpen=false, mi=0, mitems=[];

          if(SB){ sbframe.style.backgroundImage='url('+SB.url+')'; new Image().src=SB.url; }
          else { sbframe.classList.add('off'); }

          function fmt(t){
            if(!isFinite(t)||t<0) t=0;
            var s=Math.floor(t%60),m=Math.floor((t/60)%60),h=Math.floor(t/3600);
            var mm=(h>0&&m<10?'0':'')+m, ss=(s<10?'0':'')+s;
            return (h>0?h+':':'')+mm+':'+ss;
          }
          function focus(i){
            ci=(i+ctrls.length)%ctrls.length;
            ctrls.forEach(function(c){c.classList.remove('focused');});
            ctrls[ci].classList.add('focused');
          }
          function toggle(){ if(media.paused) media.play(); else media.pause(); }
          function onSeek(){ return ctrls[ci].getAttribute('data-act')==='seek'; }

          // Deferred scrub: presses only move the preview; the real seek commits on idle.
          // Each scrub session is one-directional — the opposite arrow cancels it instead
          // of stepping backward, so the target never bounces around.
          function seekBy(d){
            var dir=d>0?1:-1;
            if(pending>=0&&dir!==scrubDir){ cancelScrub(); return; }
            var dur=media.duration||1e9;
            if(pending<0){ pending=media.currentTime; scrubDir=dir; }
            pending=Math.min(dur,Math.max(0,pending+d));
            updatePreview();
            if(commitTimer) clearTimeout(commitTimer);
            commitTimer=setTimeout(commitSeek,600);
          }
          function updatePreview(){
            var d=media.duration||0;
            var pct=d?(pending/d):0;
            var r=seekBar.getBoundingClientRect();
            var x=r.left+r.width*pct;
            x=Math.min(window.innerWidth-90,Math.max(90,x));
            seekprev.style.left=x+'px';
            seekprev.classList.remove('hidden');
            seektarget.style.left=(pct*100)+'%';
            seektarget.classList.remove('hidden');
            sbtime.textContent=fmt(pending);
            if(SB){
              var f=Math.min(SB.frames-1,Math.max(0,Math.floor(pending*1000/SB.interval)));
              sbframe.style.backgroundPosition=(-(f%SB.cols)*160)+'px '+(-Math.floor(f/SB.cols)*90)+'px';
            }
          }
          function commitSeek(){
            if(commitTimer){ clearTimeout(commitTimer); commitTimer=null; }
            if(pending>=0){ media.currentTime=pending; pending=-1; }
            seekprev.classList.add('hidden');
            seektarget.classList.add('hidden');
          }
          function cancelScrub(){
            if(commitTimer){ clearTimeout(commitTimer); commitTimer=null; }
            pending=-1;
            seekprev.classList.add('hidden');
            seektarget.classList.add('hidden');
          }
          function toggleFullscreen(){
            var d=document;
            if(d.fullscreenElement||d.webkitFullscreenElement){
              (d.exitFullscreen||d.webkitExitFullscreen||function(){}).call(d);
            } else {
              var el=document.querySelector('.player-wrap');
              if(el.requestFullscreen) el.requestFullscreen();
              else if(el.webkitRequestFullscreen) el.webkitRequestFullscreen();
              else if(media.webkitEnterFullscreen) media.webkitEnterFullscreen();
            }
          }
          function activate(){
            var act=ctrls[ci].getAttribute('data-act');
            if(act==='seek'){ if(pending>=0) commitSeek(); else toggle(); }
            else if(act==='play') toggle();
            else if(act==='back') history.back();
            else if(act==='settings'){ if(menuOpen) closeMenu(); else openMenu(); }
            else if(act==='download') location.href=ctrls[ci].getAttribute('href');
          }
          function toast(t){
            ptoast.textContent=t; ptoast.classList.remove('hidden');
            if(toastTimer) clearTimeout(toastTimer);
            toastTimer=setTimeout(function(){ptoast.classList.add('hidden');},1500);
          }

          // Settings menu (gear): Fullscreen + subtitle selection, D-pad navigable.
          function activeSub(){
            var t=media.textTracks||[];
            for(var i=0;i<t.length;i++) if(t[i].mode==='showing') return i;
            return -1;
          }
          function setSub(i){
            var t=media.textTracks||[];
            for(var j=0;j<t.length;j++) t[j].mode=(j===i?'showing':'hidden');
            toast(i<0?'Subtitles off':'Subtitles: '+(t[i].label||('track '+(i+1))));
          }
          function menuItems(){
            var items=[{label:'⛶ Fullscreen',run:toggleFullscreen}];
            var t=media.textTracks?media.textTracks.length:0;
            if(t){
              var cur=activeSub();
              items.push({label:'Subtitles: Off',check:cur<0,run:function(){setSub(-1);}});
              for(var i=0;i<t;i++)(function(i){
                var lb=media.textTracks[i].label||('Track '+(i+1));
                items.push({label:'Subtitles: '+lb,check:cur===i,run:function(){setSub(i);}});
              })(i);
            } else {
              items.push({label:'No subtitles found',disabled:true});
            }
            return items;
          }
          function focusMenu(i){
            if(!mitems.length) return;
            mi=(i+mitems.length)%mitems.length;
            mitems.forEach(function(m){m.el.classList.remove('focused');});
            mitems[mi].el.classList.add('focused');
          }
          function pickMenu(){
            var it=mitems[mi]&&mitems[mi].it;
            if(!it||it.disabled) return;
            closeMenu(); it.run();
          }
          function openMenu(){
            pmenu.innerHTML='';
            mitems=menuItems().map(function(it,i){
              var el=document.createElement('div');
              el.className='mitem'+(it.disabled?' disabled':'');
              el.textContent=it.label+(it.check?'  ✓':'');
              el.addEventListener('mouseenter',function(){focusMenu(i);});
              el.addEventListener('click',function(){focusMenu(i);pickMenu();});
              pmenu.appendChild(el);
              return {el:el,it:it};
            });
            pmenu.classList.remove('hidden');
            menuOpen=true;
            focusMenu(0);
          }
          function closeMenu(){ pmenu.classList.add('hidden'); menuOpen=false; }
          function showControls(){
            pbar.classList.remove('hidden'); ptitle.classList.remove('hidden');
            if(hideTimer) clearTimeout(hideTimer);
            hideTimer=setTimeout(function(){
              if(!media.paused&&!menuOpen){pbar.classList.add('hidden'); ptitle.classList.add('hidden');}
            },3000);
          }

          media.addEventListener('play',function(){playBtn.textContent='⏸';showControls();});
          media.addEventListener('pause',function(){playBtn.textContent='▶';showControls();});
          // The fill+knob always track real playback; only the bubble + tick show the target.
          media.addEventListener('timeupdate',function(){
            var d=media.duration||0;
            var pct=d?(media.currentTime/d*100):0;
            fill.style.width=pct+'%';
            seekknob.style.left=pct+'%';
            timeEl.textContent=fmt(media.currentTime)+' / '+fmt(d);
          });

          ctrls.forEach(function(c,i){
            c.addEventListener('mouseenter',function(){focus(i);showControls();});
            c.addEventListener('click',function(e){
              focus(i);
              var act=c.getAttribute('data-act');
              if(act==='download') return; // let the <a> navigate
              e.preventDefault();
              if(act==='seek'){
                cancelScrub();
                var r=c.getBoundingClientRect();
                var p=(e.clientX-r.left)/r.width;
                media.currentTime=(media.duration||0)*Math.min(1,Math.max(0,p));
              } else {
                activate();
              }
            });
          });
          document.addEventListener('mousemove',showControls);

          // Resolve a logical key from e.key AND e.keyCode (TV remotes vary).
          function keyOf(e){
            var k=e.key, c=e.keyCode||e.which;
            if(k==='ArrowLeft'||c===37) return 'left';
            if(k==='ArrowUp'||c===38) return 'up';
            if(k==='ArrowRight'||c===39) return 'right';
            if(k==='ArrowDown'||c===40) return 'down';
            if(k==='MediaPlayPause'||c===179) return 'playpause';
            if(k==='Enter'||k===' '||c===13||c===32) return 'ok';
            if(k==='Escape'||k==='GoBack'||k==='BrowserBack'||c===8||c===27||c===461||c===10009) return 'back';
            return '';
          }

          document.addEventListener('keydown',function(e){
            if(menuOpen){
              var mh=true;
              switch(keyOf(e)){
                case 'up': focusMenu(mi-1); break;
                case 'down': focusMenu(mi+1); break;
                case 'ok': pickMenu(); break;
                case 'back': case 'left': case 'right': closeMenu(); break;
                default: mh=false;
              }
              if(mh){ showControls(); e.preventDefault(); }
              return;
            }
            var handled=true;
            switch(keyOf(e)){
              case 'left': if(onSeek()) seekBy(-10); else focus(ci-1); break;
              case 'right': if(onSeek()) seekBy(10); else focus(ci+1); break;
              case 'up': focus(ci-1); break;
              case 'down': focus(ci+1); break;
              case 'ok': activate(); break;
              case 'playpause': toggle(); break;
              case 'back': history.back(); break;
              default: handled=false;
            }
            if(handled){ showControls(); e.preventDefault(); }
          });

          focus(1); showControls();
        })();
        </script>
    """.trimIndent()

    // ---- Thumbnail serving (T10) --------------------------------------------

    /** GET /thumb?id=<media_id> — the cached JPEG, or an SVG placeholder on miss. */
    private fun serveThumb(session: IHTTPSession): Response {
        val id = session.parameters["id"]?.firstOrNull()?.toLongOrNull()
            ?: return placeholderThumb()
        val item = library.getById(id) ?: return placeholderThumb()
        val path = item.thumbnailPath
        if (path.isNullOrEmpty()) return placeholderThumb(audio = item.mimeType.startsWith("audio/"))
        val file = java.io.File(path)
        if (!file.exists()) return placeholderThumb(audio = item.mimeType.startsWith("audio/"))
        return try {
            val res = newFixedLengthResponse(
                Response.Status.OK, "image/jpeg",
                CountingInputStream(java.io.FileInputStream(file)), file.length(),
            )
            res.addHeader("Cache-Control", "max-age=86400")
            res
        } catch (e: Exception) {
            placeholderThumb()
        }
    }

    /**
     * GET /storyboard?id=<media_id> — the seek-preview sprite sheet. A plain 404 on miss;
     * the player probes this and simply falls back to a time-only scrub bubble.
     */
    private fun serveStoryboard(session: IHTTPSession): Response {
        val id = session.parameters["id"]?.firstOrNull()?.toLongOrNull()
            ?: return text(Response.Status.NOT_FOUND, "No storyboard")
        val path = library.getById(id)?.storyboardPath
            ?: return text(Response.Status.NOT_FOUND, "No storyboard")
        val file = java.io.File(path)
        if (!file.exists()) return text(Response.Status.NOT_FOUND, "No storyboard")
        return try {
            val res = newFixedLengthResponse(
                Response.Status.OK, "image/jpeg",
                CountingInputStream(java.io.FileInputStream(file)), file.length(),
            )
            res.addHeader("Cache-Control", "max-age=86400")
            res
        } catch (e: Exception) {
            text(Response.Status.NOT_FOUND, "No storyboard")
        }
    }

    // ---- Sidecar subtitles ----------------------------------------------------

    /**
     * Sidecar subtitle files for either player entry point (library id or /raw/ path):
     * files in the same directory whose name starts with the video's base name and ends
     * in .srt/.vtt, paired with a display label ("movie.en.srt" → "en"). Sorted by name
     * so /subs?n= indices are stable between the page render and the track fetch.
     */
    private fun subtitlesFor(id: Long?, v: String?): List<Pair<ChildDoc, String>> = try {
        when {
            id != null -> {
                val item = library.getById(id)
                if (item == null) {
                    emptyList()
                } else {
                    // Path-style document ids ("primary:Movies/film.mkv") hold for the
                    // external-storage/SD providers users share from; anything exotic
                    // lands in the catch and simply gets no subtitles.
                    val docId = DocumentsContract.getDocumentId(Uri.parse(item.filePath))
                    val cut = docId.lastIndexOf('/')
                    if (cut >= 0) {
                        subtitleSiblings(docId.substring(cut + 1), docId.substring(0, cut))
                    } else {
                        subtitleSiblings(docId.substringAfterLast(':'), rootDocId)
                    }
                }
            }
            v != null && v.startsWith("/raw/") -> {
                val segments = splitPath(v.removePrefix("/raw/"))
                val name = segments.lastOrNull()
                if (name == null) {
                    emptyList()
                } else {
                    subtitleSiblings(name, resolveDirDocId(segments.dropLast(1)))
                }
            }
            else -> emptyList()
        }
    } catch (e: Exception) {
        emptyList()
    }

    private fun subtitleSiblings(
        videoName: String,
        parentDocId: String?,
    ): List<Pair<ChildDoc, String>> {
        if (parentDocId == null) return emptyList()
        val base = videoName.substringBeforeLast('.')
        if (base.isEmpty()) return emptyList()
        val children = listChildren(parentDocId) ?: return emptyList()
        return children
            .filter { child ->
                !child.isDirectory &&
                    FileTypes.extensionOf(child.name) in setOf("srt", "vtt") &&
                    child.name.lowercase().startsWith(base.lowercase())
            }
            .sortedBy { it.name.lowercase() }
            .map { child ->
                val label = child.name.substringBeforeLast('.')
                    .drop(base.length).trim('.', ' ', '-', '_')
                child to label.ifEmpty { "Subs" }
            }
    }

    /**
     * GET /subs?id=<media_id>&n=<i> or /subs?v=/raw/<path>&n=<i> — the i-th sidecar
     * subtitle as WebVTT (SRT is converted on the fly; browsers only take VTT tracks).
     */
    private fun serveSubtitle(session: IHTTPSession): Response {
        val n = session.parameters["n"]?.firstOrNull()?.toIntOrNull() ?: 0
        val id = session.parameters["id"]?.firstOrNull()?.toLongOrNull()
        val v = session.parameters["v"]?.firstOrNull()
        val sub = subtitlesFor(id, v).getOrNull(n)?.first
            ?: return text(Response.Status.NOT_FOUND, "No subtitles")
        return try {
            val input = context.contentResolver.openInputStream(docUriFor(sub.documentId))
                ?: return text(Response.Status.NOT_FOUND, "No subtitles")
            val raw = input.use { it.readBytes() }
            if (raw.size > 2_000_000) return text(Response.Status.NOT_FOUND, "Subtitle too large")
            val content = String(raw, Charsets.UTF_8).removePrefix("\uFEFF")
            val vtt = if (FileTypes.extensionOf(sub.name) == "vtt") {
                content
            } else {
                "WEBVTT\n\n" + content.replace(
                    Regex("(\\d{2}:\\d{2}:\\d{2}),(\\d{3})"), "$1.$2",
                )
            }
            val res = newFixedLengthResponse(Response.Status.OK, "text/vtt", vtt)
            res.addHeader("Cache-Control", "max-age=3600")
            res
        } catch (e: Exception) {
            text(Response.Status.NOT_FOUND, "No subtitles")
        }
    }

    /** Inline SVG placeholder (film strip, or a music note for audio). */
    private fun placeholderThumb(audio: Boolean = false): Response {
        val glyph = if (audio) "🎵" else "🎬"
        val svg = """
            <svg xmlns='http://www.w3.org/2000/svg' width='320' height='180'>
              <rect width='100%' height='100%' fill='#232a33'/>
              <text x='50%' y='50%' font-size='64' text-anchor='middle'
                    dominant-baseline='central'>$glyph</text>
            </svg>
        """.trimIndent()
        val res = newFixedLengthResponse(Response.Status.OK, "image/svg+xml", svg)
        res.addHeader("Cache-Control", "max-age=3600")
        return res
    }

    // ---- File serving with Range support (T6) -------------------------------

    private fun serveFile(session: IHTTPSession, segments: List<String>): Response {
        if (segments.isEmpty()) return text(Response.Status.NOT_FOUND, "No file specified")
        val child = resolveChildDoc(segments)?.takeIf { !it.isDirectory }
            ?: return text(Response.Status.NOT_FOUND, "File not found")
        return serveDocument(session, docUriFor(child.documentId), child.name, child.size)
    }

    /**
     * GET /media?id=<media_id> — serves a scanned library item by DB id. Safe because the
     * id must exist in our media DB, which only ever holds files scanned under the root.
     */
    private fun serveMedia(session: IHTTPSession): Response {
        val id = session.parameters["id"]?.firstOrNull()?.toLongOrNull()
            ?: return text(Response.Status.BAD_REQUEST, "Missing 'id'")
        val item = library.getById(id) ?: return text(Response.Status.NOT_FOUND, "Unknown media")
        val uri = Uri.parse(item.filePath)
        // name+length are two IPC queries via DocumentFile; cache them — a video seek
        // session hits this endpoint with a burst of Range requests.
        var info = mediaInfoCache[id]
        if (info == null) {
            val doc = DocumentFile.fromSingleUri(context, uri)
            info = (doc?.name ?: item.title) to (doc?.length() ?: -1L)
            mediaInfoCache[id] = info
        }
        return serveDocument(session, uri, info.first, info.second)
    }

    /** Shared file responder with HTTP Range support, used by /raw and /media. */
    private fun serveDocument(
        session: IHTTPSession,
        fileUri: Uri,
        name: String,
        totalLength: Long,
    ): Response {
        val mime = FileTypes.mimeFor(name)
        val rangeHeader = session.headers["range"]
        val forceDownload = session.parameters["dl"]?.firstOrNull() == "1"
        val disposition = if (forceDownload) {
            "attachment; filename=\"${name.replace("\"", "")}\""
        } else {
            "inline"
        }

        // HEAD → headers only; players probe before streaming, no need to open the file.
        if (session.method == Method.HEAD) {
            val res = newFixedLengthResponse(
                Response.Status.OK, mime, java.io.ByteArrayInputStream(ByteArray(0)),
                totalLength.coerceAtLeast(0),
            )
            res.addHeader("Accept-Ranges", "bytes")
            res.addHeader("Content-Disposition", disposition)
            return res
        }

        // Range request → 206 Partial Content with only the requested window.
        if (rangeHeader != null && rangeHeader.startsWith("bytes=") && totalLength > 0) {
            val (start, end) = parseRange(rangeHeader, totalLength)
                ?: return rangeNotSatisfiable(totalLength)
            val contentLength = end - start + 1
            val input = openStreamAt(fileUri, start)
                ?: return text(Response.Status.INTERNAL_ERROR, "Cannot open file")
            val limited = CountingInputStream(LimitedInputStream(input, contentLength))
            val res = newFixedLengthResponse(
                Response.Status.PARTIAL_CONTENT, mime, limited, contentLength,
            )
            res.addHeader("Accept-Ranges", "bytes")
            res.addHeader("Content-Range", "bytes $start-$end/$totalLength")
            res.addHeader("Content-Disposition", disposition)
            return res
        }

        // Full response.
        val input = context.contentResolver.openInputStream(fileUri)
            ?.let { CountingInputStream(it) }
            ?: return text(Response.Status.INTERNAL_ERROR, "Cannot open file")
        val res = if (totalLength >= 0) {
            newFixedLengthResponse(Response.Status.OK, mime, input, totalLength)
        } else {
            newChunkedResponse(Response.Status.OK, mime, input)
        }
        res.addHeader("Accept-Ranges", "bytes")
        res.addHeader("Content-Disposition", disposition)
        return res
    }

    /** Parses a single-range `bytes=start-end` header into an inclusive [start, end]. */
    private fun parseRange(header: String, totalLength: Long): Pair<Long, Long>? {
        val spec = header.removePrefix("bytes=").split(",").firstOrNull()?.trim() ?: return null
        val dash = spec.indexOf('-')
        if (dash < 0) return null
        val startStr = spec.substring(0, dash)
        val endStr = spec.substring(dash + 1)
        return try {
            when {
                startStr.isEmpty() -> {
                    // suffix range: last N bytes
                    val n = endStr.toLong().coerceAtMost(totalLength)
                    (totalLength - n) to (totalLength - 1)
                }
                else -> {
                    val start = startStr.toLong()
                    val end = if (endStr.isEmpty()) totalLength - 1 else endStr.toLong()
                    val clampedEnd = end.coerceAtMost(totalLength - 1)
                    if (start > clampedEnd) return null
                    start to clampedEnd
                }
            }
        } catch (e: NumberFormatException) {
            null
        }
    }

    private fun rangeNotSatisfiable(totalLength: Long): Response {
        val res = text(Response.Status.RANGE_NOT_SATISFIABLE, "Requested range not satisfiable")
        res.addHeader("Content-Range", "bytes */$totalLength")
        return res
    }

    // ---- Path/URI resolution ------------------------------------------------

    /** All children of a directory in ONE ContentResolver query; null on provider error. */
    private fun listChildren(parentDocId: String): List<ChildDoc>? {
        val childrenUri =
            DocumentsContract.buildChildDocumentsUriUsingTree(rootUri, parentDocId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        return try {
            val out = ArrayList<ChildDoc>()
            context.contentResolver.query(childrenUri, projection, null, null, null)
                ?.use { c ->
                    while (c.moveToNext()) {
                        out.add(
                            ChildDoc(
                                documentId = c.getString(0) ?: continue,
                                name = c.getString(1) ?: continue,
                                mime = c.getString(2) ?: "",
                                size = if (c.isNull(3)) -1L else c.getLong(3),
                                lastModified = if (c.isNull(4)) 0L else c.getLong(4),
                            ),
                        )
                    }
                } ?: return null
            out
        } catch (e: Exception) {
            null
        }
    }

    /** Resolves path segments to a directory document id, caching each prefix. */
    private fun resolveDirDocId(segments: List<String>): String? {
        if (segments.isEmpty()) return rootDocId
        val key = segments.joinToString("/")
        dirIdCache[key]?.let { return it }
        val parentId = resolveDirDocId(segments.dropLast(1)) ?: return null
        val child = listChildren(parentId)
            ?.firstOrNull { it.isDirectory && it.name == segments.last() }
            ?: return null
        dirIdCache[key] = child.documentId
        return child.documentId
    }

    /** Resolves path segments to a file's ChildDoc (cached — Range bursts hit this hard). */
    private fun resolveChildDoc(segments: List<String>): ChildDoc? {
        if (segments.isEmpty()) return null
        val key = segments.joinToString("/")
        fileDocCache[key]?.let { return it }
        val parentId = resolveDirDocId(segments.dropLast(1)) ?: return null
        val child = listChildren(parentId)?.firstOrNull { it.name == segments.last() }
            ?: return null
        if (!child.isDirectory) fileDocCache[key] = child
        return child
    }

    private fun docUriFor(documentId: String): Uri =
        DocumentsContract.buildDocumentUriUsingTree(rootUri, documentId)

    private fun splitPath(raw: String): List<String> =
        raw.split("/").filter { it.isNotEmpty() }.map { decode(it) }

    // ---- HTML/response helpers ----------------------------------------------

    private fun breadcrumbs(segments: List<String>): String {
        val sb = StringBuilder("<nav class='crumbs'>")
        sb.append("<a href='/library'>🎬 Library</a> <span class='sep'>·</span> ")
        sb.append("<a href='/files/'>🏠 ${escape(rootName)}</a>")
        var acc = "/files/"
        for (seg in segments) {
            acc += encode(seg) + "/"
            sb.append(" <span class='sep'>/</span> ")
            sb.append("<a href='${acc}'>${escape(seg)}</a>")
        }
        sb.append("</nav>")
        return sb.toString()
    }

    private fun redirect(location: String): Response {
        val r = newFixedLengthResponse(Response.Status.REDIRECT, MIME_HTML, "")
        r.addHeader("Location", location)
        return r
    }

    private fun text(status: Response.IStatus, message: String): Response =
        newFixedLengthResponse(status, MIME_PLAINTEXT, message)

    private fun html(body: String): Response =
        newFixedLengthResponse(Response.Status.OK, "text/html; charset=utf-8", body)

    private fun htmlHead(title: String): String = """
        <!doctype html><html lang='en'><head><meta charset='utf-8'>
        <meta name='viewport' content='width=device-width,initial-scale=1'>
        <title>$title</title>
        <style>
          :root{--bg:#0f1216;--card:#181d24;--fg:#e7ecf2;--muted:#8a97a6;--accent:#4f9dff;--line:#232a33}
          *{box-sizing:border-box}
          body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 -apple-system,Segoe UI,Roboto,sans-serif}
          .wrap{max-width:980px;margin:0 auto;padding:0 16px 48px}
          .crumbs{position:sticky;top:0;background:var(--bg);padding:16px 0;border-bottom:1px solid var(--line);z-index:5}
          .crumbs a{color:var(--accent);text-decoration:none}
          .crumbs .sep{color:var(--muted)}
          .summary{color:var(--muted);margin:16px 0 8px}
          table{width:100%;border-collapse:collapse}
          th,td{text-align:left;padding:10px 8px;border-bottom:1px solid var(--line);vertical-align:middle}
          th{color:var(--muted);font-weight:600;font-size:13px}
          tr.folder a{font-weight:600}
          td a{color:var(--fg);text-decoration:none}
          td a:hover{color:var(--accent)}
          .c-icon{width:28px}.c-size{width:90px;color:var(--muted);white-space:nowrap}
          .c-date{width:150px;color:var(--muted);white-space:nowrap}
          .c-act{width:120px;white-space:nowrap;text-align:right}
          .btn{display:inline-block;border:1px solid var(--line);background:var(--card);color:var(--fg);
               border-radius:8px;padding:4px 9px;margin-left:4px;cursor:pointer;font-size:14px;text-decoration:none}
          .btn:hover{border-color:var(--accent)}
          @media(max-width:640px){.c-date{display:none}}
        </style></head><body>
    """.trimIndent()

    // ---- Shared TV / D-pad navigation (grids) -------------------------------

    /** Focus/scale + action-button styling shared by the library and file-browser grids. */
    private fun tvStyles(): String = """
        <style>
          #grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));
                gap:18px;margin-top:20px}
          .upload{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:12px 0 0;
                padding:10px 12px;background:var(--card);border:1px dashed var(--line);
                border-radius:12px}
          .upload input[type=file]{font-size:13px;color:var(--muted);max-width:100%}
          .upload button{background:var(--accent);color:#fff;border:0;border-radius:8px;
                padding:8px 14px;font-size:14px;font-weight:600;cursor:pointer}
          .tile{position:relative;display:flex;flex-direction:column;background:var(--card);
                border:1px solid var(--line);border-radius:12px;overflow:hidden;outline:none;
                cursor:pointer;transition:transform .12s ease,border-color .12s ease,box-shadow .12s ease}
          .tile.focused{transform:scale(1.05);border-color:var(--accent);
                box-shadow:0 0 0 2px var(--accent),0 8px 24px rgba(0,0,0,.4);z-index:2}
          .tile-media{position:relative;aspect-ratio:16/9;background:#232a33;display:flex;
                align-items:center;justify-content:center;font-size:52px}
          .tile-media img{width:100%;height:100%;object-fit:cover;display:block}
          .tile-name{padding:8px 10px 2px;font-size:14px;font-weight:600;line-height:1.3;
                display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
          .tile-meta{padding:0 10px 8px;font-size:11.5px;color:var(--muted)}
          .badge{position:absolute;background:rgba(0,0,0,.72);color:#fff;font-size:12px;
                 padding:2px 6px;border-radius:6px}
          .badge.dur{bottom:6px;right:6px}.badge.res{top:6px;right:6px}
          .tile-actions{display:flex;gap:6px;padding:0 8px 8px;opacity:0;max-height:0;
                overflow:hidden;transition:opacity .12s ease,max-height .12s ease}
          .tile.focused .tile-actions,.tile:hover .tile-actions{opacity:1;max-height:60px}
          .act{flex:1;text-align:center;text-decoration:none;color:var(--fg);font-size:13px;
               font-weight:600;padding:6px 4px;border-radius:8px;border:1px solid var(--line);
               background:var(--bg)}
          .act.active{background:var(--accent);border-color:var(--accent);color:#fff}
          .hint{margin-top:18px;color:var(--muted);font-size:12px;text-align:center}
        </style>
    """.trimIndent()

    /**
     * D-pad navigation shared by both grids. Left/Right move between tiles (wrapping
     * across rows); Up highlights View, Down highlights Download; OK/Enter activates the
     * highlighted action; hover focuses a tile; Esc goes up a level (data-up-href on #grid).
     */
    private fun tvNavScript(): String = """
        <script>
        (function(){
          var grid=document.getElementById('grid');
          if(!grid) return;
          var tiles=Array.prototype.slice.call(grid.querySelectorAll('.tile'));
          if(!tiles.length) return;
          var idx=0;

          // Start on the first content tile, skipping any leading nav tile.
          function initialIndex(){
            for(var i=0;i<tiles.length;i++){ if(!tiles[i].hasAttribute('data-nav')) return i; }
            return 0;
          }

          function acts(tile){return Array.prototype.slice.call(tile.querySelectorAll('a.act'));}
          function setActive(tile,which){
            var a=acts(tile);
            a.forEach(function(el){el.classList.remove('active');});
            if(!a.length) return;
            // which: 'view' or 'dl'; fall back to first action.
            var target=a.filter(function(el){return el.classList.contains(which);})[0]||a[0];
            target.classList.add('active');
          }
          function focus(i,which){
            idx=(i+tiles.length)%tiles.length;
            tiles.forEach(function(t){t.classList.remove('focused');});
            var t=tiles[idx];
            t.classList.add('focused');
            setActive(t,which||'view');
            t.scrollIntoView({block:'nearest',behavior:'smooth'});
          }
          function activate(){
            var t=tiles[idx];
            var a=t.querySelector('a.act.active')||t.querySelector('a.act');
            if(a&&a.getAttribute('href')) location.href=a.getAttribute('href');
          }

          tiles.forEach(function(t,i){
            t.setAttribute('tabindex','-1');
            t.addEventListener('mouseenter',function(){focus(i);});
          });

          // Resolve a logical key from e.key AND e.keyCode — many TV remotes only send
          // numeric key codes (or e.key='Unidentified'), so e.key alone isn't enough.
          function keyOf(e){
            var k=e.key, c=e.keyCode||e.which;
            if(k==='ArrowLeft'||c===37) return 'left';
            if(k==='ArrowUp'||c===38) return 'up';
            if(k==='ArrowRight'||c===39) return 'right';
            if(k==='ArrowDown'||c===40) return 'down';
            if(k==='Enter'||k===' '||c===13||c===32) return 'ok';
            if(k==='Escape'||k==='GoBack'||k==='BrowserBack'||c===8||c===27||c===461||c===10009) return 'back';
            return '';
          }

          document.addEventListener('keydown',function(e){
            var tag=(e.target||{}).tagName;
            if(tag==='INPUT'||tag==='TEXTAREA'||tag==='SELECT') return;
            switch(keyOf(e)){
              case 'right': focus(idx+1); e.preventDefault(); break;
              case 'left': focus(idx-1); e.preventDefault(); break;
              case 'up': setActive(tiles[idx],'view'); e.preventDefault(); break;
              case 'down': setActive(tiles[idx],'dl'); e.preventDefault(); break;
              case 'ok': activate(); e.preventDefault(); break;
              case 'back':
                var up=grid.getAttribute('data-up-href');
                if(up){location.href=up; e.preventDefault();}
                break;
            }
          });

          focus(initialIndex());
        })();
        </script>
    """.trimIndent()

    /** Appends a query param, using '?' or '&' depending on whether [url] already has one. */
    private fun appendParam(url: String, key: String, value: String): String {
        val sep = if (url.contains('?')) "&" else "?"
        return "$url$sep$key=$value"
    }

    private fun encode(s: String): String =
        URLEncoder.encode(s, "UTF-8").replace("+", "%20")

    private fun decode(s: String): String = URLDecoder.decode(s, "UTF-8")

    private fun escape(s: String): String = s
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")

    /**
     * Opens the file positioned at [start]. Uses a real O(1) seek on the file descriptor
     * (FileChannel.position) — SAF InputStream.skip() reads and discards every preceding
     * byte, which made deep seeks into large videos take seconds. Falls back to
     * skip-forward only for providers whose descriptors aren't seekable.
     */
    private fun openStreamAt(fileUri: Uri, start: Long): InputStream? {
        if (start <= 0L) return context.contentResolver.openInputStream(fileUri)

        try {
            val pfd = context.contentResolver.openFileDescriptor(fileUri, "r")
            if (pfd != null) {
                // AutoCloseInputStream closes the descriptor when the stream is closed.
                val stream = ParcelFileDescriptor.AutoCloseInputStream(pfd)
                try {
                    stream.channel.position(start)
                    return stream
                } catch (e: Exception) {
                    stream.close()
                }
            }
        } catch (_: Exception) {
        }

        val input = context.contentResolver.openInputStream(fileUri) ?: return null
        var toSkip = start
        while (toSkip > 0) {
            val skipped = input.skip(toSkip)
            if (skipped <= 0) {
                // skip() can return 0 before EOF; fall back to reading and discarding.
                if (input.read() < 0) break
                toSkip--
            } else {
                toSkip -= skipped
            }
        }
        return input
    }

    /**
     * Caps a stream (already positioned at the range start) to the requested Range
     * length so NanoHTTPD never reads past the window.
     */
    private class LimitedInputStream(
        source: InputStream,
        private var remaining: Long,
    ) : FilterInputStream(source) {

        override fun read(): Int {
            if (remaining <= 0) return -1
            val b = super.read()
            if (b >= 0) remaining--
            return b
        }

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            if (remaining <= 0) return -1
            val toRead = minOf(len.toLong(), remaining).toInt()
            val n = super.read(b, off, toRead)
            if (n > 0) remaining -= n
            return n
        }

        override fun available(): Int = minOf(super.available().toLong(), remaining).toInt()
    }
}
