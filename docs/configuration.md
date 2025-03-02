# Configuration Options

This document provides details on the configuration options for processing tasks in the EEG Data Processing Watchdog.

## Configuration File Structure

The configuration for processing tasks is defined in YAML files. Each task represents a different type of EEG recording (e.g., resting state, specific experiments). Below is an example configuration file structure:

```yaml
# =================================================================
# AUTOCLEAN CONFIGURATION FILE
# This file controls how EEG data is automatically processed and cleaned
# =================================================================

# TASK CONFIGURATION
tasks:
  # Example Task
  ExampleTask:
    mne_task: "example"
    description: "Example EEG Task"
    lossless_config: lossless_config_example.yaml    # Points to additional configuration settings
    settings:
      # PROCESSING STEPS
      resample_step:
        enabled: true        # Set to false to skip this step
        value: 250          # New sampling rate in Hz
      trim_step:
        enabled: true
        value: 10            # Number of seconds to trim from start/end
      reference_step:
        enabled: false
        value: "average"    # Type of EEG reference to use
      montage:
        enabled: false
        value: "ExampleMontage"  # Type of EEG cap/electrode layout
      event_id:
        enabled: false
        value: {}          # Empty since no triggers
      epoch_settings:
        enabled: true
        value:
          tmin: 0
          tmax: 2
        remove_baseline:
          enabled: false
          window: [null, 0]
        threshold_rejection:
          enabled: false
          volt_threshold: 
            eeg: 150e-6
    # ARTIFACT REJECTION SETTINGS
    rejection_policy:
      ch_flags_to_reject: ["noisy", "uncorrelated", "bridged"]  # Types of bad channels to reject
      ch_cleaning_mode: "interpolate"                           # How to handle bad channels
      interpolate_bads_kwargs:
        method: "MNE"                                          # Method for interpolating bad channels
      ic_flags_to_reject: ["muscle", "heart", "ch_noise", "line_noise"]  # Types of components to reject
      ic_rejection_threshold: 0.3                              # Threshold for component rejection
      remove_flagged_ics: true                                 # Whether to remove marked components   
```

## Modifying the Configuration

To modify the configuration, follow these steps:

1. Open the configuration file (e.g., `configs/autoclean_config.yaml`).
2. Locate the task you want to modify or add a new task.
3. Adjust the settings as needed. For example, to change the sampling rate for the `resample_step`, update the `value` field.
4. Save the changes to the configuration file.

## Example Configuration Files

Here are some example configuration files for different tasks:

### Resting State Task (Eyes Open)

```yaml
tasks:
  MouseXdatResting:
    mne_task: "rest"
    description: "Neuronexus Mouse XDAT Resting State"
    lossless_config: lossless_config_mea.yaml
    settings:
      resample_step:
        enabled: true
        value: 250
      trim_step:
        enabled: true
        value: 10
      reference_step:
        enabled: false
        value: "average"
      montage:
        enabled: false
        value: "MEA30"
      event_id:
        enabled: false
        value: {}
      epoch_settings:
        enabled: true
        value:
          tmin: 0
          tmax: 2
        remove_baseline:
          enabled: false
          window: [null, 0]
        threshold_rejection:
          enabled: false
          volt_threshold: 
            eeg: 150e-6
    rejection_policy:
      ch_flags_to_reject: ["noisy", "uncorrelated", "bridged"]
      ch_cleaning_mode: "interpolate"
      interpolate_bads_kwargs:
        method: "MNE"
      ic_flags_to_reject: ["muscle", "heart", "ch_noise", "line_noise"]
      ic_rejection_threshold: 0.3
      remove_flagged_ics: true
```

### Chirp Task

```yaml
tasks:
  MouseXdatChirp:
    mne_task: "chirp"
    description: "Neuronexus Mouse XDAT Chirp"
    lossless_config: configs/pylossless/lossless_config_mea.yaml
    settings:
      resample_step:
        enabled: true
        value: 250
      trim_step:
        enabled: true
        value: 4
      reference_step:
        enabled: false
        value: "average"
      montage:
        enabled: false
        value: "MEA30"
      event_id:
        enabled: true
        value: {'TTL_pulse_start': 1}
      epoch_settings:
        enabled: true
        value:
          tmin: -0.5
          tmax: 1.5
        remove_baseline:
          enabled: false
          window: [null, 0]
        threshold_rejection:
          enabled: false
          volt_threshold: 
            eeg: 150e-6
    rejection_policy:
      ch_flags_to_reject: ["noisy", "uncorrelated", "bridged"]
      ch_cleaning_mode: "interpolate"
      interpolate_bads_kwargs:
        method: "MNE"
      ic_flags_to_reject: ["muscle", "heart", "ch_noise", "line_noise"]
      ic_rejection_threshold: 0.3
      remove_flagged_ics: true
```

### ASSR Task

```yaml
tasks:
  MouseXdatAssr:
    mne_task: "assr"
    description: "Neuronexus Mouse XDAT ASSR State"
    lossless_config: lossless_config_mea.yaml
    settings:
      resample_step:
        enabled: false
        value: 250
      trim_step:
        enabled: true
        value: 4
      reference_step:
        enabled: true
        value: "average"
      montage:
        enabled: false
        value: "MEA30"
      event_id:
        enabled: true
        value: {'TTL_pulse_start'}
      epoch_settings:
        enabled: true
        value:
          tmin: -0.5
          tmax: 3
        remove_baseline:
          enabled: false
          window: [null, 0]
        threshold_rejection:
          enabled: false
          volt_threshold: 
            eeg: 150e-6
    rejection_policy:
      ch_flags_to_reject: ["noisy", "uncorrelated", "bridged"]
      ch_cleaning_mode: "interpolate"
      interpolate_bads_kwargs:
        method: "MNE"
      ic_flags_to_reject: ["muscle", "heart", "ch_noise", "line_noise"]
      ic_rejection_threshold: 0.3
      remove_flagged_ics: true
```

## Output File Configuration

The configuration file also controls which processing stages save intermediate files. This is useful for quality checking and troubleshooting. Below is an example of the output file configuration:

```yaml
stage_files:
  post_import:
    enabled: true
    suffix: "_postimport"
  post_outerlayer:
    enabled: false
    suffix: "_postouterlayer"
  post_prepipeline:
    enabled: true
    suffix: "_postprepipeline"
  post_resample:
    enabled: false
    suffix: "_postresample"
  post_reference:
    enabled: false
    suffix: "_postreference"
  post_trim:
    enabled: false
    suffix: "_posttrim"
  post_crop:
    enabled: false
    suffix: "_postcrop"
  post_prefilter:
    enabled: false
    suffix: "_postprefilter"
  post_bad_channels:
    enabled: false
    suffix: "_postbadchannels"
  post_pylossless:
    enabled: true
    suffix: "_postpylossless"
  post_rejection_policy:
    enabled: true
    suffix: "_postrejection"
  post_bad_segments:
    enabled: true
    suffix: "_postbadsegments"
  post_event_id:
    enabled: true
    suffix: "_posteventid"
  post_epochs:
    enabled: true
    suffix: "_postepochs"
  post_drop_bads:
    enabled: true
    suffix: "_postdropbads"
  post_comp:
    enabled: true
    suffix: "_postcomp"
  post_autoreject:
    enabled: true
    suffix: "_postautoreject"
  post_edit:
    enabled: true
    suffix: "_postedit"
```

By enabling or disabling these stages, you can control which intermediate files are saved during the processing pipeline.
