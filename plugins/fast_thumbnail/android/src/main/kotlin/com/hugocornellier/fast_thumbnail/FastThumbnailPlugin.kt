package com.hugocornellier.fast_thumbnail

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileOutputStream
import java.util.concurrent.Executors

class FastThumbnailPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val executor = Executors.newSingleThreadExecutor()
    private lateinit var mainHandler: android.os.Handler

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "fast_thumbnail")
        channel.setMethodCallHandler(this)
        mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "generate") {
            result.notImplemented()
            return
        }

        val inputPath = call.argument<String>("inputPath") ?: run { result.error("INVALID_ARGS", "Missing inputPath", null); return }
        val outputPath = call.argument<String>("outputPath") ?: run { result.error("INVALID_ARGS", "Missing outputPath", null); return }
        val maxWidth = call.argument<Int>("maxWidth") ?: 500
        val quality = call.argument<Int>("quality") ?: 90

        executor.execute {
            val generateResult = generateThumbnail(inputPath, outputPath, maxWidth, quality)
            mainHandler.post {
                if (generateResult != null) {
                    result.success(generateResult)
                } else {
                    result.success(null)
                }
            }
        }
    }

    private fun generateThumbnail(inputPath: String, outputPath: String, maxWidth: Int, quality: Int): Map<String, Int>? {
        try {
            // Probe dimensions without decoding pixels
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(inputPath, options)
            if (options.outWidth <= 0 || options.outHeight <= 0) return null

            // Read EXIF orientation
            val exif = ExifInterface(inputPath)
            val exifOrientation = exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)

            // Calculate original dimensions after EXIF rotation
            val isRotated = exifOrientation == ExifInterface.ORIENTATION_ROTATE_90 ||
                    exifOrientation == ExifInterface.ORIENTATION_ROTATE_270 ||
                    exifOrientation == ExifInterface.ORIENTATION_TRANSVERSE ||
                    exifOrientation == ExifInterface.ORIENTATION_TRANSPOSE
            val originalWidth = if (isRotated) options.outHeight else options.outWidth
            val originalHeight = if (isRotated) options.outWidth else options.outHeight

            // Calculate inSampleSize for subsampled decode
            val sampleSize = calculateSampleSize(options.outWidth, options.outHeight, maxWidth)
            val decodeOptions = BitmapFactory.Options().apply { inSampleSize = sampleSize }
            var bitmap = BitmapFactory.decodeFile(inputPath, decodeOptions) ?: return null

            // Apply EXIF orientation
            val matrix = Matrix()
            when (exifOrientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.postRotate(90f); matrix.preScale(-1f, 1f) }
                ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.postRotate(270f); matrix.preScale(-1f, 1f) }
            }
            if (exifOrientation != ExifInterface.ORIENTATION_NORMAL && exifOrientation != ExifInterface.ORIENTATION_UNDEFINED) {
                val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                if (rotated != bitmap) bitmap.recycle()
                bitmap = rotated
            }

            // Scale to target width
            val scale = maxWidth.toFloat() / bitmap.width.toFloat()
            if (scale < 1f) {
                val scaledHeight = (bitmap.height * scale).toInt()
                val scaled = Bitmap.createScaledBitmap(bitmap, maxWidth, scaledHeight, true)
                if (scaled != bitmap) bitmap.recycle()
                bitmap = scaled
            }

            // Write JPEG
            FileOutputStream(outputPath).use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
            }
            bitmap.recycle()

            return mapOf(
                "originalWidth" to originalWidth,
                "originalHeight" to originalHeight,
            )
        } catch (e: Exception) {
            return null
        }
    }

    private fun calculateSampleSize(width: Int, height: Int, targetWidth: Int): Int {
        var sampleSize = 1
        while (width / (sampleSize * 2) >= targetWidth) {
            sampleSize *= 2
        }
        return sampleSize
    }
}
