#!/bin/bash
# Varun Chopra <vchopra@eightfold.ai>
#
# This action runs every time a comment is added to a pull request.
# Accepts the following commands: shipit, needs_ci, needs_sandbox, e2e_needs_sandbox

set -e

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "Set the GITHUB_TOKEN env variable."
  exit 1
fi

if [[ -z "$GITHUB_REPOSITORY" ]]; then
  echo "Set the GITHUB_REPOSITORY env variable."
  exit 1
fi

if [[ -z "$GITHUB_EVENT_PATH" ]]; then
  echo "Set the GITHUB_EVENT_PATH env variable."
  exit 1
fi

add_label(){
  curl -sSL \
    -H "${AUTH_HEADER}" \
    -H "${API_HEADER}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"labels\":[\"${1}\"]}" \
    "${URI}/repos/${GITHUB_REPOSITORY}/issues/${number}/labels"
}

remove_label(){
  curl -sSL \
    -H "${AUTH_HEADER}" \
    -H "${API_HEADER}" \
    -X DELETE \
    "${URI}/repos/${GITHUB_REPOSITORY}/issues/${number}/labels/${1}"
}
IFS=$'\n'

URI="https://api.github.com"
API_HEADER="Accept: application/vnd.github.v3+json"
AUTH_HEADER="Authorization: token ${GITHUB_TOKEN}"

# --- CI k8s --------------------------------------------------------------------------
# When the repository variable CI_K8S_TRIGGER (passed in by the calling workflow) is
# "true", every needs_ci / needs_ci:lite this action adds also starts the matching CI k8s
# workflow. A label added with GITHUB_TOKEN starts no workflow, so it is started with
# workflow_dispatch, which GITHUB_TOKEN may trigger (needs `actions: write`). Never fails
# the action.
ci_k8s_request() {  # ci_k8s_request <workflow file>: start a CI k8s run of this PR
  [[ "${CI_K8S_TRIGGER:-false}" == "true" ]] || return 0
  local ref
  ref=$(jq -r '.repository.default_branch // "master"' "$GITHUB_EVENT_PATH")
  curl -sSL -o /dev/null -w "dispatch $1: HTTP %{http_code}\n" \
    -H "${AUTH_HEADER}" -H "${API_HEADER}" -X POST -H "Content-Type: application/json" \
    -d "{\"ref\":\"${ref}\",\"inputs\":{\"pr\":\"${number}\"}}" \
    "${URI}/repos/${GITHUB_REPOSITORY}/actions/workflows/${1}/dispatches" || true
}

# Likewise for the plain `sandbox` label: when SANDBOX_K8S_TRIGGER is "true", adding or
# removing it here also starts or stops the CI k8s sandbox (sandbox.yml). Never fails the
# action.
sandbox_k8s_request() {  # sandbox_k8s_request <start|stop>: start or stop this PR's CI k8s sandbox
  [[ "${SANDBOX_K8S_TRIGGER:-false}" == "true" ]] || return 0
  local ref
  ref=$(jq -r '.repository.default_branch // "master"' "$GITHUB_EVENT_PATH")
  curl -sSL -o /dev/null -w "dispatch sandbox.yml $1: HTTP %{http_code}\n" \
    -H "${AUTH_HEADER}" -H "${API_HEADER}" -X POST -H "Content-Type: application/json" \
    -d "{\"ref\":\"${ref}\",\"inputs\":{\"pr\":\"${number}\",\"action\":\"${1}\"}}" \
    "${URI}/repos/${GITHUB_REPOSITORY}/actions/workflows/sandbox.yml/dispatches" || true
}

# Likewise for shipit: when SHIPIT_K8S_TRIGGER is "true", every shipit / sudo shipit comment
# also starts shipit.yml, even when the PR already has `shipit` (commenting again is how an
# author asks for a fresh merge check, e.g. after resolving a review thread). Never fails the
# action.
shipit_k8s_request() {  # shipit_k8s_request <comment|sudo>: start a CI k8s shipit check of this PR
  [[ "${SHIPIT_K8S_TRIGGER:-false}" == "true" ]] || return 0
  local ref
  ref=$(jq -r '.repository.default_branch // "master"' "$GITHUB_EVENT_PATH")
  curl -sSL -o /dev/null -w "dispatch shipit.yml $1: HTTP %{http_code}\n" \
    -H "${AUTH_HEADER}" -H "${API_HEADER}" -X POST -H "Content-Type: application/json" \
    -d "{\"ref\":\"${ref}\",\"inputs\":{\"pr\":\"${number}\",\"trigger\":\"${1}\"}}" \
    "${URI}/repos/${GITHUB_REPOSITORY}/actions/workflows/shipit.yml/dispatches" || true
}
# --------------------------------------------------------------------------------------

# action
action=$(jq --raw-output .action "$GITHUB_EVENT_PATH")
comment_body=$(jq --raw-output .comment.body "$GITHUB_EVENT_PATH")
# Trim newlines, carriage returns and leading/trailing spaces
comment_body=$(echo "$comment_body" | grep -v '^[[:space:]]*$' | tr -d '\r' | tr -d '\n'| xargs)
number=$(jq --raw-output .issue.number "$GITHUB_EVENT_PATH")
labels=$(jq --raw-output .issue.labels[].name "$GITHUB_EVENT_PATH")

echo $action
echo $comment_body
echo $number
echo $labels

already_needs_ci=false
already_shipit=false
already_verified=false
already_verified_alt=false
already_needs_ci_lite=false
already_needs_ci_alt=false
already_needs_ci_alt_lite=false
alt_python_version=":3.13"
curr_python_version=":3.13"

if [[ "$action" != "created" ]]; then
  echo This action should only be called when a comment is created on a pull request
  exit 0
fi

# TODO: Uncomment CI alt to make it blocking
if [[ $comment_body == "shipit" || $comment_body == ":shipit:" || $comment_body == ":shipit: " || $comment_body == "sudo shipit"* || $comment_body == "sudo :shipit:"* ]]; then
  for label in $labels; do
    case $label in
      ci_verified)
        already_verified=true
        ;;
      ci_verified${alt_python_version})
        already_verified_alt=true
        ;;
      shipit)
        already_shipit=true
        ;;
      needs_ci)
        already_needs_ci=true
        ;;
      needs_ci${alt_python_version})
        already_needs_ci_alt=true
        ;;
      *)
        echo "Unknown label $label"
        ;;
    esac
  done
  if [[ "$already_verified" == false && "$already_needs_ci" == false ]]; then
    add_label "needs_ci"
    ci_k8s_request "ci_k8s_full.yml"
  fi
  if [[ "$already_verified_alt" == false && "$already_needs_ci_alt" == false ]]; then
    if [[ "$curr_python_version" != "$alt_python_version" ]]; then
      add_label "needs_ci${alt_python_version}"
    fi
  fi
  if [[ "$already_shipit" == false ]]; then
    add_label "shipit"
  fi
  if [[ $comment_body == "sudo"* ]]; then
    shipit_k8s_request sudo
  else
    shipit_k8s_request comment
  fi
  exit 0
fi

if [[ $comment_body == "needs_ci" ]]; then
  for label in $labels; do
    case $label in
      ci_verified)
        remove_label "$label"
        ;;
      needs_ci)
        already_needs_ci=true
        ;;
      "needs_ci${alt_python_version}")
        already_needs_ci_alt=true
        ;;
      *)
        echo "Unknown label $label"
        ;;
    esac
  done
  if [[ "$already_needs_ci" == false ]]; then
    add_label "needs_ci"
    ci_k8s_request "ci_k8s_full.yml"
  fi
  if [[ "$already_needs_ci_alt" == false ]]; then
    if [[ "$curr_python_version" != "$alt_python_version" ]]; then
      add_label "needs_ci${alt_python_version}"
    fi
  fi
fi

if [[ $comment_body == "needs_ci:lite" ]]; then
  for label in $labels; do
    case $label in
      ci_verified:lite)
        remove_label "$label"
        ;;
      needs_ci:lite)
        already_needs_ci_lite=true
        ;;
      *)
        echo "Unknown label $label"
        ;;
    esac
  done
  if [[ "$already_needs_ci_lite" == false ]]; then
    add_label "needs_ci:lite"
    ci_k8s_request "ci_k8s_lite.yml"
  fi
fi

if [[ $comment_body == "needs_ci${alt_python_version}" ]]; then
  for label in $labels; do
    case $label in
      "ci_verified${alt_python_version}")
        remove_label "$label"
        ;;
      "needs_ci${alt_python_version}")
        already_needs_ci_alt=true
        ;;
      *)
        echo "Unknown label $label"
        ;;
    esac
  done
  if [[ "$already_needs_ci_alt" == false ]]; then
    if [[ "$curr_python_version" != "$alt_python_version" ]]; then
      add_label "needs_ci${alt_python_version}"
    fi
  fi
fi

if [[ $comment_body == "needs_ci${alt_python_version}:lite" ]]; then
  for label in $labels; do
    case $label in
      ci_verified${alt_python_version}:lite)
        remove_label "$label"
        ;;
      needs_ci${alt_python_version}:lite)
        already_needs_ci_alt_lite=true
        ;;
      *)
        echo "Unknown label $label"
        ;;
    esac
  done
  if [[ "$already_needs_ci_alt_lite" == false ]]; then
    if [[ "$curr_python_version" != "$alt_python_version" ]]; then
      add_label "needs_ci${alt_python_version}:lite"
    fi
  fi
fi

# Add sandbox label for needs_sandbox and e2e_needs_sandbox (e2e_ prefix enables local processor)
already_needs_sandbox=false
already_needs_alternate_version_sandbox=false
alternate_python_version="3.13"
current_python_version="3.13"

if [[ $comment_body =~ ^(e2e_)?needs_sandbox(:${alternate_python_version})(:(eu|gov|ca|uae|wu|ap))?(:(dev|([0-9]+)(\.([0-9]+)?)?))?(:(([a-zA-Z0-9,]+)))?([ \t]*)?$ ]]; then
  for label in $labels; do
    case $label in
      sandbox:${alternate_python_version})
        already_needs_sandbox=true
        ;;
      "sandbox:${alternate_python_version} :united_arab_emirates:")
	already_needs_sandbox=true
	;;
      "sandbox:${alternate_python_version} :eu:")
        already_needs_sandbox=true
        ;;
      "sandbox:${alternate_python_version} :maple_leaf:")
        already_needs_sandbox=true
        ;;
      "sandbox:${alternate_python_version} :classical_building:")
        already_needs_sandbox=true
        ;;
      "sandbox:${alternate_python_version} :us:")
        already_needs_sandbox=true
        ;;
      "sandbox:${alternate_python_version} :australia:")
        already_needs_sandbox=true
        ;;
      *)
        echo "Unknown label $label"
        ;;
    esac
  done
  if [[ "$already_needs_sandbox" == false && "$current_python_version" != "$alternate_python_version" ]]; then
    if [[ $comment_body =~ (e2e_)?needs_sandbox:${alternate_python_version}:eu ]]; then
      add_label "sandbox:${alternate_python_version} :eu:"
    elif [[ $comment_body =~ (e2e_)?needs_sandbox:${alternate_python_version}:ca ]]; then
      add_label "sandbox:${alternate_python_version} :maple_leaf:"
    elif [[ $comment_body =~ (e2e_)?needs_sandbox:${alternate_python_version}:gov ]]; then
      add_label "sandbox:${alternate_python_version} :classical_building:"
    elif [[ $comment_body =~ (e2e_)?needs_sandbox:${alternate_python_version}:uae ]]; then
      add_label "sandbox:${alternate_python_version} :united_arab_emirates:"
    elif [[ $comment_body =~ (e2e_)?needs_sandbox:${alternate_python_version}:wu ]]; then
      add_label "sandbox:${alternate_python_version} :us:"
    elif [[ $comment_body =~ (e2e_)?needs_sandbox:${alternate_python_version}:ap ]]; then
      add_label "sandbox:${alternate_python_version} :australia:"
    else
      add_label "sandbox:${alternate_python_version}"
    fi
  fi

elif [[ $comment_body =~ ^(e2e_)?needs_sandbox(:(eu|gov|ca|uae|wu|ap))?(:(dev|([0-9]+)(\.([0-9]+)?)?))?(:(([a-zA-Z0-9,]+)))?([ \t]*)?$ ]]; then
  for label in $labels; do
    case $label in
      sandbox)
        already_needs_sandbox=true
        ;;
      "sandbox :united_arab_emirates:")
	already_needs_sandbox=true
	;;
      "sandbox :eu:")
        already_needs_sandbox=true
        ;;
      "sandbox :maple_leaf:")
        already_needs_sandbox=true
        ;;
      "sandbox :classical_building:")
        already_needs_sandbox=true
        ;;
      "sandbox :us:")
        already_needs_sandbox=true
        ;;
      "sandbox :australia:")
        already_needs_sandbox=true
        ;;
      *)
        echo "Unknown label $label"
        ;;
    esac
  done
  if [[ "$already_needs_sandbox" == false ]]; then
    if [[ $comment_body =~ (e2e_)?needs_sandbox:eu ]]; then
      add_label "sandbox :eu:"
    elif [[ $comment_body =~ (e2e_)?needs_sandbox:ca ]]; then
      add_label "sandbox :maple_leaf:"
    elif [[ $comment_body =~ (e2e_)?needs_sandbox:gov ]]; then
      add_label "sandbox :classical_building:"
    elif [[ $comment_body =~ (e2e_)?needs_sandbox:uae ]]; then
      add_label "sandbox :united_arab_emirates:"
    elif [[ $comment_body =~ (e2e_)?needs_sandbox:wu ]]; then
      add_label "sandbox :us:"
    elif [[ $comment_body =~ (e2e_)?needs_sandbox:ap ]]; then
      add_label "sandbox :australia:"
    else
      add_label "sandbox"
      sandbox_k8s_request start
    fi
  fi
fi

if [[ $comment_body == "stop_sandbox" ]]; then
  for label in $labels; do
    case $label in
      sandbox)
        remove_label "sandbox"
        sandbox_k8s_request stop
        ;;
      "sandbox :eu:")
        remove_label "sandbox%20:eu:"
        ;;
      "sandbox :maple_leaf:")
        remove_label "sandbox%20:maple_leaf:"
        ;;
      "sandbox :classical_building:")
        remove_label "sandbox%20:classical_building:"
        ;;
      "sandbox :united_arab_emirates:")
	      remove_label "sandbox%20:united_arab_emirates:"
	      ;;
      "sandbox :us:")
	      remove_label "sandbox%20:us:"
	      ;;
      "sandbox :australia:")
	      remove_label "sandbox%20:australia:"
	      ;;
      sandbox:${alternate_python_version})
        remove_label "sandbox:${alternate_python_version}"
        ;;
      "sandbox:${alternate_python_version} :eu:")
        remove_label "sandbox:${alternate_python_version}%20:eu:"
        ;;
      "sandbox:${alternate_python_version} :maple_leaf:")
        remove_label "sandbox:${alternate_python_version}%20:maple_leaf:"
        ;;
      "sandbox:${alternate_python_version} :classical_building:")
        remove_label "sandbox:${alternate_python_version}%20:classical_building:"
        ;;
      "sandbox:${alternate_python_version} :united_arab_emirates:")
	      remove_label "sandbox:${alternate_python_version}%20:united_arab_emirates:"
	      ;;
      "sandbox:${alternate_python_version} :us:")
	      remove_label "sandbox:${alternate_python_version}%20:us:"
	      ;;
      "sandbox:${alternate_python_version} :australia:")
	      remove_label "sandbox:${alternate_python_version}%20:australia:"
	      ;;
      *)
        echo "Unknown label $label"
        ;;
    esac
  done
fi
