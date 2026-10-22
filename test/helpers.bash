# Shared by the .bats files. Plain checks that print what they compared when they fail.

# Exact match of $output (set by bats' run).
# shellcheck disable=SC2154 # output is set by bats' run
expect_output() {
  if [[ "${output}" != "$1" ]]; then
    printf 'expected output: %s\nactual output:   %s\n' "$1" "${output}"
    return 1
  fi
}
