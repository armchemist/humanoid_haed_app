package kr.armchemist.armchemist_head

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 로봇 얼굴이므로 화면이 꺼지지 않게 한다.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 카메라 NV21 프레임 -> JPEG. Android 내장 YuvImage 를 써서 Dart 에서 픽셀을 돌리지 않는다.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "armchemist/jpeg")
            .setMethodCallHandler { call, result ->
                val nv21 = call.argument<ByteArray>("nv21")!!
                val w = call.argument<Int>("width")!!
                val h = call.argument<Int>("height")!!
                val rotation = call.argument<Int>("rotation")!!
                val maxSide = call.argument<Int>("maxSide")!!
                val quality = call.argument<Int>("quality")!!
                Thread {
                    try {
                        val jpeg = encode(nv21, w, h, rotation, maxSide, quality)
                        runOnUiThread { result.success(jpeg) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("jpeg", e.toString(), null) }
                    }
                }.start()
            }
    }

    private fun encode(nv21: ByteArray, w: Int, h: Int, rotation: Int, maxSide: Int, quality: Int): ByteArray {
        val out = ByteArrayOutputStream()
        val scale = minOf(1f, maxSide.toFloat() / maxOf(w, h))
        if (rotation == 0 && scale == 1f) {
            YuvImage(nv21, ImageFormat.NV21, w, h, null).compressToJpeg(Rect(0, 0, w, h), quality, out)
            return out.toByteArray()
        }
        // 회전/축소가 필요하면 한 번 디코드해서 Bitmap 으로 변환 후 다시 압축한다.
        YuvImage(nv21, ImageFormat.NV21, w, h, null).compressToJpeg(Rect(0, 0, w, h), 95, out)
        val src = BitmapFactory.decodeByteArray(out.toByteArray(), 0, out.size())
        val m = Matrix().apply {
            postScale(scale, scale)
            postRotate(rotation.toFloat())
        }
        val dst = Bitmap.createBitmap(src, 0, 0, w, h, m, true)
        out.reset()
        dst.compress(Bitmap.CompressFormat.JPEG, quality, out)
        src.recycle()
        if (dst !== src) dst.recycle()
        return out.toByteArray()
    }
}
