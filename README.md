# git-stache

Syncs all your GitHub repos (public + private) to a local folder. Clones new
repos, pulls existing ones.

## Requirements

- A GitHub PAT needs to be already stored in git's credential helper. If you haven't done
  this yet:

  ```bash
  git config --global credential.helper store
  git clone https://github.com/<your-username>/<any-private-repo>.git
  # enter username and PAT when prompted
  ```

## Run without cloning this repo

```bash
curl -fsSL https://raw.githubusercontent.com/ragibalasad/git-stache/main/gitstache.sh | bash
```

Or download it first if you want to read it before running:

```bash
curl -fsSL https://raw.githubusercontent.com/ragibalasad/git-stache/main/gitstache.sh -o gitstache.sh
chmod +x github-sync.sh
./gitstache.sh
```

## Notes

- Uses `git pull --ff-only` — won't create merge commits, fails on diverged branches instead.
- Token isn't written to disk or put in any URL.
- Override storage path for one run: `GH_SYNC_BASE_DIR=/path ./github-sync.sh`
