# Setup Instructions

## Prerequisites

- Docker and Docker Compose installed
- For Windows: PowerShell 5.1+
- For Linux/Mac: Bash shell

## Installation

1. Clone this repository:
```bash
git clone https://github.com/cincibrainlab/autoclean-watchdog.git
cd autoclean-watchdog
```

2. Create the required directories:
```bash
mkdir -p input output config
```

3. Add your autoclean configuration:
```bash
cp /path/to/your/autoclean_config.yaml ./config/
```

4. Build the Docker image:
```bash
docker-compose build
```

## Starting the Watchdog

Start the automatic file monitoring system:

```bash
docker-compose up -d
```

View the logs:

```bash
docker-compose logs -f
```
