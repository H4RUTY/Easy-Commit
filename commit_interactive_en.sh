#!/bin/bash

# Gemini CLI Easy Commit Script

set -e

# Color definitions
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
NC='\033[0m' # No Color

# Error handling
error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Show spinner
show_spinner() {
    local pid=$1
    local message=$2
    local delay=0.3
    local spinstr='|/-\'
    
    # Hide cursor
    printf "\033[?25l"
    
    printf "%b" "$message"
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b"
    done
    
    # Clear spinner and show completion message
    printf " [✓]\n"
    
    # Show cursor again
    printf "\033[?25h"
}

# Check if Gemini CLI is available
check_gemini_cli() {
    if ! command -v gemini &> /dev/null; then
        error_exit "Gemini CLI not found. Please install it."
    fi
}

# Check if it's a Git repository
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        error_exit "Git repository not found."
    fi
}

# Check staged changes
check_staged_changes() {
    local staged_changes
    local unstaged_changes
    
    staged_changes=$(git diff --cached --name-only)
    unstaged_changes=$(git diff --name-only)
    
    if [ -z "$staged_changes" ]; then
        if [ -z "$unstaged_changes" ]; then
            echo -e "${YELLOW}No changes to commit.${NC}"
            exit 0
        else
            echo -e "${YELLOW}No staged changes found.${NC}"
            echo -e "${CYAN}Stage all changes? [y/n]: ${NC}"
            read -r response
            case $response in
                [yY]|[yY][eE][sS])
                    git add .
                    echo -e "${GREEN}All changes have been staged.${NC}"
                    ;;
                *)
                    echo -e "${YELLOW}Exiting.${NC}"
                    exit 0
                    ;;
            esac
        fi
    fi
}

# Select commit type
select_commit_type() {
    echo -e "${CYAN}Commit type:${NC}"
    echo "[1] feat:     New feature"
    echo "[2] fix:      Bug fix"
    echo "[3] docs:     Docs only"
    echo "[4] style:    Format/whitespace, etc."
    echo "[5] refactor: Code refactoring (without changing behavior)"
    echo "[6] perf:     Performance"
    echo "[7] test:     Add/update tests"
    echo "[8] chore:    Build/other"
    
    while true; do
        echo -n "Select [1-8]: "
        read -r choice
        case $choice in
            1) commit_prefix="feat"; break;;
            2) commit_prefix="fix"; break;;
            3) commit_prefix="docs"; break;;
            4) commit_prefix="style"; break;;
            5) commit_prefix="refactor"; break;;
            6) commit_prefix="perf"; break;;
            7) commit_prefix="test"; break;;
            8) commit_prefix="chore"; break;;
            *) echo -e "${RED}Invalid selection. Enter a number between 1-8.${NC}";;
        esac
    done
}

# Manual commit message input
manual_commit_message() {
    while true; do
        echo -n "Enter commit message: "
        read -r user_message
        if [ -z "$user_message" ]; then
            echo -e "${RED}Commit message cannot be empty. Try again: ${NC}"
        else
            commit_message="$user_message"
            break
        fi
    done
}

# Generate commit message with Gemini
generate_commit_message_with_gemini() {
    local diff_output
    diff_output=$(git diff --cached)
    
    if [ -z "$diff_output" ]; then
        error_exit "No staged changes found."
    fi
    
    # Send prompt to Gemini (including prefix generation)
    local prompt="Please analyze the following Git diff and generate a concise, clear one-line commit message starting with \"${commit_prefix}: \" in English.\n\nDiff:\n$diff_output"
    
    # Run Gemini in background
    local temp_file=$(mktemp)
    (echo -e "$prompt" | gemini 2>/dev/null > "$temp_file") &
    local gemini_pid=$!
    
    # Show spinner
    show_spinner $gemini_pid "$(printf "%bGenerating commit message with Gemini...%b" "$BLUE" "$NC")"
    
    # Wait for background process to complete
    wait $gemini_pid
    local exit_code=$?
    
    # Read result
    local gemini_response
    gemini_response=$(cat "$temp_file")
    rm -f "$temp_file"
    
    if [ $exit_code -ne 0 ] || [ -z "$gemini_response" ]; then
        error_exit "Failed to get response from Gemini."
    fi
    
    # Clean up generated message (remove newlines and extra characters)
    full_commit_message=$(echo "$gemini_response" | head -n 1 | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    
    echo -e "${GREEN}Generated commit message: ${NC}$full_commit_message"
    
    while true; do
        echo -e "${CYAN}Use this commit message? [y/n]: ${NC}"
        read -r response
        case $response in
            [yY]|[yY][eE][sS])
                # Execute commit directly
                git commit -m "$full_commit_message"
                echo -e "${GREEN}Commit completed!${NC}"
                exit 0
                ;;
            [nN]|[nN][oO])
                refine_commit_message_with_gemini
                break
                ;;
            *)
                echo -e "${RED}Please answer y or n.${NC}"
                ;;
        esac
    done
}

# Refine commit message through conversation with Gemini
refine_commit_message_with_gemini() {
    echo -e "${CYAN}Describe how to refine the commit message: ${NC}"
    read -r refinement_request
    
    if [ -z "$refinement_request" ]; then
        echo -e "${YELLOW}No refinement request provided. Using original message.${NC}"
        return
    fi
    
    local prompt="Current commit message: '$full_commit_message'\n\nUser's request: $refinement_request\n\nBased on the above request, please improve the commit message starting with \"${commit_prefix}: \". Output in one line in English."
    
    # Run Gemini in background
    local temp_file=$(mktemp)
    (echo -e "$prompt" | gemini 2>/dev/null > "$temp_file") &
    local gemini_pid=$!
    
    # Show spinner
    show_spinner $gemini_pid "$(printf "%bRefining commit message with Gemini...%b" "$BLUE" "$NC")"
    
    # Wait for background process to complete
    wait $gemini_pid
    local exit_code=$?
    
    # Read result
    local refined_response
    refined_response=$(cat "$temp_file")
    rm -f "$temp_file"
    
    if [ $exit_code -ne 0 ] || [ -z "$refined_response" ]; then
        echo -e "${RED}Failed to get response from Gemini. Using original message.${NC}"
        return
    fi
    
    full_commit_message=$(echo "$refined_response" | head -n 1 | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    echo -e "${GREEN}New commit message: ${NC}$full_commit_message"
    
    while true; do
        echo -e "${CYAN}Use this commit message? [y/n]: ${NC}"
        read -r response
        case $response in
            [yY]|[yY][eE][sS])
                # Execute commit directly
                git commit -m "$full_commit_message"
                echo -e "${GREEN}Commit completed!${NC}"
                exit 0
                ;;
            [nN]|[nN][oO])
                refine_commit_message_with_gemini
                break
                ;;
            *)
                echo -e "${RED}Please answer y or n.${NC}"
                ;;
        esac
    done
}

# Select message generation method
select_message_generation_method() {
    echo -e "${CYAN}Commit message: [1] Manual, [2] Gemini${NC}"
    
    while true; do
        echo -n "Enter choise [1-2]: "
        read -r choice
        case $choice in
            1)
                manual_commit_message
                # For manual input, proceed to final confirmation
                final_commit
                break
                ;;
            2)
                generate_commit_message_with_gemini
                # For Gemini generation, commit is executed directly after approval
                break
                ;;
            *)
                echo -e "${RED}Invalid selection. Please enter 1 or 2.${NC}"
                ;;
        esac
    done
}

# Final confirmation and commit execution
final_commit() {
    local full_commit_message="${commit_prefix}: ${commit_message}"
    
    echo -e "${CYAN}Final commit message:${NC}"
    echo -e "${GREEN}$full_commit_message${NC}"
    
    while true; do
        echo -e "${CYAN}Commit with this message? [y/n]: ${NC}"
        read -r response
        case $response in
            [yY]|[yY][eE][sS])
                git commit -m "$full_commit_message"
                echo -e "${GREEN}Commit completed!${NC}"
                break
                ;;
            [nN]|[nN][oO])
                echo -e "${YELLOW}Commit cancelled.${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Please answer y or n.${NC}"
                ;;
        esac
    done
}

# Main process
main() {
    # Check prerequisites
    check_git_repo
    check_gemini_cli
    
    # Check staged changes
    check_staged_changes
    
    # Select commit type
    select_commit_type
    
    # Select commit message generation method (processing is completed within this function)
    select_message_generation_method
}

# Execute script
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi