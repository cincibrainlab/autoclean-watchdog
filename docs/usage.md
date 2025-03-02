# Usage Examples

## Automatic Processing

Simply place EEG data files in the `input` directory. The system will automatically detect and process them according to your configuration.

## Manual Processing

### Windows

```powershell
# Import the autoclean function
. ./scripts/autoclean.ps1

# Process a file
autoclean -DataPath "C:\path\to\data.edf" -Task "RestingEyesOpen" -ConfigPath "C:\path\to\config.yaml"
```

### Linux/Mac

```bash
# Make the script executable
chmod +x ./scripts/autoclean.sh

# Process a file
./scripts/autoclean.sh -DataPath "/path/to/data.edf" -Task "RestingEyesOpen" -ConfigPath "/path/to/config.yaml"
```

## Command-Line Parameters

### Watchdog Script

The `eeg_watchdog.py` script accepts the following parameters:

- `--dir`, `-d`: Directory to monitor for new EEG data files
- `--extensions`, `-e`: EEG data file extensions to monitor
- `--script`, `-s`: Path to the autoclean script
- `--task`, `-t`: EEG processing task type
- `--config`, `-c`: Path to configuration YAML file
- `--output`, `-o`: Output directory for processed files
- `--work_dir`, `-w`: Working directory for the autoclean pipeline
- `--max-workers`: Maximum number of concurrent processing tasks (default: 3)
- `--max-retries`: Maximum number of retries for error files (default: 3)
- `--reset-tracking`: Reset the tracking files and reprocess all files

## Adjusting Configuration Options

### Maximum Concurrent Processes

Adjust the `--max-workers` parameter in `docker-compose.yml` to control how many files can be processed simultaneously:

```yaml
command: 
  # ... other parameters ...
  - "--max-workers"
  - "5"  # Process up to 5 files simultaneously
```

### File Extensions

Modify the `--extensions` parameter in `docker-compose.yml` to specify which file types to monitor:

```yaml
command:
  # ... other parameters ...
  - "--extensions"
  - "edf"
  - "set"
  - "vhdr"
  - "bdf"
  - "cnt"
```

### Processing Task

Change the `--task` parameter to specify a different processing task:

```yaml
command:
  # ... other parameters ...
  - "--task"
  - "ASSR"  # Change from default "RestingEyesOpen"
```
