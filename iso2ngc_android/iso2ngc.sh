#!/data/data/com.termux/files/usr/bin/bash

cd "$(dirname "$0")" || exit 1

mkdir -p iso_in games_out/games

APP_DIR="$(pwd -P)"
ISO_DIR="$APP_DIR/iso_in"
GAMES_OUT_DIR="$APP_DIR/games_out"
GAMES_DIR="$GAMES_OUT_DIR/games"

WIT_BACKEND=""

INFO_DUMP=""
INFO_IS_GAMECUBE=0
INFO_GAME_ID=""
INFO_TITLE=""
INFO_DISC_NAME=""
INFO_DB_TITLE=""
INFO_ID_REGION=""
INFO_BI2_REGION=""

OUTPUT_TITLE=""
OUTPUT_REGION_TEXT=""
OUTPUT_FOLDER_NAME=""
FINAL_DIR=""
TMP_DIR=""
OUT=""
TMP_OUT=""
DISC_NUMBER="1"
TARGET_FILE_NAME="game.iso"

prepare_dirs() {
    cd "$APP_DIR" || return 1
    mkdir -p "$ISO_DIR" "$GAMES_DIR"
}

sanitize_name() {
    local text="$1"

    text="$(printf '%s' "$text" | tr '\r\n\t' '   ')"
    text="$(printf '%s' "$text" | sed -E 's/[^A-Za-z0-9 ]+/ /g')"
    text="$(printf '%s' "$text" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"

    printf '%s\n' "$text"
}

lower_text() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

build_region_text() {
    local id_region="$1"
    local bi2_region="$2"
    local id_lower
    local bi2_lower

    id_region="$(sanitize_name "$id_region")"
    bi2_region="$(sanitize_name "$bi2_region")"

    if [ -z "$id_region" ] && [ -z "$bi2_region" ]; then
        return 0
    fi

    if [ -z "$id_region" ]; then
        printf '%s\n' "$bi2_region"
        return 0
    fi

    if [ -z "$bi2_region" ]; then
        printf '%s\n' "$id_region"
        return 0
    fi

    id_lower="$(lower_text "$id_region")"
    bi2_lower="$(lower_text "$bi2_region")"

    if [ "$id_lower" = "$bi2_lower" ]; then
        printf '%s\n' "$id_region"
        return 0
    fi

    case " $id_lower " in
        *" $bi2_lower "*)
            printf '%s\n' "$id_region"
            return 0
            ;;
    esac

    case " $bi2_lower " in
        *" $id_lower "*)
            printf '%s\n' "$bi2_region"
            return 0
            ;;
    esac

    printf '%s %s\n' "$id_region" "$bi2_region"
}

detect_gamecube_disc_number() {
    local file_name
    local normalized

    file_name="$(basename "$1")"

    normalized="$(printf '%s' "$file_name" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+//g')"

    case "$normalized" in
        *disc2*|*disk2*|*disque2*|*cd2*|*dvd2*)
            printf '2\n'
            ;;
        *)
            printf '1\n'
            ;;
    esac
}

clean_temp_ngc() {
    find "$GAMES_DIR" -maxdepth 1 -type d -iname "*.iso2ngc_part_dir" -exec rm -rf {} +
}

detect_wit() {
    if command -v wit >/dev/null 2>&1; then
        WIT_BACKEND="termux"
        return 0
    fi

    if command -v proot-distro >/dev/null 2>&1; then
        if proot-distro login debian -- bash -lc 'command -v wit >/dev/null 2>&1' >/dev/null 2>&1; then
            WIT_BACKEND="debian"
            return 0
        fi
    fi

    WIT_BACKEND=""
    return 1
}

run_wit() {
    case "$WIT_BACKEND" in

        termux)
            wit "$@"
            ;;

        debian)
            proot-distro login debian -- wit "$@"
            ;;

        *)
            return 127
            ;;

    esac
}

require_wit() {
    detect_wit >/dev/null 2>&1

    if [ -z "$WIT_BACKEND" ]; then
        echo
        echo "Missing required tool: wit"
        echo
        echo "Run Setup / Update from option 9, then try again."
        echo
        read -p "Press Enter to continue..."
        return 1
    fi

    return 0
}

is_valid_gamecube_iso() {
    local dump_output

    dump_output="$(run_wit dump "$1" 2>/dev/null)" || return 1

    printf '%s\n' "$dump_output" | grep -Eiq 'File & disc type:[[:space:]]+.*GC[[:space:]]+&[[:space:]]+GameCube'
}

load_iso_info() {
    local iso="$1"

    INFO_DUMP=""
    INFO_IS_GAMECUBE=0
    INFO_GAME_ID=""
    INFO_TITLE=""
    INFO_DISC_NAME=""
    INFO_DB_TITLE=""
    INFO_ID_REGION=""
    INFO_BI2_REGION=""

    INFO_DUMP="$(run_wit dump "$iso" 2>/dev/null)" || return 1

    if printf '%s\n' "$INFO_DUMP" | grep -Eiq 'File & disc type:[[:space:]]+.*GC[[:space:]]+&[[:space:]]+GameCube'; then
        INFO_IS_GAMECUBE=1
    else
        INFO_IS_GAMECUBE=0
    fi

    INFO_GAME_ID="$(printf '%s\n' "$INFO_DUMP" \
        | sed -nE 's/.*Disc & part IDs:[[:space:]]+disc=([A-Za-z0-9]{6}).*/\1/p' \
        | head -n 1 \
        | tr '[:lower:]' '[:upper:]')"

    if [ -z "$INFO_GAME_ID" ]; then
        INFO_GAME_ID="$(printf '%s\n' "$INFO_DUMP" \
            | sed -nE 's/.*Disc & part IDs:.*boot=([A-Za-z0-9]{6}).*/\1/p' \
            | head -n 1 \
            | tr '[:lower:]' '[:upper:]')"
    fi

    INFO_DB_TITLE="$(printf '%s\n' "$INFO_DUMP" \
        | sed -nE 's/^[[:space:]]*DB title:[[:space:]]*(.*)$/\1/p' \
        | head -n 1 \
        | sed -E 's/[[:space:]]+$//')"

    INFO_DISC_NAME="$(printf '%s\n' "$INFO_DUMP" \
        | sed -nE 's/^[[:space:]]*Disc name:[[:space:]]*(.*)$/\1/p' \
        | head -n 1 \
        | sed -E 's/[[:space:]]+$//')"

    INFO_ID_REGION="$(printf '%s\n' "$INFO_DUMP" \
        | sed -nE 's/^[[:space:]]*ID Region:[[:space:]]*([^[]*).*/\1/p' \
        | head -n 1 \
        | sed -E 's/[[:space:]]+$//')"

    INFO_BI2_REGION="$(printf '%s\n' "$INFO_DUMP" \
        | sed -nE 's/^[[:space:]]*BI2 Region:[[:space:]]*[0-9]+[[:space:]]*\[([^]]+)\].*/\1/p' \
        | head -n 1 \
        | sed -E 's/[[:space:]]+$//')"

    if [ -n "$INFO_DB_TITLE" ]; then
        INFO_TITLE="$INFO_DB_TITLE"
    elif [ -n "$INFO_DISC_NAME" ]; then
        INFO_TITLE="$INFO_DISC_NAME"
    else
        INFO_TITLE=""
    fi

    return 0
}

make_output_names_from_info() {
    local iso="$1"
    local file_name
    local base
    local title
    local region_text
    local folder_base

    file_name="$(basename "$iso")"
    base="${file_name%.*}"

    if [ -n "$INFO_TITLE" ]; then
        title="$INFO_TITLE"
    else
        title="$base"
    fi

    title="$(sanitize_name "$title")"
    [ -z "$title" ] && title="Unknown"

    region_text="$(build_region_text "$INFO_ID_REGION" "$INFO_BI2_REGION")"
    region_text="$(sanitize_name "$region_text")"

    OUTPUT_TITLE="$title"
    OUTPUT_REGION_TEXT="$region_text"

    folder_base="$title"

    if [ -n "$region_text" ]; then
        folder_base="$folder_base $region_text"
    fi

    folder_base="$(sanitize_name "$folder_base")"
    [ -z "$folder_base" ] && folder_base="Unknown"

    if [ -n "$INFO_GAME_ID" ]; then
        OUTPUT_FOLDER_NAME="$folder_base [$INFO_GAME_ID]"
    else
        OUTPUT_FOLDER_NAME="$folder_base"
    fi

    DISC_NUMBER="$(detect_gamecube_disc_number "$iso")"

    if [ "$DISC_NUMBER" = "2" ]; then
        TARGET_FILE_NAME="disc2.iso"
    else
        TARGET_FILE_NAME="game.iso"
    fi

    FINAL_DIR="$GAMES_DIR/$OUTPUT_FOLDER_NAME"
    TMP_DIR="$GAMES_DIR/$OUTPUT_FOLDER_NAME.iso2ngc_part_dir"

    OUT="$FINAL_DIR/$TARGET_FILE_NAME"
    TMP_OUT="$TMP_DIR/$TARGET_FILE_NAME"
}

make_output_names_fallback() {
    local iso="$1"
    local file_name
    local base
    local clean_base

    file_name="$(basename "$iso")"
    base="${file_name%.*}"
    clean_base="$(sanitize_name "$base")"
    [ -z "$clean_base" ] && clean_base="Unknown"

    INFO_IS_GAMECUBE=0
    INFO_GAME_ID=""
    INFO_TITLE="$clean_base"
    INFO_ID_REGION=""
    INFO_BI2_REGION=""

    OUTPUT_TITLE="$clean_base"
    OUTPUT_REGION_TEXT=""
    OUTPUT_FOLDER_NAME="$clean_base"

    DISC_NUMBER="$(detect_gamecube_disc_number "$iso")"

    if [ "$DISC_NUMBER" = "2" ]; then
        TARGET_FILE_NAME="disc2.iso"
    else
        TARGET_FILE_NAME="game.iso"
    fi

    FINAL_DIR="$GAMES_DIR/$OUTPUT_FOLDER_NAME"
    TMP_DIR="$GAMES_DIR/$OUTPUT_FOLDER_NAME.iso2ngc_part_dir"

    OUT="$FINAL_DIR/$TARGET_FILE_NAME"
    TMP_OUT="$TMP_DIR/$TARGET_FILE_NAME"
}

copy_iso_safely() {
    local iso="$1"

    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR" || return 1

    if ! cp -f "$iso" "$TMP_OUT"; then
        rm -rf "$TMP_DIR"
        return 1
    fi

    echo
    echo "Checking temporary ISO..."
    echo

    if ! is_valid_gamecube_iso "$TMP_OUT"; then
        rm -rf "$TMP_DIR"
        return 1
    fi

    if [ -e "$FINAL_DIR" ] && [ ! -d "$FINAL_DIR" ]; then
        rm -f "$FINAL_DIR" || {
            rm -rf "$TMP_DIR"
            return 1
        }
    fi

    mkdir -p "$FINAL_DIR" || {
        rm -rf "$TMP_DIR"
        return 1
    }

    rm -f "$OUT"

    if ! mv -f "$TMP_OUT" "$OUT"; then
        rm -rf "$TMP_DIR"
        rm -f "$OUT"
        return 1
    fi

    rm -rf "$TMP_DIR"

    if [ ! -s "$OUT" ]; then
        rm -f "$OUT"
        return 1
    fi

    echo
    echo "Checking final ISO..."
    echo

    if ! is_valid_gamecube_iso "$OUT"; then
        rm -f "$OUT"
        return 1
    fi

    return 0
}

organize_gamecube_iso_recommended() {
    clear

    if ! require_wit; then
        return
    fi

    prepare_dirs || return

    clean_temp_ngc

    echo
    echo "Organize GameCube ISO to /games/ (recommended)"
    echo
    echo "Source folder:"
    echo "$ISO_DIR"
    echo
    echo "Output folder:"
    echo "$GAMES_DIR"
    echo

    found=0
    organized=0
    skipped=0
    not_gc=0
    deleted_iso=0
    errors=0

    while IFS= read -r -d '' iso; do
        found=1

        echo
        echo "----------------------------------------"
        echo "ISO:"
        echo "$iso"
        echo "----------------------------------------"
        echo

        echo "Reading ISO info..."
        echo

        if ! load_iso_info "$iso"; then
            echo "Skipped: ISO info could not be read."
            echo "The ISO may be unknown, corrupted, or unsupported."
            not_gc=$((not_gc + 1))
            skipped=$((skipped + 1))
            continue
        fi

        if [ "$INFO_IS_GAMECUBE" -ne 1 ]; then
            echo "Skipped: ISO is not detected as a GameCube game."
            echo "This may be Wii, unknown, corrupted, or unsupported."
            not_gc=$((not_gc + 1))
            skipped=$((skipped + 1))
            continue
        fi

        if [ -z "$INFO_GAME_ID" ]; then
            echo "Skipped: GameCube game ID could not be read."
            echo "Source ISO was kept for safety."
            not_gc=$((not_gc + 1))
            skipped=$((skipped + 1))
            continue
        fi

        make_output_names_from_info "$iso"

        echo "Game title:"
        echo "$OUTPUT_TITLE"
        echo
        echo "Game ID:"
        echo "$INFO_GAME_ID"
        echo
        echo "Region info:"
        if [ -n "$OUTPUT_REGION_TEXT" ]; then
            echo "$OUTPUT_REGION_TEXT"
        else
            echo "Unknown"
        fi
        echo
        echo "Detected disc:"
        echo "$DISC_NUMBER"
        echo
        echo "Game folder:"
        echo "$FINAL_DIR"
        echo
        echo "Output ISO:"
        echo "$OUT"
        echo

        if [ -f "$OUT" ]; then
            echo "Target ISO already exists. Checking it..."
            echo

            if is_valid_gamecube_iso "$OUT"; then
                echo
                echo "Existing target ISO is valid. Skipping:"
                echo "$OUT"

                if [ -f "$iso" ]; then
                    if rm -f "$iso"; then
                        echo
                        echo "Source ISO deleted:"
                        echo "$iso"
                        deleted_iso=$((deleted_iso + 1))
                    else
                        echo
                        echo "Error: target skipped but source ISO could not be deleted:"
                        echo "$iso"
                        errors=$((errors + 1))
                    fi
                fi

                skipped=$((skipped + 1))
                continue
            else
                echo
                echo "Existing target ISO is invalid. Removing it and organizing again:"
                echo "$OUT"
                rm -f "$OUT"
            fi
        fi

        if copy_iso_safely "$iso"; then
            echo
            echo "Organization completed:"
            echo "$OUT"

            organized=$((organized + 1))

            if [ -f "$iso" ]; then
                if rm -f "$iso"; then
                    echo
                    echo "Source ISO deleted:"
                    echo "$iso"
                    deleted_iso=$((deleted_iso + 1))
                else
                    echo
                    echo "Error: target ISO is valid but source ISO could not be deleted:"
                    echo "$iso"
                    errors=$((errors + 1))
                fi
            fi
        else
            echo
            echo "Error: organization failed:"
            echo "$iso"
            echo "Source ISO was kept."

            errors=$((errors + 1))
        fi

    done < <(find "$ISO_DIR" -maxdepth 1 -type f -iname "*.iso" -print0)

    clean_temp_ngc

    echo
    echo "========================================"
    echo "Summary"
    echo "========================================"
    echo
    echo "Organized:             $organized"
    echo "Skipped:               $skipped"
    echo "Not GameCube/Unknown:  $not_gc"
    echo "Deleted ISO:           $deleted_iso"
    echo "Errors:                $errors"
    echo

    if [ "$found" -eq 0 ]; then
        echo "No ISO file found in:"
        echo "$ISO_DIR"
        echo
    fi

    read -p "Press Enter to continue..."
}

force_organize_all_iso() {
    clear

    if ! require_wit; then
        return
    fi

    prepare_dirs || return

    clean_temp_ngc

    echo
    echo "Force organize ISO to /games/ (expert mode)"
    echo
    echo "Warning:"
    echo "This mode does not check if the ISO is a GameCube game."
    echo "Wii or unknown ISO files may produce folders that are not usable."
    echo
    echo "Expert mode does not delete source ISO files."
    echo
    read -p "Continue? Type y to confirm: " confirm

    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo
        echo "Cancelled."
        echo
        read -p "Press Enter to continue..."
        return
    fi

    echo
    echo "Source folder:"
    echo "$ISO_DIR"
    echo
    echo "Output folder:"
    echo "$GAMES_DIR"
    echo

    found=0
    organized=0
    skipped=0
    errors=0

    while IFS= read -r -d '' iso; do
        found=1

        echo
        echo "----------------------------------------"
        echo "ISO:"
        echo "$iso"
        echo "----------------------------------------"
        echo

        if load_iso_info "$iso"; then
            make_output_names_from_info "$iso"
        else
            echo "Warning: ISO info could not be read."
            echo "Output will use the cleaned ISO file name."
            make_output_names_fallback "$iso"
        fi

        echo
        echo "Game folder:"
        echo "$FINAL_DIR"
        echo
        echo "Output ISO:"
        echo "$OUT"
        echo
        echo "Detected disc:"
        echo "$DISC_NUMBER"
        echo

        if [ -z "$INFO_GAME_ID" ]; then
            echo "Warning: no game ID was found."
            echo "USB Loader GX / Nintendont compatibility may be reduced."
            echo
        fi

        if [ -f "$OUT" ]; then
            echo "Target ISO already exists. Checking it..."
            echo

            if is_valid_gamecube_iso "$OUT"; then
                echo
                echo "Existing target ISO is valid. Skipping:"
                echo "$OUT"

                skipped=$((skipped + 1))
                continue
            else
                echo
                echo "Existing target ISO is invalid. Removing it and organizing again:"
                echo "$OUT"
                rm -f "$OUT"
            fi
        fi

        if copy_iso_safely "$iso"; then
            echo
            echo "Organization completed:"
            echo "$OUT"

            organized=$((organized + 1))
        else
            echo
            echo "Error: organization failed:"
            echo "$iso"
            echo "Source ISO was kept."

            errors=$((errors + 1))
        fi

    done < <(find "$ISO_DIR" -maxdepth 1 -type f -iname "*.iso" -print0)

    clean_temp_ngc

    echo
    echo "========================================"
    echo "Summary"
    echo "========================================"
    echo
    echo "Organized: $organized"
    echo "Skipped:   $skipped"
    echo "Errors:    $errors"
    echo
    echo "Expert mode does not delete source ISO files."
    echo

    if [ "$found" -eq 0 ]; then
        echo "No ISO file found in:"
        echo "$ISO_DIR"
        echo
    fi

    read -p "Press Enter to continue..."
}

dump_all_iso() {
    clear

    if ! require_wit; then
        return
    fi

    prepare_dirs || return

    echo
    echo "Dump all ISO info from iso_in"
    echo
    echo "Folder:"
    echo "$ISO_DIR"
    echo

    found=0
    errors=0

    while IFS= read -r -d '' iso; do
        found=1

        echo
        echo "========================================"
        echo "ISO:"
        echo "$iso"
        echo "========================================"
        echo

        if ! run_wit dump "$iso"; then
            echo
            echo "Error: dump failed:"
            echo "$iso"

            errors=$((errors + 1))
        fi

    done < <(find "$ISO_DIR" -maxdepth 1 -type f -iname "*.iso" -print0)

    echo
    echo "========================================"
    echo "Summary"
    echo "========================================"
    echo
    echo "Errors: $errors"
    echo

    if [ "$found" -eq 0 ]; then
        echo "No ISO file found in:"
        echo "$ISO_DIR"
        echo
    fi

    read -p "Press Enter to continue..."
}

verify_all_gamecube_games() {
    clear

    if ! require_wit; then
        return
    fi

    prepare_dirs || return

    clean_temp_ngc

    echo
    echo "Verify all GameCube games from games_out"
    echo
    echo "Folder:"
    echo "$GAMES_DIR"
    echo

    found=0
    valid=0
    errors=0

    while IFS= read -r -d '' game_iso; do
        found=1

        echo
        echo "----------------------------------------"
        echo "Checking:"
        echo "$game_iso"
        echo "----------------------------------------"
        echo

        if is_valid_gamecube_iso "$game_iso"; then
            valid=$((valid + 1))
        else
            errors=$((errors + 1))
        fi

    done < <(find "$GAMES_DIR" -type f \
        \( -iname "game.iso" -o -iname "disc2.iso" \) \
        ! -path "*/.iso2ngc_part_dir/*" \
        -print0)

    echo
    echo "========================================"
    echo "Summary"
    echo "========================================"
    echo
    echo "Valid:  $valid"
    echo "Errors: $errors"
    echo

    if [ "$found" -eq 0 ]; then
        echo "No GameCube game ISO found in:"
        echo "$GAMES_DIR"
        echo
    fi

    read -p "Press Enter to continue..."
}

show_wit_status() {
    clear

    detect_wit >/dev/null 2>&1

    echo
    echo "WIT status"
    echo

    case "$WIT_BACKEND" in

        termux)
            echo "Backend: Termux native"
            echo
            wit --version
            ;;

        debian)
            echo "Backend: Debian via proot-distro"
            echo
            proot-distro login debian -- wit --version
            ;;

        *)
            echo "Backend: not installed"
            echo
            echo "Run Setup / Update from option 9."
            ;;

    esac

    echo
    read -p "Press Enter to continue..."
}

run_setup() {
    clear

    prepare_dirs || return

    if [ -f "$APP_DIR/iso2ngc_setup.sh" ]; then
        bash "$APP_DIR/iso2ngc_setup.sh"
        prepare_dirs || return
        detect_wit >/dev/null 2>&1
    else
        echo
        echo "Setup file is missing:"
        echo "$APP_DIR/iso2ngc_setup.sh"
        echo
        echo "Please reinstall iso2ngc_android because a required file is missing."
        echo
        read -p "Press Enter to continue..."
    fi
}

detect_wit >/dev/null 2>&1

while true; do
    clear

    echo
    echo "iso2ngc_android"
    echo
    echo
    echo "1) Organize GameCube ISO to /games/ (recommended)"
    echo
    echo "2) Force organize ISO to /games/ (expert mode)"
    echo
    echo "3) Dump all ISO info from iso_in"
    echo
    echo "4) Verify all GameCube games from games_out"
    echo
    echo "5) Show WIT status"
    echo
    echo
    echo "9) Run Setup / Update (required before first use)"
    echo
    echo "0) Exit"
    echo
    echo

    read -p "Choose what to do: " choice

    case "$choice" in

        1)
            organize_gamecube_iso_recommended
            ;;

        2)
            force_organize_all_iso
            ;;

        3)
            dump_all_iso
            ;;

        4)
            verify_all_gamecube_games
            ;;

        5)
            show_wit_status
            ;;

        9)
            run_setup
            ;;

        0)
            clear
            exit 0
            ;;

        *)
            echo
            echo "Invalid choice."
            sleep 1
            ;;

    esac
done