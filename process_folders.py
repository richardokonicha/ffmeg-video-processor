import subprocess
from pathlib import Path
import shutil
import pysrt
from datetime import timedelta, datetime

def check_dependencies():
    try:
        subprocess.run(["ffmpeg", "-version"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    except subprocess.CalledProcessError:
        raise EnvironmentError("Error: ffmpeg not found. Make sure it's installed and in your system's PATH.")

def create_temp_folder():
    # Create a temporary folder for video segments
    temp_folder = Path.cwd() / "temp_segments"
    if temp_folder.is_dir():
        shutil.rmtree(temp_folder)
    temp_folder.mkdir(exist_ok=True)
    return temp_folder

def clear_temps():
    temp_folder = Path.cwd() / "temp_segments"
    list_file_path = Path.cwd() / "list.txt"
    if temp_folder.is_file():
        shutil.rmtree(temp_folder)
    if list_file_path.is_file():
        with open(list_file_path, 'w') as list_file:
            list_file.write("")
        # list_file_path.unlink()

def process_language_segment(image_file, audio_file, segment_file, zoom_increment, duration):
    # Process individual language segments
    subprocess.run(["ffmpeg", "-hide_banner", "-y", "-i", str(image_file), "-i", str(audio_file),
                    "-filter_complex",
                    f"[0:v]scale=w=1280:h=720:,pad=1280:720:(ow-iw)/2:(oh-ih)/2,"
                    f"format=pix_fmts=yuva420p,scale=8000:-1,"
                    f"zoompan=z='zoom+{zoom_increment}':x=0:y=0:fps=25:d={duration*25}:s=1280x720,"
                    f"format=pix_fmts=yuva420p[v0];[v0]fps=25[vout];"
                    f"[vout]drawtext=text='':fontcolor=white:fontsize=24:"
                    f"box=1:boxcolor=black@0.5:x=(w-text_w)/2:y=h-50[outv]",
                    "-map", "[outv]", "-map", "1:a", "-c:v", "libx264", str(segment_file)])

def create_video_with_subtitle(subs, language, base_dir, video_file):
    srt_file = base_dir / f"{language}.srt"
    subs.save(srt_file, encoding='utf-8')
    subprocess.run([
        "ffmpeg",
        "-y", "-f", "concat", "-safe", "0", "-i", "list.txt",
        "-i", str(srt_file),
        "-c", "copy",
        "-c:s", "mov_text",
        "-metadata:s:s:0", f"language={language}",
        "-y", 
        str(video_file)
    ])
    print(f"Video with subtitles for language {language} successfully created: {video_file}")
    return

def create_subtitle(i, subs, duration, caption_line):
    subtitle = pysrt.SubRipItem()
    last_sub = subs[-1].end.to_time() if subs else datetime.min.time()
    last_sub_time = (datetime.combine(datetime.min.date(), last_sub) - datetime.min)
    subtitle.index = i + 1
    subtitle.start.seconds = int(last_sub_time.total_seconds())
    subtitle.end.seconds = int((last_sub_time + timedelta(seconds=duration)).total_seconds())
    subtitle.text = caption_line.strip()
    subs.append(subtitle)

def process_book(base_dir):
    try:
        clear_temps()
        check_dependencies()
        
        videos_dir = base_dir / "videos"
        images_dir = base_dir / "images"
        audio_dir = base_dir / "audio"
        
        list_file_path = Path.cwd() / "list.txt"
        
        videos_dir.mkdir(parents=True, exist_ok=True)

        for lang_dir in audio_dir.iterdir():
            if lang_dir.is_dir():
                language = lang_dir.name

                video_file = videos_dir / f"{language}.mp4"

                if video_file.is_file():
                    print(f"Video for language {language} already exists. Skipping...")
                    continue

                print(f"Processing language: {language}")

                temp_folder = create_temp_folder()

                audio_files = sorted(lang_dir.glob("*.m4a"), key=lambda x: int(x.stem))
                
                subs = pysrt.SubRipFile()
                caption_file = base_dir / f'{language}'
                with open(caption_file, 'r') as input_file:
                    cap_lines = input_file.read().strip().split('\n\n')

                for i, (audio_file, caption_line) in enumerate(zip(audio_files, cap_lines)):
                    image_file = images_dir / f"{i}.jpg"
                    if not audio_file.is_file() or not image_file.is_file():
                        print(f"Missing audio or image file for index {i} in language {language}. Skipping...")
                        continue

                    duration = float(
                        subprocess.check_output(["ffprobe", "-i", str(audio_file), "-show_entries", "format=duration",
                                                 "-v", "quiet", "-of", "csv=p=0"]))

                    frames = int(duration * 25)
                    zoom_factor = 1.09
                    zoom_increment = (zoom_factor - 1) / frames
                    segment_file = temp_folder / f"segment{i}.mp4"

                    create_subtitle(i, subs, duration, caption_line)

                    process_language_segment(image_file, audio_file, segment_file, zoom_increment, duration)
                    
                    with open(list_file_path, 'a') as list_file:
                        list_file.write(f"file '{segment_file}'\n")

                
                create_video_with_subtitle(subs, language, base_dir, video_file)
                clear_temps()

                print(f"Video for language {language} successfully created: {video_file}")
 
    except FileNotFoundError as e:
        print(f"Error: {e}. Make sure ffmpeg is installed and in your system's PATH.")
    except subprocess.CalledProcessError as e:
        print(f"Error during subprocess execution: {e}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")

def process_books(base_directory):
    try:
        # Find all book directories with an image subfolder
        book_directories = [d for d in base_directory.glob("*") if d.is_dir() and (d / "images").is_dir()]
        # Loop through directories and process each book
        for book_directory in book_directories:
            process_book(book_directory)

    except Exception as e:
        print(f"An error occurred while processing books: {e}")

if __name__ == "__main__":
    try:
        base_directory = Path.cwd()
        process_books(base_directory)
    except Exception as e:
        print(f"An error occurred: {e}")
