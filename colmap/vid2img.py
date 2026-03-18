import cv2
import os

def extract_frames_opencv(video_path, fps=3, output_path='frames'):
    """
    Extract frames from a video at a fixed FPS using OpenCV and save as PNG.
    
    Args:
        video_path (str): Path to the input video.
        fps (int): Number of frames per second to extract.
        output_path (str): Directory to save the frames.
    
    Returns:
        int: Number of frames saved.
    """
    if not os.path.exists(video_path):
        print(f"Error: Video file '{video_path}' does not exist.")
        return 0

    os.makedirs(output_path, exist_ok=True)

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"Error: Could not open video '{video_path}'.")
        return 0

    video_fps = cap.get(cv2.CAP_PROP_FPS)
    if video_fps <= 0:
        video_fps = 30  # fallback if FPS cannot be read

    frame_interval = int(video_fps / fps)
    if frame_interval < 1:
        frame_interval = 1

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    print(f"Video FPS: {video_fps:.2f}, Total frames: {total_frames}, Extract every {frame_interval} frame(s)")

    saved_count = 0
    frame_idx = 0

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        if frame_idx % frame_interval == 0:
            frame_name = os.path.join(output_path, f"frame_{saved_count:04d}.png")
            cv2.imwrite(frame_name, frame)  # PNG format
            saved_count += 1

        frame_idx += 1

    cap.release()
    print(f"Saved {saved_count} frames to '{output_path}'")
    return saved_count

# -------------------------
# Example usage:
video_path = r"C:\Users\lxp1655\Videos\colmap\PXL_20241126_174620630.mp4"
output_directory = r"C:\Users\lxp1655\Videos\colmap\images"
frames_per_second = 3  # adjust for your needs

extract_frames_opencv(video_path, fps=frames_per_second, output_path=output_directory)
