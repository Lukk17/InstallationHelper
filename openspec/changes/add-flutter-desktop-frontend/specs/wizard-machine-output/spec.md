## Purpose

Gives programs, starting with the desktop application, a stable machine-readable view of what both setup wizards offer and of what a run actually did, produced by the wizards themselves so there is only one source of truth for the toggle list and the verdicts.

## ADDED Requirements

### Requirement: The software listing has a JSON form on both wizards

`setup.sh --list-software --json` and `setup.ps1 -ListSoftware -Json` SHALL print one JSON document to standard output that validates against `setup/contract/catalog.schema.json`, and nothing else on standard output. The document MUST list exactly the toggles the existing text listing prints, in the same order, with the same default state and the same label. Each entry MUST carry `key`, `label`, `default` as a JSON boolean, and `group`. The document MUST carry `schema_version`, `wizard` and `os_family`.

#### Scenario: Listing on Linux

- WHEN `bash setup/setup.sh --list-software --json` runs on a supported Linux machine
- THEN it exits 0 and standard output parses as JSON
- AND the document validates against `setup/contract/catalog.schema.json`
- AND the keys, their order, their default states and their labels equal what `bash setup/setup.sh --list-software` prints

#### Scenario: Listing on Windows

- WHEN `pwsh -NoProfile -File setup/setup.ps1 -ListSoftware -Json` runs as a normal user
- THEN it exits 0 and standard output parses as JSON that validates against the same schema
- AND the keys, order, default states and labels equal what `-ListSoftware` prints

#### Scenario: Listing changes nothing

- WHEN either listing runs
- THEN no package is installed, no system upgrade runs, no password is asked for and no file outside the system temporary directory is written

### Requirement: The group of a toggle comes from the comment heading above it

The `group` of a toggle SHALL be the text of the nearest preceding comment line that stands alone in the group_vars file the toggle is read from, with the leading `#` and surrounding spaces removed, ignoring lines made only of `#` and `-` characters. A toggle with no such line above it MUST have `group` set to JSON null. Both wizards MUST derive the same group for every key they both list, and a tier 1 check MUST fail when they do not.

#### Scenario: Toggle under a heading

- WHEN `group_vars/all.yaml` has the line `# Browsers` followed by `install_chrome: true`
- THEN the listing entry for `install_chrome` has `group` equal to `Browsers` on both wizards

#### Scenario: Parity between the wizards

- WHEN tier 1 runs both listings against the same checkout
- THEN every key present in both documents has the same label rule outcome, the same group and the same default state where both wizards read the same file for it

### Requirement: The profile listing has a JSON form

`setup.sh --list-profiles --json` SHALL print one JSON document validating against `setup/contract/profiles.schema.json` that lists every file under `setup/ansible/profiles/` with `id` (the file name without extension), `name`, `description` and `overrides`, a map from toggle key to boolean for every selectable toggle the profile sets. The name and description MUST be derived exactly as the interactive profile screen derives them. `--list-profiles` without `--json` SHALL print the same information as text.

#### Scenario: The live profile

- WHEN `bash setup/setup.sh --list-profiles --json` runs
- THEN the document contains an entry with `id` equal to `linux_live`
- AND its `overrides` contains every selectable key that `setup/ansible/profiles/linux_live.yaml` sets, with the value that file sets

### Requirement: The JSON flag is refused where it means nothing

`--json` and `-Json` SHALL be accepted only together with a listing option. Any other combination MUST exit 2 with a message naming the options that accept it, before anything is installed, matching the existing refusal style for unknown keys.

#### Scenario: JSON with a run

- WHEN `bash setup/setup.sh --json --software defaults` runs
- THEN it exits 2 and standard error names `--list-software` and `--list-profiles`
- AND nothing is installed

### Requirement: A run can write a machine-readable result file

`setup.sh --result-file <path>` and `setup.ps1 -ResultFile <path>` SHALL write, at the end of every run that reaches the verification, a JSON document validating against `setup/contract/result.schema.json`. It MUST carry `schema_version`, `wizard`, `exit_code` equal to the code the process is about to exit with, `install_exit_code`, `verification_exit_code`, the paths of every log file the run wrote, and `applications`, one entry per application the verification reported, with `key`, `verdict`, `raw_verdict` and `detail`. `raw_verdict` MUST be the exact verdict text the on-screen report printed for that row. `verdict` MUST be its normalised form, one of `installed`, `missing`, `unreachable`, `unverifiable`, `not_requested` and `not_applicable`, mapped as the schema documents: `MISSING` to `missing`, `UNREACHABLE` and `UNREACHABLE (login shell only)` to `unreachable`, `UNVERIFIABLE` to `unverifiable`, `not requested` to `not_requested`, `not applicable` to `not_applicable`. A report verdict the schema does not map MUST make the wizard fail its own tier 1 check rather than be written as an unknown value. The file MUST be written atomically, by writing a sibling temporary file and renaming it. When the run stops before the verification, the file MUST still be written with `exit_code` and an empty `applications` list, unless the process is killed.

#### Scenario: Successful run

- WHEN a run with `--result-file /tmp/r.json` succeeds and verifies
- THEN `/tmp/r.json` exists, validates against the schema, and `exit_code` is 0
- AND every application named in the on-screen verification report appears in `applications` with the same verdict

#### Scenario: Verification finds something missing

- WHEN the install succeeds and the verification reports an application missing
- THEN the process exits 3 and the result file has `exit_code` 3 and that application with verdict `missing`

#### Scenario: Forced failure

- WHEN the tier 3 forced-failure scenario runs with a result file requested
- THEN the result file has a non-zero `exit_code` equal to the process exit code
- AND the application the scenario breaks is reported with verdict `missing`

#### Scenario: Unwritable path

- WHEN the result file path points into a directory that does not exist
- THEN the wizard exits 2 before installing anything and names the path

### Requirement: Every interactive prompt of setup.sh is listed in the contract

`setup/contract/interactive_prompts.json` SHALL list every prompt `setup.sh` itself can print and then wait on, with an `id`, the exact prompt text with `<user>` in place of the user name, the answer kind (`password`, `password_refused` or `yes_no`) and the function that prints it. A tier 1 check MUST fail, naming the line, when a `read` with `-p` in `setup.sh` has a prompt the file does not list, when the file lists a prompt `setup.sh` no longer prints, or when a `read` without `-p` is neither a `while ... read` loop fed by a redirection or a pipe nor a `read ... <<<` here-string. The desktop application MUST know every entry, which its own unit test proves by reading this file.

#### Scenario: New question added to setup.sh

- WHEN a change adds `read -r -p "Continue? [y/N] " answer` to `setup.sh` without adding it to `setup/contract/interactive_prompts.json`
- THEN `bash e2e/run.sh` fails and names the line of `setup.sh`

#### Scenario: Inventory as of this change

- WHEN the check runs against `setup.sh` as it stands on 2026-10-11
- THEN it finds the sudo password prompt of `prepare_become_password` and the reboot question of `offer_reboot`, both listed, and passes

### Requirement: Existing behaviour is unchanged

Without the new options, every existing option, the interactive path, the text output, the log files and the exit codes of both wizards SHALL behave exactly as before this change.

#### Scenario: Tier 1 gate

- WHEN `bash e2e/run.sh` runs after the change
- THEN every check that passed before the change still passes, including `list_software.sh`, `wizard_parse.sh`, `print_command_resolution.sh` and `selection_parity.sh`
