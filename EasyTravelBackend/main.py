from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from openai import OpenAI
import os

# 1. IMPORT YOUR WHISPER SCRIPT
from whisper_service import transcribe_video

app = FastAPI(title="Travel Itinerary Extractor API")

def get_openai_client() -> OpenAI:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise HTTPException(
            status_code=503,
            detail="OPENAI_API_KEY is not set on the server.",
        )
    return OpenAI(api_key=api_key)

# ==========================================
# DATA BLUEPRINTS
# ==========================================

# The Swift app will now send a URL instead of text
class VideoRequest(BaseModel):
    url: str

class Location(BaseModel):
    name: str
    category: str
    city: str

class LocationExtraction(BaseModel):
    locations: list[Location]

# ==========================================
# API ENDPOINT
# ==========================================

@app.post("/api/process-video")
async def process_video(request: VideoRequest):
    """
    1. Receives a video URL from Swift.
    2. Downloads and transcribes the audio using Whisper.
    3. Sends the transcript & metadata to OpenAI for extraction.
    4. Returns a strictly formatted JSON list of locations.
    """
    try:
        print(f"--- Starting pipeline for URL: {request.url} ---")
        
        # Step 1: Run your Whisper pipeline
        # We pass output_file=None so it doesn't clutter your folder with text files during API calls
        transcript_text = await transcribe_video(request.url, language="en", output_file=None)
        
        if not transcript_text:
            raise HTTPException(status_code=400, detail="Failed to transcribe the video.")

        print("--- Transcription complete. Extracting locations with AI... ---")
        
        # Step 2: Send the formatted transcript (which includes the caption!) to OpenAI
        client = get_openai_client()
        completion = client.beta.chat.completions.parse(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "system", 
                    "content": "You are a geospatial data extractor. Read the provided video metadata and transcript. Extract every specific physical location mentioned. Categorize them logically (e.g., Museum, Cafe, Park, Landmark, Restaurant, etc BUT NOT limited to these. Use the categories that best fit the locations)."
                },
                {
                    "role": "user", 
                    "content": transcript_text
                }
            ],
            response_format=LocationExtraction,
        )
        
        clean_data = completion.choices[0].message.parsed
        
        print("--- Pipeline successful! Returning JSON to app. ---")
        return clean_data

    except HTTPException:
        raise
    except Exception as e:
        print(f"Pipeline error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Server error: {str(e)}")