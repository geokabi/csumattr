#!/usr/bin/bash
#
# Set/check SHA256 file checksum stored in the file's extended attributes
#

csum_attr="user.sha256sum"
find_files_in_path_opts="-mount -not -empty"
check_path="."
action=""
verbose=0

usage() {
  printf \
"Usage:
$0 -a|-c|-r|-u|-p|-v|-h path

 -a   Add checksums to the files that do not have them yet
 -c   Compare the stored checksum with the SHA256 hash of the file
 -r   Remove the extended attribute from the files
 -u   Update the stored checksum to files that have a different checksum than the stored one
 -p   Print the stored SHA256 checksums
 -v   Verbose output
 -h   Print this help

The SHA256 checksums are stored in the user.sha256sum extended file attribute.
If <path> is a directory it is traversed recursively (Only in the same filesystem).
Ignores empty files.\n" >&2
}


printf_if_verbose() {
  msg="$1"

  if [[ $verbose -ne 0 ]]; then
    printf "$msg"
  fi
}

check_file() {
  filename="$1"

  if [[ $verbose -ne 0 ]]; then
    sha256sum_quiet=""
  else
    sha256sum_quiet="--status"
  fi

  csum=$(getfattr --only-values -n $csum_attr "$filename" 2>/dev/null)
  if [[ $? == 0 ]]; then
    echo "$csum  $filename" | sha256sum $sha256sum_quiet -c 2>/dev/null
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
    printf_if_verbose "Adding checksum to \'$filename\'\n"
    setfattr -n $csum_attr -v $(sha256sum "$filename" | cut -d " " -f 1) "$filename"
  fi
}

remove_checksum() {
  filename="$1"

  printf_if_verbose  "Removing checksum from \'$filename\'\n"
  setfattr -x $csum_attr "$filename"
}

update_checksum() {
  filename="$1"

  csum=$(getfattr --only-values -n $csum_attr "$filename" 2>/dev/null)
  if [[ $? == 0 ]]; then
    echo "$csum  $filename" | sha256sum --status -c 1>/dev/null 2>&1
    if [[ $? != 0 ]]; then
      printf_if_verbose  "$filename: Updating checksum\n"
      setfattr -n $csum_attr -v $(sha256sum "$filename" | cut -d " " -f 1) "$filename"
    fi
  else
    printf "$filename: Checksum attribute not found\n" >&2
  fi
}

print_checksum() {
  filename="$1"

  csum=$(getfattr --only-values -n $csum_attr "$filename" 2>/dev/null)
  if [[ $? == 0 ]]; then
    printf "$csum  $filename\n"
  else
    printf "$filename: Checksum attribute not found\n" >&2
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
    "update")
      update_checksum "$filename"
      ;;
    "print")
      print_checksum "$filename"
      ;;
  esac

  return ${err:-0}
}

# main
while getopts "acrupvh" opt; do
  case $opt in
    a)
      action="add"
      ;;
    c)
      action="check"
      ;;
    r)
      action="remove"
      ;;
    u)
      action="update"
      ;;
    p)
      action="print"
      ;;
    v)
      verbose=1
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
  printf "One of the action options (-a|-c|-r|-u|-p) must be specified.\n\n" >&2
  usage
  exit 1
fi

shift $((OPTIND-1))
check_path="$1"

if [[ -d "$check_path" ]]; then
  find "$check_path" $find_files_in_path_opts -type f -print0 | while read -d $'\0' esc_file
  do
    process_file "$esc_file"
  done;
elif [[ -f "$check_path" ]]; then
  if [[ -s "$check_path" ]]; then
    process_file "$check_path"
  fi
else
  printf "Error: file not found: $check_path\n" >&2
  exit 2
fi

# returns the error code from process_file

