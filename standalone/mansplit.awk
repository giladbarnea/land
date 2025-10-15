BEGIN {
    if (!output_dir) {
        print "Usage: awk -v output_dir=/path/to/dir -f mansplit.awk /path/to/manpage.1" > "/dev/stderr"
        print "       awk ...                                        $(man -w manpage)" > "/dev/stderr"
        exit 1
    }
    
    system("mkdir -p " output_dir)
    
    # Use ARGV[1] instead of FILENAME
    if (ARGC > 1) {
        filepath = ARGV[1]
        n = split(filepath, path_parts, "/")
        full_name = path_parts[n]
        
        # Remove extension
        dot_pos = match(full_name, /\.[^.]*$/)
        if (dot_pos > 0) {
            basename = substr(full_name, 1, dot_pos - 1)
        } else {
            basename = full_name
        }
    } else {
        basename = "unknown"
    }
    
    in_header = 1
    header = ""
}

# Capture header until the first section starts
in_header && !/^\.SH / {
    header = header $0 "\n"
    next
}

/^\.SH / {
    in_header = 0
    if (current_mandoc_cmd) {
        close(current_mandoc_cmd)
    }
    
    section = $0
    sub(/^\.SH /, "", section)
    gsub(/^"|"$/, "", section)
    gsub(/[^A-Za-z0-9_]/, "_", section)
    gsub(/_+/, "_", section)
    gsub(/^_|_$/, "", section)
    section = tolower(section)
    
    output_filename = output_dir "/" basename "." section ".txt"
    current_mandoc_cmd = "mandoc -T locale | col -b > \"" output_filename "\""
    
    # Pipe the captured header to the mandoc command for the new section.
    print header | current_mandoc_cmd
}

# For any line after the header, if we have a command to pipe to, do it.
current_mandoc_cmd {
    print | current_mandoc_cmd
}

END {
    # Close the final mandoc process.
    if (current_mandoc_cmd) {
        close(current_mandoc_cmd)
    }
}
