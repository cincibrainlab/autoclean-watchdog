"""
EEG Data Watchdog Monitor

This script monitors a directory for new EEG data files and processes them using the
autoclean pipeline with the specified parameters. It handles multiple files concurrently
with a configurable maximum number of simultaneous processes.
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

class EEGFileHandler(FileSystemEventHandler):
    def __init__(self, extensions, script_path, task, config_path, output_dir):
        """
        Initialize the EEG file handler.
        
        Args:
            extensions (list): List of file extensions to monitor (EEG data file types)
            script_path (str): Path to the autoclean script
            task (str): EEG processing task type (RestingEyesOpen, ASSR, ChirpDefault, etc.)
            config_path (str): Path to configuration YAML file
            output_dir (str): Output directory for processed files
        """
        self.extensions = [ext.lower() if ext.startswith('.') else f'.{ext.lower()}' for ext in extensions]
        self.script_path = script_path
        self.task = task
        self.config_path = config_path
        self.output_dir = output_dir
        
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
                
                # Add the file to the processing queue with its processing parameters
                file_queue.put({
                    'file_path': file_path,
                    'script_path': self.script_path,
                    'task': self.task,
                    'config_path': self.config_path,
                    'output_dir': self.output_dir
                })


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
    
    try:
        # Make sure the script is executable
        if not os.access(script_path, os.X_OK):
            subprocess.run(['chmod', '+x', script_path], check=True)
            logger.info(f"Made autoclean script executable: {script_path}")
        
        # Run the autoclean script with the appropriate parameters
        command = [
            script_path,
            "-DataPath", file_path,
            "-Task", task,
            "-ConfigPath", config_path,
            "-OutputPath", output_dir
        ]
        
        logger.info(f"Processing file: {file_path}")
        logger.info(f"Command: {' '.join(command)}")
        
        result = subprocess.run(
            command,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        
        logger.info(f"EEG data processing completed successfully for: {file_path}")
        logger.debug(f"Script output: {result.stdout}")
        return True
        
    except subprocess.CalledProcessError as e:
        logger.error(f"Error processing file {file_path}: {e}")
        logger.error(f"Script stderr: {e.stderr}")
        return False
    except Exception as e:
        logger.error(f"Unexpected error processing file {file_path}: {str(e)}")
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
    parser.add_argument('--max-workers', '-w', type=int, default=3, help='Maximum number of concurrent processing tasks (default: 3)')
    
    args = parser.parse_args()
    
    # Ensure the input directory exists
    if not os.path.exists(args.dir):
        logger.error(f"Input directory does not exist: {args.dir}")
        sys.exit(1)
    
    # Ensure the script exists
    if not os.path.exists(args.script):
        logger.error(f"Autoclean script does not exist: {args.script}")
        sys.exit(1)
    
    # Ensure the config file exists
    if not os.path.exists(args.config):
        logger.error(f"Configuration file does not exist: {args.config}")
        sys.exit(1)
    
    logger.info(f"Starting EEG data file monitoring in {args.dir}")
    logger.info(f"Watching for files with extensions: {', '.join(args.extensions)}")
    logger.info(f"Using autoclean script: {args.script}")
    logger.info(f"Task: {args.task}")
    logger.info(f"Config: {args.config}")
    logger.info(f"Output directory: {args.output}")
    logger.info(f"Maximum concurrent processes: {args.max_workers}")
    
    # Start the worker thread for processing files
    worker = threading.Thread(target=worker_thread, args=(args.max_workers,), daemon=True)
    worker.start()
    
    # Initialize the event handler and observer
    event_handler = EEGFileHandler(args.extensions, args.script, args.task, args.config, args.output)
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
                    logger.info(f"Found existing EEG data file: {file_path}")
                    file_queue.put({
                        'file_path': file_path,
                        'script_path': args.script,
                        'task': args.task,
                        'config_path': args.config,
                        'output_dir': args.output
                    })
        
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
