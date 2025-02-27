"""
EEG Data Watchdog Monitor

This script monitors a directory for new EEG data files and processes them using the
autoclean pipeline with the specified parameters. It handles multiple files concurrently
with a configurable maximum number of simultaneous processes.

It tracks processed files in CSV tracking files to avoid reprocessing files on restart.
"""

import os
import sys
import time
import argparse
import subprocess
import logging
import shutil
import threading
import queue
import csv
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

# Global file processing queue
file_queue = queue.Queue()

# Global tracking files
SUCCESS_TRACKER = "processed_files.csv"
ERROR_TRACKER = "error_files.csv"

# Host path environment variables
HOST_INPUT_DIR = os.environ.get('INPUT_DIR', '')
HOST_OUTPUT_DIR = os.environ.get('OUTPUT_DIR', '')
HOST_CONFIG_DIR = os.environ.get('CONFIG_DIR', '')
HOST_AUTOCLEAN_DIR = os.environ.get('AUTOCLEAN_DIR', '')

class EEGFileHandler(FileSystemEventHandler):
    def __init__(self, extensions, script_path, task, config_path, output_dir, work_dir, max_retries):
        """
        Initialize the EEG file handler.
        
        Args:
            extensions (list): List of file extensions to monitor (EEG data file types)
            script_path (str): Path to the autoclean script
            task (str): EEG processing task type (RestingEyesOpen, ASSR, ChirpDefault, etc.)
            config_path (str): Path to configuration YAML file
            output_dir (str): Output directory for processed files
            work_dir (str): Working directory for the autoclean pipeline
            max_retries (int): Maximum number of retries for error files
        """
        self.extensions = [ext.lower() if ext.startswith('.') else f'.{ext.lower()}' for ext in extensions]
        self.script_path = script_path
        self.task = task
        self.config_path = config_path
        self.output_dir = output_dir
        self.work_dir = work_dir
        self.max_retries = max_retries
        
        # Load tracking data
        self.success_files = load_success_tracking()
        self.error_files = load_error_tracking()
        
        # Ensure the output directory exists
        if not os.path.exists(self.output_dir):
            os.makedirs(self.output_dir)
            logger.info(f"Created output directory: {self.output_dir}")
    
    def on_created(self, event):
        """Handle file creation events."""
        if not event.is_directory:
            file_path = event.src_path
            file_ext = os.path.splitext(file_path)[1].lower()
            
            if file_ext in self.extensions:
                logger.info(f"New EEG data file detected: {file_path}")
                
                # Check if the file should be processed
                should_process, retry_count = self.should_process_file(file_path)
                
                if should_process:
                    # Add the file to the processing queue with its processing parameters
                    file_queue.put({
                        'file_path': file_path,
                        'script_path': self.script_path,
                        'task': self.task,
                        'config_path': self.config_path,
                        'output_dir': self.output_dir,
                        'work_dir': self.work_dir,
                        'max_retries': self.max_retries,
                        'retry_count': retry_count
                    })
                else:
                    logger.info(f"Skipping already processed file: {file_path}")
    
    def should_process_file(self, file_path):
        """
        Determine if a file should be processed based on the tracking files.
        
        Args:
            file_path (str): Path to the file to check
            
        Returns:
            tuple: (should_process, retry_count) - True if file should be processed and current retry count
        """
        # Get the filename portion for tracking
        filename = os.path.basename(file_path)
        
        # Check if this file has been successfully processed
        if filename in self.success_files:
            return False, 0
        
        # Check if this file has errors and has reached max retries
        retry_count = 0
        if filename in self.error_files:
            retry_count = self.error_files[filename]
            if retry_count >= self.max_retries:
                logger.warning(f"File {filename} has reached max retries ({self.max_retries}). Skipping.")
                return False, retry_count
            
            logger.info(f"Retrying file {filename} (attempt {retry_count + 1}/{self.max_retries})")
        
        return True, retry_count


def load_success_tracking():
    """
    Load tracking data from the success CSV file.
    
    Returns:
        set: Set of filenames that have been successfully processed
    """
    success_files = set()
    
    if os.path.exists(SUCCESS_TRACKER):
        try:
            with open(SUCCESS_TRACKER, 'r', newline='') as csvfile:
                reader = csv.DictReader(csvfile)
                for row in reader:
                    if 'filename' in row:
                        success_files.add(row['filename'])
        except Exception as e:
            logger.error(f"Error reading success tracker file: {e}")
    
    return success_files


def load_error_tracking():
    """
    Load tracking data from the error CSV file.
    
    Returns:
        dict: Dictionary of filenames to retry counts
    """
    error_files = {}
    
    if os.path.exists(ERROR_TRACKER):
        try:
            with open(ERROR_TRACKER, 'r', newline='') as csvfile:
                reader = csv.DictReader(csvfile)
                for row in reader:
                    if 'filename' in row and 'retries' in row:
                        try:
                            error_files[row['filename']] = int(row['retries'])
                        except ValueError:
                            error_files[row['filename']] = 0
        except Exception as e:
            logger.error(f"Error reading error tracker file: {e}")
    
    return error_files


def record_success(file_path):
    """
    Record a successfully processed file in the CSV tracker.
    
    Args:
        file_path (str): Path to the successfully processed file
    """
    filename = os.path.basename(file_path)
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    
    # Create the file with headers if it doesn't exist
    file_exists = os.path.exists(SUCCESS_TRACKER)
    
    with open(SUCCESS_TRACKER, 'a', newline='') as csvfile:
        fieldnames = ['filename', 'timestamp', 'filepath']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        
        if not file_exists:
            writer.writeheader()
        
        writer.writerow({
            'filename': filename,
            'timestamp': timestamp,
            'filepath': file_path
        })
    
    logger.info(f"Recorded successful processing of {filename}")
    
    # Remove from error tracking if present
    remove_from_error_tracking(filename)


def record_error(file_path, error_message, retry_count):
    """
    Record a file processing error in the CSV tracker.
    
    Args:
        file_path (str): Path to the file that had a processing error
        error_message (str): Error message to record
        retry_count (int): Current retry count
    """
    filename = os.path.basename(file_path)
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    
    # Increment retry count
    retry_count += 1
    
    # Create a new error tracking file
    should_write_header = not os.path.exists(ERROR_TRACKER)
    
    # Get existing errors first (to avoid duplicate entries)
    error_entries = []
    error_files = {}
    
    if os.path.exists(ERROR_TRACKER):
        try:
            with open(ERROR_TRACKER, 'r', newline='') as csvfile:
                reader = csv.DictReader(csvfile)
                for row in reader:
                    # Skip the file we're updating
                    if row.get('filename') != filename:
                        error_entries.append(row)
                        if 'filename' in row and 'retries' in row:
                            try:
                                error_files[row['filename']] = int(row['retries'])
                            except ValueError:
                                error_files[row['filename']] = 0
        except Exception as e:
            logger.error(f"Error reading error tracker file: {e}")
    
    # Add/update the current file entry
    with open(ERROR_TRACKER, 'w', newline='') as csvfile:
        fieldnames = ['filename', 'timestamp', 'filepath', 'retries', 'error']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        
        if should_write_header:
            writer.writeheader()
        
        # Write existing entries
        for entry in error_entries:
            writer.writerow(entry)
        
        # Write the new/updated entry
        writer.writerow({
            'filename': filename,
            'timestamp': timestamp,
            'filepath': file_path,
            'retries': retry_count,
            'error': error_message[:200]  # Limit error message length
        })
    
    logger.info(f"Recorded error for {filename} (retry {retry_count})")


def remove_from_error_tracking(filename):
    """
    Remove a file from the error tracking CSV when it's successfully processed.
    
    Args:
        filename (str): Name of the file to remove
    """
    if not os.path.exists(ERROR_TRACKER):
        return
    
    entries = []
    
    try:
        with open(ERROR_TRACKER, 'r', newline='') as csvfile:
            reader = csv.DictReader(csvfile)
            fieldnames = reader.fieldnames
            for row in reader:
                if row.get('filename') != filename:
                    entries.append(row)
    
        with open(ERROR_TRACKER, 'w', newline='') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            for entry in entries:
                writer.writerow(entry)
    except Exception as e:
        logger.error(f"Error updating error tracking file: {e}")


def process_file(params):
    """
    Process an EEG data file using the autoclean script.
    
    Args:
        params (dict): Dictionary containing processing parameters
    
    Returns:
        bool: True if processing was successful, False otherwise
    """
    file_path = params['file_path']
    script_path = params['script_path']
    task = params['task']
    config_path = params['config_path']
    output_dir = params['output_dir']
    work_dir = params['work_dir']
    retry_count = params.get('retry_count', 0)
    
    try:
        # Make sure the script is executable
        if not os.access(script_path, os.X_OK):
            subprocess.run(['chmod', '+x', script_path], check=True)
            logger.info(f"Made autoclean script executable: {script_path}")
        
        # Convert container paths to host paths for Docker-in-Docker
        # Get the relative path from the container's input directory
        if HOST_INPUT_DIR and file_path.startswith('/data/input/'):
            rel_path = os.path.relpath(file_path, '/data/input')
            # Use os.path.join to handle path separators correctly for the OS
            host_file_path = os.path.join(HOST_INPUT_DIR, rel_path)
            # Normalize path to use forward slashes for consistency
            host_file_path = host_file_path.replace('\\', '/')
            logger.info(f"Converted container input path {file_path} to host path {host_file_path}")
        else:
            host_file_path = file_path
            logger.warning(f"Could not convert input path {file_path} to host path, using as is")
        
        # Set up environment variables for the script
        env = os.environ.copy()
        env['HOST_INPUT_DIR'] = HOST_INPUT_DIR
        env['HOST_OUTPUT_DIR'] = HOST_OUTPUT_DIR
        env['HOST_CONFIG_DIR'] = HOST_CONFIG_DIR
        env['HOST_AUTOCLEAN_DIR'] = HOST_AUTOCLEAN_DIR
        env['HOST_FILE_PATH'] = host_file_path
        
        # Run the autoclean script with the appropriate parameters
        command = [
            script_path,
            "-DataPath", file_path,
            "-Task", task,
            "-ConfigPath", config_path,
            "-OutputPath", output_dir,
            "-WorkDir", work_dir
        ]
        
        logger.info(f"Processing file: {file_path}")
        logger.info(f"Host file path: {host_file_path}")
        logger.info(f"Command: {' '.join(command)}")
        
        result = subprocess.run(
            command,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env
        )
        
        logger.info(f"EEG data processing completed successfully for: {file_path}")
        logger.debug(f"Script output: {result.stdout}")
        
        # Record success
        record_success(file_path)
        return True
        
    except subprocess.CalledProcessError as e:
        logger.error(f"Error processing file {file_path}: {e}")
        logger.error(f"Script stderr: {e.stderr}")
        
        # Record error
        record_error(file_path, str(e.stderr), retry_count)
        return False
    except Exception as e:
        logger.error(f"Unexpected error processing file {file_path}: {str(e)}")
        
        # Record error
        record_error(file_path, str(e), retry_count)
        return False


def worker_thread(max_workers):
    """
    Worker thread that manages the ThreadPoolExecutor for processing files.
    
    Args:
        max_workers (int): Maximum number of concurrent processing tasks
    """
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        while True:
            try:
                # Get file processing parameters from the queue
                params = file_queue.get(block=True, timeout=1)
                
                # Submit the processing task to the thread pool
                executor.submit(process_file, params)
                
                # Mark the task as done
                file_queue.task_done()
                
            except queue.Empty:
                # Queue is empty, continue waiting
                continue
            except Exception as e:
                logger.error(f"Error in worker thread: {str(e)}")
                # Mark the task as done even if there was an error
                file_queue.task_done()


def main():
    """Main entry point of the script."""
    parser = argparse.ArgumentParser(description='Monitor a directory for new EEG data files and process them with autoclean')
    parser.add_argument('--dir', '-d', required=True, help='Directory to monitor for new EEG data files')
    parser.add_argument('--extensions', '-e', required=True, nargs='+', help='EEG data file extensions to monitor (e.g., edf set vhdr)')
    parser.add_argument('--script', '-s', required=True, help='Path to the autoclean script')
    parser.add_argument('--task', '-t', required=True, help='EEG processing task type (RestingEyesOpen, ASSR, ChirpDefault, etc.)')
    parser.add_argument('--config', '-c', required=True, help='Path to configuration YAML file')
    parser.add_argument('--output', '-o', required=True, help='Output directory for processed files')
    parser.add_argument('--work_dir', '-w', required=True, help='Working directory for the autoclean pipeline')
    parser.add_argument('--max-workers', type=int, default=3, help='Maximum number of concurrent processing tasks (default: 3)')
    parser.add_argument('--max-retries', type=int, default=3, help='Maximum number of retries for error files (default: 3)')
    parser.add_argument('--reset-tracking', action='store_true', help='Reset the tracking files and reprocess all files')
    
    args = parser.parse_args()
    
    # Log host path environment variables
    logger.info(f"Host input directory: {HOST_INPUT_DIR}")
    logger.info(f"Host output directory: {HOST_OUTPUT_DIR}")
    logger.info(f"Host config directory: {HOST_CONFIG_DIR}")
    logger.info(f"Host autoclean directory: {HOST_AUTOCLEAN_DIR}")
    
    # Set paths for tracking files (place them in the monitored directory)
    global SUCCESS_TRACKER, ERROR_TRACKER
    SUCCESS_TRACKER = os.path.join(args.dir, SUCCESS_TRACKER)
    ERROR_TRACKER = os.path.join(args.dir, ERROR_TRACKER)
    
    # Reset tracking if requested
    if args.reset_tracking:
        logger.info("Resetting tracking files as requested")
        if os.path.exists(SUCCESS_TRACKER):
            os.remove(SUCCESS_TRACKER)
        if os.path.exists(ERROR_TRACKER):
            os.remove(ERROR_TRACKER)
    
    logger.info(f"Starting EEG data file monitoring in {args.dir}")
    logger.info(f"Watching for files with extensions: {', '.join(args.extensions)}")
    logger.info(f"Using autoclean script: {args.script}")
    logger.info(f"Task: {args.task}")
    logger.info(f"Config: {args.config}")
    logger.info(f"Output directory: {args.output}")
    logger.info(f"Working directory: {args.work_dir}")
    logger.info(f"Maximum concurrent processes: {args.max_workers}")
    logger.info(f"Maximum retries for error files: {args.max_retries}")
    logger.info(f"Success tracker file: {SUCCESS_TRACKER}")
    logger.info(f"Error tracker file: {ERROR_TRACKER}")
    
    # Start the worker thread for processing files
    worker = threading.Thread(target=worker_thread, args=(args.max_workers,), daemon=True)
    worker.start()
    
    # Initialize the event handler and observer
    event_handler = EEGFileHandler(
        args.extensions, 
        args.script, 
        args.task, 
        args.config, 
        args.output, 
        args.work_dir,
        args.max_retries
    )
    observer = Observer()
    observer.schedule(event_handler, args.dir, recursive=True)
    observer.start()
    
    try:
        # Process existing files in the monitored directory
        for file in os.listdir(args.dir):
            file_path = os.path.join(args.dir, file)
            if os.path.isfile(file_path):
                file_ext = os.path.splitext(file_path)[1].lower()
                if file_ext in event_handler.extensions:
                    # Check if we should process this file
                    should_process, retry_count = event_handler.should_process_file(file_path)
                    if should_process:
                        logger.info(f"Found existing EEG data file to process: {file_path}")
                        file_queue.put({
                            'file_path': file_path,
                            'script_path': args.script,
                            'task': args.task,
                            'config_path': args.config,
                            'output_dir': args.output,
                            'work_dir': args.work_dir,
                            'max_retries': args.max_retries,
                            'retry_count': retry_count
                        })
                    else:
                        logger.info(f"Skipping already processed file: {file_path}")
        
        # Keep the main thread alive
        while True:
            time.sleep(1)
            
    except KeyboardInterrupt:
        logger.info("Stopping EEG data file monitoring")
        observer.stop()
        
        # Wait for the file queue to be processed
        logger.info("Waiting for remaining files to be processed...")
        file_queue.join()
        logger.info("All processing complete, exiting.")
        
    observer.join()


if __name__ == "__main__":
    main()