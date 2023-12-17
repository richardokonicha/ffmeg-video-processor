install:
	@python3 -m venv venv
	@. venv/bin/activate && pip install -r requirements.txt

video:
	@. venv/bin/activate && python process_folders.py
