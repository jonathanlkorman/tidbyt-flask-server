# Tidbyt Server

This project is a server application for rendering Tidbyt apps using Pixlet. It allows you to create and serve custom Tidbyt apps dynamically, which can be displayed on an LED matrix controlled by a Raspberry Pi.

## Overview

This project is part of a two-component system:

1. **Tidbyt Server (This repository)**: Renders Tidbyt apps and serves WebP images.
2. **LED Matrix Project**: A separate project running on a Raspberry Pi that fetches images from this server and displays them on an LED matrix.

## Table of Contents

1. [How it Works](#how-it-works)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [Running the Server](#running-the-server)
5. [Adding and Creating Apps](#adding-and-creating-apps)
6. [Helper Files](#helper-files)
7. [API Usage](#api-usage)
8. [Connecting with the LED Matrix Project](#connecting-with-the-led-matrix-project)
9. [Troubleshooting](#troubleshooting)
## How it Works

1. This server hosts and renders Tidbyt apps written in Starlark.
2. It exposes an API endpoint that accepts requests for specific apps and configurations.
3. When a request is received, the server renders the app and returns a WebP image.
4. The LED Matrix Project running on a Raspberry Pi periodically fetches these images and displays them.

## Prerequisites

- Docker
- Docker Compose

## Installation

1. Clone the repository:
   ```
   git clone https://github.com/jonathanlkorman/tidbyt-flask-server.git
   cd tidbyt-server
   ```

2. Build the Docker image:
   ```
   docker-compose build
   ```

## Running the Server

To start the server, run:

```
docker-compose up
```

The server will be available at `http://localhost:8000`.

## Adding and Creating Apps

### Adding Existing Apps

To add an existing Tidbyt app:

1. Create a new `.star` file in the `pixlet_apps` directory.
2. Copy the app code into the file.
3. Restart the server to load the new app.

### Creating New Apps

To create a new Tidbyt app:

1. Create a new `.star` file in the `pixlet_apps` directory.
2. Write your app code using the Starlark language and Tidbyt's Pixlet library.
3. Use the following template as a starting point:

```starlark
load("render.star", "render")
load("schema.star", "schema")

def main(config):
    return render.Root(
        child = render.Text("Hello, Tidbyt!")
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields = []
    )
```

4. Restart the server to load the new app.

## Helper Files

Helper files are Python scripts that can be used to fetch data or perform complex operations for your Tidbyt apps. To use a helper file:

1. Create a new Python file in the `helpers` directory (e.g., `my_helper.py`).
2. Implement a `get_data(config)` function in your helper file. This function should return a dictionary containing the data your app needs.
3. In your `.star` file, add a comment at the top specifying the helper:
   ```starlark
   # HELPER: my_helper
   ```
4. Access the helper data in your `main` function:
   ```starlark
   def main(config):
       helper_data = json.decode(config.str("helper_data", "{}"))
       # Use helper_data in your app
   ```

## API Usage

To render an app, send a POST request to `/render_app` with the following JSON payload:

```json
{
  "app_name": "your_app_name",
  "config": {
    "key1": "value1",
    "key2": "value2"
  }
}
```

The server will return a WebP image of the rendered app.

## Connecting with the LED Matrix Project

To use this server with the LED Matrix Project:

1. Ensure this server is running and accessible from your Raspberry Pi.
2. In the LED Matrix Project's configuration, set the `server_url` to point to this server's address and port.
3. The LED Matrix Project will automatically fetch and display images rendered by this server.

## Troubleshooting

- If the LED Matrix Project is not displaying images:
  - Ensure this server is running and accessible from the Raspberry Pi's network.
  - Check the server logs for any error messages related to rendering or API requests.
  - Verify that the app names in the API requests match the `.star` files in the `pixlet_apps` directory.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.