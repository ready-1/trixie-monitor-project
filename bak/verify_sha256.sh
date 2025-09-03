#!/bin/bash
# verify_sha256.sh: Verifies SHA256 checksum of a file
# Purpose: Ensure integrity of Debian Trixie ISO
# Usage: ./verify_sha256.sh <file> <checksum_file>
# Example: ./verify_sha256.sh trixie-iso/debian-13.0.0-amd64-netinst.iso trixie-iso/SHA256SUMS
# Breadcrumb: [PHASE1_VERIFY_SHA256_20250830] Updated for trixie-iso/ path
# Requirements: macOS, shasum

set -e

FILE_TO_VERIFY="$1"
CHECKSUM_FILE="$2"

if [ -z "$FILE_TO_VERIFY" ] || [ -z "$CHECKSUM_FILE" ]; then
    echo "Error: Missing arguments."
    echo "Usage: $0 <file_to_verify> <checksum_file>"
    exit 1
fi

if [ ! -f "$FILE_TO_VERIFY" ]; then
    echo "Error: File '$FILE_TO_VERIFY' not found."
    exit 1
fi
if [ ! -f "$CHECKSUM_FILE" ]; then
    echo "Error: Checksum file '$CHECKSUM_FILE' not found."
    exit 1
fi

CALCULATED_SUM=$(shasum -a 256 "$FILE_TO_VERIFY" | awk '{print $1}')
echo "Calculated SHA256: $CALCULATED_SUM"

EXPECTED_SUM=$(grep "$(basename "$FILE_TO_VERIFY")" "$CHECKSUM_FILE" | awk '{print $1}')
if [ -z "$EXPECTED_SUM" ]; then
    echo "Error: No SHA256 sum found for '$FILE_TO_VERIFY' in '$CHECKSUM_FILE'."
    exit 1
fi
echo "Expected SHA256: $EXPECTED_SUM"

if [ "$CALCULATED_SUM" = "$EXPECTED_SUM" ]; then
    echo "Success: SHA256 checksums match for '$FILE_TO_VERIFY'."
    exit 0
else
    echo "Error: SHA256 checksums do not match for '$FILE_TO_VERIFY'."
    echo "Calculated: $CALCULATED_SUM"
    echo "Expected: $EXPECTED_SUM"
    exit 1
fi
