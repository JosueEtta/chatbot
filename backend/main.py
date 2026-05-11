from fastapi import FastAPI
import ollama

app = FastAPI()   


@app.get("/")
def read_root(question: str):
# print(ollama.list())

 res = ollama.chat(
    model = "phi3",
    messages = [
        {
            "role": "user",
            "content": question
        }    
    ],

 )

 return {"response": res["message"]["content"]}
 



