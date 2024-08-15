import math
import os
import shutil

import cv2
import numpy as np
import pillow_heif
from PIL import Image, UnidentifiedImageError
from fdlite.types import Detection

from src.face_detector import FaceDetector
from src.point import Point

# Constants for output image dimensions
OUTPUT_HEIGHT: int = 1080
OUTPUT_WIDTH: int = 1920

# Alternative higher resolution
# OUTPUT_HEIGHT = 2160
# OUTPUT_WIDTH = 2880


def get_transformation_matrix(
    eyes: list[Point],
    eyes_to_stabilize_on: list[Point]
) -> np.ndarray:
    """
    Calculate the transformation matrix to align and scale eyes to the reference position.

    Args:
        eyes (list[Point]): Current positions of the eyes in the image.
        eyes_to_stabilize_on (list[Point]): Reference positions to stabilize the eyes on.

    Returns:
        np.ndarray: The transformation matrix for aligning the eyes.
    """
    dx, dy = eyes[1].x - eyes[0].x, eyes[1].y - eyes[0].y
    angle = math.atan2(dy, dx)

    dist_current = np.linalg.norm([dx, dy])
    dist_reference = np.linalg.norm([
        eyes_to_stabilize_on[1].x - eyes_to_stabilize_on[0].x,
        eyes_to_stabilize_on[1].y - eyes_to_stabilize_on[0].y
    ])
    scale = dist_reference / dist_current

    cos_a = math.cos(angle)
    sin_a = math.sin(angle)

    # Calculate rotation matrix
    m00 = scale * cos_a
    m01 = scale * sin_a
    m10 = -scale * sin_a
    m11 = scale * cos_a

    # Translation
    tX = eyes_to_stabilize_on[0].x - (eyes[0].x * m00 + eyes[0].y * m01)
    tY = eyes_to_stabilize_on[0].y - (eyes[0].x * m10 + eyes[0].y * m11)

    # Return matrix as numpy array
    return np.array([[m00, m01, tX],
                     [m10, m11, tY]])


def apply_transformation(
    image: Image.Image,
    matrix: np.ndarray,
    output_size: tuple[int, int]
) -> np.ndarray:
    """
    Apply an affine transformation to an image.

    Args:
        image (Image.Image): The input image to transform.
        matrix (np.ndarray): The transformation matrix to apply.
        output_size (tuple[int, int]): The desired output size of the transformed image.

    Returns:
        np.ndarray: The transformed image as a numpy array.
    """
    return cv2.warpAffine(np.array(image), matrix, output_size)


# Register HEIF format with Pillow
pillow_heif.register_heif_opener()


def stabilize_images(
    images: list[str],
    eyes_to_stabilize_on: list[Point],
    output_dir: str,
    output_size: tuple[int, int] = (OUTPUT_WIDTH, OUTPUT_HEIGHT),
    progress_callback=None
) -> None:
    """
    Stabilize a list of images by aligning their eyes to a reference position.

    Args:
        images (list[str]): List of image file paths to stabilize.
        eyes_to_stabilize_on (list[Point]): Reference positions to stabilize the eyes on.
        output_dir (str): Directory to save stabilized images.
        output_size (tuple[int, int], optional): Output size of stabilized images. Defaults to (OUTPUT_WIDTH, OUTPUT_HEIGHT).
        progress_callback (optional): Optional callback function to report progress.
    """
    face_detector = FaceDetector()
    total_images = len(images)
    loading_symbols = ['⠄', '⠆', '⠇', '⠋', '⠉', '⠙', '⠸', '⠼', '⠤']

    images_with_errors, images_with_no_face = [], []

    for index, img_path in enumerate(images):
        try:
            with Image.open(img_path) as img:
                img.load()

                faces: list[Detection] | None = face_detector.detect_faces(img)
                if faces is None:
                    log_no_faces(img_path, images_with_no_face)
                    continue

                eyes: list[list[Point]] = face_detector.get_eyes_from_faces(faces, img)
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


def log_no_faces(img_path: str, images_with_no_face: list[str]) -> None:
    """
    Log images with no detected faces.

    Args:
        img_path (str): Path to the image file.
        images_with_no_face (list[str]): List to store paths of images with no detected faces.
    """
    print(f"[ISSUE] No faces detected in {img_path}")
    images_with_no_face.append(img_path)


def update_progress(index: int, total_images: int, loading_symbols: list[str]) -> float:
    """
    Update and print progress of the stabilization process.

    Args:
        index (int): Current index in the list of images.
        total_images (int): Total number of images to process.
        loading_symbols (list[str]): List of symbols to show progress.

    Returns:
        float: Percentage of progress completed.
    """
    percent_complete = (index + 1) / total_images * 100
    symbol_index = index % len(loading_symbols)
    print(f"\r[LOG] Stabilizing {loading_symbols[symbol_index]} ......... {percent_complete:.2f}% complete", end='')
    return percent_complete


def print_results(images_with_errors: list[str], images_with_no_face: list[str]) -> None:
    """
    Print the results of the stabilization process.

    Args:
        images_with_errors (list[str]): List of images that encountered errors.
        images_with_no_face (list[str]): List of images with no detected faces.
    """
    skipped_due_to_errors_len = len(images_with_errors)
    images_with_no_face_len = len(images_with_no_face)
    result = f"{skipped_due_to_errors_len} skipped due to error"
    if images_with_no_face_len > 0:
        result = f"{result}, {images_with_no_face_len} had no faces found"
    print(f"\n[LOG] Stabilization complete. {result}")


def stabilize_image_directory(
    input_dir: str,
    output_dir: str,
    progress_callback=None
) -> None:
    """
    Stabilize all images in a directory.

    Args:
        input_dir (str): Directory containing images to stabilize.
        output_dir (str): Directory to save stabilized images.
        progress_callback (optional): Optional callback function to report progress.
    """
    prepare_output_directory(output_dir)

    eyes_to_stabilize_on = get_reference_eyes_position()

    img_paths = get_image_paths(input_dir)

    stabilize_images(img_paths, eyes_to_stabilize_on, output_dir, progress_callback=progress_callback)


def prepare_output_directory(output_dir: str) -> None:
    """
    Prepare the output directory by removing any existing contents and creating a new directory.

    Args:
        output_dir (str): Directory to prepare.
    """
    if os.path.exists(output_dir):
        shutil.rmtree(output_dir)
    os.makedirs(output_dir)


def get_reference_eyes_position() -> list[Point]:
    """
    Get the reference positions of the eyes for stabilization.

    Returns:
        list[Point]: Reference positions for eyes.
    """
    y = 0.48 * OUTPUT_HEIGHT
    return [
        Point((OUTPUT_WIDTH / 2) - 0.035 * OUTPUT_WIDTH, y),
        Point((OUTPUT_WIDTH / 2) + 0.035 * OUTPUT_WIDTH, y)
    ]


def get_image_paths(input_dir: str) -> list[str]:
    """
    Retrieve and sort image file paths from a directory.

    Args:
        input_dir (str): Directory containing image files.

    Returns:
        list[str]: Sorted list of image file paths.
    """
    return [
        os.path.join(input_dir, f) for f in os.listdir(input_dir)
        if f.lower().endswith(('.jpg', '.jpeg', '.png', '.webp', '.heic'))
    ]


def save_stabilized_image(img_path: str, img: np.ndarray, output_dir: str) -> None:
    """
    Save the stabilized image to the output directory.

    Args:
        img_path (str): Original image file path.
        img (np.ndarray): Stabilized image array.
        output_dir (str): Directory to save the stabilized image.
    """
    base_name = os.path.basename(img_path)
    name, _ = os.path.splitext(base_name)

    output_path = os.path.join(output_dir, f'{name}.png')  # Save as PNG

    img = Image.fromarray(img)
    img.save(output_path, 'PNG')  # Save in PNG format


def get_horizontal_center_distance(eyes: list[Point], image_center_x: float) -> float:
    """
    Calculate the horizontal distance between the eyes' center and the image center.

    Args:
        eyes (list[Point]): List of eye positions.
        image_center_x (float): Horizontal center of the image.

    Returns:
        float: Horizontal distance between the eyes' center and the image center.
    """
    left_eye, right_eye = eyes
    eyes_center_x = (left_eye.x + right_eye.x) / 2
    return abs(eyes_center_x - image_center_x)


def get_closest_eyes_to_center(eyes: list[list[Point]], img_width: int) -> list[Point]:
    """
    Get the pair of eyes closest to the center of the image.

    Args:
        eyes (list[list[Point]]): List of eye pairs.
        img_width (int): Width of the image.

    Returns:
        list[Point]: Pair of eyes closest to the center.
    """
    image_center_x = img_width / 2
    return min(eyes, key=lambda e: get_horizontal_center_distance(e, image_center_x))
