#!/bin/bash
###########

offline_mode=false
advanced_mode=false
docker_compose=true

# Function definitions
function generate_password() {
  echo $(openssl rand -base64 48)
}

function find_and_replace_compose() {
  local find="$1"
  local replace="$2"

  # Escape special characters in the 'find' variable
  find_escaped=$(echo "$find" | sed 's/[][\/.*^$]/\\&/g')
  awk -v find="$find_escaped" -v replace="$replace" '{gsub(find, replace)}1' ./docker-compose.yml > tmpfile && mv tmpfile ./docker-compose.yml
}

# Handle flags and command line arguments
while [ $# -gt 0 ]; do
  case $1 in
    -h | --help)
      echo "IoT-Utilities Platform Setup CLI Tool"
      echo "This tool is used to automatically install the IoT-Utilities Platform via Docker Compose on the local machine"
      echo "The installation requires curl and docker-compose to be installed on the local machine"
      echo ""
      echo "Flags"
      echo "  --offline: \tBy default, the docker-compose file is downloaded from GitHub. When set, a local file can be used."
      echo "  --advanced: \tBy default, all database credentials are generated automatically. When set, the user can specify them manually."
      echo "  --output-only: \tBy default, the configured project is deployed using docker-compose. When set, the CLI only generates the compose file."
      exit 0
      ;;
    --offline)
      offline_mode=true
      ;;
    --advanced)
      advanced_mode=true
      ;;
    --output-only)
      docker_compose=false
      ;;
  esac
  shift
done

# Pre-installation check: cURL installation
echo "Checking curl installation..."
if [ "$offline_mode" = false and which curl &> /dev/null ]; then
  echo "Install curl to use this installation script or use the offline mode '--offline'"
  exit 1
fi

# Pre-installation check: Docker installation
echo "Checking Docker compose installation..."
if [ which docker &> /dev/null ]; then
  echo "Install docker (compose) to use this installation script"
  exit 1
fi

if [ "$advanced_mode" = true ]; then
  echo "Advanced configuration mode is enabled"
else
  echo "Advanced configuration mode disabled. All database credentials will be generated automatically"
fi

if [ "$docker_compose" = false ]; then
  echo "Automatic docker compose installation disabled"
fi

# Installation step 1: Obtain the Docker compose template file
if [ "$offline_mode" = true ]; then
  # Check whether the compose file template exists
  echo "Running platform setup in offline mode"
  if [ -f "./docker-compose-template.yml" ]; then
    echo "Platform compose template found"
  else
    echo "Unable to find docker compose template"
    echo "Please download the file 'docker-compose-template.yml' from the 'iot-utilities-platform' GitHub repository"
    exit 1
  fi
else
  # Download the compose file from the GitHub repository
  echo "Downloading compose template from GitHub repository..."
  # TODO: Switch from development to main branch
  curl https://raw.githubusercontent.com/FluegelsApps/iot-utilities-platform/development/docker-compose-template.yml --output docker-compose-template.yml
  echo "Platform compose template download complete"
fi

# Installation step 2: Query all required parameters
echo "Please enter the requested variables in order to configure the platform"

# Installation directory
echo "Subdirectory the platform should be installed in (leave empty for current):"
echo "The path should not contain leading and trailing slashes, e.g. folder, folder/subfolder is valid"
read installationDirectory

# Hostname
echo "DNS-name or IP-Address the platform will be available at:"
read hostname

# Admin credentials
echo "Username of the admin account:"
read keycloakAdminUsername
echo "Password of the admin account:"
read -s keycloakAdminPassword

# Initial user credentials
echo "Name of the initial user:"
read keycloakInitialUsername
echo "Display name of the initial user:"
read keycloakInitialDisplayname
echo "Password of the initial user:"
read -s keycloakInitialPassword

# Database credentials
if [ "$advanced_mode" = true ]; then
  echo "External port for all HTTPS traffic:"
  read httpsPort
  echo "External port for all Kafka TCP traffic:"
  read kafkaPort
  echo "Client secret the core-service uses to authenticate with the Kafka Broker:"
  read kafkaCoreSecret
  echo "Username of the Postgres database (leave empty for default):"
  read postgresUsername
  echo "Password of the Postgres database (leave empty to generate):"
  read -s postgresPassword
  echo "Username of the Influx database (leave empty for default):"
  read influxUsername
  echo "Password of the Influx database (leave empty to generate):"
  read -s influxPassword
  echo "Organization name of the Influx database (leave empty for default):"
  read influxOrganization
  echo "Access token of the Influx database (leave empty to generate):"
  read -s influxToken
else
  # Auto-fill all required credentials
  httpsPort="443"
  kafkaPort="29092"
  postgresUsername=iot-utilities-postgres
  postgresPassword=$(generate_password)
  influxUsername=iot-utilities-influx
  influxPassword=$(generate_password)
  influxOrganization=iot-utilities
  kafkaCoreSecret=$(generate_password)
  influxToken=$(generate_password)
fi

# Installation step 3: Update the docker compose template file
# Switch the working directory if necessary
if [ "$installationDirectory" != "" ]; then
  mkdir -p "./$installationDirectory"
  cp ./docker-compose-template.yml "./$installationDirectory/docker-compose.yml"
  rm ./docker-compose-template.yml
  cd "$installationDirectory"
else
  cp ./docker-compose-template.yml ./docker-compose.yml
  rm ./docker-compose-template.yml
fi

# Replace the contents in the configuration file
echo "Creating configuration file..."
find_and_replace_compose "<HOSTNAME>" "$hostname"
find_and_replace_compose "<ADMIN_USERNAME>" "$keycloakAdminUsername"
find_and_replace_compose "<ADMIN_PASSWORD>" "$keycloakAdminPassword"
find_and_replace_compose "<INITIAL_USERNAME>" "$keycloakInitialUsername"
find_and_replace_compose "<INITIAL_DISPLAY_NAME>" "$keycloakInitialDisplayname"
find_and_replace_compose "<INITIAL_PASSWORD>" "$keycloakInitialPassword"
find_and_replace_compose "<KAFKA_CORE_SECRET>" "$kafkaCoreSecret"
find_and_replace_compose "<POSTGRES_USERNAME>" "$postgresUsername"
find_and_replace_compose "<POSTGRES_PASSWORD>" "$postgresPassword"
find_and_replace_compose "<INFLUX_USERNAME>" "$influxUsername"
find_and_replace_compose "<INFLUX_PASSWORD>" "$influxPassword"
find_and_replace_compose "<INFLUX_ORGANIZATION>" "$influxOrganization"

# Mount the local volumes into the containers
find_and_replace_compose "<POSTGRES_VOLUME>" "./postgres"
find_and_replace_compose "<INFLUX_VOLUME>" "./influx"
find_and_replace_compose "<CONFIG_VOLUME>" "./configuration"
find_and_replace_compose "<TRUST_STORE_VOLUME>" "./trust_store"

# Bind all ports for the NGINX container
find_and_replace_compose "<PORT_HTTPS>" "$httpsPort"
find_and_replace_compose "<PORT_KAFKA>" "$kafkaPort"

# Create the folder structure
echo "Creating platform file system structure"
mkdir ./postgres
mkdir ./influx
mkdir ./trust_store
mkdir ./trust_store/active
mkdir ./trust_store/certs
mkdir ./trust_store/keys
mkdir ./configuration
touch ./configuration/nginx.conf

# Installation step 4: Run docker compose up on the local machine
if [ "$docker_compose" = true ]; then
  echo "Starting IoT-Utilities Platform installation..."
  docker compose up -d
  echo "Installation complete"
  exit 0
else
  echo "Docker compose file created and saved as 'docker-compose.yml'"
  exit 0
fi