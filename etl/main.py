"""Root entry point for the JanMat ETL pipeline."""
from app.main import create_app

app = create_app()
