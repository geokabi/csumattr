#!/usr/bin/bash
#
# Set/check SHA256 file checksum stored in the file's extended attributes
#

csum_attr="user.sha256sum"
check_path="."
action=""

usage() {
  printf \
"Usage:
$0 -a|-c|-p|-r|-h path

 -a   Add checksums to the files that do not have them yet
 -c   Compare the stored checksum with the SHA256 hash of the file
 -p   Print the stored SHA256 checksums
 -d   Remove the extended attribute from the files
 -h   Print this help

The SHA256 checksums are stored in the user.sha256sum extended file attribute.
If <path> is a directory it is traversed recursively.\n" >&2
}

check_file() {
  filename="$1"

  sum=$(getfattr --only-values -n $csum_attr "$filename" 2>/dev/null)
  if [[ $? == 0 ]]; then
    echo "$sum  $filename" | sha256sum -c 2>/dev/null
    if [[ $? != 0 ]]; then
      printf "$filename: Checksum mismatch\n" >&2
      err=3 # worst case of all: replace errorcode with 3
    fi
  else
    printf "$filename: Checksum attribute not found\n" >&2
    err=${err:-1} # prevent overwriting err
  fi
}

add_checksum() {
  filename="$1"

  getfattr -n $csum_attr "$filename" 1>/dev/null 2>&1
  if [[ $? == 0 ]]; then
    printf "$filename: Checksum attribute found: Skipping\n" >&2
  else
    printf "Adding checksum to \'$filename\'\n"
    setfattr -n $csum_attr -v $(sha256sum "$filename" | cut -d " " -f 1) "$filename"
  fi
}

remove_checksum() {
  filename="$1"

  printf "Removing checksum from \'$filename\'\n"
  setfattr -x $csum_attr "$filename"
}

print_checksum() {
  filename="$1"

  sum=$(getfattr --only-values -n $csum_attr "$filename" 2>/dev/null)
  if [[ $? == 0 ]]; then
    printf "$sum  $filename\n"
  fi
}

process_file() {
  filename="$1"

  case $action in
    "add")
      add_checksum "$filename"
      ;;
    "check")
      check_file "$filename"
      ;;
    "remove")
      remove_checksum "$filename"
      ;;
    "print")
      print_checksum "$filename"
      ;;
  esac

  return ${err:-0}
}

# main
while getopts "acvhdp" opt; do
  case $opt in
    a)
      action="add"
      ;;
    c)
      action="check"
      ;;
    d)
      action="remove"
      ;;
    p)
      action="print"
      ;;
    h)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

if [[ -z $action ]]; then
  printf "The -a or -c option must be specified.\n\n" >&2
  usage
  exit 1
fi

shift $((OPTIND-1))
check_path="$1"

if [[ -d "$check_path" ]]; then
  find "$check_path" -type f -print0 | while read -d $'\0' esc_file
  do
    process_file "$esc_file"
  done;
elif [[ -f "$check_path" ]]; then
  process_file "$check_path"
else
  printf "Error: file not found: $check_path\n" >&2
  exit 2
fi

# returns the error code from process_file

