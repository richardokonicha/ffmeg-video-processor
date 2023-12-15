#!/bin/bash

if [ "$#" -eq 0 ]; then
    echo "Usage: ./script.sh title"
    exit 1
fi

title=$1
audio_dir=~/workspace/ihsan/books/$title/audio
images_dir=~/workspace/ihsan/books/$title/images
base_dir=~/workspace/ihsan/books/$title

# Desired width and height for the final video
width=1280
height=720

# Check if audio directory exists
if [ ! -d "$audio_dir" ]; then
    echo "Audio directory does not exist"
    exit 1
fi

# Loop through each language directory
for lang_dir in "$audio_dir"/*; do
    if [ -d "$lang_dir" ]; then
        language=$(basename "$lang_dir")

        # Check the videos directory exists
        if [ ! -d "$base_dir/videos" ]; then
            echo "Videos directory does not exist. Creating..."
            mkdir -p "$base_dir/videos"
        fi

        # Check if video already exists
        if [ -f "$base_dir/videos/${language}.mp4" ]; then
            echo "Video for language $language already exists. Skipping..."
            continue
        else
            echo "Processing language: $language"
            echo "" > list.txt

            # Check for audio files and corresponding image files
            for i in {0..13}; do
                audio_file="$lang_dir/$i.m4a"
                image_file="$images_dir/$i.jpg"
                
                # Check audio and image files are named correctly.
                if [ ! -f "$audio_file" ] || [ ! -f "$image_file" ]; then
                    echo "Missing audio or image file for index $i in language $language. Skipping..."
                    exit 1
                fi

                # Get the audio duration in seconds
                duration=$(ffprobe -i "$audio_file" -show_entries format=duration -v quiet -of csv="p=0")
                frames=$(bc -l <<< "$duration*25") # Total number of frames for the video
                zoom_factor="1.09" # Desired end zoom level
                zoom_increment=$(bc -l <<< "($zoom_factor-1)/$frames") # Increment per frame

                # Create individual segments
                ffmpeg -hide_banner -i "$image_file" -i "$audio_file" -filter_complex "[0:v]scale=w=${width}:h=${height}:,pad=${width}:${height}:(ow-iw)/2:(oh-ih)/2,format=pix_fmts=yuva420p,scale=8000:-1,zoompan=z='zoom+$zoom_increment':x=0:y=0:fps=25:d=$duration*25:s=${width}x${height},format=pix_fmts=yuva420p[v0];[v0]fps=25[vout]" -map "[vout]" -map 1:a -c:v libx264 "segment$i.mp4"
                
                # Append the segment to the list file
                echo "file 'segment$i.mp4'" >> list.txt
            done

            # Concatenate all the segments using the list file
            video_file = "${base_dir}/videos/${language}.mp4"
            ffmpeg -f concat -safe 0 -i list.txt -c copy "$base_dir/videos/${language}.mp4"

            # Remove temporary files
            rm segment*.mp4
        fi

        # Add Captions for each language.
        # Initialize ffmpeg command parts
        # Check the captions directory exists
        if [ ! -d "$base_dir/captions" ]; then
            echo "Captions directory does not exist. Creating..."
            mkdir -p "$base_dir/captions"
        fi

        # Check if language captions file already exists
        if [ -f "$base_dir/captions/${language}.srt" ]; then
            echo "Captions for language $language already exists. Skipping..."
        else
            ffmpeg_cmd=("ffmpeg" "-i" "$video_file")
            map_cmd=("-map" "0")
            metadata_cmd=()
            for lang_dir in "$audio_dir"/*; do
                if [ -d "$lang_dir" ]; then
                    lang=$(basename "$lang_dir")
                    echo "Processing captions for language: $lang"
                    input_file="${base_dir}/${lang}"
                    output_file="${base_dir}/captions/${lang}.srt"
                    echo "Now creating captions for: $output_file"

                    video_file="${base_dir}/videos/${language}.mp4"
                    start_time=0
                    index=0
                    sequence_number=1

                    # Remove the existing SRT file if it exists
                    if [ -f "$output_file" ]; then
                        rm "$output_file"
                    fi

                    # Function to convert time to SRT time format
                    convert_to_srt_time() {
                        local time=$(printf "%.0f" $1)
                        printf "%02d:%02d:%02d,%03d" $(($time/3600)) $(($time%3600/60)) $(($time%60)) $(($time%1*1000))
                    }

                    # Change to the directory containing the audio files
                    cd "$audio_dir" || { echo "Audio directory not found"; exit 1; }

                    # Loop through the audio files 
                    # Assume same number of audio files as sequences in text file
                    for audio in $(ls *.m4a | sort -n); do

                        # Get the duration of the audio file in seconds
                        duration=$(ffprobe -i "$audio" -show_entries format=duration -v quiet -of csv="p=0")

                        # Calculate end time
                        end_time=$(echo "$start_time + $duration" | bc)

                        start_time_srt=$(convert_to_srt_time $start_time)
                        end_time_srt=$(convert_to_srt_time $end_time)


                        # Insert the time sequence in the corresponding sequence number
                        awk -v seq_num="$sequence_number" -v start_time_srt="$start_time_srt" -v end_time_srt="$end_time_srt" '(!found && $0 ~ seq_num) {print; print start_time_srt " --> " end_time_srt; getline; print; print ""; found=1}' "$input_file" >> "$output_file"

                        # Update start_time for the next loop
                        start_time=$end_time

                        # Increment index and sequence_number for the next loop
                        sequence_number=$((sequence_number + 1))
                    done
                fi
            done
            # Loop through each language to add to ffmpeg command
            for lang_dir in "$audio_dir"/*; do
                lang=$(basename "$lang_dir")
                echo "Language is: $lang"
                srt_file="${base_dir}/captions/${lang}.srt"

                # Append to ffmpeg command arrays
                ffmpeg_cmd+=("-i" "$srt_file")
                map_cmd+=("-map" "$((idx + 1))")
                metadata_cmd+=("-metadata:s:s:${idx}" "language=${lang}")
            done

            # Combine all parts of ffmpeg command
            echo "creating video with Captions..."
            ffmpeg_cmd+=("${map_cmd[@]}" "-c" "copy" "-c:s" "mov_text" "${metadata_cmd[@]}" "${base_dir}/videos/${language}.mp4")
            "${ffmpeg_cmd[@]}"
        fi
    fi
done

rm list.txt

