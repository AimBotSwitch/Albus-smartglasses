import base64
import os
import uuid

from fastapi import FastAPI, HTTPException, Request

from openai import OpenAI
from pydantic import BaseModel

app = FastAPI()
openai_client = OpenAI()


# Folder to save received images
SAVE_DIR = "received_images"
os.makedirs(SAVE_DIR, exist_ok=True)


# Define request body
class ImageData(BaseModel):
    filename: str
    data: str  # base64 encoded image
    question: str | None = None  # optional custom question


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


@app.post("/explain-image/")
async def explain_image(image: ImageData):
    try:
        # Decode base64
        image_bytes = base64.b64decode(image.data)
        # Safe filename with UUID
        safe_name = f"{uuid.uuid4()}_{image.filename}"
        file_path = os.path.join(SAVE_DIR, safe_name)

        # Write image to disk
        with open(file_path, "wb") as f:
            f.write(image_bytes)

        # Function to encode the image
        def encode_image(image_path):
            with open(image_path, "rb") as image_file:
                return base64.b64encode(image_file.read()).decode("utf-8")

        base64_image = encode_image(file_path)

        # Use custom question if provided, otherwise use default
        question_text = (
            image.question
            if image.question
            else "what's in this image? explain in less than 10 words"
        )

        response = openai_client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": question_text,
                        },
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{base64_image}"
                            },
                        },
                    ],
                }
            ],
        )
        return {"message": response.choices[0].message.content}

    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid image data: {e}")
