import os
from flask import Flask, send_file, request
import subprocess
import json
import tempfile
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

PIXLET_WRAPPER = """
load("encoding/json.star", "json")

CONFIG_JSON = '''{config_json}'''

{original_content}

def main():
    config = json.decode(CONFIG_JSON)
    return original_main(config)
"""

# Get the directory of the current script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PIXLET_APPS_DIR = os.path.join(SCRIPT_DIR, 'pixlet_apps')
CACHE_DIR = os.path.join(SCRIPT_DIR, 'cache')

print(f"SCRIPT_DIR: {SCRIPT_DIR}")
print(f"PIXLET_APPS_DIR: {PIXLET_APPS_DIR}")
print(f"CACHE_DIR: {CACHE_DIR}")

# Ensure cache directory exists
os.makedirs(CACHE_DIR, exist_ok=True)

@app.route('/render_app', methods=['POST'])
def render_app():
    data = request.json
    app_name = data.get('app_name')
    config = data.get('config', {})

    logger.info(f"Received request for app: {app_name}")
    logger.info(f"Config: {json.dumps(config, indent=2)}")

    # Sanitize app_name to prevent directory traversal
    app_name = ''.join(c for c in app_name if c.isalnum() or c in ('_', '-'))
    original_app_path = os.path.join(PIXLET_APPS_DIR, f"{app_name}.star")

    if not os.path.exists(original_app_path):
        logger.error(f"File not found: {original_app_path}")
        return "App not found", 404
    
    logger.info(f"File found: {original_app_path}")

    try:
        with open(original_app_path, 'r') as original_file:
            original_content = original_file.read()
        
        modified_content_main = original_content.replace('def main(', 'def original_main(')
        modified_content = modified_content_main.replace('load("encoding/json.star", "json")', '')

        config_json = json.dumps(config).replace("'", "\\'").replace('"', '\\"')
        
        wrapped_content = PIXLET_WRAPPER.format(
            config_json=config_json,
            original_content=modified_content
        )

        logger.info(f"Wrapped Content: {wrapped_content}")
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.star', delete=False) as temp_file:
            temp_file.write(wrapped_content)
            temp_file_path = temp_file.name

        output_path = os.path.join(CACHE_DIR, f"{app_name}_output.webp")

        logger.info(f"Running Pixlet command: pixlet render {temp_file_path} --output {output_path}")
        result = subprocess.run(
            ['pixlet', 'render', temp_file_path, '--output', output_path],
            capture_output=True, text=True, check=True
        )

        logger.info(f"Pixlet command completed successfully")
        logger.debug(f"Pixlet output: {result.stdout}")
        
        return send_file(output_path, mimetype='image/webp')

    except subprocess.CalledProcessError as e:
        logger.error(f"Error in Pixlet execution: {e.stderr}")
        return f"Error rendering app: {e.stderr}", 500
    except Exception as e:
        logger.exception("Unexpected error occurred")
        return f"Unexpected error: {str(e)}", 500
    finally:
        if 'temp_file_path' in locals():
            os.unlink(temp_file_path)
