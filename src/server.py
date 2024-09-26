import os
from flask import Flask, send_file, request
import subprocess
import pixlet
import io

app = Flask(__name__)

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
    app_path = os.path.join(PIXLET_APPS_DIR, f"{app_name}.star")


    if not os.path.exists(app_path):
        return "App not found", 404

    try:
        # Load the Starlark script
        with open(app_path, 'r') as file:
            script_content = file.read()

        # Create a Pixlet runtime
        runtime = pixlet.Runtime()

        # Inject config into the runtime's global namespace
        for key, value in config.items():
            runtime.set_value(key, value)

        # Execute the script
        mod = runtime.exec_module(script_content)

        # Call the main function
        main_func = mod.get_value('main')
        result = main_func()

        # Render the result to WebP
        webp_data = pixlet.render(result)

        # Create an in-memory file-like object
        webp_file = io.BytesIO(webp_data)
        webp_file.seek(0)

        return send_file(webp_file, mimetype='image/webp')

    except Exception as e:
        return f"Error rendering app: {str(e)}", 500