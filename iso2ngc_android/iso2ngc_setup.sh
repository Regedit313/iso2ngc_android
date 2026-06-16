#!/data/data/com.termux/files/usr/bin/bash

clear

cd "$(dirname "$0")" || exit 1

echo
echo "iso2ngc_android Setup / Update"
echo

echo "Creating project folders..."
mkdir -p iso_in games_out/games

APP_DIR="$(pwd -P)"

echo
echo "Updating Termux..."

if ! pkg update -y; then
    echo
    echo "Error: Termux update failed."
    echo "Please check your internet connection and try again."
    echo
    read -p "Press Enter to continue..."
    exit 1
fi

if ! pkg upgrade -y; then
    echo
    echo "Error: Termux upgrade failed."
    echo "Please check your internet connection and try again."
    echo
    read -p "Press Enter to continue..."
    exit 1
fi

if [ ! -d ~/storage/shared ]; then
    echo
    echo "Setting up storage..."
    echo "If Android asks for permission, please allow it."
    echo

    if command -v termux-setup-storage >/dev/null 2>&1; then
        termux-setup-storage
    else
        echo
        echo "Warning: termux-setup-storage command was not found."
        echo "Storage access may not be configured correctly."
    fi
else
    echo
    echo "Storage is already configured."
fi

hash -r

TERMUX_WIT=0

if command -v wit >/dev/null 2>&1; then
    TERMUX_WIT=1
else
    echo
    echo "Trying to install wit directly in Termux..."
    echo "If it is not available, Debian fallback will be used."
    echo

    if pkg install -y wit; then
        hash -r

        if command -v wit >/dev/null 2>&1; then
            TERMUX_WIT=1
        fi
    else
        echo
        echo "wit is not available directly in Termux."
        echo "Debian fallback will be used."
        echo
    fi
fi

if [ "$TERMUX_WIT" -eq 1 ]; then
    echo
    echo "wit is available directly in Termux."
    echo
    wit --version
    echo
else
    echo
    echo "Installing Debian environment with proot-distro..."
    echo

    if ! pkg install -y proot-distro; then
        echo
        echo "Error: failed to install proot-distro."
        echo
        read -p "Press Enter to continue..."
        exit 1
    fi

    echo
    echo "Checking Debian..."
    echo

    if proot-distro login debian -- true >/dev/null 2>&1; then
        echo "Debian is already installed."
    else
        echo "Installing Debian..."
        echo

        if ! proot-distro install debian; then
            echo
            echo "Error: failed to install Debian."
            echo
            read -p "Press Enter to continue..."
            exit 1
        fi
    fi

    echo
    echo "Updating Debian and installing wit..."
    echo

    if ! proot-distro login debian -- bash -lc 'export DEBIAN_FRONTEND=noninteractive; apt update && apt upgrade -y && apt install -y wit'; then
        echo
        echo "Error: failed to install wit inside Debian."
        echo
        read -p "Press Enter to continue..."
        exit 1
    fi

    echo
    echo "Checking wit inside Debian..."
    echo

    if ! proot-distro login debian -- wit --version; then
        echo
        echo "Error: wit is still not available inside Debian."
        echo
        read -p "Press Enter to continue..."
        exit 1
    fi
fi

echo
echo "Setting script permissions..."
echo

chmod +x "$APP_DIR/iso2ngc.sh" 2>/dev/null
chmod +x "$APP_DIR/iso2ngc_setup.sh" 2>/dev/null
chmod +x "$APP_DIR/iso2ngc_termuxshortcut.sh" 2>/dev/null

echo
echo "Checking project files..."
echo

missing=0

if [ ! -f "$APP_DIR/iso2ngc.sh" ]; then
    echo "- Missing: iso2ngc.sh"
    missing=1
fi

if [ ! -f "$APP_DIR/iso2ngc_setup.sh" ]; then
    echo "- Missing: iso2ngc_setup.sh"
    missing=1
fi

if [ ! -f "$APP_DIR/iso2ngc_termuxshortcut.sh" ]; then
    echo "- Missing: iso2ngc_termuxshortcut.sh"
    missing=1
fi

if [ ! -d "$APP_DIR/iso_in" ]; then
    echo "- Missing: iso_in"
    missing=1
fi

if [ ! -d "$APP_DIR/games_out/games" ]; then
    echo "- Missing: games_out/games"
    missing=1
fi

if [ "$missing" -ne 0 ]; then
    echo
    echo "Warning: one or more project files/folders are missing."
    echo "Folders were created automatically, but please check the script files."
    echo
fi

echo
echo "Installation completed."
echo
echo "Put your GameCube .iso files in:"
echo "$APP_DIR/iso_in"
echo
echo "Organized games will be created in:"
echo "$APP_DIR/games_out/games"
echo
read -p "Press Enter to continue..."