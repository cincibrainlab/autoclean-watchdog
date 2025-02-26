# Troubleshooting Guide

This document contains solutions for common issues you might encounter when using the EEG Data Processing Watchdog.

## Docker Issues

### Docker Not Running

**Symptoms:**
- Error messages containing "Cannot connect to the Docker daemon"
- "Docker daemon not running" errors

**Solutions:**
1. **For Windows/Mac:** Ensure Docker Desktop is running
   - Check for the Docker icon in the system tray/menu bar
   - Start Docker Desktop from your applications if it's not running

2. **For Linux:** Start the Docker service
   ```bash
   sudo systemctl start docker
   ```

3. **Check Docker status:**
   ```bash
   docker info
   ```

### Docker Permission Issues

**Symptoms:**
- "Permission denied" errors when interacting with Docker
- Container fails to start with permission-related errors

**Solutions:**
1. **Add your user to the docker group (Linux):**
   ```bash
   sudo usermod -aG docker $USER
   # Log out and log back in for changes to take effect
   ```

2. **Run with sudo (temporary solution):**
   ```bash
   sudo docker-compose up -d
   ```

### Container Build Failures

**Symptoms:**
- `docker-compose build` fails
- Error messages during the build process

**Solutions:**
1. **Check your internet connection**

2. **View detailed build logs:**
   ```bash
   docker-compose build --progress=plain
   ```

3. **Cleanup Docker:**
   ```bash
   docker system prune -a
   docker-compose build --no-cache
   ```

## Watchdog Issues

### No Files Being Processed

**Symptoms:**
- Files are placed in the input directory but nothing happens
- No error messages in the logs

**Solutions:**
1. **Check file extensions:**
   - Ensure the file extensions match those specified in `docker-compose.yml`
   - File extensions are case-sensitive

2. **Check file permissions:**
   - Ensure the files in the input directory are readable

3. **Check watchdog logs:**
   ```bash
   docker-compose logs -f
   ```

4. **Restart the container:**
   ```bash
   docker-compose down
   docker-compose up -d
   ```

### Files Processed But No Output

**Symptoms:**
- Container logs show successful processing
- No files appear in the output directory

**Solutions:**
1. **Check output directory permissions:**
   - Ensure the output directory is writable by Docker

2. **Check container output logs:**
   ```bash
   docker-compose logs -f | grep "Processing completed"
   ```

3. **Check if processing actually failed:**
   - Look for error messages in the logs
   - Examine individual job logs in `output/[timestamp]_[filename]_[task]/process.log`

## Concurrent Processing Issues

### Too Many Processes Running

**Symptoms:**
- System performance degrades significantly
- High CPU/memory usage

**Solutions:**
1. **Reduce max workers:**
   - Edit `docker-compose.yml` and reduce the `--max-workers` parameter
   ```yaml
   command:
     # ... other parameters ...
     - "--max-workers"
     - "2"  # Reduced from default 3
   ```

2. **Restart the container with new settings:**
   ```bash
   docker-compose down
   docker-compose up -d
   ```

### Processing Queue Gets Stuck

**Symptoms:**
- Some files never get processed
- Processing seems to stop after some files

**Solutions:**
1. **Check for orphaned lock files:**
   - These may be in `/tmp/autoclean_*.lock` inside the container

2. **Access the container and check processes:**
   ```bash
   docker exec -it eeg-watchdog_eeg-watchdog_1 bash
   ps aux
   ```

3. **Restart the container:**
   ```bash
   docker-compose down
   docker-compose up -d
   ```

## Autoclean Processing Issues

### Processing Errors

**Symptoms:**
- Container logs show errors during processing
- Error messages in job logs

**Solutions:**
1. **Check your configuration file:**
   - Ensure your autoclean configuration YAML is valid
   - Check for typos or missing parameters

2. **Verify file validity:**
   - Ensure your EEG data files are in the correct format
   - Try processing a known good file as a test

3. **Examine detailed logs:**
   - Check the specific job log at `output/[timestamp]_[filename]_[task]/process.log`

4. **Test with Docker directly:**
   ```bash
   docker run --rm \
     -v "$(pwd)/input:/data" \
     -v "$(pwd)/config:/config" \
     -v "$(pwd)/output:/output" \
     autoclean-image \
     -DataPath "/data/your_file.edf" \
     -Task "RestingEyesOpen" \
     -ConfigPath "/config/autoclean_config.yaml" \
     -OutputPath "/output"
   ```

## Advanced Troubleshooting

### Debug Mode

Enable detailed debug logging by modifying the logging level in `eeg_watchdog.py`:

```python
# Change this line
logging.basicConfig(
    level=logging.INFO,
    ...
)

# To:
logging.basicConfig(
    level=logging.DEBUG,
    ...
)
```

Then rebuild and restart the container:
```bash
docker-compose down
docker-compose build
docker-compose up -d
```

### Accessing Container Shell

Access the running container to debug from inside:

```bash
docker exec -it eeg-watchdog_eeg-watchdog_1 bash
```

### Checking Container Logs

View all container logs:

```bash
docker-compose logs -f
```

View logs for specific containers:

```bash
docker-compose logs -f eeg-watchdog
```

### Checking Docker Resource Usage

```bash
docker stats
```

If you're experiencing issues not covered by this guide, please check the container logs for more details and consider filing an issue on the repository with your log outputs.
