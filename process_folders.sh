#!/bin/bash

set -e  # Exit on error

process_books() {
    base_directory=$1

    # Find all book directories with an image subfolder
    book_directories=($base_directory/*/)
    for book_directory in "${book_directories[@]}"; do
        process_book "$book_directory"
    done
}

process_book() {
    base_dir=$1
    videos_dir="$base_dir/videos"
    images_dir="$base_dir/images"
    audio_dir="$base_dir/audio"

    # Check if videos directory exists
    mkdir -p "$videos_dir"

    # Loop through each language directory
    for lang_dir in "$audio_dir"/*; do
        if [ -d "$lang_dir" ]; then
            language=$(basename "$lang_dir")

            # Check if video already exists
            video_file="$videos_dir/${language}.mp4"
            temp_folder="./temp_segments"

            if [ -f "$video_file" ]; then
                echo "Video for language $language already exists. Skipping..."
                continue
            fi

            echo "Processing language: $language"
            list_file_path="./list.txt"

            # Create a temporary folder for segments
            [ -d "$temp_folder" ] && rm -r "$temp_folder"
            mkdir -p "$temp_folder"

            # Get number of audio files sorted by name
            audio_files=($(ls "$lang_dir"/*.m4a | sort -V))

            # Caption file
            caption_file_path="$base_dir/$language"
            caption_lines=($(grep -Eo '\d+\n.+ ' "$caption_file_path"))

            # Check for audio files and corresponding image files
            for ((i=0; i<${#audio_files[@]}; i++)); do
                audio_file="${audio_files[$i]}"
                caption_text="${caption_lines[$i]}"
                echo "$caption_text caption_text"

                # Check audio and image files are named correctly
                image_file="$images_dir/${i}.jpg"
                if [ ! -f "$audio_file" ] || [ ! -f "$image_file" ]; then
                    echo "Missing audio or image file for index $i in language $language. Skipping..."
                    continue
                fi

                # Get the audio duration in seconds
                duration=$(ffprobe -i "$audio_file" -show_entries format=duration -v quiet -of csv=p=0)

                frames=$(echo "$duration * 25" | bc)  # Total number of frames for the video
                zoom_factor=1.09  # Desired end zoom level
                zoom_increment=$(echo "($zoom_factor - 1) / $frames" | bc)  # Increment per frame

                # Create individual segments in the temporary folder
                segment_file="$temp_folder/segment${i}.mp4"

                ffmpeg -hide_banner -y -i "$image_file" -i "$audio_file" -filter_complex \
                    "[0:v]scale=w=1280:h=720:,pad=1280:720:(ow-iw)/2:(oh-ih)/2,format=pix_fmts=yuva420p,scale=8000:-1,"\
                    "zoompan=z='zoom+$zoom_increment':x=0:y=0:fps=25:d=${duration*25}:s=1280x720,"\
                    "format=pix_fmts=yuva420p[v0];[v0]fps=25[vout];"\
                    "[vout]drawtext=text='$caption_text':fontcolor=white:fontsize=24:box=1:boxcolor=black@0.5:"\
                    "x=(w-text_w)/2:y=h-50[outv]"\
                    -map "[outv]" -map "1:a" -c:v libx264 "$segment_file"

                # Append the segment to the list file
                echo "file '$segment_file'" >> "$list_file_path"
            done

            # Concatenate all segments into one video
            ffmpeg -y -f concat -safe 0 -i "$list_file_path" -c copy "$video_file"

            # Remove temporary files
            rm -r "$temp_folder"

            echo "Video for language $language successfully created: $video_file"
        fi
    done
}

# Set the base directory where your books are located
base_directory=$(pwd)

# Run the processing
process_books "$base_directory"
