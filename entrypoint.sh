#!/bin/bash
# Varun Chopra <vchopra@eightfold.ai>
#
# This action runs every time a comment is added to a pull request.
# Accepts the following commands: shipit, needs_ci, needs_sandbox

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

# action
action=$(jq --raw-output .action "$GITHUB_EVENT_PATH")
comment_body=$(jq --raw-output .comment.body "$GITHUB_EVENT_PATH")
number=$(jq --raw-output .issue.number "$GITHUB_EVENT_PATH")
labels=$(jq --raw-output .issue.labels[].name "$GITHUB_EVENT_PATH")

echo $action
echo $comment_body
echo $number
echo $labels

already_needs_ci=false
already_shipit=false
already_verified=false

if [[ "$action" != "created" ]]; then
  echo This action should only be called when a comment is created on a pull request
  exit 0
fi

if [[ $comment_body == "shipit" || $comment_body == ":shipit:" || $comment_body == ":shipit: " ]]; then
  for label in $labels; do
    case $label in
      ci_verified)
        already_verified=true
        ;;
      shipit)
        already_shipit=true
        ;;
      needs_ci)
        already_needs_ci=true
        ;;
      *)
        echo "Unknown label $label"
        ;;
    esac
  done
  if [[ "$already_verified" == false && "$already_needs_ci" == false ]]; then
    add_label "needs_ci"
  fi
  if [[ "$already_shipit" == false ]]; then
    add_label "shipit"
  fi
  exit 0
fi

if [[ $comment_body == "needs_ci" ]]; then
  for label in $labels; do
    case $label in
      ci_verified)
        remove_label "$label"
        ;;
      shipit)
        remove_label "$label"
        ;;
      needs_ci)
        already_needs_ci=true
        ;;
      *)
        echo "Unknown label $label"
        ;;
    esac
  done
  if [[ "$already_needs_ci" == false ]]; then
    add_label "needs_ci"
  fi
fi

# Add sandbox is needs_sandbox
# Remove stop_sandbox if sandbox is requested again
already_needs_sandbox=false

if [[ $comment_body == "needs_sandbox" || $comment_body == "needs_sandbox:eu" || $comment_body == "needs_sandbox:ca" || $comment_body == "needs_sandbox:gov" ]]; then
  for label in $labels; do
    case $label in
      sandbox)
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
      *)
        echo "Unknown label $label"
        ;;
    esac
  done
  if [[ "$already_needs_sandbox" == false ]]; then
    if [[ $comment_body == "needs_sandbox:eu" ]]; then
      add_label "sandbox :eu:"
    elif [[ $comment_body == "needs_sandbox:ca" ]]; then
      add_label "sandbox :maple_leaf:"
    elif [[ $comment_body == "needs_sandbox:gov" ]]; then
      add_label "sandbox :classical_building:"
    else
      add_label "sandbox"
    fi
  fi
fi

if [[ $comment_body == "stop_sandbox" ]]; then
  for label in $labels; do
    case $label in
      sandbox)
        remove_label "sandbox"
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
      *)
        echo "Unknown label $label"
        ;;
    esac
  done
fi
