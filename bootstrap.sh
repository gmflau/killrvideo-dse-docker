#!/bin/bash
set -e

# First arg is `-f` or `--some-option` then prepend default dse command to option(s)
if [ "${1:0:1}" = '-' ]; then
  set -- dse cassandra -f "$@"
fi

# If we're starting DSE
if [ "$1" = 'dse' -a "$2" = 'cassandra' ]; then
  # See if we've already completed bootstrapping
  if [ ! -f killrvideo_bootstrapped ]; then
    echo 'Setting up KillrVideo'

    # Invoke the entrypoint script to start DSE as a background job and get the pid
    # starting DSE in the background the first time allows us to monitor progress and register schema
    echo '=> Starting DSE'
    /entrypoint.sh "$@" &
    dse_pid="$!"

    # Wait for port 9042 (CQL) to be ready for up to 240 seconds
    echo '=> Waiting for DSE to become available'
    /wait-for-it.sh -t 240 127.0.0.1:9042
    echo '=> DSE is available'

    # Create the keyspace if necessary
    echo '=> Ensuring keyspace is created'
    cqlsh -f /opt/killrvideo-data/keyspace.cql 127.0.0.1 9042

    # Create the schema if necessary
    echo '=> Ensuring schema is created'
    cqlsh -f /opt/killrvideo-data/schema.cql -k killrvideo 127.0.0.1 9042

    # Create DSE Search core if necessary
    echo '=> Ensuring DSE Search is configured'
    cqlsh -f /opt/killrvideo-data/videos_search.cql -k killrvideo 127.0.0.1 9042

    # Wait for port 8182 (Gremlin) to be ready for up to 120 seconds
    echo '=> Waiting for DSE Graph to become available'
    /wait-for-it.sh -t 120 127.0.0.1:8182
    echo '=> DSE Graph is available'

    # Create the graph if necessary
    echo '=> Ensuring graph is created'
    dse gremlin-console -e /opt/killrvideo-data/killrvideo_video_recommendations_schema.groovy

    # Shutdown DSE after bootstrapping to allow the entrypoint script to start normally
    echo '=> Shutting down DSE after bootstrapping'
    kill -s TERM "$dse_pid"

    # DSE will exit with code 143 (128 + 15 SIGTERM) once stopped
    set +e
    wait "$dse_pid"
    if [ $? -ne 143 ]; then
      echo >&2 'KillrVideo setup failed'
      exit 1
    fi
    set -e

    # Don't bootstrap next time we start
    touch killrvideo_bootstrapped

    # Now allow DSE to start normally below
    echo 'KillrVideo has been setup, starting DSE normally'
  fi
fi

# Run the main entrypoint script from the base image
exec /entrypoint.sh "$@"
