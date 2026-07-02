package auravation.arbiter.mock_server

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import fi.iki.elonen.NanoHTTPD
import java.io.FilterInputStream
import java.io.InputStream
import java.net.URLDecoder
import java.net.URLEncoder

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

    /** DocumentFile for the shared root; null if the persisted permission was lost. */
    private val root: DocumentFile? = DocumentFile.fromTreeUri(context, rootUri)

    /** Scanned-media store, backing the /thumb and /library routes. */
    private val library: LibraryDatabase by lazy { LibraryDatabase(context) }

    /** Requests served since this server instance started (surfaced to the UI). */
    private val requestCounter = java.util.concurrent.atomic.AtomicInteger(0)

    override fun serve(session: IHTTPSession): Response {
        FileServerEvents.requestCount(requestCounter.incrementAndGet())
        return try {
            when {
                session.method != Method.GET && session.method != Method.HEAD ->
                    text(Response.Status.METHOD_NOT_ALLOWED, "Only GET/HEAD are supported")
                root == null || !root.isDirectory ->
                    text(
                        Response.Status.INTERNAL_ERROR,
                        "Shared folder is unavailable. Re-pick it in the app.",
                    )
                else -> route(session)
            }
        } catch (e: Exception) {
            text(Response.Status.INTERNAL_ERROR, "Server error: ${e.message}")
        }
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
            else -> text(Response.Status.NOT_FOUND, "Not found")
        }
    }

    // ---- Directory listing (T5) ---------------------------------------------

    private fun listDirectory(segments: List<String>): Response {
        val dir = resolveDir(segments)
            ?: return text(Response.Status.NOT_FOUND, "Folder not found")

        val children = dir.listFiles()
        val folders = children.filter { it.isDirectory }
            .sortedBy { (it.name ?: "").lowercase() }
        val files = children.filter { it.isFile }
            .sortedBy { (it.name ?: "").lowercase() }

        val title = if (segments.isEmpty()) (root?.name ?: "Shared") else segments.last()
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
            val name = f.name ?: continue
            val href = "/files/" + basePath + encode(name) + "/"
            sb.append(tile(mediaIcon = FileTypes.iconFor(name, true), name = name, meta = "Folder"))
            sb.append(actionRow(viewHref = href, viewLabel = "📂 Open", dlHref = null))
            sb.append("</div>")
        }

        for (f in files) {
            val name = f.name ?: continue
            val rawHref = "/raw/" + basePath + encode(name)
            val meta = "${FileTypes.humanSize(f.length())} · ${FileTypes.formatDate(f.lastModified())}"
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
        if (id != null) {
            val item = library.getById(id)
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
        }
        val isVideo = mime.startsWith("video/")
        val srcAttr = escape(src)
        val dlHref = escape(appendParam(src, "dl", "1"))

        // Native controls are omitted on purpose — TV browsers don't expose them to a
        // D-pad remote. Custom, focusable controls are driven by the script below.
        val mediaEl = if (isVideo) {
            "<video id='media' autoplay playsinline><source src='$srcAttr' type='${escape(mime)}'>" +
                "Your browser cannot play this video.</video>"
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
        sb.append("<div class='pbar' id='pbar'>")
        sb.append("<button class='pctl' data-act='back' title='Back'>←</button>")
        sb.append("<button class='pctl play' data-act='play' title='Play/Pause'>⏸</button>")
        sb.append("<div class='pctl seek' data-act='seek'><div class='seek-fill' id='seekfill'></div></div>")
        sb.append("<span class='ptime' id='ptime'>0:00 / 0:00</span>")
        sb.append("<button class='pctl' data-act='fs' title='Fullscreen'>⛶</button>")
        sb.append("<a class='pctl' data-act='download' href='$dlHref' title='Download'>⬇</a>")
        sb.append("</div>")
        sb.append("<div class='ptitle' id='ptitle'>${escape(name)}</div>")
        sb.append("</div>")
        sb.append(playerStyles())
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
          .pctl.seek{flex:1;min-width:60px;height:12px;padding:0;overflow:hidden;
                background:rgba(255,255,255,.25)}
          .pctl.seek.focused{height:18px;border-color:var(--accent);background:rgba(255,255,255,.25)}
          .seek-fill{height:100%;width:0;background:var(--accent)}
          .ptime{color:#fff;font-size:13px;white-space:nowrap;font-variant-numeric:tabular-nums}
          .ptitle{position:absolute;top:0;left:0;right:0;padding:14px 18px;color:#fff;font-size:15px;
                  font-weight:600;background:linear-gradient(rgba(0,0,0,.85),transparent);
                  transition:opacity .25s ease;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
          .ptitle.hidden{opacity:0}
        </style>
    """.trimIndent()

    /** Custom D-pad player: OK=play/pause, ←/→=seek 10s, ↑/↓ move controls, Back=exit. */
    private fun playerScript(): String = """
        <script>
        (function(){
          var media=document.getElementById('media');
          var pbar=document.getElementById('pbar');
          var ptitle=document.getElementById('ptitle');
          var playBtn=pbar.querySelector('.pctl.play');
          var fill=document.getElementById('seekfill');
          var timeEl=document.getElementById('ptime');
          var ctrls=Array.prototype.slice.call(pbar.querySelectorAll('.pctl'));
          var ci=1; // default focus = play/pause
          var hideTimer=null;

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
          function seekBy(d){ var dur=media.duration||1e9; media.currentTime=Math.min(dur,Math.max(0,media.currentTime+d)); }
          function onSeek(){ return ctrls[ci].getAttribute('data-act')==='seek'; }
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
            if(act==='play'||act==='seek') toggle();
            else if(act==='back') history.back();
            else if(act==='fs') toggleFullscreen();
            else if(act==='download') location.href=ctrls[ci].getAttribute('href');
          }
          function showControls(){
            pbar.classList.remove('hidden'); ptitle.classList.remove('hidden');
            if(hideTimer) clearTimeout(hideTimer);
            hideTimer=setTimeout(function(){
              if(!media.paused){pbar.classList.add('hidden'); ptitle.classList.add('hidden');}
            },3000);
          }

          media.addEventListener('play',function(){playBtn.textContent='⏸';showControls();});
          media.addEventListener('pause',function(){playBtn.textContent='▶';showControls();});
          media.addEventListener('timeupdate',function(){
            var d=media.duration||0;
            fill.style.width=(d?(media.currentTime/d*100):0)+'%';
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
                java.io.FileInputStream(file), file.length(),
            )
            res.addHeader("Cache-Control", "max-age=86400")
            res
        } catch (e: Exception) {
            placeholderThumb()
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
        val file = resolveFile(segments)
            ?: return text(Response.Status.NOT_FOUND, "File not found")
        val name = file.name ?: segments.last()
        return serveDocument(session, file.uri, name, file.length())
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
        val doc = DocumentFile.fromSingleUri(context, uri)
        val name = doc?.name ?: item.title
        val length = doc?.length() ?: -1L
        return serveDocument(session, uri, name, length)
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

        // Range request → 206 Partial Content with only the requested window.
        if (rangeHeader != null && rangeHeader.startsWith("bytes=") && totalLength > 0) {
            val (start, end) = parseRange(rangeHeader, totalLength)
                ?: return rangeNotSatisfiable(totalLength)
            val contentLength = end - start + 1
            val input = context.contentResolver.openInputStream(fileUri)
                ?: return text(Response.Status.INTERNAL_ERROR, "Cannot open file")
            val limited = LimitedInputStream(input, start, contentLength)
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

    private fun resolveDir(segments: List<String>): DocumentFile? {
        var current = root ?: return null
        for (seg in segments) {
            if (seg.isEmpty()) continue
            current = current.findFile(seg)?.takeIf { it.isDirectory } ?: return null
        }
        return current
    }

    private fun resolveFile(segments: List<String>): DocumentFile? {
        if (segments.isEmpty()) return null
        val parent = resolveDir(segments.dropLast(1)) ?: return null
        return parent.findFile(segments.last())?.takeIf { it.isFile }
    }

    private fun splitPath(raw: String): List<String> =
        raw.split("/").filter { it.isNotEmpty() }.map { decode(it) }

    // ---- HTML/response helpers ----------------------------------------------

    private fun breadcrumbs(segments: List<String>): String {
        val sb = StringBuilder("<nav class='crumbs'>")
        sb.append("<a href='/library'>🎬 Library</a> <span class='sep'>·</span> ")
        sb.append("<a href='/files/'>🏠 ${escape(root?.name ?: "Shared")}</a>")
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
     * Wraps a SAF input stream to expose only the bytes of a requested Range: skips to
     * [start] on construction and refuses to read past [remaining] bytes. SAF streams are
     * not seekable, so this uses skip() — acceptable for typical media, though very large
     * files with frequent seeks may re-open and skip repeatedly (edge case in the plan).
     */
    private class LimitedInputStream(
        source: InputStream,
        start: Long,
        private var remaining: Long,
    ) : FilterInputStream(source) {

        init {
            var toSkip = start
            while (toSkip > 0) {
                val skipped = source.skip(toSkip)
                if (skipped <= 0) {
                    // skip() can return 0 before EOF; fall back to reading and discarding.
                    if (source.read() < 0) break
                    toSkip--
                } else {
                    toSkip -= skipped
                }
            }
        }

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
