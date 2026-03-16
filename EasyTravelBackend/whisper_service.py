import asyncio
import os
import yt_dlp
import whisper
import torch

async def download_audio_and_metadata(video_url):
    """
    Download audio from a video URL and extract metadata (description/caption).
    Returns a tuple: (audio_filename, video_description, video_title)
    """
    print("Fetching metadata and downloading audio...")

    # Options for fetching metadata only (no download yet)
    ydl_info_opts = {
        'quiet': True,
        'no_warnings': True,
    }

    loop = asyncio.get_event_loop()
    
    # Extract video info to get title and description
    video_info = await loop.run_in_executor(
        None,
        lambda: yt_dlp.YoutubeDL(ydl_info_opts).extract_info(video_url, download=False)
    )

    # Extract metadata safely
    video_title = video_info.get('title', 'video')
    # For Instagram/TikTok/YouTube, 'description' usually holds the caption
    video_description = video_info.get('description', '') 
    
    # Create a safe filename
    safe_title = "".join([c if c.isalnum() or c in " -_" else "_" for c in video_title])
    filename = f"{safe_title}.mp3"

    ydl_download_opts = {
        'format': 'bestaudio/best',
        'postprocessors': [{
            'key': 'FFmpegExtractAudio',
            'preferredcodec': 'mp3',
            'preferredquality': '192',
        }],
        'outtmpl': f'{safe_title}.%(ext)s',
        'progress_hooks': [lambda d: print(f"Download progress: {d.get('_percent_str', 'downloading...')}")],
        'overwrites': True,
        'quiet': True
    }

    # Download the audio
    await loop.run_in_executor(
        None,
        lambda: yt_dlp.YoutubeDL(ydl_download_opts).download([video_url])
    )

    return filename, video_description, video_title

async def transcribe_video(video_url, language="en", output_file="output_data.txt"):
    """
    Download video audio, transcribe it, and save both transcript and caption.
    """
    try:
        # Get audio file and metadata
        audio_file, description, title = await download_audio_and_metadata(video_url)

        # Load Whisper model
        device = "cuda" if torch.cuda.is_available() else "cpu"
        print(f"Using device: {device}")
        print("Loading Whisper model...")
        
        # Use 'base' or 'small' for speed, 'large' for accuracy
        model = whisper.load_model("base", device=device)

        print("Transcribing audio...")
        result = model.transcribe(
            audio_file,
            language=language,
            without_timestamps=True,
            fp16=(device == "cuda")
        )

        transcript_text = result["text"]

        # Format the final output
        final_output = (
            f"--- VIDEO METADATA ---\n"
            f"Title: {title}\n"
            f"Caption/Description: {description}\n\n"
            f"--- TRANSCRIPT ---\n"
            f"{transcript_text}\n"
        )

        # Save to file
        if output_file:
            with open(output_file, "w", encoding="utf-8") as f:
                f.write(final_output)
            print(f"\nSuccess! Data saved to {output_file}")

        return final_output

    except Exception as e:
        print(f"Error: {e}")
        return None
    finally:
        # Cleanup audio file
        if 'audio_file' in locals() and os.path.exists(audio_file):
            os.remove(audio_file)

async def main():
    url = input("Whisper Video Transcription \n -------------------------- \n\n Please enter the video URL: \n")
    
    # You can change the output filename here
    await transcribe_video(url, output_file="trip_data.txt")

if __name__ == "__main__":
    asyncio.run(main())