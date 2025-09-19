#!/bin/bash

# Gemini CLI 自動コミットスクリプト (日本語版)

set -e

# 色の定義
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
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
    
    # カーソルを隠す
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
    
    # カーソルを再表示
    printf "\033[?25h"
}

# Gemini CLIの可用性確認
check_gemini_cli() {
    if ! command -v gemini &> /dev/null; then
        error_exit "Gemini CLIが見つかりません。インストールしてください。"
    fi
}

# Gitリポジトリの確認
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        error_exit "Gitリポジトリが見つかりません。"
    fi
}

# ステージング変更の確認
check_staged_changes() {
    local staged_changes
    local unstaged_changes
    
    staged_changes=$(git diff --cached --name-only)
    unstaged_changes=$(git diff --name-only)
    
    if [ -z "$staged_changes" ]; then
        if [ -z "$unstaged_changes" ]; then
            echo -e "${YELLOW}コミットする変更がありません。${NC}"
            exit 0
        else
            echo -e "${YELLOW}ステージングされた変更が見つかりません。${NC}"
            echo -e "${CYAN}すべての変更をステージングしますか？ [y/n]: ${NC}"
            read -r response
            case $response in
                [yY]|[yY][eE][sS])
                    git add .
                    echo -e "${GREEN}すべての変更がステージングされました。${NC}"
                    ;;
                *)
                    echo -e "${YELLOW}終了します。${NC}"
                    exit 0
                    ;;
            esac
        fi
    fi
}

# Geminiでコミットメッセージを生成（プレフィックス自動検出）
generate_commit_message_with_gemini() {
    local diff_output
    diff_output=$(git diff --cached)
    
    if [ -z "$diff_output" ]; then
        error_exit "ステージングされた変更が見つかりません。"
    fi
    
    # Geminiにプロンプトを送信（プレフィックス自動検出とメッセージ生成）
    local prompt="以下のGit diffを分析して、簡潔で明確な一行のコミットメッセージを日本語で生成してください。

変更内容に基づいて適切なプレフィックスを選択してください：
- feat: 新機能追加
- fix: バグ修正
- docs: ドキュメント更新
- style: コードフォーマット
- refactor: リファクタリング
- perf: パフォーマンス改善
- test: テスト追加・修正
- chore: その他の雑務

フォーマット: 'プレフィックス: メッセージ'

例：
- feat: ユーザー認証システムを追加
- fix: ログインバリデーションのバグを修正
- docs: APIドキュメントを更新
- style: コードをPrettierでフォーマット
- refactor: ユーザーサービスのロジックを抽出
- perf: データベースクエリを最適化
- test: 認証モジュールの単体テストを追加
- chore: 依存関係を更新

Diff:
$diff_output"
    
    # Geminiをバックグラウンドで実行
    local temp_file=$(mktemp)
    (echo -e "$prompt" | gemini 2>/dev/null > "$temp_file") &
    local gemini_pid=$!
    
    # スピナー表示
    show_spinner $gemini_pid "$(printf "%b変更内容を分析してコミットメッセージを生成中...%b" "$BLUE" "$NC")"
    
    # バックグラウンドプロセスの完了を待機
    wait $gemini_pid
    local exit_code=$?
    
    # 結果を読み取り
    local gemini_response
    gemini_response=$(cat "$temp_file")
    rm -f "$temp_file"
    
    if [ $exit_code -ne 0 ] || [ -z "$gemini_response" ]; then
        error_exit "Geminiからのレスポンスの取得に失敗しました。"
    fi
    
    # 生成されたメッセージをクリーンアップ（改行や余分な文字を削除）
    full_commit_message=$(echo "$gemini_response" | head -n 1 | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    
    echo -e "${GREEN}生成されたコミットメッセージ:${NC}\n$full_commit_message"
    
    while true; do
        echo -e "${CYAN}このコミットメッセージを使用しますか？ [y/n]: ${NC}"
        read -r response
        case $response in
            [yY]|[yY][eE][sS])
                # 直接コミットを実行
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

# Geminiとの会話でコミットメッセージを改良
refine_commit_message_with_gemini() {
    echo -e "${CYAN}コミットメッセージをどのように改善したいですか？: ${NC}"
    read -r refinement_request
    
    if [ -z "$refinement_request" ]; then
        echo -e "${YELLOW}改善リクエストが提供されませんでした。元のメッセージを使用します。${NC}"
        # 確認に戻る
        while true; do
            echo -e "${CYAN}元のコミットメッセージを使用しますか？ [y/n]: ${NC}"
            read -r response
            case $response in
                [yY]|[yY][eE][sS])
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
        return
    fi
    
    local prompt="現在のコミットメッセージ: '$full_commit_message'

ユーザーのリクエスト: $refinement_request

上記のリクエストに基づいて、コミットメッセージを改善してください。同じフォーマット'プレフィックス: メッセージ'を保ち、一行で日本語で出力してください。"
    
    # Geminiをバックグラウンドで実行
    local temp_file=$(mktemp)
    (echo -e "$prompt" | gemini 2>/dev/null > "$temp_file") &
    local gemini_pid=$!
    
    # スピナー表示
    show_spinner $gemini_pid "$(printf "%bコミットメッセージを改良中...%b" "$BLUE" "$NC")"
    
    # バックグラウンドプロセスの完了を待機
    wait $gemini_pid
    local exit_code=$?
    
    # 結果を読み取り
    local refined_response
    refined_response=$(cat "$temp_file")
    rm -f "$temp_file"
    
    if [ $exit_code -ne 0 ] || [ -z "$refined_response" ]; then
        echo -e "${RED}Geminiからのレスポンスの取得に失敗しました。元のメッセージを使用します。${NC}"
        # 元のメッセージで確認に戻る
        while true; do
            echo -e "${CYAN}元のコミットメッセージを使用しますか？ [y/n]: ${NC}"
            read -r response
            case $response in
                [yY]|[yY][eE][sS])
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
        return
    fi
    
    full_commit_message=$(echo "$refined_response" | head -n 1 | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    echo -e "${GREEN}改善されたコミットメッセージ:${NC}\n$full_commit_message"
    
    while true; do
        echo -e "${CYAN}このコミットメッセージを使用しますか？ [y/n]: ${NC}"
        read -r response
        case $response in
            [yY]|[yY][eE][sS])
                # 直接コミットを実行
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

# メインプロセス
main() {
    # 前提条件の確認
    check_git_repo
    check_gemini_cli
    
    # ステージングされた変更の確認
    check_staged_changes
    
    # Geminiで自動的にコミットメッセージを生成
    generate_commit_message_with_gemini
}

# スクリプトを実行
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi