import os
import dotenv
import requests
import subprocess
import json
from pathlib import Path

dotenv.load_dotenv()

GREEN = "\033[92m"
RED = "\033[91m"
CYAN = "\033[96m"
YELLOW = "\033[93m"
RESET = "\033[0m"
BOLD = "\033[1m"

CONFIG_FILE = "config.json"

def get_config():
  if os.path.exists(CONFIG_FILE):
    with open(CONFIG_FILE, "r") as f:
      config = json.load(f)
      return Path(config["base_dir"])
  
  print(f"{CYAN}Where would you like to store your repositories?{RESET}")
  print(f"1. {BOLD}Documents{RESET}")
  print(f"2. {BOLD}Desktop{RESET}")
  print(f"3. {BOLD}Downloads{RESET}")
  print(f"4. {BOLD}Custom Path{RESET}")
  
  choice = input(f"\n{YELLOW}Choose an option (1-4): {RESET}")
  
  home = Path.home()
  if choice == "1":
    base = home / "Documents" / "github-archive"
  elif choice == "2":
    base = home / "Desktop" / "github-archive"
  elif choice == "3":
    base = home / "Downloads" / "github-archive"
  elif choice == "4":
    custom_path = input(f"{YELLOW}Enter custom path: {RESET}")
    base = Path(custom_path).expanduser().resolve()
  else:
    print(f"{RED}Invalid choice. Defaulting to current directory 'repos'.{RESET}")
    base = Path("repos").resolve()
    
  # Save config
  base.mkdir(parents=True, exist_ok=True)
  with open(CONFIG_FILE, "w") as f:
    json.dump({"base_dir": str(base)}, f)
    
  print(f"{GREEN}✔ Destination saved to {BOLD}{CONFIG_FILE}{RESET}{GREEN}: {base}{RESET}\n")
  return base

def get_repos(token: str):
  repos = []
  page = 1
  per_page = 100
  
  print(f"{CYAN}  Fetching repository list from GitHub...{RESET}")
  while True:
    url = f"https://api.github.com/user/repos?per_page={per_page}&page={page}&type=all"
    headers = {
        "Authorization": f"token {token}"
    }
    response = requests.get(url, headers=headers)
    
    if response.status_code == 200:
      page_repos = response.json()
      if not page_repos:
        break
      for repo in page_repos:
        repos.append({
          "full_name": repo["full_name"],
          "clone_url": repo["clone_url"]
        })
      page += 1
    else:
      print(f"{RED}✘ Error fetching repositories: {response.status_code}{RESET}")
      break
      
  return repos

def sync_repos(token: str, repos: list, base_dir: Path):
  for i, repo in enumerate(repos, 1):
    full_name = repo["full_name"]
    clone_url = repo["clone_url"]
    auth_url = clone_url.replace("https://", f"https://x-access-token:{token}@")
    repo_path = base_dir / full_name
    prefix = f"{CYAN}[{i}/{len(repos)}]{RESET}"
    
    if (repo_path / ".git").exists():
      print(f"{prefix} {YELLOW}➜ Updating {BOLD}{full_name}{RESET}...")
      result = subprocess.run(["git", "-C", str(repo_path), "pull", "--rebase"])
      if result.returncode == 0:
        print(f"      {GREEN}✔ Update complete.{RESET}")
      else:
        print(f"      {RED}✘ Failed to update {full_name}{RESET}")
    else:
      print(f"{prefix} {CYAN}➜ Cloning {BOLD}{full_name}{RESET}...")
      repo_path.parent.mkdir(parents=True, exist_ok=True)
      result = subprocess.run(["git", "clone", auth_url, str(repo_path)])
      if result.returncode == 0:
        print(f"      {GREEN}✔ Cloning complete.{RESET}")
      else:
        print(f"      {RED}✘ Failed to clone {full_name}{RESET}")

token = os.getenv("GITHUB_TOKEN")
if not token:
  print(f"{RED}✘ GITHUB_TOKEN not found in .env file.{RESET}")
  exit(1)

base_dir = get_config()
repos = get_repos(token)
print(f"{GREEN}  Found {BOLD}{len(repos)}{RESET}{GREEN} repositories. Starting sync...{RESET}\n")
sync_repos(token, repos, base_dir)
print(f"\n{GREEN}{BOLD}✔ Sync complete!{RESET}")

