import subprocess
from pathlib import Path
import shutil
import re

def process_audio_and_images(base_dir):
    videos_dir = base_dir / "videos"
    images_dir = base_dir / "images"
    audio_dir = base_dir / "audio"
    # Check if videos directory exists
    videos_dir.mkdir(parents=True, exist_ok=True)

    # Loop through each language directory
    for lang_dir in audio_dir.iterdir():
        if lang_dir.is_dir():
            language = lang_dir.name

            # Check if video already exists
            video_file = videos_dir / f"{language}.mp4"
            temp_folder = Path.cwd() / "temp_segments"
            
            if video_file.is_file():
                print(f"Video for language {language} already exists. Skipping...")
                continue

            print(f"Processing language: {language}")
            list_file_path = Path.cwd() / "list.txt"
            with open(list_file_path, 'w') as list_file:
                # This automatically truncates the file to an empty state
                pass

            # Create a temporary folder for segments
            temp_folder.mkdir(exist_ok=True)

            # Get number of audio files
            num_audio_files = len(list(lang_dir.glob("*.m4a")))
            
            # Caption file
            caption_file_path = base_dir / f"{language}"
            with open(caption_file_path, "r") as caption_file:
                caption_file_text = caption_file.read()
            caption_lines = re.findall(pattern=r'\d+\n(.+)', string=caption_file_text)
            
            # Check for audio files and corresponding image files
            for i in range(num_audio_files):
                audio_file = lang_dir / f"{i}.m4a"
                image_file = images_dir / f"{i}.jpg"
                
                caption_text = caption_lines[i]
                print(caption_text, 'caption_text')
                
                # Check audio and image files are named correctly
                if not audio_file.is_file() or not image_file.is_file():
                    print(f"Missing audio or image file for index {i} in language {language}. Skipping...")
                    return

                # Get the audio duration in seconds
                duration = float(subprocess.check_output(["ffprobe", "-i", str(audio_file), "-show_entries", "format=duration", "-v", "quiet", "-of", "csv=p=0"]))

                frames = int(duration * 25)  # Total number of frames for the video
                zoom_factor = 1.09  # Desired end zoom level
                zoom_increment = (zoom_factor - 1) / frames  # Increment per frame

                # Create individual segments in the temporary folder
                segment_file = temp_folder / f"segment{i}.mp4"
                
                subprocess.run(["ffmpeg", "-hide_banner", "-i", str(image_file), "-i", str(audio_file), "-filter_complex",
                                f"[0:v]scale=w=1280:h=720:,pad=1280:720:(ow-iw)/2:(oh-ih)/2,format=pix_fmts=yuva420p,scale=8000:-1,zoompan=z='zoom+{zoom_increment}':x=0:y=0:fps=25:d={duration*25}:s=1280x720,format=pix_fmts=yuva420p[v0];[v0]fps=25[vout];[vout]drawtext=text='{caption_text}':fontcolor=white:fontsize=24:box=1:boxcolor=black@0.5:x=(w-text_w)/2:y=h-50[outv]",
                                "-map", "[outv]", "-map", "1:a", "-c:v", "libx264", str(segment_file)])

                # Append the segment to the list file
                with open(list_file_path, 'a') as list_file:
                    list_file.write(f"file '{segment_file}'\n")

            subprocess.run(["ffmpeg", "-f", "concat", "-safe", "0", "-i", "list.txt", "-c", "copy", str(video_file)])

            # Remove temporary files
            shutil.rmtree(temp_folder)

            print(f"Video for language {language} successfully created: {video_file}")


title = "brave"
base_dir = Path.cwd() / str(title)

process_audio_and_images(base_dir)


