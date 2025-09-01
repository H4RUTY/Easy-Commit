# Gemini CLI Easy Commit

Gemini CLIを使用してコミットメッセージを自動生成

<br>

## 種類

[commit_en.sh](https://github.com/H4RUTY/Easy-Commit/blob/main/commit_en.sh) / [commit_ja.sh](https://github.com/H4RUTY/Easy-Commit/blob/main/commit_ja.sh)

- 自動でGemini CLIがコミットメッセージを作成

<br>

[commit_interactive_en.sh](https://github.com/H4RUTY/Easy-Commit/blob/main/commit_interactive_en.sh) / [commit_interactive_ja.sh](https://github.com/H4RUTY/Easy-Commit/blob/main/commit_interactive_ja.sh)

- 対話形式でコミットメッセージを作成
- 自分でコミットメッセージを書くManualモード / Geminiモード切り替え


<br>

## 実行方法（Mac）

### Gemini CLI インストール

```bash
npm install -g @google/gemini-cli
```

### 'commit'コマンド登録

```bash
chmod +x commit.sh
sudo cp commit.sh /usr/local/bin/commit
```

### 実行

```bash
commit
```
