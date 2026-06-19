#!/bin/bash
#
# This script merges master (or main) into a PR branch when a PR comment contains
# "merge master" or "merge main".
#
# It is meant to be triggered by a GitHub Action on `issue_comment.created`.

set -euo pipefail

# ----------- ENVIRONMENT CHECKS -----------
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "Set the GITHUB_TOKEN env variable."
  exit 1
fi

if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  echo "Set the GITHUB_REPOSITORY env variable."
  exit 1
fi

if [[ -z "${GITHUB_EVENT_PATH:-}" ]]; then
  echo "Set the GITHUB_EVENT_PATH env variable."
  exit 1
fi

# ----------- CONSTANTS -----------
URI="https://api.github.com"
API_HEADER="Accept: application/vnd.github.v3+json"
AUTH_HEADER="Authorization: token ${GITHUB_TOKEN}"

# ----------- PARSE EVENT DATA -----------
action=$(jq --raw-output .action "$GITHUB_EVENT_PATH")
comment_body=$(jq --raw-output .comment.body "$GITHUB_EVENT_PATH" | tr -d '\r' | tr -d '\n' | xargs)
issue_number=$(jq --raw-output .issue.number "$GITHUB_EVENT_PATH")

echo "Action: $action"
echo "Comment: $comment_body"
echo "PR Number: $issue_number"

# Only process new comments on PRs
if [[ "$action" != "created" ]]; then
  echo "This script only runs for new comments."
  exit 0
fi

is_pr=$(jq --raw-output '.issue.pull_request | if . != null then "true" else "false" end' "$GITHUB_EVENT_PATH")
if [[ "$is_pr" != "true" ]]; then
  echo "Comment is not on a pull request."
  exit 0
fi

# ----------- COMMAND CHECK -----------
if [[ "$comment_body" != "merge master" && "$comment_body" != "merge main" ]]; then
  echo "No merge command found."
  exit 0
fi

# ----------- FETCH PR DETAILS -----------
echo "Fetching PR details..."
pr_data=$(curl -sSL \
  -H "${AUTH_HEADER}" \
  -H "${API_HEADER}" \
  "${URI}/repos/${GITHUB_REPOSITORY}/pulls/${issue_number}")

head_ref=$(echo "$pr_data" | jq -r .head.ref)
base_ref=$(echo "$pr_data" | jq -r .base.ref)

echo "Base branch: $base_ref"
echo "PR branch: $head_ref"

# ----------- DETERMINE SOURCE BRANCH -----------
merge_source="master"
if [[ "$comment_body" == "merge main" ]]; then
  merge_source="main"
fi

# ----------- CLONE AND MERGE -----------
echo "Cloning repository and merging $merge_source into $head_ref..."
git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"

git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" repo
cd repo

git fetch origin "$merge_source"
git fetch origin "$head_ref"

git checkout "$head_ref"

# Attempt merge
set +e
git merge "origin/${merge_source}" --no-edit
merge_exit=$?
set -e

# ----------- HANDLE MERGE RESULT -----------
if [[ $merge_exit -eq 0 ]]; then
  # Check if there’s anything to push
  if git diff --quiet HEAD "origin/${head_ref}"; then
    echo "No changes to push (branch already up to date)."
    curl -sSL \
      -H "${AUTH_HEADER}" \
      -H "${API_HEADER}" \
      -X POST \
      -d "{\"body\":\":information_source: ${merge_source} is already up to date with ${head_ref}.\"}" \
      "${URI}/repos/${GITHUB_REPOSITORY}/issues/${issue_number}/comments"
    exit 0
  fi

  echo "Pushing merged branch..."
  git push origin "HEAD:${head_ref}"

  # Comment success
  curl -sSL \
    -H "${AUTH_HEADER}" \
    -H "${API_HEADER}" \
    -X POST \
    -d "{\"body\":\":white_check_mark: Successfully merged ${merge_source} into ${head_ref}.\"}" \
    "${URI}/repos/${GITHUB_REPOSITORY}/issues/${issue_number}/comments"
else
  echo "Merge conflict detected."
  curl -sSL \
    -H "${AUTH_HEADER}" \
    -H "${API_HEADER}" \
    -X POST \
    -d "{\"body\":\":x: Merge from ${merge_source} failed due to conflicts. Please resolve manually.\"}" \
    "${URI}/repos/${GITHUB_REPOSITORY}/issues/${issue_number}/comments"
  exit 1
fi
