#!/bin/bash
# Varun Chopra <vchopra@eightfold.ai>
#
# This action runs every time a comment is added to a pull request.
# Accepts the following commands: shipit, needs_ci

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

URI="https://api.github.com"
API_HEADER="Accept: application/vnd.github.v3+json"
AUTH_HEADER="Authorization: token ${GITHUB_TOKEN}"

# action
action=$(jq --raw-output .action "$GITHUB_EVENT_PATH")
comment_body=$(jq --raw-output .comment.body "$GITHUB_EVENT_PATH")
number=$(jq --raw-output .issue.number "$GITHUB_EVENT_PATH")
labels=$(jq --raw-output .issue.labels[].name "$GITHUB_EVENT_PATH")

already_needs_ci=false
already_needs_ci_3=false
already_needs_ci_selenium=false
already_shipit=false
already_verified=false
already_verified_3=false

if [[ "$action" != "created" ]]; then
  echo This action should only be called when a comment is created on a pull request
  exit 0
fi

if [[ $comment_body == "shipit" ]]; then
  for label in $labels; do
    case $label in
      ci_verified)
        already_verified=true
        ;;
      "ci_verified:py3")
        already_verified_3=true
        ;;
      shipit)
        already_shipit=true
        ;;
      needs_ci)
        already_needs_ci=true
        ;;
      "needs_ci:py3")
        already_needs_ci_3=true
        ;;
      *)
        echo "Unknown label $label"
        ;;
    esac
  done
  if [[ "$already_verified" == false && "$already_needs_ci" == false ]]; then
    add_label "needs_ci"
  fi
#   if [[ "$already_verified_3" == false && "$already_needs_ci_3" == false ]]; then
#     add_label "needs_ci:py3"
#   fi
  if [[ "$already_shipit" == false ]]; then
    add_label "shipit"
  fi
  exit 0
fi

if [[ $comment_body == "needs_ci" || $comment_body == "needs_ci:selenium" ]]; then
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
      "needs_ci:selenium")
        already_needs_ci_selenium=true
        ;;
      *)
        echo "Unknown label $label"
        ;;
    esac
  done
  if [[ "$already_needs_ci" == false ]]; then
    add_label "needs_ci"
    if [[ "$already_needs_ci_selenium" == false && $comment_body == "needs_ci:selenium" ]]; then
      add_label "needs_ci:selenium"
    fi
  fi
fi
