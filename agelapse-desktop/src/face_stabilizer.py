import math
import os
import shutil
import pillow_heif

import cv2
import numpy as np
from PIL import Image, UnidentifiedImageError
from src.point import Point
from src.face_detector import FaceDetector

# Constants
OUTPUT_HEIGHT = 1080
OUTPUT_WIDTH = 1440

# OUTPUT_HEIGHT = 2160
# OUTPUT_WIDTH = 2880


def get_transformation_matrix(eyes, eyes_to_stabilize_on):
  dx, dy = eyes[1].x - eyes[0].x, eyes[1].y - eyes[0].y
  angle = math.atan2(dy, dx)
  eyes_center = ((eyes[0].x + eyes[1].x) / 2, (eyes[0].y + eyes[1].y) / 2)

  dist_current = np.linalg.norm([dx, dy])
  dist_reference = np.linalg.norm([
    eyes_to_stabilize_on[1].x - eyes_to_stabilize_on[0].x,
    eyes_to_stabilize_on[1].y - eyes_to_stabilize_on[0].y
  ])
  scale = dist_reference / dist_current

  cos_a = math.cos(angle)
  sin_a = math.sin(angle)

  # Calculate rotation matrix components
  m00 = scale * cos_a
  m01 = scale * sin_a
  m10 = -scale * sin_a
  m11 = scale * cos_a

  # Adjust translation
  tX = eyes_to_stabilize_on[0].x - (eyes[0].x * m00 + eyes[0].y * m01)
  tY = eyes_to_stabilize_on[0].y - (eyes[0].x * m10 + eyes[0].y * m11)

  # Return the transformation matrix as a numpy array
  return np.array([[m00, m01, tX],
                   [m10, m11, tY]])


def apply_transformation(image, matrix, output_size):
  return cv2.warpAffine(np.array(image), matrix, output_size)


pillow_heif.register_heif_opener()


def stabilize_images(images, eyes_to_stabilize_on, output_dir, output_size=(OUTPUT_WIDTH, OUTPUT_HEIGHT),
                     progress_callback=None):
  face_detector = FaceDetector()
  total_images = len(images)
  loading_symbols = ['⠄', '⠆', '⠇', '⠋', '⠉', '⠙', '⠸', '⠼', '⠤']

  images_with_errors, images_with_no_face = [], []

  for index, img_path in enumerate(images):
    try:
      with Image.open(img_path) as img:
        img.load()

        faces = face_detector.detect_faces(img)
        if faces is None:
          log_no_faces(img_path, images_with_no_face)
          continue

        eyes = face_detector.get_eyes_from_faces(faces, img)
        if not eyes:
          log_no_faces(img_path, images_with_no_face)
          continue

        curr_eyes = get_closest_eyes_to_center(eyes, img.size[0])
        transformation_matrix = get_transformation_matrix(curr_eyes, eyes_to_stabilize_on)
        stabilized_img = apply_transformation(img, transformation_matrix, output_size)

        # Save stabilized image immediately
        save_stabilized_image(img_path, stabilized_img, output_dir)

        percent_complete = update_progress(index, total_images, loading_symbols)
        if progress_callback:
          progress_callback(int(percent_complete))

    except (FileNotFoundError, UnidentifiedImageError) as e:
      print(f"Error with image {img_path}: {e}")
    except Exception:
      images_with_errors.append(img_path)

  print_results(images_with_errors, images_with_no_face)


def log_no_faces(img_path, images_with_no_face):
  print(f"No faces detected in {img_path}")
  images_with_no_face.append(img_path)


def update_progress(index, total_images, loading_symbols):
  percent_complete = (index + 1) / total_images * 100
  symbol_index = index % len(loading_symbols)
  print(f"\r[LOG] Stabilizing {loading_symbols[symbol_index]} ......... {percent_complete:.2f}% complete", end='')
  return percent_complete


def print_results(images_with_errors, images_with_no_face):
  skipped_due_to_errors_len = len(images_with_errors)
  images_with_no_face_len = len(images_with_no_face)
  result = f"{skipped_due_to_errors_len} skipped due to error"
  if images_with_no_face_len > 0:
    result = f"{result}, {images_with_no_face_len} had no faces found"
  print(f"\n[LOG] Stabilization complete. {result}")


def stabilize_image_directory(input_dir, output_dir, progress_callback=None):
  prepare_output_directory(output_dir)

  eyes_to_stabilize_on = get_reference_eyes_position()

  img_paths = get_image_paths(input_dir)

  stabilize_images(img_paths, eyes_to_stabilize_on, output_dir, progress_callback=progress_callback)


def prepare_output_directory(output_dir):
  if os.path.exists(output_dir):
    shutil.rmtree(output_dir)
  os.makedirs(output_dir)


def prepare_data_directory(output_dir):
  base_dir = os.path.dirname(output_dir)
  data_dir = os.path.join(base_dir, "data")
  os.makedirs(data_dir, exist_ok=True)
  return data_dir


def prepare_thumbnails_directory(data_dir):
  thumbnails_dir = os.path.join(data_dir, "raw_photos_thumbnails")
  os.makedirs(thumbnails_dir, exist_ok=True)


def get_reference_eyes_position():
  y = 0.48 * OUTPUT_HEIGHT
  return [
    Point((OUTPUT_WIDTH / 2) - 0.04 * OUTPUT_WIDTH, y),
    Point((OUTPUT_WIDTH / 2) + 0.04 * OUTPUT_WIDTH, y)
  ]


def get_image_paths(input_dir):
  return [
    os.path.join(input_dir, f) for f in os.listdir(input_dir)
    if f.lower().endswith(('.jpg', '.jpeg', '.png', '.webp', '.heic'))
  ]



def save_stabilized_image(img_path, img, output_dir):
  base_name = os.path.basename(img_path)
  name, _ = os.path.splitext(base_name)

  output_path = os.path.join(output_dir, f'{name}.png')  # Save as PNG

  img = Image.fromarray(img)
  img.save(output_path, 'PNG')  # Save in PNG format


def get_horizontal_center_distance(eyes, image_center_x):
  left_eye, right_eye = eyes
  eyes_center_x = (left_eye.x + right_eye.x) / 2
  return abs(eyes_center_x - image_center_x)


def get_closest_eyes_to_center(eyes, img_width):
  image_center_x = img_width / 2
  return min(eyes, key=lambda e: get_horizontal_center_distance(e, image_center_x))
