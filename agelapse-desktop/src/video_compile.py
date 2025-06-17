import glob
import os
import platform
import subprocess
import threading
from typing import List
import tempfile


def get_ffmpeg_path() -> str:
  """
  Determine the path to the ffmpeg executable based on the operating system.

  Returns:
      str: The path to the ffmpeg executable.
  """
  base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
  if platform.system() == 'Windows':
    ffmpeg_path = os.path.join(base_dir, 'assets', 'ffmpeg_win', 'ffmpeg.exe')
    return ffmpeg_path
  elif platform.system() == 'Darwin':
    ffmpeg_path = os.path.join(base_dir, 'assets', 'ffmpeg_mac', 'ffmpeg')
    return ffmpeg_path
  return 'ffmpeg'


def get_image_files(image_dir: str) -> List[str]:
  """
  Retrieve and sort the list of image files from the specified directory.

  Args:
      image_dir (str): The directory containing the images.

  Returns:
      List[str]: A sorted list of image file paths.
  """
  image_files = sorted(glob.glob(os.path.join(image_dir, '*.png')))
  if not image_files:
    raise FileNotFoundError("No .png files found in the specified directory.")

  return image_files


def run_ffmpeg(image_dir: str, output_video: str, framerate: int) -> None:
  """
  Run ffmpeg to compile the images into a video.

  Args:
      image_dir (str): The directory containing the images.
      output_video (str): The output video file path.
      framerate (int): The output video framerate
  """
  print("[LOG] Running ffmpeg...")

  ffmpeg_path: str = get_ffmpeg_path()

  print(f"[LOG] ffmpeg path is: {ffmpeg_path}")

  list_filename = create_file_list(image_dir, framerate)

  print(f"[LOG] File list has been created")

  command = [
    ffmpeg_path,
    '-f', 'concat',
    '-safe', '0',
    '-i', list_filename,
    '-pix_fmt', 'yuv420p',
    '-y',
    output_video
  ]

  print(f"[FFMPEG] Command: {command}")

  process = subprocess.Popen(
    command,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True
  )

  while True:
    line = process.stderr.readline()
    if line == '' and process.poll() is not None:
      break

    if line:
      print(line.strip())

  process.wait()

  if os.path.exists(list_filename):
    os.remove(list_filename)

  print("\n[LOG] Video created successfully!")


def create_file_list(image_dir, framerate, list_filename=None):
  """
  Create a text file containing the list of images for FFmpeg to process.

  Args:
      image_dir (str): The directory containing the images.
      framerate (int or float): The framerate for the video.
      list_filename (str): The name of the text file to create. If None, a temporary file will be used.
  """
  try:
    print("[LOG] Creating ffmpeg file list...")

    time_per_frame = 1 / framerate

    image_files = sorted([img for img in os.listdir(image_dir) if img.endswith('.png')])

    print(f"[LOG] image_files:")
    print(image_files)

    if list_filename is None:
      temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
      list_filename = temp_file.name
      temp_file.close()

    with open(list_filename, 'w') as file_list:
      for image_file in image_files:
        file_list.write(f"file '{os.path.join(image_dir, image_file)}'\n")
        file_list.write(f"duration {time_per_frame}\n")

      if image_files:
        file_list.write(f"duration {time_per_frame}\n")

    print(f"[LOG] File list created at {list_filename}")

  except Exception as e:
    print(f"[ERROR] Error while compiling video file list: {e}")

  return list_filename


def compile_video(stabilized_img_dir: str, output_video_path: str, framerate: int) -> str:
  """
  Compile images from a specified directory into a video file.
  """
  try:
    print(f"[LOG] Compiling video (framerate: {framerate})..... ", end=' ', flush=True)

    if not os.path.exists(stabilized_img_dir):
      raise FileNotFoundError(f"The specified image directory '{stabilized_img_dir}' does not exist.")

    output_dir = os.path.dirname(output_video_path)
    if not os.path.exists(output_dir):
      os.makedirs(output_dir)

    print(f'Saving video to {output_dir}')

    def target():
      run_ffmpeg(stabilized_img_dir, output_video_path, framerate)

    thread = threading.Thread(target=target)
    thread.start()

    print("[LOG] Video compilation completed successfully.")
    return output_video_path

  except FileNotFoundError as e:
    print(f"[ERROR] {e}")
  except PermissionError as e:
    print(f"[ERROR] Permission denied: {e}")
  except Exception as e:
    print(f"[ERROR] An unexpected error occurred: {e}")

  return ""
