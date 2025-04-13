#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
# Consider enabling if script becomes stable: set -e

# --- Configuration ---
CONTENT_DIR="content"
ROOT_OUTPUT_INDEX="index.md"
ROOT_HEADER_FILE="header.md"
ROOT_FOOTER_FILE="footer.md"
SUBDIR_INDEX_FILENAME="index.md"
SUBDIR_HEADER_FILENAME="header.md"
SUBDIR_FOOTER_FILENAME="footer.md"
TEMP_ROOT_LINKS_FILE=$(mktemp)
trap 'echo "[DEBUG] Cleaning up root temp file: $TEMP_ROOT_LINKS_FILE" >&2; rm -f "$TEMP_ROOT_LINKS_FILE"' EXIT

echo "[INFO] Starting index generation process..." >&2; echo "[DEBUG] Root temp file: $TEMP_ROOT_LINKS_FILE" >&2

# --- Helper Function: Extract H1 Title ---
get_h1_title() { local file_path="$1"; local title; if [ ! -r "$file_path" ]; then return 1; fi; title=$(grep -m 1 '^# ' "$file_path" | sed -e 's/^# *//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'); if [ -n "$title" ]; then printf "%s" "$title"; return 0; else return 1; fi; }

# --- Function: Generate Index for a Specific Subdirectory ---
generate_subdir_index() {
    local subdir_path="$1"; local subdir_name=$(basename "$subdir_path")
    local index_file="$subdir_path/$SUBDIR_INDEX_FILENAME"
    local header_file="$subdir_path/$SUBDIR_HEADER_FILENAME"
    local footer_file="$subdir_path/$SUBDIR_FOOTER_FILENAME"
    local temp_links_file

    echo ">>> generate_subdir_index: START for '$subdir_path'" >&2

    local has_relevant_files=false; local has_subdirectories=false; local should_generate_index=false
    if find "$subdir_path" -maxdepth 1 -type f \( -name '*.md' -o -name '*.mdx' \) -not -name "$SUBDIR_INDEX_FILENAME" -not -name "$SUBDIR_HEADER_FILENAME" -not -name "$SUBDIR_FOOTER_FILENAME" -print -quit | grep -q .; then has_relevant_files=true; fi
    if find "$subdir_path" -mindepth 1 -maxdepth 1 -type d -print -quit | grep -q .; then has_subdirectories=true; fi
    if $has_relevant_files || $has_subdirectories; then should_generate_index=true; fi

    if ! $should_generate_index; then echo "[DEBUG SubIndex '$subdir_name'] Skipping: No relevant content." >&2; if [ -f "$index_file" ]; then echo "    Removing empty index: $index_file" >&2; rm -f "$index_file"; fi; echo "<<< generate_subdir_index: END (skipped) for '$subdir_path'" >&2; return; fi

    temp_links_file=$(mktemp); trap 'echo "[DEBUG] Cleaning up subdir temp file: $temp_links_file" >&2; rm -f "$temp_links_file"; trap - INT TERM EXIT; return' INT TERM EXIT; echo "[DEBUG SubIndex '$subdir_name'] Generating: $index_file using temp $temp_links_file" >&2
    if ! { > "$index_file"; }; then echo "[ERROR SubIndex '$subdir_name'] Failed create/clear $index_file" >&2; rm -f "$temp_links_file"; trap - INT TERM EXIT; echo "<<< generate_subdir_index: END (error) for '$subdir_path'" >&2; return; fi
    if [ -f "$header_file" ]; then cat "$header_file" >> "$index_file"; printf "\n\n" >> "$index_file"; else printf "# %s\n\n" "$subdir_name" >> "$index_file"; fi; > "$temp_links_file"

    local file_found_in_subdir=false
    if $has_relevant_files; then
        echo "[DEBUG SubIndex '$subdir_name'] Listing Files..." >&2
        find "$subdir_path" -maxdepth 1 -type f \( -name '*.md' -o -name '*.mdx' \) -not -name "$SUBDIR_INDEX_FILENAME" -not -name "$SUBDIR_HEADER_FILENAME" -not -name "$SUBDIR_FOOTER_FILENAME" -print0 | sort -z | while IFS= read -r -d $'\0' file; do file_found_in_subdir=true; local filename=$(basename "$file"); local link_text=$(get_h1_title "$file"); local title_status=$?; if [ $title_status -ne 0 ] || [ -z "$link_text" ]; then link_text="${filename%.*}"; fi; printf -- "- [%s](%s)\n" "$link_text" "./$filename" >> "$temp_links_file"; done; if $file_found_in_subdir; then printf "\n" >> "$temp_links_file"; fi
    fi

    local subdir_found_in_subdir=false
    if $has_subdirectories; then
        echo "[DEBUG SubIndex '$subdir_name'] Listing Nested Subdirectories..." >&2
        if $file_found_in_subdir; then printf "## Subdirectories\n\n" >> "$temp_links_file"; fi
        find "$subdir_path" -mindepth 1 -maxdepth 1 -type d | sort | while IFS= read -r nested_subdir; do subdir_found_in_subdir=true; echo "  [Nested Loop in '$subdir_name'] Processing nested dir: '$nested_subdir'" >&2; local nested_subdir_name=$(basename "$nested_subdir"); local nested_index_target="./$nested_subdir_name/$SUBDIR_INDEX_FILENAME"; local nested_header_file="$nested_subdir/$SUBDIR_HEADER_FILENAME"; local nested_link_text; local title_status; nested_link_text=$(get_h1_title "$nested_header_file"); title_status=$?; if [ $title_status -ne 0 ] || [ -z "$nested_link_text" ]; then nested_link_text="$nested_subdir_name"; fi; echo "  [Nested Loop in '$subdir_name'] Appending link: - [$nested_link_text]($nested_index_target)" >&2; if ! printf -- "- [%s](%s)\n" "$nested_link_text" "$nested_index_target" >> "$temp_links_file"; then echo "[ERROR SubIndex '$subdir_name'] FAILED printf to append nested subdir link for '$nested_subdir_name'!" >&2; fi; done; if $subdir_found_in_subdir; then printf "\n" >> "$temp_links_file"; fi
    fi

    echo "[DEBUG SubIndex '$subdir_name'] Content of temp file '$temp_links_file' before final append:" >&2; cat "$temp_links_file" >&2; echo "[DEBUG SubIndex '$subdir_name'] --- End Temp File ---" >&2
    if [ -s "$temp_links_file" ]; then echo "[DEBUG SubIndex '$subdir_name'] Appending temp file content to $index_file" >&2; if ! cat "$temp_links_file" >> "$index_file"; then echo "[ERROR] Failed append"; fi; else echo "[WARN SubIndex '$subdir_name'] Temp file was empty.";fi
    if [ -f "$footer_file" ]; then printf "\n" >> "$index_file"; cat "$footer_file" >> "$index_file"; fi; echo "<<< generate_subdir_index: END (processed) for '$subdir_path'" >&2; rm -f "$temp_links_file"; trap - INT TERM EXIT;
}


# --- Main Logic ---
# (Part 1 - Root Index Generation - Keep unchanged)
echo "[INFO] Generating root index file: $ROOT_OUTPUT_INDEX" >&2
if [ ! -d "$CONTENT_DIR" ]; then echo "[ERROR] Root content directory '$CONTENT_DIR' not found." >&2; rm -f "$TEMP_ROOT_LINKS_FILE"; exit 1; fi
echo "  Creating/overwriting $ROOT_OUTPUT_INDEX..." >&2
if ! { > "$ROOT_OUTPUT_INDEX"; }; then echo "[ERROR] Failed create/clear $ROOT_OUTPUT_INDEX." >&2; rm -f "$TEMP_ROOT_LINKS_FILE"; exit 1; fi
if [ -f "$ROOT_HEADER_FILE" ]; then echo "  Prepending root header: $ROOT_HEADER_FILE" >&2; cat "$ROOT_HEADER_FILE" >> "$ROOT_OUTPUT_INDEX"; printf "\n\n" >> "$ROOT_OUTPUT_INDEX"; else echo "  Root header '$ROOT_HEADER_FILE' not found." >&2; fi
> "$TEMP_ROOT_LINKS_FILE"
echo "  Processing files directly under '$CONTENT_DIR' for root index..." >&2; has_root_files=false
find "$CONTENT_DIR" -maxdepth 1 -type f \( -name '*.md' -o -name '*.mdx' \) -not -name 'index.md' -print0 | sort -z | while IFS= read -r -d $'\0' file; do has_root_files=true; filename=$(basename "$file"); link_text=$(get_h1_title "$file"); title_status=$?; if [ $title_status -ne 0 ] || [ -z "$link_text" ]; then link_text="${filename%.*}"; fi; printf -- "- [%s](%s)\n" "$link_text" "./${file}" >> "$TEMP_ROOT_LINKS_FILE"; done
if $has_root_files; then printf "\n" >> "$TEMP_ROOT_LINKS_FILE"; fi
echo "  Processing subdirectories under '$CONTENT_DIR' for root index..." >&2
find "$CONTENT_DIR" -mindepth 1 -maxdepth 1 -type d | sort | while IFS= read -r subdir; do
    subdir_name=$(basename "$subdir"); subdir_header_file="$subdir/$SUBDIR_HEADER_FILENAME"; subdir_index_link_target="./$subdir/$SUBDIR_INDEX_FILENAME"
    list_in_root=false; found_files_in_subdir=false; found_dirs_in_subdir=false
    if find "$subdir" -maxdepth 1 -type f \( -name '*.md' -o -name '*.mdx' \) -not -name "$SUBDIR_INDEX_FILENAME" -not -name "$SUBDIR_HEADER_FILENAME" -not -name "$SUBDIR_FOOTER_FILENAME" -print -quit | grep -q .; then found_files_in_subdir=true; fi
    if find "$subdir" -mindepth 1 -maxdepth 1 -type d -print -quit | grep -q .; then found_dirs_in_subdir=true; fi
    if $found_files_in_subdir || $found_dirs_in_subdir ; then list_in_root=true; fi
    if $list_in_root; then
        subdir_link_text=""; title_status="" # Initialize vars
        subdir_link_text=$(get_h1_title "$subdir_header_file"); title_status=$?
        if [ $title_status -ne 0 ] || [ -z "$subdir_link_text" ]; then subdir_link_text="$subdir_name"; fi
        echo "    Adding section for '$subdir_name' to root index." >&2
        if ! printf "## [%s](%s)\n\n" "$subdir_link_text" "$subdir_index_link_target" >> "$TEMP_ROOT_LINKS_FILE"; then echo "[ERROR RootLoop] FAILED append link '$subdir_name'" >&2; fi
    else echo "    Skipping empty subdirectory '$subdir_name' in root index." >&2; fi
done
echo "[DEBUG] Content of root temp file ($TEMP_ROOT_LINKS_FILE) before appending:" >&2; cat "$TEMP_ROOT_LINKS_FILE" >&2; echo "[DEBUG] --- End Root Temp File ---" >&2
if [ -s "$TEMP_ROOT_LINKS_FILE" ]; then if ! cat "$TEMP_ROOT_LINKS_FILE" >> "$ROOT_OUTPUT_INDEX"; then echo "[ERROR] Failed append $TEMP_ROOT_LINKS_FILE" >&2; fi; else echo "  [WARN] Root links temp file empty." >&2; fi
if [ -f "$ROOT_FOOTER_FILE" ]; then printf "\n" >> "$ROOT_OUTPUT_INDEX"; cat "$ROOT_FOOTER_FILE" >> "$ROOT_OUTPUT_INDEX"; else echo "  Root footer '$ROOT_FOOTER_FILE' not found." >&2; fi
echo "[INFO] Root index generation complete: $ROOT_OUTPUT_INDEX" >&2

# --- Part 2: Generate Index Files for ALL Subdirectories ---
echo "[INFO] Generating index files for ALL subdirectories within '$CONTENT_DIR'..." >&2
# --- FIX: Use find to get ALL directories recursively ---
find "$CONTENT_DIR" -type d -not -path '*/.git*' | sort | while IFS= read -r subdir; do
    # Skip processing the top-level content directory itself in this loop
    if [ "$subdir" == "$CONTENT_DIR" ]; then
        echo "[INFO] Skipping index generation for top-level '$CONTENT_DIR' itself." >&2
        continue
    fi

    echo "[INFO] >>> Checking/Generating index for directory: '$subdir'" >&2
    ( # Run generation in a subshell
      trap 'echo "[ERROR] Sub-index generation failed for $subdir" >&2; trap - INT TERM EXIT; exit 1' INT TERM EXIT
      # Call the existing function which knows how to handle a single directory
      generate_subdir_index "$subdir"
      trap - INT TERM EXIT # Clear trap on successful completion
    )
done
# --- End FIX ---

echo "[INFO] All index generation finished." >&2