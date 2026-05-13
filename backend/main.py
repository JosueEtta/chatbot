from collections.abc import AsyncIterable
from fastapi.sse import EventSourceResponse
from fastapi.responses import StreamingResponse
from fastapi import FastAPI
import ollama

app = FastAPI()   




@app.get("/",response_class=EventSourceResponse)
async def read_root(question: str) -> AsyncIterable[str]:
        res = ollama.chat(
            model="phi3",
            messages=[
                {
                    "role": "user",
                    "content": question
                }    
            ],
            stream=True
        )

        for chunk in res:
            yield chunk["message"]["content"]
  
