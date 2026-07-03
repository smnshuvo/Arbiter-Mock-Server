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

    /**
     * The app's launcher icon rendered to PNG once, served at /icon.png for the brand
     * header and favicon. Drawn through Canvas so adaptive (XML) icons work too.
     */
    private val iconPngBytes: ByteArray? by lazy {
        try {
            val drawable = context.packageManager.getApplicationIcon(context.packageName)
            val size = 192
            val bitmap = android.graphics.Bitmap.createBitmap(
                size, size, android.graphics.Bitmap.Config.ARGB_8888,
            )
            val canvas = android.graphics.Canvas(bitmap)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            val out = java.io.ByteArrayOutputStream()
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
            bitmap.recycle()
            out.toByteArray()
        } catch (e: Exception) {
            null
        }
    }

    /** Requests served since this server instance started (surfaced to the UI). */
    private val requestCounter = java.util.concurrent.atomic.AtomicInteger(0)

    companion object {
        /** Caps for the /subslist tree walk so a huge share can't stall the request. */
        private const val MAX_SUBTITLE_FILES = 500
        private const val MAX_SUBTITLE_DIRS = 2000

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

        /** In-flight file/media streams; the remux worker yields while this is > 0. */
        private val activeStreams = java.util.concurrent.atomic.AtomicInteger(0)

        fun activeStreamCount(): Int = activeStreams.get()

        /**
         * Wall-clock time (ms) of the most recent request. The FileServerService
         * idle watchdog reads this to auto-stop the server after inactivity.
         */
        @Volatile
        var lastActivityAt: Long = System.currentTimeMillis()

        fun idleMillis(): Long = System.currentTimeMillis() - lastActivityAt

        /**
         * Optional HTTP Basic credentials from the app's "Require login" switch.
         * Null/blank user = anonymous access (the default). Volatile so flips apply to
         * the running server.
         */
        @Volatile
        var authUser: String? = null

        @Volatile
        var authPass: String? = null

        /** Browsers currently subscribed to /remote/events (usually the one TV). */
        private val remoteClients = java.util.concurrent.CopyOnWriteArrayList<RemoteStream>()

        /** Broadcasts a remote-control message (a logical key, or "text:…") to all clients. */
        fun pushRemote(message: String) {
            if (message.isBlank()) return
            val payload = "data: $message\n\n".toByteArray(Charsets.UTF_8)
            for (client in remoteClients) client.offer(payload)
        }

        fun remoteClientCount(): Int = remoteClients.size
    }

    /**
     * One Server-Sent-Events subscriber. NanoHTTPD streams a response by reading from an
     * InputStream, so this blocks its worker thread on a queue until a message (or a 15s
     * keep-alive, which also flushes out dead sockets) is available. Closing — client
     * disconnect or server stop — unregisters it.
     */
    private class RemoteStream : InputStream() {
        private val queue = java.util.concurrent.LinkedBlockingQueue<ByteArray>()

        @Volatile
        private var closed = false
        private var current: ByteArray? = null
        private var pos = 0

        fun offer(bytes: ByteArray) {
            if (!closed) queue.offer(bytes)
        }

        override fun read(): Int {
            val one = ByteArray(1)
            val n = read(one, 0, 1)
            return if (n <= 0) -1 else one[0].toInt() and 0xff
        }

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            if (closed) return -1
            var chunk = current
            if (chunk == null || pos >= chunk.size) {
                chunk = try {
                    queue.poll(15, java.util.concurrent.TimeUnit.SECONDS)
                } catch (e: InterruptedException) {
                    null
                } ?: ": keepalive\n\n".toByteArray(Charsets.UTF_8)
                if (closed) return -1
                current = chunk
                pos = 0
            }
            val n = minOf(len, chunk.size - pos)
            System.arraycopy(chunk, pos, b, off, n)
            pos += n
            return n
        }

        override fun close() {
            closed = true
            remoteClients.remove(this)
            FileServerEvents.remoteClients(remoteClients.size)
        }
    }

    /**
     * NanoHTTPD gzips text-based responses, and HTTPSession.execute() re-applies that
     * decision AFTER serve() returns — overwriting any per-response setGzipEncoding().
     * Overriding this hook is the only reliable way to keep the SSE remote-control
     * stream uncompressed; a gzip compressor buffers the tiny events forever.
     */
    override fun useGzipWhenAccepted(r: Response?): Boolean =
        r?.mimeType?.startsWith("text/event-stream") != true && super.useGzipWhenAccepted(r)

    override fun stop() {
        // Wake and drop any held-open remote subscribers before tearing sockets down.
        for (client in remoteClients.toList()) {
            try {
                client.close()
            } catch (_: Exception) {
            }
        }
        super.stop()
    }

    /**
     * Wraps served streams so every byte read lands in [totalBytes]. [tracked] streams
     * (the big file/media responses) additionally count into [activeStreams] between
     * creation and close, so the remux worker knows when serving is busy.
     */
    private class CountingInputStream(
        delegate: InputStream,
        private val tracked: Boolean = false,
    ) : FilterInputStream(delegate) {

        private val closed = java.util.concurrent.atomic.AtomicBoolean(false)

        init {
            if (tracked) activeStreams.incrementAndGet()
        }

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

        override fun close() {
            if (tracked && closed.compareAndSet(false, true)) {
                activeStreams.decrementAndGet()
            }
            super.close()
        }
    }

    override fun serve(session: IHTTPSession): Response {
        lastActivityAt = System.currentTimeMillis()
        FileServerEvents.requestCount(requestCounter.incrementAndGet())
        val user = authUser
        if (!user.isNullOrEmpty() && !isAuthorized(session, user, authPass ?: "")) {
            val res = text(Response.Status.UNAUTHORIZED, "Authentication required")
            res.addHeader(
                "WWW-Authenticate", "Basic realm=\"Arbiter File Server\", charset=\"UTF-8\"",
            )
            return res
        }
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

    /** Validates an `Authorization: Basic` header against the configured credentials. */
    private fun isAuthorized(session: IHTTPSession, user: String, pass: String): Boolean {
        val header = session.headers["authorization"] ?: return false
        if (!header.startsWith("Basic ", ignoreCase = true)) return false
        return try {
            val supplied = android.util.Base64.decode(
                header.substring(6).trim(), android.util.Base64.DEFAULT,
            )
            val expected = "$user:$pass".toByteArray(Charsets.UTF_8)
            // Timing-safe comparison.
            java.security.MessageDigest.isEqual(supplied, expected)
        } catch (e: Exception) {
            false
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
            uri == "/icon.png" -> serveIcon()
            uri == "/favicon.ico" -> serveFavicon()
            uri == "/remote/events" -> remoteEvents()
            uri == "/remote/state" -> remoteState(session)
            uri == "/remux/start" -> remuxStart(session)
            uri == "/remux/status" -> remuxStatus(session)
            uri == "/remux" -> serveRemux(session)
            uri == "/subs" -> serveSubtitle(session)
            uri == "/subslist" -> subtitleListJson()
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
        sb.append(remoteScript())
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
        // Leading nav tiles (D-pad reachable): search focuses the header input via
        // data-focus (no navigation); Browse Files opens the full file browser.
        sb.append(tile(mediaIcon = "🔍", name = "Search", meta = "Filter the library", nav = true))
        sb.append("<div class='tile-actions'><a class='act view' data-focus='q' href='#'>🔍 Search</a></div>")
        sb.append("</div>")
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
                  var t=c.getAttribute('data-title');
                  if(t===null) return; // nav tiles (Search/Browse) stay visible
                  c.style.display=t.indexOf(q)>=0?'':'none';
                });
              }
              // Enter / Back / Down leave the search box and return to the grid.
              (function(){
                var q=document.getElementById('q');
                if(!q) return;
                q.addEventListener('keydown',function(e){
                  var k=e.key,c=e.keyCode||e.which;
                  if(k==='Enter'||c===13||k==='Escape'||c===27||c===10009||c===461||
                     k==='ArrowDown'||c===40){
                    e.preventDefault(); e.stopPropagation(); q.blur();
                  }
                });
                // Text typed on the phone remote lands in the search box.
                window.__remoteText=function(t){ q.value=t; filterCards(); };
              })();
            </script>
            """.trimIndent(),
        )
        sb.append(tvNavScript())
        sb.append(remoteScript())
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

        // Convertible containers (MKV/TS/MOV/3GP): browsers reject the declared type via
        // canPlayType() without reading a single byte, yet many can demux these with
        // compatible codecs when allowed to sniff — omit the type and let them try; if
        // playback still errors, the remux fallback below converts to MP4.
        val convertible = mime.contains("matroska") || mime == "video/mp2t" ||
            mime == "video/quicktime" || mime.contains("3gpp")
        val typeAttr = if (convertible) "" else " type='${escape(mime)}'"

        // Native controls are omitted on purpose — TV browsers don't expose them to a
        // D-pad remote. Custom, focusable controls are driven by the script below.
        val mediaEl = if (isVideo) {
            "<video id='media' autoplay playsinline><source src='$srcAttr'$typeAttr>" +
                "${trackTags}Your browser cannot play this video.</video>"
        } else {
            "<audio id='media' autoplay><source src='$srcAttr' type='${escape(mime)}'>" +
                "Your browser cannot play this audio.</audio>"
        }

        val sb = StringBuilder()
        sb.append(htmlHead(escape(name), showBrand = false))
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
        sb.append("<div class='pconfirm hidden' id='pconfirm'></div>")
        sb.append("<div class='presume hidden' id='presume'></div>")
        sb.append("<div class='ptoast hidden' id='ptoast'></div>")
        sb.append("<div class='perr hidden' id='perr'></div>")
        sb.append("<div class='pprog hidden' id='pprog'></div>")
        sb.append("<div class='ptitle' id='ptitle'>${escape(name)}</div>")
        sb.append("</div>")
        // Remux fallback config for convertible-container library items.
        val remuxConfig = item?.let { "{id:${it.id},conv:$convertible}" } ?: "null"

        sb.append(playerStyles())
        sb.append("<script>var SB=$sbConfig;var REMUX=$remuxConfig;</script>")
        sb.append(playerScript())
        sb.append(remoteScript())
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
          .pctl.seek.engaged{height:18px;box-shadow:0 0 10px 2px var(--accent)}
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
                border-radius:12px;padding:8px;min-width:230px;max-width:min(70vw,520px);
                max-height:70vh;overflow-y:auto;display:flex;
                flex-direction:column;gap:4px;box-shadow:0 8px 24px rgba(0,0,0,.5)}
          .pmenu.hidden{display:none}
          .mitem.wrap{white-space:normal;word-break:break-word}
          .mitem{color:#fff;padding:10px 14px;border-radius:8px;font-size:15px;
                border:2px solid transparent;cursor:pointer;white-space:nowrap}
          .mitem.focused{border-color:var(--accent);background:var(--accent)}
          .mitem.disabled{opacity:.5;cursor:default}
          .ptoast{position:absolute;top:64px;left:50%;transform:translateX(-50%);
                background:rgba(0,0,0,.75);color:#fff;padding:6px 16px;border-radius:10px;
                font-size:15px;transition:opacity .2s ease;pointer-events:none}
          .ptoast.hidden{opacity:0}
          .perr{position:absolute;top:42%;left:50%;transform:translate(-50%,-50%);
                background:rgba(0,0,0,.85);color:#fff;padding:16px 24px;border-radius:12px;
                font-size:16px;max-width:80%;text-align:center;z-index:5;
                border:1px solid rgba(255,255,255,.15)}
          .perr.hidden{display:none}
          .pprog{position:absolute;top:14px;right:18px;background:rgba(0,0,0,.7);color:#fff;
                font-size:12.5px;padding:5px 12px;border-radius:10px;z-index:4;
                font-variant-numeric:tabular-nums;border:1px solid rgba(255,255,255,.12)}
          .pprog.hidden{display:none}
          .presume{position:absolute;left:50%;bottom:96px;transform:translateX(-50%);
                background:rgba(20,24,30,.96);color:#fff;padding:12px 20px;border-radius:12px;
                font-size:15px;max-width:80%;text-align:center;cursor:pointer;z-index:6;
                border:2px solid var(--accent);box-shadow:0 8px 24px rgba(0,0,0,.5)}
          .presume.hidden{display:none}
          .pconfirm{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);
                background:rgba(20,24,30,.97);color:#fff;padding:22px 26px;border-radius:14px;
                max-width:80%;text-align:center;z-index:7;
                border:1px solid rgba(255,255,255,.15);box-shadow:0 8px 28px rgba(0,0,0,.6)}
          .pconfirm.hidden{display:none}
          .cmsg{font-size:16px;line-height:1.4;margin-bottom:18px}
          .crow{display:flex;gap:12px;justify-content:center}
          .cbtn{background:rgba(255,255,255,.12);color:#fff;border:2px solid transparent;
                border-radius:10px;padding:10px 20px;font-size:15px;font-weight:600;cursor:pointer}
          .cbtn.focused{border-color:var(--accent);background:var(--accent)}
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
          var seekEngaged=false; // seek bar locked for scrubbing (entered with OK)
          var pconfirm=document.getElementById('pconfirm');
          var confirmOpen=false, confirmChoice=0, confirmBtns=[], confirmYes=null, confirmNo=null;
          // Whether to ask before starting a (possibly long) conversion; persisted per device.
          var askConvert=(function(){ try{ return localStorage.getItem('askConvert')!=='0'; }catch(e){ return true; } })();
          // Whether to hide the "⚡ Fast seeking … min left" progress overlay.
          var hideProg=(function(){ try{ return localStorage.getItem('hideFastSeek')==='1'; }catch(e){ return false; } })();

          if(SB){ sbframe.style.backgroundImage='url('+SB.url+')'; new Image().src=SB.url; }
          else { sbframe.classList.add('off'); }

          function fmt(t){
            if(!isFinite(t)||t<0) t=0;
            var s=Math.floor(t%60),m=Math.floor((t/60)%60),h=Math.floor(t/3600);
            var mm=(h>0&&m<10?'0':'')+m, ss=(s<10?'0':'')+s;
            return (h>0?h+':':'')+mm+':'+ss;
          }
          function setEngaged(on){ seekEngaged=on; seekBar.classList.toggle('engaged',on); }
          function disengageSeek(commit){ if(commit) commitSeek(); else cancelScrub(); setEngaged(false); }
          function focus(i){
            // Moving the selection releases the seek bar so left/right traverse again.
            if(seekEngaged){ cancelScrub(); setEngaged(false); }
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
            if(pending>=0){ var t=pending; pending=-1; applySeek(t); }
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
            if(act==='seek'){
              if(!seekEngaged){ setEngaged(true); toast('◀ ▶ to seek · Back to exit'); }
              else if(pending>=0) commitSeek();
              else toggle();
            }
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

          // D-pad confirm dialog (Convert / Not now), reused for both conversion prompts.
          function confirmFocus(i){
            confirmChoice=(i+confirmBtns.length)%confirmBtns.length;
            confirmBtns.forEach(function(b,j){b.classList.toggle('focused',j===confirmChoice);});
          }
          function closeConfirm(){ confirmOpen=false; pconfirm.classList.add('hidden'); }
          function confirmActivate(){
            var yes=confirmChoice===0, y=confirmYes, n=confirmNo;
            closeConfirm();
            if(yes){ if(y) y(); } else { if(n) n(); }
          }
          function confirmCancel(){ var n=confirmNo; closeConfirm(); if(n) n(); }
          function openConfirm(msg,onYes,onNo){
            confirmOpen=true; confirmYes=onYes; confirmNo=onNo;
            pconfirm.innerHTML='';
            var m=document.createElement('div'); m.className='cmsg'; m.textContent=msg;
            var row=document.createElement('div'); row.className='crow';
            confirmBtns=['Convert','Not now'].map(function(lb,i){
              var b=document.createElement('div'); b.className='cbtn'; b.textContent=lb;
              b.addEventListener('mouseenter',function(){confirmFocus(i);});
              b.addEventListener('click',function(){confirmFocus(i);confirmActivate();});
              row.appendChild(b); return b;
            });
            pconfirm.appendChild(m); pconfirm.appendChild(row);
            pconfirm.classList.remove('hidden');
            showControls(); confirmFocus(0);
          }
          // Gate a conversion behind the prompt (unless the user turned asking off).
          function askConvertConfirm(onYes,onNo){
            if(!askConvert){ onYes(); return; }
            openConfirm("This file's format may not be fully supported by your browser. "
              + "Convert it for smooth playback and seeking? This can take a while.", onYes, onNo);
          }

          // Remux integration. Two paths share the same server routes:
          //  - failure path: direct playback errored → overlay + convert + play.
          //  - optimization path: MKV/TS seeks terribly (no byte index), so even when
          //    direct playback works we convert in the background and switch to the
          //    MP4 at the user's next seek (position preserved) — that seek and every
          //    one after it is then instant.
          var perr=document.getElementById('perr');
          var remuxTried=false;
          var usingRemux=false, remuxReady=false, swapping=false;
          var bgTimer=null, optToastShown=false;
          var lastKnownT=0;
          media.addEventListener('timeupdate',function(){
            if(!swapping&&media.currentTime>0) lastKnownT=media.currentTime;
          });
          function showErr(t){ perr.textContent=t; perr.classList.remove('hidden'); showControls(); }
          function finalErr(reason){
            showErr((reason?('Cannot prepare this video: '+reason):
              "This file's format isn't supported by this browser")+' — use ⬇ Download instead.');
            focus(ctrls.length-1); // Download control
          }
          function swapToRemux(resumeT,autoplay){
            usingRemux=true;
            swapping=true;
            perr.classList.add('hidden');
            var s=media.querySelector('source');
            s.setAttribute('src','/remux?id='+REMUX.id);
            s.removeAttribute('type');
            // load() aborts the old stream, which can surface as a spurious error
            // event; onMediaError ignores errors while swapping, and this guard turns
            // a genuinely broken swap into the normal failure overlay.
            var guard=setTimeout(function(){
              if(swapping){ swapping=false; finalErr(); }
            },8000);
            var once=function(){
              media.removeEventListener('loadedmetadata',once);
              clearTimeout(guard);
              swapping=false;
              if(resumeT>0) media.currentTime=resumeT;
              if(autoplay) media.play();
            };
            media.addEventListener('loadedmetadata',once);
            media.load();
          }
          function applySeek(t){
            if(remuxReady&&!usingRemux&&REMUX&&REMUX.id){
              swapToRemux(t,!media.paused);
            } else {
              media.currentTime=t;
              if(REMUX&&REMUX.conv&&!usingRemux&&!remuxReady&&!optToastShown&&!remuxTried){
                optToastShown=true;
                toast('Optimizing for fast seeking…');
              }
            }
          }
          function pollRemux(){
            setTimeout(function(){
              fetch('/remux/status?id='+REMUX.id)
                .then(function(r){return r.json();})
                .then(function(s){
                  // Resume where playback died, not from the beginning.
                  if(s.state==='ready'){ swapToRemux(lastKnownT,true); }
                  else if(s.state==='failed'){ finalErr(s.reason); }
                  else { showErr('Preparing video… '+(s.pct||0)+'%'); pollRemux(); }
                })
                .catch(function(){ finalErr(); });
            },2000);
          }
          function onMediaError(){
            if(swapping) return; // aborting the old stream mid-swap is not a failure
            if(bgTimer){ clearTimeout(bgTimer); bgTimer=null; }
            if(remuxTried||usingRemux){ finalErr(); return; }
            if(window.fetch&&REMUX&&REMUX.id&&REMUX.conv){
              remuxTried=true;
              askConvertConfirm(function(){
                showErr('Preparing video…');
                fetch('/remux/start?id='+REMUX.id)
                  .then(function(){ pollRemux(); })
                  .catch(function(){ finalErr(); });
              }, function(){ finalErr(); });
            } else {
              finalErr();
            }
          }
          media.addEventListener('error',onMediaError);
          var srcEl=media.querySelector('source');
          // A failing <source> fires error on the source element, not the media element.
          if(srcEl) srcEl.addEventListener('error',onMediaError);

          // Background optimization: kicked once direct playback of a convertible
          // container actually starts. A small corner chip shows conversion progress
          // (with an ETA once the rate stabilizes) so slow seeks during the window
          // explain themselves; it never blocks playback.
          var pprog=document.getElementById('pprog');
          var bgT0=0, bgPct0=-1;
          function progText(pct){
            var t='⚡ Fast seeking: '+pct+'%';
            var now=Date.now();
            if(bgPct0<0&&pct>0){ bgPct0=pct; bgT0=now; }
            else if(bgPct0>=0&&pct>bgPct0&&now>bgT0+5000){
              var rate=(pct-bgPct0)/((now-bgT0)/1000); // pct per second
              var left=Math.ceil((100-pct)/rate);
              t+=left>=90?(' · ~'+Math.ceil(left/60)+' min left'):(' · ~'+left+'s left');
            }
            return t;
          }
          function bgPoll(){
            bgTimer=setTimeout(function(){
              fetch('/remux/status?id='+REMUX.id)
                .then(function(r){return r.json();})
                .then(function(s){
                  if(s.state==='ready'){
                    remuxReady=true;
                    pprog.classList.add('hidden');
                    if(!hideProg) toast('Fast seeking ready');
                  } else if(s.state==='failed'){
                    // Direct play works; seeking stays slow. Drop the chip quietly.
                    pprog.classList.add('hidden');
                  } else {
                    // Keep polling either way; just don't surface the chip when hidden.
                    if(hideProg){ pprog.classList.add('hidden'); }
                    else { pprog.textContent=progText(s.pct||0); pprog.classList.remove('hidden'); }
                    bgPoll();
                  }
                })
                .catch(function(){ pprog.classList.add('hidden'); });
            },3000);
          }
          var bgStarted=false;
          media.addEventListener('playing',function(){
            if(bgStarted||remuxTried||usingRemux) return;
            if(!(window.fetch&&REMUX&&REMUX.id&&REMUX.conv)) return;
            bgStarted=true;
            // Ask before the (possibly long) background conversion. Declining just leaves
            // playback as-is with slow seeks.
            askConvertConfirm(function(){
              fetch('/remux/start?id='+REMUX.id)
                .then(function(){ bgPoll(); })
                .catch(function(){});
            }, function(){});
          });

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
              items.push({label:'No sidecar subtitles found',disabled:true});
            }
            if(media.tagName==='VIDEO') items.push({label:'＋ Custom subtitle…',run:openSubBrowser});
            if(REMUX&&REMUX.conv) items.push({label:'Fast-seek progress: '+(hideProg?'Hidden':'Shown'),run:function(){
              hideProg=!hideProg;
              try{ localStorage.setItem('hideFastSeek',hideProg?'1':'0'); }catch(e){}
              if(hideProg) pprog.classList.add('hidden');
              toast('Fast-seek progress '+(hideProg?'hidden':'shown'));
            }});
            return items;
          }
          function focusMenu(i){
            if(!mitems.length) return;
            mi=(i+mitems.length)%mitems.length;
            mitems.forEach(function(m){m.el.classList.remove('focused');});
            mitems[mi].el.classList.add('focused');
            if(mitems[mi].el.scrollIntoView) mitems[mi].el.scrollIntoView({block:'nearest'});
          }
          function pickMenu(){
            var it=mitems[mi]&&mitems[mi].it;
            if(!it||it.disabled) return;
            closeMenu(); it.run();
          }
          function renderMenu(list){
            pmenu.innerHTML='';
            pmenu.scrollTop=0;
            mitems=list.map(function(it,i){
              var el=document.createElement('div');
              el.className='mitem'+(it.disabled?' disabled':'')+(it.wrap?' wrap':'');
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
          function openMenu(){ renderMenu(menuItems()); }
          function closeMenu(){ pmenu.classList.add('hidden'); menuOpen=false; }

          // Custom subtitle picker: /subslist is every .srt/.vtt in the share, so the user
          // can attach one whose name/folder doesn't match the video. Selecting it appends
          // a <track> and shows only it.
          function openSubBrowser(){
            toast('Loading subtitles…');
            fetch('/subslist').then(function(r){return r.json();}).then(function(list){
              var items=[{label:'← Back',run:openMenu}];
              if(!list.length){
                items.push({label:'No subtitle files in the share',disabled:true});
              } else {
                list.forEach(function(s){
                  items.push({label:'📜 '+s.label,wrap:true,run:function(){loadCustomSub(s);}});
                });
              }
              renderMenu(items);
            }).catch(function(){ toast('Could not load subtitles'); });
          }
          function loadCustomSub(s){
            var tr=document.createElement('track');
            tr.kind='subtitles';
            tr.label=s.label||'Custom';
            tr.srclang='und';
            tr.src='/subs?doc='+encodeURIComponent(s.doc)+'&ext='+encodeURIComponent(s.ext||'srt');
            media.appendChild(tr);
            // The appended <track> registers in media.textTracks; show only it.
            setTimeout(function(){
              var tt=media.textTracks;
              for(var i=0;i<tt.length;i++) tt[i].mode=(tt[i]===tr.track?'showing':'hidden');
              toast('Subtitle: '+(s.label||'custom'));
            },0);
          }
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

          // Click/tap the video surface toggles play/pause. The control-bar buttons
          // are separate elements and handle their own clicks, so this only fires
          // on the video itself.
          media.addEventListener('click',function(){ toggle(); showControls(); });

          // Report playback state to the phone remote so its seekbar + volume mirror
          // the movie (throttled ~1/s on timeupdate; immediate on state changes).
          var lastReport=0;
          function reportState(force){
            var now=Date.now();
            if(!force && now-lastReport<900) return;
            lastReport=now;
            var d=media.duration, t=media.currentTime||0;
            var url='/remote/state?t='+t.toFixed(2)
                   +'&d='+(isFinite(d)?d.toFixed(2):'0')
                   +'&p='+(media.paused?1:0)
                   +'&v='+(media.volume!=null?media.volume.toFixed(2):'1');
            try{ fetch(url,{method:'GET',keepalive:true}); }catch(e){}
          }
          media.addEventListener('timeupdate',function(){ reportState(false); });
          media.addEventListener('play',function(){ reportState(true); });
          media.addEventListener('pause',function(){ reportState(true); });
          media.addEventListener('volumechange',function(){ reportState(true); });
          media.addEventListener('loadedmetadata',function(){ reportState(true); });

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
                applySeek((media.duration||0)*Math.min(1,Math.max(0,p)));
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

          // One logical-key handler shared by the DOM listener and the phone remote.
          // seekback/seekfwd come only from the remote's media buttons and seek
          // regardless of which control is focused.
          function handleKey(k){
            if(confirmOpen){
              switch(k){
                case 'left': confirmFocus(confirmChoice-1); break;
                case 'right': confirmFocus(confirmChoice+1); break;
                case 'ok': confirmActivate(); break;
                case 'back': confirmCancel(); break;
              }
              return true; // modal — swallow everything
            }
            if(resumePending){
              if(k==='ok'){ applyResume(); return true; }
              if(k==='back'){ dismissResume(); return true; }
              dismissResume(); // any other key dismisses, then acts normally below
            }
            if(menuOpen){
              switch(k){
                case 'up': focusMenu(mi-1); break;
                case 'down': focusMenu(mi+1); break;
                case 'ok': pickMenu(); break;
                case 'back': case 'left': case 'right': closeMenu(); break;
                default: return false;
              }
              showControls();
              return true;
            }
            switch(k){
              case 'left': if(onSeek()&&seekEngaged) seekBy(-10); else focus(ci-1); break;
              case 'right': if(onSeek()&&seekEngaged) seekBy(10); else focus(ci+1); break;
              case 'up': focus(ci-1); break;
              case 'down': focus(ci+1); break;
              case 'ok': activate(); break;
              case 'playpause': toggle(); break;
              case 'seekback': seekBy(-10); break;
              case 'seekfwd': seekBy(10); break;
              case 'back': if(seekEngaged) disengageSeek(true); else history.back(); break;
              default: return false;
            }
            showControls();
            return true;
          }
          window.__remoteKey=handleKey;
          // Absolute seek + volume driven from the phone remote's sliders.
          window.__remoteSeek=function(sec){
            var s=parseFloat(sec);
            if(!isNaN(s)){ applySeek(Math.max(0,s)); showControls(); reportState(true); }
          };
          window.__remoteVol=function(v){
            var x=parseFloat(v);
            if(!isNaN(x)){ media.volume=Math.min(1,Math.max(0,x)); reportState(true); }
          };

          document.addEventListener('keydown',function(e){
            if(handleKey(keyOf(e))) e.preventDefault();
          });

          // Resume-from-last-position. Position is saved per video (keyed by the /player
          // URL, so it survives the remux source-swap) in localStorage; on reopen we offer
          // to jump back. Saving pauses while the prompt is up so the fresh autoplay-from-0
          // doesn't clobber the stored position before the user answers.
          var STOREKEY='resume:'+location.pathname+location.search;
          var presume=document.getElementById('presume');
          var resumePending=false, resumeSecs=0, resumeShown=false;
          var resumeTimer=null, lastSave=0;
          function loadSaved(){ try{ return parseInt(localStorage.getItem(STOREKEY)||'0',10)||0; }catch(e){ return 0; } }
          function saveNow(){
            if(resumePending) return;
            try{
              var t=Math.floor(media.currentTime), d=media.duration||0;
              if(d&&t>=d-10) localStorage.removeItem(STOREKEY);
              else if(t>3) localStorage.setItem(STOREKEY,String(t));
            }catch(e){}
          }
          function askResume(s){
            resumePending=true; resumeSecs=s;
            presume.textContent='▶ Resume from '+fmt(s)+'?  ·  OK to resume, Back to start over';
            presume.classList.remove('hidden');
            showControls();
            if(resumeTimer) clearTimeout(resumeTimer);
            resumeTimer=setTimeout(dismissResume,12000);
          }
          function endResume(){
            resumePending=false;
            presume.classList.add('hidden');
            if(resumeTimer){ clearTimeout(resumeTimer); resumeTimer=null; }
          }
          function applyResume(){
            if(!resumePending) return;
            var t=resumeSecs; endResume(); applySeek(t); toast('Resumed from '+fmt(t));
          }
          function dismissResume(){ if(resumePending) endResume(); }
          presume.addEventListener('click',applyResume);
          media.addEventListener('loadedmetadata',function(){
            if(resumeShown) return; // fire once — the remux swap reloads metadata
            resumeShown=true;
            var s=loadSaved(), d=media.duration||0;
            if(s>5&&(!d||s<d-15)) askResume(s);
          });
          media.addEventListener('timeupdate',function(){
            var now=Date.now();
            if(now-lastSave<5000) return;
            lastSave=now; saveNow();
          });
          media.addEventListener('pause',saveNow);
          media.addEventListener('ended',function(){ try{ localStorage.removeItem(STOREKEY); }catch(e){} });
          window.addEventListener('beforeunload',saveNow);

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
     * subtitle as WebVTT; or /subs?doc=<documentId>&ext=<srt|vtt> — an arbitrary
     * subtitle file the user picked from the share (see /subslist). SRT is converted
     * on the fly; browsers only take VTT tracks.
     */
    private fun serveSubtitle(session: IHTTPSession): Response {
        val doc = session.parameters["doc"]?.firstOrNull()
        if (!doc.isNullOrEmpty()) {
            val isVtt = session.parameters["ext"]?.firstOrNull()?.lowercase() == "vtt"
            return serveSubtitleDoc(doc, isVtt)
        }
        val n = session.parameters["n"]?.firstOrNull()?.toIntOrNull() ?: 0
        val id = session.parameters["id"]?.firstOrNull()?.toLongOrNull()
        val v = session.parameters["v"]?.firstOrNull()
        val sub = subtitlesFor(id, v).getOrNull(n)?.first
            ?: return text(Response.Status.NOT_FOUND, "No subtitles")
        return serveSubtitleDoc(sub.documentId, FileTypes.extensionOf(sub.name) == "vtt")
    }

    /**
     * Reads a subtitle document (restricted to the shared tree by [docUriFor], which
     * only resolves ids the persisted tree permission covers) and returns it as WebVTT.
     * SRT gets its comma timestamps rewritten to dots; VTT is passed through.
     */
    private fun serveSubtitleDoc(documentId: String, isVtt: Boolean): Response {
        return try {
            val input = context.contentResolver.openInputStream(docUriFor(documentId))
                ?: return text(Response.Status.NOT_FOUND, "No subtitles")
            val raw = input.use { it.readBytes() }
            if (raw.size > 2_000_000) return text(Response.Status.NOT_FOUND, "Subtitle too large")
            val content = String(raw, Charsets.UTF_8).removePrefix("\uFEFF")
            val vtt = if (isVtt) {
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

    /**
     * GET /subslist \u2014 every .srt/.vtt anywhere in the shared tree as JSON
     * [{"label":"Subs/movie.fr.srt","doc":"<documentId>","ext":"srt"}], so the player's
     * "Custom subtitle" picker can load one whose name/folder doesn't match the video.
     * Bounded (depth + count caps) so a huge share can't stall the request.
     */
    private fun subtitleListJson(): Response {
        val subs = allSubtitles()
        val sb = StringBuilder("[")
        subs.forEachIndexed { i, (relPath, documentId) ->
            if (i > 0) sb.append(",")
            sb.append("{\"label\":\"").append(jsonEscape(relPath))
                .append("\",\"doc\":\"").append(jsonEscape(documentId))
                .append("\",\"ext\":\"").append(FileTypes.extensionOf(relPath))
                .append("\"}")
        }
        sb.append("]")
        val res = newFixedLengthResponse(Response.Status.OK, "application/json", sb.toString())
        res.addHeader("Cache-Control", "no-store")
        return res
    }

    /**
     * Breadth-first walk of the shared tree collecting subtitle files, each paired with
     * its share-relative path (for a readable label). Caps keep a pathological library
     * (deeply nested / tens of thousands of files) from blocking the server thread.
     */
    private fun allSubtitles(): List<Pair<String, String>> {
        val root = rootDocId ?: return emptyList()
        val out = ArrayList<Pair<String, String>>()
        val queue = ArrayDeque<Pair<String, String>>() // (documentId, share-relative path)
        queue.add(root to "")
        var dirsVisited = 0
        while (queue.isNotEmpty() && out.size < MAX_SUBTITLE_FILES && dirsVisited < MAX_SUBTITLE_DIRS) {
            val (dirId, prefix) = queue.removeFirst()
            dirsVisited++
            val children = listChildren(dirId) ?: continue
            for (child in children) {
                val rel = if (prefix.isEmpty()) child.name else "$prefix/${child.name}"
                if (child.isDirectory) {
                    queue.add(child.documentId to rel)
                } else if (FileTypes.extensionOf(child.name) in setOf("srt", "vtt")) {
                    out.add(rel to child.documentId)
                    if (out.size >= MAX_SUBTITLE_FILES) break
                }
            }
        }
        return out.sortedBy { it.first.lowercase() }
    }

    // ---- MKV remux fallback ---------------------------------------------------

    private fun libraryItem(session: IHTTPSession): MediaItem? =
        session.parameters["id"]?.firstOrNull()?.toLongOrNull()?.let { library.getById(it) }

    /** GET /remux/start?id= — queue a lossless MKV→MP4 conversion (no-op if done/busy). */
    private fun remuxStart(session: IHTTPSession): Response {
        val item = libraryItem(session)
            ?: return text(Response.Status.NOT_FOUND, "Unknown media")
        RemuxController.start(context, item)
        return text(Response.Status.OK, "started")
    }

    /** GET /remux/status?id= — {"state":"none|working|ready|failed","pct":N}. */
    private fun remuxStatus(session: IHTTPSession): Response {
        val item = libraryItem(session)
            ?: return text(Response.Status.NOT_FOUND, "Unknown media")
        val s = RemuxController.status(context, item)
        val reasonJson = s.reason
            ?.let { ",\"reason\":\"${it.replace("\\", "").replace("\"", "'")}\"" } ?: ""
        val res = newFixedLengthResponse(
            Response.Status.OK, "application/json",
            "{\"state\":\"${s.state}\",\"pct\":${s.pct}$reasonJson}",
        )
        res.addHeader("Cache-Control", "no-cache")
        return res
    }

    /** GET /remux?id= — the converted MP4, with the same Range support as /media. */
    private fun serveRemux(session: IHTTPSession): Response {
        val item = libraryItem(session)
            ?: return text(Response.Status.NOT_FOUND, "Unknown media")
        val file = RemuxController.outputFor(context, item)
        if (!file.exists() || file.length() == 0L) {
            return text(Response.Status.NOT_FOUND, "Not remuxed")
        }
        return serveDocument(session, Uri.fromFile(file), item.title + ".mp4", file.length())
    }

    /**
     * GET /remote/events — Server-Sent Events stream carrying remote-control input from
     * the app (the phone acts as a D-pad for the browser showing this page).
     */
    private fun remoteEvents(): Response {
        val stream = RemoteStream()
        stream.offer(": connected\nretry: 3000\n\n".toByteArray(Charsets.UTF_8))
        remoteClients.add(stream)
        FileServerEvents.remoteClients(remoteClients.size)
        val res = newChunkedResponse(Response.Status.OK, "text/event-stream", stream)
        res.addHeader("Cache-Control", "no-cache")
        // NanoHTTPD auto-gzips text/* responses when the browser accepts gzip; the
        // compressor buffers small SSE events indefinitely, so they'd never arrive.
        res.setGzipEncoding(false)
        return res
    }

    /**
     * GET /remote/state — the TV player reports its playback position/duration/
     * volume so the phone remote's seekbar and volume slider can mirror it.
     * Params: t=currentTime(s), d=duration(s), p=paused(0/1), v=volume(0..1).
     */
    private fun remoteState(session: IHTTPSession): Response {
        val t = session.parameters["t"]?.firstOrNull()?.toDoubleOrNull() ?: 0.0
        val d = session.parameters["d"]?.firstOrNull()?.toDoubleOrNull() ?: 0.0
        val paused = session.parameters["p"]?.firstOrNull() == "1"
        val v = session.parameters["v"]?.firstOrNull()?.toDoubleOrNull() ?: 1.0
        FileServerEvents.playback((t * 1000).toLong(), (d * 1000).toLong(), paused, v)
        val res = newFixedLengthResponse(Response.Status.NO_CONTENT, "text/plain", "")
        res.addHeader("Cache-Control", "no-cache")
        return res
    }

    /** GET /icon.png — the app's launcher icon (brand header + favicon). */
    private fun serveIcon(): Response {
        val bytes = iconPngBytes
            ?: return text(Response.Status.NOT_FOUND, "No icon")
        val res = newFixedLengthResponse(
            Response.Status.OK, "image/png",
            java.io.ByteArrayInputStream(bytes), bytes.size.toLong(),
        )
        res.addHeader("Cache-Control", "max-age=86400")
        return res
    }

    /** GET /favicon.ico — the app's bundled favicon asset (used as the page icon). */
    private fun serveFavicon(): Response {
        return try {
            val bytes = context.assets
                .open("flutter_assets/assets/favicon.ico")
                .use { it.readBytes() }
            val res = newFixedLengthResponse(
                Response.Status.OK, "image/x-icon",
                java.io.ByteArrayInputStream(bytes), bytes.size.toLong(),
            )
            res.addHeader("Cache-Control", "max-age=86400")
            res
        } catch (e: Exception) {
            // Fall back to the generated launcher icon if the asset is missing.
            serveIcon()
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
            val limited = CountingInputStream(LimitedInputStream(input, contentLength), tracked = true)
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
            ?.let { CountingInputStream(it, tracked = true) }
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

    private fun htmlHead(title: String, showBrand: Boolean = true): String {
        val brand = if (showBrand) {
            "<div class='brand'><img class='brand-icon' src='/icon.png' alt=''>" +
                "<div>Arbiter <span>File Server</span></div></div>"
        } else {
            ""
        }
        return """
        <!doctype html><html lang='en'><head><meta charset='utf-8'>
        <meta name='viewport' content='width=device-width,initial-scale=1'>
        <link rel='icon' type='image/x-icon' href='/favicon.ico'>
        <title>$title · Arbiter File Server</title>
        <style>
          :root{--bg:#0f1216;--card:#181d24;--fg:#e7ecf2;--muted:#8a97a6;--accent:#4f9dff;--line:#232a33}
          *{box-sizing:border-box}
          body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 -apple-system,Segoe UI,Roboto,sans-serif}
          .wrap{max-width:980px;margin:0 auto;padding:0 16px 48px}
          .brand{max-width:980px;margin:0 auto;padding:18px 16px 0;font-size:20px;
                 font-weight:800;letter-spacing:.3px;display:flex;align-items:center;gap:10px}
          .brand span{color:var(--accent)}
          .brand-icon{width:28px;height:28px;border-radius:7px}
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
        </style></head><body>$brand
        """.trimIndent()
    }

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
          // Search filtering hides tiles; skip them when moving focus.
          function isVisible(t){ return t.style.display!=='none' && t.offsetParent!==null; }
          function activeActIndex(tile){
            var a=acts(tile);
            for(var i=0;i<a.length;i++) if(a[i].classList.contains('active')) return i;
            return 0;
          }
          function setActiveIndex(tile,i){
            var a=acts(tile);
            a.forEach(function(el){el.classList.remove('active');});
            if(a.length){ i=Math.max(0,Math.min(a.length-1,i)); a[i].classList.add('active'); }
          }
          // Number of columns = tiles sharing the first visible row's offsetTop. offsetTop
          // is layout-stable — unlike getBoundingClientRect it isn't perturbed by the focus
          // scale transform or a smooth scroll in flight.
          function colCount(){
            var vis=tiles.filter(isVisible);
            if(vis.length<2) return 1;
            var t0=vis[0].offsetTop, c=1;
            while(c<vis.length && vis[c].offsetTop===t0) c++;
            return c;
          }
          // Index of the tile one row above/below (dir -1/+1) in visible order, or -1 (no wrap).
          function rowMove(dir){
            var vis=tiles.filter(isVisible);
            var vp=vis.indexOf(tiles[idx]);
            if(vp<0) return -1;
            var np=vp+dir*colCount();
            if(np<0||np>=vis.length) return -1;
            return tiles.indexOf(vis[np]);
          }
          function focus(i,which){
            var n=tiles.length;
            var dir=(i>=idx)?1:-1;
            var j=((i%n)+n)%n, tries=0;
            while(!isVisible(tiles[j])&&tries<n){ j=(j+dir+n)%n; tries++; }
            idx=j;
            tiles.forEach(function(t){t.classList.remove('focused');});
            var t=tiles[idx];
            t.classList.add('focused');
            setActive(t,which||'view');
            t.scrollIntoView({block:'nearest',behavior:'smooth'});
          }
          function activate(){
            var t=tiles[idx];
            var a=t.querySelector('a.act.active')||t.querySelector('a.act');
            if(!a) return;
            // data-focus actions focus an element (e.g. the search box) instead of
            // navigating — this pops the TV's on-screen keyboard.
            var fid=a.getAttribute('data-focus');
            if(fid){
              var el=document.getElementById(fid);
              if(el){ el.focus(); if(el.select) el.select(); }
              return;
            }
            if(a.getAttribute('href')) location.href=a.getAttribute('href');
          }

          Array.prototype.slice.call(document.querySelectorAll('a.act[data-focus]'))
            .forEach(function(a){
              a.addEventListener('click',function(e){
                e.preventDefault();
                var el=document.getElementById(a.getAttribute('data-focus'));
                if(el) el.focus();
              });
            });

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

          // One logical-key handler shared by the DOM listener and the phone remote.
          function handleKey(k){
            switch(k){
              case 'right': focus(idx+1); return true;
              case 'left': focus(idx-1); return true;
              case 'up': {
                var t=tiles[idx], ai=activeActIndex(t);
                if(ai>0){ setActiveIndex(t,ai-1); }
                else { var pu=rowMove(-1); if(pu>=0){ focus(pu); setActiveIndex(tiles[pu],acts(tiles[pu]).length-1); } }
                return true;
              }
              case 'down': {
                var td=tiles[idx], ad=activeActIndex(td), na=acts(td).length;
                if(ad<na-1){ setActiveIndex(td,ad+1); }
                else { var pd=rowMove(1); if(pd>=0){ focus(pd); setActiveIndex(tiles[pd],0); } }
                return true;
              }
              case 'ok': activate(); return true;
              case 'back':
                var up=grid.getAttribute('data-up-href');
                if(up){location.href=up; return true;}
                return false;
            }
            return false;
          }
          window.__remoteKey=handleKey;

          document.addEventListener('keydown',function(e){
            var tag=(e.target||{}).tagName;
            if(tag==='INPUT'||tag==='TEXTAREA'||tag==='SELECT') return;
            if(handleKey(keyOf(e))) e.preventDefault();
          });

          focus(initialIndex());
        })();
        </script>
    """.trimIndent()

    /**
     * Subscribes the page to /remote/events so the app's remote panel can drive it.
     * Messages are logical keys fed to the page's own handler (window.__remoteKey) or
     * "text:…" search input (window.__remoteText). Reconnects after drops.
     */
    private fun remoteScript(): String = """
        <script>
        (function(){
          if(!window.EventSource) return;
          function connect(){
            var es=new EventSource('/remote/events');
            es.onmessage=function(ev){
              var d=ev.data||'';
              if(d.indexOf('text:')===0){
                if(window.__remoteText) window.__remoteText(d.substring(5));
                return;
              }
              if(d.indexOf('seek:')===0){
                if(window.__remoteSeek) window.__remoteSeek(d.substring(5));
                return;
              }
              if(d.indexOf('vol:')===0){
                if(window.__remoteVol) window.__remoteVol(d.substring(4));
                return;
              }
              if(window.__remoteKey) window.__remoteKey(d);
            };
            es.onerror=function(){ es.close(); setTimeout(connect,3000); };
          }
          connect();
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

    /** Escapes a string for embedding inside a JSON string literal (see /subslist). */
    private fun jsonEscape(s: String): String {
        val sb = StringBuilder(s.length + 8)
        for (c in s) {
            when (c) {
                '\\' -> sb.append("\\\\")
                '"' -> sb.append("\\\"")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else -> if (c < ' ') sb.append("\\u%04x".format(c.code)) else sb.append(c)
            }
        }
        return sb.toString()
    }

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
