## Purpose

A desktop application for Windows, Linux and macOS that lets a person choose what the setup wizards install, run the matching wizard with that choice, follow its progress and read the outcome, without ever seeing a terminal, without ever reimplementing what the wizards decide or do.

## ADDED Requirements

### Requirement: The application never runs elevated

The application SHALL run as the logged-in user. On Windows its manifest MUST request `asInvoker`. When started elevated on Windows, or as root (effective user id 0) on Linux or macOS, it MUST refuse to continue, show why, and offer no way past the refusal. It MUST never start the wizard with `-AllowAdministrator` or `--passwordless-sudo`, with one exception: when started with both `--self-test` and `--allow-administrator`, it MAY run the wizard's listing options with `-AllowAdministrator`, because a hosted Windows runner makes every process elevated. `--allow-administrator` without `--self-test` MUST be refused with exit code 2, and `--self-test` never starts a run that installs anything.

#### Scenario: Self-test on a hosted Windows runner

- WHEN the application runs `--self-test --allow-administrator` on `windows-latest`
- THEN it runs only `setup.ps1 -ListSoftware -Json -AllowAdministrator` and exits

#### Scenario: Administrator flag outside the self-test

- WHEN the application is started with `--allow-administrator` alone
- THEN it exits 2 and names `--self-test` as the only option it combines with

#### Scenario: Started as root on Linux

- WHEN the application is started with `sudo`
- THEN it shows a message that it must be started as the normal user and that the wizard asks for the password itself
- AND it starts no process

#### Scenario: Started elevated on Windows

- WHEN the application is started with Run as administrator
- THEN it shows the same refusal and starts no process

### Requirement: The application runs only the bundled wizard for its own platform

On Linux and macOS the application SHALL run `setup/setup.sh` with `bash`, and on Windows it SHALL run `setup/setup.ps1` with PowerShell 7 (`pwsh`), from the scripts bundled in the artifact, unpacked as the desktop-distribution capability specifies. It MUST pass only options those scripts document. It MUST NOT install, configure or verify any software itself.

#### Scenario: Run started on Debian

- WHEN the user starts a run on Debian
- THEN the only process started is `bash <unpacked>/setup/setup.sh` with selection options
- AND every package that gets installed is installed by that process or its children

### Requirement: The catalogue comes from the wizard

The application SHALL build its list of choices only from `--list-software --json` (or `-ListSoftware -Json`) and, on Linux and macOS, `--list-profiles --json`. It MUST NOT read the group_vars files, keep its own list of toggles, or ship a pre-generated copy of the list. When the listing fails, it MUST show the wizard's own error output and the exit code, and offer to retry.

#### Scenario: A toggle is added to all.yaml

- WHEN a release is built from a commit where `install_example: true` was added to `setup/ansible/group_vars/all.yaml`
- THEN the application shows `install_example` with its label and default without any change to the application code

#### Scenario: Listing fails

- WHEN the listing exits non-zero
- THEN the application shows the exit code and the full standard error text and does not show a partial list

### Requirement: Prerequisites are checked before the catalogue is loaded

The application SHALL check, before running any listing, that the wizard can start: on Windows that PowerShell 7 or newer is available, on macOS that a bash of version 4 or newer exists at one of the paths `setup.sh` searches. When a prerequisite is missing it MUST say which one, link the official installation page, show the exact installation command, and offer one button that runs that command only after the user presses it, shown as a progress row with its output behind "Show details".

#### Scenario: Fresh Windows without PowerShell 7

- WHEN the application starts on a Windows machine where `pwsh` is not found
- THEN it explains that the wizard needs PowerShell 7
- AND pressing the install button runs `winget install --id Microsoft.PowerShell --exact --source winget --accept-package-agreements --accept-source-agreements` and shows it as a progress row
- AND after that command exits 0 the application finds `pwsh.exe` without being restarted and continues

#### Scenario: Windows without winget

- WHEN neither `pwsh` nor `winget` is found
- THEN the application links the official winget installation page and the official PowerShell installation page and runs nothing

#### Scenario: Fresh macOS without Homebrew

- WHEN no bash 4 or newer and no Homebrew is found
- THEN the application explains both, links https://brew.sh, shows the exact Homebrew install command that page publishes, and runs nothing until the user presses the button
- AND pressing the button runs that command, shown as a progress row, where Homebrew's own password prompt is answered through the password dialog and its confirmation questions through buttons

### Requirement: The user chooses with the same options the wizard offers

The application SHALL offer, on Linux, the desktop environment (`skip`, `kde`, `gnome`) and its action (`full`, `install`, `configure`), an optional profile, and the toggle checklist grouped by `group` with a text filter. On macOS it offers the profile and the checklist. On Windows it offers the checklist only. The checklist starts from each toggle's `default`. Choosing a profile disables the checklist and shows the profile's overrides, because the wizard refuses a profile together with a software selection. It SHALL also offer "Skip the system upgrade", off by default.

#### Scenario: Profile chosen

- WHEN the user picks the `linux_live` profile
- THEN the checklist is read-only and shows the states the profile sets
- AND the run passes `--profile linux_live` and no `--software`, `--enable` or `--disable`

### Requirement: The command is built in one place and previewed by the wizard

The application SHALL turn a selection into wizard arguments in exactly one function per wizard. For a checklist selection it MUST pass the full explicit set: `--software none --enable <every ticked key>` on Linux and macOS, `-Software none -EnableKey <every ticked key>` on Windows. Before a run it SHALL show the wizard's own answer to `--print-command` on Linux and macOS or `-PrintPlan` on Windows for exactly those arguments, and the run MUST use exactly the arguments that were previewed.

#### Scenario: Preview matches the run

- WHEN the user ticks `install_git` and `install_jq` only, on Linux, and opens the preview
- THEN the preview is the output of `setup.sh --software none --enable install_git,install_jq --print-command`
- AND pressing Run starts `setup.sh --software none --enable install_git,install_jq --result-file <path>` plus any upgrade choice, and nothing else

### Requirement: The user never sees a terminal

The application SHALL NOT contain a terminal emulator or a terminal widget, and MUST NOT offer any place where the user types into the wizard directly. The pseudo terminal (a ConPTY on Windows) SHALL exist only as a hidden channel between the application and the wizard, needed because `setup.sh` reads the sudo password from a terminal, and MUST never be drawn on screen. A tier 1 check MUST fail when the application declares or imports a terminal widget package.

#### Scenario: Terminal widget added by mistake

- WHEN `desktop/pubspec.yaml` gains the `xterm` package, or a file under `desktop/lib` imports `package:xterm/`
- THEN `bash e2e/run.sh` fails and names the file and the line

### Requirement: The run is shown as a progress list

The application SHALL start the wizard attached to the hidden pseudo terminal and show the run as a progress list built from the wizard's output: one row per step and one row per package, each with a status of running, installed, skipped with its reason, or failed with its reason, followed by the summary when the run ends. The raw output MUST be kept in memory and written, as it arrives, to a transcript file in the user's home directory, named on the summary screen, next to the wizard's own log files. The raw output SHALL be shown only behind a "Show details" button, as plain read-only text with no input, no cursor and no terminal emulation. A line the application does not recognise MUST stay in the raw output and MUST NOT stop the run. The per-application verdicts on the summary MUST come from the result file, not from the progress list.

#### Scenario: Live progress

- WHEN the wizard prints the line that starts a step or reports a package
- THEN the matching row appears or changes status in the progress list within one second
- AND the line is appended to the transcript file

#### Scenario: Package skipped

- WHEN the wizard reports a package as skipped with a reason
- THEN its row shows skipped and that reason

#### Scenario: Show details

- WHEN the user presses "Show details" during or after a run
- THEN the full output so far is shown as plain text that can be selected and copied
- AND typing in that view sends nothing to the wizard

#### Scenario: Live list and result file disagree

- WHEN a package row shows installed and the result file reports that application as `missing`
- THEN the summary shows `missing` for it

### Requirement: Every question is answered through the application's own dialogs

On Linux and macOS the application SHALL recognise the wizard's sudo password prompt (`[sudo] password for <user>:` from `setup.sh` and from sudo itself, and `Password:` from sudo on macOS) on the hidden channel and show its own modal password dialog with a password field, OK and Cancel. OK MUST write the typed password to the channel followed by a newline, and the password MUST NOT be shown, logged, written to the transcript or any other file, stored, or kept in memory after it is written. After the wizard refuses a password, the dialog SHALL open again for the next prompt with a message that the password was not accepted. Cancel MUST stop the run cleanly, by the Cancel procedure of this spec, and the summary MUST say the run was cancelled at the password question. The reboot question `Reboot now? [y/N]` SHALL be shown as Yes and No buttons that write `y` or `n` and a newline. Any other question on the channel MUST NOT leave the run waiting silently: when a partial line stays unchanged for 3 seconds, the application SHALL show it in a dialog with the last lines of output, a free text answer and a button that stops the run, close that dialog by itself when new output arrives, and stop the run cleanly when the question is not answered within 15 minutes. When there has been no output for 2 minutes, the current row SHALL offer a button that opens the same dialog.

#### Scenario: Correct password

- WHEN `setup.sh` asks for the sudo password and the user types it into the dialog and presses OK
- THEN `setup.sh` accepts it exactly as it would in a terminal and the run continues
- AND the transcript contains the prompt and no character of the password

#### Scenario: Wrong password

- WHEN the user types a wrong password
- THEN the dialog is shown again for the wizard's next prompt with the message that the password was not accepted
- AND after the wizard's third refusal the run ends with the wizard's exit code 1 and the summary says so

#### Scenario: More than one password prompt in one run

- WHEN `setup.sh` asks for the password at the start and plain `sudo` asks again later in the same run
- THEN the dialog is shown once for each prompt, as the prompt appears
- AND each answer is written to the hidden channel only, and nothing the user typed is found in the transcript, the result file or the application's data directory afterwards

#### Scenario: Cancel in the password dialog

- WHEN the user presses Cancel in the password dialog
- THEN the wizard receives an interrupt, no process started by the run is left running, and the summary says the run was cancelled at the password question with the wizard's exit code

#### Scenario: Reboot question

- WHEN `setup.sh` asks `Reboot now? [y/N]`
- THEN the application shows Yes and No buttons and writes `y` or `n` and a newline for the one pressed

#### Scenario: Unrecognised question

- WHEN the wizard prints a question the application has no pattern for and waits
- THEN within 4 seconds the application shows the question text in a dialog with a text field, Send and a button that stops the run
- AND Send writes the text and a newline to the channel

#### Scenario: Unanswered question

- WHEN that dialog is not answered for 15 minutes
- THEN the application stops the run cleanly and the summary names the unanswered question

### Requirement: On Windows, administrator rights are asked for by Windows

On Windows the application SHALL start `setup.ps1` as the normal user and MUST NOT show a password dialog or any dialog of its own for administrator rights, ask for, read or store an administrator password, or elevate itself. Each wizard step that needs administrator rights elevates itself, and Windows shows its own User Account Control prompt for it. When the user refuses that prompt, the application SHALL show the wizard's own report of the failed step and its exit code on the summary.

#### Scenario: A step needs administrator rights

- WHEN a run on Windows reaches a step that needs administrator rights
- THEN Windows shows its User Account Control prompt, and the application shows no dialog of its own
- AND the application's own process and the `pwsh` process it started stay unelevated for the whole run

#### Scenario: The user refuses the prompt

- WHEN the user refuses the User Account Control prompt
- THEN the run continues or ends as `setup.ps1` decides, and the summary shows the failed step and the wizard's exit code

### Requirement: A run can be cancelled

The application SHALL offer Cancel during a run. Cancel MUST send an interrupt (Ctrl+C) through the hidden pseudo terminal, wait up to 30 seconds for the wizard to exit, and only then end the process tree. Closing the window during a run MUST ask for confirmation and then cancel the same way.

#### Scenario: Cancel during the system upgrade

- WHEN the user presses Cancel while the wizard runs
- THEN the wizard receives an interrupt and its own exit code is shown
- AND no process started by the run is left running after the summary appears

### Requirement: The summary comes from the result file

At the end of a run the application SHALL read the result file the wizard wrote and show the overall verdict for the exit code (0 success, 1 install failure, 2 bad usage, 3 install succeeded but the verification found something missing, 130 cancelled), the per-application verdicts, and the paths of the wizard's log files and of the transcript. When the result file is missing or invalid, it MUST say so and show the process exit code and the transcript path rather than a guessed summary.

#### Scenario: Verification found a missing application

- WHEN the wizard exits 3
- THEN the summary says the install finished but something is missing, lists the applications with verdict `missing` first, and names the verification log

#### Scenario: No result file

- WHEN the wizard exits without writing the result file
- THEN the summary says the result file is missing, shows the exit code, and names the transcript

### Requirement: The process environment of the run is the user's, not the package's

The application SHALL start the wizard with an environment free of variables its own packaging injected, so host tools such as Python, apt and Ansible see the same environment they would see from a terminal. At least `LD_LIBRARY_PATH`, `LD_PRELOAD`, `GTK_PATH`, `GDK_PIXBUF_MODULE_FILE`, `GIO_MODULE_DIR`, `PYTHONPATH`, `PYTHONHOME`, `APPDIR`, `APPIMAGE`, `ARGV0`, `OWD` and every variable whose name starts with `SNAP` MUST be removed, or restored to the value the packaging saved before changing it. `TERM` MUST be set to `xterm-256color`.

#### Scenario: AppImage

- WHEN the AppImage starts a run
- THEN `env` printed by the first command of the run contains none of the variables listed above that the host terminal does not also have

### Requirement: Only one run at a time

The application SHALL refuse to start a second run while one is in progress, in the same window or in a second instance, using a lock file in the per-user application data directory that is removed when the run ends.

#### Scenario: Second instance

- WHEN a second instance is started during a run and the user presses Run
- THEN it says a run is already in progress and starts nothing
