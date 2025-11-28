import base64
import os
import uuid

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel

app = FastAPI()

# Folder to save received images
SAVE_DIR = "received_images"
os.makedirs(SAVE_DIR, exist_ok=True)


# Define request body
class ImageData(BaseModel):
    filename: str
    data: str  # base64 encoded image


@app.post("/upload-image/")
async def upload_image(image: ImageData):
    try:
        # Decode base64
        image_bytes = base64.b64decode(image.data)

        # Safe filename with UUID
        safe_name = f"{uuid.uuid4()}_{image.filename}"
        file_path = os.path.join(SAVE_DIR, safe_name)

        # Write image to disk
        with open(file_path, "wb") as f:
            f.write(image_bytes)

        return {"message": "Image received and saved", "path": file_path}

    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid image data: {e}")
