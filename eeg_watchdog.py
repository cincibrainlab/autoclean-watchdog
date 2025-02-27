"""
Minimal EEG Data Watchdog Monitor

Monitors a directory for new EEG data files and processes them with a specified script.
Tracks processed files to avoid reprocessing.
"""

import os
import time
import argparse
import subprocess
import logging
import csv
from datetime import datetime
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

# Tracking files
SUCCESS_TRACKER = "processed_files.csv"
ERROR_TRACKER = "error_files.csv"

# Host path environment variables
HOST_INPUT_DIR = os.environ.get('INPUT_DIR', '')
HOST_OUTPUT_DIR = os.environ.get('OUTPUT_DIR', '')
HOST_CONFIG_DIR = os.environ.get('CONFIG_DIR', '')
HOST_AUTOCLEAN_DIR = os.environ.get('AUTOCLEAN_DIR', '')

class EEGFileHandler(FileSystemEventHandler):
    def __init__(self, monitor_dir, extensions, script_path, task, config_path, output_dir, work_dir):
        """Initialize the EEG file handler with minimal parameters."""
        self.monitor_dir = monitor_dir
        self.extensions = [ext.lower() if ext.startswith('.') else f'.{ext.lower()}' for ext in extensions]
        self.script_path = script_path
        self.task = task
        self.config_path = config_path
        self.output_dir = output_dir
        self.work_dir = work_dir
        
        # Setup tracking files
        self.success_tracker_path = os.path.join(monitor_dir, SUCCESS_TRACKER)
        self.error_tracker_path = os.path.join(monitor_dir, ERROR_TRACKER)
        
        # Load tracking data
        self.processed_files = self._load_processed_files()
        
        # Ensure output directory exists
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
            logger.info(f"Created output directory: {output_dir}")
    
    def _load_processed_files(self):
        """Load list of previously processed files."""
        processed = set()
        
        if os.path.exists(self.success_tracker_path):
            try:
                with open(self.success_tracker_path, 'r', newline='') as csvfile:
                    reader = csv.DictReader(csvfile)
                    for row in reader:
                        if 'filename' in row:
                            processed.add(row['filename'])
            except Exception as e:
                logger.error(f"Error reading success tracker: {e}")
        
        return processed
    
    def _record_success(self, file_path):
        """Record successfully processed file."""
        filename = os.path.basename(file_path)
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        
        file_exists = os.path.exists(self.success_tracker_path)
        
        with open(self.success_tracker_path, 'a', newline='') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=['filename', 'timestamp', 'filepath'])
            
            if not file_exists:
                writer.writeheader()
            
            writer.writerow({
                'filename': filename,
                'timestamp': timestamp,
                'filepath': file_path
            })
        
        logger.info(f"Recorded successful processing of {filename}")
        self.processed_files.add(filename)
    
    def _record_error(self, file_path, error_message):
        """Record file processing error."""
        filename = os.path.basename(file_path)
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        
        file_exists = os.path.exists(self.error_tracker_path)
        
        with open(self.error_tracker_path, 'a', newline='') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=['filename', 'timestamp', 'filepath', 'error'])
            
            if not file_exists:
                writer.writeheader()
            
            writer.writerow({
                'filename': filename,
                'timestamp': timestamp,
                'filepath': file_path,
                'error': error_message[:200]  # Limit error message length
            })
        
        logger.info(f"Recorded error for {filename}")
    
    def on_created(self, event):
        """Handle file creation events."""
        if not event.is_directory:
            file_path = event.src_path
            if self._should_process(file_path):
                logger.info(f"New EEG data file detected: {file_path}")
                self._process_file(file_path)
    
    def _should_process(self, file_path):
        """Determine if a file should be processed."""
        # Check if it has the right extension
        file_ext = os.path.splitext(file_path)[1].lower()
        if file_ext not in self.extensions:
            return False
        
        # Check if it's already been processed
        filename = os.path.basename(file_path)
        if filename in self.processed_files:
            logger.info(f"Skipping already processed file: {file_path}")
            return False
        
        return True
    
    def process_existing_files(self):
        """Process existing files in the monitored directory."""
        logger.info(f"Checking for existing files in {self.monitor_dir}")
        for file in os.listdir(self.monitor_dir):
            file_path = os.path.join(self.monitor_dir, file)
            if os.path.isfile(file_path) and self._should_process(file_path):
                logger.info(f"Found existing EEG data file to process: {file_path}")
                self._process_file(file_path)
    
    def _process_file(self, file_path):
        """Process an EEG data file using the autoclean script."""
        try:
            # Make sure the script is executable
            if not os.access(self.script_path, os.X_OK):
                subprocess.run(['chmod', '+x', self.script_path], check=True)
                logger.info(f"Made script executable: {self.script_path}")
            
            # Convert container paths to host paths if environment variables are available
            host_file_path = file_path
            host_config_path = self.config_path
            host_output_path = self.output_dir
            
            # Convert input file path
            if HOST_INPUT_DIR and file_path.startswith('/data/input/'):
                rel_path = os.path.relpath(file_path, '/data/input')
                host_file_path = os.path.join(HOST_INPUT_DIR, rel_path)
                logger.info(f"Converted container input path {file_path} to host path {host_file_path}")
            
            # Convert config path
            if HOST_CONFIG_DIR and self.config_path.startswith('/app/configs/'):
                # Extract just the directory part, not the file
                host_config_path = HOST_CONFIG_DIR
                logger.info(f"Using host config directory: {host_config_path}")
            
            # Convert output path
            if HOST_OUTPUT_DIR and self.output_dir.startswith('/data/output'):
                host_output_path = HOST_OUTPUT_DIR
                logger.info(f"Using host output path: {host_output_path}")

            host_autoclean_path = HOST_AUTOCLEAN_DIR
            
            # Run the autoclean script with host paths
            command = [
                self.script_path,
                "-DataPath", host_file_path,
                "-Task", self.task,
                "-ConfigPath", host_config_path,
                "-OutputPath", host_output_path,
                "-WorkDir", host_autoclean_path
            ]
            
            logger.info(f"Processing file: {file_path}")
            logger.info(f"Using host paths in command: {' '.join(command)}")
            
            # Pass along the original environment variables
            # Don't use check=True so we can capture output even on failure
            result = subprocess.run(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=os.environ
            )
            
            # Log the output regardless of success/failure
            if result.stdout:
                logger.info(f"Script stdout: {result.stdout}")
            if result.stderr:
                logger.warning(f"Script stderr: {result.stderr}")
            
            # Check return code after capturing output
            if result.returncode != 0:
                raise subprocess.CalledProcessError(
                    result.returncode, 
                    command, 
                    output=result.stdout, 
                    stderr=result.stderr
                )
            
            logger.info(f"EEG data processing completed successfully for: {file_path}")
            self._record_success(file_path)
            
        except subprocess.CalledProcessError as e:
            logger.error(f"Error processing file {file_path}: {e}")
            logger.error(f"Script stdout: {e.output}")
            logger.error(f"Script stderr: {e.stderr}")
            self._record_error(file_path, str(e.stderr))
            
        except Exception as e:
            logger.error(f"Unexpected error processing file {file_path}: {str(e)}")
            self._record_error(file_path, str(e))


def main():
    """Main entry point of the script."""
    parser = argparse.ArgumentParser(description='Minimal EEG data file monitor')
    parser.add_argument('--dir', '-d', required=True, help='Directory to monitor')
    parser.add_argument('--extensions', '-e', required=True, nargs='+', help='File extensions to monitor')
    parser.add_argument('--script', '-s', required=True, help='Processing script path')
    parser.add_argument('--task', '-t', required=True, help='EEG processing task type')
    parser.add_argument('--config', '-c', required=True, help='Config file path')
    parser.add_argument('--output', '-o', required=True, help='Output directory')
    parser.add_argument('--work_dir', '-w', required=True, help='Working directory')
    parser.add_argument('--reset-tracking', action='store_true', help='Reset tracking files')
    
    args = parser.parse_args()
    
    # Log environment variables for debugging
    logger.info(f"INPUT_DIR: {os.environ.get('INPUT_DIR', '')}")
    logger.info(f"OUTPUT_DIR: {os.environ.get('OUTPUT_DIR', '')}")
    logger.info(f"CONFIG_DIR: {os.environ.get('CONFIG_DIR', '')}")
    logger.info(f"AUTOCLEAN_DIR: {os.environ.get('AUTOCLEAN_DIR', '')}")
    
    # Reset tracking if requested
    if args.reset_tracking:
        success_tracker = os.path.join(args.dir, SUCCESS_TRACKER)
        error_tracker = os.path.join(args.dir, ERROR_TRACKER)
        
        if os.path.exists(success_tracker):
            os.remove(success_tracker)
            logger.info(f"Reset success tracker: {success_tracker}")
            
        if os.path.exists(error_tracker):
            os.remove(error_tracker)
            logger.info(f"Reset error tracker: {error_tracker}")
    
    # Initialize the handler and observer
    handler = EEGFileHandler(
        args.dir,
        args.extensions,
        args.script,
        args.task,
        args.config,
        args.output,
        args.work_dir
    )
    
    observer = Observer()
    observer.schedule(handler, args.dir, recursive=True)
    observer.start()
    
    logger.info(f"Started monitoring directory: {args.dir}")
    logger.info(f"Watching for files with extensions: {', '.join(args.extensions)}")
    
    try:
        # Process existing files first
        handler.process_existing_files()
        
        # Keep the script running
        while True:
            time.sleep(1)
            
    except KeyboardInterrupt:
        logger.info("Stopping monitoring")
        observer.stop()
        
    observer.join()


if __name__ == "__main__":
    main()