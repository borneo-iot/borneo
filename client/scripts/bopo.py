#!/bin/python

import os
import subprocess
import argparse
import sys
import tempfile

__LANGUAGES = [
    'en_US',
    'de',
    'es',
    'zh_CN',
]

# Function to run shell commands and check for errors
def run_command(command):
    print(f"Executing: {command}")
    result = subprocess.run(command, shell=True, text=True, capture_output=True)
    if result.returncode != 0:
        print(f"Error occurred: {result.stderr}", file=sys.stderr)
        exit(result.returncode)


def normalize_catalog(file_path, clear_fuzzy=False):
    command = "msgattrib --no-location --sort-output"
    if clear_fuzzy:
        command += " --clear-fuzzy"
    command += f" -o {file_path} {file_path}"
    run_command(command)

# Function to find all .dart files and generate messages.pot
def generate_pot(project_path):
    lib_path = os.path.join(project_path, "lib")  # Dart source code path
    assets_path = os.path.join(project_path, "assets", "i18n")  # Translation files directory
    # Always make sure the English source locale is included in the update
    # list.  We ship en_US.po even though it typically just mirrors msgid values
    # because some build tools rely on its existence.
    languages = list(__LANGUAGES)
    if 'en_US' not in languages and 'en_us' not in languages:
        languages.insert(0, 'en_US')

    # Step 1: Find all Dart files recursively
    dart_files = []
    for root, dirs, files in os.walk(lib_path):
        for file in files:
            if file.endswith(".dart"):
                dart_files.append(os.path.relpath(os.path.join(root, file), lib_path))

    if not dart_files:
        print(f"No Dart files found in {lib_path}!")
        exit(1)

    # Step 2: Sort Dart files lexicographically
    dart_files.sort()

    # Ensure assets directory exists
    os.makedirs(assets_path, exist_ok=True)

    # Step 3: Generate .pot file
    pot_output_path = os.path.join(assets_path, "messages.pot")

    # Windows can hit command line limits when passing many files directly.
    # Write the list of Dart files to a temporary file and use --files-from.
    import tempfile
    with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".txt") as tf:
        for f in dart_files:
            tf.write(f + "\n")
        file_list_path = tf.name

    command = (
        f"xgettext --no-location --from-code=UTF-8 -L Python --keyword=translate "
        f"--output={pot_output_path} --directory={lib_path} --files-from={file_list_path}"
    )
    run_command(command)
    normalize_catalog(pot_output_path)

    # Step 4: Use msginit to create .po files for each language
    for lang in languages:
        po_file = os.path.join(assets_path, f"{lang}.po")

        # Create .po file using msginit
        if not os.path.exists(po_file) :
            print(f"Creating new .po file for {lang} at {po_file}")
            command = f"msginit --no-translator --input={pot_output_path} --locale={lang}.UTF-8 --output={po_file}"
            run_command(command)
            normalize_catalog(po_file)
        else:
            # Update the .po file with new translations using msgmerge
            # Disable fuzzy matching so only exact matches are merged
            print(f"Updating .po file for {lang}...")
            update_command = (
                f"msgmerge --no-location --backup=off --previous --no-fuzzy-matching --update {po_file} {pot_output_path}"
            )
            run_command(update_command)

            # Optional: clear any existing 'fuzzy' flags that may already be present in the file
            # This keeps only confirmed translations and avoids fuzzy entries lingering around
            normalize_catalog(po_file, clear_fuzzy=True)

    # Step 5: Compile .po files to .mo
    # for lang in languages:
    #     print(f"Compiling .mo file for {lang}...")
    #     po_file = os.path.join(assets_path, f"{lang}.po")
    #     mo_file = os.path.join(assets_path, f"{lang}.mo")
    #     compile_command = f"msgfmt {po_file} -o {mo_file}"
    #     run_command(compile_command)

    print("Translation update complete!")

# Main function to parse command line arguments
def list_missing(project_path):
    """Scan all .po files under assets/i18n and print missing translations.

    Displays file path, line number (when available) and the msgid.
    """
    assets_path = os.path.join(project_path, "assets", "i18n")
    if not os.path.isdir(assets_path):
        print(f"Assets directory not found: {assets_path}")
        exit(1)

    import polib

    for fname in sorted(os.listdir(assets_path)):
        # ignore non-po files and the English base locale (no translations needed)
        if not fname.endswith(".po"):
            continue
        # skip the default english locale which we don't want to report
        if fname.lower() == "en_us.po":
            continue

        po_path = os.path.join(assets_path, fname)
        print(f"Checking {po_path}...")
        po = polib.pofile(po_path)
        for entry in po:
            # untranslated when msgstr is empty and not fuzzy or obsolete
            if not entry.msgstr and not entry.fuzzy and not entry.obsolete:
                line = entry.linenum or '?'
                print(f"{po_path}:{line} - {entry.msgid}")


def check_files(project_path):
    """Verify that all translation files are well formed.

    Parses each .po file and runs msgfmt --check if available.  Exits
    with a non-zero status if any file is invalid.
    """
    assets_path = os.path.join(project_path, "assets", "i18n")
    if not os.path.isdir(assets_path):
        print(f"Assets directory not found: {assets_path}")
        exit(1)

    import polib
    errors = False
    for fname in sorted(os.listdir(assets_path)):
        if not fname.endswith(".po"):
            continue
        po_path = os.path.join(assets_path, fname)
        print(f"Validating {po_path}...")
        try:
            _ = polib.pofile(po_path)
        except Exception as e:
            print(f"  parse error: {e}", file=sys.stderr)
            errors = True
            continue
        with tempfile.NamedTemporaryFile(delete=False) as mo_tf:
            mo_path = mo_tf.name
        cmd = ["msgfmt", "--check", "--statistics", po_path, "-o", mo_path]
        result = subprocess.run(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            os.remove(mo_path)
        except OSError:
            pass
        if result.returncode != 0:
            print(f"  msgfmt check failed: {result.stderr.strip()}", file=sys.stderr)
            errors = True
    if errors:
        print("One or more files failed the check", file=sys.stderr)
        exit(1)
    print("All translation files are well-formed.")


def main():
    parser = argparse.ArgumentParser(description="Manage translation files for a Flutter project.")
    subparsers = parser.add_subparsers(dest='command', required=True)

    # update subcommand (previous default behaviour)
    upd = subparsers.add_parser('update', help="Generate/update .pot and .po files from Dart sources")
    upd.add_argument('project_path', help="The path to the Flutter project")

    # missing translations command
    miss = subparsers.add_parser('missing', help="List missing translations in .po files")
    miss.add_argument('project_path', help="The path to the Flutter project")

    # check command verifies that .po files are syntactically correct
    chk = subparsers.add_parser('check', help="Validate the format of translation files")
    chk.add_argument('project_path', help="The path to the Flutter project")

    args = parser.parse_args()

    if args.command == 'update':
        generate_pot(args.project_path)
    elif args.command == 'missing':
        list_missing(args.project_path)
    elif args.command == 'check':
        check_files(args.project_path)
    else:
        parser.print_help()
        exit(1)

if __name__ == "__main__":
    main()
