#!/usr/bin/env zsh

function print_sorted_duplicated_files(){
  python3.12 - <<EOF
import os

def get_file_size(file_path):
    """Returns the size of the file in bytes. Returns 0 if the file cannot be accessed."""
    try:
        return os.path.getsize(file_path)
    except OSError:
        return 0

def process_file(file_path):
    """Processes the file, calculates total sizes of duplicate groups, and filters based on size."""
    total_size_dict = {}
    with open(file_path, 'r') as f:
        group = []
        for line in f:
            line = line.strip()
            if line:
                group.append(line)
            else:
                if group:
                    process_group(group, total_size_dict)
                    group = []
        # Process the last group if the file doesn't end with a newline
        if group:
            process_group(group, total_size_dict)
    return total_size_dict

def process_group(group, total_size_dict):
    """Calculates the total size for a group of duplicate files and updates the dictionary."""
    group_size = 0
    valid_files = []
    for file in group:
        file_size = get_file_size(file)
        if file_size > 0:
            valid_files.append(file)
            group_size += file_size
    if group_size >= 100 * 1024 * 1024:  # Convert 100MB to bytes
        total_size_dict[tuple(valid_files)] = group_size * len(valid_files)

def sort_by_total_size(total_size_dict):
    """Sorts the dictionary items by total size in descending order."""
    return sorted(total_size_dict.items(), key=lambda x: x[1], reverse=True)

def print_results(sorted_files):
    for group, total_size in sorted_files:
        print(f"Total size: {total_size} bytes")
        for file in group:
            print(file)
        print()


def main(file_path):
    """Main function to process the file and print the results."""
    total_size_dict = process_file(file_path)
    sorted_files = sort_by_total_size(total_size_dict)
    print_results(sorted_files)

# Provide the path to your text file
file_path = '/tmp/duplicate-files'
main(file_path)
EOF
}

function main(){
  sudo du -ah / | sort -rh | head -n 10000 >/tmp/biggest-files
  sudo fdupes --recurse --size --time --order=time / > /tmp/duplicate-files  # use print_sorted_duplicated_files
  sudo find / -type f -exec gdu --apparent-size --block-size=1M {} + | sort -n -r > /tmp/sparse-files
  sudo find / -type f -user "$(whoami)" -atime +365 -mtime +365 -ctime +365 > /tmp/old-files
}

main "$@"
