import os
from flask import Flask, send_file, request
import subprocess
import json
import tempfile

app = Flask(__name__)

PIXLET_WRAPPER = """
load("encoding/json.star", "json")

# Parse the config JSON
config = json.decode(CONFIG_JSON)

# Inject config into globals
for key, value in config.items():
    globals()[key] = value

{original_content}

if __name__ == "__main__":
    main()
"""

# Get the directory of the current script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PIXLET_APPS_DIR = os.path.join(SCRIPT_DIR, 'pixlet_apps')
CACHE_DIR = os.path.join(SCRIPT_DIR, 'cache')

# Ensure cache directory exists
os.makedirs(CACHE_DIR, exist_ok=True)

@app.route('/get_image')
def get_image():
    app_name = request.args.get('app', 'clock')
    app_name = ''.join(c for c in app_name if c.isalnum() or c in ('_', '-'))
    
    app_path = os.path.join(PIXLET_APPS_DIR, f"{app_name}.star")
    
    if not os.path.exists(app_path):
        return f"App not found: {app_path}", 404
    
    output_path = os.path.join(CACHE_DIR, f"{app_name}_output.webp")
    
    try:
        # Render Pixlet app to WebP
        subprocess.run(['pixlet', 'render', app_path, '--output', output_path], check=True)
    except subprocess.CalledProcessError as e:
        return f"Error rendering Pixlet app: {e}", 500
    
    return send_file(output_path, mimetype='image/webp')

@app.route('/render_app', methods=['POST'])
def render_app():
    data = request.json
    app_name = data.get('app_name')
    config = data.get('config', {})

    # Path to the original .star file
    original_app_path = os.path.join(PIXLET_APPS_DIR, f"{app_name}.star")

    if not os.path.exists(original_app_path):
        return "App not found", 404

    # Create a temporary file with the wrapped content
    with open(original_app_path, 'r') as original_file:
        original_content = original_file.read()
    
    config_json = json.dumps(config)
    wrapped_content = PIXLET_WRAPPER.format(original_content=original_content)
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='.star', delete=False) as temp_file:
        temp_file.write(f'CONFIG_JSON = """{config_json}"""\n\n')
        temp_file.write(wrapped_content)
        temp_file_path = temp_file.name

    output_path = os.path.join(CACHE_DIR, f"{app_name}_output.webp")


    # Run pixlet with the wrapped file
    try:
        subprocess.run(
            ['pixlet', 'render', temp_file_path, '--output', output_path],
            capture_output=True, text=True, check=True
        )
        
        return send_file(output_path, mimetype='image/webp')
    except subprocess.CalledProcessError as e:
        return f"Error rendering app: {e.stderr}", 500
    finally:
        # Clean up the temporary file
        os.unlink(temp_file_path)
