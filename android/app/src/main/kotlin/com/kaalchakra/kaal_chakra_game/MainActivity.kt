package com.kaalchakra.kaal_chakra_game

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * A tiny sound-effect channel backed directly by Android's [SoundPool].
 *
 * The game synthesises its effects as WAV bytes. Instead of routing every
 * sound through a full media player (which re-prepares per play and stalls
 * the frame when a realm passes) the bytes are written to a cache file once,
 * decoded by the SoundPool on its own thread, and every later play is a
 * single cheap stream start — no waiting on the platform main thread.
 *
 * [SoundPool] needs API 21+, which is the project minimum, so the Builder
 * path is used unconditionally.
 */
class SoundEffects private constructor() {

    companion object {
        const val CHANNEL = "kaalchakra/sound_effects"
        private const val MAX_STREAMS = 8

        @Volatile
        private var instance: SoundEffects? = null

        fun attach(flutterEngine: FlutterEngine, context: Context) {
            val effects = instance ?: SoundEffects().also { instance = it }
            effects.attachTo(flutterEngine, context)
        }

        /** Frees the pool when the Flutter engine detaches (activity teardown). */
        fun release() {
            val effects = instance ?: return
            synchronized(effects) {
                if (effects::soundPool.isInitialized) {
                    effects.soundPool.release()
                }
                effects.sounds.clear()
                effects.loadedIds.clear()
                effects.loadLatches.clear()
            }
            instance = null
        }
    }

    private val loadExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val sounds = ConcurrentHashMap<String, Int>()
    private val loadedIds: MutableSet<Int> = ConcurrentHashMap.newKeySet()
    private val loadLatches = ConcurrentHashMap<Int, CountDownLatch>()

    private lateinit var cacheDir: File
    private lateinit var soundPool: SoundPool

    private fun newPool(): SoundPool {
        val pool = SoundPool.Builder()
            .setMaxStreams(MAX_STREAMS)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            .build()
        pool.setOnLoadCompleteListener { _, sampleId, status ->
            if (status == 0) loadedIds.add(sampleId)
            loadLatches.remove(sampleId)?.countDown()
        }
        return pool
    }

    fun attachTo(flutterEngine: FlutterEngine, context: Context) {
        cacheDir = context.cacheDir
        soundPool = newPool()
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "load" -> {
                    val key = call.argument<String>("key") ?: ""
                    val bytes = call.argument<ByteArray>("bytes")
                    if (key.isEmpty() || bytes == null) {
                        result.error("badArgs", "key and bytes are required", null)
                        return@setMethodCallHandler
                    }
                    val existing = sounds[key]
                    if (existing != null) {
                        result.success(existing)
                        return@setMethodCallHandler
                    }
                    loadExecutor.execute {
                        try {
                            val id = loadFromBytes(key, bytes)
                            mainHandler.post { result.success(id) }
                        } catch (t: Throwable) {
                            mainHandler.post { result.error("loadFailed", t.message, null) }
                        }
                    }
                }
                "play" -> {
                    val soundId = call.argument<Int>("soundId") ?: 0
                    val volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
                    val loop = call.argument<Boolean>("loop") ?: false
                    if (soundId > 0 && loadedIds.contains(soundId)) {
                        val streamId = soundPool.play(
                            soundId, volume, volume, 1, if (loop) -1 else 0, 1.0f,
                        )
                        result.success(streamId)
                    } else {
                        result.success(0)
                    }
                }
                "stop" -> {
                    val streamId = call.argument<Int>("streamId") ?: 0
                    if (streamId > 0) soundPool.stop(streamId)
                    result.success(null)
                }
                "release" -> {
                    sounds.clear()
                    loadedIds.clear()
                    loadLatches.clear()
                    soundPool.release()
                    soundPool = newPool()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Writes [bytes] to a cache file and decodes it, waiting until it plays. */
    private fun loadFromBytes(key: String, bytes: ByteArray): Int {
        val file = File.createTempFile("sfx_", ".wav", cacheDir)
        FileOutputStream(file).use { it.write(bytes) }
        file.deleteOnExit()

        // Register the latch before loading so the completion callback can
        // never fire between the load call and the wait.
        val latch = CountDownLatch(1)
        val id = soundPool.load(file.absolutePath, 1)
        if (id <= 0) return 0
        loadLatches[id] = latch
        if (!loadedIds.contains(id)) {
            // Off the main thread, so waiting here is harmless — and it only
            // happens once per sound for the lifetime of the app.
            latch.await(2, TimeUnit.SECONDS)
        }
        loadLatches.remove(id)
        sounds[key] = id
        return id
    }
}

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SoundEffects.attach(flutterEngine, applicationContext)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        SoundEffects.release()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
