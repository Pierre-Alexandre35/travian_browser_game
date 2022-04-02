import uvicorn
from src import create_app

app = create_app()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", log_level="info", reload=True)
