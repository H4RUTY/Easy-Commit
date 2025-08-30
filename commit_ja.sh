#!/bin/bash

# Gemini CLI Easy Commit Script

set -e

# 色の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[38;5;208m'
BLUE='\033[38;5;39m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# エラーハンドリング
error_exit() {
    echo -e "${RED}エラー: $1${NC}" >&2
    exit 1
}

# スピナー表示
show_spinner() {
    local pid=$1
    local message=$2
    local delay=0.3
    local spinstr='|/-\'
    
    # カーソルを非表示にする
    printf "\033[?25l"
    
    printf "%b" "$message"
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b"
    done
    
    # スピナーをクリアして完了メッセージを表示
    printf " [✓]\n"
    
    # カーソルを再表示する
    printf "\033[?25h"
}

# Gemini CLIが利用可能かチェック
check_gemini_cli() {
    if ! command -v gemini &> /dev/null; then
        error_exit "Gemini CLIが見つかりません。インストールしてください。"
    fi
}

# Gitリポジトリかチェック
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        error_exit "Gitリポジトリではありません。"
    fi
}

# ステージングされた変更をチェック
check_staged_changes() {
    local staged_changes
    local unstaged_changes
    
    staged_changes=$(git diff --cached --name-only)
    unstaged_changes=$(git diff --name-only)
    
    if [ -z "$staged_changes" ]; then
        if [ -z "$unstaged_changes" ]; then
            echo -e "${YELLOW}コミットできる変更がありません。${NC}"
            exit 0
        else
            echo -e "${YELLOW}ステージングされている変更がありません。${NC}"
            echo -e "${CYAN}全ての変更をステージングしてコミットしますか？ [y/n]${NC}"
            read -r response
            case $response in
                [yY]|[yY][eE][sS])
                    git add .
                    echo -e "${GREEN}全ての変更をステージングしました。${NC}"
                    ;;
                *)
                    echo -e "${YELLOW}処理を終了します。${NC}"
                    exit 0
                    ;;
            esac
        fi
    fi
}

# コミットタイプを選択
select_commit_type() {
    echo -e "${CYAN}コミットの種類を選択してください:${NC}"
    echo "[1] feat:     新機能追加"
    echo "[2] fix:      バグ修正"
    echo "[3] docs:     ドキュメントのみの変更"
    echo "[4] style:    コードの意味に影響しない変更（空白、インデントの修正など）"
    echo "[5] refactor: バグ修正でも機能追加でもない変更（可読性・保守性のための変更など）"
    echo "[6] perf:     パフォーマンス向上のための変更"
    echo "[7] test:     テスト追加・修正"
    echo "[8] chore:    ビルドや補助的タスク（ライブラリ変更など）"
    
    while true; do
        echo -n "選択してください [1-8]: "
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
            *) echo -e "${RED}無効な選択です。1-8の数字を入力してください。${NC}";;
        esac
    done
}

# 手動でコミットメッセージを入力
manual_commit_message() {
    while true; do
        echo -n "コミットメッセージを入力してください: "
        read -r user_message
        if [ -z "$user_message" ]; then
            echo -e "${RED}コミットメッセージは空欄にできません。再度入力してください: ${NC}"
        else
            commit_message="$user_message"
            break
        fi
    done
}

# Geminiにコミットメッセージを生成させる
generate_commit_message_with_gemini() {
    local diff_output
    diff_output=$(git diff --cached)
    
    if [ -z "$diff_output" ]; then
        error_exit "ステージングされた変更が見つかりません。"
    fi
    
    # Geminiにプロンプトを送信（prefixも含めて生成）
    local prompt="以下のGitの変更差分を分析して、「${commit_prefix}: 」で始まる簡潔で分かりやすい1行のコミットメッセージを日本語で生成してください。\n\n変更差分:\n$diff_output"
    
    # バックグラウンドでGeminiを実行
    local temp_file=$(mktemp)
    (echo -e "$prompt" | gemini 2>/dev/null > "$temp_file") &
    local gemini_pid=$!
    
    # スピナーを表示
    show_spinner $gemini_pid "$(printf "%bGeminiでコミットメッセージを生成しています...%b" "$BLUE" "$NC")"
    
    # バックグラウンド処理の完了を待つ
    wait $gemini_pid
    local exit_code=$?
    
    # 結果を読み込み
    local gemini_response
    gemini_response=$(cat "$temp_file")
    rm -f "$temp_file"
    
    if [ $exit_code -ne 0 ] || [ -z "$gemini_response" ]; then
        error_exit "Geminiからの応答を取得できませんでした。"
    fi
    
    # 生成されたメッセージをクリーンアップ（改行や余分な文字を削除）
    full_commit_message=$(echo "$gemini_response" | head -n 1 | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    
    echo -e "${GREEN}生成されたコミットメッセージ: ${NC}$full_commit_message"
    
    while true; do
        echo -e "${CYAN}このコミットメッセージでよろしいですか？ [y/n]${NC}"
        read -r response
        case $response in
            [yY]|[yY][eE][sS])
                # 直接コミット実行
                git commit -m "$full_commit_message"
                echo -e "${GREEN}コミットが完了しました！${NC}"
                exit 0
                ;;
            [nN]|[nN][oO])
                refine_commit_message_with_gemini
                break
                ;;
            *)
                echo -e "${RED}yまたはnで答えてください。${NC}"
                ;;
        esac
    done
}

# コミットメッセージをGeminiと会話して改善
refine_commit_message_with_gemini() {
    echo -e "${CYAN}コミットメッセージをどのように変更したいか説明してください: ${NC}"
    read -r refinement_request
    
    if [ -z "$refinement_request" ]; then
        echo -e "${YELLOW}変更要求が空でした。元のメッセージを使用します。${NC}"
        return
    fi
    
    local prompt="現在のコミットメッセージ: '$full_commit_message'\n\nユーザーの要求: $refinement_request\n\n上記の要求に基づいて、「${commit_prefix}: 」で始まるコミットメッセージを改善してください。1行で日本語で出力してください。"
    
    # バックグラウンドでGeminiを実行
    local temp_file=$(mktemp)
    (echo -e "$prompt" | gemini 2>/dev/null > "$temp_file") &
    local gemini_pid=$!
    
    # スピナーを表示
    show_spinner $gemini_pid "$(printf "%bGeminiでコミットメッセージを改善しています...%b" "$BLUE" "$NC")"
    
    # バックグラウンド処理の完了を待つ
    wait $gemini_pid
    local exit_code=$?
    
    # 結果を読み込み
    local refined_response
    refined_response=$(cat "$temp_file")
    rm -f "$temp_file"
    
    if [ $exit_code -ne 0 ] || [ -z "$refined_response" ]; then
        echo -e "${RED}Geminiからの応答を取得できませんでした。元のメッセージを使用します。${NC}"
        return
    fi
    
    full_commit_message=$(echo "$refined_response" | head -n 1 | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    echo -e "${GREEN}新しいコミットメッセージ: ${NC}$full_commit_message"
    
    while true; do
        echo -e "${CYAN}このコミットメッセージでよろしいですか？ [y/n]${NC}"
        read -r response
        case $response in
            [yY]|[yY][eE][sS])
                # 直接コミット実行
                git commit -m "$full_commit_message"
                echo -e "${GREEN}コミットが完了しました！${NC}"
                exit 0
                ;;
            [nN]|[nN][oO])
                refine_commit_message_with_gemini
                break
                ;;
            *)
                echo -e "${RED}yまたはnで答えてください。${NC}"
                ;;
        esac
    done
}

# コミットメッセージの生成方法を選択
select_message_generation_method() {
    echo -e "${CYAN}コミットメッセージを自分で書きますか[1]、それともGeminiに依頼しますか[2]？${NC}"
    
    while true; do
        echo -n "選択してください [1-2]: "
        read -r choice
        case $choice in
            1)
                manual_commit_message
                # 手動入力の場合は最終確認へ進む
                final_commit
                break
                ;;
            2)
                generate_commit_message_with_gemini
                # Gemini生成の場合は承認後に直接コミットされるため、ここで終了
                break
                ;;
            *)
                echo -e "${RED}無効な選択です。1または2を入力してください。${NC}"
                ;;
        esac
    done
}

# 最終確認とコミット実行
final_commit() {
    local full_commit_message="${commit_prefix}: ${commit_message}"
    
    echo -e "${CYAN}最終的なコミットメッセージ:${NC}"
    echo -e "${GREEN}$full_commit_message${NC}"
    
    while true; do
        echo -e "${CYAN}この内容でコミットしますか？ [y/n]${NC}"
        read -r response
        case $response in
            [yY]|[yY][eE][sS])
                git commit -m "$full_commit_message"
                echo -e "${GREEN}コミットが完了しました！${NC}"
                break
                ;;
            [nN]|[nN][oO])
                echo -e "${YELLOW}コミットをキャンセルしました。${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}yまたはnで答えてください。${NC}"
                ;;
        esac
    done
}

# メイン処理
main() {
    echo -e "${BLUE}=== Gemini CLI Easy Commit ===${NC}"
    
    # 前提条件チェック
    check_git_repo
    check_gemini_cli
    
    # ステージングされた変更をチェック
    check_staged_changes
    
    # コミットタイプを選択
    select_commit_type
    
    # コミットメッセージ生成方法を選択（この中で処理が完結する）
    select_message_generation_method
}

# スクリプト実行
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi