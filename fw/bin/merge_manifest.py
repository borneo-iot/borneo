#!/usr/bin/env python3
import json
import argparse
import os
import glob
import sys

def main():
    parser = argparse.ArgumentParser(description='Merge manifest JSON files into a single array.')
    parser.add_argument('directory', help='Directory path containing *.manifest.json files')
    parser.add_argument('-o', '--output', required=True, help='Output JSON file path')

    args = parser.parse_args()

    if not os.path.isdir(args.directory):
        print(f"Error: Directory '{args.directory}' does not exist.")
        sys.exit(1)

    manifest_files = glob.glob(os.path.join(args.directory, '*.manifest.json'))

    if not manifest_files:
        print(f"No *.manifest.json files found in '{args.directory}'.")
        sys.exit(1)

    merged_data = []

    for file_path in manifest_files:
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                merged_data.append(data)
        except json.JSONDecodeError as e:
            print(f"Error parsing JSON in '{file_path}': {e}")
            sys.exit(1)
        except Exception as e:
            print(f"Error reading '{file_path}': {e}")
            sys.exit(1)

    try:
        with open(args.output, 'w', encoding='utf-8') as f:
            json.dump(merged_data, f, indent=4)
        print(f"Successfully merged {len(merged_data)} manifest files into '{args.output}'.")
    except Exception as e:
        print(f"Error writing to output file '{args.output}': {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()

