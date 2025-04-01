#!/bin/bash

# Mock functions to simulate GitHub API calls
function add_label() {
    echo "Adding label: $1"
}

function remove_label() {
    echo "Removing label: $1"
}

# Test case function
function test_case() {
    local test_name=$1
    local comment=$2
    local initial_labels=("${@:3}")
    
    echo "=== Test Case: $test_name ==="
    echo "Comment: '$comment'"
    echo "Initial labels: ${initial_labels[*]}"
    
    # Reset state variables
    already_needs_sandbox=false
    already_needs_alternate_version_sandbox=false
    alternate_python_version=":3.13"
    already_verified=false
    already_needs_ci=false
    already_needs_ci_alt=false
    already_needs_ci_alt_python_version=false
    already_needs_ci_lite=false
    already_needs_ci_lite_alt_python_version=false
    # Process comment
    if [[ $comment == "shipit" || $comment == ":shipit:" || $comment == ":shipit: " || $comment == "sudo shipit"* || $comment == "sudo :shipit:"* ]]; then
        for label in "${initial_labels[@]}"; do
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
    elif [[ $comment == "needs_ci" ]]; then
        for label in "${initial_labels[@]}"; do
            case $label in
                ci_verified)
                    remove_label "$label"
                    ;;
                needs_ci)
                    already_needs_ci=true
                    ;;
                "needs_ci${alternate_python_version}")
                    already_needs_ci_alt_python_version=true
                    ;;
                *)
                    echo "Unknown label $label"
                    ;;
            esac
        done
        if [[ "$already_needs_ci" == false ]]; then
            add_label "needs_ci"
        fi
        if [[ "$already_needs_ci_alt_python_version" == false ]]; then
            add_label "needs_ci${alternate_python_version}"
        fi
    elif [[ $comment == "needs_ci:lite" ]]; then
        for label in "${initial_labels[@]}"; do
            case $label in
                ci_verified:lite)
                    remove_label "$label"
                    ;;
                needs_ci:lite)
                    already_needs_ci_lite=true
                    ;;
                "needs_ci${alternate_python_version}:lite")
                    already_needs_ci_lite_alt_python_version=true
                    ;;
                *)
                    echo "Unknown label $label"
                    ;;
            esac
        done
        if [[ "$already_needs_ci_lite" == false ]]; then
            add_label "needs_ci:lite"
        fi
        if [[ "$already_needs_ci_lite_alt_python_version" == false ]]; then
            add_label "needs_ci${alternate_python_version}:lite"
        fi
    elif [[ $comment == "needs_ci${alternate_python_version}" ]]; then
        for label in "${initial_labels[@]}"; do
            case $label in
                "ci_verified${alternate_python_version}")
                    remove_label "$label"
                    ;;
                "needs_ci${alternate_python_version}")
                    already_needs_ci_alt=true
                    ;;
                *)
                    echo "Unknown label $label"
                    ;;
            esac
        done
        if [[ "$already_needs_ci_alt" == false ]]; then
            add_label "needs_ci${alternate_python_version}"
        fi
    elif [[ $comment == "needs_ci${alternate_python_version}:lite" ]]; then
        for label in "${initial_labels[@]}"; do
            case $label in
                "ci_verified${alternate_python_version}:lite")
                    remove_label "$label"
                    ;;
                "needs_ci${alternate_python_version}:lite")
                    already_needs_ci_alt_lite=true
                    ;;
                *)
                    echo "Unknown label $label"
                    ;;
            esac
        done
        if [[ "$already_needs_ci_alt_lite" == false ]]; then
            add_label "needs_ci${alternate_python_version}:lite"
        fi
    elif [[ $comment =~ ^needs_sandbox(:${alternate_python_version})(:(eu|gov|ca|uae|wu))?(:(dev|([0-9]+)(\.([0-9]+)?)?))?([ \t]*)?$ ]]; then
        for label in "${initial_labels[@]}"; do
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
                *)
                    echo "Unknown label $label"
                    ;;
            esac
        done
        if [[ "$already_needs_sandbox" == false ]]; then
            if [[ $comment =~ needs_sandbox:eu  ]]; then
                add_label "sandbox :eu:"
            elif [[ $comment =~ needs_sandbox:ca ]]; then
                add_label "sandbox :maple_leaf:"
            elif [[ $comment =~ needs_sandbox:gov  ]]; then
                add_label "sandbox :classical_building:"
            elif [[ $comment =~ needs_sandbox:uae  ]]; then
                add_label "sandbox :united_arab_emirates:"
            elif [[ $comment =~ needs_sandbox:wu  ]]; then
                add_label "sandbox :us:"
            else
                add_label "sandbox"
            fi
        fi
    elif [[ $comment == "stop_sandbox" ]]; then
        for label in "${initial_labels[@]}"; do
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
                "sandbox :united_arab_emirates:")
                    remove_label "sandbox%20:united_arab_emirates:"
                    ;;
                "sandbox :us:")
                    remove_label "sandbox%20:us:"
                    ;;
                "sandbox:${alternate_python_version}")
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
                *)
                    echo "Unknown label $label"
                    ;;
            esac
        done
    fi
    echo "=== End Test ==="
    echo
}

# Test needs_ci functionality
test_case "Add needs_ci - No existing labels" \
    "needs_ci"

test_case "Add needs_ci - Labels already exist" \
    "needs_ci" \
    "needs_ci" \
    "needs_ci:3.13"

test_case "Add needs_ci - Remove ci_verified when adding needs_ci" \
    "needs_ci" \
    "ci_verified"

# Test needs_ci:lite functionality
test_case "Add needs_ci:lite - No existing labels" \
    "needs_ci:lite"

test_case "Add needs_ci:lite - Labels already exist" \
    "needs_ci:lite" \
    "needs_ci:lite" \
    "needs_ci:3.13:lite"

test_case "Add needs_ci:lite - Remove ci_verified:lite when adding needs_ci:lite" \
    "needs_ci:lite" \
    "ci_verified:lite"
