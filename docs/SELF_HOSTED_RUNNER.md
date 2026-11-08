# Run FieldOS's GitHub jobs on your own computer (free)

GitHub charges for the minutes its own machines run. Jobs that run on your
own computer (a "self-hosted runner") are free, even for a private repo.
Your computer has to be switched on and connected while a job runs.

Every Linux job in `.github/workflows` reads the repository variable
`LINUX_RUNNER`. Unset, jobs use GitHub's machines. Set to `self-hosted`,
they use your computer. Delete the variable to go back.

The Windows desktop installer and the iPhone build still need GitHub's
machines. The Android app, the database deploy and every check run on
yours.

## 1. Get a Linux terminal

- **Windows 10/11:** open PowerShell as administrator, run
  `wsl --install -d Ubuntu`, restart, then open "Ubuntu" from the Start menu
  and choose a username and password.
- **Ubuntu or another Linux:** open a terminal.
- **Mac:** not supported for these jobs (some steps need Linux). Use a
  Windows or Linux computer, or a small Linux machine in the cloud.

## 2. Install the tools the jobs expect

Paste this in the Ubuntu terminal:

```bash
sudo apt update
sudo apt install -y curl git unzip xz-utils zip jq python3 python3-pip python3-venv \
  libglu1-mesa docker.io openjdk-17-jdk
sudo usermod -aG docker "$USER"
```

Close the terminal and open it again so Docker works without `sudo`.

## 3. Connect the runner to GitHub

1. Open github.com/organizations/Vidyuthlabstechnologies/settings/actions/runners
2. Click **New runner**, then **New self-hosted runner**, and choose
   **Linux** and **x64**.
3. GitHub shows a block of commands under "Download" and "Configure".
   Paste them into the Ubuntu terminal one by one. When it asks
   questions, press Enter to keep each default.
4. Start it with `./run.sh`. Leave this window open. It says
   "Listening for Jobs" when it's ready.

To start it by itself whenever the computer starts (Ubuntu, or WSL with
systemd), run `sudo ./svc.sh install && sudo ./svc.sh start` in the same
folder instead of `./run.sh`.

## 4. Point the jobs at it

1. Open github.com/Vidyuthlabstechnologies/fieldos/settings/variables/actions
2. Click **New repository variable**. Name: `LINUX_RUNNER`. Value:
   `self-hosted`. Save.

From now on, jobs show up in the runner window. Re-run anything that failed
from the Actions tab.

## Safety

- The jobs run code from this repository on your computer. Only people you
  trust should be able to push to it. Pull requests from forks don't run
  here, because the repository is private.
- The "free disk space" steps only run on GitHub's machines, never on yours.
- The first Android build downloads Flutter and the Android SDK, about
  3 GB. Later builds reuse them.
