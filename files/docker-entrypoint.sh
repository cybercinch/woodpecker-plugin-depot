#!/bin/bash

# This is to serve as a Plugin for Woodpecker to enable running of builds on depot.dev

set -eo pipefail
shopt -s nullglob

# check to see if this file is being run or sourced from another script
_is_sourced() {
	# https://unix.stackexchange.com/a/215279
	[ "${#FUNCNAME[@]}" -ge 2 ] \
		&& [ "${FUNCNAME[0]}" = '_is_sourced' ] \
		&& [ "${FUNCNAME[1]}" = 'source' ]
}

# logging functions
drone_log() {
	local type="$1"; shift
	# accept argument string or stdin
	local text="$*"; if [ "$#" -eq 0 ]; then text="$(cat)"; fi
	local dt; dt="$(date -D 'YYYY-MM-DD hh:mm[:ss]')"
	printf '%s [%s] [woodpecker-depot]: %s\n' "$dt" "$type" "$text"
}	
woodpecker_note() {
	drone_log Note "$@"
}
woodpecker_warn() {
	drone_log Warn "$@" >&2
}
woodpecker_error() {
	drone_log ERROR "$@" >&2
	exit 1
}


# Verify that the minimally required password settings are set for operation.
function verify_minimum_env {
        if [ -z "$PLUGIN_PROJECT" ]; then
                woodpecker_warn "token setting is required for plugin operation"
        fi
        if [ -z "$PLUGIN_TOKEN" ]; then
                woodpecker_warn "token setting is required for plugin operation"
        fi
        if [ -z "$PLUGIN_REPO" ]; then
                woodpecker_warn "repo setting is required for plugin operation"
        fi
        if [ -z "$PLUGIN_TAG" ]; then
                woodpecker_warn "tag setting is required for plugin operation"
        fi
        if [ -z "$PLUGIN_REPOHOST" ]; then
                woodpecker_warn "repohost setting is required for plugin operation"
        fi
        if [ -z "$PLUGIN_PLATFORMS" ]; then
                woodpecker_warn "platforms setting is required for plugin operation"
        fi
        if [ "${PLUGIN_REPOHOST}" == "docker.io" ]
         then
                if [ -z "$PLUGIN_USERNAME" ] || [ -z "$PLUGIN_PASSWORD" ]
                 then
                   woodpecker_warn "username and password are required for plugin operation"
                fi
        fi
	if [ -z "$PLUGIN_PROJECT" ] ||
           [ -z "$PLUGIN_TOKEN" ] || 
           [ -z "$PLUGIN_REPO" ] ||
           [ -z "$PLUGIN_TAGS" ] ||
           [ -z "$PLUGIN_REPOHOST" ] ||
           [ -z "$PLUGIN_PLATFORMS" ] ; then
		woodpecker_error <<-'EOF'
			You need to specify one/all of the following settings:
			 - token
             - project
             - repo
			 - tag
			 - repohost
			 - platforms
             - username
             - password
		EOF
	fi
        woodpecker_note "Sufficient configuration"

}

function parse_tags {
        # set (,) as delimiter
        IFS=','

        read -ra TAGS_ARRAY <<< "$PLUGIN_TAGS"

        TAGS_LENGTH=${#TAGS_ARRAY[@]}
        for (( i=0; i<TAGS_LENGTH; i++ ));
        do
            tags+=( -t "${PLUGIN_REPO}:${TAGS_ARRAY[$i]}" )
        done

        # Reset IFS to default value
        IFS=' '
}

function build_cli {

        options+=( --project "${PLUGIN_PROJECT}" )
        options+=( --platform "${PLUGIN_PLATFORMS}" )
        

        if [[ -n ${PLUGIN_TAG} ]]; then
                # Singular tag support
                options+=( -t "${PLUGIN_REPO}:${PLUGIN_TAG}" )
        elif [[ -n ${PLUGIN_TAGS} ]]; then
                # Multiple tags must be supplied
                # set (,) as delimiter
                IFS=','
                # Read tags into an array
                read -ra TAGS_ARRAY <<< "$PLUGIN_TAGS"

                # For each tag append to the cli parameters
                for (( i=0; i<${#TAGS_ARRAY[@]}; i++ ));
                do
                        options+=( -t "${PLUGIN_REPO}:${TAGS_ARRAY[$i]}" )
                done
        fi
        # Reset IFS to default value
        IFS=' '
        # Specify the path to file
        options+=( -f "${PLUGIN_DOCKERFILE}" )
        if [[ -n "${PLUGIN_QUIET}" && "${PLUGIN_QUIET}" == 'true' ]]; then
                options+=( --quiet )
        fi
        if [[ -n "${PLUGIN_PUSH}" && "${PLUGIN_PUSH}" == 'true' ]]; then
                options+=( --push )
        fi
        if [[ -n "${PLUGIN_LOAD}" && "${PLUGIN_LOAD}" == 'true' ]]; then
                options+=( --load )
        fi
        # Specify the Docker context
        options+=( "${PLUGIN_CONTEXT:=.}" )

}

function build_on_depot {
        if [ "${PLUGIN_REPOHOST}" == "docker.io" ]; then
                woodpecker_note "Building image ${PLUGIN_REPO}:${PLUGIN_TAG} for Docker Hub"
                # Login to Docker Hub
                woodpecker_note "Logging in to Docker Hub..."
                LOGON=$(echo "${PLUGIN_PASSWORD}" | docker login \
                                                   --username "${PLUGIN_USERNAME}" \
                                                   --password-stdin 2>/dev/null )
                woodpecker_note "${LOGON}"

                woodpecker_note "Building and pushing with Depot..."
                # Build and push with depot

                #parse_tags
                # Build the Commandline parameters
                build_cli

                DEPOT_TOKEN=${PLUGIN_TOKEN} depot build "${options[@]}"
                woodpecker_note "Build completed"
        else
                woodpecker_note "Building image ${PLUGIN_REPO}:${PLUGIN_TAG} for Custom Repo: ${PLUGIN_REPOHOST}"
                # Login to Container Registry
                woodpecker_note "Logging in to Container Registry..."
                LOGON=$(echo "${PLUGIN_PASSWORD}" | docker login \
                                                   --username "${PLUGIN_USERNAME}" \
                                                   --password-stdin 2>/dev/null ) \
                                                   "${PLUGIN_REPOHOST}" 
        fi 
}

_main() {
                woodpecker_note "Starting"
		verify_minimum_env "$@"
                woodpecker_note "$@"
                woodpecker_note "Depot version is: $(depot --version)"
                build_on_depot "$@"
}

# If we are sourced from elsewhere, don't perform any further actions
if ! _is_sourced; then
	_main "$@"
fi