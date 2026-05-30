@echo off
cd /d "%~dp0"
python -m venv .venv 2>nul
call .venv\Scripts\activate.bat
pip install -r requirements.txt -q
uvicorn main:app --reload --host 0.0.0.0 --port 8000
