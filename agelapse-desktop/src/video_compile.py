import glob
import os
import platform
import subprocess
import time
from typing import List

## Test

def get_ffmpeg_path() -> str:
    """
    Determine the path to the ffmpeg executable based on the operating system.

    Returns:
        str: The path to the ffmpeg executable.
    """
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    if platform.system() == 'Windows':
        ffmpeg_path = os.path.join(base_dir, 'assets', 'ffmpeg_win', 'ffmpeg.exe')
        print(f"[DEBUG] FFmpeg path for Windows: {ffmpeg_path}")
        return ffmpeg_path
    elif platform.system() == 'Darwin':
        # Use the static FFmpeg binary for macOS
        ffmpeg_path = os.path.join(base_dir, 'assets', 'ffmpeg_mac', 'ffmpeg')
        print(f"[DEBUG] FFmpeg path for macOS: {ffmpeg_path}")
        return ffmpeg_path
    return 'ffmpeg'  # Assume ffmpeg is available in PATH on Linux


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

    # Debug: Print the sorted image files
    print(f"Sorted image files: {image_files}")

    return image_files

def run_ffmpeg(image_dir: str, output_video: str) -> None:
    """
    Run ffmpeg to compile the images into a video.

    Args:
        image_dir (str): The directory containing the images.
        output_video (str): The output video file path.
    """
    ffmpeg_path = get_ffmpeg_path()
    system = platform.system()

    if system == "Darwin":
        # macOS: Use glob pattern
        pattern = os.path.join(image_dir, '*.png')
        command = [
            ffmpeg_path,
            '-pattern_type', 'glob',
            '-i', pattern,
            '-framerate', '16',
            '-vcodec', 'libx264',
            '-pix_fmt', 'yuv420p',
            '-profile:v', 'high',
            '-level:v', '4.1',
            '-crf', '18',  # higher quality CRF
            '-preset', 'slow',  # slower preset for better compression
            '-b:v', '5M',  # target bitrate
            '-maxrate', '10M',  # maximum bitrate
            '-bufsize', '20M',  # buffer size
            '-movflags', '+faststart',  # optimize for streaming
            '-y',  # Overwrite output files without asking
            output_video
        ]
    else:
        # Windows: Directly pass image files as input arguments
        image_files = get_image_files(image_dir)
        input_args = []
        for image_file in image_files:
            input_args.extend(['-i', image_file])

        # Create the ffmpeg command for concatenating images
        filter_complex = ''.join([f"[{i}:v]" for i in range(len(image_files))]) + f"concat=n={len(image_files)}:v=1:a=0[outv]"
        
        command = [
            ffmpeg_path,
            *input_args,
            '-filter_complex', filter_complex,
            '-map', '[outv]',
            '-vcodec', 'libx264',
            '-pix_fmt', 'yuv420p',
            '-profile:v', 'high',
            '-level:v', '4.1',
            '-crf', '18',  # higher quality CRF
            '-preset', 'slow',  # slower preset for better compression
            '-b:v', '5M',  # target bitrate
            '-maxrate', '10M',  # maximum bitrate
            '-bufsize', '20M',  # buffer size
            '-movflags', '+faststart',  # optimize for streaming
            '-y',  # Overwrite output files without asking
            output_video
        ]

    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    spinner = ['|', '/', '—', '\\']
    spinner_index = 0

    while True:
        line = process.stderr.readline()
        if line == '' and process.poll() is not None:
            break

        # Print the current line from ffmpeg output
        if line:
            print(line.strip())

        # Update spinner
        print(f"\b{spinner[spinner_index]}", end='', flush=True)
        spinner_index = (spinner_index + 1) % len(spinner)

        # Necessary for text spinner
        time.sleep(0.1)

    process.wait()

    print("\b \n[LOG] Video created successfully!")


def compile_video(stabilized_img_dir: str, output_video_path: str) -> str:
    """
    Compile images from a specified directory into a video file.
    """
    try:
        print("[LOG] Compiling video ..... ", end=' ', flush=True)

        if not os.path.exists(stabilized_img_dir):
            raise FileNotFoundError(f"The specified image directory '{stabilized_img_dir}' does not exist.")

        output_dir = os.path.dirname(output_video_path)
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)

        print(f'Saving video to {output_dir}')

        run_ffmpeg(stabilized_img_dir, output_video_path)

        print("done.")
        return output_video_path

    except FileNotFoundError as e:
        print(f"[ERROR] {e}")
    except PermissionError as e:
        print(f"[ERROR] Permission denied: {e}")
    except Exception as e:
        print(f"[ERROR] An unexpected error occurred: {e}")

    return ""
