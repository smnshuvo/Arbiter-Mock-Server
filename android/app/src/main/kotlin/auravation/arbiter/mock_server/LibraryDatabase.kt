package auravation.arbiter.mock_server

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/** A scanned media file with its extracted metadata. */
data class MediaItem(
    val id: Long,
    val filePath: String,
    val title: String,
    val durationMs: Long,
    val width: Int,
    val height: Int,
    val mimeType: String,
    val thumbnailPath: String?,
    val lastModified: Long,
    val addedAt: Long,
    val storyboardPath: String? = null,
    val storyboardFrames: Int = 0,
    val storyboardIntervalMs: Long = 0,
    val storyboardCols: Int = 0,
)

/**
 * SQLite store for scanned media metadata (native, separate from the app's Dart sqflite
 * DB — the two are intentionally distinct). Backs the library grid so it renders without
 * re-scanning the filesystem on every request.
 */
class LibraryDatabase(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DB_NAME, null, DB_VERSION) {

    companion object {
        private const val DB_NAME = "file_server_library.db"
        private const val DB_VERSION = 2
        const val TABLE = "media_items"

        private const val COL_ID = "id"
        private const val COL_PATH = "file_path"
        private const val COL_TITLE = "title"
        private const val COL_DURATION = "duration_ms"
        private const val COL_WIDTH = "width"
        private const val COL_HEIGHT = "height"
        private const val COL_MIME = "mime_type"
        private const val COL_THUMB = "thumbnail_path"
        private const val COL_MODIFIED = "last_modified"
        private const val COL_ADDED = "added_at"
        private const val COL_SB_PATH = "storyboard_path"
        private const val COL_SB_FRAMES = "storyboard_frames"
        private const val COL_SB_INTERVAL = "storyboard_interval_ms"
        private const val COL_SB_COLS = "storyboard_cols"
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE $TABLE (
              $COL_ID INTEGER PRIMARY KEY AUTOINCREMENT,
              $COL_PATH TEXT UNIQUE NOT NULL,
              $COL_TITLE TEXT,
              $COL_DURATION INTEGER,
              $COL_WIDTH INTEGER,
              $COL_HEIGHT INTEGER,
              $COL_MIME TEXT,
              $COL_THUMB TEXT,
              $COL_MODIFIED INTEGER,
              $COL_ADDED INTEGER,
              $COL_SB_PATH TEXT,
              $COL_SB_FRAMES INTEGER DEFAULT 0,
              $COL_SB_INTERVAL INTEGER DEFAULT 0,
              $COL_SB_COLS INTEGER DEFAULT 0
            )
            """.trimIndent(),
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            db.execSQL("ALTER TABLE $TABLE ADD COLUMN $COL_SB_PATH TEXT")
            db.execSQL("ALTER TABLE $TABLE ADD COLUMN $COL_SB_FRAMES INTEGER DEFAULT 0")
            db.execSQL("ALTER TABLE $TABLE ADD COLUMN $COL_SB_INTERVAL INTEGER DEFAULT 0")
            db.execSQL("ALTER TABLE $TABLE ADD COLUMN $COL_SB_COLS INTEGER DEFAULT 0")
        }
    }

    /** Returns the row id for a path, or null if unknown. */
    private fun idForPath(filePath: String): Long? {
        readableDatabase.query(
            TABLE, arrayOf(COL_ID), "$COL_PATH = ?", arrayOf(filePath),
            null, null, null,
        ).use { c ->
            return if (c.moveToFirst()) c.getLong(0) else null
        }
    }

    /** Returns last_modified for an existing row, or null if the path is unknown. */
    fun lastModifiedFor(filePath: String): Long? {
        readableDatabase.query(
            TABLE, arrayOf(COL_MODIFIED), "$COL_PATH = ?", arrayOf(filePath),
            null, null, null,
        ).use { c ->
            return if (c.moveToFirst()) c.getLong(0) else null
        }
    }

    fun upsert(item: MediaItem) {
        // Reuse the existing row id if this path is already known. Without this,
        // CONFLICT_REPLACE deletes + re-inserts and AUTOINCREMENT hands out a NEW id
        // on every rescan, breaking any /media?id= or /player?id= URL already in use.
        val existingId = idForPath(item.filePath)
        val values = ContentValues().apply {
            if (existingId != null) put(COL_ID, existingId)
            put(COL_PATH, item.filePath)
            put(COL_TITLE, item.title)
            put(COL_DURATION, item.durationMs)
            put(COL_WIDTH, item.width)
            put(COL_HEIGHT, item.height)
            put(COL_MIME, item.mimeType)
            put(COL_THUMB, item.thumbnailPath)
            put(COL_MODIFIED, item.lastModified)
            put(COL_ADDED, item.addedAt)
            put(COL_SB_PATH, item.storyboardPath)
            put(COL_SB_FRAMES, item.storyboardFrames)
            put(COL_SB_INTERVAL, item.storyboardIntervalMs)
            put(COL_SB_COLS, item.storyboardCols)
        }
        // UNIQUE(file_path) makes this an upsert via CONFLICT_REPLACE.
        writableDatabase.insertWithOnConflict(
            TABLE, null, values, SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    fun getById(id: Long): MediaItem? {
        readableDatabase.query(
            TABLE, null, "$COL_ID = ?", arrayOf(id.toString()), null, null, null,
        ).use { c -> return if (c.moveToFirst()) c.toMediaItem() else null }
    }

    fun getByPath(filePath: String): MediaItem? {
        readableDatabase.query(
            TABLE, null, "$COL_PATH = ?", arrayOf(filePath), null, null, null,
        ).use { c -> return if (c.moveToFirst()) c.toMediaItem() else null }
    }

    /** Attaches a generated storyboard to an existing row (backfill after incremental scans). */
    fun updateStoryboard(id: Long, path: String, frames: Int, intervalMs: Long, cols: Int) {
        val values = ContentValues().apply {
            put(COL_SB_PATH, path)
            put(COL_SB_FRAMES, frames)
            put(COL_SB_INTERVAL, intervalMs)
            put(COL_SB_COLS, cols)
        }
        writableDatabase.update(TABLE, values, "$COL_ID = ?", arrayOf(id.toString()))
    }

    /** All items, newest first, optionally filtered by a title LIKE query. */
    fun getAll(query: String? = null): List<MediaItem> {
        val selection = if (query.isNullOrBlank()) null else "$COL_TITLE LIKE ?"
        val args = if (query.isNullOrBlank()) null else arrayOf("%$query%")
        val out = ArrayList<MediaItem>()
        readableDatabase.query(
            TABLE, null, selection, args, null, null, "$COL_ADDED DESC",
        ).use { c ->
            while (c.moveToNext()) out.add(c.toMediaItem())
        }
        return out
    }

    /** Every file path currently stored — used to prune rows for deleted files. */
    fun allPaths(): Set<String> {
        val out = HashSet<String>()
        readableDatabase.query(TABLE, arrayOf(COL_PATH), null, null, null, null, null).use { c ->
            while (c.moveToNext()) out.add(c.getString(0))
        }
        return out
    }

    fun deleteByPath(filePath: String) {
        writableDatabase.delete(TABLE, "$COL_PATH = ?", arrayOf(filePath))
    }

    fun count(): Int {
        readableDatabase.rawQuery("SELECT COUNT(*) FROM $TABLE", null).use { c ->
            return if (c.moveToFirst()) c.getInt(0) else 0
        }
    }

    private fun android.database.Cursor.toMediaItem(): MediaItem = MediaItem(
        id = getLong(getColumnIndexOrThrow(COL_ID)),
        filePath = getString(getColumnIndexOrThrow(COL_PATH)),
        title = getString(getColumnIndexOrThrow(COL_TITLE)) ?: "",
        durationMs = getLong(getColumnIndexOrThrow(COL_DURATION)),
        width = getInt(getColumnIndexOrThrow(COL_WIDTH)),
        height = getInt(getColumnIndexOrThrow(COL_HEIGHT)),
        mimeType = getString(getColumnIndexOrThrow(COL_MIME)) ?: "application/octet-stream",
        thumbnailPath = getString(getColumnIndexOrThrow(COL_THUMB)),
        lastModified = getLong(getColumnIndexOrThrow(COL_MODIFIED)),
        addedAt = getLong(getColumnIndexOrThrow(COL_ADDED)),
        storyboardPath = getString(getColumnIndexOrThrow(COL_SB_PATH)),
        storyboardFrames = getInt(getColumnIndexOrThrow(COL_SB_FRAMES)),
        storyboardIntervalMs = getLong(getColumnIndexOrThrow(COL_SB_INTERVAL)),
        storyboardCols = getInt(getColumnIndexOrThrow(COL_SB_COLS)),
    )
}
