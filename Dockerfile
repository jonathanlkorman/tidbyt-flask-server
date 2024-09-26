# Use an official Python runtime as a parent image
FROM python:3.9-slim

# Set the working directory in the container
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy the current directory contents into the container at /app
COPY . /app

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Download and install Pixlet
RUN curl -LO https://github.com/tidbyt/pixlet/releases/download/v0.33.5/pixlet_0.33.5_linux_amd64.tar.gz \
    && tar -xzf pixlet_0.33.5_linux_amd64.tar.gz \
    && chmod +x pixlet \
    && mv pixlet /usr/local/bin/ \
    && rm pixlet_0.33.5_linux_amd64.tar.gz

# Verify Pixlet installation
RUN pixlet version

# Make port 8000 available to the world outside this container
EXPOSE 8000

# Create a directory for the cache
RUN mkdir -p /app/cache

# Set the PYTHONPATH to include the src directory
ENV PYTHONPATH=/app/src:$PYTHONPATH

# Run gunicorn when the container launches
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "server:app"]