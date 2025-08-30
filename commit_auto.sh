#!/bin/bash

# Gemini CLI Auto Commit Script

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[38;5;208m'
BLUE='\033[38;5;39m'
CYAN='\033[0;36m'
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

# Generate commit message with Gemini (auto-detect prefix)
generate_commit_message_with_gemini() {
    local diff_output
    diff_output=$(git diff --cached)
    
    if [ -z "$diff_output" ]; then
        error_exit "No staged changes found."
    fi
    
    # Send prompt to Gemini (auto-detect prefix and generate message)
    local prompt="Please analyze the following Git diff and generate a concise, clear one-line commit message in English. 

Choose the appropriate prefix from: feat, fix, docs, style, refactor, perf, test, chore based on the changes, and format as 'prefix: message'.

Examples:
- feat: add user authentication system
- fix: resolve login validation bug
- docs: update API documentation
- style: format code with prettier
- refactor: extract user service logic
- perf: optimize database queries
- test: add unit tests for auth module
- chore: update dependencies

Diff:
$diff_output"
    
    # Run Gemini in background
    local temp_file=$(mktemp)
    (echo -e "$prompt" | gemini 2>/dev/null > "$temp_file") &
    local gemini_pid=$!
    
    # Show spinner
    show_spinner $gemini_pid "$(printf "%bAnalyzing changes and generating commit message...%b" "$BLUE" "$NC")"
    
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
    
    echo -e "${GREEN}Generated commit message:${NC}\n$full_commit_message"
    
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
    echo -e "${CYAN}How would you like to improve the commit message?: ${NC}"
    read -r refinement_request
    
    if [ -z "$refinement_request" ]; then
        echo -e "${YELLOW}No refinement request provided. Using original message.${NC}"
        # Go back to confirmation
        while true; do
            echo -e "${CYAN}Use the original commit message? [y/n]: ${NC}"
            read -r response
            case $response in
                [yY]|[yY][eE][sS])
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
        return
    fi
    
    local prompt="Current commit message: '$full_commit_message'

User's request: $refinement_request

Based on the above request, please improve the commit message. Keep the same format 'prefix: message' and output in one line in English."
    
    # Run Gemini in background
    local temp_file=$(mktemp)
    (echo -e "$prompt" | gemini 2>/dev/null > "$temp_file") &
    local gemini_pid=$!
    
    # Show spinner
    show_spinner $gemini_pid "$(printf "%bRefining commit message...%b" "$BLUE" "$NC")"
    
    # Wait for background process to complete
    wait $gemini_pid
    local exit_code=$?
    
    # Read result
    local refined_response
    refined_response=$(cat "$temp_file")
    rm -f "$temp_file"
    
    if [ $exit_code -ne 0 ] || [ -z "$refined_response" ]; then
        echo -e "${RED}Failed to get response from Gemini. Using original message.${NC}"
        # Go back to confirmation with original message
        while true; do
            echo -e "${CYAN}Use the original commit message? [y/n]: ${NC}"
            read -r response
            case $response in
                [yY]|[yY][eE][sS])
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
        return
    fi
    
    full_commit_message=$(echo "$refined_response" | head -n 1 | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    echo -e "${GREEN}Improved commit message:${NC}\n$full_commit_message"
    
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

# Main process
main() {
    # Check prerequisites
    check_git_repo
    check_gemini_cli
    
    # Check staged changes
    check_staged_changes
    
    # Generate commit message automatically with Gemini
    generate_commit_message_with_gemini
}

# Execute script
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi