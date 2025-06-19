from bisect import bisect_left, bisect_right
import numpy as np
from PIL import Image, ImageDraw
from typing import Sequence, Tuple

print("[LOG] Importing .fdlite files... This may take a moment.")

from fdlite.face_detection import FaceDetection, FaceDetectionModel
from fdlite.face_landmark import FaceLandmark, face_detection_to_roi
from fdlite.iris_landmark import IrisLandmark, IrisResults, iris_roi_from_face_landmarks

print("[LOG] .fdlite files imported successfully.")

from fdlite.transform import bbox_from_landmarks
from src.point import Point

_Point = Tuple[int, int]
_Size = Tuple[int, int]
_Rect = Tuple[int, int, int, int]


def _is_below_segment(A: _Point, B: _Point, C: _Point, mid: int) -> bool:
    dx, dy = B[0] - A[0], B[1] - A[1]
    if not dx:
        return A[1] <= C[1] <= B[1]

    m = dy / dx
    y = (C[0] - A[0]) / dx * m + A[1]
    sign = -1 if A[1] > mid else 1

    return sign * (C[1] - y) > 0


def _find_contour_segment(contour: Sequence[_Point], point: _Point) -> Tuple[_Point, _Point]:
    def distance(a: _Point, b: _Point) -> int:
        return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2

    MAX_IDX = len(contour) - 1
    left_idx = max(bisect_left(contour, point) - 1, 0)
    right_idx = min(bisect_right(contour, point), MAX_IDX)

    while left_idx > 0 and distance(point, contour[left_idx]) > distance(point, contour[left_idx - 1]):
        left_idx -= 1

    while right_idx < MAX_IDX and distance(point, contour[right_idx]) > distance(point, contour[right_idx + 1]):
        right_idx += 1

    return contour[left_idx], contour[right_idx]


def _get_iris_location(results: IrisResults, image_size: _Size) -> Tuple[_Rect, _Size]:
    bbox = bbox_from_landmarks(results.iris).absolute(image_size)
    width, height = int(bbox.width + 1), int(bbox.height + 1)
    left, top = int(bbox.xmin), int(bbox.ymin)
    location = (left, top, left + width, top + height)

    return location, (width, height)


def _get_iris_mask(
    results: IrisResults,
    iris_location: _Rect,
    iris_size: _Size,
    image_size: _Size
) -> Image.Image:
    left, top, _, bottom = iris_location
    iris_width, iris_height = iris_size
    img_width, img_height = image_size

    eyeball_sorted = sorted([
        (int(pt.x * img_width), int(pt.y * img_height))
        for pt in results.eyeball_contour
    ])
    bbox = bbox_from_landmarks(results.eyeball_contour).absolute(image_size)
    x_ofs, y_ofs = left, top
    y_start = int(max(bbox.ymin, top))
    y_end = int(min(bbox.ymax, bottom))
    mask = np.zeros((iris_height, iris_width), dtype=np.uint8)

    a, b = iris_width // 2, iris_height // 2
    cx, cy = left + a, top + b
    box_center_y = int(bbox.ymin + bbox.ymax) // 2
    b_sqr = b ** 2

    for y in range(y_start, y_end):
        x = int(a * np.sqrt(b_sqr - (y - cy) ** 2) / b)
        x0, x1 = cx - x, cx + x

        A, B = _find_contour_segment(eyeball_sorted, (x0, y))
        left_inside = _is_below_segment(A, B, (x0, y), box_center_y)

        C, D = _find_contour_segment(eyeball_sorted, (x1, y))
        right_inside = _is_below_segment(C, D, (x1, y), box_center_y)

        if not (left_inside or right_inside):
            continue

        if not left_inside:
            x0 = int(max((B[0] - A[0]) / (B[1] - A[1]) * (y - A[1]) + A[0], x0))

        if not right_inside:
            x1 = int(min((D[0] - C[0]) / (D[1] - C[1]) * (y - C[1]) + C[0], x1))

        mask[(y - y_ofs), int(x0 - x_ofs):int(x1 - x_ofs)] = 255

    return Image.fromarray(mask, mode="L")


class FaceDetector:
    def __init__(self):
        self.face_detection = FaceDetection(FaceDetectionModel.BACK_CAMERA)
        self.face_landmarks = FaceLandmark()
        self.iris_landmarks = IrisLandmark()

    def detect_face(self, image: Image.Image):
        detections = self.face_detection(image)
        if not detections:
            print("No face detected :(")
            return None
        return face_detection_to_roi(detections[0], image.size)

    def detect_faces(self, image: Image.Image):
        detections = self.face_detection(image)
        if not detections:
            print("No faces detected :(")
            return None
        return detections

    def detect_landmarks(self, image: Image.Image, face_roi):
        return self.face_landmarks(image, face_roi)

    def getXY(self, image: Image.Image, iris_results: IrisResults):
        iris_location, _ = _get_iris_location(iris_results, image.size)
        x = (iris_location[0] + iris_location[2]) / 2
        y = (iris_location[1] + iris_location[3]) / 2

        return x, y

    def get_left_and_right_results(self, img: Image.Image, face):
        roi = face_detection_to_roi(face, img.size)
        landmarks = self.detect_landmarks(img, roi)

        try:
            left_eye_roi, right_eye_roi = iris_roi_from_face_landmarks(landmarks, img.size)
        except Exception:
            return None, None

        left_eye_results = self.iris_landmarks(img, left_eye_roi)
        right_eye_results = self.iris_landmarks(img, right_eye_roi, is_right_eye=True)

        return left_eye_results, right_eye_results

    def get_eyes_from_faces(self, faces, img):
        eyes = []

        for face in faces:
            left_eye_results, right_eye_results = self.get_left_and_right_results(img, face)

            if not left_eye_results or not right_eye_results:
                continue

            x, y = self.getXY(img, left_eye_results)
            left_point = Point(x, y)

            x, y = self.getXY(img, right_eye_results)
            right_point = Point(x, y)

            eyes.append([left_point, right_point])

        return eyes

    def recolor_iris(self, image: Image.Image, iris_results: IrisResults) -> Image.Image:
        x, y = self.getXY(image, iris_results)
        draw = ImageDraw.Draw(image)
        radius = 1.5
        draw.ellipse(
            [(x - radius, y - radius), (x + radius, y + radius)],
            outline=(0, 255, 0),
            width=3
        )
        return image