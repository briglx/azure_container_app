#!/usr/bin/env bash
#########################################################################
# Render a role definition from a template by substituting variables.
# Usage: render_role_template.sh -i <input_template_file> -o <output_file> -v <var1=value1> -v <var2=value2> ...
# Globals:
# Params
#    -i, Input template file
#    -o, Output file (optional; if not specified, output to stdout)
#    -v, Variable substitution in the form var=value (can be specified multiple times)
#########################################################################
# Stop on errors
set -e

show_help(){
    echo "Usage: $0 -i <input_template_file> -o <output_file> -v <var1=value1> -v <var2=value2> ..." >&2
}

# Parameters
while getopts "i:o:v:" opt; do
  case $opt in
    i)
      input_template_file="$OPTARG"
      ;;
    o)
      output_file="$OPTARG"
      ;;
    v)
      var_assignments+=("$OPTARG")
      ;;
    *)
      show_help
      exit 1
      ;;
  esac
done

if [ -z "$input_template_file" ]; then
    show_help
    exit 1
fi

# Read the template content
template_content=$(<"$input_template_file")

# Perform variable substitutions
for assignment in "${var_assignments[@]}"; do
    var_name="${assignment%%=*}"
    var_value="${assignment#*=}"
    echo "Substituting {{$var_name}} with $var_value" >&2
    template_content="${template_content//\{\{$var_name\}\}/$var_value}"
done

# Write the rendered content to the output file if -o is specified
if [ -n "$output_file" ]; then
  echo "$template_content" > "$output_file"
  echo "Rendered template saved to $output_file" >&2
fi

echo "$template_content"
