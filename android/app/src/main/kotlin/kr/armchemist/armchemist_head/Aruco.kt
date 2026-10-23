package kr.armchemist.armchemist_head

import org.opencv.android.OpenCVLoader
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.objdetect.ArucoDetector
import org.opencv.objdetect.DetectorParameters
import org.opencv.objdetect.Objdetect
import kotlin.math.hypot

/// 카메라 NV21 프레임에서 ArUco 마커를 찾는다. 중앙 서버(central/aruco.py)와 같은 DICT_4X4_50.
/// 서버는 축소된 JPEG 에서 찾지만, 여기서는 카메라 원본 해상도의 Y(밝기) 평면을 그대로 쓴다.
/// 한 스레드에서만 부른다 (ArucoDetector 는 스레드 안전하지 않다).
class Aruco {
    private val detector by lazy {
        check(OpenCVLoader.initLocal()) { "OpenCV 로드 실패" }
        ArucoDetector(Objdetect.getPredefinedDictionary(Objdetect.DICT_4X4_50), DetectorParameters())
    }

    /// 결과 좌표는 회전 보정된 이미지 기준 0~1 정규화 (서버로 보내는 JPEG 과 같은 기준, 미러 아님).
    /// corners 는 마커마다 [x0, y0, x1, y1, x2, y2, x3, y3] (왼쪽 위부터 시계 방향, OpenCV 순서).
    fun detect(nv21: ByteArray, w: Int, h: Int, rotation: Int): Map<String, Any> {
        val t = System.nanoTime()
        val det = detector // 처음 부를 때 OpenCV 네이티브 라이브러리를 로드한다. Mat 보다 먼저여야 한다.
        val raw = Mat(h, w, CvType.CV_8UC1)
        raw.put(0, 0, nv21, 0, w * h) // NV21 앞부분 w*h 바이트가 Y 평면 = 그레이스케일
        val gray = when (rotation) {
            90 -> Mat().also { Core.rotate(raw, it, Core.ROTATE_90_CLOCKWISE) }
            180 -> Mat().also { Core.rotate(raw, it, Core.ROTATE_180) }
            270 -> Mat().also { Core.rotate(raw, it, Core.ROTATE_90_COUNTERCLOCKWISE) }
            else -> raw
        }
        val gw = gray.cols().toDouble()
        val gh = gray.rows().toDouble()
        val corners = ArrayList<Mat>()
        val ids = Mat()
        det.detectMarkers(gray, corners, ids)

        val markers = corners.mapIndexed { i, c ->
            val p = FloatArray(8)
            c.get(0, 0, p)
            var side = 0.0
            for (k in 0 until 4) {
                val n = (k + 1) % 4
                side += hypot((p[2 * n] - p[2 * k]).toDouble(), (p[2 * n + 1] - p[2 * k + 1]).toDouble())
            }
            mapOf(
                "id" to ids.get(i, 0)[0].toInt(),
                "corners" to List(8) { k -> p[k] / if (k % 2 == 0) gw else gh },
                "side_px" to side / 4,
            )
        }.sortedByDescending { it["side_px"] as Double }

        corners.forEach { it.release() }
        ids.release()
        if (gray !== raw) gray.release()
        raw.release()
        return mapOf(
            "markers" to markers,
            "width" to gw.toInt(),
            "height" to gh.toInt(),
            "ms" to (System.nanoTime() - t) / 1e6,
        )
    }
}
