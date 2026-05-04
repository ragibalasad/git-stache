# git-stache

Clone all of your your GitHub repositories locally with a single script.

## Requirements

- Python 3.x
- Git
- A GitHub Personal Access Token with `repo` scope — [create one here](https://github.com/settings/tokens)

## Setup

```bash
git clone https://github.com/ragibalasad/git-stache.git
cd git-stache
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Copy `.env.example` to `.env` and add your token:

```text
GITHUB_TOKEN=your_personal_access_token_here
```

## Usage

```bash
python3 main.py
```

First run will ask where to store your repos. That choice is saved to `config.json` and reused on every subsequent run.

## How it works

- Fetches all repos you have access to via the GitHub API
- Clones repos that don't exist locally
- Pulls (rebase) repos that do
- Organizes everything as `<destination>/<owner>/<repo>`

## License

MIT
