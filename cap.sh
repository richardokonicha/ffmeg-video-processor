#!/bin/bash

# Check if at least one story name and one language are provided
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <story-name> <language1> [<language2> ...]"
    exit 1
fi

# Initialize variables
story_name="$1"
shift  # remove story_name from $@

languages=("$@")  # Create an array from the remaining arguments
echo $language
base_dir="/Users/mali/workspace/ihsan/books/${story_name}/"
audio_dir="${base_dir}audio"
video_file="${base_dir}video.mp4"

# Initialize ffmpeg command parts
ffmpeg_cmd=("ffmpeg" "-i" "$video_file")
map_cmd=("-map" "0")
metadata_cmd=()

echo "Creating SRT captions..."
for language in "${languages[@]}"; do
    echo "Processing for language: $language"
    input_file="${base_dir}${language}"
    output_file="${base_dir}captions_${language}.srt"

    video_file="${base_dir}video.mp4"
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
done

# Loop through each language to add to ffmpeg command
for idx in "${!languages[@]}"; do
    lang=${languages[$idx]}
    srt_file="${base_dir}captions_${lang}.srt"

    # Append to ffmpeg command arrays
    ffmpeg_cmd+=("-i" "$srt_file")
    map_cmd+=("-map" "$((idx + 1))")
    metadata_cmd+=("-metadata:s:s:${idx}" "language=${lang}")
done

# Combine all parts of ffmpeg command
echo "creating video with Captions..."
ffmpeg_cmd+=("${map_cmd[@]}" "-c" "copy" "-c:s" "mov_text" "${metadata_cmd[@]}" "${base_dir}final.mp4")
"${ffmpeg_cmd[@]}"
